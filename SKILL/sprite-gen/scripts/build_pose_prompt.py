#!/usr/bin/env python3
"""
build_pose_prompt — 检测姿态缺口 + 构建姿态参考图提示词

输入: {work_dir}/{精灵名}(含 _meta.json) + _user_anims.json
做了:
  1. 扫描 _user_anims.json,按 group(aerial/ground)分类
  2. 判断 ready.png 当前姿态(由用户在 _meta.json 中标注,或默认 ground)
  3. 检测缺口:有空中动画但 ready 是地面 → 缺飞行参考图;反之亦然
  4. 对每个缺口构建提示词(角色描述 + 目标姿态 + 幕布色)

输出:
  {work_dir}/{精灵名}/_gen_images/{姿态}.prompt.txt — 每个缺失姿态一条 prompt
  无缺口时不生成此文件

后续:
  有 _gen_images/{姿态}.prompt.txt → Agent 对每条调 generate_image 2次 → 用户选 → 存参考图
  无姿态提示词输出 → 直接下一步
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))

from prompt_builder import build_pose_reference_prompt


AERIAL_KEYWORDS = {"fly", "air", "hover", "aerial", "dash", "glide", "float"}
GROUND_KEYWORDS = {"idle", "walk", "run", "jump", "attack", "punch", "kick",
                   "slash", "cast", "hurt", "death", "crouch", "incubate", "stand"}


def _classify_group(anim_id):
    aid = anim_id.lower()
    if any(kw in aid for kw in AERIAL_KEYWORDS):
        return "aerial"
    return "ground"


def main():
    ap = argparse.ArgumentParser(description="检测姿态缺口 + 构建姿态提示词")
    ap.add_argument("char_dir", help="{work_dir}/{精灵名}(含 _meta.json)")
    ap.add_argument("anims", help="_user_anims.json 路径")
    ap.add_argument("--ready-pose", choices=["ground", "aerial"], default=None,
                    help="ready.png 当前姿态(不传则默认 ground)")
    args = ap.parse_args()

    meta = json.load(open(os.path.join(args.char_dir, "_meta.json"), encoding="utf-8"))
    anims = json.load(open(args.anims, encoding="utf-8"))
    key_color_name = meta["key_color_name"]
    ready_pose = args.ready_pose or meta.get("ready_pose", "ground")

    # 扫描动画分组
    has_aerial = any(_classify_group(a["id"]) == "aerial" for a in anims)
    has_ground = any(_classify_group(a["id"]) == "ground" for a in anims)
    has_crouch = any("incubate" in a["id"] or "crouch" in a["id"] for a in anims)

    # 检测缺口
    gaps = []
    if has_aerial and ready_pose != "aerial":
        gaps.append({
            "pose": "aerial",
            "filename": "aerial.png",
            "desc": "飞行/空中姿态参考图",
            "prompt_hint": "flying or hovering in mid-air, wings spread",
        })
    if has_ground and ready_pose != "ground":
        gaps.append({
            "pose": "ground",
            "filename": "standing.png",
            "desc": "站立/地面姿态参考图",
            "prompt_hint": "standing on the ground in a relaxed pose",
        })
    if has_crouch:
        gaps.append({
            "pose": "crouching",
            "filename": "crouching.png",
            "desc": "蹲伏姿态参考图",
            "prompt_hint": "crouching low with legs tucked underneath",
        })

    if not gaps:
        print("无姿态缺口,不需要补图。")
        return

    # 构建提示词
    results = []
    for gap in gaps:
        prompt = build_pose_reference_prompt(gap["prompt_hint"], key_color_name)
        results.append({
            "pose": gap["pose"],
            "filename": gap["filename"],
            "desc": gap["desc"],
            "prompt": prompt,
        })
        print(f"缺口: {gap['desc']} → {gap['filename']}")
        print(f"  prompt: {prompt[:80]}...")

    gen_images_dir = os.path.join(args.char_dir, "_gen_images")
    os.makedirs(gen_images_dir, exist_ok=True)
    for r in results:
        out_path = os.path.join(gen_images_dir, f"{r['pose']}.prompt.txt")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(r["prompt"])
        print(f"  → {out_path}")
    print(f"\n共 {len(results)} 个姿态缺口")
    print("后续: Agent 对每条 .prompt.txt 调 generate_image 2次 → 用户选 → 存为对应参考图")


if __name__ == "__main__":
    main()
