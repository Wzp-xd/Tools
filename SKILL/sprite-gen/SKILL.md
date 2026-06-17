---
name: sprite-gen
description: 从一张角色图生成 2D 游戏透明精灵表(序列帧)。当用户说"生成序列帧"、"做精灵表"、"生成动画帧"、"sprite gen"、"角色动画生成"、"图生序列帧"、"做sprite"时使用此技能。
---

# 2D 角色动画生成

从一张角色设定图生成游戏可用的透明精灵表(图集 PNG + 配置 JSON + WebP 动画预览)。

## 你的职责

你是执行者。按下面的流程调脚本、跟用户交互。★ 标记的地方停下来问用户。

## 铁律

1. **所有 prompt 必须通过脚本合成。**
2. **不许自己调 `scripts/helpers/` 里的任何东西。** 只调入口脚本。

## 开始前

精灵生成是独立任务(耗时长、多次交互),不要用 subagent。向用户提示:
```
建议新开一个会话来执行精灵生成,避免占用当前对话上下文。
如需新开,复制以下内容发给新会话:

---
请使用 sprite-gen 技能,为我生成精灵序列帧。
角色图: [粘贴路径或拖入]
角色名: [填写]
---
```

用户选择在当前会话继续 → 根据意图判断起点:
- 用户给了新角色图 / 要做新精灵 → 从步骤0 开始
- 用户说"继续做 xxx" / "接着上次的" → 读 `{work_dir}/{角色名}/_progress.json`,从对应步骤继续

**每步完成后更新进度:**
```bash
python3 scripts/update_progress.py <角色目录> --step <步骤号> --status done
```

### 0. 环境检查(首次)

```bash
# Linux/Mac/容器
bash scripts/check_env.sh

# Windows
scripts\check_env.bat
```
自动检测 Python + 依赖,缺失自动补装。

### 1. ★ 收集输入

一次性问用户:
- 角色设定图(路径或拖入)
- 角色名

视角选项(逐字展示,不许改/加/删):
```
角色图需要怎么处理?(建议右侧视)
1. 不用动 / 原图已朝向右侧
2. 侧视朝左,翻转成朝右                 [CLI: --flip]
3. 转成纯侧视朝右                      [AI: 转视角]
4. (推荐) 右侧视,上身侧面下身微转露双腿 (Cheated profile) [AI: 转视角]
```

导出参数(逐字展示,不许改/加/删,用户不改则用默认):
```
输出精灵高度: ___px  [默认 256](角色实际内容高度,不含透明边距)
帧模式: F(全帧24fps) / K(关键姿态抽帧)  [默认 F]
```

可选:用户指定画风 → `--art-style "..."`

### 2. 预处理

```bash
python3 scripts/prepare_ready_image.py <角色图> --char-name <角色名> --option <1-4> --target-height <高度> --frame-mode <F/K>
```

脚本输出 `_gen_images/ready.png` + `_meta.json`(含所有配置一次写全)。

### 3. [条件] AI 转视角/换幕布

**脚本输出 `_gen_images/ready.prompt.txt` 时:**
- 读取提示词,用 ready.png 作参考图,调用图像生成 **2 次**(cnt 递增):
  - MCP: 优先 `edit_image`,效果不行再换 `generate_image`
- 展示候选给用户,**必须逐字附上以下评判标准**(不许省略/改写):
  ```
  选哪张?对照以下标准:
  1. 严格朝右侧面
  2. 双腿分开可见,不互相遮挡
  3. 肢体轮廓清晰,无截断
  4. 中性站姿(非动作姿态)
  5. 背景是指定的幕布色(纯色均匀,无渐变、无阴影、无杂物)
  6. 比例正常,无变形
  ```
- 用户选 → 将选中的复制为 `_gen_images/ready.png`

**无 `ready.prompt.txt` 时:** 直接下一步。

### 4. ★ 选角色类型 + 动画清单

能从上下文(角色图、角色名、对话历史)判断类型时,直接给出判断 + 推荐清单,同时附上其他类型供用户改选。无法判断时再让用户选:

| 类型 | 推荐动画 |
|------|---------|
| humanoid | idle, walk, run, jump, attack, hurt |
| bird | fly_flap, dash, peck, ground_idle, run, hurt |
| slime | idle, bounce_move, blob_attack, hurt |
| beast | idle, run, pounce, roar, hurt |
| other | idle, move, attack, hurt |

用户增删确定清单。可自定义动画(id 自由命名)。每个动画可选填 `duration`(视频秒数),不填用默认。

Agent 按 `refs/action_guide.md` 规则写 action 描述。保存为 `{角色目录}/_user_anims.json`:
```json
[
  {"id": "idle", "play_type": "loop", "action": "stands on the ground, body slightly swaying with a lively breathing rhythm"},
  {"id": "attack", "play_type": "once", "action": "throws a devastating punch forward", "duration": "10"}
]
```

### 5. [条件] 姿态缺口检测

```bash
python3 scripts/build_pose_prompt.py <角色目录> <角色目录>/_user_anims.json
```

**输出 `_gen_images/{姿态}.prompt.txt` 时:**
- 对每条提示词,用 ready.png 调图像生成 2 次,附标准让用户对照选择:
  ```
  选哪张?对照以下标准:
  1. 姿态与目标动画匹配
  2. 角色外观一致(脸/服装没变)
  3. 背景纯净无杂物
  4. 无多余肢体或物件
  ```
- 用户选 → 复制为 `_gen_images/{姿态}.png`

**无输出时:** 直接下一步。

### 6. 组装视频提示词

```bash
python3 scripts/build_video_prompt.py <角色目录> <角色目录>/_user_anims.json
```

输出 `_gen_videos/{动画id}/anim.prompt.json`(含 prompt/ref_image/duration)。

**Agent 审核:** 读各 `anim.prompt.json` 检查提示词是否合理。需调整 → 改 `_user_anims.json` 重跑。

### 7. ★ 逐一执行

对动画清单中的每个动画,循环以下 4 步:

**a. 生成视频**(从 `anim.prompt.json` 读 prompt/ref_image/duration):
- MCP: `create_video_task`,比例 1:1 → 搬到 `_gen_videos/{id}/anim.mp4`

**b. ★ 审核视频**

展示视频给用户,附审核要点(✅ 通过 / 🔄 重新生成):
```
1. 动作符合用户要求,匹配目标动画
2. 幕布色全程保持不变且纯净均匀(无渐变、无阴影、无多余物件)
3. 角色无明显变形/模糊/融化
4. 相机无移动(角色始终居中)
```

**c. 转序列帧**

```bash
python3 scripts/video_to_sprites.py <角色目录> --anims <动画id>
```

**d. ★ 验收精灵表**

脚本输出预览信息:云端输出 markdown 图片链接(直接贴入回复),本地输出文件路径(用系统默认浏览器打开给用户看)。

展示 `frames_preview.webp` + 脚本输出的验收清单(✅ 通过 / 🔄 重做此动画):
```
[自动检测]
✅/⚠️ sourceSize 一致
✅/⚠️ 背景透明
✅/⚠️ 图集每页 ≤ max_sheet_size
✅/⚠️ JSON 帧数一致
✅/⚠️ 无帧出框

[需审查(查看 frames_preview.webp)]
☐ 朝向正确
☐ 节奏流畅
☐ 尺寸稳定
☐ 边缘无 key 色残留
```

### 8. 完成确认

全部动画完成后,更新进度:
```bash
python3 scripts/update_progress.py <角色目录> --step 8 --status done
```

## 重做/续做

- **重做某个动画:** 改 `_user_anims.json` 里的 action → 从步骤6 重跑
- **增加新动画:** 往 `_user_anims.json` 追加新条目(不动已有的)→ 从步骤5 继续(只对新动画走姿态检测→提示词→生成)
- **改导出参数:** 改 `_meta.json` 的 target_height/frame_mode → 重跑 `video_to_sprites.py`

## 产出结构

```
{work_dir}/{角色名}/                    ← 精灵工作目录
├── _meta.json
├── _progress.json
├── _user_anims.json
├── _gen_images/
│   ├── ready.png
│   ├── ready.prompt.txt
│   └── ready_cand_{cnt}.png
├── _gen_videos/
│   ├── idle/
│   │   ├── anim.prompt.json
│   │   ├── anim.mp4
│   │   ├── frames/
│   │   │   └── frame_*.png
│   │   └── frames_preview.webp
│   └── ...

{output_dir}/{角色名}/                  ← 最终精灵表
├── idle/
│   ├── spritesheet.json + .png         (首页无编号)
│   ├── spritesheet-1.json + .png       (如有分页,relatedMultiPacks 关联)
│   └── ...
└── ...

assets/image/                           ← 云端精灵预览(脚本自动生成,仅云端环境)
├── {角色名}_{动画id}_frames_preview.webp
└── ...
```

## 配置(config.json)

| 字段 | 默认 | 说明 |
|------|------|------|
| work_dir | .build/sprite-gen | 精灵工作目录(配置/提示词/中间产物) |
| output_dir | assets/sprites | 最终精灵表目录 |
| target_height | 256 | 精灵表角色像素高度 |
| fps | 24 | 帧率 |
| frame_mode | F | F=全帧 / K=关键姿态抽帧 |
| max_sheet_size | 2048 | 单页图集上限 |
| video_duration | "5" | 视频秒数 |
| video_prompt_strength | 0.7 | 视频 prompt 约束强度 |
| prompt_merge_negative | true | 反向提示词合并进正向(true)还是独立字段(false) |
| chroma_strength | 1.5 | 色差键抠除强度 |
| chroma_edge_shrink | 1 | alpha 边缘内缩像素 |
| detect_min_cycle_frames | 10 | 循环检测最小帧数 |
| detect_padding_frames | 3 | 峰值隔离前后留帧 |
| preview_format | webp | 预览格式 |

**配置优先级:** `_user_anims.json(动画级)` > `_meta.json(角色级)` > `config.json(全局)`

## 脚本一览

| 脚本 | 职责 |
|------|------|
| `prepare_ready_image.py` | 选色+合成+flip+输出转视角提示词+写 _meta.json |
| `build_pose_prompt.py` | 姿态缺口检测+输出姿态提示词 |
| `build_video_prompt.py` | 组装视频提示词(模板+negative+ref_image+duration) |
| `video_to_sprites.py` | 拆帧+循环检测+抠图+精灵表导出+验收清单 |
| `check_env.py/.sh/.bat` | 环境检测+依赖补装 |
| `update_progress.py` | 更新步骤进度(_progress.json) |

## 依赖

- Python 3.10+(通过步骤0 check_env 自动检测)
- MCP 工具: edit_image / create_video_task(图像/视频生成)
