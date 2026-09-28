-- ============================================================================
-- UI.lua - HUD 渲染
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Weapon = require "modules.Weapon"

local M = {}

local CONFIG = Config.CONFIG

--- 是否为触摸/移动模式（用于决定显示虚拟按钮还是按键提示）
local isTouchMode = false

--- 设置输入模式
---@param touchMode boolean 是否为触摸模式
function M.SetTouchMode(touchMode)
    isTouchMode = touchMode
end

--- 获取是否为触摸模式
---@return boolean
function M.IsTouchMode()
    return isTouchMode
end

-- UI 配置 (3A级科技风格)
local UI_CONFIG = {
    padding = 14,
    cornerRadius = 6,
    -- 主色调：深蓝科技风
    bgColor = { 8, 12, 22, 200 },
    borderColor = { 60, 140, 200, 120 },
    accentColor = { 80, 180, 255 },      -- 科技蓝高亮
    warningColor = { 255, 180, 60 },     -- 警告橙
    dangerColor = { 255, 80, 80 },       -- 危险红
    successColor = { 80, 255, 140 },     -- 成功绿
}

--- 绘制科技感面板背景（带发光边框）
local function drawPanelBg(nvg, x, y, w, h, glowColor)
    glowColor = glowColor or UI_CONFIG.accentColor
    
    -- 外发光效果
    local glowSize = 15
    local paint = nvgBoxGradient(nvg, x - glowSize/2, y - glowSize/2, 
        w + glowSize, h + glowSize, UI_CONFIG.cornerRadius + 4, glowSize,
        nvgRGBA(glowColor[1], glowColor[2], glowColor[3], 30),
        nvgRGBA(glowColor[1], glowColor[2], glowColor[3], 0))
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x - glowSize, y - glowSize, w + glowSize * 2, h + glowSize * 2, UI_CONFIG.cornerRadius + 6)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    
    -- 主背景（渐变）
    local bgPaint = nvgLinearGradient(nvg, x, y, x, y + h,
        nvgRGBA(UI_CONFIG.bgColor[1] + 10, UI_CONFIG.bgColor[2] + 15, UI_CONFIG.bgColor[3] + 25, UI_CONFIG.bgColor[4]),
        nvgRGBA(UI_CONFIG.bgColor[1], UI_CONFIG.bgColor[2], UI_CONFIG.bgColor[3], UI_CONFIG.bgColor[4]))
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, UI_CONFIG.cornerRadius)
    nvgFillPaint(nvg, bgPaint)
    nvgFill(nvg)
    
    -- 顶部高光线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x + UI_CONFIG.cornerRadius, y + 1)
    nvgLineTo(nvg, x + w - UI_CONFIG.cornerRadius, y + 1)
    nvgStrokeColor(nvg, nvgRGBA(glowColor[1], glowColor[2], glowColor[3], 60))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
    
    -- 边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, UI_CONFIG.cornerRadius)
    nvgStrokeColor(nvg, nvgRGBA(UI_CONFIG.borderColor[1], UI_CONFIG.borderColor[2], UI_CONFIG.borderColor[3], UI_CONFIG.borderColor[4]))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

--- 绘制科技感进度条
local function drawTechProgressBar(nvg, x, y, w, h, progress, color, bgAlpha)
    bgAlpha = bgAlpha or 80
    progress = math.max(0, math.min(1, progress))
    
    -- 背景槽
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, h / 2)
    nvgFillColor(nvg, nvgRGBA(20, 25, 35, bgAlpha))
    nvgFill(nvg)
    
    -- 进度填充（带渐变）
    if progress > 0 then
        local fillW = w * progress
        local paint = nvgLinearGradient(nvg, x, y, x + fillW, y,
            nvgRGBA(color[1], color[2], color[3], 255),
            nvgRGBA(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7, 255))
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, fillW, h, h / 2)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
        
        -- 高光
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 2, y + 1, fillW - 4, h * 0.35, h / 4)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 40))
        nvgFill(nvg)
    end
    
    -- 边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, h / 2)
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], 80))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

--- 绘制准心
function M.DrawCrosshair()
    local nvg = GameState.nvg
    local cx = GameState.screenWidth / 2
    local cy = GameState.screenHeight / 2
    
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 4)
    nvgFillColor(nvg, nvgRGBA(255, 60, 60, 220))
    nvgFill(nvg)
    
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 6)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 100))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

--- 绘制换弹圆形进度条（准心周围）
function M.DrawReloadCircle()
    if not GameState.isReloading or not GameState.currentWeapon then
        return
    end
    
    local nvg = GameState.nvg
    local cx = GameState.screenWidth / 2
    local cy = GameState.screenHeight / 2
    
    -- 计算进度
    local reloadProgress = 1.0 - (GameState.reloadTimer / GameState.currentWeapon.reloadTime)
    reloadProgress = math.max(0, math.min(1, reloadProgress))
    
    local radius = 40
    local thickness = 6
    
    -- 背景圆环
    nvgBeginPath(nvg)
    nvgArc(nvg, cx, cy, radius, 0, math.pi * 2, NVG_CW)
    nvgStrokeColor(nvg, nvgRGBA(50, 50, 50, 150))
    nvgStrokeWidth(nvg, thickness)
    nvgStroke(nvg)
    
    -- 进度圆弧（从顶部开始，顺时针）
    if reloadProgress > 0 then
        local startAngle = -math.pi / 2  -- 从顶部开始
        local endAngle = startAngle + reloadProgress * math.pi * 2
        
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, cy, radius, startAngle, endAngle, NVG_CW)
        nvgStrokeColor(nvg, nvgRGBA(255, 200, 100, 230))
        nvgStrokeWidth(nvg, thickness)
        nvgLineCap(nvg, NVG_ROUND)
        nvgStroke(nvg)
    end
end

--- 准星击中反馈状态
local crosshairHitTimer = 0
local CROSSHAIR_HIT_DURATION = 0.15

--- 触发准星击中反馈
function M.TriggerCrosshairHit()
    crosshairHitTimer = CROSSHAIR_HIT_DURATION
end

--- 更新准星状态
function M.UpdateCrosshair(dt)
    if crosshairHitTimer > 0 then
        crosshairHitTimer = crosshairHitTimer - dt
    end
end

--- 绘制枪口准心（3A科技风格）
function M.DrawGunCrosshair()
    if not GameState.gunAimVisible or not GameState.gunAimScreenPos then
        return
    end
    
    local nvg = GameState.nvg
    local cx = GameState.gunAimScreenPos.x
    local cy = GameState.gunAimScreenPos.y
    
    if cx < 0 or cx > GameState.screenWidth or cy < 0 or cy > GameState.screenHeight then
        return
    end
    
    -- 动态参数
    local size = 18
    local thickness = 2.5
    local baseGap = 8
    local gap = baseGap + GameState.crosshairSpread
    
    -- 击中反馈：颜色和大小变化
    local isHit = crosshairHitTimer > 0
    local hitProgress = isHit and (crosshairHitTimer / CROSSHAIR_HIT_DURATION) or 0
    
    -- 基础颜色
    local r, g, b = 80, 200, 255  -- 科技蓝
    if isHit then
        -- 击中时变为亮红色
        r = 255
        g = math.floor(80 + 120 * (1 - hitProgress))
        b = math.floor(80 * (1 - hitProgress))
    end
    
    -- 击中时准星收缩
    local hitScale = 1.0 - hitProgress * 0.3
    local currentGap = gap * hitScale
    local currentSize = size * (1.0 + hitProgress * 0.2)
    
    -- ========== 主十字线 ==========
    nvgStrokeWidth(nvg, thickness)
    nvgStrokeColor(nvg, nvgRGBA(r, g, b, 255))
    nvgLineCap(nvg, NVG_ROUND)
    
    -- 上
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - currentGap - currentSize)
    nvgLineTo(nvg, cx, cy - currentGap)
    nvgStroke(nvg)
    -- 下
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy + currentGap)
    nvgLineTo(nvg, cx, cy + currentGap + currentSize)
    nvgStroke(nvg)
    -- 左
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - currentGap - currentSize, cy)
    nvgLineTo(nvg, cx - currentGap, cy)
    nvgStroke(nvg)
    -- 右
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + currentGap, cy)
    nvgLineTo(nvg, cx + currentGap + currentSize, cy)
    nvgStroke(nvg)
    
    -- ========== 斜角装饰线（科幻风格）==========
    local cornerOffset = currentGap * 0.7
    local cornerLen = 6
    nvgStrokeWidth(nvg, 1.5)
    nvgStrokeColor(nvg, nvgRGBA(r, g, b, 150))
    
    -- 四个斜角
    local corners = {
        { cx - cornerOffset, cy - cornerOffset, -1, -1 },
        { cx + cornerOffset, cy - cornerOffset,  1, -1 },
        { cx - cornerOffset, cy + cornerOffset, -1,  1 },
        { cx + cornerOffset, cy + cornerOffset,  1,  1 },
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, c[1], c[2])
        nvgLineTo(nvg, c[1] + c[3] * cornerLen, c[2] + c[4] * cornerLen)
        nvgStroke(nvg)
    end
    
    -- ========== 中心点 ==========
    -- 中心亮点
    local dotRadius = isHit and 3.5 or 2.5
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, dotRadius)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgFill(nvg)
    
    -- 中心小圆环
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 5)
    nvgStrokeColor(nvg, nvgRGBA(r, g, b, 180))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

--- 绘制狙击镜瞄准UI（黑色遮罩+圆形瞄准镜）
function M.DrawSniperScope()
    -- 检查是否激活狙击镜
    if not GameState.scopeActive then return end
    
    local nvg = GameState.nvg
    local screenW = GameState.screenWidth
    local screenH = GameState.screenHeight
    local cx = screenW / 2
    local cy = screenH / 2
    
    -- 瞄准镜半径（基于屏幕短边）
    local scopeRadius = math.min(screenW, screenH) * 0.4
    
    -- ========== 1. 绘制黑色遮罩（四个角落） ==========
    -- 使用路径剪切：画整个屏幕，挖掉中心圆
    nvgBeginPath(nvg)
    -- 外框（整个屏幕）
    nvgRect(nvg, 0, 0, screenW, screenH)
    -- 内圆（逆时针绘制以形成孔洞）
    nvgPathWinding(nvg, NVG_HOLE)
    nvgCircle(nvg, cx, cy, scopeRadius)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
    nvgFill(nvg)
    
    -- ========== 2. 瞄准镜边框 ==========
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, scopeRadius)
    nvgStrokeWidth(nvg, 4)
    nvgStrokeColor(nvg, nvgRGBA(30, 30, 35, 255))
    nvgStroke(nvg)
    
    -- 内边框
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, scopeRadius - 3)
    nvgStrokeWidth(nvg, 1)
    nvgStrokeColor(nvg, nvgRGBA(60, 60, 70, 255))
    nvgStroke(nvg)
    
    -- ========== 3. 十字准星 ==========
    local crossLen = scopeRadius * 0.8
    local crossGap = 15  -- 中心留空
    local crossWidth = 1.5
    
    nvgStrokeWidth(nvg, crossWidth)
    nvgStrokeColor(nvg, nvgRGBA(20, 20, 20, 255))
    
    -- 水平线（左）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - crossLen, cy)
    nvgLineTo(nvg, cx - crossGap, cy)
    nvgStroke(nvg)
    
    -- 水平线（右）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + crossGap, cy)
    nvgLineTo(nvg, cx + crossLen, cy)
    nvgStroke(nvg)
    
    -- 垂直线（上）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - crossLen)
    nvgLineTo(nvg, cx, cy - crossGap)
    nvgStroke(nvg)
    
    -- 垂直线（下）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy + crossGap)
    nvgLineTo(nvg, cx, cy + crossLen)
    nvgStroke(nvg)
    
    -- ========== 4. 刻度线 ==========
    local tickSpacing = scopeRadius * 0.15
    local tickLen = 8
    nvgStrokeWidth(nvg, 1)
    
    -- 水平刻度
    for i = 1, 4 do
        local offset = i * tickSpacing
        -- 左侧刻度
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - crossGap - offset, cy - tickLen / 2)
        nvgLineTo(nvg, cx - crossGap - offset, cy + tickLen / 2)
        nvgStroke(nvg)
        -- 右侧刻度
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx + crossGap + offset, cy - tickLen / 2)
        nvgLineTo(nvg, cx + crossGap + offset, cy + tickLen / 2)
        nvgStroke(nvg)
    end
    
    -- 垂直刻度（下方，用于测距）
    for i = 1, 4 do
        local offset = i * tickSpacing
        local tLen = tickLen * (1 - i * 0.15)  -- 越远刻度越短
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - tLen / 2, cy + crossGap + offset)
        nvgLineTo(nvg, cx + tLen / 2, cy + crossGap + offset)
        nvgStroke(nvg)
    end
    
    -- ========== 5. 中心瞄准点 ==========
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 2)
    nvgFillColor(nvg, nvgRGBA(255, 50, 50, 255))
    nvgFill(nvg)
    
    -- ========== 6. 镜片效果（轻微暗角） ==========
    local innerRadius = scopeRadius * 0.7
    local gradient = nvgRadialGradient(nvg, cx, cy, innerRadius, scopeRadius,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 60))
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, scopeRadius)
    nvgFillPaint(nvg, gradient)
    nvgFill(nvg)
end

--- 绘制左上角面板（武器信息 + 血条 - 3A科技风格）
function M.DrawLeftPanel()
    local nvg = GameState.nvg
    local pad = UI_CONFIG.padding
    
    -- 面板尺寸
    local panelX = 15
    local panelY = 15
    local panelW = 240
    local panelH = 140
    
    -- 绘制背景
    drawPanelBg(nvg, panelX, panelY, panelW, panelH)
    
    nvgFontFace(nvg, "sans")
    
    local contentX = panelX + pad
    local contentY = panelY + pad
    
    -- 武器名称（带图标效果）
    nvgFontSize(nvg, 14)
    nvgFillColor(nvg, nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 180))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgText(nvg, contentX, contentY, "◆ 装备武器")
    
    contentY = contentY + 18
    nvgFontSize(nvg, 20)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    local weaponName = GameState.currentWeapon and GameState.currentWeapon.nameZh or "无武器"
    nvgText(nvg, contentX, contentY, weaponName)
    
    -- 弹药数量（大号数字 + 发光效果）
    contentY = contentY + 28
    local ammoColor = UI_CONFIG.accentColor
    if GameState.isReloading then
        ammoColor = UI_CONFIG.warningColor
    elseif GameState.currentAmmo <= 5 then
        ammoColor = UI_CONFIG.dangerColor
    end
    
    -- 弹药数字发光
    nvgFontSize(nvg, 32)
    nvgFillColor(nvg, nvgRGBA(ammoColor[1], ammoColor[2], ammoColor[3], 60))
    local ammoNum = GameState.isReloading and "..." or tostring(GameState.currentAmmo)
    nvgText(nvg, contentX + 1, contentY + 1, ammoNum)
    
    nvgFillColor(nvg, nvgRGBA(ammoColor[1], ammoColor[2], ammoColor[3], 255))
    nvgText(nvg, contentX, contentY, ammoNum)
    
    -- 备弹（较小）
    local ammoWidth = nvgTextBounds(nvg, 0, 0, ammoNum)
    nvgFontSize(nvg, 16)
    nvgFillColor(nvg, nvgRGBA(150, 160, 180, 200))
    nvgText(nvg, contentX + ammoWidth + 8, contentY + 12, "/ " .. GameState.reserveAmmo)
    
    -- 装弹进度条
    contentY = contentY + 38
    if GameState.isReloading and GameState.currentWeapon then
        local reloadProgress = 1.0 - (GameState.reloadTimer / GameState.currentWeapon.reloadTime)
        drawTechProgressBar(nvg, contentX, contentY, panelW - pad * 2, 6, reloadProgress, UI_CONFIG.warningColor)
        contentY = contentY + 12
    end
    
    -- 手榴弹图标
    nvgFontSize(nvg, 14)
    nvgFillColor(nvg, nvgRGBA(200, 180, 120, 255))
    nvgText(nvg, contentX, contentY, "💣 × " .. GameState.grenadeCount)
    
    -- 血条
    contentY = contentY + 22
    local healthBarWidth = panelW - pad * 2
    local healthBarHeight = 14
    
    local healthPercent = GameState.playerHealth / CONFIG.MaxHealth
    local healthColor
    if healthPercent > 0.5 then
        healthColor = UI_CONFIG.successColor
    elseif healthPercent > 0.25 then
        healthColor = UI_CONFIG.warningColor
    else
        healthColor = UI_CONFIG.dangerColor
    end
    
    drawTechProgressBar(nvg, contentX, contentY, healthBarWidth, healthBarHeight, healthPercent, healthColor)
    
    -- 血量数字（叠加在进度条上）
    nvgFontSize(nvg, 11)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, contentX + healthBarWidth / 2, contentY + healthBarHeight / 2, 
            math.floor(GameState.playerHealth) .. " / " .. CONFIG.MaxHealth)
end

--- 绘制右下角按键提示
function M.DrawKeyHints()
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    local pad = UI_CONFIG.padding
    
    -- 按键提示内容
    local hints = {
        { key = "WASD",  desc = "移动" },
        { key = "鼠标",  desc = "视角" },
        { key = "左键",  desc = "射击" },
        { key = "右键",  desc = "瞄准" },
        { key = "空格",  desc = "跳跃" },
        { key = "R",     desc = "换弹" },
        { key = "V",     desc = "补充弹药" },
        { key = "E",     desc = "手榴弹" },
        { key = "Q",     desc = "换手" },
        { key = "1-3",   desc = "切换武器" },
    }
    
    -- 计算面板尺寸
    local lineHeight = 18
    local panelW = 130
    local panelH = #hints * lineHeight + pad * 2
    local panelX = w - 15 - panelW
    local panelY = h - 15 - panelH
    
    -- 绘制背景
    drawPanelBg(nvg, panelX, panelY, panelW, panelH)
    
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 13)
    
    local contentY = panelY + pad
    
    for _, hint in ipairs(hints) do
        -- 按键
        nvgFillColor(nvg, nvgRGBA(255, 220, 100, 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(nvg, panelX + pad, contentY, hint.key)
        
        -- 描述
        nvgFillColor(nvg, nvgRGBA(180, 180, 180, 255))
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(nvg, panelX + panelW - pad, contentY, hint.desc)
        
        contentY = contentY + lineHeight
    end
end

--- 绘制瞄准指示器
function M.DrawAimIndicator()
    if not Weapon.IsAiming() and GameState.aimTransition <= 0 then
        return
    end
    
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 瞄准时显示 ADS 指示
    local alpha = math.floor(GameState.aimTransition * 150)
    if alpha > 0 then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 14)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgText(nvg, w / 2, h - 80, "ADS")
    end
end

--- 绘制死亡界面
function M.DrawDeathScreen()
    if not GameState.isDead then return end
    
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 半透明红色覆盖
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, w, h)
    nvgFillColor(nvg, nvgRGBA(80, 0, 0, 150))
    nvgFill(nvg)
    
    -- 死亡面板背景
    local panelW = 300
    local panelH = 120
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2
    
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvg, nvgRGBA(30, 10, 10, 220))
    nvgFill(nvg)
    
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 12)
    nvgStrokeColor(nvg, nvgRGBA(150, 50, 50, 200))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    -- 死亡文字
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 48)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 80, 80, 255))
    nvgText(nvg, w / 2, h / 2 - 15, "你死了")
    
    nvgFontSize(nvg, 18)
    nvgFillColor(nvg, nvgRGBA(200, 200, 200, 255))
    nvgText(nvg, w / 2, h / 2 + 30, "按 [空格] 重生")
end

--- 渲染主函数
--- 更新受伤滤镜（淡出效果）
function M.UpdateDamageFlash(dt)
    if GameState.damageFlashAlpha > 0 then
        -- 淡出速度：约0.5秒完全消失
        local fadeSpeed = 1.5
        GameState.damageFlashAlpha = math.max(0, GameState.damageFlashAlpha - fadeSpeed * dt)
    end
end

--- 绘制受伤红色滤镜
function M.DrawDamageFlash()
    if GameState.damageFlashAlpha <= 0 then return end
    
    local vg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 绘制全屏红色半透明遮罩（边缘更红，中心较淡）
    local alpha = GameState.damageFlashAlpha
    
    -- 使用径向渐变：中心透明，边缘红色
    local centerX, centerY = w / 2, h / 2
    local innerRadius = math.min(w, h) * 0.3
    local outerRadius = math.max(w, h) * 0.8
    
    local innerColor = nvgRGBA(255, 0, 0, 0)
    local outerColor = nvgRGBA(180, 0, 0, math.floor(255 * alpha))
    
    local paint = nvgRadialGradient(vg, centerX, centerY, innerRadius, outerRadius, innerColor, outerColor)
    
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制子弹时间视觉效果（屏幕边缘虚化）
function M.DrawBulletTimeEffect()
    if not GameState.bulletTimeActive then return end
    
    local vg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 计算效果强度（基于缓入缓出）
    local timer = GameState.bulletTimeTimer
    local duration = GameState.bulletTimeDuration
    local easeIn = GameState.bulletTimeEaseIn
    local easeOut = GameState.bulletTimeEaseOut
    
    local intensity = 1.0
    if timer < easeIn then
        -- 缓入阶段
        local t = timer / easeIn
        intensity = t * t * (3 - 2 * t)  -- smoothstep
    elseif timer > duration - easeOut then
        -- 缓出阶段
        local t = (duration - timer) / easeOut
        intensity = t * t * (3 - 2 * t)  -- smoothstep
    end
    
    -- 使用冷色调（浅蓝色）表示时间减速
    local centerX, centerY = w / 2, h / 2
    local innerRadius = math.min(w, h) * 0.75
    local outerRadius = math.max(w, h) * 0.95
    
    -- 边缘虚化颜色（接近白色的浅蓝色）
    local alpha = math.floor(255 * intensity)
    local innerColor = nvgRGBA(220, 235, 255, 0)
    local outerColor = nvgRGBA(200, 220, 255, alpha)
    
    local paint = nvgRadialGradient(vg, centerX, centerY, innerRadius, outerRadius, innerColor, outerColor)
    
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    
    -- 添加微弱的扫描线效果增强科幻感
    nvgSave(vg)
    nvgGlobalAlpha(vg, 0.03 * intensity)
    for y = 0, h, 4 do
        nvgBeginPath(vg)
        nvgRect(vg, 0, y, w, 1)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 255))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

-- 菜单按钮状态
local menuButtonHovered = false
local menuButtonPressed = false
local playAgainButtonHovered = false  -- 再来一局按钮
local returnMenuButtonHovered = false  -- 返回主菜单按钮

-- 武器圆盘选择器状态
local weaponWheelOpen = false          -- 圆盘是否展开
local weaponWheelAnimation = 0         -- 展开动画进度 (0-1)
local weaponWheelHoveredIndex = 0      -- 当前悬停的武器索引 (1-6)
local weaponButtonHovered = false      -- 武器按钮是否悬停
local weaponWheelIcon = nil            -- 武器圆盘图标句柄

-- 分数弹出提示队列
local scorePopups = {}                 -- { { score, x, y, timer, alpha } }
local POPUP_DURATION = 1.2             -- 弹出持续时间（秒）
local POPUP_RISE_SPEED = 80            -- 上升速度（像素/秒）

--- 绘制主菜单
function M.DrawMainMenu()
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 半透明背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, w, h)
    nvgFillColor(nvg, nvgRGBA(10, 15, 25, 200))
    nvgFill(nvg)
    
    -- 标题
    nvgFontSize(nvg, 64)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, w/2, h * 0.3, "射击训练场")
    
    -- 副标题
    nvgFontSize(nvg, 24)
    nvgFillColor(nvg, nvgRGBA(180, 180, 200, 200))
    nvgText(nvg, w/2, h * 0.3 + 50, "60秒限时挑战")
    
    -- 开始按钮
    local btnW = 200
    local btnH = 60
    local btnX = w/2 - btnW/2
    local btnY = h * 0.7
    
    -- 按钮背景
    local btnColor = menuButtonHovered and nvgRGBA(60, 120, 200, 255) or nvgRGBA(40, 80, 160, 255)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btnX, btnY, btnW, btnH, 12)
    nvgFillColor(nvg, btnColor)
    nvgFill(nvg)
    
    -- 按钮边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btnX, btnY, btnW, btnH, 12)
    nvgStrokeColor(nvg, nvgRGBA(100, 150, 220, 255))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    -- 按钮文字
    nvgFontSize(nvg, 28)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, w/2, btnY + btnH/2, "开始游戏")
    
    -- 提示文字
    nvgFontSize(nvg, 18)
    nvgFillColor(nvg, nvgRGBA(150, 150, 170, 180))
    nvgText(nvg, w/2, h * 0.85, "点击按钮或按 空格键 开始")
end

--- 绘制顶部状态栏（3A科技风格HUD）
function M.DrawTimer()
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 自适应尺寸
    local baseWidth = 1920
    local scale = math.max(0.6, math.min(1.2, w / baseWidth))
    
    local notchWidth = math.floor(320 * scale)
    local notchHeight = math.floor(48 * scale)
    local notchRadius = math.floor(8 * scale)
    
    notchWidth = math.max(240, math.min(450, notchWidth))
    notchHeight = math.max(38, math.min(60, notchHeight))
    
    local notchX = w/2 - notchWidth/2
    local notchY = 0
    
    -- 底部发光效果
    local glowPaint = nvgBoxGradient(nvg, notchX, notchY + notchHeight - 5, 
        notchWidth, 20, 10, 15,
        nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 40),
        nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, notchX - 10, notchY + notchHeight - 5, notchWidth + 20, 25)
    nvgFillPaint(nvg, glowPaint)
    nvgFill(nvg)
    
    -- 刘海背景（渐变）
    local bgPaint = nvgLinearGradient(nvg, notchX, notchY, notchX, notchY + notchHeight,
        nvgRGBA(15, 22, 35, 240),
        nvgRGBA(8, 12, 22, 250))
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, notchX, notchY)
    nvgLineTo(nvg, notchX + notchWidth, notchY)
    nvgLineTo(nvg, notchX + notchWidth, notchY + notchHeight - notchRadius)
    nvgArcTo(nvg, notchX + notchWidth, notchY + notchHeight, notchX + notchWidth - notchRadius, notchY + notchHeight, notchRadius)
    nvgLineTo(nvg, notchX + notchRadius, notchY + notchHeight)
    nvgArcTo(nvg, notchX, notchY + notchHeight, notchX, notchY + notchHeight - notchRadius, notchRadius)
    nvgClosePath(nvg)
    nvgFillPaint(nvg, bgPaint)
    nvgFill(nvg)
    
    -- 科技感边框
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, notchX, notchY)
    nvgLineTo(nvg, notchX, notchY + notchHeight - notchRadius)
    nvgArcTo(nvg, notchX, notchY + notchHeight, notchX + notchRadius, notchY + notchHeight, notchRadius)
    nvgLineTo(nvg, notchX + notchWidth - notchRadius, notchY + notchHeight)
    nvgArcTo(nvg, notchX + notchWidth, notchY + notchHeight, notchX + notchWidth, notchY + notchHeight - notchRadius, notchRadius)
    nvgLineTo(nvg, notchX + notchWidth, notchY)
    nvgStrokeColor(nvg, nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 100))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
    
    -- 底部高光线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, notchX + notchRadius + 20, notchY + notchHeight - 1)
    nvgLineTo(nvg, notchX + notchWidth - notchRadius - 20, notchY + notchHeight - 1)
    nvgStrokeColor(nvg, nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 150))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    nvgFontFace(nvg, "sans")
    local centerY = notchHeight / 2 + 2
    local sectionWidth = notchWidth / 3
    
    -- 字体大小
    local labelSize = math.max(10, math.floor(11 * scale))
    local valueSize = math.max(14, math.floor(17 * scale))
    local timerSize = math.max(20, math.floor(26 * scale))
    
    local labelOffset = math.floor(9 * scale)
    local valueOffset = math.floor(8 * scale)
    
    -- ========== 左侧：分数（带图标） ==========
    local scoreX = notchX + sectionWidth / 2
    nvgFontSize(nvg, labelSize)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(100, 140, 180, 200))
    nvgText(nvg, scoreX, centerY - labelOffset, "◇ SCORE")
    
    -- 分数发光效果
    nvgFontSize(nvg, valueSize)
    nvgFillColor(nvg, nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 80))
    nvgText(nvg, scoreX + 1, centerY + valueOffset + 1, tostring(GameState.score))
    nvgFillColor(nvg, nvgRGBA(UI_CONFIG.accentColor[1], UI_CONFIG.accentColor[2], UI_CONFIG.accentColor[3], 255))
    nvgText(nvg, scoreX, centerY + valueOffset, tostring(GameState.score))
    
    -- ========== 中间：倒计时（主焦点） ==========
    local remaining = math.max(0, GameState.gameDuration - GameState.gameTimer)
    local minutes = math.floor(remaining / 60)
    local seconds = math.floor(remaining % 60)
    local timeStr = string.format("%d:%02d", minutes, seconds)
    
    -- 时间颜色和脉冲效果
    local tr, tg, tb = 255, 255, 255
    local pulse = 1.0
    if remaining <= 10 then
        tr, tg, tb = 255, 80, 80
        -- 闪烁效果
        pulse = 0.7 + 0.3 * math.abs(math.sin(remaining * 3))
    elseif remaining <= 30 then
        tr, tg, tb = 255, 200, 100
    end
    
    nvgFontSize(nvg, timerSize)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 发光
    nvgFillColor(nvg, nvgRGBA(tr, tg, tb, math.floor(60 * pulse)))
    nvgText(nvg, w/2 + 1, centerY + 1, timeStr)
    nvgFillColor(nvg, nvgRGBA(tr, tg, tb, math.floor(255 * pulse)))
    nvgText(nvg, w/2, centerY, timeStr)
    
    -- ========== 右侧：命中率 ==========
    local hitRate = 0
    if GameState.totalShots > 0 then
        hitRate = (GameState.shotsHit / GameState.totalShots) * 100
    end
    
    local hitX = notchX + notchWidth - sectionWidth / 2
    nvgFontSize(nvg, labelSize)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(100, 140, 180, 200))
    nvgText(nvg, hitX, centerY - labelOffset, "◇ ACCURACY")
    
    -- 命中率颜色
    local hitColor = hitRate >= 50 and UI_CONFIG.successColor or UI_CONFIG.warningColor
    nvgFontSize(nvg, valueSize)
    nvgFillColor(nvg, nvgRGBA(hitColor[1], hitColor[2], hitColor[3], 80))
    nvgText(nvg, hitX + 1, centerY + valueOffset + 1, string.format("%.0f%%", hitRate))
    nvgFillColor(nvg, nvgRGBA(hitColor[1], hitColor[2], hitColor[3], 255))
    nvgText(nvg, hitX, centerY + valueOffset, string.format("%.0f%%", hitRate))
end

--- 武器名称映射（用于圆盘显示）
local WEAPON_NAMES = {
    -- 旧武器（兼容）
    pistol = "手枪",
    rifle = "步枪",
    shotgun = "霰弹枪",
    ak47 = "机枪",
    -- 新prefab武器
    g17 = "G17",
    ak74 = "AK74",
    m4 = "M4",
    mp5 = "MP5",
    sks = "SKS",
    sawed = "短管",
}

--- 武器颜色映射
local WEAPON_COLORS = {
    -- 旧武器（兼容）
    pistol = { 120, 120, 140 },
    rifle = { 80, 130, 180 },
    shotgun = { 160, 100, 60 },
    ak47 = { 100, 160, 80 },
    -- 新prefab武器
    g17 = { 100, 100, 120 },     -- 深灰蓝（手枪）
    ak74 = { 180, 120, 60 },     -- 橙棕（AK系列）
    m4 = { 60, 140, 180 },       -- 蓝色（现代步枪）
    mp5 = { 80, 80, 100 },       -- 深灰（冲锋枪）
    sks = { 140, 100, 60 },      -- 木棕（经典步枪）
    sawed = { 160, 80, 80 },     -- 暗红（霰弹枪）
}

--- 更新武器圆盘动画
function M.UpdateWeaponWheel(dt)
    local animSpeed = 8.0
    if weaponWheelOpen then
        weaponWheelAnimation = math.min(1, weaponWheelAnimation + dt * animSpeed)
    else
        weaponWheelAnimation = math.max(0, weaponWheelAnimation - dt * animSpeed)
    end
end

--- 绘制武器切换按钮和圆盘
function M.DrawWeaponWheel()
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 自适应尺寸（与 VirtualControls 中的 Q 按钮保持一致）
    local minDim = math.min(w, h)
    local baseBtnRadius = math.max(45, minDim * 0.06)  -- 与 main.lua 中的 btnRadius 一致
    local btnRadius = baseBtnRadius * 0.8              -- 与 Q 按钮大小一致
    local margin = math.max(25, minDim * 0.03)
    local spacing = math.max(15, minDim * 0.02)
    
    -- 武器按钮位置（左上角，Q按钮下方）
    -- Q按钮位置：x = margin + baseBtnRadius, y = margin + 120 + baseBtnRadius
    -- Q按钮半径：baseBtnRadius * 0.8
    local qBtnRadius = baseBtnRadius * 0.8
    local qBtnY = margin + 120 + baseBtnRadius
    local btnX = margin + baseBtnRadius
    -- Q按钮底部 + 间距 + 武器按钮半径 + 20像素下移
    local btnY = qBtnY + qBtnRadius + spacing * 2 + btnRadius + 20
    
    -- 获取鼠标位置
    local mx, my = input.mousePosition.x, input.mousePosition.y
    
    -- 检查按钮悬停
    local distToBtn = math.sqrt((mx - btnX)^2 + (my - btnY)^2)
    weaponButtonHovered = distToBtn <= btnRadius
    
    -- 绘制武器按钮
    local btnBgColor = weaponButtonHovered and nvgRGBA(60, 80, 120, 240) or nvgRGBA(30, 40, 60, 220)
    nvgBeginPath(nvg)
    nvgCircle(nvg, btnX, btnY, btnRadius)
    nvgFillColor(nvg, btnBgColor)
    nvgFill(nvg)
    
    -- 按钮边框
    nvgBeginPath(nvg)
    nvgCircle(nvg, btnX, btnY, btnRadius)
    nvgStrokeColor(nvg, nvgRGBA(100, 130, 180, 200))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    -- 加载武器图标（只加载一次）
    if not weaponWheelIcon and nvg then
        weaponWheelIcon = nvgCreateImage(nvg, "assets/icon_weapon_wheel_20260202074921.png", 0)
    end
    
    -- 绘制武器图标
    if weaponWheelIcon and weaponWheelIcon > 0 then
        local iconSize = btnRadius * 1.4
        local iconX = btnX - iconSize / 2
        local iconY = btnY - iconSize / 2
        local imgPaint = nvgImagePattern(nvg, iconX, iconY, iconSize, iconSize, 0, weaponWheelIcon, 0.9)
        nvgBeginPath(nvg)
        nvgRect(nvg, iconX, iconY, iconSize, iconSize)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        -- 备用：使用 emoji
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, btnRadius * 0.6)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, btnX, btnY, "🔫")
    end
    
    -- 绘制 T 快捷键提示（按钮右下角）
    if not isTouchMode then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 背景圆
        local keyX = btnX + btnRadius * 0.6
        local keyY = btnY + btnRadius * 0.6
        nvgBeginPath(nvg)
        nvgCircle(nvg, keyX, keyY, 10)
        nvgFillColor(nvg, nvgRGBA(40, 50, 70, 220))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, keyX, keyY, 10)
        nvgStrokeColor(nvg, nvgRGBA(100, 140, 200, 200))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
        -- T 文字
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, keyX, keyY, "T")
    end
    
    -- 如果圆盘展开，绘制圆盘（在屏幕中心）
    if weaponWheelAnimation > 0.01 then
        -- 计算 scale 用于圆盘绘制
        local baseWidth = 1920
        local uiScale = math.max(0.6, math.min(1.2, w / baseWidth))
        -- 圆盘显示在屏幕中心
        local centerX = w / 2
        local centerY = h / 2
        M.DrawWeaponWheelExpanded(centerX, centerY, uiScale, mx, my)
    end
end

--- 绘制展开的武器圆盘
function M.DrawWeaponWheelExpanded(centerX, centerY, scale, mx, my)
    local nvg = GameState.nvg
    local WEAPON_ORDER = Config.WEAPON_ORDER
    
    local numWeapons = #WEAPON_ORDER
    local wheelRadius = math.floor(160 * scale) * weaponWheelAnimation   -- 加大圆盘半径
    local itemRadius = math.floor(55 * scale) * weaponWheelAnimation     -- 加大武器按钮
    
    -- 半透明背景圆
    nvgBeginPath(nvg)
    nvgCircle(nvg, centerX, centerY, wheelRadius + itemRadius + 10)
    nvgFillColor(nvg, nvgRGBA(10, 15, 25, math.floor(180 * weaponWheelAnimation)))
    nvgFill(nvg)
    
    -- 重置悬停索引
    weaponWheelHoveredIndex = 0
    
    -- 绘制每个武器选项
    for i, weaponId in ipairs(WEAPON_ORDER) do
        -- 计算位置（圆形分布，从顶部开始）
        local angle = (i - 1) * (2 * math.pi / numWeapons) - math.pi / 2
        local itemX = centerX + math.cos(angle) * wheelRadius
        local itemY = centerY + math.sin(angle) * wheelRadius
        
        -- 检查悬停
        local distToItem = math.sqrt((mx - itemX)^2 + (my - itemY)^2)
        local isHovered = distToItem <= itemRadius
        local isCurrentWeapon = weaponId == GameState.currentWeaponId
        
        if isHovered then
            weaponWheelHoveredIndex = i
        end
        
        -- 获取武器颜色
        local wc = WEAPON_COLORS[weaponId] or { 100, 100, 100 }
        
        -- 绘制武器项背景
        local bgAlpha = isHovered and 255 or (isCurrentWeapon and 220 or 180)
        local bgBright = isHovered and 1.3 or (isCurrentWeapon and 1.1 or 1.0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, itemX, itemY, itemRadius)
        nvgFillColor(nvg, nvgRGBA(
            math.floor(wc[1] * bgBright),
            math.floor(wc[2] * bgBright),
            math.floor(wc[3] * bgBright),
            bgAlpha
        ))
        nvgFill(nvg)
        
        -- 当前武器边框高亮
        if isCurrentWeapon then
            nvgBeginPath(nvg)
            nvgCircle(nvg, itemX, itemY, itemRadius)
            nvgStrokeColor(nvg, nvgRGBA(255, 220, 100, 255))
            nvgStrokeWidth(nvg, 3)
            nvgStroke(nvg)
        elseif isHovered then
            nvgBeginPath(nvg)
            nvgCircle(nvg, itemX, itemY, itemRadius)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
        end
        
        -- 武器序号
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, math.floor(20 * scale * weaponWheelAnimation))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
        nvgText(nvg, itemX, itemY - 12 * scale, tostring(i))
        
        -- 武器名称
        local weaponName = WEAPON_NAMES[weaponId] or weaponId
        nvgFontSize(nvg, math.floor(16 * scale * weaponWheelAnimation))
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, itemX, itemY + 14 * scale, weaponName)
    end
    
    -- 中心提示
    if weaponWheelHoveredIndex > 0 then
        local hoveredId = WEAPON_ORDER[weaponWheelHoveredIndex]
        local hoveredName = WEAPON_NAMES[hoveredId] or hoveredId
        nvgFontSize(nvg, math.floor(22 * scale))
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg, centerX, centerY, "选择: " .. hoveredName)
    else
        -- 没有悬停时显示提示
        nvgFontSize(nvg, math.floor(18 * scale))
        nvgFillColor(nvg, nvgRGBA(180, 180, 200, 180))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg, centerX, centerY, "点击选择武器")
    end
end

--- 检查武器圆盘交互
---@return string|nil 选中的武器ID，或nil
function M.CheckWeaponWheelInput()
    local WEAPON_ORDER = Config.WEAPON_ORDER
    
    -- 检查按钮点击（切换圆盘开关）
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        if weaponButtonHovered and not weaponWheelOpen then
            -- 点击按钮打开圆盘
            weaponWheelOpen = true
            return nil
        elseif weaponWheelOpen then
            -- 圆盘已打开，检查选择
            if weaponWheelHoveredIndex > 0 then
                local selectedId = WEAPON_ORDER[weaponWheelHoveredIndex]
                weaponWheelOpen = false
                return selectedId
            else
                -- 点击空白处关闭
                weaponWheelOpen = false
                return nil
            end
        end
    end
    
    -- 按 ESC 关闭圆盘
    if weaponWheelOpen and input:GetKeyPress(KEY_ESCAPE) then
        weaponWheelOpen = false
    end
    
    return nil
end

--- 圆盘是否展开（用于阻止其他输入）
function M.IsWeaponWheelOpen()
    return weaponWheelOpen
end

--- 切换武器圆盘显示
function M.ToggleWeaponWheel()
    weaponWheelOpen = not weaponWheelOpen
end

-- ============================================================================
-- 分数弹出提示系统
-- ============================================================================

--- 显示分数弹出提示
---@param score number 获得的分数
---@param screenX number|nil 屏幕X坐标（可选，默认屏幕中心偏上）
---@param screenY number|nil 屏幕Y坐标（可选，默认屏幕中心偏上）
function M.ShowScorePopup(score, screenX, screenY)
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 默认位置：屏幕中心偏上
    local x = screenX or w / 2
    local y = screenY or h * 0.35
    
    -- 添加随机偏移，避免多个弹出重叠
    x = x + (math.random() - 0.5) * 60
    y = y + (math.random() - 0.5) * 30
    
    table.insert(scorePopups, {
        score = score,
        x = x,
        y = y,
        timer = 0,
        alpha = 1.0,
    })
end

--- 更新分数弹出提示
function M.UpdateScorePopups(dt)
    -- 逆序遍历，方便删除
    for i = #scorePopups, 1, -1 do
        local popup = scorePopups[i]
        popup.timer = popup.timer + dt
        
        -- 上升动画
        popup.y = popup.y - POPUP_RISE_SPEED * dt
        
        -- 淡出（后半段开始淡出）
        if popup.timer > POPUP_DURATION * 0.5 then
            local fadeProgress = (popup.timer - POPUP_DURATION * 0.5) / (POPUP_DURATION * 0.5)
            popup.alpha = 1.0 - fadeProgress
        end
        
        -- 超时删除
        if popup.timer >= POPUP_DURATION then
            table.remove(scorePopups, i)
        end
    end
end

--- 绘制分数弹出提示
function M.DrawScorePopups()
    local nvg = GameState.nvg
    if not nvg then return end
    
    nvgFontFace(nvg, "sans")
    
    for _, popup in ipairs(scorePopups) do
        local alpha = math.floor(popup.alpha * 255)
        if alpha <= 0 then goto continue end
        
        -- 缩放动画：开始时放大，然后缩小到正常大小
        local scale = 1.0
        if popup.timer < 0.15 then
            -- 弹出放大效果
            local t = popup.timer / 0.15
            scale = 1.0 + 0.3 * (1 - t * t)
        end
        
        local fontSize = math.floor(28 * scale)
        local text = "+" .. tostring(popup.score)
        
        nvgFontSize(nvg, fontSize)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        
        -- 阴影
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.5)))
        nvgText(nvg, popup.x + 2, popup.y + 2, text)
        
        -- 主文字（金黄色）
        nvgFillColor(nvg, nvgRGBA(255, 220, 80, alpha))
        nvgText(nvg, popup.x, popup.y, text)
        
        ::continue::
    end
end

--- 绘制游戏结束界面
function M.DrawGameOver()
    local nvg = GameState.nvg
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 半透明背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, w, h)
    nvgFillColor(nvg, nvgRGBA(10, 15, 25, 220))
    nvgFill(nvg)
    
    -- 标题
    nvgFontSize(nvg, 56)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 200, 50, 255))
    nvgText(nvg, w/2, h * 0.25, "游戏结束")
    
    -- 统计面板
    local panelW = 320
    local panelH = 200
    local panelX = w/2 - panelW/2
    local panelY = h * 0.35
    
    -- 面板背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvg, nvgRGBA(30, 35, 50, 240))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 12)
    nvgStrokeColor(nvg, nvgRGBA(80, 100, 140, 200))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    -- 统计信息
    local lineHeight = 40
    local startY = panelY + 35
    
    nvgFontSize(nvg, 24)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    
    -- 得分
    nvgFillColor(nvg, nvgRGBA(180, 180, 200, 255))
    nvgText(nvg, panelX + 30, startY, "得分:")
    nvgFillColor(nvg, nvgRGBA(100, 200, 255, 255))
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, panelX + panelW - 30, startY, tostring(GameState.score))
    
    -- 击中靶子数
    startY = startY + lineHeight
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(180, 180, 200, 255))
    nvgText(nvg, panelX + 30, startY, "击中靶子:")
    nvgFillColor(nvg, nvgRGBA(100, 255, 150, 255))
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, panelX + panelW - 30, startY, tostring(GameState.targetsHit))
    
    -- 总射击次数
    startY = startY + lineHeight
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(180, 180, 200, 255))
    nvgText(nvg, panelX + 30, startY, "射击次数:")
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, panelX + panelW - 30, startY, tostring(GameState.totalShots))
    
    -- 命中率
    startY = startY + lineHeight
    local hitRate = 0
    if GameState.totalShots > 0 then
        hitRate = (GameState.shotsHit / GameState.totalShots) * 100
    end
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(180, 180, 200, 255))
    nvgText(nvg, panelX + 30, startY, "命中率:")
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local hitColor = hitRate >= 50 and nvgRGBA(100, 255, 100, 255) or nvgRGBA(255, 150, 100, 255)
    nvgFillColor(nvg, hitColor)
    nvgText(nvg, panelX + panelW - 30, startY, string.format("%.1f%%", hitRate))
    
    -- 按钮区域
    local btnW = 180
    local btnH = 50
    local btnGap = 20  -- 按钮间距
    local totalBtnWidth = btnW * 2 + btnGap
    local btnStartX = w/2 - totalBtnWidth/2
    local btnY = h * 0.75
    
    -- 再来一局按钮
    local playAgainX = btnStartX
    local playAgainHovered = playAgainButtonHovered or false
    local playAgainColor = playAgainHovered and nvgRGBA(60, 180, 100, 255) or nvgRGBA(40, 140, 80, 255)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, playAgainX, btnY, btnW, btnH, 10)
    nvgFillColor(nvg, playAgainColor)
    nvgFill(nvg)
    
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, playAgainX, btnY, btnW, btnH, 10)
    nvgStrokeColor(nvg, nvgRGBA(100, 200, 140, 255))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    nvgFontSize(nvg, 24)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, playAgainX + btnW/2, btnY + btnH/2, "再来一局")
    
    -- 返回主菜单按钮
    local menuX = btnStartX + btnW + btnGap
    local menuHovered = returnMenuButtonHovered or false
    local menuColor = menuHovered and nvgRGBA(100, 120, 180, 255) or nvgRGBA(60, 80, 140, 255)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, menuX, btnY, btnW, btnH, 10)
    nvgFillColor(nvg, menuColor)
    nvgFill(nvg)
    
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, menuX, btnY, btnW, btnH, 10)
    nvgStrokeColor(nvg, nvgRGBA(120, 150, 200, 255))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, menuX + btnW/2, btnY + btnH/2, "返回主菜单")
    
    -- 提示
    nvgFontSize(nvg, 16)
    nvgFillColor(nvg, nvgRGBA(150, 150, 170, 180))
    nvgText(nvg, w/2, h * 0.88, "按 空格键 再来一局 | 按 ESC 返回主菜单")
end

--- 检查菜单按钮点击（主菜单的开始游戏按钮）
---@return boolean 是否点击了按钮
function M.CheckMenuButton()
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 主菜单按钮位置
    local btnW = 200
    local btnH = 60
    local btnX = w/2 - btnW/2
    local btnY = h * 0.7
    
    -- 获取鼠标/触摸位置
    local mx, my = input.mousePosition.x, input.mousePosition.y
    
    -- 检查鼠标悬停
    menuButtonHovered = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH
    
    -- 检查点击
    if menuButtonHovered and input:GetMouseButtonPress(MOUSEB_LEFT) then
        return true
    end
    
    -- 检查空格键
    if input:GetKeyPress(KEY_SPACE) then
        return true
    end
    
    return false
end

--- 检查游戏结束界面的按钮点击
---@return string|nil "play_again" 再来一局, "return_menu" 返回主菜单, nil 无点击
function M.CheckGameOverButtons()
    local w = GameState.screenWidth
    local h = GameState.screenHeight
    
    -- 按钮布局参数（与 DrawGameOver 保持一致）
    local btnW = 180
    local btnH = 50
    local btnGap = 20
    local totalBtnWidth = btnW * 2 + btnGap
    local btnStartX = w/2 - totalBtnWidth/2
    local btnY = h * 0.75
    
    -- 获取鼠标/触摸位置
    local mx, my = input.mousePosition.x, input.mousePosition.y
    
    -- 再来一局按钮
    local playAgainX = btnStartX
    playAgainButtonHovered = mx >= playAgainX and mx <= playAgainX + btnW and my >= btnY and my <= btnY + btnH
    
    -- 返回主菜单按钮
    local menuX = btnStartX + btnW + btnGap
    returnMenuButtonHovered = mx >= menuX and mx <= menuX + btnW and my >= btnY and my <= btnY + btnH
    
    -- 检查点击
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        if playAgainButtonHovered then
            return "play_again"
        elseif returnMenuButtonHovered then
            return "return_menu"
        end
    end
    
    -- 检查键盘快捷键
    if input:GetKeyPress(KEY_SPACE) then
        return "play_again"
    end
    if input:GetKeyPress(KEY_ESCAPE) then
        return "return_menu"
    end
    
    return nil
end

function M.Render()
    if not GameState.nvg then return end
    
    nvgBeginFrame(GameState.nvg, GameState.screenWidth, GameState.screenHeight, 1.0)
    
    -- 根据游戏阶段渲染不同 UI
    if GameState.gamePhase == GameState.GAME_PHASE.MENU then
        M.DrawMainMenu()
    elseif GameState.gamePhase == GameState.GAME_PHASE.PLAYING then
        -- 游戏中 UI
        M.DrawTimer()
        M.DrawReloadCircle()
        M.DrawGunCrosshair()
        M.DrawSniperScope()  -- 狙击镜UI（覆盖在准星上方）
        M.DrawLeftPanel()
        -- 键鼠模式下显示按键提示，触摸模式下显示武器圆盘
        if not isTouchMode then
            M.DrawKeyHints()
        else
            M.DrawWeaponWheel()  -- 武器选择圆盘（触摸模式）
        end
        M.DrawScorePopups()  -- 分数弹出提示
        M.DrawAimIndicator()
        M.DrawBulletTimeEffect()
        M.DrawDamageFlash()
        M.DrawDeathScreen()
    elseif GameState.gamePhase == GameState.GAME_PHASE.GAME_OVER then
        M.DrawGameOver()
    end
    
    nvgEndFrame(GameState.nvg)
end

return M
