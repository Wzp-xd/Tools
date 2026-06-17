"""
Keyframe extraction for 2D game sprite animations.

Algorithm: motion accumulation + pose extrema detection + complexity-adaptive frame count.

Steps:
  1. Compute per-frame optical flow magnitude and direction signals.
  2. Estimate motion complexity → determine target keyframe count.
  3. Detect pose extrema (direction reversals) → force-keep these frames.
  4. Fill remaining quota via cumulative motion thresholding.
  5. Merge, enforce first-frame inclusion, clamp to target range.

Usage:
  python3 tools/keyframe_extract.py <frames_dir> [--target-min N] [--target-max N]
"""

import os, sys, glob, argparse, json
import numpy as np
import cv2
from PIL import Image


# ── Complexity estimation ─────────────────────────────────────────

def compute_motion_signals(grays):
    """Return per-frame optical flow magnitude and direction change arrays."""
    magnitudes = []
    directions = []
    for i in range(1, len(grays)):
        flow = cv2.calcOpticalFlowFarneback(
            grays[i - 1], grays[i], None,
            pyr_scale=0.5, levels=3, winsize=15,
            iterations=3, poly_n=5, poly_sigma=1.2, flags=0)
        mag = np.sqrt(flow[..., 0] ** 2 + flow[..., 1] ** 2)
        magnitudes.append(mag.mean())
        ang = np.arctan2(flow[..., 1], flow[..., 0])
        directions.append(np.mean(ang))
    return np.array(magnitudes), np.array(directions)


def estimate_complexity(magnitudes, directions):
    """
    Classify animation complexity based on motion statistics.

    Returns (level, suggested_min, suggested_max):
      "simple"  → 6-8   (idle, breathe)
      "medium"  → 10-14 (run, walk)
      "complex" → 14-20 (attack, multi-hit combo)
    """
    if len(magnitudes) < 3:
        return "simple", 4, 6

    cv = np.std(magnitudes) / (np.mean(magnitudes) + 1e-6)
    dir_changes = 0
    for i in range(1, len(directions)):
        delta = abs(directions[i] - directions[i - 1])
        if delta > np.pi:
            delta = 2 * np.pi - delta
        if delta > 0.5:
            dir_changes += 1

    dir_change_rate = dir_changes / len(directions)

    if cv < 0.4 and dir_change_rate < 0.15:
        return "simple", 6, 8
    elif cv > 0.8 or dir_change_rate > 0.35:
        return "complex", 14, 20
    else:
        return "medium", 10, 14


# ── Pose extrema detection ────────────────────────────────────────

def detect_pose_extrema(magnitudes, min_distance=3):
    """
    Detect frames where motion direction reverses (pose turning points).
    These are the "key poses": highest leg lift, widest wing spread, etc.
    Returns frame indices (in the original 0-based indexing).
    """
    if len(magnitudes) < 5:
        return []

    smoothed = np.convolve(magnitudes, np.ones(3) / 3, mode='same')
    extrema = []
    for i in range(2, len(smoothed) - 2):
        is_max = smoothed[i] >= smoothed[i-1] and smoothed[i] >= smoothed[i+1]
        is_min = smoothed[i] <= smoothed[i-1] and smoothed[i] <= smoothed[i+1]
        if is_max or is_min:
            if not extrema or (i - extrema[-1]) >= min_distance:
                extrema.append(i)
    # Shift by +1 because magnitudes[i] corresponds to transition from frame i to i+1,
    # so the extrema index maps to frame index i+1
    return [e + 1 for e in extrema if e + 1 < len(magnitudes) + 1]


# ── Cumulative motion thresholding ────────────────────────────────

def cumulative_motion_select(magnitudes, target_count, already_selected):
    """
    Select frames by accumulating motion magnitude until a threshold is exceeded.
    Adaptively adjusts the threshold so the final count ≈ target_count.
    """
    total_motion = np.sum(magnitudes)
    remaining = target_count - len(already_selected)
    if remaining <= 0:
        return []

    threshold = total_motion / (remaining + 1)

    selected = []
    accumulated = 0.0
    for i in range(len(magnitudes)):
        frame_idx = i + 1  # frame 0 is always included; motion[0] is frame0→frame1
        if frame_idx in already_selected:
            accumulated = 0.0
            continue
        accumulated += magnitudes[i]
        if accumulated >= threshold:
            selected.append(frame_idx)
            accumulated = 0.0

    return selected


# ── Main extraction ───────────────────────────────────────────────

def extract_keyframes(frame_paths, target_min=None, target_max=None):
    """
    Extract keyframe indices from a sequence of animation frames.

    Args:
        frame_paths: list of PNG file paths (full frames, can be transparent or white-bg)
        target_min: override minimum keyframe count (None = auto from complexity)
        target_max: override maximum keyframe count (None = auto from complexity)

    Returns:
        dict with keys:
          indices: list[int] - 0-based keyframe indices into frame_paths
          complexity: str
          target_range: [min, max]
          extrema_count: int
          method: str
    """
    grays = []
    for p in frame_paths:
        img = cv2.imread(p, cv2.IMREAD_UNCHANGED)
        if img is None:
            continue
        if len(img.shape) == 3 and img.shape[2] == 4:
            gray = cv2.cvtColor(img[:, :, :3], cv2.COLOR_BGR2GRAY)
        else:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img
        grays.append(gray)

    N = len(grays)
    if N < 4:
        return {
            "indices": list(range(N)),
            "complexity": "trivial",
            "target_range": [N, N],
            "extrema_count": 0,
            "method": "all_frames (too few to extract)",
        }

    magnitudes, directions = compute_motion_signals(grays)
    complexity, auto_min, auto_max = estimate_complexity(magnitudes, directions)

    t_min = target_min if target_min is not None else auto_min
    t_max = target_max if target_max is not None else auto_max

    t_min = min(t_min, N)
    t_max = min(t_max, N)

    # If total frames already within target, keep all
    if N <= t_max:
        return {
            "indices": list(range(N)),
            "complexity": complexity,
            "target_range": [t_min, t_max],
            "extrema_count": 0,
            "method": "all_frames (within target range)",
        }

    # Step 1: Always include first frame
    selected = {0}

    # Step 2: Detect and include pose extrema
    extrema = detect_pose_extrema(magnitudes)
    for e in extrema:
        if e < N:
            selected.add(e)

    # Step 3: If too many extrema, keep only the most significant
    if len(selected) > t_max - 1:
        extrema_with_mag = [(e, magnitudes[min(e, len(magnitudes) - 1)]) for e in selected if e > 0]
        extrema_with_mag.sort(key=lambda x: x[1], reverse=True)
        selected = {0}
        for e, _ in extrema_with_mag[:t_max - 2]:
            selected.add(e)

    extrema_count = len(selected) - 1  # minus frame 0

    # Step 4: Fill remaining with cumulative motion selection
    target_total = (t_min + t_max) // 2
    if len(selected) < target_total:
        extras = cumulative_motion_select(magnitudes, target_total, selected)
        for e in extras:
            if len(selected) >= t_max:
                break
            selected.add(e)

    # Step 5: If still below minimum, add evenly spaced fillers
    if len(selected) < t_min:
        all_indices = set(range(N))
        available = sorted(all_indices - selected)
        needed = t_min - len(selected)
        if available and needed > 0:
            step = max(1, len(available) // (needed + 1))
            for i in range(0, len(available), step):
                if len(selected) >= t_min:
                    break
                selected.add(available[i])

    indices = sorted(selected)

    return {
        "indices": indices,
        "complexity": complexity,
        "target_range": [t_min, t_max],
        "extrema_count": extrema_count,
        "method": "motion_accumulation + pose_extrema_detection",
    }


# ── File operations ───────────────────────────────────────────────

def create_key_version(source_dir, key_dir, keyframe_result, source_fps=24):
    """
    Create _key version by copying selected keyframes and generating GIF/preview.

    Args:
        source_dir: directory containing frame_XXXX.png (source, already bg-removed)
        key_dir: output directory for _key version
        keyframe_result: dict from extract_keyframes()
        source_fps: original animation fps
    """
    os.makedirs(key_dir, exist_ok=True)

    source_frames = sorted(glob.glob(os.path.join(source_dir, "frame_*.png")))
    indices = keyframe_result["indices"]

    total_duration_ms = len(source_frames) * (1000 / source_fps)
    key_frame_duration_ms = int(total_duration_ms / len(indices))
    key_fps = 1000 / key_frame_duration_ms if key_frame_duration_ms > 0 else 12

    copied_frames = []
    for new_idx, src_idx in enumerate(indices):
        if src_idx >= len(source_frames):
            continue
        src_path = source_frames[src_idx]
        dst_path = os.path.join(key_dir, f"frame_{new_idx + 1:04d}.png")
        img = Image.open(src_path)
        img.save(dst_path, "PNG")
        copied_frames.append(img)
        print(f"  frame_{new_idx + 1:04d}.png ← source frame_{src_idx + 1:04d}.png")

    if not copied_frames:
        print("Warning: no frames copied")
        return

    # Generate GIF (same total duration as full version)
    gif_path = os.path.join(key_dir, "preview.gif")
    frames_rgba = [f.convert("RGBA") for f in copied_frames]
    frames_rgba[0].save(
        gif_path,
        save_all=True,
        append_images=frames_rgba[1:],
        duration=key_frame_duration_ms,
        loop=0,
        disposal=2,
    )
    print(f"  preview.gif ({len(indices)} frames, {key_frame_duration_ms}ms/frame ≈ {key_fps:.0f}fps)")

    # Generate preview.png strip
    thumb_size = 120
    n_show = min(10, len(copied_frames))
    step = max(1, len(copied_frames) // n_show)
    sel = [copied_frames[i * step] for i in range(n_show)]
    strip_imgs = []
    for f in sel:
        thumb = f.copy()
        thumb.thumbnail((thumb_size, thumb_size))
        canvas = Image.new("RGBA", (thumb_size, thumb_size), (0, 0, 0, 0))
        canvas.paste(thumb, ((thumb_size - thumb.width) // 2, (thumb_size - thumb.height) // 2))
        strip_imgs.append(canvas)
    strip = Image.new("RGBA", (thumb_size * len(strip_imgs), thumb_size), (240, 240, 240, 255))
    for i, s in enumerate(strip_imgs):
        strip.paste(s, (i * thumb_size, 0), s)
    strip.save(os.path.join(key_dir, "preview.png"))
    print(f"  preview.png ({n_show} thumbnails)")

    # Save keyframe_map.json
    map_data = {
        "source_anim": os.path.basename(source_dir),
        "source_total_frames": len(source_frames),
        "source_fps": source_fps,
        "keyframe_indices": indices,
        "keyframe_count": len(indices),
        "target_fps": round(key_fps, 1),
        "frame_duration_ms": key_frame_duration_ms,
        "complexity": keyframe_result["complexity"],
        "target_range": keyframe_result["target_range"],
        "extrema_count": keyframe_result["extrema_count"],
        "method": keyframe_result["method"],
    }
    json_path = os.path.join(key_dir, "keyframe_map.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(map_data, f, indent=2, ensure_ascii=False)
    print(f"  keyframe_map.json saved")

    return map_data


# ── CLI ───────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Extract keyframes from animation")
    parser.add_argument("frames_dir", help="Directory of frame_XXXX.png files")
    parser.add_argument("--target-min", type=int, default=None)
    parser.add_argument("--target-max", type=int, default=None)
    parser.add_argument("--output-dir", default=None,
                        help="Output directory for _key version (default: {frames_dir}_key)")
    parser.add_argument("--fps", type=int, default=24, help="Source animation FPS")
    args = parser.parse_args()

    frame_paths = sorted(glob.glob(os.path.join(args.frames_dir, "frame_*.png")))
    if not frame_paths:
        print(f"No frame_*.png found in {args.frames_dir}")
        sys.exit(1)

    print(f"Source: {len(frame_paths)} frames in {args.frames_dir}")

    result = extract_keyframes(frame_paths, args.target_min, args.target_max)

    print(f"\nComplexity: {result['complexity']}")
    print(f"Target range: {result['target_range']}")
    print(f"Pose extrema detected: {result['extrema_count']}")
    print(f"Selected keyframes: {len(result['indices'])}")
    print(f"Indices: {result['indices']}")
    print(f"Method: {result['method']}")

    key_dir = args.output_dir or args.frames_dir + "_key"
    print(f"\nCreating key version → {key_dir}")
    create_key_version(args.frames_dir, key_dir, result, source_fps=args.fps)
    print("\nDone!")


if __name__ == "__main__":
    main()
