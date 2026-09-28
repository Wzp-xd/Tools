-- ============================================================================
-- Third Person Shooter - Main Entry (多人模式)
-- 支持: Standalone / Client / Server 三种模式
--
-- 控制说明:
--   WASD: 移动 | Shift: 跑步 | Space: 跳跃
--   Q: 切换持枪 | 鼠标左键: 射击 | 鼠标右键: 瞄准 | R: 换弹
-- ============================================================================

local Module = nil

function Start()
    if IsServerMode() then
        print("[Main] Starting in SERVER mode")
        Module = require("network.Server")
    elseif IsNetworkMode() then
        print("[Main] Starting in CLIENT mode")
        Module = require("network.Client")
    else
        print("[Main] Starting in STANDALONE mode")
        Module = require("network.Standalone")
    end
    Module.Start()
end

function Stop()
    if Module and Module.Stop then
        Module.Stop()
    end
end
