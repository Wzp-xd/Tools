# 试管 3D 视觉增强设计方案

## 0. 现状分析

### 当前已有的视觉效果

| 区域 | 效果 | 实现方式 |
|------|------|---------|
| 管壁 | 左侧高光渐变 | `nvgLinearGradient` 白→透明，alpha=40 |
| 管壁 | 右侧微弱高光 | `nvgLinearGradient` 透明→白，alpha=12 |
| 管壁 | 轮廓描边 | 纯色描边，`nvgRGBA(180,200,230,60)` |
| 管口 | 外圈高光描边 | 白蓝色描边，alpha=120 |
| 管口 | 上沿高光弧 | Bézier 上半弧描边，alpha=80 |
| 管口 | 内圈暗色填充 | 深黑，alpha=220 |
| 管内衬底 | 深色背景 | 纯色填充，`nvgRGBA(10,10,20,200)` |
| 液体 | 纯色桶形填充 | 统一颜色 + liquidAlpha=210 |
| 液面 | 椭圆高光 | 比液体亮 +40，alpha=160 |
| 管底 | 阴影投影 | `nvgBoxGradient` 黑色渐变 |
| 液滴 | 径向渐变 + 高光点 | `nvgRadialGradient` + 小椭圆白点 |

### 当前缺失的 3D 感

1. **管壁**：只有简单的左侧线性高光，缺少圆柱体的连续光照过渡
2. **管壁**：无环境反射/折射暗示，不像玻璃
3. **液体**：每格纯色平涂，无深度感和体积感
4. **液体**：无管壁折射导致的边缘暗化效果
5. **球底**：无球底弧面的高光或反射
6. **液面**：椭圆高光太简单，缺少凹液面的光影细节
7. **整体**：缺少环境光遮蔽（AO）暗示

---

## 1. 玻璃管壁增强

### 1.1 圆柱体光照模型

真实玻璃圆柱的亮度分布遵循菲涅尔反射 + 漫反射的组合。简化为 NanoVG 的分段渐变：

```
  光源方向（假设左上 45°）
       ↘
  ┌─────────────────────┐
  │暗│ 亮   │    │  暗反│  │
  │边│ 反射 │ 中间│  射带│  │
  │缘│ 高光 │ 过渡│     │  │
  └─────────────────────┘
  0%  15%  35%   75%  90% 100%

  ← tubeWidth →
```

**实现**：将现有的单一左侧渐变替换为多层渐变叠加：

| 层 | 区域 | 效果 | alpha |
|----|------|------|-------|
| A | 0%~5% | 左边缘暗线 | 黑色，alpha 20~0 |
| B | 8%~28% | 主高光带 | 白色，alpha 0→55→0 |
| C | 70%~90% | 右侧次高光 | 白色，alpha 0→20→0 |
| D | 95%~100% | 右边缘暗线 | 黑色，alpha 0~15 |

### 1.2 球底反光

球底弧面增加一个小的高光椭圆，模拟球面反射：

```
          ╲         ╱
           ╲       ╱
            ╲     ╱
             ╲   ╱
              ╲ ╱
          ····◯····     ← 球底高光椭圆（偏左上方）
               V
```

**实现**：在管壁绘制之后，画一个小椭圆高光点。位置偏向光源方向（左上），使用径向渐变从白色过渡到透明。

### 1.3 玻璃厚度高光（管口立体感）

管口椭圆的外圈与内圈之间增加一圈**玻璃厚度环**，用渐变模拟玻璃横截面的折射：

```
        ╭═══════════╮      外圈（现有高光描边）
       ╭┤▓▓▓▓▓▓▓▓▓▓▓├╮     厚度环（新增：渐变填充）
       │╰───────────╯│     内圈（现有暗色填充）
```

**实现**：外圈和内圈之间绘制一个环形区域（外椭圆减内椭圆），填充从浅蓝白到深色的径向渐变。

---

## 2. 液体立体感增强

### 2.1 液体柱体光照

液体在圆柱管内也呈圆柱分布，左右边缘应比中间暗。实现为在桶形液体上叠加一层边缘暗化渐变：

```
  ┌─────────────────┐
  │暗│             │暗│    ← 左右边缘暗化
  │  │  中间保持   │  │
  │  │  原色       │  │
  └─────────────────┘
```

**实现**：在每个液体 slot 绘制后，使用相同的桶形路径 clip，叠加两个线性渐变：
- 左侧：黑色 alpha 40→0（占内径 20%）
- 右侧：黑色 alpha 0→30（占内径 20%）

### 2.2 液体内部高光带

类似管壁的高光，液体内部也应有一道偏左的高光，模拟透过玻璃折射看到的液体高光：

```
  ┌─────────────────┐
  │  │▒│           │  │    ← 液体高光带（窄竖条）
  │  │▒│           │  │
  │  │▒│           │  │
  └─────────────────┘
     20~30% 位置
```

**实现**：窄矩形 + 线性渐变，白色 alpha 0→25→0，宽度约为内径的 8%。

### 2.3 凹液面增强

当前液面只有一个纯色椭圆高光。增强为两层效果：

```
       ╭ ─ ─ ─ ─ ─ ─ ─ ╮
      (  亮环（椭圆描边）  )    ← 边缘高光环
       ╰ ─ ─ ─ ─ ─ ─ ─ ╯
          ◯ 光斑             ← 偏左上的小高光点
```

| 层 | 效果 | 说明 |
|----|------|------|
| 现有 | 椭圆填充高光 | 保留，作为液面基底亮度 |
| 新增 A | 椭圆描边高光环 | 白色描边 alpha=50，模拟凹面边缘反射 |
| 新增 B | 偏左小高光点 | 小椭圆，白色径向渐变，模拟光源反射点 |

---

## 3. 管内深度感

### 3.1 管内衬底渐变

当前管内衬底是纯色 `(10,10,20,200)`。改为垂直渐变，模拟管内越深越暗：

```
  管口处（较浅）   → nvgRGBA(15, 15, 30, 180)
  球底处（更深）   → nvgRGBA(5, 5, 15, 220)
```

### 3.2 管内边缘暗角

在管内衬底上叠加左右边缘暗化，增加圆柱内壁的纵深感。与液体边缘暗化类似，但应用于衬底层：

```
  ┌─────────────────┐
  │▓│             │▓│    ← 管内壁阴影
  │▓│   深色中间  │▓│
  │▓│             │▓│
  └─────────────────┘
```

---

## 4. 环境光遮蔽（AO）暗示

### 4.1 管口内沿阴影

管口内圈下方增加一圈渐变阴影，模拟管口遮挡光线的效果：

```
       ╰──────────╯
       ▒▒▒▒▒▒▒▒▒▒▒▒     ← 管口内沿 AO 阴影（渐变消失）
       │           │
       │           │
```

**实现**：在 straightTop 处绘制一个水平渐变矩形（上深下浅），高度约 4~6px。

### 4.2 球底内壁阴影

球底弧面与直筒交汇处，增加一圈柔和的暗角过渡：

**实现**：在 straightBottom 处绘制类似的渐变矩形（下深上浅），高度约 3~4px。

---

## 5. 渲染管线变更

### 5.1 新增步骤

在现有 9 步基础上插入新的绘制步骤：

```
第 1 步   阴影              （不变）
第 2 步   管内衬底           （改为渐变 + 边缘暗化）
第 2.5步  管口内沿 AO 阴影   （新增）
第 3 步   Scissor            （不变）
第 4 步   桶形液体层          （支持收缩渲染 shrinkState，见 §9.4）
第 4.5步  液体边缘暗化        （新增：叠加左右暗化渐变）
第 4.6步  液体高光带          （新增：偏左的窄高光条）
第 5.5步  填充液柱            （新增：fill 阶段的临时液柱，见 §9.4）
          释放 Scissor
第 6 步   玻璃管壁            （改为多层渐变）
第 6.5步  球底高光            （新增）
第 7 步   管口椭圆            （增加厚度环）
第 8 步   顶层液面高光         （增加描边环 + 光斑，收缩时跟随有效液面位置）
第 8.5步  填充液柱液面         （新增：fill 阶段液柱顶部液面椭圆）
第 9 步   选中发光            （不变）
```

### 5.2 改动范围汇总

| 函数 | 改动类型 |
|------|---------|
| `_drawInnerBack` | 改：纯色→垂直渐变 + 边缘暗化 |
| `_drawGlassWall` | 改：单层渐变→多层渐变（A/B/C/D 四层） |
| `_drawRim` | 改：增加厚度环渐变填充 |
| `_drawLiquidSlot` | 改：支持 `shrinkState` 收缩渲染（见 §9.4） |
| `_drawLiquidShading` | **新增**：液体边缘暗化 + 高光带 |
| `_drawLiquidSurface` | 改：增加描边环 + 光斑；收缩时液面 Y 跟随有效液面 |
| `_drawBallHighlight` | **新增**：球底弧面高光点 |
| `_drawInnerAO` | **新增**：管口内沿 AO 阴影 |
| `_drawFillColumn` | **新增**：fill 阶段临时液柱绘制（§9.4） |
| `_drawBulge` | **已删除**：隆起效果已被 rise 阶段替代 |

---

## 6. 新增配置参数

```lua
Config.TUBE.glass = {
    -- 管壁光照
    mainHighlightAlpha  = 55,    -- 主高光带最亮 alpha
    secHighlightAlpha   = 20,    -- 次高光带最亮 alpha
    edgeDarkAlpha       = 20,    -- 边缘暗线 alpha
    -- 球底高光
    ballHighlightAlpha  = 40,    -- 球底高光点 alpha
    ballHighlightSize   = 0.3,   -- 高光点相对球底宽度
    -- 管口厚度环
    rimRingAlpha        = 50,    -- 厚度环 alpha
}

Config.TUBE.liquid = {
    -- 边缘暗化
    edgeDarkAlpha       = 40,    -- 液体边缘暗化 alpha
    edgeWidth           = 0.20,  -- 暗化区域占内径比例
    -- 高光带
    highlightAlpha      = 25,    -- 液体高光带 alpha
    highlightWidth      = 0.08,  -- 高光带宽度占内径比例
    highlightPos        = 0.22,  -- 高光带中心位置（0=左壁, 1=右壁）
    -- 液面增强
    surfaceRingAlpha    = 50,    -- 液面描边环 alpha
    surfaceSpotAlpha    = 60,    -- 液面光斑 alpha
    surfaceSpotSize     = 0.15,  -- 光斑相对椭圆大小
}

Config.TUBE.ao = {
    rimShadowHeight     = 5,     -- 管口内沿 AO 高度（px）
    rimShadowAlpha      = 60,    -- 管口内沿 AO alpha
    ballJointAlpha      = 40,    -- 球底交汇处 AO alpha
    ballJointHeight     = 3,     -- 球底交汇处 AO 高度（px）
}
```

---

## 7. 视觉效果对照

| 维度 | 当前效果 | 增强后效果 |
|------|---------|-----------|
| 管壁 | 左侧单一线性高光 | 四层渐变：暗边→主高光→中间过渡→次高光→暗边 |
| 球底 | 无反光 | 偏左上方高光点 |
| 管口 | 描边 + 暗色填充 | 描边 + 厚度环渐变 + 暗色填充 |
| 液体 | 纯色平涂 | 纯色 + 边缘暗化 + 高光带 |
| 液面 | 单一椭圆高光 | 椭圆高光 + 边缘描边环 + 偏左光斑 |
| 管内 | 纯色深黑 | 垂直渐变 + 边缘暗化 |
| AO | 无 | 管口内沿阴影 + 球底交汇阴影 |

---

## 8. 实现优先级

按视觉提升效果排序，分两批实现：

### 第一批（高收益）

1. **管壁多层渐变**（§1.1）— 最大的视觉提升，将平面感变为圆柱体
2. **液体边缘暗化**（§2.1）— 液体从平涂变为有体积感
3. **管内衬底渐变**（§3.1）— 增加深度感，成本低

### 第二批（精细打磨）

4. **液面增强**（§2.3）— 描边环 + 光斑
5. **球底高光**（§1.2）— 球底弧面立体感
6. **管口厚度环**（§1.3）— 管口更精致
7. **液体高光带**（§2.2）— 细节提升
8. **AO 阴影**（§4）— 整体氛围提升

---

## 9. 倒水动画流程

### 9.1 动画流程概览

4 阶段倒水动画：

```
上升(rise) → 飞行(fly) → 融入(merge) → 填充(fill) → [数据写入]
```

**数据层时序**：
1. 点击倒水时，**立即** `removeFromSource` 从源管数组移除液体
2. rise 阶段：渲染层用 `shrinkState` 让源管顶部已移除的格子**逐渐缩减高度**（底部不动、顶部下移），液滴从液面位置上升到管口
3. rise 结束后：渲染层切换为 `hideFromTop = pour.count` 完全隐藏已移除的格子
4. 液滴飞行到目标管口 → 融入动画（液滴缩小消失）→ 填充液柱下落到目标层位
5. fill 结束后 `addToTarget` 把颜色加入目标管数组

**视觉流程**：

```
  源管        源管         源管        目标管         目标管
 ┌──┐       ┌──┐        ┌──┐       ┌──┐          ┌──┐
 │🟥│       │  │ ◯      │  │  ◯→   │  │          │  │
 │🟥│  →→   │  │↑上升    │  │       │  │    →→    │🟥│ ← 液柱下落到位
 │🟦│       │🟥│←缩减    │  │       │🟦│          │🟦│
 │🟦│       │🟦│        │🟦│       │🟦│          │🟦│
 └──┘       └──┘        └──┘       └──┘          └──┘
  起始      rise 阶段     fly 阶段               fill 结束
```

### 9.2 阶段 1：上升（rise）

液滴从源管**液面原始位置**出现（而非管口），逐渐上升到管口上方。同时，源管对应的液体格子**逐渐缩减高度直至消失**，形成"液体被抽出"的视觉效果。

#### 视觉效果

```
  t=0              t=0.5            t=1.0
 ┌──┐             ┌──┐            ┌──┐
 │  │             │  │  ◯←半大    │  │ ◯←完整大小
 │🟥│ ◯←极小      │  │            │  │
 │🟥│↑液面位置     │🟥│←缩了一半    │  │←完全消失
 │🟦│             │🟦│            │🟦│
 └──┘             └──┘            └──┘
```

#### 关键参数

| 参数 | 含义 | 值 |
|------|------|-----|
| `riseDuration` | 上升阶段时长 | 0.25s |
| 缓动函数 | easeOutQuad | 先快后慢，"弹出"感 |
| 液滴初始 aspect | 0.1（极小） | 逐渐长到 1.0（标准大小） |

#### 液滴起始位置计算

```lua
-- main.lua onTubeClick 中：
local originalCount = #game_.tubes[fromIdx] + pourInfo.count  -- 移除前的格数
local liquidTopY = fromStraightTop + (Config.CAPACITY - originalCount) * d.slotHeight
local riseEndY = fromPos.y  -- 管口 Y（上升终点）
```

`liquidTopY` 是**移除前**液面的 Y 坐标，需要用 `#当前数组 + 移除数量` 反推原始格数。

### 9.3 阶段 2~4：飞行、融入、填充

这三个阶段与之前一致：

| 阶段 | 时长 | 缓动 | 说明 |
|------|------|------|------|
| fly（飞行） | 0.30s | 二次贝塞尔弧线 | 液滴沿抛物线飞行到目标管口 |
| merge（融入） | 0.12s | 线性 | 液滴在管口位置缩小消失 |
| fill（填充） | 0.20s | easeInQuad（加速下落） | 液柱从管口下落到目标层位 |

**fly 阶段起点变更**：起始 Y 为 `riseEndY`（管口位置），不再是旧的 `fromY - detachStretch`。

### 9.4 AnimationManager 改动

#### triggerPour 签名

新增 `sourceRiseInfo` 参数，由 main.lua 计算并传入：

```lua
function AnimationManager:triggerPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `sourceRiseInfo.liquidTopY` | number | 源管液面原始 Y 坐标（液滴起始位置） |
| `sourceRiseInfo.riseEndY` | number | 上升终点 Y（管口位置） |
| `targetFillInfo.straightTop` | number | 目标管管口 Y |
| `targetFillInfo.targetSlotTop` | number | 目标格顶部 Y |
| `targetFillInfo.columnHeight` | number | 填充液柱高度 |

#### pourAnim 新增字段

```lua
pourAnim = {
    -- ... 通用字段 ...
    
    -- rise 阶段专用
    riseLiquidTopY = liquidTopY,  -- 液面起始 Y
    riseEndY       = riseEndY,    -- 上升终点 Y
    riseProgress   = 0,           -- rise 进度 0→1（给渲染层读取，用于液面缩减）
    
    -- 液滴初始状态
    blobY    = liquidTopY,        -- 起始 Y = 液面位置
    aspect   = 0.1,               -- 极小，逐渐长大
}
```

#### rise 阶段更新逻辑

```lua
if p.phase == "rise" then
    local t = math.min(p.timer / A.riseDuration, 1.0)
    local eased = 1.0 - (1.0 - t) * (1.0 - t)  -- easeOutQuad
    
    p.riseProgress = t          -- 给渲染层读取
    p.blobX = p.fromX
    p.blobY = lerp(p.riseLiquidTopY, p.riseEndY, eased)
    p.aspect = lerp(0.1, 1.0, eased)
    p.rotation = 0
    
    if t >= 1.0 then
        p.phase = "fly"
        p.timer = 0
        p.riseProgress = 1.0
    end
end
```

### 9.5 渲染层改动

#### 源管：shrinkState 收缩渲染

rise 阶段的源管不再用 `hideFromTop` 立即隐藏，而是用 `shrinkState` 逐渐缩减高度：

```lua
-- main.lua HandleNanoVGRender 中：
local hideFromTop = 0
local shrinkState = nil
if pour.active and pour.fromIdx == i then
    if pour.phase == "rise" then
        shrinkState = {
            count    = pour.count,       -- 正在缩减的格数
            progress = pour.riseProgress, -- 0→1 缩减进度
        }
    else
        hideFromTop = pour.count         -- rise 结束后直接隐藏
    end
end
```

#### TubeRenderer 液体渲染逻辑

收到 `shrinkState` 时的渲染行为：

```lua
local baseCount = #tube - hideFromTop        -- 数据层可见格数
local shrinkCount = shrink and shrink.count or 0
local shrinkProgress = shrink and shrink.progress or 0
local totalVisibleCount = baseCount + shrinkCount

for slot = 1, totalVisibleCount do
    local isShrinking = (slot > baseCount)
    local colorIdx = isShrinking and shrinkColorIdx or tube[slot]
    
    if isShrinking then
        local remainRatio = 1.0 - shrinkProgress
        local shrunkH = slotHeight * remainRatio
        -- 底部固定不动，顶部向下移动（高度缩减）
        effectiveSlotY = slotBottom - shrunkH
    end
end
```

**关键规则**：收缩格子**底部不动**、**顶部下移**，视觉上是液体被"抽走"。

#### 液面跟随收缩位置

当存在收缩格时，液面椭圆 Y 跟随有效顶部：

```lua
if shrinkCount > 0 then
    local slotBottom = straightTop + (CAPACITY - topShrinkSlot) * slotHeight + slotHeight
    local remainRatio = 1.0 - shrinkProgress
    surfaceY = slotBottom - slotHeight * remainRatio  -- 跟随缩减后的顶部
end
```

#### 填充液柱与液面

- fill 阶段的临时液柱绘制逻辑不变（第 5.5 步）
- fill 阶段在液柱顶部绘制液面椭圆（第 8.5 步）

#### `_drawBulge` 已删除

隆起效果（bulge）的渲染方法已完全删除，不再存在。

### 9.6 数据时序变更

| 阶段 | 时序 |
|------|------|
| 点击倒水 | `removeFromSource` 立即执行 |
| rise | 源管 `shrinkState` 逐渐缩减（`riseProgress` 0→1） |
| fly~merge | 源管 `hideFromTop` 隐藏 |
| fill | 临时液柱动画，数据未写入 |
| fill 结束 | `addToTarget` 写入，动画结束 |

### 9.7 配置参数

```lua
Config.ANIM.pour = {
    riseDuration   = 0.25,   -- 阶段 1: 上升（液滴从液面出现 + 液面缩减）
    flyDuration    = 0.30,   -- 阶段 2: 飞行（贝塞尔弧线）
    arcPeakH       = 50,     -- 飞行弧线最高点偏移
    mergeDuration  = 0.12,   -- 阶段 3: 融入（液滴缩小消失）
    fillDuration   = 0.20,   -- 阶段 4: 填充（液柱下落到目标层位）
}
```

**已删除的参数**：
- ~~`bulgeDuration`~~ — 隆起阶段已移除
- ~~`bulgeHeight`~~ — 隆起高度已移除
- ~~`detachDuration`~~ — 断裂阶段已移除
- ~~`detachStretch`~~ — 断裂拉伸已移除

### 9.8 布局信息传递

fill 阶段需要知道目标管的内部布局坐标。采用 **main.lua 层面传入**方案：

`triggerPour` 接受 `targetFillInfo` 和 `sourceRiseInfo` 两个参数，均由 main.lua 的 `onTubeClick` 计算并提供：

```lua
-- main.lua onTubeClick 中
local d = TubeRenderer.deriveTubeParams()

-- 目标管 fill 信息
local targetStraightTop = positions_[toIdx].y + d.rimEllipseRY * 2
local existingCount = #game_.tubes[toIdx]
local targetSlotTop = targetStraightTop
    + (Config.CAPACITY - existingCount - pourInfo.count) * d.slotHeight

-- 源管 rise 信息
local fromStraightTop = fromPos.y + d.rimEllipseRY * 2
local originalCount = #game_.tubes[fromIdx] + pourInfo.count
local liquidTopY = fromStraightTop + (Config.CAPACITY - originalCount) * d.slotHeight
local riseEndY = fromPos.y

anims_:triggerPour(fromIdx, toIdx, pourInfo.color, pourInfo.count, positions_, {
    straightTop   = targetStraightTop,
    targetSlotTop = targetSlotTop,
    columnHeight  = pourInfo.count * d.slotHeight,
}, {
    liquidTopY = liquidTopY,
    riseEndY   = riseEndY,
})
```

### 9.9 边界情况

| 情况 | 处理方式 |
|------|---------|
| 倒入空管底部（slot 1） | fill 液柱下降到球底弧区域，用桶形路径裁剪 |
| 倒多格（count > 1） | 液柱高度 = count × slotHeight，作为整体下降 |
| fill 进行中的渲染顺序 | 临时液柱在 Scissor 内、管壁之前绘制 |
| fill 液柱与现有液体的颜色分界 | 临时液柱底部用 `semiEllipseCW` 弧衔接 |
| **快速连续倒水** | `pourAnim.active` 锁保护，不会并发 |
| fill/rise 阶段点击其他管 | 忽略输入，等待动画结束 |
| 收缩格颜色 | 使用 `baseCount` 位置的颜色（即正常数据层最顶格） |

---

## 10. 性能考量

### 10.1 NanoVG 绘制调用增量

增强方案增加了多层渐变叠加，每管的 NanoVG 绘制调用数变化：

| 绘制内容 | 当前调用数/管 | 增强后调用数/管 | 增量 |
|---------|-------------|---------------|------|
| 管壁渐变 | 2（左+右） | 4（A/B/C/D 四层） | +2 |
| 管内衬底 | 1 | 2（渐变+边缘暗化） | +1 |
| 液体着色（每格） | 0 | 2（左+右边缘暗化）+ 1（高光带） | +3/格 |
| 液面 | 1 | 3（原高光+描边环+光斑） | +2 |
| AO 阴影 | 0 | 2（管口+球底） | +2 |
| 球底高光 | 0 | 1 | +1 |
| 管口厚度环 | 0 | 1 | +1 |

**以 12 管、每管 4 格液体为例**：
- 当前：每管约 8 次 → 总计 ~96 次
- 增强后：每管约 8 + 9 + 12（液体4格×3）= ~29 次 → 总计 ~348 次

增量约 3.6 倍。NanoVG 内部会批合并同 paint 的绘制，实际 GPU 压力不会线性增长，但仍需关注。

### 10.2 优化策略

| 策略 | 说明 |
|------|------|
| **按批次开启** | 第一批（§8）实现后先测帧率，再决定是否继续第二批 |
| **合并渐变层** | 管壁 A/D 暗边可合并为一次绘制（左右暗边在同一矩形内用两端渐变） |
| **液体着色共享 clip** | 同一管内所有液体格的边缘暗化可共享一次 Scissor/clip，减少 save/restore |
| **静态管缓存** | 空管或已完成的管（单色满管）可缓存到 FBO 纹理，跳过逐帧重绘 |
| **距离裁剪** | 屏幕外或极小的管跳过增强渐变（fallback 到现有简单渲染） |

### 10.3 性能基准线

实施前后应采集以下指标：

| 指标 | 测试场景 | 关注阈值 |
|------|---------|---------|
| 帧率（FPS） | 14 管、满液体、持续动画 | 低端机 ≥ 50fps |
| 帧时间波动 | 倒水动画期间 | 单帧峰值 ≤ 20ms |
| GPU 利用率 | 全屏管排列 | — |
