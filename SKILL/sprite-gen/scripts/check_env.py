#!/usr/bin/env python3
"""
check_env — 检测依赖环境,缺失的自动补装。

首次使用 sprite-gen 前跑一次即可。
如果容器镜像/venv 已预装全部依赖,本脚本秒过(全 ✅)。

不创建 venv、不管 Python 怎么来的——只检测+补装缺失包。
"""
import importlib
import subprocess
import sys

REQUIRED = [
    ("numpy", "numpy"),
    ("cv2", "opencv-python"),
    ("PIL", "Pillow"),
    ("scipy", "scipy"),
    ("skimage", "scikit-image"),
    ("imagehash", "imagehash"),
]


def check_and_install():
    missing = []
    for import_name, pip_name in REQUIRED:
        try:
            m = importlib.import_module(import_name)
            v = getattr(m, "__version__", "?")
            print(f"  ✅ {pip_name} {v}")
        except ImportError:
            missing.append((import_name, pip_name))
            print(f"  ❌ {pip_name} — missing")

    if not missing:
        print("\nAll dependencies ready.")
        return True

    print(f"\nInstalling {len(missing)} missing package(s)...")
    pip_names = [p for _, p in missing]
    cmd = [sys.executable, "-m", "pip", "install"] + pip_names
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"\n❌ pip install failed:")
        print(result.stderr[-500:] if result.stderr else result.stdout[-500:])
        print(f"\nTry manually: {sys.executable} -m pip install {' '.join(pip_names)}")
        return False

    # Verify
    print("\nVerifying...")
    all_ok = True
    for import_name, pip_name in missing:
        try:
            importlib.import_module(import_name)
            print(f"  ✅ {pip_name} installed")
        except ImportError:
            print(f"  ❌ {pip_name} still missing!")
            all_ok = False

    if all_ok:
        print("\nAll dependencies ready.")
    else:
        print("\nSome packages failed to install. Check errors above.")
    return all_ok


if __name__ == "__main__":
    print(f"Python: {sys.executable} ({sys.version.split()[0]})")
    print(f"Checking dependencies...\n")
    ok = check_and_install()
    sys.exit(0 if ok else 1)
