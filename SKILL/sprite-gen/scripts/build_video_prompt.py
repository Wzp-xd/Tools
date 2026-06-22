#!/usr/bin/env python3
"""
build_video_prompt — 为动画列表组装完整提示词 + 分配参考图

输入: {work_dir}/{精灵名}(含 _meta.json) + _user_anims.json(动画描述列表)
     _user_anims.json 格式: [{"id":"idle","play_type":"loop","action":"body gently bobbing..."}, ...]

做了:
  1. 读 _meta.json 拿 key_color_name
  2. character:按 play_type 选角色模板; sequence:选中立序列模板 + 用户自定义提示词
  3. character 按动画分类(aerial/ground)分配对应参考图; sequence 固定 ready.png
  4. 推导视频分辨率期望值(可配置,默认 target_height/content_ratio*1.2 后归档)
  5. 输出 _gen_videos/{id}/anim.prompt.json(prompt + negative + ref_image)

输出: {work_dir}/{精灵名}/_gen_videos/{id}/anim.prompt.json
     每条包含: id, play_type, action, prompt, negative, ref_image, duration,
               video_expected_resolution, video_generation_tier

anim.prompt.json 是完整的生成配方——谁来生成(脚本/MCP)直接读这里就够。
"""
import argparse
import copy
import glob
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))

from env_compat import ensure_utf8
from prompt_builder import build_prompt, build_sequence_prompt

ensure_utf8()

AERIAL_KEYWORDS = {"fly", "air", "hover", "aerial", "dash", "glide", "float"}
VIDEO_RESOLUTION_BUCKETS = (480, 720, 1080)
VIDEO_RESOLUTION_REDUNDANCY = 1.2
VIDEO_GENERATION_TIERS = {"fast", "default"}


def _deep_merge(base, override):
    result = copy.deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _bucket_video_resolution(value):
    """Map a numeric expectation to the nearest supported upper bucket."""
    try:
        v = float(str(value).lower().rstrip("p"))
    except (TypeError, ValueError):
        return None
    for bucket in VIDEO_RESOLUTION_BUCKETS:
        if v <= bucket:
            return bucket
    return VIDEO_RESOLUTION_BUCKETS[-1]


def _content_ratio(layout, prefer_legacy=False):
    if prefer_legacy and layout.get("char_ratio") is not None:
        value = layout.get("char_ratio")
    else:
        value = layout.get("content_ratio")
        if value is None:
            value = layout.get("char_ratio")
    value = float(value or 0.6)
    return max(0.01, min(value, 1.0))


def _video_expected_resolution(cfg):
    explicit = cfg.get("video_expected_resolution")
    if explicit not in (None, "", "auto"):
        return _bucket_video_resolution(explicit)

    asset_type = str(cfg.get("asset_type", "character") or "character").strip().lower()
    layout = cfg.get("ready_layout", {}) or {}
    target_height = float(cfg.get("target_height", 256) or 256)
    ratio = _content_ratio(layout, prefer_legacy=bool(cfg.get("_prefer_legacy_char_ratio")))
    expected_canvas = target_height / ratio * VIDEO_RESOLUTION_REDUNDANCY
    return _bucket_video_resolution(expected_canvas)


def _video_generation_tier(cfg):
    tier = str(cfg.get("video_generation_tier", "fast") or "fast").strip().lower()
    if tier not in VIDEO_GENERATION_TIERS:
        print(f"⚠️ 未知 video_generation_tier={tier!r},按 fast 处理")
        return "fast"
    return tier


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


def _normalize_asset_type(value):
    asset_type = str(value or "character").strip().lower()
    if asset_type not in ("character", "sequence"):
        print(f"⚠️ 未知 asset_type={value!r},按 character 处理")
        return "character"
    return asset_type


def main():
    ap = argparse.ArgumentParser(description="组装动画提示词 + 分配参考图")
    ap.add_argument("char_dir", help="{work_dir}/{精灵名}(含 _meta.json)")
    ap.add_argument("anims", help="_user_anims.json 路径")
    args = ap.parse_args()

    # 读 config → meta 覆盖(统一优先级)
    cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    meta = json.load(open(os.path.join(args.char_dir, "_meta.json"), encoding="utf-8"))
    prefer_legacy_char_ratio = (
        isinstance(meta.get("ready_layout"), dict) and
        meta["ready_layout"].get("char_ratio") is not None and
        meta["ready_layout"].get("content_ratio") is None
    )
    cfg = _deep_merge(cfg, meta)
    cfg["_prefer_legacy_char_ratio"] = prefer_legacy_char_ratio

    key_color_name = cfg["key_color_name"]
    asset_type = _normalize_asset_type(cfg.get("asset_type", "character"))
    merge_neg = cfg.get("prompt_merge_negative", True)
    default_duration = str(cfg.get("video_duration", "5"))
    video_resolution = _video_expected_resolution(cfg)
    video_tier = _video_generation_tier(cfg)
    anims = json.load(open(args.anims, encoding="utf-8"))

    results = []
    for a in anims:
        aid = a["id"]
        pt = a["play_type"]
        action = a["action"]
        duration = a.get("duration", default_duration)
        user_prompt = (a.get("user_prompt") or "").strip()
        if asset_type == "sequence":
            prompt, negative = build_sequence_prompt(aid, pt, action, key_color_name,
                                                     user_prompt=user_prompt)
        else:
            prompt, negative = build_prompt(aid, pt, action, key_color_name)

        # merge_negative_to_prompt: 融入 prompt 尾部,不单独输出
        if merge_neg and negative:
            prompt = prompt + "\nAvoid: " + negative
            negative = None

        ref_image = "_gen_images/ready.png" if asset_type == "sequence" else _pick_ref_image(aid, args.char_dir)
        entry = {"id": aid, "play_type": pt, "action": action,
                 "prompt": prompt, "ref_image": ref_image, "duration": duration,
                 "asset_type": asset_type,
                 "video_expected_resolution": video_resolution,
                 "video_generation_tier": video_tier}
        if user_prompt:
            entry["user_prompt"] = user_prompt
        if negative:
            entry["negative"] = negative
        results.append(entry)
        print(f"{'='*60}")
        print(f"[{aid}] ({pt}) ref={ref_image} duration={duration} resolution≈{video_resolution}p tier={video_tier}")
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
