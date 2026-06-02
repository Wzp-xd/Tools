-- ============================================================
-- Renderer/Effects.lua - 水流、胜利粒子、胜利文字
-- ============================================================

local Config = require("config")
local Common = require("Renderer.Common")

local lerp = Common.lerp

local Effects = {}

-- ============================================================
-- 水流绘制 (Phase 4: 粗细渐变 + 圆头圆尾 + 高光)
-- ============================================================

--- 绘制从源管口到目标管的水流
function Effects.drawWaterStream(nvg, startX, startY, dstCX, dstCY, fillTotal, pourColor)
    local colors = Config.getColors()
    local color = colors[pourColor]
    if not color then return end

    local tube = Config.tube
    local render = Config.render
    local d = Common.deriveTubeParams()
    local halfH = d.totalHeight / 2

    local straightTop = dstCY - halfH + d.rimEllipseRY * 2
    local surfaceY = straightTop + d.topPadding + (tube.layerCount - fillTotal) * d.slotHeight
    local mouthY = dstCY - halfH
    local endX = dstCX
    local endY = math.max(surfaceY, mouthY)

    local segments = render.streamSegments
    local streamW = render.streamWidth

    -- 计算路径点和宽度
    local pts = {}
    for s = 0, segments do
        local t = s / segments
        local px = lerp(startX, endX, t)
        local py = lerp(startY, endY, t * t) -- 抛物线
        local w = streamW * (1.0 - 0.5 * t) * (0.7 + 0.3 * math.sin(t * math.pi))
        pts[s] = { x = px, y = py, w = math.max(w, 1.5) }
    end

    -- 水流主体：左侧轮廓 + 右侧轮廓闭合
    nvgBeginPath(nvg)
    local p0 = pts[0]
    nvgMoveTo(nvg, p0.x - p0.w / 2, p0.y)

    -- 左侧轮廓
    for s = 1, segments do
        nvgLineTo(nvg, pts[s].x - pts[s].w / 2, pts[s].y)
    end

    -- 圆尾
    local pEnd = pts[segments]
    nvgLineTo(nvg, pEnd.x - pEnd.w / 2, pEnd.y)
    nvgBezierTo(nvg,
        pEnd.x - pEnd.w / 2, pEnd.y + pEnd.w * 0.4,
        pEnd.x + pEnd.w / 2, pEnd.y + pEnd.w * 0.4,
        pEnd.x + pEnd.w / 2, pEnd.y)

    -- 右侧轮廓
    for s = segments - 1, 0, -1 do
        nvgLineTo(nvg, pts[s].x + pts[s].w / 2, pts[s].y)
    end

    -- 圆头闭合
    nvgBezierTo(nvg,
        p0.x + p0.w / 2, p0.y - p0.w * 0.3,
        p0.x - p0.w / 2, p0.y - p0.w * 0.3,
        p0.x - p0.w / 2, p0.y)

    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], tube.liquidAlpha))
    nvgFill(nvg)

    -- 边缘暗化
    local minX = math.min(startX, endX) - streamW
    local edgeGradL = nvgLinearGradient(nvg,
        minX, startY, minX + streamW * 1.5, startY,
        nvgRGBA(0, 0, 0, 35), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, minX, startY, streamW * 1.5, endY - startY)
    nvgFillPaint(nvg, edgeGradL)
    nvgFill(nvg)

    -- 高光带
    nvgBeginPath(nvg)
    for s = 0, segments do
        local px = pts[s].x - pts[s].w * 0.25
        local py = pts[s].y
        if s == 0 then nvgMoveTo(nvg, px, py)
        else nvgLineTo(nvg, px, py) end
    end
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 50))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

-- ============================================================
-- 胜利粒子
-- ============================================================

--- 绘制胜利粒子效果
function Effects.drawWinParticles(nvg, lx, ly, lw, lh, particles)
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
-- 胜利文字
-- ============================================================

--- 绘制"恭喜通关"文字
function Effects.drawWinText(nvg, cx, cy)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 40)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 暗色投影
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 120))
    nvgText(nvg, cx + 2, cy + 3, "恭喜通关!")
    -- 金色主文字
    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
    nvgText(nvg, cx, cy, "恭喜通关!")
end

return Effects
