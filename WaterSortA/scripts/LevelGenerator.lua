-- ============================================================
-- LevelGenerator.lua - 关卡生成（支持可解性验证和难度控制）
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

--- 检查关卡是否已完成(所有非空管为纯色且满管)
---@param tubes table[]
---@return boolean
local function isSolved(tubes)
    local layerCount = Config.tube.layerCount
    for i = 1, #tubes do
        local tube = tubes[i]
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

--- 生成基础关卡（随机洗牌法）
---@param level integer
---@return table[] tubes
function LevelGenerator.generate(level)
    local cfg = Config.getLevelConfig(level)
    local layerCount = Config.tube.layerCount

    local allLayers = {}
    for c = 1, cfg.colors do
        for _ = 1, layerCount do
            table.insert(allLayers, c)
        end
    end
    shuffleArray(allLayers)

    local tubes = {}
    local idx = 1
    for i = 1, cfg.colors do
        tubes[i] = {}
        for _ = 1, layerCount do
            tubes[i][#tubes[i] + 1] = allLayers[idx]
            idx = idx + 1
        end
    end
    for i = cfg.colors + 1, cfg.tubes do
        tubes[i] = {}
    end

    return tubes
end

--- 生成可解性更好的关卡（多次洗牌选择非退化布局）
--- 避免生成"一开始就已分好"的平凡关卡
---@param level integer
---@param maxAttempts? integer 最大尝试次数（默认20）
---@return table[] tubes
function LevelGenerator.generateQuality(level, maxAttempts)
    maxAttempts = maxAttempts or 20
    local layerCount = Config.tube.layerCount
    local bestTubes = nil
    local bestScore = -1

    for _ = 1, maxAttempts do
        local tubes = LevelGenerator.generate(level)

        -- 评分: 颜色混乱度越高越好（避免已经排好的管）
        local score = 0
        for i = 1, #tubes do
            local tube = tubes[i]
            if #tube > 0 then
                local transitions = 0
                for j = 2, #tube do
                    if tube[j] ~= tube[j - 1] then
                        transitions = transitions + 1
                    end
                end
                score = score + transitions
            end
        end

        -- 避免已经完成的关卡
        if isSolved(tubes) then
            score = 0
        end

        if score > bestScore then
            bestScore = score
            bestTubes = tubes
        end
    end

    return bestTubes
end

return LevelGenerator
