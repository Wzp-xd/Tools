-- level_generator.lua
-- 参数化随机关卡生成器
--
-- 生成流程：
--   1. 建齿轮池（每色 CAPACITY 个）
--   2. 分配锁定插板：随机解锁色 + 随机填充其余槽（不允许全相同）
--   3. 将剩余齿轮均匀分配到普通颜色插板（每板恰好 CAPACITY 个）
--   4. 逐格 pairwise swap 打散布局（只在非锁定插板间操作）
--   5. 循环检查已完成插板，强制破开（最多 100 轮防死循环）
--   6. 标记隐藏齿轮 & 标记 sink 插板
--   （空插板始终为空，不参与打散）

local LevelGenerator = {}

local CAPACITY = 4  -- 每根插板固定容量

-- ---------------------------------------------------------------
-- LCG 随机数生成器（Park-Miller，避免污染全局 math.random）
-- ---------------------------------------------------------------
local function NewRNG(seed)
    local s = seed or os.time()
    if s == 0 then s = 1 end
    return {
        next = function(self)
            s = (s * 16807) % 2147483647
            return s
        end,
        int = function(self, lo, hi)
            return lo + (self:next() % (hi - lo + 1))
        end,
        float = function(self)
            return self:next() / 2147483647
        end,
    }
end

-- ---------------------------------------------------------------
-- 颜色名称表（与 renderer.lua 保持一致）
-- ---------------------------------------------------------------
local COLOR_NAMES = {
    -- 前 12 色（当前关卡使用，colorCount 2~12）
    "cyan", "yellow", "coral", "violet", "lime", "blue",
    "rose", "forest", "red", "navy", "brown", "maroon",
    -- 扩展备用（当前关卡不使用）
    "green", "purple", "orange", "teal", "gold", "pink",
    "olive", "indigo", "crimson", "azure",
}

-- ---------------------------------------------------------------
-- 辅助
-- ---------------------------------------------------------------
local function actualColor(c)
    if c and c:sub(1, 7) == "hidden_" then
        return c:sub(8)
    end
    return c
end

local function isHidden(c)
    return c ~= nil and c:sub(1, 7) == "hidden_"
end

-- 检查插板是否处于"已完成"状态（满 CAPACITY 且全同色）
local function isPegCompleted(peg)
    if #peg ~= CAPACITY then return false end
    local color = actualColor(peg[1])
    for _, c in ipairs(peg) do
        if actualColor(c) ~= color then return false end
    end
    return true
end

-- Fisher-Yates 洗牌（in-place）
local function shuffle(arr, rng)
    for i = #arr, 2, -1 do
        local j = rng:int(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- ---------------------------------------------------------------
-- 标记隐藏齿轮
-- 从插板 1 的底部（slot 1）开始，跳过锁定插板，每板最多标记 3 个，
-- 顶部 slot 永不标记（保证玩家至少能看到顶色）
--
-- 特殊逻辑：当 hiddenGears > 6 且锁定插板数 > 1 时，
-- 随机选取最多 1 个锁定插板，将其底部最多 3 个齿轮标记为隐藏（计入总预算）
-- ---------------------------------------------------------------
local function markHiddenGears(pegs, hiddenGears, lockedSet, rng)
    if hiddenGears <= 0 then return end
    local remaining = hiddenGears

    -- 收集锁定插板列表
    local lockedList = {}
    for pegIdx in pairs(lockedSet) do
        lockedList[#lockedList + 1] = pegIdx
    end

    -- 特殊逻辑：hiddenGears > 3 且有锁定插板时，30% 概率随机选取最多 1 个锁定插板参与隐藏标记
    if hiddenGears > 3 and #lockedList >= 1 and rng:float() < 0.3 then
        -- 随机选 1 个锁定插板
        local chosen = lockedList[rng:int(1, #lockedList)]
        local peg = pegs[chosen]
        if #peg > 0 then
            local maxHide = math.min(3, #peg - 1)
            for slot = 1, maxHide do
                if remaining <= 0 then break end
                local c = peg[slot]
                if not isHidden(c) then
                    peg[slot] = "hidden_" .. actualColor(c)
                    remaining = remaining - 1
                end
            end
        end
    end

    -- 正常逻辑：非锁定插板，从底部开始标记隐藏齿轮
    for pegIdx = 1, #pegs do
        if remaining <= 0 then break end
        local peg = pegs[pegIdx]
        if #peg > 0 and not lockedSet[pegIdx] then
            local maxHide = math.min(3, #peg - 1)
            for slot = 1, maxHide do
                if remaining <= 0 then break end
                local c = peg[slot]
                if not isHidden(c) then
                    peg[slot] = "hidden_" .. actualColor(c)
                    remaining = remaining - 1
                end
            end
        end
    end
end

-- ---------------------------------------------------------------
-- 主入口：LevelGenerator.Generate(cfg)
--
-- cfg 字段：
--   colorCount   number  颜色数（2–22）
--   emptyPegs    number  空插板数（通常 2）
--   lockedGroups number  锁定插板数（0、1 或 2）
--   hiddenGears  number  隐藏齿轮数（0–colorCount×3）
--   sinkPegs     number  只进不出插板数（仅从空插板中选取）
--   seed         number  随机种子（nil=每次随机）
--
-- 返回格式：{ pegs={}, capacity=4, locks={}, sinks={} }
-- ---------------------------------------------------------------
function LevelGenerator.Generate(cfg)
    local colorCount   = cfg.colorCount   or 3
    local emptyPegs    = cfg.emptyPegs    or 1
    local lockedGroups = cfg.lockedGroups or 0
    local hiddenGears  = cfg.hiddenGears  or 0
    local sinkCount    = cfg.sinkPegs     or 0
    local seed         = cfg.seed

    assert(colorCount >= 2 and colorCount <= #COLOR_NAMES,
        string.format("colorCount 超出范围：%d（最大 %d）", colorCount, #COLOR_NAMES))

    local rng = NewRNG(seed)

    -- ===============================================================
    -- 第一步：建立齿轮池（每色 CAPACITY 个）
    -- ===============================================================
    -- pool[color] = 剩余可用数量
    local pool = {}
    for i = 1, colorCount do
        pool[COLOR_NAMES[i]] = CAPACITY
    end

    -- ===============================================================
    -- 第二步：分配锁定插板
    --
    -- 对每个锁定插板：
    --   a. 从所有颜色中随机选一个作为"解锁色"（此色的所有齿轮必须全部在锁定插板外）
    --      → 锁定插板内不放任何解锁色齿轮
    --   b. 将剩余 CAPACITY 个槽填入随机颜色（不含解锁色），
    --      且不允许全部相同（确保插板初始不是"已完成"状态）
    -- ===============================================================
    local pegs  = {}
    local locks = {}

    -- 已被选为解锁色的颜色集合（同一颜色不能被两个锁定插板同时作为解锁色）
    local usedUnlockColors = {}
    -- 锁定插板下标集合
    local lockedSet = {}

    for _ = 1, lockedGroups do
        -- 选解锁色：从未被用作解锁色的颜色中随机选
        local availUnlock = {}
        for i = 1, colorCount do
            if not usedUnlockColors[COLOR_NAMES[i]] then
                availUnlock[#availUnlock + 1] = COLOR_NAMES[i]
            end
        end
        assert(#availUnlock > 0, "颜色不足以分配解锁色")
        local unlockColor = availUnlock[rng:int(1, #availUnlock)]
        usedUnlockColors[unlockColor] = true

        -- 填充锁定插板的 CAPACITY 个槽
        -- 可用颜色：所有颜色中排除解锁色，且仍有剩余齿轮
        local fillColors = {}
        for i = 1, colorCount do
            local c = COLOR_NAMES[i]
            if c ~= unlockColor and pool[c] > 0 then
                fillColors[#fillColors + 1] = c
            end
        end
        assert(#fillColors > 0, "锁定插板无可用填充颜色")

        -- 先随机填 CAPACITY 个槽，然后检查是否全同色；若全同色则强制替换一个槽
        local peg = {}
        for _ = 1, CAPACITY do
            -- 从 fillColors 中随机选，但只选仍有库存的
            local avail = {}
            for _, c in ipairs(fillColors) do
                if pool[c] > 0 then avail[#avail + 1] = c end
            end
            assert(#avail > 0, "锁定插板填充时颜色库存耗尽")
            local chosen = avail[rng:int(1, #avail)]
            peg[#peg + 1] = chosen
            pool[chosen] = pool[chosen] - 1
        end

        -- 检查是否全同色（已完成状态），若是则强制替换一个槽为不同颜色
        local firstColor = peg[1]
        local allSame = true
        for _, c in ipairs(peg) do
            if c ~= firstColor then allSame = false; break end
        end
        if allSame then
            -- 找一个不同于 firstColor 的可用颜色（排除解锁色）
            local alt = nil
            for i = 1, colorCount do
                local c = COLOR_NAMES[i]
                if c ~= firstColor and c ~= unlockColor and pool[c] > 0 then
                    alt = c
                    break
                end
            end
            if alt then
                -- 替换 peg 中随机一个槽
                local slotToReplace = rng:int(1, CAPACITY)
                pool[peg[slotToReplace]] = pool[peg[slotToReplace]] + 1
                peg[slotToReplace] = alt
                pool[alt] = pool[alt] - 1
            end
            -- 若找不到 alt（极端情况，颜色数极少），保留原样（不理想但不死循环）
        end

        local pegIdx = #pegs + 1
        pegs[pegIdx] = peg
        locks[pegIdx] = unlockColor
        lockedSet[pegIdx] = true

        print(string.format("[LevelGenerator] 锁定插板 #%d 解锁色=%s，内容=[%s]",
            pegIdx, unlockColor, table.concat(peg, ",")))
    end

    -- ===============================================================
    -- 第三步：将剩余齿轮分配到普通颜色插板（每板恰好 CAPACITY 个）
    -- ===============================================================
    -- 收集所有剩余齿轮
    local gearPool = {}
    for i = 1, colorCount do
        local c = COLOR_NAMES[i]
        for _ = 1, pool[c] do
            gearPool[#gearPool + 1] = c
        end
    end

    -- 打乱齿轮池（先洗牌，再顺序填入，避免前几板颜色过于集中）
    shuffle(gearPool, rng)

    -- 普通颜色插板数 = colorCount - lockedGroups
    local normalPegCount = colorCount - lockedGroups
    -- 验证齿轮数量匹配
    assert(#gearPool == normalPegCount * CAPACITY,
        string.format("齿轮数量不匹配：gearPool=%d，需要=%d", #gearPool, normalPegCount * CAPACITY))

    local gearIdx = 1
    for _ = 1, normalPegCount do
        local peg = {}
        for _ = 1, CAPACITY do
            peg[#peg + 1] = gearPool[gearIdx]
            gearIdx = gearIdx + 1
        end
        pegs[#pegs + 1] = peg
    end

    -- 追加空插板（始终为空，不参与打散）
    local emptyPegStart = #pegs + 1
    for _ = 1, emptyPegs do
        pegs[#pegs + 1] = {}
    end

    -- ===============================================================
    -- 第四步：pairwise swap 打散（只操作非锁定的颜色插板）
    --
    -- 对每个槽位，随机挑另一个槽位对调：
    --   - 遍历所有非锁定插板的所有槽
    --   - 每个槽与另一个随机非锁定插板的随机槽对调
    -- 执行多轮确保充分打散
    -- ===============================================================
    -- 收集所有可操作槽（[pegIdx, slotIdx] 对）
    local function collectSlots()
        local slots = {}
        for pi = 1, #pegs do
            if not lockedSet[pi] and #pegs[pi] > 0 then
                for si = 1, #pegs[pi] do
                    slots[#slots + 1] = { pi, si }
                end
            end
        end
        return slots
    end

    -- 执行 3 轮 pairwise swap（3 轮 = 每个槽平均交换 3 次）
    for _ = 1, 3 do
        local slots = collectSlots()
        -- Fisher-Yates 打乱槽列表本身，再两两对调
        shuffle(slots, rng)
        -- 将打乱后的槽列表两两配对对调
        local i = 1
        while i + 1 <= #slots do
            local a = slots[i]
            local b = slots[i + 1]
            pegs[a[1]][a[2]], pegs[b[1]][b[2]] = pegs[b[1]][b[2]], pegs[a[1]][a[2]]
            i = i + 2
        end
    end

    -- ===============================================================
    -- 第五步：循环检查已完成插板，强制破开（最多 100 轮）
    -- ===============================================================
    -- 收集所有非锁定颜色插板
    local function getNormalPegs()
        local result = {}
        for pi = 1, #pegs do
            if not lockedSet[pi] and pi < emptyPegStart then
                result[#result + 1] = pi
            end
        end
        return result
    end

    local maxBreakLoop = 100
    for breakLoop = 1, maxBreakLoop do
        -- 找到所有已完成插板
        local completedList = {}
        for _, pi in ipairs(getNormalPegs()) do
            if isPegCompleted(pegs[pi]) then
                completedList[#completedList + 1] = pi
            end
        end
        if #completedList == 0 then
            print(string.format("[LevelGenerator] 第 %d 轮检查：无已完成插板，结束", breakLoop))
            break
        end

        print(string.format("[LevelGenerator] 第 %d 轮检查：发现 %d 个已完成插板，强制破开",
            breakLoop, #completedList))

        -- 对每个已完成插板，将顶部齿轮与另一个随机非锁定插板的随机槽对调
        for _, pi in ipairs(completedList) do
            -- 收集候选插板（非锁定、非空、不是同一个）
            local candidates = {}
            for _, ti in ipairs(getNormalPegs()) do
                if ti ~= pi and #pegs[ti] > 0 then
                    candidates[#candidates + 1] = ti
                end
            end
            if #candidates > 0 then
                local ti = candidates[rng:int(1, #candidates)]
                -- 随机选 pi 中的一个槽和 ti 中的一个槽对调
                local si = rng:int(1, #pegs[pi])
                local sj = rng:int(1, #pegs[ti])
                pegs[pi][si], pegs[ti][sj] = pegs[ti][sj], pegs[pi][si]
            end
        end

        -- 若已达上限，打印警告
        if breakLoop == maxBreakLoop then
            print("[LevelGenerator] WARNING: 达到最大破开轮数 100，可能仍有已完成插板")
        end
    end

    -- ===============================================================
    -- 第六步：标记隐藏齿轮
    -- ===============================================================
    if hiddenGears > 0 then
        markHiddenGears(pegs, hiddenGears, lockedSet, rng)
    end

    -- 安全：若非锁定插板顶部仍是隐藏齿轮，立即显示
    for i, peg in ipairs(pegs) do
        if not lockedSet[i] and #peg > 0 and isHidden(peg[#peg]) then
            peg[#peg] = actualColor(peg[#peg])
        end
    end

    -- ===============================================================
    -- 第七步：随机选取空插板作为只进不出插板（sink）
    -- ===============================================================
    local sinks = {}
    if sinkCount > 0 then
        local emptyIdxs = {}
        for i, peg in ipairs(pegs) do
            if #peg == 0 then
                emptyIdxs[#emptyIdxs + 1] = i
            end
        end
        local n = math.min(sinkCount, #emptyIdxs)
        for i = 1, n do
            local j = rng:int(i, #emptyIdxs)
            emptyIdxs[i], emptyIdxs[j] = emptyIdxs[j], emptyIdxs[i]
            sinks[emptyIdxs[i]] = true
        end
    end

    -- ===============================================================
    -- 输出结果
    -- ===============================================================
    print(string.format("[LevelGenerator] 生成完成：%d色 %d空 %d锁定 %d隐藏 %d只进不出",
        colorCount, emptyPegs, lockedGroups, hiddenGears, sinkCount))

    -- 调试：打印每根插板内容
    for pi, peg in ipairs(pegs) do
        local label = ""
        if lockedSet[pi] then
            label = string.format("(锁定,解锁色=%s)", locks[pi])
        elseif #peg == 0 then
            label = "(空)"
        end
        print(string.format("  插板 #%d %s: [%s]%s", pi, label, table.concat(peg, ","),
            isPegCompleted(peg) and " ★完成" or ""))
    end

    return {
        pegs     = pegs,
        capacity = CAPACITY,
        locks    = locks,
        sinks    = sinks,
    }
end

return LevelGenerator
