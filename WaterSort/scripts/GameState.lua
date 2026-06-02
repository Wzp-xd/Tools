-- ============================================================
-- GameState.lua - 游戏状态管理与核心逻辑
-- 支持: 迷雾层 / 封印管 / 临时管 / 单向管
-- ============================================================

local Config = require("config")
local LevelGenerator = require("LevelGenerator")

local GameState = {}
GameState.__index = GameState

-- ============================================================
-- 颜色编码工具（迷雾层核心）
-- 正数 = 可见颜色, 负数 = 隐藏颜色(绝对值为真实色)
-- ============================================================

--- 判断颜色是否隐藏
---@param color integer
---@return boolean
function GameState.isHidden(color)
    return color < 0
end

--- 获取真实颜色值（去掉隐藏标记）
---@param color integer
---@return integer
function GameState.realColor(color)
    return math.abs(color)
end

-- ============================================================
-- 构造
-- ============================================================

--- 创建新的游戏状态实例
---@return table
function GameState.new()
    local self = setmetatable({}, GameState)
    self.tubes = {}
    self.tubeCount = 0
    self.colorCount = 0
    self.selectedTube = nil
    self.level = 1
    self.isWin = false
    self.undoStack = {}

    -- 进阶机制字段
    self.locks = {}       -- { [tubeIdx] = unlockColorIdx } 封印管解锁条件
    self.tempTubes = {}   -- { [tubeIdx] = capacity }       临时管容量
    self.sinkTubes = {}   -- { [tubeIdx] = true }           单向管标记

    -- 并发倒水：管级锁定
    self.sourceLocked = {}   -- { [tubeIdx] = true } 正在作为源瓶倒出
    self.receivingCount = {} -- { [tubeIdx] = int }  正在接收的动画数

    -- 揭雾事件队列（供动画系统消费）
    self.pendingReveals = {}  -- { tubeIdx1, tubeIdx2, ... }

    return self
end

-- ============================================================
-- 关卡加载
-- ============================================================

--- 加载关卡
---@param level integer
function GameState:loadLevel(level)
    local cfg = Config.getLevelConfig(level)
    self.level = level
    self.selectedTube = nil
    self.isWin = false
    self.undoStack = {}
    self.locks = {}
    self.tempTubes = {}
    self.sinkTubes = {}
    self.sourceLocked = {}
    self.receivingCount = {}
    self.pendingReveals = {}

    if cfg.type == "manual" and cfg.tubes_data then
        -- 手写关卡
        self.tubes = {}
        for i = 1, #cfg.tubes_data do
            self.tubes[i] = {}
            for j = 1, #cfg.tubes_data[i] do
                self.tubes[i][j] = cfg.tubes_data[i][j]
            end
        end
        self.tubeCount = #self.tubes
        self.colorCount = cfg.colors
    else
        -- 生成关卡
        local result = LevelGenerator.generateQuality(level, cfg)
        self.tubes = result.tubes
        self.tubeCount = result.tubeCount
        self.colorCount = cfg.colors
        self.locks = result.locks or {}
        self.tempTubes = result.tempTubes or {}
        self.sinkTubes = result.sinkTubes or {}
    end
end

-- ============================================================
-- 迷雾层揭开
-- ============================================================

--- 检查并揭开管顶的隐藏层（倒水后调用）
---@param tubeIdx integer
---@return boolean revealed 是否有层被揭开
function GameState:revealTopIfHidden(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return false end
    local top = tube[#tube]
    if GameState.isHidden(top) then
        tube[#tube] = GameState.realColor(top)
        table.insert(self.pendingReveals, tubeIdx)
        return true
    end
    return false
end

--- 消费一个待揭雾事件
---@return integer|nil tubeIdx
function GameState:popPendingReveal()
    if #self.pendingReveals > 0 then
        return table.remove(self.pendingReveals, 1)
    end
    return nil
end

-- ============================================================
-- 管类型判断
-- ============================================================

--- 判断是否封印管（锁定中）
---@param tubeIdx integer
---@return boolean
function GameState:isLocked(tubeIdx)
    return self.locks[tubeIdx] ~= nil
end

--- 判断是否临时管
---@param tubeIdx integer
---@return boolean
function GameState:isTempTube(tubeIdx)
    return self.tempTubes[tubeIdx] ~= nil
end

--- 获取临时管容量
---@param tubeIdx integer
---@return integer
function GameState:getTempCapacity(tubeIdx)
    return self.tempTubes[tubeIdx] or Config.tube.layerCount
end

--- 判断是否单向管
---@param tubeIdx integer
---@return boolean
function GameState:isSinkTube(tubeIdx)
    return self.sinkTubes[tubeIdx] == true
end

-- ============================================================
-- 核心游戏逻辑
-- ============================================================

--- 获取管顶颜色（隐藏层返回 nil，不可操作）
---@param tubeIdx integer
---@return integer|nil
function GameState:getTopColor(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return nil end
    local top = tube[#tube]
    if GameState.isHidden(top) then return nil end
    return top
end

--- 获取管顶真实颜色（即使隐藏也返回）
---@param tubeIdx integer
---@return integer|nil
function GameState:getTopRealColor(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return nil end
    return GameState.realColor(tube[#tube])
end

--- 获取管顶连续同色层数（遇到隐藏层停止）
---@param tubeIdx integer
---@return integer
function GameState:getTopConsecutiveCount(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return 0 end
    local top = tube[#tube]
    if GameState.isHidden(top) then return 0 end
    local topColor = top
    local count = 0
    for i = #tube, 1, -1 do
        if GameState.isHidden(tube[i]) then break end
        if tube[i] == topColor then
            count = count + 1
        else
            break
        end
    end
    return count
end

--- 判断管是否可选中（作为源）— 基础逻辑（不含并发锁检查）
---@param tubeIdx integer
---@return boolean
function GameState:canSelect(tubeIdx)
    if self:isLocked(tubeIdx) then return false end
    if self:isSinkTube(tubeIdx) then return false end
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return false end
    -- 管顶是隐藏层不可选
    if GameState.isHidden(tube[#tube]) then return false end
    return true
end

-- ============================================================
-- 并发倒水：管级锁定
-- ============================================================

--- 判断管是否可被选为源瓶（含并发锁检查）
---@param tubeIdx integer
---@return boolean
function GameState:canSelectAsSource(tubeIdx)
    if self.sourceLocked[tubeIdx] then return false end
    if (self.receivingCount[tubeIdx] or 0) > 0 then return false end
    return self:canSelect(tubeIdx)
end

--- 锁定源管
---@param tubeIdx integer
function GameState:lockSource(tubeIdx)
    self.sourceLocked[tubeIdx] = true
end

--- 解锁源管
---@param tubeIdx integer
function GameState:unlockSource(tubeIdx)
    self.sourceLocked[tubeIdx] = nil
end

--- 增加目标管接收计数
---@param tubeIdx integer
function GameState:addReceiving(tubeIdx)
    self.receivingCount[tubeIdx] = (self.receivingCount[tubeIdx] or 0) + 1
end

--- 减少目标管接收计数
---@param tubeIdx integer
function GameState:removeReceiving(tubeIdx)
    local c = (self.receivingCount[tubeIdx] or 0) - 1
    self.receivingCount[tubeIdx] = c > 0 and c or nil
end

--- 判断能否从 src 倒向 dst
---@param srcIdx integer
---@param dstIdx integer
---@return boolean
function GameState:canPour(srcIdx, dstIdx)
    if srcIdx == dstIdx then return false end
    -- 源管检查
    if self:isLocked(srcIdx) then return false end
    if self:isSinkTube(srcIdx) then return false end
    local src = self.tubes[srcIdx]
    if not src or #src == 0 then return false end
    local srcTop = src[#src]
    if GameState.isHidden(srcTop) then return false end
    -- 目标管检查
    if self:isLocked(dstIdx) then return false end
    -- 正在作为源瓶倒出的管子，必须等归位后才能作为目标
    if self.sourceLocked[dstIdx] then return false end
    local dst = self.tubes[dstIdx]
    if not dst then return false end
    -- 容量检查
    local maxCap = self:isTempTube(dstIdx) and self:getTempCapacity(dstIdx) or Config.tube.layerCount
    local dstSpace = maxCap - #dst
    if dstSpace <= 0 then return false end
    -- 颜色匹配
    if #dst > 0 then
        local dstTop = dst[#dst]
        -- 目标管顶如果是隐藏层，不可作为目标
        if GameState.isHidden(dstTop) then return false end
        if dstTop ~= srcTop then return false end
    end
    return true
end

--- 获取可倒层数
---@param srcIdx integer
---@param dstIdx integer
---@return integer
function GameState:getPourCount(srcIdx, dstIdx)
    local dst = self.tubes[dstIdx]
    local maxCap = self:isTempTube(dstIdx) and self:getTempCapacity(dstIdx) or Config.tube.layerCount
    local space = maxCap - #dst
    return math.min(self:getTopConsecutiveCount(srcIdx), space)
end

--- 检查是否有封印管需要解锁
---@return table|nil unlocked { tubeIdx, color } 或 nil
function GameState:checkUnlocks()
    if next(self.locks) == nil then return nil end
    local layerCount = Config.tube.layerCount
    -- 找到场上已完成纯色的颜色集合
    local completedColors = {}
    for i = 1, self.tubeCount do
        if not self:isTempTube(i) then
            local tube = self.tubes[i]
            if #tube == layerCount then
                local first = GameState.realColor(tube[1])
                local pure = true
                for j = 2, #tube do
                    if GameState.realColor(tube[j]) ~= first then pure = false; break end
                end
                if pure then
                    completedColors[first] = true
                end
            end
        end
    end
    -- 检查锁
    for tubeIdx, unlockColor in pairs(self.locks) do
        if completedColors[unlockColor] then
            self.locks[tubeIdx] = nil
            return { tubeIdx = tubeIdx, color = unlockColor }
        end
    end
    return nil
end

--- 检查是否通关
---@return boolean
function GameState:checkWin()
    local layerCount = Config.tube.layerCount
    local completedCount = 0

    for i = 1, self.tubeCount do
        local tube = self.tubes[i]
        -- 临时管必须为空
        if self:isTempTube(i) then
            if #tube > 0 then return false end
        elseif #tube == layerCount then
            local first = GameState.realColor(tube[1])
            local pure = true
            for j = 2, #tube do
                if GameState.realColor(tube[j]) ~= first then pure = false; break end
            end
            if pure then completedCount = completedCount + 1 end
        elseif #tube > 0 then
            return false
        end
    end

    return completedCount == self.colorCount
end

-- ============================================================
-- 状态操作
-- ============================================================

--- 保存撤销快照（含所有机制状态）
function GameState:saveUndoState()
    local snapshot = {
        tubes = {},
        locks = {},
        tempTubes = {},
        sinkTubes = {},
    }
    for i = 1, self.tubeCount do
        snapshot.tubes[i] = {}
        for j = 1, #self.tubes[i] do
            snapshot.tubes[i][j] = self.tubes[i][j]
        end
    end
    for k, v in pairs(self.locks) do snapshot.locks[k] = v end
    for k, v in pairs(self.tempTubes) do snapshot.tempTubes[k] = v end
    for k, v in pairs(self.sinkTubes) do snapshot.sinkTubes[k] = v end
    table.insert(self.undoStack, snapshot)
end

--- 撤销一步（有动画进行中时禁止）
---@param hasActiveAnims boolean 是否有正在进行的动画
---@return boolean 是否成功撤销
function GameState:undo(hasActiveAnims)
    if #self.undoStack == 0 or hasActiveAnims then return false end
    local snapshot = table.remove(self.undoStack)
    self.tubes = snapshot.tubes
    self.locks = snapshot.locks
    self.tempTubes = snapshot.tempTubes
    self.sinkTubes = snapshot.sinkTubes
    self.selectedTube = nil
    self.isWin = false
    self.sourceLocked = {}
    self.receivingCount = {}
    self.pendingReveals = {}
    return true
end

--- 数据先行：发起倒水时立即提交状态变更
--- 返回动画所需的信息，nil 表示无法倒水
---@param srcIdx integer
---@param dstIdx integer
---@return table|nil pourInfo { srcIdx, dstIdx, pourCount, pourColor, srcSnapshot }
function GameState:commitPour(srcIdx, dstIdx)
    local pourCount = self:getPourCount(srcIdx, dstIdx)
    if pourCount <= 0 then return nil end

    -- 保存 undo 快照（数据变更前）
    self:saveUndoState()
    -- 限制 undo 栈深度
    if #self.undoStack > 30 then
        table.remove(self.undoStack, 1)
    end

    -- 保存源管快照（动画渲染用）
    local srcSnapshot = self:getTubeSnapshot(srcIdx)
    local pourColor = self:getTopColor(srcIdx)

    -- 从源管顶部移除 pourCount 层
    local src = self.tubes[srcIdx]
    local dst = self.tubes[dstIdx]
    for _ = 1, pourCount do
        table.insert(dst, table.remove(src))
    end

    -- 锁定源管、增加目标接收计数
    self:lockSource(srcIdx)
    self:addReceiving(dstIdx)

    return {
        srcIdx = srcIdx,
        dstIdx = dstIdx,
        pourCount = pourCount,
        pourColor = pourColor,
        srcSnapshot = srcSnapshot,
    }
end

--- 获取管的快照（用于动画开始前保存源管状态）
---@param tubeIdx integer
---@return table
function GameState:getTubeSnapshot(tubeIdx)
    local tube = self.tubes[tubeIdx]
    local snapshot = {}
    for j = 1, #tube do snapshot[j] = tube[j] end
    return snapshot
end

--- 选中/取消选中试管
---@param tubeIdx integer|nil
function GameState:select(tubeIdx)
    if tubeIdx then
        if not self:canSelect(tubeIdx) then return end
    end
    self.selectedTube = tubeIdx
end

--- 获取撤销栈深度
---@return integer
function GameState:getUndoCount()
    return #self.undoStack
end

--- 购买/获得临时管（容量叠加逻辑）
---@return integer newIdx 新增或升级的管索引
function GameState:addTempTube()
    -- 查找未满级的临时管
    for idx, cap in pairs(self.tempTubes) do
        if cap < Config.tube.layerCount then
            self.tempTubes[idx] = cap + 1
            return idx
        end
    end
    -- 全部满级，创建新管
    self.tubeCount = self.tubeCount + 1
    local newIdx = self.tubeCount
    self.tubes[newIdx] = {}
    self.tempTubes[newIdx] = 1
    return newIdx
end

return GameState
