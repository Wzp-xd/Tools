-- renderer.lua
-- NanoVG 绘制：齿轮、插板、场景、动画

local GameState    = require("game_state")
local SoundManager = require("sound_manager")

local Renderer = {}

-- ---------------------------------------------------------------
-- 颜色定义（RGB）
-- ---------------------------------------------------------------
local COLORS = {
    -- 基础 10 色
    red    = { 220, 60,  60  },
    blue   = { 60,  120, 220 },
    green  = { 50,  180, 80  },
    yellow = { 220, 190, 40  },
    purple = { 150, 60,  210 },
    orange = { 220, 130, 40  },
    cyan   = { 40,  200, 210 },
    pink   = { 230, 80,  160 },
    lime   = { 140, 210, 40  },
    brown  = { 160, 100, 50  },
    -- 扩展 12 色（高难度关卡专用）
    maroon  = { 160, 30,  30  },
    navy    = { 20,  40,  160 },
    teal    = { 20,  160, 150 },
    gold    = { 215, 175, 20  },
    violet  = { 200, 70,  230 },
    coral   = { 230, 95,  75  },
    forest  = { 30,  120, 50  },
    rose    = { 230, 125, 165 },
    olive   = { 130, 145, 30  },
    indigo  = { 65,  25,  175 },
    crimson = { 185, 20,  55  },
    azure   = { 20,  135, 215 },
    -- 特殊
    hidden = { 35,  38,  48  },  -- 隐藏齿轮暗色（近黑深蓝灰）
}

-- UI 色调
local BG_COLOR        = { 18,  24,  38  }   -- 深蓝背景
local PEG_COLOR       = { 80,  90,  110 }   -- 插板灰蓝
local PEG_BASE_COLOR  = { 60,  70,  90  }   -- 插板底座
local SLOT_COLOR      = { 30,  38,  55  }   -- 空槽暗格
local SELECT_COLOR    = { 255, 220, 80  }   -- 选中高亮
local HINT_COLOR      = { 80,  200, 140 }   -- 可移动目标提示
local DONE_COLOR      = { 255, 210, 60  }   -- 已完成插板金色


---@type table<string, number>
local gearImgs_       = {}                   -- 各颜色齿轮图片句柄（由 Renderer.Init 加载）
local pegBaseImg_     = nil                  -- 插板底座图片（peg_selected，始终显示）
local hubSingleImg_   = nil                  -- 临时插板图片（正方形单格）
local pegCapImg_      = nil                  -- 插板完成封盖图片（peg_normal，完成时盖下）
local pegBlockerImg_  = nil                  -- 只进不出阻挡钢筋图片（sink peg 齿轮层之上绘制）
local bgImg_           = nil                  -- 游戏内背景图
local pegLockedCapImg_ = nil                 -- 锁定插板盖子图片（锁链+挂锁）
local gearHubCapImg_  = nil                  -- 轴承盖图片（移动完成后覆盖在齿轮中心）


-- ---------------------------------------------------------------
-- 布局参数（自适应，由 RecalcLayout 计算）
-- ---------------------------------------------------------------
local layout_ = {}

-- ---------------------------------------------------------------
-- 布局过渡动画（添加临时插板时的平滑过渡）
-- ---------------------------------------------------------------
local layoutTransition_ = nil
--[[
结构:
layoutTransition_ = {
    progress  = 0,         -- 0→1
    duration  = 0.38,      -- 过渡时长（秒）
    oldPositions = {[i] = {x, bottom}},  -- 旧插板的屏幕位置快照
    newPositions = {[i] = {x, bottom}},  -- 新插板的屏幕位置快照
    oldSizes = {pegW, pegH, gearR, slotH},  -- 旧布局尺寸
    newSizes = {pegW, pegH, gearR, slotH},  -- 新布局尺寸
    flyIn = {              -- 飞入动画参数（仅新增插板时有值）
        pegIdx = N,        -- 新增插板索引
        startX = ...,      -- 道具栏按钮屏幕 X
        startY = ...,      -- 道具栏按钮屏幕 Y
    } or nil,
}
]]

local function easeOutCubic(t)
    return 1 - (1 - t) ^ 3
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function updateLayoutTransition(dt)
    if not layoutTransition_ then return end
    local lt = layoutTransition_
    lt.progress = lt.progress + dt / lt.duration
    if lt.progress >= 1.0 then
        -- 过渡结束，恢复最终尺寸
        layout_.pegW  = lt.newSizes.pegW
        layout_.pegH  = lt.newSizes.pegH
        layout_.gearR = lt.newSizes.gearR
        layout_.slotH = lt.newSizes.slotH
        layoutTransition_ = nil
        return
    end
    local t = easeOutCubic(lt.progress)
    -- 每帧覆写 layout_ 尺寸字段为插值结果
    layout_.pegW  = lerp(lt.oldSizes.pegW, lt.newSizes.pegW, t)
    layout_.pegH  = lerp(lt.oldSizes.pegH, lt.newSizes.pegH, t)
    layout_.gearR = lerp(lt.oldSizes.gearR, lt.newSizes.gearR, t)
    layout_.slotH = lerp(lt.oldSizes.slotH, lt.newSizes.slotH, t)
end

-- 行数阈值：普通插板数超过阈值时切换到多行布局
local TWO_ROW_THRESHOLD   = 5    -- >5 插板 → 两行
local THREE_ROW_THRESHOLD = 16   -- >16 插板 → 三行

function Renderer.RecalcLayout(W, H)
    local BASE_W   = 480
    local scale    = W / BASE_W

    local pegCount = GameState.PegCount()
    local cap      = GameState.GetCapacity()

    local pegGap   = math.floor(10 * scale * 0.9)
    local topPad   = math.floor(100 * scale) + 50
    local botPad   = math.floor(172 * scale) + 30  -- 156px 道具栏 + 16px 缓冲 + 30px 安全区
    local rowGap   = math.floor(24  * scale)   -- 行间垂直间距

    -- ── 分离普通插板和临时插板 ──────────────────────────────────
    local normalIndices = {}   -- 普通(4格)插板的原始下标
    local tempIndices   = {}   -- 临时(1格)插板的原始下标
    for i = 1, pegCount do
        if GameState.IsTempPeg(i) then
            tempIndices[#tempIndices + 1] = i
        else
            normalIndices[#normalIndices + 1] = i
        end
    end
    local normalCount = #normalIndices
    local tempCount   = #tempIndices

    -- ── 确定普通插板行数与每行数量 ──────────────────────────────
    local threeRow = (normalCount > THREE_ROW_THRESHOLD)
    local twoRow   = (not threeRow) and (normalCount > TWO_ROW_THRESHOLD)

    local row1Count, row2Count, row3Count
    if threeRow then
        row1Count = math.ceil(normalCount / 3)
        local rest = normalCount - row1Count
        row2Count  = math.ceil(rest / 2)
        row3Count  = rest - row2Count
    elseif twoRow then
        row1Count  = math.ceil(normalCount / 2)
        row2Count  = normalCount - row1Count
        row3Count  = 0
    else
        row1Count  = normalCount
        row2Count  = 0
        row3Count  = 0
    end

    -- 普通行数
    local normalRowCount = threeRow and 3 or (twoRow and 2 or 1)
    -- 是否有临时插板行
    local hasTempRow = (tempCount > 0)

    -- ── 自适应插板尺寸：同时受宽度和高度约束，保持素材宽高比 ────
    local ASSET_RATIO = 128 / 512   -- 素材宽 / 素材高（128×512 px）
    local maxPerRow   = math.max(row1Count, row2Count, math.max(row3Count, 1))
    -- 也要考虑临时插板行的宽度需求
    if hasTempRow then
        maxPerRow = math.max(maxPerRow, tempCount)
    end
    local marginX     = math.floor(8 * scale)
    local availW      = W - 2 * marginX
    local availH      = H - topPad - botPad

    -- 约束1：水平方向能放下所有插板
    local pegWbyWidth = math.floor((availW - (maxPerRow - 1) * pegGap) / maxPerRow)

    -- 约束2：垂直方向能放下所有行（含行间距）
    --   普通插板行高 = pegH（基于 cap=4）
    --   临时插板行高 = pegH * 0.25
    --   总高度 = pegH * normalRowCount + pegH*0.25 (如有临时行) + rowGap * 行间数
    --   → pegH ≤ (availH - rowGap*总间隔数) / (normalRowCount + 0.25*hasTempRow)
    local totalGaps = normalRowCount - 1 + (hasTempRow and 1 or 0)
    local heightDenom = normalRowCount + (hasTempRow and 0.25 or 0)
    local pegHmax = math.floor((availH - rowGap * totalGaps) / heightDenom)

    -- 由 pegH 上限反推 pegW 上限
    local gearSlotFactor = 0.8
    local pegWbyHeight
    if cap > 0 then
        pegWbyHeight = math.floor((pegHmax - math.floor(10 * scale)) / (gearSlotFactor * cap))
    else
        pegWbyHeight = pegWbyWidth
    end

    -- 约束3：素材宽高比
    local pegWcand = math.min(pegWbyWidth, pegWbyHeight)
    local gearR_c  = pegWcand * 0.43
    local pegH_c   = math.floor(pegWcand * 0.8) * cap + math.floor(10 * scale)
    local pegWbyAspect = math.floor(pegH_c * ASSET_RATIO)
    local pegW = math.min(pegWcand, pegWbyAspect)
    pegW       = math.max(pegW, math.floor(20 * scale))   -- 最小宽度保底

    local gearRBase = math.max(math.floor(pegW * 0.43), math.floor(8 * scale))
    local slotH = math.floor(pegW * 0.8)
    local pegH  = slotH * cap + math.floor(10 * scale)
    local gearR = math.floor(gearRBase * 1.1)
    local stepX = pegW + pegGap

    -- 临时插板行高度 = 普通行高度的 25%
    local tempRowH = math.floor(pegH * 0.25)

    -- ── 每行横向起始 X（居中）──────────────────────────────────
    local function rowStartX(cnt)
        if cnt <= 0 then cnt = 1 end
        local totalW = cnt * pegW + (cnt - 1) * pegGap
        return math.floor((W - totalW) / 2) + math.floor(pegW / 2)
    end

    -- ── 纵向居中分配所有行（普通行 + 临时行）──────────────────────
    local totalPegH = pegH * normalRowCount + (hasTempRow and tempRowH or 0) + rowGap * totalGaps
    local centerY   = topPad + availH / 2

    -- row1Bottom = 顶行的底部 Y
    local row1Bottom = math.floor(centerY - totalPegH / 2 + pegH)
    local row2Bottom = row1Bottom + pegH + rowGap
    local row3Bottom = row2Bottom + pegH + rowGap

    -- 临时插板行底部 Y（在所有普通行之下）
    local lastNormalBottom
    if threeRow then
        lastNormalBottom = row3Bottom
    elseif twoRow then
        lastNormalBottom = row2Bottom
    else
        lastNormalBottom = row1Bottom
    end
    local tempRowBottom = lastNormalBottom + rowGap + tempRowH

    layout_ = {
        scale      = scale,
        gearR      = gearR,
        pegW       = pegW,
        pegGap     = pegGap,
        slotH      = slotH,
        pegH       = pegH,
        stepX      = stepX,
        twoRow     = twoRow,
        threeRow   = threeRow,
        row1Count  = row1Count,
        row2Count  = row2Count,
        row3Count  = row3Count,
        row1StartX = rowStartX(row1Count),
        row2StartX = rowStartX(row2Count > 0 and row2Count or 1),
        row3StartX = rowStartX(row3Count > 0 and row3Count or 1),
        row1Bottom = row1Bottom,
        row2Bottom = row2Bottom,
        row3Bottom = row3Bottom,
        -- 临时插板行布局
        hasTempRow    = hasTempRow,
        tempCount     = tempCount,
        tempIndices   = tempIndices,
        normalIndices = normalIndices,
        tempRowH      = tempRowH,
        tempRowBottom = tempRowBottom,
        tempRowStartX = rowStartX(tempCount),
        -- 兼容旧代码的单排字段
        startX     = rowStartX(row1Count),
        pegTop     = row1Bottom - pegH,
        pegBottom  = row1Bottom,
        W          = W,
        H          = H,
        topPad     = topPad,
        botPad     = botPad,
    }


end

-- 获取第 i 根插板所在行及该行内列号（从1开始）
-- 返回: row (1/2/3 普通行, "temp" 临时行), col
local function pegRowCol(i)
    -- 检查是否为临时插板
    if GameState.IsTempPeg(i) then
        -- 在临时插板行中的列号
        local col = 1
        if layout_.tempIndices then
            for k, idx in ipairs(layout_.tempIndices) do
                if idx == i then col = k; break end
            end
        end
        return "temp", col
    end

    -- 普通插板：找到在 normalIndices 中的顺序位置
    local normalPos = i   -- 默认（向后兼容）
    if layout_.normalIndices then
        for k, idx in ipairs(layout_.normalIndices) do
            if idx == i then normalPos = k; break end
        end
    end

    if layout_.threeRow then
        if normalPos <= layout_.row1Count then
            return 1, normalPos
        elseif normalPos <= layout_.row1Count + layout_.row2Count then
            return 2, normalPos - layout_.row1Count
        else
            return 3, normalPos - layout_.row1Count - layout_.row2Count
        end
    elseif layout_.twoRow then
        if normalPos <= layout_.row1Count then
            return 1, normalPos
        else
            return 2, normalPos - layout_.row1Count
        end
    else
        return 1, normalPos
    end
end

-- 获取第 i 根插板中心 X（过渡期间返回插值位置）
local function pegX(i)
    if layoutTransition_ and layoutTransition_.newPositions then
        local lt = layoutTransition_
        local newPos = lt.newPositions[i]
        if newPos then
            local t = easeOutCubic(lt.progress)
            -- 飞入的新插板：从道具栏位置出发
            if lt.flyIn and i == lt.flyIn.pegIdx and not lt.oldPositions[i] then
                return lerp(lt.flyIn.startX, newPos.x, t)
            end
            local oldX = lt.oldPositions[i] and lt.oldPositions[i].x or newPos.x
            return lerp(oldX, newPos.x, t)
        end
    end
    local row, col = pegRowCol(i)
    local startX
    if     row == "temp" then startX = layout_.tempRowStartX
    elseif row == 1 then startX = layout_.row1StartX
    elseif row == 2 then startX = layout_.row2StartX
    else                 startX = layout_.row3StartX end
    return startX + (col - 1) * layout_.stepX
end

-- 获取第 i 根插板的底部 Y（过渡期间返回插值位置）
local function pegBottom(i)
    if layoutTransition_ and layoutTransition_.newPositions then
        local lt = layoutTransition_
        local newPos = lt.newPositions[i]
        if newPos then
            local t = easeOutCubic(lt.progress)
            -- 飞入的新插板：从道具栏位置出发
            if lt.flyIn and i == lt.flyIn.pegIdx and not lt.oldPositions[i] then
                return lerp(lt.flyIn.startY, newPos.bottom, t)
            end
            local oldBot = lt.oldPositions[i] and lt.oldPositions[i].bottom or newPos.bottom
            return lerp(oldBot, newPos.bottom, t)
        end
    end
    local row = pegRowCol(i)
    if     row == "temp" then return layout_.tempRowBottom
    elseif row == 1 then return layout_.row1Bottom
    elseif row == 2 then return layout_.row2Bottom
    else                 return layout_.row3Bottom end
end

-- 获取第 i 根插板的顶部 Y
local function pegTop(i)
    if GameState.IsTempPeg(i) then
        return pegBottom(i) - (layout_.tempRowH or layout_.pegH)
    end
    return pegBottom(i) - layout_.pegH
end

-- 获取第 i 根插板第 slot 格的中心 Y（slot=1 是底部）
local function slotY(slot, pegIdx)
    local bot = pegIdx and pegBottom(pegIdx) or layout_.pegBottom
    -- 临时插板只有1格，居中于 tempRowH 高度内
    if pegIdx and GameState.IsTempPeg(pegIdx) then
        local h = layout_.tempRowH or layout_.pegH
        return bot - h / 2
    end
    return bot - (slot - 1) * layout_.slotH - layout_.slotH / 2
end

-- 获取过渡期间插板的透明度（飞入的新插板渐显，其余为 1.0）
local function getTransitionAlpha(i)
    if layoutTransition_ and layoutTransition_.newPositions
       and layoutTransition_.flyIn and i == layoutTransition_.flyIn.pegIdx
       and not layoutTransition_.oldPositions[i] then
        return easeOutCubic(layoutTransition_.progress)
    end
    return 1.0
end

-- ---------------------------------------------------------------
-- 布局过渡 API
-- ---------------------------------------------------------------

--- 开始布局过渡：在改变 GameState（增加插板）之前调用，快照当前布局位置
---@param opts {duration?: number, flyIn?: {pegIdx: number, startX: number, startY: number}}
function Renderer.BeginLayoutTransition(opts)
    opts = opts or {}
    local pegCount = GameState.PegCount()
    local oldPositions = {}
    for i = 1, pegCount do
        oldPositions[i] = { x = pegX(i), bottom = pegBottom(i) }
    end
    local oldSizes = {
        pegW  = layout_.pegW,
        pegH  = layout_.pegH,
        gearR = layout_.gearR,
        slotH = layout_.slotH,
    }
    layoutTransition_ = {
        progress     = 0,
        duration     = opts.duration or 0.38,
        oldPositions = oldPositions,
        newPositions = nil,  -- CommitLayoutTransition 填充
        oldSizes     = oldSizes,
        newSizes     = nil,  -- CommitLayoutTransition 填充
        flyIn        = opts.flyIn or nil,
    }
end

--- 提交布局过渡：在 RecalcLayout 之后调用，快照新布局位置并启动动画
function Renderer.CommitLayoutTransition()
    if not layoutTransition_ then return end
    local lt = layoutTransition_
    local pegCount = GameState.PegCount()
    local newPositions = {}
    -- 此时 layoutTransition_.newPositions 为 nil，pegX/pegBottom 会走正常计算路径
    for i = 1, pegCount do
        newPositions[i] = { x = pegX(i), bottom = pegBottom(i) }
    end
    lt.newPositions = newPositions
    lt.newSizes = {
        pegW  = layout_.pegW,
        pegH  = layout_.pegH,
        gearR = layout_.gearR,
        slotH = layout_.slotH,
    }
end

--- 取消布局过渡（Begin 后发现不需要过渡时调用）
function Renderer.CancelLayoutTransition()
    layoutTransition_ = nil
end

-- 将屏幕坐标转换为插板下标（返回 nil 表示未命中）
-- 获取第 i 根插板的中心坐标（用于教程动画定位）
function Renderer.GetPegCenter(i)
    if not layout_ or not layout_.pegH then return 0, 0 end
    local cx  = pegX(i)
    local top = pegTop(i)
    local bot = pegBottom(i)
    return cx, (top + bot) / 2
end

function Renderer.HitTestPeg(px, py)
    for i = 1, GameState.PegCount() do
        local cx   = pegX(i)
        local top  = pegTop(i)
        local bot  = pegBottom(i)
        local halfW = layout_.pegW / 2 + 6
        if px >= cx - halfW and px <= cx + halfW
           and py >= top - 20
           and py <= bot + 20 then
            return i
        end
    end
    return nil
end

-- ---------------------------------------------------------------
-- 核心：drawGear
-- ---------------------------------------------------------------
-- 参数：
--   ctx      NanoVG context
--   cx, cy   齿轮中心
--   r        外圆（齿顶）半径
--   color    颜色名字符串（"red","blue"...）
--   angle    旋转角（弧度）
--   selected 是否选中
--   alpha    透明度 0-255

-- ---------------------------------------------------------------
-- drawGear：使用白色基础图片 + Multiply 叠色实现着色
-- ---------------------------------------------------------------
-- 叠色原理：
--   1. 先用 nvgImagePattern 绘制白色齿轮（含高光/阴影质感）
--   2. 再用 NVG_MULTIPLY 混合模式叠加颜色矩形
--      白色区域 × 颜色 = 颜色；暗色区域 × 颜色 = 保持暗
--   3. 图片未加载时回退到纯 NanoVG 程序化绘制
-- ---------------------------------------------------------------

-- 回退用路径构建（图片未加载时使用）
local function buildGearPath(ctx, rInner, rOuter, nTeeth, toothHalf, gapHalf)
    local first = true
    for k = 0, nTeeth - 1 do
        local base = k * 2 * math.pi / nTeeth
        local pts = {
            { rInner, base - gapHalf   },
            { rOuter, base - toothHalf },
            { rOuter, base + toothHalf },
            { rInner, base + gapHalf   },
        }
        for _, p in ipairs(pts) do
            local x = p[1] * math.cos(p[2])
            local y = p[1] * math.sin(p[2])
            if first then
                nvgMoveTo(ctx, x, y)
                first = false
            else
                nvgLineTo(ctx, x, y)
            end
        end
    end
    nvgClosePath(ctx)
end

local function drawGear(ctx, cx, cy, r, color, selected, alpha)
    alpha = alpha or 255
    local img = gearImgs_[color] or gearImgs_["hidden"]
    if not img then return end

    local d = r * 2
    local paint = nvgImagePattern(ctx, cx - r, cy - r, d, d, 0, img, alpha / 255.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, cx - r, cy - r, d, d)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
end

-- ---------------------------------------------------------------
-- Renderer.Init：加载齿轮图片资源（在 NanoVG context 创建后调用）
-- ---------------------------------------------------------------
function Renderer.Init(ctx)
    -- 加载兵符图片（韩信点兵主题 - 方形令牌兵符）
    local GEAR_IMAGE_PATHS = {
        red     = "image/tally_red_20260601100300.png",
        blue    = "image/tally_blue_20260601100123.png",
        green   = "image/tally_green_20260601100132.png",
        yellow  = "image/tally_gold_20260601100122.png",
        purple  = "image/tally_purple_20260601100134.png",
        orange  = "image/tally_orange_20260601100126.png",
        cyan    = "image/tally_cyan_20260601100131.png",
        pink    = "image/tally_rose_20260601100350.png",
        lime    = "image/tally_cyan_20260601100131.png",
        brown   = "image/tally_dark_20260601100121.png",
        maroon  = "image/tally_dark_20260601100121.png",
        navy    = "image/tally_dark_20260601100121.png",
        teal    = "image/tally_teal_20260601100128.png",
        gold    = "image/tally_gold_20260601100122.png",
        violet  = "image/tally_purple_20260601100134.png",
        coral   = "image/tally_rose_20260601100350.png",
        forest  = "image/tally_green_20260601100132.png",
        rose    = "image/tally_rose_20260601100350.png",
        olive   = "image/tally_teal_20260601100128.png",
        indigo  = "image/tally_blue_20260601100123.png",
        crimson = "image/tally_red_20260601100300.png",
        azure   = "image/tally_blue_20260601100123.png",
        hidden  = "image/tally_hidden_20260601100525.png",
    }
    for color, path in pairs(GEAR_IMAGE_PATHS) do
        local h = nvgCreateImage(ctx, path, 0)
        if h and h >= 0 then
            gearImgs_[color] = h
            print("[Renderer] 齿轮图片加载成功 color=" .. color .. " handle=" .. h)
        else
            print("[Renderer] 齿轮图片加载失败 color=" .. color .. " path=" .. path)
        end
    end

    pegBaseImg_ = nvgCreateImage(ctx, "image/wood_box_base_20260601101000.png", 0)
    if pegBaseImg_ and pegBaseImg_ >= 0 then
        print("[Renderer] 木盒底座图片加载成功 handle=" .. pegBaseImg_)
    else
        pegBaseImg_ = nil
        print("[Renderer] 木盒底座图片加载失败，回退到程序化绘制")
    end

    hubSingleImg_ = nvgCreateImage(ctx, "image/wood_box_single_20260601100959.png", 0)
    if hubSingleImg_ and hubSingleImg_ >= 0 then
        print("[Renderer] 单槽木盒图片加载成功 handle=" .. hubSingleImg_)
    else
        hubSingleImg_ = nil
        print("[Renderer] 单槽木盒图片加载失败，回退到程序化绘制")
    end

    pegCapImg_ = nvgCreateImage(ctx, "image/wood_box_cap_20260601105656.png", 0)
    if pegCapImg_ and pegCapImg_ >= 0 then
        print("[Renderer] 木盒封盖图片加载成功 handle=" .. pegCapImg_)
    else
        pegCapImg_ = nil
        print("[Renderer] 木盒封盖图片加载失败")
    end

    pegBlockerImg_ = nvgCreateImage(ctx, "image/wood_box_blocker_20260601101002.png", 0)
    if pegBlockerImg_ and pegBlockerImg_ >= 0 then
        print("[Renderer] 木质挡板图片加载成功 handle=" .. pegBlockerImg_)
    else
        pegBlockerImg_ = nil
        print("[Renderer] 木质挡板图片加载失败，只进不出队列无阻挡覆盖")
    end

    pegLockedCapImg_ = nvgCreateImage(ctx, "image/wood_box_locked_20260601105657.png", 0)
    if pegLockedCapImg_ and pegLockedCapImg_ >= 0 then
        print("[Renderer] 锁定木盒图片加载成功 handle=" .. pegLockedCapImg_)
    else
        pegLockedCapImg_ = nil
        print("[Renderer] 锁定木盒图片加载失败，回退到程序化绘制")
    end

    gearHubCapImg_ = nvgCreateImage(ctx, "image/soldier_emblem_20260601090712.png", 0)
    if gearHubCapImg_ and gearHubCapImg_ >= 0 then
        print("[Renderer] 士兵军徽图片加载成功 handle=" .. gearHubCapImg_)
    else
        gearHubCapImg_ = nil
        print("[Renderer] 士兵军徽图片加载失败")
    end

    bgImg_ = nvgCreateImage(ctx, "image/bg_game_camp_20260601090944.png", 0)
    if bgImg_ and bgImg_ >= 0 then
        print("[Renderer] 游戏背景图加载成功 handle=" .. bgImg_)
    else
        bgImg_ = nil
        print("[Renderer] 游戏背景图加载失败，回退到渐变背景")
    end
end

-- ---------------------------------------------------------------
-- 插板状态辅助
-- ---------------------------------------------------------------

-- 解析显示颜色：
--   普通齿轮 → 原样返回
--   隐藏齿轮 + isVisible=true（顶部/手中）→ 真实颜色
--   隐藏齿轮 + isVisible=false（非顶）→ "hidden"（暗色）
local function resolveColor(rawColor, isVisible)
    if GameState.IsHiddenGear(rawColor) then
        if isVisible then
            return GameState.ActualColor(rawColor)
        else
            return "hidden"
        end
    end
    return rawColor
end

-- 判断插板是否全部同色（不要求插满，按实际颜色比较）
local function isAllSameColor(pegIdx)
    local peg = GameState.GetPegs()[pegIdx]
    if #peg == 0 then return false, nil end
    local c = GameState.ActualColor(peg[1])
    for _, g in ipairs(peg) do
        if GameState.ActualColor(g) ~= c then return false, nil end
    end
    return true, c   -- 返回实际颜色名（不含 hidden_ 前缀）
end




-- ---------------------------------------------------------------
-- 前向声明（被 drawLockedPeg 使用，在文件后面定义）
-- ---------------------------------------------------------------
---@type table
local unlockAnims_ = {}   -- 解锁演出状态（后面动画区也赋值到同一 local）
-- easeOutCubic 已在文件顶部定义（layoutTransition 区域）

-- ---------------------------------------------------------------
-- 辅助：绘制插板图片底座（居中于 cx，对齐 top/bot）
-- ---------------------------------------------------------------
local function drawPegBaseImage(ctx, cx, top, bot, pegW, alpha)
    if not pegBaseImg_ then return end
    -- 按素材宽高比（128:512）以插板高度为基准，避免细长变形
    local ASSET_RATIO = 128 / 512
    local imgH = (bot - top) * 1.05 * 0.9   -- 略高，让顶底螺丝不被裁切；0.9 控制视觉大小
    local imgW = imgH * ASSET_RATIO
    local imgX = cx - imgW / 2
    local imgY = top - (imgH - (bot - top)) * 0.5
    local paint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, pegBaseImg_, alpha / 255.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, imgX, imgY, imgW, imgH)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
end
-- 辅助：绘制临时插板正方形图片（以 cx/slotCY 为中心，边长 = pegW * 1.15）
local function drawTempPegImage(ctx, cx, cy, pegW, alpha)
    if not hubSingleImg_ then
        -- 程序化回退：蓝色虚线边框正方形
        local half = pegW * 0.58
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, cx - half, cy - half, half * 2, half * 2, 8)
        nvgStrokeColor(ctx, nvgRGBA(80, 140, 255, alpha))
        nvgStrokeWidth(ctx, 2.0)
        nvgStroke(ctx)
        return
    end
    local size = pegW * 0.805
    local half = size * 0.5
    local paint = nvgImagePattern(ctx, cx - half, cy - half, size, size, 0, hubSingleImg_, alpha / 255.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, cx - half, cy - half, size, size)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
end

local function drawLockedPeg(ctx, i)
    local cx          = pegX(i)
    local top         = pegTop(i)
    local bot         = pegBottom(i)
    local pegW        = layout_.pegW
    local pegH        = bot - top
    local s           = layout_.scale
    local unlockColor = GameState.GetUnlockColor(i)

    -- ── 解锁动画参数（默认静止锁定状态） ────────────────────────
    local ua           = unlockAnims_[i]
    local capScale     = 1.0
    local capAlpha     = 255
    local capShakeX    = 0
    local lightAlpha   = 220   -- 灯块主体 alpha（初始值）

    if ua then
        local p = ua.progress
        local PHASE1_END = 0.3   -- 灯块消失
        local PHASE2_END = 0.6   -- 震动结束
        -- Phase 1：灯块 fade out
        if p <= PHASE1_END then
            local t      = p / PHASE1_END
            lightAlpha   = math.floor(220 * (1 - t))
        else
            lightAlpha   = 0
        end
        -- Phase 2：盖子震动
        if p > PHASE1_END and p <= PHASE2_END then
            capScale  = 1.0
            capAlpha  = 255
            local t2  = (p - PHASE1_END) / (PHASE2_END - PHASE1_END)
            local freq = 5.0
            local damp = 1 - t2
            capShakeX = math.floor(pegW * 0.07 * damp * math.sin(t2 * freq * math.pi * 2))
        end
        -- Phase 3：盖子扩大 + 消散
        if p > PHASE2_END then
            local t3  = (p - PHASE2_END) / (1.0 - PHASE2_END)
            local et  = easeOutCubic(t3)
            capScale  = 1.0 + 0.5 * et      -- 1.0 → 1.5
            capAlpha  = math.floor(255 * (1 - et))
            capShakeX = 0
        end
    end

    -- ── 层级1：底座图片（与普通插板一致） ───────────────────────
    drawPegBaseImage(ctx, cx, top, bot, pegW, 255)

    -- ── 层级2：齿轮（暗化，透明度 90，表示被锁住；整体上移 50% 齿轮高） ──
    -- 用 Scissor 裁剪到插板范围，防止上移后顶部齿轮突出插板顶边
    local peg       = GameState.GetPegs()[i]
    local gearLiftY = layout_.slotH * 0.5   -- 上移 50% 齿轮槽高（= 齿轮直径）
    nvgSave(ctx)
    nvgScissor(ctx, cx - pegW / 2 - 4, top, pegW + 8, pegH)
    for slot = 1, #peg do
        local rawColor     = peg[slot]
        local displayColor = GameState.IsHiddenGear(rawColor) and "hidden" or rawColor
        drawGear(ctx, cx, slotY(slot, i) - gearLiftY, layout_.gearR, displayColor, false, 90)
    end
    nvgRestore(ctx)

    -- 动画完成后不再绘制盖子和灯块
    if ua and ua.done then return end

    -- ── 层级3：锁定盖子图片（锁链+挂锁，覆盖齿轮） ─────────────
    local ASSET_RATIO = 84 / 218   -- 素材实际尺寸 84×218（已裁剪透明边距）
    local imgH = pegH * 1.08 * capScale
    local imgW = imgH * ASSET_RATIO
    local imgX = cx + capShakeX - imgW / 2
    local imgY = (top + bot) * 0.5 - imgH * 0.5

    if capAlpha > 0 then
        if pegLockedCapImg_ then
            local paint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, pegLockedCapImg_, capAlpha / 255.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, imgX, imgY, imgW, imgH)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        else
            -- Fallback：半透明深色遮罩
            local cr = math.floor(8 * s)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, cx + capShakeX - pegW / 2 - 3, top, pegW + 6, pegH, cr)
            nvgFillColor(ctx, nvgRGBA(12, 14, 20, capAlpha))
            nvgFill(ctx)
        end
    end

    -- ── 层级4：解锁颜色预览（盖子中心显示对应颜色的齿轮图片，60% 尺寸） ──
    if unlockColor and lightAlpha > 0 then
        local img = gearImgs_[unlockColor] or gearImgs_["hidden"]
        if img then
            local gearR   = layout_.gearR
            local previewR = gearR * 0.6
            local d        = previewR * 2
            local previewCY = (top + bot) * 0.5 - pegH * 0.18
            local px       = cx - previewR
            local py       = previewCY - previewR
            local a        = lightAlpha / 255.0
            local paint    = nvgImagePattern(ctx, px, py, d, d, 0, img, a)
            nvgBeginPath(ctx)
            nvgRect(ctx, px, py, d, d)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end
    end
end


-- ---------------------------------------------------------------
-- 辅助：左侧颜色灯条（20×100 等比缩放，发光效果）
-- ---------------------------------------------------------------
-- cx, cy：灯条中心坐标；pegH：参考插板高度；progress：0→1 从底向上亮起
local function drawColorLight(ctx, cx, cy, pegH, color, s, progress)
    progress = progress or 1.0
    if progress <= 0 then return end

    local col     = COLORS[color] or { 120, 120, 120 }
    local lightW  = math.max(4, math.floor(6  * s))
    local fullH   = math.max(20, math.floor(pegH * 0.55))   -- 完整高度
    local cr      = lightW / 2

    -- 底部固定，顶部随 progress 向上增长
    local bot     = cy + fullH / 2          -- 底边（固定）
    local lightH  = math.floor(fullH * progress)
    if lightH < 1 then return end
    local lightY  = bot - lightH            -- 顶边（向上移动）
    local lightX  = cx - lightW / 2

    -- 透明度也随进度淡入（60%→100% 区间内做 alpha 渐变）
    local alphaScale = math.min(1.0, progress / 0.6)
    local glowA   = math.floor(100 * alphaScale)
    local bodyA   = math.floor(230 * alphaScale)
    local shineA  = math.floor(160 * alphaScale)
    local borderA = math.floor(200 * alphaScale)

    -- 发光晕（以灯条当前顶端为中心，随亮起逐渐扩散）
    local glowCY  = lightY + lightH * 0.3   -- 偏向顶端
    local glowR   = lightW * 3.5
    local glow    = nvgRadialGradient(ctx,
        cx, glowCY, 0, glowR,
        nvgRGBA(col[1], col[2], col[3], glowA),
        nvgRGBA(col[1], col[2], col[3], 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, cx - glowR, glowCY - glowR, glowR * 2, glowR * 2)
    nvgFillPaint(ctx, glow)
    nvgFill(ctx)

    -- 灯条主体
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, lightX, lightY, lightW, lightH, cr)
    nvgFillColor(ctx, nvgRGBA(col[1], col[2], col[3], bodyA))
    nvgFill(ctx)

    -- 顶部高光（仅在当前已亮区域内）
    local shine = nvgLinearGradient(ctx,
        lightX, lightY, lightX, lightY + lightH * 0.4,
        nvgRGBA(255, 255, 255, shineA), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, lightX, lightY, lightW, lightH, cr)
    nvgFillPaint(ctx, shine)
    nvgFill(ctx)

    -- 边框
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, lightX, lightY, lightW, lightH, cr)
    nvgStrokeColor(ctx, nvgRGBA(
        math.min(255, col[1] + 80),
        math.min(255, col[2] + 80),
        math.min(255, col[3] + 80), borderA))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)
end

-- ---------------------------------------------------------------
-- 绘制插板
-- ---------------------------------------------------------------
local function drawPeg(ctx, i, selectedPeg, validTargets)
    local cx    = pegX(i)
    local top   = pegTop(i)
    local bot   = pegBottom(i)
    local pegW  = layout_.pegW
    local s     = layout_.scale

    -- 飞入过渡透明度（正常为 1.0，飞入中渐显）
    local tAlpha = getTransitionAlpha(i)
    local baseAlpha = math.floor(tAlpha * 255)

    local isCompleted = GameState.IsPegCompleted(i)
    local isSelected  = (selectedPeg == i) and not isCompleted
    local isTempPeg   = GameState.IsTempPeg(i)

    if isTempPeg then
        -- ── 临时插板：正方形图片（限制在 tempRowH 内）───────────────
        local cy = slotY(1, i)   -- 只有1格，取第1槽中心
        local tempH = layout_.tempRowH or layout_.pegH
        local drawW = math.min(pegW, tempH / 0.805)  -- 确保图片高度 ≤ tempRowH
        drawTempPegImage(ctx, cx, cy, drawW, baseAlpha)

        -- 选中高亮边框
        if isSelected then
            local half = drawW * 0.406
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, cx - half - 4, cy - half - 4, half * 2 + 8, half * 2 + 8, 12)
            nvgStrokeColor(ctx, nvgRGBA(SELECT_COLOR[1], SELECT_COLOR[2], SELECT_COLOR[3], 200))
            nvgStrokeWidth(ctx, 2.5)
            nvgStroke(ctx)
        end
    elseif pegBaseImg_ then
        -- ── 图片模式：直接绘制 peg_selected 底座图片 ─────────────────
        drawPegBaseImage(ctx, cx, top, bot, pegW, baseAlpha)

        -- 空槽格（未完成时显示，叠在图片上方）
        if not isCompleted then
            local cap = GameState.GetCapacity()
            for slot = 1, cap do
                local sy = slotY(slot, i)
                nvgBeginPath(ctx)
                nvgCircle(ctx, cx, sy, layout_.gearR * 0.42)
                nvgStrokeColor(ctx, nvgRGBA(40, 55, 80, math.floor(100 * tAlpha)))
                nvgStrokeWidth(ctx, 1.0)
                nvgStroke(ctx)
            end
        end

        -- 选中高亮边框（蓝色描边）
        if isSelected then
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, cx - pegW / 2 - 4, top - 4, pegW + 8, (bot - top) + 8, 10)
            nvgStrokeColor(ctx, nvgRGBA(SELECT_COLOR[1], SELECT_COLOR[2], SELECT_COLOR[3], 200))
            nvgStrokeWidth(ctx, 2.5)
            nvgStroke(ctx)
        end
    else
        -- ── 程序化回退 ───────────────────────────────────────────────
        local barW    = math.floor(10 * s)
        local barColor = isCompleted and DONE_COLOR or PEG_COLOR
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, cx - barW / 2, top, barW, bot - top, barW / 2)
        nvgFillColor(ctx, nvgRGBA(barColor[1], barColor[2], barColor[3], 200))
        nvgFill(ctx)

        local baseW = pegW + math.floor(8 * s)
        local baseH = math.floor(14 * s)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, cx - baseW / 2, bot - baseH, baseW, baseH + math.floor(4 * s), math.floor(5 * s))
        local baseCol = isCompleted and DONE_COLOR or PEG_BASE_COLOR
        nvgFillColor(ctx, nvgRGBA(baseCol[1], baseCol[2], baseCol[3], 230))
        nvgFill(ctx)

        if not isCompleted then
            local cap = GameState.GetCapacity()
            for slot = 1, cap do
                local sy = slotY(slot, i)
                nvgBeginPath(ctx)
                nvgCircle(ctx, cx, sy, layout_.gearR * 0.45)
                nvgStrokeColor(ctx, nvgRGBA(SLOT_COLOR[1], SLOT_COLOR[2], SLOT_COLOR[3], 120))
                nvgStrokeWidth(ctx, 1.0)
                nvgStroke(ctx)
            end
        end
    end

end

-- ---------------------------------------------------------------
-- 动画状态
-- ---------------------------------------------------------------
local time_        = 0

-- 封装演出：[i] { progress, color, done, shakeOffset }
--   phase1 (0→0.7)：图片从 150% 缩放到 100%，透明度 0→255
--   phase2 (0.7→1.0)：盖下后震动（阻尼正弦偏移）
local sealAnims_   = {}
local sealAllowed_ = {}   -- [pegIdx]=true 表示允许启动封盖动画（移动结束后由 TriggerSeal 设置）

-- 解锁演出：[i] { progress, done }（已在文件头部前向声明，此处无需重复 local）
--   phase1 (0→0.3)：灯块透明度 220→0（消失）
--   phase2 (0.3→0.6)：盖子震动（阻尼正弦）
--   phase3 (0.6→1.0)：盖子缩放 1.0→1.5，透明度 255→0（消散）
-- unlockAnims_ 已在前向声明处初始化为 {}

-- easeOutCubic 定义在文件顶部（layoutTransition 区域），此处无需重复定义

-- 绘制单个插板的封盖图（pegCapImg_），在阻挡层之上
-- 层级：底座 → 齿轮 → 阻挡 → 盖子 → 灯条
local function drawSealCap(ctx, i)
    local seal = sealAnims_[i]
    if not seal then return end

    local cx    = pegX(i)
    local top   = pegTop(i)
    local bot   = pegBottom(i)
    local pegW  = layout_.pegW
    local pegH  = bot - top
    local s     = layout_.scale

    local PHASE1_END = 0.7
    local p          = seal.progress

    -- ── 阶段判断 ────────────────────────────────────────────────
    local scaleFactor, alpha, shakeX
    if p <= PHASE1_END then
        -- Phase 1：缩放 1.5→1.0，透明度 0→255
        local t   = p / PHASE1_END
        local et  = easeOutCubic(t)
        scaleFactor = 1.5 - 0.5 * et
        alpha       = math.floor(255 * et)
        shakeX      = 0
    else
        -- Phase 2：保持 1.0，震动（阻尼正弦）
        scaleFactor = 1.0
        alpha       = 255
        local t2    = (p - PHASE1_END) / (1.0 - PHASE1_END)
        local freq  = 5.0
        local damp  = 1 - t2
        shakeX      = math.floor(pegW * 0.06 * damp * math.sin(t2 * freq * math.pi * 2))
    end

    -- ── 绘制 pegCapImg_（或程序化 fallback） ────────────────────
    local ASSET_RATIO = 87 / 219   -- 素材实际尺寸 87×219（已裁剪透明边距）
    local imgH = pegH * 1.08 * 0.9 * scaleFactor   -- 0.9 控制视觉大小
    local imgW = imgH * ASSET_RATIO
    local imgX = cx + shakeX - imgW / 2
    local imgY = (top + bot) * 0.5 - imgH / 2

    if pegCapImg_ then
        local paint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, pegCapImg_, alpha / 255.0)
        nvgBeginPath(ctx)
        nvgRect(ctx, imgX, imgY, imgW, imgH)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
    else
        local sealCol = COLORS[seal.color] or { 180, 180, 180 }
        local cr3     = math.floor(8 * s)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, imgX, imgY, imgW, imgH, cr3)
        nvgFillColor(ctx, nvgRGBA(sealCol[1], sealCol[2], sealCol[3], alpha))
        nvgFill(ctx)
    end
end

-- 绘制单个插板的灯条（在盖子层之上，最顶层）
local function drawSealLight(ctx, i)
    local seal = sealAnims_[i]
    if not seal then return end
    if not (seal.done and seal.lightProgress and seal.lightProgress > 0) then return end

    local cx  = pegX(i)
    local top = pegTop(i)
    local bot = pegBottom(i)
    local pegH = bot - top
    local s   = layout_.scale
    local capCY = (top + bot) * 0.5
    drawColorLight(ctx, cx, capCY, pegH, seal.color, s, seal.lightProgress)
end

-- 兼容旧调用（保留名称，内部转发到新函数）
local function drawSealOverlay(ctx, i)
    drawSealCap(ctx, i)
    drawSealLight(ctx, i)
end

-- 提示高亮（闪烁）
local hintPegs_     = nil   -- { from, to } 或 nil
local hintTimer_    = 0
local hintRingImg_  = nil   -- NanoVG 图片句柄（由 main.lua 注入）

function Renderer.SetHint(hint)
    hintPegs_  = hint
    hintTimer_ = 0
    if hint then
        SoundManager.Play("hint_show")
    end
end

function Renderer.ClearHint()
    hintPegs_  = nil
    hintTimer_ = 0
end

function Renderer.GetHint()
    return hintPegs_
end

-- 由 main.lua 在加载图片后调用
function Renderer.SetHintRingImage(imgHandle)
    hintRingImg_ = imgHandle
end

-- 移动动画
local moveAnim_ = nil
-- { fromIdx, toIdx, color, count,
--   startX, startY, endX, endY,
--   progress, duration, onDone }

-- 通关粒子
local particles_   = {}

-- ---------------------------------------------------------------
-- 插板完成特效（灯条满格时触发）
-- pegBurstAnims_[i] = {
--   cx, cy        : 爆炸中心（屏幕坐标，触发时记录）
--   col           : 插板颜色 {r,g,b}
--   flash         : 光爆进度 0→1（0.35s）
--   rings[]       : 扩散光环列表 { progress 0→1, delay, r, g, b }
--   sparks[]      : 向上粒子列表 { x,y,vx,vy,life,r,col }
-- }
-- ---------------------------------------------------------------
local pegBurstAnims_ = {}

-- 触发单个插板完成特效
local function spawnPegBurst(pegIdx, colName)
    SoundManager.Play("peg_burst")
    local cx  = pegX(pegIdx)
    local top = pegTop(pegIdx)
    local bot = pegBottom(pegIdx)
    local cy  = (top + bot) * 0.5
    local col = COLORS[colName] or { 180, 180, 180 }
    local s   = layout_.scale
    local r   = layout_.gearR

    -- 向上粒子：12 个小色块从中心向上扇形喷射
    local sparks = {}
    for k = 1, 14 do
        local spreadAngle = math.pi * 0.7   -- 扇形半角（70°）
        local angle = -math.pi / 2 + (math.random() - 0.5) * 2 * spreadAngle
        local speed = (80 + math.random() * 140) * s
        sparks[k] = {
            x    = cx + (math.random() - 0.5) * r * 0.6,
            y    = cy,
            vx   = math.cos(angle) * speed,
            vy   = math.sin(angle) * speed,
            life = 0.55 + math.random() * 0.25,
            maxLife = 0.8,
            rad  = (2.5 + math.random() * 3.5) * s,
            col  = col,
        }
    end
    -- 额外 4 颗白色高光粒子（提亮感）
    for k = 1, 4 do
        local angle = -math.pi / 2 + (math.random() - 0.5) * math.pi * 0.5
        local speed = (120 + math.random() * 100) * s
        sparks[#sparks + 1] = {
            x    = cx, y = cy,
            vx   = math.cos(angle) * speed,
            vy   = math.sin(angle) * speed,
            life = 0.4 + math.random() * 0.2,
            maxLife = 0.6,
            rad  = (1.5 + math.random() * 2) * s,
            col  = { 255, 255, 255 },
        }
    end

    -- 扩散光环：3 圈，带延迟错开
    local rings = {}
    for k = 1, 3 do
        rings[k] = {
            progress = 0,
            delay    = (k - 1) * 0.08,   -- 每圈错开 80ms
            active   = false,
            col      = col,
        }
    end

    pegBurstAnims_[pegIdx] = {
        cx    = cx,
        cy    = cy,
        col   = col,
        flash = 0,
        rings = rings,
        sparks = sparks,
    }
end

-- ---------------------------------------------------------------
-- 解锁颜色亮相特效（盖子消散后立即触发）
-- unlockRevealAnims_[i] = {
--   cx, cy  : 插板中心
--   col     : 解锁颜色 {r,g,b}
--   flash   : 白色闪光 0→1 (0.30s)
--   bloom   : 颜色光晕 0→1 (0.55s)
--   rings[] : 扩散光环 { progress, delay, active, col }
--   sparks[]: 全向粒子 { x,y,vx,vy,life,maxLife,rad,col }
-- }
-- ---------------------------------------------------------------
local unlockRevealAnims_ = {}

local function spawnUnlockReveal(pegIdx, colName)
    if not colName then return end
    SoundManager.Play("unlock_reveal")
    local cx  = pegX(pegIdx)
    local top = pegTop(pegIdx)
    local bot = pegBottom(pegIdx)
    local cy  = (top + bot) * 0.5
    local col = COLORS[colName] or { 180, 180, 180 }
    local s   = layout_.scale
    local r   = layout_.gearR

    -- 全向散射粒子：16 彩色 + 4 白色高光
    local sparks = {}
    for k = 1, 16 do
        local angle = (k - 1) * (2 * math.pi / 16) + (math.random() - 0.5) * 0.4
        local speed = (65 + math.random() * 125) * s
        sparks[k] = {
            x       = cx + (math.random() - 0.5) * r * 0.5,
            y       = cy + (math.random() - 0.5) * r * 0.5,
            vx      = math.cos(angle) * speed,
            vy      = math.sin(angle) * speed,
            life    = 0.5 + math.random() * 0.3,
            maxLife = 0.8,
            rad     = (2.0 + math.random() * 3.5) * s,
            col     = col,
        }
    end
    for _ = 1, 4 do
        local angle = math.random() * 2 * math.pi
        local speed = (100 + math.random() * 90) * s
        sparks[#sparks + 1] = {
            x = cx, y = cy,
            vx      = math.cos(angle) * speed,
            vy      = math.sin(angle) * speed,
            life    = 0.3 + math.random() * 0.2,
            maxLife = 0.5,
            rad     = (1.5 + math.random() * 2.0) * s,
            col     = { 255, 255, 255 },
        }
    end

    -- 2 圈扩散光环，错开 120ms
    local rings = {}
    for k = 1, 2 do
        rings[k] = {
            progress = 0,
            delay    = (k - 1) * 0.12,
            active   = false,
            col      = col,
        }
    end

    unlockRevealAnims_[pegIdx] = {
        cx = cx, cy = cy, col = col,
        flash = 0, bloom = 0,
        rings = rings, sparks = sparks,
    }
end

-- SpawnParticles(cx, cy)
--   cx,cy : 爆炸中心（屏幕坐标）
function Renderer.SpawnParticles(cx, cy)
    SoundManager.Play("fireworks")
    particles_ = {}

    local s = layout_.scale or 1.0

    -- 收集本关所有插板的实际颜色，作为粒子颜色池
    local colorPool = {}
    local pegs = GameState.GetPegs()
    for _, peg in ipairs(pegs) do
        if #peg > 0 then
            local c = GameState.ActualColor(peg[1])
            if COLORS[c] then
                colorPool[#colorPool + 1] = COLORS[c]
            end
        end
    end
    -- 颜色池为空时回退到默认调色板
    if #colorPool == 0 then
        colorPool = {
            COLORS.red, COLORS.blue, COLORS.green, COLORS.yellow,
            COLORS.purple, COLORS.orange, COLORS.cyan, COLORS.pink,
        }
    end

    print(string.format("[Renderer] SpawnParticles cx=%.0f cy=%.0f scale=%.2f colorPool=%d", cx, cy, s, #colorPool))

    -- 彩色粒子（按关卡颜色散射）
    for _ = 1, 45 do
        local angle = math.random() * math.pi * 2
        local speed = (100 + math.random() * 220) * s
        local col   = colorPool[math.random(1, #colorPool)]
        particles_[#particles_ + 1] = {
            x    = cx, y = cy,
            vx   = math.cos(angle) * speed,
            vy   = math.sin(angle) * speed - 80 * s,
            life = 1.0,
            r    = (4 + math.random() * 7) * s,
            col  = col,
            star = false,
        }
    end
    print(string.format("[Renderer] 粒子生成完毕 count=%d", #particles_))
end

function Renderer.UpdateParticles(dt)
    for i = #particles_, 1, -1 do
        local p = particles_[i]
        p.x    = p.x + p.vx * dt
        p.y    = p.y + p.vy * dt
        p.vy   = p.vy + 300 * dt   -- 重力
        p.life = p.life - dt * 0.45
        if p.life <= 0 then
            table.remove(particles_, i)
        end
    end
end

function Renderer.IsAnimating()
    return moveAnim_ ~= nil
end

-- 所有已完成插板的封盖 + 灯条动画均已结束
function Renderer.AllSealsSettled()
    local pegs = GameState.GetPegs()
    for i = 1, #pegs do
        if GameState.IsPegCompleted(i) then
            local sa = sealAnims_[i]
            if not sa or not sa.done then return false end
            if not sa.lightProgress or sa.lightProgress < 1.0 then return false end
        end
    end
    return true
end

-- 启动移动动画（3段：垂直升起 → 贝塞尔曲线横移 → 垂直落下）
function Renderer.PlayMoveAnim(fromIdx, toIdx, count, onDone)
    local pegs     = GameState.GetPegs()
    -- 动画前 from 插板已经执行过 Move，所以 from 里少了 count 个
    local fromSlot = #pegs[fromIdx] + count   -- 移走前顶部 slot
    local toSlot   = #pegs[toIdx]             -- 移入后顶部 slot

    -- 悬停高度：插板顶部再上方留出一个齿轮半径距离，额外上抬 30 逻辑像素（自适应）
    local extraLift   = math.floor(30 * layout_.scale)
    local liftLeaderY = pegTop(fromIdx) - layout_.gearR * 2.0 - extraLift
    local landLeaderY = pegTop(toIdx)   - layout_.gearR * 2.0 - extraLift

    -- 为每个飞行齿轮记录：起始Y、抬起悬停Y、落点悬停Y、目标Y
    -- k=1 是原始顶部齿轮，k=count 是原始底部齿轮
    -- 目标顺序翻转：原顶部(k=1) → 目标最低槽，原底部(k=count) → 目标最高槽
    -- 所有齿轮汇聚到同一悬停高度（liftLeaderY/landLeaderY），段2贝塞尔一起横移
    local gears = {}
    for k = 1, count do
        gears[k] = {
            startY = slotY(fromSlot - (k - 1), fromIdx),
            -- 所有齿轮升到同一悬停高度后再开始贝塞尔横移
            liftY  = liftLeaderY,
            landY  = landLeaderY,
            endY   = slotY(toSlot - count + k, toIdx),   -- 翻转：k=1→底部 k=count→顶部
            delay  = (k - 1) * 0.08,  -- 每个齿轮错开 80ms 出发（平移延迟，不压缩）
        }
    end

    moveAnim_ = {
        fromIdx   = fromIdx,
        toIdx     = toIdx,
        count     = count,
        startX    = pegX(fromIdx),
        endX      = pegX(toIdx),
        liftLeadY = liftLeaderY,
        landLeadY = landLeaderY,
        gears     = gears,
        progress  = 0,
        duration  = 0.42 + (count - 1) * 0.08,  -- 延长总时长以容纳最后一个齿轮完成
        color     = GameState.TopColor(toIdx),
        onDone    = onDone,
    }
end



local function updateMoveAnim(dt)
    if not moveAnim_ then return end
    moveAnim_.progress = moveAnim_.progress + dt / moveAnim_.duration
    if moveAnim_.progress >= 1.0 then
        moveAnim_.progress = 1.0
        local cb = moveAnim_.onDone
        moveAnim_ = nil
        if cb then cb() end
    end
end

-- 缓动函数（ease-out）
local function easeOut(t)
    return 1 - (1 - t) ^ 3
end

-- ---------------------------------------------------------------
-- Update（每帧调用）


function Renderer.Update(dt, selectedPeg)
    time_ = time_ + dt
    updateLayoutTransition(dt)

    local pegs = GameState.GetPegs()
    -- phase1 (0→0.7)：0.5s 缩放入场；phase2 (0.7→1.0)：0.3s 震动
    local SEAL_DUR = 0.8   -- 封蛖动画总时长（秒）

    for i = 1, #pegs do
        local isCompleted = GameState.IsPegCompleted(i)   -- 插满且全色一致

        if isCompleted then
            -- 触发/推进封盖演出（需等移动动画结束后 TriggerSeal 显式允许）
            if not sealAnims_[i] and sealAllowed_[i] then
                -- 首次进入完成状态：取第一格的实际颜色
                local col = GameState.ActualColor(pegs[i][1])
                sealAnims_[i] = { progress = 0, color = col, done = false }
            end
            local sa2 = sealAnims_[i]
            if sa2 and not sa2.done then
                sa2.progress = sa2.progress + dt / SEAL_DUR
                if sa2.progress >= 1.0 then
                    sa2.progress    = 1.0
                    sa2.done        = true
                    sa2.lightProgress = 0   -- 盖板落定后启动灯条动画
                end
            elseif sa2 and sa2.lightProgress ~= nil and sa2.lightProgress < 1.0 then
                -- 灯条从底部向上亮起，0.5s 完成
                local LIGHT_DUR = 0.5
                local prevLP = sa2.lightProgress
                sa2.lightProgress = math.min(1.0, sa2.lightProgress + dt / LIGHT_DUR)
                -- 灯条首次满格：触发插板完成特效
                if prevLP < 1.0 and sa2.lightProgress >= 1.0 then
                    spawnPegBurst(i, sa2.color)
                end
            end
        else
            -- 如果曾完成后又被撤销，清除封盖演出和许可
            sealAnims_[i]   = nil
            sealAllowed_[i] = nil
        end
    end

    -- 推进提示闪烁计时器
    if hintPegs_ then
        hintTimer_ = hintTimer_ + dt
    end

    -- 推进解锁演出
    local UNLOCK_DUR = 0.9   -- 解锁动画总时长（秒）
    for i = 1, #pegs do
        local ua = unlockAnims_[i]
        if ua and not ua.done then
            ua.progress = ua.progress + dt / UNLOCK_DUR
            if ua.progress >= 1.0 then
                ua.progress = 1.0
                ua.done     = true
                -- 盖子刚消散 → 触发颜色亮相特效
                spawnUnlockReveal(i, GameState.GetUnlockColor(i))
            end
        end
    end

    -- 推进解锁颜色亮相特效
    local REVEAL_FLASH_DUR = 0.30
    local REVEAL_BLOOM_DUR = 0.55
    local REVEAL_RING_DUR  = 0.50
    local REVEAL_GRAVITY   = 180
    for pegIdx, rev in pairs(unlockRevealAnims_) do
        local alive = false

        if rev.flash < 1.0 then
            rev.flash = math.min(1.0, rev.flash + dt / REVEAL_FLASH_DUR)
            alive = true
        end
        if rev.bloom < 1.0 then
            rev.bloom = math.min(1.0, rev.bloom + dt / REVEAL_BLOOM_DUR)
            alive = true
        end

        for _, ring in ipairs(rev.rings) do
            if not ring.active then
                ring.delay = ring.delay - dt
                if ring.delay <= 0 then ring.active = true end
            end
            if ring.active and ring.progress < 1.0 then
                ring.progress = math.min(1.0, ring.progress + dt / REVEAL_RING_DUR)
                alive = true
            end
        end

        for k = #rev.sparks, 1, -1 do
            local sp = rev.sparks[k]
            sp.x    = sp.x + sp.vx * dt
            sp.y    = sp.y + sp.vy * dt
            sp.vy   = sp.vy + REVEAL_GRAVITY * dt
            sp.life = sp.life - dt
            if sp.life <= 0 then
                table.remove(rev.sparks, k)
            else
                alive = true
            end
        end

        if not alive then unlockRevealAnims_[pegIdx] = nil end
    end

    updateMoveAnim(dt)
    Renderer.UpdateParticles(dt)

    -- 更新插板完成特效
    local FLASH_DUR = 0.35
    local RING_DUR  = 0.50
    local SPARK_GRAVITY = 260
    for pegIdx, burst in pairs(pegBurstAnims_) do
        local alive = false

        -- 光爆进度
        if burst.flash < 1.0 then
            burst.flash = math.min(1.0, burst.flash + dt / FLASH_DUR)
            alive = true
        end

        -- 扩散光环
        for _, ring in ipairs(burst.rings) do
            if not ring.active then
                ring.delay = ring.delay - dt
                if ring.delay <= 0 then ring.active = true end
            end
            if ring.active and ring.progress < 1.0 then
                ring.progress = math.min(1.0, ring.progress + dt / RING_DUR)
                alive = true
            end
        end

        -- 向上粒子
        for k = #burst.sparks, 1, -1 do
            local sp = burst.sparks[k]
            sp.x    = sp.x + sp.vx * dt
            sp.y    = sp.y + sp.vy * dt
            sp.vy   = sp.vy + SPARK_GRAVITY * dt   -- 重力（比通关粒子轻）
            sp.life = sp.life - dt
            if sp.life <= 0 then
                table.remove(burst.sparks, k)
            else
                alive = true
            end
        end

        if not alive then
            pegBurstAnims_[pegIdx] = nil
        end
    end
end

-- 触发解锁演出（由 game logic 在插板解锁时调用）
function Renderer.TriggerUnlock(i)
    unlockAnims_[i] = { progress = 0, done = false }
end

-- 撤回时清除解锁动画，让盖子恢复显示
function Renderer.ClearUnlock(i)
    unlockAnims_[i] = nil
    unlockRevealAnims_[i] = nil
end

function Renderer.TriggerSeal(i)
    sealAllowed_[i] = true
end

-- 重置所有关卡相关动画状态（切关/重试时调用）
function Renderer.ResetLevel()
    sealAnims_   = {}
    sealAllowed_ = {}
    unlockAnims_ = {}
    hintPegs_       = nil
    hintTimer_      = 0
    moveAnim_       = nil
    particles_          = {}
    pegBurstAnims_      = {}
    unlockRevealAnims_  = {}
    layoutTransition_   = nil
end

-- ---------------------------------------------------------------
-- 主渲染入口
-- ---------------------------------------------------------------
function Renderer.Draw(ctx, W, H, selectedPeg, validTargets)
    -- 背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, W, H)
    if bgImg_ then
        -- 保持素材比例（720×1290），cover 模式居中，允许超出窗口
        local IMG_W, IMG_H = 720, 1290
        local scaleX = W / IMG_W
        local scaleY = H / IMG_H
        local scale  = math.max(scaleX, scaleY)
        local drawW  = IMG_W * scale
        local drawH  = IMG_H * scale
        local drawX  = (W - drawW) * 0.5
        local drawY  = (H - drawH) * 0.5
        local paint  = nvgImagePattern(ctx, drawX, drawY, drawW, drawH, 0, bgImg_, 1.0)
        nvgFillPaint(ctx, paint)
    else
        local bg = nvgLinearGradient(ctx, 0, 0, 0, H,
            nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 255),
            nvgRGBA(BG_COLOR[1] + 8, BG_COLOR[2] + 10, BG_COLOR[3] + 20, 255))
        nvgFillPaint(ctx, bg)
    end
    nvgFill(ctx)

    local pegs = GameState.GetPegs()

    -- 绘制提示高亮环（在插板之下，避免遮盖齿轮）
    if hintPegs_ then
        -- 0.6Hz 闪烁（亮0.8s，灭0.4s 循环）
        local cycle = hintTimer_ % 1.2
        local alpha = 0
        if cycle < 0.8 then
            -- 正弦平滑亮灭
            alpha = math.floor(math.sin(cycle / 0.8 * math.pi) * 220)
        end
        if alpha > 0 then
            local HINT_FROM = { 255, 160, 40  }
            local HINT_TO_C = { 80,  220, 140 }
            for _, entry in ipairs({
                { idx = hintPegs_.from, col = HINT_FROM },
                { idx = hintPegs_.to,   col = HINT_TO_C },
            }) do
                local pidx = entry.idx
                local col  = entry.col
                local cx2  = pegX(pidx)
                local top2 = pegTop(pidx)
                local bot2 = pegBottom(pidx)
                local pw2  = layout_.pegW
                local ringSize = pw2 * 2.2   -- 光圈直径约为插板宽度的 2.2 倍
                local ringCX   = cx2
                local ringCY   = (top2 + bot2) * 0.5  -- 居中于插板高度

                if hintRingImg_ then
                    -- 使用图片光圈，叠加颜色调（from=橙色，to=绿色）
                    local imgPaint = nvgImagePattern(ctx,
                        ringCX - ringSize * 0.5, ringCY - ringSize * 0.5,
                        ringSize, ringSize, 0, hintRingImg_,
                        alpha / 255.0)
                    nvgBeginPath(ctx)
                    nvgRect(ctx,
                        ringCX - ringSize * 0.5, ringCY - ringSize * 0.5,
                        ringSize, ringSize)
                    nvgFillPaint(ctx, imgPaint)
                    nvgFill(ctx)
                    -- 叠加颜色光晕（from=橙，to=绿），增加区分度
                    nvgBeginPath(ctx)
                    nvgRoundedRect(ctx, cx2 - pw2 * 0.5 - 4, top2 - 4, pw2 + 8, (bot2 - top2) + 8, 10)
                    nvgStrokeColor(ctx, nvgRGBA(col[1], col[2], col[3], math.floor(alpha * 0.6)))
                    nvgStrokeWidth(ctx, 2.5)
                    nvgStroke(ctx)
                else
                    -- 回退：纯 NanoVG 线框
                    nvgBeginPath(ctx)
                    nvgRoundedRect(ctx, cx2 - pw2 * 0.5 - 6, top2 - 6, pw2 + 12, (bot2 - top2) + 12, 12)
                    nvgStrokeColor(ctx, nvgRGBA(col[1], col[2], col[3], alpha))
                    nvgStrokeWidth(ctx, 3.0)
                    nvgStroke(ctx)
                end
            end
        end
    end

    -- 绘制所有插板底座（锁定 / 只进不出 / 普通 统一使用 drawPeg 通用底座）
    for i = 1, #pegs do
        local isLocked = GameState.IsPegLocked(i)
        -- 解锁动画进行中（done=false）时继续渲染锁定外观（含动画效果）
        local hasUnlockAnim = unlockAnims_[i] and not unlockAnims_[i].done
        if isLocked or hasUnlockAnim then
            drawLockedPeg(ctx, i)
        else
            -- sink peg 与普通插板共用相同底座图片，视觉由阻挡层区分
            drawPeg(ctx, i, selectedPeg, validTargets)
        end
    end

    -- 绘制所有齿轮
    -- BUG FIX：选中插板的顶部齿轮组由 DrawFloatingGears 负责绘制（含上移效果），
    --          此处跳过，避免双重绘制导致选中状态混乱
    local animTo = moveAnim_ and moveAnim_.toIdx

    for i = 1, #pegs do
        -- 锁定插板：遮罩已覆盖，跳过齿轮绘制（解锁动画中同理，由 drawLockedPeg 处理）
        -- 只进不出插板：允许绘制已放入的齿轮（齿轮颜色略暗，表示永久存放）
        local skipGears = GameState.IsPegLocked(i) or (unlockAnims_[i] and not unlockAnims_[i].done)
        if not skipGears then
            local peg = pegs[i]
            local isSink = GameState.IsPegSink(i)

            -- 计算需要跳过的顶部格数
            local skipTop = 0
            if moveAnim_ and i == animTo then
                -- 动画目标插板：跳过正在飞入的那组
                skipTop = moveAnim_.count
            elseif i == selectedPeg and not GameState.IsPegCompleted(i) and not isSink then
                -- 选中插板（未完成且非 sink）：顶部齿轮组由 DrawFloatingGears 绘制
                -- sink 插板不能选中（CanMove 禁止作为来源），此分支实际不会触发，保留防御
                skipTop = GameState.TopGroupCount(i)
            end

            -- 已完成插板的齿轮缓慢旋转，其余正常
            local visibleTop = #peg - skipTop   -- 本次可见的最高 slot 下标
            local gearAlpha = math.floor(getTransitionAlpha(i) * 255)
            local gearR = layout_.gearR
            for slot = 1, visibleTop do
                -- 隐藏齿轮：只有数据真实顶部（slot == #peg）才显示真实颜色
                local isTop        = (slot == #peg)
                local displayColor = resolveColor(peg[slot], isTop)
                local alpha = gearAlpha
                drawGear(ctx, pegX(i), slotY(slot, i), gearR,
                    displayColor, false, alpha)
            end
        end
    end

    -- ── 层级2.5：轴承盖（始终显示在齿轮中心）──────────────────────
    if gearHubCapImg_ then
        local capR  = layout_.gearR * 0.25   -- 直径 = 齿轮直径 * 25%
        local capD  = capR * 2
        for i = 1, #pegs do
            local skipGears = GameState.IsPegLocked(i) or (unlockAnims_[i] and not unlockAnims_[i].done)
            if not skipGears then
                local peg    = pegs[i]
                -- 与齿轮绘制保持一致：动画目标插板跳过飞入的槽，选中插板跳过顶部浮起组
                local skipTop = 0
                if moveAnim_ and i == moveAnim_.toIdx then
                    skipTop = moveAnim_.count
                elseif i == selectedPeg and not GameState.IsPegCompleted(i) and not GameState.IsPegSink(i) then
                    skipTop = GameState.TopGroupCount(i)
                end
                local visibleTop = #peg - skipTop
                for slot = 1, visibleTop do
                    local cx    = pegX(i)
                    local cy    = slotY(slot, i)
                    local paint = nvgImagePattern(ctx, cx - capR, cy - capR, capD, capD, 0, gearHubCapImg_, 1.0)
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, cx, cy, capR)
                    nvgFillPaint(ctx, paint)
                    nvgFill(ctx)
                end
            end
        end
    end

    -- ── 层级3：阻挡（sink peg 钢筋，齿轮之上）────────────────────
    for i = 1, #pegs do
        if GameState.IsPegSink(i) and pegBlockerImg_ then
            local cx   = pegX(i)
            local top  = pegTop(i)
            local bot  = pegBottom(i)
            local ASSET_RATIO = 128 / 512   -- 素材实际尺寸 128×512
            local imgH = (bot - top) * 0.75
            local imgW = imgH * ASSET_RATIO
            local imgX = cx - imgW / 2
            local imgY = top - (imgH - (bot - top)) * 0.5
            local paint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, pegBlockerImg_, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, imgX, imgY, imgW, imgH)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end
    end

    -- ── 层级4：盖子（完成动画封盖，阻挡之上）────────────────────
    for i = 1, #pegs do
        if not GameState.IsPegLocked(i) then
            drawSealCap(ctx, i)
        end
    end

    -- ── 层级5：灯条（完成后彩色指示条，最顶层）──────────────────
    for i = 1, #pegs do
        if not GameState.IsPegLocked(i) then
            drawSealLight(ctx, i)
        end
    end

    -- 绘制飞行中的动画齿轮（3段：垂直升 → 贝塞尔横移 → 垂直落）
    if moveAnim_ then
        local rawT   = moveAnim_.progress
        local startX = moveAnim_.startX
        local endX   = moveAnim_.endX

        -- 3段占比：升起25% / 贝塞尔横移50% / 落下25%
        local T1 = 0.25   -- 段1结束
        local T2 = 0.75   -- 段2结束（段3开始）

        local midX = (startX + endX) * 0.5
        local arcH = math.max(math.abs(endX - startX) * 0.35, 30)

        for k = 1, moveAnim_.count do
            local g  = moveAnim_.gears[k]

            -- 每个齿轮平移延迟：起始时间错开，结束时间同样错开（不压缩）
            local effT = math.max(0.0, math.min(1.0, rawT - g.delay))

            -- 每个齿轮有独立的贝塞尔控制点（基于各自的 liftY/landY）
            local ctrlY = math.min(g.liftY, g.landY) - arcH

            local gx, gy

            if effT <= T1 then
                -- ── 段1：垂直升起（匀速）────────────────────────────────
                local segT = effT / T1
                gx = startX
                gy = g.startY + (g.liftY - g.startY) * segT

            elseif effT <= T2 then
                -- ── 段2：二次贝塞尔曲线横移（匀速）─────────────────────
                local et   = (effT - T1) / (T2 - T1)
                local oneM = 1.0 - et
                -- X：共享同一横向贝塞尔
                gx = oneM*oneM*startX + 2.0*oneM*et*midX + et*et*endX
                -- Y：每个齿轮走自己的贝塞尔弧
                gy = oneM*oneM*g.liftY + 2.0*oneM*et*ctrlY + et*et*g.landY

            else
                -- ── 段3：垂直落下（ease-in，保持缓入手感）───────────────
                local segT = 1.0 - (1.0 - (effT - T2) / (1.0 - T2))^2
                gx = endX
                gy = g.landY + (g.endY - g.landY) * segT
            end

            local flyGearR = layout_.gearR
            drawGear(ctx, gx, gy, flyGearR, moveAnim_.color, false, 255)

            -- 轴承盖跟随飞行齿轮
            if gearHubCapImg_ then
                local capR  = flyGearR * 0.25
                local capD  = capR * 2
                local paint = nvgImagePattern(ctx, gx - capR, gy - capR, capD, capD, 0, gearHubCapImg_, 1.0)
                nvgBeginPath(ctx)
                nvgCircle(ctx, gx, gy, capR)
                nvgFillPaint(ctx, paint)
                nvgFill(ctx)
            end
        end
    end

    -- 粒子
    for _, p in ipairs(particles_) do
        local a   = math.floor(math.min(p.life, 1.0) * 255)
        local rad = p.r * math.min(p.life, 1.0)
        if p.star then
            -- 五角星（金色粒子专用）
            local cx2, cy2 = p.x, p.y
            local outerR   = rad
            local innerR   = rad * 0.42
            nvgBeginPath(ctx)
            for k = 0, 4 do
                local outerA = -math.pi / 2 + k * 2 * math.pi / 5
                local innerA = outerA + math.pi / 5
                if k == 0 then
                    nvgMoveTo(ctx, cx2 + math.cos(outerA) * outerR, cy2 + math.sin(outerA) * outerR)
                else
                    nvgLineTo(ctx, cx2 + math.cos(outerA) * outerR, cy2 + math.sin(outerA) * outerR)
                end
                nvgLineTo(ctx, cx2 + math.cos(innerA) * innerR, cy2 + math.sin(innerA) * innerR)
            end
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(p.col[1], p.col[2], p.col[3], a))
            nvgFill(ctx)
            -- 描边增加亮度
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 200, math.floor(a * 0.6)))
            nvgStrokeWidth(ctx, 1.0)
            nvgStroke(ctx)
        else
            -- 普通圆形粒子
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, rad)
            nvgFillColor(ctx, nvgRGBA(p.col[1], p.col[2], p.col[3], a))
            nvgFill(ctx)
        end
    end

    -- -------------------------------------------------------
    -- 插板完成特效：光爆 + 扩散光环 + 向上粒子
    -- -------------------------------------------------------
    local s = layout_.scale or 1.0
    for _, burst in pairs(pegBurstAnims_) do
        local cx, cy = burst.cx, burst.cy
        local col    = burst.col

        -- 1. 光爆（中心径向渐变圆，随 flash 进度扩散并淡出）
        if burst.flash < 1.0 then
            local maxR = layout_.gearR * 2.8
            local t    = burst.flash
            -- ease-out：快速扩大后减慢
            local eR   = maxR * (1 - (1 - t) * (1 - t))
            -- alpha：先快速亮起再线性淡出
            local alpha = math.max(0, 1 - t * 1.4) * 200
            local paint = nvgRadialGradient(ctx,
                cx, cy, eR * 0.05, eR,
                nvgRGBA(255, 255, 255, math.floor(alpha)),
                nvgRGBA(col[1], col[2], col[3], 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, eR)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end

        -- 2. 扩散光环（stroke 圆，向外扩散同时淡出）
        for _, ring in ipairs(burst.rings) do
            if ring.active then
                local maxR = layout_.gearR * 3.2
                local t    = ring.progress
                local eR   = maxR * t * (2 - t)   -- ease-out
                local alpha = math.max(0, 1 - t) * 200
                nvgBeginPath(ctx)
                nvgCircle(ctx, cx, cy, eR)
                nvgStrokeColor(ctx, nvgRGBA(ring.col[1], ring.col[2], ring.col[3], math.floor(alpha)))
                nvgStrokeWidth(ctx, (3.0 - t * 2.0) * s)
                nvgStroke(ctx)
            end
        end

        -- 3. 向上粒子（小圆点）
        for _, sp in ipairs(burst.sparks) do
            local lifeRatio = sp.life / sp.maxLife
            local a   = math.floor(math.min(lifeRatio, 1.0) * 220)
            local rad = sp.rad * math.max(0.3, lifeRatio)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sp.x, sp.y, rad)
            nvgFillColor(ctx, nvgRGBA(sp.col[1], sp.col[2], sp.col[3], a))
            nvgFill(ctx)
        end
    end

    -- -------------------------------------------------------
    -- 解锁颜色亮相特效：白色闪光 + 颜色光晕 + 扩散光环 + 全向粒子
    -- -------------------------------------------------------
    for _, rev in pairs(unlockRevealAnims_) do
        local cx2, cy2 = rev.cx, rev.cy
        local col2     = rev.col

        -- 1. 白色闪光（迅速扩散后淡出，象征盖子炸开瞬间的强光）
        if rev.flash < 1.0 then
            local t     = rev.flash
            local maxR  = layout_.gearR * 3.2
            local eR    = maxR * (1 - (1 - t) * (1 - t))
            local alpha = math.max(0, 1 - t * 1.7) * 240
            local paint = nvgRadialGradient(ctx,
                cx2, cy2, eR * 0.02, eR,
                nvgRGBA(255, 255, 255, math.floor(alpha)),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx2, cy2, eR)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end

        -- 2. 颜色光晕（慢速扩散，用插板解锁颜色染色，持续感更强）
        if rev.bloom < 1.0 then
            local t     = rev.bloom
            local maxR  = layout_.gearR * 2.6
            local eR    = maxR * (1 - (1 - t) * (1 - t))
            local alpha = math.max(0, 1 - t) * 170
            local paint = nvgRadialGradient(ctx,
                cx2, cy2, eR * 0.08, eR,
                nvgRGBA(col2[1], col2[2], col2[3], math.floor(alpha)),
                nvgRGBA(col2[1], col2[2], col2[3], 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx2, cy2, eR)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end

        -- 3. 扩散光环
        for _, ring in ipairs(rev.rings) do
            if ring.active then
                local maxR  = layout_.gearR * 3.8
                local t     = ring.progress
                local eR    = maxR * t * (2 - t)
                local alpha = math.max(0, 1 - t) * 220
                nvgBeginPath(ctx)
                nvgCircle(ctx, cx2, cy2, eR)
                nvgStrokeColor(ctx, nvgRGBA(ring.col[1], ring.col[2], ring.col[3], math.floor(alpha)))
                nvgStrokeWidth(ctx, (4.0 - t * 3.0) * s)
                nvgStroke(ctx)
            end
        end

        -- 4. 全向粒子
        for _, sp in ipairs(rev.sparks) do
            local lifeRatio = sp.life / sp.maxLife
            local a   = math.floor(math.min(lifeRatio, 1.0) * 220)
            local rad = sp.rad * math.max(0.3, lifeRatio)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sp.x, sp.y, rad)
            nvgFillColor(ctx, nvgRGBA(sp.col[1], sp.col[2], sp.col[3], a))
            nvgFill(ctx)
        end
    end
end

-- 绘制选中插板上方的浮起预览（选中时齿轮组略微上移）
function Renderer.DrawFloatingGears(ctx, selectedPeg)
    if not selectedPeg then return end
    -- 锁定插板无法选中，但防御性检查
    if GameState.IsPegLocked(selectedPeg) then return end
    local pegs  = GameState.GetPegs()
    local peg   = pegs[selectedPeg]
    if #peg == 0 then return end

    local gearR = layout_.gearR

    local count = GameState.TopGroupCount(selectedPeg)
    local lift  = gearR * 0.6 + math.sin(time_ * 4) * 4   -- 悬浮抖动

    for k = 0, count - 1 do
        local slot  = #peg - k
        -- 手中持有的隐藏齿轮全部显示真实颜色（已揭示）
        local displayColor = resolveColor(peg[slot], true)
        local gx = pegX(selectedPeg)
        local gy = slotY(slot, selectedPeg) - lift
        drawGear(ctx, gx, gy, gearR, displayColor, (k == 0), 255)
        -- 轴承盖跟随浮起齿轮
        if gearHubCapImg_ then
            local capR  = gearR * 0.25
            local capD  = capR * 2
            local paint = nvgImagePattern(ctx, gx - capR, gy - capR, capD, capD, 0, gearHubCapImg_, 1.0)
            nvgBeginPath(ctx)
            nvgCircle(ctx, gx, gy, capR)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        end
    end
end

-- 在插板上方绘制数量徽标
function Renderer.DrawCountBadge(ctx, selectedPeg)
    if not selectedPeg then return end
    local count = GameState.TopGroupCount(selectedPeg)
    if count <= 1 then return end

    local cx = pegX(selectedPeg)
    local pegs = GameState.GetPegs()
    local peg  = pegs[selectedPeg]
    local topSlotY = slotY(#peg, selectedPeg) - layout_.gearR * 1.8

    local badgeR = layout_.gearR * 0.5
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, topSlotY, badgeR)
    nvgFillColor(ctx, nvgRGBA(SELECT_COLOR[1], SELECT_COLOR[2], SELECT_COLOR[3], 220))
    nvgFill(ctx)

    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, badgeR * 1.4)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(20, 20, 20, 255))
    nvgText(ctx, cx, topSlotY, tostring(count), nil)
end

return Renderer
