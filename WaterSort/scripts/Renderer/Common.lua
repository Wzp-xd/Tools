-- ============================================================
-- Renderer/Common.lua - 公共工具函数、推导参数、布局计算
-- ============================================================

local Config = require("config")
local Animation = require("Animation")

local Common = {}

local lerp = Animation.lerp
local clamp = Animation.clamp
Common.lerp = lerp
Common.clamp = clamp

-- ============================================================
-- 常量
-- ============================================================
Common.KAPPA = 0.5522847498 -- 4 * (sqrt(2) - 1) / 3，用于 Bézier 圆弧近似

-- ============================================================
-- 颜色工具函数
-- ============================================================

--- 将颜色按比例变暗
---@param color table {r, g, b}
---@param factor number 0~1
---@return integer, integer, integer
function Common.darkenColor(color, factor)
    return
        math.floor(clamp(color[1] * factor, 0, 255)),
        math.floor(clamp(color[2] * factor, 0, 255)),
        math.floor(clamp(color[3] * factor, 0, 255))
end

--- 将颜色增亮
---@param color table {r, g, b}
---@param amount number 增加量
---@return integer, integer, integer
function Common.lightenColor(color, amount)
    return
        math.floor(clamp(color[1] + amount, 0, 255)),
        math.floor(clamp(color[2] + amount, 0, 255)),
        math.floor(clamp(color[3] + amount, 0, 255))
end

-- ============================================================
-- Bézier 半椭圆弧
-- ============================================================

--- 绘制半椭圆弧（从左到右，经过底部，顺时针方向）
--- 起点 (cx - rx, cy) 必须由上层 moveTo/lineTo 到达
--- 终点 (cx + rx, cy)
function Common.semiEllipseCW(vg, cx, cy, rx, ry)
    local K = Common.KAPPA
    nvgBezierTo(vg,
        cx - rx,       cy + ry * K,
        cx - rx * K,   cy + ry,
        cx,            cy + ry)
    nvgBezierTo(vg,
        cx + rx * K,   cy + ry,
        cx + rx,       cy + ry * K,
        cx + rx,       cy)
end

--- 绘制半椭圆弧（从右到左，经过底部）
--- 起点 (cx + rx, cy)，终点 (cx - rx, cy)
function Common.semiEllipseRTL(vg, cx, cy, rx, ry)
    local K = Common.KAPPA
    nvgBezierTo(vg,
        cx + rx,       cy + ry * K,
        cx + rx * K,   cy + ry,
        cx,            cy + ry)
    nvgBezierTo(vg,
        cx - rx * K,   cy + ry,
        cx - rx,       cy + ry * K,
        cx - rx,       cy)
end

-- ============================================================
-- 推导参数（带缓存）
-- ============================================================

local _cachedParams = nil

--- 从 Config.tube 实时计算所有推导参数
---@return table
function Common.deriveTubeParams()
    if _cachedParams then return _cachedParams end
    local T = Config.tube
    local CAP = T.layerCount

    local outerRadius   = T.width / 2
    local innerWidth    = T.width - 2 * T.wall
    local innerRadius   = innerWidth / 2
    local rimEllipseRY  = outerRadius * T.ellipticity
    local liqEllipseRY  = innerRadius * T.ellipticity
    local bottomEllipseRY = rimEllipseRY
    local innerBottomEllipseRY = liqEllipseRY

    local bodyHeight = T.topPadding + CAP * T.slotHeight
    local totalHeight = rimEllipseRY * 2 + bodyHeight + bottomEllipseRY

    _cachedParams = {
        outerRadius             = outerRadius,
        innerWidth              = innerWidth,
        innerRadius             = innerRadius,
        slotHeight              = T.slotHeight,
        topPadding              = T.topPadding,
        bodyHeight              = bodyHeight,
        rimEllipseRY            = rimEllipseRY,
        liqEllipseRY            = liqEllipseRY,
        bottomEllipseRY         = bottomEllipseRY,
        innerBottomEllipseRY    = innerBottomEllipseRY,
        totalHeight             = totalHeight,
    }
    return _cachedParams
end

--- 供外部调用：获取试管总高度（用于布局和 hitTest）
function Common.getTubeHeight()
    local d = Common.deriveTubeParams()
    return d.totalHeight
end

-- ============================================================
-- 布局计算（带缓存）
-- ============================================================

local _posCache = { w = 0, h = 0, count = 0, result = nil }

--- 计算所有试管的中心位置
---@param canvasW number
---@param canvasH number
---@param tubeCount integer
---@return table[] positions { {x, y}, ... }
function Common.getTubePositions(canvasW, canvasH, tubeCount)
    if _posCache.w == canvasW and _posCache.h == canvasH and _posCache.count == tubeCount then
        return _posCache.result
    end

    local tube = Config.tube
    local d = Common.deriveTubeParams()
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
        local topY = centerY - tube.rowGap / 2 - d.totalHeight / 4
        local botY = centerY + tube.rowGap / 2 + d.totalHeight / 4
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

    _posCache = { w = canvasW, h = canvasH, count = tubeCount, result = positions }
    return positions
end

-- ============================================================
-- 层合并：连续同色层合并为 segment
-- ============================================================

--- 将 layers 数组合并为连续同色 segments
--- 支持 removedCount（从顶部移除的层数，可含小数）
---@param layers integer[] 颜色索引数组（从底到顶）
---@param removedCount? number 已移除的层数（从顶层开始，默认 0）
---@return { colorIdx: integer, count: number }[] segments 从底到顶排列
function Common.mergeSegments(layers, removedCount)
    removedCount = removedCount or 0
    local totalLayers = #layers
    local effectiveTop = totalLayers - removedCount
    if effectiveTop <= 0 then return {} end

    local floorTop = math.floor(effectiveTop)
    local frac = effectiveTop - floorTop  -- 顶层的小数部分

    local segments = {}
    local curColor = nil
    local curCount = 0

    for j = 1, floorTop do
        local colorIdx = layers[j]
        if colorIdx == curColor then
            curCount = curCount + 1
        else
            if curColor then
                segments[#segments + 1] = { colorIdx = curColor, count = curCount }
            end
            curColor = colorIdx
            curCount = 1
        end
    end

    -- 处理顶部小数层
    if frac > 0 and floorTop + 1 <= totalLayers then
        local topColorIdx = layers[floorTop + 1]
        if topColorIdx == curColor then
            curCount = curCount + frac
        else
            if curColor then
                segments[#segments + 1] = { colorIdx = curColor, count = curCount }
            end
            curColor = topColorIdx
            curCount = frac
        end
    end

    if curColor then
        segments[#segments + 1] = { colorIdx = curColor, count = curCount }
    end

    return segments
end

-- ============================================================
-- 几何辅助
-- ============================================================

--- 旋转点 (px,py) 绕 (ox,oy) 旋转 angle 弧度
function Common.rotatePoint(px, py, ox, oy, angle)
    local dx = px - ox
    local dy = py - oy
    local c = math.cos(angle)
    local s = math.sin(angle)
    return ox + dx * c - dy * s, oy + dx * s + dy * c
end

--- 线段与水平线交点
function Common.segHIntersect(x1, y1, x2, y2, hY)
    if (y1 - hY) * (y2 - hY) > 0 then return nil end
    if math.abs(y2 - y1) < 0.001 then return nil end
    local t = (hY - y1) / (y2 - y1)
    if t < -0.01 or t > 1.01 then return nil end
    return x1 + t * (x2 - x1)
end

return Common
