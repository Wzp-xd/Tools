# 倒水系统开发指南

> 本文档基于当前水排序游戏的并发倒水实现，总结出可复用的架构模式和关键技巧，供其他倒水类游戏参考。

---

## 目录

1. [核心架构：数据先行](#1-核心架构数据先行)
2. [管级锁定系统](#2-管级锁定系统)
3. [并发动画管理](#3-并发动画管理)
4. [渲染层与数据层分离](#4-渲染层与数据层分离)
5. [水流终点跟踪](#5-水流终点跟踪)
6. [动画阶段设计](#6-动画阶段设计)
7. [撤销系统兼容](#7-撤销系统兼容)
8. [关键参数配置](#8-关键参数配置)
9. [常见陷阱与解决方案](#9-常见陷阱与解决方案)

---

## 1. 核心架构：数据先行

### 原则

**操作时立即提交数据变更，动画仅为视觉表现层。**

传统做法是"动画完成后再修改数据"，但这会导致并发操作时状态管理极其复杂（需要跟踪"预期状态"）。数据先行模式将问题简化为：

```
用户操作 → 立即修改 tubes 数据 → 启动动画（纯视觉）
                                      ↓
                              动画完成 → 解锁管
```

### 实现

```lua
--- 数据先行提交倒水
function GameState:commitPour(srcIdx, dstIdx)
    local pourCount = self:getPourCount(srcIdx, dstIdx)
    if pourCount <= 0 then return nil end

    -- 1. 保存 undo 快照（变更前）
    self:saveUndoState()

    -- 2. 保存源管快照（动画渲染用，因为数据马上要变）
    local srcSnapshot = self:getTubeSnapshot(srcIdx)
    local pourColor = self:getTopColor(srcIdx)

    -- 3. 立即修改数据
    local src = self.tubes[srcIdx]
    local dst = self.tubes[dstIdx]
    for _ = 1, pourCount do
        table.insert(dst, table.remove(src))
    end

    -- 4. 加锁
    self:lockSource(srcIdx)
    self:addReceiving(dstIdx)

    -- 5. 返回动画所需信息
    return {
        srcIdx = srcIdx,
        dstIdx = dstIdx,
        pourCount = pourCount,
        pourColor = pourColor,
        srcSnapshot = srcSnapshot,  -- 源管的变更前快照
    }
end
```

### 为什么需要 srcSnapshot

数据已经提交（源管层被移除），但源管动画还需要渲染"正在倒出"的过程。因此必须保存源管变更前的快照，让动画系统用快照渲染源管，而非实时数据。

---

## 2. 管级锁定系统

### 两种锁

| 锁类型 | 字段 | 含义 | 限制 |
|--------|------|------|------|
| `sourceLocked` | `{ [tubeIdx] = true }` | 正在倒出中 | 不可被选为源、不可被选为目标 |
| `receivingCount` | `{ [tubeIdx] = int }` | 正在接收的动画数 | 不可被选为源（可继续接收） |

### 为什么 receivingCount 是计数器而非布尔值

一个管可以同时被多个源管倒入（只要颜色匹配且有空间）。当一个动画完成时只减 1，不能直接清除。

### 选源逻辑

```lua
function GameState:canSelectAsSource(tubeIdx)
    -- 正在倒出 → 不可选
    if self.sourceLocked[tubeIdx] then return false end
    -- 正在接收 → 不可选（数据已变，顶色可能不准确）
    if (self.receivingCount[tubeIdx] or 0) > 0 then return false end
    -- 基础检查（非空、非锁定、顶层非迷雾）
    return self:canSelect(tubeIdx)
end
```

### 生命周期

```
commitPour() → lockSource(src), addReceiving(dst)
    ...动画播放中...
动画完成 → unlockSource(src), removeReceiving(dst)
```

---

## 3. 并发动画管理

### 数据结构

用列表代替单一对象，支持多个倒水动画同时进行：

```lua
self.activeAnims = {}  -- 每个元素是一个独立的动画状态对象

-- 单个动画对象结构
{
    phase = "move",        -- 当前阶段: "move"|"tilt"|"pour"|"return"
    timer = 0,            -- 当前阶段已用时间
    srcIdx = 1,           -- 源管索引
    dstIdx = 3,           -- 目标管索引
    pourLayers = 2,       -- 要倒的层数
    pouredSoFar = 0,      -- 已倒层数（浮点，动画进度）
    pourColor = 1,        -- 倒入的颜色
    srcOrigLayers = {...},-- 源管快照
}
```

### 更新循环

逆序遍历以安全删除完成的动画：

```lua
function Animation:update(dt, selectedTube, tubeCount)
    local completedAnims = {}

    for i = #self.activeAnims, 1, -1 do
        local a = self.activeAnims[i]
        a.timer = a.timer + dt
        local done = false

        -- 状态机推进...
        if a.phase == "move" then
            if a.timer >= moveDuration then
                a.phase = "tilt"; a.timer = 0
            end
        elseif a.phase == "pour" then
            a.pouredSoFar = clamp(a.timer / pourPerLayer, 0, a.pourLayers)
            if a.pouredSoFar >= a.pourLayers then
                a.phase = "return"; a.timer = 0
            end
        elseif a.phase == "return" then
            if a.timer >= returnDuration then done = true end
        end

        if done then
            table.insert(completedAnims, a)
            table.remove(self.activeAnims, i)
        end
    end

    return completedAnims
end
```

### 查询接口

渲染时需要快速查询特定管的动画状态：

```lua
-- 查询某管是否正在作为源（跳过静态渲染）
function Animation:getAnimForSource(tubeIdx)

-- 查询某管作为目标的所有动画（计算视觉液面）
-- 遍历 activeAnims 中 dstIdx == tubeIdx 的条目
```

---

## 4. 渲染层与数据层分离

### 核心问题

数据先行后，目标管的 `tubes[dstIdx]` 已包含新层，但视觉上这些层还没"到达"。如果直接渲染全部数据，水会瞬间出现。

### 解决方案：hideLayers + extraFill

```lua
-- 对每个目标管，计算需要隐藏的层数和已动画填充量
local hideLayers = 0
local extraFill = 0
local extraColor = nil

for _, a in ipairs(anim.activeAnims) do
    if a.dstIdx == i then
        if a.phase == "move" or a.phase == "tilt" then
            -- 水还没开始倒：隐藏全部预提交层
            hideLayers = hideLayers + a.pourLayers
        elseif a.phase == "pour" then
            -- 正在倒：隐藏全部，但用 extraFill 渐进恢复
            hideLayers = hideLayers + a.pourLayers
            extraFill = extraFill + a.pouredSoFar  -- 0 → pourLayers 的浮点
            extraColor = a.pourColor
        end
        -- "return" 阶段：不隐藏（全部已到位）
    end
end

-- 截断管数据的顶部层
local visibleLayers = tubes[i]
if hideLayers > 0 then
    visibleLayers = {}
    for j = 1, #tubes[i] - hideLayers do
        visibleLayers[j] = tubes[i][j]
    end
end

-- 渲染：截断后的层 + extraFill 表现动画进度
drawStaticTubeLayers(nvg, cx, cy, visibleLayers, extraFill, extraColor)
```

### 各阶段视觉效果

| 阶段 | hideLayers | extraFill | 视觉效果 |
|------|-----------|-----------|---------|
| move | pourLayers | 0 | 目标管无变化（水还没来） |
| tilt | pourLayers | 0 | 目标管无变化（源管刚倾斜） |
| pour | pourLayers | 0→pourLayers | 液面从底部逐渐上升 |
| return | 0 | 0 | 层全部正常显示 |

### extraFill 渲染原理

渲染器接收 `extraFill`（浮点数）和 `extraColor`，在已有层之上绘制额外的"部分层"：

```lua
-- Renderer 内部逻辑
local extraLayers = math.floor(extraFill)  -- 完整额外层数
local extraFrac = extraFill - extraLayers  -- 顶部不足一层的部分

-- 将 extraLayers 个完整层 + 1 个 extraFrac 部分层追加到渲染列表
```

---

## 5. 水流终点跟踪

### 问题

水流（stream）从源管口落到目标管液面。如果用 `#tubes[dst]` 计算液面位置，由于数据已预提交，终点会跳到最终位置，而视觉液面还在下方 → 水流中间出现断裂空隙。

### 解决方案

水流终点 = 视觉液面位置 = 截断层 + 已填充量：

```lua
-- 在 pour 阶段绘制水流时
local visualFill = #tubes[dstIdx] - pour.pourLayers + pour.pouredSoFar
drawWaterStream(nvg, startX, startY, dstCX, dstCY, visualFill, pourColor)
```

这样水流终点会跟随 `pouredSoFar` 的增长而上升，始终紧贴视觉液面。

---

## 6. 动画阶段设计

### 四阶段状态机

```
move → tilt → pour → return
```

| 阶段 | 描述 | 源管视觉 | 目标管视觉 |
|------|------|---------|-----------|
| **move** | 源管移动到目标管上方 | 带着液体移动（快照渲染） | 无变化 |
| **tilt** | 源管倾斜到倒水角度 | 旋转倾斜 | 无变化 |
| **pour** | 液体流出 | 液面下降 + 水流绘制 | 液面上升 |
| **return** | 源管回到原位 | 空管回归 | 全部层正常显示 |

### 源管渲染（用快照）

源管使用 `srcOrigLayers` 快照渲染，不用实时数据（实时数据已清空）：

```lua
-- 源管的液面下降通过 removedCount 控制
local removedCount = 0
if pour.phase == "pour" then
    removedCount = pour.pouredSoFar  -- 浮点，渐进移除
elseif pour.phase == "return" then
    removedCount = pour.pourLayers   -- 全部移除
end

drawTiltedWater(nvg, cx, cy, pivotWX, pivotWY, angle,
    pour.srcOrigLayers, removedCount)
```

### 倾斜角度计算

根据剩余液体量动态计算倾斜角（液体越少，需要倾斜越大才能倒出）：

```lua
function Animation.getTiltAngleForRemaining(remaining)
    -- 简化模型：内壁高度 / 液面高度 → arctan
    local waterH = remaining * slotHeight
    local deficit = innerH - waterH
    local angle = math.atan(deficit / halfInnerW)
    return clamp(angle, tiltAngleMin, tiltAngleMax)
end
```

---

## 7. 撤销系统兼容

### 约束

- 有活跃动画时**禁止撤销**（数据已提交，动画进行中撤销会导致渲染混乱）
- Undo 栈有深度限制（如 30 步），防止内存膨胀

```lua
function GameState:undo(hasActiveAnims)
    if #self.undoStack == 0 or hasActiveAnims then return false end
    local snapshot = table.remove(self.undoStack)
    self.tubes = snapshot.tubes
    -- 恢复所有锁状态
    self.sourceLocked = {}
    self.receivingCount = {}
    return true
end
```

### 快照内容

每次 `commitPour` 前保存完整的管数据和机制状态：

```lua
snapshot = {
    tubes = deepCopy(self.tubes),
    locks = copy(self.locks),       -- 封印管
    tempTubes = copy(self.tempTubes),
    sinkTubes = copy(self.sinkTubes),
}
```

---

## 8. 关键参数配置

所有动画时间参数集中管理，方便调节手感：

```lua
Config.animation = {
    moveDuration   = 0.30,  -- 源管飞到目标上方的时长
    tiltDuration   = 0.20,  -- 倾斜动画时长
    pourPerLayer   = 0.28,  -- 每层液体的倒出时长（决定倒水速度感）
    returnDuration = 0.30,  -- 源管回到原位时长
    tiltAngleMin   = math.rad(18),   -- 满管最小倾斜角
    tiltAngleMax   = math.rad(100),  -- 空管最大倾斜角
}
```

### 调参建议

| 参数 | 偏小效果 | 偏大效果 |
|------|---------|---------|
| `moveDuration` | 快速移动，节奏紧凑 | 缓慢移动，优雅感 |
| `pourPerLayer` | 快速倒水，连击感强 | 慢速倒水，观赏性强 |
| `returnDuration` | 快速归位，适合速通 | 慢速归位，有余韵 |

---

## 9. 常见陷阱与解决方案

### 陷阱 1：目标管水面瞬间出现

**原因**：数据先行后，渲染直接读取了已修改的管数据。

**解决**：用 `hideLayers` 截断顶部层，`extraFill` 渐进恢复（见第 4 节）。

### 陷阱 2：水流终点与液面脱节

**原因**：水流终点用 `#tubes[dst]` 计算，包含了预提交的全部层。

**解决**：`visualFill = #tubes[dst] - pourLayers + pouredSoFar`（见第 5 节）。

### 陷阱 3：同一管被同时选为源和目标

**原因**：缺少管级锁。

**解决**：`sourceLocked` 阻止选为源/目标，`receivingCount > 0` 阻止选为源。

### 陷阱 4：多个动画完成时只处理了一个

**原因**：完成回调只处理单个。

**解决**：`update()` 返回 `completedAnims` 列表，主循环遍历处理所有完成项。

### 陷阱 5：撤销后锁状态残留

**原因**：undo 恢复了管数据，但没清理锁。

**解决**：undo 时显式重置 `sourceLocked = {}`、`receivingCount = {}`。

### 陷阱 6：return 阶段源管闪烁

**原因**：动画完成后从列表移除，源管在下一帧突然切换为静态渲染，但数据中源管已清空。

**解决**：这不是 bug——源管数据确实已清空（数据先行），动画完成即是正确结果。如果视觉有跳变，检查 return 阶段的 `removedCount` 是否等于 `pourLayers`。

---

## 架构总结

```
┌─────────────────────────────────────────────┐
│                 main.lua                     │
│  handleTubeTap → commitPour → startPour     │
│  HandleUpdate  → anim:update → 处理完成列表  │
│  Render        → 静态管(hideLayers) + 动画管 │
└──────────┬──────────────┬───────────────────┘
           │              │
    ┌──────▼──────┐  ┌───▼──────────┐
    │ GameState   │  │ Animation    │
    │             │  │              │
    │ commitPour  │  │ activeAnims  │
    │ lockSource  │  │ update(dt)   │
    │ unlockSrc   │  │ 4-phase FSM  │
    │ undo        │  │              │
    └─────────────┘  └──────────────┘
                            │
                     ┌──────▼──────┐
                     │ Renderer    │
                     │             │
                     │ Liquid      │ ← extraFill/extraColor
                     │ Effects     │ ← waterStream(visualFill)
                     │ Glass       │
                     └─────────────┘
```

---

## 适用场景

本架构不仅适用于水排序，也适用于：

- **颜料混合游戏** — 多管同时倒入
- **鸡尾酒调制** — 多种液体分层
- **化学实验模拟** — 试剂转移
- **沙子/球排序** — 同样的容器+颗粒模型

核心思想不变：**数据先行 + 管级锁 + hideLayers 视觉分离**。
