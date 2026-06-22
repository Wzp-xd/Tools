#!/usr/bin/env python3
"""
update_progress — 更新资产工作目录的 _progress.json

用法:
  python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status <状态> [--detail "..."]
  python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status <状态> --next-step <步骤号> --next-action "..."
  python3 scripts/update_progress.py {work_dir}/{精灵名} --step 7 --status in_progress --gate video_review --decision approved --anim idle --artifact "_gen_videos/idle/anim.mp4"

示例:
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 2 --status done
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 8 --status done --detail "idle,walk completed"
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 8 --status in_progress --detail "idle done, walk pending"
"""
import argparse
import datetime as _dt
import json
import os


ASSET_TYPE_FALLBACK = "character"

FLOW_LABELS = {
    "character": "角色/对象动画流程",
    "sequence": "非角色序列帧流程",
}

CHARACTER_STEP_LABELS = {
    0: "环境检查",
    1: "收集输入",
    2: "预处理 ready.png",
    3: "AI 转视角/换幕布",
    4: "选角色类型和动画清单",
    5: "姿态缺口检测",
    6: "组装视频提示词",
    7: "逐一生成/审核/导出动画",
    8: "完成确认",
}

SEQUENCE_STEP_LABELS = {
    0: "环境检查",
    1: "收集输入",
    2: "预处理 ready 图",
    4: "选动画清单",
    6: "组装视频提示词",
    7: "逐一执行动画",
    8: "完成确认",
}

STEP_LABELS_BY_ASSET_TYPE = {
    "character": CHARACTER_STEP_LABELS,
    "sequence": SEQUENCE_STEP_LABELS,
}

CHARACTER_GATE_LABELS = {
    "session": "是否新开会话",
    "input": "步骤1 输入确认",
    "ready_image": "步骤3 ready 图候选确认",
    "animation_list": "步骤4 动画清单确认",
    "pose_image": "步骤5 姿态图候选确认",
    "video_review": "步骤7b 视频审核",
    "spritesheet_review": "步骤7d 精灵表验收",
}

SEQUENCE_GATE_LABELS = {
    "session": "是否新开会话",
    "input": "步骤1 输入确认",
    "ready_image": "步骤2 素材候选确认",
    "animation_list": "步骤4 动画清单确认",
    "pose_image": "步骤2 素材候选确认",
    "video_review": "步骤7b 视频审核",
    "spritesheet_review": "步骤7d 精灵表验收",
}

GATE_LABELS_BY_ASSET_TYPE = {
    "character": CHARACTER_GATE_LABELS,
    "sequence": SEQUENCE_GATE_LABELS,
}

GATE_KEYS = sorted(CHARACTER_GATE_LABELS)


def _now():
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")


def _normalize_asset_type(value):
    if value == "sequence":
        return "sequence"
    return ASSET_TYPE_FALLBACK


def _load_asset_type(asset_dir):
    meta_path = os.path.join(asset_dir, "_meta.json")
    if not os.path.exists(meta_path):
        return ASSET_TYPE_FALLBACK
    try:
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, json.JSONDecodeError):
        return ASSET_TYPE_FALLBACK
    return _normalize_asset_type(meta.get("asset_type"))


def _step_label(asset_type, step):
    labels = STEP_LABELS_BY_ASSET_TYPE.get(asset_type, CHARACTER_STEP_LABELS)
    return labels.get(step, f"步骤{step}")


def _gate_label(asset_type, gate):
    labels = GATE_LABELS_BY_ASSET_TYPE.get(asset_type, CHARACTER_GATE_LABELS)
    return labels.get(gate, gate)


def _load_progress(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = {}
    data.setdefault("schema_version", 2)
    data.setdefault("steps", {})
    data.setdefault("confirmation_gates", {})
    data.setdefault("animations", {})
    return data


def _artifact_list(values):
    if not values:
        return []
    out = []
    for value in values:
        for item in value.split(","):
            item = item.strip()
            if item:
                out.append(item)
    return out


def main():
    ap = argparse.ArgumentParser(description="更新 _progress.json")
    ap.add_argument("asset_dir", help="{work_dir}/{精灵名}")
    ap.add_argument("--step", type=int, required=True, help="当前步骤号(0-9)")
    ap.add_argument("--status", required=True, choices=["done", "in_progress", "failed"], help="状态")
    ap.add_argument("--detail", default="", help="补充说明")
    ap.add_argument("--next-step", type=int, default=None, help="建议下一步步骤号")
    ap.add_argument("--next-action", default="", help="给下一轮 AI/用户看的下一步说明")
    ap.add_argument("--gate", choices=GATE_KEYS, help="本次更新对应的人工确认点")
    ap.add_argument("--decision", choices=["pending", "confirmed", "approved", "rejected", "redo", "skipped"],
                    help="人工确认点结果")
    ap.add_argument("--anim", "--anim-id", dest="anim_id", default=None, help="动画 id,如 idle/walk/attack")
    ap.add_argument("--artifact", action="append", default=[], help="与本次确认相关的产物路径,可重复或用逗号分隔")
    args = ap.parse_args()

    asset_type = _load_asset_type(args.asset_dir)
    flow_label = FLOW_LABELS[asset_type]
    progress_path = os.path.join(args.asset_dir, "_progress.json")
    now = _now()
    label = _step_label(asset_type, args.step)
    artifacts = _artifact_list(args.artifact)

    progress = _load_progress(progress_path)
    progress["schema_version"] = 2
    progress["asset_type"] = asset_type
    progress["flow_label"] = flow_label

    # 兼容旧字段,同时写入更易读的新结构。
    progress["current_step"] = args.step
    progress["current_status"] = args.status
    progress["current"] = {
        "step": args.step,
        "label": label,
        "asset_type": asset_type,
        "flow_label": flow_label,
        "status": args.status,
        "detail": args.detail,
        "updated_at": now,
    }
    progress["steps"][str(args.step)] = {
        "label": label,
        "asset_type": asset_type,
        "flow_label": flow_label,
        "status": args.status,
        "detail": args.detail,
        "updated_at": now,
    }

    if args.next_step is not None or args.next_action:
        next_step = args.next_step if args.next_step is not None else args.step
        progress["next_action"] = {
            "step": next_step,
            "label": _step_label(asset_type, next_step),
            "asset_type": asset_type,
            "flow_label": flow_label,
            "summary": args.next_action,
        }

    if args.gate:
        gate_entry = {
            "label": _gate_label(asset_type, args.gate),
            "decision": args.decision or "pending",
            "step": args.step,
            "asset_type": asset_type,
            "flow_label": flow_label,
            "detail": args.detail,
            "artifacts": artifacts,
            "updated_at": now,
        }
        progress["confirmation_gates"][args.gate] = gate_entry

        if args.anim_id:
            anim_entry = progress["animations"].setdefault(args.anim_id, {})
            anim_entry[args.gate] = gate_entry
            anim_entry["updated_at"] = now

    with open(progress_path, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)

    print(f"_progress.json: asset_type={asset_type} flow={flow_label} step={args.step} status={args.status} label={label}")
    if args.gate:
        print(f"gate: {args.gate} decision={args.decision or 'pending'} anim={args.anim_id or '-'}")


if __name__ == "__main__":
    main()
