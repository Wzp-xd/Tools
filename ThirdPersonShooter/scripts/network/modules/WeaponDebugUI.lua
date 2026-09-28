-- ============================================================================
-- WeaponDebugUI.lua - 武器调试UI模块
-- 提供滑块调整武器绑定位置、缩放和发射位置
-- ============================================================================

local WeaponConfig = require "network.modules.WeaponConfig"

local M = {}

-- UI 状态
local enabled_ = false
local nvgCtx_ = nil
local fontId_ = -1

-- 当前编辑的武器配置（实时修改）
local currentWeaponId_ = nil
local editValues_ = {
    posX = 0, posY = 0, posZ = 0,
    scale = 1.0,
    muzzleX = 0, muzzleY = 0, muzzleZ = 0,
}

-- 滑块配置
local sliders_ = {
    { key = "posX",    label = "偏移 X",   min = -0.5, max = 0.5, step = 0.01 },
    { key = "posY",    label = "偏移 Y",   min = -0.5, max = 0.5, step = 0.01 },
    { key = "posZ",    label = "偏移 Z",   min = -0.5, max = 0.5, step = 0.01 },
    { key = "scale",   label = "缩放",     min = 0.5,  max = 3.0, step = 0.01 },
    { key = "muzzleX", label = "枪口 X",   min = -0.7, max = 0.7, step = 0.01 },
    { key = "muzzleY", label = "枪口 Y",   min = -0.7, max = 0.7, step = 0.01 },
    { key = "muzzleZ", label = "枪口 Z",   min = -0.7, max = 0.7, step = 0.01 },
}

-- UI 布局
local UI = {
    x = 10,
    y = 150,
    width = 280,
    sliderHeight = 28,
    padding = 8,
    labelWidth = 70,
    valueWidth = 50,
}

-- 鼠标交互状态
local draggingSlider_ = nil
local hoverSlider_ = nil

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init(ctx, font)
    nvgCtx_ = ctx
    fontId_ = font
end

function M.SetEnabled(enabled)
    enabled_ = enabled
end

function M.IsEnabled()
    return enabled_
end

function M.Toggle()
    enabled_ = not enabled_
    return enabled_
end

-- ============================================================================
-- 武器切换时加载默认值
-- ============================================================================

function M.OnWeaponChanged(weaponId)
    if weaponId == currentWeaponId_ then return end
    currentWeaponId_ = weaponId
    
    if not weaponId then
        return
    end
    
    local cfg = WeaponConfig.WEAPONS[weaponId]
    if not cfg or not cfg.model then
        return
    end
    
    local model = cfg.model
    local pos = model.positionOffset or Vector3.ZERO
    local muzzle = model.muzzleOffset or Vector3.ZERO
    local scale = model.scale or Vector3(1, 1, 1)
    
    editValues_.posX = pos.x
    editValues_.posY = pos.y
    editValues_.posZ = pos.z
    editValues_.scale = scale.x  -- 假设统一缩放
    editValues_.muzzleX = muzzle.x
    editValues_.muzzleY = muzzle.y
    editValues_.muzzleZ = muzzle.z
    
    print(string.format("[WeaponDebugUI] Loaded %s: pos(%.2f,%.2f,%.2f) scale=%.1f muzzle(%.2f,%.2f,%.2f)",
        weaponId, pos.x, pos.y, pos.z, scale.x, muzzle.x, muzzle.y, muzzle.z))
end

-- ============================================================================
-- 获取当前编辑值（供外部使用）
-- ============================================================================

function M.GetPositionOffset()
    return Vector3(editValues_.posX, editValues_.posY, editValues_.posZ)
end

function M.GetScale()
    return Vector3(editValues_.scale, editValues_.scale, editValues_.scale)
end

function M.GetMuzzleOffset()
    return Vector3(editValues_.muzzleX, editValues_.muzzleY, editValues_.muzzleZ)
end

function M.GetCurrentWeaponId()
    return currentWeaponId_
end

-- ============================================================================
-- 鼠标事件处理
-- ============================================================================

function M.HandleMouseDown(x, y, button)
    if not enabled_ then return false end
    if button ~= MOUSEB_LEFT then return false end
    
    -- 检查是否点击了滑块
    for i, slider in ipairs(sliders_) do
        local sliderY = UI.y + (i - 1) * (UI.sliderHeight + UI.padding) + 25
        local sliderX = UI.x + UI.labelWidth + 10
        local sliderW = UI.width - UI.labelWidth - UI.valueWidth - 20
        
        if x >= sliderX and x <= sliderX + sliderW and
           y >= sliderY and y <= sliderY + UI.sliderHeight then
            draggingSlider_ = i
            M.UpdateSliderValue(i, x, sliderX, sliderW)
            return true
        end
    end
    
    return false
end

function M.HandleMouseUp(x, y, button)
    if draggingSlider_ then
        draggingSlider_ = nil
        return true
    end
    return false
end

function M.HandleMouseMove(x, y, isMouseDown)
    if not enabled_ then return false end
    
    -- 如果鼠标释放，停止拖拽
    if not isMouseDown and draggingSlider_ then
        draggingSlider_ = nil
    end
    
    -- 更新 hover 状态
    hoverSlider_ = nil
    for i, slider in ipairs(sliders_) do
        local sliderY = UI.y + (i - 1) * (UI.sliderHeight + UI.padding) + 25
        local sliderX = UI.x + UI.labelWidth + 10
        local sliderW = UI.width - UI.labelWidth - UI.valueWidth - 20
        
        if x >= sliderX and x <= sliderX + sliderW and
           y >= sliderY and y <= sliderY + UI.sliderHeight then
            hoverSlider_ = i
            break
        end
    end
    
    -- 拖拽中更新值
    if draggingSlider_ then
        local sliderX = UI.x + UI.labelWidth + 10
        local sliderW = UI.width - UI.labelWidth - UI.valueWidth - 20
        M.UpdateSliderValue(draggingSlider_, x, sliderX, sliderW)
        return true
    end
    
    return false
end

function M.UpdateSliderValue(index, mouseX, sliderX, sliderW)
    local slider = sliders_[index]
    if not slider then return end
    
    local t = (mouseX - sliderX) / sliderW
    t = math.max(0, math.min(1, t))
    
    local value = slider.min + t * (slider.max - slider.min)
    
    -- 按步进对齐
    if slider.step then
        value = math.floor(value / slider.step + 0.5) * slider.step
    end
    
    editValues_[slider.key] = value
end

-- ============================================================================
-- 检查鼠标是否在UI区域内
-- ============================================================================

function M.IsMouseOverUI(x, y)
    if not enabled_ then return false end
    
    local totalHeight = #sliders_ * (UI.sliderHeight + UI.padding) + 60
    return x >= UI.x and x <= UI.x + UI.width and
           y >= UI.y and y <= UI.y + totalHeight
end

-- ============================================================================
-- 渲染
-- ============================================================================

function M.Render(ctx)
    if not enabled_ then return end
    if not ctx then ctx = nvgCtx_ end
    if not ctx then return end
    
    local totalHeight = #sliders_ * (UI.sliderHeight + UI.padding) + 60
    
    -- 背景面板
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, UI.x, UI.y, UI.width, totalHeight, 8)
    nvgFillColor(ctx, nvgRGBA(20, 25, 35, 230))
    nvgFill(ctx)
    
    -- 边框
    nvgStrokeColor(ctx, nvgRGBA(60, 80, 120, 200))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
    
    -- 标题
    if fontId_ ~= -1 then
        nvgFontFaceId(ctx, fontId_)
    end
    nvgFontSize(ctx, 16)
    nvgFillColor(ctx, nvgRGBA(100, 200, 255, 255))
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    
    local titleText = "武器调试"
    if currentWeaponId_ then
        local cfg = WeaponConfig.WEAPONS[currentWeaponId_]
        if cfg then
            titleText = titleText .. " - " .. (cfg.nameZh or cfg.name)
        end
    end
    nvgText(ctx, UI.x + 10, UI.y + 5, titleText)
    
    -- 绘制滑块
    for i, slider in ipairs(sliders_) do
        local y = UI.y + (i - 1) * (UI.sliderHeight + UI.padding) + 25
        M.DrawSlider(ctx, slider, i, y)
    end
    
    -- 底部提示
    nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(150, 150, 150, 200))
    local tipY = UI.y + totalHeight - 18
    nvgText(ctx, UI.x + 10, tipY, "F4 关闭 | 拖拽滑块调整")
end

function M.DrawSlider(ctx, slider, index, y)
    local sliderX = UI.x + UI.labelWidth + 10
    local sliderW = UI.width - UI.labelWidth - UI.valueWidth - 20
    local sliderH = 8
    local sliderCenterY = y + UI.sliderHeight / 2
    
    local value = editValues_[slider.key] or 0
    local t = (value - slider.min) / (slider.max - slider.min)
    t = math.max(0, math.min(1, t))
    
    -- 标签
    nvgFontSize(ctx, 14)
    nvgFillColor(ctx, nvgRGBA(200, 200, 200, 255))
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(ctx, UI.x + 10, sliderCenterY, slider.label)
    
    -- 滑块轨道背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sliderX, sliderCenterY - sliderH / 2, sliderW, sliderH, 4)
    nvgFillColor(ctx, nvgRGBA(50, 55, 65, 255))
    nvgFill(ctx)
    
    -- 滑块填充
    local fillW = sliderW * t
    if fillW > 0 then
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sliderX, sliderCenterY - sliderH / 2, fillW, sliderH, 4)
        
        -- 根据是否拖拽/悬停改变颜色
        if draggingSlider_ == index then
            nvgFillColor(ctx, nvgRGBA(100, 200, 255, 255))
        elseif hoverSlider_ == index then
            nvgFillColor(ctx, nvgRGBA(80, 160, 220, 255))
        else
            nvgFillColor(ctx, nvgRGBA(60, 140, 200, 255))
        end
        nvgFill(ctx)
    end
    
    -- 滑块手柄
    local handleX = sliderX + sliderW * t
    local handleR = 10
    
    nvgBeginPath(ctx)
    nvgCircle(ctx, handleX, sliderCenterY, handleR)
    
    if draggingSlider_ == index then
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    elseif hoverSlider_ == index then
        nvgFillColor(ctx, nvgRGBA(220, 230, 240, 255))
    else
        nvgFillColor(ctx, nvgRGBA(180, 190, 200, 255))
    end
    nvgFill(ctx)
    
    -- 手柄边框
    nvgStrokeColor(ctx, nvgRGBA(100, 120, 150, 255))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
    
    -- 数值显示
    nvgFontSize(ctx, 13)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local valueText = string.format("%.2f", value)
    nvgText(ctx, UI.x + UI.width - 10, sliderCenterY, valueText)
end

return M
