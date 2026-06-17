"""
Sprite sheet exporter for 2D game animations.

Pipeline:  tight crop → scale → sprite sheet pack → TexturePacker JSON

Usage:
  python3 tools/sprite_export.py <frames_dir> [--target-height 128] [--padding 2]
"""

import os, sys, glob, argparse, json, math
import numpy as np
from PIL import Image


def _next_power_of_two(n):
    if n <= 0:
        return 1
    return 1 << (n - 1).bit_length()


def compute_union_bbox(frame_paths, padding=2):
    """
    Compute the union bounding box across all frames.
    Returns (left, top, right, bottom) in pixel coordinates.
    """
    min_x, min_y = float('inf'), float('inf')
    max_x, max_y = 0, 0

    for fp in frame_paths:
        img = Image.open(fp).convert("RGBA")
        alpha = np.array(img)[:, :, 3]
        rows = np.any(alpha > 0, axis=1)
        cols = np.any(alpha > 0, axis=0)
        if not rows.any():
            continue
        y0, y1 = np.where(rows)[0][[0, -1]]
        x0, x1 = np.where(cols)[0][[0, -1]]
        min_x = min(min_x, x0)
        min_y = min(min_y, y0)
        max_x = max(max_x, x1)
        max_y = max(max_y, y1)

    if min_x == float('inf'):
        w, h = Image.open(frame_paths[0]).size
        return (0, 0, w, h)

    min_x = max(0, min_x - padding)
    min_y = max(0, min_y - padding)
    max_x = max_x + padding
    max_y = max_y + padding

    return (min_x, min_y, max_x + 1, max_y + 1)


def tight_crop_frames(frame_paths, bbox):
    """Crop all frames to the given bounding box. Returns list of PIL Images."""
    left, top, right, bottom = bbox
    cropped = []
    for fp in frame_paths:
        img = Image.open(fp).convert("RGBA")
        w, h = img.size
        r = min(right, w)
        b = min(bottom, h)
        crop = img.crop((left, top, r, b))
        cropped.append(crop)
    return cropped


def scale_frames(frames, target_height):
    """Scale frames so character height = target_height, preserving aspect ratio."""
    if not frames:
        return []

    src_w, src_h = frames[0].size
    ratio = target_height / src_h
    new_w = max(1, round(src_w * ratio))
    new_h = target_height

    scaled = []
    for f in frames:
        s = f.resize((new_w, new_h), Image.LANCZOS)
        scaled.append(s)
    return scaled


def pack_spritesheet(scaled_frames, output_dir, anim_id, fps=24, play_type="loop",
                     source_size=None, sss_offsets=None, frame_durations=None,
                     max_sheet_size=2048):
    """
    Pack frames into a single-row horizontal sprite sheet PNG + TexturePacker JSON.

    source_size:  (W, H) — the character-level unified canvas size.
                  When set, written as sourceSize so the game engine can keep
                  all animations at consistent scale.
    sss_offsets:  list of (ox, oy) per frame — where each tight-cropped frame
                  sits inside the unified canvas.  Written as spriteSourceSize.
    frame_durations: optional list of per-frame display durations in ms
                  (Aseprite-style). Lets keyframe-reduced anims keep the original
                  rhythm even though keyframes are non-uniformly spaced. When None,
                  each frame falls back to int(1000/fps). meta.frameTags[].fps is
                  always kept as a uniform-speed fallback for simple players.
    """
    if not scaled_frames:
        return

    os.makedirs(output_dir, exist_ok=True)
    fw, fh = scaled_frames[0].size
    n = len(scaled_frames)

    MAX = max_sheet_size
    cols = max(1, min(n, MAX // max(1, fw)))
    rows_per_page = max(1, MAX // max(1, fh))
    per_page = max(1, cols * rows_per_page)
    n_pages = (n + per_page - 1) // per_page

    ss = {"w": source_size[0], "h": source_size[1]} if source_size else {"w": fw, "h": fh}

    # 多页输出:每页独立 JSON+PNG(TexturePacker multipack 标准)
    # 页间通过 meta.relatedMultiPacks 关联
    page_json_names = ["spritesheet.json"] + [f"spritesheet-{p}.json" for p in range(1, n_pages)]
    page_img_names = ["spritesheet.png"] + [f"spritesheet-{p}.png" for p in range(1, n_pages)]

    for p in range(n_pages):
        page_frames = scaled_frames[p * per_page:(p + 1) * per_page]
        pn = len(page_frames)
        pcols = max(1, min(pn, cols))
        prows = (pn + pcols - 1) // pcols
        sheet_w = min(MAX, _next_power_of_two(pcols * fw))
        sheet_h = min(MAX, _next_power_of_two(prows * fh))
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

        frames_meta = {}
        for li, frame in enumerate(page_frames):
            gi = p * per_page + li
            x = (li % pcols) * fw
            y = (li // pcols) * fh
            sheet.paste(frame, (x, y), frame)
            ox, oy = (sss_offsets[gi] if sss_offsets and gi < len(sss_offsets) else (0, 0))
            dur = (int(round(frame_durations[gi])) if frame_durations and gi < len(frame_durations)
                   else int(round(1000 / fps)))
            frames_meta[f"{anim_id}_{gi + 1:04d}"] = {
                "frame": {"x": x, "y": y, "w": fw, "h": fh},
                "rotated": False, "trimmed": True,
                "spriteSourceSize": {"x": ox, "y": oy, "w": fw, "h": fh},
                "sourceSize": ss, "duration": dur,
            }

        img_name = page_img_names[p]
        json_name = page_json_names[p]
        sheet.save(os.path.join(output_dir, img_name), "PNG")

        # relatedMultiPacks: 关联其他页的 JSON(不含自己)
        related = [j for j in page_json_names if j != json_name]

        json_data = {
            "frames": frames_meta,
            "meta": {
                "app": "sprite-gen",
                "version": "1.0",
                "image": img_name,
                "format": "RGBA8888",
                "size": {"w": sheet_w, "h": sheet_h},
                "scale": "1",
                "frameTags": [{
                    "name": anim_id,
                    "from": p * per_page,
                    "to": p * per_page + pn - 1,
                    "direction": "forward",
                    "repeat": -1 if play_type == "loop" else 1,
                    "fps": fps,
                }],
                "relatedMultiPacks": related if related else None,
            },
        }
        # 单页时不输出 relatedMultiPacks
        if not related:
            del json_data["meta"]["relatedMultiPacks"]

        with open(os.path.join(output_dir, json_name), "w", encoding="utf-8") as f:
            json.dump(json_data, f, indent=2, ensure_ascii=False)

        print(f"  {img_name}: {sheet_w}x{sheet_h}, {pn} frames ({pcols}x{prows} grid, {fw}x{fh}/frame)")

    print(f"  {anim_id}: {n} frames, {n_pages} page(s), {fps}fps, {play_type}, sourceSize {ss['w']}x{ss['h']}")
    return {
        "frame_size": (fw, fh),
        "frame_count": n,
        "pages": n_pages,
    }


def export_animation(frames_dir, output_dir, anim_id,
                     target_height=128, padding=2, fps=24, play_type="loop"):
    """Full pipeline: tight crop → scale → sprite sheet."""
    frame_paths = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not frame_paths:
        print(f"No frame_*.png in {frames_dir}")
        return None

    print(f"\nExporting {anim_id} ({len(frame_paths)} frames)")

    print("  Computing union bbox...")
    bbox = compute_union_bbox(frame_paths, padding=padding)
    crop_w = bbox[2] - bbox[0]
    crop_h = bbox[3] - bbox[1]
    print(f"  Union bbox: {bbox} → {crop_w}x{crop_h}")

    print("  Tight cropping...")
    cropped = tight_crop_frames(frame_paths, bbox)

    print(f"  Scaling to height={target_height}px...")
    scaled = scale_frames(cropped, target_height=target_height)
    sw, sh = scaled[0].size
    print(f"  Scaled frame size: {sw}x{sh}")

    print("  Packing sprite sheet...")
    anim_export_dir = os.path.join(output_dir, anim_id)
    result = pack_spritesheet(scaled, anim_export_dir, anim_id, fps=fps, play_type=play_type)

    return result


def export_character(char_anim_dir, output_dir, target_height=256, padding=2,
                     anim_configs=None):
    """
    Two-pass character-level export with TexturePacker-standard metadata.

    Pass 1 — scan every animation's per-anim bbox, scale to target_height,
             record scaled (w, h).  Compute unified sourceSize =
             (max_w, max_h) across all animations.
    Pass 2 — for each animation, tight-crop + scale as before (compact PNG),
             but compute each frame's offset within the unified canvas and
             write correct sourceSize / spriteSourceSize in JSON.

    Result: every spritesheet has the same sourceSize.  The game engine
    renders into that virtual canvas using the offset, so a crouching bird
    naturally appears smaller than a standing one.  PNG stays compact.
    """
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

    # ── Pass 1: collect per-anim bbox → find global scale ratio ─────
    print(f"Pass 1: scanning {len(anim_dirs)} animations...")
    anim_info = {}
    max_crop_h = 0
    for name, sub, frames in anim_dirs:
        bbox = compute_union_bbox(frames, padding=padding)
        crop_w = bbox[2] - bbox[0]
        crop_h = bbox[3] - bbox[1]
        anim_info[name] = {"bbox": bbox, "crop_w": crop_w, "crop_h": crop_h}
        max_crop_h = max(max_crop_h, crop_h)
        print(f"  {name}: bbox {crop_w}x{crop_h}")

    # Single global ratio: tallest animation fills target_height exactly.
    # Shorter animations stay proportionally shorter.
    global_ratio = target_height / max_crop_h
    print(f"\nTallest crop: {max_crop_h}px → global ratio: {global_ratio:.4f}")

    max_sw, max_sh = 0, 0
    for name, info in anim_info.items():
        sw = max(1, round(info["crop_w"] * global_ratio))
        sh = max(1, round(info["crop_h"] * global_ratio))
        info["scaled_w"] = sw
        info["scaled_h"] = sh
        max_sw = max(max_sw, sw)
        max_sh = max(max_sh, sh)
        print(f"  {name}: scaled {sw}x{sh}")

    unified_w, unified_h = max_sw, max_sh
    print(f"\nUnified sourceSize: {unified_w}x{unified_h}")

    # ── Pass 2: export each animation with offset metadata ──────────
    print(f"\nPass 2: exporting with offsets...")
    results = {}
    for name, sub, frames in anim_dirs:
        cfg = configs.get(name, {})
        fps = cfg.get("fps", 24)
        play_type = cfg.get("play_type", "loop")
        frame_durations = cfg.get("frame_durations")  # optional per-frame ms
        info = anim_info[name]
        fw, fh = info["scaled_w"], info["scaled_h"]

        ox = (unified_w - fw) // 2
        oy = unified_h - fh

        print(f"\n  {name}: {len(frames)}f, {fw}x{fh}, offset=({ox},{oy})")

        cropped = tight_crop_frames(frames, info["bbox"])
        scaled = scale_frames(cropped, target_height=fh)

        offsets = [(ox, oy)] * len(scaled)

        anim_export_dir = os.path.join(output_dir, name)
        result = pack_spritesheet(
            scaled, anim_export_dir, name,
            fps=fps, play_type=play_type,
            source_size=(unified_w, unified_h),
            sss_offsets=offsets,
            frame_durations=frame_durations,
        )
        if result:
            results[name] = result

    print(f"\n{'='*60}")
    print(f"Character export done. {len(results)} animations.")
    print(f"Unified sourceSize: {unified_w}x{unified_h}")
    return results


def main():
    parser = argparse.ArgumentParser(description="Export animation as sprite sheet")
    parser.add_argument("frames_dir", help="Directory of frame_XXXX.png files, "
                        "or character animation dir (with --character)")
    parser.add_argument("--character", action="store_true",
                        help="Character-level export: scans all animation subdirs, "
                        "computes unified sourceSize, writes correct offsets.")
    parser.add_argument("--target-height", type=int, default=128)
    parser.add_argument("--padding", type=int, default=2)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--play-type", default="loop", choices=["loop", "once"])
    parser.add_argument("--output-dir", default=None,
                        help="Export directory (default: {parent}/_export)")
    parser.add_argument("--anim-id", default=None,
                        help="Animation ID (default: directory name)")
    parser.add_argument("--anim-config", default=None,
                        help="JSON with per-animation overrides: "
                        '{"dash_key": {"fps": 4, "play_type": "once"}, ...}')
    args = parser.parse_args()

    if args.character:
        anim_configs = None
        if args.anim_config:
            with open(args.anim_config, encoding="utf-8") as f:
                anim_configs = json.load(f)
        char_dir = args.frames_dir.rstrip("/")
        output_dir = args.output_dir or os.path.join(
            os.path.dirname(char_dir), "导出")
        export_character(char_dir, output_dir,
                         target_height=args.target_height,
                         padding=args.padding,
                         anim_configs=anim_configs)
    else:
        anim_id = args.anim_id or os.path.basename(args.frames_dir.rstrip("/"))
        parent = os.path.dirname(args.frames_dir.rstrip("/"))
        output_dir = args.output_dir or os.path.join(parent, "_export")
        result = export_animation(
            args.frames_dir, output_dir, anim_id,
            target_height=args.target_height,
            padding=args.padding,
            fps=args.fps,
            play_type=args.play_type,
        )
        if result:
            print(f"\nDone! Output: {os.path.join(output_dir, anim_id)}/")


if __name__ == "__main__":
    main()
