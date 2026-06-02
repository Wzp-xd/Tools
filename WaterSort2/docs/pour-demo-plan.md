# 试管倒水美术切片 Demo 方案

> **目标**：用模块化架构实现**完整美术品质**的倒水全流程视觉效果——包含 5 阶段液体动画（隆起→断裂→飞行→融入→沉降）、液滴形变、sin 波浪液面、涟漪特效、Scissor 裁剪。
> Demo 阶段不含关卡系统，但代码结构可直接扩展为正式游戏。

## 1. Demo 范围

### 包含

| 功能 | 说明 |
|------|------|
| 试管渲染 | 3D 玻璃质感试管（渐变管壁 + 管口高光 + 投影 + Scissor 裁剪防溢出） |
| 液体渲染 | 渐变色块 + **sin() 波浪液面** + 横向立体渐变 + 高光条 |
| 点击/触摸选中 | 试管上移 + 发光边框（同时支持鼠标和触摸） |
| **5 阶段倒水动画** | ① 隆起 → ② 断裂 → ③ 贝塞尔弧线飞行 → ④ 融入涟漪 → ⑤ 沉降衰减 |
| **液滴形变** | 飞行中椭圆宽高比随 t 变化，模拟流体拉伸感 |
| **融入涟漪** | 液滴接触目标管液面时产生涟漪波纹，阻尼衰减 |
| 源管液面下降 | 隆起/断裂阶段源管顶部液面同步动态下降 |
| 非法震动 | 不合法操作时试管水平震动 |
| 重置按钮 | 恢复到本组初始状态 |
| 刷新按钮 | 随机生成一组新的试管数据 |

### 不包含（Demo 阶段）

关卡系统、胜利检测、撤销、计分、关卡选择、主题切换、音效

### 扩展预留

以上"不包含"功能均在模块接口中预留了扩展点，详见 §9。

## 2. 测试场景

固定 **5 根试管**（3 色 + 2 空），容量 4 格：

```
初始状态（固定，用于重置）：

  [红蓝绿红] [蓝绿红蓝] [绿红蓝绿] [  空  ] [  空  ]
     管1        管2        管3       管4      管5
```

刷新时随机打乱生成新状态（同样 3 色 2 空）。

## 3. 文件结构

```
scripts/
├── main.lua               -- 入口：生命周期、事件订阅、模块组装（~150 行）
├── Config.lua             -- 所有常量配置：颜色、几何参数、5 阶段动画参数（~140 行）
├── GameState.lua          -- 纯数据层：试管数据、倒水判定、随机生成（~150 行）
├── TubeRenderer.lua       -- 试管+液体渲染：管壁、玻璃质感、sin 波浪液面、Scissor 裁剪、涟漪、液滴形变（~350 行）
├── AnimationManager.lua   -- 动画驱动：选中上移、5 阶段倒水、液滴形变、涟漪、震动（~300 行）
└── InputHandler.lua       -- 输入处理：鼠标/触摸 → hitTest → 分发事件（~80 行）
```

**总计约 1170 行**，每个文件不超过 350 行，职责清晰。

### 为什么不是单文件

| 对比 | 单文件 | 模块化 |
|------|--------|--------|
| Demo 阶段 | 略快（少几个 require） | 稍慢但可接受 |
| 加关卡系统 | 需大幅重构，逻辑/渲染耦合 | 新增 `LevelManager.lua`，GameState 加字段 |
| 换皮肤主题 | 改 CONFIG + 散落各处的颜色 | 替换 Config.lua 或扩展 Theme 表 |
| 加新特效 | 在大文件中找位置插入 | AnimationManager 加方法 |
| 多人协作 | 冲突严重 | 各改各的文件 |

## 4. 模块依赖关系

```
main.lua
  │
  ├─ require → Config.lua          （纯数据，无依赖）
  ├─ require → GameState.lua       （依赖 Config）
  ├─ require → TubeRenderer.lua    （依赖 Config）
  ├─ require → AnimationManager.lua（依赖 Config）
  └─ require → InputHandler.lua    （依赖 Config）

  数据流向（单向）：
  InputHandler → main（事件回调）→ GameState（数据变更）
                                 → AnimationManager（启动动画）
                                 → TubeRenderer（每帧读取状态渲染）
```

**关键原则**：模块之间不直接互相 require，由 main.lua 做中介组装。

## 5. 各模块详细设计

### 5.1 Config.lua — 常量配置

纯数据模块，返回一张只读配置表。后续换皮肤只需替换或扩展此文件。

```lua
local Config = {}

Config.CAPACITY = 4

Config.COLORS = {
    { 220,  60,  60 },  -- 1 红
    {  60, 120, 220 },  -- 2 蓝
    {  60, 180,  80 },  -- 3 绿
    { 240, 200,  40 },  -- 4 黄
    { 160,  80, 200 },  -- 5 紫
    { 240, 140,  40 },  -- 6 橙
    {  40, 200, 200 },  -- 7 青
    { 240, 120, 160 },  -- 8 粉
}

Config.TUBE = {
    width        = 50,
    innerWidth   = 42,
    slotHeight   = 36,
    topOpenH     = 12,
    bottomRadius = 20,
    wallWidth    = 4,
    gap          = 20,
}

Config.ANIM = {
    select = {
        liftY    = 8,
        duration = 0.1,
    },

    -- ===== 5 阶段倒水动画 =====
    pour = {
        -- 阶段 1: 隆起（液体在源管中鼓起）
        bulgeDuration  = 0.15,
        bulgeHeight    = 6,       -- 鼓出管口的像素高度

        -- 阶段 2: 断裂（拉伸变细 → 形成独立液滴）
        detachDuration = 0.10,
        detachStretch  = 12,      -- 拉伸距离

        -- 阶段 3: 飞行（贝塞尔弧线）
        flyDuration    = 0.30,
        arcPeakH       = 50,      -- 弧线最高点偏移

        -- 阶段 4: 融入（液滴接触目标管液面）
        mergeDuration  = 0.12,

        -- 阶段 5: 沉降（目标管液面上升 + 波纹衰减）
        -- 由 wobble + ripple 驱动，无需额外 duration
    },

    -- 液滴形变（飞行阶段椭圆宽高比随 t 变化）
    droplet = {
        baseWidth   = 0.6,   -- 相对 innerWidth 的基础宽度比例
        minAspect   = 0.5,   -- 最扁时宽高比（拉伸态，断裂和起飞瞬间）
        maxAspect   = 1.4,   -- 最圆时宽高比（飞行中段）
        rotateSpeed = 3.0,   -- 飞行中轻微旋转速度 (rad/s)
    },

    -- 波浪液面（sin 波）
    wave = {
        frequency  = 0.3,     -- 空间频率（每像素的波数）
        amplitude  = 1.8,     -- 静态波浪振幅（像素）
        timeSpeed  = 2.5,     -- 时间波动速度
    },

    -- 目标管涟漪（液滴融入后）
    ripple = {
        amplitude  = 4.0,     -- 初始振幅
        frequency  = 16,      -- 频率
        damping    = 5.0,     -- 衰减系数
    },

    -- 阻尼正弦波抖动（通用，源管液面下降后也触发）
    wobble = {
        amplitude = 3.0,
        frequency = 12,
        damping   = 4.5,
    },

    shake = {
        amplitude = 4,
        frequency = 20,
        duration  = 0.3,
    },

    glow = {
        color   = { 100, 180, 255 },
        alpha   = 100,
        feather = 6,
    },
}

-- 初始固定数据（用于重置）
Config.INITIAL_TUBES = {
    { 1, 3, 2, 1 },
    { 2, 1, 3, 2 },
    { 3, 2, 1, 3 },
    {},
    {},
}

return Config
```

### 5.2 GameState.lua — 纯数据层

只管数据和规则，不知道渲染和动画的存在。返回一个可实例化的对象。

**扩展点**：后续加关卡时，`init()` 接收关卡数据而非固定数据；加胜利检测只需新增 `isComplete()` 方法；加撤销只需加 `history` 栈。

```lua
local Config = require("Config")

local GameState = {}
GameState.__index = GameState

function GameState.new()
    local self = setmetatable({}, GameState)
    self.tubes = {}
    self.selected = nil          -- 当前选中试管索引，nil=未选
    self:reset()
    return self
end

-- 深拷贝 INITIAL_TUBES 作为初始状态
function GameState:reset()
    self.tubes = {}
    for i, tube in ipairs(Config.INITIAL_TUBES) do
        self.tubes[i] = {}
        for j, v in ipairs(tube) do
            self.tubes[i][j] = v
        end
    end
    self.selected = nil
end

-- Fisher-Yates 洗牌随机生成
function GameState:randomize(colorCount, emptyCount)
    colorCount = colorCount or 3
    emptyCount = emptyCount or 2
    local cap = Config.CAPACITY

    local pool = {}
    for color = 1, colorCount do
        for _ = 1, cap do
            pool[#pool + 1] = color
        end
    end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    self.tubes = {}
    for t = 1, colorCount do
        self.tubes[t] = {}
        for s = 1, cap do
            self.tubes[t][s] = pool[(t - 1) * cap + s]
        end
    end
    for e = 1, emptyCount do
        self.tubes[colorCount + e] = {}
    end
    self.selected = nil
end

function GameState:getTopColor(tubeIdx)
    local tube = self.tubes[tubeIdx]
    return tube[#tube]  -- nil if empty
end

function GameState:getTopCount(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if #tube == 0 then return 0 end
    local color = tube[#tube]
    local count = 0
    for i = #tube, 1, -1 do
        if tube[i] == color then count = count + 1
        else break end
    end
    return count
end

function GameState:canPour(fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    local from = self.tubes[fromIdx]
    local to   = self.tubes[toIdx]
    if #from == 0 then return false end
    if #to >= Config.CAPACITY then return false end
    if #to == 0 then return true end
    return self:getTopColor(fromIdx) == self:getTopColor(toIdx)
end

function GameState:calcPourCount(fromIdx, toIdx)
    local consecutive = self:getTopCount(fromIdx)
    local space = Config.CAPACITY - #self.tubes[toIdx]
    return math.min(consecutive, space)
end

--- 执行倒水数据变更（一步完成），返回 { color, count } 供动画使用
--- 适用于无动画的瞬间倒水场景
--- @return { color: number, count: number }
function GameState:executePour(fromIdx, toIdx)
    local info = self:removeFromSource(fromIdx, toIdx)
    self:addToTarget(toIdx, info.color, info.count)
    return info
end

--- 倒水拆分步骤 1/2：从源管移除顶部连续同色液体
--- 动画场景下先调用此方法，动画结束后再调用 addToTarget
--- @return { color: number, count: number }
function GameState:removeFromSource(fromIdx, toIdx)
    local count = self:calcPourCount(fromIdx, toIdx)
    local color = self:getTopColor(fromIdx)
    for i = 1, count do
        table.remove(self.tubes[fromIdx])
    end
    return { color = color, count = count }
end

--- 倒水拆分步骤 2/2：将液体添加到目标管
function GameState:addToTarget(toIdx, color, count)
    for i = 1, count do
        self.tubes[toIdx][#self.tubes[toIdx] + 1] = color
    end
end

--- 扩展预留：检查是否全部完成（每管纯色或空）
function GameState:isComplete()
    for _, tube in ipairs(self.tubes) do
        if #tube > 0 and #tube < Config.CAPACITY then return false end
        if #tube == Config.CAPACITY then
            local c = tube[1]
            for j = 2, #tube do
                if tube[j] ~= c then return false end
            end
        end
    end
    return true
end

return GameState
```

### 5.3 TubeRenderer.lua — 试管与液体渲染

只负责"给我 NanoVG context、试管数据和动画状态，我画出来"。不持有任何游戏状态。

**美术切片增强**：sin 波浪液面、Scissor 裁剪、液滴形变、涟漪渲染。

```lua
local Config = require("Config")

local TubeRenderer = {}

local TUBE = Config.TUBE
local COLORS = Config.COLORS

--- 颜色分量 clamp 到 [0, 255]，防止加减偏移后越界
local function clampC(v) return math.max(0, math.min(255, math.floor(v))) end

-- 全局时间累加器（用于液面波浪动画）
local globalTime_ = 0

function TubeRenderer.updateTime(dt)
    globalTime_ = globalTime_ + dt
end

--- 计算所有试管的屏幕位置
--- @return table positions, number tubeH
function TubeRenderer.calcPositions(tubeCount, screenW, screenH)
    local totalW = tubeCount * TUBE.width + (tubeCount - 1) * TUBE.gap
    local startX = (screenW - totalW) / 2
    local tubeH  = TUBE.topOpenH + TUBE.slotHeight * Config.CAPACITY + TUBE.bottomRadius
    local startY = (screenH - tubeH) / 2

    local positions = {}
    for i = 1, tubeCount do
        positions[i] = {
            x = startX + (i - 1) * (TUBE.width + TUBE.gap),
            y = startY,
        }
    end
    return positions, tubeH
end

--- 绘制背景渐变
function TubeRenderer.drawBackground(vg, w, h)
    local bg = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(15, 15, 30, 255), nvgRGBA(30, 30, 50, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
end

--- 绘制单根试管（管壁 + 液体 + 特效）
--- @param vg      NanoVG context
--- @param x       number 试管左上角 X（已含 shake 偏移）
--- @param y       number 试管左上角 Y（已含 select lift 偏移）
--- @param tube    table  颜色数组 { colorIdx, ... }，索引1=底部
--- @param opts    table  { selected, hideFromTop, wobbleOffset, rippleState, bulgeState }
function TubeRenderer.drawTube(vg, x, y, tube, opts)
    opts = opts or {}
    local hideFromTop = opts.hideFromTop or 0
    local wobbleOff   = opts.wobbleOffset or 0
    local selected    = opts.selected or false
    local ripple      = opts.rippleState     -- { amplitude, timer } or nil
    local bulge       = opts.bulgeState      -- { progress, color } or nil

    local innerX = x + TUBE.wallWidth
    local innerW = TUBE.innerWidth
    local tubeH  = TUBE.topOpenH + TUBE.slotHeight * Config.CAPACITY + TUBE.bottomRadius

    -- 1) 管底投影
    TubeRenderer._drawShadow(vg, x, y + tubeH, TUBE.width)

    -- 2) 管内衬底（深色）
    TubeRenderer._drawInnerBack(vg, innerX, y + TUBE.topOpenH, innerW,
        TUBE.slotHeight * Config.CAPACITY + TUBE.bottomRadius)

    -- 3) Scissor 裁剪：确保液体不溢出管内轮廓
    nvgSave(vg)
    nvgIntersectScissor(vg, innerX, y + TUBE.topOpenH, innerW,
        TUBE.slotHeight * Config.CAPACITY + TUBE.bottomRadius)

    -- 4) 液体层
    local visibleCount = #tube - hideFromTop
    for slot = 1, visibleCount do
        local colorIdx = tube[slot]
        local slotY = y + TUBE.topOpenH + (Config.CAPACITY - slot) * TUBE.slotHeight
        local isTop = (slot == visibleCount)

        TubeRenderer._drawLiquidSlot(vg, innerX, slotY, innerW, TUBE.slotHeight,
            colorIdx, isTop, wobbleOff, ripple)
    end

    -- 5) 源管隆起效果（bulge 阶段，液体鼓出管口）
    if bulge and visibleCount > 0 then
        local topColorIdx = tube[visibleCount]
        TubeRenderer._drawBulge(vg, innerX, y + TUBE.topOpenH, innerW,
            topColorIdx, bulge.progress)
    end

    nvgRestore(vg)  -- 释放 Scissor

    -- 6) 玻璃管壁（半透明渐变，画在液体上方）
    TubeRenderer._drawGlassWall(vg, x, y, TUBE.width, tubeH)

    -- 7) 管口高光
    TubeRenderer._drawRim(vg, x, y, TUBE.width)

    -- 8) 选中发光
    if selected then
        TubeRenderer._drawGlow(vg, x, y, TUBE.width, tubeH)
    end
end

--- 绘制飞行液滴（支持形变）
--- @param opts table { blobX, blobY, colorIdx, count, aspect, rotation }
function TubeRenderer.drawFlyingDroplet(vg, opts)
    local color = COLORS[opts.colorIdx]
    local baseW = TUBE.innerWidth * Config.ANIM.droplet.baseWidth
    local aspect = opts.aspect or 1.0
    local rotation = opts.rotation or 0

    -- 椭圆尺寸：aspect > 1 表示纵向拉伸，< 1 表示横向拉伸
    local w = baseW / math.sqrt(aspect)
    local h = baseW * math.sqrt(aspect)

    nvgSave(vg)
    nvgTranslate(vg, opts.blobX, opts.blobY)
    nvgRotate(vg, rotation)

    -- 主体椭圆
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, 0, w / 2, h / 2)
    local grad = nvgRadialGradient(vg, -w * 0.15, -h * 0.15, 1, math.max(w, h) * 0.6,
        nvgRGBA(clampC(color[1] + 40), clampC(color[2] + 40), clampC(color[3] + 40), 240),
        nvgRGBA(clampC(color[1] - 10), clampC(color[2] - 10), clampC(color[3] - 10), 220))
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 液滴高光
    nvgBeginPath(vg)
    nvgEllipse(vg, -w * 0.15, -h * 0.2, w * 0.2, h * 0.15)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
    nvgFill(vg)

    nvgRestore(vg)
end

-- === 内部绘制方法 ===

function TubeRenderer._drawShadow(vg, x, bottomY, w)
    local shadow = nvgBoxGradient(vg, x + 2, bottomY - 4, w - 4, 8, 4, 12,
        nvgRGBA(0, 0, 0, 80), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - 8, bottomY - 10, w + 16, 20)
    nvgFillPaint(vg, shadow)
    nvgFill(vg)
end

function TubeRenderer._drawInnerBack(vg, x, y, w, h)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, TUBE.bottomRadius * 0.8)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 200))
    nvgFill(vg)
end

--- 绘制液体色块（含 sin 波浪液面）
function TubeRenderer._drawLiquidSlot(vg, x, y, w, h, colorIdx, isTop, wobbleOff, ripple)
    local c = COLORS[colorIdx]
    local WV = Config.ANIM.wave

    -- 矩形主体
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    local grad = nvgLinearGradient(vg, x, y, x + w, y,
        nvgRGBA(clampC(c[1] + 30), clampC(c[2] + 30), clampC(c[3] + 30), 255),
        nvgRGBA(clampC(c[1] - 20), clampC(c[2] - 20), clampC(c[3] - 20), 255))
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 顶层：sin 波浪液面 + wobble 偏移 + 涟漪
    if isTop then
        local rippleOff = 0
        if ripple and ripple.amplitude > 0.1 then
            rippleOff = ripple.amplitude
                * math.sin(ripple.timer * Config.ANIM.ripple.frequency * math.pi * 2)
                * math.exp(-Config.ANIM.ripple.damping * ripple.timer)
        end

        local totalOff = wobbleOff + rippleOff

        -- sin 波浪曲线绘制
        nvgBeginPath(vg)
        local step = 2
        for px = 0, w do
            local waveY = math.sin((px + x) * WV.frequency + globalTime_ * WV.timeSpeed)
                        * WV.amplitude
            local py = y + totalOff + waveY
            if px == 0 then
                nvgMoveTo(vg, x + px, py)
            else
                nvgLineTo(vg, x + px, py)
            end
        end
        -- 封闭路径：底部矩形
        nvgLineTo(vg, x + w, y + 6)
        nvgLineTo(vg, x, y + 6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(clampC(c[1] + 40), clampC(c[2] + 40), clampC(c[3] + 40), 160))
        nvgFill(vg)
    end
end

--- 绘制隆起效果（bulge 阶段）
function TubeRenderer._drawBulge(vg, innerX, topOpenY, innerW, colorIdx, progress)
    local c = COLORS[colorIdx]
    local bulgeH = Config.ANIM.pour.bulgeHeight * progress

    -- 鼓起的半圆弧
    nvgBeginPath(vg)
    nvgMoveTo(vg, innerX, topOpenY)
    nvgBezierTo(vg,
        innerX + innerW * 0.2, topOpenY - bulgeH,
        innerX + innerW * 0.8, topOpenY - bulgeH,
        innerX + innerW, topOpenY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(clampC(c[1] + 20), clampC(c[2] + 20), clampC(c[3] + 20), 200))
    nvgFill(vg)
end

function TubeRenderer._drawGlassWall(vg, x, y, w, h)
    -- 左侧高光
    local glassL = nvgLinearGradient(vg, x, y, x + w * 0.3, y,
        nvgRGBA(255, 255, 255, 40), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, TUBE.bottomRadius)
    nvgFillPaint(vg, glassL)
    nvgFill(vg)

    -- 右侧微弱高光
    local glassR = nvgLinearGradient(vg, x + w * 0.8, y, x + w, y,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, 12))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, TUBE.bottomRadius)
    nvgFillPaint(vg, glassR)
    nvgFill(vg)

    -- 管壁轮廓
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, TUBE.bottomRadius)
    nvgStrokeColor(vg, nvgRGBA(180, 200, 230, 60))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

function TubeRenderer._drawRim(vg, x, y, w)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y)
    nvgLineTo(vg, x + w, y)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

function TubeRenderer._drawGlow(vg, x, y, w, h)
    local gc = Config.ANIM.glow
    local glow = nvgBoxGradient(vg, x - 2, y - 2, w + 4, h + 4,
        TUBE.bottomRadius + 2, gc.feather,
        nvgRGBA(gc.color[1], gc.color[2], gc.color[3], gc.alpha),
        nvgRGBA(gc.color[1], gc.color[2], gc.color[3], 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 8, y - 8, w + 16, h + 16, TUBE.bottomRadius + 6)
    nvgFillPaint(vg, glow)
    nvgFill(vg)
end

return TubeRenderer
```

### 5.4 AnimationManager.lua — 动画驱动

管理所有动画状态的生命周期。5 阶段倒水动画 + 液滴形变 + 涟漪状态。

```lua
local Config = require("Config")

local AnimationManager = {}
AnimationManager.__index = AnimationManager

function AnimationManager.new(tubeCount)
    local self = setmetatable({}, AnimationManager)

    self.tubeCount = tubeCount

    -- 每管独立的动画状态
    self.selectAnims = {}   -- [i] = { target, current }
    self.wobbles     = {}   -- [i] = { amplitude, timer }
    self.shakes      = {}   -- [i] = { timer }
    self.ripples     = {}   -- [i] = { amplitude, timer }
    for i = 1, tubeCount do
        self.selectAnims[i] = { target = 0, current = 0 }
        self.wobbles[i]     = { amplitude = 0, timer = 0 }
        self.shakes[i]      = { timer = 0 }
        self.ripples[i]     = { amplitude = 0, timer = 0 }
    end

    -- 全局倒水动画
    self.pourAnim = { active = false }

    return self
end

-- === 触发接口 ===

function AnimationManager:setSelected(index)
    for i = 1, self.tubeCount do
        self.selectAnims[i].target = (i == index) and Config.ANIM.select.liftY or 0
    end
end

function AnimationManager:clearSelected()
    for i = 1, self.tubeCount do
        self.selectAnims[i].target = 0
    end
end

function AnimationManager:triggerWobble(tubeIdx, amplitude)
    self.wobbles[tubeIdx] = {
        amplitude = amplitude or Config.ANIM.wobble.amplitude,
        timer = 0,
    }
end

function AnimationManager:triggerRipple(tubeIdx)
    self.ripples[tubeIdx] = {
        amplitude = Config.ANIM.ripple.amplitude,
        timer = 0,
    }
end

function AnimationManager:triggerShake(tubeIdx)
    self.shakes[tubeIdx] = { timer = 0 }
end

--- 启动 5 阶段倒水动画
--- @param fromIdx number
--- @param toIdx   number
--- @param color   number 颜色索引
--- @param count   number 倒几格
--- @param positions table 试管位置表 { {x,y}, ... }
function AnimationManager:triggerPour(fromIdx, toIdx, color, count, positions)
    local fromPos = positions[fromIdx]
    local toPos   = positions[toIdx]

    self.pourAnim = {
        active   = true,
        phase    = "bulge",   -- 阶段 1
        fromIdx  = fromIdx,
        toIdx    = toIdx,
        color    = color,
        count    = count,
        timer    = 0,

        -- 起止坐标（预计算）
        fromX = fromPos.x + Config.TUBE.width / 2,
        fromY = fromPos.y,
        toX   = toPos.x + Config.TUBE.width / 2,
        toY   = toPos.y + Config.TUBE.topOpenH,

        -- 飞行液滴当前状态
        blobX    = fromPos.x + Config.TUBE.width / 2,
        blobY    = fromPos.y,
        aspect   = 1.0,       -- 椭圆宽高比
        rotation = 0,         -- 旋转角度

        -- 隆起进度（给渲染层用）
        bulgeProgress = 0,
    }
end

function AnimationManager:isPourActive()
    return self.pourAnim.active
end

-- === 每帧更新 ===

--- @return table|nil pourResult  倒水完成时返回 { fromIdx, toIdx, color, count }
function AnimationManager:update(dt)
    self:_updateSelectAnims(dt)
    self:_updateWobbles(dt)
    self:_updateShakes(dt)
    self:_updateRipples(dt)
    return self:_updatePourAnim(dt)
end

-- === 读取接口（给渲染层用） ===

function AnimationManager:getSelectLift(tubeIdx)
    return self.selectAnims[tubeIdx].current
end

function AnimationManager:getWobbleOffset(tubeIdx)
    local w = self.wobbles[tubeIdx]
    if w.amplitude <= 0.1 then return 0 end
    return w.amplitude * math.sin(w.timer * Config.ANIM.wobble.frequency * math.pi * 2)
end

function AnimationManager:getRippleState(tubeIdx)
    return self.ripples[tubeIdx]
end

function AnimationManager:getShakeOffset(tubeIdx)
    local s = self.shakes[tubeIdx]
    if s.timer >= Config.ANIM.shake.duration then return 0 end
    local progress = s.timer / Config.ANIM.shake.duration
    local decay = 1 - progress
    return Config.ANIM.shake.amplitude * decay
        * math.sin(s.timer * Config.ANIM.shake.frequency * math.pi * 2)
end

function AnimationManager:getPourState()
    return self.pourAnim
end

-- === 内部实现 ===

function AnimationManager:_updateSelectAnims(dt)
    local speed = Config.ANIM.select.liftY / Config.ANIM.select.duration
    for i = 1, self.tubeCount do
        local a = self.selectAnims[i]
        if a.current < a.target then
            a.current = math.min(a.current + speed * dt, a.target)
        elseif a.current > a.target then
            a.current = math.max(a.current - speed * dt, a.target)
        end
    end
end

function AnimationManager:_updateWobbles(dt)
    local damping = Config.ANIM.wobble.damping
    for i = 1, self.tubeCount do
        local w = self.wobbles[i]
        if w.amplitude > 0.1 then
            w.timer = w.timer + dt
            w.amplitude = w.amplitude * math.exp(-damping * dt)
        end
    end
end

function AnimationManager:_updateShakes(dt)
    for i = 1, self.tubeCount do
        local s = self.shakes[i]
        if s.timer < Config.ANIM.shake.duration then
            s.timer = s.timer + dt
        end
    end
end

function AnimationManager:_updateRipples(dt)
    for i = 1, self.tubeCount do
        local r = self.ripples[i]
        if r.amplitude > 0.1 then
            r.timer = r.timer + dt
            -- amplitude 保持不变，衰减在渲染端通过 exp(-damping*timer) 计算
        end
    end
end

local function bezier2(p0, p1, p2, t)
    local u = 1 - t
    return u * u * p0 + 2 * u * t * p1 + t * t * p2
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 5 阶段倒水动画更新
--- @return table|nil pourResult
function AnimationManager:_updatePourAnim(dt)
    local p = self.pourAnim
    if not p.active then return nil end

    p.timer = p.timer + dt
    local A = Config.ANIM.pour
    local D = Config.ANIM.droplet

    -- ========== 阶段 1: 隆起 ==========
    if p.phase == "bulge" then
        local t = math.min(p.timer / A.bulgeDuration, 1.0)
        p.bulgeProgress = t
        p.blobX = p.fromX
        p.blobY = p.fromY
        if t >= 1.0 then
            p.phase = "detach"
            p.timer = 0
        end

    -- ========== 阶段 2: 断裂 ==========
    elseif p.phase == "detach" then
        local t = math.min(p.timer / A.detachDuration, 1.0)
        p.bulgeProgress = 1.0 - t  -- 隆起消退
        p.blobX = p.fromX
        p.blobY = p.fromY - A.detachStretch * t
        -- 纵向拉伸：从圆变成纵向椭圆
        p.aspect = lerp(1.0, D.minAspect, t)
        p.rotation = 0
        if t >= 1.0 then
            p.phase = "fly"
            p.timer = 0
            p.bulgeProgress = 0
        end

    -- ========== 阶段 3: 飞行 ==========
    elseif p.phase == "fly" then
        local t = math.min(p.timer / A.flyDuration, 1.0)

        -- 贝塞尔弧线
        local x0 = p.fromX
        local y0 = p.fromY - A.detachStretch
        local x2, y2 = p.toX, p.toY
        local xMid = (x0 + x2) / 2
        local yPeak = math.min(y0, y2) - A.arcPeakH

        p.blobX = bezier2(x0, xMid, x2, t)
        p.blobY = bezier2(y0, yPeak, y2, t)

        -- 形变：起飞时扁 → 中段圆 → 降落时又扁
        local aspectT = 1.0 - math.abs(t - 0.5) * 2   -- 0 → 1 → 0
        p.aspect = lerp(D.minAspect, D.maxAspect, aspectT)

        -- 轻微旋转
        p.rotation = math.sin(p.timer * D.rotateSpeed) * 0.15

        if t >= 1.0 then
            p.phase = "merge"
            p.timer = 0
        end

    -- ========== 阶段 4: 融入 ==========
    elseif p.phase == "merge" then
        local t = math.min(p.timer / A.mergeDuration, 1.0)
        p.blobX = p.toX
        p.blobY = p.toY
        -- 液滴缩小消失
        p.aspect = lerp(D.maxAspect, 0.1, t)
        p.rotation = 0

        if t >= 1.0 then
            -- 触发涟漪 + wobble
            self:triggerRipple(p.toIdx)
            self:triggerWobble(p.toIdx)
            -- 源管也触发轻微 wobble（液面下降后的晃动）
            self:triggerWobble(p.fromIdx, Config.ANIM.wobble.amplitude * 0.5)

            local result = {
                fromIdx = p.fromIdx,
                toIdx   = p.toIdx,
                color   = p.color,
                count   = p.count,
            }
            p.active = false
            return result
        end
    end

    return nil
end

return AnimationManager
```

### 5.5 InputHandler.lua — 输入处理

将物理坐标转换为逻辑坐标，做 hitTest，然后通过回调通知外部。

```lua
local Config = require("Config")

local InputHandler = {}

local TUBE = Config.TUBE
local callback_ = nil
local positions_ = nil
local tubeH_ = 0
local getAnimOffsets_ = nil   -- function(i) → liftY, shakeX

--- 初始化
--- @param opts table { positions, tubeH, getAnimOffsets, onTubeClick }
function InputHandler.init(opts)
    positions_       = opts.positions
    tubeH_           = opts.tubeH
    getAnimOffsets_  = opts.getAnimOffsets
    callback_        = opts.onTubeClick

    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
end

--- 布局变化时更新
function InputHandler.updateLayout(positions, tubeH)
    positions_ = positions
    tubeH_     = tubeH
end

-- 以下两个函数必须为全局函数，供 SubscribeToEvent 按名称回调
-- luacheck: globals HandleMouseDown HandleTouchBegin

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    if UI.IsPointerOverUI() then return end

    local mousePos = input.mousePosition
    local dpr = graphics:GetDPR()
    InputHandler._processHit(mousePos.x / dpr, mousePos.y / dpr)
end

function HandleTouchBegin(eventType, eventData)
    if UI.IsPointerOverUI() then return end

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    InputHandler._processHit(tx / dpr, ty / dpr)
end

function InputHandler._processHit(px, py)
    if not positions_ or not callback_ then return end
    for i, pos in ipairs(positions_) do
        local liftY, shakeX = 0, 0
        if getAnimOffsets_ then
            liftY, shakeX = getAnimOffsets_(i)
        end
        local tx = pos.x + shakeX
        local ty = pos.y - liftY

        if px >= tx and px <= tx + TUBE.width
           and py >= ty and py <= ty + tubeH_ then
            callback_(i)
            return
        end
    end
end

return InputHandler
```

### 5.6 main.lua — 入口与组装

组装所有模块，管理生命周期。这是唯一知道所有模块存在的文件。

```lua
local UI = require("urhox-libs/UI")
local Config           = require("Config")
local GameState        = require("GameState")
local TubeRenderer     = require("TubeRenderer")
local AnimationManager = require("AnimationManager")
local InputHandler     = require("InputHandler")

local game_      ---@type GameState
local anims_     ---@type AnimationManager
local positions_ = {}
local tubeH_     = 0
local nvgCtx_    = nil

-- ============================================================
-- 生命周期
-- ============================================================

function Start()
    graphics.windowTitle = "倒水美术切片"

    -- 1) 初始化 UI
    UI.Init({
        fonts = {{ family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }},
        scale = UI.Scale.DEFAULT,
    })
    CreateHUD()

    -- 2) 初始化游戏数据
    game_ = GameState.new()
    anims_ = AnimationManager.new(#game_.tubes)

    -- 3) 计算布局
    updateLayout()

    -- 4) 初始化输入
    InputHandler.init({
        positions = positions_,
        tubeH     = tubeH_,
        getAnimOffsets = function(i)
            return anims_:getSelectLift(i), anims_:getShakeOffset(i)
        end,
        onTubeClick = onTubeClick,
    })

    -- 5) NanoVG 渲染事件
    nvgCtx_ = UI.GetNanoVGContext()
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")

    -- 6) 帧更新
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== Pour Water Art-Slice Demo Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================
-- 布局
-- ============================================================

function updateLayout()
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    positions_, tubeH_ = TubeRenderer.calcPositions(
        #game_.tubes, w / dpr, h / dpr)
end

-- ============================================================
-- 核心交互逻辑
-- ============================================================

function onTubeClick(index)
    if anims_:isPourActive() then return end

    if game_.selected == nil then
        if #game_.tubes[index] > 0 then
            game_.selected = index
            anims_:setSelected(index)
        end
    elseif game_.selected == index then
        game_.selected = nil
        anims_:clearSelected()
    else
        if game_:canPour(game_.selected, index) then
            local fromIdx = game_.selected

            -- 拆分步骤 1/2：先从数据层移除源管顶部（渲染层由动画接管飞行液滴）
            local pourInfo = game_:removeFromSource(fromIdx, index)

            anims_:triggerPour(fromIdx, index, pourInfo.color, pourInfo.count, positions_)
            game_.selected = nil
            anims_:clearSelected()
        else
            anims_:triggerShake(index)
            game_.selected = nil
            anims_:clearSelected()
        end
    end
end

-- ============================================================
-- 帧更新
-- ============================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 更新渲染器时间（用于液面波浪动画）
    TubeRenderer.updateTime(dt)

    local pourResult = anims_:update(dt)
    if pourResult then
        -- 拆分步骤 2/2：倒水动画结束 → 将液体添加到目标管
        game_:addToTarget(pourResult.toIdx, pourResult.color, pourResult.count)
    end
end

-- ============================================================
-- NanoVG 渲染
-- ============================================================

function HandleNanoVGRender(eventType, eventData)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW, logH = w / dpr, h / dpr

    nvgBeginFrame(nvgCtx_, logW, logH, dpr)

    TubeRenderer.drawBackground(nvgCtx_, logW, logH)

    local pour = anims_:getPourState()

    for i = 1, #game_.tubes do
        local pos = positions_[i]
        local liftY   = anims_:getSelectLift(i)
        local shakeX  = anims_:getShakeOffset(i)
        local wobbleY = anims_:getWobbleOffset(i)

        local hideFromTop = 0
        if pour.active and pour.fromIdx == i then
            hideFromTop = pour.count
        end

        -- 隆起状态（仅源管在 bulge/detach 阶段）
        local bulgeState = nil
        if pour.active and pour.fromIdx == i and pour.bulgeProgress > 0 then
            bulgeState = { progress = pour.bulgeProgress, color = pour.color }
        end

        TubeRenderer.drawTube(nvgCtx_,
            pos.x + shakeX,
            pos.y - liftY,
            game_.tubes[i],
            {
                selected     = (game_.selected == i),
                hideFromTop  = hideFromTop,
                wobbleOffset = wobbleY,
                rippleState  = anims_:getRippleState(i),
                bulgeState   = bulgeState,
            }
        )
    end

    -- 飞行液滴（detach / fly / merge 阶段可见）
    if pour.active and pour.phase ~= "bulge" then
        TubeRenderer.drawFlyingDroplet(nvgCtx_, {
            blobX    = pour.blobX,
            blobY    = pour.blobY,
            colorIdx = pour.color,
            count    = pour.count,
            aspect   = pour.aspect,
            rotation = pour.rotation,
        })
    end

    nvgEndFrame(nvgCtx_)
end

-- ============================================================
-- HUD
-- ============================================================

function CreateHUD()
    local root = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = "倒水美术切片",
                fontSize = 22,
                fontColor = { 200, 220, 255, 200 },
                marginTop = 20,
            },
            UI.Panel {
                flexDirection = "row",
                gap = 24,
                marginBottom = 30,
                children = {
                    UI.Button {
                        text = "重置", variant = "secondary",
                        onClick = function()
                            game_:reset()
                            anims_ = AnimationManager.new(#game_.tubes)
                            updateLayout()
                        end,
                    },
                    UI.Button {
                        text = "刷新", variant = "primary",
                        onClick = function()
                            game_:randomize(3, 2)
                            anims_ = AnimationManager.new(#game_.tubes)
                            updateLayout()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end
```

## 6. 交互状态机

```
              点击非空管
  [空闲] ──────────────→ [已选中]
    ↑                       │
    │  点击已选/空白区域     │  点击其他管
    ├───────────────────────┤
    │                       ↓
    │                   ┌─ 合法? ─┐
    │                   │ YES     │ NO
    │                   ↓         ↓
    │              [5阶段动画]  [震动反馈]
    │               │              │
    │   ┌───────────┘              │
    │   │                          │
    │   ▼                          │
    │  ① 隆起 (0.15s)             │
    │   │  液体在源管鼓起          │
    │   ▼                          │
    │  ② 断裂 (0.10s)             │
    │   │  拉伸→断开→独立液滴      │
    │   ▼                          │
    │  ③ 飞行 (0.30s)             │
    │   │  贝塞尔弧线+形变+旋转    │
    │   ▼                          │
    │  ④ 融入 (0.12s)             │
    │   │  液滴缩小→涟漪+wobble    │
    │   ▼                          │
    │  ⑤ 沉降                     │
    │   │  液面上升+波纹衰减       │
    │   │                          │
    └───┴──────────────────────────┘
                    回到 [空闲]
```

## 7. NanoVG 绘制技法速查

| 视觉效果 | NanoVG API |
|---------|-----------|
| 管壁玻璃渐变 | `nvgLinearGradient` 左右亮→暗 + `nvgRoundedRect` |
| 管壁右侧微光 | 第二层 `nvgLinearGradient` 弱白色 |
| 管底投影 | `nvgBoxGradient` + 大 `feather` 值 + 半透明黑色 |
| 选中发光 | `nvgBoxGradient` + 蓝色内亮外透明 |
| 液体色块 | `nvgRect` + `nvgLinearGradient` 横向立体感 |
| **sin 波浪液面** | `for px` 逐像素 `nvgLineTo(x, baseY + sin(x*freq + time)*amp)` |
| **液体裁剪** | `nvgSave` + `nvgIntersectScissor` + 绘制 + `nvgRestore` |
| **隆起鼓包** | `nvgBezierTo` 半圆弧 + 半透明填充 |
| **液滴形变** | `nvgEllipse` + `nvgTranslate/nvgRotate` 变换 |
| **液滴高光** | 偏心小椭圆 `nvgEllipse` 白色半透明 |
| **液滴径向渐变** | `nvgRadialGradient` 偏心亮→暗 |
| **融入涟漪** | 阻尼正弦波叠加在顶层 sin 波浪上 |
| 管口高光 | `nvgStrokeWidth(2)` + 半透明白色 `nvgStroke` |

## 8. 开发顺序

| 步骤 | 文件 | 内容 | 验证方式 |
|------|------|------|----------|
| 1 | Config + main | 框架搭建 + UI.Init + NanoVG 事件 + HUD 按钮 | 深色渐变背景 + 两个按钮 |
| 2 | TubeRenderer | 静态试管渲染（管壁 + 双侧高光 + 衬底 + 管口高光 + 投影） | 5 根空玻璃试管 |
| 3 | TubeRenderer | 静态液体 + sin 波浪液面 + Scissor 裁剪 | 填满彩色液体的试管，液面持续微动 |
| 4 | GameState + main | 数据层 + 点击流程（无动画，瞬间切换） | 点击两管液体瞬间转移 |
| 5 | InputHandler | 鼠标/触摸输入 + hitTest + UI 穿透 | 点击/触摸试管有响应 |
| 6 | AnimationManager | 选中上移 + 发光 | 点击试管有上移和发光反馈 |
| 7 | AnimationManager + TubeRenderer | 阶段 ①② 隆起 + 断裂 + 液滴生成 | 点击后液体鼓起、拉伸、断开 |
| 8 | AnimationManager + TubeRenderer | 阶段 ③ 贝塞尔飞行 + 液滴形变 + 旋转 | 液滴沿弧线飞行，形状动态变化 |
| 9 | AnimationManager + TubeRenderer | 阶段 ④⑤ 融入涟漪 + 沉降波纹衰减 | 液滴消失 → 涟漪扩散 → 液面上升 |
| 10 | AnimationManager | 非法震动 | 往满管倒时震动 |
| 11 | main | 重置 / 刷新按钮接线 | 按钮正常工作 |

## 9. 扩展路线图

以下功能在当前架构下可直接扩展，无需重构：

| 功能 | 扩展方式 | 涉及模块 |
|------|---------|---------|
| **关卡系统** | 新增 `LevelManager.lua`，`GameState:init(levelData)` 接收关卡数据 | + LevelManager, ~ GameState |
| **胜利检测** | `GameState:isComplete()` 已预留，main 中倒水后调用 | ~ main |
| **撤销/重做** | GameState 加 `history` 栈，`executePour` 前 push 快照 | ~ GameState |
| **计分系统** | GameState 加 `moves` 计数器，HUD 加 Label 显示 | ~ GameState, ~ main |
| **主题皮肤** | Config.lua 改为 `Config.loadTheme("ocean")`，TubeRenderer 读取主题颜色 | ~ Config, ~ TubeRenderer |
| **完成特效** | AnimationManager 加 `triggerComplete()` + 粒子/星星渲染 | ~ AnimationManager, ~ TubeRenderer |
| **音效** | main 中动画触发点加 `playSound()`，音效资源在 assets/ | ~ main |
| **关卡选择 UI** | 新增 `LevelSelectScreen.lua`，用 UI 组件构建 | + LevelSelectScreen |
| **教程引导** | 新增 `Tutorial.lua`，叠加高亮遮罩层 | + Tutorial |
| **试管数量变化** | `calcPositions` 已支持任意数量，AnimationManager.new(n) 动态初始化 | 无需改动 |
| **难度递增** | `GameState:randomize(colorCount, emptyCount)` 已支持参数化 | 无需改动 |

### 关键设计决策说明

**为什么倒水分两步（removeFromSource → 动画 → addToTarget），而不是一步完成？**

前一版方案采用延迟修改（动画期间用 hideFromTop 标记不渲染），但模块化后这会导致 GameState 和 AnimationManager 之间出现隐式数据依赖。当前方案将 `executePour` 拆分为两个封装方法：

1. main 调用 `game_:removeFromSource(fromIdx, toIdx)` 立即从源管移除，返回 `{ color, count }`
2. AnimationManager 接管飞行液滴的坐标/形变渲染（5 阶段）
3. 阶段 ④ 融入结束后 main 收到 `pourResult`，调用 `game_:addToTarget(toIdx, color, count)` 添加到目标管

这样 GameState 在动画期间处于"半完成"状态（源管已减、目标管未加），但数据操作完全封装在 GameState 内部，main 只调用公开方法，不直接操作 `game_.tubes`。两个模块各自保持独立。

> 注：`executePour` 保留为便捷方法，内部调用 `removeFromSource` + `addToTarget`，供无动画的瞬间倒水场景使用。

**为什么用 5 阶段而不是 2 阶段？**

可行性分析中指出，拉伸→断裂→飞行→融入→沉降的 5 段时间线能产生"视觉上令人信服"的流体效果，且本质上仍是参数化 2D 路径动画，不需要物理模拟。作为美术切片 Demo，这 5 个阶段是验证最终美术品质的最小完整集。
