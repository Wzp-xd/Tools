#!/usr/bin/env python3
"""Describe the current effective sprite-gen config and generate static refs."""

import argparse
import copy
import json
import os
import sys

# 自给自足地把 helpers 加到 path,不依赖 build_video_prompt 导入时的副作用。
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))

from build_video_prompt import (
    _video_expected_resolution,
)


VIDEO_GENERATION_TIERS = {"fast", "default"}


ASSET_TYPE_SPECS = [
    {
        "asset_type": "character",
        "label": "角色/对象动画",
        "applies_to": "角色、怪物、可行动对象、缺省 pivot 在脚底的对象动画",
        "guide": "refs/character_guide.md",
        "pivot_default": "脚底",
        "notes": "适合需要按角色/对象支点切换动作的精灵",
    },
    {
        "asset_type": "sequence",
        "label": "非角色序列帧",
        "applies_to": "特效、图标动画、视频式纹理序列、缺省 pivot 在中心的非角色动画",
        "guide": "refs/sequence_guide.md",
        "pivot_default": "中心",
        "notes": "适合按普通图片/序列帧播放的非角色素材",
    },
]


CONFIG_BASE_SPECS = [
    {
        "key": "work_dir",
        "choices": "路径",
        "desc": "sprite-gen 工作目录,保存配置、提示词、中间产物、参考图和预览",
        "when": "通常不改;需要把中间产物放到指定目录时调整",
    },
    {
        "key": "output_dir",
        "choices": "路径",
        "desc": "最终游戏资产输出目录",
        "when": "游戏项目使用不同资产目录时调整",
    },
    {
        "key": "asset_type",
        "choices": "character / sequence",
        "desc": "素材类型;character=角色/对象动画,sequence=非角色序列帧/视频式序列帧",
        "when": "由流程选择决定;不要在已开始的精灵中随意切换",
    },
    {
        "key": "target_height",
        "choices": "整数像素",
        "desc": "输出精灵高度,指导出后素材主体实际内容高度,不含透明边距",
        "when": "根据游戏中的预期呈现大小设置,不建议依赖游戏运行时缩放",
    },
    {
        "key": "ready_layout.content_ratio",
        "choices": "0.01-1.0",
        "desc": "素材主体在 ready 方图中的占比;值越小预留动画空间越多,但画布和视频推导分辨率越大",
        "when": "动作容易出框时调小;主体太小、细节不足或生成成本过高时调大",
    },
]


OPTION_SPECS = [
    {
        "key": "source_size_mode",
        "choices": "canvas / bbox-per-anim",
        "desc": "sourceSize 计算方式;canvas 更稳定,bbox-per-anim 空白更少但切动画需应用 pivot",
        "when": "需要减小透明留白且运行时是 absolute+pivot 时改为 bbox-per-anim",
    },
    {
        "key": "fps",
        "choices": "整数",
        "desc": "导出帧率和每帧 duration",
        "when": "想更顺滑可调高,想减小帧数和体积可调低",
    },
    {
        "key": "video_duration",
        "choices": "秒数字符串",
        "desc": "每条视频生成时长",
        "when": "复杂单次动作可加长,普通循环通常保持缺省",
    },
    {
        "key": "video_generation_tier",
        "choices": "fast / default",
        "desc": "视频生成档位",
        "when": "优先速度用 fast,优先质量稳定性用 default",
    },
    {
        "key": "video_expected_resolution",
        "choices": "480 / 720 / 1080 / null",
        "desc": "给视频模型的期望分辨率;null 会自动推导",
        "when": "细节不足时调高,想节省生成成本和时间可调低",
    },
    {
        "key": "ready_layout.offset_ratio_x",
        "choices": "数字",
        "desc": "ready 图水平偏移;正数右移,负数左移",
        "when": "需要给某一侧动作留空间时调整",
    },
    {
        "key": "ready_layout.offset_ratio_y",
        "choices": "数字",
        "desc": "ready 图垂直偏移;正数下移,负数上移",
        "when_by_asset_type": {
            "character": "角色脚底需要更靠下或动作需要上下空间时调整",
            "sequence": "素材中心需要上下微调或特效需要上下空间时调整",
        },
    },
    {
        "key": "chroma_strength",
        "choices": "数字",
        "desc": "色差键抠图强度",
        "when": "背景残留时调高,边缘被吃掉时调低",
    },
    {
        "key": "chroma_edge_shrink",
        "choices": "整数像素",
        "desc": "alpha 边缘内缩像素",
        "when": "边缘有幕布色描边时调高,细线/光效被削掉时调到 0",
    },
    {
        "key": "detect_min_cycle_frames",
        "choices": "整数帧",
        "desc": "循环检测的最小周期帧数",
        "when": "循环被截得太短时调高,很短循环识别不到时调低",
    },
    {
        "key": "detect_padding_frames",
        "choices": "整数帧",
        "desc": "单次动画峰值前后额外保留帧数",
        "when": "动作头尾被切掉时调高,想更紧凑时调低",
    },
]


CONFIG_TAIL_SPECS = [
    {
        "key": "ready_pose",
        "choices": "ground / aerial",
        "desc": "ready.png 当前姿态,供 character 流程判断是否需要补姿态参考图",
        "when": "ready 图不是地面站姿而是空中/飞行姿态时设为 aerial",
    },
    {
        "key": "prompt_merge_negative",
        "choices": "true / false",
        "desc": "是否把反向提示词合并进视频正向提示词的 Avoid 段",
        "when": "目标视频接口支持独立 negative 字段时可设为 false",
    },
    {
        "key": "frame_mode",
        "choices": "F / K",
        "desc": "F=按 fps 全帧;K=关键姿态抽帧,用于减少帧数和产物大小",
        "when": "需要完整帧率用 F;更重视体积和关键姿态时用 K",
    },
    {
        "key": "max_sheet_size",
        "choices": "整数像素",
        "desc": "单页图集上限",
        "when": "目标运行时或平台有更小纹理尺寸限制时调低",
    },
    {
        "key": "fal_proxy",
        "choices": "字符串",
        "desc": "生成服务代理地址",
        "when": "仅在接入环境要求代理时配置",
    },
]


CONFIG_FIELD_ORDER = [
    "work_dir",
    "output_dir",
    "asset_type",
    "target_height",
    "ready_layout.content_ratio",
    "source_size_mode",
    "fps",
    "frame_mode",
    "max_sheet_size",
    "ready_pose",
    "video_duration",
    "video_generation_tier",
    "video_expected_resolution",
    "prompt_merge_negative",
    "ready_layout.offset_ratio_x",
    "ready_layout.offset_ratio_y",
    "chroma_strength",
    "chroma_edge_shrink",
    "detect_min_cycle_frames",
    "detect_padding_frames",
    "fal_proxy",
]


CONFIG_LABELS = {
    "work_dir": "工作目录",
    "output_dir": "输出目录",
    "asset_type": "素材类型",
    "target_height": "输出精灵高度",
    "ready_layout.content_ratio": "精灵画布占比",
    "source_size_mode": "sourceSize 策略",
    "fps": "帧率",
    "frame_mode": "帧模式",
    "max_sheet_size": "单页图集上限",
    "ready_pose": "当前姿态",
    "video_duration": "视频时长",
    "video_generation_tier": "视频生成档位",
    "video_expected_resolution": "视频期望分辨率",
    "prompt_merge_negative": "合并反向提示词",
    "ready_layout.offset_ratio_x": "画布水平偏移",
    "ready_layout.offset_ratio_y": "画布垂直偏移",
    "chroma_strength": "抠图强度",
    "chroma_edge_shrink": "边缘内缩",
    "detect_min_cycle_frames": "循环检测最小帧数",
    "detect_padding_frames": "动作留帧",
    "fal_proxy": "生成服务代理",
}


JSON_SEMANTICS = [
    {
        "key": "frame",
        "desc": "裁剪后小图在 spritesheet PNG 里的位置和尺寸",
    },
    {
        "key": "sourceSize",
        "desc": "`source_size_mode=canvas` 时是缩放后的原始帧画布;`bbox-per-anim` 时是单个动画所有帧 alpha bbox 并集,并保留 pivot 所需空间",
    },
    {
        "key": "spriteSourceSize",
        "desc": "当前帧 tight crop 在 `sourceSize` 画布里的位置和尺寸",
    },
    {
        "key": "meta.pivot",
        "desc": "入口 sheet 的通用对齐点,固定写 `space=sourceSize`,`unit=normalized`,`origin=top_left`;character 来自 ready 图内容 bbox bottom-center,无法推导时缺省 `(0.5,0.5)`,sequence 缺省 `(0.5,0.5)`",
    },
    {
        "key": "meta.source_size_mode",
        "desc": "入口 sheet 使用的 `sourceSize` 策略,值与配置字段 `source_size_mode` 一致,供运行时/使用者对照文档选择布局方式",
    },
    {
        "key": "animations",
        "desc": "可选有序动画定义数组;每个动画用显式帧 key 数组声明播放顺序,不依赖 `frames` 字典顺序",
    },
    {
        "key": "meta.relatedMultiPacks",
        "desc": "可选关联 sheet JSON 列表,用于分页或多入口引用",
    },
    {
        "key": "duration",
        "desc": "K 模式读 `keyframe_map.json`;F 模式用 `1000 / fps`",
    },
]


SHEET_JSON_SCHEMA_REF = (
    "自行开发播放器时,参考 `refs/spritesheet.schema.json`;普通生成/使用无需读取。"
)


SPRITESHEET_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://tapmaker.local/sprite-gen/spritesheet.schema.json",
    "title": "sprite-gen 图集 JSON",
    "description": (
        "sprite-gen 生成的 TexturePacker/Pixi 风格 JSON,用于描述图集帧、"
        "动画帧序列和关联的分页/子表 JSON。"
    ),
    "type": "object",
    "required": ["meta"],
    "additionalProperties": True,
    "properties": {
        "frames": {
            "type": "object",
            "description": "帧表。key 是全局唯一帧名,value 是该帧在图集 PNG 中的位置、裁剪信息、sourceSize 和时长。",
            "additionalProperties": {"$ref": "#/$defs/frameEntry"},
        },
        "animations": {
            "type": "array",
            "description": "动画定义数组。数组顺序有意义,第一个动画可作为调用方未指定动画时的缺省动画。",
            "items": {"$ref": "#/$defs/animation"},
        },
        "meta": {
            "description": "图集或入口 JSON 的元信息,包括图片文件、图集尺寸、sourceSize 策略、通用 pivot 和关联 JSON。",
            "$ref": "#/$defs/meta",
        },
    },
    "$defs": {
        "rect": {
            "type": "object",
            "description": "矩形区域,x/y 为左上角,w/h 为尺寸,单位为像素。",
            "required": ["x", "y", "w", "h"],
            "additionalProperties": True,
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "w": {"type": "integer", "minimum": 1},
                "h": {"type": "integer", "minimum": 1},
            },
        },
        "size": {
            "type": "object",
            "description": "二维尺寸,单位为像素。",
            "required": ["w", "h"],
            "additionalProperties": True,
            "properties": {
                "w": {"type": "integer", "minimum": 0},
                "h": {"type": "integer", "minimum": 0},
            },
        },
        "frameEntry": {
            "type": "object",
            "description": "单帧 TexturePacker 风格数据。",
            "required": [
                "frame",
                "rotated",
                "trimmed",
                "spriteSourceSize",
                "sourceSize",
            ],
            "additionalProperties": True,
            "properties": {
                "frame": {
                    "description": "该帧在当前图集 PNG 中的矩形区域。",
                    "$ref": "#/$defs/rect",
                },
                "rotated": {
                    "type": "boolean",
                    "description": "是否旋转打包。sprite-gen 当前固定为 false。",
                },
                "trimmed": {
                    "type": "boolean",
                    "description": "是否裁掉透明边距。sprite-gen 输出为 tight crop,通常为 true。",
                },
                "spriteSourceSize": {
                    "description": "tight crop 后的帧在 sourceSize 画布中的位置和尺寸。",
                    "$ref": "#/$defs/rect",
                },
                "sourceSize": {
                    "description": "播放/对齐时使用的原始逻辑画布尺寸。",
                    "$ref": "#/$defs/size",
                },
                "duration": {
                    "type": "integer",
                    "minimum": 0,
                    "description": "该帧播放时长,单位毫秒。K 帧模式可能逐帧不同。",
                },
            },
        },
        "pivot": {
            "type": "object",
            "description": "支点。用于 absolute 布局或游戏演出中的对齐。",
            "required": ["space", "unit", "origin", "x", "y"],
            "additionalProperties": True,
            "properties": {
                "space": {
                    "const": "sourceSize",
                    "description": "支点坐标所在空间。sprite-gen 固定为 sourceSize。",
                },
                "unit": {
                    "const": "normalized",
                    "description": "坐标单位。normalized 表示 0..1 归一化。",
                },
                "origin": {
                    "const": "top_left",
                    "description": "坐标原点。top_left 表示 sourceSize 左上角。",
                },
                "x": {"type": "number", "description": "归一化 x 坐标。"},
                "y": {"type": "number", "description": "归一化 y 坐标。"},
            },
        },
        "animation": {
            "type": "object",
            "description": "一个动画的播放定义。",
            "required": ["name", "frames"],
            "additionalProperties": True,
            "properties": {
                "name": {
                    "type": "string",
                    "minLength": 1,
                    "description": "动画名,用于播放/查找。",
                },
                "frames": {
                    "type": "array",
                    "description": "有序帧 key 数组。每个 key 应能在合并后的 frames 表中查到。",
                    "minItems": 1,
                    "items": {"type": "string", "minLength": 1},
                },
                "direction": {
                    "enum": ["forward", "reverse", "pingpong"],
                    "description": "播放方向。缺省按 forward 处理。",
                },
                "repeat": {
                    "type": "integer",
                    "description": "循环次数。<=0 表示无限循环,N>=1 表示播放 N 次。",
                },
                "fps": {
                    "type": "integer",
                    "minimum": 1,
                    "description": "该动画的统一帧率提示。实际逐帧时长优先看 frame.duration。",
                },
                "pivot": {
                    "description": "该动画专用支点。缺省回退 meta.pivot。",
                    "$ref": "#/$defs/pivot",
                },
            },
        },
        "meta": {
            "type": "object",
            "description": "图集或入口 JSON 的元信息。",
            "additionalProperties": True,
            "properties": {
                "app": {"const": "sprite-gen", "description": "生成器标识。"},
                "version": {"type": "string", "description": "格式/生成器版本。"},
                "image": {"type": "string", "description": "当前 JSON 对应的图集 PNG 文件名。"},
                "format": {"type": "string", "description": "图集像素格式描述。"},
                "size": {"description": "当前图集 PNG 尺寸。", "$ref": "#/$defs/size"},
                "scale": {"type": "string", "description": "贴图缩放倍率字符串。"},
                "source_size_mode": {
                    "enum": ["canvas", "bbox-per-anim"],
                    "description": "sourceSize 计算策略,与生成配置 source_size_mode 对应。",
                },
                "pivot": {
                    "description": "通用支点。animation.pivot 缺省时回退到这里。",
                    "$ref": "#/$defs/pivot",
                },
                "relatedMultiPacks": {
                    "type": "array",
                    "description": "关联的其他 sheet JSON 文件列表,用于分页或多入口引用。",
                    "items": {"type": "string", "minLength": 1},
                    "uniqueItems": True,
                },
            },
        },
    },
}


CONFIG_PRIORITY_TEXT = (
    "`_user_anims.json`(动画级) > `_meta.json`(精灵级) > `config.json`(全局)"
)

LAYOUT_USAGE_TEXT = (
    "流式布局/普通图片序列播放只看元素盒子,不会自动理解 `meta.pivot`;"
    "这类播放/预览优先用 `source_size_mode=canvas`。游戏演出或需要精确切动作时,"
    "使用 absolute 布局,并按 `sourceSize + spriteSourceSize + meta.pivot` 应用支点。"
)


def _deep_merge(base, override):
    result = copy.deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _get_nested(data, dotted_key, default=None):
    cur = data
    for part in dotted_key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def _resolve_layout_value(layout, asset_type, key):
    specific = f"{key}@{asset_type}"
    if specific in layout:
        return layout[specific]
    return layout.get(key)


def _content_ratio(layout, prefer_legacy=False):
    if prefer_legacy and layout.get("char_ratio") is not None:
        value = layout.get("char_ratio")
    else:
        value = layout.get("content_ratio")
        if value is None:
            value = layout.get("char_ratio")
    value = float(value or 0.6)
    return max(0.01, min(value, 1.0))


def _normalize_frame_mode(value):
    mode = str(value or "F").strip().upper()
    return mode if mode in {"F", "K"} else "F"


def _normalize_source_size_mode(value):
    mode = str(value or "canvas").strip().lower()
    return mode if mode in {"canvas", "bbox-per-anim"} else "canvas"


def _normalize_video_generation_tier(value):
    tier = str(value or "fast").strip().lower()
    return tier if tier in VIDEO_GENERATION_TIERS else "fast"


def _resolve_value(cfg, key, asset_type):
    if key.startswith("ready_layout."):
        layout_key = key.split(".", 1)[1]
        layout = cfg.get("ready_layout", {}) or {}
        if layout_key in ("offset_ratio_x", "offset_ratio_y"):
            value = _resolve_layout_value(layout, asset_type, layout_key)
            return float(value or 0)
        if layout_key == "content_ratio":
            return _content_ratio(
                layout, prefer_legacy=bool(cfg.get("_prefer_legacy_char_ratio")))
    if key == "asset_type":
        return asset_type
    if key == "frame_mode":
        return _normalize_frame_mode(_get_nested(cfg, key))
    if key == "source_size_mode":
        return _normalize_source_size_mode(_get_nested(cfg, key))
    if key == "video_generation_tier":
        return _normalize_video_generation_tier(_get_nested(cfg, key))
    if key == "ready_pose":
        value = str(_get_nested(cfg, key) or "ground").strip().lower()
        return value if value in {"ground", "aerial"} else "ground"
    if key == "prompt_merge_negative":
        value = _get_nested(cfg, key)
        return True if value is None else bool(value)
    return _get_nested(cfg, key)


def _resolve_runtime_value(cfg, key, asset_type):
    if key == "video_expected_resolution":
        return _video_expected_resolution(cfg)
    return _resolve_value(cfg, key, asset_type)


def _format_value(value):
    if value is None:
        return "留空/自动"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        if value == "":
            return '""'
        return f'"{value}"' if value.isdigit() else value
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def load_effective_config(asset_type=None, sprite_work_dir=None):
    cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)

    meta = {}
    meta_path = None
    if sprite_work_dir:
        meta_path = os.path.join(sprite_work_dir, "_meta.json")
        if not os.path.isfile(meta_path):
            raise FileNotFoundError(
                f"--sprite-work-dir 指向的目录缺少 _meta.json: {meta_path}"
            )

    if meta_path:
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)

    prefer_legacy_char_ratio = (
        isinstance(meta.get("ready_layout"), dict) and
        meta["ready_layout"].get("char_ratio") is not None and
        meta["ready_layout"].get("content_ratio") is None
    )
    cfg = _deep_merge(cfg, meta)
    cfg["_prefer_legacy_char_ratio"] = prefer_legacy_char_ratio
    resolved_asset_type = str(
        asset_type or cfg.get("asset_type", "character") or "character"
    ).strip().lower()
    if resolved_asset_type not in {"character", "sequence"}:
        resolved_asset_type = "character"
    cfg["asset_type"] = resolved_asset_type
    return cfg, resolved_asset_type


def build_current_config_rows(asset_type=None, sprite_work_dir=None,
                              expanded_only=False):
    cfg, resolved_asset_type = load_effective_config(
        asset_type=asset_type, sprite_work_dir=sprite_work_dir)
    option_keys = {spec["key"] for spec in OPTION_SPECS}
    rows = []
    for spec in _all_config_specs():
        if expanded_only and spec["key"] not in option_keys:
            continue
        value = _resolve_value(cfg, spec["key"], resolved_asset_type)
        runtime_value = _resolve_runtime_value(cfg, spec["key"], resolved_asset_type)
        rows.append({
            "field": spec["key"],
            "label": CONFIG_LABELS.get(spec["key"], spec["key"]),
            "choices": spec["choices"],
            "value": value,
            "runtime_value": runtime_value,
            "expanded": spec["key"] in option_keys,
            "description": spec["desc"],
            "when_to_change": (
                spec.get("when_by_asset_type", {}).get(resolved_asset_type) or
                spec.get("when", "")
            ),
        })
    return resolved_asset_type, rows


def build_option_rows(asset_type=None, sprite_work_dir=None):
    return build_current_config_rows(
        asset_type=asset_type,
        sprite_work_dir=sprite_work_dir,
        expanded_only=True,
    )


def _all_config_specs():
    by_key = {}
    for spec in CONFIG_BASE_SPECS + OPTION_SPECS + CONFIG_TAIL_SPECS:
        by_key[spec["key"]] = spec
    return [by_key[key] for key in CONFIG_FIELD_ORDER]


def _format_static_default(cfg, key):
    if key in ("ready_layout.offset_ratio_x", "ready_layout.offset_ratio_y"):
        character_value = _resolve_value(cfg, key, "character")
        sequence_value = _resolve_value(cfg, key, "sequence")
        if character_value != sequence_value:
            return (
                f"character={_format_value(character_value)}; "
                f"sequence={_format_value(sequence_value)}"
            )
        return _format_value(character_value)
    return _format_value(_resolve_value(cfg, key, "character"))


def _format_static_when(spec):
    by_asset_type = spec.get("when_by_asset_type")
    if by_asset_type:
        parts = []
        for asset_type in ("character", "sequence"):
            if asset_type in by_asset_type:
                parts.append(f"{asset_type}: {by_asset_type[asset_type]}")
        return "; ".join(parts)
    return spec.get("when", "")


def build_config_rows():
    cfg, _ = load_effective_config(asset_type="character")
    option_keys = {spec["key"] for spec in OPTION_SPECS}
    rows = []
    for spec in _all_config_specs():
        rows.append({
            "field": spec["key"],
            "label": CONFIG_LABELS.get(spec["key"], spec["key"]),
            "default": _format_static_default(cfg, spec["key"]),
            "expanded": spec["key"] in option_keys,
            "choices": spec["choices"],
            "description": spec["desc"],
            "when_to_change": _format_static_when(spec),
        })
    return rows


def build_asset_type_rows():
    return [copy.deepcopy(spec) for spec in ASSET_TYPE_SPECS]


def build_config_payload():
    return {
        "config_priority": CONFIG_PRIORITY_TEXT,
        "config": build_config_rows(),
        "json_semantics": copy.deepcopy(JSON_SEMANTICS),
        "sheet_json_schema": SHEET_JSON_SCHEMA_REF,
        "layout_usage": LAYOUT_USAGE_TEXT,
    }


def print_asset_types(rows):
    print("素材类型选项:")
    for row in rows:
        print(
            f"- {row['asset_type']}: {row['label']}。适用: {row['applies_to']}。"
            f"缺省 pivot={row['pivot_default']}。执行指南: {row['guide']}。"
            f"{row['notes']}。"
        )


def print_current_config(asset_type, rows):
    print(f"当前配置(asset_type={asset_type}):")
    groups = [
        ("基础配置", [row for row in rows if not row["expanded"]]),
        ("更多选项", [row for row in rows if row["expanded"]]),
    ]
    for title, group_rows in groups:
        print(f"[{title}]")
        for row in group_rows:
            _print_current_config_row(row)


def _print_current_config_row(row):
        runtime_note = ""
        if row["runtime_value"] != row["value"]:
            runtime_note = f"; 生成用 {_format_value(row['runtime_value'])}"
        print(
            f"- {row['label']} ({row['field']}): {_format_value(row['value'])}"
            f"{runtime_note}; 可选 {row['choices']}。"
            f"{row['description']}。{row['when_to_change']}。"
        )


def print_config(payload):
    print("配置字段:")
    print(f"配置优先级: {payload['config_priority']}")
    for row in payload["config"]:
        expanded = "是" if row["expanded"] else "否"
        print(
            f"- {row['label']} ({row['field']}): 缺省 {row['default']}; 展开项={expanded}; "
            f"可选 {row['choices']}。{row['description']}。{row['when_to_change']}。"
        )
    print()
    print("图集 JSON 语义:")
    for row in payload["json_semantics"]:
        print(f"- {row['key']}: {row['desc']}。")
    print()
    print(f"sheet.json schema: {payload['sheet_json_schema']}")
    print(payload["layout_usage"])


def render_asset_types_markdown():
    lines = [
        "# 素材类型(asset_type)",
        "",
        "> 本文件由 sprite-gen 内部生成脚本生成;不要手工修改。",
        "",
        "| asset_type | 类型 | 适用场景 | 缺省 pivot | 执行指南 | 说明 |",
        "|------------|------|----------|------------|----------|------|",
    ]
    for row in build_asset_type_rows():
        lines.append(
            f"| {row['asset_type']} | {row['label']} | {row['applies_to']} | "
            f"{row['pivot_default']} | `{row['guide']}` | {row['notes']} |"
        )
    lines.extend([
        "",
        "无法判断素材类型时,只问用户选择 `character` 或 `sequence`,不要继续跑脚本。",
        "",
    ])
    return "\n".join(lines)


def render_config_options_markdown():
    payload = build_config_payload()
    lines = [
        "# 配置字段与图集语义",
        "",
        "> 本文件由 sprite-gen 内部生成脚本生成;不要手工修改。",
        "",
        f"配置优先级: {payload['config_priority']}",
        "",
        "静态缺省值来自 `config.json` 和生成脚本的隐式 fallback。已有精灵工作目录时,当前值可能被 `_meta.json` 覆盖;需要展示给用户时运行 `python3 scripts/describe_options.py --sprite-work-dir {work_dir}/{精灵名}`。",
        "",
        "| 名称 | 缺省值 | 展开项 | 取值 | 说明 | 何时调整 |",
        "|------|--------|--------|------|------|----------|",
    ]
    for row in payload["config"]:
        expanded = "是" if row["expanded"] else "否"
        lines.append(
            f"| {row['label']} ({row['field']}) | {row['default']} | {expanded} | {row['choices']} | "
            f"{row['description']} | {row['when_to_change']} |"
        )

    lines.extend([
        "",
        "## 图集 JSON 语义",
        "",
    ])
    for row in payload["json_semantics"]:
        lines.append(f"- `{row['key']}`: {row['desc']}。")
    lines.extend([
        "",
        "## sheet.json schema",
        "",
        payload["sheet_json_schema"],
        "",
    ])
    lines.extend([payload["layout_usage"], ""])
    return "\n".join(lines)


def write_refs():
    skill_dir = os.path.dirname(os.path.dirname(__file__))
    refs_dir = os.path.join(skill_dir, "refs")
    os.makedirs(refs_dir, exist_ok=True)
    outputs = {
        "asset_types.md": render_asset_types_markdown(),
        "config_options.md": render_config_options_markdown(),
        "spritesheet.schema.json": json.dumps(
            SPRITESHEET_SCHEMA, ensure_ascii=False, indent=2),
    }
    written = []
    for name, content in outputs.items():
        path = os.path.join(refs_dir, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        written.append(path)
    return written


def main():
    parser = argparse.ArgumentParser(
        description="Print current effective sprite-gen config")
    parser.add_argument("--asset-type", choices=["character", "sequence"], default=None)
    parser.add_argument("--sprite-work-dir", default=None,
                        help="{work_dir}/{精灵名}, contains _meta.json")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args()

    core_args = [
        ("--asset-type", args.asset_type is not None),
        ("--sprite-work-dir", bool(args.sprite_work_dir)),
    ]
    selected = [name for name, enabled in core_args if enabled]
    if len(selected) != 1:
        parser.error(
            "请选择且只选择一个核心参数: "
            "--asset-type <character|sequence>（新精灵/按类型查看）, "
            "--sprite-work-dir {work_dir}/{精灵名}（已有精灵,读取 _meta.json）。"
        )

    try:
        asset_type, rows = build_current_config_rows(
            asset_type=args.asset_type, sprite_work_dir=args.sprite_work_dir)
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    payload = {
        "asset_type": asset_type,
        "config_priority": CONFIG_PRIORITY_TEXT,
        "config": rows,
    }

    if args.format == "json":
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    print_current_config(payload["asset_type"], payload["config"])


if __name__ == "__main__":
    main()
