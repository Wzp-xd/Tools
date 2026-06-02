-- ============================================================
-- Animation.lua - 动画状态机（并发倾倒、抖动、选中偏移、胜利）
-- 支持多个倒水动画同时播放
-- ============================================================

local Config = require("config")

local Animation = {}
Animation.__index = Animation

-- ============================================================
-- 缓动函数
-- ============================================================
local Easing = {}

function Easing.inOutQuad(t)
    if t < 0.5 then return 2 * t * t
    else return -1 + (4 - 2 * t) * t end
end

function Easing.outQuad(t)
    return t * (2 - t)
end

function Easing.outBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

Animation.Easing = Easing

-- ============================================================
-- 工具函数
-- ============================================================
local function lerp(a, b, t) return a + (b - a) * t end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

Animation.lerp = lerp
Animation.clamp = clamp

--- 根据剩余液体量计算所需倾斜角度
---@param remaining number 当前剩余层数(浮点)
---@return number angle 弧度
function Animation.getTiltAngleForRemaining(remaining)
    local tube = Config.tube
    local anim = Config.animation
    -- 直筒段内液体可用高度（平底椭圆：全部层都在直筒段内）
    local innerH = tube.topPadding + tube.layerCount * tube.slotHeight
    local halfInnerW = (tube.width - 2 * tube.wall) / 2
    local layerH = tube.slotHeight
    local waterH = remaining * layerH
    if waterH < 0.5 then
        return anim.tiltAngleMax
    end
    local deficit = innerH - waterH
    if deficit <= 0 then
        return anim.tiltAngleMin
    end
    local angle = math.atan(deficit / halfInnerW)
    if remaining < 1 then
        local t = 1 - remaining
        angle = angle + (anim.tiltAngleMax - angle) * t
    end
    return clamp(angle, anim.tiltAngleMin, anim.tiltAngleMax)
end

-- ============================================================
-- 构造
-- ============================================================

--- 创建新的动画管理器
---@return table
function Animation.new()
    local self = setmetatable({}, Animation)
    -- 并发倾倒动画列表
    self.activeAnims = {}  -- { {phase, timer, srcIdx, dstIdx, pourLayers, ...}, ... }
    -- 抖动
    self.shake = { tubeIdx = nil, timer = 0 }
    -- 选中偏移
    self.tubeOffsetY = {}
    -- 胜利效果
    self.win = { timer = 0, particles = {}, active = false }
    return self
end

--- 是否有活跃的倾倒动画
---@return boolean
function Animation:hasActiveAnims()
    return #self.activeAnims > 0
end

--- 获取指定管作为源的活跃动画（渲染用）
---@param tubeIdx integer
---@return table|nil anim
function Animation:getAnimForSource(tubeIdx)
    for _, a in ipairs(self.activeAnims) do
        if a.srcIdx == tubeIdx then return a end
    end
    return nil
end

--- 获取指定管作为目标的所有活跃动画信息（渲染用）
---@param tubeIdx integer
---@return number totalPouredSoFar 所有正在倒入该管的已倒量合计
---@return integer|nil pourColor 倒入颜色（取第一个动画的颜色，多个并发应相同）
function Animation:getDstAnimInfo(tubeIdx)
    local totalPoured = 0
    local color = nil
    for _, a in ipairs(self.activeAnims) do
        if a.dstIdx == tubeIdx then
            if a.phase == "pour" or a.phase == "return" then
                totalPoured = totalPoured + a.pouredSoFar
                color = color or a.pourColor
            end
        end
    end
    return totalPoured, color
end

--- 开始一个新的倾倒动画
---@param pourInfo table 来自 GameState:commitPour() 的返回值
function Animation:startPour(pourInfo)
    local a = {
        phase = "move",  -- "move"|"tilt"|"pour"|"return"
        timer = 0,
        srcIdx = pourInfo.srcIdx,
        dstIdx = pourInfo.dstIdx,
        pourLayers = pourInfo.pourCount,
        pouredSoFar = 0,
        pourColor = pourInfo.pourColor,
        srcOrigLayers = pourInfo.srcSnapshot,
    }
    table.insert(self.activeAnims, a)
end

--- 开始抖动
---@param tubeIdx integer
function Animation:startShake(tubeIdx)
    self.shake.tubeIdx = tubeIdx
    self.shake.timer = Config.interaction.shakeDuration
end

--- 开始胜利效果
function Animation:startWin()
    self.win.active = true
    self.win.timer = 0
    self.win.particles = {}
    local wfx = Config.winEffect
    local colors = Config.getColors()
    for _ = 1, wfx.particleCount do
        table.insert(self.win.particles, {
            x = math.random() * 0.6 + 0.2,
            y = 0.4 + math.random() * 0.2,
            vx = (math.random() - 0.5) * (wfx.particleMaxVx - wfx.particleMinVx)
                 + (wfx.particleMaxVx + wfx.particleMinVx) / 2,
            vy = math.random() * (wfx.particleMaxVy - wfx.particleMinVy) + wfx.particleMinVy,
            color = math.random(1, #colors),
            size = math.random(wfx.particleMinSize, wfx.particleMaxSize),
            life = 1.0,
            decay = wfx.particleDecayMin + math.random() * (wfx.particleDecayMax - wfx.particleDecayMin),
        })
    end
end

--- 停止胜利效果
function Animation:stopWin()
    self.win.active = false
    self.win.timer = 0
    self.win.particles = {}
end

--- 初始化试管偏移数组
---@param tubeCount integer
function Animation:initOffsets(tubeCount)
    self.tubeOffsetY = {}
    for i = 1, tubeCount do
        self.tubeOffsetY[i] = 0
    end
end

--- 每帧更新
---@param dt number
---@param selectedTube integer|nil
---@param tubeCount integer
---@return table completedAnims 本帧完成的动画列表（可能为空）
function Animation:update(dt, selectedTube, tubeCount)
    local completedAnims = {}
    local animCfg = Config.animation
    local interact = Config.interaction

    -- 更新所有活跃倾倒动画（逆序遍历以安全移除）
    for i = #self.activeAnims, 1, -1 do
        local a = self.activeAnims[i]
        a.timer = a.timer + dt
        local done = false

        if a.phase == "move" then
            if a.timer >= animCfg.moveDuration then
                a.phase = "tilt"
                a.timer = 0
            end
        elseif a.phase == "tilt" then
            if a.timer >= animCfg.tiltDuration then
                a.phase = "pour"
                a.timer = 0
                a.pouredSoFar = 0
            end
        elseif a.phase == "pour" then
            a.pouredSoFar = clamp(a.timer / animCfg.pourPerLayer, 0, a.pourLayers)
            if a.timer >= a.pourLayers * animCfg.pourPerLayer then
                a.phase = "return"
                a.timer = 0
                a.pouredSoFar = a.pourLayers
            end
        elseif a.phase == "return" then
            if a.timer >= animCfg.returnDuration then
                done = true
            end
        end

        if done then
            table.insert(completedAnims, a)
            table.remove(self.activeAnims, i)
        end
    end

    -- 更新抖动
    if self.shake.timer > 0 then
        self.shake.timer = self.shake.timer - dt
        if self.shake.timer <= 0 then
            self.shake.timer = 0
            self.shake.tubeIdx = nil
        end
    end

    -- 更新选中偏移
    for i = 1, tubeCount do
        local target = (selectedTube == i) and -interact.selectOffset or 0
        local cur = self.tubeOffsetY[i] or 0
        local diff = target - cur
        if math.abs(diff) < 0.3 then
            self.tubeOffsetY[i] = target
        else
            self.tubeOffsetY[i] = cur + diff * math.min(1.0, interact.selectAnimSpd * dt)
        end
    end

    -- 更新胜利粒子
    if self.win.active then
        self.win.timer = self.win.timer + dt
        local gravity = Config.winEffect.particleGravity
        for _, pa in ipairs(self.win.particles) do
            if pa.life > 0 then
                pa.x = pa.x + pa.vx * dt / 600
                pa.y = pa.y + pa.vy * dt / 600
                pa.vy = pa.vy + gravity * dt
                pa.life = pa.life - pa.decay * dt
            end
        end
    end

    return completedAnims
end

--- 获取抖动X偏移
---@param tubeIdx integer
---@return number
function Animation:getShakeOffsetX(tubeIdx)
    local s = self.shake
    if s.tubeIdx ~= tubeIdx or s.timer <= 0 then return 0 end
    local interact = Config.interaction
    local p = 1 - s.timer / interact.shakeDuration
    return math.sin(p * math.pi * interact.shakeFreq * 2) * interact.shakeAmplitude * (1 - p)
end

--- 获取胜利弹跳Y偏移
---@param tubeIdx integer
---@return number
function Animation:getWinBounceY(tubeIdx)
    if not self.win.active then return 0 end
    local wfx = Config.winEffect
    local delay = (tubeIdx - 1) * wfx.bounceDelay
    local bt = clamp((self.win.timer - delay) / wfx.bounceDuration, 0, 1)
    if bt > 0 then
        return -math.sin(bt * math.pi) * wfx.bounceHeight
    end
    return 0
end

return Animation
