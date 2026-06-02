-- ============================================================
-- Renderer/TiltedWater.lua - 倾斜试管水面渲染（segment-based）
-- 连续同色层合并为一个 segment，一次性绘制
-- 顶层 segment 上边缘 = 液面弧（向上），非顶层 = 分界弧（向下）
-- ============================================================

local Config = require("config")
local Common = require("Renderer.Common")

local clamp = Common.clamp
local KAPPA = Common.KAPPA
local rotatePoint = Common.rotatePoint
local segHIntersect = Common.segHIntersect

local TiltedWater = {}

-- ============================================================
-- 内部辅助
-- ============================================================

--- 计算旋转后管内轮廓（含球底弧采样点）
local function computeRotatedOutline(cx, cy, pivotWX, pivotWY, angle, d)
    local halfH = d.totalHeight / 2
    local innerLeft = cx - d.innerRadius
    local innerRight = cx + d.innerRadius
    local straightTop = cy - halfH + d.rimEllipseRY * 2
    local straightBottom = straightTop + d.bodyHeight

    local points = {}
    -- 左上
    points[#points + 1] = { x = innerLeft, y = straightTop }
    -- 左下（底部椭圆起点）
    points[#points + 1] = { x = innerLeft, y = straightBottom }

    -- 底部椭圆弧采样（10 个点近似半椭圆）
    local SAMPLES = 10
    for i = 0, SAMPLES do
        local t = i / SAMPLES
        local sampleAngle = math.pi * (1 - t) -- π → 0，从左到右
        local bx = cx + d.innerRadius * math.cos(sampleAngle)
        local by = straightBottom + d.innerBottomEllipseRY * math.sin(sampleAngle)
        points[#points + 1] = { x = bx, y = by }
    end

    -- 右下
    points[#points + 1] = { x = innerRight, y = straightBottom }
    -- 右上
    points[#points + 1] = { x = innerRight, y = straightTop }

    -- 对所有点做旋转
    for _, p in ipairs(points) do
        p.x, p.y = rotatePoint(p.x, p.y, pivotWX, pivotWY, angle)
    end

    return points
end

--- 从轮廓多边形中找水平线 Y 与轮廓左右交点
local function findHorizontalIntersections(outline, hY)
    local leftX, rightX = math.huge, -math.huge
    for i = 1, #outline do
        local cur = outline[i]
        local nxt = outline[(i % #outline) + 1]
        local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, hY)
        if ix then
            if ix < leftX then leftX = ix end
            if ix > rightX then rightX = ix end
        end
    end
    if leftX == math.huge or rightX == -math.huge then
        return nil, nil
    end
    return leftX, rightX
end

--- Sutherland-Hodgman 裁剪：保留 y >= clipY 的部分
local function clipPolyAbove(poly, clipY)
    if #poly == 0 then return {} end
    local out = {}
    for i = 1, #poly do
        local cur = poly[i]
        local nxt = poly[(i % #poly) + 1]
        local curIn = cur.y >= clipY - 0.01
        local nxtIn = nxt.y >= clipY - 0.01
        if curIn and nxtIn then
            out[#out + 1] = nxt
        elseif curIn and not nxtIn then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
            if ix then out[#out + 1] = { x = ix, y = clipY } end
        elseif not curIn and nxtIn then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
            if ix then out[#out + 1] = { x = ix, y = clipY } end
            out[#out + 1] = nxt
        end
    end
    return out
end

--- Sutherland-Hodgman 裁剪：保留 y <= clipY 的部分
local function clipPolyBelow(poly, clipY)
    if #poly == 0 then return {} end
    local out = {}
    for i = 1, #poly do
        local cur = poly[i]
        local nxt = poly[(i % #poly) + 1]
        local curIn = cur.y <= clipY + 0.01
        local nxtIn = nxt.y <= clipY + 0.01
        if curIn and nxtIn then
            out[#out + 1] = nxt
        elseif curIn and not nxtIn then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
            if ix then out[#out + 1] = { x = ix, y = clipY } end
        elseif not curIn and nxtIn then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, clipY)
            if ix then out[#out + 1] = { x = ix, y = clipY } end
            out[#out + 1] = nxt
        end
    end
    return out
end

--- 在多边形路径中，将位于指定 Y 水平线上的连续边替换为 Bézier 弧
--- @param vg userdata
--- @param band table[] 多边形顶点
--- @param edgeY number 要替换弧线的 Y 坐标
--- @param arcRY number 弧线高度（正=向下弯曲，负=向上弯曲）
local function drawBandWithArc(vg, band, edgeY, arcRY)
    local tolerance = 0.5

    nvgMoveTo(vg, band[1].x, band[1].y)
    for k = 2, #band do
        local prev = band[k - 1]
        local cur = band[k]
        local prevOnEdge = math.abs(prev.y - edgeY) < tolerance
        local curOnEdge = math.abs(cur.y - edgeY) < tolerance
        if prevOnEdge and curOnEdge then
            local arcCX = (prev.x + cur.x) / 2
            local arcRX = math.abs(cur.x - prev.x) / 2
            if arcRX < 1 then
                nvgLineTo(vg, cur.x, cur.y)
            elseif cur.x > prev.x then
                -- 从左到右
                nvgBezierTo(vg,
                    prev.x,              edgeY + arcRY * KAPPA,
                    arcCX - arcRX * KAPPA, edgeY + arcRY,
                    arcCX,               edgeY + arcRY)
                nvgBezierTo(vg,
                    arcCX + arcRX * KAPPA, edgeY + arcRY,
                    cur.x,               edgeY + arcRY * KAPPA,
                    cur.x,               edgeY)
            else
                -- 从右到左
                nvgBezierTo(vg,
                    prev.x,              edgeY + arcRY * KAPPA,
                    arcCX + arcRX * KAPPA, edgeY + arcRY,
                    arcCX,               edgeY + arcRY)
                nvgBezierTo(vg,
                    arcCX - arcRX * KAPPA, edgeY + arcRY,
                    cur.x,               edgeY + arcRY * KAPPA,
                    cur.x,               edgeY)
            end
        else
            nvgLineTo(vg, cur.x, cur.y)
        end
    end

    -- 关闭路径时检查最后一条边
    local lastPt = band[#band]
    local firstPt = band[1]
    local lastOnEdge = math.abs(lastPt.y - edgeY) < tolerance
    local firstOnEdge = math.abs(firstPt.y - edgeY) < tolerance
    if lastOnEdge and firstOnEdge then
        local arcCX = (lastPt.x + firstPt.x) / 2
        local arcRX = math.abs(firstPt.x - lastPt.x) / 2
        if arcRX >= 1 then
            if firstPt.x > lastPt.x then
                nvgBezierTo(vg,
                    lastPt.x,             edgeY + arcRY * KAPPA,
                    arcCX - arcRX * KAPPA, edgeY + arcRY,
                    arcCX,                edgeY + arcRY)
                nvgBezierTo(vg,
                    arcCX + arcRX * KAPPA, edgeY + arcRY,
                    firstPt.x,            edgeY + arcRY * KAPPA,
                    firstPt.x,            edgeY)
            else
                nvgBezierTo(vg,
                    lastPt.x,             edgeY + arcRY * KAPPA,
                    arcCX + arcRX * KAPPA, edgeY + arcRY,
                    arcCX,                edgeY + arcRY)
                nvgBezierTo(vg,
                    arcCX - arcRX * KAPPA, edgeY + arcRY,
                    firstPt.x,            edgeY + arcRY * KAPPA,
                    firstPt.x,            edgeY)
            end
        end
    end
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 绘制倾斜试管中的水（segment-based）
function TiltedWater.draw(nvg, cx, cy, pivotWX, pivotWY, angle, origLayers, removedCount)
    local vg = nvg
    local d = Common.deriveTubeParams()
    local tube = Config.tube
    local colors = Config.getColors()
    local halfH = d.totalHeight / 2
    local L = Config.tube.liquid

    local remaining = #origLayers - removedCount
    if remaining <= 0.05 then return end

    local innerLeft = cx - d.innerRadius
    local innerRight = cx + d.innerRadius
    local innerTop = cy - halfH + d.rimEllipseRY * 2
    local innerBottom = innerTop + d.bodyHeight

    local absAngle = math.abs(angle)
    local innerH = d.bodyHeight
    local halfInnerW = d.innerRadius

    -- 合并连续同色层为 segments
    local segments = Common.mergeSegments(origLayers, removedCount)
    if #segments == 0 then return end

    -- 计算合并后的有效总格数
    local effectiveRemaining = 0
    for _, seg in ipairs(segments) do
        effectiveRemaining = effectiveRemaining + seg.count
    end

    -- 角度 >= 90° 时: 贴壁矩形渲染（简化，不分层）
    if absAngle >= math.pi * 0.5 then
        local thickness = effectiveRemaining * d.slotHeight * (2 * halfInnerW) / innerH
        if thickness < 0.5 then return end

        local rectX1, rectX2
        if angle >= 0 then
            rectX1 = innerRight - thickness
            rectX2 = innerRight
        else
            rectX1 = innerLeft
            rectX2 = innerLeft + thickness
        end

        local p1x, p1y = rotatePoint(rectX1, innerTop, pivotWX, pivotWY, angle)
        local p2x, p2y = rotatePoint(rectX2, innerTop, pivotWX, pivotWY, angle)
        local p3x, p3y = rotatePoint(rectX2, innerBottom, pivotWX, pivotWY, angle)
        local p4x, p4y = rotatePoint(rectX1, innerBottom, pivotWX, pivotWY, angle)

        -- 极端角度只用底层颜色
        local color = colors[segments[1].colorIdx]
        if not color then return end

        nvgBeginPath(vg)
        nvgMoveTo(vg, p1x, p1y)
        nvgLineTo(vg, p2x, p2y)
        nvgLineTo(vg, p3x, p3y)
        nvgLineTo(vg, p4x, p4y)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 225))
        nvgFill(vg)
        return
    end

    -- 使用球底弧采样的完整轮廓
    local outline = computeRotatedOutline(cx, cy, pivotWX, pivotWY, angle, d)

    -- 正常倾斜: 水平液面裁剪
    local tanA = absAngle > 0.001 and math.tan(absAngle) or 0
    local avgH = effectiveRemaining * d.slotHeight
    local hPour = math.min(avgH + halfInnerW * tanA, innerH)

    local pourWallX = angle >= 0 and (cx + halfInnerW) or (cx - halfInnerW)
    local pourWallWaterLocalY = innerBottom - hPour
    local _, waterY = rotatePoint(pourWallX, pourWallWaterLocalY, pivotWX, pivotWY, angle)

    if absAngle < 0.001 then
        waterY = innerBottom - effectiveRemaining * d.slotHeight
    end

    local surfaceArcRY = d.innerRadius * L.surfaceRXScale * L.ellipticity
    local boundaryArcRY = d.innerRadius * L.boundaryRXScale * L.ellipticity * 0.8

    local maxY = outline[1].y
    for _, pt in ipairs(outline) do
        if pt.y > maxY then maxY = pt.y end
    end

    -- 水平线裁剪管内轮廓（整体液体区域）
    local clippedPoly = {}
    for i = 1, #outline do
        local cur = outline[i]
        local nxt = outline[(i % #outline) + 1]
        local curBelow = cur.y >= waterY
        local nxtBelow = nxt.y >= waterY
        if curBelow then clippedPoly[#clippedPoly + 1] = cur end
        if curBelow ~= nxtBelow then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, waterY)
            if ix then clippedPoly[#clippedPoly + 1] = { x = ix, y = waterY } end
        end
    end

    if #clippedPoly < 3 then return end

    -- 计算每个 segment 的 Y 分界线
    -- segments 从底到顶排列，累计格数从底部算起
    local segBoundaries = {}  -- segBoundaries[i] = { top = Y, bottom = Y }
    local accSlots = 0

    for i = 1, #segments do
        local seg = segments[i]
        -- 底部 Y（之前层的高度）
        local hBot = math.min(accSlots * d.slotHeight + halfInnerW * tanA, innerH)
        local localYBot = innerBottom - hBot
        local _, worldYBot
        if absAngle < 0.001 then
            worldYBot = localYBot
        else
            _, worldYBot = rotatePoint(pourWallX, localYBot, pivotWX, pivotWY, angle)
        end

        -- 顶部 Y（包含当前层）
        accSlots = accSlots + seg.count
        local hTop = math.min(accSlots * d.slotHeight + halfInnerW * tanA, innerH)
        local localYTop = innerBottom - hTop
        local _, worldYTop
        if absAngle < 0.001 then
            worldYTop = localYTop
        else
            _, worldYTop = rotatePoint(pourWallX, localYTop, pivotWX, pivotWY, angle)
        end

        -- 最底层的底部扩展到 maxY，最顶层的顶部对齐 waterY
        local bTop = (i == #segments) and waterY or worldYTop
        local bBottom = (i == 1) and maxY or worldYBot

        -- 确保 top < bottom（屏幕坐标 Y 向下）
        if bTop > bBottom then bTop, bBottom = bBottom, bTop end

        segBoundaries[i] = { top = bTop, bottom = bBottom }
    end

    -- ============ ① 逐 segment 填充液体多边形 ============
    for i = 1, #segments do
        local seg = segments[i]
        local color = colors[seg.colorIdx]
        if not color then goto nextSeg end

        local bounds = segBoundaries[i]
        local band = clipPolyAbove(clippedPoly, bounds.top)
        band = clipPolyBelow(band, bounds.bottom)

        if #band >= 3 then
            local isTop = (i == #segments)
            -- 顶边的弧线 Y 和弧高
            local edgeY = bounds.top
            local arcRY
            if isTop then
                arcRY = -surfaceArcRY  -- 向上弯曲（负 Y 方向）
            else
                arcRY = boundaryArcRY  -- 向下弯曲（正 Y 方向）
            end

            nvgBeginPath(vg)
            drawBandWithArc(vg, band, edgeY, arcRY)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], tube.liquidAlpha))
            nvgFill(vg)
        end

        ::nextSeg::
    end

    -- ============ ② 颜色分界椭圆装饰 ============
    for i = 2, #segments do
        local below = segments[i - 1]
        local above = segments[i]
        local belowColor = colors[below.colorIdx]
        if not belowColor then goto nextBoundary end

        local bY = segBoundaries[i].bottom  -- i 的底部 = i-1 的顶部 = 分界线
        local bLeftX, bRightX = findHorizontalIntersections(outline, bY)
        if bLeftX and bRightX then
            local bWidth = bRightX - bLeftX
            local bCX = (bLeftX + bRightX) / 2
            if bWidth > 4 then
                local bRX = bWidth / 2 * L.boundaryRXScale
                local fixedBoundaryRY = d.innerRadius * L.boundaryRXScale * L.ellipticity * 0.8
                local dr, dg, db = Common.darkenColor(belowColor, L.boundaryDarken)
                nvgBeginPath(vg)
                nvgEllipse(vg, bCX, bY, bRX, fixedBoundaryRY)
                nvgFillColor(vg, nvgRGBA(dr, dg, db, 32))
                nvgFill(vg)
            end
        end
        ::nextBoundary::
    end

    -- ============ ③ 顶层液面椭圆 ============
    local surfLeftX, surfRightX = findHorizontalIntersections(outline, waterY)
    if surfLeftX and surfRightX then
        local surfWidth = surfRightX - surfLeftX
        if surfWidth > 4 then
            local surfCX = (surfLeftX + surfRightX) / 2
            local topSeg = segments[#segments]
            local topColor = colors[topSeg.colorIdx]
            if topColor then
                local sRX = surfWidth / 2 * L.surfaceRXScale
                local fixedSurfaceRY = surfaceArcRY

                -- 椭圆面（亮色填充）
                local lr, lg, lb = Common.lightenColor(topColor, 40)
                nvgBeginPath(vg)
                nvgEllipse(vg, surfCX, waterY, sRX, fixedSurfaceRY)
                nvgFillColor(vg, nvgRGBA(lr, lg, lb, 150))
                nvgFill(vg)

                -- 描边环
                nvgBeginPath(vg)
                nvgEllipse(vg, surfCX, waterY, sRX * L.surfaceRingScale, fixedSurfaceRY * L.surfaceRingScale)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, L.surfaceRingAlpha))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)

                -- 光斑
                local spotR = sRX * L.surfaceSpotSize
                local spotCX = surfCX - sRX * L.spotOffsetX
                local spotCY = waterY - fixedSurfaceRY * L.spotOffsetY
                local spotGrad = nvgRadialGradient(vg, spotCX, spotCY, 1, spotR,
                    nvgRGBA(255, 255, 255, L.surfaceSpotAlpha), nvgRGBA(255, 255, 255, 0))
                nvgBeginPath(vg)
                nvgEllipse(vg, spotCX, spotCY, spotR, spotR * 0.7)
                nvgFillPaint(vg, spotGrad)
                nvgFill(vg)
            end
        end
    end
end

return TiltedWater
