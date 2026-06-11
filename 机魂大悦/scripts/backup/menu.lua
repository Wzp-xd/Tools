-- ============================================================================
-- 主菜单模块 - NanoVG 动画版
-- 机甲/军事科幻风格，带粒子、辉光、扫描线等效果
-- ============================================================================

local UI = require("urhox-libs/UI")
local CONFIG = require "config"

local Menu = {}

---@type Widget|nil
local rootWidget_ = nil
local initialized_ = false

-- ============================================================================
-- NanoVG 主菜单状态
-- ============================================================================

local menuVg_ = nil           -- NanoVG 上下文
local menuFont_ = -1          -- 字体句柄
local menuAnimTime_ = 0       -- 动画累计时间
local menuActive_ = false     -- 主菜单是否活跃
local menuCallbacks_ = nil    -- 回调缓存
local hoveredBtn_ = 0         -- 当前 hover 按钮索引 (0=无)
local btnGlow_ = {}           -- 按钮辉光强度 (lerp)
local menuButtons_ = {}       -- 按钮命中区域 [{x,y,w,h,action}]

-- 前向声明
local ShowLevelSelect

-- 粒子系统
local menuParticles_ = {}
local PARTICLE_COUNT_NORMAL = 30
local PARTICLE_COUNT_NARROW = 15

-- ============================================================================
-- 自适应布局参数
-- ============================================================================

--- 获取当前屏幕逻辑尺寸和布局参数
---@return table layout
local function GetLayout()
    local dpr = graphics:GetDPR()
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    local isPortrait = h > w
    local isNarrow = w < 600

    return {
        dpr = dpr,
        isPortrait = isPortrait,
        isNarrow = isNarrow,
        screenW = w,
        screenH = h,
        -- 主菜单
        titleSize = isNarrow and 28 or 40,
        subtitleSize = isNarrow and 12 or 15,
        btnWidth = isNarrow and 180 or 240,
        btnHeight = isNarrow and 40 or 48,
        btnFontSize = isNarrow and 14 or 16,
        titleMarginBottom = isNarrow and 24 or 40,
        gap = isNarrow and 10 or 14,
        -- 关卡选择
        levelTitleSize = isNarrow and 20 or 26,
        cardWidth = isNarrow and 150 or 200,
        cardPadding = isNarrow and 10 or 16,
        cardIconSize = isNarrow and 28 or 40,
        cardNameSize = isNarrow and 14 or 17,
        cardDescSize = isNarrow and 10 or 12,
        cardBtnWidth = isNarrow and 90 or 120,
        cardBtnHeight = isNarrow and 32 or 40,
        cardBtnFontSize = isNarrow and 13 or 15,
        cardGap = isNarrow and 10 or 20,
        -- 竖屏关卡卡片方向
        cardDir = isPortrait and "column" or "row",
    }
end

-- ============================================================================
-- 粒子系统
-- ============================================================================

local function CreateParticle(w, h, fullRandom)
    return {
        x = math.random() * w,
        y = fullRandom and (math.random() * h) or (h + math.random() * 20),
        vx = (math.random() - 0.5) * 12,
        vy = -(15 + math.random() * 30),
        life = 0,
        maxLife = 4 + math.random() * 6,
        size = 0.8 + math.random() * 2.0,
        brightness = 0.4 + math.random() * 0.6,
    }
end

local function InitParticles(w, h, count)
    menuParticles_ = {}
    for i = 1, count do
        menuParticles_[i] = CreateParticle(w, h, true)
        -- 随机初始生命，避免同时出现
        menuParticles_[i].life = math.random() * menuParticles_[i].maxLife
    end
end

local function UpdateParticles(dt, w, h)
    for i, p in ipairs(menuParticles_) do
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life + dt
        if p.life >= p.maxLife or p.y < -10 then
            menuParticles_[i] = CreateParticle(w, h, false)
        end
    end
end

-- ============================================================================
-- NanoVG 绘制函数 (按绘制顺序)
-- ============================================================================

--- 1. 深色渐变背景
local function DrawBackground(ctx, w, h)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local bg = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(10, 14, 28, 255),
        nvgRGBA(4, 6, 14, 255))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)
end

--- 2. 六角网格
local function DrawHexGrid(ctx, w, h, t)
    local spacing = w < 600 and 45 or 65
    local hexR = spacing * 0.35
    local scrollY = (t * 12) % (spacing * 1.732)
    local baseAlpha = 18 + 8 * math.sin(t * 0.8)

    nvgStrokeWidth(ctx, 1.0)

    local cols = math.ceil(w / spacing) + 2
    local rows = math.ceil(h / (spacing * 0.866)) + 3

    for row = -1, rows do
        for col = -1, cols do
            local offsetX = (row % 2 == 0) and 0 or (spacing * 0.5)
            local cx = col * spacing + offsetX
            local cy = row * spacing * 0.866 - scrollY

            -- 仅绘制屏幕可见范围
            if cx > -spacing and cx < w + spacing and cy > -spacing and cy < h + spacing then
                -- 基于位置的伪随机亮度变化
                local seed = (col * 17 + row * 31) % 100
                local extra = 0
                if seed < 8 then
                    extra = 15 * math.sin(t * 2.0 + seed * 0.5)
                end
                local alpha = math.max(0, math.min(255, math.floor(baseAlpha + extra)))

                nvgBeginPath(ctx)
                for i = 0, 5 do
                    local angle = (i * 60 + 30) * math.pi / 180
                    local px = cx + math.cos(angle) * hexR
                    local py = cy + math.sin(angle) * hexR
                    if i == 0 then
                        nvgMoveTo(ctx, px, py)
                    else
                        nvgLineTo(ctx, px, py)
                    end
                end
                nvgClosePath(ctx)
                nvgStrokeColor(ctx, nvgRGBA(25, 80, 130, alpha))
                nvgStroke(ctx)
            end
        end
    end
end

--- 3. 浮动粒子
local function DrawParticles(ctx)
    for _, p in ipairs(menuParticles_) do
        local lifeRatio = p.life / p.maxLife
        -- 淡入淡出
        local alpha = p.brightness
        if lifeRatio < 0.15 then
            alpha = alpha * (lifeRatio / 0.15)
        elseif lifeRatio > 0.75 then
            alpha = alpha * (1.0 - (lifeRatio - 0.75) / 0.25)
        end

        if alpha > 0.01 then
            -- 辉光
            local glowR = p.size * 4
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, glowR)
            local grad = nvgRadialGradient(ctx, p.x, p.y, 0, glowR,
                nvgRGBAf(0.3, 0.75, 1.0, alpha * 0.25),
                nvgRGBAf(0.2, 0.5, 0.8, 0))
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)

            -- 核心亮点
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, p.size)
            nvgFillColor(ctx, nvgRGBAf(0.5, 0.85, 1.0, alpha * 0.9))
            nvgFill(ctx)
        end
    end
end

--- 4. 扫描线
local function DrawScanLines(ctx, w, h, t)
    local lineSpacing = 4
    local scrollY = (t * 35) % lineSpacing
    nvgBeginPath(ctx)
    local y = scrollY
    while y < h do
        nvgRect(ctx, 0, y, w, 1)
        y = y + lineSpacing
    end
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 15))
    nvgFill(ctx)

    -- 移动的高亮扫描带
    local bandY = ((t * 60) % (h + 80)) - 40
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, bandY, w, 2)
    local bandGrad = nvgLinearGradient(ctx, 0, bandY, 0, bandY + 2,
        nvgRGBA(80, 180, 255, 0),
        nvgRGBA(80, 180, 255, 25))
    nvgFillPaint(ctx, bandGrad)
    nvgFill(ctx)
end

--- 5. 暗角
local function DrawVignette(ctx, w, h)
    local cx, cy = w / 2, h / 2
    local maxR = math.sqrt(cx * cx + cy * cy)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local grad = nvgRadialGradient(ctx, cx, cy, maxR * 0.35, maxR,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, 150))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

--- 6. 战术框角
local function DrawCornerFrames(ctx, w, h, t)
    local len = w < 600 and 28 or 42
    local m = w < 600 and 10 or 18
    local alpha = math.floor(60 + 40 * math.sin(t * 1.5))
    local color = nvgRGBA(40, 160, 220, alpha)

    nvgStrokeColor(ctx, color)
    nvgStrokeWidth(ctx, 1.5)

    -- 左上
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, m, m + len)
    nvgLineTo(ctx, m, m)
    nvgLineTo(ctx, m + len, m)
    nvgStroke(ctx)

    -- 右上
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, w - m - len, m)
    nvgLineTo(ctx, w - m, m)
    nvgLineTo(ctx, w - m, m + len)
    nvgStroke(ctx)

    -- 左下
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, m, h - m - len)
    nvgLineTo(ctx, m, h - m)
    nvgLineTo(ctx, m + len, h - m)
    nvgStroke(ctx)

    -- 右下
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, w - m, h - m - len)
    nvgLineTo(ctx, w - m, h - m)
    nvgLineTo(ctx, w - m - len, h - m)
    nvgStroke(ctx)

    -- 小十字标记 (各角内侧)
    local crossSize = 4
    local crossAlpha = math.floor(40 + 25 * math.sin(t * 2.5 + 1.0))
    nvgStrokeColor(ctx, nvgRGBA(40, 160, 220, crossAlpha))
    nvgStrokeWidth(ctx, 1.0)

    local crossPositions = {
        { m + len * 0.5, m + len * 0.5 },
        { w - m - len * 0.5, m + len * 0.5 },
        { m + len * 0.5, h - m - len * 0.5 },
        { w - m - len * 0.5, h - m - len * 0.5 },
    }
    for _, pos in ipairs(crossPositions) do
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, pos[1] - crossSize, pos[2])
        nvgLineTo(ctx, pos[1] + crossSize, pos[2])
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, pos[1], pos[2] - crossSize)
        nvgLineTo(ctx, pos[1], pos[2] + crossSize)
        nvgStroke(ctx)
    end
end

--- 7+8. 标题与副标题
local function DrawTitle(ctx, w, h, t, L)
    local titleY = h * 0.30
    local pulse = 1.2 + 0.3 * math.sin(t * 2.0)

    -- 标题辉光
    local glowW = L.titleSize * 5
    local glowH = L.titleSize * 2
    nvgBeginPath(ctx)
    nvgRect(ctx, w / 2 - glowW, titleY - glowH, glowW * 2, glowH * 2)
    local titleGlow = nvgRadialGradient(ctx, w / 2, titleY, 5, glowW * 0.6,
        nvgRGBAf(0.15, 0.55, 1.0, 0.12 * pulse),
        nvgRGBAf(0.1, 0.3, 0.6, 0.0))
    nvgFillPaint(ctx, titleGlow)
    nvgFill(ctx)

    -- 标题文字阴影
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, L.titleSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 30, 60, 120))
    nvgText(ctx, w / 2 + 2, titleY + 2, "边境铁幕", nil)

    -- 标题文字
    nvgFillColor(ctx, nvgRGBA(70, 195, 255, 255))
    nvgText(ctx, w / 2, titleY, "边境铁幕", nil)

    -- 标题下方装饰线
    local lineW = L.isNarrow and 100 or 160
    local lineY = titleY + L.titleSize * 0.65
    local lineAlpha = math.floor(80 + 30 * math.sin(t * 1.8))

    nvgBeginPath(ctx)
    nvgRect(ctx, w / 2 - lineW / 2, lineY, lineW, 1)
    local lineGrad = nvgLinearGradient(ctx,
        w / 2 - lineW / 2, lineY, w / 2 + lineW / 2, lineY,
        nvgRGBA(40, 160, 220, 0),
        nvgRGBA(40, 160, 220, lineAlpha))
    nvgFillPaint(ctx, lineGrad)
    nvgFill(ctx)
    -- 对称的右半
    nvgBeginPath(ctx)
    nvgRect(ctx, w / 2 - lineW / 2, lineY, lineW, 1)
    local lineGrad2 = nvgLinearGradient(ctx,
        w / 2 + lineW / 2, lineY, w / 2 - lineW / 2, lineY,
        nvgRGBA(40, 160, 220, 0),
        nvgRGBA(40, 160, 220, lineAlpha))
    nvgFillPaint(ctx, lineGrad2)
    nvgFill(ctx)

    -- 副标题
    local subY = lineY + (L.isNarrow and 14 or 20)
    local subAlpha = math.floor(130 + 40 * math.sin(t * 1.3 + 0.5))
    nvgFontSize(ctx, L.subtitleSize)
    nvgFillColor(ctx, nvgRGBA(100, 140, 180, subAlpha))
    nvgText(ctx, w / 2, subY, "ARMORED CORE V", nil)
end

--- 9. 菜单按钮
local function DrawButtons(ctx, w, h, t, L)
    local startY = h * 0.50
    local buttons = {}

    -- 构建按钮列表 (与原版逻辑一致)
    table.insert(buttons, {
        label = "选择关卡",
        primary = true,
        action = function()
            ShowLevelSelect({
                onStartLevel = menuCallbacks_.onStartLevel,
                onBack = function()
                    Menu.Show(menuCallbacks_)
                end,
            })
        end,
    })

    if menuCallbacks_.onArmory then
        table.insert(buttons, {
            label = "整备机体",
            action = function()
                Menu.Hide()
                menuCallbacks_.onArmory()
            end,
        })
    end

    if menuCallbacks_.onDebugMode then
        table.insert(buttons, {
            label = "调试模式",
            action = function()
                Menu.Hide()
                menuCallbacks_.onDebugMode()
            end,
        })
    end

    -- 确保 btnGlow_ 数量足够
    while #btnGlow_ < #buttons do
        table.insert(btnGlow_, 0)
    end

    menuButtons_ = {}

    for i, btn in ipairs(buttons) do
        local bx = (w - L.btnWidth) / 2
        local by = startY + (i - 1) * (L.btnHeight + L.gap)
        local glow = btnGlow_[i] or 0

        -- 存储命中区域
        menuButtons_[i] = { x = bx, y = by, w = L.btnWidth, h = L.btnHeight, action = btn.action }

        -- Hover 辉光光晕 (boxGradient bloom)
        if glow > 0.01 then
            local feather = 12 + 12 * glow
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - feather, by - feather,
                L.btnWidth + feather * 2, L.btnHeight + feather * 2)
            local haloGrad = nvgBoxGradient(ctx, bx, by, L.btnWidth, L.btnHeight, 6, feather,
                nvgRGBAf(0.15, 0.55, 1.0, 0.2 * glow),
                nvgRGBAf(0.1, 0.3, 0.6, 0.0))
            nvgFillPaint(ctx, haloGrad)
            nvgFill(ctx)
        end

        -- 按钮背景
        local bgR = btn.primary and (20 + math.floor(35 * glow)) or (12 + math.floor(28 * glow))
        local bgG = btn.primary and (40 + math.floor(50 * glow)) or (18 + math.floor(35 * glow))
        local bgB = btn.primary and (80 + math.floor(50 * glow)) or (40 + math.floor(50 * glow))
        local bgA = math.floor(190 + 50 * glow)

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx, by, L.btnWidth, L.btnHeight, 5)
        nvgFillColor(ctx, nvgRGBA(bgR, bgG, bgB, bgA))
        nvgFill(ctx)

        -- 按钮边框
        local borderA = math.floor(100 + 155 * glow)
        local borderR = btn.primary and (50 + math.floor(60 * glow)) or (35 + math.floor(55 * glow))
        local borderG = btn.primary and (140 + math.floor(80 * glow)) or (80 + math.floor(90 * glow))
        local borderBl = btn.primary and (220 + math.floor(35 * glow)) or (160 + math.floor(60 * glow))

        nvgStrokeColor(ctx, nvgRGBA(borderR, borderG, borderBl, borderA))
        nvgStrokeWidth(ctx, 1.0 + 0.5 * glow)
        nvgStroke(ctx)

        -- 按钮文字
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, L.btnFontSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local textA = math.floor(200 + 55 * glow)
        nvgFillColor(ctx, nvgRGBA(
            btn.primary and (140 + math.floor(115 * glow)) or (150 + math.floor(105 * glow)),
            btn.primary and (210 + math.floor(45 * glow)) or (190 + math.floor(65 * glow)),
            255, textA))
        nvgText(ctx, bx + L.btnWidth / 2, by + L.btnHeight / 2, btn.label, nil)

        -- 主按钮 左侧小三角指示器
        if btn.primary and glow > 0.1 then
            local triX = bx + 14
            local triY = by + L.btnHeight / 2
            local triSize = 4
            local triAlpha = math.floor(255 * glow)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, triX, triY - triSize)
            nvgLineTo(ctx, triX + triSize, triY)
            nvgLineTo(ctx, triX, triY + triSize)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(80, 200, 255, triAlpha))
            nvgFill(ctx)
        end
    end
end

--- 10. 版本号
local function DrawVersionLabel(ctx, w, h, L)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, L.isNarrow and 10 or 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(80, 100, 130, 100))
    nvgText(ctx, w / 2, h - (L.isNarrow and 10 or 16), "v2.0", nil)
end

--- 11. 入场黑幕淡出
local function DrawEntranceFade(ctx, w, h, t)
    if t < 0.8 then
        local alpha = math.floor(255 * (1.0 - t / 0.8))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, h)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, alpha))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- NanoVG 事件处理
-- ============================================================================

--- Update 事件: 时间累积、粒子更新、交互检测
function HandleMenuUpdate(eventType, eventData)
    if not menuActive_ then return end

    local dt = eventData["TimeStep"]:GetFloat()
    menuAnimTime_ = menuAnimTime_ + dt

    local L = GetLayout()
    local w, h = L.screenW, L.screenH

    -- 更新粒子
    UpdateParticles(dt, w, h)

    -- 按钮辉光 lerp
    for i = 1, math.max(#btnGlow_, #menuButtons_) do
        local target = (hoveredBtn_ == i) and 1.0 or 0.0
        local cur = btnGlow_[i] or 0
        btnGlow_[i] = cur + (target - cur) * math.min(1.0, dt * 8.0)
    end

    -- 鼠标 hover 检测
    local dpr = L.dpr
    local mx = input:GetMousePosition().x / dpr
    local my = input:GetMousePosition().y / dpr
    hoveredBtn_ = 0
    for i, btn in ipairs(menuButtons_) do
        if mx >= btn.x and mx <= btn.x + btn.w and
           my >= btn.y and my <= btn.y + btn.h then
            hoveredBtn_ = i
            break
        end
    end

    -- 触屏支持
    if hoveredBtn_ == 0 and input:GetNumTouches() > 0 then
        local touch = input:GetTouch(0)
        local tx = touch.position.x / dpr
        local ty = touch.position.y / dpr
        for i, btn in ipairs(menuButtons_) do
            if tx >= btn.x and tx <= btn.x + btn.w and
               ty >= btn.y and ty <= btn.y + btn.h then
                hoveredBtn_ = i
                break
            end
        end
    end

    -- 点击检测
    local clicked = false
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        clicked = true
    end
    -- 触屏点击
    if not clicked and input:GetNumTouches() > 0 then
        local touch = input:GetTouch(0)
        if touch.pressure > 0 then
            -- 检查是否为新触摸（delta 接近触摸位置）
            local tx = touch.position.x / dpr
            local ty = touch.position.y / dpr
            for i, btn in ipairs(menuButtons_) do
                if tx >= btn.x and tx <= btn.x + btn.w and
                   ty >= btn.y and ty <= btn.y + btn.h then
                    if touch.delta.x == 0 and touch.delta.y == 0 then
                        hoveredBtn_ = i
                        clicked = true
                    end
                    break
                end
            end
        end
    end

    if clicked and hoveredBtn_ > 0 then
        local btn = menuButtons_[hoveredBtn_]
        if btn and btn.action then
            btn.action()
        end
    end
end

--- NanoVGRender 事件: 绘制所有层
function HandleMenuNanoVGRender(eventType, eventData)
    if not menuActive_ or not menuVg_ then return end

    local L = GetLayout()
    local w, h = L.screenW, L.screenH

    nvgBeginFrame(menuVg_, w, h, L.dpr)

    local t = menuAnimTime_

    DrawBackground(menuVg_, w, h)
    DrawHexGrid(menuVg_, w, h, t)
    DrawParticles(menuVg_)
    DrawScanLines(menuVg_, w, h, t)
    DrawVignette(menuVg_, w, h)
    DrawCornerFrames(menuVg_, w, h, t)
    DrawTitle(menuVg_, w, h, t, L)
    DrawButtons(menuVg_, w, h, t, L)
    DrawVersionLabel(menuVg_, w, h, L)
    DrawEntranceFade(menuVg_, w, h, t)

    nvgEndFrame(menuVg_)
end

-- ============================================================================
-- UI 初始化（给关卡选择和军械库用）
-- ============================================================================

local function EnsureUIInit()
    if initialized_ then return end
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
    initialized_ = true
end

-- ============================================================================
-- 关卡选择页面（保持 UI 系统，不变）
-- ============================================================================

local levelSelectCallbacks_ = nil

---@param callbacks table { onStartLevel: function, onBack: function }
ShowLevelSelect = function(callbacks)
    EnsureUIInit()
    Menu.Hide()

    levelSelectCallbacks_ = callbacks
    local L = GetLayout()

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    local levelCards = {}
    -- 关卡编号标签 + 主题色（无 emoji）
    local tags = { "01", "02", "03", "04" }
    local colors = {
        { 40, 180, 120 },   -- 绿 - 靶场
        { 100, 160, 255 },  -- 蓝 - 对战
        { 255, 100, 60 },   -- 红 - 叛乱
        { 200, 50, 220 },   -- 紫 - 精英
    }

    for i, level in ipairs(CONFIG.Levels) do
        local c = colors[i] or { 150, 150, 150 }
        local tag = tags[i] or string.format("%02d", i)

        table.insert(levelCards, UI.Panel {
            width = L.cardWidth,
            paddingLeft = L.cardPadding,
            paddingRight = L.cardPadding,
            paddingTop = L.cardPadding + 30,
            paddingBottom = L.cardPadding + 30,
            backgroundColor = { 16, 22, 36, 240 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { c[1], c[2], c[3], 80 },
            flexDirection = "column",
            alignItems = "center",
            hoverBackgroundColor = { c[1], c[2], c[3], 40 },
            hoverBorderColor = { c[1], c[2], c[3], 200 },
            children = {
                -- 编号标签（替代 emoji）
                UI.Panel {
                    width = L.isNarrow and 36 or 48,
                    height = L.isNarrow and 36 or 48,
                    borderRadius = L.isNarrow and 18 or 24,
                    backgroundColor = { c[1], c[2], c[3], 35 },
                    borderWidth = 1,
                    borderColor = { c[1], c[2], c[3], 100 },
                    justifyContent = "center",
                    alignItems = "center",
                    marginBottom = L.isNarrow and 6 or 10,
                    children = {
                        UI.Label {
                            text = tag,
                            fontSize = L.isNarrow and 13 or 16,
                            fontWeight = "bold",
                            fontColor = { c[1], c[2], c[3], 230 },
                            textAlign = "center",
                        },
                    },
                },
                -- 关卡名
                UI.Label {
                    text = level.name,
                    fontSize = L.cardNameSize,
                    fontWeight = "bold",
                    fontColor = { c[1], c[2], c[3], 255 },
                    textAlign = "center",
                    marginBottom = L.isNarrow and 3 or 6,
                },
                -- 描述
                UI.Label {
                    text = level.desc,
                    fontSize = L.cardDescSize,
                    fontColor = { 140, 160, 190, 170 },
                    textAlign = "center",
                    marginBottom = L.isNarrow and 8 or 14,
                },
                -- 分隔线
                UI.Panel {
                    width = "70%",
                    height = 1,
                    backgroundColor = { c[1], c[2], c[3], 50 },
                    marginBottom = L.isNarrow and 8 or 14,
                },
                -- 出击按钮
                UI.Button {
                    text = "出击",
                    variant = "primary",
                    width = L.cardBtnWidth,
                    height = L.cardBtnHeight,
                    fontSize = L.cardBtnFontSize,
                    fontWeight = "bold",
                    backgroundColor = { c[1], c[2], c[3], 180 },
                    hoverBackgroundColor = { c[1], c[2], c[3], 240 },
                    pressedBackgroundColor = { math.max(0, c[1] - 40), math.max(0, c[2] - 40), math.max(0, c[3] - 40), 255 },
                    borderWidth = 1,
                    borderColor = { c[1], c[2], c[3], 100 },
                    onClick = function()
                        Menu.Hide()
                        if callbacks.onStartLevel then
                            callbacks.onStartLevel(i)
                        end
                    end,
                },
            },
        })
    end

    -- 返回按钮
    local backBtn = UI.Button {
        text = "< 返回",
        width = L.isNarrow and 80 or 100,
        height = L.isNarrow and 32 or 38,
        fontSize = L.isNarrow and 12 or 14,
        backgroundColor = { 30, 35, 55, 200 },
        textColor = { 160, 180, 220, 220 },
        hoverBackgroundColor = { 50, 60, 90, 230 },
        pressedBackgroundColor = { 25, 30, 50, 250 },
        borderWidth = 1,
        borderColor = { 60, 100, 160, 120 },
        onClick = function()
            if callbacks.onBack then
                callbacks.onBack()
            end
        end,
    }

    rootWidget_ = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = { 10, 14, 28, 250 },
            to = { 4, 6, 14, 255 },
        },
        children = {
            -- 标题
            UI.Label {
                text = "-- 选择关卡 --",
                fontSize = L.levelTitleSize,
                fontWeight = "bold",
                fontColor = { 80, 190, 255, 240 },
                textAlign = "center",
                marginBottom = L.isNarrow and 4 or 8,
            },
            -- 副标题
            UI.Label {
                text = "SELECT MISSION",
                fontSize = L.isNarrow and 10 or 12,
                fontColor = { 100, 130, 170, 120 },
                textAlign = "center",
                marginBottom = L.isNarrow and 14 or 24,
            },
            -- 卡片容器
            UI.Panel {
                flexDirection = L.cardDir,
                justifyContent = "center",
                alignItems = L.isPortrait and "center" or "stretch",
                gap = L.cardGap,
                marginBottom = L.isNarrow and 16 or 30,
                children = levelCards,
            },
            backBtn,
        },
    }

    UI.SetRoot(rootWidget_)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 显示主菜单 (NanoVG 动画版)
---@param callbacks table { onStartLevel: function, onDebugMode: function|nil, onArmory: function|nil }
function Menu.Show(callbacks)
    EnsureUIInit()
    Menu.Hide()

    menuCallbacks_ = callbacks
    menuAnimTime_ = 0
    hoveredBtn_ = 0
    btnGlow_ = {}
    menuButtons_ = {}

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    -- 创建 NanoVG 上下文
    menuVg_ = nvgCreate(1)
    if not menuVg_ then
        print("ERROR: Menu failed to create NanoVG context")
        return
    end
    menuFont_ = nvgCreateFont(menuVg_, "sans", "Fonts/MiSans-Regular.ttf")
    menuActive_ = true

    -- 初始化粒子
    local L = GetLayout()
    local pCount = L.isNarrow and PARTICLE_COUNT_NARROW or PARTICLE_COUNT_NORMAL
    InitParticles(L.screenW, L.screenH, pCount)

    -- 订阅事件
    SubscribeToEvent("Update", "HandleMenuUpdate")
    SubscribeToEvent(menuVg_, "NanoVGRender", "HandleMenuNanoVGRender")
end

--- 隐藏主菜单
function Menu.Hide()
    -- 清理 UI 控件 (关卡选择页面)
    if rootWidget_ then
        rootWidget_:Destroy()
        rootWidget_ = nil
    end

    -- 清理 NanoVG 主菜单
    if menuActive_ then
        menuActive_ = false
        UnsubscribeFromEvent("Update")
        if menuVg_ then
            nvgDelete(menuVg_)
            menuVg_ = nil
        end
        menuFont_ = -1
        menuAnimTime_ = 0
        hoveredBtn_ = 0
        btnGlow_ = {}
        menuButtons_ = {}
        menuParticles_ = {}
    end
end

--- 获取 UI 模块引用（供其他模块复用已初始化的 UI）
function Menu.GetUI()
    EnsureUIInit()
    return UI
end

--- 清理
function Menu.Shutdown()
    Menu.Hide()
    if initialized_ then
        UI.Shutdown()
        initialized_ = false
    end
end

return Menu
