--- TubeRenderer.lua — 试管+液体渲染（v2）
--- 试管形状：管口椭圆 + 直筒管壁 + Bézier 半椭圆球底
--- 液体形状：统一纯色矩形（直筒段）+ 椭圆液面 + 球底 Bézier 填充
local Config = require("Config")

local TubeRenderer = {}

local COLORS = Config.COLORS

--- 颜色分量 clamp 到 [0, 255]
local function clampC(v) return math.max(0, math.min(255, math.floor(v))) end

-- ============================================================
-- Bézier 半椭圆弧
-- ============================================================

local KAPPA = 0.5522847498 -- 4 * (sqrt(2) - 1) / 3

--- 绘制半椭圆弧（从左到右，经过底部，顺时针方向）
--- 起点 (cx - rx, cy) 必须由上层 moveTo/lineTo 到达
--- 终点 (cx + rx, cy)
---@param vg userdata NanoVG context
---@param cx number 椭圆中心 X
---@param cy number 椭圆中心 Y（弧起始 Y，底部在 cy + ry）
---@param rx number 水平半径
---@param ry number 垂直半径
local function semiEllipseCW(vg, cx, cy, rx, ry)
    -- 左侧四分之一弧：(cx-rx, cy) → (cx, cy+ry)
    nvgBezierTo(vg,
        cx - rx,       cy + ry * KAPPA,
        cx - rx * KAPPA, cy + ry,
        cx,            cy + ry)
    -- 右侧四分之一弧：(cx, cy+ry) → (cx+rx, cy)
    nvgBezierTo(vg,
        cx + rx * KAPPA, cy + ry,
        cx + rx,       cy + ry * KAPPA,
        cx + rx,       cy)
end

--- 绘制半椭圆弧（从右到左，经过底部，用于桶形顶弧）
--- 起点 (cx + rx, cy) 必须由上层 moveTo/lineTo 到达
--- 终点 (cx - rx, cy)
---@param vg userdata NanoVG context
---@param cx number 椭圆中心 X
---@param cy number 椭圆中心 Y（弧起始 Y，底部在 cy + ry）
---@param rx number 水平半径
---@param ry number 垂直半径
local function semiEllipseRTL(vg, cx, cy, rx, ry)
    -- 右侧四分之一弧：(cx+rx, cy) → (cx, cy+ry)
    nvgBezierTo(vg,
        cx + rx,       cy + ry * KAPPA,
        cx + rx * KAPPA, cy + ry,
        cx,            cy + ry)
    -- 左侧四分之一弧：(cx, cy+ry) → (cx-rx, cy)
    nvgBezierTo(vg,
        cx - rx * KAPPA, cy + ry,
        cx - rx,       cy + ry * KAPPA,
        cx - rx,       cy)
end

-- ============================================================
-- 推导参数（带缓存，仅首次计算）
-- ============================================================

--- 从当前 Config.TUBE 实时计算所有推导参数（带缓存，仅首次计算）
--- bodyHeight = topPadding + (CAPACITY-1)*slotHeight + slotHeight*bottomSlotRatio
--- 底部一格在直筒段的高度 = slotHeight * bottomSlotRatio，其余高度由球底弧补足
---@return table
local _cachedParams = nil

local function deriveTubeParams()
    if _cachedParams then return _cachedParams end
    local T = Config.TUBE
    local CAP = Config.CAPACITY

    local outerRadius   = T.tubeWidth / 2
    local innerWidth    = T.tubeWidth - 2 * T.wallThickness
    local innerRadius   = innerWidth / 2
    local rimEllipseRY  = outerRadius * T.ellipticity
    local liqEllipseRY  = innerRadius * T.ellipticity
    local innerBallRY   = T.ballHeight - T.wallThickness

    -- 直筒段高度 = 顶部空白 + (CAPACITY-1)格标准高度 + 底部一格在直筒段的部分
    local bottomSlotStraightH = T.slotHeight * T.bottomSlotRatio
    local bodyHeight = T.topPadding + (CAP - 1) * T.slotHeight + bottomSlotStraightH
    local totalHeight = rimEllipseRY * 2 + bodyHeight + T.ballHeight

    _cachedParams = {
        outerRadius        = outerRadius,
        innerWidth         = innerWidth,
        innerRadius        = innerRadius,
        slotHeight         = T.slotHeight,
        topPadding         = T.topPadding,
        bottomSlotStraightH = bottomSlotStraightH,
        bodyHeight         = bodyHeight,
        rimEllipseRY       = rimEllipseRY,
        liqEllipseRY       = liqEllipseRY,
        innerBallRY        = innerBallRY,
        totalHeight        = totalHeight,
    }
    return _cachedParams
end

-- ============================================================
-- 布局
-- ============================================================

--- 计算所有试管的屏幕位置
---@return table positions, number tubeH
function TubeRenderer.calcPositions(tubeCount, screenW, screenH)
    local T = Config.TUBE
    local d = deriveTubeParams()
    local totalW = tubeCount * T.tubeWidth + (tubeCount - 1) * T.gap
    local startX = (screenW - totalW) / 2
    local startY = (screenH - d.totalHeight) / 2

    local positions = {}
    for i = 1, tubeCount do
        positions[i] = {
            x = startX + (i - 1) * (T.tubeWidth + T.gap),
            y = startY,
        }
    end
    return positions, d.totalHeight
end

-- ============================================================
-- 绘制背景
-- ============================================================

function TubeRenderer.drawBackground(vg, w, h)
    local bg = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(12, 15, 35, 255), nvgRGBA(8, 10, 25, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
end

-- ============================================================
-- 绘制单根试管
-- ============================================================

--- 绘制单根试管（管壁 + 液体 + 特效）
---@param vg      userdata NanoVG context
---@param x       number 试管左上角 X（已含 shake 偏移）
---@param y       number 试管左上角 Y（已含 select lift 偏移）
---@param tube    table  颜色数组 { colorIdx, ... }，索引1=底部
---@param opts    table  { selected, hideFromTop, shrinkState, wobbleOffset, rippleState, fillState }
function TubeRenderer.drawTube(vg, x, y, tube, opts)
    opts = opts or {}
    local hideFromTop = opts.hideFromTop or 0
    local wobbleOff   = opts.wobbleOffset or 0
    local selected    = opts.selected or false
    local ripple      = opts.rippleState
    local shrink      = opts.shrinkState  -- { count, progress }
    local tiltAngle   = opts.tiltAngle or 0  -- 管倾斜角度（度），用于液面水平

    local T = Config.TUBE
    local d = deriveTubeParams()

    -- 关键 Y 坐标
    local cx            = x + d.outerRadius            -- 管中心 X
    local innerX        = cx - d.innerRadius           -- 管内区域左边缘
    local straightTop   = y + d.rimEllipseRY * 2       -- 直筒段起始 Y
    local straightBottom = straightTop + d.bodyHeight    -- 直筒段底部 Y（球底弧起始）
    local tubeBottom    = straightBottom + T.ballHeight -- 试管最低点

    -- 1) 管底投影
    TubeRenderer._drawShadow(vg, x, tubeBottom, T.tubeWidth)

    -- 2) 管内衬底（§3.1 垂直渐变 + §3.2 边缘暗化）
    TubeRenderer._drawInnerBack(vg, cx, innerX, straightTop, straightBottom,
        d.innerRadius, d.innerBallRY, d.rimEllipseRY, d.liqEllipseRY)

    -- 2.5) 管口内沿 AO 阴影（§4.1）
    TubeRenderer._drawInnerAO(vg, innerX, straightTop, straightBottom,
        d.innerWidth, d.innerBallRY)

    -- 3) Scissor 裁剪（上方预留椭圆液面 + 波浪 + 抖动的空间）
    local surfaceMargin = d.liqEllipseRY + 10  -- 椭圆半高 + wobble/ripple/wave 余量
    nvgSave(vg)
    nvgIntersectScissor(vg, innerX, straightTop - surfaceMargin,
        d.innerWidth, surfaceMargin + d.bodyHeight + d.innerBallRY)

    -- 4) 液体层（从底到顶绘制桶形液体，每格为完整封闭路径）
    -- tube[] 是数据层当前状态（rise 阶段已移除顶部液体）
    local baseCount = #tube - hideFromTop  -- 常驻可见格数

    -- shrink 阶段：在 baseCount 之上再绘制正在缩减的格
    -- shrinkCount 格的高度按 (1-progress) 缩放
    local shrinkCount = 0
    local shrinkProgress = 0
    local shrinkColorIdx = nil
    if shrink and shrink.count > 0 then
        shrinkCount = shrink.count
        shrinkProgress = shrink.progress or 0
        -- 使用 shrinkState 中明确传入的颜色（即 pour.color）
        -- 不能用 tube[baseCount]：removeFromSource 已移除顶部液体，
        -- 残余 top 颜色可能与被倒出颜色不同
        shrinkColorIdx = shrink.colorIdx
    end

    -- 总可见格数 = 常驻格 + 缩减格
    local totalVisibleCount = baseCount + shrinkCount

    -- 计算 shrink 整体收缩的顶部截止 Y（多格整体从顶部消失，而非每格独立缩矮）
    -- shrink 液体总高 = shrinkCount * slotHeight，剩余高度 = 总高 * (1-progress)
    -- shrinkCutY = 底部不动，顶部整体下压的截止线
    local shrinkCutY = nil
    if shrinkCount > 0 then
        -- 最底层 shrink 格的底部 Y（即 baseCount+1 格的底部）
        local bottomShrinkSlotY = straightTop + d.topPadding
            + (Config.CAPACITY - (baseCount + 1)) * d.slotHeight + d.slotHeight
        -- 最顶层 shrink 格的顶部 Y（即 totalVisibleCount 格的顶部）
        local topShrinkSlotY = straightTop + d.topPadding
            + (Config.CAPACITY - totalVisibleCount) * d.slotHeight
        local totalShrinkH = bottomShrinkSlotY - topShrinkSlotY
        local remainH = totalShrinkH * (1.0 - shrinkProgress)
        -- 截止线 = 从底部向上量出剩余高度
        shrinkCutY = bottomShrinkSlotY - remainH
    end

    -- 获取某格的颜色
    local function getSlotColor(s)
        if s > baseCount then return shrinkColorIdx
        else return tube[s] end
    end

    -- 分组绘制：将相邻同色格合并为一个桶形，消除 alpha 叠加缝隙
    local slot = 1
    while slot <= totalVisibleCount do
        local colorIdx = getSlotColor(slot)
        if not colorIdx then break end

        -- 向上扩展找连续同色格
        local groupEnd = slot
        while groupEnd < totalVisibleCount do
            local nextColor = getSlotColor(groupEnd + 1)
            if nextColor == colorIdx then
                groupEnd = groupEnd + 1
            else
                break
            end
        end

        -- 组的 Y 范围（slot=底格，groupEnd=顶格）
        local groupTopY = straightTop + d.topPadding + (Config.CAPACITY - groupEnd) * d.slotHeight
        local groupBottomY = straightTop + d.topPadding + (Config.CAPACITY - slot) * d.slotHeight + d.slotHeight
        local isBottom = (slot == 1)
        local groupContainsShrink = (groupEnd > baseCount)

        -- shrink 裁剪
        local effectiveTopY = groupTopY
        local shouldDraw = true
        if groupContainsShrink and shrinkCutY then
            if groupBottomY <= shrinkCutY then
                shouldDraw = false
            elseif effectiveTopY < shrinkCutY then
                effectiveTopY = shrinkCutY
            end
        end

        if shouldDraw then
            -- 顶层液体波浪（仅非缩减格的最顶组）
            local topArcOffY = 0
            local isTopGroup = (groupEnd == totalVisibleCount)
            if isTopGroup and not groupContainsShrink then
                local rippleOff = 0
                if ripple and ripple.amplitude > 0.1 then
                    rippleOff = ripple.amplitude
                        * math.sin(ripple.timer * Config.ANIM.ripple.frequency * math.pi * 2)
                        * math.exp(-Config.ANIM.ripple.damping * ripple.timer)
                end
                topArcOffY = wobbleOff + rippleOff
            end

            TubeRenderer._drawLiquidSlot(vg, cx, innerX, d.innerWidth,
                effectiveTopY, groupBottomY, colorIdx, isBottom,
                straightBottom, d.innerRadius, d.innerBallRY, d.liqEllipseRY,
                topArcOffY, isTopGroup, tiltAngle)
        end

        slot = groupEnd + 1
    end

    -- 4.2) 不同颜色液体交界处：上层液体底部深色标记（3D 深度效果）
    for s = 2, baseCount do
        local upperColor = tube[s]
        local lowerColor = tube[s - 1]
        if upperColor and lowerColor and upperColor ~= lowerColor then
            local boundaryY = straightTop + d.topPadding
                + (Config.CAPACITY - s) * d.slotHeight + d.slotHeight
            local c = COLORS[upperColor]
            local darkColor = nvgRGBA(
                clampC(c[1] * 0.35),
                clampC(c[2] * 0.35),
                clampC(c[3] * 0.35),
                160)

            if tiltAngle and math.abs(tiltAngle) > 0.5 then
                -- 倾斜时：斜线带替代椭圆
                local slantHalf = d.innerRadius * math.tan(math.rad(tiltAngle))
                local leftBY  = boundaryY + slantHalf
                local rightBY = boundaryY - slantHalf
                local bandH = d.liqEllipseRY * 0.5
                nvgBeginPath(vg)
                nvgMoveTo(vg, innerX, leftBY - bandH)
                nvgLineTo(vg, innerX + d.innerWidth, rightBY - bandH)
                nvgLineTo(vg, innerX + d.innerWidth, rightBY + bandH)
                nvgLineTo(vg, innerX, leftBY + bandH)
                nvgClosePath(vg)
                nvgFillColor(vg, darkColor)
                nvgFill(vg)
            else
                -- 正常：椭圆
                local ellipseRX = d.innerRadius * 0.80
                local ellipseRY = d.liqEllipseRY * 0.80
                nvgBeginPath(vg)
                nvgEllipse(vg, cx, boundaryY, ellipseRX, ellipseRY)
                nvgFillColor(vg, darkColor)
                nvgFill(vg)
            end
        end
    end

    -- 4.5) 液体边缘暗化 + 高光带（§2.1 + §2.2，§5.1 传入 shrink 修正高度）
    if totalVisibleCount > 0 then
        TubeRenderer._drawLiquidShading(vg, cx, innerX, d.innerWidth,
            straightTop, straightBottom, d.innerRadius, d.innerBallRY,
            d.liqEllipseRY, d.slotHeight, totalVisibleCount, wobbleOff, ripple,
            shrink, tiltAngle)
    end

    -- 5.5) fill 阶段临时液柱（§9.4）
    if opts.fillState then
        local fs = opts.fillState
        TubeRenderer._drawFillColumn(vg, cx, innerX, d.innerWidth,
            straightTop, straightBottom, d.innerRadius, d.innerBallRY,
            d.liqEllipseRY, d.slotHeight, fs)
    end

    nvgRestore(vg) -- 释放 Scissor

    -- 6) 玻璃管壁（§1.1 四层渐变）
    TubeRenderer._drawGlassWall(vg, x, straightTop, straightBottom,
        cx, d.outerRadius, T.ballHeight, T.tubeWidth, d.rimEllipseRY)

    -- 6.5) 球底高光（§1.2）
    TubeRenderer._drawBallHighlight(vg, cx, straightBottom, d.outerRadius, T.ballHeight)

    -- 7) 管口椭圆（§1.3 含厚度环）
    TubeRenderer._drawRim(vg, cx, straightTop,
        d.outerRadius, d.innerRadius, T.ellipticity)

    -- 8) 顶层液面椭圆 + 波浪（§2.3 增强：描边环 + 光斑）
    if totalVisibleCount > 0 then
        nvgSave(vg)
        nvgIntersectScissor(vg, innerX, straightTop - surfaceMargin,
            d.innerWidth, surfaceMargin + d.bodyHeight)

        -- 确定液面位置和颜色
        local surfaceColorIdx
        local surfaceY
        if shrinkCount > 0 and shrinkColorIdx then
            -- rise 阶段：液面在整体截止线位置
            surfaceY = shrinkCutY or (straightTop + d.topPadding + (Config.CAPACITY - totalVisibleCount) * d.slotHeight)
            surfaceColorIdx = shrinkColorIdx
        else
            -- 正常状态：液面在常驻格顶部
            local topSlot = baseCount
            surfaceY = straightTop + d.topPadding + (Config.CAPACITY - topSlot) * d.slotHeight
            surfaceColorIdx = tube[topSlot]
        end

        if surfaceColorIdx then
            TubeRenderer._drawLiquidSurface(vg, innerX, surfaceY, d.innerWidth,
                surfaceColorIdx, wobbleOff, ripple, d.liqEllipseRY, tiltAngle)
        end
        nvgRestore(vg)
    end

    -- 8.5) fill 液柱顶部液面（液面从 existingTopY 上涨到 targetSlotTop）
    if opts.fillState then
        local fs = opts.fillState
        local startTopY = fs.existingTopY or straightTop   -- 现有液面位置（底部）
        local endTopY   = fs.targetSlotTop or straightTop   -- 目标液面位置（顶部）
        local progress  = fs.progress or 0
        local fillTopY  = startTopY + (endTopY - startTopY) * progress

        nvgSave(vg)
        nvgIntersectScissor(vg, innerX, straightTop - surfaceMargin,
            d.innerWidth, surfaceMargin + d.bodyHeight)
        TubeRenderer._drawLiquidSurface(vg, innerX, fillTopY, d.innerWidth,
            fs.colorIdx, fs.wobbleOffset or 0, fs.rippleState, d.liqEllipseRY)
        nvgRestore(vg)
    end

    -- 9) 选中发光
    if selected then
        TubeRenderer._drawGlow(vg, x, y, T.tubeWidth, d.totalHeight, d.outerRadius)
    end
end

-- ============================================================
-- 飞行液滴
-- ============================================================

--- 绘制飞行液滴（支持形变）
function TubeRenderer.drawFlyingDroplet(vg, opts)
    local T = Config.TUBE
    local d = deriveTubeParams()
    local color = COLORS[opts.colorIdx]
    local baseW = d.innerWidth * Config.ANIM.droplet.baseWidth
    local aspect = opts.aspect or 1.0
    local rotation = opts.rotation or 0

    if aspect < 0.15 then return end

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

-- ============================================================
-- 内部绘制方法
-- ============================================================

--- 管底投影
function TubeRenderer._drawShadow(vg, x, bottomY, tubeW)
    local shadow = nvgBoxGradient(vg, x + 2, bottomY - 4, tubeW - 4, 8, 4, 12,
        nvgRGBA(0, 0, 0, 80), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - 8, bottomY - 10, tubeW + 16, 20)
    nvgFillPaint(vg, shadow)
    nvgFill(vg)
end

--- 管内衬底封闭路径（复用）
local function innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBallRY, liqEllipseRY)
    nvgMoveTo(vg, innerX, rimCY)
    nvgLineTo(vg, innerX, bottomY)
    semiEllipseCW(vg, cx, bottomY, innerR, innerBallRY)
    nvgLineTo(vg, innerX + innerR * 2, rimCY)
    nvgBezierTo(vg,
        innerX + innerR * 2,       rimCY - liqEllipseRY * KAPPA,
        cx + innerR * KAPPA,       rimCY - liqEllipseRY,
        cx,                        rimCY - liqEllipseRY)
    nvgBezierTo(vg,
        cx - innerR * KAPPA,       rimCY - liqEllipseRY,
        innerX,                    rimCY - liqEllipseRY * KAPPA,
        innerX,                    rimCY)
    nvgClosePath(vg)
end

--- 管内衬底（纯透明中间 + 边缘暗化）
function TubeRenderer._drawInnerBack(vg, cx, innerX, topY, bottomY, innerR, innerBallRY, rimEllipseRY, liqEllipseRY)
    local rimCY = topY - rimEllipseRY
    local innerW = innerR * 2

    -- 左侧边缘暗化（从左壁向内渐隐，模拟玻璃弧面折射）
    local edgeW = innerW * 0.22
    local edgeL = nvgLinearGradient(vg, innerX, topY, innerX + edgeW, topY,
        nvgRGBA(0, 0, 0, 40), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBallRY, liqEllipseRY)
    nvgFillPaint(vg, edgeL)
    nvgFill(vg)

    -- 右侧边缘暗化
    local rightX = innerX + innerW
    local edgeR = nvgLinearGradient(vg, rightX - edgeW, topY, rightX, topY,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 28))
    nvgBeginPath(vg)
    innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBallRY, liqEllipseRY)
    nvgFillPaint(vg, edgeR)
    nvgFill(vg)
end

--- 绘制单格液体（完整桶形封闭路径）
--- 形状：左壁 → 底弧 → 右壁 → 顶弧（向下凹） → 闭合
--- 非底层向下延伸覆盖前一格的顶弧区域，消除 alpha 叠加色差
--- isTopGroup: 该组是否为最顶层组（用于斜面处理）
--- tiltAngle: 管倾斜角度（度），液面需保持世界水平
function TubeRenderer._drawLiquidSlot(vg, cx, innerX, innerW, slotY, slotBottom,
    colorIdx, isBottom, straightBottom, innerR, innerBallRY, liqEllipseRY, topArcOffY,
    isTopGroup, tiltAngle)
    local c = COLORS[colorIdx]
    local alpha = Config.TUBE.liquidAlpha
    local topY = slotY + (topArcOffY or 0)

    -- 顶部圆角半径（3D 圆润效果）
    local cornerR = math.min(5, innerR * 0.2)

    -- 计算斜面偏移（所有层级 + 有倾斜时）
    local slantHalf = 0  -- 液面从中心到边缘的 Y 偏移量
    local useSlant = tiltAngle and math.abs(tiltAngle) > 0.5
    if useSlant then
        -- 旋转坐标系中，世界水平线斜率 = tan(tiltAngle)
        -- 管顺时针旋转（顶右倾）时：右侧液位高（Y小），左侧液位低（Y大）
        slantHalf = innerR * math.tan(math.rad(tiltAngle))
    end

    nvgBeginPath(vg)

    if useSlant then
        -- 斜面模式：顶面和非底层底面都是斜线
        local leftTopY  = topY + slantHalf   -- 左端低（管右倾时左侧液位低）
        local rightTopY = topY - slantHalf   -- 右端高（管右倾时右侧液位高）

        -- 左壁起点
        nvgMoveTo(vg, innerX, leftTopY)

        if isBottom then
            -- 底层组：底部跟管底曲线
            nvgLineTo(vg, innerX, straightBottom)
            semiEllipseCW(vg, cx, straightBottom, innerR, innerBallRY)
            nvgLineTo(vg, innerX + innerW, rightTopY)
        else
            -- 非底层组：底部也是斜线（与下方组顶部对齐）
            local leftBotY  = slotBottom + slantHalf
            local rightBotY = slotBottom - slantHalf
            nvgLineTo(vg, innerX, leftBotY)
            nvgLineTo(vg, innerX + innerW, rightBotY)
            nvgLineTo(vg, innerX + innerW, rightTopY)
        end

        -- 顶面斜线（右→左）+ 轻微曲线模拟液面张力
        local midX = cx
        local midY = topY - math.abs(slantHalf) * 0.08  -- 中心微微上凸
        nvgQuadTo(vg, midX, midY, innerX, leftTopY)

        nvgClosePath(vg)
    else
        -- 原有水平模式
        -- 左壁起点：从圆角下方开始
        nvgMoveTo(vg, innerX, topY + cornerR)

        if isBottom then
            nvgLineTo(vg, innerX, straightBottom)
            semiEllipseCW(vg, cx, straightBottom, innerR, innerBallRY)
            nvgLineTo(vg, innerX + innerW, topY + cornerR)
        else
            nvgLineTo(vg, innerX, slotBottom)
            semiEllipseCW(vg, cx, slotBottom, innerR, liqEllipseRY)
            nvgLineTo(vg, innerX + innerW, topY + cornerR)
        end

        -- 右上圆角
        local rightX = innerX + innerW
        nvgQuadTo(vg,
            rightX, topY,
            rightX - cornerR, topY)
        -- 顶弧
        semiEllipseRTL(vg, cx, topY, innerR - cornerR, liqEllipseRY)
        -- 左上圆角
        nvgQuadTo(vg,
            innerX, topY,
            innerX, topY + cornerR)

        nvgClosePath(vg)
    end

    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
    nvgFill(vg)
end

--- 绘制顶层液面高光椭圆 + 描边环 + 光斑（§2.3 增强）
--- tiltAngle: 倾斜角度（度），倾斜时用斜线高光代替椭圆
function TubeRenderer._drawLiquidSurface(vg, x, y, w, colorIdx, wobbleOff, ripple, liqEllipseRY, tiltAngle)
    local c = COLORS[colorIdx]
    local L = Config.TUBE.liquid
    local halfW = w / 2
    local ellipseCX = x + halfW

    -- 倾斜模式：斜线高光代替椭圆
    if tiltAngle and math.abs(tiltAngle) > 0.5 then
        local slantHalf = halfW * math.tan(math.rad(tiltAngle))
        local leftY  = y + slantHalf   -- 左端低（管右倾时）
        local rightY = y - slantHalf   -- 右端高（管右倾时）
        local innerX = x
        local rightX = x + w

        -- 斜面高光带（沿斜线的窄带状渐变）
        nvgBeginPath(vg)
        local bandH = liqEllipseRY * 0.8
        nvgMoveTo(vg, innerX, leftY - bandH)
        nvgLineTo(vg, rightX, rightY - bandH)
        nvgLineTo(vg, rightX, rightY + bandH)
        nvgLineTo(vg, innerX, leftY + bandH)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(
            clampC(c[1] + 40), clampC(c[2] + 40), clampC(c[3] + 40), 120))
        nvgFill(vg)

        -- 斜面描边线（模拟液面边缘反射）
        nvgBeginPath(vg)
        local midY = y - math.abs(slantHalf) * 0.08
        nvgMoveTo(vg, rightX, rightY)
        nvgQuadTo(vg, ellipseCX, midY, innerX, leftY)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, L.surfaceRingAlpha))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 高光点（偏向液位高侧：管右倾时偏右）
        local spotT = (slantHalf > 0) and 0.7 or 0.3
        local spotCX2 = innerX + w * spotT
        local spotCY2 = leftY + (rightY - leftY) * spotT
        local spotR = halfW * L.surfaceSpotSize
        local spotGrad = nvgRadialGradient(vg, spotCX2, spotCY2, 1, spotR,
            nvgRGBA(255, 255, 255, L.surfaceSpotAlpha),
            nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, spotCX2, spotCY2, spotR, spotR * 0.7)
        nvgFillPaint(vg, spotGrad)
        nvgFill(vg)
        return
    end

    -- 正常水平模式
    local rippleOff = 0
    if ripple and ripple.amplitude > 0.1 then
        rippleOff = ripple.amplitude
            * math.sin(ripple.timer * Config.ANIM.ripple.frequency * math.pi * 2)
            * math.exp(-Config.ANIM.ripple.damping * ripple.timer)
    end
    local totalOff = wobbleOff + rippleOff

    local ellipseCY = y + totalOff

    -- 椭圆液面高光（保留原有）
    nvgBeginPath(vg)
    nvgEllipse(vg, ellipseCX, ellipseCY, halfW, liqEllipseRY)
    nvgFillColor(vg, nvgRGBA(
        clampC(c[1] + 40), clampC(c[2] + 40), clampC(c[3] + 40), 160))
    nvgFill(vg)

    -- §2.3 新增 A：椭圆描边高光环（模拟凹面边缘反射）
    nvgBeginPath(vg)
    nvgEllipse(vg, ellipseCX, ellipseCY, halfW * 0.85, liqEllipseRY * 0.85)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, L.surfaceRingAlpha))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- §2.3 新增 B：偏左上小高光点（模拟光源反射点）
    local spotR = halfW * L.surfaceSpotSize
    local spotCX = ellipseCX - halfW * 0.25
    local spotCY = ellipseCY - liqEllipseRY * 0.15
    local spotGrad = nvgRadialGradient(vg, spotCX, spotCY, 1, spotR,
        nvgRGBA(255, 255, 255, L.surfaceSpotAlpha),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, spotCX, spotCY, spotR, spotR * 0.7)
    nvgFillPaint(vg, spotGrad)
    nvgFill(vg)
end

--- 绘制玻璃管壁（§1.1 四层渐变 + 轮廓描边）
function TubeRenderer._drawGlassWall(vg, x, straightTop, straightBottom,
    cx, outerR, ballH, tubeW, rimEllipseRY)
    local G = Config.TUBE.glass

    -- 层0：管壁蓝色调底色（§5 新增）
    if G.baseTintColor and G.baseTintAlpha > 0 then
        local tc = G.baseTintColor
        nvgBeginPath(vg)
        TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], G.baseTintAlpha))
        nvgFill(vg)
    end

    -- 层A：左边缘暗线（0%~5%）
    local darkL = nvgLinearGradient(vg, x, straightTop, x + tubeW * 0.05, straightTop,
        nvgRGBA(0, 0, 0, G.edgeDarkAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, darkL)
    nvgFill(vg)

    -- 层B：主高光带（8%~28%）— 用三段渐变模拟 0→peak→0
    local hlX0 = x + tubeW * 0.08
    local hlX1 = x + tubeW * 0.18  -- 峰值位置
    local hlX2 = x + tubeW * 0.28
    -- 左半：0→peak
    local hlL = nvgLinearGradient(vg, hlX0, straightTop, hlX1, straightTop,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, G.mainHighlightAlpha))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, hlL)
    nvgFill(vg)
    -- 右半：peak→0
    local hlR = nvgLinearGradient(vg, hlX1, straightTop, hlX2, straightTop,
        nvgRGBA(255, 255, 255, G.mainHighlightAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, hlR)
    nvgFill(vg)

    -- 层C：右侧次高光（70%~90%）
    local shX0 = x + tubeW * 0.70
    local shX1 = x + tubeW * 0.80
    local shX2 = x + tubeW * 0.90
    local shL = nvgLinearGradient(vg, shX0, straightTop, shX1, straightTop,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, G.secHighlightAlpha))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, shL)
    nvgFill(vg)
    local shR = nvgLinearGradient(vg, shX1, straightTop, shX2, straightTop,
        nvgRGBA(255, 255, 255, G.secHighlightAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, shR)
    nvgFill(vg)

    -- 层D：右边缘暗线（95%~100%）
    local darkR = nvgLinearGradient(vg, x + tubeW * 0.95, straightTop, x + tubeW, straightTop,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, math.floor(G.edgeDarkAlpha * 0.75)))
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, darkR)
    nvgFill(vg)

    -- 管壁轮廓描边
    nvgBeginPath(vg)
    TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgStrokeColor(vg, nvgRGBA(180, 200, 230, 35))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

--- 试管外轮廓路径（直筒 + Bézier 半椭圆球底）
function TubeRenderer._tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    local leftWall  = x
    local rightWall = x + tubeW
    local rimCY = straightTop - rimEllipseRY  -- 管口椭圆中心 Y

    nvgMoveTo(vg, leftWall, rimCY)
    nvgLineTo(vg, leftWall, straightBottom)
    semiEllipseCW(vg, cx, straightBottom, outerR, ballH)
    nvgLineTo(vg, rightWall, rimCY)
    -- 上半椭圆弧闭合（右 → 顶 → 左），与管口外圈椭圆吻合
    nvgBezierTo(vg,
        rightWall,             rimCY - rimEllipseRY * KAPPA,
        cx + outerR * KAPPA,   rimCY - rimEllipseRY,
        cx,                    rimCY - rimEllipseRY)
    nvgBezierTo(vg,
        cx - outerR * KAPPA,   rimCY - rimEllipseRY,
        leftWall,              rimCY - rimEllipseRY * KAPPA,
        leftWall,              rimCY)
    nvgClosePath(vg)
end

--- 管口椭圆 + 厚度环（§1.3，由 ellipticity 统一控制）
function TubeRenderer._drawRim(vg, cx, straightTop, outerR, innerR, ellipticity)
    local outerRY = outerR * ellipticity
    local innerRY = innerR * ellipticity
    local rimCY = straightTop - outerRY

    local G = Config.TUBE.glass

    -- 外圈（玻璃边缘高光描边）
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, outerR, outerRY)
    nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 70))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- §1.3 厚度环（外圈与内圈之间的玻璃截面渐变）
    -- 用径向渐变模拟玻璃截面的折射效果
    local midR = (outerR + innerR) / 2
    local midRY = (outerRY + innerRY) / 2
    local ringGrad = nvgRadialGradient(vg, cx - outerR * 0.15, rimCY - outerRY * 0.2,
        midR * 0.5, midR * 1.2,
        nvgRGBA(180, 200, 230, G.rimRingAlpha),
        nvgRGBA(40, 50, 70, math.floor(G.rimRingAlpha * 0.3)))
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, outerR - 0.5, outerRY - 0.5)
    -- 用 pathWinding 减去内圈形成环形
    nvgPathWinding(vg, NVG_HOLE)
    nvgEllipse(vg, cx, rimCY, innerR + 0.5, innerRY + 0.5)
    nvgFillPaint(vg, ringGrad)
    nvgFill(vg)

    -- 内圈（暗色管口开口填充）
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, innerR, innerRY)
    nvgFillColor(vg, nvgRGBA(8, 8, 18, 220))
    nvgFill(vg)

    -- 管口上沿高光弧线（Bézier 上半椭圆弧）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - outerR, rimCY)
    nvgBezierTo(vg,
        cx - outerR,       rimCY - outerRY * KAPPA,
        cx - outerR * KAPPA, rimCY - outerRY,
        cx,                rimCY - outerRY)
    nvgBezierTo(vg,
        cx + outerR * KAPPA, rimCY - outerRY,
        cx + outerR,       rimCY - outerRY * KAPPA,
        cx + outerR,       rimCY)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 45))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

--- 管口内沿 AO 阴影 + 球底交汇处 AO（§4.1 + §4.2）
function TubeRenderer._drawInnerAO(vg, innerX, straightTop, straightBottom, innerW, innerBallRY)
    local AO = Config.TUBE.ao

    -- §4.1 管口内沿 AO：straightTop 向下渐变消失
    local aoTop = nvgLinearGradient(vg, innerX, straightTop, innerX, straightTop + AO.rimShadowHeight,
        nvgRGBA(0, 0, 0, AO.rimShadowAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, innerX, straightTop, innerW, AO.rimShadowHeight)
    nvgFillPaint(vg, aoTop)
    nvgFill(vg)

    -- §4.2 球底交汇处 AO：straightBottom 向下渐变消失
    local aoBot = nvgLinearGradient(vg, innerX, straightBottom - AO.ballJointHeight, innerX, straightBottom,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, AO.ballJointAlpha))
    nvgBeginPath(vg)
    nvgRect(vg, innerX, straightBottom - AO.ballJointHeight, innerW, AO.ballJointHeight)
    nvgFillPaint(vg, aoBot)
    nvgFill(vg)
end

--- 液体边缘暗化 + 高光带（§2.1 + §2.2 + §5.1 shrink 高度修正）
--- 在所有液体 slot 绘制之后，用单次 clip 叠加边缘暗化和高光带
function TubeRenderer._drawLiquidShading(vg, cx, innerX, innerW,
    straightTop, straightBottom, innerR, innerBallRY, liqEllipseRY,
    slotHeight, visibleCount, wobbleOff, ripple, shrinkState, tiltAngle)
    local L = Config.TUBE.liquid

    -- 计算液体区域范围（含 topPadding 偏移）
    local topPadding = Config.TUBE.topPadding
    local topSlotY = straightTop + topPadding + (Config.CAPACITY - visibleCount) * slotHeight

    -- §5.1 如果存在 shrink，修正 topSlotY 为整体截止线位置
    if shrinkState and shrinkState.count > 0 then
        -- 最底层 shrink 格的底部 Y
        local baseCount2 = visibleCount - shrinkState.count
        local bottomShrinkSlotY = straightTop + topPadding
            + (Config.CAPACITY - (baseCount2 + 1)) * slotHeight + slotHeight
        -- 整体截止线
        local totalShrinkH = shrinkState.count * slotHeight
        local remainH = totalShrinkH * (1.0 - (shrinkState.progress or 0))
        topSlotY = bottomShrinkSlotY - remainH
    end
    local rippleOff = 0
    if ripple and ripple.amplitude > 0.1 then
        rippleOff = ripple.amplitude
            * math.sin(ripple.timer * Config.ANIM.ripple.frequency * math.pi * 2)
            * math.exp(-Config.ANIM.ripple.damping * ripple.timer)
    end
    local liqTopY = topSlotY + wobbleOff + rippleOff
    -- 倾斜时液面高侧更高，扩展 shading 范围以覆盖斜面
    if tiltAngle and math.abs(tiltAngle) > 0.5 then
        local slantHalf = innerR * math.tan(math.rad(tiltAngle))
        liqTopY = liqTopY - math.abs(slantHalf)
    end
    local liqBotY = straightBottom + innerBallRY

    -- §2.1 左侧边缘暗化
    local edgeW = innerW * L.edgeWidth
    local edgeL = nvgLinearGradient(vg, innerX, straightTop, innerX + edgeW, straightTop,
        nvgRGBA(0, 0, 0, L.edgeDarkAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, innerX, liqTopY - liqEllipseRY, edgeW, liqBotY - liqTopY + liqEllipseRY)
    nvgFillPaint(vg, edgeL)
    nvgFill(vg)

    -- §2.1 右侧边缘暗化
    local rightX = innerX + innerW
    local edgeR = nvgLinearGradient(vg, rightX - edgeW, straightTop, rightX, straightTop,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, math.floor(L.edgeDarkAlpha * 0.75)))
    nvgBeginPath(vg)
    nvgRect(vg, rightX - edgeW, liqTopY - liqEllipseRY, edgeW, liqBotY - liqTopY + liqEllipseRY)
    nvgFillPaint(vg, edgeR)
    nvgFill(vg)

    -- §2.2 液体高光带（偏左的窄竖条）
    local hlCenterX = innerX + innerW * L.highlightPos
    local hlHalfW = innerW * L.highlightWidth / 2
    local hlL = nvgLinearGradient(vg, hlCenterX - hlHalfW, straightTop, hlCenterX, straightTop,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, L.highlightAlpha))
    nvgBeginPath(vg)
    nvgRect(vg, hlCenterX - hlHalfW, liqTopY - liqEllipseRY, hlHalfW * 2, liqBotY - liqTopY + liqEllipseRY)
    nvgFillPaint(vg, hlL)
    nvgFill(vg)

    local hlR = nvgLinearGradient(vg, hlCenterX, straightTop, hlCenterX + hlHalfW, straightTop,
        nvgRGBA(255, 255, 255, L.highlightAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgRect(vg, hlCenterX, liqTopY - liqEllipseRY, hlHalfW, liqBotY - liqTopY + liqEllipseRY)
    nvgFillPaint(vg, hlR)
    nvgFill(vg)
end

--- 球底高光（§1.2）— 球底弧面偏左上的小高光点
function TubeRenderer._drawBallHighlight(vg, cx, straightBottom, outerR, ballH)
    local G = Config.TUBE.glass
    local hlW = outerR * G.ballHighlightSize
    local hlH = ballH * G.ballHighlightSize * 0.6
    -- 偏向光源方向（左上）
    local hlCX = cx - outerR * 0.25
    local hlCY = straightBottom + ballH * 0.45

    local grad = nvgRadialGradient(vg, hlCX, hlCY, 1, math.max(hlW, hlH),
        nvgRGBA(255, 255, 255, G.ballHighlightAlpha),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, hlCX, hlCY, hlW, hlH)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

--- fill 阶段临时液柱（§9.4 改为液面上涨方向）
--- 底部固定在 existingTopY（现有液面），顶部从 existingTopY 上涨到 targetSlotTop
function TubeRenderer._drawFillColumn(vg, cx, innerX, innerW,
    straightTop, straightBottom, innerR, innerBallRY, liqEllipseRY,
    slotHeight, fillState)

    local fs = fillState
    local c = COLORS[fs.colorIdx]
    local alpha = Config.TUBE.liquidAlpha

    -- 底部固定在现有液面位置，顶部随 progress 上涨
    local bottomY   = fs.existingTopY or straightBottom  -- 现有液面（固定底部）
    local endTopY   = fs.targetSlotTop or bottomY        -- 目标顶部
    local progress  = fs.progress or 0
    local currentTopY = bottomY + (endTopY - bottomY) * progress  -- 从 bottomY 向上涨到 endTopY

    -- 安全检查：如果顶部和底部重合或反转，不绘制
    if currentTopY >= bottomY then return end

    -- 顶部圆角半径（3D 圆润效果）
    local cornerR = math.min(5, innerR * 0.2)

    -- 绘制桶形液柱
    nvgBeginPath(vg)
    -- 左壁起点：从圆角下方开始
    nvgMoveTo(vg, innerX, currentTopY + cornerR)

    if bottomY > straightBottom then
        -- 底部进入球底弧区域
        nvgLineTo(vg, innerX, straightBottom)
        semiEllipseCW(vg, cx, straightBottom, innerR, innerBallRY)
        nvgLineTo(vg, innerX + innerW, currentTopY + cornerR)
    else
        -- 底部在直筒段
        nvgLineTo(vg, innerX, bottomY)
        semiEllipseCW(vg, cx, bottomY, innerR, liqEllipseRY)
        nvgLineTo(vg, innerX + innerW, currentTopY + cornerR)
    end

    -- 右上圆角
    local rightX = innerX + innerW
    nvgQuadTo(vg, rightX, currentTopY, rightX - cornerR, currentTopY)
    -- 顶弧（右→左，缩进 cornerR）
    semiEllipseRTL(vg, cx, currentTopY, innerR - cornerR, liqEllipseRY)
    -- 左上圆角
    nvgQuadTo(vg, innerX, currentTopY, innerX, currentTopY + cornerR)
    nvgClosePath(vg)

    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
    nvgFill(vg)

    -- §3.1 填充液柱边缘暗化 + 高光带（与常规液体 _drawLiquidShading 视觉一致）
    local L = Config.TUBE.liquid
    local colH = bottomY - currentTopY
    if colH > 0 then
        local edgeW = innerW * L.edgeWidth
        -- 左侧暗化
        local edgeL = nvgLinearGradient(vg, innerX, currentTopY, innerX + edgeW, currentTopY,
            nvgRGBA(0, 0, 0, L.edgeDarkAlpha), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRect(vg, innerX, currentTopY, edgeW, colH)
        nvgFillPaint(vg, edgeL)
        nvgFill(vg)
        -- 右侧暗化
        local edgeR = nvgLinearGradient(vg, rightX - edgeW, currentTopY, rightX, currentTopY,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, math.floor(L.edgeDarkAlpha * 0.75)))
        nvgBeginPath(vg)
        nvgRect(vg, rightX - edgeW, currentTopY, edgeW, colH)
        nvgFillPaint(vg, edgeR)
        nvgFill(vg)
        -- 高光带
        local hlCenterX = innerX + innerW * L.highlightPos
        local hlHalfW = innerW * L.highlightWidth / 2
        local hlL2 = nvgLinearGradient(vg, hlCenterX - hlHalfW, currentTopY, hlCenterX, currentTopY,
            nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, L.highlightAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, hlCenterX - hlHalfW, currentTopY, hlHalfW * 2, colH)
        nvgFillPaint(vg, hlL2)
        nvgFill(vg)
        local hlR2 = nvgLinearGradient(vg, hlCenterX, currentTopY, hlCenterX + hlHalfW, currentTopY,
            nvgRGBA(255, 255, 255, L.highlightAlpha), nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(vg)
        nvgRect(vg, hlCenterX, currentTopY, hlHalfW, colH)
        nvgFillPaint(vg, hlR2)
        nvgFill(vg)
    end
end

--- 选中发光
function TubeRenderer._drawGlow(vg, x, y, tubeW, totalH, outerR)
    local gc = Config.ANIM.glow
    local glow = nvgBoxGradient(vg, x - 2, y - 2, tubeW + 4, totalH + 4,
        outerR + 2, gc.feather,
        nvgRGBA(gc.color[1], gc.color[2], gc.color[3], gc.alpha),
        nvgRGBA(gc.color[1], gc.color[2], gc.color[3], 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 8, y - 8, tubeW + 16, totalH + 16, outerR + 6)
    nvgFillPaint(vg, glow)
    nvgFill(vg)
end

-- ============================================================
-- 倾倒模式：水流路径绘制
-- ============================================================

--- 绘制从源管口到目标管口的水流
---@param vg      userdata NanoVG context
---@param opts    table  { startX, startY, endX, endY, colorIdx, progress, fading, timer }
function TubeRenderer.drawStream(vg, opts)
    local S = Config.ANIM.stream
    local c = COLORS[opts.colorIdx]
    local alpha = Config.TUBE.liquidAlpha

    local startX = opts.startX
    local startY = opts.startY
    local endX   = opts.endX
    local endY   = opts.endY
    local timer  = opts.timer or 0
    local fading = opts.fading or 0       -- 0=完全可见, 1=完全消失
    local progress = opts.progress or 1   -- 液面下降进度（控制流量感）

    if fading >= 1.0 then return end

    local d = deriveTubeParams()
    local baseStartW = d.innerWidth * S.streamStartW
    local baseEndW   = d.innerWidth * S.streamEndW

    -- fading 阶段水流变细
    local fadeScale = 1.0 - fading * fading
    local startW = baseStartW * fadeScale
    local endW   = baseEndW * fadeScale

    if startW < 0.5 then return end

    local segments = S.streamSegments
    local dx = endX - startX
    local dy = endY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    -- 飞行时间（用于重力计算）
    local flightTime = dist / 300  -- 近似飞行时间

    -- 构建水流路径点
    local points = {}
    for i = 0, segments do
        local t = i / segments
        local px = startX + dx * t
        -- 抛物线：起点和终点在正确位置，中间受重力下坠
        local gravityDrop = 0.5 * S.streamGravity * (flightTime * t) * (flightTime * t)
        -- 减去线性插值的重力（让两端精确落在 startY/endY）
        local linearGrav = 0.5 * S.streamGravity * flightTime * flightTime * t
        local py = startY + dy * t + gravityDrop - linearGrav
        -- 横向波动
        local wobble = math.sin(t * 6 + timer * S.streamWobbleSpd) * S.streamWobbleAmp * t * (1 - t) * 4
        px = px + wobble
        points[i + 1] = { x = px, y = py }
    end

    -- 用连续四边形模拟变宽度水流
    local streamAlpha = math.floor(alpha * (1 - fading * 0.7))
    for i = 1, #points - 1 do
        local p0 = points[i]
        local p1 = points[i + 1]
        local segT0 = (i - 1) / (#points - 1)
        local segT1 = i / (#points - 1)
        local w0 = startW + (endW - startW) * segT0
        local w1 = startW + (endW - startW) * segT1

        -- 计算法线方向
        local sdx = p1.x - p0.x
        local sdy = p1.y - p0.y
        local slen = math.sqrt(sdx * sdx + sdy * sdy)
        if slen < 0.01 then slen = 0.01 end
        local nx = -sdy / slen
        local ny = sdx / slen

        -- 主水流体
        nvgBeginPath(vg)
        nvgMoveTo(vg, p0.x + nx * w0 / 2, p0.y + ny * w0 / 2)
        nvgLineTo(vg, p1.x + nx * w1 / 2, p1.y + ny * w1 / 2)
        nvgLineTo(vg, p1.x - nx * w1 / 2, p1.y - ny * w1 / 2)
        nvgLineTo(vg, p0.x - nx * w0 / 2, p0.y - ny * w0 / 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], streamAlpha))
        nvgFill(vg)

        -- 高光带（水流中心偏左的窄亮条）
        local hlW0 = w0 * 0.25
        local hlW1 = w1 * 0.25
        local hlOff = -0.15  -- 偏左
        nvgBeginPath(vg)
        nvgMoveTo(vg, p0.x + nx * w0 * hlOff + nx * hlW0 / 2, p0.y + ny * w0 * hlOff + ny * hlW0 / 2)
        nvgLineTo(vg, p1.x + nx * w1 * hlOff + nx * hlW1 / 2, p1.y + ny * w1 * hlOff + ny * hlW1 / 2)
        nvgLineTo(vg, p1.x + nx * w1 * hlOff - nx * hlW1 / 2, p1.y + ny * w1 * hlOff - ny * hlW1 / 2)
        nvgLineTo(vg, p0.x + nx * w0 * hlOff - nx * hlW0 / 2, p0.y + ny * w0 * hlOff - ny * hlW0 / 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(30 * (1 - fading))))
        nvgFill(vg)
    end

    -- 水流起点的圆头（管口处）
    if startW > 1 then
        nvgBeginPath(vg)
        nvgEllipse(vg, startX, startY, startW / 2, startW * 0.3)
        nvgFillColor(vg, nvgRGBA(
            clampC(c[1] + 20), clampC(c[2] + 20), clampC(c[3] + 20), streamAlpha))
        nvgFill(vg)
    end
end

--- 绘制断流小液滴
---@param vg    userdata NanoVG context
---@param drips table    液滴数组 { {x, y, r, timer, lifetime, colorIdx}, ... }
---@param colorIdx number 颜色索引
function TubeRenderer.drawDrips(vg, drips, colorIdx)
    local c = COLORS[colorIdx]
    for _, drip in ipairs(drips) do
        local life = drip.timer / drip.lifetime
        local a = math.floor(220 * (1 - life))
        local r = drip.r * (1 - life * 0.4)
        nvgBeginPath(vg)
        nvgCircle(vg, drip.x, drip.y, r)
        nvgFillColor(vg, nvgRGBA(
            clampC(c[1] + 20), clampC(c[2] + 20), clampC(c[3] + 20), a))
        nvgFill(vg)
    end
end

--- 公有方法：导出 deriveTubeParams 供外部计算布局信息
TubeRenderer.deriveTubeParams = deriveTubeParams

return TubeRenderer
