-- save_manager.lua
-- 云存档管理：通关记录、金币、连胜、签到
--
-- 存档结构（存储在 clientCloud key="save_data"）：
-- {
--   version        = 1,
--   unlocked       = 5,
--   levels         = { ["1"] = { bestMoves = 8 }, ... },
--   coins          = 0,
--   winStreak      = 0,
--   lastCheckInDay = "",
-- }

local SaveManager = {}

-- ---------------------------------------------------------------
-- 测试开关
-- ---------------------------------------------------------------
local DEV_UNLOCK_ALL = false

local CLOUD_KEY = "save_data"
local SAVE_VER  = 1

-- 内存中的存档数据（始终作为读取源头）
local data_ = nil

-- 云存档是否已加载完成
local loaded_ = false

-- 会话级 lastLevel
local sessionLastLevel_ = nil

-- ---------------------------------------------------------------
-- 默认存档
-- ---------------------------------------------------------------
local function newSave()
    return {
        version        = SAVE_VER,
        unlocked       = 1,
        levels         = {},
        coins          = 0,
        winStreak      = 0,
        lastCheckInDay = "",
        -- 道具库存
        undoCount      = 0,
        tempHubCount   = 0,
        -- 任务系统：累计通关关卡数（循环计数用于判断领取进度）
        taskClearedTotal = 0,   -- 历史总通关次数（含重复）
        taskUndoClaimed  = 0,   -- 已领取的撤回奖励轮次（每5关一次）
        taskHubClaimed   = 0,   -- 已领取的插板奖励轮次（每10关一次）
    }
end

-- ---------------------------------------------------------------
-- 兼容旧存档字段
-- ---------------------------------------------------------------
local function migrate(d)
    if not d.levels            then d.levels            = {} end
    if not d.winStreak         then d.winStreak         = 0  end
    if not d.lastCheckInDay    then d.lastCheckInDay    = "" end
    if not d.coins             then d.coins             = 0  end
    if not d.undoCount         then d.undoCount         = 0  end
    if not d.tempHubCount      then d.tempHubCount      = 0  end
    if not d.taskClearedTotal  then d.taskClearedTotal  = 0  end
    if not d.taskUndoClaimed   then d.taskUndoClaimed   = 0  end
    if not d.taskHubClaimed    then d.taskHubClaimed    = 0  end
    return d
end

-- ---------------------------------------------------------------
-- 确保 data_ 已初始化（同步兜底，云加载完成前用默认值）
-- ---------------------------------------------------------------
local function ensureData()
    if not data_ then
        data_ = newSave()
    end
end

-- ---------------------------------------------------------------
-- 异步加载云存档（游戏启动时调用一次）
-- onDone(success) 在加载完成后回调
-- ---------------------------------------------------------------
function SaveManager.LoadAsync(onDone)
    data_   = newSave()   -- 先用默认值，加载完成后替换
    loaded_ = false

    clientCloud:Get(CLOUD_KEY, {
        ok = function(values, iscores)
            local saved = values and values[CLOUD_KEY]
            if saved and type(saved) == "table" and saved.version then
                data_ = migrate(saved)
                --print(string.format("[SaveManager] 云存档加载成功，已解锁到第 %d 关", data_.unlocked or 1))
            else
                data_ = newSave()
                --print("[SaveManager] 无云存档，使用初始数据")
            end
            loaded_ = true
            if onDone then onDone(true) end
        end,
        error = function(code, reason)
            --print(string.format("[SaveManager] 云存档读取失败 (code=%s): %s", tostring(code), tostring(reason)))
            data_   = newSave()
            loaded_ = true
            if onDone then onDone(false) end
        end,
        timeout = function()
            --print("[SaveManager] 云存档读取超时，使用本地默认值")
            data_   = newSave()
            loaded_ = true
            if onDone then onDone(false) end
        end,
    })
end

-- ---------------------------------------------------------------
-- 同步接口兼容（供旧调用点使用，云加载完成前返回默认值）
-- ---------------------------------------------------------------
function SaveManager.Load()
    ensureData()
end

-- ---------------------------------------------------------------
-- 写入云存档（异步，fire-and-forget）
-- ---------------------------------------------------------------
function SaveManager.Save()
    if not data_ then return end

    clientCloud:Set(CLOUD_KEY, data_, {
        ok = function()
            --print(string.format("[SaveManager] 云存档已写入，已解锁第 %d 关", data_.unlocked or 1))
        end,
        error = function(code, reason)
            --print(string.format("[SaveManager] 云存档写入失败 (code=%s): %s", tostring(code), tostring(reason)))
        end,
        timeout = function()
            --print("[SaveManager] 云存档写入超时")
        end,
    })
end

-- ---------------------------------------------------------------
-- RecordClear 兼容接口（已废弃，转发到 RecordWin）
-- ---------------------------------------------------------------
function SaveManager.RecordClear(levelIndex, moves)
    --print("[SaveManager] WARNING: RecordClear 已废弃，请改用 RecordWin")
    SaveManager.RecordWin(levelIndex, moves)
end

-- ---------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------

function SaveManager.IsCleared(levelIndex)
    ensureData()
    return data_.levels[tostring(levelIndex)] ~= nil
end

function SaveManager.GetBestMoves(levelIndex)
    ensureData()
    local entry = data_.levels[tostring(levelIndex)]
    return entry and entry.bestMoves or nil
end

function SaveManager.GetUnlocked()
    if DEV_UNLOCK_ALL then return 99999 end
    ensureData()
    return data_.unlocked or 1
end

function SaveManager.SetLastLevel(levelIndex)
    sessionLastLevel_ = levelIndex
    ensureData()
    data_.lastLevel = levelIndex
    SaveManager.Save()
end

function SaveManager.GetLastLevel()
    if sessionLastLevel_ then return sessionLastLevel_ end
    ensureData()
    return data_.lastLevel or 1
end

function SaveManager.GetClearedCount()
    ensureData()
    local count = 0
    for _ in pairs(data_.levels) do count = count + 1 end
    return count
end

-- ---------------------------------------------------------------
-- 金币管理
-- ---------------------------------------------------------------

function SaveManager.GetCoins()
    ensureData()
    return data_.coins or 0
end

function SaveManager.SpendCoins(amount)
    ensureData()
    local coins = data_.coins or 0
    if coins < amount then
        --print(string.format("[SaveManager] 金币不足：需要 %d，现有 %d", amount, coins))
        return false
    end
    data_.coins = coins - amount
    SaveManager.Save()
    --print(string.format("[SaveManager] 消耗金币 %d，剩余 %d", amount, data_.coins))
    return true
end

function SaveManager.AddCoins(amount)
    ensureData()
    data_.coins = (data_.coins or 0) + amount
    SaveManager.Save()
    --print(string.format("[SaveManager] 获得金币 %d，当前 %d", amount, data_.coins))
end

-- ---------------------------------------------------------------
-- 连胜系统
-- ---------------------------------------------------------------

local STREAK_MULTIPLIERS = { 1.0, 2.0, 5.0, 10.0, 15.0 }

function SaveManager.GetWinStreak()
    ensureData()
    return data_.winStreak or 0
end

function SaveManager.GetStreakMultiplier()
    local streak = SaveManager.GetWinStreak()
    local idx = math.min(math.max(streak, 0) + 1, #STREAK_MULTIPLIERS)
    return STREAK_MULTIPLIERS[idx]
end

function SaveManager.CalcWinCoins()
    local BASE = 10
    return math.floor(BASE * SaveManager.GetStreakMultiplier())
end

function SaveManager.RecordWin(levelIndex, moves)
    ensureData()

    local entry = data_.levels[tostring(levelIndex)]
    if not entry then
        data_.levels[tostring(levelIndex)] = { bestMoves = moves }
    else
        if moves < entry.bestMoves then
            entry.bestMoves = moves
        end
    end

    local nextUnlock = levelIndex + 1
    if nextUnlock > (data_.unlocked or 1) then
        data_.unlocked = nextUnlock
    end

    local multiplierUsed = SaveManager.GetStreakMultiplier()
    local coins = SaveManager.CalcWinCoins()

    data_.winStreak = (data_.winStreak or 0) + 1
    data_.coins     = (data_.coins or 0) + coins

    SaveManager.Save()
    --print(string.format("[SaveManager] 通关关卡%d：%d步，连胜%d，获得金币%d（倍率×%.1f）",
    --    levelIndex, moves, data_.winStreak, coins, multiplierUsed))
    return coins
end

function SaveManager.ResetWinStreak()
    ensureData()
    data_.winStreak = 0
    SaveManager.Save()
    --print("[SaveManager] 连胜已重置")
end

-- ---------------------------------------------------------------
-- 每日签到系统
-- ---------------------------------------------------------------

local CHECK_IN_COINS = 50

local function todayStr()
    local t = os.date("*t")
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function SaveManager.HasCheckedInToday()
    ensureData()
    return (data_.lastCheckInDay or "") == todayStr()
end

function SaveManager.DoCheckIn()
    ensureData()
    if SaveManager.HasCheckedInToday() then
        --print("[SaveManager] 今日已签到")
        return 0
    end
    data_.lastCheckInDay = todayStr()
    data_.coins = (data_.coins or 0) + CHECK_IN_COINS
    SaveManager.Save()
    --print(string.format("[SaveManager] 签到成功，获得 %d 金币，当前 %d", CHECK_IN_COINS, data_.coins))
    return CHECK_IN_COINS
end

function SaveManager.GetCheckInReward()
    return CHECK_IN_COINS
end

-- ---------------------------------------------------------------
-- 道具库存
-- ---------------------------------------------------------------

function SaveManager.GetUndoCount()
    ensureData()
    return data_.undoCount or 0
end

function SaveManager.GetTempHubCount()
    ensureData()
    return data_.tempHubCount or 0
end

function SaveManager.AddUndoCount(n)
    ensureData()
    data_.undoCount = (data_.undoCount or 0) + (n or 1)
    SaveManager.Save()
end

function SaveManager.AddTempHubCount(n)
    ensureData()
    data_.tempHubCount = (data_.tempHubCount or 0) + (n or 1)
    SaveManager.Save()
end

--- 消耗一个撤回道具，返回是否成功
function SaveManager.UseUndo()
    ensureData()
    if (data_.undoCount or 0) <= 0 then return false end
    data_.undoCount = data_.undoCount - 1
    SaveManager.Save()
    return true
end

--- 消耗一个插板道具，返回是否成功
function SaveManager.UseTempHub()
    ensureData()
    if (data_.tempHubCount or 0) <= 0 then return false end
    data_.tempHubCount = data_.tempHubCount - 1
    SaveManager.Save()
    return true
end

-- ---------------------------------------------------------------
-- 任务系统
-- UNDO_TASK_INTERVAL  = 5  → 每通关5关，可领1个撤回道具
-- HUB_TASK_INTERVAL   = 10 → 每通关10关，可领1个插板道具
-- ---------------------------------------------------------------

local UNDO_TASK_INTERVAL = 5
local HUB_TASK_INTERVAL  = 10

--- 通关时累加总通关计数（在 RecordWin 之后由任务系统调用）
function SaveManager.IncrTaskCleared()
    ensureData()
    data_.taskClearedTotal = (data_.taskClearedTotal or 0) + 1
    SaveManager.Save()
end

--- 获取总通关计数
function SaveManager.GetTaskClearedTotal()
    ensureData()
    return data_.taskClearedTotal or 0
end

--- 撤回任务：当前可领取轮次（= floor(total/5)），已领 taskUndoClaimed 轮
--- 返回可领取数量（0 表示没得领）
function SaveManager.GetTaskUndoClaimable()
    ensureData()
    local total    = data_.taskClearedTotal or 0
    local earned   = math.floor(total / UNDO_TASK_INTERVAL)
    local claimed  = data_.taskUndoClaimed or 0
    return math.max(0, earned - claimed)
end

--- 插板任务：类似
function SaveManager.GetTaskHubClaimable()
    ensureData()
    local total    = data_.taskClearedTotal or 0
    local earned   = math.floor(total / HUB_TASK_INTERVAL)
    local claimed  = data_.taskHubClaimed or 0
    return math.max(0, earned - claimed)
end

--- 领取一次撤回奖励（自动写入库存）
function SaveManager.ClaimTaskUndo()
    if SaveManager.GetTaskUndoClaimable() <= 0 then return false end
    ensureData()
    data_.taskUndoClaimed = (data_.taskUndoClaimed or 0) + 1
    data_.undoCount       = (data_.undoCount or 0) + 1
    SaveManager.Save()
    --print(string.format("[SaveManager] 领取撤回道具，库存 %d", data_.undoCount))
    return true
end

--- 领取一次插板奖励（自动写入库存）
function SaveManager.ClaimTaskHub()
    if SaveManager.GetTaskHubClaimable() <= 0 then return false end
    ensureData()
    data_.taskHubClaimed  = (data_.taskHubClaimed or 0) + 1
    data_.tempHubCount    = (data_.tempHubCount or 0) + 1
    SaveManager.Save()
    --print(string.format("[SaveManager] 领取插板道具，库存 %d", data_.tempHubCount))
    return true
end

--- 撤回任务进度（当前周期内完成关卡数 / 5）
function SaveManager.GetTaskUndoProgress()
    ensureData()
    local total   = data_.taskClearedTotal or 0
    local claimed = data_.taskUndoClaimed  or 0
    local base    = claimed * UNDO_TASK_INTERVAL
    local progress = total - base
    return math.min(progress, UNDO_TASK_INTERVAL), UNDO_TASK_INTERVAL
end

--- 插板任务进度（当前周期内完成关卡数 / 10）
function SaveManager.GetTaskHubProgress()
    ensureData()
    local total   = data_.taskClearedTotal or 0
    local claimed = data_.taskHubClaimed   or 0
    local base    = claimed * HUB_TASK_INTERVAL
    local progress = total - base
    return math.min(progress, HUB_TASK_INTERVAL), HUB_TASK_INTERVAL
end

return SaveManager
