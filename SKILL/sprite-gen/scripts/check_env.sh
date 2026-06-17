#!/bin/bash
# check_env.sh — 检测 Python + 依赖,缺失自动补装
# Linux/Mac/容器通用

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. 检测系统 python
if command -v python3 &>/dev/null; then
    PY=python3
elif command -v python &>/dev/null; then
    PY=python
else
    echo "❌ Python not found. Install Python 3.10+ first."
    exit 1
fi

echo "Python: $($PY --version) ($PY)"

# 2. 跑依赖检测
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec $PY "$SCRIPT_DIR/check_env.py"
