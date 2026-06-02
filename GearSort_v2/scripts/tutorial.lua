-- tutorial.lua
-- 第一关教程引导动画
-- 循环播放「手指出现→点击插板1→移动→点击插板2→消失」
-- 直到玩家退出关卡为止

local Renderer = require("renderer")

local Tutorial = {}

-- ---------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------
local FINGER_PATH = "image/tutorial_finger_20260601091927.png"

-- 动画时间轴（秒）
local T_APPEAR     = 0.3   -- 手指淡入时长
local T_CLICK1     = 0.25  -- 第一次按下（缩放）时长
local T_LIFT1      = 0.15  -- 第一次抬起时长
local T_MOVE       = 0.55  -- 移动到第二个插板时长
local T_CLICK2     = 0.25  -- 第二次按下时长
local T_LIFT2      = 0.15  -- 第二次抬起时长
local T_DISAPPEAR  = 0.35  -- 手指淡出时长
local T_PAUSE      = 0.6   -- 消失后暂停，再循环

local TOTAL_DUR = T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE
                  + T_CLICK2 + T_LIFT2 + T_DISAPPEAR + T_PAUSE

-- 手指图片尺寸（渲染大小，可自由调整）
local FINGER_W = 216
local FINGER_H = 216

-- 点击时手指缩小比例
local CLICK_SCALE = 0.82

-- ---------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------
---@type number|nil
local fingerImg_  = nil   -- NanoVG 图片句柄
local active_     = false -- 是否激活教程动画
local timer_      = 0     -- 当前动画时间（秒）
local nvgCtx_     = nil   -- NanoVG 上下文引用

-- ---------------------------------------------------------------
-- Tutorial.Init：在 Start() 阶段调用，传入 NanoVG ctx
-- ---------------------------------------------------------------
function Tutorial.Init(ctx)
    nvgCtx_ = ctx
    fingerImg_ = nvgCreateImage(ctx, FINGER_PATH, 0)
    if fingerImg_ and fingerImg_ > 0 then
        print("[Tutorial] 手指图片加载成功 handle=" .. fingerImg_)
    else
        fingerImg_ = nil
        print("[Tutorial] WARN: 手指图片未找到，教程将以程序化手形替代")
    end
end

-- ---------------------------------------------------------------
-- Tutorial.Start / Stop
-- ---------------------------------------------------------------
function Tutorial.Start()
    active_ = true
    timer_  = 0
    print("[Tutorial] 教程动画启动")
end

function Tutorial.Stop()
    active_ = false
    print("[Tutorial] 教程动画已停止")
end

function Tutorial.IsActive()
    return active_
end

-- ---------------------------------------------------------------
-- Tutorial.Update：每帧调用，dt 为帧间隔
-- ---------------------------------------------------------------
function Tutorial.Update(dt)
    if not active_ then return end
    timer_ = timer_ + dt
    -- 到达总时长后循环
    if timer_ >= TOTAL_DUR then
        timer_ = timer_ - TOTAL_DUR
        if timer_ < 0 then timer_ = 0 end
    end
end

-- ---------------------------------------------------------------
-- Tutorial.Draw：在 NanoVGRender 事件中调用，绘制手指动画
-- ---------------------------------------------------------------
function Tutorial.Draw(ctx)
    if not active_ then return end
    if not nvgCtx_ then return end

    -- 获取两个插板的中心坐标
    local x1, y1 = Renderer.GetPegCenter(1)   -- 插板1（3个齿轮）
    local x2, y2 = Renderer.GetPegCenter(2)   -- 插板2（1个齿轮）

    -- 手指图标偏移：让手指尖对准插板中心，图片偏右上（食指在右下角）
    local ox = -FINGER_W * 0.15
    local oy = -FINGER_H * 0.05

    local t = timer_

    -- ── 阶段1：手指淡入（在插板1位置出现）──────────────────────
    local alpha   = 255   -- 整体透明度
    local scale   = 1.0   -- 点击缩放
    local cx, cy  = x1, y1

    if t < T_APPEAR then
        -- 淡入
        local p = t / T_APPEAR
        alpha = math.floor(p * 255)
        cx, cy = x1, y1

    -- ── 阶段2：第一次点击（按下）────────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 then
        local p = (t - T_APPEAR) / T_CLICK1
        -- 按下时缩小
        scale = 1.0 - (1.0 - CLICK_SCALE) * math.sin(p * math.pi)
        cx, cy = x1, y1

    -- ── 阶段3：第一次点击（抬起）────────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 + T_LIFT1 then
        cx, cy = x1, y1

    -- ── 阶段4：从插板1移动到插板2 ───────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE then
        local p = (t - T_APPEAR - T_CLICK1 - T_LIFT1) / T_MOVE
        -- ease-in-out
        local ease = p < 0.5 and (2 * p * p) or (1 - (-2 * p + 2)^2 / 2)
        -- 轻微弧线：中途抬高
        local arc = math.sin(ease * math.pi) * 24
        cx = x1 + (x2 - x1) * ease
        cy = y1 + (y2 - y1) * ease - arc

    -- ── 阶段5：第二次点击（按下）────────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE + T_CLICK2 then
        local p = (t - T_APPEAR - T_CLICK1 - T_LIFT1 - T_MOVE) / T_CLICK2
        scale = 1.0 - (1.0 - CLICK_SCALE) * math.sin(p * math.pi)
        cx, cy = x2, y2

    -- ── 阶段6：第二次点击（抬起）────────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE + T_CLICK2 + T_LIFT2 then
        cx, cy = x2, y2

    -- ── 阶段7：手指淡出 ──────────────────────────────────────────
    elseif t < T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE + T_CLICK2 + T_LIFT2 + T_DISAPPEAR then
        local p = (t - T_APPEAR - T_CLICK1 - T_LIFT1 - T_MOVE - T_CLICK2 - T_LIFT2) / T_DISAPPEAR
        alpha = math.floor((1.0 - p) * 255)
        cx, cy = x2, y2

    -- ── 阶段8：暂停（手指不可见）────────────────────────────────
    else
        alpha = 0
        cx, cy = x2, y2
    end

    if alpha <= 0 then return end

    -- 绘制手指
    local drawW = FINGER_W * scale
    local drawH = FINGER_H * scale
    local drawX = cx + ox - drawW / 2
    local drawY = cy + oy - drawH / 2

    if fingerImg_ then
        -- 使用图片
        local paint = nvgImagePattern(ctx, drawX, drawY, drawW, drawH, 0, fingerImg_, alpha / 255.0)
        nvgBeginPath(ctx)
        nvgRect(ctx, drawX, drawY, drawW, drawH)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
    else
        -- 回退：程序化手形（简单圆形）
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx + ox, cy + oy, 22 * scale)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, alpha))
        nvgFill(ctx)
        -- 食指
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, cx + ox - 8 * scale, cy + oy - 36 * scale, 16 * scale, 30 * scale, 8 * scale)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, alpha))
        nvgFill(ctx)
    end

    -- 点击波纹（仅在按下阶段绘制）
    local inClick1 = (t >= T_APPEAR and t < T_APPEAR + T_CLICK1)
    local inClick2 = (t >= T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE
                      and t < T_APPEAR + T_CLICK1 + T_LIFT1 + T_MOVE + T_CLICK2)

    if inClick1 or inClick2 then
        local clickProg
        if inClick1 then
            clickProg = (t - T_APPEAR) / T_CLICK1
        else
            clickProg = (t - T_APPEAR - T_CLICK1 - T_LIFT1 - T_MOVE) / T_CLICK2
        end
        local rippleR = 54 + clickProg * 78
        local rippleA = math.floor((1.0 - clickProg) * 160)
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, rippleR)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 200, rippleA))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
    end
end

return Tutorial
