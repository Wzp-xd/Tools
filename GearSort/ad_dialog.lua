-- ad_dialog.lua
-- 观看广告弹窗：调用 sdk:ShowRewardVideoAd 播放真实激励视频广告，完成后执行奖励回调
-- 同时支持"花费金币"直接购买选项（可选）
--
-- 用法（仅广告）：
--   AdDialog.Show({
--       title    = "使用提示",
--       desc     = "观看广告后获得一次提示",
--       icon     = "Textures/UI/icon_hint.png",
--       onGrant  = function() ... end,   -- 广告看完后的奖励逻辑
--   })
--
-- 用法（广告 + 金币双选项）：
--   AdDialog.Show({
--       title        = "临时插板",
--       desc         = "...",
--       icon         = "image/gear_hub_cap.png",
--       coinCost     = 1000,               -- 可选：金币购买费用
--       onSpendCoins = function() ... end, -- 可选：花费金币后的逻辑
--       onGrant      = function() ... end, -- 广告看完后的奖励逻辑
--   })
--
-- 已接入真实广告 SDK（sdk:ShowRewardVideoAd），调用方代码无需改动。
-- ---------------------------------------------------------------

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎注入的全局 SDK 对象

local UI          = require("urhox-libs/UI")
local UIAnim      = require("ui_anim")
local SaveManager = require("save_manager")

local SoundManager = require("sound_manager")
local AdDialog = {}

-- ---------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------
---@type table|nil
local overlay_    = nil   -- 遮罩层（半透明背景）
---@type table|nil
local card_       = nil   -- 弹窗卡片（内容区域）
---@type table|nil
local rootRef_    = nil   -- 调用方传入的 UI 根节点（用于 AppendChild）

-- 弹窗内可更新的子节点引用
---@type table|nil
local iconNode_   = nil
---@type table|nil
local titleNode_  = nil
---@type table|nil
local descNode_   = nil

---@type table|nil
local watchBtn_   = nil   -- "观看广告" 主按钮
---@type table|nil
local cancelBtn_  = nil   -- "取消" 按钮
---@type table|nil
local coinBtn_    = nil   -- 金币购买按钮（可选）

-- 当前待执行的回调
---@type function|nil
local pendingGrant_      = nil
---@type function|nil
local pendingSpendCoins_ = nil

-- 当前弹窗配置（用于广告失败后恢复金币按钮状态）
---@type table|nil
local currentCfg_ = nil

-- 广告播放状态
local adPlaying_    = false

-- ---------------------------------------------------------------
-- 公共 API
-- ---------------------------------------------------------------

--- 初始化：需在 UIOverlay.Init 之后调用一次，传入 UI 根节点
---@param uiRoot table  UI.SetRoot 后的根节点
function AdDialog.Init(uiRoot)
    rootRef_ = uiRoot
    _buildPanel()
end

--- 显示广告弹窗（带弹入动画）
---@param cfg table  { title, desc, icon, onGrant, coinCost?, onSpendCoins? }
function AdDialog.Show(cfg)
    if not overlay_ or not card_ then return end

    -- 保存当前配置（用于失败后恢复）
    currentCfg_ = cfg

    -- 更新内容
    pendingGrant_      = cfg.onGrant
    pendingSpendCoins_ = cfg.onSpendCoins

    if titleNode_ then titleNode_:SetText(cfg.title or "观看广告") end
    if descNode_  then descNode_:SetText(cfg.desc or "观看广告以继续") end
    if iconNode_  then
        iconNode_.props.backgroundImage = cfg.icon or "Textures/UI/icon_ad.png"
    end

    -- 金币按钮：有 coinCost 时显示，否则隐藏
    if coinBtn_ then
        if cfg.coinCost and cfg.onSpendCoins then
            coinBtn_:SetVisible(true)
            coinBtn_:SetText(string.format("花费 %d 金币", cfg.coinCost))
            -- 金币足够时用黄色可点击，不够时灰色禁用
            local currentCoins = SaveManager.GetCoins() or 0
            local canAfford = currentCoins >= cfg.coinCost
            if canAfford then
                coinBtn_:SetDisabled(false)
                coinBtn_:SetStyle({ backgroundColor = { 230, 180, 20, 255 }, textColor = { 30, 20, 0, 255 } })
            else
                coinBtn_:SetDisabled(true)
                coinBtn_:SetStyle({ backgroundColor = { 60, 65, 90, 255 }, textColor = { 160, 160, 180, 255 } })
            end
            coinBtn_.props.onClick = function()
                _hideWithAnim(function()
                    if pendingSpendCoins_ then
                        pendingSpendCoins_()
                        pendingSpendCoins_ = nil
                    end
                end)
            end
        else
            coinBtn_:SetVisible(false)
        end
    end

    -- 重置播放状态
    _resetAd()

    -- 播放弹入动画
    UIAnim.PopupIn(card_, overlay_, { overshoot = 2.2 })

    -- autoPlay: 跳过确认，立即开始播放广告
    if cfg.autoPlay then
        _startAd()
    end
end

--- 关闭弹窗（带弹出动画）
function AdDialog.Hide()
    _hideWithAnim(nil)
end

--- 每帧更新（保留接口兼容，真实广告由 SDK 回调驱动，无需倒计时）
---@param dt number
function AdDialog.Update(dt)
    -- 真实广告通过 sdk 回调处理，此处无需额外逻辑
end

--- 当前是否有弹窗显示（用于屏蔽底层点击）
---@return boolean
function AdDialog.IsVisible()
    return overlay_ ~= nil and overlay_:IsVisible()
end

-- ---------------------------------------------------------------
-- 内部：带动画关闭
-- ---------------------------------------------------------------
function _hideWithAnim(onDone)
    if not overlay_ or not card_ then return end
    adPlaying_ = false
    UIAnim.PopupOut(card_, overlay_, {
        onComplete = function()
            if onDone then onDone() end
        end,
    })
end

-- ---------------------------------------------------------------
-- 内部：构建弹窗 UI 树（懒创建，只创建一次）
-- ---------------------------------------------------------------
function _buildPanel()
    local dpr     = graphics:GetDPR() or 1
    local screenW = graphics:GetWidth() / dpr

    -- 卡片最大宽度：屏幕宽度的 85%，上限 340
    local cardW = math.min(340, math.floor(screenW * 0.85))



    -- 弹窗卡片（内容区域）
    local cardPanel = UI.Panel {
        id = "adCard",
        width      = cardW,
        maxWidth   = cardW,
        flexShrink = 0,
        paddingTop = 22, paddingBottom = 24,
        paddingLeft = 22, paddingRight = 22,
        backgroundColor = { 18, 22, 40, 252 },
        borderRadius = 20,
        borderWidth  = 1.5,
        borderColor  = { 80, 140, 255, 120 },
        alignItems   = "stretch",
        gap = 12,
        children = {
            -- 标题行（图标 + 文字）
            UI.Panel {
                flexDirection  = "row",
                alignItems     = "center",
                justifyContent = "center",
                alignSelf      = "center",
                gap = 10,
                marginBottom = 2,
                children = {
                    UI.Panel {
                        id     = "adIcon",
                        width  = 34, height = 34,
                        backgroundImage = "Textures/UI/icon_ad.png",
                        backgroundFit   = "contain",
                    },
                    UI.Label {
                        id        = "adTitle",
                        text      = "观看广告",
                        fontSize  = 17,
                        fontWeight = "bold",
                        fontColor = { 220, 235, 255, 255 },
                    },
                },
            },
            -- 奖励说明（stretch 宽度，flexShrink=1 确保不溢出，wordBreak 自动换行）
            UI.Panel {
                width      = "100%",
                flexShrink = 1,
                alignItems = "center",
                paddingTop = 4, paddingBottom = 4,
                minHeight  = 40,
                children = {
                    UI.Label {
                        id        = "adDesc",
                        text      = "观看广告以继续",
                        fontSize  = 13,
                        fontColor = { 160, 175, 210, 220 },
                        textAlign = "center",
                        wordBreak = "break-word",
                        maxWidth  = cardW - 44,  -- 卡片宽度 - 左右内边距
                    },
                },
            },
            -- 分隔线
            UI.Panel {
                width           = "100%",
                height          = 1,
                marginTop       = 2,
                marginBottom    = 2,
                backgroundColor = { 60, 70, 110, 100 },
            },
            -- 金币购买按钮（默认隐藏，有 coinCost 时显示）
            UI.Panel {
                width          = "100%",
                alignItems     = "center",
                justifyContent = "center",
                children = {
                    UI.Button {
                        id      = "adCoinBtn",
                        text    = "花费金币",
                        variant = "secondary",
                        width   = 200, height = 40,
                        fontSize = 13,
                        visible = false,
                    },
                },
            },
            -- 按钮区
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "center",
                alignSelf      = "center",
                gap = 12,
                marginTop = 4,
                children = {
                    -- 取消按钮
                    UI.Button {
                        id       = "adCancelBtn",
                        text     = "取消",
                        variant  = "ghost",
                        width    = 96, height = 40,
                        fontSize = 13,
                        onClick  = function()
                            _hideWithAnim(nil)
                        end,
                    },
                    -- 观看广告按钮
                    UI.Button {
                        id       = "adWatchBtn",
                        text     = "观看广告",
                        variant  = "primary",
                        width    = 150, height = 40,
                        fontSize = 13,
                        onClick  = function()
                            _startAd()
                        end,
                    },
                },
            },
        },
    }

    -- 遮罩层（半透明背景，点击不关闭）
    local overlayPanel = UI.Panel {
        id = "adDialogOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems     = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 180 },
        visible = false,
        children = {
            cardPanel,
        },
    }

    overlay_  = overlayPanel
    card_     = overlayPanel:FindById("adCard")

    titleNode_= overlayPanel:FindById("adTitle")
    descNode_ = overlayPanel:FindById("adDesc")
    iconNode_ = overlayPanel:FindById("adIcon")
    watchBtn_ = overlayPanel:FindById("adWatchBtn")
    cancelBtn_= overlayPanel:FindById("adCancelBtn")
    coinBtn_  = overlayPanel:FindById("adCoinBtn")

    -- 将弹窗挂到根节点
    if rootRef_ then
        rootRef_:AddChild(overlayPanel)
    end
end

-- ---------------------------------------------------------------
-- 内部：重置广告状态
-- ---------------------------------------------------------------
function _resetAd()
    adPlaying_ = false



    -- 恢复按钮状态
    if watchBtn_ then
        watchBtn_:SetText("观看广告")
        watchBtn_:SetDisabled(false)
        watchBtn_.props.onClick = function() _startAd() end
    end
    if cancelBtn_ then
        cancelBtn_:SetDisabled(false)
        cancelBtn_.props.onClick = function() _hideWithAnim(nil) end
    end

    -- 恢复金币按钮状态（广告失败后恢复为初始状态）
    if coinBtn_ and coinBtn_:IsVisible() and currentCfg_ and currentCfg_.coinCost then
        local currentCoins = SaveManager.GetCoins() or 0
        local canAfford = currentCoins >= currentCfg_.coinCost
        if canAfford then
            coinBtn_:SetDisabled(false)
            coinBtn_:SetStyle({ backgroundColor = { 230, 180, 20, 255 }, textColor = { 30, 20, 0, 255 } })
        else
            coinBtn_:SetDisabled(true)
            coinBtn_:SetStyle({ backgroundColor = { 60, 65, 90, 255 }, textColor = { 160, 160, 180, 255 } })
        end
    end
end

-- ---------------------------------------------------------------
-- 内部：开始播放（真实广告 SDK 调用）
-- ---------------------------------------------------------------
function _startAd()
    adPlaying_ = true



    -- 广告播放中：禁用所有按钮
    if watchBtn_ then
        watchBtn_:SetText("播放中…")
        watchBtn_:SetDisabled(true)
    end
    if cancelBtn_ then
        cancelBtn_:SetDisabled(true)
    end
    if coinBtn_ and coinBtn_:IsVisible() then
        coinBtn_:SetDisabled(true)
        coinBtn_:SetStyle({ backgroundColor = { 60, 65, 90, 255 }, textColor = { 160, 160, 180, 255 } })
    end

    -- 调用真实广告 SDK
    sdk:ShowRewardVideoAd(function(result)
        adPlaying_ = false
        if result.success then
            -- 广告完整观看，发放奖励
            _onAdFinished()
        else
            -- 广告播放失败或用户提前关闭
            _onAdFailed(result.msg)
        end
    end)
end

-- ---------------------------------------------------------------
-- 内部：广告播放完毕
-- ---------------------------------------------------------------
function _onAdFinished()
    -- 广告看完，直接发放奖励并关闭弹窗
    SoundManager.Play("reward_chest", 0.7)
    _hideWithAnim(function()
        if pendingGrant_ then
            pendingGrant_()
            pendingGrant_ = nil
        end
    end)
end

-- ---------------------------------------------------------------
-- 内部：广告播放失败（真实广告接入时使用）
-- ---------------------------------------------------------------
function _onAdFailed(reason)
    print("[AdDialog] 广告加载失败：" .. tostring(reason))
    print("[AdDialog] 广告播放失败提示用户")
    _resetAd()
end

return AdDialog
