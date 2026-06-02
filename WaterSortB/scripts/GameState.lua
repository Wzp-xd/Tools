--- GameState.lua — 纯数据层：试管数据、倒水判定、随机生成
local Config = require("Config")

local GameState = {}
GameState.__index = GameState

function GameState.new()
    local self = setmetatable({}, GameState)
    self.tubes = {}
    self.selected = nil
    self:reset()
    return self
end

--- 深拷贝 INITIAL_TUBES 作为初始状态
function GameState:reset()
    self.tubes = {}
    for i, tube in ipairs(Config.INITIAL_TUBES) do
        self.tubes[i] = {}
        for j, v in ipairs(tube) do
            self.tubes[i][j] = v
        end
    end
    self.selected = nil
end

--- Fisher-Yates 洗牌随机生成
function GameState:randomize(colorCount, emptyCount)
    colorCount = colorCount or 3
    emptyCount = emptyCount or 2
    local cap = Config.CAPACITY

    local pool = {}
    for color = 1, colorCount do
        for _ = 1, cap do
            pool[#pool + 1] = color
        end
    end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    self.tubes = {}
    for t = 1, colorCount do
        self.tubes[t] = {}
        for s = 1, cap do
            self.tubes[t][s] = pool[(t - 1) * cap + s]
        end
    end
    for e = 1, emptyCount do
        self.tubes[colorCount + e] = {}
    end
    self.selected = nil
end

function GameState:getTopColor(tubeIdx)
    local tube = self.tubes[tubeIdx]
    return tube[#tube]
end

function GameState:getTopCount(tubeIdx)
    local tube = self.tubes[tubeIdx]
    if #tube == 0 then return 0 end
    local color = tube[#tube]
    local count = 0
    for i = #tube, 1, -1 do
        if tube[i] == color then count = count + 1
        else break end
    end
    return count
end

function GameState:canPour(fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    local from = self.tubes[fromIdx]
    local to   = self.tubes[toIdx]
    if #from == 0 then return false end
    if #to >= Config.CAPACITY then return false end
    return true
end

function GameState:calcPourCount(fromIdx, toIdx)
    local consecutive = self:getTopCount(fromIdx)
    local space = Config.CAPACITY - #self.tubes[toIdx]
    return math.min(consecutive, space)
end

--- 执行倒水数据变更（一步完成），返回 { color, count }
function GameState:executePour(fromIdx, toIdx)
    local info = self:removeFromSource(fromIdx, toIdx)
    self:addToTarget(toIdx, info.color, info.count)
    return info
end

--- 倒水拆分步骤 1/2：从源管移除顶部连续同色液体
---@return { color: number, count: number }
function GameState:removeFromSource(fromIdx, toIdx)
    local count = self:calcPourCount(fromIdx, toIdx)
    local color = self:getTopColor(fromIdx)
    for _ = 1, count do
        table.remove(self.tubes[fromIdx])
    end
    return { color = color, count = count }
end

--- 倒水拆分步骤 2/2：将液体添加到目标管
function GameState:addToTarget(toIdx, color, count)
    for _ = 1, count do
        self.tubes[toIdx][#self.tubes[toIdx] + 1] = color
    end
end

--- 检查是否全部完成
function GameState:isComplete()
    for _, tube in ipairs(self.tubes) do
        if #tube > 0 and #tube < Config.CAPACITY then return false end
        if #tube == Config.CAPACITY then
            local c = tube[1]
            for j = 2, #tube do
                if tube[j] ~= c then return false end
            end
        end
    end
    return true
end

return GameState
