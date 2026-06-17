#!/usr/bin/env python3
"""
pick_key_color — 为 chroma key 动态选择背景幕布色。

原理:抠图删的是背景幕布色,所以幕布色必须是"角色身上没有、且离角色所有颜色都尽量远"
的颜色。本工具采集角色调色板,在候选色中选"到角色(+预期特效色)最小距离最大"的那个。

不固定品红/绿幕 —— 每个角色动态算。影视绿幕假设主体是真人(皮肤不含绿),
而我们能控制生成背景、角色颜色任意,所以按角色选最远色严格更优。

用法:
  CLI:   python pick_key_color.py <image> [--effect-colors 255,0,0 0,0,255] [--json]
  import: from pick_key_color import pick_key_color; rgb, info = pick_key_color("ready.png")
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image


# 候选幕布色:覆盖色相环 + 高饱和。chroma key 实践偏好高饱和纯色,边缘 despill 才干净。
CANDIDATES = {
    "magenta":     (255, 0, 255),
    "green":       (0, 255, 0),
    "cyan":        (0, 255, 255),
    "blue":        (0, 0, 255),
    "chartreuse":  (128, 255, 0),
    "spring":      (0, 255, 128),
    "azure":       (0, 128, 255),
    "violet":      (128, 0, 255),
    "rose":        (255, 0, 128),
    "orange":      (255, 128, 0),
    "red":         (255, 0, 0),
    "yellow":      (255, 255, 0),
}


def _character_pixels(img, bg_tol=12):
    """返回角色像素的 Nx3 数组(排除透明 & 排除四角推断出的纯色背景)。"""
    if img.mode == "RGBA":
        a = np.asarray(img)
        alpha = a[:, :, 3]
        rgb = a[:, :, :3].astype(np.int32)
        chars = rgb[alpha > 200]
        if len(chars):
            return chars
        # 全不透明的 RGBA,退化到按角点背景剔除
        img = img.convert("RGB")
    rgb = np.asarray(img.convert("RGB")).astype(np.int32)
    h, w, _ = rgb.shape
    corners = np.array([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    bg = corners.mean(0)
    flat = rgb.reshape(-1, 3)
    keep = np.sqrt(((flat - bg) ** 2).sum(1)) > bg_tol * np.sqrt(3)
    chars = flat[keep]
    return chars if len(chars) else flat


def pick_key_color(image_path, effect_colors=None, candidates=None):
    """
    返回 (recommended_rgb_tuple, info_dict)。
    info: {'recommended','margin','ranking':[(name,rgb,min_dist),...]}
    margin = 推荐色到角色/特效色的最小距离(越大越安全,经验上 >120 较稳)。
    """
    img = Image.open(image_path)
    chars = _character_pixels(img).astype(np.float32)
    palette = chars
    if effect_colors:
        ec = np.array(effect_colors, dtype=np.float32)
        palette = np.vstack([palette, ec]) if len(palette) else ec

    cand = candidates or CANDIDATES
    ranking = []
    for name, c in cand.items():
        d = np.sqrt(((palette - np.array(c, dtype=np.float32)) ** 2).sum(1)).min()
        ranking.append((name, tuple(c), float(d)))
    ranking.sort(key=lambda r: -r[2])

    best_name, best_rgb, best_d = ranking[0]
    info = {
        "recommended": best_rgb,
        "recommended_name": best_name,
        "margin": round(best_d, 1),
        "ranking": [{"name": n, "rgb": list(c), "min_dist": round(d, 1)} for n, c, d in ranking],
    }
    return best_rgb, info


def main():
    ap = argparse.ArgumentParser(description="动态选 chroma key 背景幕布色")
    ap.add_argument("image", help="角色图(透明原图或 ready.png)")
    ap.add_argument("--effect-colors", nargs="*", default=[],
                    help="预期特效色,如 255,80,0 80,160,255")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()

    ecs = []
    for s in args.effect_colors:
        ecs.append(tuple(int(x) for x in s.split(",")))

    rgb, info = pick_key_color(args.image, effect_colors=ecs or None)
    if args.json:
        print(json.dumps(info, ensure_ascii=False, indent=2))
    else:
        print(f"推荐幕布色: {info['recommended_name']} {rgb}  (安全裕度={info['margin']})")
        print("排名(到角色最近距离,越大越安全):")
        for r in info["ranking"]:
            print(f"  {r['name']:11} {tuple(r['rgb'])}  {r['min_dist']}")
        if info["margin"] < 100:
            print("⚠️ 裕度偏低(<100):角色颜色覆盖很广,边缘 despill 需更小心,"
                  "或考虑生成时让角色避开该色域。")


if __name__ == "__main__":
    main()
