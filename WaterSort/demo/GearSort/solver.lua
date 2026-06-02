-- solver.lua
-- 自动提示：通过贪心启发式搜索找出当前最优一步移动
--
-- 策略（从高到低优先级）：
--   1. 可以让某根插板达到"完成状态"（插满同色）
--   2. 可以归纳同色到已有的同色组（巩固颜色）
--   3. 将顶色从"混杂插板"移到"空插板"（释放空间）
--
-- 返回 { from, to } 或 nil（无合法移动 / 已完成）

local GameState = require("game_state")

local Solver = {}

-- ---------------------------------------------------------------
-- 内部辅助
-- ---------------------------------------------------------------

-- 插板"同色纯净度"评分（越高越好）
-- 返回该插板底部连续同色数 / 总齿轮数
local function purityScore(pegIdx)
    local peg = GameState.GetPegs()[pegIdx]
    if #peg == 0 then return 0 end
    local topColor = GameState.ActualColor(peg[#peg])
    local count    = 0
    for i = #peg, 1, -1 do
        if GameState.ActualColor(peg[i]) == topColor then
            count = count + 1
        else
            break
        end
    end
    return count / #peg
end

-- 移动后目标插板是否会完成（插满且全色一致）
local function wouldComplete(fromIdx, toIdx)
    local pegs = GameState.GetPegs()
    local cap  = GameState.GetCapacity()
    local from = pegs[fromIdx]
    local to   = pegs[toIdx]

    local movingColor = GameState.ActualColor(from[#from])
    local count = GameState.TopGroupCount(fromIdx)
    local space = cap - #to

    -- 移动后 to 的新大小
    local newSize = #to + math.min(count, space)
    if newSize ~= cap then return false end

    -- 检查 to 中现有齿轮颜色是否全与 movingColor 相同
    for _, c in ipairs(to) do
        if GameState.ActualColor(c) ~= movingColor then return false end
    end
    return true
end

-- ---------------------------------------------------------------
-- 主接口：返回最优 { from, to } 或 nil
-- ---------------------------------------------------------------
function Solver.BestMove()
    if GameState.IsSolved() then return nil end

    local pegs = GameState.GetPegs()
    local n    = #pegs

    -- 候选移动列表，每项 { from, to, priority, score }
    -- priority: 3=完成插板，2=归纳同色，1=释放空间
    local candidates = {}

    for fi = 1, n do
        for ti = 1, n do
            if GameState.CanMove(fi, ti) then
                local priority = 1
                local score    = 0

                if wouldComplete(fi, ti) then
                    -- 最高优先：此移动能完成一根插板
                    priority = 3
                    score    = 100
                else
                    local toPeg = pegs[ti]
                    if #toPeg > 0 then
                        -- 目标非空：归纳同色组（同色巩固）
                        priority = 2
                        -- 分数：目标插板现有同色数越多越好
                        score = GameState.TopGroupCount(ti) * 10
                              + purityScore(ti) * 5
                    else
                        -- 目标为空：释放来源插板的上方空间
                        -- 只有当来源插板有两种颜色时才值得释放
                        local fromPeg = pegs[fi]
                        local hasBlock = false
                        local topColor = GameState.ActualColor(fromPeg[#fromPeg])
                        for _, c in ipairs(fromPeg) do
                            if GameState.ActualColor(c) ~= topColor then
                                hasBlock = true; break
                            end
                        end
                        if hasBlock then
                            priority = 1
                            score    = GameState.TopGroupCount(fi) * 3
                        else
                            -- 来源本来就是单色，移到空插板无意义（除非没有更好的选择）
                            priority = 0
                            score    = -10
                        end
                    end
                end

                candidates[#candidates + 1] = {
                    from = fi, to = ti,
                    priority = priority, score = score
                }
            end
        end
    end

    if #candidates == 0 then return nil end

    -- 按 priority 降序，同 priority 内按 score 降序
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.score > b.score
    end)

    local best = candidates[1]
    return { from = best.from, to = best.to }
end

return Solver
