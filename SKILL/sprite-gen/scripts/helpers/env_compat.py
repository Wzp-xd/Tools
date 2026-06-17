"""环境兼容模块:工作区定位 + ASCII 临时目录 + 环境设置。"""
import os
import shutil
import tempfile


def ensure_utf8():
    os.environ.setdefault("PYTHONUTF8", "1")


def find_workspace_root():
    """定位工作区根目录。

    策略:
    1. TapMaker 容器:上层目录是 /home/Maker → 直接用 /workspace
    2. 非 TapMaker:往上找含 .claude / .maker / .codex 的目录
    3. 都找不到:返回 cwd
    """
    # TapMaker 容器检测
    if os.path.isdir("/home/Maker"):
        return "/workspace"

    # 非 TapMaker:往上找标记目录
    d = os.path.dirname(os.path.abspath(__file__))
    markers = (".claude", ".maker", ".codex", ".git")
    for _ in range(10):
        if any(os.path.isdir(os.path.join(d, m)) for m in markers):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.getcwd()


def resolve_output_dir(config_output_dir):
    """将 config.json 的 output_dir(相对于工作区根)解析为绝对路径。

    工作区根 + output_dir,不管什么环境都一样。
    """
    root = find_workspace_root()
    return os.path.normpath(os.path.join(root, config_output_dir))


def ascii_workdir(name="sprite_work"):
    """返回一个 ASCII 路径的临时工作目录(cv2 安全)。已存在则清空重建。"""
    d = os.path.join(tempfile.gettempdir(), name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    return d


def copy_back(src, dst):
    """把 ASCII 目录结果拷回 unicode 目标路径。"""
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def is_cloud():
    """是否在 TapMaker 云端容器中运行。"""
    return os.path.isdir("/home/Maker")


import base64 as _b64

_PLATFORM_URLS = {
    "production": b"aHR0cHM6Ly9tYWtlci50YXB0YXAuY24=",
    "default": b"aHR0cHM6Ly9mdXBpbmcuYWdudC54ZC5jb20=",
}
_ENV_CFG_PATH = b"ZGlzdC9lbnYuanNvbg=="
_PREVIEW_DIR = b"YXNzZXRzL2ltYWdl"


def _get_platform_base():
    """返回平台域名。"""
    import json
    root = find_workspace_root()
    env_file = os.path.join(root, _b64.b64decode(_ENV_CFG_PATH).decode())
    env = "default"
    try:
        with open(env_file, encoding="utf-8") as f:
            env = json.load(f).get("env", "default")
    except Exception:
        pass
    key = env if env in _PLATFORM_URLS else "default"
    return _b64.b64decode(_PLATFORM_URLS[key]).decode()


def cloud_preview_url(src_path, char_name, anim_id):
    """云端环境:拷贝预览文件并返回平台 URL。非云端返回 None。"""
    if not is_cloud():
        return None

    root = find_workspace_root()
    preview_rel = _b64.b64decode(_PREVIEW_DIR).decode()
    preview_dir = os.path.join(root, preview_rel)
    os.makedirs(preview_dir, exist_ok=True)

    ext = os.path.splitext(src_path)[1]
    unique_name = f"{char_name}_{anim_id}_frames_preview{ext}"
    dst = os.path.join(preview_dir, unique_name)
    shutil.copy2(src_path, dst)

    import urllib.parse
    rel_path = f"{preview_rel}/{unique_name}"
    encoded = urllib.parse.quote(rel_path)

    try:
        with open("/etc/hostname", "r") as f:
            app_uuid = f.read().strip()
    except Exception:
        return None

    import time as _time
    ts = int(_time.time() * 1000)
    base = _get_platform_base()
    return f"{base}/api/v1/apps/{app_uuid}/files?path={encoded}&t={ts}"
