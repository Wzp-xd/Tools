-- game_state.lua
-- 插板状态管理、合法性判断、撤销栈

local Levels = require("levels")

local GameState = {}

-- ---------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------
local pegs_       = {}   -- 当前插板状态（二维数组，1=底部）
local capacity_   = 4
local history_    = {}   -- 撤销栈，每项 { from, to, count, unlocked }
local moveCount_  = 0
local levelIndex_ = 1
local solved_     = false
local lockedPegs_ = {}   -- [pegIdx] = "colorName"：插板锁定状态（完成对应颜色后解锁）
local sinkPegs_   = {}   -- [pegIdx] = true：只进不出插板（空插板专属，齿轮只能放入不能取出）
local extraPegUsed_ = false  -- 本关是否已使用过加板道具
local adContinueUsed_ = false  -- 本关是否已使用过广告续命

-- 临时插板（容量=1，本局有效，可存在多个）
local tempPegSet_   = {}     -- [pegIdx] = true：所有临时插板下标集合

-- ---------------------------------------------------------------
-- 隐藏齿轮辅助
-- ---------------------------------------------------------------
-- 剥离 "hidden_" 前缀，返回实际颜色名（如 "hidden_red" → "red"）
local function actualColor(c)
    if c and c:sub(1, 7) == "hidden_" then
        return c:sub(8)
    end
    return c
end

-- ---------------------------------------------------------------
-- 锁定插板辅助
-- ---------------------------------------------------------------

-- 检查是否有插板因完成条件满足而应解锁；返回本次解锁列表 { {pegIdx, color}, ... }
local function checkUnlocks()
    local justUnlocked = {}
    for pegIdx, requiredColor in pairs(lockedPegs_) do
        for i, peg in ipairs(pegs_) do
            -- 找到一根已完成且实际颜色匹配的插板
            if #peg > 0 and GameState.IsPegCompleted(i) and actualColor(peg[1]) == requiredColor then
                justUnlocked[#justUnlocked + 1] = { pegIdx = pegIdx, color = requiredColor }
                break
            end
        end
    end
    -- 执行解锁
    for _, u in ipairs(justUnlocked) do
        lockedPegs_[u.pegIdx] = nil
        -- 解锁后若新顶部是隐藏齿轮，立即显示（安全措施）
        local peg = pegs_[u.pegIdx]
        if #peg > 0 and GameState.IsHiddenGear(peg[#peg]) then
            peg[#peg] = actualColor(peg[#peg])
        end
        --print(string.format("[GameState] 插板 %d 已解锁（需要颜色：%s）", u.pegIdx, u.color))
    end
    return justUnlocked
end

-- ---------------------------------------------------------------
-- 初始化 / 重置
-- ---------------------------------------------------------------
function GameState.LoadLevel(index)
    local data    = Levels.Clone(index)
    pegs_         = data.pegs
    capacity_     = data.capacity
    history_      = {}
    moveCount_    = 0
    levelIndex_   = index
    solved_       = false
    -- 初始化锁定插板
    lockedPegs_   = {}
    if data.locks then
        for k, v in pairs(data.locks) do
            lockedPegs_[k] = v
        end
    end
    -- 初始化只进不出插板
    sinkPegs_ = {}
    if data.sinks then
        for k, v in pairs(data.sinks) do
            sinkPegs_[k] = v
        end
    end
    -- 重置加板道具
    extraPegUsed_ = false
    -- 重置广告续命
    adContinueUsed_ = false
    -- 重置临时插板集合
    tempPegSet_ = {}
    -- 关卡自带临时插板（从 L20 开始每关默认一个）
    -- 若 Levels.Clone 标记了 noTempPeg（无限关卡随机变化），则跳过
    local src = Levels.data[math.min(index, #Levels.data)]
    if not data.noTempPeg and src and src.tempPeg and src.tempPeg > 0 then
        pegs_[#pegs_ + 1] = {}
        tempPegSet_[#pegs_] = true
        --print(string.format("[GameState] 关卡 %d 自带临时插板，下标 %d", index, #pegs_))
    end
    -- 安全措施：若未锁定插板顶部即为隐藏齿轮的情况，直接显示
    -- 锁定插板内的隐藏齿轮保持原样（解锁后若顶部是隐藏齿轮再处理）
    -- （正常关卡不应出现此情况，仅作防御性处理）
    for idx, peg in ipairs(pegs_) do
        if #peg > 0 and not lockedPegs_[idx] then
            if peg[#peg]:sub(1, 7) == "hidden_" then
                peg[#peg] = peg[#peg]:sub(8)
            end
        end
    end
    --print(string.format("[GameState] 加载关卡 %d，共 %d 根插板", index, #pegs_))
end

function GameState.Reset()
    GameState.LoadLevel(levelIndex_)
end

-- ---------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------
function GameState.GetPegs()
    return pegs_
end

function GameState.GetCapacity()
    return capacity_
end

function GameState.GetMoveCount()
    return moveCount_
end

function GameState.GetLevelIndex()
    return levelIndex_
end

function GameState.IsSolved()
    return solved_
end

function GameState.PegCount()
    return #pegs_
end

-- 对外暴露隐藏齿轮辅助（renderer 等模块使用）
function GameState.ActualColor(c)
    return actualColor(c)
end

function GameState.IsHiddenGear(c)
    return c ~= nil and c:sub(1, 7) == "hidden_"
end

-- 锁定插板查询接口
function GameState.IsPegLocked(pegIdx)
    return lockedPegs_[pegIdx] ~= nil
end

function GameState.GetUnlockColor(pegIdx)
    return lockedPegs_[pegIdx]
end

function GameState.GetLockedPegs()
    return lockedPegs_
end

-- 只进不出插板查询接口
function GameState.IsPegSink(pegIdx)
    return sinkPegs_[pegIdx] == true
end

-- 判断某根插板是否已完成（插满且全部实际颜色相同）
-- 临时插板（容量=1）装满1个即为"满"，但不视为完成，以便胜利检查时要求清空
-- hidden_red 与 red 视为同色
function GameState.IsPegCompleted(pegIdx)
    -- 临时插板：永远不算"完成"（不会产生封盖动画，胜利要求它为空）
    if tempPegSet_[pegIdx] then return false end
    local peg = pegs_[pegIdx]
    if #peg ~= capacity_ then return false end
    local color = actualColor(peg[1])
    for _, c in ipairs(peg) do
        if actualColor(c) ~= color then return false end
    end
    return true
end

-- 取某根插板顶部实际颜色（若空返回 nil，去掉 hidden_ 前缀）
function GameState.TopColor(pegIdx)
    local peg = pegs_[pegIdx]
    if #peg == 0 then return nil end
    return actualColor(peg[#peg])
end

-- 取顶部连续同色（按实际颜色）的齿轮数量
-- 规则：隐藏齿轮在非顶部位置时不可操作，计数到此终止
-- （若隐藏齿轮恰好已是顶部，说明已经被显示/转换，正常计入）
function GameState.TopGroupCount(pegIdx)
    local peg = pegs_[pegIdx]
    if #peg == 0 then return 0 end
    local color = actualColor(peg[#peg])
    local count = 0
    for i = #peg, 1, -1 do
        -- 非顶部位置遇到隐藏齿轮：立即停止（不可被操作）
        if i < #peg and GameState.IsHiddenGear(peg[i]) then break end
        if actualColor(peg[i]) == color then
            count = count + 1
        else
            break
        end
    end
    return count
end

-- ---------------------------------------------------------------
-- 合法性判断
-- ---------------------------------------------------------------
function GameState.CanMove(fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    -- 锁定插板不可操作（既不能作为来源，也不能作为目标）
    if lockedPegs_[fromIdx] then return false end
    if lockedPegs_[toIdx]   then return false end
    -- 只进不出插板：不能作为移动来源（可以作为目标）
    if sinkPegs_[fromIdx] then return false end
    local from = pegs_[fromIdx]
    local to   = pegs_[toIdx]
    if #from == 0 then return false end                   -- 源为空
    if GameState.IsPegCompleted(fromIdx) then return false end  -- 源已完成，锁定
    if GameState.IsPegCompleted(toIdx)   then return false end  -- 目标已完成，锁定
    -- 使用每根插板的独立容量（临时插板容量为1）
    local toCap = GameState.GetPegCapacity(toIdx)
    if #to >= toCap then return false end                 -- 目标已满

    local movingColor = actualColor(from[#from])          -- 用实际颜色比较（剥离 hidden_ 前缀）
    local topTo       = to[#to]
    -- 目标为空，或目标顶部实际颜色相同
    return topTo == nil or actualColor(topTo) == movingColor
end

-- 检查从 fromIdx 到 toIdx 是否可以「完全移动」：
-- 即将 fromIdx 顶部连续同色齿轮全部移入 toIdx（目标空位 >= 可移动数量）
-- 前提：CanMove(fromIdx, toIdx) == true
function GameState.CanFullMove(fromIdx, toIdx)
    if not GameState.CanMove(fromIdx, toIdx) then return false end
    local to    = pegs_[toIdx]
    local toCap = GameState.GetPegCapacity(toIdx)
    local space = toCap - #to
    local group = GameState.TopGroupCount(fromIdx)
    return space >= group
end

-- 检查当前局面是否还有任意「完全移动」
-- 只有存在至少一个完全移动时，才认为局面未死锁
function GameState.HasAnyMove()
    for fi = 1, #pegs_ do
        for ti = 1, #pegs_ do
            if GameState.CanFullMove(fi, ti) then
                return true
            end
        end
    end
    return false
end

-- 返回所有可接受 fromIdx 顶部颜色的目标插板下标列表
function GameState.ValidTargets(fromIdx)
    local targets = {}
    for i = 1, #pegs_ do
        if GameState.CanMove(fromIdx, i) then
            targets[#targets + 1] = i
        end
    end
    return targets
end

-- ---------------------------------------------------------------
-- 执行移动（连续同色整组）
-- ---------------------------------------------------------------
function GameState.Move(fromIdx, toIdx)
    if not GameState.CanMove(fromIdx, toIdx) then
        return false
    end

    local from  = pegs_[fromIdx]
    local to    = pegs_[toIdx]
    local color = from[#from]
    local toCap = GameState.GetPegCapacity(toIdx)
    local space = toCap - #to

    -- 计算实际可移动数量（受目标空位限制）
    local groupSize = GameState.TopGroupCount(fromIdx)
    local count     = math.min(groupSize, space)

    -- 记录撤销历史（先占位，移动后填入解锁和显示列表）
    local histEntry = { from = fromIdx, to = toIdx, count = count, unlocked = {}, revealed = {} }
    history_[#history_ + 1] = histEntry

    -- 执行移动
    for _ = 1, count do
        local gear = table.remove(from)    -- 从顶部弹出
        table.insert(to, gear)             -- 推入目标顶部
    end

    -- 移动后：若 from 插板新顶部是隐藏齿轮，立即将其转为普通齿轮（显示颜色）
    -- 记入 histEntry.revealed，供 Undo 还原为 hidden_X 状态
    if #from > 0 and GameState.IsHiddenGear(from[#from]) then
        local hiddenColor = from[#from]
        from[#from] = actualColor(hiddenColor)   -- 去掉 hidden_ 前缀
        histEntry.revealed[#histEntry.revealed + 1] = {
            pegIdx    = fromIdx,
            slotIdx   = #from,
            hiddenColor = hiddenColor,
        }
        --print(string.format("[GameState] 插板 %d 第 %d 格隐藏齿轮已显示：%s",
        --    fromIdx, #from, actualColor(hiddenColor)))
    end

    -- 检查并执行解锁，结果存入历史（支持 Undo 重新锁定）
    histEntry.unlocked = checkUnlocks()

    moveCount_ = moveCount_ + 1
    GameState.CheckSolved()
    return true
end

-- ---------------------------------------------------------------
-- 是否有可撤销的操作
-- ---------------------------------------------------------------
function GameState.CanUndo()
    return #history_ > 0
end

-- 撤销
-- ---------------------------------------------------------------
function GameState.Undo()
    if #history_ == 0 then return false end
    local last = table.remove(history_)
    local from = pegs_[last.from]
    local to   = pegs_[last.to]

    -- 先还原因本次移动而显示的隐藏齿轮（在齿轮移回之前还原，保证索引正确）
    for _, r in ipairs(last.revealed or {}) do
        pegs_[r.pegIdx][r.slotIdx] = r.hiddenColor
    end

    -- 将 last.count 个齿轮从 to 移回 from
    for _ = 1, last.count do
        local gear = table.remove(to)
        table.insert(from, gear)
    end
    -- 撤销本次移动触发的解锁：重新锁定对应插板
    local relocked = {}
    for _, u in ipairs(last.unlocked or {}) do
        lockedPegs_[u.pegIdx] = u.color
        relocked[#relocked + 1] = u.pegIdx
    end
    moveCount_ = moveCount_ - 1
    solved_    = false
    return true, relocked
end

-- ---------------------------------------------------------------
-- 加板道具
-- ---------------------------------------------------------------

-- 是否可以使用加板（本关未使用过且游戏未结束）
function GameState.CanUseExtraPeg()
    return not extraPegUsed_ and not solved_
end

-- 使用加板：末尾追加一根空插板，返回新插板索引；失败返回 nil
function GameState.UseExtraPeg()
    if not GameState.CanUseExtraPeg() then return nil end
    extraPegUsed_ = true
    pegs_[#pegs_ + 1] = {}
    --print(string.format("[GameState] 加板道具已使用，当前插板数 %d", #pegs_))
    return #pegs_
end

function GameState.IsExtraPegUsed()
    return extraPegUsed_
end

-- ---------------------------------------------------------------
-- 广告续命（死锁时看广告增加一根空白插板继续游戏）
-- ---------------------------------------------------------------

function GameState.CanAdContinue()
    return not adContinueUsed_ and not solved_
end

-- 使用广告续命：末尾追加一根正常容量的空插板，返回新插板索引；失败返回 nil
function GameState.UseAdContinue()
    if not GameState.CanAdContinue() then return nil end
    adContinueUsed_ = true
    pegs_[#pegs_ + 1] = {}
    --print(string.format("[GameState] 广告续命已使用，新增空白插板，当前插板数 %d", #pegs_))
    return #pegs_
end

function GameState.IsAdContinueUsed()
    return adContinueUsed_
end

-- ---------------------------------------------------------------
-- 临时插板道具
-- ---------------------------------------------------------------

-- 获取指定插板的容量（临时插板容量为 1，其他插板为全局 capacity_）
function GameState.GetPegCapacity(pegIdx)
    if tempPegSet_[pegIdx] then
        return 1
    end
    return capacity_
end

-- 是否可以使用临时插板（无数量限制，只要游戏未结束即可）
function GameState.CanUseTempHub()
    return not solved_
end

-- 使用临时插板：末尾追加一根容量为 1 的空插板，返回新插板索引；失败返回 nil
function GameState.UseTempHub()
    if not GameState.CanUseTempHub() then return nil end
    pegs_[#pegs_ + 1] = {}
    local newIdx = #pegs_
    tempPegSet_[newIdx] = true
    --print(string.format("[GameState] 临时插板道具已使用，插板下标 %d（容量=1），当前临时插板总数 %d", newIdx, GameState.GetTempPegCount()))
    return newIdx
end

-- 获取当前临时插板数量
function GameState.GetTempPegCount()
    local count = 0
    for _ in pairs(tempPegSet_) do count = count + 1 end
    return count
end

-- 判断某插板是否是临时插板（用于渲染特殊样式）
function GameState.IsTempPeg(pegIdx)
    return tempPegSet_[pegIdx] == true
end

function GameState.GetTempPegIdx()
    -- 兼容：返回最后一个临时插板下标（多个时返回最大的）
    local maxIdx = nil
    for idx in pairs(tempPegSet_) do
        if not maxIdx or idx > maxIdx then maxIdx = idx end
    end
    return maxIdx
end

-- ---------------------------------------------------------------
-- 胜利判断
-- ---------------------------------------------------------------
function GameState.CheckSolved()
    -- 每根插板必须是「已完成（插满同色）」或「空」，否则未胜利
    -- 临时插板必须为空（不允许遗留齿轮）
    for i, peg in ipairs(pegs_) do
        if tempPegSet_[i] then
            -- 临时插板：必须为空才能通关
            if #peg ~= 0 then
                solved_ = false
                return
            end
        elseif #peg == 0 then
            -- 空插板合法，继续检查
        elseif GameState.IsPegCompleted(i) then
            -- 已完成插板合法，继续检查
        else
            -- 部分填充 / 颜色混杂 → 未胜利
            solved_ = false
            return
        end
    end
    solved_ = true
    --print(string.format("[GameState] 关卡 %d 通关！步数 %d", levelIndex_, moveCount_))
end

return GameState
