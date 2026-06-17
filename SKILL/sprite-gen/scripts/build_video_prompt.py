#!/usr/bin/env python3
"""
build_video_prompt — 为动画列表组装完整提示词 + 分配参考图

输入: 角色目录(含 _meta.json) + _user_anims.json(动画描述列表)
     _user_anims.json 格式: [{"id":"idle","play_type":"loop","action":"body gently bobbing..."}, ...]

做了:
  1. 读 _meta.json 拿 key_color_name
  2. 对每个动画,按 play_type 选模板(loop/once/attack)+ 填入动作描述 + 组装 negative
  3. 按动画分类(aerial/ground)分配对应参考图(如有姿态补图)
  4. 输出 _gen_videos/{id}/anim.prompt.json(prompt + negative + ref_image)

输出: {角色目录}/_gen_videos/{id}/anim.prompt.json
     每条包含: id, play_type, action, prompt, negative, ref_image

anim.prompt.json 是完整的生成配方——谁来生成(脚本/MCP)直接读这里就够。
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))

from prompt_builder import build_prompt

AERIAL_KEYWORDS = {"fly", "air", "hover", "aerial", "dash", "glide", "float"}


def _pick_ref_image(anim_id, char_dir):
    """按动画分类选参考图:aerial → aerial.png(如有),否则 ready.png。"""
    gen_images_dir = os.path.join(char_dir, "_gen_images")
    aid_lower = anim_id.lower()

    if any(kw in aid_lower for kw in AERIAL_KEYWORDS):
        if os.path.exists(os.path.join(gen_images_dir, "aerial.png")):
            return "_gen_images/aerial.png"

    if "incubate" in aid_lower or "crouch" in aid_lower:
        if os.path.exists(os.path.join(gen_images_dir, "crouching.png")):
            return "_gen_images/crouching.png"

    return "_gen_images/ready.png"


def main():
    ap = argparse.ArgumentParser(description="组装动画提示词 + 分配参考图")
    ap.add_argument("char_dir", help="角色目录(含 _meta.json)")
    ap.add_argument("anims", help="_user_anims.json 路径")
    args = ap.parse_args()

    # 读 config → meta 覆盖(统一优先级)
    cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    meta = json.load(open(os.path.join(args.char_dir, "_meta.json"), encoding="utf-8"))
    cfg.update(meta)

    key_color_name = cfg["key_color_name"]
    merge_neg = cfg.get("prompt_merge_negative", True)
    default_duration = str(cfg.get("video_duration", "5"))
    anims = json.load(open(args.anims, encoding="utf-8"))

    results = []
    for a in anims:
        aid = a["id"]
        pt = a["play_type"]
        action = a["action"]
        duration = a.get("duration", default_duration)
        prompt, negative = build_prompt(aid, pt, action, key_color_name)

        # merge_negative_to_prompt: 融入 prompt 尾部,不单独输出
        if merge_neg and negative:
            prompt = prompt + "\nAvoid: " + negative
            negative = None

        ref_image = _pick_ref_image(aid, args.char_dir)
        entry = {"id": aid, "play_type": pt, "action": action,
                 "prompt": prompt, "ref_image": ref_image, "duration": duration}
        if negative:
            entry["negative"] = negative
        results.append(entry)
        print(f"{'='*60}")
        print(f"[{aid}] ({pt}) ref={ref_image} duration={duration}")
        print(f"PROMPT:\n{prompt}")
        if negative:
            print(f"NEGATIVE:\n{negative}")

    gen_videos_dir = os.path.join(args.char_dir, "_gen_videos")
    os.makedirs(gen_videos_dir, exist_ok=True)
    for r in results:
        aid_dir = os.path.join(gen_videos_dir, r["id"])
        os.makedirs(aid_dir, exist_ok=True)
        out_path = os.path.join(aid_dir, "anim.prompt.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(r, f, ensure_ascii=False, indent=2)
    print(f"\n{'='*60}")
    print(f"共 {len(results)} 个动画 → _gen_videos/{{id}}/anim.prompt.json")
    print(f"AI 审核后可直接修改对应文件。generate_video / MCP 逐个读取。")


if __name__ == "__main__":
    main()
