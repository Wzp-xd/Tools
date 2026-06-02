--- InputHandler.lua — 输入处理：鼠标/触摸 → hitTest → 分发事件
local Config = require("Config")

local InputHandler = {}

local TUBE = Config.TUBE
local callback_        = nil
local positions_       = nil
local tubeH_           = 0
local getAnimOffsets_  = nil
local uiModule_        = nil -- UI 模块引用，用于 IsPointerOverUI

--- 初始化
---@param opts table { positions, tubeH, getAnimOffsets, onTubeClick, uiModule }
function InputHandler.init(opts)
    positions_       = opts.positions
    tubeH_           = opts.tubeH
    getAnimOffsets_  = opts.getAnimOffsets
    callback_        = opts.onTubeClick
    uiModule_        = opts.uiModule

    SubscribeToEvent("MouseButtonDown", "HandleMouseDown_Input")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin_Input")
end

--- 布局变化时更新
function InputHandler.updateLayout(positions, tubeH)
    positions_ = positions
    tubeH_     = tubeH
end

-- 全局回调函数（避免与其他模块冲突，加后缀）
-- luacheck: globals HandleMouseDown_Input HandleTouchBegin_Input

function HandleMouseDown_Input(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    if uiModule_ and uiModule_.IsPointerOverUI() then return end

    local mousePos = input.mousePosition
    local dpr = graphics:GetDPR()
    InputHandler._processHit(mousePos.x / dpr, mousePos.y / dpr)
end

function HandleTouchBegin_Input(eventType, eventData)
    if uiModule_ and uiModule_.IsPointerOverUI() then return end

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    InputHandler._processHit(tx / dpr, ty / dpr)
end

function InputHandler._processHit(px, py)
    if not positions_ or not callback_ then return end
    for i, pos in ipairs(positions_) do
        local liftY, shakeX = 0, 0
        if getAnimOffsets_ then
            liftY, shakeX = getAnimOffsets_(i)
        end
        local tx = pos.x + shakeX
        local ty = pos.y - liftY

        if px >= tx and px <= tx + TUBE.tubeWidth
           and py >= ty and py <= ty + tubeH_ then
            callback_(i)
            return
        end
    end
end

return InputHandler
