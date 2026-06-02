--- main.lua — 入口：生命周期、事件订阅、模块组装
local UI = require("urhox-libs/UI")
local Config           = require("Config")
local GameState        = require("GameState")
local TubeRenderer     = require("TubeRenderer")
local AnimationManager = require("AnimationManager")
local InputHandler     = require("InputHandler")

local game_      = nil
local anims_     = nil
local positions_ = {}
local tubeH_     = 0
local nvgCtx_    = nil

-- ============================================================
-- 生命周期
-- ============================================================

function Start()
    graphics.windowTitle = "倒水美术切片"

    -- 1) 初始化 UI
    UI.Init({
        fonts = {{ family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }},
        scale = UI.Scale.DEFAULT,
    })
    CreateHUD()

    -- 2) 初始化游戏数据
    game_ = GameState.new()
    anims_ = AnimationManager.new(#game_.tubes)

    -- 3) 计算布局
    updateLayout()

    -- 4) 初始化输入
    InputHandler.init({
        positions = positions_,
        tubeH     = tubeH_,
        getAnimOffsets = function(i)
            return anims_:getSelectLift(i), anims_:getShakeOffset(i)
        end,
        onTubeClick = onTubeClick,
        uiModule = UI,
    })

    -- 5) NanoVG 渲染事件（使用独立上下文，与 UI 的 NanoVG 上下文共存）
    nvgCtx_ = nvgCreate(1)
    nvgCreateFont(nvgCtx_, "sans", "Fonts/MiSans-Regular.ttf")
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")

    -- 6) 帧更新
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== Pour Water Art-Slice Demo Started ===")
end

function Stop()
    if nvgCtx_ then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
    UI.Shutdown()
end

-- ============================================================
-- 布局
-- ============================================================

function updateLayout()
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    positions_, tubeH_ = TubeRenderer.calcPositions(
        #game_.tubes, w / dpr, h / dpr)
    InputHandler.updateLayout(positions_, tubeH_)
end

-- ============================================================
-- 核心交互逻辑
-- ============================================================

function onTubeClick(index)
    if anims_:isPourActive() then return end

    if game_.selected == nil then
        -- 选中非空管
        if #game_.tubes[index] > 0 then
            game_.selected = index
            anims_:setSelected(index)
        end
    elseif game_.selected == index then
        -- 取消选中
        game_.selected = nil
        anims_:clearSelected()
    else
        -- 尝试倒水
        if game_:canPour(game_.selected, index) then
            local fromIdx = game_.selected

            -- 拆分步骤 1/2：先从数据层移除源管顶部
            local pourInfo = game_:removeFromSource(fromIdx, index)

            local d = TubeRenderer.deriveTubeParams()

            -- 预计算 fill 阶段目标管布局信息
            local targetPos = positions_[index]
            local targetStraightTop = targetPos.y + d.rimEllipseRY * 2
            local existingCount = #game_.tubes[index]
            local targetSlotTop = targetStraightTop + d.topPadding
                + (Config.CAPACITY - existingCount - pourInfo.count) * d.slotHeight
            local existingTopY = targetStraightTop + d.topPadding
                + (Config.CAPACITY - existingCount) * d.slotHeight

            -- 预计算 rise 阶段源管信息
            -- removeFromSource 已移除顶部液体，当前 tubes[fromIdx] 是移除后的状态
            -- 被移除的液体原来在 slot (removedAfterCount+1) ~ (removedAfterCount+count)
            -- 顶层 slot 的 Y = straightTop + (CAPACITY - originalCount) * slotHeight
            local fromPos = positions_[fromIdx]
            local fromStraightTop = fromPos.y + d.rimEllipseRY * 2
            local originalCount = #game_.tubes[fromIdx] + pourInfo.count
            local liquidTopY = fromStraightTop + d.topPadding + (Config.CAPACITY - originalCount) * d.slotHeight
            -- 上升终点 = 管口上方（rimEllipseRY 处，即 fromPos.y）
            local riseEndY = fromPos.y

            anims_:triggerPour(fromIdx, index, pourInfo.color, pourInfo.count, positions_, {
                straightTop   = targetStraightTop,
                targetSlotTop = targetSlotTop,
                existingTopY  = existingTopY,
                columnHeight  = pourInfo.count * d.slotHeight,
            }, {
                liquidTopY = liquidTopY,
                riseEndY   = riseEndY,
            })
            game_.selected = nil
            anims_:clearSelected()
        else
            -- 非法操作：震动反馈
            anims_:triggerShake(index)
            game_.selected = nil
            anims_:clearSelected()
        end
    end
end

-- ============================================================
-- 帧更新
-- ============================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    local pourResult = anims_:update(dt)
    if pourResult then
        -- 拆分步骤 2/2：倒水动画结束 → 将液体添加到目标管
        game_:addToTarget(pourResult.toIdx, pourResult.color, pourResult.count)
    end
end

-- ============================================================
-- NanoVG 渲染
-- ============================================================

function HandleNanoVGRender(eventType, eventData)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW, logH = w / dpr, h / dpr

    nvgBeginFrame(nvgCtx_, logW, logH, dpr)

    TubeRenderer.drawBackground(nvgCtx_, logW, logH)

    local pour = anims_:getPourState()
    local isStream = pour.active and pour.mode == "stream"

    for i = 1, #game_.tubes do
        local pos = positions_[i]
        local liftY   = anims_:getSelectLift(i)
        local shakeX  = anims_:getShakeOffset(i)
        local wobbleY = anims_:getWobbleOffset(i)

        -- 源管：rise/tilt+stream 阶段渐变缩减
        local hideFromTop = 0
        local shrinkState = nil
        if pour.active and pour.fromIdx == i then
            if isStream then
                -- stream 模式：tilt 阶段不缩减，stream+settle 阶段液面下降
                if pour.phase == "stream" or pour.phase == "settle" then
                    shrinkState = {
                        count    = pour.count,
                        progress = pour.liquidDrainProgress or 0,
                        colorIdx = pour.color,
                    }
                elseif pour.phase == "tilt" then
                    shrinkState = {
                        count    = pour.count,
                        progress = 0,
                        colorIdx = pour.color,
                    }
                end
            else
                -- droplet 模式原有逻辑
                if pour.phase == "rise" then
                    shrinkState = {
                        count    = pour.count,
                        progress = pour.riseProgress or 0,
                        colorIdx = pour.color,
                    }
                end
            end
        end

        -- fill 状态（仅目标管在 fill 阶段）
        local fillState = nil
        if pour.active and pour.phase == "fill" and pour.toIdx == i and pour.fillInfo then
            fillState = {
                colorIdx      = pour.color,
                count         = pour.count,
                targetSlotTop = pour.fillInfo.targetSlotTop,
                existingTopY  = pour.fillInfo.existingTopY,
                progress      = pour.fillProgress or 0,
                wobbleOffset  = wobbleY,
                rippleState   = anims_:getRippleState(i),
            }
        end

        -- stream 模式下源管需要倾斜渲染
        local tiltAngle = nil
        if isStream and pour.fromIdx == i and pour.phase ~= "fill" then
            tiltAngle = pour.tiltAngle or 0
        end

        if tiltAngle and math.abs(tiltAngle) > 0.1 then
            -- 倾斜渲染：以管底中心为轴心旋转，同时抬升源管
            local streamLift = (pour.active and pour.currentLift) or 0
            local d = TubeRenderer.deriveTubeParams()
            local cx = pos.x + shakeX + Config.TUBE.tubeWidth / 2
            local drawY = pos.y - liftY - streamLift
            local straightTop = drawY + d.rimEllipseRY * 2
            local straightBottom = straightTop + d.bodyHeight
            local tubeBottom = straightBottom + Config.TUBE.ballHeight
            local pivotX = cx
            local pivotY = tubeBottom

            nvgSave(nvgCtx_)
            nvgTranslate(nvgCtx_, pivotX, pivotY)
            nvgRotate(nvgCtx_, math.rad(tiltAngle))
            nvgTranslate(nvgCtx_, -pivotX, -pivotY)

            TubeRenderer.drawTube(nvgCtx_,
                pos.x + shakeX,
                drawY,
                game_.tubes[i],
                {
                    selected     = (game_.selected == i),
                    hideFromTop  = hideFromTop,
                    shrinkState  = shrinkState,
                    wobbleOffset = wobbleY,
                    rippleState  = anims_:getRippleState(i),
                    fillState    = fillState,
                    tiltAngle    = tiltAngle,
                }
            )
            nvgRestore(nvgCtx_)
        else
            TubeRenderer.drawTube(nvgCtx_,
                pos.x + shakeX,
                pos.y - liftY,
                game_.tubes[i],
                {
                    selected     = (game_.selected == i),
                    hideFromTop  = hideFromTop,
                    shrinkState  = shrinkState,
                    wobbleOffset = wobbleY,
                    rippleState  = anims_:getRippleState(i),
                    fillState    = fillState,
                }
            )
        end
    end

    -- ========== 倒水特效 ==========

    if isStream then
        -- stream 模式：绘制水流
        if pour.phase == "stream" or pour.phase == "settle" then
            -- 计算旋转后的源管管口位置（含抬升偏移）
            local angleDeg = pour.tiltAngle or 0
            local angleRad = math.rad(angleDeg)
            local cosA = math.cos(angleRad)
            local sinA = math.sin(angleRad)
            local rimRelY = pour.rimRelY or 0
            local streamLift = pour.currentLift or 0
            local rimX = pour.pivotX + (-rimRelY * sinA)
            local rimY = pour.pivotY + (rimRelY * cosA) - streamLift

            -- 水流终点 = 目标管管口
            local endX = pour.toCX
            local endY = pour.toRimY

            local fading = 0
            if pour.phase == "settle" then
                fading = pour.streamFading or 0
            end

            TubeRenderer.drawStream(nvgCtx_, {
                startX   = rimX,
                startY   = rimY,
                endX     = endX,
                endY     = endY,
                colorIdx = pour.color,
                progress = pour.streamProgress or 1,
                fading   = fading,
                timer    = pour.timer or 0,
            })
        end

        -- 断流小液滴
        local drips = anims_:getStreamDrips()
        if #drips > 0 then
            TubeRenderer.drawDrips(nvgCtx_, drips, pour.color)
        end
    else
        -- droplet 模式：飞行液滴（rise / fly / merge 阶段可见，fill 阶段不显示）
        if pour.active and pour.phase ~= "fill" then
            -- 拉丝效果
            if pour.phase == "rise" and (pour.riseProgress or 0) < 0.5 then
                local prog = pour.riseProgress or 0
                local alpha = math.floor(150 * (1 - prog * 2))
                local c = Config.COLORS[pour.color]
                local surfaceY = pour.riseLiquidTopY
                    + prog * pour.count * Config.TUBE.slotHeight
                local d = TubeRenderer.deriveTubeParams()
                local dropHalfH = d.innerWidth * Config.ANIM.droplet.baseWidth * 0.5
                    * math.sqrt(pour.aspect or 0.5)
                local threadTopY = pour.blobY + dropHalfH * 0.6
                if surfaceY > threadTopY + 2 then
                    local lineW = 2.0 * (1 - prog * 2)
                    nvgBeginPath(nvgCtx_)
                    nvgMoveTo(nvgCtx_, pour.blobX, threadTopY)
                    nvgLineTo(nvgCtx_, pour.blobX, surfaceY)
                    nvgStrokeColor(nvgCtx_, nvgRGBA(c[1], c[2], c[3], alpha))
                    nvgStrokeWidth(nvgCtx_, lineW)
                    nvgLineCap(nvgCtx_, NVG_ROUND)
                    nvgStroke(nvgCtx_)
                end
            end

            TubeRenderer.drawFlyingDroplet(nvgCtx_, {
                blobX    = pour.blobX,
                blobY    = pour.blobY,
                colorIdx = pour.color,
                count    = pour.count,
                aspect   = pour.aspect,
                rotation = pour.rotation,
            })
        end
    end

    -- 水花粒子（两种模式共用）
    local splashes = anims_:getSplashParticles()
    if #splashes > 0 then
        local function clamp255(v) return math.max(0, math.min(255, math.floor(v))) end
        for _, sp in ipairs(splashes) do
            local c = Config.COLORS[sp.colorIdx]
            local life = sp.timer / sp.lifetime
            local alpha = math.floor(220 * (1 - life))
            local r = sp.r * (1 - life * 0.5)
            nvgBeginPath(nvgCtx_)
            nvgCircle(nvgCtx_, sp.x, sp.y, r)
            nvgFillColor(nvgCtx_, nvgRGBA(
                clamp255(c[1] + 30), clamp255(c[2] + 30), clamp255(c[3] + 30), alpha))
            nvgFill(nvgCtx_)
        end
    end

    nvgEndFrame(nvgCtx_)
end

-- ============================================================
-- HUD
-- ============================================================

--- 模式按钮引用（用于更新文本）
local modeBtnRef_ = nil

local function getModeLabel()
    if Config.POUR_MODE == "stream" then
        return "模式: 倾倒"
    else
        return "模式: 飞行"
    end
end

function CreateHUD()
    local modeBtn = UI.Button {
        text = getModeLabel(), variant = "outline",
        onClick = function(self)
            -- 动画进行中禁止切换
            if anims_ and anims_:isPourActive() then return end
            if Config.POUR_MODE == "stream" then
                Config.POUR_MODE = "droplet"
            else
                Config.POUR_MODE = "stream"
            end
            self.text = getModeLabel()
        end,
    }
    modeBtnRef_ = modeBtn

    local root = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            -- 顶部标题
            UI.Label {
                text = "倒水美术切片",
                fontSize = 22,
                fontColor = { 200, 220, 255, 200 },
                marginTop = 20,
            },
            -- 底部按钮
            UI.Panel {
                flexDirection = "row",
                gap = 24,
                marginBottom = 30,
                children = {
                    UI.Button {
                        text = "重置", variant = "secondary",
                        onClick = function()
                            game_:reset()
                            anims_ = AnimationManager.new(#game_.tubes)
                            updateLayout()
                        end,
                    },
                    UI.Button {
                        text = "刷新", variant = "primary",
                        onClick = function()
                            game_:randomize(3, 2)
                            anims_ = AnimationManager.new(#game_.tubes)
                            updateLayout()
                        end,
                    },
                    modeBtn,
                },
            },
        },
    }
    UI.SetRoot(root)
end
