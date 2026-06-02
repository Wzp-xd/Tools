local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")

-- ============================================================
-- 常量
-- ============================================================
local TUBE_WIDTH       = 56
local TUBE_HEIGHT      = 190
local TUBE_WALL        = 6
local TUBE_GAP         = 24
local TUBE_ROW_GAP     = 50
local LAYER_COUNT      = 4
local TUBE_BOTTOM_R    = 6

local SELECT_OFFSET    = 22
local SELECT_ANIM_SPD  = 12
local SHAKE_DURATION   = 0.3
local SHAKE_AMPLITUDE  = 5
local SHAKE_FREQ       = 7

local ANIM_MOVE_DUR    = 0.30
local ANIM_TILT_DUR    = 0.20
local ANIM_POUR_PER    = 0.28
local ANIM_RETURN_DUR  = 0.30
-- 倾斜角度根据剩余液体量动态计算(基于几何关系)
local TILT_ANGLE_MIN   = math.rad(18)   -- 满管时最小视觉角度
local TILT_ANGLE_MAX   = math.rad(100)  -- 最大倾斜角度上限(超过水平，确保倒空)

local WIN_BOUNCE_DUR   = 0.45
local WIN_BOUNCE_DELAY = 0.07
local WIN_PARTICLE_COUNT = 35

local COLORS = {
    { 230, 65,  65  },
    { 65,  140, 230 },
    { 70,  190, 90  },
    { 245, 205, 50  },
    { 170, 90,  210 },
    { 245, 150, 50  },
    { 50,  210, 210 },
    { 245, 130, 170 },
}

-- ============================================================
-- 数学工具
-- ============================================================
local function EaseInOutQuad(t)
    if t < 0.5 then return 2 * t * t
    else return -1 + (4 - 2 * t) * t end
end

local function EaseOutQuad(t)
    return t * (2 - t)
end

local function EaseOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

local function lerp(a, b, t) return a + (b - a) * t end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 根据剩余液体量计算所需倾斜角度(基于几何物理)
-- 原理: 液面要到达管口才能倒出
-- 倾斜角 α = atan((管内高度 - 液面高度) / 管内半宽)
-- remaining: 当前剩余层数(浮点)
local function getTiltAngleForRemaining(remaining)
    local innerH = TUBE_HEIGHT - 2 * TUBE_WALL               -- 管内可容液体高度(平底矩形)
    local halfInnerW = (TUBE_WIDTH - 2 * TUBE_WALL) / 2      -- 管内半宽
    local layerH = innerH / LAYER_COUNT
    local waterH = remaining * layerH  -- 液面高度(从管底算起)
    if waterH < 0.5 then
        return TILT_ANGLE_MAX  -- 几乎空管，直接最大角度，避免残留
    end
    local deficit = innerH - waterH    -- 液面距管口的距离
    if deficit <= 0 then
        return TILT_ANGLE_MIN  -- 满管，最小角度即可
    end
    -- 物理角度: 需要将液面在倾倒侧抬升 deficit 这么多
    local angle = math.atan(deficit / halfInnerW)
    -- 不足1层时,从物理角度平滑过渡到最大角度(物理公式极限≈83°,不够倒空)
    if remaining < 1 then
        local t = 1 - remaining  -- 0→1 随液体减少
        angle = angle + (TILT_ANGLE_MAX - angle) * t
    end
    return clamp(angle, TILT_ANGLE_MIN, TILT_ANGLE_MAX)
end

-- 旋转点 (px,py) 绕 (ox,oy) 旋转 angle 弧度
local function rotatePoint(px, py, ox, oy, angle)
    local dx = px - ox
    local dy = py - oy
    local c = math.cos(angle)
    local s = math.sin(angle)
    return ox + dx * c - dy * s, oy + dx * s + dy * c
end

-- ============================================================
-- 游戏状态
-- ============================================================
local gameState = {
    tubes = {},
    tubeCount = 0,
    colorCount = 0,
    selectedTube = nil,
    level = 1,
    isAnimating = false,
    isWin = false,
}

local tubeOffsetY = {}

local animState = {
    phase = "none",
    timer = 0,
    srcIdx = 0,
    dstIdx = 0,
    pourLayers = 0,
    pouredSoFar = 0,     -- 连续浮点进度 0~pourLayers
    pourColor = 0,
    tiltDir = 1,
    srcOrigLayers = {},
}

local shakeState = { tubeIdx = nil, timer = 0 }

local winState = { timer = 0, particles = {}, active = false }

local undoStack = {}
local canvasWidget = nil
local globalTime = 0

-- ============================================================
-- 关卡
-- ============================================================
local LEVEL_CONFIG = {
    { tubes = 5, colors = 3, empty = 2 },
    { tubes = 5, colors = 3, empty = 2 },
    { tubes = 5, colors = 3, empty = 2 },
    { tubes = 6, colors = 4, empty = 2 },
    { tubes = 6, colors = 4, empty = 2 },
    { tubes = 6, colors = 4, empty = 2 },
    { tubes = 7, colors = 5, empty = 2 },
    { tubes = 7, colors = 5, empty = 2 },
    { tubes = 8, colors = 6, empty = 2 },
    { tubes = 8, colors = 6, empty = 2 },
    { tubes = 9, colors = 7, empty = 2 },
    { tubes = 9, colors = 7, empty = 2 },
    { tubes = 10, colors = 8, empty = 2 },
}

local function getLevelConfig(level)
    if level <= #LEVEL_CONFIG then return LEVEL_CONFIG[level] end
    return { tubes = 10, colors = 8, empty = 2 }
end

local function shuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function generateLevel(level)
    local cfg = getLevelConfig(level)
    gameState.tubeCount = cfg.tubes
    gameState.colorCount = cfg.colors
    gameState.level = level
    gameState.selectedTube = nil
    gameState.isAnimating = false
    gameState.isWin = false
    undoStack = {}

    local allLayers = {}
    for c = 1, cfg.colors do
        for _ = 1, LAYER_COUNT do
            table.insert(allLayers, c)
        end
    end
    shuffleArray(allLayers)

    gameState.tubes = {}
    local idx = 1
    for i = 1, cfg.colors do
        gameState.tubes[i] = {}
        for j = 1, LAYER_COUNT do
            gameState.tubes[i][j] = allLayers[idx]
            idx = idx + 1
        end
    end
    for i = cfg.colors + 1, cfg.tubes do
        gameState.tubes[i] = {}
    end

    tubeOffsetY = {}
    for i = 1, cfg.tubes do tubeOffsetY[i] = 0 end

    winState.active = false
    winState.timer = 0
    winState.particles = {}
    animState.phase = "none"
end

-- ============================================================
-- 游戏逻辑
-- ============================================================
local function getTopColor(tube)
    if #tube == 0 then return nil end
    return tube[#tube]
end

local function getTopConsecutiveCount(tube)
    if #tube == 0 then return 0 end
    local topColor = tube[#tube]
    local count = 0
    for i = #tube, 1, -1 do
        if tube[i] == topColor then count = count + 1
        else break end
    end
    return count
end

local function canPour(srcIdx, dstIdx)
    local src = gameState.tubes[srcIdx]
    local dst = gameState.tubes[dstIdx]
    if #src == 0 or srcIdx == dstIdx then return false end
    local dstSpace = LAYER_COUNT - #dst
    if dstSpace <= 0 then return false end
    local dstTop = getTopColor(dst)
    if dstTop ~= nil and dstTop ~= getTopColor(src) then return false end
    return true
end

local function getPourCount(srcIdx, dstIdx)
    local src = gameState.tubes[srcIdx]
    local dst = gameState.tubes[dstIdx]
    return math.min(getTopConsecutiveCount(src), LAYER_COUNT - #dst)
end

local function checkWin()
    for i = 1, gameState.tubeCount do
        local tube = gameState.tubes[i]
        if #tube > 0 then
            if #tube ~= LAYER_COUNT then return false end
            local first = tube[1]
            for j = 2, #tube do
                if tube[j] ~= first then return false end
            end
        end
    end
    return true
end

local function saveUndoState()
    local snapshot = {}
    for i = 1, gameState.tubeCount do
        snapshot[i] = {}
        for j = 1, #gameState.tubes[i] do snapshot[i][j] = gameState.tubes[i][j] end
    end
    table.insert(undoStack, snapshot)
end

local function doUndo()
    if #undoStack == 0 or gameState.isAnimating then return end
    gameState.tubes = table.remove(undoStack)
    gameState.selectedTube = nil
    gameState.isWin = false
    winState.active = false
end

local function initWinParticles()
    winState.particles = {}
    for _ = 1, WIN_PARTICLE_COUNT do
        table.insert(winState.particles, {
            x = math.random() * 0.6 + 0.2,
            y = 0.4 + math.random() * 0.2,
            vx = (math.random() - 0.5) * 250,
            vy = -math.random() * 350 - 80,
            color = math.random(1, #COLORS),
            size = math.random(5, 11),
            life = 1.0,
            decay = 0.5 + math.random() * 0.4,
        })
    end
end

local function finishPour()
    gameState.tubes[animState.srcIdx] = animState.srcOrigLayers
    local src = gameState.tubes[animState.srcIdx]
    local dst = gameState.tubes[animState.dstIdx]
    for _ = 1, animState.pourLayers do
        table.insert(dst, table.remove(src))
    end
    animState.phase = "none"
    gameState.isAnimating = false
    if checkWin() then
        gameState.isWin = true
        winState.active = true
        winState.timer = 0
        initWinParticles()
    end
end

local function executePour(srcIdx, dstIdx)
    local count = getPourCount(srcIdx, dstIdx)
    if count == 0 then return end
    saveUndoState()
    local src = gameState.tubes[srcIdx]
    animState.srcIdx = srcIdx
    animState.dstIdx = dstIdx
    animState.pourLayers = count
    animState.pouredSoFar = 0
    animState.pourColor = getTopColor(src)
    animState.srcOrigLayers = {}
    for j = 1, #src do animState.srcOrigLayers[j] = src[j] end
    animState.phase = "move"
    animState.timer = 0
    gameState.isAnimating = true
    gameState.selectedTube = nil
end

-- ============================================================
-- 布局
-- ============================================================
local function getTubePositions(canvasW, canvasH)
    local positions = {}
    local count = gameState.tubeCount
    if count <= 5 then
        local totalW = count * TUBE_WIDTH + (count - 1) * TUBE_GAP
        local startX = (canvasW - totalW) / 2
        local centerY = canvasH / 2
        for i = 1, count do
            positions[i] = {
                x = startX + (i - 1) * (TUBE_WIDTH + TUBE_GAP) + TUBE_WIDTH / 2,
                y = centerY,
            }
        end
    else
        local topCount = math.ceil(count / 2)
        local botCount = count - topCount
        local topTotalW = topCount * TUBE_WIDTH + (topCount - 1) * TUBE_GAP
        local botTotalW = botCount * TUBE_WIDTH + (botCount - 1) * TUBE_GAP
        local centerY = canvasH / 2
        local topY = centerY - TUBE_ROW_GAP / 2 - TUBE_HEIGHT / 4
        local botY = centerY + TUBE_ROW_GAP / 2 + TUBE_HEIGHT / 4
        local topStartX = (canvasW - topTotalW) / 2
        for i = 1, topCount do
            positions[i] = {
                x = topStartX + (i - 1) * (TUBE_WIDTH + TUBE_GAP) + TUBE_WIDTH / 2,
                y = topY,
            }
        end
        local botStartX = (canvasW - botTotalW) / 2
        for i = 1, botCount do
            positions[topCount + i] = {
                x = botStartX + (i - 1) * (TUBE_WIDTH + TUBE_GAP) + TUBE_WIDTH / 2,
                y = botY,
            }
        end
    end
    return positions
end

-- ============================================================
-- 绘制: 试管内部几何辅助
-- 试管内部区域参数(相对于试管中心cx,cy)
-- ============================================================
local function tubeInnerMetrics()
    local halfW = TUBE_WIDTH / 2
    local halfH = TUBE_HEIGHT / 2
    local innerHalfW = halfW - TUBE_WALL
    local floorYOffset = halfH - TUBE_WALL       -- 管内底面相对cy的偏移
    local innerH = TUBE_HEIGHT - 2 * TUBE_WALL   -- 可容液体高度(平底矩形: 管口rim到管底)
    local layerH = innerH / LAYER_COUNT
    return {
        innerHalfW = innerHalfW,
        floorYOffset = floorYOffset,
        innerH = innerH,
        layerH = layerH,
    }
end

-- ============================================================
-- NanoVG 绘制
-- ============================================================
local GameCanvas = Widget:Extend("GameCanvas")

function GameCanvas:Render(nvg)
    self:RenderFullBackground(nvg)
    local l = self:GetAbsoluteLayout()
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 渐变背景
    local bgPaint = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h,
        nvgRGBA(232, 236, 244, 255), nvgRGBA(246, 248, 255, 255))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, bgPaint)
    nvgFill(nvg)

    local positions = getTubePositions(l.w, l.h)

    -- 阴影层
    for i = 1, gameState.tubeCount do
        if not (animState.phase ~= "none" and i == animState.srcIdx) then
            local pos = positions[i]
            local cx = l.x + pos.x
            local cy = l.y + pos.y + (tubeOffsetY[i] or 0)
            nvgBeginPath(nvg)
            nvgEllipse(nvg, cx + 2, cy + TUBE_HEIGHT / 2 + 5, TUBE_WIDTH / 2 - 4, 4)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 20))
            nvgFill(nvg)
        end
    end

    -- 静态试管
    for i = 1, gameState.tubeCount do
        if animState.phase ~= "none" and i == animState.srcIdx then
            goto continue
        end

        local pos = positions[i]
        local cx = l.x + pos.x
        local cy = l.y + pos.y + (tubeOffsetY[i] or 0)

        -- 抖动
        local shakeX = 0
        if shakeState.tubeIdx == i and shakeState.timer > 0 then
            local p = 1 - shakeState.timer / SHAKE_DURATION
            shakeX = math.sin(p * math.pi * SHAKE_FREQ * 2) * SHAKE_AMPLITUDE * (1 - p)
        end

        -- 通关弹跳
        local bounceY = 0
        if winState.active then
            local delay = (i - 1) * WIN_BOUNCE_DELAY
            local bt = clamp((winState.timer - delay) / WIN_BOUNCE_DUR, 0, 1)
            if bt > 0 then bounceY = -math.sin(bt * math.pi) * 18 end
        end

        -- 目标管动画时连续水面上升
        local extraFill = 0  -- 额外填充比例 (0~1 每层)
        local extraColor = nil
        if (animState.phase == "pour" or animState.phase == "return") and i == animState.dstIdx then
            extraFill = animState.pouredSoFar
            extraColor = animState.pourColor
        end

        self:drawStaticTube(nvg, cx + shakeX, cy + bounceY, gameState.tubes[i], extraFill, extraColor)

        -- 选中光圈
        if gameState.selectedTube == i then
            nvgBeginPath(nvg)
            nvgEllipse(nvg, cx + shakeX, cy + TUBE_HEIGHT / 2 + 8 + bounceY, TUBE_WIDTH / 2, 5)
            nvgFillColor(nvg, nvgRGBA(90, 170, 255, 70))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgEllipse(nvg, cx + shakeX, cy + TUBE_HEIGHT / 2 + 8 + bounceY, TUBE_WIDTH / 2 - 6, 3)
            nvgFillColor(nvg, nvgRGBA(120, 200, 255, 50))
            nvgFill(nvg)
        end

        ::continue::
    end

    -- 动画源试管
    if animState.phase ~= "none" then
        self:drawAnimSource(nvg, l, positions)
    end

    -- 通关效果
    if winState.active then
        self:drawWinParticles(nvg, l)
    end
    if gameState.isWin then
        self:drawWinText(nvg, l)
    end

    nvgRestore(nvg)
end

-- 绘制静态(直立)试管
function GameCanvas:drawStaticTube(nvg, cx, cy, layers, extraFill, extraColor)
    local m = tubeInnerMetrics()
    local halfW = TUBE_WIDTH / 2
    local halfH = TUBE_HEIGHT / 2
    local tubeLeft = cx - halfW
    local tubeTop = cy - halfH
    local floorY = cy + m.floorYOffset  -- 管内底面Y

    -- === 水层 ===
    local totalLayers = #layers
    local extraLayers = 0
    local extraFrac = 0
    if extraFill and extraFill > 0 then
        extraLayers = math.floor(extraFill)
        extraFrac = extraFill - extraLayers
    end

    -- 绘制已有层 + 额外层
    local drawCount = totalLayers + extraLayers + (extraFrac > 0 and 1 or 0)
    for j = 1, math.min(drawCount, LAYER_COUNT) do
        local colorIdx
        local thisH = m.layerH
        if j <= totalLayers then
            colorIdx = layers[j]
        else
            colorIdx = extraColor
            -- 最后的分数层
            if j == totalLayers + extraLayers + 1 and extraFrac > 0 then
                thisH = m.layerH * extraFrac
            end
        end

        local color = COLORS[colorIdx]
        if not color then goto nextLayer end

        local layerBottom = floorY - (j - 1) * m.layerH
        local layerTop = layerBottom - thisH

        nvgBeginPath(nvg)
        nvgRect(nvg, cx - m.innerHalfW, layerTop, m.innerHalfW * 2, layerBottom - layerTop)

        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 230))
        nvgFill(nvg)

        -- 顶层水面光泽
        if j == drawCount or j == LAYER_COUNT then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx - m.innerHalfW + 5, layerTop + 1, m.innerHalfW * 2 - 10, 2.5, 1)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 60))
            nvgFill(nvg)
        end

        -- 层间线
        if j > 1 and j <= totalLayers then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, cx - m.innerHalfW + 2, layerBottom)
            nvgLineTo(nvg, cx + m.innerHalfW - 2, layerBottom)
            nvgStrokeColor(nvg, nvgRGBA(
                math.floor(color[1] * 0.6),
                math.floor(color[2] * 0.6),
                math.floor(color[3] * 0.6), 100))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end

        ::nextLayer::
    end

    -- === 玻璃外壳 ===
    self:drawGlassShell(nvg, cx, cy)
end

-- 绘制玻璃外壳(管壁)
function GameCanvas:drawGlassShell(nvg, cx, cy)
    local halfW = TUBE_WIDTH / 2
    local halfH = TUBE_HEIGHT / 2
    local tubeLeft = cx - halfW
    local tubeRight = cx + halfW
    local tubeTop = cy - halfH
    local tubeBottom = cy + halfH
    local outerR = TUBE_BOTTOM_R + TUBE_WALL  -- 外壁底部圆角
    local innerR = TUBE_BOTTOM_R               -- 内壁底部圆角
    local innerLeft = tubeLeft + TUBE_WALL
    local innerRight = tubeRight - TUBE_WALL
    local innerBottom = tubeBottom - TUBE_WALL

    -- 半透明壁填充 (外壁路径 + 内壁路径反向)
    nvgBeginPath(nvg)
    -- 外壁: 左上 → 左下 → 底左圆角 → 底平 → 底右圆角 → 右上
    nvgMoveTo(nvg, tubeLeft, tubeTop)
    nvgLineTo(nvg, tubeLeft, tubeBottom - outerR)
    nvgArc(nvg, tubeLeft + outerR, tubeBottom - outerR, outerR, math.pi, math.pi * 0.5, 1)
    nvgLineTo(nvg, tubeRight - outerR, tubeBottom)
    nvgArc(nvg, tubeRight - outerR, tubeBottom - outerR, outerR, math.pi * 0.5, 0, 1)
    nvgLineTo(nvg, tubeRight, tubeTop)
    -- 内壁回(反向矩形，与水层底部对齐): 右上 → 右下 → 左下 → 左上
    nvgLineTo(nvg, innerRight, tubeTop)
    nvgLineTo(nvg, innerRight, innerBottom)
    nvgLineTo(nvg, innerLeft, innerBottom)
    nvgLineTo(nvg, innerLeft, tubeTop)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(200, 215, 240, 40))
    nvgFill(nvg)

    -- 外轮廓描边
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, tubeLeft, tubeTop)
    nvgLineTo(nvg, tubeLeft, tubeBottom - outerR)
    nvgArc(nvg, tubeLeft + outerR, tubeBottom - outerR, outerR, math.pi, math.pi * 0.5, 1)
    nvgLineTo(nvg, tubeRight - outerR, tubeBottom)
    nvgArc(nvg, tubeRight - outerR, tubeBottom - outerR, outerR, math.pi * 0.5, 0, 1)
    nvgLineTo(nvg, tubeRight, tubeTop)
    nvgStrokeColor(nvg, nvgRGBA(170, 185, 210, 180))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 管口装饰
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tubeLeft - 1, tubeTop - 2, TUBE_WIDTH + 2, 4, 2)
    nvgFillColor(nvg, nvgRGBA(170, 185, 210, 140))
    nvgFill(nvg)

    -- 左高光
    local hlPaint = nvgLinearGradient(nvg, tubeLeft + 2, tubeTop, tubeLeft + 7, tubeTop,
        nvgRGBA(255, 255, 255, 50), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, tubeLeft + 2, tubeTop + 8, 4, TUBE_HEIGHT - TUBE_BOTTOM_R - 16)
    nvgFillPaint(nvg, hlPaint)
    nvgFill(nvg)
end

-- ============================================================
-- 倾斜试管绘制 (水面保持水平)
-- ============================================================
function GameCanvas:drawAnimSource(nvg, layout, positions)
    local srcPos = positions[animState.srcIdx]
    local dstPos = positions[animState.dstIdx]
    local srcCX = layout.x + srcPos.x
    local srcCY = layout.y + srcPos.y + (tubeOffsetY[animState.srcIdx] or 0)
    local dstCX = layout.x + dstPos.x
    local dstCY = layout.y + dstPos.y + (tubeOffsetY[animState.dstIdx] or 0)

    local isLeft = srcPos.x <= dstPos.x
    animState.tiltDir = isLeft and 1 or -1

    local halfW = TUBE_WIDTH / 2

    -- 旋转中心: 管口靠近目标侧的角点
    -- 当源在左时, 旋转中心是管口右角 (cx + halfW, cy - halfH)
    -- 当源在右时, 旋转中心是管口左角 (cx - halfW, cy - halfH)
    local pivotLocalX = isLeft and halfW or -halfW
    local pivotLocalY = -TUBE_HEIGHT / 2

    -- 移动目标: 使旋转中心(管口角)对齐到目标管口旁5px
    local targetPivotX = dstCX + (isLeft and -5 or 5)
    local targetPivotY = dstCY - TUBE_HEIGHT / 2 - 30
    -- 反推试管中心
    local targetCX = targetPivotX - pivotLocalX
    local targetCY = targetPivotY - pivotLocalY

    -- 当前试管中心位置和角度
    local curCX, curCY, curAngle = srcCX, srcCY, 0

    -- 动态角度: 基于源管当前剩余液体量
    local srcTotal = #animState.srcOrigLayers  -- 倒水前总层数
    -- 倒水开始时的角度(基于初始液面)
    local angleStart = getTiltAngleForRemaining(srcTotal)
    -- 倒水结束时的角度(基于倒完后液面)
    local angleEnd = getTiltAngleForRemaining(srcTotal - animState.pourLayers)

    if animState.phase == "move" then
        local t = EaseInOutQuad(clamp(animState.timer / ANIM_MOVE_DUR, 0, 1))
        curCX = lerp(srcCX, targetCX, t)
        curCY = lerp(srcCY, targetCY, t)
    elseif animState.phase == "tilt" then
        curCX = targetCX
        curCY = targetCY
        local t = EaseOutQuad(clamp(animState.timer / ANIM_TILT_DUR, 0, 1))
        curAngle = angleStart * animState.tiltDir * t
    elseif animState.phase == "pour" then
        curCX = targetCX
        curCY = targetCY
        -- 物理正确: 根据当前剩余液量实时计算角度，保证水面始终在管口
        local effectiveRemaining = srcTotal - animState.pouredSoFar
        curAngle = getTiltAngleForRemaining(effectiveRemaining) * animState.tiltDir
    elseif animState.phase == "return" then
        local t = EaseInOutQuad(clamp(animState.timer / ANIM_RETURN_DUR, 0, 1))
        curCX = lerp(targetCX, srcCX, t)
        curCY = lerp(targetCY, srcCY, t)
        curAngle = angleEnd * animState.tiltDir * (1 - t)
    end

    -- 当前显示层数
    local origLayers = animState.srcOrigLayers
    local removedCount = 0
    if animState.phase == "pour" then
        removedCount = animState.pouredSoFar  -- 浮点，连续
    elseif animState.phase == "return" then
        removedCount = animState.pourLayers
    end

    -- 旋转中心(世界坐标)
    local pivotWX = curCX + pivotLocalX
    local pivotWY = curCY + pivotLocalY

    -- 绘制旋转的管壁
    nvgSave(nvg)
    nvgTranslate(nvg, pivotWX, pivotWY)
    nvgRotate(nvg, curAngle)
    nvgTranslate(nvg, -pivotWX, -pivotWY)
    self:drawGlassShell(nvg, curCX, curCY)
    nvgRestore(nvg)

    -- 绘制管内水层(水面保持水平)
    if #origLayers - math.floor(removedCount) > 0 then
        self:drawTiltedWater(nvg, curCX, curCY, pivotWX, pivotWY, curAngle,
            origLayers, removedCount)
    end

    -- 绘制水流
    if animState.phase == "pour" and removedCount < animState.pourLayers then
        self:drawWaterStream(nvg, curCX, curCY, pivotWX, pivotWY, curAngle,
            dstCX, dstCY, isLeft)
    end
end

-- 线段与水平线交点: 给定线段(x1,y1)-(x2,y2)和水平线y=hY, 返回交点x
-- 如果无交点(平行或不在线段范围内)返回nil
local function segHIntersect(x1, y1, x2, y2, hY)
    if (y1 - hY) * (y2 - hY) > 0 then return nil end  -- 同侧无交点
    if math.abs(y2 - y1) < 0.001 then return nil end  -- 近水平线段
    local t = (hY - y1) / (y2 - y1)
    if t < -0.01 or t > 1.01 then return nil end
    return x1 + t * (x2 - x1)
end

-- 绘制倾斜管中的水(水面始终水平于地面)
function GameCanvas:drawTiltedWater(nvg, cx, cy, pivotWX, pivotWY, angle, origLayers, removedCount)
    local m = tubeInnerMetrics()
    local halfH = TUBE_HEIGHT / 2

    local remaining = #origLayers - removedCount
    if remaining <= 0.05 then return end  -- 近似空管不渲染残留

    -- 管内几何(未旋转,世界坐标)
    local innerLeft = cx - m.innerHalfW
    local innerRight = cx + m.innerHalfW
    local innerTop = cy - halfH
    local innerBottom = cy + halfH - TUBE_WALL  -- 管内底面

    -- 旋转后的管内四角(简单矩形，无底部圆角)
    local ltx, lty = rotatePoint(innerLeft, innerTop, pivotWX, pivotWY, angle)
    local lbx, lby = rotatePoint(innerLeft, innerBottom, pivotWX, pivotWY, angle)
    local rbx, rby = rotatePoint(innerRight, innerBottom, pivotWX, pivotWY, angle)
    local rtx, rty = rotatePoint(innerRight, innerTop, pivotWX, pivotWY, angle)

    -- 构建管内轮廓(旋转后，从左上开始顺时针，纯矩形)
    local outline = {}
    table.insert(outline, { x = ltx, y = lty })  -- 左上(管口)
    table.insert(outline, { x = lbx, y = lby })  -- 左下
    table.insert(outline, { x = rbx, y = rby })  -- 右下
    table.insert(outline, { x = rtx, y = rty })  -- 右上(管口)

    -- 计算水面世界Y坐标 (基于体积守恒 + 倾斜偏移)
    -- 原理: 在管局部坐标系中，液体平均高度 = remaining*layerH
    -- 倾斜时，液面在倾倒侧上升 halfInnerW*tan(|angle|)
    -- 取倾倒侧墙面上的水面点，旋转到世界坐标，得到水面Y
    
    local absAngle = math.abs(angle)
    local innerH = m.innerH
    local halfInnerW = m.innerHalfW

    -- 获取剩余层信息
    local floorRemoved = math.floor(removedCount)
    local fracRemoved = removedCount - floorRemoved
    local layersToShow = {}
    for j = 1, #origLayers - floorRemoved do
        layersToShow[j] = origLayers[j]
    end

    -- 有效剩余量
    local effectiveRemaining = remaining
    if #layersToShow > 0 and fracRemoved > 0 then
        effectiveRemaining = #layersToShow - fracRemoved
    end

    -- 角度 >= 90° 时: 以倾倒侧管壁为底的矩形渲染(避免tan奇异)
    if absAngle >= math.pi * 0.5 then
        -- 体积守恒: 面积 = effectiveRemaining * layerH * 管内宽, 厚度 = 面积 / 管高
        local thickness = effectiveRemaining * m.layerH * (2 * halfInnerW) / innerH
        if thickness < 0.5 then return end  -- 太薄不渲染

        -- 在管局部坐标中构建贴壁矩形
        local rectX1, rectX2
        if angle >= 0 then
            -- 倾倒侧是右壁
            rectX1 = innerRight - thickness
            rectX2 = innerRight
        else
            -- 倾倒侧是左壁
            rectX1 = innerLeft
            rectX2 = innerLeft + thickness
        end
        local rectY1 = innerTop
        local rectY2 = innerBottom

        -- 旋转四角到世界坐标
        local p1x, p1y = rotatePoint(rectX1, rectY1, pivotWX, pivotWY, angle)
        local p2x, p2y = rotatePoint(rectX2, rectY1, pivotWX, pivotWY, angle)
        local p3x, p3y = rotatePoint(rectX2, rectY2, pivotWX, pivotWY, angle)
        local p4x, p4y = rotatePoint(rectX1, rectY2, pivotWX, pivotWY, angle)

        -- 取最底层颜色(倒空时只剩最后一层)
        local colorIdx = layersToShow[1]
        local color = colorIdx and COLORS[colorIdx]
        if not color then return end

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, p1x, p1y)
        nvgLineTo(nvg, p2x, p2y)
        nvgLineTo(nvg, p3x, p3y)
        nvgLineTo(nvg, p4x, p4y)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 225))
        nvgFill(nvg)
        return  -- 直接返回，不执行后续tan-based逻辑
    end

    -- 倾倒侧液面高度(管局部坐标，从管底innerBottom往上)
    local avgH = effectiveRemaining * m.layerH
    local tanA = absAngle > 0.001 and math.tan(absAngle) or 0
    local hPour = avgH + halfInnerW * tanA  -- 倾倒侧液面高度
    hPour = math.min(hPour, innerH)          -- 不超过管高(超出=溢出/倒水)

    -- 倾倒侧墙面上的水面点(管局部坐标，未旋转)
    -- 倾倒侧X = angle>0时右墙(cx+halfInnerW), angle<0时左墙(cx-halfInnerW)
    local pourWallX
    if angle >= 0 then
        pourWallX = cx + halfInnerW
    else
        pourWallX = cx - halfInnerW
    end
    local pourWallWaterLocalY = innerBottom - hPour  -- 管局部Y坐标

    -- 旋转到世界坐标
    local _, waterY = rotatePoint(pourWallX, pourWallWaterLocalY, pivotWX, pivotWY, angle)

    -- 如果角度为0或极小，使用静态一致的水面位置
    if absAngle < 0.001 then
        waterY = innerBottom - effectiveRemaining * m.layerH
    end

    -- 找到管内最低点(世界Y最大) - 用于层分割
    local maxY = outline[1].y
    for _, pt in ipairs(outline) do
        if pt.y > maxY then maxY = pt.y end
    end

    -- 用水平线 y=waterY 裁剪管内轮廓，获取 waterY 以下的多边形
    -- 算法: 遍历轮廓线段，构建裁剪后的多边形
    local clippedPoly = {}
    for i = 1, #outline do
        local cur = outline[i]
        local nxt = outline[(i % #outline) + 1]
        local curBelow = cur.y >= waterY  -- 在水面线下方(y值更大)
        local nxtBelow = nxt.y >= waterY

        if curBelow then
            table.insert(clippedPoly, cur)
        end

        -- 如果线段跨越水面线，加入交点
        if curBelow ~= nxtBelow then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, waterY)
            if ix then
                table.insert(clippedPoly, { x = ix, y = waterY })
            end
        end
    end

    if #clippedPoly < 3 then return end

    -- 分层着色: 每层边界也用同样的物理公式计算世界Y
    -- 层j的边界(从底往上计): 局部高度 = j*layerH, 倾倒侧 += halfInnerW*tanA
    local layerYPositions = {}  -- layerYPositions[j] = j层顶部的世界Y
    for j = 0, #layersToShow do
        if j == 0 then
            -- 第0层底部 = 管底最低点
            layerYPositions[0] = maxY
        else
            -- 第j层顶部: 用物理公式计算
            local hJ = j * m.layerH + halfInnerW * tanA
            hJ = math.min(hJ, innerH)
            local localY_j = innerBottom - hJ
            if absAngle < 0.001 then
                layerYPositions[j] = localY_j
            else
                local _, worldY_j = rotatePoint(pourWallX, localY_j, pivotWX, pivotWY, angle)
                layerYPositions[j] = worldY_j
            end
        end
    end

    -- Sutherland-Hodgman 多边形裁剪: 裁剪到 y >= clipY 的半平面
    local function clipPolyAbove(poly, clipY)
        -- 保留 y >= clipY 的部分 (屏幕坐标，y大=下方)
        if #poly == 0 then return {} end
        local out = {}
        for i = 1, #poly do
            local cur = poly[i]
            local nxt = poly[(i % #poly) + 1]
            local curIn = cur.y >= clipY - 0.01
            local nxtIn = nxt.y >= clipY - 0.01
            if curIn and nxtIn then
                -- 两点都在内侧
                table.insert(out, nxt)
            elseif curIn and not nxtIn then
                -- cur在内，nxt在外 → 输出交点
                local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
                if ix then table.insert(out, { x = ix, y = clipY }) end
            elseif not curIn and nxtIn then
                -- cur在外，nxt在内 → 输出交点 + nxt
                local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
                if ix then table.insert(out, { x = ix, y = clipY }) end
                table.insert(out, nxt)
            end
            -- 两点都在外侧: 不输出
        end
        return out
    end

    -- Sutherland-Hodgman 多边形裁剪: 裁剪到 y <= clipY 的半平面
    local function clipPolyBelow(poly, clipY)
        -- 保留 y <= clipY 的部分
        if #poly == 0 then return {} end
        local out = {}
        for i = 1, #poly do
            local cur = poly[i]
            local nxt = poly[(i % #poly) + 1]
            local curIn = cur.y <= clipY + 0.01
            local nxtIn = nxt.y <= clipY + 0.01
            if curIn and nxtIn then
                table.insert(out, nxt)
            elseif curIn and not nxtIn then
                local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
                if ix then table.insert(out, { x = ix, y = clipY }) end
            elseif not curIn and nxtIn then
                local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
                if ix then table.insert(out, { x = ix, y = clipY }) end
                table.insert(out, nxt)
            end
        end
        return out
    end

    -- 裁剪多边形到水平带 [bandTopY, bandBottomY]
    local function clipPolyBand(poly, bandTopY, bandBottomY)
        local result = clipPolyAbove(poly, bandTopY)   -- y >= bandTopY
        result = clipPolyBelow(result, bandBottomY)     -- y <= bandBottomY
        return result
    end

    -- 绘制每层颜色
    for j = 1, #layersToShow do
        local colorIdx = layersToShow[j]
        local color = COLORS[colorIdx]
        if not color then goto nextTiltLayer end

        -- 第j层: 底部Y = layerYPositions[j-1], 顶部Y = layerYPositions[j]
        local bandBottom = layerYPositions[j - 1] or maxY
        local bandTop = layerYPositions[j] or waterY

        -- 最顶层分数消耗调整
        if j == #layersToShow and fracRemoved > 0 then
            bandTop = waterY
        end

        -- 确保 bandTop <= bandBottom (Y轴向下)
        if bandTop > bandBottom then bandTop, bandBottom = bandBottom, bandTop end

        local band = clipPolyBand(clippedPoly, bandTop, bandBottom)
        if #band >= 3 then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, band[1].x, band[1].y)
            for k = 2, #band do
                nvgLineTo(nvg, band[k].x, band[k].y)
            end
            nvgClosePath(nvg)
            nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 225))
            nvgFill(nvg)
        end

        -- 层间分隔线
        if j > 1 then
            -- 找到 bandBottom 线与管壁的交点画分隔线
            local sepY = bandBottom
            local sepLeftX = segHIntersect(ltx, lty, lbx, lby, sepY)
                or segHIntersect(lbx, lby, rbx, rby, sepY)
            local sepRightX = segHIntersect(rtx, rty, rbx, rby, sepY)
                or segHIntersect(rbx, rby, lbx, lby, sepY)
            if sepLeftX and sepRightX then
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, sepLeftX + 2, sepY)
                nvgLineTo(nvg, sepRightX - 2, sepY)
                nvgStrokeColor(nvg, nvgRGBA(
                    math.floor(color[1] * 0.6),
                    math.floor(color[2] * 0.6),
                    math.floor(color[3] * 0.6), 80))
                nvgStrokeWidth(nvg, 1)
                nvgStroke(nvg)
            end
        end

        -- 顶层水面高光
        if j == #layersToShow then
            -- 水面线 = waterY，找到左右交点
            local hlLeftX = segHIntersect(ltx, lty, lbx, lby, waterY)
            local hlRightX = segHIntersect(rtx, rty, rbx, rby, waterY)
            if hlLeftX and hlRightX then
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, hlLeftX + 4, waterY + 1)
                nvgLineTo(nvg, hlRightX - 4, waterY + 1)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 60))
                nvgStrokeWidth(nvg, 2)
                nvgStroke(nvg)
            end
        end

        ::nextTiltLayer::
    end
end

-- 绘制水流
function GameCanvas:drawWaterStream(nvg, srcCX, srcCY, pivotWX, pivotWY, angle, dstCX, dstCY, isLeft)
    local color = COLORS[animState.pourColor]
    if not color then return end

    local halfW = TUBE_WIDTH / 2
    local halfH = TUBE_HEIGHT / 2

    -- 水流起点: 管口靠近目标侧的角(旋转后位置)
    local tipX = srcCX + (isLeft and halfW or -halfW)
    local tipY = srcCY - halfH
    local startX, startY = rotatePoint(tipX, tipY, pivotWX, pivotWY, angle)

    -- 水流终点: 目标管内液面高度
    local m = tubeInnerMetrics()
    local dstTube = gameState.tubes[animState.dstIdx]
    local dstLayers = #dstTube
    local fillTotal = dstLayers + animState.pouredSoFar  -- 已有层 + 正在倒入的层
    local floorY = dstCY + m.floorYOffset
    local surfaceY = floorY - fillTotal * m.layerH
    -- 限制不超过管口
    local mouthY = dstCY - halfH
    local endX = dstCX
    local endY = math.max(surfaceY, mouthY)

    -- 弧形水流(多段)
    local segments = 10
    local streamW = 7

    nvgBeginPath(nvg)
    -- 左侧轮廓
    for s = 0, segments do
        local t = s / segments
        -- X: 线性插值
        local px = lerp(startX, endX, t)
        -- Y: 二次曲线(自然下落弧线)
        local py = lerp(startY, endY, t * t)
        -- 宽度渐变(起始较细、中间较粗、末端细)
        local w = streamW * (0.6 + 0.4 * math.sin(t * math.pi))
        if s == 0 then
            nvgMoveTo(nvg, px - w / 2, py)
        else
            nvgLineTo(nvg, px - w / 2, py)
        end
    end
    -- 右侧轮廓(反向)
    for s = segments, 0, -1 do
        local t = s / segments
        local px = lerp(startX, endX, t)
        local py = lerp(startY, endY, t * t)
        local w = streamW * (0.6 + 0.4 * math.sin(t * math.pi))
        nvgLineTo(nvg, px + w / 2, py)
    end
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 210))
    nvgFill(nvg)

    -- 高光
    nvgBeginPath(nvg)
    for s = 0, segments do
        local t = s / segments
        local px = lerp(startX, endX, t) - 1
        local py = lerp(startY, endY, t * t)
        if s == 0 then nvgMoveTo(nvg, px, py)
        else nvgLineTo(nvg, px, py) end
    end
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 45))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

function GameCanvas:drawWinParticles(nvg, l)
    for _, p in ipairs(winState.particles) do
        if p.life > 0 then
            local c = COLORS[p.color]
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + p.x * l.w, l.y + p.y * l.h, p.size * p.life)
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(p.life * 220)))
            nvgFill(nvg)
        end
    end
end

function GameCanvas:drawWinText(nvg, l)
    local cx = l.x + l.w / 2
    local cy = l.y + 55
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 40)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 25))
    nvgText(nvg, cx + 1, cy + 2, "恭喜通关!")
    nvgFillColor(nvg, nvgRGBA(255, 195, 40, 255))
    nvgText(nvg, cx, cy, "恭喜通关!")
end

-- ============================================================
-- 交互
-- ============================================================
local function hitTestTube(localX, localY, canvasW, canvasH)
    local positions = getTubePositions(canvasW, canvasH)
    local padX, padY = 8, 12
    for i = 1, gameState.tubeCount do
        local pos = positions[i]
        local left = pos.x - TUBE_WIDTH / 2 - padX
        local right = pos.x + TUBE_WIDTH / 2 + padX
        local top = pos.y - TUBE_HEIGHT / 2 - SELECT_OFFSET - padY
        local bottom = pos.y + TUBE_HEIGHT / 2 + padY
        if localX >= left and localX <= right and localY >= top and localY <= bottom then
            return i
        end
    end
    return nil
end

local function handleTubeTap(tubeIdx)
    if gameState.isAnimating or gameState.isWin then return end
    if gameState.selectedTube == nil then
        if #gameState.tubes[tubeIdx] > 0 then
            gameState.selectedTube = tubeIdx
        end
    elseif gameState.selectedTube == tubeIdx then
        gameState.selectedTube = nil
    else
        local srcIdx = gameState.selectedTube
        if canPour(srcIdx, tubeIdx) then
            executePour(srcIdx, tubeIdx)
        else
            shakeState.tubeIdx = tubeIdx
            shakeState.timer = SHAKE_DURATION
            if #gameState.tubes[tubeIdx] > 0 then
                gameState.selectedTube = tubeIdx
            else
                gameState.selectedTube = nil
            end
        end
    end
end

-- ============================================================
-- 更新
-- ============================================================
local function updateAnimation(dt)
    if animState.phase == "none" then return end
    animState.timer = animState.timer + dt

    if animState.phase == "move" then
        if animState.timer >= ANIM_MOVE_DUR then
            animState.phase = "tilt"
            animState.timer = 0
        end
    elseif animState.phase == "tilt" then
        if animState.timer >= ANIM_TILT_DUR then
            animState.phase = "pour"
            animState.timer = 0
            animState.pouredSoFar = 0
        end
    elseif animState.phase == "pour" then
        animState.pouredSoFar = clamp(animState.timer / ANIM_POUR_PER, 0, animState.pourLayers)
        if animState.timer >= animState.pourLayers * ANIM_POUR_PER then
            animState.phase = "return"
            animState.timer = 0
            animState.pouredSoFar = animState.pourLayers
        end
    elseif animState.phase == "return" then
        if animState.timer >= ANIM_RETURN_DUR then
            finishPour()
        end
    end
end

local function updateShake(dt)
    if shakeState.timer > 0 then
        shakeState.timer = shakeState.timer - dt
        if shakeState.timer <= 0 then
            shakeState.timer = 0
            shakeState.tubeIdx = nil
        end
    end
end

local function updateTubeOffsets(dt)
    for i = 1, gameState.tubeCount do
        local target = (gameState.selectedTube == i) and -SELECT_OFFSET or 0
        local cur = tubeOffsetY[i] or 0
        local diff = target - cur
        if math.abs(diff) < 0.3 then
            tubeOffsetY[i] = target
        else
            tubeOffsetY[i] = cur + diff * math.min(1.0, SELECT_ANIM_SPD * dt)
        end
    end
end

local function updateWin(dt)
    if not winState.active then return end
    winState.timer = winState.timer + dt
    for _, p in ipairs(winState.particles) do
        if p.life > 0 then
            p.x = p.x + p.vx * dt / 600
            p.y = p.y + p.vy * dt / 600
            p.vy = p.vy + 450 * dt
            p.life = p.life - p.decay * dt
        end
    end
end

-- ============================================================
-- UI
-- ============================================================
local levelLabel = nil
local nextLevelBtn = nil

local function buildUI()
    levelLabel = UI.Label {
        text = "关卡: Lv." .. gameState.level,
        fontSize = 18,
        fontColor = { 255, 255, 255, 240 },
    }

    local undoBtn = UI.Button {
        text = "撤回",
        fontSize = 14,
        onClick = function() doUndo() end,
    }

    local resetBtn = UI.Button {
        text = "重置",
        fontSize = 14,
        onClick = function() generateLevel(gameState.level) end,
    }

    nextLevelBtn = UI.Button {
        text = "下一关",
        fontSize = 16,
        onClick = function()
            generateLevel(gameState.level + 1)
            levelLabel:SetText("关卡: Lv." .. gameState.level)
            nextLevelBtn:SetStyle({ opacity = 0 })
        end,
    }
    nextLevelBtn:SetStyle({ opacity = 0 })

    canvasWidget = GameCanvas {
        id = "gameCanvas",
        flexGrow = 1,
        width = "100%",
        onPointerDown = function(event, widget)
            if event.button == MOUSEB_LEFT then
                local lt = widget:GetAbsoluteLayout()
                local localX = event.x - lt.x
                local localY = event.y - lt.y
                local idx = hitTestTube(localX, localY, lt.w, lt.h)
                if idx then
                    handleTubeTap(idx)
                elseif not gameState.isAnimating then
                    gameState.selectedTube = nil
                end
            end
        end,
    }

    local topBar = UI.Panel {
        width = "100%",
        height = 46,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 16,
        backgroundColor = { 50, 55, 75, 255 },
        children = {
            levelLabel,
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = { undoBtn, resetBtn },
            },
        },
    }

    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 240, 242, 248, 255 },
        children = {
            topBar,
            canvasWidget,
            UI.Panel {
                width = "100%",
                height = 52,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 240, 242, 248, 255 },
                children = { nextLevelBtn },
            },
        },
    })
end

-- ============================================================
-- 入口
-- ============================================================
function Start()
    math.randomseed(os.time())
    UI.Init({
        fonts = {{ family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }},
        scale = UI.Scale.DEFAULT,
    })
    generateLevel(1)
    buildUI()
    SubscribeToEvent("Update", "HandleUpdate")
    log:Write(LOG_INFO, "WaterSort started")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    globalTime = globalTime + dt
    updateAnimation(dt)
    updateShake(dt)
    updateTubeOffsets(dt)
    updateWin(dt)
    if gameState.isWin and nextLevelBtn then
        nextLevelBtn:SetStyle({ opacity = 1 })
    end
end

function Stop()
    UI.Shutdown()
end
