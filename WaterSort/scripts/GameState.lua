-- ============================================================
-- GameState.lua - 游戏状态管理与核心逻辑
-- ============================================================

local Config = require("config")
local LevelGenerator = require("LevelGenerator")

local GameState = {}
GameState.__index = GameState

--- 创建新的游戏状态实例
---@return table
function GameState.new()
    local self = setmetatable({}, GameState)
    self.tubes = {}
    self.tubeCount = 0
    self.colorCount = 0
    self.selectedTube = nil
    self.level = 1
    self.isAnimating = false
    self.isWin = false
    self.undoStack = {}
    return self
end

--- 加载关卡
---@param level integer
function GameState:loadLevel(level)
    local cfg = Config.getLevelConfig(level)
    self.tubeCount = cfg.tubes
    self.colorCount = cfg.colors
    self.level = level
    self.selectedTube = nil
    self.isAnimating = false
    self.isWin = false
    self.undoStack = {}
    self.tubes = LevelGenerator.generateQuality(level)
end

--- 获取管顶颜色
---@param tubeIdx integer
---@return integer|nil
function GameState:getTopColor(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return nil end
    return tube[#tube]
end

--- 获取管顶连续同色层数
---@param tubeIdx integer
---@return integer
function GameState:getTopConsecutiveCount(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if not tube or #tube == 0 then return 0 end
    local topColor = tube[#tube]
    local count = 0
    for i = #tube, 1, -1 do
        if tube[i] == topColor then
            count = count + 1
        else
            break
        end
    end
    return count
end

--- 判断能否从 src 倒向 dst
---@param srcIdx integer
---@param dstIdx integer
---@return boolean
function GameState:canPour(srcIdx, dstIdx)
    local src = self.tubes[srcIdx]
    local dst = self.tubes[dstIdx]
    if not src or not dst then return false end
    if #src == 0 or srcIdx == dstIdx then return false end
    local layerCount = Config.tube.layerCount
    local dstSpace = layerCount - #dst
    if dstSpace <= 0 then return false end
    local dstTop = (#dst > 0) and dst[#dst] or nil
    if dstTop ~= nil and dstTop ~= src[#src] then return false end
    return true
end

--- 获取可倒层数
---@param srcIdx integer
---@param dstIdx integer
---@return integer
function GameState:getPourCount(srcIdx, dstIdx)
    local dst = self.tubes[dstIdx]
    local layerCount = Config.tube.layerCount
    return math.min(self:getTopConsecutiveCount(srcIdx), layerCount - #dst)
end

--- 检查是否通关
---@return boolean
function GameState:checkWin()
    local layerCount = Config.tube.layerCount
    for i = 1, self.tubeCount do
        local tube = self.tubes[i]
        if #tube > 0 then
            if #tube ~= layerCount then return false end
            local first = tube[1]
            for j = 2, #tube do
                if tube[j] ~= first then return false end
            end
        end
    end
    return true
end

--- 保存撤销快照
function GameState:saveUndoState()
    local snapshot = {}
    for i = 1, self.tubeCount do
        snapshot[i] = {}
        for j = 1, #self.tubes[i] do
            snapshot[i][j] = self.tubes[i][j]
        end
    end
    table.insert(self.undoStack, snapshot)
end

--- 撤销一步
---@return boolean 是否成功撤销
function GameState:undo()
    if #self.undoStack == 0 or self.isAnimating then return false end
    self.tubes = table.remove(self.undoStack)
    self.selectedTube = nil
    self.isWin = false
    return true
end

--- 执行倒水（仅数据层，不含动画）
---@param srcIdx integer
---@param dstIdx integer
---@return integer pourCount 实际倒出的层数
function GameState:executePour(srcIdx, dstIdx)
    local count = self:getPourCount(srcIdx, dstIdx)
    if count == 0 then return 0 end
    self:saveUndoState()
    local src = self.tubes[srcIdx]
    local dst = self.tubes[dstIdx]
    for _ = 1, count do
        table.insert(dst, table.remove(src))
    end
    if self:checkWin() then
        self.isWin = true
    end
    return count
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
    if tubeIdx and self.tubes[tubeIdx] and #self.tubes[tubeIdx] == 0 then
        return  -- 空管不能选中
    end
    self.selectedTube = tubeIdx
end

--- 获取撤销栈深度
---@return integer
function GameState:getUndoCount()
    return #self.undoStack
end

return GameState
