-- levels.lua
-- 关卡数据，共 40 关（全部参数化）
--
-- 参数说明：
--   colorCount   颜色数（每种颜色恰好 4 个齿轮）
--   emptyPegs    空插板数（用于临时存放，固定 2）
--   lockedGroups 锁定插板数（0、1 或 2）
--   hiddenGears  隐藏齿轮数（从插板1底部起逐槽标记，最多3个/根，跳过锁定插板）
--   sinkPegs     只进不出插板数（从空插板中随机选取）
--
-- ⚠️ 插板总数上限：7×2 = 14 根
--   总插板 = colorCount + emptyPegs + lockedGroups ≤ 14
--   → 无锁时 colorCount 最大 10（10+2+0=12）
--   → locked=1 时 colorCount 最大 10（10+2+1=13）
--   → locked=2 时 colorCount 最大 10（10+2+2=14）
--
-- 难度递进约束（L15 起）：
--   • lockedGroups 最高 2
--   • hiddenGears 最高 (colorCount-3)*3
--   • colorCount 最高 10
--
-- 难度递进规则（L1-L14，教程+阶段二~五前半）：
--   • 教程关(L1)：手写，1色(cyan)
--   • 阶段二(L2-L5)：3色，hidden 0/3 + 锁定引入
--   • 阶段三(L6-L10)：4色，hidden 0/3/6 + 锁定组合
--   • 阶段四(L11-L12)：4色+锁，hidden 3→6
--   • 阶段五前半(L13-L14)：5色，hidden 0→3
-- 难度递进规则（L15-L40，阶段五续~最终关）：
--   • 阶段五续(L15-L16)：5色，locked 1→0，hidden 6→9
--   • 阶段六(L17-L19)：6色，locked 1→0→2，hidden 3→6→0
--   • 阶段七(L20-L22)：7色，locked 0→0→2，hidden 9→6→0 + tempPeg
--   • 阶段八(L23-L25)：8色，locked 1→0→1，hidden 3→6→6 + tempPeg
--   • 阶段九(L26-L28)：9色，locked 2→0→2，hidden 3→9→3 + tempPeg
--   • 阶段十(L29-L32)：10色，locked 0→0→2→0，hidden 6→9→0→15 + tempPeg
--   • 阶段十一(L33-L36)：10色，locked 2→0→2→1，hidden 6→9→0→3 + sink 引入(L35)
--   • 阶段十二(L37-L40)：终极阶段，locked 2→0→1→2+sink+hidden 0→6→6→6，最终关满配

local LevelGenerator = require("level_generator")

local Levels = {}

-- session 级缓存：同一会话内同一关卡始终生成相同布局
Levels._cache = {}

Levels.data = {

    -- ========== 教程关：特殊手写关卡 ==========
    -- L1: 教程关，1色（cyan），插板1有3个齿轮，插板2有1个齿轮，插板3为空
    -- 目标：把插板2的1个齿轮移到插板1，完成同色汇总
    {
        type     = "manual",
        capacity = 4,
        pegs     = {
            { "cyan", "cyan", "cyan" },   -- 插板1：3个齿轮（底→顶：索引1=底）
            { "cyan" },                   -- 插板2：1个齿轮
            {},                           -- 插板3：空插板
        },
        locks = {},
        sinks = {},
        -- 教程关卡标记
        isTutorial = true,
    },

    -- ========== 阶段二：3色（L2-L4）==========
    -- L2: 3色引入，无隐藏
    { type="generated", colorCount=3, emptyPegs=2, lockedGroups=0, hiddenGears=0 },
    -- L3: 3色，隐藏3个
    { type="generated", colorCount=3, emptyPegs=2, lockedGroups=0, hiddenGears=3 },
    -- L4: 3色+锁定，无隐藏
    { type="generated", colorCount=3, emptyPegs=2, lockedGroups=1, hiddenGears=0 },

    -- ========== 阶段三：4色（L5-L7）==========
    -- L5: 4色+锁定，无隐藏
    { type="generated", colorCount=4, emptyPegs=2, lockedGroups=1, hiddenGears=0 },
    -- L6: 4色，隐藏6个
    { type="generated", colorCount=4, emptyPegs=2, lockedGroups=0, hiddenGears=6 },
    -- L7: 4色+锁定，隐藏3个
    { type="generated", colorCount=4, emptyPegs=2, lockedGroups=1, hiddenGears=3 },

    -- ========== 阶段五：5色（L8-L10）==========
    -- L8: 5色，隐藏3个
    { type="generated", colorCount=5, emptyPegs=2, lockedGroups=0, hiddenGears=3 },
    -- L9: 5色+锁定，隐藏6个
    { type="generated", colorCount=5, emptyPegs=2, lockedGroups=1, hiddenGears=6 },
    -- L10: 5色，隐藏9个
    { type="generated", colorCount=5, emptyPegs=2, lockedGroups=0, hiddenGears=9 },

    -- ========== 阶段六：6色（L11-L13）==========
    -- L11: 6色+锁定，隐藏3个
    { type="generated", colorCount=6, emptyPegs=2, lockedGroups=1, hiddenGears=3 },
    -- L12: 6色，隐藏6个
    { type="generated", colorCount=6, emptyPegs=2, lockedGroups=0, hiddenGears=6 },
    -- L13: 6色+locked 2，无隐藏
    { type="generated", colorCount=6, emptyPegs=2, lockedGroups=2, hiddenGears=0 },

    -- ========== 阶段七：7色（L14-L16）==========
    -- L14: 7色，隐藏9个 + 临时插板
    { type="generated", colorCount=7, emptyPegs=2, lockedGroups=0, hiddenGears=9, tempPeg=1 },
    -- L15: 7色，隐藏6个 + 临时插板
    { type="generated", colorCount=7, emptyPegs=2, lockedGroups=0, hiddenGears=6, tempPeg=1 },
    -- L16: 7色+locked 2，无隐藏 + 临时插板
    { type="generated", colorCount=7, emptyPegs=2, lockedGroups=2, hiddenGears=0, tempPeg=1 },

    -- ========== 阶段八：8色（L17-L19）==========
    -- L17: 8色+锁定，隐藏3个 + 临时插板
    { type="generated", colorCount=8, emptyPegs=2, lockedGroups=1, hiddenGears=3, tempPeg=1 },
    -- L18: 8色，隐藏6个 + 临时插板
    { type="generated", colorCount=8, emptyPegs=2, lockedGroups=0, hiddenGears=6, tempPeg=1 },
    -- L19: 8色+锁定，隐藏6个 + 临时插板
    { type="generated", colorCount=8, emptyPegs=2, lockedGroups=1, hiddenGears=6, tempPeg=1 },

    -- ========== 阶段九：9色（L20-L22）==========
    -- L20: 9色+locked 2，隐藏3个 + 临时插板
    { type="generated", colorCount=9, emptyPegs=2, lockedGroups=2, hiddenGears=3, tempPeg=1 },
    -- L21: 9色，隐藏9个 + 临时插板
    { type="generated", colorCount=9, emptyPegs=2, lockedGroups=0, hiddenGears=9, tempPeg=1 },
    -- L22: 9色+locked 2，隐藏3个 + 临时插板
    { type="generated", colorCount=9, emptyPegs=2, lockedGroups=2, hiddenGears=3, tempPeg=1 },

    -- ========== 阶段十：10色（L23-L28）==========
    -- L23: 10色，隐藏6个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=6, tempPeg=1 },
    -- L24: 10色，隐藏9个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=9, tempPeg=1 },
    -- L25: 10色+locked 2，无隐藏 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=0, tempPeg=1 },
    -- L26: 10色，隐藏15个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=15, tempPeg=1 },
    -- L27: 10色+locked 2，隐藏6个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=6, tempPeg=1 },
    -- L28: 10色，隐藏9个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=9, tempPeg=1 },

    -- ========== 阶段十一：10色+sink 引入（L29-L34）==========
    -- L29: 10色+locked 2，sink×1 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=0, sinkPegs=1, tempPeg=1 },
    -- L30: 10色+锁定，隐藏3个 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=1, hiddenGears=3, tempPeg=1 },
    -- L31: 10色+locked 2，sink×1 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=0, sinkPegs=1, tempPeg=1 },
    -- L32: 10色，隐藏6个+sink×1 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=6, sinkPegs=1, tempPeg=1 },
    -- L33: 10色+锁定，隐藏6个+sink×1 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=1, hiddenGears=6, sinkPegs=1, tempPeg=1 },
    -- L34: 10色+locked 2，隐藏6个+sink×1 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=6, sinkPegs=1, tempPeg=1 },
    -- L35: 10色+locked 2，无隐藏+sink×1（sink 首次引入）→ 14 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=0, sinkPegs=1, tempPeg=1 },
    -- L36: 10色+locked 1，隐藏3个 → 13 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=1, hiddenGears=3, tempPeg=1 },

    -- ========== 阶段十二：终极阶段（L37-L40）==========
    -- L37: 10色+locked 2，sink×1（纯锁+sink，无hidden）→ 14 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=0, sinkPegs=1, tempPeg=1 },
    -- L38: 10色，隐藏6个+sink×1 → 12 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=0, hiddenGears=6, sinkPegs=1, tempPeg=1 },
    -- L39: 10色+locked 1，隐藏6个+sink×1 → 13 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=1, hiddenGears=6, sinkPegs=1, tempPeg=1 },
    -- L40: 10色+locked 2，隐藏7个+sink×1（最终关，最高难度）→ 14 插板 + 临时插板
    { type="generated", colorCount=10, emptyPegs=2, lockedGroups=2, hiddenGears=7, sinkPegs=1, tempPeg=1 },
}

-- ---------------------------------------------------------------
-- 深拷贝关卡数据（重置时使用）
-- 对于 type="generated" 的关卡，首次调用时生成布局并缓存，后续从缓存深拷贝
-- ---------------------------------------------------------------
function Levels.Clone(levelIndex)
    -- 超出配置范围时，使用最后一关的配置（关卡数可无限增长）
    local dataIndex = math.min(levelIndex, #Levels.data)
    local src = Levels.data[dataIndex]

    if src.type == "manual" then
        -- 手写关卡：直接深拷贝，不经过生成器
        local result = {
            pegs     = {},
            capacity = src.capacity or 4,
            locks    = {},
            sinks    = {},
        }
        for i, peg in ipairs(src.pegs) do
            result.pegs[i] = {}
            for j, color in ipairs(peg) do
                result.pegs[i][j] = color
            end
        end
        if src.locks then
            for k, v in pairs(src.locks) do result.locks[k] = v end
        end
        if src.sinks then
            for k, v in pairs(src.sinks) do result.sinks[k] = v end
        end
        return result
    end

    if src.type == "generated" then
        src = LevelGenerator.Generate(src)
    end

    local result = {
        pegs     = {},
        capacity = src.capacity,
        locks    = {},
        sinks    = {},
    }
    for i, peg in ipairs(src.pegs) do
        result.pegs[i] = {}
        for j, color in ipairs(peg) do
            result.pegs[i][j] = color
        end
    end
    if src.locks then
        for k, v in pairs(src.locks) do
            result.locks[k] = v
        end
    end
    if src.sinks then
        for k, v in pairs(src.sinks) do
            result.sinks[k] = v
        end
    end

    -- 超出配置范围时（无限关卡），对最后一关配置进行随机变化
    if levelIndex > #Levels.data then
        local roll = math.random()
        if roll < 0.40 then
            -- 40% 概率：删除一个只进不出插板，变为普通空白插板
            local sinkKeys = {}
            for k in pairs(result.sinks) do
                sinkKeys[#sinkKeys + 1] = k
            end
            if #sinkKeys > 0 then
                local removeIdx = sinkKeys[math.random(#sinkKeys)]
                result.sinks[removeIdx] = nil
                --print(string.format("[Levels] 无限关卡随机变化：移除只进不出插板 #%d，变为空白插板", removeIdx))
            end
        elseif roll < 0.75 then
            -- 35% 概率：删除1格临时插板，变为一个普通空白插板
            result.noTempPeg = true
            result.pegs[#result.pegs + 1] = {}
            --print("[Levels] 无限关卡随机变化：移除1格临时插板，替换为普通空白插板")
        else
            -- 25% 概率：维持不变
            --print("[Levels] 无限关卡随机变化：维持原配置不变")
        end
    end

    return result
end

-- 清除指定关卡的缓存（下次进入时重新随机生成）
function Levels.ClearCache(levelIndex)
    if levelIndex then
        Levels._cache[levelIndex] = nil
    else
        Levels._cache = {}
    end
end

function Levels.Count()
    return #Levels.data
end

-- 返回关卡的颜色数（用于星级计算）
function Levels.GetColorCount(levelIndex)
    local dataIndex = math.min(levelIndex, #Levels.data)
    local src = Levels.data[dataIndex]
    if not src then return 3 end
    return src.colorCount or 3
end

return Levels
