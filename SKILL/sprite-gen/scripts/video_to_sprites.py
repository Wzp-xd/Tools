#!/usr/bin/env python3
"""
video_to_sprites — 视频变精灵表(全自动后处理管线)

输入: {work_dir}/{精灵名}(含 _meta.json + _gen_videos/{动画id}/anim.mp4)
     --anims id1,id2,...   指定处理哪些动画(不传=_gen_videos 下全部有 anim.mp4 的)

做了:
  1. OpenCV 拆全帧(ASCII 临时目录,绕 cv2 中文路径)
  2. 循环动画 → 循环检测(TSM+pHash+光流+SSIM+JumpRatio)找完整循环窗口
     单次动画 → 峰值隔离,只留动作爆发段
  3. 色差键抠图(chroma key):按幕布色 alpha 化,去溢色,消 h264 渗色边
  4. frame_mode=K 时抽关键帧,写 duration 保持原节奏
  5. 精灵级精灵表导出:按 source_size_mode 写 pivot/sourceSize,多行网格 ≤ max_sheet_size
  6. 从最终图集 PNG/JSON 反合成 frames_preview.webp(反映 target_height/sourceSize)

输出:
  {work_dir}/{精灵名}/_gen_videos/{动画id}/frames/frame_*.png (临时中间帧,成功导出后自动清理)
  {work_dir}/{精灵名}/_gen_videos/{动画id}/frames_key/frame_*.png (K 模式临时中间帧,成功导出后自动清理)
  {work_dir}/{精灵名}/_gen_videos/{动画id}/frames_preview.webp
  {output_dir}/{精灵名}/{动画id}/spritesheet.png + spritesheet.json

传几个做几个:
  --anims idle        → 只做 idle
  --anims idle,walk   → 做这两个
  不传                → 全做

可反复调用(重做某个动画时只传那个 id)。
"""
import argparse
import copy
import json
import glob
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))

import cv2
import numpy as np
from PIL import Image

import cycle_detect as CD
from chroma_key import chroma_key_image
import keyframe_extract as KE
import sprite_export as SE
from env_compat import ensure_utf8, ascii_workdir

ensure_utf8()


def _load_json(path):
    """读 JSON;用 with 确保文件句柄即时释放(避免 Windows 上后续 rmtree 占用)。"""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _deep_merge(base, override):
    result = copy.deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def extract_frames(video_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    paths = []
    i = 0
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        i += 1
        p = os.path.join(out_dir, f"frame_{i:04d}.png")
        cv2.imwrite(p, fr)
        paths.append(p)
    cap.release()
    return paths


def detect_segment(frame_paths, grays, play_type, cfg_detect):
    min_cycle = cfg_detect.get("min_cycle", 10)
    padding = cfg_detect.get("peak_padding", 3)

    if play_type == "once":
        r = CD.isolate_action_peak(grays, padding=padding)
        return frame_paths[r["start"]:r["end"] + 1]

    # loop
    results = {}
    for name, fn in [("TSM", lambda: CD.tsm_period(grays, min_cycle=min_cycle)[0]),
                     ("pHash", lambda: CD.phash_period(frame_paths, min_cycle=min_cycle)[0]),
                     ("Flow", lambda: CD.flow_period(grays, min_cycle=min_cycle)[0]),
                     ("SSIM", lambda: CD.ssim_period(grays, min_cycle=min_cycle)[0])]:
        try:
            results[name] = fn()
        except Exception:
            results[name] = None
    ests = [v for v in results.values() if v]
    cands = CD.jump_ratio_candidates(grays, ests, min_cycle=min_cycle, top_n=4) if ests else []
    if cands:
        best = cands[0]
        return frame_paths[best["start"]:best["start"] + best["cycle_len"]]
    # fallback
    a0, a1 = CD.detect_active_region(grays)
    return frame_paths[a0:a1 + 1]


def normalize_frame_mode(value):
    mode = str(value or "F").strip().upper()
    if mode not in ("F", "K"):
        print(f"  ⚠️ 未知 frame_mode={value!r},按 F 处理")
        return "F"
    return mode


def normalize_asset_type(value):
    asset_type = str(value or "character").strip().lower()
    if asset_type not in ("character", "sequence"):
        print(f"  ⚠️ 未知 asset_type={value!r},按 character 处理")
        return "character"
    return asset_type


def normalize_source_size_mode(value):
    mode = str(value or "canvas").strip().lower()
    if mode not in ("canvas", "bbox-per-anim"):
        print(f"  ⚠️ 未知 source_size_mode={value!r},按 canvas 处理")
        return "canvas"
    return mode


def normalize_bool(value, default=False):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().lower()
    if text in ("true", "1", "yes", "on"):
        return True
    if text in ("false", "0", "no", "off"):
        return False
    return default


def _load_keyframe_map(key_dir):
    map_path = os.path.join(key_dir, "keyframe_map.json")
    if not os.path.isfile(map_path):
        return None
    try:
        with open(map_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _keyframe_map_valid(map_data, key_dir, source_count, fps, play_type):
    if not map_data:
        return False
    key_count = int(map_data.get("keyframe_count", 0) or 0)
    key_files = glob.glob(os.path.join(key_dir, "frame_*.png"))
    try:
        fps_match = abs(float(map_data.get("source_fps")) - float(fps)) < 0.001
    except (TypeError, ValueError):
        fps_match = False
    return (
        map_data.get("source_total_frames") == source_count and
        fps_match and
        map_data.get("play_type") == play_type and
        key_count > 0 and
        len(key_files) == key_count and
        len(map_data.get("frame_durations_ms", [])) == key_count
    )


def ensure_keyframes(frames_dir, fps, play_type, force=False):
    """Create or refresh frames_key/ for K mode and return (dir, map)."""
    source_frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not source_frames:
        return frames_dir, None

    key_dir = os.path.join(os.path.dirname(frames_dir), "frames_key")
    map_data = _load_keyframe_map(key_dir)
    if not force and _keyframe_map_valid(map_data, key_dir, len(source_frames), fps, play_type):
        return key_dir, map_data

    if os.path.exists(key_dir):
        shutil.rmtree(key_dir)

    result = KE.extract_keyframes(source_frames)
    print(f"  K帧抽取: {len(source_frames)} → {len(result['indices'])} 帧 "
          f"({result['complexity']}, target={result['target_range']})")
    map_data = KE.create_key_version(frames_dir, key_dir, result,
                                     source_fps=fps, play_type=play_type,
                                     write_preview=False)
    return key_dir, map_data


def write_preview_webp(frame_images, frame_durations, preview_path):
    if not frame_images:
        return
    frame_images[0].save(preview_path, format="WEBP",
                         save_all=True, append_images=frame_images[1:],
                         duration=frame_durations, loop=0, lossless=True)


def write_preview_from_dir(frames_dir, preview_path, fps, frame_durations=None):
    frame_paths = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    imgs = [Image.open(p).convert("RGBA") for p in frame_paths]
    durations = frame_durations or [int(1000 / max(1, fps))] * len(imgs)
    write_preview_webp(imgs, durations, preview_path)


def _frame_sort_key(frame_name):
    try:
        return int(frame_name.rsplit("_", 1)[1])
    except (IndexError, ValueError):
        return frame_name


def write_export_preview(anim_export_dir, preview_path):
    """Recompose a WebP preview from final atlas PNG/JSON metadata."""
    entries = []
    for json_path in glob.glob(os.path.join(anim_export_dir, "spritesheet*.json")):
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
        image_path = os.path.join(anim_export_dir, data["meta"]["image"])
        for frame_name, frame_meta in data["frames"].items():
            entries.append((_frame_sort_key(frame_name), image_path, frame_meta))

    if not entries:
        return False

    entries.sort(key=lambda item: item[0])
    sheet_cache = {}
    frames = []
    durations = []
    for _, image_path, frame_meta in entries:
        if image_path not in sheet_cache:
            sheet_cache[image_path] = Image.open(image_path).convert("RGBA")
        sheet = sheet_cache[image_path]

        rect = frame_meta["frame"]
        sprite_rect = frame_meta["spriteSourceSize"]
        source_size = frame_meta["sourceSize"]
        frame_img = sheet.crop((
            int(rect["x"]), int(rect["y"]),
            int(rect["x"] + rect["w"]), int(rect["y"] + rect["h"]),
        ))
        canvas = Image.new("RGBA", (int(source_size["w"]), int(source_size["h"])), (0, 0, 0, 0))
        canvas.alpha_composite(frame_img, (int(sprite_rect["x"]), int(sprite_rect["y"])))
        frames.append(canvas)
        durations.append(int(frame_meta.get("duration", 42)))

    write_preview_webp(frames, durations, preview_path)
    return True


def get_export_frames_dir(gen_videos_dir, aid, frame_mode):
    anim_dir = os.path.join(gen_videos_dir, aid)
    if frame_mode == "K":
        key_dir = os.path.join(anim_dir, "frames_key")
        if glob.glob(os.path.join(key_dir, "frame_*.png")):
            return key_dir
    return os.path.join(anim_dir, "frames")


def check_sprite_consistency(exports_dir, expected_meta):
    """比对 exports/ 下所有动画的精灵级参数是否与本次导出一致。

    中间帧导出后即被清理,无法靠重新收集 frames 保证一致;改为以每个动画
    spritesheet.json meta 顶层持久化的导出参数为准。只比对真正影响合并图集的
    字段(SPRITE_CONSISTENCY_KEYS)。返回 [(动画名, 差异)] 列表,空表示全部一致。
    """
    issues = []
    if not os.path.isdir(exports_dir):
        return issues
    for name in sorted(os.listdir(exports_dir)):
        sheet = os.path.join(exports_dir, name, "spritesheet.json")
        if not os.path.isfile(sheet):
            continue
        try:
            with open(sheet, encoding="utf-8") as f:
                meta = json.load(f).get("meta", {})
        except (OSError, ValueError):
            issues.append((name, "spritesheet.json 无法读取"))
            continue
        if not all(k in meta for k in SE.SPRITE_CONSISTENCY_KEYS):
            issues.append((name, "缺少导出参数(旧版本导出,建议重导)"))
            continue
        diff = {k: f"{meta.get(k)!r}→应为{expected_meta[k]!r}"
                for k in SE.SPRITE_CONSISTENCY_KEYS
                if meta.get(k) != expected_meta[k]}
        if diff:
            issues.append((name, diff))
    return issues


def cleanup_intermediate_frames(gen_videos_dir, anim_ids):
    removed_dirs = 0
    removed_frames = 0
    for aid in anim_ids:
        anim_dir = os.path.join(gen_videos_dir, aid)
        for name in ("frames", "frames_key"):
            frame_dir = os.path.join(anim_dir, name)
            if not os.path.isdir(frame_dir):
                continue
            removed_frames += len(glob.glob(os.path.join(frame_dir, "frame_*.png")))
            shutil.rmtree(frame_dir)
            removed_dirs += 1
    print(f"  清理中间帧: {removed_dirs} 个目录, {removed_frames} 张 frame_*.png")


def main():
    ap = argparse.ArgumentParser(description="视频 → 精灵表(全自动后处理)")
    ap.add_argument("char_dir", help="{work_dir}/{精灵名}")
    ap.add_argument("--anims", default=None, help="动画id列表(逗号分隔),不传=全部")
    args = ap.parse_args()

    cfg = _load_json(os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json"))
    meta = _load_json(os.path.join(args.char_dir, "_meta.json"))
    cfg = _deep_merge(cfg, meta)  # meta 覆盖 config
    key_color = tuple(cfg["key_color"])
    target_height = cfg.get("target_height", 256)
    asset_type = normalize_asset_type(cfg.get("asset_type", "character"))
    fps = cfg.get("fps", 24)
    frame_mode = normalize_frame_mode(cfg.get("frame_mode", "F"))
    source_size_mode = normalize_source_size_mode(cfg.get("source_size_mode", "canvas"))
    export_merged_spritesheet = normalize_bool(
        cfg.get("export_merged_spritesheet"), default=False)
    max_sheet = cfg.get("max_sheet_size", 2048)
    chroma_cfg = {"strength": cfg.get("chroma_strength", 1.5),
                  "edge_shrink": cfg.get("chroma_edge_shrink", 1)}
    detect_cfg = {"min_cycle": cfg.get("detect_min_cycle_frames", 10),
                  "peak_padding": cfg.get("detect_padding_frames", 3)}

    gen_videos_dir = os.path.join(args.char_dir, "_gen_videos")

    # 找要处理的动画
    if args.anims:
        anim_ids = args.anims.split(",")
    else:
        anim_ids = [d for d in os.listdir(gen_videos_dir)
                    if os.path.isfile(os.path.join(gen_videos_dir, d, "anim.mp4"))]

    # 从 _gen_videos/{id}/anim.prompt.json 读 play_type
    play_types = {}
    for d in os.listdir(gen_videos_dir):
        pf = os.path.join(gen_videos_dir, d, "anim.prompt.json")
        if os.path.isfile(pf):
            p = _load_json(pf)
            play_types[p["id"]] = p["play_type"]

    # ASCII 临时目录(cv2 不认中文路径)
    work = ascii_workdir("sprite_work")

    import time as _t
    char_name = meta.get("char_name", os.path.basename(args.char_dir))
    anim_configs = {}
    keyframe_maps = {}

    for aid in anim_ids:
        video = os.path.join(gen_videos_dir, aid, "anim.mp4")
        if not os.path.exists(video):
            print(f"跳过 {aid}: 无 anim.mp4")
            continue

        pt = play_types.get(aid, "loop")
        print(f"\n{'='*50}")
        print(f"[{aid}] ({pt})")
        _t0_total = _t.time()

        # 拷视频到 ASCII 目录 + 拆帧
        _t0 = _t.time()
        v_ascii = os.path.join(work, aid, "anim.mp4")
        os.makedirs(os.path.dirname(v_ascii), exist_ok=True)
        shutil.copy2(video, v_ascii)
        fr_dir = os.path.join(work, aid, "raw_frames")
        extract_frames(v_ascii, fr_dir)
        frame_paths, grays = CD.load_frames_gray(fr_dir)
        print(f"  拆帧: {len(frame_paths)} 帧 ({_t.time()-_t0:.1f}s)")

        # 循环检测 / 峰值隔离(用缩小帧加速)
        _t0 = _t.time()
        DETECT_H = 480
        if grays[0].shape[0] > DETECT_H:
            scale = DETECT_H / grays[0].shape[0]
            grays_small = [cv2.resize(g, (max(1, int(g.shape[1]*scale)), DETECT_H)) for g in grays]
        else:
            grays_small = grays
        chosen = detect_segment(frame_paths, grays_small, pt, detect_cfg)
        print(f"  选段: {len(chosen)} 帧 ({_t.time()-_t0:.1f}s)")

        # 色差键抠图 → 输出到 _gen_videos/{aid}/frames/
        _t0 = _t.time()
        frames_dir = os.path.join(gen_videos_dir, aid, "frames")
        if os.path.exists(frames_dir):
            shutil.rmtree(frames_dir)
        os.makedirs(frames_dir)
        imgs = []
        for j, sp in enumerate(chosen):
            with Image.open(sp) as _raw:
                im = chroma_key_image(_raw, key_color,
                                      strength=chroma_cfg.get("strength", 1.5),
                                      edge_shrink=chroma_cfg.get("edge_shrink", 1))
            op = os.path.join(frames_dir, f"frame_{j+1:04d}.png")
            im.save(op)
            imgs.append(im)
        print(f"  抠图: {len(imgs)} 帧 ({_t.time()-_t0:.1f}s)")

        # frames_preview.webp
        _t0 = _t.time()
        dur = int(1000 / max(1, fps))
        preview_path = os.path.join(gen_videos_dir, aid, "frames_preview.webp")
        write_preview_webp(imgs, [dur] * len(imgs), preview_path)
        print(f"  frames_preview.webp 中间预览 ({_t.time()-_t0:.1f}s)")

        if frame_mode == "K":
            key_dir, key_map = ensure_keyframes(frames_dir, fps, pt, force=True)
            if key_map:
                keyframe_maps[aid] = key_map
                write_preview_from_dir(key_dir, preview_path, fps,
                                       key_map.get("frame_durations_ms", []))
                ratio = key_map.get("compression_ratio", 1)
                print(f"  K帧: {key_map['source_total_frames']} → {key_map['keyframe_count']} 帧 "
                      f"({ratio:.1%})")
                print(f"  frames_preview.webp 已更新为 K帧中间预览")

        anim_configs[aid] = {"play_type": pt, "fps": fps}
        print(f"  合计: {_t.time()-_t0_total:.1f}s")

    # 精灵级统一导出
    from env_compat import resolve_output_dir, cloud_preview_url
    assets_root = resolve_output_dir(cfg.get("output_dir", "assets/sprites"))
    exports_dir = os.path.join(assets_root, char_name)
    exported_anim_ids = []
    if anim_configs:
        _t0 = _t.time()
        print(f"\n{'='*50}")
        print(f"精灵表导出 (target_height={target_height}, asset_type={asset_type}, frame_mode={frame_mode}, source_size_mode={source_size_mode}, max_sheet={max_sheet}, export_merged_spritesheet={export_merged_spritesheet})")

        # 收集所有帧目录(含之前已处理的 + 本次新处理的)
        all_frames_root = os.path.join(work, "all_frames")
        if os.path.exists(all_frames_root):
            shutil.rmtree(all_frames_root)
        os.makedirs(all_frames_root)

        # 汇总所有动画的帧到临时 ASCII 目录(sprite_export 需要)
        all_anim_configs = {}
        for aid_dir in os.listdir(gen_videos_dir):
            fdir = os.path.join(gen_videos_dir, aid_dir, "frames")
            if os.path.isdir(fdir) and glob.glob(os.path.join(fdir, "frame_*.png")):
                pt = play_types.get(aid_dir, "loop")
                export_fdir = fdir
                cfg_entry = {"play_type": pt, "fps": fps}
                if frame_mode == "K":
                    key_fdir, key_map = ensure_keyframes(fdir, fps, pt)
                    if key_map:
                        export_fdir = key_fdir
                        keyframe_maps[aid_dir] = key_map
                        cfg_entry["frame_durations"] = key_map.get("frame_durations_ms", [])
                    else:
                        print(f"  ⚠️ {aid_dir}: K帧生成失败,临时按全帧导出")
                dst = os.path.join(all_frames_root, aid_dir)
                shutil.copytree(export_fdir, dst)
                all_anim_configs[aid_dir] = cfg_entry
        exported_anim_ids = list(all_anim_configs)

        export_tmp = os.path.join(work, "export")
        os.makedirs(export_tmp, exist_ok=True)
        ready_image_path = os.path.join(args.char_dir, "_gen_images", "ready.png")
        SE.export_character(all_frames_root, export_tmp, target_height=target_height,
                            anim_configs=all_anim_configs,
                            max_sheet_size=max_sheet,
                            ready_image_path=ready_image_path,
                            key_color=key_color,
                            asset_type=asset_type,
                            source_size_mode=source_size_mode)

        # 逐个拷回 exports/
        os.makedirs(exports_dir, exist_ok=True)
        for aid_dir in os.listdir(export_tmp):
            src = os.path.join(export_tmp, aid_dir)
            dst = os.path.join(exports_dir, aid_dir)
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)

        # 精灵级一致性检查:本次只重导了部分动画时,exports/ 里残留的旧动画
        # 可能是用不同参数导出的,合并图集/manifest 会混用 → 显式告警。
        expected_meta = SE.sprite_export_meta(
            target_height, asset_type, source_size_mode, max_sheet)
        consistency_issues = check_sprite_consistency(exports_dir, expected_meta)
        if consistency_issues:
            print("  ⚠️ 精灵级参数不一致(合并图集/manifest 会混用不同参数):")
            for name, detail in consistency_issues:
                print(f"     - {name}: {detail}")
            print("     建议:用同一套参数对全部动画重跑,使精灵内各动画一致。")

        if export_merged_spritesheet:
            merged_result = SE.export_merged_spritesheet_from_exports(
                exports_dir,
                max_sheet_size=max_sheet,
                source_size_mode=source_size_mode,
            )
            if merged_result:
                print(f"  合并图集: {os.path.join(exports_dir, 'spritesheet.json')}")
            sprite_manifest = SE.write_sprite_manifest(exports_dir)
        else:
            SE.clear_merged_spritesheet(exports_dir)
            sprite_manifest = SE.write_sprite_manifest(exports_dir)
        print(f"  精灵入口: {os.path.abspath(sprite_manifest)}")

        for aid_dir in all_anim_configs:
            preview_path = os.path.join(gen_videos_dir, aid_dir, "frames_preview.webp")
            if write_export_preview(os.path.join(exports_dir, aid_dir), preview_path):
                if aid_dir in anim_configs:
                    preview_url = cloud_preview_url(preview_path, char_name, aid_dir)
                    if preview_url:
                        print(f"  最终预览: ![{aid_dir}]({preview_url})")
                    else:
                        print(f"  最终预览: {os.path.abspath(preview_path)}")

        print(f"  导出耗时: {_t.time()-_t0:.1f}s")

    # ═══ 验收清单 ═══
    print(f"\n{'═'*50}")
    print("验收清单")
    print(f"{'═'*50}")

    print("\n[自动检测]")

    # sourceSize 与配置模式一致
    source_sizes = set()
    source_sizes_by_anim = {}
    for jf in glob.glob(os.path.join(exports_dir, "*/spritesheet*.json")):
        anim_name = os.path.basename(os.path.dirname(jf))
        anim_sizes = source_sizes_by_anim.setdefault(anim_name, set())
        data = _load_json(jf)
        for f_meta in data["frames"].values():
            size = (f_meta["sourceSize"]["w"], f_meta["sourceSize"]["h"])
            source_sizes.add(size)
            anim_sizes.add(size)
    if source_size_mode == "bbox-per-anim":
        unstable = {name: sorted(sizes)
                    for name, sizes in source_sizes_by_anim.items()
                    if len(sizes) > 1}
        if not unstable:
            print("  ✅ sourceSize=bbox-per-anim(每个动画内部一致,不同动画可不同)")
        else:
            print(f"  ⚠️ sourceSize 异常(bbox-per-anim 下同一动画内不应变化): {unstable}")
    elif len(source_sizes) <= 1:
        ss = source_sizes.pop() if source_sizes else (0, 0)
        print(f"  ✅ sourceSize=canvas(缩放后原始帧画布 {ss[0]}×{ss[1]})")
    else:
        print(f"  ⚠️ sourceSize 不一致(canvas 模式下应保持原始帧画布一致): {source_sizes}")

    mode_issues = []
    for jf in glob.glob(os.path.join(exports_dir, "*/spritesheet.json")):
        data = _load_json(jf)
        if data.get("meta", {}).get("source_size_mode") != source_size_mode:
            mode_issues.append(os.path.relpath(jf, exports_dir))
    if not mode_issues:
        print(f"  ✅ 入口 meta.source_size_mode={source_size_mode}")
    else:
        print(f"  ⚠️ 入口 meta.source_size_mode 缺失或不一致: {mode_issues}")

    # meta.pivot 合法且一致
    pivot_issues = []
    pivots = set()
    for jf in glob.glob(os.path.join(exports_dir, "*/spritesheet.json")):
        data = _load_json(jf)
        pivot = data.get("meta", {}).get("pivot")
        ok = False
        if isinstance(pivot, dict):
            try:
                px = float(pivot.get("x"))
                py = float(pivot.get("y"))
                ok = (
                    pivot.get("space") == "sourceSize" and
                    pivot.get("unit") == "normalized" and
                    pivot.get("origin") == "top_left" and
                    0.0 <= px <= 1.0 and
                    0.0 <= py <= 1.0
                )
                if ok:
                    pivots.add((round(px, 6), round(py, 6)))
            except (TypeError, ValueError):
                ok = False
        if not ok:
            pivot_issues.append(os.path.relpath(jf, exports_dir))
    if source_size_mode == "bbox-per-anim" and not pivot_issues:
        print(f"  ✅ 入口 meta.pivot 合法(sourceSize normalized,bbox-per-anim 下不同动画可不同)")
    elif not pivot_issues and len(pivots) <= 1:
        pv = next(iter(pivots), (0.5, 0.5))
        print(f"  ✅ 入口 meta.pivot 合法且一致(sourceSize normalized {pv[0]}, {pv[1]})")
    elif not pivot_issues:
        print(f"  ⚠️ 入口 meta.pivot 不一致: {pivots}")
    else:
        print(f"  ⚠️ 入口 meta.pivot 异常: {pivot_issues}")

    # 背景透明
    dirty = 0
    for aid in anim_configs:
        sample = os.path.join(get_export_frames_dir(gen_videos_dir, aid, frame_mode), "frame_0001.png")
        if os.path.exists(sample):
            a = np.asarray(Image.open(sample).convert("RGBA"))[:, :, 3]
            if a[0, 0] > 10 or a[0, -1] > 10 or a[-1, 0] > 10 or a[-1, -1] > 10:
                dirty += 1
    if dirty == 0:
        print("  ✅ 背景透明(角点无脏像素)")
    else:
        print(f"  ⚠️ {dirty} 个动画角点有非透明像素")

    # 精灵表尺寸
    oversized = []
    for sp in glob.glob(os.path.join(exports_dir, "*/spritesheet*.png")):
        with Image.open(sp) as im:
            if im.width > max_sheet or im.height > max_sheet:
                oversized.append(f"{os.path.basename(os.path.dirname(sp))}: {im.width}×{im.height}")
    if not oversized:
        print(f"  ✅ 精灵表每页 ≤ {max_sheet}")
    else:
        print(f"  ⚠️ 超尺寸: {oversized}")

    # JSON 帧数
    frame_mismatch = []
    for aid in anim_configs:
        fdir = get_export_frames_dir(gen_videos_dir, aid, frame_mode)
        frames_on_disk = len(glob.glob(os.path.join(fdir, "frame_*.png")))
        json_count = 0
        for jf in glob.glob(os.path.join(exports_dir, aid, "spritesheet*.json")):
            data = _load_json(jf)
            json_count += len(data["frames"])
        if frames_on_disk != json_count and json_count > 0:
            frame_mismatch.append(f"{aid}: disk={frames_on_disk} json={json_count}")
    if not frame_mismatch:
        print("  ✅ JSON 帧数与实际一致")
    else:
        print(f"  ⚠️ 帧数不一致: {frame_mismatch}")

    if frame_mode == "K":
        k_issues = []
        k_summaries = []
        for aid in anim_configs:
            key_dir = os.path.join(gen_videos_dir, aid, "frames_key")
            key_map = keyframe_maps.get(aid) or _load_keyframe_map(key_dir)
            if not key_map:
                k_issues.append(f"{aid}: 缺少 keyframe_map.json")
                continue
            key_count = key_map.get("keyframe_count", 0)
            duration_count = len(key_map.get("frame_durations_ms", []))
            if key_count != duration_count:
                k_issues.append(f"{aid}: keyframes={key_count}, durations={duration_count}")
                continue
            src_count = key_map.get("source_total_frames", 0)
            ratio = key_map.get("compression_ratio", 1)
            k_summaries.append(f"{aid}: {src_count}→{key_count} ({ratio:.1%})")
        if not k_issues:
            print(f"  ✅ K帧 duration 完整: {', '.join(k_summaries)}")
        else:
            print(f"  ⚠️ K帧元数据异常: {k_issues}")

    # 出框检测
    out_of_bounds = []
    for aid in anim_configs:
        fdir = get_export_frames_dir(gen_videos_dir, aid, frame_mode)
        for fp in glob.glob(os.path.join(fdir, "frame_*.png")):
            a = np.asarray(Image.open(fp).convert("RGBA"))[:, :, 3]
            if (a[0, :].max() > 10 or a[-1, :].max() > 10 or
                    a[:, 0].max() > 10 or a[:, -1].max() > 10):
                out_of_bounds.append(f"{aid}/{os.path.basename(fp)}")
                break
    if not out_of_bounds:
        print("  ✅ 无帧出框")
    else:
        print(f"  ⚠️ 出框: {out_of_bounds}")

    print("\n[需人工/Agent 审查(查看 frames_preview.webp)]")
    if asset_type == "sequence":
        print("  ☐ 序列表现符合用户要求")
        print("  ☐ 节奏流畅")
        print("  ☐ 画面位置和尺寸符合预期")
        print("  ☐ 边缘无 key 色残留")
    else:
        print("  ☐ 动作方向正确(朝右,未转身)")
        print("  ☐ 动画节奏流畅")
        print("  ☐ 无帧间角色忽大忽小")
        print("  ☐ 最终角色大小符合游戏预期")
        print("  ☐ 边缘无 key 色残留")

    print(f"\n完成: {len(anim_configs)} 个动画")
    print(f"  导出 → {os.path.abspath(exports_dir)}/{{id}}/")
    cleanup_intermediate_frames(gen_videos_dir, exported_anim_ids or list(anim_configs))
    print("  中间帧已自动清理;保留 anim.mp4、frames_preview.webp 和最终 exports/。")


if __name__ == "__main__":
    main()
