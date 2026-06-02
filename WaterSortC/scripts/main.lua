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
    if game.isAnimating or game.isWin then return end

    if game.selectedTube == nil then
        game:select(tubeIdx)
    elseif game.selectedTube == tubeIdx then
        game:select(nil)
    else
        local srcIdx = game.selectedTube
        if game:canPour(srcIdx, tubeIdx) then
            -- 开始倾倒动画（数据不立即移动，动画结束后才提交）
            local pourCount = game:getPourCount(srcIdx, tubeIdx)
            local pourColor = game:getTopColor(srcIdx)
            local srcSnapshot = game:getTubeSnapshot(srcIdx)
            game:saveUndoState()
            -- 从源管移除顶层（动画期间源管显示用 srcSnapshot）
            local src = game.tubes[srcIdx]
            for _ = 1, pourCount do
                table.remove(src)
            end
            game.selectedTube = nil
            game.isAnimating = true
            anim:startPour(srcIdx, tubeIdx, pourCount, pourColor, srcSnapshot)
        else
            anim:startShake(tubeIdx)
            if #game.tubes[tubeIdx] > 0 then
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
    local pour = anim.pour

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
        if pour.phase ~= "none" and i == pour.srcIdx then
            goto continue
        end

        local pos = positions[i]
        local cx = l.x + pos.x
        local cy = l.y + pos.y + (anim.tubeOffsetY[i] or 0)

        local shakeX = anim:getShakeOffsetX(i)
        local bounceY = anim:getWinBounceY(i)

        -- 目标管动画时水面上升
        local extraFill = 0
        local extraColor = nil
        if (pour.phase == "pour" or pour.phase == "return") and i == pour.dstIdx then
            extraFill = pour.pouredSoFar
            extraColor = pour.pourColor
        end

        -- 绘制瓶子底层（管壁）
        Renderer.drawGlassShellBase(nvg, cx + shakeX, cy + bounceY)
        -- 绘制水层
        Renderer.drawStaticTubeLayers(nvg, cx + shakeX, cy + bounceY,
            game.tubes[i], extraFill, extraColor)
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

        ::continue::
    end

    -- 动画源试管
    if pour.phase ~= "none" then
        self:drawAnimSource(nvg, l, positions)
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

function GameCanvas:drawAnimSource(nvg, layout, positions)
    local pour = anim.pour
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

    -- 管内水层
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
        local dstTube = game.tubes[pour.dstIdx]
        local fillTotal = #dstTube + pour.pouredSoFar  -- 包含正在倒入的量
        Renderer.drawWaterStream(nvg, startX, startY, dstCX, dstCY, fillTotal, pour.pourColor)
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
            if game:undo() then
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
                elseif not game.isAnimating then
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
        fonts = {{ family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }},
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

    local pourFinished = anim:update(dt, game.selectedTube, game.tubeCount)

    -- 倾倒动画完成后：提交数据到目标管，检查胜利
    if pourFinished then
        local pour = anim.pour
        local dst = game.tubes[pour.dstIdx]
        for _ = 1, pour.pourLayers do
            table.insert(dst, pour.pourColor)
        end
        game.isAnimating = false
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
