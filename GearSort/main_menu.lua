-- main_menu.lua
-- 主界面：顶栏（头像/等级/货币）+ LOGO + 主按钮 + 底部导航

local UI            = require("urhox-libs/UI")
local SaveManager   = require("save_manager")
local Levels        = require("levels")
local CoinFlyEffect = require("coin_fly_effect")
local SoundManager  = require("sound_manager")

local UIAnim        = require("ui_anim")

local MainMenu = {}

-- ---------------------------------------------------------------
-- 道具飞行动画（领取后图标飞向背包 Tab）
-- ---------------------------------------------------------------
local flyOverlay_   = nil  -- 飞行粒子挂载容器
local flyParticles_ = {}   -- 当前活跃粒子 { node, sx, sy, cx, cy, tx, ty, delay, duration, elapsed, done }
local flyOnDone_    = nil  -- 全部飞完后回调

local FLY_ICON_SIZE     = 48
local FLY_ICON_SIZE_END = 28
local FLY_COUNT         = 1
local FLY_DELAY_MAX     = 0
local FLY_DURATION_MIN  = 0.75
local FLY_DURATION_MAX  = 0.85
local FLY_SCATTER       = 0
local FLY_CTRL_MIN      = 140
local FLY_CTRL_MAX      = 220

local function flyRnd(lo, hi) return lo + math.random() * (hi - lo) end

local function flyCleanup()
    if flyOverlay_ then
        flyOverlay_:Remove()
        flyOverlay_ = nil
    end
    flyParticles_ = {}
    flyOnDone_    = nil
end

--- 每帧驱动飞行粒子（由 MainMenu 内部 Update 调用）
local function updateFlyParticles(dt)
    if #flyParticles_ == 0 then return end
    local allDone = true
    for _, p in ipairs(flyParticles_) do
        if p.done then goto continue end
        p.elapsed = p.elapsed + dt
        if p.elapsed < p.delay then allDone = false; goto continue end
        local fe = p.elapsed - p.delay
        if fe >= p.duration then
            p.node:SetStyle({ opacity = 0 })
            p.done = true
        else
            local t = fe / p.duration
            -- easeInOut cubic
            local et = (t < 0.5) and (4*t*t*t) or (1 - 4*(1-t)*(1-t)*(1-t))
            -- 二次贝塞尔
            local u = 1 - et
            local px = u*u*p.sx + 2*u*et*p.cx + et*et*p.tx
            local py = u*u*p.sy + 2*u*et*p.cy + et*et*p.ty
            local sz = FLY_ICON_SIZE + (FLY_ICON_SIZE_END - FLY_ICON_SIZE) * et
            local alpha = (et > 0.75) and (1 - (et - 0.75) / 0.25) or 1.0
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
        local cb = flyOnDone_
        flyCleanup()
        if cb then cb() end
    end
end

--- 发射道具图标飞向目标位置
--- @param iconPath string 道具图标路径
--- @param srcX number 起始 X（逻辑坐标）
--- @param srcY number 起始 Y
--- @param dstX number 目标 X
--- @param dstY number 目标 Y
--- @param onDone function|nil 完成回调
local function playItemFly(iconPath, srcX, srcY, dstX, dstY, onDone)
    flyCleanup()
    flyOnDone_ = onDone

    local nodes = {}
    for i = 1, FLY_COUNT do
        nodes[i] = UI.Panel {
            position        = "absolute",
            left            = -FLY_ICON_SIZE,
            top             = -FLY_ICON_SIZE,
            width           = FLY_ICON_SIZE,
            height          = FLY_ICON_SIZE,
            backgroundImage = iconPath,
            backgroundFit   = "contain",
            pointerEvents   = "none",
            opacity         = 0,
        }
    end

    flyOverlay_ = UI.Panel {
        position      = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
        children      = nodes,
    }
    local root = UI.GetRoot()
    if not root then
        flyCleanup()
        if onDone then onDone() end
        return
    end
    root:AddChild(flyOverlay_)

    for i = 1, FLY_COUNT do
        local angle = flyRnd(0, math.pi * 2)
        local dist  = flyRnd(0, FLY_SCATTER)
        local sx = srcX + math.cos(angle) * dist
        local sy = srcY + math.sin(angle) * dist

        local midX = (sx + dstX) * 0.5
        local midY = (sy + dstY) * 0.5
        local dx   = dstX - sx
        local dy   = dstY - sy
        local len  = math.sqrt(dx*dx + dy*dy)
        local nx, ny = 0, -1
        if len > 1 then nx = -dy/len; ny = dx/len end
        local side = (math.random(0,1) == 0) and 1 or -1
        local cd   = flyRnd(FLY_CTRL_MIN, FLY_CTRL_MAX)
        local ctrlX = midX + nx * cd * side
        local ctrlY = midY + ny * cd * side

        local delay = FLY_DELAY_MAX * ((i-1) / math.max(FLY_COUNT-1, 1))

        nodes[i]:SetStyle({ left = sx - FLY_ICON_SIZE*0.5, top = sy - FLY_ICON_SIZE*0.5, opacity = 0 })

        flyParticles_[i] = {
            node = nodes[i],
            sx = sx, sy = sy,
            cx = ctrlX, cy = ctrlY,
            tx = dstX, ty = dstY,
            delay    = delay,
            duration = flyRnd(FLY_DURATION_MIN, FLY_DURATION_MAX),
            elapsed  = 0,
            done     = false,
        }
    end
end

-- ---------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------
local root_                = nil
local onPlay_              = nil
local onSelectLevel_       = nil   -- 打开关卡选择面板
local onSelectLevelStart_  = nil   -- 选定某一关后进入游戏
local onBag_               = nil
local navActiveTab_        = "home"
local navTabs_             = {}
local levelSelPanel_       = nil   -- 独立关卡选择覆盖层
local levelSelBtns_        = {}    -- 关卡格子引用（用于刷新）
local coinLabel_           = nil   -- 顶栏金币数字 Label（用于刷新 & 定位）
local coinIconPanel_       = nil   -- 顶栏金币图标 Panel（用于飞金币目标定位）
local checkInDialog_       = nil   -- 签到弹窗面板
local checkInCard_         = nil   -- 签到弹窗内部卡片（动画用）
local checkInBtn_          = nil   -- 签到按钮（用于已签到时禁用显示）
local checkInRewardPanel_  = nil   -- 奖励展示区（用于飞金币起点定位）
local sideSignBtn_         = nil   -- 左侧签到入口按钮图标（用于更新徽章）
local sideSignPanel_       = nil   -- 左侧签到入口整体容器（切换 tab 时显隐）
local taskPanel_           = nil   -- 任务面板
local taskUndoBar_         = nil   -- 撤回任务进度条 Panel
local taskHubBar_          = nil   -- 插板任务进度条 Panel
local taskUndoLabel_       = nil   -- 撤回任务进度文字
local taskHubLabel_        = nil   -- 插板任务进度文字
local taskUndoClaimBtn_    = nil   -- 撤回任务领取按钮
local taskHubClaimBtn_     = nil   -- 插板任务领取按钮
local taskUndoCard_        = nil   -- 撤回任务卡片容器（闪光动画用）
local taskHubCard_         = nil   -- 插板任务卡片容器（闪光动画用）
local homeScrollView_      = nil   -- 主页 scrollView（切换 tab 时隐藏/显示）
local bagPanel_            = nil   -- 背包面板
local bagUndoCountLabel_   = nil   -- 背包内撤回道具数量
local bagHubCountLabel_    = nil   -- 背包内临时插板数量
local cachedCallbacks_     = nil   -- Show() 时缓存的回调，用于分辨率变化后重建
local isShowing_           = false -- 当前是否正在显示主菜单
local logoNode_            = nil   -- Logo 面板节点（用于入场动画）

-- ---------------------------------------------------------------
-- 飞行动画辅助（需在 navTabs_ 声明之后）
-- ---------------------------------------------------------------

--- 获取背包 Tab 的屏幕中心坐标
local function getBagTabPosition()
    local tab = navTabs_["bag"]
    if not tab then return nil, nil end
    local ok, layout = pcall(function() return tab:GetAbsoluteLayoutForHitTest() end)
    if not ok or not layout then return nil, nil end
    return layout.x + layout.w * 0.5, layout.y + layout.h * 0.5
end

--- 卡片领取刷新特效：缩放脉冲 + 透明度闪烁
--- @param card any UI 节点
local function playCardFlash(card)
    if not card then return end
    UIAnim.CancelAll(card)
    -- 阶段1：快速缩小 + 闪白
    UIAnim.Tween({
        target   = card,
        from     = { scale = 1.0, opacity = 1.0 },
        to       = { scale = 0.92, opacity = 0.5 },
        duration = 0.12,
        easing   = UIAnim.Easing.easeInCubic,
        onComplete = function()
            -- 阶段2：弹回 + 恢复
            UIAnim.Tween({
                target   = card,
                from     = { scale = 0.92, opacity = 0.5 },
                to       = { scale = 1.0, opacity = 1.0 },
                duration = 0.28,
                easing   = UIAnim.Easing.easeOutBack,
            })
        end,
    })
end

-- ---------------------------------------------------------------
-- 颜色主题
-- ---------------------------------------------------------------
local C = {
    bg          = { 8,  14,  30, 255 },
    surface     = { 16, 24,  52, 245 },
    surfaceHi   = { 22, 34,  68, 240 },
    border      = { 50, 90, 180,  70 },
    borderGold  = { 180, 140, 50,  80 },
    accent      = { 60, 140, 255, 255 },
    accentDim   = { 60, 140, 255, 120 },
    textPrimary = { 220, 235, 255, 255 },
    textSecond  = { 130, 160, 210, 200 },
    textMuted   = { 80,  105, 155, 180 },
    gold        = { 255, 200,  55, 255 },
    crystal     = { 100, 215, 255, 255 },
    navActive   = { 80,  160, 255, 255 },
    navInactive = { 100, 120, 165, 190 },
    red         = { 230,  60,  60, 255 },
    divider     = { 40,  60, 120,  80 },
}

-- ---------------------------------------------------------------
-- 主按钮（带背景图）
-- ---------------------------------------------------------------
local function PrimaryButton(opts)
    return UI.Button {
        text        = opts.text or "",
        fontSize    = opts.fontSize or 20,
        fontColor   = C.textPrimary,
        fontWeight  = "bold",
        width       = opts.width or "100%",
        height      = opts.height or 80,
        borderRadius = opts.radius or 6,
        backgroundImage    = "image/menu_topbar_bg_cropped.png",
        backgroundFit   = "fill",
        borderWidth = 0,
        padding = 0,
        flexDirection  = "row",
        alignItems     = "stretch",
        justifyContent = "center",
        gap = 10,
        onClick  = opts.onClick,
        children = opts.children,
    }
end

local function SecondaryButton(opts)
    return UI.Button {
        text        = opts.text or "",
        fontSize    = opts.fontSize or 17,
        fontColor   = C.textPrimary,
        fontWeight  = "bold",
        flexGrow    = opts.flexGrow or 0,
        width       = opts.width or nil,
        height      = opts.height or 68,
        borderRadius = opts.radius or 6,
        backgroundImage    = "image/menu_topbar_bg_cropped.png",
        backgroundFit   = "cover",
        borderWidth = 0,
        flexDirection  = "row",
        alignItems     = "center",
        justifyContent = "center",
        gap = 8,
        onClick  = opts.onClick,
        children = opts.children,
    }
end

-- ---------------------------------------------------------------
-- 左上角：玩家信息面板（头像 + 昵称 + 等级进度条）
-- ---------------------------------------------------------------
local nicknameLabel_ = nil  -- 昵称 Label 引用
local nicknameFetched_ = false  -- 是否已成功获取过昵称

local function buildPlayerPanel()
    nicknameLabel_ = UI.Label {
        text       = "GearMaster",
        fontSize   = 15,
        fontColor  = C.textPrimary,
        fontWeight = "bold",
    }
    return UI.Panel {
        position        = "absolute",
        top             = 50, left = "2%",
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 10,
        paddingLeft     = 10, paddingRight = 16,
        paddingTop      = 6, paddingBottom = 6,
        borderRadius    = 25,
        backgroundColor = { 8, 14, 36, 215 },
        borderWidth     = 1,
        borderColor     = C.borderGold,
        children = {
            -- 头像圆框
            UI.Panel {
                width           = 40, height = 40,
                borderRadius    = 20,
                borderWidth     = 2,
                borderColor     = C.borderGold,
                backgroundColor = { 20, 32, 65, 255 },
                overflow        = "hidden",
                alignItems      = "center",
                justifyContent  = "center",
                children = {
                    UI.Panel {
                        width           = 36, height = 36,
                        backgroundImage = "image/icon_avatar_20260525094956.png",
                        backgroundFit   = "contain",
                    },
                },
            },
            -- 昵称
            nicknameLabel_,
        },
    }
end

local function fetchNickname()
    if nicknameFetched_ then return end
    ---@diagnostic disable-next-line: undefined-global
    local ok, myUserId = pcall(function() return lobby:GetMyUserId() end)
    if not ok or not myUserId then return end
    GetUserNickname({
        userIds = { myUserId },
        onSuccess = function(nicknames)
            if nicknames and #nicknames > 0 and nicknames[1].nickname and nicknames[1].nickname ~= "" then
                nicknameFetched_ = true
                if nicknameLabel_ then
                    nicknameLabel_:SetText(nicknames[1].nickname)
                end
            end
        end,
        onError = function(errorCode)
            --print("[MainMenu] 获取昵称失败:", errorCode)
        end,
    })
end

-- ---------------------------------------------------------------
-- 右上角：金币资源面板（仅金币）
-- ---------------------------------------------------------------
local function buildCoinPanel()
    return UI.Panel {
        position        = "absolute",
        top             = 50, right = "2%",
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 8,
        paddingLeft     = 14, paddingRight = 14,
        paddingTop      = 8, paddingBottom = 8,
        borderRadius    = 25,
        backgroundColor = { 8, 14, 36, 215 },
        borderWidth     = 1,
        borderColor     = C.borderGold,
        children = {
            UI.Panel {
                id              = "topBarCoinIcon",
                width           = 32, height = 32,
                backgroundImage = "image/icon_coin_20260525095234.png",
                backgroundFit   = "contain",
            },
            UI.Label {
                id         = "topBarCoinLabel",
                text       = tostring(SaveManager.GetCoins()),
                fontSize   = 20,
                fontColor  = C.gold,
                fontWeight = "bold",
            },
        },
    }
end

-- ---------------------------------------------------------------
-- LOGO 区
-- ---------------------------------------------------------------
local function buildLogo()
    return UI.Panel {
        id         = "mainLogo",
        width      = "100%",
        height     = 500,
        paddingTop = 200,
        alignItems     = "center",
        justifyContent = "center",
        children = {
            UI.Panel {
                width  = 440,
                height = 440,
                backgroundImage    = "image/menu_logo_20260525091734.png",
                backgroundFit   = "contain",
            },
        },
    }
end

-- ---------------------------------------------------------------
-- 连胜进度条 UI
-- 节点含义：达到该连胜数时，【当局及之后每局】的倍率
-- streak=0→×1, streak=1→×2, streak=2→×5, streak=3→×10, streak=4+→×15
-- ---------------------------------------------------------------
local STREAK_NODES = {
    { streak = 0, label = "×1",  color = { 120, 160, 220, 255 } },
    { streak = 1, label = "×2",  color = {  80, 210, 160, 255 } },
    { streak = 2, label = "×5",  color = { 255, 200,  60, 255 } },
    { streak = 3, label = "×10", color = { 255, 130,  40, 255 } },
    { streak = 4, label = "×15", color = { 255,  60,  60, 255 } },
}

local function buildStreakBar()
    local streak     = SaveManager.GetWinStreak()
    local multiplier = SaveManager.GetStreakMultiplier()
    local nodeCount  = #STREAK_NODES  -- 5

    -- 自适应缩放：以 750px 逻辑宽度为基准
    local dpr    = graphics:GetDPR() or 1
    local screenW = graphics:GetWidth() / dpr
    local sc     = math.min(1.4, math.max(0.6, screenW / 750))

    -- 节点 streak 从 0 起算，进度条：streak=0 → 空，streak>=4 → 满
    -- fillPct: 当前连胜在 [0, nodeCount-1] 区间的百分比（共 4 段间隔）
    local maxStreak     = nodeCount - 1   -- 4
    local clampedStreak = math.min(math.max(streak, 0), maxStreak)
    local fillPct       = math.floor(clampedStreak / maxStreak * 100)
    local fillW         = string.format("%d%%", fillPct)

    -- 当前档位索引：streak=0→1, streak=1→2, ..., streak=4+→5
    local curIdx   = math.min(streak + 1, nodeCount)
    local curColor = STREAK_NODES[curIdx].color

    -- 倍率文字（下一档提示）
    local nextNode = STREAK_NODES[math.min(curIdx + 1, nodeCount)]
    local tipText  = streak == 0
        and "赢一局开启连胜加成"
        or  (streak >= maxStreak
            and "已达最高倍率！"
            or  string.format("再赢 %d 局升至 %s", nextNode.streak - streak, nextNode.label))

    -- 节点尺寸（统一在循环外计算，供进度条 offset 使用）
    local nBig  = math.floor(32 * sc)
    local nSml  = math.floor(16 * sc)
    local nDot  = math.floor(12 * sc)
    -- 进度条两端各缩进半个大圆宽度，使轨道精确在两端节点圆心之间延伸
    local trackOffset = math.floor(nBig / 2)

    -- 节点指示点（5 个）
    local nodeItems = {}
    for i, nd in ipairs(STREAK_NODES) do
        local reached = (streak >= nd.streak)
        local isCur   = (streak == nd.streak) or (streak >= maxStreak and i == nodeCount)
        nodeItems[i] = UI.Panel {
            -- 外圆
            width = isCur and nBig or nSml,
            height = isCur and nBig or nSml,
            borderRadius = isCur and math.floor(nBig/2) or math.floor(nSml/2),
            backgroundColor = reached and nd.color or { 25, 35, 75, 220 },
            borderWidth = isCur and 3 or 1,
            borderColor = reached and nd.color or { 50, 70, 130, 180 },
            alignItems     = "center",
            justifyContent = "center",
            children = isCur and {
                UI.Panel {
                    width = nDot, height = nDot,
                    borderRadius = math.floor(nDot/2),
                    backgroundColor = { 255, 255, 255, 200 },
                },
            } or {},
        }
    end

    -- 倍率里程碑标签（5 列等分）
    local labelItems = {}
    for i, nd in ipairs(STREAK_NODES) do
        local reached = (streak >= nd.streak)
        local isCur   = (streak == nd.streak) or (streak >= maxStreak and i == nodeCount)
        labelItems[i] = UI.Panel {
            flexGrow       = 1,
            alignItems     = (i == 1 and "flex-start")
                          or (i == nodeCount and "flex-end")
                          or "center",
            children = {
                UI.Label {
                    text      = nd.label,
                    fontSize  = math.floor((isCur and 22 or 20) * sc),
                    fontColor = isCur and nd.color
                             or (reached and { nd.color[1], nd.color[2], nd.color[3], 180 }
                             or C.textMuted),
                    fontWeight = isCur and "bold" or "normal",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = math.floor(64 * sc), paddingRight = math.floor(64 * sc),
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = C.surface,
                borderRadius = math.floor(14 * sc),
                borderWidth  = 1,
                borderColor  = C.border,
                paddingTop = math.floor(12 * sc), paddingBottom = math.floor(14 * sc),
                paddingLeft = math.floor(80 * sc), paddingRight = math.floor(80 * sc),
                gap = math.floor(10 * sc),
                children = {
                    -- 行1：标题（左）+ 当前倍率（右）
                    UI.Panel {
                        flexDirection  = "row",
                        alignItems     = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems    = "center",
                                gap = 6,
                                children = {
                                    UI.Label {
                                        text      = "连胜加成",
                                        fontSize  = math.floor(26 * sc),
                                        fontColor = C.textSecond,
                                    },
                                    -- 连胜数气泡
                                    UI.Panel {
                                        paddingLeft = 7, paddingRight = 7,
                                        paddingTop = 2, paddingBottom = 2,
                                        borderRadius = 8,
                                        backgroundColor = streak > 0
                                            and { curColor[1], curColor[2], curColor[3], 40 }
                                            or  { 30, 40, 80, 160 },
                                        borderWidth = 1,
                                        borderColor = streak > 0
                                            and { curColor[1], curColor[2], curColor[3], 120 }
                                            or  { 50, 65, 120, 100 },
                                        children = {
                                            UI.Label {
                                                text      = string.format("%d 连胜", streak),
                                                fontSize  = math.floor(11 * sc),
                                                fontColor = streak > 0 and curColor or C.textMuted,
                                                fontWeight = "bold",
                                            },
                                        },
                                    },
                                },
                            },
                            -- 当前倍率大字
                            UI.Panel {
                                flexDirection = "row",
                                alignItems    = "baseline",
                                gap = 3,
                                children = {
                                    UI.Label {
                                        text      = string.format("×%.1f", multiplier):gsub("%.0$", ""),
                                        fontSize  = math.floor(44 * sc),
                                        fontColor = curColor,
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text      = "金币",
                                        fontSize  = math.floor(11 * sc),
                                        fontColor = C.textMuted,
                                    },
                                },
                            },
                        },
                    },

                    -- 行2：进度条 + 节点
                    -- 结构：最外层是绝对定位容器（宽100%，高40）
                    --   └─ 轨道容器（两端缩进 trackOffset，flexRow，alignItems=center）
                    --       ├─ 背景轨道（flexGrow=1，高6，absolute覆盖）
                    --       └─ 填充条（width=fillW%，高6，absolute left=0）
                    --   └─ 节点行（absolute，left/right=0，space-between）
                    UI.Panel {
                        width = "100%",
                        height = math.floor(40 * sc),
                        alignItems = "center",
                        justifyContent = "center",
                        children = {
                            -- 轨道区（两端留 trackOffset，内部放背景轨道和填充条）
                            UI.Panel {
                                position = "absolute",
                                left = trackOffset, right = trackOffset,
                                height = 6,
                                children = {
                                    -- 背景轨道（满宽）
                                    UI.Panel {
                                        position = "absolute",
                                        left = 0, right = 0, top = 0, bottom = 0,
                                        borderRadius = 3,
                                        backgroundColor = { 20, 30, 70, 200 },
                                    },
                                    -- 填充进度：width = fillPct% of 轨道宽
                                    UI.Panel {
                                        position = "absolute",
                                        left = 0, top = 0, bottom = 0,
                                        width = fillW,
                                        borderRadius = 3,
                                        backgroundColor = curColor,
                                    },
                                },
                            },
                            -- 节点行（覆盖完整宽度，节点圆心精确落在轨道两端）
                            UI.Panel {
                                position = "absolute",
                                left = 0, right = 0,
                                flexDirection  = "row",
                                justifyContent = "space-between",
                                alignItems     = "center",
                                children       = nodeItems,
                            },
                        },
                    },

                    -- 行3：倍率标签行
                    UI.Panel {
                        width          = "100%",
                        flexDirection  = "row",
                        justifyContent = "space-between",
                        children       = labelItems,
                    },

                    -- 行4：提示文字
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text      = tipText,
                                fontSize  = math.floor(11 * sc),
                                fontColor = C.textMuted,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------
-- 主按钮区
-- ---------------------------------------------------------------
local function buildButtons()
    local currentLevel = SaveManager.GetUnlocked()
    -- 按钮设计尺寸 250×90，根据实际宽度等比算高度
    local IMG_W, IMG_H = 250, 90
    local dpr        = graphics:GetDPR() or 1
    local screenW    = graphics:GetWidth() / dpr
    -- 两侧间距自适应：屏幕宽度的 15%，限制在 60~200 之间
    local padH       = math.min(200, math.max(60, math.floor(screenW * 0.15)))
    local btnW       = screenW - padH * 2
    local btnH       = math.floor(btnW * IMG_H / IMG_W)
    -- 以图片原始宽度为基准缩放字体
    local fontScale  = btnW / IMG_W
    local fsMain     = math.max(10, math.floor(23 * fontScale))
    local fsSub      = math.max(8,  math.floor(14 * fontScale))

    return UI.Panel {
        width = "100%",
        paddingLeft = padH, paddingRight = padH,
        gap = 10,
        alignItems = "center",
        children = {
            -- 继续游戏
            PrimaryButton {
                text    = "",
                width   = "100%",
                height  = btnH,
                onClick = function()
                    SoundManager.Play("menu_start")
                    if onPlay_ then onPlay_() end
                end,
                children = {
                    UI.Panel {
                        width          = "100%",
                        height         = "100%",
                        flexDirection  = "column",
                        alignItems     = "center",
                        justifyContent = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text        = "开始游戏",
                                fontSize    = fsMain,
                                fontColor   = { 255, 255, 255, 255 },
                                fontWeight  = "bold",
                                strokeColor = { 0, 0, 0, 255 },
                                strokeWidth = 4,
                            },
                        },
                    },
                },
            },

        },
    }
end

-- ---------------------------------------------------------------
-- 侧边快捷入口（排行榜 / 礼包）
-- ---------------------------------------------------------------
-- ---------------------------------------------------------------
-- 签到弹窗
-- ---------------------------------------------------------------
local function buildCheckInDialog()
    local alreadyDone = SaveManager.HasCheckedInToday()
    local reward      = SaveManager.GetCheckInReward()

    -- 签到按钮（需要保存引用）
    local confirmBtn = UI.Button {
        id              = "checkInConfirmBtn",
        text            = alreadyDone and "已签到" or string.format("签到领取 +%d 金币", reward),
        width           = "100%",
        height          = math.floor(274 * 94 / 270),
        fontSize        = 18,
        backgroundImage = alreadyDone and nil or "Textures/UI/btn_emboss.png",
        backgroundFit   = "fill",
        backgroundColor = alreadyDone and { 40, 50, 90, 180 } or nil,
        fontColor       = alreadyDone and { 120, 140, 180, 200 } or C.gold,
        fontWeight      = "bold",
        opacity         = alreadyDone and 0.6 or 1.0,
        onClick = alreadyDone and nil or function()
            local earned = SaveManager.DoCheckIn()
            if earned > 0 then
                SoundManager.Play("checkin_reward")
                -- 更新按钮状态为已签到
                if checkInBtn_ then
                    checkInBtn_:SetStyle({
                        backgroundColor = { 40, 50, 90, 180 },
                        opacity         = 0.6,
                    })
                    checkInBtn_:SetText("已签到")
                end
                -- 隐藏侧边签到按钮上的红点徽章
                if sideSignBtn_ then
                    local badge = sideSignBtn_:FindById("checkInBadge")
                    if badge then badge:SetVisible(false) end
                end
                -- 飞金币：从签到侧边按钮（始终可见，布局已稳定）飞向右上角金币 UI
                local tx, ty = MainMenu.GetCoinUIPosition()
                -- 先获取起点坐标（弹窗关闭前）
                local sx, sy
                if sideSignBtn_ then
                    local ok, layout = pcall(function()
                        return sideSignBtn_:GetAbsoluteLayoutForHitTest()
                    end)
                    if ok and layout then
                        sx = layout.x + layout.w * 0.5
                        sy = layout.y + layout.h * 0.5
                    end
                end
                -- 关闭弹窗（动画淡出）
                if checkInDialog_ and checkInCard_ then
                    UIAnim.PopupOut(checkInCard_, checkInDialog_)
                end
                if tx and ty then
                    local dpr = graphics:GetDPR() or 1
                    local sw  = graphics:GetWidth()  / dpr
                    local sh  = graphics:GetHeight() / dpr
                    local coinCount = math.min(math.max(math.floor(earned / 5), 3), 15)
                    local fromX = sx or (sw * 0.5)
                    local fromY = sy or (sh * 0.5)
                    CoinFlyEffect.Play(fromX, fromY, tx, ty, coinCount, function()
                        MainMenu.RefreshCoinDisplay()
                    end)
                else
                    MainMenu.RefreshCoinDisplay()
                end
            end
        end,
    }
    checkInBtn_ = confirmBtn

    local rewardPanel = UI.Panel {
        width           = "100%",
        height          = 64,
        borderRadius    = 12,
        backgroundColor = { 8, 14, 36, 200 },
        borderWidth     = 1,
        borderColor     = { 180, 140, 50, 60 },
        flexDirection   = "row",
        alignItems      = "center",
        justifyContent  = "center",
        gap             = 10,
        children = {
            UI.Panel {
                width = 36, height = 36,
                backgroundImage = "image/icon_coin_20260525095234.png",
                backgroundFit   = "contain",
            },
            UI.Label {
                text      = string.format("+%d 金币", reward),
                fontSize  = 28,
                fontColor = C.gold,
                fontWeight = "bold",
            },
        },
    }
    checkInRewardPanel_ = rewardPanel

    return UI.Panel {
        id              = "checkInDialog",
        position        = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems      = "center",
        justifyContent  = "center",
        backgroundColor = { 0, 0, 0, 180 },
        visible         = false,
        children = {
            UI.Panel {
                id              = "checkInCard",
                width           = 320,
                paddingTop      = 24, paddingBottom = 20,
                paddingLeft     = 24, paddingRight  = 24,
                backgroundColor = { 16, 22, 48, 252 },
                borderRadius    = 20,
                borderWidth     = 1,
                borderColor     = C.borderGold,
                alignItems      = "center",
                gap             = 16,
                children = {
                    -- 图标
                    UI.Panel {
                        width  = 80, height = 80,
                        backgroundImage = "image/icon_gift_20260525094945.png",
                        backgroundFit   = "contain",
                    },
                    -- 标题
                    UI.Label {
                        text      = "每日签到",
                        fontSize  = 22,
                        fontColor = C.gold,
                        fontWeight = "bold",
                    },
                    -- 说明
                    UI.Label {
                        text      = string.format("每天签到可领取 %d 金币", reward),
                        fontSize  = 14,
                        fontColor = C.textSecond,
                    },
                    -- 奖励展示区
                    rewardPanel,
                    -- 签到 / 已签到 按钮
                    confirmBtn,
                    -- 关闭按钮
                    UI.Button {
                        text      = "关闭",
                        variant   = "ghost",
                        width     = "100%",
                        height    = 44,
                        fontSize  = 14,
                        fontColor = C.textMuted,
                        onClick = function()
                            if checkInDialog_ and checkInCard_ then
                                UIAnim.PopupOut(checkInCard_, checkInDialog_)
                            end
                        end,
                    },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------
-- 侧边快捷入口
-- ---------------------------------------------------------------
local function buildSideButtons()
    local alreadyDone = SaveManager.HasCheckedInToday()
    -- 未签到时显示红点徽章（尺寸 ×0.5）
    local badgeNode = (not alreadyDone) and UI.Panel {
        id              = "checkInBadge",
        position        = "absolute",
        top = -3, right = -3,
        width = 11, height = 11,
        borderRadius = 6,
        backgroundColor = C.red,
        alignItems     = "center",
        justifyContent = "center",
        children = {
            UI.Label { text = "!", fontSize = 7, fontColor = { 255, 255, 255, 255 }, fontWeight = "bold" },
        },
    } or nil

    -- 签到按钮：138×138 降低 50% → 69×69，图标填满按钮
    local iconWrap = UI.Panel {
        id              = "checkInSideIcon",
        width           = 69, height = 69,
        borderRadius    = 18,
        backgroundColor = C.surfaceHi,
        borderWidth     = 1,
        borderColor     = C.borderGold,
        alignItems      = "center",
        justifyContent  = "center",
        overflow        = "visible",
        children = {
            UI.Panel {
                width           = 69, height = 69,   -- 图标与按钮等大
                backgroundImage = "image/icon_gift_20260525094945.png",
                backgroundFit   = "contain",
            },
            badgeNode or UI.Panel {},
        },
    }

    local sideBtn = UI.Panel {
        width      = 75,
        alignItems = "center",
        gap        = 4,
        onClick    = function()
            SoundManager.Play("btn_click")
            if checkInDialog_ and checkInCard_ then
                UIAnim.PopupIn(checkInCard_, checkInDialog_)
            end
        end,
        children = {
            iconWrap,
            UI.Label {
                text      = "签到",
                fontSize  = 15,
                fontColor = C.textSecond,
            },
        },
    }
    sideSignBtn_ = sideBtn

    -- 向下对齐：bottom 锚定在连胜 UI 上方
    local leftPanel = UI.Panel {
        id         = "sideSignPanel",
        position   = "absolute",
        left       = 36,
        bottom     = 530,
        alignItems = "center",
        gap        = 4,
        children   = { sideBtn },
    }

    local rightPanel = UI.Panel {}

    return leftPanel, rightPanel
end

-- ---------------------------------------------------------------
-- 切换页签（显示/隐藏主页内容与任务面板）
-- ---------------------------------------------------------------
local function switchTab(tabId)
    local prevTab = navActiveTab_
    if tabId ~= prevTab then
        SoundManager.Play("tab_switch")
    end
    navActiveTab_ = tabId
    -- 刷新导航 tab 高亮（切换背景图 + 文字颜色）
    for id, panel in pairs(navTabs_) do
        local active = (id == tabId)
        panel.props.backgroundImage = active
            and "image/btn_glow_v1_cropped.png"
            or  "image/btn_raised_v1_cropped.png"
        local lbl = panel:GetChildAt(0)
        if lbl then
            lbl.props.fontColor  = { 255, 255, 255, 255 }
            lbl.props.fontWeight = active and "bold" or "normal"
        end
    end

    -- Tab 内容切换动画（仅 tab 确实切换时）
    local tabOrder = { home = 1, tasks = 2, bag = 3 }
    local doAnim = (prevTab ~= tabId)

    -- 确定进入面板的节点
    local incomingNode = nil
    if tabId == "home" then incomingNode = homeScrollView_
    elseif tabId == "tasks" then incomingNode = taskPanel_
    elseif tabId == "bag" then incomingNode = bagPanel_
    end

    -- 主页内容
    if homeScrollView_ then
        if tabId == "home" then
            homeScrollView_:SetVisible(true)
        else
            homeScrollView_:SetVisible(false)
        end
    end
    -- 签到侧边按钮：仅主页显示
    if sideSignPanel_ then
        sideSignPanel_:SetVisible(tabId == "home")
    end
    -- 切换离开主页时关闭签到弹窗（即时关闭，不播动画）
    if tabId ~= "home" and checkInDialog_ then
        if checkInCard_ then
            UIAnim.CancelAll(checkInCard_)
            checkInCard_:SetStyle({ opacity = 1, top = 0 })
        end
        UIAnim.CancelAll(checkInDialog_)
        checkInDialog_:SetVisible(false)
        checkInDialog_:SetStyle({ opacity = 1 })
    end
    -- 任务面板
    if taskPanel_ then
        if tabId == "tasks" then
            taskPanel_:SetVisible(true)
            MainMenu.RefreshTaskPanel()
        else
            taskPanel_:SetVisible(false)
        end
    end
    -- 背包面板
    if bagPanel_ then
        if tabId == "bag" then
            bagPanel_:SetVisible(true)
            MainMenu.RefreshBagPanel()
        else
            bagPanel_:SetVisible(false)
        end
    end

    -- 淡入进入面板（简洁动画，避免复杂滑动带来的布局问题）
    if doAnim and incomingNode then
        UIAnim.FadeIn(incomingNode, UIAnim.Duration.TAB_SLIDE, {
            easing = UIAnim.Easing.easeOutCubic,
        })
    end
end

-- ---------------------------------------------------------------
-- 构建任务面板（全屏覆盖，初始隐藏）
-- ---------------------------------------------------------------
local function buildTaskPanel()
    -- 进度条辅助函数
    local function buildProgressBar(barId, labelId, current, total, color)
        local pct = (total > 0) and (current / total) or 0
        return UI.Panel {
            width = "100%",
            height = 12,
            borderRadius = 6,
            backgroundColor = { 20, 30, 55, 255 },
            overflow = "hidden",
            children = {
                UI.Panel {
                    id = barId,
                    width = math.floor(pct * 100) .. "%",
                    height = "100%",
                    borderRadius = 6,
                    backgroundColor = color,
                },
            },
        }
    end

    -- 撤回任务卡片
    local undoProg, undoTotal = SaveManager.GetTaskUndoProgress()
    local undoClaimable = SaveManager.GetTaskUndoClaimable()
    local undoCard = UI.Panel {
        id = "taskUndoCard",
        width = "100%",
        padding = 20,
        backgroundColor = { 16, 24, 46, 240 },
        borderRadius = 16,
        borderWidth = 1,
        borderColor = { 80, 110, 200, 100 },
        gap = 12,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                width = "100%",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 10,
                        children = {
                            UI.Panel {
                                width = 44, height = 44,
                                backgroundImage = "Textures/UI/icon_undo.png",
                                backgroundFit = "contain",
                            },
                            UI.Panel {
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = "撤回道具",
                                        fontSize = 18,
                                        fontColor = { 220, 235, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "每通关 5 关获得 1 个",
                                        fontSize = 12,
                                        fontColor = { 130, 160, 200, 200 },
                                    },
                                },
                            },
                        },
                    },
                    -- 领取按钮
                    UI.Button {
                        id = "taskUndoClaimBtn",
                        text = undoClaimable > 0 and "领取" or "进行中",
                        variant = undoClaimable > 0 and "primary" or "ghost",
                        width = 80, height = 38,
                        fontSize = 15,
                        opacity = undoClaimable > 0 and 1.0 or 0.5,
                        onClick = undoClaimable > 0 and function()
                            SoundManager.Play("task_claim")
                            SaveManager.ClaimTaskUndo()
                            MainMenu.RefreshTaskPanel()
                        end or nil,
                    },
                },
            },
            -- 进度文字
            UI.Label {
                id = "taskUndoLabel",
                text = string.format("进度：%d / %d 关", undoProg, undoTotal),
                fontSize = 14,
                fontColor = { 160, 190, 240, 220 },
            },
            -- 进度条
            buildProgressBar("taskUndoBar", "taskUndoBarFill",
                undoProg, undoTotal, { 100, 160, 255, 220 }),
        },
    }

    -- 插板任务卡片
    local hubProg, hubTotal = SaveManager.GetTaskHubProgress()
    local hubClaimable = SaveManager.GetTaskHubClaimable()
    local hubCard = UI.Panel {
        id = "taskHubCard",
        width = "100%",
        padding = 20,
        backgroundColor = { 16, 24, 46, 240 },
        borderRadius = 16,
        borderWidth = 1,
        borderColor = { 180, 120, 50, 100 },
        gap = 12,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                width = "100%",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 10,
                        children = {
                            UI.Panel {
                                width = 44, height = 44,
                                backgroundImage = "image/hub_single_slot_20260526063407.png",
                                backgroundFit = "contain",
                            },
                            UI.Panel {
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = "临时插板",
                                        fontSize = 18,
                                        fontColor = { 255, 210, 140, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "每通关 10 关获得 1 个",
                                        fontSize = 12,
                                        fontColor = { 180, 150, 100, 200 },
                                    },
                                },
                            },
                        },
                    },
                    UI.Button {
                        id = "taskHubClaimBtn",
                        text = hubClaimable > 0 and "领取" or "进行中",
                        variant = hubClaimable > 0 and "primary" or "ghost",
                        width = 80, height = 38,
                        fontSize = 15,
                        opacity = hubClaimable > 0 and 1.0 or 0.5,
                        onClick = hubClaimable > 0 and function()
                            SoundManager.Play("task_claim")
                            SaveManager.ClaimTaskHub()
                            MainMenu.RefreshTaskPanel()
                        end or nil,
                    },
                },
            },
            UI.Label {
                id = "taskHubLabel",
                text = string.format("进度：%d / %d 关", hubProg, hubTotal),
                fontSize = 14,
                fontColor = { 220, 180, 100, 220 },
            },
            buildProgressBar("taskHubBar", "taskHubBarFill",
                hubProg, hubTotal, { 255, 180, 60, 220 }),
        },
    }

    return UI.Panel {
        id = "taskPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        backgroundColor = { 6, 10, 22, 245 },
        children = {
            -- 背景底图（复用主菜单背景）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "Textures/UI/bg_main_menu.png",
                backgroundFit = "cover",
                opacity = 0.4,
            },
            -- 内容区
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 70,
                children = {
                    UI.ScrollView {
                        width = "100%", height = "100%",
                        scrollY = true, scrollX = false,
                        showScrollbar = false,
                        children = {
                            UI.Panel {
                                width = "100%",
                                paddingTop = 80,
                                paddingBottom = 24,
                                paddingLeft = 20,
                                paddingRight = 20,
                                gap = 16,
                                children = {
                                    -- 页面标题
                                    UI.Label {
                                        text = "任务",
                                        fontSize = 26,
                                        fontColor = { 220, 235, 255, 255 },
                                        fontWeight = "bold",
                                        alignSelf = "center",
                                    },
                                    UI.Label {
                                        text = "完成关卡即可积累任务进度，进度达标后点击领取道具",
                                        fontSize = 13,
                                        fontColor = { 120, 150, 200, 180 },
                                        alignSelf = "center",
                                        textAlign = "center",
                                    },
                                    -- 分隔线
                                    UI.Panel {
                                        width = "100%", height = 1,
                                        backgroundColor = { 60, 80, 140, 80 },
                                        marginBottom = 4,
                                    },
                                    undoCard,
                                    hubCard,
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------
-- 构建背包面板（全屏覆盖，初始隐藏）
-- ---------------------------------------------------------------
local function buildBagPanel()
    -- 道具卡片辅助函数
    local function buildItemCard(opts)
        -- opts: icon, name, desc, countId, color, emptyText
        local color = opts.color or { 100, 160, 255, 255 }
        return UI.Panel {
            width = "100%",
            padding = 20,
            backgroundColor = { 16, 24, 46, 240 },
            borderRadius = 16,
            borderWidth = 1,
            borderColor = { color[1], color[2], color[3], 80 },
            gap = 14,
            children = {
                -- 顶部：图标 + 名称 + 描述
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 14,
                    width = "100%",
                    children = {
                        -- 图标容器
                        UI.Panel {
                            width = 64, height = 64,
                            borderRadius = 14,
                            backgroundColor = { color[1], color[2], color[3], 18 },
                            borderWidth = 1,
                            borderColor = { color[1], color[2], color[3], 60 },
                            alignItems = "center",
                            justifyContent = "center",
                            children = {
                                UI.Panel {
                                    width = 48, height = 48,
                                    backgroundImage = opts.icon,
                                    backgroundFit = "contain",
                                },
                            },
                        },
                        -- 文字区
                        UI.Panel {
                            flexGrow = 1,
                            gap = 4,
                            children = {
                                UI.Label {
                                    text = opts.name,
                                    fontSize = 18,
                                    fontColor = { color[1], color[2], color[3], 255 },
                                    fontWeight = "bold",
                                },
                                UI.Label {
                                    text = opts.desc,
                                    fontSize = 13,
                                    fontColor = { 130, 155, 200, 190 },
                                },
                            },
                        },
                    },
                },
                -- 分隔线
                UI.Panel {
                    width = "100%", height = 1,
                    backgroundColor = { color[1], color[2], color[3], 30 },
                },
                -- 底部：数量展示
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "space-between",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = "当前库存",
                            fontSize = 14,
                            fontColor = { 130, 155, 200, 180 },
                        },
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "baseline",
                            gap = 5,
                            children = {
                                UI.Label {
                                    id = opts.countId,
                                    text = "0",
                                    fontSize = 34,
                                    fontColor = { color[1], color[2], color[3], 255 },
                                    fontWeight = "bold",
                                },
                                UI.Label {
                                    text = "个",
                                    fontSize = 15,
                                    fontColor = { 130, 155, 200, 180 },
                                },
                            },
                        },
                    },
                },
                -- 获取途径提示
                UI.Panel {
                    width = "100%",
                    padding = 10,
                    borderRadius = 8,
                    backgroundColor = { 10, 16, 35, 200 },
                    borderWidth = 1,
                    borderColor = { 40, 55, 110, 80 },
                    children = {
                        UI.Label {
                            text = opts.howToGet,
                            fontSize = 12,
                            fontColor = { 100, 130, 180, 180 },
                            textAlign = "center",
                            width = "100%",
                        },
                    },
                },
            },
        }
    end

    local undoCount = SaveManager.GetUndoCount()
    local hubCount  = SaveManager.GetTempHubCount()

    local undoCard = buildItemCard({
        icon      = "Textures/UI/icon_undo.png",
        name      = "撤回道具",
        desc      = "撤销上一步操作，在游戏中使用",
        countId   = "bagUndoCount",
        color     = { 255, 180, 60 },
        howToGet  = "获取途径：任务系统（每通关 5 关领取 1 个）",
    })

    local hubCard = buildItemCard({
        icon      = "image/hub_single_slot_20260526063407.png",
        name      = "临时插板",
        desc      = "临时增加一个插槽，本局有效",
        countId   = "bagHubCount",
        color     = { 100, 160, 255 },
        howToGet  = "获取途径：任务系统（每通关 10 关领取 1 个）",
    })

    return UI.Panel {
        id = "bagPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        backgroundColor = { 6, 10, 22, 245 },
        children = {
            -- 背景底图
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "Textures/UI/bg_main_menu.png",
                backgroundFit = "cover",
                opacity = 0.4,
            },
            -- 内容区（留出底部导航高度）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 70,
                children = {
                    UI.ScrollView {
                        width = "100%", height = "100%",
                        scrollY = true, scrollX = false,
                        showScrollbar = false,
                        children = {
                            UI.Panel {
                                width = "100%",
                                paddingTop = 80,
                                paddingBottom = 24,
                                paddingLeft = 20,
                                paddingRight = 20,
                                gap = 16,
                                children = {
                                    -- 页面标题
                                    UI.Label {
                                        text = "背包",
                                        fontSize = 26,
                                        fontColor = { 220, 235, 255, 255 },
                                        fontWeight = "bold",
                                        alignSelf = "center",
                                    },
                                    UI.Label {
                                        text = "存放通过任务和购买获得的道具",
                                        fontSize = 13,
                                        fontColor = { 120, 150, 200, 180 },
                                        alignSelf = "center",
                                        textAlign = "center",
                                    },
                                    -- 分隔线
                                    UI.Panel {
                                        width = "100%", height = 1,
                                        backgroundColor = { 60, 80, 140, 80 },
                                        marginBottom = 4,
                                    },
                                    undoCard,
                                    hubCard,
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------
-- 底部导航栏
-- ---------------------------------------------------------------
local function buildNavBar()
    local tabs = {
        { id = "home",  label = "主页",
          onClick = function() switchTab("home") end },
        { id = "tasks", label = "任务",
          onClick = function() switchTab("tasks") end },
        { id = "bag",   label = "背包",
          onClick = function() switchTab("bag") end },
    }

    local tabItems = {}
    for _, tab in ipairs(tabs) do
        local t        = tab
        local isActive = (t.id == navActiveTab_)
        local btn = UI.Panel {
            id              = "navTab_" .. t.id,
            flexGrow        = 1,
            margin          = 8,
            alignItems      = "center",
            justifyContent  = "center",
            backgroundImage = isActive
                and "image/btn_glow_v1_cropped.png"
                or  "image/btn_raised_v1_cropped.png",
            backgroundFit   = "fill",
            backgroundSlice = { 6, 6, 6, 6 },
            paddingTop      = 10,
            paddingBottom   = 10,
            onClick         = t.onClick,
            children = {
                UI.Label {
                    text       = t.label,
                    fontSize   = 18,
                    fontColor  = { 255, 255, 255, 255 },
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
        tabItems[#tabItems + 1] = btn
        navTabs_[t.id] = btn
    end

    return UI.Panel {
        position      = "absolute",
        bottom        = 30, left = 0, right = 0,
        height        = 80,
        flexDirection = "row",
        alignItems    = "center",
        children      = tabItems,
    }
end

-- ---------------------------------------------------------------
-- 独立关卡选择覆盖层
-- ---------------------------------------------------------------
local function buildLevelSelect()
    local unlocked = SaveManager.GetUnlocked()
    local levelButtons = {}
    levelSelBtns_ = {}

    for i = 1, Levels.Count() do
        local idx      = i
        local isLocked  = (i > unlocked)
        local isCleared = SaveManager.IsCleared(i)
        local bgSrc = (not isLocked and isCleared)
            and "Textures/UI/cell_cleared.png"
            or  "Textures/UI/cell_locked.png"

        local btn = UI.Panel {
            id             = "menuLvlBtn_" .. i,
            width          = 56, height = 56,
            alignItems     = "center",
            justifyContent = "center",
            borderRadius   = 10,
            overflow       = "hidden",
            backgroundImage    = bgSrc,
            backgroundFit   = "cover",
            opacity        = isLocked and 0.55 or 1.0,
            children = {
                UI.Label {
                    text      = isLocked and "🔒" or tostring(i),
                    fontSize  = isLocked and 16 or 17,
                    fontColor = isLocked
                        and { 200, 200, 210, 230 }
                        or  (isCleared and { 255, 255, 200, 255 } or { 220, 235, 255, 255 }),
                },
            },
            onClick = isLocked and nil or function()
                SoundManager.Play("btn_click")
                MainMenu.HideLevelSelect()
                if onSelectLevelStart_ then onSelectLevelStart_(idx) end
            end,
        }
        levelButtons[#levelButtons + 1] = btn
        levelSelBtns_[i] = btn
    end

    return UI.Panel {
        id = "menuLevelSelPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        alignItems     = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 180 },
        visible = false,
        children = {
            UI.Panel {
                width = 340,
                maxHeight = 540,
                paddingTop = 20, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 22, 28, 46, 252 },
                borderRadius = 18,
                borderWidth  = 1,
                borderColor  = { 80, 100, 180, 100 },
                alignItems   = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text      = "选择关卡",
                        fontSize  = 20,
                        fontColor = { 180, 200, 255, 255 },
                        fontWeight = "bold",
                    },
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
                        text    = "关闭",
                        variant = "secondary",
                        width   = 100, height = 36,
                        fontSize = 13,
                        onClick = function()
                            MainMenu.HideLevelSelect()
                        end,
                    },
                },
            },
        },
    }
end

function MainMenu.ShowLevelSelect()
    if levelSelPanel_ then levelSelPanel_:SetVisible(true) end
end

function MainMenu.HideLevelSelect()
    if levelSelPanel_ then levelSelPanel_:SetVisible(false) end
end

-- ---------------------------------------------------------------
-- 屏幕分辨率变化时重建界面（全局函数，供引擎事件系统回调）
-- ---------------------------------------------------------------
function MainMenuHandleScreenMode()
    if not isShowing_ or not cachedCallbacks_ then return end
    -- 过渡动画期间不重建（避免打断圆形擦除 + 重复触发 Logo 动画）
    if UIAnim.IsTransitioning() then return end
    -- Logo 入场动画进行中不重建（避免节点被销毁导致动画中断/重复）
    if logoNode_ and UIAnim.IsAnimating(logoNode_) then return end
    -- 保留当前 tab 状态
    local prevTab = navActiveTab_
    MainMenu.Show(cachedCallbacks_, { skipLogoAnim = true })
    -- 恢复到变化前的 tab
    if prevTab ~= "home" then
        switchTab(prevTab)
    end
end

-- ---------------------------------------------------------------
-- 初始化 / 显示 / 隐藏
-- ---------------------------------------------------------------
function MainMenu.Show(callbacks, opts)
    -- 缓存回调，供分辨率变化后重建使用
    if callbacks then cachedCallbacks_ = callbacks end
    opts = opts or {}
    isShowing_ = true
    SubscribeToEvent("ScreenMode", "MainMenuHandleScreenMode")

    onPlay_               = cachedCallbacks_ and cachedCallbacks_.onPlay
    onSelectLevel_        = cachedCallbacks_ and cachedCallbacks_.onSelectLevel
    onSelectLevelStart_   = cachedCallbacks_ and cachedCallbacks_.onSelectLevelStart
    onBag_                = cachedCallbacks_ and cachedCallbacks_.onBag

    local playerPanel         = buildPlayerPanel()
    fetchNickname()
    local coinPanel           = buildCoinPanel()
    local logo                = buildLogo()
    local streakBar           = buildStreakBar()
    local buttons             = buildButtons()
    local leftSide, rightSide = buildSideButtons()
    local navBar              = buildNavBar()
    local levelSel            = buildLevelSelect()
    local checkInDlg          = buildCheckInDialog()

    local scrollContent = UI.Panel {
        width = "100%",
        minHeight     = "100%",
        paddingTop    = 76,
        paddingBottom = 160,
        gap = 14,
        alignItems = "center",
        children = {
            logo,
            UI.Panel { flexGrow = 1 },  -- 弹性空白，把下方内容推向底部
            streakBar,
            buttons,
            UI.Panel { height = 4 },
        },
    }

    local scrollView = UI.ScrollView {
        id = "homeScrollView",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        scrollY       = true,
        scrollX       = false,
        showScrollbar = false,
        children = { scrollContent },
    }

    local taskPanel = buildTaskPanel()
    local bagPanel  = buildBagPanel()

    -- 背景图层：保持原始宽高比，cover 模式自适应屏幕
    local bgImage = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = "Textures/UI/bg_main_menu.png",
        backgroundFit   = "cover",
    }

    root_ = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 6, 10, 22, 255 },   -- 兜底色（图片未加载时）
        children = {
            bgImage,        -- 最底层
            scrollView,
            taskPanel,      -- 任务面板（覆盖在 scrollView 之上）
            bagPanel,       -- 背包面板（覆盖在 scrollView 之上）
            playerPanel,    -- 左上角玩家信息
            coinPanel,      -- 右上角金币
            leftSide,
            rightSide,
            navBar,
            levelSel,       -- 关卡选择覆盖层
            checkInDlg,     -- 签到弹窗（覆盖在最顶层）
        },
    }

    -- 缓存节点引用
    levelSelPanel_  = root_:FindById("menuLevelSelPanel")
    coinLabel_      = root_:FindById("topBarCoinLabel")
    coinIconPanel_  = root_:FindById("topBarCoinIcon")
    checkInDialog_  = root_:FindById("checkInDialog")
    checkInCard_    = root_:FindById("checkInCard")
    sideSignPanel_  = root_:FindById("sideSignPanel")
    taskPanel_      = root_:FindById("taskPanel")
    homeScrollView_ = root_:FindById("homeScrollView")
    bagPanel_       = root_:FindById("bagPanel")
    logoNode_       = root_:FindById("mainLogo")
    -- 预设 Logo 初始状态：如果需要播放入场动画则放大+透明，否则直接正常显示
    local skipLogoAnim = opts.skipLogoAnim
    if logoNode_ and not skipLogoAnim then
        logoNode_:SetStyle({ opacity = 0, scale = 1.6 })
    end
    -- 缓存任务面板内部节点
    taskUndoLabel_     = root_:FindById("taskUndoLabel")
    taskHubLabel_      = root_:FindById("taskHubLabel")
    taskUndoBar_       = root_:FindById("taskUndoBar")
    taskHubBar_        = root_:FindById("taskHubBar")
    taskUndoClaimBtn_  = root_:FindById("taskUndoClaimBtn")
    taskHubClaimBtn_   = root_:FindById("taskHubClaimBtn")
    taskUndoCard_      = root_:FindById("taskUndoCard")
    taskHubCard_       = root_:FindById("taskHubCard")
    -- 缓存背包面板内部节点
    bagUndoCountLabel_ = root_:FindById("bagUndoCount")
    bagHubCountLabel_  = root_:FindById("bagHubCount")

    UI.SetRoot(root_)

    -- Logo 入场动画（仅非静默刷新时播放）
    if logoNode_ and not skipLogoAnim then
        UIAnim.LogoEntrance(logoNode_)
    end

    --print("[MainMenu] 主界面已显示")
end

function MainMenu.Hide()
    isShowing_          = false
    cachedCallbacks_    = nil
    UnsubscribeFromEvent("ScreenMode")
    -- 取消 Logo 上残留的循环动画
    if logoNode_ then UIAnim.CancelAll(logoNode_) end
    root_               = nil
    logoNode_           = nil
    coinLabel_          = nil
    coinIconPanel_      = nil
    checkInDialog_      = nil
    checkInCard_        = nil
    checkInBtn_         = nil
    checkInRewardPanel_ = nil
    sideSignBtn_        = nil
    sideSignPanel_      = nil
    taskPanel_          = nil
    homeScrollView_     = nil
    bagPanel_           = nil
    bagUndoCountLabel_  = nil
    bagHubCountLabel_   = nil
    taskUndoLabel_      = nil
    taskHubLabel_       = nil
    taskUndoBar_        = nil
    taskHubBar_         = nil
    taskUndoClaimBtn_   = nil
    taskHubClaimBtn_    = nil
    taskUndoCard_       = nil
    taskHubCard_        = nil
    navActiveTab_       = "home"
    navTabs_            = {}
    --print("[MainMenu] 主界面已隐藏")
end

-- ---------------------------------------------------------------
-- 刷新任务面板进度和按钮状态
-- ---------------------------------------------------------------
function MainMenu.RefreshTaskPanel()
    local undoProg, undoTotal = SaveManager.GetTaskUndoProgress()
    local hubProg,  hubTotal  = SaveManager.GetTaskHubProgress()
    local undoClaimable = SaveManager.GetTaskUndoClaimable()
    local hubClaimable  = SaveManager.GetTaskHubClaimable()

    -- 进度文字
    if taskUndoLabel_ then
        taskUndoLabel_:SetText(string.format("进度：%d / %d 关", undoProg, undoTotal))
    end
    if taskHubLabel_ then
        taskHubLabel_:SetText(string.format("进度：%d / %d 关", hubProg, hubTotal))
    end

    -- 进度条宽度
    if taskUndoBar_ then
        local pct = (undoTotal > 0) and math.floor(undoProg / undoTotal * 100) or 0
        taskUndoBar_:SetStyle({ width = pct .. "%" })
    end
    if taskHubBar_ then
        local pct = (hubTotal > 0) and math.floor(hubProg / hubTotal * 100) or 0
        taskHubBar_:SetStyle({ width = pct .. "%" })
    end

    -- 撤回领取按钮
    if taskUndoClaimBtn_ then
        local canClaim = undoClaimable > 0
        taskUndoClaimBtn_:SetText(canClaim and "领取" or "进行中")
        taskUndoClaimBtn_:SetStyle({ opacity = canClaim and 1.0 or 0.5 })
        taskUndoClaimBtn_:SetDisabled(not canClaim)
        taskUndoClaimBtn_.props.onClick = canClaim and function(self)
            SoundManager.Play("task_claim")
            SaveManager.ClaimTaskUndo()
            -- 飞行动画：图标飞向背包 Tab
            local btnOk, btnLayout = pcall(function() return self:GetAbsoluteLayoutForHitTest() end)
            local dstX, dstY = getBagTabPosition()
            if btnOk and btnLayout and dstX then
                local sx = btnLayout.x + btnLayout.w * 0.5
                local sy = btnLayout.y + btnLayout.h * 0.5
                playItemFly("Textures/UI/icon_undo.png", sx, sy, dstX, dstY, function()
                    MainMenu.RefreshBagPanel()
                end)
            end
            -- 卡片刷新特效
            playCardFlash(taskUndoCard_)
            MainMenu.RefreshTaskPanel()
        end or nil
    end

    -- 插板领取按钮
    if taskHubClaimBtn_ then
        local canClaim = hubClaimable > 0
        taskHubClaimBtn_:SetText(canClaim and "领取" or "进行中")
        taskHubClaimBtn_:SetStyle({ opacity = canClaim and 1.0 or 0.5 })
        taskHubClaimBtn_:SetDisabled(not canClaim)
        taskHubClaimBtn_.props.onClick = canClaim and function(self)
            SoundManager.Play("task_claim")
            SaveManager.ClaimTaskHub()
            -- 飞行动画：图标飞向背包 Tab
            local btnOk, btnLayout = pcall(function() return self:GetAbsoluteLayoutForHitTest() end)
            local dstX, dstY = getBagTabPosition()
            if btnOk and btnLayout and dstX then
                local sx = btnLayout.x + btnLayout.w * 0.5
                local sy = btnLayout.y + btnLayout.h * 0.5
                playItemFly("image/hub_single_slot_20260526063407.png", sx, sy, dstX, dstY, function()
                    MainMenu.RefreshBagPanel()
                end)
            end
            -- 卡片刷新特效
            playCardFlash(taskHubCard_)
            MainMenu.RefreshTaskPanel()
        end or nil
    end
end

-- ---------------------------------------------------------------
-- 刷新背包面板道具数量
-- ---------------------------------------------------------------
function MainMenu.RefreshBagPanel()
    local undoCount = SaveManager.GetUndoCount()
    local hubCount  = SaveManager.GetTempHubCount()
    -- 数量 > 0 黄色，= 0 蓝色
    local colorHas  = { 255, 180, 60, 255 }
    local colorNone = { 100, 160, 255, 255 }
    if bagUndoCountLabel_ then
        bagUndoCountLabel_:SetText(tostring(undoCount))
        bagUndoCountLabel_:SetStyle({ fontColor = (undoCount > 0) and colorHas or colorNone })
    end
    if bagHubCountLabel_ then
        bagHubCountLabel_:SetText(tostring(hubCount))
        bagHubCountLabel_:SetStyle({ fontColor = (hubCount > 0) and colorHas or colorNone })
    end
end

-- ---------------------------------------------------------------
-- 刷新顶栏金币数字（飞金币演出结束后调用）
-- ---------------------------------------------------------------
function MainMenu.RefreshCoinDisplay()
    if coinLabel_ then
        local coins = SaveManager.GetCoins()
        -- 格式化：千位逗号分隔
        local s = tostring(coins)
        local result = ""
        local len = #s
        for i = 1, len do
            if i > 1 and (len - i + 1) % 3 == 0 then
                result = result .. ","
            end
            result = result .. s:sub(i, i)
        end
        coinLabel_:SetText(result)
    end
    --print(string.format("[MainMenu] 金币数字刷新：%d", SaveManager.GetCoins()))
end

-- ---------------------------------------------------------------
-- 返回顶栏金币图标的屏幕中心坐标（供飞金币演出定位目标）
-- 若 UI 未就绪返回 nil, nil
-- ---------------------------------------------------------------
function MainMenu.GetCoinUIPosition()
    if not coinIconPanel_ then return nil, nil end
    local ok, layout = pcall(function()
        return coinIconPanel_:GetAbsoluteLayoutForHitTest()
    end)
    if not ok or not layout then return nil, nil end
    local cx = layout.x + layout.w * 0.5
    local cy = layout.y + layout.h * 0.5
    return cx, cy
end

-- ---------------------------------------------------------------
-- 每帧更新（由 main.lua HandleUpdate 调用）
-- ---------------------------------------------------------------
function MainMenu.Update(dt)
    updateFlyParticles(dt)
end

return MainMenu
