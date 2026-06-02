-- ============================================================
-- Renderer/Liquid.lua - 静态试管水层绘制（segment-based）
-- 支持: 迷雾层（负数颜色值 → 深灰色 + 问号）
-- ============================================================

local Config = require("config")
local Common = require("Renderer.Common")

local clamp = Common.clamp
local semiEllipseCW = Common.semiEllipseCW
local semiEllipseRTL = Common.semiEllipseRTL

local Liquid = {}

--- 获取层的渲染颜色（处理迷雾层）
--- 正数 = 正常颜色, 负数 = 迷雾色
---@param colorIdx integer
---@return table color {r,g,b}
---@return boolean isHidden
local function getLayerColor(colorIdx)
    if colorIdx < 0 then
        return Config.tube.fog.color, true
    end
    local colors = Config.getColors()
    return colors[colorIdx], false
end

-- ============================================================
-- 内部辅助
-- ============================================================

--- 顶层液面椭圆：亮色填充 + 描边环 + 光斑
local function drawLiquidSurfaceEllipse(vg, cx, surfaceY, innerR, color)
    local L = Config.tube.liquid
    local ellipseRX = innerR * L.surfaceRXScale
    local ellipseRY = ellipseRX * L.ellipticity

    -- 椭圆面（亮色填充）
    local lr, lg, lb = Common.lightenColor(color, 40)
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, surfaceY, ellipseRX, ellipseRY)
    nvgFillColor(vg, nvgRGBA(lr, lg, lb, 160))
    nvgFill(vg)

    -- 描边环（白色细线，模拟凹面反射）
    local ringScale = L.surfaceRingScale
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, surfaceY, ellipseRX * ringScale, ellipseRY * ringScale)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, L.surfaceRingAlpha))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 光斑（偏左上小高光点）
    local spotR = ellipseRX * L.surfaceSpotSize
    local spotCX = cx - ellipseRX * L.spotOffsetX
    local spotCY = surfaceY - ellipseRY * L.spotOffsetY
    local spotGrad = nvgRadialGradient(vg, spotCX, spotCY, 1, spotR,
        nvgRGBA(255, 255, 255, L.surfaceSpotAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, spotCX, spotCY, spotR, spotR * 0.7)
    nvgFillPaint(vg, spotGrad)
    nvgFill(vg)
end

--- 绘制单个液体 segment
--- @param vg userdata NanoVG context
--- @param cx number 管中心 X
--- @param d table deriveTubeParams 结果
--- @param segTopY number segment 顶部 Y
--- @param segBottomY number segment 底部 Y
--- @param color table {r, g, b}
--- @param isTop boolean 是否是最顶层 segment
--- @param isBottom boolean 是否接触管底
--- @param straightBottom number 管体直段底部 Y
local function drawSegment(vg, cx, d, segTopY, segBottomY, color, isTop, isBottom, straightBottom)
    local tube = Config.tube
    local L = tube.liquid
    local innerX = cx - d.innerRadius
    local arcRX = d.innerRadius
    local topArcRY = d.innerRadius * L.surfaceRXScale * L.ellipticity
    local boundaryArcRY = d.innerRadius * L.boundaryRXScale * L.ellipticity * 0.8

    nvgBeginPath(vg)

    -- 顶边：从右到左
    if isTop then
        -- 液面弧（向上弯曲）
        nvgMoveTo(vg, innerX + d.innerWidth, segTopY)
        semiEllipseRTL(vg, cx, segTopY, arcRX, -topArcRY)
    else
        -- 分界弧（向下弯曲）
        nvgMoveTo(vg, innerX + d.innerWidth, segTopY)
        semiEllipseRTL(vg, cx, segTopY, arcRX, boundaryArcRY)
    end

    -- 左侧边：从顶向底
    nvgLineTo(vg, innerX, segBottomY)

    -- 底边
    if isBottom then
        -- 管底球形弧
        nvgLineTo(vg, innerX, straightBottom)
        semiEllipseCW(vg, cx, straightBottom, d.innerRadius, d.innerBottomEllipseRY)
        nvgLineTo(vg, innerX + d.innerWidth, segBottomY)
    else
        -- 下方分界弧（向下弯曲，从左到右）
        semiEllipseCW(vg, cx, segBottomY, arcRX, boundaryArcRY)
    end

    -- 右侧边：从底向顶
    nvgLineTo(vg, innerX + d.innerWidth, segTopY)

    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], tube.liquidAlpha))
    nvgFill(vg)
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 绘制迷雾层问号标记
---@param vg userdata
---@param cx number 管中心X
---@param segTopY number segment 顶部Y
---@param segBottomY number segment 底部Y
---@param innerRadius number 管内径
local function drawFogQuestionMark(vg, cx, segTopY, segBottomY, innerRadius)
    local fogCfg = Config.tube.fog
    local midY = (segTopY + segBottomY) / 2
    local fontSize = math.min(innerRadius * 0.8, (segBottomY - segTopY) * 0.7)
    if fontSize < 6 then return end

    nvgFontSize(vg, fontSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, fogCfg.questionAlpha))
    nvgText(vg, cx, midY, "?")
end

--- 绘制静态试管水层（segment-based：连续同色层合并一次绘制）
--- 支持迷雾层: 负数颜色 → 迷雾色渲染 + 问号标记
function Liquid.drawStaticLayers(nvg, cx, cy, layers, extraFill, extraColor)
    local vg = nvg
    local d = Common.deriveTubeParams()
    local tube = Config.tube
    local colors = Config.getColors()

    local halfH = d.totalHeight / 2
    local straightTop = cy - halfH + d.rimEllipseRY * 2
    local straightBottom = straightTop + d.bodyHeight
    local innerX = cx - d.innerRadius

    -- 构建有效层列表（含 extraFill）
    local effectiveLayers = {}
    for i = 1, #layers do
        effectiveLayers[i] = layers[i]
    end
    local extraLayers = 0
    local extraFrac = 0
    if extraFill and extraFill > 0 and extraColor then
        extraLayers = math.floor(extraFill)
        extraFrac = extraFill - extraLayers
        for _ = 1, extraLayers do
            effectiveLayers[#effectiveLayers + 1] = extraColor
        end
        if extraFrac > 0 then
            effectiveLayers[#effectiveLayers + 1] = extraColor
        end
    end

    local totalSlots = #effectiveLayers
    if totalSlots <= 0 then return end

    -- 合并连续同色层为 segments
    -- 迷雾层使用特殊 colorIdx = 0 标记（所有隐藏层合并为迷雾色）
    local segments = {}
    local curKey = nil    -- 用于合并判断的 key: 正数=原色, "fog"=迷雾
    local curColorIdx = nil
    local curCount = 0
    local fullCount = extraFrac > 0 and (totalSlots - 1) or totalSlots

    for j = 1, fullCount do
        local colorIdx = effectiveLayers[j]
        local key = colorIdx < 0 and "fog" or colorIdx
        if key == curKey then
            curCount = curCount + 1
        else
            if curKey then
                segments[#segments + 1] = { colorIdx = curColorIdx, count = curCount, isFog = (curKey == "fog") }
            end
            curKey = key
            curColorIdx = colorIdx
            curCount = 1
        end
    end
    -- 处理顶部小数层
    if extraFrac > 0 then
        local topColorIdx = effectiveLayers[totalSlots]
        local topKey = topColorIdx < 0 and "fog" or topColorIdx
        if topKey == curKey then
            curCount = curCount + extraFrac
        else
            if curKey then
                segments[#segments + 1] = { colorIdx = curColorIdx, count = curCount, isFog = (curKey == "fog") }
            end
            curKey = topKey
            curColorIdx = topColorIdx
            curCount = extraFrac
        end
    end
    if curKey then
        segments[#segments + 1] = { colorIdx = curColorIdx, count = curCount, isFog = (curKey == "fog") }
    end

    if #segments <= 0 then return end

    -- Scissor 裁剪到管内区域
    nvgSave(vg)
    nvgIntersectScissor(vg, innerX, straightTop, d.innerWidth, d.bodyHeight + d.innerBottomEllipseRY)

    -- 计算每个 segment 的 Y 范围并绘制
    local slotBase = straightTop + d.topPadding + tube.layerCount * d.slotHeight  -- 最底格的底部 Y
    local accSlots = 0  -- 从底部累计的格数

    -- 收集迷雾 segment 位置（绘制问号用）
    local fogSegments = {}

    for i = 1, #segments do
        local seg = segments[i]
        local color
        if seg.isFog then
            color = Config.tube.fog.color
        else
            color = colors[seg.colorIdx]
        end
        if not color then
            accSlots = accSlots + seg.count
            goto nextSeg
        end

        local segBottomY = slotBase - accSlots * d.slotHeight
        local segTopY = slotBase - (accSlots + seg.count) * d.slotHeight

        local isTop = (i == #segments)
        local isBottom = (i == 1)

        -- 迷雾层使用迷雾 alpha
        local origAlpha = tube.liquidAlpha
        if seg.isFog then
            tube.liquidAlpha = Config.tube.fog.alpha
        end
        drawSegment(vg, cx, d, segTopY, segBottomY, color, isTop, isBottom, straightBottom)
        tube.liquidAlpha = origAlpha

        -- 记录迷雾 segment 位置供后续绘制问号
        if seg.isFog then
            table.insert(fogSegments, { topY = segTopY, bottomY = segBottomY })
        end

        accSlots = accSlots + seg.count
        ::nextSeg::
    end

    -- 分界椭圆装饰（segment 间才有，半透明暗色椭圆强化 3D 感）
    local L = Config.tube.liquid
    accSlots = 0
    for i = 1, #segments - 1 do
        accSlots = accSlots + segments[i].count
        local boundaryY = slotBase - accSlots * d.slotHeight
        local seg = segments[i]
        local belowColor
        if seg.isFog then
            belowColor = Config.tube.fog.color
        else
            belowColor = colors[seg.colorIdx]
        end
        if belowColor then
            local ellipseRX = d.innerRadius * L.boundaryRXScale
            local ellipseRY = ellipseRX * L.ellipticity * 0.8
            local dr, dg, db = Common.darkenColor(belowColor, L.boundaryDarken)
            nvgBeginPath(vg)
            nvgEllipse(vg, cx, boundaryY, ellipseRX, ellipseRY)
            nvgFillColor(vg, nvgRGBA(dr, dg, db, 32))
            nvgFill(vg)
        end
    end

    -- 顶层液面椭圆
    local topSeg = segments[#segments]
    local topColor
    if topSeg.isFog then
        topColor = Config.tube.fog.color
    else
        topColor = colors[topSeg.colorIdx]
    end
    if topColor then
        local topAccSlots = 0
        for i = 1, #segments do topAccSlots = topAccSlots + segments[i].count end
        local surfaceY = slotBase - topAccSlots * d.slotHeight
        drawLiquidSurfaceEllipse(vg, cx, surfaceY, d.innerRadius, topColor)
    end

    -- 绘制迷雾层问号标记（在液体之上）
    for _, fogSeg in ipairs(fogSegments) do
        drawFogQuestionMark(vg, cx, fogSeg.topY, fogSeg.bottomY, d.innerRadius)
    end

    nvgRestore(vg)
end

return Liquid
