-- ============================================================
-- Renderer.lua - NanoVG 渲染器（试管、水层、水流、粒子）
-- ============================================================

local Config = require("config")
local Animation = require("Animation")

local Renderer = {}

local lerp = Animation.lerp
local clamp = Animation.clamp

-- ============================================================
-- 布局计算
-- ============================================================

--- 计算所有试管的中心位置
---@param canvasW number
---@param canvasH number
---@param tubeCount integer
---@return table[] positions { {x, y}, ... }
function Renderer.getTubePositions(canvasW, canvasH, tubeCount)
    local tube = Config.tube
    local positions = {}

    if tubeCount <= 5 then
        local totalW = tubeCount * tube.width + (tubeCount - 1) * tube.gap
        local startX = (canvasW - totalW) / 2
        local centerY = canvasH / 2
        for i = 1, tubeCount do
            positions[i] = {
                x = startX + (i - 1) * (tube.width + tube.gap) + tube.width / 2,
                y = centerY,
            }
        end
    else
        local topCount = math.ceil(tubeCount / 2)
        local botCount = tubeCount - topCount
        local topTotalW = topCount * tube.width + (topCount - 1) * tube.gap
        local botTotalW = botCount * tube.width + (botCount - 1) * tube.gap
        local centerY = canvasH / 2
        local topY = centerY - tube.rowGap / 2 - tube.height / 4
        local botY = centerY + tube.rowGap / 2 + tube.height / 4
        local topStartX = (canvasW - topTotalW) / 2
        for i = 1, topCount do
            positions[i] = {
                x = topStartX + (i - 1) * (tube.width + tube.gap) + tube.width / 2,
                y = topY,
            }
        end
        local botStartX = (canvasW - botTotalW) / 2
        for i = 1, botCount do
            positions[topCount + i] = {
                x = botStartX + (i - 1) * (tube.width + tube.gap) + tube.width / 2,
                y = botY,
            }
        end
    end
    return positions
end

-- ============================================================
-- 几何辅助
-- ============================================================

--- 管内几何参数
local function tubeInnerMetrics()
    local tube = Config.tube
    local halfW = tube.width / 2
    local innerHalfW = halfW - tube.wall
    local floorYOffset = tube.height / 2 - tube.wall
    local innerH = tube.height - 2 * tube.wall
    local layerH = innerH / tube.layerCount
    return {
        innerHalfW = innerHalfW,
        floorYOffset = floorYOffset,
        innerH = innerH,
        layerH = layerH,
    }
end

--- 旋转点 (px,py) 绕 (ox,oy) 旋转 angle 弧度
local function rotatePoint(px, py, ox, oy, angle)
    local dx = px - ox
    local dy = py - oy
    local c = math.cos(angle)
    local s = math.sin(angle)
    return ox + dx * c - dy * s, oy + dx * s + dy * c
end

--- 线段与水平线交点
local function segHIntersect(x1, y1, x2, y2, hY)
    if (y1 - hY) * (y2 - hY) > 0 then return nil end
    if math.abs(y2 - y1) < 0.001 then return nil end
    local t = (hY - y1) / (y2 - y1)
    if t < -0.01 or t > 1.01 then return nil end
    return x1 + t * (x2 - x1)
end

Renderer.tubeInnerMetrics = tubeInnerMetrics
Renderer.rotatePoint = rotatePoint

-- ============================================================
-- 绘制: 玻璃外壳
-- ============================================================

function Renderer.drawGlassShell(nvg, cx, cy)
    local tube = Config.tube
    local theme = Config.getTheme()
    local glass = theme.glass
    local halfW = tube.width / 2
    local halfH = tube.height / 2
    local tubeLeft = cx - halfW
    local tubeRight = cx + halfW
    local tubeTop = cy - halfH
    local tubeBottom = cy + halfH
    local outerR = tube.bottomR + tube.wall
    local innerLeft = tubeLeft + tube.wall
    local innerRight = tubeRight - tube.wall
    local innerBottom = tubeBottom - tube.wall

    -- 半透明壁填充
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, tubeLeft, tubeTop)
    nvgLineTo(nvg, tubeLeft, tubeBottom - outerR)
    nvgArc(nvg, tubeLeft + outerR, tubeBottom - outerR, outerR, math.pi, math.pi * 0.5, 1)
    nvgLineTo(nvg, tubeRight - outerR, tubeBottom)
    nvgArc(nvg, tubeRight - outerR, tubeBottom - outerR, outerR, math.pi * 0.5, 0, 1)
    nvgLineTo(nvg, tubeRight, tubeTop)
    -- 内壁回
    nvgLineTo(nvg, innerRight, tubeTop)
    nvgLineTo(nvg, innerRight, innerBottom)
    nvgLineTo(nvg, innerLeft, innerBottom)
    nvgLineTo(nvg, innerLeft, tubeTop)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(glass.fillColor[1], glass.fillColor[2],
        glass.fillColor[3], glass.fillColor[4]))
    nvgFill(nvg)

    -- 外轮廓描边
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, tubeLeft, tubeTop)
    nvgLineTo(nvg, tubeLeft, tubeBottom - outerR)
    nvgArc(nvg, tubeLeft + outerR, tubeBottom - outerR, outerR, math.pi, math.pi * 0.5, 1)
    nvgLineTo(nvg, tubeRight - outerR, tubeBottom)
    nvgArc(nvg, tubeRight - outerR, tubeBottom - outerR, outerR, math.pi * 0.5, 0, 1)
    nvgLineTo(nvg, tubeRight, tubeTop)
    nvgStrokeColor(nvg, nvgRGBA(glass.strokeColor[1], glass.strokeColor[2],
        glass.strokeColor[3], glass.strokeColor[4]))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 管口装饰
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tubeLeft - 1, tubeTop - 2, tube.width + 2, 4, 2)
    nvgFillColor(nvg, nvgRGBA(glass.rimColor[1], glass.rimColor[2],
        glass.rimColor[3], glass.rimColor[4]))
    nvgFill(nvg)

    -- 左高光
    local hlPaint = nvgLinearGradient(nvg, tubeLeft + 2, tubeTop, tubeLeft + 7, tubeTop,
        nvgRGBA(glass.highlightColor[1], glass.highlightColor[2],
            glass.highlightColor[3], glass.highlightColor[4]),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, tubeLeft + 2, tubeTop + 8, 4, tube.height - tube.bottomR - 16)
    nvgFillPaint(nvg, hlPaint)
    nvgFill(nvg)
end

-- ============================================================
-- 绘制: 静态试管水层
-- ============================================================

function Renderer.drawStaticTubeLayers(nvg, cx, cy, layers, extraFill, extraColor)
    local m = tubeInnerMetrics()
    local tube = Config.tube
    local render = Config.render
    local colors = Config.getColors()
    local floorY = cy + m.floorYOffset

    local totalLayers = #layers
    local extraLayers = 0
    local extraFrac = 0
    if extraFill and extraFill > 0 then
        extraLayers = math.floor(extraFill)
        extraFrac = extraFill - extraLayers
    end

    local drawCount = totalLayers + extraLayers + (extraFrac > 0 and 1 or 0)
    for j = 1, math.min(drawCount, tube.layerCount) do
        local colorIdx
        local thisH = m.layerH
        if j <= totalLayers then
            colorIdx = layers[j]
        else
            colorIdx = extraColor
            if j == totalLayers + extraLayers + 1 and extraFrac > 0 then
                thisH = m.layerH * extraFrac
            end
        end

        local color = colors[colorIdx]
        if not color then goto nextLayer end

        local layerBottom = floorY - (j - 1) * m.layerH
        local layerTop = layerBottom - thisH

        nvgBeginPath(nvg)
        nvgRect(nvg, cx - m.innerHalfW, layerTop, m.innerHalfW * 2, layerBottom - layerTop)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], render.waterAlpha))
        nvgFill(nvg)

        -- 顶层水面光泽
        if j == drawCount or j == tube.layerCount then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx - m.innerHalfW + 5, layerTop + 1, m.innerHalfW * 2 - 10, 2.5, 1)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, render.surfaceHighlightAlpha))
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
                math.floor(color[3] * 0.6), render.layerLineAlpha))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end

        ::nextLayer::
    end
end

-- ============================================================
-- 绘制: 倾斜试管的水 (水面保持水平)
-- ============================================================

function Renderer.drawTiltedWater(nvg, cx, cy, pivotWX, pivotWY, angle, origLayers, removedCount)
    local m = tubeInnerMetrics()
    local tube = Config.tube
    local render = Config.render
    local colors = Config.getColors()
    local halfH = tube.height / 2

    local remaining = #origLayers - removedCount
    if remaining <= 0.05 then return end

    local innerLeft = cx - m.innerHalfW
    local innerRight = cx + m.innerHalfW
    local innerTop = cy - halfH
    local innerBottom = cy + halfH - tube.wall

    -- 旋转后的管内四角
    local ltx, lty = rotatePoint(innerLeft, innerTop, pivotWX, pivotWY, angle)
    local lbx, lby = rotatePoint(innerLeft, innerBottom, pivotWX, pivotWY, angle)
    local rbx, rby = rotatePoint(innerRight, innerBottom, pivotWX, pivotWY, angle)
    local rtx, rty = rotatePoint(innerRight, innerTop, pivotWX, pivotWY, angle)

    local outline = {
        { x = ltx, y = lty },
        { x = lbx, y = lby },
        { x = rbx, y = rby },
        { x = rtx, y = rty },
    }

    local absAngle = math.abs(angle)
    local innerH = m.innerH
    local halfInnerW = m.innerHalfW

    local floorRemoved = math.floor(removedCount)
    local fracRemoved = removedCount - floorRemoved
    local layersToShow = {}
    for j = 1, #origLayers - floorRemoved do
        layersToShow[j] = origLayers[j]
    end

    local effectiveRemaining = remaining
    if #layersToShow > 0 and fracRemoved > 0 then
        effectiveRemaining = #layersToShow - fracRemoved
    end

    -- 角度 >= 90° 时: 贴壁矩形渲染
    if absAngle >= math.pi * 0.5 then
        local thickness = effectiveRemaining * m.layerH * (2 * halfInnerW) / innerH
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

        local colorIdx = layersToShow[1]
        local color = colorIdx and colors[colorIdx]
        if not color then return end

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, p1x, p1y)
        nvgLineTo(nvg, p2x, p2y)
        nvgLineTo(nvg, p3x, p3y)
        nvgLineTo(nvg, p4x, p4y)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 225))
        nvgFill(nvg)
        return
    end

    -- 正常倾斜: 水平液面裁剪
    local tanA = absAngle > 0.001 and math.tan(absAngle) or 0
    local avgH = effectiveRemaining * m.layerH
    local hPour = math.min(avgH + halfInnerW * tanA, innerH)

    local pourWallX = angle >= 0 and (cx + halfInnerW) or (cx - halfInnerW)
    local pourWallWaterLocalY = innerBottom - hPour
    local _, waterY = rotatePoint(pourWallX, pourWallWaterLocalY, pivotWX, pivotWY, angle)

    if absAngle < 0.001 then
        waterY = innerBottom - effectiveRemaining * m.layerH
    end

    local maxY = outline[1].y
    for _, pt in ipairs(outline) do
        if pt.y > maxY then maxY = pt.y end
    end

    -- 水平线裁剪管内轮廓
    local clippedPoly = {}
    for i = 1, #outline do
        local cur = outline[i]
        local nxt = outline[(i % #outline) + 1]
        local curBelow = cur.y >= waterY
        local nxtBelow = nxt.y >= waterY
        if curBelow then table.insert(clippedPoly, cur) end
        if curBelow ~= nxtBelow then
            local ix = segHIntersect(cur.x, cur.y, nxt.x, nxt.y, waterY)
            if ix then table.insert(clippedPoly, { x = ix, y = waterY }) end
        end
    end

    if #clippedPoly < 3 then return end

    -- 分层着色
    local layerYPositions = {}
    for j = 0, #layersToShow do
        if j == 0 then
            layerYPositions[0] = maxY
        else
            local hJ = math.min(j * m.layerH + halfInnerW * tanA, innerH)
            local localY_j = innerBottom - hJ
            if absAngle < 0.001 then
                layerYPositions[j] = localY_j
            else
                local _, worldY_j = rotatePoint(pourWallX, localY_j, pivotWX, pivotWY, angle)
                layerYPositions[j] = worldY_j
            end
        end
    end

    -- Sutherland-Hodgman 裁剪
    local function clipPolyAbove(poly, clipY)
        if #poly == 0 then return {} end
        local out = {}
        for i = 1, #poly do
            local cur = poly[i]
            local nxt = poly[(i % #poly) + 1]
            local curIn = cur.y >= clipY - 0.01
            local nxtIn = nxt.y >= clipY - 0.01
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

    local function clipPolyBelow(poly, clipY)
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

    for j = 1, #layersToShow do
        local colorIdx = layersToShow[j]
        local color = colors[colorIdx]
        if not color then goto nextTiltLayer end

        local bandBottom = layerYPositions[j - 1] or maxY
        local bandTop = layerYPositions[j] or waterY
        if j == #layersToShow and fracRemoved > 0 then
            bandTop = waterY
        end
        if bandTop > bandBottom then bandTop, bandBottom = bandBottom, bandTop end

        local band = clipPolyAbove(clippedPoly, bandTop)
        band = clipPolyBelow(band, bandBottom)

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

-- ============================================================
-- 绘制: 水流
-- ============================================================

function Renderer.drawWaterStream(nvg, startX, startY, dstCX, dstCY, fillTotal, pourColor)
    local colors = Config.getColors()
    local color = colors[pourColor]
    if not color then return end

    local tube = Config.tube
    local render = Config.render
    local m = tubeInnerMetrics()
    local halfH = tube.height / 2

    local floorY = dstCY + m.floorYOffset
    local surfaceY = floorY - fillTotal * m.layerH
    local mouthY = dstCY - halfH
    local endX = dstCX
    local endY = math.max(surfaceY, mouthY)

    local segments = render.streamSegments
    local streamW = render.streamWidth

    nvgBeginPath(nvg)
    for s = 0, segments do
        local t = s / segments
        local px = lerp(startX, endX, t)
        local py = lerp(startY, endY, t * t)
        local w = streamW * (0.6 + 0.4 * math.sin(t * math.pi))
        if s == 0 then nvgMoveTo(nvg, px - w / 2, py)
        else nvgLineTo(nvg, px - w / 2, py) end
    end
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

-- ============================================================
-- 绘制: 胜利粒子
-- ============================================================

function Renderer.drawWinParticles(nvg, lx, ly, lw, lh, particles)
    local colors = Config.getColors()
    for _, p in ipairs(particles) do
        if p.life > 0 then
            local c = colors[p.color]
            if c then
                nvgBeginPath(nvg)
                nvgCircle(nvg, lx + p.x * lw, ly + p.y * lh, p.size * p.life)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(p.life * 220)))
                nvgFill(nvg)
            end
        end
    end
end

-- ============================================================
-- 绘制: 胜利文字
-- ============================================================

function Renderer.drawWinText(nvg, cx, cy)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 40)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 25))
    nvgText(nvg, cx + 1, cy + 2, "恭喜通关!")
    nvgFillColor(nvg, nvgRGBA(255, 195, 40, 255))
    nvgText(nvg, cx, cy, "恭喜通关!")
end

return Renderer
