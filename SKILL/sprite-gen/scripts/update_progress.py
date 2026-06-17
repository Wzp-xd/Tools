#!/usr/bin/env python3
"""
update_progress — 更新角色工作目录的 _progress.json

用法:
  python3 scripts/update_progress.py <角色目录> --step <步骤号> --status <状态> [--detail "..."]

示例:
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 2 --status done
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 8 --status done --detail "idle,walk completed"
  python3 scripts/update_progress.py .build/sprite-gen/Tarara --step 8 --status in_progress --detail "idle done, walk pending"
"""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser(description="更新 _progress.json")
    ap.add_argument("char_dir", help="角色工作目录")
    ap.add_argument("--step", type=int, required=True, help="当前步骤号(0-9)")
    ap.add_argument("--status", required=True, choices=["done", "in_progress", "failed"], help="状态")
    ap.add_argument("--detail", default="", help="补充说明")
    args = ap.parse_args()

    progress_path = os.path.join(args.char_dir, "_progress.json")

    # 读已有(如有)
    if os.path.exists(progress_path):
        progress = json.load(open(progress_path, encoding="utf-8"))
    else:
        progress = {"steps": {}}

    # 更新
    progress["current_step"] = args.step
    progress["current_status"] = args.status
    progress["steps"][str(args.step)] = {"status": args.status, "detail": args.detail}

    with open(progress_path, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)

    print(f"_progress.json: step={args.step} status={args.status}")


if __name__ == "__main__":
    main()
