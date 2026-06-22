---
name: sprite-gen
description: 从角色图、对象图或非角色素材图生成 2D 游戏透明精灵表(序列帧)。当用户说"生成序列帧"、"做精灵表"、"生成动画帧"、"sprite gen"、"角色动画生成"、"图生序列帧"、"非角色序列帧"、"做sprite"时使用此技能。
---

# 2D 精灵序列帧生成

生成游戏可用的透明精灵表(图集 PNG + 配置 JSON + WebP 动画预览)。素材类型和配置字段说明是静态 refs,需要时再读取:
- 素材类型: `refs/asset_types.md`
- 配置字段与图集语义: `refs/config_options.md`

## 你的职责

你是执行者。先处理会话门禁和流程选择,再只读取并执行对应流程指南。★ 标记的地方必须停下来问用户。

## 铁律

1. **触发本 skill 后,第一件事必须处理"是否新开会话"。** 除非用户在同一条最新消息中明确说"已新开会话/就在当前会话继续/不要新开",否则先停下来询问用户,不能开始生成、跑脚本或调用 MCP。
2. **流程必须先分流再执行。** `character` 与 `sequence` 的步骤互相独立;选定流程后只执行该流程指南,不得把另一条流程的步骤混进来。
3. **所有 prompt 必须通过脚本合成。**
4. **不许自己调 `scripts/helpers/` 里的任何东西。** 只调入口脚本。
5. **起点定位和用户审核都是硬门禁。** 按下面的"首轮强制回复 / 流程选择 / 起点门禁 / 人工确认规则"处理,不得静默运行完整流程。
6. **只能在已选流程指南定义的步骤入口继续。** 不得自造流程,不得直接从用户需求跳到 MCP 生成、拆帧或最终导出。

## 开始前

精灵生成是独立任务(耗时长、多次交互),不要用 subagent。向用户提示:
```
建议新开一个会话来执行精灵生成,避免占用当前对话上下文。
如需新开,复制以下内容发给新会话:

---
请使用 sprite-gen 技能,为我生成精灵序列帧。
我已新开会话,请在当前会话继续执行,不要再次询问是否新开会话。
素材类型: [角色/对象动画 或 非角色序列帧]
素材参考图: [粘贴路径或拖入]
精灵名: [填写]
---
```

**首轮强制回复:**
- 如果用户最新消息没有明确写"已新开会话/就在当前会话继续/不要新开",回复只能包含上面的新开会话提示,并以这一句结尾: `要新开会话,还是在当前会话继续?`
- 发出首轮强制回复后立即停止,等待用户选择。不得补充计划,不得收集参数,不得跑脚本,不得调用 MCP。

## 流程选择

先确定 `asset_type`,再进入对应指南。已有 `_meta.json` 时以 `_meta.json.asset_type` 为准;缺失时按用户输入判断。素材类型的静态说明和执行指南映射见 `refs/asset_types.md`。

选定流程后,只读取并执行 `refs/asset_types.md` 中对应的执行指南。无法判断时,只问用户选择 `character` 或 `sequence`,不要继续跑脚本。

## 起点门禁

恢复或续做时:

1. 先读 `{work_dir}/{精灵名}/_meta.json` 和 `{work_dir}/{精灵名}/_progress.json`。
2. 用 `_meta.json.asset_type` 选择 `refs/character_guide.md` 或 `refs/sequence_guide.md`。
3. 只按已选指南里的起点门禁定位下一步。
4. `_progress.json` 或当前对话没有明确记录用户确认时,对应 ★ 审核点一律视为未确认。

用户要求给已有精灵直接做某个具体动画/序列时,也只能按已选流程指南定位起点;该条目必须进入用户确认过的清单,不得直接跳到视频生成、拆帧或导出。

## 人工确认规则

- 每个 ★ 确认点都必须展示产物、审核标准和可选动作。
- "继续/直接做/你看着办"不等于审核通过。
- 用户要求跳过审核时,也只能压缩说明;★ 确认点仍必须给出产物链接/路径、标准清单和一次确认机会。
- 恢复流程时,只有当前对话或 `_progress.json.confirmation_gates` / `_progress.json.animations` 明确记录了用户确认,才算已确认。

## 进度记录

进度记录统一从 `prepare_ready_image.py` 成功写出 `{work_dir}/{精灵名}/_meta.json` 后开始。步骤0/1不调用 `update_progress.py`;预处理后先补记步骤1输入确认,再按实际产物记录步骤2状态。此后每步完成都更新进度。`update_progress.py` 会自行读取 `{work_dir}/{精灵名}/_meta.json.asset_type`,拼接对应流程的步骤文案:
```bash
python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status done
```

预处理后的公共记录模板如下。两条资产指南的步骤2只描述预处理和审核,不要重复粘贴这些命令:
```bash
# ready.png 已生成(character 或 sequence 透明输入)
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 1 --status done --gate input --decision confirmed --artifact _meta.json,_gen_images/ready.png --next-step 2 --next-action "预处理 ready 图"
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 2 --status done --artifact _gen_images/ready.png --next-step <下一步骤号> --next-action "<已选流程下一步>"

# 非透明输入: 已生成 cutout_ref/cutout.prompt,等待透明抠图审核
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 1 --status done --gate input --decision confirmed --artifact _meta.json,_gen_images/cutout_ref.png,_gen_images/cutout.prompt.txt --next-step 2 --next-action "生成并审核透明抠图"
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 2 --status in_progress --gate ready_image --decision pending --artifact _gen_images/cutout_ref.png,_gen_images/cutout.prompt.txt --next-action "生成并审核透明抠图"

# 透明抠图审核通过,并重跑得到 ready.png
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 2 --status done --gate ready_image --decision approved --artifact _gen_images/cutout.png,_gen_images/ready.png --next-step <下一步骤号> --next-action "<已选流程下一步>"
```

确认点完成时,同时记录 gate,让新会话能恢复:
```bash
# 清单已确认
python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status done --gate animation_list --decision confirmed --artifact _user_anims.json --next-step <下一步骤号> --next-action "继续已选流程的下一步"

# 某条视频审核通过
python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status in_progress --gate video_review --decision approved --anim <动画id> --artifact _gen_videos/<动画id>/anim.mp4 --next-action "转序列帧并导出精灵表"

# 某条精灵表验收通过
python3 scripts/update_progress.py {work_dir}/{精灵名} --step <步骤号> --status in_progress --gate spritesheet_review --decision approved --anim <动画id> --artifact _gen_videos/<动画id>/frames_preview.webp --next-action "继续下一个动画或完成流程"
```

`_progress.json` 是给 AI 恢复流程看的状态文件。关键字段:
```json
{
  "schema_version": 2,
  "asset_type": "character",
  "flow_label": "角色/对象动画流程",
  "current": {"step": 7, "label": "逐一生成/审核/导出动画", "status": "in_progress"},
  "next_action": {"step": 7, "summary": "继续下一个动画或完成步骤8"},
  "steps": {"4": {"label": "选角色类型和动画清单", "status": "done"}},
  "confirmation_gates": {
    "animation_list": {"decision": "confirmed", "artifacts": ["_user_anims.json"]}
  },
  "animations": {
    "idle": {
      "video_review": {"decision": "approved", "artifacts": ["_gen_videos/idle/anim.mp4"]},
      "spritesheet_review": {"decision": "approved", "artifacts": ["_gen_videos/idle/frames_preview.webp"]}
    }
  }
}
```

## 工作目录与输出目录

`work_dir` 是 sprite-gen 工作目录,用于保存配置、提示词、中间产物、参考图和预览。
`output_dir` 是游戏资产输出目录,最终精灵表写到这里。

不要根据素材路径推断或改写 `work_dir` / `output_dir`。步骤2运行 `prepare_ready_image.py` 后,记录脚本输出的 `work_dir`、`{work_dir}/{精灵名}`、`output_dir`、`{output_dir}/{精灵名}`。后续命令的目录参数直接使用 `{work_dir}/{精灵名}`;最终游戏资产输出目录使用 `{output_dir}/{精灵名}`。

## 产出结构

```
{work_dir}/{精灵名}/                    ← sprite-gen 工作目录下的本精灵子目录
├── _meta.json
├── _progress.json
├── _user_anims.json                   ← 兼容脚本命名;sequence 流程也使用此文件
├── _gen_images/
│   ├── ready.png
│   ├── ready.prompt.txt
│   ├── cutout_ref.png                  (非透明输入的抠图参考)
│   ├── cutout.prompt.txt               (非透明输入的抠图提示词)
│   ├── cutout_cand_{cnt}.png
│   ├── cutout.png
│   └── ready_cand_{cnt}.png
├── _gen_videos/
│   ├── <动画id>/
│   │   ├── anim.prompt.json
│   │   ├── anim.mp4
│   │   ├── frames/                    (临时中间帧,成功导出后自动清理)
│   │   ├── frames_key/                (K 模式临时中间帧,成功导出后自动清理)
│   │   └── frames_preview.webp
│   └── ...

{output_dir}/{精灵名}/                  ← 最终游戏资产输出目录
├── sprite.json                         (精灵入口;列各动画入口 spritesheet.json)
├── <动画id>/
│   ├── spritesheet.json + .png         (首页无编号)
│   ├── spritesheet-1.json + .png       (额外分页;由入口 relatedMultiPacks 关联)
│   └── ...
└── ...

assets/image/                           ← 云端精灵预览(脚本自动生成,仅云端环境)
├── {精灵名}_{动画id}_frames_preview.webp
└── ...
```

## 配置与图集语义

字段语义、静态缺省值、展开项、`sourceSize`/`pivot` 说明见 `refs/config_options.md`。自行开发播放器时再参考 `refs/spritesheet.schema.json`;普通生成/使用无需读取 schema。需要解释某字段时,用 `rg -n "<字段名>|sourceSize|pivot|schema" refs/config_options.md` 精确读取,不要整读长文档。

配置优先级: `_user_anims.json`(动画级) > `_meta.json`(精灵级) > `config.json`(全局)。

用户选择"展开更多选项"时,运行 `python3 scripts/describe_options.py --asset-type <character|sequence>`;如果已有 `{work_dir}/{精灵名}`,改用 `python3 scripts/describe_options.py --sprite-work-dir {work_dir}/{精灵名}`。`--asset-type` 与 `--sprite-work-dir` 两个对话流程入口互斥,不得同时传。脚本输出是给用户看的完整配置分组,必须原样展示,不得摘要、改写、过滤或只列字段名。

维护规则: `refs/asset_types.md` 和 `refs/config_options.md` 由 `scripts/describe_options.py` 内部同源生成;修改素材类型或配置字段元数据后必须重新生成。

## 脚本一览

| 脚本 | 职责 |
|------|------|
| `describe_options.py` | 输出当前有效配置,并为维护者生成静态 refs |
| `prepare_ready_image.py` | 选色+合成+flip+输出转视角/换幕布/透明抠图提示词+写 _meta.json |
| `build_pose_prompt.py` | character 流程姿态缺口检测+输出姿态提示词 |
| `build_video_prompt.py` | 组装视频提示词(模板+negative+ref_image+duration) |
| `video_to_sprites.py` | 拆帧+循环检测+抠图+K帧抽取+精灵表导出+最终预览+中间帧清理 |
| `check_env.py/.sh/.bat` | 环境检测+依赖补装 |
| `update_progress.py` | 更新步骤进度(_progress.json),自动按 asset_type 写流程文案 |

## 依赖

- Python 3.10+(通过各流程步骤0 check_env 自动检测)
- MCP 工具: edit_image / create_video_task(图像/视频生成)
