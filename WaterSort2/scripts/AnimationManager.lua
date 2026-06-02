--- AnimationManager.lua — 动画驱动：选中上移、4 阶段倒水（rise→fly→merge→fill）、液滴形变、涟漪、震动
local Config = require("Config")

local AnimationManager = {}
AnimationManager.__index = AnimationManager

function AnimationManager.new(tubeCount)
    local self = setmetatable({}, AnimationManager)

    self.tubeCount = tubeCount

    -- 每管独立的动画状态
    self.selectAnims = {}
    self.wobbles     = {}
    self.shakes      = {}
    self.ripples     = {}
    for i = 1, tubeCount do
        self.selectAnims[i] = { target = 0, current = 0 }
        self.wobbles[i]     = { amplitude = 0, timer = 0 }
        self.shakes[i]      = { timer = Config.ANIM.shake.duration } -- 初始已结束
        self.ripples[i]     = { amplitude = 0, timer = 0 }
    end

    -- 全局倒水动画
    self.pourAnim = { active = false }

    -- 水花粒子列表
    self.splashParticles = {}

    return self
end

-- === 触发接口 ===

function AnimationManager:setSelected(index)
    for i = 1, self.tubeCount do
        self.selectAnims[i].target = (i == index) and Config.ANIM.select.liftY or 0
    end
end

function AnimationManager:clearSelected()
    for i = 1, self.tubeCount do
        self.selectAnims[i].target = 0
    end
end

function AnimationManager:triggerWobble(tubeIdx, amplitude)
    self.wobbles[tubeIdx] = {
        amplitude = amplitude or Config.ANIM.wobble.amplitude,
        timer = 0,
    }
end

function AnimationManager:triggerRipple(tubeIdx)
    self.ripples[tubeIdx] = {
        amplitude = Config.ANIM.ripple.amplitude,
        timer = 0,
    }
end

function AnimationManager:triggerShake(tubeIdx)
    self.shakes[tubeIdx] = { timer = 0 }
end

--- 触发水花粒子（液滴入水时调用）
---@param x number 碰撞点 X
---@param y number 碰撞点 Y
---@param colorIdx number 液体颜色索引
function AnimationManager:triggerSplash(x, y, colorIdx)
    local S = Config.ANIM.splash
    local halfAngle = S.spreadAngle / 2
    for _ = 1, S.count do
        -- 随机角度：以正上方（-90°）为中心，左右扩散 halfAngle
        local angleDeg = -90 + (math.random() * 2 - 1) * halfAngle
        local angleRad = math.rad(angleDeg)
        -- 随机速度变化（70%~130%）
        local spd = S.speed * (0.7 + math.random() * 0.6)
        local radius = S.minRadius + math.random() * (S.maxRadius - S.minRadius)
        table.insert(self.splashParticles, {
            x  = x,
            y  = y,
            vx = math.cos(angleRad) * spd,
            vy = math.sin(angleRad) * spd,
            r  = radius,
            colorIdx = colorIdx,
            timer    = 0,
            lifetime = S.lifetime * (0.7 + math.random() * 0.6),
        })
    end
end

--- 启动倒水动画（根据模式分发到 droplet 或 stream）
---@param fromIdx       number
---@param toIdx         number
---@param color         number 颜色索引
---@param count         number 倒几格
---@param positions     table  试管位置表 { {x,y}, ... }
---@param targetFillInfo table|nil { straightTop, targetSlotTop, columnHeight }
---@param sourceRiseInfo table { liquidTopY, riseEndY }  源管液面Y坐标 + 上升终点Y
function AnimationManager:triggerPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
    if Config.POUR_MODE == "stream" then
        self:triggerStreamPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
        return
    end
    self:triggerDropletPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
end

--- 启动液滴飞行动画（rise→fly→merge→fill→完成）
function AnimationManager:triggerDropletPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
    local fromPos = positions[fromIdx]
    local toPos   = positions[toIdx]

    local halfW = Config.TUBE.tubeWidth / 2
    local riseInfo = sourceRiseInfo or {}
    -- 液滴起始位置 = 源管液面顶部 Y
    local liquidTopY = riseInfo.liquidTopY or fromPos.y
    -- 上升终点 = 管口上方一小段
    local riseEndY   = riseInfo.riseEndY or fromPos.y

    self.pourAnim = {
        active   = true,
        phase    = "rise",
        fromIdx  = fromIdx,
        toIdx    = toIdx,
        color    = color,
        count    = count,
        timer    = 0,

        -- 起止坐标（预计算）
        fromX = fromPos.x + halfW,
        fromY = riseEndY,             -- fly 起点 = rise 终点
        toX   = toPos.x + halfW,
        toY   = toPos.y + halfW * Config.TUBE.ellipticity * 2,  -- 管口位置（fly 终点）
        mergeEndY = targetFillInfo and targetFillInfo.existingTopY
                    or (toPos.y + halfW * Config.TUBE.ellipticity * 2),  -- merge 终点 = 液面位置

        -- rise 阶段参数
        riseLiquidTopY = liquidTopY,  -- 液面起始 Y
        riseEndY       = riseEndY,    -- 上升终点 Y
        riseProgress   = 0,           -- rise 进度 0→1（给渲染层读取）

        -- 飞行液滴当前状态
        blobX    = fromPos.x + halfW,
        blobY    = liquidTopY,
        aspect   = 0.1,
        rotation = 0,

        -- fill 阶段布局信息（由 main.lua 提供）
        fillInfo = targetFillInfo,
        fillProgress = 0,
    }
end

function AnimationManager:isPourActive()
    return self.pourAnim.active
end

-- === 每帧更新 ===

--- @return table|nil pourResult  倒水完成时返回 { fromIdx, toIdx, color, count }
function AnimationManager:update(dt)
    self:_updateSelectAnims(dt)
    self:_updateWobbles(dt)
    self:_updateShakes(dt)
    self:_updateRipples(dt)
    self:_updateSplashParticles(dt)
    return self:_updatePourAnim(dt)
end

-- === 读取接口（给渲染层用） ===

function AnimationManager:getSelectLift(tubeIdx)
    return self.selectAnims[tubeIdx].current
end

function AnimationManager:getWobbleOffset(tubeIdx)
    local w = self.wobbles[tubeIdx]
    if w.amplitude <= 0.1 then return 0 end
    return w.amplitude * math.sin(w.timer * Config.ANIM.wobble.frequency * math.pi * 2)
        * math.exp(-Config.ANIM.wobble.damping * w.timer)
end

function AnimationManager:getRippleState(tubeIdx)
    return self.ripples[tubeIdx]
end

function AnimationManager:getShakeOffset(tubeIdx)
    local s = self.shakes[tubeIdx]
    if s.timer >= Config.ANIM.shake.duration then return 0 end
    local progress = s.timer / Config.ANIM.shake.duration
    local decay = 1 - progress
    return Config.ANIM.shake.amplitude * decay
        * math.sin(s.timer * Config.ANIM.shake.frequency * math.pi * 2)
end

function AnimationManager:getPourState()
    return self.pourAnim
end

function AnimationManager:getSplashParticles()
    return self.splashParticles
end

-- === 内部实现 ===

function AnimationManager:_updateSelectAnims(dt)
    local speed = Config.ANIM.select.liftY / Config.ANIM.select.duration
    for i = 1, self.tubeCount do
        local a = self.selectAnims[i]
        if a.current < a.target then
            a.current = math.min(a.current + speed * dt, a.target)
        elseif a.current > a.target then
            a.current = math.max(a.current - speed * dt, a.target)
        end
    end
end

function AnimationManager:_updateWobbles(dt)
    for i = 1, self.tubeCount do
        local w = self.wobbles[i]
        if w.amplitude > 0.1 then
            w.timer = w.timer + dt
            -- 振幅随时间衰减（渲染端通过 exp(-damping*timer) 计算实际偏移）
            if w.timer > 2.0 then
                w.amplitude = 0
            end
        end
    end
end

function AnimationManager:_updateShakes(dt)
    for i = 1, self.tubeCount do
        local s = self.shakes[i]
        if s.timer < Config.ANIM.shake.duration then
            s.timer = s.timer + dt
        end
    end
end

function AnimationManager:_updateRipples(dt)
    for i = 1, self.tubeCount do
        local r = self.ripples[i]
        if r.amplitude > 0.1 then
            r.timer = r.timer + dt
            if r.timer > 2.0 then
                r.amplitude = 0
            end
        end
    end
end

function AnimationManager:_updateSplashParticles(dt)
    local gravity = Config.ANIM.splash.gravity
    local i = 1
    while i <= #self.splashParticles do
        local sp = self.splashParticles[i]
        sp.timer = sp.timer + dt
        if sp.timer >= sp.lifetime then
            table.remove(self.splashParticles, i)
        else
            sp.vy = sp.vy + gravity * dt  -- 重力
            sp.x = sp.x + sp.vx * dt
            sp.y = sp.y + sp.vy * dt
            i = i + 1
        end
    end
end

--- 启动倾倒水流动画（tilt→stream→settle→fill→完成）
function AnimationManager:triggerStreamPour(fromIdx, toIdx, color, count, positions, targetFillInfo, sourceRiseInfo)
    local fromPos = positions[fromIdx]
    local toPos   = positions[toIdx]

    local halfW = Config.TUBE.tubeWidth / 2
    local d = require("TubeRenderer").deriveTubeParams()

    -- 源管和目标管的关键坐标
    local fromCX = fromPos.x + halfW
    local toCX   = toPos.x + halfW
    local toRimY = toPos.y + d.rimEllipseRY  -- 目标管口椭圆中心 Y

    -- 倾斜方向：目标在左边 → 逆时针（负角度），右边 → 顺时针（正角度）
    local direction = (toIdx > fromIdx) and 1 or -1

    -- 源管管底中心（旋转轴心）
    local fromStraightTop = fromPos.y + d.rimEllipseRY * 2
    local fromStraightBottom = fromStraightTop + d.bodyHeight
    local fromTubeBottom = fromStraightBottom + Config.TUBE.ballHeight
    local pivotX = fromCX
    local pivotY = fromTubeBottom

    -- 源管管口椭圆中心（旋转前）相对轴心的 Y 偏移
    local rimRelY = (fromPos.y + d.rimEllipseRY) - fromTubeBottom  -- 负值

    -- 计算需要抬起的高度（确保倾斜后管口高于目标管口）
    -- 倾斜后管口 Y = pivotY + rimRelY * cos(maxAngle)
    -- rimRelY 是负值，cos < 1 → 管口会下沉
    local streamCfg = Config.ANIM.stream
    local maxAngleRad = math.rad(streamCfg.tiltAngle)
    local tiltedRimY = pivotY + rimRelY * math.cos(maxAngleRad)
    local liftMargin = streamCfg.liftMargin or 20
    local liftAmount = math.max(0, tiltedRimY - toRimY + liftMargin)

    self.pourAnim = {
        active   = true,
        mode     = "stream",
        phase    = "tilt",
        fromIdx  = fromIdx,
        toIdx    = toIdx,
        color    = color,
        count    = count,
        timer    = 0,

        -- 倾斜参数
        direction   = direction,
        tiltAngle   = 0,           -- 当前倾斜角度（度）
        maxTiltAngle = Config.ANIM.stream.tiltAngle * direction,
        pivotX      = pivotX,
        pivotY      = pivotY,
        rimRelY     = rimRelY,     -- 管口相对轴心的 Y 偏移

        -- 目标管参数
        toCX     = toCX,
        toRimY   = toRimY,

        -- 抬升参数
        liftAmount  = liftAmount,  -- 最终抬升量（px）
        currentLift = 0,           -- 当前抬升量（动画中插值）

        -- 水流参数
        streamProgress = 0,        -- 水流进度 0→1
        streamFading   = 0,        -- settle 阶段水流淡出进度

        -- 源管液面下降参数
        liquidDrainProgress = 0,   -- 液面下降进度 0→1

        -- rise 信息（用于渲染层读取源管液面）
        riseProgress = 0,          -- 兼容渲染层读取

        -- fill 阶段布局信息
        fillInfo     = targetFillInfo,
        fillProgress = 0,

        -- 断流小液滴
        drips = {},

        -- 源管原始位置（渲染层需要）
        fromPos = fromPos,
    }
end

--- 获取断流小液滴
function AnimationManager:getStreamDrips()
    if self.pourAnim.active and self.pourAnim.mode == "stream" then
        return self.pourAnim.drips or {}
    end
    return {}
end

local function bezier2(p0, p1, p2, t)
    local u = 1 - t
    return u * u * p0 + 2 * u * t * p1 + t * t * p2
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 倒水动画更新（根据模式分发）
---@return table|nil pourResult
function AnimationManager:_updatePourAnim(dt)
    local p = self.pourAnim
    if not p.active then return nil end

    if p.mode == "stream" then
        return self:_updateStreamAnim(dt)
    end

    p.timer = p.timer + dt
    local A = Config.ANIM.pour
    local D = Config.ANIM.droplet

    -- ========== 阶段 1: 上升（液滴从液面上升到管口上方，液面同步下降） ==========
    if p.phase == "rise" then
        local t = math.min(p.timer / A.riseDuration, 1.0)
        -- easeInQuad：先慢后快，到达管口时速度最大，与 fly 阶段无缝衔接
        local eased = t * t

        p.riseProgress = eased  -- 使用 eased 值，与液滴运动同步

        -- §4.1 水平微振：振幅 1.5px，随上升逐渐稳定
        local wobbleX = math.sin(p.timer * 18) * 1.5 * (1 - eased)
        p.blobX = p.fromX + wobbleX
        p.blobY = lerp(p.riseLiquidTopY, p.riseEndY, eased)

        -- 液滴从细长变圆：起始 2.5（窄高）→ 结束 1.0（圆），宽度始终不超过 baseW
        p.aspect = lerp(2.5, 1.0, eased)
        p.rotation = 0

        if t >= 1.0 then
            -- 液滴离开源管，触发源管液面抖动
            self:triggerWobble(p.fromIdx, Config.ANIM.wobble.amplitude * 0.5)
            p.phase = "fly"
            p.timer = 0
            p.riseProgress = 1.0
        end

    -- ========== 阶段 2: 飞行 ==========
    elseif p.phase == "fly" then
        local t = math.min(p.timer / A.flyDuration, 1.0)

        local x0 = p.fromX
        local y0 = p.riseEndY
        local x2, y2 = p.toX, p.toY
        local xMid = (x0 + x2) / 2
        local yPeak = math.min(y0, y2) - A.arcPeakH

        p.blobX = bezier2(x0, xMid, x2, t)
        p.blobY = bezier2(y0, yPeak, y2, t)

        -- 形变：起飞时从 rise 终点(1.0) 平滑过渡 → 中段圆 → 降落时扁
        local aspectT = 1.0 - math.abs(t - 0.5) * 2  -- 0→1→0 三角波
        local flyAspect = lerp(D.minAspect, D.maxAspect, aspectT)
        -- 前 10% 从 rise 终点 aspect(1.0) 平滑过渡到 fly 曲线值
        if t < 0.1 then
            local blendT = t / 0.1
            p.aspect = lerp(1.0, flyAspect, blendT)
        else
            p.aspect = flyAspect
        end

        -- 轻微旋转
        p.rotation = math.sin(p.timer * D.rotateSpeed) * 0.15

        if t >= 1.0 then
            p.phase = "merge"
            p.timer = 0
        end

    -- ========== 阶段 3: 融入（液滴从管口下落到液面） ==========
    elseif p.phase == "merge" then
        local t = math.min(p.timer / A.mergeDuration, 1.0)
        -- easeInQuad：先慢后快，模拟液滴被液面"吸入"加速下落
        local eased = t * t
        p.blobX = p.toX
        p.blobY = lerp(p.toY, p.mergeEndY, eased)  -- 从管口下落到液面位置
        -- aspect 增大 = 变窄变高（被液面吸入拉长），避免变宽超出试管
        p.aspect = lerp(D.maxAspect, 3.0, eased)
        p.rotation = 0

        -- §2.2 预涟漪：merge 末尾提前触发弱涟漪预告
        if t > 0.8 and not p._preRipple then
            self:triggerRipple(p.toIdx)
            self.ripples[p.toIdx].amplitude = Config.ANIM.ripple.amplitude * 0.3
            p._preRipple = true
        end

        if t >= 1.0 then
            -- 触发涟漪 + wobble + 水花（液滴入水瞬间）
            self:triggerRipple(p.toIdx)
            self:triggerWobble(p.toIdx)
            self:triggerSplash(p.toX, p.mergeEndY, p.color)

            if p.fillInfo then
                -- 进入 fill 阶段
                p.phase = "fill"
                p.timer = 0
                p.fillProgress = 0
            else
                -- 无 fill 信息时直接结束（兼容旧调用）
                local result = {
                    fromIdx = p.fromIdx,
                    toIdx   = p.toIdx,
                    color   = p.color,
                    count   = p.count,
                }
                p.active = false
                return result
            end
        end

    -- ========== 阶段 4: 填充 ==========
    elseif p.phase == "fill" then
        local t = math.min(p.timer / A.fillDuration, 1.0)
        -- easeOutQuad：减速上涨，模拟液面填充
        p.fillProgress = 1 - (1 - t) * (1 - t)

        if t >= 1.0 then
            local result = {
                fromIdx = p.fromIdx,
                toIdx   = p.toIdx,
                color   = p.color,
                count   = p.count,
            }
            p.active = false
            return result
        end
    end

    return nil
end

--- 倾倒水流动画更新（tilt→stream→settle→fill）
---@return table|nil pourResult
function AnimationManager:_updateStreamAnim(dt)
    local p = self.pourAnim
    p.timer = p.timer + dt
    local S = Config.ANIM.stream

    -- 旋转后管口位置的计算辅助（含抬升偏移）
    local function calcRotatedRim(angleDeg)
        local angleRad = math.rad(angleDeg)
        local cosA = math.cos(angleRad)
        local sinA = math.sin(angleRad)
        -- 管口中心相对轴心的偏移 (0, rimRelY)
        local rx = -p.rimRelY * sinA   -- rimRelY 是负值
        local ry = p.rimRelY * cosA
        return p.pivotX + rx, p.pivotY + ry - (p.currentLift or 0)
    end

    -- ========== 阶段 1: Tilt（倾斜）==========
    if p.phase == "tilt" then
        local t = math.min(p.timer / S.tiltDuration, 1.0)
        -- easeInOutQuad
        local eased
        if t < 0.5 then
            eased = 2 * t * t
        else
            eased = 1 - (-2 * t + 2) * (-2 * t + 2) / 2
        end

        p.tiltAngle = p.maxTiltAngle * eased
        p.currentLift = p.liftAmount * eased

        if t >= 1.0 then
            p.tiltAngle = p.maxTiltAngle
            p.currentLift = p.liftAmount
            p.phase = "stream"
            p.timer = 0
            -- 触发目标管持续涟漪
            self:triggerWobble(p.toIdx, Config.ANIM.wobble.amplitude * 0.3)
        end

    -- ========== 阶段 2: Stream（水流）==========
    elseif p.phase == "stream" then
        local t = math.min(p.timer / S.streamDuration, 1.0)

        p.currentLift = p.liftAmount
        p.streamProgress = t
        -- 液面下降与水流同步
        p.liquidDrainProgress = t
        -- 兼容渲染层的 shrink 效果
        p.riseProgress = t

        -- 持续小涟漪
        if math.floor(p.timer * 8) ~= math.floor((p.timer - dt) * 8) then
            self.ripples[p.toIdx] = {
                amplitude = Config.ANIM.ripple.amplitude * 0.4,
                timer = 0,
            }
        end

        -- 持续小水花
        if math.floor(p.timer * 10) ~= math.floor((p.timer - dt) * 10) then
            local rimX, _ = calcRotatedRim(p.tiltAngle)
            -- 水花在目标管口
            self:triggerSplash(p.toCX, p.toRimY, p.color)
            -- 减少粒子数量（持续飞溅，不要太多）
            while #self.splashParticles > 4 do
                table.remove(self.splashParticles, 1)
            end
        end

        if t >= 1.0 then
            p.phase = "settle"
            p.timer = 0
            p.streamFading = 0
        end

    -- ========== 阶段 3: Settle（归位 + 断流）==========
    elseif p.phase == "settle" then
        local t = math.min(p.timer / S.settleDuration, 1.0)
        -- easeOutQuad
        local eased = 1 - (1 - t) * (1 - t)

        -- 倾斜角度回归 0
        p.tiltAngle = p.maxTiltAngle * (1 - eased)
        -- 抬升同步回落
        p.currentLift = p.liftAmount * (1 - eased)
        -- 水流淡出
        p.streamFading = eased

        -- 断流小液滴（在 settle 开始时生成）
        if t < 0.1 and #p.drips == 0 then
            local rimX, rimY = calcRotatedRim(p.maxTiltAngle * 0.5)
            for _ = 1, S.dripCount do
                local angleDeg = -90 + (math.random() * 2 - 1) * 30
                local angleRad = math.rad(angleDeg)
                local spd = S.dripSpeed * (0.6 + math.random() * 0.8)
                local r = S.dripMinRadius + math.random() * (S.dripMaxRadius - S.dripMinRadius)
                -- 朝目标管方向偏移初速度
                local vxBias = (p.toCX - rimX) * 0.8
                table.insert(p.drips, {
                    x  = rimX + (math.random() * 2 - 1) * 3,
                    y  = rimY,
                    vx = math.cos(angleRad) * spd + vxBias,
                    vy = math.sin(angleRad) * spd,
                    r  = r,
                    timer    = 0,
                    lifetime = S.dripLifetime * (0.7 + math.random() * 0.6),
                })
            end
        end

        -- 更新断流液滴
        local dripGravity = S.dripGravity
        local di = 1
        while di <= #p.drips do
            local drip = p.drips[di]
            drip.timer = drip.timer + dt
            if drip.timer >= drip.lifetime then
                table.remove(p.drips, di)
            else
                drip.vy = drip.vy + dripGravity * dt
                drip.x = drip.x + drip.vx * dt
                drip.y = drip.y + drip.vy * dt
                di = di + 1
            end
        end

        if t >= 1.0 then
            -- 触发最终涟漪 + wobble
            self:triggerRipple(p.toIdx)
            self:triggerWobble(p.toIdx)
            -- 触发最终水花
            self:triggerSplash(p.toCX, p.toRimY, p.color)

            if p.fillInfo then
                p.phase = "fill"
                p.timer = 0
                p.fillProgress = 0
                p.tiltAngle = 0
            else
                local result = {
                    fromIdx = p.fromIdx,
                    toIdx   = p.toIdx,
                    color   = p.color,
                    count   = p.count,
                }
                p.active = false
                return result
            end
        end

    -- ========== 阶段 4: Fill（填充，复用 droplet 逻辑）==========
    elseif p.phase == "fill" then
        local t = math.min(p.timer / S.fillDuration, 1.0)
        p.fillProgress = 1 - (1 - t) * (1 - t)

        if t >= 1.0 then
            local result = {
                fromIdx = p.fromIdx,
                toIdx   = p.toIdx,
                color   = p.color,
                count   = p.count,
            }
            p.active = false
            return result
        end
    end

    return nil
end

return AnimationManager
