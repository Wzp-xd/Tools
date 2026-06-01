-- ui_anim.lua
-- UI 动画引擎：缓动函数 + Tween 管理 + 通用动画工具
-- 由 main.lua HandleUpdate 每帧调用 UIAnim.Update(dt) 驱动

local SoundManager = require("sound_manager")

local UIAnim = {}

-- ===============================================================
-- 一、缓动函数
-- ===============================================================

UIAnim.Easing = {}

--- easeOutCubic: 平滑减速
function UIAnim.Easing.easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

--- easeInCubic: 加速
function UIAnim.Easing.easeInCubic(t)
    return t * t * t
end

--- easeOutQuart: 更强减速
function UIAnim.Easing.easeOutQuart(t)
    local u = 1 - t
    return 1 - u * u * u * u
end

--- easeInQuart: 更强加速
function UIAnim.Easing.easeInQuart(t)
    return t * t * t * t
end

--- easeOutBack: 弹过头再回
---@param overshoot number|nil 默认 1.70158
function UIAnim.Easing.easeOutBack(t, overshoot)
    local s = overshoot or 1.70158
    local u = t - 1
    return 1 + (s + 1) * u * u * u + s * u * u
end

--- easeInBack: 后拉再弹出
function UIAnim.Easing.easeInBack(t, overshoot)
    local s = overshoot or 1.70158
    return (s + 1) * t * t * t - s * t * t
end

--- easeOutElastic: 弹簧振荡
function UIAnim.Easing.easeOutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return math.pow(2, -10 * t) * math.sin((t - 0.075) * 2 * math.pi / 0.3) + 1
end

--- easeOutBounce: 落地弹跳
function UIAnim.Easing.easeOutBounce(t)
    if t < 1 / 2.75 then
        return 7.5625 * t * t
    elseif t < 2 / 2.75 then
        t = t - 1.5 / 2.75
        return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then
        t = t - 2.25 / 2.75
        return 7.5625 * t * t + 0.9375
    else
        t = t - 2.625 / 2.75
        return 7.5625 * t * t + 0.984375
    end
end

--- easeInOutSine: 正弦缓入缓出（适合呼吸循环）
function UIAnim.Easing.easeInOutSine(t)
    return -(math.cos(math.pi * t) - 1) * 0.5
end

--- linear: 线性
function UIAnim.Easing.linear(t)
    return t
end

--- 衰减正弦波（Logo 抖动专用）
--- amplitude: 初始振幅度数, freq: Hz, decay: 衰减系数
function UIAnim.Easing.dampedSine(t, amplitude, freq, decay)
    amplitude = amplitude or 4
    freq = freq or 6
    decay = decay or 5
    return amplitude * math.sin(freq * math.pi * t) * math.exp(-decay * t)
end

-- ===============================================================
-- 二、时间常量（秒）
-- ===============================================================

UIAnim.Duration = {
    BTN_PRESS       = 0.080,
    BTN_RELEASE     = 0.150,
    TAB_SLIDE       = 0.320,
    POPUP_IN        = 0.300,
    POPUP_OUT       = 0.200,
    LOGO_SCALE      = 0.600,
    LOGO_FADE       = 0.400,
    LOGO_SHAKE      = 0.500,
    LEVEL_TRANS     = 0.500,
    OVERLAY_FADE    = 0.250,
    STAGGER_ITEM    = 0.200,
    STAGGER_DELAY   = 0.040,
    NUMBER_BOUNCE   = 0.250,
    TOAST_IN        = 0.250,
    TOAST_OUT       = 0.200,
    TOAST_STAY      = 2.000,
}

-- ===============================================================
-- 三、Tween 引擎
-- ===============================================================

---@class Tween
---@field id number
---@field elapsed number
---@field delay number
---@field duration number
---@field easing function
---@field easingArg number|nil
---@field from table
---@field to table
---@field current table
---@field onUpdate function|nil
---@field onComplete function|nil
---@field target table|nil  -- UI 节点（自动 SetStyle）
---@field cancelled boolean
---@field looping boolean|nil
---@field yoyo boolean|nil

local tweens_ = {}
local nextId_ = 1

--- 插值计算
local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 创建 Tween
---@param opts table { target?, from, to, duration, delay?, easing?, easingArg?, onUpdate?, onComplete?, looping?, yoyo? }
---@return number id (用于 cancel)
function UIAnim.Tween(opts)
    local id = nextId_
    nextId_ = nextId_ + 1

    local from = opts.from or {}
    local to   = opts.to or {}
    local current = {}
    for k, v in pairs(from) do
        current[k] = v
    end

    tweens_[id] = {
        id        = id,
        elapsed   = 0,
        delay     = opts.delay or 0,
        duration  = opts.duration or 0.3,
        easing    = opts.easing or UIAnim.Easing.easeOutCubic,
        easingArg = opts.easingArg,
        from      = from,
        to        = to,
        current   = current,
        onUpdate  = opts.onUpdate,
        onComplete = opts.onComplete,
        target    = opts.target,
        cancelled = false,
        looping   = opts.looping or false,
        yoyo      = opts.yoyo or false,
        direction = 1,  -- 1=forward, -1=reverse(yoyo)
    }

    return id
end

--- 取消 Tween
function UIAnim.Cancel(id)
    if tweens_[id] then
        tweens_[id].cancelled = true
    end
end

--- 取消所有属于某个 target 的 Tween
function UIAnim.CancelAll(target)
    if not target then return end
    for id, tw in pairs(tweens_) do
        if tw.target == target then
            tw.cancelled = true
        end
    end
end

--- 快进某 Tween 到终态
function UIAnim.FastForward(id)
    local tw = tweens_[id]
    if not tw or tw.cancelled then return end
    -- 直接设终态
    for k, v in pairs(tw.to) do
        tw.current[k] = v
    end
    if tw.target and tw.target.SetStyle then
        tw.target:SetStyle(tw.current)
    end
    if tw.onUpdate then tw.onUpdate(tw.current, 1.0) end
    if tw.onComplete then tw.onComplete() end
    tw.cancelled = true
end

--- 快进某 target 所有 Tween 到终态
function UIAnim.FastForwardAll(target)
    if not target then return end
    for id, tw in pairs(tweens_) do
        if tw.target == target and not tw.cancelled then
            UIAnim.FastForward(id)
        end
    end
end

--- 检查某 target 是否有正在播放的动画
function UIAnim.IsAnimating(target)
    if not target then return false end
    for _, tw in pairs(tweens_) do
        if tw.target == target and not tw.cancelled then
            return true
        end
    end
    return false
end

--- 每帧驱动（由 main.lua HandleUpdate 调用）
function UIAnim.Update(dt)
    local toRemove = {}
    for id, tw in pairs(tweens_) do
        if tw.cancelled then
            toRemove[#toRemove + 1] = id
            goto continue
        end

        tw.elapsed = tw.elapsed + dt

        -- 延迟等待
        if tw.elapsed < tw.delay then
            goto continue
        end

        local t = (tw.elapsed - tw.delay) / tw.duration
        if t > 1 then t = 1 end

        -- yoyo 反向
        local easedT
        if tw.direction == -1 then
            easedT = tw.easing(1 - t, tw.easingArg)
        else
            easedT = tw.easing(t, tw.easingArg)
        end

        -- 插值所有属性
        for k, fromVal in pairs(tw.from) do
            local toVal = tw.to[k]
            if toVal ~= nil then
                tw.current[k] = lerp(fromVal, toVal, easedT)
            end
        end

        -- 自动 SetStyle
        if tw.target and tw.target.SetStyle then
            tw.target:SetStyle(tw.current)
        end

        -- 回调
        if tw.onUpdate then
            tw.onUpdate(tw.current, easedT)
        end

        -- 完成判定
        if t >= 1 then
            if tw.looping then
                if tw.yoyo then
                    tw.direction = -tw.direction
                end
                tw.elapsed = tw.delay
            else
                if tw.onComplete then tw.onComplete() end
                toRemove[#toRemove + 1] = id
            end
        end

        ::continue::
    end

    -- 清理已完成/已取消的 Tween
    for _, id in ipairs(toRemove) do
        tweens_[id] = nil
    end
end

-- ===============================================================
-- 四、便捷动画工具
-- ===============================================================

--- 淡入节点
function UIAnim.FadeIn(node, duration, opts)
    opts = opts or {}
    UIAnim.CancelAll(node)
    node:SetStyle({ opacity = 0 })
    node:SetVisible(true)
    return UIAnim.Tween({
        target   = node,
        from     = { opacity = 0 },
        to       = { opacity = opts.toOpacity or 1 },
        duration = duration or UIAnim.Duration.OVERLAY_FADE,
        delay    = opts.delay or 0,
        easing   = opts.easing or UIAnim.Easing.easeOutCubic,
        onComplete = opts.onComplete,
    })
end

--- 淡出节点（完成后隐藏）
function UIAnim.FadeOut(node, duration, opts)
    opts = opts or {}
    UIAnim.CancelAll(node)
    return UIAnim.Tween({
        target   = node,
        from     = { opacity = 1 },
        to       = { opacity = 0 },
        duration = duration or UIAnim.Duration.OVERLAY_FADE,
        delay    = opts.delay or 0,
        easing   = opts.easing or UIAnim.Easing.easeInCubic,
        onComplete = function()
            node:SetVisible(false)
            node:SetStyle({ opacity = 1 })  -- 复位供下次使用
            if opts.onComplete then opts.onComplete() end
        end,
    })
end

--- 弹窗弹入（从下方弹入 + 缩放 + 淡入）
---@param card table UI 节点（弹窗卡片）
---@param overlay table|nil 遮罩节点
---@param opts table|nil { overshoot?, onComplete? }
function UIAnim.PopupIn(card, overlay, opts)
    opts = opts or {}
    local screenH = (graphics:GetHeight() or 800) / (graphics:GetDPR() or 1)

    SoundManager.Play("whoosh", 0.4)

    -- 遮罩淡入
    if overlay then
        UIAnim.CancelAll(overlay)
        overlay:SetVisible(true)
        overlay:SetStyle({ opacity = 0 })
        UIAnim.Tween({
            target   = overlay,
            from     = { opacity = 0 },
            to       = { opacity = 1 },
            duration = UIAnim.Duration.OVERLAY_FADE,
            easing   = UIAnim.Easing.easeOutCubic,
        })
    end

    -- 卡片弹入
    UIAnim.CancelAll(card)
    card:SetVisible(true)
    local offsetY = screenH * 0.20
    card:SetStyle({ opacity = 0, top = offsetY })
    UIAnim.Tween({
        target   = card,
        from     = { opacity = 0, top = offsetY },
        to       = { opacity = 1, top = 0 },
        duration = UIAnim.Duration.POPUP_IN,
        delay    = 0.05,
        easing   = UIAnim.Easing.easeOutBack,
        easingArg = opts.overshoot or 1.8,
        onComplete = opts.onComplete,
    })
end

--- 弹窗弹出（向上退出 + 缩小 + 淡出）
---@param card table UI 节点
---@param overlay table|nil 遮罩节点
---@param opts table|nil { onComplete? }
function UIAnim.PopupOut(card, overlay, opts)
    opts = opts or {}
    local screenH = (graphics:GetHeight() or 800) / (graphics:GetDPR() or 1)
    local offsetY = -screenH * 0.10

    UIAnim.CancelAll(card)
    UIAnim.Tween({
        target   = card,
        from     = { opacity = 1, top = 0 },
        to       = { opacity = 0, top = offsetY },
        duration = UIAnim.Duration.POPUP_OUT,
        easing   = UIAnim.Easing.easeInCubic,
        onComplete = function()
            card:SetVisible(false)
            card:SetStyle({ opacity = 1, top = 0 })
            if opts.onComplete then opts.onComplete() end
        end,
    })

    -- 遮罩延迟淡出
    if overlay then
        UIAnim.CancelAll(overlay)
        UIAnim.Tween({
            target   = overlay,
            from     = { opacity = 1 },
            to       = { opacity = 0 },
            duration = UIAnim.Duration.POPUP_OUT,
            delay    = 0.10,
            easing   = UIAnim.Easing.easeInCubic,
            onComplete = function()
                overlay:SetVisible(false)
                overlay:SetStyle({ opacity = 1 })
            end,
        })
    end
end

--- 失败弹窗（从上方落下 + 弹跳）
function UIAnim.PopupBounceIn(card, overlay, opts)
    opts = opts or {}
    local screenH = (graphics:GetHeight() or 800) / (graphics:GetDPR() or 1)

    SoundManager.Play("pop", 0.5)

    -- 遮罩淡入
    if overlay then
        UIAnim.CancelAll(overlay)
        overlay:SetVisible(true)
        overlay:SetStyle({ opacity = 0 })
        UIAnim.Tween({
            target   = overlay,
            from     = { opacity = 0 },
            to       = { opacity = 1 },
            duration = UIAnim.Duration.OVERLAY_FADE,
            easing   = UIAnim.Easing.easeOutCubic,
        })
    end

    -- 卡片从顶部落下
    UIAnim.CancelAll(card)
    card:SetVisible(true)
    local startY = -screenH * 0.15
    card:SetStyle({ opacity = 0, top = startY })
    UIAnim.Tween({
        target   = card,
        from     = { opacity = 0, top = startY },
        to       = { opacity = 1, top = 0 },
        duration = 0.400,
        easing   = UIAnim.Easing.easeOutBounce,
        onComplete = opts.onComplete,
    })
end

--- Stagger 动画：子元素依次淡入
---@param nodes table[] UI 节点数组
---@param opts table|nil { delay?, interval?, duration?, easing?, translateY?, onComplete? }
function UIAnim.Stagger(nodes, opts)
    opts = opts or {}
    local interval   = opts.interval or UIAnim.Duration.STAGGER_DELAY
    local duration   = opts.duration or UIAnim.Duration.STAGGER_ITEM
    local translateY = opts.translateY or 20
    local baseDelay  = opts.delay or 0
    local lastId     = nil

    for i, node in ipairs(nodes) do
        UIAnim.CancelAll(node)
        node:SetStyle({ opacity = 0 })
        node:SetVisible(true)
        local isLast = (i == #nodes)
        lastId = UIAnim.Tween({
            target   = node,
            from     = { opacity = 0 },
            to       = { opacity = 1 },
            duration = duration,
            delay    = baseDelay + (i - 1) * interval,
            easing   = opts.easing or UIAnim.Easing.easeOutCubic,
            onComplete = isLast and opts.onComplete or nil,
        })
    end

    return lastId
end

--- 数字跳动动画
---@param node table UI Label 节点
---@param oldVal number
---@param newVal number
---@param opts table|nil { duration?, onComplete? }
function UIAnim.NumberBounce(node, oldVal, newVal, opts)
    opts = opts or {}
    UIAnim.CancelAll(node)

    local duration = opts.duration or UIAnim.Duration.NUMBER_BOUNCE
    local isIncrease = newVal > oldVal

    -- 仅用 opacity 动画模拟弹跳
    UIAnim.Tween({
        target   = node,
        from     = { opacity = 0.5 },
        to       = { opacity = 1 },
        duration = duration,
        easing   = UIAnim.Easing.easeOutCubic,
        onComplete = opts.onComplete,
    })
end

--- Toast 滑入/驻留/滑出
---@param node table Toast UI 节点
---@param opts table|nil { stayTime?, onDone? }
function UIAnim.Toast(node, opts)
    opts = opts or {}
    local stayTime = opts.stayTime or UIAnim.Duration.TOAST_STAY

    UIAnim.CancelAll(node)
    node:SetVisible(true)
    node:SetStyle({ opacity = 0 })

    -- 滑入
    UIAnim.Tween({
        target   = node,
        from     = { opacity = 0 },
        to       = { opacity = 1 },
        duration = UIAnim.Duration.TOAST_IN,
        easing   = UIAnim.Easing.easeOutCubic,
        onComplete = function()
            -- 驻留后滑出
            UIAnim.Tween({
                target   = node,
                from     = { opacity = 1 },
                to       = { opacity = 0 },
                duration = UIAnim.Duration.TOAST_OUT,
                delay    = stayTime,
                easing   = UIAnim.Easing.easeInCubic,
                onComplete = function()
                    node:SetVisible(false)
                    node:SetStyle({ opacity = 1 })
                    if opts.onDone then opts.onDone() end
                end,
            })
        end,
    })
end

--- Logo 入场动画（缩放+淡入 → 衰减抖动 → 呼吸循环）
---@param node table Logo UI 节点
---@param opts table|nil { firstTime?, onSettled? }
function UIAnim.LogoEntrance(node, opts)
    opts = opts or {}
    UIAnim.CancelAll(node)
    node:SetVisible(true)

    local duration   = opts.duration   or 1.0   -- 动画总时长（默认 1 秒）
    local startScale = opts.startScale or 1.6   -- 初始放大倍率

    -- 初始状态：放大 + 透明
    node:SetStyle({ opacity = 0, scale = startScale })

    -- 缩放 + 淡入合并为一个 Tween，避免多 Tween 分别 SetStyle 导致闪烁
    UIAnim.Tween({
        target   = node,
        from     = { scale = startScale, opacity = 0 },
        to       = { scale = 1.0, opacity = 1.0 },
        duration = duration,
        easing   = UIAnim.Easing.easeOutBack,
        onComplete = function()
            -- 入场结束后开始呼吸循环
            if opts.onSettled then opts.onSettled() end
            UIAnim.LogoBreathing(node)
        end,
    })
end

--- Logo 呼吸循环
function UIAnim.LogoBreathing(node)
    UIAnim.Tween({
        target   = node,
        from     = { opacity = 0.95 },
        to       = { opacity = 1.0 },
        duration = 3.0,
        easing   = UIAnim.Easing.easeInOutSine,
        looping  = true,
        yoyo     = true,
    })
end

--- 按钮按下反馈
---@param node table 按钮节点
function UIAnim.ButtonPress(node)
    UIAnim.CancelAll(node)
    UIAnim.Tween({
        target   = node,
        from     = { opacity = 1.0 },
        to       = { opacity = 0.85 },
        duration = UIAnim.Duration.BTN_PRESS,
        easing   = UIAnim.Easing.easeInCubic,
    })
end

--- 按钮弹起反馈
---@param node table 按钮节点
---@param opts table|nil { onComplete? }
function UIAnim.ButtonRelease(node, opts)
    opts = opts or {}
    UIAnim.CancelAll(node)
    UIAnim.Tween({
        target   = node,
        from     = { opacity = 0.85 },
        to       = { opacity = 1.0 },
        duration = UIAnim.Duration.BTN_RELEASE,
        easing   = UIAnim.Easing.easeOutBack,
        easingArg = 1.5,
        onComplete = opts.onComplete,
    })
end

-- ===============================================================
-- 五、NanoVG 过渡效果（关卡切换）
-- ===============================================================

local transition_ = {
    active   = false,
    phase    = "none",    -- "close" | "open"
    elapsed  = 0,
    duration = 0.4,
    onMidpoint = nil,     -- 遮挡完毕时回调（切换场景）
    onDone   = nil,       -- 全部完成回调
    -- 圆形擦除参数
    centerX  = 0,
    centerY  = 0,
    maxRadius = 0,
}

--- 启动关卡过渡
---@param opts table { centerX?, centerY?, onMidpoint, onDone? }
function UIAnim.StartTransition(opts)
    local dpr = graphics:GetDPR() or 1
    local w = graphics:GetWidth() / dpr   -- 逻辑坐标
    local h = graphics:GetHeight() / dpr  -- 逻辑坐标

    transition_.active   = true
    transition_.phase    = "close"
    transition_.elapsed  = 0
    transition_.duration = UIAnim.Duration.LEVEL_TRANS
    transition_.onMidpoint = opts.onMidpoint
    transition_.onDone   = opts.onDone
    transition_.centerX  = opts.centerX or (w * 0.5)
    transition_.centerY  = opts.centerY or (h * 0.5)
    transition_.maxRadius = math.sqrt(w * w + h * h)
end

--- 每帧更新过渡状态（由 main.lua 调用）
function UIAnim.UpdateTransition(dt)
    if not transition_.active then return end
    transition_.elapsed = transition_.elapsed + dt

    if transition_.phase == "close" then
        if transition_.elapsed >= transition_.duration then
            -- 中点：场景切换
            if transition_.onMidpoint then
                transition_.onMidpoint()
                transition_.onMidpoint = nil
            end
            transition_.phase = "open"
            transition_.elapsed = 0
            transition_.duration = 0.500
        end
    elseif transition_.phase == "open" then
        if transition_.elapsed >= transition_.duration then
            transition_.active = false
            transition_.phase = "none"
            if transition_.onDone then
                transition_.onDone()
                transition_.onDone = nil
            end
        end
    end
end

--- NanoVG 绘制过渡效果（在 NanoVGRender 事件中调用）
---@param vg userdata NanoVG 上下文
---@param w number 画布宽度（NanoVG 坐标系下）
---@param h number 画布高度（NanoVG 坐标系下）
function UIAnim.DrawTransition(vg, w, h)
    if not transition_.active then return end

    local t = transition_.elapsed / transition_.duration
    if t > 1 then t = 1 end

    -- 始终使用传入的画布尺寸计算中心和半径，避免坐标系不匹配
    local cx = w * 0.5
    local cy = h * 0.5
    local maxR = math.sqrt(w * w + h * h)

    if transition_.phase == "close" then
        -- 从中间扩大的实心圆逐渐覆盖全屏
        local easedT = UIAnim.Easing.easeInCubic(t)
        local radius = maxR * easedT

        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgFillColor(vg, nvgRGBA(10, 14, 26, 255))
        nvgFill(vg)
    elseif transition_.phase == "open" then
        -- 圆形缩回：从全屏到 0
        local easedT = UIAnim.Easing.easeInOutSine(t)
        local radius = maxR * easedT

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgCircle(vg, cx, cy, radius)
        nvgPathWinding(vg, NVG_HOLE)
        nvgFillColor(vg, nvgRGBA(10, 14, 26, 255))
        nvgFill(vg)
    end
end

--- 是否正在过渡
function UIAnim.IsTransitioning()
    return transition_.active
end

-- ===============================================================
-- 六、全局获取活跃 Tween 数量（性能监控）
-- ===============================================================

function UIAnim.GetActiveTweenCount()
    local count = 0
    for _ in pairs(tweens_) do
        count = count + 1
    end
    return count
end

--- 清除所有 Tween（场景切换时调用）
function UIAnim.Clear()
    tweens_ = {}
end

return UIAnim
