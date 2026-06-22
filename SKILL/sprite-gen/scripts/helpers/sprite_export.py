"""
Sprite sheet exporter for 2D game animations.

Pipeline: per-frame tight crop -> scale -> shelf pack -> TexturePacker-style JSON
"""

import argparse
import glob
import json
import math
import os

import numpy as np
from PIL import Image


def _json_scalar(value):
    return value is None or isinstance(value, (str, int, float, bool))


def _format_json(value, level=0, indent=2):
    pad = " " * (level * indent)
    child_pad = " " * ((level + 1) * indent)
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = ["{"]
        items = list(value.items())
        for index, (key, item) in enumerate(items):
            suffix = "," if index < len(items) - 1 else ""
            key_text = json.dumps(str(key), ensure_ascii=False)
            lines.append(
                f"{child_pad}{key_text}: {_format_json(item, level + 1, indent)}{suffix}")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "[]"
        if all(_json_scalar(item) for item in value):
            return json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
        lines = ["["]
        for index, item in enumerate(value):
            suffix = "," if index < len(value) - 1 else ""
            lines.append(f"{child_pad}{_format_json(item, level + 1, indent)}{suffix}")
        lines.append(f"{pad}]")
        return "\n".join(lines)
    return json.dumps(value, ensure_ascii=False)


def write_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(_format_json(data))
        f.write("\n")


def _next_power_of_two(n):
    if n <= 0:
        return 1
    return 1 << (n - 1).bit_length()


def _mask_bbox(mask, padding=0):
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not rows.any() or not cols.any():
        return None

    y0, y1 = np.where(rows)[0][[0, -1]]
    x0, x1 = np.where(cols)[0][[0, -1]]
    h, w = mask.shape
    x0 = max(0, int(x0) - padding)
    y0 = max(0, int(y0) - padding)
    x1 = min(w - 1, int(x1) + padding)
    y1 = min(h - 1, int(y1) + padding)
    return (x0, y0, x1 + 1, y1 + 1)


def _alpha_bbox(img, padding=0):
    alpha = np.asarray(img.convert("RGBA"))[:, :, 3]
    bbox = _mask_bbox(alpha > 0, padding=padding)
    if bbox is None:
        w, h = img.size
        return (0, 0, min(1, w), min(1, h))
    return bbox


def compute_image_bbox(image_path, padding=0, key_color=None, key_tolerance=24):
    """Compute visible bbox for ready/reference images."""
    img = Image.open(image_path).convert("RGBA")
    arr = np.asarray(img)
    alpha = arr[:, :, 3]

    if np.any(alpha < 250):
        mask = alpha > 10
    elif key_color is not None:
        rgb = arr[:, :, :3].astype(np.int16)
        key = np.asarray(key_color, dtype=np.int16)
        mask = np.any(np.abs(rgb - key) > key_tolerance, axis=2)
    else:
        mask = alpha > 10

    bbox = _mask_bbox(mask, padding=padding)
    if bbox is None:
        w, h = img.size
        return (0, 0, w, h)
    return bbox


def compute_ready_pivot_ratio(ready_image_path, key_color=None):
    """Return (x_ratio, y_ratio, content_h_ratio, bbox) from ready bbox bottom-center."""
    if not ready_image_path or not os.path.isfile(ready_image_path):
        return 0.5, 0.5, 1.0, None

    bbox = compute_image_bbox(ready_image_path, padding=0, key_color=key_color)
    with Image.open(ready_image_path) as _ready_img:
        w, h = _ready_img.size
    x_ratio = ((bbox[0] + bbox[2]) / 2.0) / max(1, w)
    y_ratio = bbox[3] / max(1, h)
    content_h_ratio = (bbox[3] - bbox[1]) / max(1, h)
    return x_ratio, y_ratio, content_h_ratio, bbox


def make_pivot_meta(x, y):
    return {
        "space": "sourceSize",
        "unit": "normalized",
        "origin": "top_left",
        "x": round(float(x), 6),
        "y": round(float(y), 6),
    }


def parse_rgb(value):
    if value is None:
        return None
    if isinstance(value, (list, tuple)) and len(value) == 3:
        return tuple(int(v) for v in value)
    parts = str(value).split(",")
    if len(parts) != 3:
        raise ValueError("RGB must be formatted as r,g,b")
    return tuple(int(p.strip()) for p in parts)


def normalize_asset_type(value):
    asset_type = str(value or "character").strip().lower()
    if asset_type not in {"character", "sequence"}:
        raise ValueError("asset_type must be 'character' or 'sequence'")
    return asset_type


def normalize_source_size_mode(value):
    mode = str(value or "canvas").strip().lower()
    if mode not in {"canvas", "bbox-per-anim"}:
        raise ValueError("source_size_mode must be 'canvas' or 'bbox-per-anim'")
    return mode


# 精灵级导出参数,平铺写进每个动画 spritesheet.json 的 meta 顶层(导出溯源)。
SPRITE_EXPORT_META_KEYS = (
    "target_height", "asset_type", "source_size_mode", "max_sheet_size")

# 一致性比对的字段:这几个都是精灵级全局参数,且都会改变每个动画自身的导出结果——
# target_height 决定缩放、source_size_mode 决定 sourceSize/pivot 语义、max_sheet_size
# 决定单动画图集的分页。增量重跑时若某动画用了不同的值,精灵内就不自洽。
# asset_type 不比对:它是精灵级常量(一个精灵非 character 即 sequence),不会逐动画变化。
SPRITE_CONSISTENCY_KEYS = ("target_height", "source_size_mode", "max_sheet_size")


def sprite_export_meta(target_height, asset_type, source_size_mode, max_sheet_size):
    """构造写进每个动画 spritesheet.json meta 顶层的精灵级导出参数。"""
    return {
        "target_height": int(target_height),
        "asset_type": normalize_asset_type(asset_type),
        "source_size_mode": normalize_source_size_mode(source_size_mode),
        "max_sheet_size": int(max_sheet_size),
    }


def _scale_for_frame(frame_size, target_height, asset_type, ready_content_h_ratio):
    frame_w, frame_h = frame_size
    if frame_h <= 0:
        return 1.0
    content_h = frame_h * max(ready_content_h_ratio, 0.0001)
    return target_height / max(content_h, 1.0)


def _resize_image(img, scale):
    w, h = img.size
    out_w = max(1, int(round(w * scale)))
    out_h = max(1, int(round(h * scale)))
    return img.resize((out_w, out_h), Image.LANCZOS)


def _source_region_for_bbox_mode(raw_entries, pivot_ratio):
    left = min(entry["bbox"][0] for entry in raw_entries)
    top = min(entry["bbox"][1] for entry in raw_entries)
    right = max(entry["bbox"][2] for entry in raw_entries)
    bottom = max(entry["bbox"][3] for entry in raw_entries)

    canvas_w, canvas_h = raw_entries[0]["canvas_size"]
    pivot_x, pivot_y = pivot_ratio
    pivot_abs_x = float(pivot_x) * canvas_w
    pivot_abs_y = float(pivot_y) * canvas_h

    # Keep the pivot inside sourceSize so normalized pivot stays valid.
    left = min(left, int(math.floor(pivot_abs_x)))
    top = min(top, int(math.floor(pivot_abs_y)))
    right = max(right, int(math.ceil(pivot_abs_x)))
    bottom = max(bottom, int(math.ceil(pivot_abs_y)))
    if right <= left:
        right = left + 1
    if bottom <= top:
        bottom = top + 1
    return left, top, right, bottom


def _pivot_in_source_region(pivot_ratio, canvas_size, source_region):
    left, top, right, bottom = source_region
    source_w = max(1, right - left)
    source_h = max(1, bottom - top)
    pivot_abs_x = float(pivot_ratio[0]) * canvas_size[0]
    pivot_abs_y = float(pivot_ratio[1]) * canvas_size[1]
    return (
        (pivot_abs_x - left) / source_w,
        (pivot_abs_y - top) / source_h,
    )


def _build_frame_entries(frame_paths, target_height, asset_type,
                         ready_content_h_ratio, padding=2,
                         source_size_mode="canvas", pivot_ratio=(0.5, 0.5)):
    raw_entries = []
    mode = normalize_source_size_mode(source_size_mode)

    for frame_path in frame_paths:
        img = Image.open(frame_path).convert("RGBA")
        frame_w, frame_h = img.size
        scale = _scale_for_frame((frame_w, frame_h), target_height,
                                 asset_type, ready_content_h_ratio)
        scaled_frame = _resize_image(img, scale)
        source_w, source_h = scaled_frame.size
        source_size = (source_w, source_h)

        # Crop after full-frame scaling so spriteSourceSize uses the same
        # sampling grid as sourceSize. Cropping first and scaling the crop can
        # introduce per-frame rounding drift in tight atlases.
        bbox = _alpha_bbox(scaled_frame, padding=padding)
        left, top, right, bottom = bbox
        crop = scaled_frame.crop((left, top, right, bottom))

        raw_entries.append({
            "image": crop,
            "canvas_size": source_size,
            "bbox": bbox,
            "scale": scale,
        })

    entries = []
    source_sizes = set()
    if not raw_entries:
        return entries, source_sizes, pivot_ratio

    if mode == "bbox-per-anim":
        shared_region = _source_region_for_bbox_mode(raw_entries, pivot_ratio)
        pivot_for_source = _pivot_in_source_region(
            pivot_ratio, raw_entries[0]["canvas_size"], shared_region)
    else:
        shared_region = None
        pivot_for_source = pivot_ratio

    for raw in raw_entries:
        left, top, right, bottom = raw["bbox"]
        sprite_w, sprite_h = raw["image"].size
        if shared_region:
            region_left, region_top, region_right, region_bottom = shared_region
            source_size = (region_right - region_left, region_bottom - region_top)
            sprite_x = left - region_left
            sprite_y = top - region_top
        else:
            source_size = raw["canvas_size"]
            sprite_x = left
            sprite_y = top
        source_sizes.add(source_size)
        entries.append({
            "image": raw["image"],
            "source_size": source_size,
            "sprite_source_size": {
                "x": sprite_x,
                "y": sprite_y,
                "w": sprite_w,
                "h": sprite_h,
            },
            "bbox": raw["bbox"],
            "scale": raw["scale"],
        })

    return entries, source_sizes, pivot_for_source


def _split_shelf_pages(entries, max_sheet_size):
    if not entries:
        return []

    pages = []
    current = []
    x = 0
    y = 0
    row_h = 0
    used_w = 0
    used_h = 0

    def finish_page():
        nonlocal current, x, y, row_h, used_w, used_h
        if current:
            pages.append({"entries": current, "used_w": used_w, "used_h": used_h})
        current = []
        x = 0
        y = 0
        row_h = 0
        used_w = 0
        used_h = 0

    for entry in entries:
        fw, fh = entry["image"].size
        if fw > max_sheet_size or fh > max_sheet_size:
            raise ValueError(
                f"frame {fw}x{fh} exceeds max_sheet_size={max_sheet_size}")

        if x > 0 and x + fw > max_sheet_size:
            x = 0
            y += row_h
            row_h = 0

        if y > 0 and y + fh > max_sheet_size:
            finish_page()

        placed = dict(entry)
        placed["atlas_x"] = x
        placed["atlas_y"] = y
        current.append(placed)

        x += fw
        row_h = max(row_h, fh)
        used_w = max(used_w, x)
        used_h = max(used_h, y + fh)

    finish_page()
    return pages


def _pack_named_spritesheet(named_entries, output_dir, animations,
                            max_sheet_size=2048, pivot_meta=None,
                            source_size_mode="canvas", log_label="spritesheet",
                            export_meta=None):
    if not named_entries:
        return None

    os.makedirs(output_dir, exist_ok=True)
    pages = _split_shelf_pages(named_entries, max_sheet_size)
    page_json_names = ["spritesheet.json"] + [
        f"spritesheet-{p}.json" for p in range(1, len(pages))]
    page_img_names = ["spritesheet.png"] + [
        f"spritesheet-{p}.png" for p in range(1, len(pages))]

    for page_index, page in enumerate(pages):
        page_entries = page["entries"]
        sheet_w = min(max_sheet_size, _next_power_of_two(page["used_w"]))
        sheet_h = min(max_sheet_size, _next_power_of_two(page["used_h"]))
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

        frames_meta = {}
        for entry in page_entries:
            frame = entry["image"]
            fw, fh = frame.size
            x = entry["atlas_x"]
            y = entry["atlas_y"]
            # Frames do not overlap in the atlas. Paste RGBA pixels directly;
            # using the frame as its own mask would square soft alpha edges and
            # can shrink tight-cropped frames differently from frame to frame.
            sheet.paste(frame, (x, y))

            ss_w, ss_h = entry["source_size"]
            frames_meta[entry["name"]] = {
                "frame": {"x": x, "y": y, "w": fw, "h": fh},
                "rotated": False,
                "trimmed": True,
                "spriteSourceSize": entry["sprite_source_size"],
                "sourceSize": {"w": ss_w, "h": ss_h},
                "duration": int(round(entry["duration"])),
            }
        img_name = page_img_names[page_index]
        json_name = page_json_names[page_index]
        sheet.save(os.path.join(output_dir, img_name), "PNG")

        meta = {
            "image": img_name,
            "format": "RGBA8888",
            "size": {"w": sheet_w, "h": sheet_h},
            "scale": "1",
        }
        if page_index == 0:
            meta.update({
                "app": "sprite-gen",
                "version": "1.0",
                "source_size_mode": source_size_mode,
            })
            # 精灵级导出参数平铺到 meta 顶层,随每个动画持久化,供后续增量重跑
            # 比对一致性(见 video_to_sprites.check_sprite_consistency)。
            if export_meta:
                meta.update(export_meta)
            if len(page_json_names) > 1:
                meta["relatedMultiPacks"] = page_json_names[1:]
            if pivot_meta:
                meta["pivot"] = pivot_meta

        json_data = {"meta": meta, "frames": frames_meta}
        if page_index == 0:
            json_data["animations"] = animations
        write_json(os.path.join(output_dir, json_name), json_data)

        print(f"  {img_name}: {sheet_w}x{sheet_h}, {len(page_entries)} frames")

    source_sizes = {entry["source_size"] for entry in named_entries}
    source_summary = ", ".join(f"{w}x{h}" for w, h in sorted(source_sizes))
    print(f"  {log_label}: {len(named_entries)} frames, {len(pages)} page(s), "
          f"sourceSize {source_summary}")
    return {
        "frame_count": len(named_entries),
        "pages": len(pages),
        "source_sizes": sorted(source_sizes),
    }


def _strip_common_animation_pivots(animations, common_pivot):
    if not common_pivot:
        return animations
    stripped = []
    for animation in animations:
        item = dict(animation)
        if item.get("pivot") == common_pivot:
            item.pop("pivot", None)
        stripped.append(item)
    return stripped


def pack_spritesheet(frame_entries, output_dir, anim_id, fps=24, play_type="loop",
                     frame_durations=None, max_sheet_size=2048, pivot_meta=None,
                     source_size_mode="canvas", export_meta=None):
    """Pack variable-size frames in order using a deterministic shelf packer."""
    if not frame_entries:
        return None

    named_entries = []
    for index, entry in enumerate(frame_entries):
        named = dict(entry)
        named["name"] = f"{anim_id}_{index + 1:04d}"
        named["duration"] = (
            int(round(frame_durations[index]))
            if frame_durations and index < len(frame_durations)
            else int(round(1000 / max(1, fps)))
        )
        named_entries.append(named)

    animations = [{
        "name": anim_id,
        "frames": [entry["name"] for entry in named_entries],
        "direction": "forward",
        "repeat": -1 if play_type == "loop" else 1,
        "fps": fps,
    }]
    result = _pack_named_spritesheet(
        named_entries,
        output_dir,
        animations,
        max_sheet_size=max_sheet_size,
        pivot_meta=pivot_meta,
        source_size_mode=source_size_mode,
        log_label=anim_id,
        export_meta=export_meta,
    )
    if result:
        result["fps"] = fps
        result["play_type"] = play_type
    return result


def clear_merged_spritesheet(output_dir):
    for pattern in ("spritesheet*.json", "spritesheet*.png"):
        for path in glob.glob(os.path.join(output_dir, pattern)):
            if os.path.isfile(path):
                os.remove(path)


def _load_exported_animation(anim_dir, anim_id):
    entry_json = os.path.join(anim_dir, "spritesheet.json")
    if not os.path.isfile(entry_json):
        return None

    with open(entry_json, encoding="utf-8") as f:
        entry_data = json.load(f)

    page_jsons = [entry_json]
    for related in entry_data.get("meta", {}).get("relatedMultiPacks", []):
        page_jsons.append(os.path.join(anim_dir, related))

    entries_by_name = {}
    for page_json in page_jsons:
        if not os.path.isfile(page_json):
            continue
        with open(page_json, encoding="utf-8") as f:
            page_data = json.load(f)
        image_name = page_data.get("meta", {}).get("image")
        if not image_name:
            continue
        image_path = os.path.join(anim_dir, image_name)
        if not os.path.isfile(image_path):
            continue
        sheet = Image.open(image_path).convert("RGBA")
        for frame_name, frame_meta in page_data.get("frames", {}).items():
            rect = frame_meta["frame"]
            sprite_rect = frame_meta["spriteSourceSize"]
            source_size = frame_meta["sourceSize"]
            frame_img = sheet.crop((
                int(rect["x"]), int(rect["y"]),
                int(rect["x"] + rect["w"]), int(rect["y"] + rect["h"]),
            ))
            entries_by_name[frame_name] = {
                "name": frame_name,
                "image": frame_img,
                "source_size": (int(source_size["w"]), int(source_size["h"])),
                "sprite_source_size": {
                    "x": int(sprite_rect["x"]),
                    "y": int(sprite_rect["y"]),
                    "w": int(sprite_rect["w"]),
                    "h": int(sprite_rect["h"]),
                },
                "duration": int(frame_meta.get("duration", 42)),
            }

    animations = entry_data.get("animations") or []
    if not animations:
        return None
    animation = dict(animations[0])
    frame_names = animation.get("frames") or []
    missing = [name for name in frame_names if name not in entries_by_name]
    if missing:
        raise ValueError(
            f"{entry_json}: animations[0].frames references missing frame key(s): "
            f"{', '.join(missing)}")
    entries = [entries_by_name[name] for name in frame_names]
    if not entries:
        return None

    meta = entry_data.get("meta", {})
    animation.setdefault("name", anim_id)
    animation.setdefault("direction", "forward")
    animation["frames"] = [entry["name"] for entry in entries]
    pivot_meta = animation.get("pivot") or meta.get("pivot")
    return entries, animation, pivot_meta


def export_merged_spritesheet_from_exports(output_dir, max_sheet_size=2048,
                                           source_size_mode="canvas"):
    """Regenerate root merged spritesheet from per-animation exported sheets."""
    named_entries = []
    animations = []
    tag_pivots = []
    source_sizes = set()
    animation_count = 0

    if not os.path.isdir(output_dir):
        return None

    for anim_id in sorted(os.listdir(output_dir)):
        anim_dir = os.path.join(output_dir, anim_id)
        if not os.path.isdir(anim_dir):
            continue
        loaded = _load_exported_animation(anim_dir, anim_id)
        if not loaded:
            continue
        entries, source_animation, pivot_meta = loaded
        named_entries.extend(entries)
        for entry in entries:
            source_sizes.add(entry["source_size"])

        animation = {
            key: value for key, value in source_animation.items()
            if key not in {"frames", "pivot"}
        }
        animation.setdefault("name", anim_id)
        animation.setdefault("direction", "forward")
        animation["frames"] = [entry["name"] for entry in entries]
        if pivot_meta:
            animation["pivot"] = pivot_meta
        animations.append(animation)
        tag_pivots.append(pivot_meta)
        animation_count += 1

    clear_merged_spritesheet(output_dir)
    if not named_entries:
        print(f"No exported animation sheets to merge in {output_dir}")
        return None

    pivot_values = [pivot for pivot in tag_pivots if pivot]
    common_pivot = (
        pivot_values[0]
        if pivot_values and len(pivot_values) == len(tag_pivots)
        and all(pivot == pivot_values[0] for pivot in pivot_values)
        else None
    )
    result = _pack_named_spritesheet(
        named_entries,
        output_dir,
        _strip_common_animation_pivots(animations, common_pivot),
        max_sheet_size=max_sheet_size,
        pivot_meta=common_pivot,
        source_size_mode=normalize_source_size_mode(source_size_mode),
        log_label="merged",
    )
    if result:
        result["animations"] = animation_count
        result["source_sizes"] = sorted(source_sizes)
    return result


def write_sprite_manifest(output_dir, entry_sheets=None):
    """Write sprite.json as a virtual TexturePacker-style entry sheet."""
    related = list(entry_sheets or [])
    if entry_sheets is None and os.path.isdir(output_dir):
        for name in sorted(os.listdir(output_dir)):
            sheet_path = os.path.join(output_dir, name, "spritesheet.json")
            if os.path.isfile(sheet_path):
                related.append(f"{name}/spritesheet.json")

    data = {
        "meta": {
            "app": "sprite-gen",
            "version": "1.0",
            "relatedMultiPacks": related,
        },
    }
    out_path = os.path.join(output_dir, "sprite.json")
    os.makedirs(output_dir, exist_ok=True)
    write_json(out_path, data)
    return out_path


def export_animation(frames_dir, output_dir, anim_id, target_height=128,
                     padding=2, fps=24, play_type="loop",
                     asset_type="sequence", ready_image_path=None, key_color=None,
                     max_sheet_size=2048, source_size_mode="canvas"):
    frame_paths = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not frame_paths:
        print(f"No frame_*.png in {frames_dir}")
        return None

    asset_type = normalize_asset_type(asset_type)
    ready_px, ready_py, ready_ratio, _ = compute_ready_pivot_ratio(
        ready_image_path, key_color=key_color)
    if asset_type == "character":
        px, py = ready_px, ready_py
    else:
        px, py = 0.5, 0.5

    entries, _, pivot_for_source = _build_frame_entries(
        frame_paths, target_height, asset_type, ready_ratio, padding=padding,
        source_size_mode=source_size_mode, pivot_ratio=(px, py))
    anim_export_dir = os.path.join(output_dir, anim_id)
    return pack_spritesheet(
        entries, anim_export_dir, anim_id,
        fps=fps, play_type=play_type,
        max_sheet_size=max_sheet_size,
        pivot_meta=make_pivot_meta(*pivot_for_source),
        source_size_mode=normalize_source_size_mode(source_size_mode),
        export_meta=sprite_export_meta(target_height, asset_type,
                                       source_size_mode, max_sheet_size),
    )


def export_character(char_anim_dir, output_dir, target_height=256, padding=2,
                     anim_configs=None, max_sheet_size=2048,
                     ready_image_path=None, key_color=None,
                     asset_type="character", source_size_mode="canvas"):
    """Export animation subdirs as independent atlases with common atlas semantics."""
    asset_type = normalize_asset_type(asset_type)
    source_size_mode = normalize_source_size_mode(source_size_mode)
    anim_dirs = []
    for name in sorted(os.listdir(char_anim_dir)):
        sub = os.path.join(char_anim_dir, name)
        if not os.path.isdir(sub):
            continue
        frames = sorted(glob.glob(os.path.join(sub, "frame_*.png")))
        if frames:
            anim_dirs.append((name, sub, frames))

    if not anim_dirs:
        print(f"No animation subdirs with frame_*.png in {char_anim_dir}")
        return

    configs = anim_configs or {}
    ready_pivot_x, ready_pivot_y, ready_content_ratio, ready_bbox = compute_ready_pivot_ratio(
        ready_image_path, key_color=key_color)
    if asset_type == "character":
        pivot_x, pivot_y = ready_pivot_x, ready_pivot_y
        if ready_bbox:
            print(f"Pivot: ready bbox bottom-center ratio=({pivot_x:.4f}, {pivot_y:.4f})")
        else:
            print("Pivot: fallback ratio=(0.5000, 0.5000)")
    else:
        pivot_x, pivot_y = 0.5, 0.5
        print(f"Pivot: sequence default center ratio=(0.5000, 0.5000), "
              f"ready content height ratio={ready_content_ratio:.4f}")

    print(f"Exporting {len(anim_dirs)} animations "
          f"(asset_type={asset_type}, target_height={target_height}, "
          f"source_size_mode={source_size_mode})")
    export_meta = sprite_export_meta(target_height, asset_type,
                                     source_size_mode, max_sheet_size)
    results = {}
    all_source_sizes = set()
    for name, sub, frames in anim_dirs:
        cfg = configs.get(name, {})
        fps = cfg.get("fps", 24)
        play_type = cfg.get("play_type", "loop")
        frame_durations = cfg.get("frame_durations")

        entries, source_sizes, pivot_for_source = _build_frame_entries(
            frames, target_height, asset_type, ready_content_ratio,
            padding=padding,
            source_size_mode=source_size_mode,
            pivot_ratio=(pivot_x, pivot_y))
        all_source_sizes.update(source_sizes)
        if len(source_sizes) > 1:
            print(f"  WARNING {name}: source frame sizes differ after scaling: "
                  f"{sorted(source_sizes)}")

        print(f"\n  {name}: {len(frames)} frames, "
              f"{len(source_sizes)} sourceSize value(s)")
        anim_export_dir = os.path.join(output_dir, name)
        result = pack_spritesheet(
            entries, anim_export_dir, name,
            fps=fps, play_type=play_type,
            frame_durations=frame_durations,
            max_sheet_size=max_sheet_size,
            pivot_meta=make_pivot_meta(*pivot_for_source),
            source_size_mode=source_size_mode,
            export_meta=export_meta,
        )
        if result:
            results[name] = result

    if len(all_source_sizes) > 1:
        print(f"\nWARNING: sourceSize differs across exported animations: "
              f"{sorted(all_source_sizes)}")
    print(f"\n{'=' * 60}")
    print(f"Atlas export done. {len(results)} animations.")
    return results


def export_merged_character(char_anim_dir, output_dir, target_height=256, padding=2,
                            anim_configs=None, max_sheet_size=2048,
                            ready_image_path=None, key_color=None,
                            asset_type="character", source_size_mode="canvas"):
    """Export all animation subdirs into one root spritesheet entry."""
    asset_type = normalize_asset_type(asset_type)
    source_size_mode = normalize_source_size_mode(source_size_mode)
    configs = anim_configs or {}

    ready_pivot_x, ready_pivot_y, ready_content_ratio, ready_bbox = compute_ready_pivot_ratio(
        ready_image_path, key_color=key_color)
    if asset_type == "character":
        pivot_x, pivot_y = ready_pivot_x, ready_pivot_y
    else:
        pivot_x, pivot_y = 0.5, 0.5

    named_entries = []
    animations = []
    tag_pivots = []
    source_sizes = set()
    anim_count = 0
    for name in sorted(os.listdir(char_anim_dir)):
        sub = os.path.join(char_anim_dir, name)
        if not os.path.isdir(sub):
            continue
        frames = sorted(glob.glob(os.path.join(sub, "frame_*.png")))
        if not frames:
            continue

        cfg = configs.get(name, {})
        fps = cfg.get("fps", 24)
        play_type = cfg.get("play_type", "loop")
        frame_durations = cfg.get("frame_durations")
        entries, anim_source_sizes, pivot_for_source = _build_frame_entries(
            frames, target_height, asset_type, ready_content_ratio,
            padding=padding,
            source_size_mode=source_size_mode,
            pivot_ratio=(pivot_x, pivot_y))
        if not entries:
            continue

        anim_frame_names = []
        for index, entry in enumerate(entries):
            named = dict(entry)
            named["name"] = f"{name}_{index + 1:04d}"
            named["duration"] = (
                int(round(frame_durations[index]))
                if frame_durations and index < len(frame_durations)
                else int(round(1000 / max(1, fps)))
            )
            named_entries.append(named)
            anim_frame_names.append(named["name"])
        pivot_meta = make_pivot_meta(*pivot_for_source)
        animation = {
            "name": name,
            "frames": anim_frame_names,
            "direction": "forward",
            "repeat": -1 if play_type == "loop" else 1,
            "fps": fps,
            "pivot": pivot_meta,
        }
        animations.append(animation)
        tag_pivots.append(pivot_meta)
        source_sizes.update(anim_source_sizes)
        anim_count += 1

    clear_merged_spritesheet(output_dir)
    if not named_entries:
        print(f"No animation frames to merge in {char_anim_dir}")
        return None

    common_pivot = tag_pivots[0] if all(p == tag_pivots[0] for p in tag_pivots) else None
    result = _pack_named_spritesheet(
        named_entries,
        output_dir,
        _strip_common_animation_pivots(animations, common_pivot),
        max_sheet_size=max_sheet_size,
        pivot_meta=common_pivot,
        source_size_mode=source_size_mode,
        log_label="merged",
    )
    if result:
        result["animations"] = anim_count
        result["source_sizes"] = sorted(source_sizes)
    return result


def main():
    parser = argparse.ArgumentParser(description="Export animation as sprite sheet")
    parser.add_argument("frames_dir", help="Directory of frame_XXXX.png files, "
                        "or animation root dir with --character")
    parser.add_argument("--character", action="store_true",
                        help="Export all animation subdirs independently")
    parser.add_argument("--asset-type", default="character",
                        choices=["character", "sequence"])
    parser.add_argument("--target-height", type=int, default=128)
    parser.add_argument("--padding", type=int, default=2)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--play-type", default="loop", choices=["loop", "once"])
    parser.add_argument("--max-sheet-size", type=int, default=2048)
    parser.add_argument("--source-size-mode", default="canvas",
                        choices=["canvas", "bbox-per-anim"])
    parser.add_argument("--ready-image", default=None,
                        help="ready.png used to derive pivot for character assets")
    parser.add_argument("--key-color", default=None,
                        help="Backdrop RGB for ready.png, formatted as r,g,b")
    parser.add_argument("--output-dir", default=None,
                        help="Export directory (default: {parent}/_export)")
    parser.add_argument("--anim-id", default=None,
                        help="Animation ID (default: directory name)")
    parser.add_argument("--anim-config", default=None,
                        help="JSON with per-animation overrides")
    args = parser.parse_args()

    if args.character:
        anim_configs = None
        if args.anim_config:
            with open(args.anim_config, encoding="utf-8") as f:
                anim_configs = json.load(f)
        char_dir = args.frames_dir.rstrip("/\\")
        output_dir = args.output_dir or os.path.join(os.path.dirname(char_dir), "_export")
        export_character(
            char_dir, output_dir,
            target_height=args.target_height,
            padding=args.padding,
            anim_configs=anim_configs,
            max_sheet_size=args.max_sheet_size,
            ready_image_path=args.ready_image,
            key_color=parse_rgb(args.key_color),
            asset_type=args.asset_type,
            source_size_mode=args.source_size_mode,
        )
    else:
        anim_id = args.anim_id or os.path.basename(args.frames_dir.rstrip("/\\"))
        parent = os.path.dirname(args.frames_dir.rstrip("/\\"))
        output_dir = args.output_dir or os.path.join(parent, "_export")
        result = export_animation(
            args.frames_dir, output_dir, anim_id,
            target_height=args.target_height,
            padding=args.padding,
            fps=args.fps,
            play_type=args.play_type,
            asset_type=args.asset_type,
            ready_image_path=args.ready_image,
            key_color=parse_rgb(args.key_color),
            max_sheet_size=args.max_sheet_size,
            source_size_mode=args.source_size_mode,
        )
        if result:
            print(f"\nDone! Output: {os.path.join(output_dir, anim_id)}")


if __name__ == "__main__":
    main()
