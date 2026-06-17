#!/usr/bin/env python3
"""
prepare_ready_image — 预处理角色图,生成 ready.png + _meta.json

输入:
  <角色图路径>
  --char-name       角色名
  --option 1-4      视角选项
  --target-height   精灵高度(不传用 config 默认)
  --frame-mode      帧模式 F/K(不传用 config 默认)
  --art-style       风格词(转视角时用,可选)

做了:
  1. 动态选幕布色
  2. 合成到 1:1 方图幕布色底(有alpha时)/原图填充到方图(无alpha时)
  3. option=2 时翻转
  4. 判断是否需要 AI 转视角/换底 → 输出 ready.prompt.txt

输出:
  {work_dir}/{角色名}/_gen_images/ready.png
  {work_dir}/{角色名}/_meta.json(含所有配置:key_color/target_height/frame_mode/...)
  {work_dir}/{角色名}/_gen_images/ready.prompt.txt(有追加提示词时)
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))
from pick_key_color import pick_key_color
from prompt_builder import build_side_view_prompt
from env_compat import resolve_output_dir


def _has_alpha(img):
    if img.mode != "RGBA":
        return False
    a = np.asarray(img)[:, :, 3]
    return bool((a < 250).any())


def _compose_to_backdrop(img, key_rgb, layout=None):
    """透明图合成到 1:1 方图幕布色底。"""
    ly = layout or {}
    char_ratio = ly.get("char_ratio", 0.6)
    m_top = ly.get("margin_top", 0.3)

    a = np.asarray(img)
    alpha = a[:, :, 3]
    ys, xs = np.where(alpha > 10)
    if len(ys) == 0:
        raise ValueError("图像无有效像素(全透明)")
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())
    crop = img.crop((x0, y0, x1 + 1, y1 + 1))
    bw, bh = crop.size
    size = int(max(bw, bh) / char_ratio)
    canvas = Image.new("RGBA", (size, size), key_rgb + (255,))
    px = (size - bw) // 2
    py = int(size * m_top)
    canvas.alpha_composite(crop, (px, py))
    return canvas.convert("RGB")


def main():
    ap = argparse.ArgumentParser(description="预处理角色图 → ready.png + _meta.json")
    ap.add_argument("image", help="角色图路径")
    ap.add_argument("--char-name", default=None, help="角色名")
    ap.add_argument("--option", type=int, choices=[1, 2, 3, 4], default=1,
                    help="视角: 1=不动 2=翻转 3=纯侧视 4=cheated profile")
    ap.add_argument("--target-height", type=int, default=None, help="精灵高度px")
    ap.add_argument("--frame-mode", default=None, choices=["F", "K"], help="帧模式")
    ap.add_argument("--art-style", default=None, help="风格词")
    args = ap.parse_args()

    # 读 config
    cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))

    # 解析输出路径
    out_root = resolve_output_dir(cfg.get("work_dir", ".build/sprite-gen"))
    char_name = args.char_name or os.path.splitext(os.path.basename(args.image))[0]
    char_dir = os.path.join(out_root, char_name)
    gen_images_dir = os.path.join(char_dir, "_gen_images")
    os.makedirs(gen_images_dir, exist_ok=True)

    print(f"角色: {char_name}")
    print(f"工作目录: {char_dir}")

    # 1. 动态选幕布色
    rgb, info = pick_key_color(args.image)
    key_color_name = info["recommended_name"]
    print(f"幕布色: {key_color_name} {rgb} (裕度={info['margin']})")

    # 2. 合成到方图
    layout = cfg.get("ready_layout", {})
    char_ratio = layout.get("char_ratio", 0.6)
    m_top = layout.get("margin_top", 0.3)

    img = Image.open(args.image).convert("RGBA")
    has_alpha = _has_alpha(img)
    ready_path = os.path.join(gen_images_dir, "ready.png")

    MAX_READY_SIZE = 1280

    if has_alpha:
        ready_img = _compose_to_backdrop(img, rgb, layout)
        if ready_img.width > MAX_READY_SIZE:
            ready_img = ready_img.resize((MAX_READY_SIZE, MAX_READY_SIZE), Image.LANCZOS)
        ready_img.save(ready_path)
        print(f"透明图 → 1:1 方图 {key_color_name} 底(角色占{int(char_ratio*100)}%, {ready_img.width}px)")
    else:
        im_rgb = img.convert("RGB")
        w, h = im_rgb.size
        size = int(max(w, h) / char_ratio)
        if size > MAX_READY_SIZE:
            scale = MAX_READY_SIZE / size
            im_rgb = im_rgb.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
            w, h = im_rgb.size
            size = MAX_READY_SIZE
        canvas = Image.new("RGB", (size, size), rgb)
        px = (size - w) // 2
        py = int(size * m_top)
        canvas.paste(im_rgb, (px, py))
        canvas.save(ready_path)
        print(f"非透明图 → 1:1 方图填充(角色占{int(char_ratio*100)}%, {size}px)")

    # 3. 翻转
    if args.option == 2:
        im = Image.open(ready_path)
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        im.save(ready_path)
        print("已翻转")

    # 4. 判断是否需要 AI 转视角/换底
    need_view = args.option in (3, 4)
    need_backdrop_change = not has_alpha
    view_angle = "profile" if args.option == 3 else "cheated" if args.option == 4 else None

    prompt_path = os.path.join(gen_images_dir, "ready.prompt.txt")
    if need_view or need_backdrop_change:
        prompt = build_side_view_prompt(key_color_name, art_style=args.art_style,
                                        view_angle=view_angle or "profile")
        if need_backdrop_change and not need_view:
            prompt = (f"Redraw this exact same character in the exact same pose and angle.\n"
                      f"Keep the exact same art style, rendering and shading as the input image.\n"
                      f"Preserve all colors, clothing, accessories, hairstyle, and proportions exactly.\n"
                      f"Do not change, simplify, or add any design elements.\n"
                      f"Pure solid {key_color_name} background, no shadow, no ground line.")
        with open(prompt_path, "w", encoding="utf-8") as f:
            f.write(prompt)
        print(f"提示词 → {prompt_path}")
    else:
        if os.path.exists(prompt_path):
            os.remove(prompt_path)
        print("无追加提示词(ready.png 可直接使用)")

    print(f"ready.png → {ready_path}")

    # 写 _meta.json(一次写全,含导出参数)
    meta = {
        "char_name": char_name,
        "char_dir": char_dir,
        "key_color": list(rgb),
        "key_color_name": key_color_name,
        "margin": info["margin"],
        "has_alpha": has_alpha,
        "option": args.option,
        "target_height": args.target_height or cfg.get("target_height", 256),
        "frame_mode": args.frame_mode or cfg.get("frame_mode", "F"),
    }
    meta_path = os.path.join(char_dir, "_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f"_meta.json → {meta_path}")


if __name__ == "__main__":
    main()
