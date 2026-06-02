-- main.lua
-- 齿轮分拣 (Gear Sort) MVP 入口
-- 竖屏游戏，NanoVG 绘制齿轮，urhox-libs/UI 叠加 HUD

local GameState      = require("game_state")
local Renderer       = require("renderer")
local UIOverlay      = require("ui_overlay")
local MainMenu       = require("main_menu")
local Levels         = require("levels")
local SoundManager   = require("sound_manager")
local SaveManager    = require("save_manager")
local Solver         = require("solver")
local Tutorial       = require("tutorial")
local CoinFlyEffect  = require("coin_fly_effect")
local UIAnim         = require("ui_anim")
local UI             = require("urhox-libs/UI")

-- ---------------------------------------------------------------
-- 全局状态
-- ---------------------------------------------------------------
local nvgCtx_       = nil
local W_            = 0
local H_            = 0

-- 场景阶段："menu" | "game"
local phase_        = "menu"

-- 待传给飞金币演出的金币数（通关时记录，返回主界面时使用）
local pendingFlyCoins_ = 0

local selectedPeg_  = nil   -- 当前选中的插板下标（nil=未选中）
local validTargets_ = {}    -- 可移动目标下标列表

-- 输入锁（动画播放期间禁止执行移动，但允许预选操作）
local inputLocked_  = false

-- 动画期间的预排队操作（最多保留1步）
local queuedMove_   = nil   -- { from, to, count, pegWasComplete, lockedBefore }
local queuedSelect_ = nil   -- 动画期间临时记录选中的插板（无预排队时使用）

-- 待显示胜利弹窗（等封盖+灯条动画全部结束后弹出）
local pendingWin_          = false
local pendingWinMoves_     = 0
local pendingWinBest_      = 0
local pendingWinDelay_     = 0   -- AllSealsSettled 后的延迟倒计时（秒）
local pendingWinCoins_     = 0   -- 本局获得金币数
local pendingWinStreak_    = 0   -- 通关后连胜数
local pendingWinMultiplier_= 1.0 -- 本次倍率
local winCoinFlyTimer_     = -1  -- 胜利弹窗弹出后延迟飞金币的计时（-1=未激活）
local winCoinFlyRetry_     = false  -- 是否处于重试等待（坐标尚未就绪）
local backMenuFlyCoins_    = 0   -- 返回主界面时待飞的金币数（等待布局稳定后触发）
local backMenuFlyDelay_    = -1  -- 返回主界面飞金币的延迟计时（-1=未激活）

-- ---------------------------------------------------------------
-- Start / Stop
-- ---------------------------------------------------------------
function Start()
    graphics.windowTitle = "齿轮分拣"

    -- NanoVG 上下文
    nvgCtx_ = nvgCreate(1)
    nvgCreateFont(nvgCtx_, "sans", "Fonts/LongZhuTi-Regular.ttf")
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleRender")

    -- 加载齿轮图片（白色基础图 + 代码着色）
    Renderer.Init(nvgCtx_)

    -- 加载 hint_ring 图片（提示光圈特效）
    local hintRingNvg = nvgCreateImage(nvgCtx_, "image/hint_ring_20260601092224.png", 0)
    if hintRingNvg and hintRingNvg > 0 then
        Renderer.SetHintRingImage(hintRingNvg)
        print("[Main] hint_ring 图片加载成功 handle=" .. hintRingNvg)
    else
        print("[Main] WARN: hint_ring.png 未找到，使用线框回退")
    end

    -- 教程动画初始化（加载手指图片）
    Tutorial.Init(nvgCtx_)

    -- UI 层（先初始化，但暂不 SetRoot）
    UIOverlay.Init({
        onUndo        = HandleUndo,
        onReset       = HandleReset,
        onNextLevel   = HandleNextLevel,
        onSelectLevel = HandleSelectLevel,
        onResume      = EnterMenu,
        onTempHub     = HandleTempHub,
        onBackMenu    = HandleBackMenu,
    })

    -- 音效 & 存档（云存档异步加载，加载完成后重建主界面以显示真实连胜/金币）
    SoundManager.Init()
    SaveManager.LoadAsync(function(success)
        print(string.format("[Main] 云存档加载%s", success and "成功" or "失败（使用默认值）"))
        -- 若此时仍在主界面，重建整个主界面以刷新连胜条、金币等所有动态数据
        if phase_ == "menu" then
            MainMenu.Show(nil)
        end
    end)

    -- 注册过渡遮罩为 UI GlobalComponent（在 UI 渲染末尾绘制，覆盖所有 UI 内容）
    UI.RegisterGlobalComponent("transition_overlay", {
        Render = function(_, vg)
            if not UIAnim.IsTransitioning() then return end
            -- 使用 UI 缩放后的画布尺寸（与 nvgBeginFrame 一致）
            local uiScale = UI.GetScale() or (graphics:GetDPR() or 1)
            local w = graphics:GetWidth() / uiScale
            local h = graphics:GetHeight() / uiScale
            UIAnim.DrawTransition(vg, w, h)
        end,
    })

    -- 事件订阅
    SubscribeToEvent("Update",          "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin",      "HandleTouchBegin")
    SubscribeToEvent("ScreenMode",      "HandleScreenMode")

    -- 启动时进入主界面
    EnterMenu()

    print("[Main] 齿轮分拣启动，共 " .. Levels.Count() .. " 关")
end

function Stop()
    UIOverlay.Shutdown()
    if nvgCtx_ then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
end

-- ---------------------------------------------------------------
-- 场景切换
-- ---------------------------------------------------------------
function EnterMenu()
    -- 内部实际执行切换（供直接调用或过渡中间回调）
    local function doEnterMenu()
        phase_ = "menu"
        selectedPeg_  = nil
        validTargets_ = {}
        Tutorial.Stop()
        winCoinFlyTimer_  = -1
        winCoinFlyRetry_  = false
        backMenuFlyDelay_ = -1
        backMenuFlyCoins_ = 0
        CoinFlyEffect.Stop()
        SoundManager.PlayBGM("menu")
        MainMenu.Show({
            onPlay = function()
                local lastLevel  = SaveManager.GetLastLevel() or 1
                local startLevel = math.max(1, lastLevel)
                EnterGame(startLevel)
            end,
            onSelectLevel = function()
                MainMenu.ShowLevelSelect()
            end,
            onSelectLevelStart = function(idx)
                EnterGame(idx)
            end,
            onBag = function()
                print("[Main] 背包（暂未实现）")
            end,
        })
        print("[Main] 进入主界面")
    end

    -- 如果当前在游戏中，使用过渡动画切回菜单
    if phase_ == "game" and not UIAnim.IsTransitioning() then
        UIAnim.StartTransition({
            onMidpoint = function()
                doEnterMenu()
            end,
        })
    else
        -- 首次启动或已在菜单中，直接执行
        doEnterMenu()
    end
end

function EnterGame(levelIdx)
    levelIdx = levelIdx or 1

    -- 若已在过渡中，跳过重复触发
    if UIAnim.IsTransitioning() then return end

    -- 启动圆形擦除过渡
    UIAnim.StartTransition({
        onMidpoint = function()
            -- 中间时刻：执行真正的场景切换
            phase_ = "game"
            MainMenu.Hide()
            UIOverlay.Show()
            SoundManager.PlayBGM("game")
            SaveManager.SetLastLevel(levelIdx)
            GameState.LoadLevel(levelIdx)
            selectedPeg_  = nil
            validTargets_ = {}
            inputLocked_  = false
            pendingWin_   = false
            queuedMove_   = nil
            queuedSelect_ = nil
            Renderer.ResetLevel()
            RefreshLayout()

            -- 第一关（教程关）启动引导动画
            local levelData = Levels.data[levelIdx]
            if levelData and levelData.isTutorial then
                Tutorial.Start()
            else
                Tutorial.Stop()
            end

            print(string.format("[Main] 进入游戏，关卡 %d", levelIdx))
        end,
    })
end

-- ---------------------------------------------------------------
-- 布局刷新
-- ---------------------------------------------------------------
function RefreshLayout()
    W_ = graphics:GetWidth()
    H_ = graphics:GetHeight()
    Renderer.RecalcLayout(W_, H_)
    UIOverlay.RefreshHUD()
    print(string.format("[Main] 布局刷新 %dx%d", W_, H_))
end

-- ---------------------------------------------------------------
-- 事件处理
-- ---------------------------------------------------------------
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    SoundManager.Update(dt)
    UIAnim.Update(dt)          -- 驱动 UI Tween 动画
    UIAnim.UpdateTransition(dt) -- 驱动关卡过渡效果

    -- 过渡遮罩通过 UI.RegisterGlobalComponent 在 UI 渲染末尾绘制（覆盖所有 UI）
    MainMenu.Update(dt)       -- 驱动道具飞行粒子
    UIOverlay.Update(dt)       -- 驱动广告倒计时
    Tutorial.Update(dt)        -- 驱动教程动画计时
    CoinFlyEffect.Update(dt)   -- 驱动飞金币粒子动画

    -- 胜利弹窗出现后的飞金币延迟触发（含重试，直到 UI 坐标就绪）
    -- 起点：弹窗内 "+N" 标签  目标：HUD 右上角金币图标
    if winCoinFlyTimer_ >= 0 then
        winCoinFlyTimer_ = winCoinFlyTimer_ - dt
        if winCoinFlyTimer_ <= 0 then
            local sx, sy = UIOverlay.GetWinCoinSourcePosition()
            local tx, ty = UIOverlay.GetHudCoinUIPosition()
            if sx and sy and tx and ty then
                -- 坐标就绪，发射
                winCoinFlyTimer_  = -1
                winCoinFlyRetry_  = false
                local numCoins = math.min(math.max(pendingWinCoins_, 1), 30)
                CoinFlyEffect.Play(sx, sy, tx, ty, numCoins, function()
                    UIOverlay.RefreshCoinDisplay()
                end)
            else
                -- 坐标尚未就绪，每帧重试（间隔 0.05s 避免空转太快）
                winCoinFlyTimer_ = 0.05
                if not winCoinFlyRetry_ then
                    winCoinFlyRetry_ = true
                    print("[Main] 飞金币：等待弹窗坐标就绪...")
                end
            end
        end
    end

    -- 返回主界面后延迟飞金币（等待 Yoga 布局稳定后再读目标坐标）
    -- 必须在 phase 检查之前，因为此时 phase 已经是 "menu"
    if backMenuFlyDelay_ >= 0 then
        backMenuFlyDelay_ = backMenuFlyDelay_ - dt
        if backMenuFlyDelay_ <= 0 then
            backMenuFlyDelay_ = -1
            local tx, ty = MainMenu.GetCoinUIPosition()
            if tx and ty then
                local dpr = graphics:GetDPR() or 1
                local sw  = graphics:GetWidth()  / dpr
                local sh  = graphics:GetHeight() / dpr
                local numCoins = math.min(math.max(backMenuFlyCoins_, 1), 30)
                CoinFlyEffect.Play(sw * 0.5, sh * 0.5, tx, ty, numCoins, function()
                    MainMenu.RefreshCoinDisplay()
                end)
                backMenuFlyCoins_ = 0
            else
                -- 坐标仍未就绪，再等一帧
                backMenuFlyDelay_ = 0.05
            end
        end
    end

    if phase_ ~= "game" then return end
    Renderer.Update(dt, selectedPeg_)

    -- 等封盖 + 灯条动画全部结束后，再延迟 0.5s 同时触发烟花和胜利窗
    if pendingWin_ then
        if pendingWinDelay_ < 0 then
            -- 阶段1：等待所有封盖动画结束
            if Renderer.AllSealsSettled() then
                -- 封盖落定：立即触发烟花，再等 1.2s 弹出弹窗（让玩家先看到粒子特效）
                Renderer.SpawnParticles(W_ / 2, H_ / 2)
                SoundManager.Play("shimmer", 0.5)
                pendingWinDelay_ = 1.2   -- 开始计时
            end
        else
            -- 阶段2：倒计时结束后弹出弹窗
            pendingWinDelay_ = pendingWinDelay_ - dt
            if pendingWinDelay_ <= 0 then
                pendingWin_ = false
                UIOverlay.ShowWin({
                    moves       = pendingWinMoves_,
                    bestMoves   = pendingWinBest_,
                    coinsEarned = pendingWinCoins_,
                    winStreak   = pendingWinStreak_,
                    multiplier  = pendingWinMultiplier_,
                    onReset     = function()
                        winCoinFlyTimer_ = -1
                        winCoinFlyRetry_ = false
                        CoinFlyEffect.Stop()
                        HandleReset()
                    end,
                    onNextLevel = function()
                        winCoinFlyTimer_ = -1
                        winCoinFlyRetry_ = false
                        CoinFlyEffect.Stop()
                        HandleNextLevel()
                    end,
                    onBackMenu  = function()
                        winCoinFlyTimer_ = -1
                        winCoinFlyRetry_ = false
                        CoinFlyEffect.Stop()
                        HandleBackMenu(pendingFlyCoins_)
                    end,
                })
                -- 弹窗出现后延迟 0.3 秒触发飞金币演出（飞向弹窗内的金币图标）
                winCoinFlyTimer_ = 0.3
            end
        end
    end

end

function HandleScreenMode(eventType, eventData)
    RefreshLayout()
end

-- ---------------------------------------------------------------
-- 执行一次移动（含动画、音效、解锁检测、通关检测）
-- 由 HandleClick 和 onDone 回调（排队移动）共同调用
-- ---------------------------------------------------------------
function ExecuteMove(from, to)
    local pegs  = GameState.GetPegs()
    local count = math.min(
        GameState.TopGroupCount(from),
        GameState.GetPegCapacity(to) - #pegs[to]
    )

    -- 快照：移动前的锁定状态 & 目标完成状态
    local pegWasComplete = GameState.IsPegCompleted(to)
    local lockedBeforeSnapshot = {}
    local lockedCountBefore = 0
    for pegIdx, color in pairs(GameState.GetLockedPegs()) do
        lockedBeforeSnapshot[pegIdx] = color
        lockedCountBefore = lockedCountBefore + 1
    end

    GameState.Move(from, to)
    UIOverlay.RefreshHUD()

    -- 解锁检测
    local lockedAfter = GameState.GetLockedPegs()
    local lockedCountAfter = 0
    for _ in pairs(lockedAfter) do lockedCountAfter = lockedCountAfter + 1 end
    local justUnlocked = lockedCountAfter < lockedCountBefore

    -- 音效
    if not justUnlocked and not (GameState.IsPegCompleted(to) and not pegWasComplete) then
        SoundManager.Play("gear_place")
        SoundManager.Play("gear_mesh", 0.5)
    end
    if justUnlocked then
        SoundManager.Play("peg_unlock")
        for pegIdx = 1, #GameState.GetPegs() do
            if not lockedAfter[pegIdx] and lockedBeforeSnapshot[pegIdx] then
                Renderer.TriggerUnlock(pegIdx)
            end
        end
    end

    -- 锁定输入，清空排队，播放动画
    inputLocked_  = true
    selectedPeg_  = nil
    validTargets_ = {}
    queuedMove_   = nil
    queuedSelect_ = nil

    -- SoundManager.Play("gear_rotate", 0.4)
    Renderer.PlayMoveAnim(from, to, count, function()
        inputLocked_ = false

        -- 动画结束后判断插板完成
        local justCompleted = GameState.IsPegCompleted(to) and not pegWasComplete
        if justCompleted then
            SoundManager.Play("peg_complete")
            SoundManager.Play("sparkle", 0.6)
            Renderer.TriggerSeal(to)
        end

        -- 检查通关
        if GameState.IsSolved() then
            local levelIdx  = GameState.GetLevelIndex()
            local moves     = GameState.GetMoveCount()
            -- 必须在 RecordWin 之前读倍率，RecordWin 内部会先用当前倍率算金币再累加连胜
            local multiplier  = SaveManager.GetStreakMultiplier()
            -- RecordWin：自动累加连胜、发放金币，返回本次获得金币数
            local coinsEarned = SaveManager.RecordWin(levelIdx, moves)
            -- 通关后把"继续游戏"指针推进到下一关（关卡数可无限增长，超出配置范围时复用最后一关配置）
            local nextLevel = levelIdx + 1
            SaveManager.SetLastLevel(nextLevel)
            -- 任务系统：累加通关计数
            SaveManager.IncrTaskCleared()
            local bestMoves   = SaveManager.GetBestMoves(levelIdx)
            local winStreak   = SaveManager.GetWinStreak()
            local newMultiplier = SaveManager.GetStreakMultiplier()
            pendingFlyCoins_  = coinsEarned
            SoundManager.Play("level_win")
            if newMultiplier > multiplier then
                SoundManager.Play("rank_up", 0.7)
            end
            pendingWin_      = true
            pendingWinDelay_ = -1
            pendingWinMoves_ = moves
            pendingWinBest_  = bestMoves
            -- 打包通关弹窗所需数据（等动画结束后用）
            pendingWinCoins_      = coinsEarned
            pendingWinStreak_     = winStreak
            pendingWinMultiplier_ = multiplier
            queuedMove_      = nil
            queuedSelect_    = nil
            return
        end

        -- 检查死锁
        if not GameState.HasAnyMove() then
            SoundManager.Play("level_lose")
            UIOverlay.ShowLose({
                winStreak    = SaveManager.GetWinStreak(),
                coinBalance  = SaveManager.GetCoins(),
                onKeepStreak = function()
                    -- 花费900金币：直接添加空白插板继续游戏（不受 adContinueUsed_ 限制）
                    if SaveManager.SpendCoins(900) then
                        UIOverlay.HideLose()
                        -- 直接添加空白插板（绕过 CanAdContinue 守卫）
                        Renderer.BeginLayoutTransition({ duration = 0.4 })
                        local curPegs = GameState.GetPegs()
                        curPegs[#curPegs + 1] = {}
                        selectedPeg_  = nil
                        validTargets_ = {}
                        W_ = graphics:GetWidth()
                        H_ = graphics:GetHeight()
                        Renderer.RecalcLayout(W_, H_)
                        Renderer.CommitLayoutTransition()
                        UIOverlay.RefreshHUD()
                        SoundManager.Play("peg_unlock")
                        print(string.format("[Main] 花费900金币，继续游戏并获得空白插板，当前插板数 %d", #curPegs))
                    end
                end,
                onReset = function()
                    if SaveManager.GetWinStreak() > 0 then
                        SoundManager.Play("chain_break", 0.7)
                    end
                    SaveManager.ResetWinStreak()
                    HandleReset()
                end,
                onSelectLevel = function()
                    if SaveManager.GetWinStreak() > 0 then
                        SoundManager.Play("chain_break", 0.7)
                    end
                    SaveManager.ResetWinStreak()
                    UIOverlay.ToggleLevelSelect()
                end,
                onAdContinue = GameState.CanAdContinue() and function()
                    UIOverlay.HideLose()
                    UIOverlay.ShowAdDialog({
                        title   = "继续游戏",
                        desc    = "观看广告，获得一个空白插板\n帮助你继续完成本关",
                        icon    = "image/icon_camp_order_20260601091034.png",
                        autoPlay = true,
                        onGrant = function()
                            ActivateAdContinue()
                        end,
                    })
                end or nil,
                onBackMenu = function()
                    if SaveManager.GetWinStreak() > 0 then
                        SoundManager.Play("chain_break", 0.7)
                    end
                    SaveManager.ResetWinStreak()
                    HandleBackMenu(0)
                end,
            })
            queuedMove_   = nil
            queuedSelect_ = nil
            return
        end

        -- 执行排队的移动（如果有）
        if queuedMove_ then
            local qm = queuedMove_
            queuedMove_ = nil
            -- 验证排队移动仍然合法
            if GameState.CanMove(qm.from, qm.to) then
                Tutorial.Stop()
                ExecuteMove(qm.from, qm.to)
                return
            end
        end

        -- 恢复预选状态（如果有）
        if queuedSelect_ then
            local qs = queuedSelect_
            queuedSelect_ = nil
            local pegsNow = GameState.GetPegs()
            if #pegsNow[qs] > 0
                and not GameState.IsPegCompleted(qs)
                and not GameState.IsPegLocked(qs)
                and not GameState.IsPegSink(qs)
            then
                selectedPeg_  = qs
                validTargets_ = GameState.ValidTargets(qs)
            end
        end
    end)
end

-- 统一处理点击坐标
function HandleClick(px, py)
    if phase_ ~= "game" then return end
    if UIOverlay.IsModalOpen() then return end
    if GameState.IsSolved() then return end

    local hitPeg = Renderer.HitTestPeg(px, py)

    -- 任何点击都清除提示高亮
    Renderer.ClearHint()

    -- ── 动画播放期间：只允许预选操作 ────────────────────────────
    if inputLocked_ then
        if hitPeg == nil then
            -- 点击空白：清除预选和排队
            queuedMove_   = nil
            queuedSelect_ = nil
            return
        end

        local pegs = GameState.GetPegs()

        if queuedMove_ == nil and queuedSelect_ == nil then
            -- 尚无预选：选中一个来源插板
            if #pegs[hitPeg] == 0 then return end
            if GameState.IsPegCompleted(hitPeg) then return end
            if GameState.IsPegLocked(hitPeg) then return end
            if GameState.IsPegSink(hitPeg) then return end
            queuedSelect_ = hitPeg
            SoundManager.Play("gear_select")
        elseif queuedMove_ == nil and queuedSelect_ ~= nil then
            if hitPeg == queuedSelect_ then
                -- 再次点击同一插板：取消预选
                queuedSelect_ = nil
                return
            end
            -- 尝试排队移动
            if GameState.CanMove(queuedSelect_, hitPeg) then
                queuedMove_   = { from = queuedSelect_, to = hitPeg }
                queuedSelect_ = nil
                SoundManager.Play("gear_place")
            else
                -- 目标不合法：改选新来源
                local pegsNow = GameState.GetPegs()
                if #pegsNow[hitPeg] > 0
                    and not GameState.IsPegCompleted(hitPeg)
                    and not GameState.IsPegLocked(hitPeg)
                    and not GameState.IsPegSink(hitPeg)
                then
                    queuedSelect_ = hitPeg
                    SoundManager.Play("gear_select")
                else
                    queuedSelect_ = nil
                    SoundManager.Play("move_invalid")
                end
            end
        else
            -- 已有排队移动：点击可替换目标或取消
            if queuedMove_ and hitPeg == queuedMove_.to then
                -- 点击相同目标：取消排队
                queuedMove_ = nil
            else
                -- 不做更多操作，最多保留1步排队
            end
        end
        return
    end

    -- ── 正常状态（无动画）────────────────────────────────────────
    if hitPeg == nil then
        selectedPeg_  = nil
        validTargets_ = {}
        return
    end

    if selectedPeg_ == nil then
        -- 没有选中：选中此插板（非空、未完成）
        local pegs = GameState.GetPegs()
        if #pegs[hitPeg] == 0 then return end
        if GameState.IsPegCompleted(hitPeg) then return end
        if GameState.IsPegLocked(hitPeg) then return end
        if GameState.IsPegSink(hitPeg) then return end

        selectedPeg_  = hitPeg
        validTargets_ = GameState.ValidTargets(hitPeg)
        SoundManager.Play("gear_select")
    else
        if hitPeg == selectedPeg_ then
            -- 再次点击同一插板：取消选中
            SoundManager.Play("gear_remove", 0.5)
            selectedPeg_  = nil
            validTargets_ = {}
            return
        end

        -- 尝试移动
        if GameState.CanMove(selectedPeg_, hitPeg) then
            Tutorial.Stop()
            ExecuteMove(selectedPeg_, hitPeg)
        else
            -- 移动非法：保持当前选中
            SoundManager.Play("move_invalid")
        end
    end
end

function HandleMouseDown(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    HandleClick(x, y)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    HandleClick(x, y)
end

-- ---------------------------------------------------------------
-- 道具回调
-- ---------------------------------------------------------------

-- 临时插板：点击道具栏按钮触发，弹出购买弹窗（花1000金币 or 看广告）
function HandleTempHub()
    if inputLocked_ then return end
    if not GameState.CanUseTempHub() then return end

    local stockCount = SaveManager.GetTempHubCount()
    if stockCount > 0 then
        -- 有库存：直接消耗
        SaveManager.UseTempHub()
        ActivateTempHub()
        return
    end

    -- 无库存：弹广告/金币购买
    local coins = SaveManager.GetCoins()
    UIOverlay.ShowAdDialog({
        title   = "临时插板",
        desc    = string.format("放置一块只有1格的临时插板\n帮助临时转移一个齿轮\n\n当前金币：%d", coins),
        icon    = "image/icon_camp_order_20260601091034.png",
        coinCost    = 1000,
        onSpendCoins = function()
            if SaveManager.SpendCoins(1000) then
                ActivateTempHub()
            else
                print("[Main] 金币不足，无法使用临时插板")
            end
        end,
        onGrant = function()
            ActivateTempHub()
        end,
    })
end

-- 激活临时插板（内部函数）
function ActivateTempHub()
    if not GameState.CanUseTempHub() then return end

    -- 获取道具按钮的屏幕坐标作为飞入起点
    local btnX, btnY = UIOverlay.GetTempHubBtnScreenPos()

    -- 快照旧布局（Begin 在 GameState 变化前调用）
    -- 注意：newIdx 还不知道，先 Begin，用 GameState.PegCount()+1 推测新插板索引
    local futureIdx = GameState.PegCount() + 1
    Renderer.BeginLayoutTransition({
        duration = 0.4,
        flyIn = (btnX and btnY) and {
            pegIdx = futureIdx,
            startX = btnX,
            startY = btnY,
        } or nil,
    })

    local newIdx = GameState.UseTempHub()
    if newIdx then
        selectedPeg_  = nil
        validTargets_ = {}
        -- 重新计算布局（新的插板数）
        W_ = graphics:GetWidth()
        H_ = graphics:GetHeight()
        Renderer.RecalcLayout(W_, H_)
        -- 提交过渡（快照新布局，启动动画）
        Renderer.CommitLayoutTransition()
        UIOverlay.RefreshHUD()
        SoundManager.Play("peg_unlock")
        print(string.format("[Main] 临时插板已激活，插板下标 %d（带过渡动画）", newIdx))
    else
        -- UseTempHub 失败，取消过渡
        Renderer.CancelLayoutTransition()
    end
end

-- 广告续命：添加一根正常容量的空白插板继续游戏
function ActivateAdContinue()
    if not GameState.CanAdContinue() then return end

    Renderer.BeginLayoutTransition({ duration = 0.4 })

    local newIdx = GameState.UseAdContinue()
    if newIdx then
        selectedPeg_  = nil
        validTargets_ = {}
        W_ = graphics:GetWidth()
        H_ = graphics:GetHeight()
        Renderer.RecalcLayout(W_, H_)
        Renderer.CommitLayoutTransition()
        UIOverlay.RefreshHUD()
        SoundManager.Play("peg_unlock")
        print(string.format("[Main] 广告续命已激活，新增空白插板下标 %d", newIdx))
    else
        Renderer.CancelLayoutTransition()
    end
end

function HandleUndo()
    if inputLocked_ then return end
    local ok, relocked = GameState.Undo()
    if ok then
        selectedPeg_  = nil
        validTargets_ = {}
        -- 重新锁定的插板：清除解锁动画，恢复盖子
        for _, pegIdx in ipairs(relocked or {}) do
            Renderer.ClearUnlock(pegIdx)
        end
        UIOverlay.RefreshHUD()
        SoundManager.Play("undo")
    end
end

function HandleReset()
    if inputLocked_ then return end
    GameState.Reset()
    selectedPeg_  = nil
    validTargets_ = {}
    Renderer.ResetLevel()   -- 清除解锁动画等渲染状态，防止重玩时锁定盖子不显示
    UIOverlay.HideWin()
    UIOverlay.HideLose()
    UIOverlay.RefreshHUD()
    SoundManager.Play("reset")
end

function HandleNextLevel()
    local next = GameState.GetLevelIndex() + 1
    -- 关卡数可无限增长，超出配置范围时 Levels.Clone 会自动使用最后一关的配置
    HandleSelectLevel(next)
end

-- 返回主界面并触发飞金币演出
function HandleBackMenu(coinsToFly)
    coinsToFly = coinsToFly or pendingFlyCoins_ or 0
    pendingFlyCoins_ = 0
    EnterMenu()
    -- UI 刚建立，Yoga 布局需至少一帧才稳定，延迟 0.1 秒再读坐标
    if coinsToFly > 0 then
        backMenuFlyCoins_ = coinsToFly
        backMenuFlyDelay_ = 0.1
    end
    print(string.format("[Main] 返回主界面，飞金币 %d 枚（等待布局稳定）", coinsToFly))
end

function HandleSelectLevel(idx)
    if UIAnim.IsTransitioning() then return end

    local function doLoadLevel()
        -- 若当前在主界面，先切换到游戏场景
        if phase_ == "menu" then
            MainMenu.Hide()
        end
        phase_ = "game"
        SaveManager.SetLastLevel(idx)
        -- 清除该关卡缓存，确保每次进入都重新生成布局
        Levels.ClearCache(idx)
        GameState.LoadLevel(idx)
        selectedPeg_  = nil
        validTargets_ = {}
        inputLocked_  = false
        pendingWin_   = false
        queuedMove_   = nil
        queuedSelect_ = nil
        Renderer.ResetLevel()
        UIOverlay.HideWin()
        UIOverlay.HideLose()
        UIOverlay.HideLevelSelect()
        RefreshLayout()

        -- 教程关进入时启动动画，其他关卡停止
        local levelData = Levels.data[idx]
        if levelData and levelData.isTutorial then
            Tutorial.Start()
        else
            Tutorial.Stop()
        end
    end

    -- 使用圆形擦除过渡
    SoundManager.Play("chapter_transition", 0.6)
    UIAnim.StartTransition({
        onMidpoint = doLoadLevel,
    })
end

-- ---------------------------------------------------------------
-- NanoVG 渲染
-- ---------------------------------------------------------------
function HandleRender(eventType, eventData)
    if not nvgCtx_ then return end

    local W = graphics:GetWidth()
    local H = graphics:GetHeight()

    -- game 阶段：绘制游戏内容
    if phase_ == "game" then
        -- 检测窗口尺寸变化
        if W ~= W_ or H ~= H_ then
            W_ = W
            H_ = H
            Renderer.RecalcLayout(W_, H_)
        end

        nvgBeginFrame(nvgCtx_, W, H, 1.0)

        -- 动画期间用预选插板代替 selectedPeg_ 显示高亮
        local renderSelected = selectedPeg_
        local renderTargets  = validTargets_
        if inputLocked_ and queuedSelect_ then
            renderSelected = queuedSelect_
            renderTargets  = GameState.ValidTargets(queuedSelect_)
        end

        -- 主场景（背景 + 插板 + 齿轮 + 粒子）
        Renderer.Draw(nvgCtx_, W, H, renderSelected, renderTargets)

        -- 选中悬浮齿轮（叠加在顶层）
        local floatTarget = selectedPeg_
        if inputLocked_ and queuedSelect_ then
            floatTarget = queuedSelect_
        end
        if floatTarget then
            Renderer.DrawFloatingGears(nvgCtx_, floatTarget)
        end

        -- 教程引导手指动画（最顶层）
        Tutorial.Draw(nvgCtx_)

        nvgEndFrame(nvgCtx_)
    end
end
