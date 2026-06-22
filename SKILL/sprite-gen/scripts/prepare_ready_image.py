#!/usr/bin/env python3
"""
prepare_ready_image — 预处理素材图,生成 ready.png + _meta.json

输入:
  <素材图路径>
  --char-name       精灵名(兼容旧参数名)
  --option 1-4      视角选项
  --target-height   精灵高度(不传用 config 默认)
  --frame-mode      帧模式 F/K(不传用 config 默认)
  --art-style       风格词(转视角时用,可选)
  --set key=value   只写入有消费侧的 _meta 覆盖项,可重复

做了:
  1. 动态选幕布色
  2. 有 alpha 时合成到 1:1 方图幕布色底;无 alpha 时输出透明抠图请求
  3. option=2 时翻转
  4. 判断是否需要 AI 转视角/透明抠图 → 输出 ready.prompt.txt 或 cutout.prompt.txt

输出:
  {work_dir}/{精灵名}/_gen_images/ready.png
  {work_dir}/{精灵名}/_meta.json(含关键元信息和显式 --set 覆盖项;后续脚本再与 config.json 合并)
  {work_dir}/{精灵名}/_gen_images/ready.prompt.txt(有追加提示词时)
  {work_dir}/{精灵名}/_gen_images/cutout_ref.png + cutout.prompt.txt(无 alpha 时)
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))
from pick_key_color import pick_key_color
from prompt_builder import build_cutout_prompt, build_side_view_prompt
from env_compat import resolve_output_dir

ALLOWED_META_OVERRIDES = {
    "target_height",
    "asset_type",
    "frame_mode",
    "source_size_mode",
    "export_merged_spritesheet",
    "ready_layout.content_ratio",
    "ready_layout.offset_ratio_x",
    "ready_layout.offset_ratio_y",
    "ready_pose",
    "video_duration",
    "video_generation_tier",
    "video_expected_resolution",
    "prompt_merge_negative",
    "fps",
    "max_sheet_size",
    "chroma_strength",
    "chroma_edge_shrink",
    "detect_min_cycle_frames",
    "detect_padding_frames",
}


def _has_alpha(img):
    if img.mode != "RGBA":
        return False
    a = np.asarray(img)[:, :, 3]
    return bool((a < 250).any())


def _parse_set_value(raw):
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def _set_nested(data, dotted_key, value):
    parts = dotted_key.split(".")
    cur = data
    for part in parts[:-1]:
        child = cur.get(part)
        if not isinstance(child, dict):
            child = {}
            cur[part] = child
        cur = child
    cur[parts[-1]] = value


def _has_nested(data, dotted_key):
    cur = data
    for part in dotted_key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return False
        cur = cur[part]
    return True


def _resolve_ready_layout(cfg, meta_overrides, asset_type):
    layout = dict(cfg.get("ready_layout", {}) or {})
    content_ratio = layout.get("content_ratio")
    if content_ratio is None:
        content_ratio = layout.get("char_ratio")
    if content_ratio is None:
        content_ratio = 0.6
    content_ratio = max(0.01, min(float(content_ratio), 1.0))
    layout["content_ratio"] = content_ratio

    layout["offset_ratio_x"] = float(_resolve_layout_value(layout, asset_type, "offset_ratio_x") or 0)
    layout["offset_ratio_y"] = float(_resolve_layout_value(layout, asset_type, "offset_ratio_y") or 0)
    return layout


def _resolve_layout_value(layout, asset_type, key):
    specific = f"{key}@{asset_type}"
    if specific in layout:
        return layout[specific]
    return layout.get(key)


def _resolve_paste_position(canvas_size, content_width, content_height, layout):
    base_x = (canvas_size - content_width) / 2.0
    base_y = (canvas_size - content_height) / 2.0
    x = base_x + canvas_size * float(layout.get("offset_ratio_x", 0) or 0)
    y = base_y + canvas_size * float(layout.get("offset_ratio_y", 0) or 0)
    return int(round(x)), int(round(y))


def _apply_meta_override(cfg, meta_overrides, item):
    if "=" not in item:
        raise ValueError(f"--set 需要 key=value 格式: {item}")
    key, raw = item.split("=", 1)
    key = key.strip()
    if key not in ALLOWED_META_OVERRIDES:
        allowed = ", ".join(sorted(ALLOWED_META_OVERRIDES))
        raise ValueError(f"不支持的 _meta 覆盖项: {key}. 允许: {allowed}")
    value = _parse_set_value(raw.strip())
    if key == "frame_mode":
        value = str(value).upper()
        if value not in {"F", "K"}:
            raise ValueError("frame_mode 只能是 F 或 K")
    if key == "video_generation_tier":
        value = str(value).lower()
        if value not in {"fast", "default"}:
            raise ValueError("video_generation_tier 只能是 fast 或 default")
    if key == "asset_type":
        value = str(value).lower()
        if value not in {"character", "sequence"}:
            raise ValueError("asset_type 只能是 character 或 sequence")
    if key == "source_size_mode":
        value = str(value).lower()
        if value not in {"canvas", "bbox-per-anim"}:
            raise ValueError("source_size_mode 只能是 canvas 或 bbox-per-anim")
    if key == "export_merged_spritesheet" and not isinstance(value, bool):
        raise ValueError("export_merged_spritesheet 只能是 true 或 false")
    if key == "ready_pose" and value not in {"ground", "aerial"}:
        raise ValueError("ready_pose 只能是 ground 或 aerial")

    _set_nested(cfg, key, value)
    _set_nested(meta_overrides, key, value)


def _compose_to_backdrop(img, key_rgb, layout=None):
    """透明图合成到 1:1 方图幕布色底。"""
    ly = layout or {}
    content_ratio = ly.get("content_ratio", 0.6)

    a = np.asarray(img)
    alpha = a[:, :, 3]
    ys, xs = np.where(alpha > 10)
    if len(ys) == 0:
        raise ValueError("图像无有效像素(全透明)")
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())
    crop = img.crop((x0, y0, x1 + 1, y1 + 1))
    bw, bh = crop.size
    size = int(max(bw, bh) / content_ratio)
    canvas = Image.new("RGBA", (size, size), key_rgb + (255,))
    px, py = _resolve_paste_position(size, bw, bh, ly)
    canvas.alpha_composite(crop, (px, py))
    return canvas.convert("RGB")


def _print_cutout_next_action(cutout_ref_path, cutout_prompt_path, char_dir):
    cutout_path = os.path.join(char_dir, "_gen_images", "cutout.png")
    print("下一步:")
    print("1. 用 cutout_ref.png 作为参考图,读取 cutout.prompt.txt 调图像生成 2 次,保存为 _gen_images/cutout_cand_{cnt}.png")
    print("2. 向用户展示候选图,必须等待用户确认;审核标准:主体一致、背景透明、边缘干净、构图不裁切且比例正常")
    print(f"3. 将用户选中的透明图保存为 {cutout_path}")
    print("4. 用同一组步骤2参数重跑本脚本,只把输入图换成 _gen_images/cutout.png")
    print("5. 重跑得到 ready.png 后,按主文档预处理公共记录模板记录步骤2完成")
    print(f"参考图: {cutout_ref_path}")
    print(f"提示词: {cutout_prompt_path}")


def main():
    ap = argparse.ArgumentParser(description="预处理素材图 → ready.png + _meta.json")
    ap.add_argument("image", help="素材图路径")
    ap.add_argument("--char-name", default=None, help="精灵名(兼容旧参数名)")
    ap.add_argument("--option", type=int, choices=[1, 2, 3, 4], default=1,
                    help="视角: 1=不动 2=翻转 3=纯侧视 4=cheated profile")
    ap.add_argument("--target-height", type=int, default=None, help="精灵高度px")
    ap.add_argument("--frame-mode", default=None, choices=["F", "K"], help="帧模式")
    ap.add_argument("--art-style", default=None, help="风格词")
    ap.add_argument("--set", dest="meta_sets", action="append", default=[],
                    help="高级 _meta 覆盖项,key=value,可重复")
    args = ap.parse_args()

    # 读 config
    cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    meta_overrides = {}
    for item in args.meta_sets:
        _apply_meta_override(cfg, meta_overrides, item)
    if args.target_height is not None:
        cfg["target_height"] = args.target_height
        meta_overrides["target_height"] = args.target_height
    if args.frame_mode is not None:
        cfg["frame_mode"] = args.frame_mode
        meta_overrides["frame_mode"] = args.frame_mode
    asset_type = str(cfg.get("asset_type", "character") or "character").strip().lower()

    # 解析输出路径
    out_root = resolve_output_dir(cfg.get("work_dir", ".build/sprite-gen"))
    asset_output_root = resolve_output_dir(cfg.get("output_dir", "assets/sprites"))
    char_name = args.char_name or os.path.splitext(os.path.basename(args.image))[0]
    char_dir = os.path.join(out_root, char_name)
    asset_output_dir = os.path.join(asset_output_root, char_name)
    gen_images_dir = os.path.join(char_dir, "_gen_images")
    os.makedirs(gen_images_dir, exist_ok=True)

    print(f"精灵: {char_name} (asset_type={asset_type})")
    print(f"work_dir: {out_root}")
    print(f"{{work_dir}}/{{精灵名}}: {char_dir}")
    print(f"output_dir: {asset_output_root}")
    print(f"{{output_dir}}/{{精灵名}}: {asset_output_dir}")

    # 1. 动态选幕布色
    rgb, info = pick_key_color(args.image)
    key_color_name = info["recommended_name"]
    print(f"幕布色: {key_color_name} {rgb} (安全距离={info['key_color_min_distance']})")

    # 2. 合成到方图
    layout = _resolve_ready_layout(cfg, meta_overrides, asset_type)
    content_ratio = layout.get("content_ratio", 0.6)

    img = Image.open(args.image).convert("RGBA")
    has_alpha = _has_alpha(img)
    ready_path = os.path.join(gen_images_dir, "ready.png")
    ready_written = False

    MAX_READY_SIZE = 1280

    if not has_alpha:
        cutout_ref_path = os.path.join(gen_images_dir, "cutout_ref.png")
        cutout_prompt_path = os.path.join(gen_images_dir, "cutout.prompt.txt")
        img.convert("RGB").save(cutout_ref_path)
        with open(cutout_prompt_path, "w", encoding="utf-8") as f:
            f.write(build_cutout_prompt(art_style=args.art_style))
        for stale_path in (ready_path, os.path.join(gen_images_dir, "ready.prompt.txt")):
            if os.path.exists(stale_path):
                os.remove(stale_path)
        print("非透明输入 → 需要先 AI 抠成透明图,再重跑本脚本")
        _print_cutout_next_action(cutout_ref_path, cutout_prompt_path, char_dir)
    elif has_alpha:
        ready_img = _compose_to_backdrop(img, rgb, layout)
        if ready_img.width > MAX_READY_SIZE:
            ready_img = ready_img.resize((MAX_READY_SIZE, MAX_READY_SIZE), Image.LANCZOS)
        ready_img.save(ready_path)
        ready_written = True
        print(f"透明图 → 1:1 方图 {key_color_name} 底(主体占{int(content_ratio*100)}%, {ready_img.width}px)")
    else:
        im_rgb = img.convert("RGB")
        w, h = im_rgb.size
        size = int(max(w, h) / content_ratio)
        if size > MAX_READY_SIZE:
            scale = MAX_READY_SIZE / size
            im_rgb = im_rgb.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
            w, h = im_rgb.size
            size = MAX_READY_SIZE
        canvas = Image.new("RGB", (size, size), rgb)
        px, py = _resolve_paste_position(size, w, h, layout)
        canvas.paste(im_rgb, (px, py))
        canvas.save(ready_path)
        ready_written = True
        print(f"非透明图 → 1:1 方图填充(主体占{int(content_ratio*100)}%, {size}px)")

    # 3. 翻转
    if args.option == 2 and ready_written:
        with Image.open(ready_path) as _src:
            im = _src.transpose(Image.FLIP_LEFT_RIGHT)
        im.save(ready_path)
        print("已翻转")

    # 4. 判断是否需要 AI 转视角
    need_view = args.option in (3, 4)
    view_angle = "profile" if args.option == 3 else "cheated" if args.option == 4 else None

    prompt_path = os.path.join(gen_images_dir, "ready.prompt.txt")
    if ready_written and need_view:
        prompt = build_side_view_prompt(key_color_name, art_style=args.art_style,
                                        view_angle=view_angle or "profile")
        with open(prompt_path, "w", encoding="utf-8") as f:
            f.write(prompt)
        print(f"提示词 → {prompt_path}")
    elif ready_written:
        if os.path.exists(prompt_path):
            os.remove(prompt_path)
        print("无追加提示词(ready.png 可直接使用)")

    if ready_written:
        print(f"ready.png → {ready_path}")

    # 写 _meta.json(关键元信息 + 显式 --set 覆盖项)
    meta = {
        "char_name": char_name,
        "char_dir": char_dir,
        "key_color": list(rgb),
        "key_color_name": key_color_name,
        "has_alpha": has_alpha,
        "option": args.option,
        "target_height": cfg.get("target_height", 256),
        "asset_type": cfg.get("asset_type", "character"),
        "frame_mode": cfg.get("frame_mode", "F"),
    }
    meta.update(meta_overrides)
    meta_path = os.path.join(char_dir, "_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f"_meta.json → {meta_path}")


if __name__ == "__main__":
    main()
