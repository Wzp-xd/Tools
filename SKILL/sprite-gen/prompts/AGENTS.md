# prompts/ — Prompt 模板铁律

## 绝对禁止

- **不许改动模板里的任何措辞**。"strict side-view profile facing right" 不许换成 "keep same orientation"、"面朝右" 或任何"意思差不多"的写法。
- 不许删掉任何一行约束(包括 "no turning"、"Mouth closed"、negative 里的视角词)。
- **不许在模板以外的地方自己手写 prompt 字符串**。所有 prompt(包括视频生成和转侧视)必须通过 `prompt_builder.py` 生成。
- **不许自己加风格词**(如 "clean flat"、"pixel art"、"game-sprite art style")。风格由 `{ART_STYLE}` 占位符控制——用户指定则填,未指定则缺省"保持原图风格"。

## 模板文件

| 文件 | 用途 | 占位符 |
|------|------|--------|
| `loop.txt` | 循环动画视频 prompt | `{动作描述}` `{KEY_COLOR}` |
| `once.txt` | 单次动画视频 prompt | `{动作描述}` `{KEY_COLOR}` |
| `attack.txt` | 攻击动画视频 prompt | `{动作描述}` `{KEY_COLOR}` |
| `side_view.txt` | 转侧视 edit_image prompt | `{ART_STYLE}` `{KEY_COLOR}` |
| `negative_base.txt` | 基础 negative(所有动画) | 无 |
| `negative_once.txt` | 单次追加 negative | 无 |
| `negative_attack.txt` | 攻击追加 negative | 无 |

## 占位符说明

| 占位符 | 来源 | 缺省 | 示例 |
|--------|------|------|------|
| `{动作描述}` | Agent 按 `refs/02-动画Prompt生成.md` 的规则写(1-2句,不描述外观) | 无缺省,必填 | `walks forward with exaggerated bouncy steps, body bobbing` |
| `{KEY_COLOR}` | `pick_key_color.py` 的输出(颜色英文名) | 无缺省,必填 | `magenta` |
| `{ART_STYLE}` | 用户指定的风格(如 "anime cel-shading") | 未指定→自动填 "Keep the exact same art style, rendering and shading as the input image" | `pixel art` |

## 使用方式

```python
from helpers.prompt_builder import build_prompt, build_side_view_prompt

# 视频生成
prompt, neg = build_prompt(anim_id, play_type, action_desc, key_color_name)

# 转侧视
sv_prompt = build_side_view_prompt(key_color_name, art_style=None)  # None→保持原图风格
sv_prompt = build_side_view_prompt(key_color_name, art_style="anime cel-shading")  # 用户指定
```

`prompt_builder.py` 从 .txt 读模板 + 替换占位符。**Agent 绝不要绕过它直接拼字符串。**
