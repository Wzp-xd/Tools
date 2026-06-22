"""从 prompts/ 读模板 + 替换占位符,生成完整 prompt 和 negative_prompt。

使用:
    from tools.prompt_builder import (
        build_prompt,
        build_sequence_prompt,
        build_side_view_prompt,
        build_cutout_prompt,
        build_pose_reference_prompt,
    )
    prompt, neg = build_prompt("walk", "loop", "walks forward with bouncy steps", "magenta")
    prompt, neg = build_sequence_prompt("spark", "loop", "pulses in place", "green", "keep compact")
    sv_prompt = build_side_view_prompt("magenta", art_style="anime cel-shading")
    cutout_prompt = build_cutout_prompt(art_style="anime cel-shading")
    pose_prompt = build_pose_reference_prompt("flying or hovering in mid-air", "magenta")
"""
import os

_TEMPLATE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "prompts")

_DEFAULT_ART_STYLE = "Keep the exact same art style, rendering and shading as the input image"


def _read(name):
    with open(os.path.join(_TEMPLATE_DIR, name), encoding="utf-8") as f:
        return f.read().strip()


def build_prompt(anim_id, play_type, action_desc, key_color_name):
    """
    返回 (prompt, negative_prompt)。

    play_type: "loop" / "once" / "attack" / 或任何自定义类型(自动发现同名 .txt)
      - "attack" 或动画id含 attack/punch/kick/slash/strike/peck/smash/stab/shoot/cast → 用攻击模板
      - "once" → 通用单次三段式
      - "loop" → 循环模板
      - 其他 → 查找 prompts/{play_type}.txt(可扩展,加 .txt 就能用)
    """
    attack_keywords = {"attack", "punch", "kick", "slash", "strike", "peck",
                       "smash", "stab", "shoot", "cast"}
    is_attack = (play_type == "attack" or
                 any(kw in anim_id.lower() for kw in attack_keywords))

    if is_attack:
        tpl_name = "attack.txt"
    elif play_type == "once":
        tpl_name = "once.txt"
    elif os.path.exists(os.path.join(_TEMPLATE_DIR, f"{play_type}.txt")):
        tpl_name = f"{play_type}.txt"
    else:
        tpl_name = "loop.txt"

    tpl = _read(tpl_name)
    full_action = f"{anim_id} animation, {action_desc}"
    prompt = (tpl.replace("{动作描述}", full_action)
                 .replace("{KEY_COLOR}", key_color_name)
                 .strip())

    neg_parts = [_read("negative_base.txt")]
    if play_type in ("once", "attack") or is_attack:
        neg_parts.append(_read("negative_once.txt"))
    if is_attack:
        neg_parts.append(_read("negative_attack.txt"))

    # 按动画语义自动追加飞行/地面 negative(防幻觉)
    aerial_keywords = {"fly", "air", "hover", "aerial", "dash", "glide", "float"}
    aid_lower = anim_id.lower()
    if any(kw in aid_lower for kw in aerial_keywords):
        neg_file = "negative_aerial.txt"
    else:
        neg_file = "negative_ground.txt"
    if os.path.exists(os.path.join(_TEMPLATE_DIR, neg_file)):
        neg_parts.append(_read(neg_file))

    # 可扩展:如果存在 negative_{play_type}.txt 且未被上面的逻辑覆盖,追加
    already = {"negative_base.txt", "negative_once.txt", "negative_attack.txt",
               "negative_aerial.txt", "negative_ground.txt"}
    neg_custom = f"negative_{play_type}.txt"
    if neg_custom not in already and os.path.exists(os.path.join(_TEMPLATE_DIR, neg_custom)):
        neg_parts.append(_read(neg_custom))

    negative = ", ".join(neg_parts)

    return prompt, negative


def build_sequence_prompt(anim_id, play_type, action_desc, key_color_name, user_prompt=None):
    """
    Build neutral sequence/VFX prompts without character-facing constraints.

    user_prompt is a user-provided extra requirement merged through template placeholders.
    """
    if os.path.exists(os.path.join(_TEMPLATE_DIR, f"sequence_{play_type}.txt")):
        tpl_name = f"sequence_{play_type}.txt"
    elif play_type == "once":
        tpl_name = "sequence_once.txt"
    else:
        tpl_name = "sequence_loop.txt"

    tpl = _read(tpl_name)
    full_action = f"{anim_id} sequence, {action_desc}"
    extra = (user_prompt or "").strip()
    extra_line = f"Additional user requirements: {extra}" if extra else "No additional user requirements."
    prompt = (tpl.replace("{动作描述}", full_action)
                 .replace("{用户提示词}", extra_line)
                 .replace("{KEY_COLOR}", key_color_name)
                 .strip())

    neg_parts = [_read("negative_sequence_base.txt")]
    if play_type == "once" and os.path.exists(os.path.join(_TEMPLATE_DIR, "negative_sequence_once.txt")):
        neg_parts.append(_read("negative_sequence_once.txt"))

    neg_custom = f"negative_sequence_{play_type}.txt"
    already = {"negative_sequence_base.txt", "negative_sequence_once.txt"}
    if neg_custom not in already and os.path.exists(os.path.join(_TEMPLATE_DIR, neg_custom)):
        neg_parts.append(_read(neg_custom))

    return prompt, ", ".join(neg_parts)


_VIEW_ANGLES = {
    "profile": "strict side-view profile facing right, full body viewed directly from the side",
    "cheated": "side-view facing right, rotate hips legs and feet together to a 75-degree angle so both full legs are clearly visible and separated from hip to foot, do NOT keep the original front-facing feet",
}


def build_side_view_prompt(key_color_name, art_style=None, view_angle=None):
    """
    返回转侧视用的 edit_image prompt。

    art_style:   用户指定的风格(如 "anime cel-shading")。None→缺省保持原图风格。
    view_angle:  "profile"(纯侧视,默认) / "cheated"(cheated profile,露双腿)。
    """
    style = art_style if art_style else _DEFAULT_ART_STYLE
    angle = _VIEW_ANGLES.get(view_angle or "profile", _VIEW_ANGLES["profile"])
    tpl = _read("side_view.txt")
    return (tpl.replace("{VIEW_ANGLE}", angle)
               .replace("{ART_STYLE}", style)
               .replace("{KEY_COLOR}", key_color_name)
               .strip())


def build_cutout_prompt(art_style=None):
    """Return edit_image prompt for extracting a transparent foreground asset."""
    style = art_style if art_style else _DEFAULT_ART_STYLE
    tpl = _read("cutout_transparent.txt")
    return tpl.replace("{ART_STYLE}", style).strip()

def build_pose_reference_prompt(pose_hint, key_color_name, art_style=None):
    """Return edit_image prompt for a missing character pose reference."""
    style = art_style if art_style else _DEFAULT_ART_STYLE
    tpl = _read("pose_reference.txt")
    return (tpl.replace("{POSE_HINT}", pose_hint)
               .replace("{ART_STYLE}", style)
               .replace("{KEY_COLOR}", key_color_name)
               .strip())
