#!/usr/bin/env python3
"""
video_to_sprites — 视频变精灵表(全自动后处理管线)

输入: 角色目录(含 _meta.json + _gen_videos/{动画id}/anim.mp4)
     --anims id1,id2,...   指定处理哪些动画(不传=_gen_videos 下全部有 anim.mp4 的)

做了:
  1. OpenCV 拆全帧(ASCII 临时目录,绕 cv2 中文路径)
  2. 循环动画 → 循环检测(TSM+pHash+光流+SSIM+JumpRatio)找完整循环窗口
     单次动画 → 峰值隔离,只留动作爆发段
  3. 色差键抠图(chroma key):按幕布色 alpha 化,去溢色,消 h264 渗色边
  4. 角色级统一精灵表导出:两遍扫描 sourceSize,多行网格 ≤ max_sheet_size
  5. 生成 frames_preview.webp(动画 WebP,lossless 全 alpha)

输出:
  {角色目录}/_gen_videos/{动画id}/frames/frame_*.png
  {角色目录}/_gen_videos/{动画id}/frames_preview.webp
  {角色目录}/exports/{动画id}/spritesheet.png + spritesheet.json

传几个做几个:
  --anims idle        → 只做 idle
  --anims idle,walk   → 做这两个
  不传                → 全做

可反复调用(重做某个动画时只传那个 id)。
"""
import argparse
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
import sprite_export as SE
from env_compat import ensure_utf8, ascii_workdir

ensure_utf8()


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


def main():
    ap = argparse.ArgumentParser(description="视频 → 精灵表(全自动后处理)")
    ap.add_argument("char_dir", help="角色目录")
    ap.add_argument("--anims", default=None, help="动画id列表(逗号分隔),不传=全部")
    args = ap.parse_args()

    cfg = json.load(open(os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json"), encoding="utf-8"))
    meta = json.load(open(os.path.join(args.char_dir, "_meta.json"), encoding="utf-8"))
    cfg.update(meta)  # meta 覆盖 config
    key_color = tuple(cfg["key_color"])
    target_height = cfg.get("target_height", 256)
    fps = cfg.get("fps", 24)
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
            p = json.load(open(pf, encoding="utf-8"))
            play_types[p["id"]] = p["play_type"]

    # ASCII 临时目录(cv2 不认中文路径)
    work = ascii_workdir("sprite_work")

    import time as _t
    char_name = meta.get("char_name", os.path.basename(args.char_dir))
    anim_configs = {}

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
            im = chroma_key_image(Image.open(sp), key_color,
                                  strength=chroma_cfg.get("strength", 1.5),
                                  edge_shrink=chroma_cfg.get("edge_shrink", 1))
            op = os.path.join(frames_dir, f"frame_{j+1:04d}.png")
            im.save(op)
            imgs.append(im)
        print(f"  抠图: {len(imgs)} 帧 ({_t.time()-_t0:.1f}s)")

        # frames_preview.webp
        _t0 = _t.time()
        dur = int(1000 / fps)
        preview_path = os.path.join(gen_videos_dir, aid, "frames_preview.webp")
        imgs[0].save(preview_path, format="WEBP",
                     save_all=True, append_images=imgs[1:],
                     duration=dur, loop=0, lossless=True)
        print(f"  frames_preview.webp ({_t.time()-_t0:.1f}s)")

        # 预览输出
        from env_compat import cloud_preview_url
        preview_url = cloud_preview_url(preview_path, char_name, aid)
        if preview_url:
            print(f"  预览: ![{aid}]({preview_url})")
        else:
            print(f"  预览: {os.path.abspath(preview_path)}")

        anim_configs[aid] = {"play_type": pt, "fps": fps}
        print(f"  合计: {_t.time()-_t0_total:.1f}s")

    # 角色级统一导出
    from env_compat import resolve_output_dir
    assets_root = resolve_output_dir(cfg.get("output_dir", "assets/sprites"))
    exports_dir = os.path.join(assets_root, char_name)
    if anim_configs:
        _t0 = _t.time()
        print(f"\n{'='*50}")
        print(f"精灵表导出 (target_height={target_height}, max_sheet={max_sheet})")

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
                dst = os.path.join(all_frames_root, aid_dir)
                shutil.copytree(fdir, dst)
                pt = play_types.get(aid_dir, "loop")
                all_anim_configs[aid_dir] = {"play_type": pt, "fps": fps}

        export_tmp = os.path.join(work, "export")
        os.makedirs(export_tmp, exist_ok=True)
        SE.export_character(all_frames_root, export_tmp, target_height=target_height,
                            anim_configs=all_anim_configs)

        # 逐个拷回 exports/
        os.makedirs(exports_dir, exist_ok=True)
        for aid_dir in os.listdir(export_tmp):
            src = os.path.join(export_tmp, aid_dir)
            dst = os.path.join(exports_dir, aid_dir)
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)

        print(f"  导出耗时: {_t.time()-_t0:.1f}s")

    # ═══ 验收清单 ═══
    print(f"\n{'═'*50}")
    print("验收清单")
    print(f"{'═'*50}")

    print("\n[自动检测]")

    # sourceSize 一致
    source_sizes = set()
    for jf in glob.glob(os.path.join(exports_dir, "*/spritesheet*.json")):
        data = json.load(open(jf, encoding="utf-8"))
        for f_meta in data["frames"].values():
            source_sizes.add((f_meta["sourceSize"]["w"], f_meta["sourceSize"]["h"]))
    if len(source_sizes) <= 1:
        ss = source_sizes.pop() if source_sizes else (0, 0)
        print(f"  ✅ sourceSize 一致 ({ss[0]}×{ss[1]})")
    else:
        print(f"  ⚠️ sourceSize 不一致: {source_sizes}")

    # 背景透明
    dirty = 0
    for aid in anim_configs:
        sample = os.path.join(gen_videos_dir, aid, "frames", "frame_0001.png")
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
        im = Image.open(sp)
        if im.width > max_sheet or im.height > max_sheet:
            oversized.append(f"{os.path.basename(os.path.dirname(sp))}: {im.width}×{im.height}")
    if not oversized:
        print(f"  ✅ 精灵表每页 ≤ {max_sheet}")
    else:
        print(f"  ⚠️ 超尺寸: {oversized}")

    # JSON 帧数
    frame_mismatch = []
    for aid in anim_configs:
        fdir = os.path.join(gen_videos_dir, aid, "frames")
        frames_on_disk = len(glob.glob(os.path.join(fdir, "frame_*.png")))
        json_count = 0
        for jf in glob.glob(os.path.join(exports_dir, aid, "spritesheet*.json")):
            data = json.load(open(jf, encoding="utf-8"))
            json_count += len(data["frames"])
        if frames_on_disk != json_count and json_count > 0:
            frame_mismatch.append(f"{aid}: disk={frames_on_disk} json={json_count}")
    if not frame_mismatch:
        print("  ✅ JSON 帧数与实际一致")
    else:
        print(f"  ⚠️ 帧数不一致: {frame_mismatch}")

    # 出框检测
    out_of_bounds = []
    for aid in anim_configs:
        fdir = os.path.join(gen_videos_dir, aid, "frames")
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
    print("  ☐ 动作方向正确(朝右,未转身)")
    print("  ☐ 动画节奏流畅")
    print("  ☐ 无帧间角色忽大忽小")

    print(f"\n完成: {len(anim_configs)} 个动画")
    print(f"  帧 → _gen_videos/{{id}}/frames/")
    print(f"  导出 → exports/{{id}}/")


if __name__ == "__main__":
    main()
