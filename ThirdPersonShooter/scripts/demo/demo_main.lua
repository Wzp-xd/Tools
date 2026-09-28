-- ============================================================================
-- 3D Shooter Demo - 3D射击游戏Demo（腰射模式）
-- 基于 UrhoX 引擎开发 - 模块化版本
-- ============================================================================
--
-- 玩法说明:
--   - WASD 移动
--   - 空格键跳跃
--   - 鼠标控制视角
--   - 左键射击
--   - 右键按住瞄准 (ADS)
--   - E 投掷手榴弹
--   - R 键换弹
--   - Q 切换左右手（带动画）
--   - F 子弹时间（持续3秒，5倍减速）
--   - 1/2/3 切换武器
--   - B 显示/隐藏怪物碰撞体
--   - ESC 退出
--
-- ============================================================================

require "LuaScripts/Utilities/Sample"

-- 加载 GameHUD（虚拟摇杆和按钮）
require "urhox-libs.UI.GameHUD"
require "urhox-libs.UI.VirtualControls"
local InputManager = require("urhox-libs.Platform.InputManager")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")

-- 加载模块
local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Physics = require "modules.Physics"
local Audio = require "modules.Audio"
local Scene = require "modules.Scene"
local Player = require "modules.Player"
local Weapon = require "modules.Weapon"
local Bullet = require "modules.Bullet"
local HitEffects = require "modules.HitEffects"
local Grenade = require "modules.Grenade"
local Monster = require "modules.Monster"
local Target = require "modules.Target"
local UI = require "modules.UI"

local CONFIG = Config.CONFIG

-- ============================================================================
-- 生命周期函数
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title
    
    -- 获取屏幕尺寸
    GameState.screenWidth = graphics:GetWidth()
    GameState.screenHeight = graphics:GetHeight()
    
    -- 初始化场景
    Scene.Create()
    
    -- 创建玩家
    Player.Create()
    
    -- 创建武器
    Weapon.CreateGun()
    Weapon.InitWeapon(Config.WEAPON_ORDER[1])  -- 默认使用1号枪
    
    -- 创建怪物（根据开关状态）
    if GameState.dynamicMonsterEnabled then
        Monster.Create(false)  -- 动态敌人
    end
    
    -- 创建靶子（替代原来的静态敌人）
    Target.Create()
    
    -- 初始化 NanoVG
    InitNanoVG()
    
    -- 初始化音效
    Audio.Init()
    
    -- 订阅事件
    SubscribeToEvents()
    
    -- 初始化触屏控制（移动端支持）
    InitTouchControls()
    
    -- 初始化按钮图标渲染
    InitIconRenderer()
    
    -- 设置初始游戏阶段为菜单
    GameState.gamePhase = GameState.GAME_PHASE.MENU
    
    -- 菜单状态下显示鼠标
    input.mouseMode = MM_ABSOLUTE
    
    -- 清除初始创建的靶子（等开始游戏后再创建）
    Target.ClearAll()
    
    print("=== 射击训练场 - 等待开始游戏 ===")
end

function Stop()
    Audio.StopAll()
    
    if GameState.nvg then
        nvgDelete(GameState.nvg)
        GameState.nvg = nil
    end
    print("=== Game Stopped ===")
end

-- ============================================================================
-- NanoVG 初始化
-- ============================================================================

function InitNanoVG()
    GameState.nvg = nvgCreate(1)
    if GameState.nvg then
        GameState.nvgFont = nvgCreateFont(GameState.nvg, "sans", "Fonts/MiSans-Regular.ttf")
        print("NanoVG initialized, font loaded")
    else
        print("Failed to create NanoVG context!")
    end
end

-- ============================================================================
-- 触屏控制组件引用（需要在图标渲染前声明）
-- ============================================================================

---@type table
local touchControls = {
    joystick = nil,        -- 虚拟摇杆
    fireBtn = nil,         -- 开火按钮
    jumpBtn = nil,         -- 跳跃按钮
    reloadBtn = nil,       -- 换弹按钮
    bulletTimeBtn = nil,   -- 子弹时间按钮
    switchHandBtn = nil,   -- 换手按钮
}

--- 测试开关：强制显示手机UI（虚拟按钮），默认开启
local FORCE_TOUCH_UI = true

--- 是否为触摸/移动模式（用于决定显示虚拟按钮还是按键提示）
local isTouchMode = false

-- ============================================================================
-- 按钮图标渲染系统
-- ============================================================================

--- 图标渲染上下文和图片句柄
local iconRenderer = {
    nvg = nil,
    icons = {},  -- { fire = handle, jump = handle, ... }
}

--- 初始化图标渲染系统
function InitIconRenderer()
    -- 创建专用 NanoVG 上下文（渲染优先级高于 VirtualControls）
    iconRenderer.nvg = nvgCreate(1)
    if not iconRenderer.nvg then
        print("WARNING: Failed to create icon NanoVG context")
        return
    end
    
    -- 设置渲染优先级高于 VirtualControls (999999)
    nvgSetRenderOrder(iconRenderer.nvg, 1000000)
    
    -- 加载字体
    iconRenderer.fontId = nvgCreateFont(iconRenderer.nvg, "iconfont", "Fonts/MiSans-Regular.ttf")
    
    print("Icon renderer initialized (NanoVG drawing mode)")
    
    -- 订阅渲染事件
    SubscribeToEvent(iconRenderer.nvg, "NanoVGRender", "HandleIconRender")
end

--- 计算按钮的屏幕位置（与 VirtualControls 相同的短边缩放逻辑）
local function calculateButtonScreenPos(btn)
    if not btn then return 0, 0, 0 end
    
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    
    -- VirtualControls 使用设计分辨率 1920x1080，短边 1080
    local designW, designH = 1920, 1080
    local designShortSide = 1080
    
    -- 短边缩放：与 VirtualControls 一致
    local scaleFactor = math.min(screenW, screenH) / designShortSide
    
    -- 计算偏移（居中显示）
    local scaledWidth = designW * scaleFactor
    local scaledHeight = designH * scaleFactor
    local offsetX = (screenW - scaledWidth) / 2
    local offsetY = (screenH - scaledHeight) / 2
    
    -- 获取按钮在设计坐标中的位置
    local pos = btn.position
    local align = btn.alignment or {HA_RIGHT, VA_BOTTOM}
    
    -- 计算实际屏幕边缘在设计坐标系中的位置（与 VirtualControls 一致）
    local screenRightInDesign = (screenW - offsetX) / scaleFactor
    local screenBottomInDesign = (screenH - offsetY) / scaleFactor
    local screenLeftInDesign = -offsetX / scaleFactor
    local screenTopInDesign = -offsetY / scaleFactor
    
    -- 计算设计坐标中的中心位置
    local designCenterX, designCenterY = pos.x, pos.y
    
    -- 根据对齐方式调整（使用实际屏幕边缘）
    if align[1] == HA_RIGHT then
        designCenterX = screenRightInDesign + pos.x
    elseif align[1] == HA_CENTER then
        designCenterX = designW / 2 + pos.x
    else -- HA_LEFT
        designCenterX = screenLeftInDesign + pos.x
    end
    
    if align[2] == VA_BOTTOM then
        designCenterY = screenBottomInDesign + pos.y
    elseif align[2] == VA_CENTER then
        designCenterY = designH / 2 + pos.y
    else -- VA_TOP
        designCenterY = screenTopInDesign + pos.y
    end
    
    -- 转换到屏幕坐标
    local screenX = offsetX + designCenterX * scaleFactor
    local screenY = offsetY + designCenterY * scaleFactor
    local screenRadius = btn.radius * scaleFactor
    
    return screenX, screenY, screenRadius
end

-- ============================================================================
-- NanoVG 图标绘制函数 (3A级酷炫风格)
-- ============================================================================

--- 绘制发光效果
local function drawGlow(ctx, cx, cy, radius, r, g, b, alpha)
    local paint = nvgRadialGradient(ctx, cx, cy, radius * 0.2, radius, 
        nvgRGBA(r, g, b, alpha), nvgRGBA(r, g, b, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, radius)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
end

--- 绘制开火图标（酷炫准星 + 发光）
local function drawFireIcon(ctx, cx, cy, size)
    -- 红色发光效果
    drawGlow(ctx, cx, cy, size * 0.5, 255, 80, 60, 80)
    
    local r = size * 0.35
    local lineLen = size * 0.22
    local gap = size * 0.1
    local thickness = size * 0.055
    
    -- 外圈光晕
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r * 0.45)
    nvgStrokeWidth(ctx, thickness * 0.5)
    nvgStrokeColor(ctx, nvgRGBA(255, 100, 80, 60))
    nvgStroke(ctx)
    
    -- 主准星线条（渐变色）
    nvgStrokeWidth(ctx, thickness)
    nvgLineCap(ctx, NVG_ROUND)
    
    -- 上（橙红渐变）
    nvgStrokeColor(ctx, nvgRGBA(255, 120, 80, 255))
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - gap)
    nvgLineTo(ctx, cx, cy - gap - lineLen)
    nvgStroke(ctx)
    
    -- 下
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy + gap)
    nvgLineTo(ctx, cx, cy + gap + lineLen)
    nvgStroke(ctx)
    
    -- 左
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - gap, cy)
    nvgLineTo(ctx, cx - gap - lineLen, cy)
    nvgStroke(ctx)
    
    -- 右
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx + gap, cy)
    nvgLineTo(ctx, cx + gap + lineLen, cy)
    nvgStroke(ctx)
    
    -- 中心亮点
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, size * 0.04)
    nvgFillColor(ctx, nvgRGBA(255, 200, 180, 255))
    nvgFill(ctx)
    
    -- 射击冷却圈显示
    if GameState.fireCooldown and GameState.fireCooldown > 0 and GameState.currentWeapon then
        local fireRate = GameState.currentWeapon.fireRate or 0.1
        local cooldownProgress = GameState.fireCooldown / fireRate
        cooldownProgress = math.max(0, math.min(1, cooldownProgress))
        local arcAngle = cooldownProgress * math.pi * 2
        
        -- 绘制冷却弧
        nvgBeginPath(ctx)
        nvgArc(ctx, cx, cy, r + size * 0.08, -math.pi / 2, -math.pi / 2 + arcAngle, NVG_CW)
        nvgStrokeWidth(ctx, thickness * 1.2)
        nvgStrokeColor(ctx, nvgRGBA(255, 100, 80, 180))
        nvgStroke(ctx)
    end
end

--- 绘制跳跃图标（动感箭头 + 发光）
local function drawJumpIcon(ctx, cx, cy, size)
    -- 青色发光
    drawGlow(ctx, cx, cy, size * 0.45, 80, 200, 255, 70)
    
    local arrowH = size * 0.35
    local arrowW = size * 0.28
    local thickness = size * 0.06
    
    nvgStrokeWidth(ctx, thickness)
    nvgLineCap(ctx, NVG_ROUND)
    nvgLineJoin(ctx, NVG_ROUND)
    
    -- 双层箭头效果
    -- 外层（较淡）
    nvgStrokeColor(ctx, nvgRGBA(80, 180, 255, 100))
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - arrowW * 1.2, cy + arrowH * 0.5)
    nvgLineTo(ctx, cx, cy - arrowH * 0.3)
    nvgLineTo(ctx, cx + arrowW * 1.2, cy + arrowH * 0.5)
    nvgStroke(ctx)
    
    -- 主箭头
    nvgStrokeColor(ctx, nvgRGBA(100, 220, 255, 255))
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - arrowW, cy + arrowH * 0.25)
    nvgLineTo(ctx, cx, cy - arrowH * 0.45)
    nvgLineTo(ctx, cx + arrowW, cy + arrowH * 0.25)
    nvgStroke(ctx)
    
    -- 底部加速线
    nvgStrokeWidth(ctx, thickness * 0.6)
    nvgStrokeColor(ctx, nvgRGBA(100, 220, 255, 150))
    for i = 1, 3 do
        local offsetY = arrowH * 0.35 + i * size * 0.08
        local lineW = arrowW * (1.1 - i * 0.2)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx - lineW, cy + offsetY)
        nvgLineTo(ctx, cx + lineW, cy + offsetY)
        nvgStroke(ctx)
    end
end

--- 绘制换弹图标（旋转弹夹 + 发光）
local function drawReloadIcon(ctx, cx, cy, size)
    -- 绿色发光
    drawGlow(ctx, cx, cy, size * 0.45, 100, 255, 120, 60)
    
    local r = size * 0.28
    local thickness = size * 0.055
    
    nvgLineCap(ctx, NVG_ROUND)
    
    -- 外圈光晕
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r * 1.3)
    nvgStrokeWidth(ctx, thickness * 0.4)
    nvgStrokeColor(ctx, nvgRGBA(100, 255, 120, 40))
    nvgStroke(ctx)
    
    -- 主圆弧
    nvgStrokeWidth(ctx, thickness)
    nvgStrokeColor(ctx, nvgRGBA(120, 255, 140, 255))
    nvgBeginPath(ctx)
    nvgArc(ctx, cx, cy, r, -math.pi * 0.75, math.pi * 0.55, NVG_CW)
    nvgStroke(ctx)
    
    -- 箭头三角形
    local arrowAngle = math.pi * 0.55
    local arrowX = cx + r * math.cos(arrowAngle)
    local arrowY = cy + r * math.sin(arrowAngle)
    local arrowSize = size * 0.1
    
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, arrowX + arrowSize * 0.3, arrowY - arrowSize)
    nvgLineTo(ctx, arrowX + arrowSize * 0.8, arrowY + arrowSize * 0.3)
    nvgLineTo(ctx, arrowX - arrowSize * 0.5, arrowY + arrowSize * 0.2)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(120, 255, 140, 255))
    nvgFill(ctx)
    
    -- 中心弹夹图标
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - size * 0.06, cy - size * 0.12, size * 0.12, size * 0.24, size * 0.02)
    nvgFillColor(ctx, nvgRGBA(180, 255, 190, 200))
    nvgFill(ctx)
end

--- 绘制子弹时间图标（科幻时钟 + 发光）
local function drawBulletTimeIcon(ctx, cx, cy, size, btn)
    -- 检查冷却状态
    local onCooldown = btn and btn.cooldownRemaining and btn.cooldownRemaining > 0
    
    -- 冷却时使用灰色，否则使用紫色
    local glowR, glowG, glowB = 180, 100, 255
    local mainR, mainG, mainB = 200, 150, 255
    local brightR, brightG, brightB = 255, 200, 255
    local centerR, centerG, centerB = 255, 220, 255
    local glowAlpha = 80
    
    if onCooldown then
        -- 冷却中：灰色调
        glowR, glowG, glowB = 80, 80, 90
        mainR, mainG, mainB = 100, 100, 110
        brightR, brightG, brightB = 120, 120, 130
        centerR, centerG, centerB = 140, 140, 150
        glowAlpha = 40
    end
    
    -- 发光
    drawGlow(ctx, cx, cy, size * 0.5, glowR, glowG, glowB, glowAlpha)
    
    local r = size * 0.32
    local thickness = size * 0.045
    
    -- 外圈脉冲效果（多层）
    for i = 3, 1, -1 do
        local alpha = onCooldown and (15 + (4 - i) * 12) or (30 + (4 - i) * 25)
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r + i * size * 0.04)
        nvgStrokeWidth(ctx, thickness * 0.3)
        nvgStrokeColor(ctx, nvgRGBA(mainR, mainG - 30, mainB, alpha))
        nvgStroke(ctx)
    end
    
    -- 主表盘
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgStrokeWidth(ctx, thickness)
    nvgStrokeColor(ctx, nvgRGBA(mainR, mainG, mainB, 255))
    nvgStroke(ctx)
    
    -- 刻度线
    nvgStrokeWidth(ctx, thickness * 0.5)
    for i = 0, 11 do
        local angle = i * math.pi / 6 - math.pi / 2
        local innerR = r * 0.75
        local outerR = r * 0.9
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx + math.cos(angle) * innerR, cy + math.sin(angle) * innerR)
        nvgLineTo(ctx, cx + math.cos(angle) * outerR, cy + math.sin(angle) * outerR)
        nvgStrokeColor(ctx, nvgRGBA(mainR, mainG, mainB, onCooldown and 80 or 150))
        nvgStroke(ctx)
    end
    
    -- 时针
    nvgStrokeWidth(ctx, thickness * 1.2)
    nvgStrokeColor(ctx, nvgRGBA(brightR, brightG, brightB, 255))
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy)
    nvgLineTo(ctx, cx, cy - r * 0.45)
    nvgStroke(ctx)
    
    -- 分针
    nvgStrokeWidth(ctx, thickness * 0.8)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy)
    nvgLineTo(ctx, cx + r * 0.55, cy + r * 0.15)
    nvgStroke(ctx)
    
    -- 中心宝石
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, size * 0.05)
    nvgFillColor(ctx, nvgRGBA(centerR, centerG, centerB, 255))
    nvgFill(ctx)
    
    -- 冷却时显示冷却进度弧和剩余时间
    -- 使用 GameState 中的冷却值
    local cooldownMax = GameState.bulletTimeCooldownMax or 15
    if onCooldown and cooldownMax > 0 then
        local remaining = btn.cooldownRemaining or 0
        -- 确保 remaining 在有效范围内
        remaining = math.max(0, math.min(remaining, cooldownMax))
        local cooldownProgress = remaining / cooldownMax
        local arcAngle = cooldownProgress * math.pi * 2
        nvgBeginPath(ctx)
        nvgArc(ctx, cx, cy, r + size * 0.06, -math.pi / 2, -math.pi / 2 + arcAngle, NVG_CW)
        nvgStrokeWidth(ctx, thickness * 0.8)
        nvgStrokeColor(ctx, nvgRGBA(60, 60, 70, 200))
        nvgStroke(ctx)
        
        -- 显示剩余冷却时间数字
        if iconRenderer.fontId and iconRenderer.fontId >= 0 then
            local timeText = string.format("%.0f", math.ceil(remaining))
            nvgFontFaceId(ctx, iconRenderer.fontId)
            nvgFontSize(ctx, size * 0.28)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 文字阴影
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 200))
            nvgText(ctx, cx + 1, cy + 1, timeText, nil)
            -- 文字本体
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
            nvgText(ctx, cx, cy, timeText, nil)
        end
    end
end

--- 绘制换手图标（双向切换 + 发光）
local function drawSwitchIcon(ctx, cx, cy, size)
    -- 白色发光
    drawGlow(ctx, cx, cy, size * 0.4, 200, 200, 220, 50)
    
    local arrowW = size * 0.22
    local arrowH = size * 0.14
    local gap = size * 0.12
    local thickness = size * 0.05
    
    nvgStrokeWidth(ctx, thickness)
    nvgLineCap(ctx, NVG_ROUND)
    nvgLineJoin(ctx, NVG_ROUND)
    
    -- 左箭头（填充）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - gap, cy - arrowH)
    nvgLineTo(ctx, cx - gap - arrowW, cy)
    nvgLineTo(ctx, cx - gap, cy + arrowH)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(200, 220, 255, 200))
    nvgFill(ctx)
    
    -- 右箭头（填充）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx + gap, cy - arrowH)
    nvgLineTo(ctx, cx + gap + arrowW, cy)
    nvgLineTo(ctx, cx + gap, cy + arrowH)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(200, 220, 255, 200))
    nvgFill(ctx)
    
    -- 中间连接线
    nvgStrokeColor(ctx, nvgRGBA(180, 200, 240, 150))
    nvgStrokeWidth(ctx, thickness * 0.6)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - gap * 0.3, cy)
    nvgLineTo(ctx, cx + gap * 0.3, cy)
    nvgStroke(ctx)
end

--- 渲染按钮图标和按键标签
---@param ctx NVGContextWrapper NanoVG上下文
---@param btn table 按钮对象
---@param drawIconFunc function 图标绘制函数
---@param keyLabel string|nil 按键标签（非手机模式显示）
local function renderButtonIcon(ctx, btn, drawIconFunc, keyLabel)
    if not btn then return end
    if not btn._shouldShow then return end
    
    local cx, cy, radius = calculateButtonScreenPos(btn)
    local iconSize = radius * 1.6
    
    -- 绘制图标（传递按钮对象以支持冷却状态检查）
    drawIconFunc(ctx, cx, cy, iconSize, btn)
    
    -- 非手机模式下显示按键文字
    if keyLabel and not input.touchEmulation then
        if iconRenderer.fontId and iconRenderer.fontId >= 0 then
            local fontSize = radius * 0.35
            local textY = cy + radius + fontSize * 0.8
            
            nvgFontFaceId(ctx, iconRenderer.fontId)
            nvgFontSize(ctx, fontSize)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            
            -- 文字阴影
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
            nvgText(ctx, cx + 1, textY + 1, "[" .. keyLabel .. "]", nil)
            
            -- 文字本体
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
            nvgText(ctx, cx, textY, "[" .. keyLabel .. "]", nil)
        end
    end
end

--- 图标渲染事件处理
function HandleIconRender(eventType, eventData)
    -- 键鼠模式下不渲染虚拟按钮图标
    if not isTouchMode then return end
    
    local ctx = iconRenderer.nvg
    if not ctx then return end
    
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    
    nvgBeginFrame(ctx, w, h, 1.0)
    
    -- 绘制各按钮图标（带按键标签）
    renderButtonIcon(ctx, touchControls.fireBtn, drawFireIcon, "LMB")
    renderButtonIcon(ctx, touchControls.jumpBtn, drawJumpIcon, "Space")
    renderButtonIcon(ctx, touchControls.reloadBtn, drawReloadIcon, "R")
    renderButtonIcon(ctx, touchControls.bulletTimeBtn, drawBulletTimeIcon, "F")
    renderButtonIcon(ctx, touchControls.switchHandBtn, drawSwitchIcon, "Q")
    
    nvgEndFrame(ctx)
end

-- ============================================================================
-- 触屏控制初始化
-- ============================================================================

--- 初始化触屏控制
function InitTouchControls()
    -- 检测是否为触摸/移动模式
    -- FORCE_TOUCH_UI 开关用于在桌面端测试手机UI
    isTouchMode = FORCE_TOUCH_UI or PlatformUtils.IsTouchSupported()
    print("Input mode: " .. (isTouchMode and "Touch/Mobile" or "Keyboard/Mouse") .. 
          (FORCE_TOUCH_UI and " (FORCE_TOUCH_UI enabled)" or ""))
    
    -- 通知 UI 模块当前的输入模式
    UI.SetTouchMode(isTouchMode)
    
    -- 初始化 GameHUD（只用于摇杆和触屏转镜头）
    GameHUD.Initialize()
    
    -- 只创建摇杆，按钮全部自定义
    local hud = GameHUD.Create({
        enableJump = false,
        enableRun = false,
        enableShooter = false,
    })
    
    touchControls.joystick = hud.joystick
    
    -- ========================================================================
    -- 自定义按钮布局（右下角区域）
    -- 布局参考图：
    --           [Reload]
    --   [Jump]   [FIRE]  
    --   [F]              
    -- ========================================================================
    
    -- 自适应按钮尺寸：基于屏幕短边计算
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local minDim = math.min(screenW, screenH)
    
    -- 按钮尺寸基于屏幕短边的比例
    local btnRadius = math.max(45, minDim * 0.06)    -- 普通按钮：屏幕短边的6%，最小45
    local fireRadius = math.max(70, minDim * 0.10)   -- 开火按钮：屏幕短边的10%，最小70
    local margin = math.max(25, minDim * 0.03)       -- 边距：屏幕短边的3%
    local spacing = math.max(15, minDim * 0.02)      -- 按钮间距：屏幕短边的2%
    
    -- 右下角按钮整体偏移（向左上方移动0.1屏幕宽高）
    local offsetX = screenW * 0.1   -- 向左偏移0.1屏幕宽度
    local offsetY = screenH * 0.1   -- 向上偏移0.1屏幕高度
    
    -- 开火按钮 - 最大，右下角中心位置
    touchControls.fireBtn = VirtualControls.CreateButton({
        position = Vector2(-margin - fireRadius - offsetX, -margin - fireRadius - offsetY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = fireRadius,
        label = "",
        iconPath = "assets/icon_fire_20260202031456.png",
        mouseBinding = "LMB",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = isTouchMode,  -- 只在触摸模式下显示
        color = {255, 80, 80},         -- 红色
        pressedColor = {255, 150, 150},
        on_press = function()
            Bullet.Fire()
        end,
    })
    
    -- 跳跃按钮 - 开火按钮的左侧
    touchControls.jumpBtn = VirtualControls.CreateButton({
        position = Vector2(-margin - fireRadius * 2 - spacing - btnRadius - offsetX, -margin - btnRadius - offsetY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "",
        iconPath = "assets/icon_jump_20260202031517.png",
        keyBinding = "SPACE",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = isTouchMode,  -- 只在触摸模式下显示
        color = {100, 200, 255},       -- 蓝色
        pressedColor = {150, 230, 255},
        on_press = function()
            Player.Jump()
        end,
    })
    
    -- 换弹按钮 - 开火按钮的上方
    touchControls.reloadBtn = VirtualControls.CreateButton({
        position = Vector2(-margin - fireRadius - offsetX, -margin - fireRadius * 2 - spacing - btnRadius - offsetY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "",
        iconPath = "assets/icon_reload_20260202031538.png",
        keyBinding = "R",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = isTouchMode,  -- 只在触摸模式下显示
        color = {100, 255, 100},       -- 绿色
        pressedColor = {150, 255, 150},
        on_press = function()
            Weapon.StartReload()
        end,
    })
    
    -- 子弹时间按钮 - 开火按钮的左上角（带冷却显示）
    touchControls.bulletTimeBtn = VirtualControls.CreateButton({
        position = Vector2(-margin - fireRadius * 2 - spacing - btnRadius - offsetX, -margin - btnRadius * 2 - spacing - btnRadius - offsetY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "",
        iconPath = "assets/icon_bullettime_20260202031600.png",
        keyBinding = "F",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = isTouchMode,  -- 只在触摸模式下显示
        color = {180, 100, 255},       -- 紫色
        pressedColor = {220, 150, 255},
        -- 注意：不设置 cooldown 参数，完全由 GameState.bulletTimeCooldown 管理
        on_press = function()
            if not GameState.bulletTimeActive and GameState.bulletTimeCooldown <= 0 then
                GameState.bulletTimeActive = true
                GameState.bulletTimeTimer = 0
                GameState.bulletTimeCooldown = GameState.bulletTimeCooldownMax
                print("Bullet Time Activated! Cooldown: " .. GameState.bulletTimeCooldownMax .. "s")
            end
        end,
    })
    
    -- ========================================================================
    -- 左上角按钮（信息UI下方）
    -- ========================================================================
    
    -- 换手按钮 - 左上角，信息UI下方
    touchControls.switchHandBtn = VirtualControls.CreateButton({
        position = Vector2(margin + btnRadius, margin + 120 + btnRadius),  -- 120 是信息UI的高度
        alignment = {HA_LEFT, VA_TOP},
        radius = btnRadius * 0.8,
        label = "",
        iconPath = "assets/icon_switch_20260202031621.png",
        keyBinding = "Q",
        opacity = 0.4,
        activeOpacity = 0.8,
        alwaysShow = isTouchMode,  -- 只在触摸模式下显示
        color = {200, 200, 200},       -- 灰色
        pressedColor = {255, 255, 255},
        on_press = function()
            Weapon.ToggleHandedness()
        end,
    })
    
    -- ========================================================================
    -- 启用触屏转镜头
    -- ========================================================================
    
    GameHUD.EnableTouchLook({
        camera = GameState.cameraNode,
        sensitivity = 2.0,
        invertY = false,
        onLook = function(deltaYaw, deltaPitch)
            -- 根据FOV调整灵敏度（FOV越低，灵敏度越低，便于精确瞄准）
            local baseFov = CONFIG.CameraFov
            local currentFov = GameState.camera and GameState.camera.fov or baseFov
            local fovSensitivityMult = currentFov / baseFov
            
            GameState.yaw = GameState.yaw + deltaYaw * fovSensitivityMult
            GameState.pitch = GameState.pitch + deltaPitch * fovSensitivityMult
            GameState.pitch = Clamp(GameState.pitch, -89.0, 89.0)
            
            if GameState.playerNode then
                GameState.playerNode.rotation = Quaternion(GameState.yaw, Vector3.UP)
            end
            if GameState.cameraNode then
                GameState.cameraNode.rotation = Quaternion(GameState.pitch, Vector3.RIGHT)
            end
        end,
    })
    
    print("[TouchControls] Custom layout initialized")
end

--- 获取虚拟摇杆输入
---@return number x 左右方向 (-1 到 1)
---@return number z 前后方向 (-1 到 1，向前为正)
function GetJoystickInput()
    local joystick = touchControls.joystick
    if not joystick then
        return 0, 0
    end
    
    local deadZone = 0.15
    local x, z = 0, 0
    
    ---@type number
    local jx = joystick.x or 0
    ---@type number
    local jy = joystick.y or 0
    
    -- 摇杆 x: 左右
    if math.abs(jx) > deadZone then
        x = jx
    end
    
    -- 摇杆 y: 屏幕坐标系，需要反转（上推 y<0 = 前进 z>0）
    if math.abs(jy) > deadZone then
        z = -jy
    end
    
    return x, z
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")  -- 新增：用于更新第三人称相机
    SubscribeToEvent("PreRenderUI", "HandleRenderUI")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    
    -- 订阅物理碰撞事件（用于子弹碰撞检测）
    SubscribeToEvent("PhysicsCollisionStart", "HandlePhysicsCollision")
end

--- 处理物理碰撞事件
---@param eventType string
---@param eventData PhysicsCollisionStartEventData
function HandlePhysicsCollision(eventType, eventData)
    local nodeA = eventData:GetPtr("NodeA")
    local nodeB = eventData:GetPtr("NodeB")
    
    if not nodeA or not nodeB then return end
    
    -- 检查是否是子弹碰撞
    local bulletNode = nil
    local otherNode = nil
    
    -- 判断哪个是子弹节点
    if GameState.bulletDataMap[nodeA] then
        bulletNode = nodeA
        otherNode = nodeB
    elseif GameState.bulletDataMap[nodeB] then
        bulletNode = nodeB
        otherNode = nodeA
    end
    
    -- 如果不是子弹碰撞，直接返回
    if not bulletNode then return end
    
    -- 射线检测模式下不处理物理碰撞（击中效果已在射击时处理）
    if Config.CONFIG.BulletCollisionMode == Config.BULLET_COLLISION_MODE.RAYCAST then return end
    
    -- 获取子弹数据
    local bullet = GameState.bulletDataMap[bulletNode]
    if not bullet then return end
    
    -- 获取子弹的实时飞行方向
    local actualDirection = bullet.direction
    if bullet.rigidBody then
        local velocity = bullet.rigidBody.linearVelocity
        local speed = velocity:Length()
        if speed > 0.1 then
            actualDirection = velocity / speed
        end
    end
    
    -- 物理碰撞模式：使用子弹当前位置作为碰撞点
    -- 稍微回退一点以确保弹孔在表面上而不是内部
    local contactPosition = bulletNode.worldPosition - actualDirection * 0.05
    
    -- 弹孔法线 = 子弹方向的反向（默认值）
    local contactNormal = actualDirection * (-1)
    
    -- 尝试用短距离射线获取精确的碰撞法线（从子弹位置向前一小段）
    if GameState.physicsWorld then
        local rayStart = bulletNode.worldPosition - actualDirection * 0.5  -- 回退 0.5 米
        local ray = Ray(rayStart, actualDirection)
        local result = GameState.physicsWorld:RaycastSingle(ray, 1.0, GameState.COLLISION_MASK.BULLET)
        if result.body then
            contactPosition = result.position
            contactNormal = result.normal
        end
    end
    
    -- 调用子弹模块处理碰撞
    Bullet.HandleBulletCollision(bulletNode, otherNode, contactPosition, contactNormal)
end

function HandleScreenMode(eventType, eventData)
    GameState.screenWidth = graphics:GetWidth()
    GameState.screenHeight = graphics:GetHeight()
end

--- 开始游戏（从菜单进入游戏）
local function StartGame()
    -- 先清除场景中的对象（在 Reset 之前，否则引用会丢失）
    Bullet.ClearAll()      -- 子弹和弹壳
    Target.ClearAll()      -- 靶子
    HitEffects.ClearAll()  -- 命中特效
    Grenade.ClearAll()     -- 手榴弹
    
    -- 重置游戏状态
    GameState.Reset()
    
    -- 立即重置子弹时间按钮冷却显示
    if touchControls.bulletTimeBtn then
        touchControls.bulletTimeBtn.cooldownRemaining = 0
    end
    
    -- 重置玩家位置
    if GameState.playerNode then
        GameState.playerNode.position = Vector3(0, CONFIG.PlayerHeight, 0)
    end
    
    -- 重新创建靶子
    Target.Create()
    
    -- 重新初始化武器
    Weapon.InitWeapon(Config.WEAPON_ORDER[1])  -- 默认使用1号枪
    
    -- 设置游戏阶段为游戏中
    GameState.gamePhase = GameState.GAME_PHASE.PLAYING
    GameState.gameTimer = 0
    
    -- 锁定鼠标
    input.mouseMode = MM_RELATIVE
    
    print("=== 游戏开始! 60秒限时挑战 ===")
end

--- 游戏结束
local function EndGame()
    GameState.gamePhase = GameState.GAME_PHASE.GAME_OVER
    
    -- 解锁鼠标（方便点击按钮）
    input.mouseMode = MM_ABSOLUTE
    
    -- 计算命中率
    local hitRate = 0
    if GameState.totalShots > 0 then
        hitRate = (GameState.shotsHit / GameState.totalShots) * 100
    end
    
    print(string.format("=== 游戏结束! 得分: %d, 命中率: %.1f%% ===", GameState.score, hitRate))
end

--- 返回主菜单（清理游戏场景）
local function ReturnToMenu()
    -- 清除所有子弹
    Bullet.ClearAll()
    
    -- 清除所有靶子
    Target.ClearAll()
    
    -- 重置游戏状态
    GameState.Reset()
    
    -- 立即重置子弹时间按钮冷却显示
    if touchControls.bulletTimeBtn then
        touchControls.bulletTimeBtn.cooldownRemaining = 0
    end
    
    -- 重置玩家位置和状态
    if GameState.playerNode then
        GameState.playerNode.position = Vector3(0, CONFIG.PlayerHeight, 0)
    end
    GameState.isDead = false
    
    -- 重置武器状态
    Weapon.InitWeapon(Config.WEAPON_ORDER[1])  -- 默认使用1号枪
    
    -- 设置游戏阶段为主菜单
    GameState.gamePhase = GameState.GAME_PHASE.MENU
    
    -- 显示鼠标
    input.mouseMode = MM_ABSOLUTE
    
    print("=== 返回主菜单 ===")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    
    -- 更新屏幕尺寸
    GameState.screenWidth = graphics:GetWidth()
    GameState.screenHeight = graphics:GetHeight()
    
    -- 根据游戏阶段处理
    if GameState.gamePhase == GameState.GAME_PHASE.MENU then
        -- 主菜单：检查开始按钮
        if UI.CheckMenuButton() then
            StartGame()
        end
        return
    elseif GameState.gamePhase == GameState.GAME_PHASE.GAME_OVER then
        -- 游戏结束：检查按钮
        local action = UI.CheckGameOverButtons()
        if action == "play_again" then
            StartGame()
        elseif action == "return_menu" then
            ReturnToMenu()
        end
        return
    end
    
    -- ========== 以下是游戏中逻辑 ==========
    
    -- 更新游戏计时器
    GameState.gameTimer = GameState.gameTimer + dt
    
    -- 检查游戏是否结束
    if GameState.gameTimer >= GameState.gameDuration then
        EndGame()
        return
    end
    
    -- 子弹时间更新（使用真实时间，不受 timeScale 影响）
    UpdateBulletTime(dt)
    
    -- 死亡状态处理
    if GameState.isDead then
        if input:GetKeyPress(KEY_SPACE) then
            Player.Respawn()
        end
        return
    end
    
    -- 更新射击冷却（受游戏速度影响）
    local gameSpeed = GameState.gameSpeed or 1.0
    if GameState.fireCooldown > 0 then
        GameState.fireCooldown = GameState.fireCooldown - dt * gameSpeed
    end
    
    -- 处理输入
    HandleInput(dt)
    
    -- 更新各系统
    Bullet.Update(dt)
    Weapon.UpdateGunAnimation(dt)
    UpdateRecoil(dt)
    UpdateCameraShake(dt)
    Weapon.UpdateReload(dt)
    Player.UpdateHealth(dt)
    Player.UpdateAnimation(dt)  -- 更新角色动画状态机
    Monster.Update(dt)
    Target.Update(dt)
    HitEffects.Update(dt)
    Grenade.Update(dt)
    Bullet.UpdateGunAimPoint()
    UI.UpdateDamageFlash(dt)
    UI.UpdateWeaponWheel(dt)
    UI.UpdateScorePopups(dt)
    UI.UpdateCrosshair(dt)
    
    -- 检查武器圆盘交互
    local selectedWeapon = UI.CheckWeaponWheelInput()
    if selectedWeapon then
        -- 切换到选中的武器
        Weapon.InitWeapon(selectedWeapon)
    end
end

--- 更新后坐力恢复
function UpdateRecoil(dt)
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    
    -- 记录是否有后坐力变化（用于决定是否需要更新旋转）
    local recoilChanged = false
    
    -- 缓动应用待处理的后坐力（受游戏速度影响）
    if GameState.pendingRecoilPitch > 0.01 or GameState.pendingRecoilPitch < -0.01 then
        local applyAmount = CONFIG.RecoilEaseSpeed * dt * gameSpeed
        if GameState.pendingRecoilPitch > 0 then
            local apply = math.min(applyAmount, GameState.pendingRecoilPitch)
            GameState.pitch = GameState.pitch - apply
            GameState.pendingRecoilPitch = GameState.pendingRecoilPitch - apply
        else
            local apply = math.max(-applyAmount, GameState.pendingRecoilPitch)
            GameState.pitch = GameState.pitch - apply
            GameState.pendingRecoilPitch = GameState.pendingRecoilPitch - apply
        end
        GameState.pitch = Clamp(GameState.pitch, -89.0, 89.0)
        recoilChanged = true
    else
        GameState.pendingRecoilPitch = 0
    end
    
    if GameState.pendingRecoilYaw > 0.01 or GameState.pendingRecoilYaw < -0.01 then
        local applyAmount = CONFIG.RecoilEaseSpeed * dt * gameSpeed
        if GameState.pendingRecoilYaw > 0 then
            local apply = math.min(applyAmount, GameState.pendingRecoilYaw)
            GameState.yaw = GameState.yaw + apply
            GameState.pendingRecoilYaw = GameState.pendingRecoilYaw - apply
        else
            local apply = math.max(-applyAmount, GameState.pendingRecoilYaw)
            GameState.yaw = GameState.yaw + apply
            GameState.pendingRecoilYaw = GameState.pendingRecoilYaw - apply
        end
        recoilChanged = true
    else
        GameState.pendingRecoilYaw = 0
    end
    
    -- 后坐力恢复
    if GameState.recoilPitch > 0 then
        local recovery = CONFIG.RecoilRecoverySpeed * dt
        GameState.recoilPitch = math.max(0, GameState.recoilPitch - recovery)
    end
    
    if GameState.recoilYaw ~= 0 then
        local recovery = CONFIG.RecoilRecoverySpeed * dt
        if GameState.recoilYaw > 0 then
            GameState.recoilYaw = math.max(0, GameState.recoilYaw - recovery)
        else
            GameState.recoilYaw = math.min(0, GameState.recoilYaw + recovery)
        end
    end
    
    -- 枪口过高时自动恢复
    if GameState.pitch < CONFIG.MaxUpwardPitch and GameState.pendingRecoilPitch < 0.1 then
        local recoverySpeed = CONFIG.PitchRecoverySpeed * dt
        local targetPitch = CONFIG.PitchRecoveryTarget
        if GameState.pitch < targetPitch then
            GameState.pitch = math.min(targetPitch, GameState.pitch + recoverySpeed)
            recoilChanged = true
        end
    end
    
    -- 准心扩散恢复（受游戏速度影响）
    if GameState.crosshairSpread > 0 then
        local recoverySpeed = CONFIG.CrosshairRecoverySpeed
        if GameState.currentWeapon and GameState.currentWeapon.crosshairRecoverySpeed then
            recoverySpeed = GameState.currentWeapon.crosshairRecoverySpeed
        end
        if not GameState.isPlayerMoving then
            recoverySpeed = recoverySpeed * 1.5
        end
        -- 瞄准状态下准心恢复速度提升30%
        if GameState.isAiming then
            recoverySpeed = recoverySpeed * 1.3
        end
        GameState.crosshairSpread = math.max(0, GameState.crosshairSpread - recoverySpeed * dt * gameSpeed)
    end
    
    -- 🔧 关键修复：后坐力改变了 yaw/pitch 后，立即应用到节点旋转
    -- 否则只有鼠标移动时才会更新旋转，导致后坐力"积压"
    if recoilChanged and GameState.playerNode and GameState.cameraNode then
        GameState.playerNode.rotation = Quaternion(GameState.yaw, Vector3.UP)
        GameState.cameraNode.rotation = Quaternion(GameState.pitch, Vector3.RIGHT)
    end
end

--- 更新子弹时间
function UpdateBulletTime(dt)
    -- 更新冷却（使用真实时间）
    if GameState.bulletTimeCooldown > 0 then
        GameState.bulletTimeCooldown = GameState.bulletTimeCooldown - dt
        
        -- 确保冷却不会变成负值
        if GameState.bulletTimeCooldown < 0 then
            GameState.bulletTimeCooldown = 0
        end
        
        -- 同步按钮的冷却显示
        if touchControls.bulletTimeBtn then
            touchControls.bulletTimeBtn.cooldownRemaining = GameState.bulletTimeCooldown
        end
    end
    
    if not GameState.bulletTimeActive then
        -- 确保非子弹时间时游戏速度为 1.0
        GameState.gameSpeed = 1.0
        GameState.bulletTimeFovMultiplier = 0.0
        -- 恢复正常重力
        if GameState.physicsWorld then
            GameState.physicsWorld.gravity = Vector3(0, CONFIG.Gravity, 0)
        end
        -- 禁用颜色分级（恢复正常画面）
        if GameState.colorGrading then
            GameState.colorGrading.colorGradingEnabled = false
        end
        return
    end
    
    -- 更新计时器（使用真实时间 dt）
    GameState.bulletTimeTimer = GameState.bulletTimeTimer + dt
    
    local timer = GameState.bulletTimeTimer
    local duration = GameState.bulletTimeDuration
    local easeIn = GameState.bulletTimeEaseIn
    local targetScale = GameState.bulletTimeScale
    
    local gameSpeed = 1.0
    
    -- 计算各阶段时间点
    local holdRatio = 0.4  -- 40% 的时间保持最低速度
    local holdEnd = easeIn + (duration - easeIn) * holdRatio  -- 持续阶段结束时间
    
    if timer < easeIn then
        -- 缓入阶段：从 1.0 快速缓动到 targetScale
        local t = timer / easeIn
        -- 使用平滑缓动 (smoothstep)
        t = t * t * (3 - 2 * t)
        gameSpeed = 1.0 + (targetScale - 1.0) * t
    elseif timer < holdEnd then
        -- 持续阶段：保持在最低速度
        gameSpeed = targetScale
    elseif timer < duration then
        -- 恢复阶段：从 targetScale 逐渐恢复到 1.0
        local recoveryTime = duration - holdEnd  -- 恢复阶段的总时长
        local t = (timer - holdEnd) / recoveryTime  -- 0 -> 1
        -- easeInQuad: t^2（开始时慢，接近结束时加速）
        local easedT = t * t
        gameSpeed = targetScale + (1.0 - targetScale) * easedT
    else
        -- 子弹时间结束
        GameState.bulletTimeActive = false
        GameState.bulletTimeTimer = 0
        -- 注意：冷却从激活时开始计算，这里不再设置
        gameSpeed = 1.0
    end
    
    -- 记录上一帧的游戏速度（用于检测速度变化）
    local prevGameSpeed = GameState.gameSpeed or 1.0
    
    -- 应用游戏速度（影响玩家移动、怪物移动、子弹速度、换弹等）
    GameState.gameSpeed = gameSpeed
    
    -- 调整重力（使用 gameSpeed² 让下落看起来也慢）
    -- 原理：位移 s = 0.5 * g * t²，时间变慢 k 倍时，需要 g' = g * k² 才能保持视觉一致
    if GameState.physicsWorld then
        local gravityScale = gameSpeed * gameSpeed
        GameState.physicsWorld.gravity = Vector3(0, CONFIG.Gravity * gravityScale, 0)
    end
    
    -- 当游戏速度变化时，同步调整玩家的垂直速度
    -- 这样在空中进入/退出子弹时间时，跳跃高度保持一致
    if GameState.playerBody and math.abs(prevGameSpeed - gameSpeed) > 0.001 then
        local velocity = GameState.playerBody.linearVelocity
        -- 速度按比例缩放：newVelocity = oldVelocity * (newSpeed / oldSpeed)
        local speedRatio = gameSpeed / prevGameSpeed
        GameState.playerBody.linearVelocity = Vector3(
            velocity.x * speedRatio,
            velocity.y * speedRatio,
            velocity.z * speedRatio
        )
    end
    
    -- 计算 FOV 缩放系数（与 gameSpeed 同步缓动）
    -- gameSpeed: 1.0 -> 0.1，fovMultiplier: 0.0 -> 1.0
    local fovMultiplier = (1.0 - gameSpeed) / (1.0 - targetScale)
    fovMultiplier = math.max(0, math.min(1, fovMultiplier))  -- clamp 0-1
    GameState.bulletTimeFovMultiplier = fovMultiplier
    
    -- 更新颜色分级（子弹时间提升对比度）
    if GameState.colorGrading then
        -- 启用颜色分级
        GameState.colorGrading.colorGradingEnabled = true
        -- 禁用 LUT 效果
        GameState.colorGrading:SetLUTIntensity(0)
        -- 对比度：正常 1.0 -> 子弹时间 1.3（随 fovMultiplier 缓动）
        local normalContrast = 1.0
        local bulletTimeContrast = 1.3
        GameState.colorGrading.globalContrast = normalContrast + (bulletTimeContrast - normalContrast) * fovMultiplier
    end
end

--- 更新镜头抖动
function UpdateCameraShake(dt)
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    
    if GameState.cameraShakeTime > 0 and GameState.currentWeapon then
        -- 镜头抖动时间受游戏速度影响
        GameState.cameraShakeTime = GameState.cameraShakeTime - dt * gameSpeed
        local w = GameState.currentWeapon
        local progress = GameState.cameraShakeTime / w.cameraShakeDuration
        local intensity = w.cameraShakeIntensity * progress
        GameState.cameraShakeOffset = Vector3(
            (math.random() - 0.5) * 2 * intensity,
            (math.random() - 0.5) * 2 * intensity,
            0
        )
    else
        GameState.cameraShakeOffset = Vector3.ZERO
    end
end

--- 处理输入
function HandleInput(dt)
    -- 鼠标视角控制（PC 端）
    -- 注意：移动端的视角控制由 GameHUD.EnableTouchLook 处理
    if input.mouseMode == MM_RELATIVE then
        local mouseDeltaX = input.mouseMoveX
        local mouseDeltaY = input.mouseMoveY
        
        -- 只有鼠标有移动时才更新（避免与触屏冲突）
        if mouseDeltaX ~= 0 or mouseDeltaY ~= 0 then
            -- 根据FOV调整灵敏度（FOV越低，灵敏度越低，便于精确瞄准）
            local baseFov = CONFIG.CameraFov
            local currentFov = GameState.camera and GameState.camera.fov or baseFov
            local fovSensitivityMult = currentFov / baseFov
            local adjustedSensitivity = CONFIG.MouseSensitivity * fovSensitivityMult
            
            GameState.yaw = GameState.yaw + mouseDeltaX * adjustedSensitivity
            GameState.pitch = GameState.pitch + mouseDeltaY * adjustedSensitivity
            GameState.pitch = Clamp(GameState.pitch, -89.0, 89.0)
            
            GameState.playerNode.rotation = Quaternion(GameState.yaw, Vector3.UP)
            GameState.cameraNode.rotation = Quaternion(GameState.pitch, Vector3.RIGHT)
        end
    end
    
    -- 跳跃（键盘，触屏跳跃由 GameHUD 回调处理）
    if input:GetKeyPress(KEY_SPACE) then
        Player.Jump()
    end
    
    -- 检测是否在地面上（用于准心等）
    GameState.isGrounded = Player.IsGrounded()
    
    -- 水平移动方向（同时支持键盘和虚拟摇杆）
    local moveDir = Vector3.ZERO
    
    -- 键盘输入 (WASD)
    if input:GetKeyDown(KEY_W) then moveDir = moveDir + Vector3.FORWARD end
    if input:GetKeyDown(KEY_S) then moveDir = moveDir - Vector3.FORWARD end
    if input:GetKeyDown(KEY_A) then moveDir = moveDir - Vector3.RIGHT end
    if input:GetKeyDown(KEY_D) then moveDir = moveDir + Vector3.RIGHT end
    
    -- 虚拟摇杆输入（移动端）
    local joystickX, joystickZ = GetJoystickInput()
    if joystickX ~= 0 or joystickZ ~= 0 then
        moveDir = moveDir + Vector3(joystickX, 0, joystickZ)
    end
    
    GameState.isPlayerMoving = moveDir:Length() > 0
    
    -- 检测跑步状态（Shift键，瞄准时不能跑步）
    GameState.isRunning = input:GetKeyDown(KEY_SHIFT) and GameState.isPlayerMoving and not GameState.isAiming
    
    if GameState.isPlayerMoving then
        moveDir = moveDir:Normalized()
        -- 转换到世界坐标
        local worldMoveDir = GameState.playerNode.rotation * moveDir
        -- 使用物理系统移动
        Player.Move(worldMoveDir, dt)
    else
        -- 没有输入时减速
        Player.StopMovement()
    end
    
    -- 武器切换（键盘）
    if input:GetKeyPress(KEY_1) then Weapon.SwitchToWeaponByIndex(1) end
    if input:GetKeyPress(KEY_2) then Weapon.SwitchToWeaponByIndex(2) end
    if input:GetKeyPress(KEY_3) then Weapon.SwitchToWeaponByIndex(3) end
    if input:GetKeyPress(KEY_4) then Weapon.SwitchToWeaponByIndex(4) end
    if input:GetKeyPress(KEY_5) then Weapon.SwitchToWeaponByIndex(5) end
    if input:GetKeyPress(KEY_6) then Weapon.SwitchToWeaponByIndex(6) end
    if input:GetKeyPress(KEY_7) then Weapon.SwitchToWeaponById("rifle") end  -- 测试武器：rifle（子弹速度10）
    if input:GetKeyPress(KEY_T) then UI.ToggleWeaponWheel() end  -- 切换武器选择面板
    
    if input.mouseMoveWheel ~= 0 then Weapon.SwitchToNextWeapon() end
    
    if input:GetKeyPress(KEY_Q) then Weapon.ToggleHandedness() end
    if input:GetKeyPress(KEY_Z) then Monster.ToggleDynamic() end
    if input:GetKeyPress(KEY_X) then Monster.ToggleStatic() end
    if input:GetKeyPress(KEY_M) then Audio.ToggleSound() end
    if input:GetKeyPress(KEY_V) then Weapon.RefillAmmo() end
    if input:GetKeyPress(KEY_R) then Weapon.StartReload() end
    if input:GetKeyPress(KEY_E) then Grenade.Throw() end
    if input:GetKeyPress(KEY_B) then Monster.ToggleColliderDisplay() end
    
    -- 子弹时间触发 (F 键) - 触屏由按钮回调处理
    -- 注意：VirtualControls 按钮已绑定 F 键，这里不需要重复处理
    -- 但保留以防用户禁用了虚拟按钮
    
    -- 右键瞄准 (ADS) - 仅 PC 端
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        Weapon.StartAiming()
    else
        Weapon.StopAiming()
    end
    
    -- 射击（键盘/鼠标，触屏射击由 GameHUD 回调处理）
    if GameState.currentWeapon then
        if GameState.currentWeapon.automatic then
            if input:GetMouseButtonDown(MOUSEB_LEFT) then
                Bullet.Fire()
            end
        else
            if input:GetMouseButtonPress(MOUSEB_LEFT) then
                Bullet.Fire()
            end
        end
    end
end

--- 渲染 UI
function HandleRenderUI(eventType, eventData)
    UI.Render()
end

--- 后更新：更新第三人称相机
---@param eventType string
---@param eventData UpdateEventData
function HandlePostUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    
    -- 更新第三人称相机位置（必须在 PostUpdate 中调用，确保角色位置已更新）
    Player.UpdateCamera(dt)
end
