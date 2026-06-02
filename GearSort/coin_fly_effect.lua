-- coin_fly_effect.lua
-- 飞金币粒子演出：N 枚金币从屏幕四周沿贝塞尔弧线飞向目标 UI 位置
-- 依赖：urhox-libs/UI（将覆盖层作为子节点挂入当前 root 渲染树）

local UI           = require("urhox-libs/UI")
local SoundManager = require("sound_manager")

local CoinFlyEffect = {}

-- ---------------------------------------------------------------
-- 参数常量
-- ---------------------------------------------------------------
local COIN_IMG      = "image/icon_coin_reward_20260526074619.png"
local COIN_SIZE     = 60          -- 飞行图标初始边长（逻辑像素）
local COIN_SIZE_END = 42          -- 到达终点时缩小至此
local MAX_PARTICLES = 30          -- 最多飞出粒子数

-- 时间参数（秒）
local DELAY_MAX  = 0.40   -- 各粒子错开最大延迟
local FLY_MIN    = 0.55
local FLY_MAX    = 0.90

-- 起点散布半径：粒子在起始坐标附近随机偏移（逻辑像素）
local SPAWN_SCATTER = 30

-- 贝塞尔控制点偏移距离范围（像素，垂直于起终点连线方向）
local CTRL_DIST_MIN = 80
local CTRL_DIST_MAX = 220

-- ---------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------
---@type table[]
local particles_   = {}
---@type table|nil
local overlay_     = nil   -- 全屏覆盖 Panel（挂在 Overlay 栈上）
local onComplete_  = nil   -- 全部到达后的回调
local active_      = false

-- ---------------------------------------------------------------
-- 缓动：ease-in-out cubic
-- ---------------------------------------------------------------
local function easeInOut(t)
    if t < 0.5 then return 4*t*t*t
    else local u = 1-t; return 1 - 4*u*u*u end
end

-- ---------------------------------------------------------------
-- 二次贝塞尔插值
-- ---------------------------------------------------------------
local function bezier2(ax, ay, bx, by, cx, cy, t)
    local u = 1 - t
    return u*u*ax + 2*u*t*bx + t*t*cx,
           u*u*ay + 2*u*t*by + t*t*cy
end

-- ---------------------------------------------------------------
-- 随机浮点数
-- ---------------------------------------------------------------
local function rnd(lo, hi) return lo + math.random() * (hi - lo) end

-- ---------------------------------------------------------------
-- 出发坐标：在给定中心点附近随机散布
-- ---------------------------------------------------------------
local function spawnPos(cx, cy)
    local angle = rnd(0, math.pi * 2)
    local dist  = rnd(0, SPAWN_SCATTER)
    return cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
end

-- ---------------------------------------------------------------
-- 停止 & 清理
-- ---------------------------------------------------------------
local function cleanup()
    if overlay_ then
        overlay_:Remove()   -- 从渲染树摘除
        overlay_ = nil
    end
    particles_  = {}
    onComplete_ = nil
    active_     = false
end

-- ---------------------------------------------------------------
-- 每帧驱动（由 main.lua HandleUpdate 调用）
-- ---------------------------------------------------------------
function CoinFlyEffect.Update(dt)
    if not active_ then return end

    local allDone = true
    for _, p in ipairs(particles_) do
        if p.done then goto continue end

        p.elapsed = p.elapsed + dt

        if p.elapsed < p.delay then
            -- 还在等待延迟：保持透明
            allDone = false
            goto continue
        end

        local fe = p.elapsed - p.delay   -- 飞行已用时
        if fe >= p.duration then
            -- 到达终点：隐藏
            p.node:SetStyle({ opacity = 0 })
            p.done = true
            SoundManager.Play("coin_collect", 0.3)
        else
            local t      = easeInOut(fe / p.duration)
            local px, py = bezier2(p.sx, p.sy, p.cx, p.cy, p.tx, p.ty, t)
            local sz     = COIN_SIZE + (COIN_SIZE_END - COIN_SIZE) * t
            -- 接近终点时淡出（最后 30% 渐隐）
            local alpha  = (t > 0.7) and (1 - (t - 0.7) / 0.3) or 1.0
            p.node:SetStyle({
                left    = px - sz * 0.5,
                top     = py - sz * 0.5,
                width   = sz,
                height  = sz,
                opacity = alpha,
            })
            allDone = false
        end
        ::continue::
    end

    if allDone then
        local cb = onComplete_
        cleanup()
        SoundManager.Play("coin_land")
        if cb then cb() end
    end
end

-- ---------------------------------------------------------------
-- 对外接口：发射金币
--   sourceX / sourceY : 起始位置（如弹窗内的 "+N" 标签中心）
--   targetX / targetY : 目标金币 UI 中心的屏幕坐标
--   count             : 实际获得金币数（决定粒子数，上限 MAX_PARTICLES）
--   onComplete        : 全部到达后的回调
-- ---------------------------------------------------------------
function CoinFlyEffect.Play(sourceX, sourceY, targetX, targetY, count, onComplete)
    -- 中止上一次尚未完成的演出
    if active_ then
        local oldCb = onComplete_
        cleanup()
        if oldCb then oldCb() end
    end

    local numP = math.min(math.max(count, 0), MAX_PARTICLES)
    if numP == 0 then
        if onComplete then onComplete() end
        return
    end

    onComplete_ = onComplete
    active_     = true
    particles_  = {}

    -- 为每个粒子建 Panel 节点
    local nodes = {}
    for i = 1, numP do
        nodes[i] = UI.Panel {
            position        = "absolute",
            left            = -COIN_SIZE,
            top             = -COIN_SIZE,
            width           = COIN_SIZE,
            height          = COIN_SIZE,
            backgroundImage = COIN_IMG,
            backgroundFit   = "contain",
            pointerEvents   = "none",
            opacity         = 0,
        }
    end

    -- 建立全屏覆盖层，挂入当前 root 渲染树（必须 AddChild 才会被渲染）
    overlay_ = UI.Panel {
        position      = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
        children      = nodes,
    }
    local root = UI.GetRoot()
    if root then
        root:AddChild(overlay_)
    else
        --print("[CoinFlyEffect] ERROR: UI root 不存在，无法挂载覆盖层")
        cleanup()
        if onComplete then onComplete() end
        return
    end

    -- 初始化粒子数据
    for i = 1, numP do
        local sx, sy = spawnPos(sourceX, sourceY)
        local midX   = (sx + targetX) * 0.5
        local midY   = (sy + targetY) * 0.5

        -- 计算起终点连线的垂直方向（法线），控制点沿法线随机偏移
        local dx     = targetX - sx
        local dy     = targetY - sy
        local len    = math.sqrt(dx * dx + dy * dy)
        -- 法线（顺时针旋转 90°）：(-dy, dx) / len，长度归一化
        local nx, ny = 0, -1
        if len > 1 then
            nx = -dy / len
            ny =  dx / len
        end
        -- 随机选左侧或右侧，偏移距离在 [CTRL_DIST_MIN, CTRL_DIST_MAX]
        local side   = (math.random(0, 1) == 0) and 1 or -1
        local dist   = rnd(CTRL_DIST_MIN, CTRL_DIST_MAX)
        local ctrlX  = midX + nx * dist * side
        local ctrlY  = midY + ny * dist * side

        -- 延迟：均匀分散在 [0, DELAY_MAX] 区间
        local delay = DELAY_MAX * ((i - 1) / math.max(numP - 1, 1))

        local node = nodes[i]
        -- 设置初始位置（透明，等 delay 到了再现身）
        node:SetStyle({
            left    = sx - COIN_SIZE * 0.5,
            top     = sy - COIN_SIZE * 0.5,
            opacity = 0,
        })

        particles_[i] = {
            node     = node,
            sx = sx,    sy = sy,
            cx = ctrlX, cy = ctrlY,
            tx = targetX, ty = targetY,
            delay    = delay,
            duration = rnd(FLY_MIN, FLY_MAX),
            elapsed  = 0,
            done     = false,
        }
    end

    --print(string.format("[CoinFlyEffect] 飞金币演出：%d 粒子 → (%.0f, %.0f)",
    --    numP, targetX, targetY))
end

-- ---------------------------------------------------------------
-- 强制中止（切换界面时调用，立即触发回调）
-- ---------------------------------------------------------------
function CoinFlyEffect.Stop()
    if not active_ then return end
    local cb = onComplete_
    cleanup()
    if cb then cb() end
end

return CoinFlyEffect
