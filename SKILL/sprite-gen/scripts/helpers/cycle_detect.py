"""
Multi-strategy animation cycle detection.

Combines 4 approaches from the literature:
  1. TSM  – Temporal Self-Similarity Matrix (RepNet-style)
           Build an NxN cosine-similarity matrix of frame embeddings,
           then analyse diagonal stripes via autocorrelation of the
           first-row signal to find the dominant period.
  2. pHash – Perceptual Hashing (sunnybala/video-loop-detection style)
           Hamming distance between each frame's pHash and frame-0's pHash.
           Detect the first deep valley after the minimum cycle length.
  3. Optical Flow period – Dense optical flow magnitude is computed
           per frame, and FFT-based autocorrelation finds the dominant
           motion period.
  4. Character-region SSIM – SSIM restricted to the non-white character
           region (previous baseline approach).

The script produces:
  - Per-method cycle length suggestion
  - A consensus / weighted vote
  - A diagnostic visualisation saved as _video/cycle_diagnosis.png
"""

import os, sys, glob, argparse
import numpy as np
import cv2
from PIL import Image
from skimage.metrics import structural_similarity as ssim
import imagehash
from scipy.signal import find_peaks
from scipy.fft import fft, ifft

# ── helpers ─────────────────────────────────────────────────────────

def load_frames_gray(frame_dir):
    paths = sorted(glob.glob(os.path.join(frame_dir, "frame_*.png")))
    grays = [cv2.imread(p, cv2.IMREAD_GRAYSCALE) for p in paths]
    return paths, grays


def char_bbox(gray, threshold=240, pad=15):
    mask = (gray < threshold).astype(np.uint8)
    kernel = np.ones((pad, pad), np.uint8)
    mask = cv2.dilate(mask, kernel, iterations=2)
    ys, xs = np.where(mask > 0)
    if len(ys) == 0:
        h, w = gray.shape
        return 0, h, 0, w
    return ys.min(), ys.max(), xs.min(), xs.max()


# ── Method 1: TSM (Temporal Self-Similarity Matrix) ────────────────

def tsm_period(grays, resize=64, min_cycle=10):
    """
    Build a cosine-similarity matrix of resized frame vectors,
    then autocorrelate the first-row similarity signal to find
    the dominant period (RepNet-style approach).
    """
    N = len(grays)
    vecs = np.array([cv2.resize(g, (resize, resize)).flatten().astype(np.float32)
                     for g in grays])
    norms = np.linalg.norm(vecs, axis=1, keepdims=True)
    norms[norms == 0] = 1
    vecs = vecs / norms

    sim_row0 = vecs @ vecs[0]

    ac = np.real(ifft(np.abs(fft(sim_row0 - sim_row0.mean())) ** 2))
    ac = ac[:N // 2]
    ac = ac / (ac[0] if ac[0] != 0 else 1)

    peaks, props = find_peaks(ac[min_cycle:], height=0.05, distance=5)
    if len(peaks) == 0:
        return None, sim_row0, ac
    best = peaks[np.argmax(props["peak_heights"])] + min_cycle
    return int(best), sim_row0, ac


# ── Method 2: pHash distance ──────────────────────────────────────

def phash_period(frame_paths, min_cycle=10, hash_size=16):
    """
    Compute pHash Hamming distance between frame 0 and every other frame.
    The first prominent valley after min_cycle frames indicates a loop return.
    """
    ref = Image.open(frame_paths[0]).convert("L")
    ref_hash = imagehash.phash(ref, hash_size=hash_size)

    distances = []
    for p in frame_paths:
        h = imagehash.phash(Image.open(p).convert("L"), hash_size=hash_size)
        distances.append(ref_hash - h)
    distances = np.array(distances, dtype=float)

    inv = distances.max() - distances
    peaks, props = find_peaks(inv[min_cycle:], height=inv[min_cycle:].max() * 0.6,
                              distance=5, prominence=2)
    if len(peaks) == 0:
        return None, distances
    best = peaks[0] + min_cycle
    return int(best), distances


# ── Method 3: Optical Flow period ─────────────────────────────────

def flow_period(grays, min_cycle=10):
    """
    Compute dense optical flow magnitude between consecutive frames,
    then find the dominant period via FFT autocorrelation of that signal.
    """
    magnitudes = []
    for i in range(1, len(grays)):
        flow = cv2.calcOpticalFlowFarneback(
            grays[i - 1], grays[i], None,
            pyr_scale=0.5, levels=3, winsize=15,
            iterations=3, poly_n=5, poly_sigma=1.2, flags=0)
        mag = np.sqrt(flow[..., 0] ** 2 + flow[..., 1] ** 2)
        magnitudes.append(mag.mean())
    sig = np.array(magnitudes)

    ac = np.real(ifft(np.abs(fft(sig - sig.mean())) ** 2))
    ac = ac[:len(sig) // 2]
    ac = ac / (ac[0] if ac[0] != 0 else 1)

    peaks, props = find_peaks(ac[min_cycle:], height=0.05, distance=5)
    if len(peaks) == 0:
        return None, sig, ac
    best = peaks[np.argmax(props["peak_heights"])] + min_cycle
    return int(best), sig, ac


# ── Method 4: Character-region SSIM ───────────────────────────────

def ssim_period(grays, min_cycle=10):
    y1, y2, x1, x2 = char_bbox(grays[0])
    ref_crop = grays[0][y1:y2, x1:x2]

    scores = []
    for i, g in enumerate(grays):
        if i < min_cycle:
            scores.append(0.0)
            continue
        crop = g[y1:y2, x1:x2]
        s = ssim(ref_crop, crop)
        scores.append(s)
    scores = np.array(scores)

    peaks, props = find_peaks(scores[min_cycle:], height=0.6,
                              distance=5, prominence=0.02)
    if len(peaks) == 0:
        return None, scores
    best = peaks[0] + min_cycle
    return int(best), scores


# ── Consensus ─────────────────────────────────────────────────────

def consensus(results, tolerance=3):
    """
    Weighted median approach. Weight: TSM=3, pHash=3, Flow=2, SSIM=2.
    Find the cluster of estimates within `tolerance` frames.
    """
    weights = {"TSM": 3, "pHash": 3, "Flow": 2, "SSIM": 2}
    estimates = []
    for name, val in results.items():
        if val is not None:
            w = weights.get(name, 1)
            estimates.extend([val] * w)
    if not estimates:
        return None
    estimates = sorted(estimates)
    best_count, best_val = 0, estimates[len(estimates) // 2]
    for e in set(estimates):
        count = sum(1 for x in estimates if abs(x - e) <= tolerance)
        if count > best_count:
            best_count = count
            best_val = e
    return int(best_val)


# ── Visualisation (PIL-based, no matplotlib dependency) ───────────

def _draw_signal(width, height, values, color=(0, 120, 255), bg=(255, 255, 255)):
    """Draw a simple line chart as a PIL Image."""
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(img)
    if len(values) < 2:
        return img
    vmin, vmax = min(values), max(values)
    rng = vmax - vmin if vmax != vmin else 1
    margin = 4
    pts = []
    for i, v in enumerate(values):
        x = margin + int(i * (width - 2 * margin) / (len(values) - 1))
        y = height - margin - int((v - vmin) / rng * (height - 2 * margin))
        pts.append((x, y))
    for i in range(len(pts) - 1):
        draw.line([pts[i], pts[i + 1]], fill=color, width=1)
    return img


def _draw_vline(img, x_frac, color=(255, 0, 0)):
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    x = int(4 + x_frac * (img.width - 8))
    draw.line([(x, 0), (x, img.height)], fill=color, width=2)
    return img


def make_diagnosis_plot(frame_paths, grays,
                        tsm_sim, tsm_ac, tsm_est,
                        phash_dist, phash_est,
                        flow_sig, flow_ac, flow_est,
                        ssim_scores, ssim_est,
                        final_est, out_path):
    from PIL import Image, ImageDraw, ImageFont

    chart_w, chart_h = 600, 140
    thumb_size = 100
    N = len(grays)

    charts = []
    labels = []

    def add_chart(values, est, label, color):
        img = _draw_signal(chart_w, chart_h, list(values), color=color)
        if est is not None and len(values) > 1:
            _draw_vline(img, est / (len(values) - 1))
        charts.append(img)
        labels.append(label)

    add_chart(tsm_sim, tsm_est, f"TSM cosine sim→F0 (est={tsm_est})", (0, 100, 220))
    add_chart(tsm_ac, tsm_est, f"TSM autocorrelation (est={tsm_est})", (0, 100, 220))
    add_chart(phash_dist, phash_est, f"pHash Hamming dist→F0 (est={phash_est})", (128, 0, 200))
    inv = phash_dist.max() - phash_dist
    add_chart(inv, phash_est, f"pHash inverted (est={phash_est})", (128, 0, 200))
    add_chart(flow_sig, flow_est, f"OpticalFlow magnitude (est={flow_est})", (0, 160, 0))
    add_chart(flow_ac, flow_est, f"OpticalFlow autocorr (est={flow_est})", (0, 160, 0))
    add_chart(ssim_scores, ssim_est, f"Char-SSIM→F0 (est={ssim_est})", (220, 120, 0))

    label_h = 18
    row_h = chart_h + label_h
    rows = (len(charts) + 1) // 2
    panel_w = chart_w * 2 + 20
    panel_h = rows * row_h + 20

    thumb_strip_h = thumb_size + 30
    total_h = panel_h + thumb_strip_h + 60

    canvas = Image.new("RGB", (panel_w, total_h), (255, 255, 255))
    draw = ImageDraw.Draw(canvas)

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
        font_title = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
    except Exception:
        font = ImageFont.load_default()
        font_title = font

    draw.text((10, 5), f"Cycle Detection — Consensus: {final_est} frames  "
              f"(TSM={tsm_est} pHash={phash_est} Flow={flow_est} SSIM={ssim_est})",
              fill=(0, 0, 0), font=font_title)

    y_off = 30
    for idx, (chart, label) in enumerate(zip(charts, labels)):
        col = idx % 2
        row = idx // 2
        x = 10 + col * (chart_w + 10)
        y = y_off + row * row_h
        draw.text((x, y), label, fill=(60, 60, 60), font=font)
        canvas.paste(chart, (x, y + label_h))

    # Frame strip: F0 vs candidates around each method's estimate
    y_strip = y_off + rows * row_h + 10
    draw.text((10, y_strip), "Frame comparison — F0 (ref) vs candidate loop points:",
              fill=(0, 0, 0), font=font)
    y_strip += 20

    candidates = sorted(set(
        [e for e in [tsm_est, phash_est, flow_est, ssim_est] if e is not None and e < N]
    ))
    show_indices = [0] + candidates
    x_pos = 10
    for idx in show_indices:
        thumb = cv2.resize(grays[idx], (thumb_size, thumb_size))
        thumb_pil = Image.fromarray(thumb)
        canvas.paste(thumb_pil, (x_pos, y_strip))
        lbl = "F0 (ref)" if idx == 0 else f"F{idx}"
        draw.text((x_pos, y_strip + thumb_size + 2), lbl, fill=(0, 0, 0), font=font)
        x_pos += thumb_size + 8

    canvas.save(out_path)
    print(f"Saved diagnosis plot → {out_path}")


# ── Action Segmentation (for single-play animations) ─────────────

def reference_deviation_signal(grays):
    """
    Compute per-frame deviation from the reference pose (frame 0).
    Returns a 1-D numpy array where higher values = further from neutral.

    For single-play animations (dash, attack, hurt), the video structure is:
        [idle/hover] → [action onset] → [action peak] → [recovery] → [idle/hover]
    This signal peaks during the action and stays low during idle portions.
    """
    y1, y2, x1, x2 = char_bbox(grays[0])
    ref_crop = grays[0][y1:y2, x1:x2]
    deviations = np.array([
        np.mean(cv2.absdiff(ref_crop, g[y1:y2, x1:x2])) for g in grays
    ])
    return deviations


def action_segment(grays, percentile=40, padding=4):
    """
    Segment the action region from a single-play animation video.

    Uses reference deviation to find where the character departs from and
    returns to its neutral pose. The action interval is the contiguous
    region where deviation exceeds a percentile-based threshold.

    Args:
        grays: list of grayscale frames
        percentile: deviation percentile for threshold (lower = wider interval)
        padding: extra frames to keep before/after the action boundaries

    Returns:
        (action_start, action_end, deviations)
        Indices are inclusive. Returns (0, len-1, deviations) if detection fails.
    """
    deviations = reference_deviation_signal(grays)
    N = len(grays)

    threshold = np.percentile(deviations, percentile)
    above = deviations > threshold

    action_start = None
    action_end = None
    for i in range(N):
        if above[i]:
            if action_start is None:
                action_start = i
            action_end = i

    if action_start is None:
        return 0, N - 1, deviations

    action_start = max(0, action_start - padding)
    action_end = min(N - 1, action_end + padding)
    return action_start, action_end, deviations


def generate_action_candidate_gifs(frame_paths, grays, out_dir,
                                   percentiles=(30, 40, 50), padding=4, fps=24):
    """
    Generate candidate GIFs for a single-play animation using different
    percentile thresholds. Returns list of candidate dicts.
    """
    os.makedirs(out_dir, exist_ok=True)
    candidates = []
    for pct in percentiles:
        start, end, devs = action_segment(grays, percentile=pct, padding=padding)
        n_frames = end - start + 1
        frames_pil = [Image.open(frame_paths[j]).convert("RGBA")
                      for j in range(start, end + 1)]
        gif_name = f"action_{n_frames}f_P{pct}.gif"
        gif_path = os.path.join(out_dir, gif_name)
        frames_pil[0].save(
            gif_path, save_all=True, append_images=frames_pil[1:],
            duration=int(1000 / fps), loop=0, disposal=2,
        )
        c = {
            "start": start, "end": end, "n_frames": n_frames,
            "percentile": pct, "gif_path": gif_path,
        }
        candidates.append(c)
        print(f"  {gif_name}  (frame_{start+1:04d}~{end+1:04d}, {n_frames} frames)")
    return candidates


# ── Peak Isolation (for single-play animations, v2) ──────────────

def interframe_motion_signal(grays):
    """Compute per-frame motion magnitude (absdiff with previous frame)."""
    motions = np.zeros(len(grays))
    for i in range(1, len(grays)):
        motions[i] = np.mean(cv2.absdiff(grays[i], grays[i - 1]))
    return motions


def detect_active_region(grays, smooth_kernel=7, margin=2):
    """
    Find the frame range where actual animation is happening,
    skipping leading/trailing static segments that Kling often produces.

    Uses Otsu's method on the smoothed motion signal to separate
    "active" frames from "static" frames.

    Returns (active_start, active_end) inclusive indices.
    If the whole video is active or static, returns (0, len-1).
    """
    motions = interframe_motion_signal(grays)
    kernel = np.ones(smooth_kernel) / smooth_kernel
    smoothed = np.convolve(motions, kernel, mode='same')

    sig_uint8 = np.clip(smoothed / (smoothed.max() + 1e-9) * 255, 0, 255).astype(np.uint8)
    thresh_val, _ = cv2.threshold(sig_uint8, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    threshold = thresh_val / 255.0 * (smoothed.max() + 1e-9)

    active = smoothed > threshold * 0.5
    indices = np.where(active)[0]
    if len(indices) == 0:
        return 0, len(grays) - 1

    start = max(0, int(indices[0]) - margin)
    end = min(len(grays) - 1, int(indices[-1]) + margin)
    return start, end


def isolate_action_peak(grays, padding=3, smooth_kernel=5):
    """
    Peak-isolation algorithm for single-play animations.

    Combines two signals:
      - Reference deviation: how far each frame is from the idle pose
      - Inter-frame motion: how fast things are moving between frames
    Their product highlights frames that are BOTH far from idle AND in
    active motion, naturally suppressing idle/hover frames to near zero.

    Uses Otsu's method on the combined signal to find the optimal threshold
    that separates action frames from idle frames, then finds the contiguous
    region around the peak that exceeds this threshold.

    Args:
        grays: list of grayscale frames (motion frames, static trimmed)
        padding: extra frames on each side for natural transitions
        smooth_kernel: moving-average kernel size for noise reduction

    Returns:
        dict with keys:
          start, end: inclusive frame indices into grays
          n_frames: frame count
          peak_idx: index of action climax
          peak_value: combined signal value at climax
          threshold: Otsu-derived threshold used for boundary detection
          combined_signal: the full combined signal array (for diagnostics)
    """
    N = len(grays)
    if N < 6:
        return {"start": 0, "end": N - 1, "n_frames": N, "peak_idx": 0,
                "peak_value": 0, "threshold": 0, "combined_signal": np.zeros(N)}

    devs = reference_deviation_signal(grays)
    motions = interframe_motion_signal(grays)

    d_min, d_max = devs.min(), devs.max()
    m_min, m_max = motions.min(), motions.max()
    devs_n = (devs - d_min) / (d_max - d_min + 1e-6)
    mot_n = (motions - m_min) / (m_max - m_min + 1e-6)

    combined = devs_n * mot_n

    kernel = np.ones(smooth_kernel) / smooth_kernel
    smoothed = np.convolve(combined, kernel, mode='same')

    sig_u8 = np.clip((smoothed / (smoothed.max() + 1e-9) * 255), 0, 255).astype(np.uint8)
    otsu_val, _ = cv2.threshold(sig_u8, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    threshold = (otsu_val / 255.0) * smoothed.max()

    above = smoothed > threshold
    peak_idx = int(np.argmax(smoothed))

    left = peak_idx
    while left > 0 and above[left - 1]:
        left -= 1
    right = peak_idx
    while right < N - 1 and above[right + 1]:
        right += 1

    left = max(0, left - padding)
    right = min(N - 1, right + padding)

    return {
        "start": left,
        "end": right,
        "n_frames": right - left + 1,
        "peak_idx": peak_idx,
        "peak_value": float(smoothed[peak_idx]),
        "threshold": float(threshold),
        "combined_signal": smoothed,
    }


def isolate_action_and_export_gif(frame_paths, grays, out_dir,
                                  padding=3, fps=24):
    """
    One-shot action isolation: detect the action peak, export a single GIF.
    Uses Otsu threshold on the combined signal for automatic boundary detection.

    Also exports a tighter version (deviation FWHM) as fallback.
    """
    os.makedirs(out_dir, exist_ok=True)
    result = isolate_action_peak(grays, padding=padding)

    start, end = result["start"], result["end"]
    n = result["n_frames"]
    dur_sec = n / fps

    frames_pil = [Image.open(frame_paths[j]).convert("RGBA")
                  for j in range(start, end + 1)]
    gif_name = f"action_{n}f_peak.gif"
    gif_path = os.path.join(out_dir, gif_name)
    frames_pil[0].save(
        gif_path, save_all=True, append_images=frames_pil[1:],
        duration=int(1000 / fps), loop=0, disposal=2,
    )
    result["gif_path"] = gif_path
    print(f"  ★ peak isolation (Otsu): {n} frames ({dur_sec:.1f}s) "
          f"frame_{start+1:04d}~frame_{end+1:04d}")
    print(f"    peak at frame_{result['peak_idx']+1:04d}, "
          f"threshold={result['threshold']:.4f}")
    print(f"    GIF: {gif_path}")

    # Fallback: tighter version using deviation FWHM
    devs = reference_deviation_signal(grays)
    dev_thresh = devs.max() * 0.6
    above_dev = devs > dev_thresh
    peak_idx = result["peak_idx"]
    tl = peak_idx
    while tl > 0 and above_dev[tl - 1]:
        tl -= 1
    tr = peak_idx
    while tr < len(grays) - 1 and above_dev[tr + 1]:
        tr += 1
    tp = max(0, padding - 1)
    tl = max(0, tl - tp)
    tr = min(len(grays) - 1, tr + tp)
    tn = tr - tl + 1
    tight_pil = [Image.open(frame_paths[j]).convert("RGBA")
                 for j in range(tl, tr + 1)]
    tight_gif = os.path.join(out_dir, f"action_{tn}f_tight.gif")
    tight_pil[0].save(
        tight_gif, save_all=True, append_images=tight_pil[1:],
        duration=int(1000 / fps), loop=0, disposal=2,
    )
    tight = {"start": tl, "end": tr, "n_frames": tn, "gif_path": tight_gif}
    print(f"    fallback tight (dev 60%): {tn} frames ({tn/fps:.1f}s) "
          f"frame_{tl+1:04d}~frame_{tr+1:04d} → {tight_gif}")

    return result, tight


# ── Frame Quality Gate ───────────────────────────────────────────

def frame_quality_gate(frame_paths, grays, ref_gray, hash_size=16,
                       identity_threshold=0.75, ar_deviation_threshold=0.40):
    """
    Score each frame on two quality axes and return pass/fail results.

    1. Identity (pHash): How similar is this frame's character to the reference?
       Catches character design drift over time.
    2. View consistency (bbox aspect ratio): Does the character maintain
       side-view proportions? Catches 3D rotation / perspective changes.

    Returns:
        list of dicts with keys: index, path, identity, frame_ar, ar_dev, passed
    """
    ref_pil = Image.open(frame_paths[0]).convert("L") if not ref_gray.any() \
        else Image.fromarray(ref_gray).convert("L")
    ref_hash = imagehash.phash(ref_pil, hash_size=hash_size)
    y1, y2, x1, x2 = char_bbox(ref_gray)
    ref_ar = (x2 - x1) / (y2 - y1) if (y2 - y1) > 0 else 1.0

    results = []
    for i, (fp, g) in enumerate(zip(frame_paths, grays)):
        frame_hash = imagehash.phash(Image.fromarray(g).convert("L"),
                                     hash_size=hash_size)
        hash_dist = ref_hash - frame_hash
        identity = 1.0 - hash_dist / (hash_size * hash_size)

        fy1, fy2, fx1, fx2 = char_bbox(g)
        frame_ar = (fx2 - fx1) / (fy2 - fy1) if (fy2 - fy1) > 0 else 0
        ar_dev = abs(frame_ar - ref_ar) / ref_ar if ref_ar > 0 else 999

        passed = identity > identity_threshold and ar_dev < ar_deviation_threshold
        results.append({
            "index": i, "path": fp, "identity": identity,
            "frame_ar": frame_ar, "ar_dev": ar_dev, "passed": passed,
        })
    return results, ref_ar


# ── Jump Ratio scoring ────────────────────────────────────────────

def jump_ratio_candidates(grays, all_estimates, min_cycle=10, top_n=4):
    """
    For each candidate cycle length, slide a window across the active region
    to find the (start, cycle_len) pair with the best Transition Jump Ratio:

        jump_ratio = |F(start+cycle_len-1) - F(start)| / mean(inter-frame diffs)

    Automatically skips leading/trailing static segments via detect_active_region.
    Rejects windows whose average inter-frame motion is below a floor threshold,
    preventing static frames from being selected as "perfect loops".

    Returns top_n candidates sorted by jump_ratio ascending.
    Each candidate dict contains: cycle_len, jump_ratio, start, active_start, active_end.
    """
    valid = [e for e in all_estimates if e is not None]
    if not valid:
        return []

    active_start, active_end = detect_active_region(grays)
    active_len = active_end - active_start + 1
    print(f"  [active region] frame {active_start}~{active_end} "
          f"({active_len} frames, skipped {active_start} leading + "
          f"{len(grays)-1-active_end} trailing static frames)")

    active_grays = grays[active_start:active_end + 1]
    if active_len < min_cycle:
        active_grays = grays
        active_start = 0
        active_end = len(grays) - 1
        active_len = len(grays)

    lo = max(min_cycle, min(valid) - 5)
    hi = min(active_len - 1, max(valid) + 5)
    if lo > hi:
        lo = min_cycle
        hi = min(active_len - 1, max(valid) + 10)

    y1, y2, x1, x2 = char_bbox(active_grays[0])

    global_motions = interframe_motion_signal(active_grays)
    global_motion_median = np.median(global_motions[global_motions > 0]) if np.any(global_motions > 0) else 0
    motion_floor = global_motion_median * 0.3

    results = []
    seen_cycles = {}

    for cycle_len in range(lo, hi + 1):
        if cycle_len >= active_len:
            break

        best_jr = 999
        best_start = 0
        best_avg_trans = 0

        stride = max(1, cycle_len // 4)
        for s in range(0, active_len - cycle_len, stride):
            trans = []
            for i in range(s + 1, s + cycle_len):
                diff = cv2.absdiff(active_grays[i - 1][y1:y2, x1:x2],
                                   active_grays[i][y1:y2, x1:x2])
                trans.append(np.mean(diff))
            avg_trans = np.mean(trans) if trans else 0

            if avg_trans < motion_floor:
                continue

            loop_diff = cv2.absdiff(active_grays[s + cycle_len - 1][y1:y2, x1:x2],
                                    active_grays[s][y1:y2, x1:x2])
            loop_trans = np.mean(loop_diff)
            jr = loop_trans / avg_trans if avg_trans > 0 else 999

            if jr < best_jr:
                best_jr = jr
                best_start = s
                best_avg_trans = avg_trans

        if best_avg_trans >= motion_floor:
            results.append({
                "cycle_len": cycle_len,
                "jump_ratio": best_jr,
                "start": active_start + best_start,
                "active_start": active_start,
                "active_end": active_end,
            })

    results.sort(key=lambda r: r["jump_ratio"])
    return results[:top_n]


# ── Candidate GIF generation ─────────────────────────────────────

def generate_candidate_gifs(frame_paths, candidates, out_dir, fps=24):
    """
    Generate a looping GIF for each candidate cycle.
    Uses the candidate's 'start' field to offset into frame_paths.
    """
    os.makedirs(out_dir, exist_ok=True)
    gif_paths = []
    for c in candidates:
        n = c["cycle_len"]
        jr = c["jump_ratio"]
        s = c.get("start", 0)
        frames_pil = []
        for i in range(s, s + n):
            if i >= len(frame_paths):
                break
            frames_pil.append(Image.open(frame_paths[i]).convert("RGBA"))
        if not frames_pil:
            continue
        gif_name = f"cycle_{n}f_s{s}_jr{jr:.2f}.gif"
        gif_path = os.path.join(out_dir, gif_name)
        frames_pil[0].save(
            gif_path,
            save_all=True,
            append_images=frames_pil[1:],
            duration=int(1000 / fps),
            loop=0,
            disposal=2,
        )
        c["gif_path"] = gif_path
        gif_paths.append(gif_path)
        print(f"  {gif_name}  ({n} frames from frame_{s:04d}, jump_ratio={jr:.2f})")
    return gif_paths


# ── Main ──────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Detect animation cycle length")
    parser.add_argument("frame_dir", help="Directory of frame_XXXX.png files")
    parser.add_argument("--min-cycle", type=int, default=10,
                        help="Minimum cycle length to consider")
    parser.add_argument("--trim-static", type=int, default=0,
                        help="Number of leading static frames to skip")
    parser.add_argument("--out", default=None,
                        help="Output path for diagnosis image")
    parser.add_argument("--gif-dir", default=None,
                        help="Output dir for candidate loop GIFs")
    parser.add_argument("--top-n", type=int, default=4,
                        help="Number of top candidates to output")
    args = parser.parse_args()

    frame_paths, grays = load_frames_gray(args.frame_dir)
    if args.trim_static > 0:
        frame_paths = frame_paths[args.trim_static:]
        grays = grays[args.trim_static:]

    total = len(grays)
    print(f"Loaded {total} frames from {args.frame_dir}")
    if args.trim_static:
        print(f"  (skipped first {args.trim_static} static frames)")

    min_c = args.min_cycle
    results = {}

    print("\n▸ Method 1: TSM (Temporal Self-Similarity Matrix)")
    tsm_est, tsm_sim, tsm_ac = tsm_period(grays, min_cycle=min_c)
    results["TSM"] = tsm_est
    print(f"  → estimated period: {tsm_est}")

    print("\n▸ Method 2: pHash (Perceptual Hash)")
    phash_est, phash_dist = phash_period(frame_paths, min_cycle=min_c)
    results["pHash"] = phash_est
    print(f"  → estimated period: {phash_est}")

    print("\n▸ Method 3: Optical Flow period")
    flow_est, flow_sig, flow_ac = flow_period(grays, min_cycle=min_c)
    results["Flow"] = flow_est
    print(f"  → estimated period: {flow_est}")

    print("\n▸ Method 4: Character-region SSIM")
    ssim_est, ssim_scores = ssim_period(grays, min_cycle=min_c)
    results["SSIM"] = ssim_est
    print(f"  → estimated period: {ssim_est}")

    print(f"\n  Individual estimates: TSM={tsm_est}  pHash={phash_est}  "
          f"Flow={flow_est}  SSIM={ssim_est}")

    # Jump Ratio refinement
    print(f"\n▸ Jump Ratio refinement (top {args.top_n}):")
    all_estimates = list(results.values())
    candidates = jump_ratio_candidates(grays, all_estimates,
                                       min_cycle=min_c, top_n=args.top_n)
    for i, c in enumerate(candidates):
        star = "★" if i == 0 else " "
        print(f"  {star} {c['cycle_len']} frames — jump_ratio = {c['jump_ratio']:.3f}")

    best = candidates[0]["cycle_len"] if candidates else 24
    print(f"\n{'='*50}")
    print(f"  RECOMMENDED: {best} frames (jump_ratio={candidates[0]['jump_ratio']:.3f})")
    print(f"{'='*50}")

    # Generate candidate GIFs
    gif_dir = args.gif_dir or os.path.join(os.path.dirname(args.frame_dir),
                                            "cycle_candidates")
    print(f"\n▸ Generating candidate loop GIFs → {gif_dir}")
    generate_candidate_gifs(frame_paths, candidates, gif_dir)

    # Diagnosis plot
    out_path = args.out or os.path.join(os.path.dirname(args.frame_dir),
                                        "cycle_diagnosis.png")
    make_diagnosis_plot(
        frame_paths, grays,
        tsm_sim, tsm_ac, tsm_est,
        phash_dist, phash_est,
        flow_sig, flow_ac, flow_est,
        ssim_scores, ssim_est,
        best, out_path)

    return candidates


if __name__ == "__main__":
    main()
