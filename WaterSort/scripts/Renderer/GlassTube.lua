-- ============================================================
-- Renderer/GlassTube.lua - 3D 玻璃管壁绘制
-- ============================================================

local Config = require("config")
local Common = require("Renderer.Common")

local GlassTube = {}

local KAPPA = Common.KAPPA
local semiEllipseCW = Common.semiEllipseCW

-- ============================================================
-- 内部路径辅助
-- ============================================================

--- 试管外轮廓路径（直筒 + 底部椭圆弧 + 上方椭圆弧闭合）
local function tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, bottomRY, tubeW, rimEllipseRY)
    local rimCY = straightTop - rimEllipseRY

    nvgMoveTo(vg, x, rimCY)
    nvgLineTo(vg, x, straightBottom)
    semiEllipseCW(vg, cx, straightBottom, outerR, bottomRY)
    nvgLineTo(vg, x + tubeW, rimCY)
    nvgBezierTo(vg,
        x + tubeW,             rimCY - rimEllipseRY * KAPPA,
        cx + outerR * KAPPA,   rimCY - rimEllipseRY,
        cx,                    rimCY - rimEllipseRY)
    nvgBezierTo(vg,
        cx - outerR * KAPPA,   rimCY - rimEllipseRY,
        x,                     rimCY - rimEllipseRY * KAPPA,
        x,                     rimCY)
    nvgClosePath(vg)
end

--- 管内衬底封闭路径
local function innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBottomRY, liqEllipseRY)
    nvgMoveTo(vg, innerX, rimCY)
    nvgLineTo(vg, innerX, bottomY)
    semiEllipseCW(vg, cx, bottomY, innerR, innerBottomRY)
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

-- ============================================================
-- 各层绘制
-- ============================================================

--- 管底投影
local function drawShadow(vg, x, bottomY, tubeW)
    local shadow = nvgBoxGradient(vg, x + 2, bottomY - 4, tubeW - 4, 8, 4, 12,
        nvgRGBA(0, 0, 0, 80), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - 8, bottomY - 10, tubeW + 16, 20)
    nvgFillPaint(vg, shadow)
    nvgFill(vg)
end

--- 管内衬底（边缘暗化）
local function drawInnerBack(vg, cx, innerX, topY, bottomY, innerR, innerBottomRY, rimEllipseRY, liqEllipseRY)
    local rimCY = topY - rimEllipseRY
    local innerW = innerR * 2

    local edgeW = innerW * 0.22
    local edgeL = nvgLinearGradient(vg, innerX, topY, innerX + edgeW, topY,
        nvgRGBA(0, 0, 0, 40), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBottomRY, liqEllipseRY)
    nvgFillPaint(vg, edgeL)
    nvgFill(vg)

    local rightX = innerX + innerW
    local edgeR = nvgLinearGradient(vg, rightX - edgeW, topY, rightX, topY,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 28))
    nvgBeginPath(vg)
    innerBackPath(vg, cx, innerX, rimCY, bottomY, innerR, innerBottomRY, liqEllipseRY)
    nvgFillPaint(vg, edgeR)
    nvgFill(vg)
end

--- 管口内沿 AO 阴影 + 底部椭圆交汇处 AO
local function drawInnerAO(vg, innerX, straightTop, straightBottom, innerW)
    local AO = Config.tube.ao

    local aoTop = nvgLinearGradient(vg, innerX, straightTop, innerX, straightTop + AO.rimShadowHeight,
        nvgRGBA(0, 0, 0, AO.rimShadowAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, innerX, straightTop, innerW, AO.rimShadowHeight)
    nvgFillPaint(vg, aoTop)
    nvgFill(vg)

    local aoBot = nvgLinearGradient(vg, innerX, straightBottom - AO.ballJointHeight, innerX, straightBottom,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, AO.ballJointAlpha))
    nvgBeginPath(vg)
    nvgRect(vg, innerX, straightBottom - AO.ballJointHeight, innerW, AO.ballJointHeight)
    nvgFillPaint(vg, aoBot)
    nvgFill(vg)
end

--- 玻璃管壁（4 层渐变光照模型）
local function drawGlassWall(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    local G = Config.tube.glass

    -- 层0：管壁蓝色调底色
    if G.baseTintColor and G.baseTintAlpha > 0 then
        local tc = G.baseTintColor
        nvgBeginPath(vg)
        tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], G.baseTintAlpha))
        nvgFill(vg)
    end

    -- 层A：左边缘暗线
    local darkL = nvgLinearGradient(vg, x, straightTop, x + tubeW * 0.05, straightTop,
        nvgRGBA(0, 0, 0, G.edgeDarkAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, darkL)
    nvgFill(vg)

    -- 层B：主高光带（8%~28%）
    local hlX0 = x + tubeW * 0.08
    local hlX1 = x + tubeW * 0.18
    local hlX2 = x + tubeW * 0.28
    local hlL = nvgLinearGradient(vg, hlX0, straightTop, hlX1, straightTop,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, G.mainHighlightAlpha))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, hlL)
    nvgFill(vg)
    local hlR = nvgLinearGradient(vg, hlX1, straightTop, hlX2, straightTop,
        nvgRGBA(255, 255, 255, G.mainHighlightAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, hlR)
    nvgFill(vg)

    -- 层C：右侧次高光（70%~90%）
    local shX0 = x + tubeW * 0.70
    local shX1 = x + tubeW * 0.80
    local shX2 = x + tubeW * 0.90
    local shL = nvgLinearGradient(vg, shX0, straightTop, shX1, straightTop,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, G.secHighlightAlpha))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, shL)
    nvgFill(vg)
    local shR = nvgLinearGradient(vg, shX1, straightTop, shX2, straightTop,
        nvgRGBA(255, 255, 255, G.secHighlightAlpha), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, shR)
    nvgFill(vg)

    -- 层D：右边缘暗线
    local darkR = nvgLinearGradient(vg, x + tubeW * 0.95, straightTop, x + tubeW, straightTop,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, math.floor(G.edgeDarkAlpha * 0.75)))
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgFillPaint(vg, darkR)
    nvgFill(vg)

    -- 管壁轮廓描边
    nvgBeginPath(vg)
    tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    nvgStrokeColor(vg, nvgRGBA(180, 200, 230, 35))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

--- 管口椭圆 + 厚度环
local function drawRim(vg, cx, straightTop, outerR, innerR, ellipticity)
    local outerRY = outerR * ellipticity
    local innerRY = innerR * ellipticity
    local rimCY = straightTop - outerRY
    local G = Config.tube.glass

    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, outerR, outerRY)
    nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 70))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local midR = (outerR + innerR) / 2
    local ringGrad = nvgRadialGradient(vg, cx - outerR * 0.15, rimCY - outerRY * 0.2,
        midR * 0.5, midR * 1.2,
        nvgRGBA(180, 200, 230, G.rimRingAlpha),
        nvgRGBA(40, 50, 70, math.floor(G.rimRingAlpha * 0.3)))
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, outerR - 0.5, outerRY - 0.5)
    nvgPathWinding(vg, NVG_HOLE)
    nvgEllipse(vg, cx, rimCY, innerR + 0.5, innerRY + 0.5)
    nvgFillPaint(vg, ringGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgEllipse(vg, cx, rimCY, innerR, innerRY)
    nvgFillColor(vg, nvgRGBA(8, 8, 18, 220))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - outerR, rimCY)
    nvgBezierTo(vg,
        cx - outerR,         rimCY - outerRY * KAPPA,
        cx - outerR * KAPPA, rimCY - outerRY,
        cx,                  rimCY - outerRY)
    nvgBezierTo(vg,
        cx + outerR * KAPPA, rimCY - outerRY,
        cx + outerR,         rimCY - outerRY * KAPPA,
        cx + outerR,         rimCY)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 45))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

--- 底部椭圆高光
local function drawBottomHighlight(vg, cx, straightBottom, outerR, bottomRY)
    local G = Config.tube.glass
    local hlW = outerR * G.ballHighlightSize
    local hlH = bottomRY * G.ballHighlightSize * 0.8
    local hlCX = cx - outerR * 0.25
    local hlCY = straightBottom + bottomRY * 0.4

    local grad = nvgRadialGradient(vg, hlCX, hlCY, 1, math.max(hlW, hlH),
        nvgRGBA(255, 255, 255, G.ballHighlightAlpha),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, hlCX, hlCY, hlW, hlH)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 绘制试管底层（投影 + 管内衬底 + AO + 管壁）
function GlassTube.drawBase(nvg, cx, cy)
    local vg = nvg
    local T = Config.tube
    local d = Common.deriveTubeParams()

    local x = cx - d.outerRadius
    local halfH = d.totalHeight / 2
    local straightTop = cy - halfH + d.rimEllipseRY * 2
    local straightBottom = straightTop + d.bodyHeight
    local tubeBottom = straightBottom + d.bottomEllipseRY
    local innerX = cx - d.innerRadius

    drawShadow(vg, x, tubeBottom, T.width)
    drawInnerBack(vg, cx, innerX, straightTop, straightBottom,
        d.innerRadius, d.innerBottomEllipseRY, d.rimEllipseRY, d.liqEllipseRY)
    drawInnerAO(vg, innerX, straightTop, straightBottom, d.innerWidth)
    drawGlassWall(vg, x, straightTop, straightBottom, cx, d.outerRadius,
        d.bottomEllipseRY, T.width, d.rimEllipseRY)
end

--- 绘制试管高光层（底部高光 + 管口椭圆）
function GlassTube.drawHighlights(nvg, cx, cy)
    local vg = nvg
    local T = Config.tube
    local d = Common.deriveTubeParams()

    local halfH = d.totalHeight / 2
    local straightTop = cy - halfH + d.rimEllipseRY * 2
    local straightBottom = straightTop + d.bodyHeight

    drawBottomHighlight(vg, cx, straightBottom, d.outerRadius, d.bottomEllipseRY)
    drawRim(vg, cx, straightTop, d.outerRadius, d.innerRadius, T.ellipticity)
end

return GlassTube
