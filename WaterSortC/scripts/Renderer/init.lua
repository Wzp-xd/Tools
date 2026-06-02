-- ============================================================
-- Renderer/init.lua - 统一公共 API（替代原 Renderer.lua）
-- ============================================================

local Common      = require("Renderer.Common")
local GlassTube   = require("Renderer.GlassTube")
local Liquid      = require("Renderer.Liquid")
local TiltedWater = require("Renderer.TiltedWater")
local Effects     = require("Renderer.Effects")

local Renderer = {}

-- ============================================================
-- 从 Common 导出的公共接口
-- ============================================================
Renderer.getTubeHeight      = Common.getTubeHeight
Renderer.getTubePositions   = Common.getTubePositions
Renderer.deriveTubeParams   = Common.deriveTubeParams
Renderer.rotatePoint        = Common.rotatePoint
Renderer.tubeInnerMetrics   = function()
    local d = Common.deriveTubeParams()
    return {
        innerHalfW = d.innerRadius,
        floorYOffset = d.bodyHeight / 2 + d.rimEllipseRY,
        innerH = d.bodyHeight,
        layerH = d.slotHeight,
    }
end

-- ============================================================
-- 从 GlassTube 导出
-- ============================================================
Renderer.drawGlassShellBase       = GlassTube.drawBase
Renderer.drawGlassShellHighlights = GlassTube.drawHighlights

-- ============================================================
-- 从 Liquid 导出
-- ============================================================
Renderer.drawStaticTubeLayers = Liquid.drawStaticLayers

-- ============================================================
-- 从 TiltedWater 导出
-- ============================================================
Renderer.drawTiltedWater = TiltedWater.draw

-- ============================================================
-- 从 Effects 导出
-- ============================================================
Renderer.drawWaterStream  = Effects.drawWaterStream
Renderer.drawWinParticles = Effects.drawWinParticles
Renderer.drawWinText      = Effects.drawWinText

return Renderer
