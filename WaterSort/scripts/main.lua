-- ============================================================
-- main.lua - 水排序游戏 (Water Sort Puzzle)
-- 模块化入口：组装 Config / GameState / Animation / Renderer
-- ============================================================

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")

local Config = require("config")
local GameState = require("GameState")
local Animation = require("Animation")
local Renderer = require("Renderer")

-- ============================================================
-- 实例
-- ============================================================
local game = GameState.new()
local anim = Animation.new()

local canvasWidget = nil
local levelLabel = nil
local nextLevelBtn = nil

-- ============================================================
-- 游戏流程
-- ============================================================

local function startLevel(level)
    game:loadLevel(level)
    anim:initOffsets(game.tubeCount)
    anim:stopWin()
    if levelLabel then
        levelLabel:SetText("关卡: Lv." .. game.level)
    end
    if nextLevelBtn then
        nextLevelBtn:SetStyle({ opacity = 0 })
    end
end

local function handleTubeTap(tubeIdx)
    if game.isWin then return end

    if game.selectedTube == nil then
        -- 尝试选中（含并发锁检查）
        if game:canSelectAsSource(tubeIdx) then
            game:select(tubeIdx)
        else
            anim:startShake(tubeIdx)
        end
    elseif game.selectedTube == tubeIdx then
        game:select(nil)
    else
        local srcIdx = game.selectedTube
        if game:canPour(srcIdx, tubeIdx) then
            -- 数据先行：立即提交状态变更
            local pourInfo = game:commitPour(srcIdx, tubeIdx)
            if pourInfo then
                game.selectedTube = nil
                anim:startPour(pourInfo)
            end
        else
            anim:startShake(tubeIdx)
            if game:canSelectAsSource(tubeIdx) then
                game:select(tubeIdx)
            else
                game:select(nil)
            end
        end
    end
end

local function hitTestTube(localX, localY, canvasW, canvasH)
    local positions = Renderer.getTubePositions(canvasW, canvasH, game.tubeCount)
    local tube = Config.tube
    local tubeH = Renderer.getTubeHeight()
    local padX, padY = 8, 12
    for i = 1, game.tubeCount do
        local pos = positions[i]
        local left = pos.x - tube.width / 2 - padX
        local right = pos.x + tube.width / 2 + padX
        local top = pos.y - tubeH / 2 - Config.interaction.selectOffset - padY
        local bottom = pos.y + tubeH / 2 + padY
        if localX >= left and localX <= right and localY >= top and localY <= bottom then
            return i
        end
    end
    return nil
end

-- ============================================================
-- 自定义 Canvas Widget
-- ============================================================
local GameCanvas = Widget:Extend("GameCanvas")

function GameCanvas:Render(nvg)
    self:RenderFullBackground(nvg)
    local l = self:GetAbsoluteLayout()
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    local theme = Config.getTheme()
    local tube = Config.tube
    local render = Config.render

    -- 渐变背景
    local bg = theme.background
    local bgPaint = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h,
        nvgRGBA(bg.gradientTop[1], bg.gradientTop[2], bg.gradientTop[3], bg.gradientTop[4]),
        nvgRGBA(bg.gradientBottom[1], bg.gradientBottom[2], bg.gradientBottom[3], bg.gradientBottom[4]))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, bgPaint)
    nvgFill(nvg)

    local positions = Renderer.getTubePositions(l.w, l.h, game.tubeCount)
    local tubeH = Renderer.getTubeHeight()

    -- 静态试管
    for i = 1, game.tubeCount do
        -- 跳过正在作为源管动画的管（由 drawAnimSources 单独渲染）
        if anim:getAnimForSource(i) then
            goto continue
        end

        local pos = positions[i]
        local cx = l.x + pos.x
        local cy = l.y + pos.y + (anim.tubeOffsetY[i] or 0)

        local shakeX = anim:getShakeOffsetX(i)
        local bounceY = anim:getWinBounceY(i)

        -- 目标管动画时水面上升（支持多个并发倒入）
        -- 数据先行后，目标管数据已包含新层，需隐去"动画中未到达"的层数
        -- 用 hideLayers 从真实数据中截掉顶部未到达层，extraFill 表现渐入进度
        local hideLayers = 0
        local extraFill = 0
        local extraColor = nil
        for _, a in ipairs(anim.activeAnims) do
            if a.dstIdx == i then
                if a.phase == "move" or a.phase == "tilt" then
                    hideLayers = hideLayers + a.pourLayers
                elseif a.phase == "pour" then
                    hideLayers = hideLayers + a.pourLayers
                    extraFill = extraFill + a.pouredSoFar
                    extraColor = a.pourColor
                end
                -- "return" 阶段：所有层已视觉到位，不隐藏
            end
        end

        -- 截掉尚未动画到达的顶部层
        local visibleLayers = game.tubes[i]
        if hideLayers > 0 then
            visibleLayers = {}
            local total = #game.tubes[i]
            for j = 1, total - hideLayers do
                visibleLayers[j] = game.tubes[i][j]
            end
        end

        -- 绘制瓶子底层（管壁）
        Renderer.drawGlassShellBase(nvg, cx + shakeX, cy + bounceY)
        -- 绘制水层（用截断后的层 + extraFill 表现动画进度）
        Renderer.drawStaticTubeLayers(nvg, cx + shakeX, cy + bounceY,
            visibleLayers, extraFill, extraColor)
        -- 绘制瓶子高光层（管口+底部高光）
        Renderer.drawGlassShellHighlights(nvg, cx + shakeX, cy + bounceY)

        -- 选中光圈
        if game.selectedTube == i then
            nvgBeginPath(nvg)
            nvgEllipse(nvg, cx + shakeX, cy + tubeH / 2 + 8 + bounceY, tube.width / 2, 5)
            nvgFillColor(nvg, nvgRGBA(90, 170, 255, render.selectGlowAlpha))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgEllipse(nvg, cx + shakeX, cy + tubeH / 2 + 8 + bounceY, tube.width / 2 - 6, 3)
            nvgFillColor(nvg, nvgRGBA(120, 200, 255, render.selectGlowInnerAlpha))
            nvgFill(nvg)
        end

        -- 封印管标记（锁图标 + 暗化覆盖）
        if game:isLocked(i) then
            local lockCX = cx + shakeX
            local lockCY = cy + bounceY - tubeH / 2 - 12
            -- 暗化覆盖
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, lockCX - tube.width / 2, cy + bounceY - tubeH / 2,
                tube.width, tubeH, 8)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 80))
            nvgFill(nvg)
            -- 锁图标
            nvgFontSize(nvg, 20)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 200, 60, 220))
            nvgText(nvg, lockCX, lockCY, "🔒")
            -- 解锁色提示（小圆点）
            local unlockColor = game.locks[i]
            if unlockColor then
                local themeColors = Config.getColors()
                local uc = themeColors[unlockColor]
                if uc then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, lockCX, lockCY + 14, 5)
                    nvgFillColor(nvg, nvgRGBA(uc[1], uc[2], uc[3], 220))
                    nvgFill(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 160))
                    nvgStrokeWidth(nvg, 1.0)
                    nvgStroke(nvg)
                end
            end
        end

        -- 单向管标记（向下箭头）
        if game:isSinkTube(i) then
            local sCX = cx + shakeX
            local sCY = cy + bounceY - tubeH / 2 - 8
            nvgFontSize(nvg, 16)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 100, 100, 200))
            nvgText(nvg, sCX, sCY, "⬇")
        end

        -- 临时管标记（容量数字 + 底部标签）
        if game:isTempTube(i) then
            local tCX = cx + shakeX
            local tCY = cy + bounceY + tubeH / 2 + 10
            local cap = game:getTempCapacity(i)
            nvgFontSize(nvg, 12)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(180, 220, 255, 200))
            nvgText(nvg, tCX, tCY, cap .. "/" .. Config.tube.layerCount)
        end

        ::continue::
    end

    -- 动画源试管（支持多个并发）
    for _, a in ipairs(anim.activeAnims) do
        self:drawAnimSource(nvg, l, positions, a)
    end

    -- 胜利效果
    if anim.win.active then
        Renderer.drawWinParticles(nvg, l.x, l.y, l.w, l.h, anim.win.particles)
    end
    if game.isWin then
        Renderer.drawWinText(nvg, l.x + l.w / 2, l.y + 55)
    end

    nvgRestore(nvg)
end

function GameCanvas:drawAnimSource(nvg, layout, positions, pour)
    local tube = Config.tube
    local render = Config.render
    local srcPos = positions[pour.srcIdx]
    local dstPos = positions[pour.dstIdx]
    local srcCX = layout.x + srcPos.x
    local srcCY = layout.y + srcPos.y + (anim.tubeOffsetY[pour.srcIdx] or 0)
    local dstCX = layout.x + dstPos.x
    local dstCY = layout.y + dstPos.y + (anim.tubeOffsetY[pour.dstIdx] or 0)

    local isLeft = srcPos.x <= dstPos.x
    local tiltDir = isLeft and 1 or -1

    local halfW = tube.width / 2
    local halfH = Renderer.getTubeHeight() / 2

    local pivotLocalX = isLeft and halfW or -halfW
    local pivotLocalY = -halfH

    local targetPivotX = dstCX + (isLeft and -render.pourTipOffset or render.pourTipOffset)
    local targetPivotY = dstCY - halfH - render.pourAboveOffset
    local targetCX = targetPivotX - pivotLocalX
    local targetCY = targetPivotY - pivotLocalY

    local curCX, curCY, curAngle = srcCX, srcCY, 0
    local animCfg = Config.animation

    local srcTotal = #pour.srcOrigLayers
    local angleStart = Animation.getTiltAngleForRemaining(srcTotal)
    local angleEnd = Animation.getTiltAngleForRemaining(srcTotal - pour.pourLayers)

    if pour.phase == "move" then
        local t = Animation.Easing.inOutQuad(Animation.clamp(pour.timer / animCfg.moveDuration, 0, 1))
        curCX = Animation.lerp(srcCX, targetCX, t)
        curCY = Animation.lerp(srcCY, targetCY, t)
    elseif pour.phase == "tilt" then
        curCX = targetCX
        curCY = targetCY
        local t = Animation.Easing.outQuad(Animation.clamp(pour.timer / animCfg.tiltDuration, 0, 1))
        curAngle = angleStart * tiltDir * t
    elseif pour.phase == "pour" then
        curCX = targetCX
        curCY = targetCY
        local effectiveRemaining = srcTotal - pour.pouredSoFar
        curAngle = Animation.getTiltAngleForRemaining(effectiveRemaining) * tiltDir
    elseif pour.phase == "return" then
        local t = Animation.Easing.inOutQuad(Animation.clamp(pour.timer / animCfg.returnDuration, 0, 1))
        curCX = Animation.lerp(targetCX, srcCX, t)
        curCY = Animation.lerp(targetCY, srcCY, t)
        curAngle = angleEnd * tiltDir * (1 - t)
    end

    local removedCount = 0
    if pour.phase == "pour" then
        removedCount = pour.pouredSoFar
    elseif pour.phase == "return" then
        removedCount = pour.pourLayers
    end

    local pivotWX = curCX + pivotLocalX
    local pivotWY = curCY + pivotLocalY

    -- 旋转管壁底层
    nvgSave(nvg)
    nvgTranslate(nvg, pivotWX, pivotWY)
    nvgRotate(nvg, curAngle)
    nvgTranslate(nvg, -pivotWX, -pivotWY)
    Renderer.drawGlassShellBase(nvg, curCX, curCY)
    nvgRestore(nvg)

    -- 管内水层（用快照渲染，不用实时管数据）
    if #pour.srcOrigLayers - math.floor(removedCount) > 0 then
        Renderer.drawTiltedWater(nvg, curCX, curCY, pivotWX, pivotWY, curAngle,
            pour.srcOrigLayers, removedCount)
    end

    -- 旋转管壁高光层
    nvgSave(nvg)
    nvgTranslate(nvg, pivotWX, pivotWY)
    nvgRotate(nvg, curAngle)
    nvgTranslate(nvg, -pivotWX, -pivotWY)
    Renderer.drawGlassShellHighlights(nvg, curCX, curCY)
    nvgRestore(nvg)

    -- 水流
    if pour.phase == "pour" and removedCount < pour.pourLayers then
        local tipX = curCX + (isLeft and halfW or -halfW)
        local tipY = curCY - halfH
        local startX, startY = Renderer.rotatePoint(tipX, tipY, pivotWX, pivotWY, curAngle)
        -- 水流终点 = 目标管实际视觉液面（考虑所有并发动画的隐藏量）
        local dstTube = game.tubes[pour.dstIdx]
        local totalHide = 0
        local totalExtra = 0
        for _, a in ipairs(anim.activeAnims) do
            if a.dstIdx == pour.dstIdx then
                if a.phase == "move" or a.phase == "tilt" then
                    totalHide = totalHide + a.pourLayers
                elseif a.phase == "pour" then
                    totalHide = totalHide + a.pourLayers
                    totalExtra = totalExtra + a.pouredSoFar
                end
            end
        end
        local visualFill = #dstTube - totalHide + totalExtra
        Renderer.drawWaterStream(nvg, startX, startY, dstCX, dstCY, visualFill, pour.pourColor)
    end
end

-- ============================================================
-- UI 构建
-- ============================================================

local function buildUI()
    levelLabel = UI.Label {
        text = "关卡: Lv." .. game.level,
        fontSize = 18,
        fontColor = { 255, 255, 255, 240 },
    }

    local undoBtn = UI.Button {
        text = "撤回",
        fontSize = 14,
        onClick = function()
            if game:undo(anim:hasActiveAnims()) then
                anim:stopWin()
            end
        end,
    }

    local resetBtn = UI.Button {
        text = "重置",
        fontSize = 14,
        onClick = function() startLevel(game.level) end,
    }

    nextLevelBtn = UI.Button {
        text = "下一关",
        fontSize = 16,
        onClick = function()
            startLevel(game.level + 1)
        end,
    }
    nextLevelBtn:SetStyle({ opacity = 0 })

    canvasWidget = GameCanvas {
        id = "gameCanvas",
        flexGrow = 1,
        width = "100%",
        onPointerDown = function(event, widget)
            if event.button == MOUSEB_LEFT then
                local lt = widget:GetAbsoluteLayout()
                local localX = event.x - lt.x
                local localY = event.y - lt.y
                local idx = hitTestTube(localX, localY, lt.w, lt.h)
                if idx then
                    handleTubeTap(idx)
                else
                    game:select(nil)
                end
            end
        end,
    }

    local theme = Config.getTheme()

    local topBar = UI.Panel {
        width = "100%",
        height = 46,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 16,
        backgroundColor = theme.topBar,
        children = {
            levelLabel,
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = { undoBtn, resetBtn },
            },
        },
    }

    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 18, 22, 38, 255 },
        children = {
            topBar,
            canvasWidget,
            UI.Panel {
                width = "100%",
                height = 52,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 22, 28, 45, 255 },
                children = { nextLevelBtn },
            },
        },
    })
end

-- ============================================================
-- 引擎入口
-- ============================================================

function Start()
    math.randomseed(os.time())
    UI.Init({
        fonts = {{ family = "sans", weights = { normal = "Fonts/LongZhuTi-Regular.ttf", bold = "Fonts/LongZhuTi-Regular.ttf" } }},
        scale = UI.Scale.DEFAULT,
    })
    startLevel(1)
    buildUI()
    SubscribeToEvent("Update", "HandleUpdate")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    local completedAnims = anim:update(dt, game.selectedTube, game.tubeCount)

    -- 处理本帧完成的所有动画
    for _, a in ipairs(completedAnims) do
        -- 解锁源管、减少目标接收计数
        game:unlockSource(a.srcIdx)
        game:removeReceiving(a.dstIdx)

        -- 揭雾检查: 源管顶层可能是隐藏层
        game:revealTopIfHidden(a.srcIdx)

        -- 解锁检查: 是否有封印管因纯色完成而解锁
        local unlocked = game:checkUnlocks()
        if unlocked then
            game:revealTopIfHidden(unlocked.tubeIdx)
        end
    end

    -- 胜利检查（所有动画完成时才判定）
    if #completedAnims > 0 and not anim:hasActiveAnims() then
        if game:checkWin() then
            game.isWin = true
            anim:startWin()
        end
    end

    -- 显示下一关按钮
    if game.isWin and nextLevelBtn then
        nextLevelBtn:SetStyle({ opacity = 1 })
    end
end

function Stop()
    UI.Shutdown()
end
