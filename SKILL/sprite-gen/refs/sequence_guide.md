# 非角色序列帧流程(sequence)

只在 `asset_type=sequence` 时执行本指南。不要混入 `character` 流程步骤;不做侧视、转视角、姿态缺口检测。

## 起点门禁

| 文件证据 | 允许起点 |
|---------|---------|
| 没有 `{work_dir}/{精灵名}` 或缺少 `_meta.json` | 步骤0/1 |
| 有 `_meta.json` + `_gen_images/cutout_ref.png` / `_gen_images/cutout.prompt.txt`,但没有 `_gen_images/ready.png` | 步骤2 抠图审核 |
| 有 `_meta.json`,但缺少 `_gen_images/ready.png` | 步骤0/1 |
| 有 `_meta.json` + `ready.png`,但没有 `_user_anims.json` | 步骤4 |
| 有 `_user_anims.json`,需要新增/重做动画 | "重做/续做"指定入口,最早步骤6 |
| 有 `anim.prompt.json`,但没有用户确认过的视频 | 步骤7a/7b |
| 有 `anim.mp4`,但没有用户验收过精灵表 | 步骤7b,通过后再步骤7c/7d |
| `_progress.json` 证明前序步骤完成 | 从已完成步骤后的下一个本流程步骤继续 |

## 人工确认点

| 确认点 | 必须等待用户确认 |
|-------|----------------|
| 步骤1 收集输入 | 素材图、精灵名、基础项 |
| 步骤2 透明抠图候选(条件) | 无 alpha 输入时,必须确认 cutout 后重跑 ready |
| 步骤4 动画清单 | 动画列表和 play_type |
| 步骤7b 视频审核 | 通过/重新生成 |
| 步骤7d 精灵表验收 | 通过/重做此动画 |

## 0. 环境检查(首次)

```bash
# Linux/Mac/容器
bash scripts/check_env.sh

# Windows
scripts\check_env.bat
```

## 1. ★ 收集输入

以交互方式向用户收集以下内容:

- 非角色素材图(路径或拖入;作为预处理来源和幕布色依据,后续以 `ready.png` 作为视频生成参考图)
- 精灵名
- 其余展示项(逐字展示,不许改/加/删,用户不改则用缺省):
  ```
  输出精灵高度: ___px  [缺省 256](素材主体实际像素高度,不含透明边距;请根据游戏中的预期大小设置)
  精灵画布占比: ___  [缺省 0.6](素材主体在 ready 方图中的占比;值越小预留动画空间越多,但画布和视频推导分辨率越大)
  帧模式: F(按 fps 全帧) / K(关键姿态抽帧,减少帧数和产物大小)  [缺省 F]
  美术风格要求: ___  [缺省保持原图风格](如"像素风"、"卡通赛璐璐"、"低多边形")
  ```
- 询问: `是否展开更多选项?` 默认不展开。

只有用户选择"展开更多选项"时,运行 `python3 scripts/describe_options.py --asset-type sequence`,并原样展示完整脚本输出(包含 `[基础配置]` 和 `[更多选项]` 分组)。不得摘要、改写或只列字段名。用户未填写的项全部保持当前值。

## 2. ★ 预处理 ready 图(条件审核)

```bash
python3 scripts/prepare_ready_image.py <素材图> --char-name <精灵名> --option 1 --target-height <高度> --frame-mode <F/K> --set asset_type=sequence [--set ready_layout.content_ratio=<精灵画布占比>] [--art-style "..."] [--set key=value ...]
```

`_meta.json.asset_type` 必须是 `sequence`。
用户修改"精灵画布占比"时,必须通过 `--set ready_layout.content_ratio=<值>` 写入 `_meta.json`;用户保持缺省时不要传这个 `--set`。

运行后记录脚本输出的 `work_dir`、`{work_dir}/{精灵名}`、`output_dir`、`{output_dir}/{精灵名}`;后续命令的目录参数均使用 `{work_dir}/{精灵名}`。

按脚本输出分支处理:

- 有 `_gen_images/ready.png` + `_meta.json`: 按主文档"预处理后的公共记录模板"的 `ready.png 已生成` 记录进度,进入步骤4。
- 只有 `_gen_images/cutout_ref.png` + `_gen_images/cutout.prompt.txt` + `_meta.json`,没有可用 `ready.png`: 严格按脚本输出的"下一步"执行;完成透明抠图审核、用同一组步骤2参数重跑并得到 `ready.png`,再进入步骤4。

## 4. ★ 选动画清单

向用户确认要生成的动画清单。动画必须来自用户输入中的目标动画、动作名或明确需求;信息不足以确定动画时,先询问用户补充目标、循环/单次和动作描述。用户确认前不得写入 `_user_anims.json`。

每个动画包含:

- `id`: 动画 id,由用户目标归纳命名。
- `play_type`: `loop` 或 `once`。
- `action`: 视频生成动作描述。
- `user_prompt`: 可选,用户自定义提示词补充;用于补充颜色、范围、节奏、形态等要求,不得替代 `action`。
- `duration`: 可选视频秒数,不填用缺省。

用户确认后保存为 `{work_dir}/{精灵名}/_user_anims.json`。字段结构:
```json
[
  {"id": "<动画id>", "play_type": "loop|once", "action": "<动作描述>", "user_prompt": "<可选>", "duration": "<可选>"}
]
```

## 6. 组装视频提示词

```bash
python3 scripts/build_video_prompt.py {work_dir}/{精灵名} {work_dir}/{精灵名}/_user_anims.json
```

输出 `_gen_videos/{动画id}/anim.prompt.json`(含 prompt/ref_image/duration/video_expected_resolution/video_generation_tier)。

**Agent 审核:** 读各 `anim.prompt.json` 检查提示词是否合理。需调整时,改 `_user_anims.json`,回到步骤6。

## 7. ★ 逐一执行动画

对动画清单中的每个动画,循环以下 4 步。每次只处理一个动画。

生成某个 `anim.mp4` 后必须立刻停止在视频审核点,展示该视频、审核标准和可选动作,等待用户明确通过/重做。当前动画视频未审核通过并记录 `video_review` 前,不得生成下一个动画的视频。

**a. 生成视频**

从 `anim.prompt.json` 读 prompt/ref_image/duration/video_expected_resolution/video_generation_tier。

- MCP: `create_video_task`,比例 1:1。
- 分辨率按 `video_expected_resolution` 尽量传递(模型能力未必完全生效)。
- 生成档位按 `video_generation_tier` 传递。
- 生成完搬到 `_gen_videos/{id}/anim.mp4`。

**b. ★ 审核视频**

展示视频给用户,附审核要点(通过 / 重新生成):
```
1. 动作符合用户要求,匹配目标动画
2. 幕布色全程保持不变且纯净均匀(无渐变、无阴影、无多余物件)
3. 主体无明显变形/模糊/融化
4. 相机无不必要移动
```

**c. 转序列帧并导出**

```bash
python3 scripts/video_to_sprites.py {work_dir}/{精灵名} --anims <动画id>
```

脚本在输出最终 `frames_preview.webp`、最终 `exports/` 和验收清单后,自动清理 `frames/frames_key` 中间帧,并重写 `{output_dir}/{精灵名}/sprite.json`。导出的入口 `spritesheet.json` 必须写 `meta.pivot`;sequence 流程的 pivot 缺省固定为 `sourceSize` 归一化坐标 `(0.5,0.5)`。额外分页 `spritesheet-N.json` 只保留最小 TexturePacker meta,不写动画语义。

**d. ★ 验收精灵表**

脚本输出预览信息:云端输出 markdown 图片链接(直接贴入回复),本地输出文件路径(展示给用户看)。

展示 `frames_preview.webp` + 脚本输出的验收清单(通过 / 重做此动画)。`frames_preview.webp` 由最终图集 PNG/JSON 反合成,用于检查最终尺寸和动画表现。如果帧模式是 K,还必须展示关键帧压缩信息:
```
[自动检测]
✅/⚠️ sourceSize 与 source_size_mode 一致
✅/⚠️ 入口 meta.source_size_mode 已写入
✅/⚠️ 入口 meta.pivot 合法(sourceSize normalized; bbox-per-anim 下不同动画可不同)
✅/⚠️ 背景透明
✅/⚠️ 图集每页 ≤ max_sheet_size
✅/⚠️ JSON 帧数一致
✅/⚠️ 无帧出框

[需审查(查看 frames_preview.webp)]
☐ 动作符合用户要求
☐ 节奏流畅
☐ 画面位置和尺寸符合预期
☐ 边缘无 key 色残留
```

## 8. 完成确认

全部动画完成后,更新进度:
```bash
python3 scripts/update_progress.py {work_dir}/{精灵名} --step 8 --status done
```

## 重做/续做

- **重做某个动画:** 改 `_user_anims.json` 里的 action,回到步骤6。
- **增加新动画:** 往 `_user_anims.json` 追加新动画(不动已有的),从步骤6继续。
- **改输出精灵高度:** 改 `_meta.json` 的 `target_height`,回到步骤7c/7d。最终大小应在导出阶段确定,不建议在游戏运行时调整缩放。
