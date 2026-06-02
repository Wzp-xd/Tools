-- ============================================================
-- LevelGenerator.lua - 关卡生成（支持全部进阶机制）
-- 迷雾层 / 封印管 / 临时管 / 单向管
-- ============================================================

local Config = require("config")

local LevelGenerator = {}

--- Fisher-Yates 洗牌
---@param arr table
local function shuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

--- 深拷贝管组
---@param tubes table[]
---@return table[]
local function deepCopyTubes(tubes)
    local copy = {}
    for i = 1, #tubes do
        copy[i] = {}
        for j = 1, #tubes[i] do
            copy[i][j] = tubes[i][j]
        end
    end
    return copy
end

-- ============================================================
-- 基础生成（随机洗牌法，生成普通颜色管 + 空管）
-- ============================================================

--- 生成基础关卡（无机制纯颜色洗牌）
---@param colors integer 颜色种数
---@param empty integer 空管数
---@param lockedCount integer 封印管数（也是颜色管，但被锁）
---@return table[] tubes, integer tubeCount
local function generateBaseTubes(colors, empty, lockedCount)
    local layerCount = Config.tube.layerCount
    local totalColorTubes = colors  -- 包含封印管
    local totalTubes = totalColorTubes + empty

    -- 生成所有颜色层
    local allLayers = {}
    for c = 1, colors do
        for _ = 1, layerCount do
            table.insert(allLayers, c)
        end
    end
    shuffleArray(allLayers)

    -- 分配到管中
    local tubes = {}
    local idx = 1
    for i = 1, totalColorTubes do
        tubes[i] = {}
        for _ = 1, layerCount do
            tubes[i][#tubes[i] + 1] = allLayers[idx]
            idx = idx + 1
        end
    end
    -- 空管
    for i = totalColorTubes + 1, totalTubes do
        tubes[i] = {}
    end

    return tubes, totalTubes
end

-- ============================================================
-- 迷雾层分配
-- ============================================================

--- 为管组分配隐藏层（底层优先，不隐藏管顶）
---@param tubes table[] 管组（会被原地修改）
---@param hiddenLayers integer 总隐藏层数
---@param lockedTubeSet table 被封印管索引集合（跳过）
---@param colorTubeCount integer 颜色管数量（在这些管中分配迷雾）
local function assignHiddenLayers(tubes, hiddenLayers, lockedTubeSet, colorTubeCount)
    if hiddenLayers <= 0 then return end
    local layerCount = Config.tube.layerCount

    -- 收集可分配位置: 非封印管的非顶层位置（layer 1 ~ layerCount-1）
    local candidates = {}  -- { {tubeIdx, layerIdx}, ... }
    for i = 1, colorTubeCount do
        if not lockedTubeSet[i] then
            -- 底部到第二层（索引1 ~ layerCount-1）可以隐藏
            for j = 1, layerCount - 1 do
                table.insert(candidates, { i, j })
            end
        end
    end

    shuffleArray(candidates)

    local assigned = 0
    for k = 1, #candidates do
        if assigned >= hiddenLayers then break end
        local tubeIdx = candidates[k][1]
        local layerIdx = candidates[k][2]
        local color = tubes[tubeIdx][layerIdx]
        if color > 0 then  -- 未被隐藏
            tubes[tubeIdx][layerIdx] = -color
            assigned = assigned + 1
        end
    end
end

-- ============================================================
-- 封印管分配（含死锁防护）
-- ============================================================

--- 分配封印管
---@param tubes table[] 管组
---@param colorCount integer 颜色种数
---@param lockedCount integer 封印管数
---@param colorTubeCount integer 颜色管数量
---@return table locks { [tubeIdx] = unlockColorIdx }
local function assignLocks(tubes, colorCount, lockedCount, colorTubeCount)
    if lockedCount <= 0 then return {} end
    local layerCount = Config.tube.layerCount

    -- 统计每个颜色在哪些管中出现
    local colorInTubes = {}  -- { [color] = { tubeIdx1, tubeIdx2, ... } }
    for c = 1, colorCount do colorInTubes[c] = {} end
    for i = 1, colorTubeCount do
        local seen = {}
        for j = 1, #tubes[i] do
            local c = math.abs(tubes[i][j])
            if not seen[c] then
                seen[c] = true
                table.insert(colorInTubes[c], i)
            end
        end
    end

    -- 选择哪些管被锁定:
    -- 优先选择颜色混合度高的管（更有挑战性）
    local tubeScores = {}
    for i = 1, colorTubeCount do
        local transitions = 0
        for j = 2, #tubes[i] do
            if math.abs(tubes[i][j]) ~= math.abs(tubes[i][j - 1]) then
                transitions = transitions + 1
            end
        end
        table.insert(tubeScores, { idx = i, score = transitions })
    end
    -- 按混合度降序排列（选最混的管锁住，增加难度）
    table.sort(tubeScores, function(a, b) return a.score > b.score end)

    local locks = {}
    local lockedSet = {}
    local usedUnlockColors = {}

    for _, entry in ipairs(tubeScores) do
        if #lockedSet >= lockedCount then break end  -- 用 table 代替 next 检查
        local tubeIdx = entry.idx

        -- 为此管选择一个解锁颜色
        -- 规则: 解锁色不能出现在此管内（防死锁），也不能仅存在于已锁管中
        local tubeColors = {}
        for j = 1, #tubes[tubeIdx] do
            tubeColors[math.abs(tubes[tubeIdx][j])] = true
        end

        local bestUnlockColor = nil
        local shuffledColors = {}
        for c = 1, colorCount do table.insert(shuffledColors, c) end
        shuffleArray(shuffledColors)

        for _, c in ipairs(shuffledColors) do
            if not tubeColors[c] and not usedUnlockColors[c] then
                -- 检查该颜色是否在非封印管中有层（保证可达性）
                local reachable = false
                for _, tIdx in ipairs(colorInTubes[c]) do
                    if tIdx ~= tubeIdx and not lockedSet[tIdx] then
                        reachable = true
                        break
                    end
                end
                if reachable then
                    bestUnlockColor = c
                    break
                end
            end
        end

        if bestUnlockColor then
            locks[tubeIdx] = bestUnlockColor
            lockedSet[tubeIdx] = true
            usedUnlockColors[bestUnlockColor] = true
            table.insert(lockedSet, tubeIdx)  -- track count via # (won't affect set lookup)
        end
    end

    return locks, lockedSet
end

-- ============================================================
-- 单向管分配（从空管中分配）
-- ============================================================

--- 分配单向管
---@param tubes table[]
---@param sinkCount integer
---@param colorTubeCount integer
---@param totalTubeCount integer
---@return table sinkTubes { [tubeIdx] = true }
local function assignSinkTubes(tubes, sinkCount, colorTubeCount, totalTubeCount)
    if sinkCount <= 0 then return {} end
    local sinkTubes = {}

    -- 从空管中选择（空管索引在 colorTubeCount+1 ~ totalTubeCount）
    local emptyIndices = {}
    for i = colorTubeCount + 1, totalTubeCount do
        table.insert(emptyIndices, i)
    end
    shuffleArray(emptyIndices)

    for k = 1, math.min(sinkCount, #emptyIndices) do
        sinkTubes[emptyIndices[k]] = true
    end

    return sinkTubes
end

-- ============================================================
-- 临时管追加
-- ============================================================

--- 追加临时管到管组末尾
---@param tubes table[]
---@param tubeCount integer
---@param tempTubeCount integer
---@return table tempTubes { [tubeIdx] = capacity }, integer newTubeCount
local function appendTempTubes(tubes, tubeCount, tempTubeCount)
    if tempTubeCount <= 0 then return {}, tubeCount end
    local tempTubes = {}
    for k = 1, tempTubeCount do
        local newIdx = tubeCount + k
        tubes[newIdx] = {}
        tempTubes[newIdx] = 1  -- 初始容量 1
    end
    return tempTubes, tubeCount + tempTubeCount
end

-- ============================================================
-- 评分函数（选最佳布局）
-- ============================================================

--- 评估管组的混乱度
---@param tubes table[]
---@param colorTubeCount integer
---@return integer
local function scoreTubes(tubes, colorTubeCount)
    local score = 0
    local layerCount = Config.tube.layerCount

    for i = 1, colorTubeCount do
        local tube = tubes[i]
        if #tube > 0 then
            local transitions = 0
            for j = 2, #tube do
                if math.abs(tube[j]) ~= math.abs(tube[j - 1]) then
                    transitions = transitions + 1
                end
            end
            score = score + transitions

            -- 检查是否已经完成（扣分）
            if #tube == layerCount then
                local first = math.abs(tube[1])
                local pure = true
                for j = 2, #tube do
                    if math.abs(tube[j]) ~= first then pure = false; break end
                end
                if pure then score = score - 10 end
            end
        end
    end

    return score
end

-- ============================================================
-- 公开 API
-- ============================================================

--- 生成基础关卡（向后兼容，无机制）
---@param level integer
---@return table[] tubes
function LevelGenerator.generate(level)
    local cfg = Config.getLevelConfig(level)
    local tubes = generateBaseTubes(cfg.colors, cfg.empty, cfg.lockedCount)
    return tubes
end

--- 生成完整关卡（含所有机制，多次尝试选最佳）
--- 新签名: 接受 cfg 表或 level 数字
---@param level integer
---@param cfgOrAttempts table|integer|nil cfg表 或 旧式maxAttempts数字
---@return table result { tubes, tubeCount, locks, tempTubes, sinkTubes }
function LevelGenerator.generateQuality(level, cfgOrAttempts)
    local cfg
    if type(cfgOrAttempts) == "table" then
        cfg = cfgOrAttempts
    else
        cfg = Config.getLevelConfig(level)
    end

    local maxAttempts = 20
    local layerCount = Config.tube.layerCount
    local colors = cfg.colors
    local empty = cfg.empty or 2
    local lockedCount = cfg.lockedCount or 0
    local hiddenLayers = cfg.hiddenLayers or 0
    local sinkCount = cfg.sinkCount or 0
    local tempTubeCount = cfg.tempTubeCount or 0

    local bestResult = nil
    local bestScore = -999

    for _ = 1, maxAttempts do
        -- 1. 生成基础颜色管 + 空管
        local tubes, tubeCount = generateBaseTubes(colors, empty, lockedCount)
        local colorTubeCount = colors  -- 前 colors 个管都是颜色管

        -- 2. 分配封印管
        local locks, lockedSet = assignLocks(tubes, colors, lockedCount, colorTubeCount)
        if type(lockedSet) ~= "table" then lockedSet = {} end

        -- 3. 分配迷雾层（在非封印的颜色管上）
        assignHiddenLayers(tubes, hiddenLayers, lockedSet, colorTubeCount)

        -- 4. 分配单向管（从空管中）
        local sinkTubes = assignSinkTubes(tubes, sinkCount, colorTubeCount, tubeCount)

        -- 5. 追加临时管
        local tempTubes, finalTubeCount = appendTempTubes(tubes, tubeCount, tempTubeCount)

        -- 评分
        local score = scoreTubes(tubes, colorTubeCount)

        -- 额外惩罚: 如果封印管分配不足目标数量
        local actualLockCount = 0
        for _ in pairs(locks) do actualLockCount = actualLockCount + 1 end
        if actualLockCount < lockedCount then
            score = score - 50
        end

        if score > bestScore then
            bestScore = score
            bestResult = {
                tubes = tubes,
                tubeCount = finalTubeCount,
                locks = locks,
                tempTubes = tempTubes,
                sinkTubes = sinkTubes,
            }
        end
    end

    return bestResult
end

return LevelGenerator
