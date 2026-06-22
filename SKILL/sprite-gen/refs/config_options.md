# 配置字段与图集语义

> 本文件由 sprite-gen 内部生成脚本生成;不要手工修改。

配置优先级: `_user_anims.json`(动画级) > `_meta.json`(精灵级) > `config.json`(全局)

静态缺省值来自 `config.json` 和生成脚本的隐式 fallback。已有精灵工作目录时,当前值可能被 `_meta.json` 覆盖;需要展示给用户时运行 `python3 scripts/describe_options.py --sprite-work-dir {work_dir}/{精灵名}`。

| 名称 | 缺省值 | 展开项 | 取值 | 说明 | 何时调整 |
|------|--------|--------|------|------|----------|
| 工作目录 (work_dir) | .build/sprite-gen | 否 | 路径 | sprite-gen 工作目录,保存配置、提示词、中间产物、参考图和预览 | 通常不改;需要把中间产物放到指定目录时调整 |
| 输出目录 (output_dir) | assets/sprites | 否 | 路径 | 最终游戏资产输出目录 | 游戏项目使用不同资产目录时调整 |
| 素材类型 (asset_type) | character | 否 | character / sequence | 素材类型;character=角色/对象动画,sequence=非角色序列帧/视频式序列帧 | 由流程选择决定;不要在已开始的精灵中随意切换 |
| 输出精灵高度 (target_height) | 256 | 否 | 整数像素 | 输出精灵高度,指导出后素材主体实际内容高度,不含透明边距 | 根据游戏中的预期呈现大小设置,不建议依赖游戏运行时缩放 |
| 精灵画布占比 (ready_layout.content_ratio) | 0.6 | 否 | 0.01-1.0 | 素材主体在 ready 方图中的占比;值越小预留动画空间越多,但画布和视频推导分辨率越大 | 动作容易出框时调小;主体太小、细节不足或生成成本过高时调大 |
| sourceSize 策略 (source_size_mode) | canvas | 是 | canvas / bbox-per-anim | sourceSize 计算方式;canvas 更稳定,bbox-per-anim 空白更少但切动画需应用 pivot | 需要减小透明留白且运行时是 absolute+pivot 时改为 bbox-per-anim |
| 帧率 (fps) | 24 | 是 | 整数 | 导出帧率和每帧 duration | 想更顺滑可调高,想减小帧数和体积可调低 |
| 帧模式 (frame_mode) | F | 否 | F / K | F=按 fps 全帧;K=关键姿态抽帧,用于减少帧数和产物大小 | 需要完整帧率用 F;更重视体积和关键姿态时用 K |
| 单页图集上限 (max_sheet_size) | 2048 | 否 | 整数像素 | 单页图集上限 | 目标运行时或平台有更小纹理尺寸限制时调低 |
| 当前姿态 (ready_pose) | ground | 否 | ground / aerial | ready.png 当前姿态,供 character 流程判断是否需要补姿态参考图 | ready 图不是地面站姿而是空中/飞行姿态时设为 aerial |
| 视频时长 (video_duration) | "5" | 是 | 秒数字符串 | 每条视频生成时长 | 复杂单次动作可加长,普通循环通常保持缺省 |
| 视频生成档位 (video_generation_tier) | fast | 是 | fast / default | 视频生成档位 | 优先速度用 fast,优先质量稳定性用 default |
| 视频期望分辨率 (video_expected_resolution) | 留空/自动 | 是 | 480 / 720 / 1080 / null | 给视频模型的期望分辨率;null 会自动推导 | 细节不足时调高,想节省生成成本和时间可调低 |
| 合并反向提示词 (prompt_merge_negative) | true | 否 | true / false | 是否把反向提示词合并进视频正向提示词的 Avoid 段 | 目标视频接口支持独立 negative 字段时可设为 false |
| 画布水平偏移 (ready_layout.offset_ratio_x) | 0 | 是 | 数字 | ready 图水平偏移;正数右移,负数左移 | 需要给某一侧动作留空间时调整 |
| 画布垂直偏移 (ready_layout.offset_ratio_y) | character=0.1; sequence=0 | 是 | 数字 | ready 图垂直偏移;正数下移,负数上移 | character: 角色脚底需要更靠下或动作需要上下空间时调整; sequence: 素材中心需要上下微调或特效需要上下空间时调整 |
| 抠图强度 (chroma_strength) | 1.5 | 是 | 数字 | 色差键抠图强度 | 背景残留时调高,边缘被吃掉时调低 |
| 边缘内缩 (chroma_edge_shrink) | 1 | 是 | 整数像素 | alpha 边缘内缩像素 | 边缘有幕布色描边时调高,细线/光效被削掉时调到 0 |
| 循环检测最小帧数 (detect_min_cycle_frames) | 10 | 是 | 整数帧 | 循环检测的最小周期帧数 | 循环被截得太短时调高,很短循环识别不到时调低 |
| 动作留帧 (detect_padding_frames) | 3 | 是 | 整数帧 | 单次动画峰值前后额外保留帧数 | 动作头尾被切掉时调高,想更紧凑时调低 |
| 生成服务代理 (fal_proxy) | "" | 否 | 字符串 | 生成服务代理地址 | 仅在接入环境要求代理时配置 |

## 图集 JSON 语义

- `frame`: 裁剪后小图在 spritesheet PNG 里的位置和尺寸。
- `sourceSize`: `source_size_mode=canvas` 时是缩放后的原始帧画布;`bbox-per-anim` 时是单个动画所有帧 alpha bbox 并集,并保留 pivot 所需空间。
- `spriteSourceSize`: 当前帧 tight crop 在 `sourceSize` 画布里的位置和尺寸。
- `meta.pivot`: 入口 sheet 的通用对齐点,固定写 `space=sourceSize`,`unit=normalized`,`origin=top_left`;character 来自 ready 图内容 bbox bottom-center,无法推导时缺省 `(0.5,0.5)`,sequence 缺省 `(0.5,0.5)`。
- `meta.source_size_mode`: 入口 sheet 使用的 `sourceSize` 策略,值与配置字段 `source_size_mode` 一致,供运行时/使用者对照文档选择布局方式。
- `animations`: 可选有序动画定义数组;每个动画用显式帧 key 数组声明播放顺序,不依赖 `frames` 字典顺序。
- `meta.relatedMultiPacks`: 可选关联 sheet JSON 列表,用于分页或多入口引用。
- `duration`: K 模式读 `keyframe_map.json`;F 模式用 `1000 / fps`。

## sheet.json schema

自行开发播放器时,参考 `refs/spritesheet.schema.json`;普通生成/使用无需读取。

流式布局/普通图片序列播放只看元素盒子,不会自动理解 `meta.pivot`;这类播放/预览优先用 `source_size_mode=canvas`。游戏演出或需要精确切动作时,使用 absolute 布局,并按 `sourceSize + spriteSourceSize + meta.pivot` 应用支点。
