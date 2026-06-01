-- ui_overlay.lua
-- urhox-libs/UI 层：HUD、弹窗（通关、设置）、关卡选择

local UI           = require("urhox-libs/UI")
local UIAnim       = require("ui_anim")
local GameState    = require("game_state")
local Levels       = require("levels")
local SaveManager  = require("save_manager")
local AdDialog     = require("ad_dialog")
local SoundManager = require("sound_manager")

local UIOverlay = {}

-- ---------------------------------------------------------------
-- 内部回调引用（由 main.lua 注入）
-- ---------------------------------------------------------------
local onUndo_       = nil
local onReset_      = nil
local onNextLevel_  = nil
local onSelectLevel_= nil
local onResume_     = nil
local onTempHub_    = nil
local onBackMenu_   = nil   -- 返回主界面（触发飞金币演出）

-- ---------------------------------------------------------------
-- UI 根节点
-- ---------------------------------------------------------------
local root_              = nil
local hudLevel_          = nil   -- 关卡标签
local hudCoinIcon_       = nil   -- HUD 右上角金币图标（飞金币目标）
local hudCoinLabel_      = nil   -- HUD 右上角金币数字
local tempHubBtn_        = nil   -- 临时插板道具按钮
local tempHubCountLabel_ = nil   -- 道具数量标签
local tempHubCountBadge_ = nil   -- 道具数量角标背景
local undoBtn_           = nil   -- 撤回道具按钮
local undoCountLabel_    = nil   -- 撤回道具数量角标
local undoCountBadge_    = nil   -- 撤回数量角标背景
local winPanel_          = nil   -- 通关弹窗（遮罩层）
local winCard_           = nil   -- 通关弹窗卡片
local winMoves_          = nil   -- 步数结果
local winBest_           = nil   -- 最佳步数标签
local winStreakRow_       = nil   -- 通关弹窗连胜行（可隐藏）
local winStreakLabel_     = nil   -- 连胜文字
local winCoinIcon_       = nil   -- 通关弹窗金币图标（飞金币演出目标）
local winCoinsLabel_     = nil   -- 金币奖励文字
local losePanel_         = nil   -- 失败弹窗（遮罩层）
local loseCard_          = nil   -- 失败弹窗卡片
local loseStreakRow_      = nil   -- 失败弹窗连胜提示行（可隐藏）
local loseStreakLabel_    = nil   -- 连胜数文字
local loseKeepBtn_       = nil   -- 花费金币保连胜按钮
local levelSelPanel_     = nil   -- 关卡选择面板
local pausePanel_        = nil   -- 暂停弹窗（遮罩层）
local pauseCard_         = nil   -- 暂停弹窗卡片
local levelBtns_         = {}    -- 关卡按钮引用列表（用于刷新状态）

-- ShowWin/ShowLose 传入的回调（每次显示时更新）
local winOnReset_    = nil
local winOnNext_     = nil
local winOnBackMenu_ = nil
local loseOnKeep_    = nil
local loseOnReset_   = nil
local loseOnSelect_  = nil
local loseOnAdContinue_ = nil
local loseOnBackMenu_   = nil

-- 是否显示关卡选择 / 暂停
local showLevelSel_ = false
local showPause_    = false

-- ---------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------
function UIOverlay.Init(callbacks)
    onUndo_        = callbacks.onUndo
    onReset_       = callbacks.onReset
    onNextLevel_   = callbacks.onNextLevel
    onSelectLevel_ = callbacks.onSelectLevel
    onResume_      = callbacks.onResume
    onTempHub_     = callbacks.onTempHub
    onBackMenu_    = callbacks.onBackMenu

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/LongZhuTi-Regular.ttf",
                bold   = "Fonts/LongZhuTi-Regular.ttf",
            }}
        },
        scale = UI.Scale.DEFAULT,
    })

    UIOverlay.BuildUI()
    print("[UIOverlay] UI 初始化完成")
end

function UIOverlay.Shutdown()
    UI.Shutdown()
end

-- ---------------------------------------------------------------
-- 构建 UI 树
-- ---------------------------------------------------------------
function UIOverlay.BuildUI()
    -- HUD 顶部
    local hud = UI.Panel {
        position = "absolute",
        top = 50, left = 0, right = 0,
        height = 80,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 12, paddingRight = 12,
        children = {
            -- 左：菜单图标按钮
            UI.Button {
                variant  = "ghost",
                width = 64, height = 64,
                paddingLeft = 0, paddingRight = 0,
                paddingTop = 0, paddingBottom = 0,
                backgroundImage = "image/btn_menu_20260525064658.png",
                backgroundFit   = "contain",
                onClick = function()
                    SoundManager.Play("btn_click")
                    UIOverlay.ShowPause()
                end,
            },
            -- 中：关卡标题（绝对居中容器，不拦截点击）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                alignItems = "center",
                justifyContent = "center",
                pointerEvents = "none",
                overflow = "hidden",
                children = {
                    -- 容器：宽度 x2
                    UI.Panel {
                        width = "60%", minWidth = 280, maxWidth = 758,
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents = "none",
                        children = {
                            -- 背景：独立 UI，以高度为基准，按素材宽高比计算宽度
                            UI.Panel {
                                position = "absolute",
                                height = "130%",
                                aspectRatio = 379 / 211,
                                backgroundImage = "image/ui_btn_secondary_20260525112622.png",
                                backgroundFit   = "fill",
                                pointerEvents = "none",
                            },
                            -- 文字：独立 UI，字号降低 25%
                            UI.Label {
                                id = "hudLevel",
                                text = "关卡 1",
                                fontSize = 27,
                                fontColor = { 180, 205, 255, 255 },
                                strokeColor = { 20, 40, 100, 220 },
                                strokeWidth = 3,
                            },
                        },
                    },
                },
            },
            -- 右：金币显示 + 撤销按钮
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap = 8,
                children = {
                    -- 金币面板（与主菜单右上角同款）
                    UI.Panel {
                        id              = "hudCoinPanel",
                        flexDirection   = "row",
                        alignItems      = "center",
                        gap             = 8,
                        paddingLeft     = 14, paddingRight = 14,
                        paddingTop      = 8, paddingBottom = 8,
                        borderRadius    = 25,
                        backgroundColor = { 8, 14, 36, 215 },
                        borderWidth     = 1,
                        borderColor     = { 180, 140, 50, 80 },
                        children = {
                            UI.Panel {
                                id              = "hudCoinIcon",
                                width           = 32, height = 32,
                                backgroundImage = "image/icon_coin_20260525095234.png",
                                backgroundFit   = "contain",
                            },
                            UI.Label {
                                id         = "hudCoinLabel",
                                text       = "0",
                                fontSize   = 20,
                                fontColor  = { 255, 200, 55, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },

                },
            },
        },
    }

    -- 通关弹窗（默认隐藏）
    local winPanel = UI.Panel {
        id = "winPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 0 },   -- 透明：让 NanoVG 粒子特效透过显示
        visible = false,
        children = {
            UI.Panel {
                id = "winCard",
                width = 450,
                paddingTop = 24, paddingBottom = 28,
                paddingLeft = 28, paddingRight = 28,
                backgroundImage = "Textures/UI/popup_panel.png",
                backgroundFit   = "fill",
                alignItems = "center",
                gap = 10,
                children = {
                    -- PUZZLE SOLVED! 标题图片
                    UI.Panel {
                        width  = 240,
                        height = math.floor(240 * 341 / 512),
                        backgroundImage    = "Textures/UI/win_title.png",
                        backgroundFit   = "contain",
                    },
                    -- 标题下分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 100, 180, 60 },
                        marginBottom = 4,
                    },
                    -- 本次步数
                    UI.Label {
                        id = "winMoves",
                        text = "步数：0",
                        fontSize = 18,
                        fontColor = { 220, 235, 255, 240 },
                    },
                    -- 最佳步数
                    UI.Label {
                        id = "winBest",
                        text = "",
                        fontSize = 13,
                        fontColor = { 100, 220, 120, 210 },
                    },
                    -- 连胜 + 倍率行（连胜=0时隐藏）
                    UI.Panel {
                        id = "winStreakRow",
                        width = "100%",
                        paddingTop = 6, paddingBottom = 6,
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = { 255, 160, 30, 25 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 255, 180, 50, 80 },
                        alignItems = "center",
                        visible = false,
                        children = {
                            UI.Label {
                                id = "winStreakLabel",
                                text = "🔥 1 连胜  ×1.0 加成",
                                fontSize = 14,
                                fontColor = { 255, 200, 80, 255 },
                            },
                        },
                    },
                    -- 金币奖励行（图标 + 数字，图标作为飞金币目标）
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        justifyContent = "center",
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Panel {
                                id = "winCoinIcon",
                                width = 36, height = 36,
                                backgroundImage = "image/icon_coin_reward_20260526074619.png",
                                backgroundFit   = "contain",
                            },
                            UI.Label {
                                id = "winCoinsLabel",
                                text = "+10",
                                fontSize = 28,
                                fontColor = { 255, 220, 60, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 100, 180, 40 },
                    },
                    -- 按钮区
                    UI.Panel {
                        width = "100%",
                        padding = 16,
                        paddingTop = 30,
                        paddingBottom = 30,
                        gap = 24,
                        alignItems = "center",
                        children = {
                            -- 下一关
                            UI.Button {
                                text            = "下一关",
                                variant         = "primary",
                                width           = "70%",
                                height          = math.floor(274 * 94 / 270 * 0.7),
                                fontSize        = 24,
                                backgroundImage = "Textures/UI/btn_emboss.png",
                                backgroundFit   = "fill",
                                onClick = function()
                                    SoundManager.Play("next_level")
                                    UIOverlay.HideWin()
                                    if winOnNext_ then winOnNext_()
                                    elseif onNextLevel_ then onNextLevel_() end
                                end,
                            },
                            -- 返回主界面（触发飞金币演出）
                            UI.Button {
                                text            = "返回主界面",
                                variant         = "ghost",
                                width           = "70%",
                                height          = math.floor(274 * 94 / 270 * 0.7),
                                fontSize        = 24,
                                backgroundImage = "Textures/UI/btn_emboss.png",
                                backgroundFit   = "fill",
                                onClick = function()
                                    SoundManager.Play("back_menu")
                                    UIOverlay.HideWin()
                                    if winOnBackMenu_ then winOnBackMenu_()
                                    elseif onBackMenu_ then onBackMenu_() end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- 失败弹窗（默认隐藏）
    local losePanel = UI.Panel {
        id = "losePanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        children = {
            UI.Panel {
                id = "loseCard",
                width = 450,
                paddingTop = 28, paddingBottom = 28,
                paddingLeft = 28, paddingRight = 28,
                backgroundColor = { 40, 20, 30, 245 },
                borderRadius = 20,
                borderWidth = 1,
                borderColor = { 200, 80, 80, 120 },
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text = "无路可走",
                        fontSize = 26,
                        fontColor = { 255, 120, 100, 255 },
                    },
                    UI.Label {
                        text = "没有可移动的齿轮了",
                        fontSize = 14,
                        fontColor = { 200, 160, 160, 200 },
                    },
                    -- 连胜提示区（连胜=0时隐藏）
                    UI.Panel {
                        id = "loseStreakRow",
                        width = "100%",
                        paddingTop = 10, paddingBottom = 10,
                        paddingLeft = 12, paddingRight = 12,
                        backgroundColor = { 255, 140, 30, 20 },
                        borderRadius = 10,
                        borderWidth = 1,
                        borderColor = { 255, 160, 50, 70 },
                        alignItems = "center",
                        gap = 4,
                        visible = false,
                        children = {
                            UI.Label {
                                id = "loseStreakLabel",
                                text = "🔥 当前连胜：1 连胜",
                                fontSize = 15,
                                fontColor = { 255, 200, 80, 255 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "⚠️ 重置将中断你的连胜！",
                                fontSize = 12,
                                fontColor = { 255, 160, 100, 200 },
                            },
                        },
                    },
                    -- 花费金币保连胜按钮（连胜=0时隐藏）
                    UI.Button {
                        id = "loseKeepBtn",
                        text = "花费 900 金币  保持连胜继续",
                        variant = "primary",
                        width = "100%", height = 48,
                        fontSize = 14,
                        visible = false,
                        onClick = function()
                            SoundManager.Play("btn_click")
                            if loseOnKeep_ then loseOnKeep_() end
                        end,
                    },
                    -- 分隔线（连胜>0时显示）
                    UI.Panel {
                        id = "loseDivider",
                        width = "100%", height = 1,
                        backgroundColor = { 180, 60, 60, 60 },
                        visible = false,
                    },
                    -- 观看广告继续按钮
                    UI.Button {
                        id = "loseAdContinueBtn",
                        text = "观看广告  继续游戏",
                        variant = "primary",
                        width = "100%", height = 48,
                        fontSize = 14,
                        visible = false,
                        onClick = function()
                            SoundManager.Play("btn_click")
                            if loseOnAdContinue_ then loseOnAdContinue_() end
                        end,
                    },
                    -- 退出关卡按钮
                    UI.Button {
                        text = "退出关卡",
                        variant = "secondary",
                        width = "100%", height = 40,
                        fontSize = 14,
                        onClick = function()
                            SoundManager.Play("btn_click")
                            UIOverlay.HideLose()
                            if loseOnBackMenu_ then loseOnBackMenu_()
                            elseif onBackMenu_ then onBackMenu_() end
                        end,
                    },
                },
            },
        },
    }

    -- 关卡选择面板（默认隐藏）
    -- 每个关卡格子：编号（未解锁显示 🔒）
    local levelButtons = {}
    local unlocked = SaveManager.GetUnlocked()
    for i = 1, Levels.Count() do
        local idx       = i
        local isLocked  = (i > unlocked)
        local isCleared = SaveManager.IsCleared(i)
        local btnId     = "lvlBtn_" .. i

        -- 背景图片：已通关 → cell_cleared，锁定/未通关 → cell_locked
        local bgSrc = (not isLocked and isCleared)
            and "Textures/UI/cell_cleared.png"
            or  "Textures/UI/cell_locked.png"

        levelButtons[#levelButtons + 1] = UI.Panel {
            id             = btnId,
            width          = 56, height = 56,
            alignItems     = "center",
            justifyContent = "center",
            borderRadius   = 10,
            overflow       = "hidden",
            backgroundImage    = bgSrc,
            backgroundFit   = "cover",
            opacity        = isLocked and 0.55 or 1.0,
            children = {
                -- 文字层（叠加在图片上方）
                UI.Label {
                    text      = isLocked and "🔒" or tostring(i),
                    fontSize  = isLocked and 16 or 17,
                    fontColor = isLocked
                        and { 200, 200, 210, 230 }
                        or  (isCleared and { 255, 255, 200, 255 } or { 220, 235, 255, 255 }),
                },
            },
            onClick = isLocked and nil or function()
                SoundManager.Play("level_select")
                UIOverlay.HideLevelSelect()
                if onSelectLevel_ then onSelectLevel_(idx) end
            end,
        }
        levelBtns_[i] = levelButtons[#levelButtons]
    end

    local levelSelPanel = UI.Panel {
        id = "levelSelPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 170 },
        visible = false,
        children = {
            UI.Panel {
                width = 340,
                -- 不设固定 height，改为 maxHeight + flexShrink 让面板自适应屏幕
                maxHeight = 520,
                paddingTop = 20, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 22, 28, 46, 248 },
                borderRadius = 18,
                borderWidth = 1,
                borderColor = { 80, 100, 180, 100 },
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text = "选择关卡",
                        fontSize = 18,
                        fontColor = { 180, 200, 255, 255 },
                    },
                    -- ScrollView 包裹关卡格子，支持竖向滚动
                    UI.ScrollView {
                        width      = "100%",
                        flexGrow   = 1,
                        flexBasis  = 0,
                        scrollY    = true,
                        scrollX    = false,
                        showScrollbar = true,
                        children = {
                            UI.Panel {
                                flexDirection  = "row",
                                flexWrap       = "wrap",
                                gap            = 8,
                                justifyContent = "center",
                                width          = "100%",
                                paddingBottom  = 4,
                                children       = levelButtons,
                            },
                        },
                    },
                    UI.Button {
                        text = "关闭",
                        variant = "secondary",
                        width = 100, height = 36,
                        fontSize = 13,
                        onClick = function()
                            SoundManager.Play("btn_click")
                            UIOverlay.HideLevelSelect()
                            if onResume_ then onResume_() end
                        end,
                    },
                },
            },
        },
    }

    -- 暂停弹窗（默认隐藏）
    local pausePanel = UI.Panel {
        id = "pausePanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 170 },
        visible = false,
        children = {
            UI.Panel {
                id = "pauseCard",
                width = 450, height = 600,
                paddingTop = 36, paddingBottom = 42,
                paddingLeft = 42, paddingRight = 42,
                backgroundImage = "Textures/UI/popup_panel.png",
                backgroundFit   = "fill",
                alignItems = "center",
                gap = 18,
                children = {
                    UI.Label {
                        text = "暂停",
                        fontSize = 22,
                        fontColor = { 180, 200, 255, 255 },
                        fontWeight = "bold",
                    },
                    -- 标题下分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 100, 180, 60 },
                        marginBottom = 4,
                    },
                    -- 装饰图
                    UI.Panel {
                        width = 234, height = 234,
                        backgroundImage = "image/pause_deco_sleepy_gears_20260527090227.png",
                        backgroundFit = "contain",
                        marginTop = "auto",
                        marginBottom = 8,
                    },
                    -- 按钮区（底部居中，边距+16）
                    UI.Panel {
                        width = "100%",
                        marginTop = "auto",
                        marginBottom = 16,
                        alignItems = "center",
                        gap = 18,
                        children = {
                            -- 继续游戏
                            UI.Button {
                                text = "继续游戏",
                                variant = "primary",
                                width = 274, height = math.floor(274 * 94 / 270 * 0.75),
                                fontSize = 19,
                                backgroundImage = "Textures/UI/btn_emboss.png",
                                backgroundFit   = "fill",
                                onClick = function()
                                    SoundManager.Play("btn_click")
                                    UIOverlay.HidePause()
                                end,
                            },
                            -- 退出关卡
                            UI.Button {
                                text = "退出关卡",
                                variant = "ghost",
                                width = 274, height = math.floor(274 * 94 / 270 * 0.75),
                                fontSize = 19,
                                backgroundImage = "Textures/UI/btn_emboss.png",
                                backgroundFit   = "fill",
                                onClick = function()
                                    SoundManager.Play("btn_click")
                                    UIOverlay.HidePause(function()
                                        if onResume_ then onResume_() end
                                    end)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- 底部道具栏
    local itemBar = UI.Panel {
        id = "itemBar",
        position = "absolute",
        bottom = 30, left = 0, right = 0,
        height = 156,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 16,
        paddingBottom = 8,
        children = {
            -- 临时插板道具格子
            UI.Button {
                id = "tempHubBtn",
                variant = "ghost",
                position = "relative",
                width = 128, height = 128,
                borderRadius = 16,
                backgroundColor = { 25, 35, 60, 220 },
                borderWidth = 1,
                borderColor = { 80, 110, 180, 160 },
                alignItems = "center",
                justifyContent = "center",
                padding = 0,
                onClick = function()
                    if onTempHub_ then onTempHub_() end
                end,
                children = {
                    -- 插板图标
                    UI.Panel {
                        width = 96, height = 96,
                        backgroundImage = "image/hub_single_slot_20260526063407.png",
                        backgroundFit   = "contain",
                        pointerEvents   = "none",
                    },
                    -- 数量角标
                    UI.Panel {
                        id = "tempHubCountBadge",
                        position = "absolute",
                        bottom = 4, right = 4,
                        width = 32, height = 32,
                        borderRadius = 16,
                        backgroundColor = { 255, 170, 30, 230 },
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents   = "none",
                        children = {
                            UI.Label {
                                id = "tempHubCount",
                                text = "1",
                                fontSize = 16,
                                fontColor = { 20, 10, 0, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
            -- 撤回道具格子
            UI.Button {
                id = "undoBtn",
                variant = "ghost",
                position = "relative",
                width = 128, height = 128,
                borderRadius = 16,
                backgroundColor = { 25, 35, 60, 220 },
                borderWidth = 1,
                borderColor = { 80, 110, 180, 160 },
                alignItems = "center",
                justifyContent = "center",
                padding = 0,
                onClick = function()
                    if not GameState.CanUndo() then return end
                    local cnt = SaveManager.GetUndoCount()
                    if cnt > 0 then
                        -- 有库存：直接消耗
                        SaveManager.UseUndo()
                        if onUndo_ then onUndo_() end
                        UIOverlay.RefreshHUD()
                    else
                        -- 库存为0：弹广告/金币购买弹窗
                        AdDialog.Show({
                            title    = "撤回操作",
                            desc     = "消耗 300 金币或观看广告，撤回上一步",
                            icon     = "Textures/UI/icon_undo.png",
                            coinCost = 300,
                            onSpendCoins = function()
                                if SaveManager.SpendCoins(300) then
                                    if hudCoinLabel_ then
                                        hudCoinLabel_:SetText(tostring(SaveManager.GetCoins()))
                                    end
                                    if onUndo_ then onUndo_() end
                                    UIOverlay.RefreshHUD()
                                end
                            end,
                            onGrant = function()
                                if onUndo_ then onUndo_() end
                                UIOverlay.RefreshHUD()
                            end,
                        })
                    end
                end,
                children = {
                    -- 撤回图标
                    UI.Panel {
                        width = 72, height = 72,
                        backgroundImage = "Textures/UI/icon_undo.png",
                        backgroundFit   = "contain",
                        pointerEvents   = "none",
                    },
                    -- 数量角标
                    UI.Panel {
                        id = "undoCountBadge",
                        position = "absolute",
                        bottom = 4, right = 4,
                        width = 32, height = 32,
                        borderRadius = 16,
                        backgroundColor = { 100, 140, 255, 220 },
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents = "none",
                        children = {
                            UI.Label {
                                id = "undoCount",
                                text = "0",
                                fontSize = 16,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
        },
    }

    -- 组合根节点
    root_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { hud, itemBar, winPanel, losePanel, levelSelPanel, pausePanel },
    }
    UI.SetRoot(root_)

    -- 初始化广告弹窗（挂到根节点上）
    AdDialog.Init(root_)

    -- 缓存常用节点引用
    hudLevel_          = root_:FindById("hudLevel")
    hudCoinIcon_       = root_:FindById("hudCoinIcon")
    hudCoinLabel_      = root_:FindById("hudCoinLabel")
    tempHubBtn_        = root_:FindById("tempHubBtn")
    tempHubCountLabel_ = root_:FindById("tempHubCount")
    tempHubCountBadge_ = root_:FindById("tempHubCountBadge")
    undoBtn_           = root_:FindById("undoBtn")
    undoCountLabel_    = root_:FindById("undoCount")
    undoCountBadge_    = root_:FindById("undoCountBadge")
    winPanel_          = root_:FindById("winPanel")
    winCard_           = root_:FindById("winCard")
    winMoves_          = root_:FindById("winMoves")
    winBest_           = root_:FindById("winBest")
    winStreakRow_      = root_:FindById("winStreakRow")
    winStreakLabel_    = root_:FindById("winStreakLabel")
    winCoinIcon_      = root_:FindById("winCoinIcon")
    winCoinsLabel_    = root_:FindById("winCoinsLabel")
    losePanel_         = root_:FindById("losePanel")
    loseCard_          = root_:FindById("loseCard")
    loseStreakRow_     = root_:FindById("loseStreakRow")
    loseStreakLabel_   = root_:FindById("loseStreakLabel")
    loseKeepBtn_       = root_:FindById("loseKeepBtn")
    levelSelPanel_     = root_:FindById("levelSelPanel")
    pausePanel_        = root_:FindById("pausePanel")
    pauseCard_         = root_:FindById("pauseCard")
end

-- ---------------------------------------------------------------
-- HUD 刷新
-- ---------------------------------------------------------------
function UIOverlay.RefreshHUD()
    if hudLevel_ then
        hudLevel_:SetText("关卡 " .. tostring(GameState.GetLevelIndex()))
    end
    if hudCoinLabel_ then
        hudCoinLabel_:SetText(tostring(SaveManager.GetCoins()))
    end
    -- 临时插板按钮：游戏已解决时禁用（无数量限制）
    if tempHubBtn_ then
        local isSolved = GameState.IsSolved()
        -- 已通关则完全禁用；无库存时仍可点击（弹广告/购买）
        local isDisabled = isSolved
        tempHubBtn_.props.opacity = isDisabled and 0.35 or 1.0
        if isDisabled then
            tempHubBtn_.props.onClick = nil
        else
            tempHubBtn_.props.onClick = function()
                if onTempHub_ then onTempHub_() end
            end
        end
    end
    -- 临时插板数量角标：显示库存数 + 动态背景色
    local hubCount = SaveManager.GetTempHubCount()
    if tempHubCountLabel_ then
        tempHubCountLabel_:SetText(tostring(hubCount))
    end
    if tempHubCountBadge_ then
        -- 数量>0 黄色，=0 蓝色
        local bgColor = hubCount > 0 and { 255, 170, 30, 230 } or { 100, 140, 255, 220 }
        tempHubCountBadge_:SetStyle({ backgroundColor = bgColor })
    end
    -- 撤回数量角标 + 动态背景色
    local undoCount = SaveManager.GetUndoCount()
    if undoCountLabel_ then
        undoCountLabel_:SetText(tostring(undoCount))
    end
    if undoCountBadge_ then
        local bgColor = undoCount > 0 and { 255, 170, 30, 230 } or { 100, 140, 255, 220 }
        undoCountBadge_:SetStyle({ backgroundColor = bgColor })
    end
    -- 撤回按钮：仅游戏已通关时完全禁用；无步可撤时灰显但可点击（给出提示）
    if undoBtn_ then
        local isSolved = GameState.IsSolved()
        local canUndo  = GameState.CanUndo()
        -- 已通关：完全禁用
        undoBtn_.props.opacity = isSolved and 0.35 or 1.0
        if isSolved then
            undoBtn_.props.onClick = nil
        else
            -- 无步可撤时半透明提示（仍可点击但给出提示，不弹广告/花金币）
            undoBtn_.props.opacity = (not canUndo) and 0.5 or 1.0
            undoBtn_.props.onClick = function()
                if not canUndo then
                    -- 没有可撤回的步骤（游戏开始前或已全部撤回）
                    return
                end
                local cnt = SaveManager.GetUndoCount()
                if cnt > 0 then
                    -- 有库存：直接消耗
                    SaveManager.UseUndo()
                    if onUndo_ then onUndo_() end
                    UIOverlay.RefreshHUD()
                else
                    -- 库存为0：弹广告/金币购买弹窗（与临时插板相同逻辑）
                    AdDialog.Show({
                        title    = "撤回操作",
                        desc     = "消耗 300 金币或观看广告，撤回上一步",
                        icon     = "Textures/UI/icon_undo.png",
                        coinCost = 300,
                        onSpendCoins = function()
                            if SaveManager.SpendCoins(300) then
                                if hudCoinLabel_ then
                                    hudCoinLabel_:SetText(tostring(SaveManager.GetCoins()))
                                end
                                if onUndo_ then onUndo_() end
                                UIOverlay.RefreshHUD()
                            end
                        end,
                        onGrant = function()
                            if onUndo_ then onUndo_() end
                            UIOverlay.RefreshHUD()
                        end,
                    })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------
-- 通关弹窗
-- opts 表：
--   moves       本次步数
--   bestMoves   历史最佳步数
--   coinsEarned 本局获得金币（已入账）
--   winStreak   通关后的连胜数（已+1）
--   multiplier  本次倍率
--   onReset     重玩回调（可选，覆盖全局）
--   onNextLevel 下一关回调（可选，覆盖全局）
--   onBackMenu  返回主界面回调（可选，覆盖全局）
-- ---------------------------------------------------------------
function UIOverlay.ShowWin(opts)
    -- 兼容旧调用方式：ShowWin(moves, bestMoves)
    local moves, bestMoves, coinsEarned, winStreak, multiplier
    if type(opts) == "number" then
        moves       = opts
        bestMoves   = nil -- 旧调用方式第二参数无法在此捕获，降级为 nil
        -- 从 SaveManager 读取最新值兜底
        coinsEarned = SaveManager.CalcWinCoins and SaveManager.CalcWinCoins() or 10
        winStreak   = SaveManager.GetWinStreak and SaveManager.GetWinStreak() or 0
        multiplier  = SaveManager.GetStreakMultiplier and SaveManager.GetStreakMultiplier() or 1.0
        winOnReset_    = nil
        winOnNext_     = nil
        winOnBackMenu_ = nil
    else
        opts        = opts or {}
        moves       = opts.moves       or GameState.GetMoveCount()
        bestMoves   = opts.bestMoves
        coinsEarned = opts.coinsEarned or 10
        winStreak   = opts.winStreak   or 0
        multiplier  = opts.multiplier  or 1.0
        winOnReset_    = opts.onReset
        winOnNext_     = opts.onNextLevel
        winOnBackMenu_ = opts.onBackMenu
    end

    if winMoves_ then
        winMoves_:SetText(string.format("本次：%d 步", moves))
    end
    if winBest_ then
        if bestMoves and bestMoves < moves then
            winBest_:SetText(string.format("最佳：%d 步", bestMoves))
        elseif bestMoves and bestMoves == moves then
            winBest_:SetText("创造最佳记录！")
            SoundManager.Play("new_record", 0.8)
        else
            winBest_:SetText("")
        end
    end

    -- 连胜行（连胜>=1才显示）
    if winStreakRow_ then
        local showStreak = (winStreak >= 1)
        winStreakRow_:SetVisible(showStreak)
        if showStreak and winStreakLabel_ then
            winStreakLabel_:SetText(string.format("🔥 %d 连胜  ×%.1f 加成", winStreak, multiplier))
        end
    end

    -- 金币奖励
    if winCoinsLabel_ then
        winCoinsLabel_:SetText(string.format("+%d", coinsEarned))
    end

    -- 通关后刷新关卡选择面板（解锁新关卡）
    UIOverlay.RefreshLevelSelect()
    if winPanel_ then
        -- 使用弹窗动画弹入（胜利使用更强弹性）
        UIAnim.PopupIn(winCard_, winPanel_, { overshoot = 2.5 })
    end
    SoundManager.Play("win_popup")
end

function UIOverlay.HideWin()
    if winPanel_ and winCard_ then
        UIAnim.PopupOut(winCard_, winPanel_)
    elseif winPanel_ then
        winPanel_:SetVisible(false)
    end
end

-- ---------------------------------------------------------------
-- 失败弹窗
-- opts 表：
--   winStreak    当前连胜数（0 则隐藏保连胜区域）
--   coinBalance  当前金币余额
--   onKeepStreak 花费900金币保连胜回调
--   onReset      再来一次回调（会重置连胜）
--   onSelectLevel 选关回调（会重置连胜）
--   onBackMenu   退出关卡返回主菜单回调
-- ---------------------------------------------------------------
function UIOverlay.ShowLose(opts)
    opts = opts or {}
    local winStreak   = opts.winStreak   or 0
    local coinBalance = opts.coinBalance or SaveManager.GetCoins()
    loseOnKeep_   = opts.onKeepStreak
    loseOnReset_  = opts.onReset
    loseOnSelect_ = opts.onSelectLevel
    loseOnBackMenu_ = opts.onBackMenu

    local showStreak = (winStreak > 0)

    -- 连胜提示区
    if loseStreakRow_ then
        loseStreakRow_:SetVisible(showStreak)
        if showStreak and loseStreakLabel_ then
            loseStreakLabel_:SetText(string.format("🔥 当前连胜：%d 连胜", winStreak))
        end
    end

    -- 保连胜按钮（有连胜才显示）
    if loseKeepBtn_ then
        loseKeepBtn_:SetVisible(showStreak)
        if showStreak then
            local canAfford = (coinBalance >= 900)
            loseKeepBtn_.props.opacity = canAfford and 1.0 or 0.4
            if canAfford then
                loseKeepBtn_.props.onClick = function()
                    if loseOnKeep_ then loseOnKeep_() end
                end
            else
                loseKeepBtn_.props.onClick = function()
                    -- 金币不足提示（通过 print 后续可换 toast）
                    print("[UIOverlay] 金币不足，无法保连胜（需要900，当前" .. coinBalance .. "）")
                end
            end
        end
    end

    -- 分隔线
    local divider = root_ and root_:FindById("loseDivider")
    if divider then divider:SetVisible(showStreak) end

    -- 广告续命按钮（可用时显示）
    loseOnAdContinue_ = opts.onAdContinue
    local adBtn = root_ and root_:FindById("loseAdContinueBtn")
    if adBtn then
        local canContinue = (loseOnAdContinue_ ~= nil)
        adBtn:SetVisible(canContinue)
    end

    if losePanel_ then
        -- 失败弹窗：从顶部落下 + 弹跳
        UIAnim.PopupBounceIn(loseCard_, losePanel_)
    end
    SoundManager.Play("lose_popup")
end

function UIOverlay.HideLose()
    if losePanel_ and loseCard_ then
        UIAnim.PopupOut(loseCard_, losePanel_)
    elseif losePanel_ then
        losePanel_:SetVisible(false)
    end
end

-- ---------------------------------------------------------------
-- 暂停弹窗
-- ---------------------------------------------------------------
function UIOverlay.ShowPause()
    showPause_ = true
    if pausePanel_ then
        UIAnim.PopupIn(pauseCard_, pausePanel_)
    end
    SoundManager.Play("pause_open")
end

function UIOverlay.HidePause(onComplete)
    showPause_ = false
    if pausePanel_ and pauseCard_ then
        UIAnim.PopupOut(pauseCard_, pausePanel_, {
            onComplete = onComplete,
        })
    elseif pausePanel_ then
        pausePanel_:SetVisible(false)
        if onComplete then onComplete() end
    end
    SoundManager.Play("pause_close")
end

-- 将游戏 UI 重新设为 root（从主菜单切回游戏时调用）
function UIOverlay.Show()
    if root_ then UI.SetRoot(root_) end
end

-- ---------------------------------------------------------------
-- 关卡选择面板
-- ---------------------------------------------------------------

-- 通关后刷新各按钮的解锁/通关状态
function UIOverlay.RefreshLevelSelect()
    local unlocked = SaveManager.GetUnlocked()
    for i, btn in ipairs(levelBtns_) do
        if not btn then goto continue end
        local isLocked  = (i > unlocked)
        local isCleared = SaveManager.IsCleared(i)

        -- 更新背景图片和透明度（直接设置在 Panel 上）
        local bgSrc = (not isLocked and isCleared)
            and "Textures/UI/cell_cleared.png"
            or  "Textures/UI/cell_locked.png"
        btn.props.backgroundImage = bgSrc
        btn.props.opacity         = isLocked and 0.55 or 1.0

        -- 更新编号标签（index 0 = Label 文字层）
        local numLabel = btn:GetChildAt(0)
        if numLabel then
            numLabel:SetText(isLocked and "🔒" or tostring(i))
            numLabel.props.fontColor = isLocked
                and { 200, 200, 210, 230 }
                or  (isCleared and { 255, 255, 200, 255 } or { 220, 235, 255, 255 })
        end

        -- 更新点击事件
        if isLocked then
            btn.props.onClick = nil
        else
            local idx = i
            btn.props.onClick = function()
                SoundManager.Play("level_select")
                UIOverlay.HideLevelSelect()
                if onSelectLevel_ then onSelectLevel_(idx) end
            end
        end
        ::continue::
    end
end

function UIOverlay.ToggleLevelSelect()
    showLevelSel_ = not showLevelSel_
    if levelSelPanel_ then levelSelPanel_:SetVisible(showLevelSel_) end
end

function UIOverlay.HideLevelSelect()
    showLevelSel_ = false
    if levelSelPanel_ then levelSelPanel_:SetVisible(false) end
end

function UIOverlay.IsModalOpen()
    return showLevelSel_
        or showPause_
        or (winPanel_  and winPanel_:IsVisible())
        or (losePanel_ and losePanel_:IsVisible())
        or AdDialog.IsVisible()
end

--- 每帧驱动广告倒计时，需在 main.lua HandleUpdate 中调用
---@param dt number
function UIOverlay.Update(dt)
    AdDialog.Update(dt)
end

--- 直接弹出广告弹窗（供外部直接调用，如新增道具）
---@param cfg table  { title, desc, icon, onGrant }
function UIOverlay.ShowAdDialog(cfg)
    AdDialog.Show(cfg)
end

-- ---------------------------------------------------------------
-- 返回通关弹窗金币图标的屏幕中心坐标（旧接口，保留兼容）
-- 未就绪时返回 nil, nil
-- ---------------------------------------------------------------
function UIOverlay.GetWinCoinUIPosition()
    if not winCoinIcon_ then return nil, nil end
    local ok, layout = pcall(function()
        return winCoinIcon_:GetAbsoluteLayoutForHitTest()
    end)
    if not ok or not layout then return nil, nil end
    return layout.x + layout.w * 0.5, layout.y + layout.h * 0.5
end

-- ---------------------------------------------------------------
-- 返回通关弹窗 "+N" 金币数字标签的屏幕中心坐标（飞金币演出起点）
-- 未就绪时返回 nil, nil
-- ---------------------------------------------------------------
function UIOverlay.GetWinCoinSourcePosition()
    if not winCoinsLabel_ then return nil, nil end
    local ok, layout = pcall(function()
        return winCoinsLabel_:GetAbsoluteLayoutForHitTest()
    end)
    if not ok or not layout then return nil, nil end
    return layout.x + layout.w * 0.5, layout.y + layout.h * 0.5
end

-- ---------------------------------------------------------------
-- 返回 HUD 右上角金币图标的屏幕中心坐标（飞金币演出最终目标）
-- 未就绪时返回 nil, nil
-- ---------------------------------------------------------------
function UIOverlay.GetHudCoinUIPosition()
    if not hudCoinIcon_ then return nil, nil end
    local ok, layout = pcall(function()
        return hudCoinIcon_:GetAbsoluteLayoutForHitTest()
    end)
    if not ok or not layout then return nil, nil end
    return layout.x + layout.w * 0.5, layout.y + layout.h * 0.5
end

-- ---------------------------------------------------------------
-- 返回临时插板按钮的屏幕中心坐标（飞入动画起点）
-- 未就绪时返回 nil, nil
-- ---------------------------------------------------------------
function UIOverlay.GetTempHubBtnScreenPos()
    if not tempHubBtn_ then return nil, nil end
    local ok, layout = pcall(function()
        return tempHubBtn_:GetAbsoluteLayoutForHitTest()
    end)
    if not ok or not layout then return nil, nil end
    return layout.x + layout.w * 0.5, layout.y + layout.h * 0.5
end

-- ---------------------------------------------------------------
-- 刷新 HUD 金币数字（飞金币演出结束后调用）
-- ---------------------------------------------------------------
function UIOverlay.RefreshCoinDisplay()
    if hudCoinLabel_ then
        hudCoinLabel_:SetText(tostring(SaveManager.GetCoins()))
    end
end

return UIOverlay
