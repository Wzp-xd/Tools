#!/usr/bin/env python3
"""
chroma_key — 业内标准「色差键(color-difference / Vlahos)」纯算法抠图。

与"欧氏距离阈值"的关键区别:色差键按 **key 色相的占比** 推 alpha,并把 key 色分量
从 RGB 里彻底扣除 —— 任何含 key 色的像素(含边缘、含半透明特效透出的幕布色)都被
**alpha 化**且**不留 key 色残留**。这正是影视绿/蓝幕的标准做法。

数学(以品红 key=(1,0,1) 为例,前景 F 在品红幕布 K 上合成 P=F·a+K·(1-a)):
  品红的高通道=R,B,低通道=G。定义 spill s = min(R,B) - max(G) ≈ 幕布占比 (1-a)
    · 纯品红(1,0,1): s=1 → alpha=0
    · 纯白前景(1,1,1): s=0 → alpha=1(不动)
    · 白↔品红边缘(1,.5,1): s=.5 → alpha=.5 且去品红后= (.5,.5,.5)=预乘
  alpha = 1 - s
  去溢色:高通道各减 s → 得到**预乘**色(已无 key 色);除以 alpha 得直通色
对任意 key 色通用(绿:s=G-max(R,B);蓝:s=B-max(R,G);青/黄类比)。
对角色真实颜色(不含 key 色相)s≈0 → 不受影响。

纯 numpy+PIL,认中文路径。半透明特效透出的品红 → 自动按占比 alpha 化、去品红。
"""
import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageFilter


def _color_difference_alpha_despill(rgb01, key_rgb, strength=1.0):
    """返回 (alpha[H,W], premult_rgb[H,W,3])。rgb01 归一化 0..1。"""
    K = np.array(key_rgb, dtype=np.float32) / 255.0
    hi = K >= 0.5
    hi_idx = [i for i in range(3) if hi[i]]
    lo_idx = [i for i in range(3) if not hi[i]]
    chans = [rgb01[:, :, 0], rgb01[:, :, 1], rgb01[:, :, 2]]

    if not hi_idx or not lo_idx:
        # 退化 key(白/黑/灰,无明确色相)→ 回退到到 key 色的距离法
        d = np.sqrt(((rgb01 - K) ** 2).sum(2))
        alpha = np.clip((d - 0.16) / 0.32, 0, 1)
        return alpha, rgb01 * alpha[:, :, None]

    hi_min = np.minimum.reduce([chans[i] for i in hi_idx])
    lo_max = np.maximum.reduce([chans[i] for i in lo_idx])
    s = np.clip((hi_min - lo_max) * strength, 0.0, 1.0)   # ≈ 幕布占比(1-alpha)
    alpha = 1.0 - s

    premult = rgb01.copy()
    for i in hi_idx:                                       # 高通道减 s → 去除 key 色,得预乘
        premult[:, :, i] = np.clip(rgb01[:, :, i] - s, 0.0, 1.0)
    # 低通道本就不含 key 色,但要乘到预乘域以保持一致(实心区 alpha=1 不变)
    for i in lo_idx:
        premult[:, :, i] = np.clip(rgb01[:, :, i] * 1.0, 0.0, 1.0)
    # premult 已是"高通道去 key"的结果;对实心区(s=0)= 原色,对边缘= 预乘色
    return alpha, premult


def chroma_key_image(img, key_rgb, despill=True, premultiply=False,
                     strength=3.0, edge_shrink=2, defringe=0.0):
    """单张 PIL 图 → RGBA(色差键)。
    premultiply: 输出预乘 alpha(消缩放白/色边)。
    edge_shrink: alpha 向内收缩像素(切渗色环)。
    defringe:    0..1,半透明边缘带去饱和强度(把 h264 渗出的彩色边拉向中性灰)。
    """
    rgb01 = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    alpha, premult = _color_difference_alpha_despill(rgb01, key_rgb, strength)

    # 直通色必须用【原始 alpha】反预乘,否则被放大(白边bug)。
    a0 = alpha[:, :, None]
    straight = np.where(a0 > 1e-3, np.clip(premult / np.clip(a0, 1e-3, 1.0), 0, 1), 0.0)

    # edge_shrink 只收缩【输出 alpha 通道】,不参与上面的反预乘。
    alpha_out = alpha
    if edge_shrink and edge_shrink > 0:
        a_img = Image.fromarray((alpha * 255).astype(np.uint8))
        a_img = a_img.filter(ImageFilter.MinFilter(2 * edge_shrink + 1))
        alpha_out = np.asarray(a_img).astype(np.float32) / 255.0

    if not despill:
        out_rgb = rgb01
    elif premultiply:
        out_rgb = straight * alpha_out[:, :, None]    # 用收缩后的 alpha 重新预乘,一致
    else:
        out_rgb = straight

    alpha = alpha_out

    if defringe and defringe > 0:
        # 仅在半透明边缘带把颜色去饱和(拉向亮度灰),消除任何残留彩边(粉/红/蓝)
        band = np.clip((1.0 - np.abs(alpha - 0.5) * 2.0), 0, 1)   # 0.5 附近最强,0/1 处为 0
        band = (band * defringe)[:, :, None]
        lum = (0.299 * out_rgb[:, :, 0] + 0.587 * out_rgb[:, :, 1] +
               0.114 * out_rgb[:, :, 2])[:, :, None]
        out_rgb = out_rgb * (1 - band) + lum * band

    out = np.dstack([np.clip(out_rgb, 0, 1) * 255.0, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def chroma_key_dir(in_dir, out_dir, key_rgb, despill=True, premultiply=False,
                   strength=3.0, edge_shrink=2, pattern="frame_*.png"):
    os.makedirs(out_dir, exist_ok=True)
    paths = sorted(glob.glob(os.path.join(in_dir, pattern)))
    outs = []
    for p in paths:
        keyed = chroma_key_image(Image.open(p), key_rgb, despill, premultiply, strength, edge_shrink)
        op = os.path.join(out_dir, os.path.basename(p))
        keyed.save(op)
        outs.append(op)
    return outs


def _parse_rgb(s):
    return tuple(int(x) for x in s.split(","))


def main():
    ap = argparse.ArgumentParser(description="色差键纯算法抠图")
    ap.add_argument("in_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--key", required=True, help="幕布色 R,G,B,如 255,0,255")
    ap.add_argument("--strength", type=float, default=1.0, help="抠除强度(>1 更激进去 key 色)")
    ap.add_argument("--edge-shrink", type=int, default=0, help="alpha 向内收缩像素(默认0,色差键通常无需)")
    ap.add_argument("--no-despill", action="store_true")
    ap.add_argument("--premultiply", action="store_true", help="输出预乘 alpha")
    ap.add_argument("--pattern", default="frame_*.png")
    args = ap.parse_args()
    outs = chroma_key_dir(args.in_dir, args.out_dir, _parse_rgb(args.key),
                          despill=not args.no_despill, premultiply=args.premultiply,
                          strength=args.strength, edge_shrink=args.edge_shrink, pattern=args.pattern)
    print(f"chroma key (color-difference) done: {len(outs)} frames -> {args.out_dir} "
          f"(key={args.key}, strength={args.strength}, premultiply={args.premultiply})")


if __name__ == "__main__":
    main()
