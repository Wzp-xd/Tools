-- ============================================================================
-- Target.lua - 靶子系统（带杆子的圆盘靶子）
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Audio = require "modules.Audio"
local Scene = require "modules.Scene"
local UI = require "modules.UI"

local M = {}

local CONFIG = Config.CONFIG

-- 靶子类型
M.TARGET_TYPE = {
    STATIC = 1,   -- 固定靶
    MOVING = 2,   -- 移动靶
    WHITE = 3,    -- 白色靶（有生命值）
}

-- 靶子状态
M.TARGET_STATE = {
    ACTIVE = 1,       -- 活动中
    FALLING = 2,      -- 向后倒下中
    SINKING = 3,      -- 正在下沉
    HIDDEN = 4,       -- 隐藏中
    RISING = 5,       -- 正在升起
}

-- 靶子分数等级配置（分数越高，靶子越小，颜色越醒目）
local TARGET_SCORE_LEVELS = {
    {
        score = 100,            -- 基础分
        sizeScale = 1.0,        -- 正常大小
        name = "普通靶",
        -- 靶子颜色（从外到内）- 经典白黑配色
        ringColors = {
            Color(1.0, 1.0, 1.0, 1.0),   -- 白色
            Color(0.1, 0.1, 0.1, 1.0),   -- 黑色
            Color(1.0, 1.0, 1.0, 1.0),   -- 白色
            Color(0.1, 0.1, 0.1, 1.0),   -- 黑色
            Color(0.9, 0.2, 0.2, 1.0),   -- 红色靶心
        },
    },
    {
        score = 200,            -- 双倍分
        sizeScale = 0.75,       -- 较小
        name = "蓝色靶",
        -- 蓝色系
        ringColors = {
            Color(0.3, 0.5, 0.8, 1.0),   -- 浅蓝
            Color(0.1, 0.3, 0.6, 1.0),   -- 深蓝
            Color(0.4, 0.6, 0.9, 1.0),   -- 亮蓝
            Color(0.1, 0.2, 0.5, 1.0),   -- 深蓝
            Color(1.0, 0.85, 0.0, 1.0),  -- 金色靶心
        },
    },
    {
        score = 300,            -- 三倍分
        sizeScale = 0.55,       -- 更小
        name = "绿色靶",
        -- 绿色系
        ringColors = {
            Color(0.3, 0.7, 0.3, 1.0),   -- 浅绿
            Color(0.1, 0.5, 0.1, 1.0),   -- 深绿
            Color(0.4, 0.8, 0.4, 1.0),   -- 亮绿
            Color(0.1, 0.4, 0.1, 1.0),   -- 深绿
            Color(1.0, 0.5, 0.0, 1.0),   -- 橙色靶心
        },
    },
    {
        score = 500,            -- 五倍分
        sizeScale = 0.4,        -- 最小
        name = "金色靶",
        -- 金色/红色系（高价值目标）
        ringColors = {
            Color(0.9, 0.7, 0.2, 1.0),   -- 金色
            Color(0.8, 0.2, 0.1, 1.0),   -- 红色
            Color(1.0, 0.85, 0.3, 1.0),  -- 亮金
            Color(0.7, 0.1, 0.1, 1.0),   -- 深红
            Color(1.0, 1.0, 1.0, 1.0),   -- 白色靶心（高对比）
        },
    },
}

-- 靶子配置
local TARGET_CONFIG = {
    -- 杆子参数
    poleRadius = 0.08,        -- 杆子半径
    poleHeight = 2.7,         -- 杆子高度（增加0.2）
    poleColor = Color(0.3, 0.25, 0.2, 1.0),  -- 木色
    
    -- 靶子盘参数
    discRadius = 0.8,         -- 靶盘基础半径（会被 sizeScale 缩放）
    discThickness = 0.08,     -- 靶盘厚度
    ringCount = 5,            -- 环数
    
    -- 默认靶子颜色（被 TARGET_SCORE_LEVELS 覆盖）
    ringColors = {
        Color(1.0, 1.0, 1.0, 1.0),   -- 最外环 - 白色
        Color(0.1, 0.1, 0.1, 1.0),   -- 黑色
        Color(0.2, 0.6, 0.9, 1.0),   -- 蓝色
        Color(0.9, 0.2, 0.2, 1.0),   -- 红色
        Color(1.0, 0.85, 0.0, 1.0),  -- 中心 - 金黄色（靶心）
    },
    
    -- 动画参数
    fallSpeed = 300.0,        -- 倒下速度（度/秒）90度/0.3秒=300
    fallAngle = 90.0,         -- 倒下角度（向后倒90度）
    sinkSpeed = 3.0,          -- 下沉速度
    riseSpeed = 30.0,         -- 升起速度（0.1秒完成）
    sinkDepth = 3.0,          -- 下沉深度
    respawnDelay = 3.0,       -- 重生延迟
    
    -- 移动靶参数
    moveSpeed = 2.5,          -- 移动速度
    moveRange = 8.0,          -- 移动范围
    
    -- 得分
    baseScore = 100,          -- 基础得分
    bullseyeBonus = 50,       -- 靶心加分
    
    -- 白色靶子配置
    whiteTargetHealth = 100,      -- 白色靶子生命值
    whiteTargetScore = 300,       -- 白色靶子击破得分
    whiteTargetDamagePerHit = 25, -- 每次击中扣除的生命值
    
    -- 靶子生命周期配置
    targetLifetime = 30.0,        -- 靶子存活时间（秒）
    fadeOutDuration = 0.3,        -- 消失前的淡出时间（秒）- 快速消失
    
    -- 靶子动态生成配置
    spawnInterval = 2.0,          -- 生成间隔（秒）
    maxActiveTargets = 15,        -- 最大同时存在靶子数
    minActiveTargets = 5,         -- 最少同时存在靶子数
}

--- 创建 PBR 材质
local function CreatePBRMaterial(color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.5))
    if emissive then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    return mat
end

--- 创建白色靶盘（单一颜色，用于白色靶子）
---@param parentNode Node 父节点
---@return Node discNode 靶盘节点
---@return StaticModel discModel 靶盘模型组件（用于更新颜色）
---@return Material discMaterial 靶盘材质（用于更新颜色）
local function CreateWhiteTargetDisc(parentNode)
    local discNode = parentNode:CreateChild("Disc")
    discNode.position = Vector3(0, TARGET_CONFIG.poleHeight, 0)
    -- 旋转90度让靶盘面向水平方向
    discNode.rotation = Quaternion(90, Vector3.RIGHT)
    
    local totalRadius = TARGET_CONFIG.discRadius
    local thickness = TARGET_CONFIG.discThickness
    
    -- 创建单一颜色的圆盘
    local ringNode = discNode:CreateChild("WhiteDisc")
    ringNode.scale = Vector3(totalRadius * 2, thickness, totalRadius * 2)
    ringNode.position = Vector3(0, 0.01, 0)
    
    local model = ringNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    -- 初始颜色为白色
    local mat = CreatePBRMaterial(Color(1.0, 1.0, 1.0, 1.0), 0.1, 0.6)
    model:SetMaterial(mat)
    model.castShadows = true
    
    -- 添加靶盘背面
    local backNode = discNode:CreateChild("Back")
    backNode.scale = Vector3(totalRadius * 2, thickness, totalRadius * 2)
    backNode.position = Vector3(0, -thickness * 0.5, 0)
    
    local backModel = backNode:CreateComponent("StaticModel")
    backModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local backMat = CreatePBRMaterial(Color(0.4, 0.3, 0.2, 1.0), 0.0, 0.7)
    backModel:SetMaterial(backMat)
    
    return discNode, model, mat
end

--- 创建圆盘靶子（使用圆柱体绘制同心圆环）
---@param parentNode Node 父节点
---@param scoreLevel table|nil 分数等级配置（可选，默认使用第一级）
local function CreateTargetDisc(parentNode, scoreLevel)
    -- 使用传入的分数等级，默认使用第一级
    scoreLevel = scoreLevel or TARGET_SCORE_LEVELS[1]
    
    local discNode = parentNode:CreateChild("Disc")
    discNode.position = Vector3(0, TARGET_CONFIG.poleHeight, 0)
    -- 旋转90度让靶盘面向水平方向（绕X轴旋转，从朝天变成朝前）
    discNode.rotation = Quaternion(90, Vector3.RIGHT)
    
    -- 使用多个圆柱体叠加来创建同心环效果
    local ringCount = TARGET_CONFIG.ringCount
    -- 根据分数等级缩放靶盘大小
    local totalRadius = TARGET_CONFIG.discRadius * scoreLevel.sizeScale
    local thickness = TARGET_CONFIG.discThickness * scoreLevel.sizeScale
    
    -- 使用分数等级的颜色配置
    local ringColors = scoreLevel.ringColors or TARGET_CONFIG.ringColors
    
    for i = 1, ringCount do
        local ringNode = discNode:CreateChild("Ring" .. i)
        
        -- 计算环的半径（从外到内）
        local outerRadius = totalRadius * (ringCount - i + 1) / ringCount
        
        -- 使用圆柱体作为环
        ringNode.scale = Vector3(outerRadius * 2, thickness, outerRadius * 2)
        -- Z偏移避免 Z-fighting（旋转后原来的Y变成了Z），内层在前
        ringNode.position = Vector3(0, i * 0.01, 0)
        
        local model = ringNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        
        -- 设置颜色（使用分数等级的颜色）
        local color = ringColors[i] or Color(0.5, 0.5, 0.5, 1.0)
        local mat = CreatePBRMaterial(color, 0.1, 0.6)
        model:SetMaterial(mat)
        model.castShadows = true
    end
    
    -- 添加靶盘背面（用于从后面看时有东西）
    local backNode = discNode:CreateChild("Back")
    backNode.scale = Vector3(totalRadius * 2, thickness, totalRadius * 2)
    backNode.position = Vector3(0, -thickness * 0.5, 0)
    
    local backModel = backNode:CreateComponent("StaticModel")
    backModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local backMat = CreatePBRMaterial(Color(0.4, 0.3, 0.2, 1.0), 0.0, 0.7)
    backModel:SetMaterial(backMat)
    
    return discNode, totalRadius
end

--- 创建靶子杆子
local function CreateTargetPole(parentNode)
    local poleNode = parentNode:CreateChild("Pole")
    poleNode.position = Vector3(0, TARGET_CONFIG.poleHeight / 2, 0)
    poleNode.scale = Vector3(
        TARGET_CONFIG.poleRadius * 2,
        TARGET_CONFIG.poleHeight,
        TARGET_CONFIG.poleRadius * 2
    )
    
    local model = poleNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local mat = CreatePBRMaterial(TARGET_CONFIG.poleColor, 0.0, 0.7)
    model:SetMaterial(mat)
    model.castShadows = true
    
    return poleNode
end

--- 根据权重随机选择分数等级
---@return table 选中的分数等级配置
local function RandomScoreLevel()
    -- 权重分布：100分(50%), 200分(30%), 300分(15%), 500分(5%)
    local weights = { 50, 30, 15, 5 }
    local totalWeight = 0
    for _, w in ipairs(weights) do
        totalWeight = totalWeight + w
    end
    
    local roll = math.random() * totalWeight
    local cumulative = 0
    for i, w in ipairs(weights) do
        cumulative = cumulative + w
        if roll <= cumulative then
            return TARGET_SCORE_LEVELS[i]
        end
    end
    return TARGET_SCORE_LEVELS[1]  -- 默认返回第一级
end

--- 让靶子朝向玩家
---@param target table 靶子数据
local function FacePlayer(target)
    if not target.node or not GameState.playerNode then return end
    
    local playerPos = GameState.playerNode.position
    local targetPos = target.node.position
    
    -- 计算水平方向向量（忽略Y轴）
    local toPlayer = Vector3(playerPos.x - targetPos.x, 0, playerPos.z - targetPos.z)
    if toPlayer:Length() > 0.1 then
        target.node.rotation = Quaternion(Vector3.FORWARD, toPlayer:Normalized())
    end
end

--- 创建单个靶子
---@param position Vector3 位置
---@param targetType number 靶子类型
---@param moveDir number|nil 移动方向
---@param scoreLevel table|nil 分数等级（可选，随机分配）
function M.CreateOne(position, targetType, moveDir, scoreLevel)
    local targetNode = GameState.scene:CreateChild("Target")
    targetNode.position = position
    
    -- 让靶子朝向场地中心（原点）
    local toCenter = Vector3(0, 0, 0) - position
    toCenter.y = 0  -- 只在水平面旋转
    if toCenter:Length() > 0.1 then
        targetNode.rotation = Quaternion(Vector3.FORWARD, toCenter:Normalized())
    end
    
    -- 创建杆子
    local poleNode = CreateTargetPole(targetNode)
    
    -- 创建靶盘（白色靶子使用单色圆盘，普通靶子根据分数等级创建）
    local discNode, discModel, discMaterial
    local isWhiteTarget = (targetType == M.TARGET_TYPE.WHITE)
    local actualRadius = TARGET_CONFIG.discRadius  -- 实际靶盘半径
    
    -- 如果不是白色靶子，随机选择分数等级
    if not isWhiteTarget then
        scoreLevel = scoreLevel or RandomScoreLevel()
    end
    
    if isWhiteTarget then
        discNode, discModel, discMaterial = CreateWhiteTargetDisc(targetNode)
    else
        discNode, actualRadius = CreateTargetDisc(targetNode, scoreLevel)
    end
    
    -- 添加刚体和碰撞体（用于射击检测）
    local rigidBody = targetNode:CreateComponent("RigidBody")
    rigidBody.mass = 0  -- 静态物体
    rigidBody.friction = 0.5
    rigidBody.collisionLayer = GameState.COLLISION_LAYER.TARGET
    rigidBody.collisionMask = GameState.COLLISION_MASK.TARGET
    rigidBody.collisionEventMode = COLLISION_ALWAYS
    
    -- 使用圆柱形碰撞体覆盖靶盘（旋转90度匹配靶盘朝向）
    -- 碰撞体大小根据实际靶盘大小调整
    local collisionRadius = isWhiteTarget and TARGET_CONFIG.discRadius or actualRadius
    local collisionThickness = isWhiteTarget and TARGET_CONFIG.discThickness or (TARGET_CONFIG.discThickness * scoreLevel.sizeScale)
    
    local shape = targetNode:CreateComponent("CollisionShape")
    shape:SetCylinder(
        collisionRadius * 2,
        collisionThickness * 2,
        Vector3(0, TARGET_CONFIG.poleHeight, 0),
        Quaternion(90, Vector3.RIGHT)  -- 旋转匹配靶盘
    )
    
    -- 靶子数据
    local target = {
        node = targetNode,
        poleNode = poleNode,
        discNode = discNode,
        rigidBody = rigidBody,
        
        -- 类型和状态
        targetType = targetType or M.TARGET_TYPE.STATIC,
        state = M.TARGET_STATE.ACTIVE,
        
        -- 位置
        basePosition = Vector3(position.x, position.y, position.z),
        currentHeight = 0,  -- 相对于基础位置的高度偏移
        
        -- 移动靶参数
        moveDir = moveDir or 1,  -- 1 = 向右, -1 = 向左
        moveOffset = 0,          -- 当前移动偏移
        
        -- 动画计时器
        fallAngle = 0,            -- 当前倒下角度
        sinkTimer = 0,
        respawnTimer = 0,
        
        -- 生命周期计时器
        lifeTimer = 0,            -- 已存活时间
        lifetime = TARGET_CONFIG.targetLifetime,  -- 总生命周期
        isFading = false,         -- 是否正在淡出
        
        -- 得分（根据分数等级）
        hitScore = isWhiteTarget and TARGET_CONFIG.whiteTargetScore or (scoreLevel and scoreLevel.score or TARGET_CONFIG.baseScore),
        scoreLevel = scoreLevel,  -- 保存分数等级信息
        
        -- 白色靶子专属属性
        isWhiteTarget = isWhiteTarget,
        health = isWhiteTarget and TARGET_CONFIG.whiteTargetHealth or 0,
        maxHealth = isWhiteTarget and TARGET_CONFIG.whiteTargetHealth or 0,
        discModel = discModel,      -- 用于更新颜色
        discMaterial = discMaterial, -- 用于更新颜色
    }
    
    table.insert(GameState.targets, target)
    
    -- 注册到节点映射（用于碰撞检测）
    GameState.targetNodeMap = GameState.targetNodeMap or {}
    GameState.targetNodeMap[targetNode] = target
    
    -- 立即让靶子朝向玩家（不等到第一次 Update）
    FacePlayer(target)
    
    return target
end

--- 检查位置是否在中央掩体方块内
---@param pos Vector3 要检查的位置
---@param margin number 安全边距
---@return boolean 是否在掩体内
local function IsInsideCoverBlock(pos, margin)
    -- 中央掩体参数（与 Scene.lua 中的 CreateCenterCover 保持一致）
    local coverWidth = 4.0    -- 中央间隙宽度
    local coverLength = 14.0  -- 掩体长度
    local pos_dis = (coverWidth + coverLength) / 2  -- = 9
    local halfSize = coverLength / 2  -- = 7
    
    -- 四个掩体方块的中心位置
    local coverCenters = {
        { x = pos_dis, z = pos_dis },    -- 右前
        { x = pos_dis, z = -pos_dis },   -- 右后
        { x = -pos_dis, z = pos_dis },   -- 左前
        { x = -pos_dis, z = -pos_dis },  -- 左后
    }
    
    local safeMargin = margin or 2.0
    
    for _, center in ipairs(coverCenters) do
        -- 检查是否在方块范围内（加上安全边距）
        local minX = center.x - halfSize - safeMargin
        local maxX = center.x + halfSize + safeMargin
        local minZ = center.z - halfSize - safeMargin
        local maxZ = center.z + halfSize + safeMargin
        
        if pos.x >= minX and pos.x <= maxX and pos.z >= minZ and pos.z <= maxZ then
            return true
        end
    end
    
    return false
end

--- 检查位置是否有效（不与墙壁、障碍物或其他靶子重叠）
---@param pos Vector3 要检查的位置
---@param minDistToWall number 距离墙壁的最小距离
---@param minDistToOther number 距离其他靶子的最小距离
---@return boolean 位置是否有效
local function IsValidPosition(pos, minDistToWall, minDistToOther)
    local arenaHalf = CONFIG.ArenaSize / 2
    
    -- 检查是否在场地边界内（考虑墙壁厚度和安全距离）
    local safeMargin = minDistToWall or 3.0
    if math.abs(pos.x) > arenaHalf - safeMargin or math.abs(pos.z) > arenaHalf - safeMargin then
        return false
    end
    
    -- 检查是否离玩家出生点太近
    local playerSpawnDist = 8.0
    if pos.x * pos.x + pos.z * pos.z < playerSpawnDist * playerSpawnDist then
        return false
    end
    
    -- 检查是否在中央掩体方块内
    if IsInsideCoverBlock(pos, 2.5) then
        return false
    end
    
    -- 检查是否与已有靶子太近
    local minDist = minDistToOther or 4.0
    for _, target in ipairs(GameState.targets) do
        if target.basePosition then
            local dx = pos.x - target.basePosition.x
            local dz = pos.z - target.basePosition.z
            local distSq = dx * dx + dz * dz
            if distSq < minDist * minDist then
                return false
            end
        end
    end
    
    -- 检查是否与障碍物碰撞（使用物理射线检测）
    if GameState.scene then
        local physics = GameState.scene:GetComponent("PhysicsWorld")
        if physics then
            -- 从位置上方向下发射射线检测
            local ray = Ray(Vector3(pos.x, 5, pos.z), Vector3.DOWN)
            local result = physics:RaycastSingle(ray, 10.0, GameState.COLLISION_LAYER.ENVIRONMENT)
            
            -- 如果射线击中的不是地面（Y > 0.5），说明有障碍物
            if result and result.body and result.position.y > 0.5 then
                return false
            end
        end
    end
    
    return true
end

--- 生成一个有效的随机位置
---@param minDist number 距离墙壁的最小距离
---@param maxAttempts number 最大尝试次数
---@return Vector3|nil 有效位置或nil
local function GenerateRandomPosition(minDist, maxAttempts)
    local arenaHalf = CONFIG.ArenaSize / 2
    local safeMargin = minDist or 5.0
    local attempts = maxAttempts or 20
    
    for _ = 1, attempts do
        local x = (math.random() * 2 - 1) * (arenaHalf - safeMargin)
        local z = (math.random() * 2 - 1) * (arenaHalf - safeMargin)
        local pos = Vector3(x, 0, z)
        
        if IsValidPosition(pos, safeMargin, 4.0) then
            return pos
        end
    end
    
    return nil
end

--- 为位置添加随机偏移
---@param pos Vector3 原始位置
---@param randomRange number 随机偏移范围
---@return Vector3 添加偏移后的位置
local function AddRandomOffset(pos, randomRange)
    local offsetX = (math.random() - 0.5) * 2 * randomRange
    local offsetZ = (math.random() - 0.5) * 2 * randomRange
    return Vector3(pos.x + offsetX, pos.y, pos.z + offsetZ)
end

--- 创建所有靶子（初始化）
function M.Create()
    -- 清除旧靶子
    M.ClearAll()
    
    -- 重置生成计时器
    spawnTimer = 0
    
    -- 只创建少量初始靶子（其余靠动态生成）
    local initialCount = TARGET_CONFIG.minActiveTargets
    local created = 0
    
    for _ = 1, initialCount do
        local pos = GenerateRandomPosition(5.0, 30)
        if pos then
            -- 随机决定是固定靶还是移动靶（30%概率移动靶）
            local targetType = math.random() < 0.3 and M.TARGET_TYPE.MOVING or M.TARGET_TYPE.STATIC
            local moveDir = math.random() < 0.5 and 1 or -1
            M.CreateOne(pos, targetType, moveDir)
            created = created + 1
        end
    end
    
    print("Created " .. created .. " initial targets (more will spawn dynamically)")
end

--- 清除所有靶子
function M.ClearAll()
    for _, target in ipairs(GameState.targets) do
        if target.node then
            target.node:Remove()
        end
    end
    GameState.targets = {}
    GameState.targetNodeMap = {}
end

--- 更新白色靶子颜色（根据生命值比例从白色变为红色）
---@param target table 靶子数据
local function UpdateWhiteTargetColor(target)
    if not target.isWhiteTarget or not target.discMaterial then return end
    
    -- 计算生命值比例 (1.0 = 满血, 0.0 = 死亡)
    local healthRatio = target.health / target.maxHealth
    healthRatio = math.max(0, math.min(1, healthRatio))
    
    -- 颜色插值：白色 (1,1,1) -> 红色 (1,0,0)
    -- 当 healthRatio = 1 时，颜色为白色
    -- 当 healthRatio = 0 时，颜色为红色
    local r = 1.0
    local g = healthRatio  -- 1 -> 0
    local b = healthRatio  -- 1 -> 0
    
    local newColor = Color(r, g, b, 1.0)
    target.discMaterial:SetShaderParameter("MatDiffColor", Variant(newColor))
end

--- 靶子被击中
function M.Hit(target)
    -- 允许在 ACTIVE 和 RISING 状态被击中
    if target.state ~= M.TARGET_STATE.ACTIVE and target.state ~= M.TARGET_STATE.RISING then
        return false
    end
    
    -- 增加命中计数（用于计算命中率）
    GameState.shotsHit = (GameState.shotsHit or 0) + 1
    
    -- 触发准星击中反馈效果
    UI.TriggerCrosshairHit()
    
    -- 白色靶子有生命值
    if target.isWhiteTarget then
        -- 扣除生命值
        target.health = target.health - TARGET_CONFIG.whiteTargetDamagePerHit
        
        -- 更新颜色
        UpdateWhiteTargetColor(target)
        
        -- 播放击中音效
        Audio.PlaySfx("hit_enemy")
        
        -- 如果还有生命值，不倒下
        if target.health > 0 then
            return true  -- 击中了，但没有倒下
        end
        
        -- 生命值归零，加分并倒下
        GameState.score = GameState.score + target.hitScore
        GameState.targetsHit = GameState.targetsHit + 1
        UI.ShowScorePopup(target.hitScore)
    else
        -- 普通靶子，直接加分
        GameState.score = GameState.score + target.hitScore
        GameState.targetsHit = GameState.targetsHit + 1
        UI.ShowScorePopup(target.hitScore)
        
        -- 播放音效
        Audio.PlaySfx("hit_enemy")
    end
    
    -- 切换到倒下状态（向后倒）
    target.state = M.TARGET_STATE.FALLING
    target.fallAngle = 0
    
    -- 禁用碰撞（同时禁用 collisionLayer，阻止射线检测击中）
    if target.rigidBody then
        target.rigidBody.collisionLayer = 0
        target.rigidBody.collisionMask = 0
    end
    
    return true
end

--- 更新单个靶子
local function UpdateTarget(target, dt)
    if not target.node then return end
    
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    
    -- 根据状态更新
    if target.state == M.TARGET_STATE.ACTIVE then
        -- 更新生命周期计时器
        target.lifeTimer = target.lifeTimer + dt * gameSpeed
        
        -- 检查是否超时（30秒后消失）
        if target.lifeTimer >= target.lifetime then
            -- 标记为待删除
            target.shouldRemove = true
            return
        end
        
        -- 检查是否进入淡出阶段（最后1秒）
        local fadeStartTime = target.lifetime - TARGET_CONFIG.fadeOutDuration
        if target.lifeTimer >= fadeStartTime and not target.isFading then
            target.isFading = true
        end
        
        -- 淡出效果：快速缩小并下沉
        if target.isFading then
            local fadeProgress = (target.lifeTimer - fadeStartTime) / TARGET_CONFIG.fadeOutDuration
            fadeProgress = math.min(1.0, fadeProgress)
            
            -- 使用 ease-out 缓动（开始快，结束慢）
            local easedProgress = 1.0 - (1.0 - fadeProgress) * (1.0 - fadeProgress)
            
            -- 快速缩小靶盘（缩小到接近0）
            local scale = math.max(0.01, 1.0 - easedProgress * 0.95)  -- 缩小到5%
            if target.discNode then
                target.discNode.scale = Vector3(scale, scale, scale)
            end
            -- 杆子也一起缩小
            if target.poleNode then
                target.poleNode.scale = Vector3(scale * 0.16, scale * 2.5, scale * 0.16)
            end
            
            -- 快速下沉效果
            target.currentHeight = -easedProgress * 1.5  -- 下沉1.5米
            
            -- 更新位置
            local newPos = Vector3(
                target.basePosition.x + target.moveOffset,
                target.basePosition.y + target.currentHeight,
                target.basePosition.z
            )
            target.node.position = newPos
        end
        
        -- 始终朝向玩家
        FacePlayer(target)
        
        -- 移动靶的移动逻辑（受游戏速度影响）
        if target.targetType == M.TARGET_TYPE.MOVING then
            target.moveOffset = target.moveOffset + TARGET_CONFIG.moveSpeed * target.moveDir * dt * gameSpeed
            
            -- 到达边界时反向
            if math.abs(target.moveOffset) >= TARGET_CONFIG.moveRange / 2 then
                target.moveDir = -target.moveDir
            end
            
            -- 更新位置
            local newPos = Vector3(
                target.basePosition.x + target.moveOffset,
                target.basePosition.y + target.currentHeight,
                target.basePosition.z
            )
            target.node.position = newPos
        end
        
    elseif target.state == M.TARGET_STATE.FALLING then
        -- 向后倒下动画（绕X轴旋转，向后倒）（受游戏速度影响）
        target.fallAngle = target.fallAngle + TARGET_CONFIG.fallSpeed * dt * gameSpeed
        
        if target.fallAngle >= TARGET_CONFIG.fallAngle then
            -- 倒下完成，切换到下沉状态
            target.fallAngle = TARGET_CONFIG.fallAngle
            target.state = M.TARGET_STATE.SINKING
            target.sinkTimer = 0
        end
        
        -- 保持朝向玩家的水平旋转，叠加向后倒的旋转
        if GameState.playerNode then
            local playerPos = GameState.playerNode.position
            local targetPos = target.node.position
            local toPlayer = Vector3(playerPos.x - targetPos.x, 0, playerPos.z - targetPos.z)
            
            if toPlayer:Length() > 0.1 then
                -- 先计算朝向玩家的旋转
                local faceRotation = Quaternion(Vector3.FORWARD, toPlayer:Normalized())
                -- 叠加向后倒的旋转（绕本地X轴，向后倒）
                local fallRotation = Quaternion(-target.fallAngle, Vector3.RIGHT)
                target.node.rotation = faceRotation * fallRotation
            end
        end
        
    elseif target.state == M.TARGET_STATE.SINKING then
        -- 下沉动画（保持倒下姿态）（受游戏速度影响）
        target.sinkTimer = target.sinkTimer + dt * gameSpeed
        local sinkProgress = target.sinkTimer * TARGET_CONFIG.sinkSpeed / TARGET_CONFIG.sinkDepth
        
        if sinkProgress >= 1.0 then
            -- 完全下沉
            target.currentHeight = -TARGET_CONFIG.sinkDepth
            target.state = M.TARGET_STATE.HIDDEN
            target.respawnTimer = 0
        else
            -- 缓动下沉
            local easedProgress = sinkProgress * sinkProgress  -- ease-in
            target.currentHeight = -TARGET_CONFIG.sinkDepth * easedProgress
        end
        
        -- 更新位置
        local newPos = Vector3(
            target.basePosition.x + target.moveOffset,
            target.basePosition.y + target.currentHeight,
            target.basePosition.z
        )
        target.node.position = newPos
        
        -- 保持倒下姿态（不改变旋转）
        
    elseif target.state == M.TARGET_STATE.HIDDEN then
        -- 等待重生（受游戏速度影响）
        target.respawnTimer = target.respawnTimer + dt * gameSpeed
        
        if target.respawnTimer >= TARGET_CONFIG.respawnDelay then
            -- 开始升起
            target.state = M.TARGET_STATE.RISING
            target.sinkTimer = 0
            
            -- 升起时就启用碰撞，可以被射击
            if target.rigidBody then
                target.rigidBody.collisionLayer = GameState.COLLISION_LAYER.TARGET
                target.rigidBody.collisionMask = GameState.COLLISION_MASK.TARGET
            end
        end
        
    elseif target.state == M.TARGET_STATE.RISING then
        -- 升起动画（同时恢复直立）（受游戏速度影响）
        target.sinkTimer = target.sinkTimer + dt * gameSpeed
        local riseProgress = target.sinkTimer * TARGET_CONFIG.riseSpeed / TARGET_CONFIG.sinkDepth
        
        if riseProgress >= 1.0 then
            -- 完全升起
            target.currentHeight = 0
            target.fallAngle = 0
            target.state = M.TARGET_STATE.ACTIVE
            
            -- 重新启用碰撞
            if target.rigidBody then
                target.rigidBody.collisionLayer = GameState.COLLISION_LAYER.TARGET
                target.rigidBody.collisionMask = GameState.COLLISION_MASK.TARGET
            end
            
            -- 白色靶子重置生命值和颜色
            if target.isWhiteTarget then
                target.health = target.maxHealth
                UpdateWhiteTargetColor(target)
            end
        else
            -- 缓动升起
            local easedProgress = 1 - (1 - riseProgress) * (1 - riseProgress)  -- ease-out
            target.currentHeight = -TARGET_CONFIG.sinkDepth * (1 - easedProgress)
            -- 同步恢复角度
            target.fallAngle = TARGET_CONFIG.fallAngle * (1 - easedProgress)
        end
        
        -- 更新位置
        local newPos = Vector3(
            target.basePosition.x + target.moveOffset,
            target.basePosition.y + target.currentHeight,
            target.basePosition.z
        )
        target.node.position = newPos
        
        -- 恢复直立的旋转（朝向玩家 + 逐渐直立）
        if GameState.playerNode then
            local playerPos = GameState.playerNode.position
            local targetPos = target.node.position
            local toPlayer = Vector3(playerPos.x - targetPos.x, 0, playerPos.z - targetPos.z)
            
            if toPlayer:Length() > 0.1 then
                local faceRotation = Quaternion(Vector3.FORWARD, toPlayer:Normalized())
                local fallRotation = Quaternion(-target.fallAngle, Vector3.RIGHT)
                target.node.rotation = faceRotation * fallRotation
            end
        end
    end
end

-- 生成计时器
local spawnTimer = 0

--- 删除单个靶子
---@param target table 靶子数据
local function RemoveTarget(target)
    if target.node then
        -- 从节点映射中移除
        if GameState.targetNodeMap then
            GameState.targetNodeMap[target.node] = nil
        end
        -- 删除节点
        target.node:Remove()
        target.node = nil
    end
end

--- 统计当前活动靶子数量
---@return number 活动靶子数量
local function CountActiveTargets()
    local count = 0
    for _, target in ipairs(GameState.targets) do
        if target.state == M.TARGET_STATE.ACTIVE or target.state == M.TARGET_STATE.RISING then
            count = count + 1
        end
    end
    return count
end

--- 生成一个随机靶子
local function SpawnRandomTarget()
    local pos = GenerateRandomPosition(5.0, 30)
    if pos then
        -- 随机决定是固定靶还是移动靶（30%概率移动靶）
        local targetType = math.random() < 0.3 and M.TARGET_TYPE.MOVING or M.TARGET_TYPE.STATIC
        local moveDir = math.random() < 0.5 and 1 or -1
        M.CreateOne(pos, targetType, moveDir)
        return true
    end
    return false
end

--- 更新所有靶子
function M.Update(dt)
    local gameSpeed = GameState.gameSpeed or 1.0
    
    -- 更新所有靶子
    for _, target in ipairs(GameState.targets) do
        UpdateTarget(target, dt)
    end
    
    -- 删除标记为待删除的靶子
    local i = 1
    while i <= #GameState.targets do
        local target = GameState.targets[i]
        if target.shouldRemove then
            RemoveTarget(target)
            table.remove(GameState.targets, i)
        else
            i = i + 1
        end
    end
    
    -- 更新生成计时器
    spawnTimer = spawnTimer + dt * gameSpeed
    
    -- 定时生成新靶子
    if spawnTimer >= TARGET_CONFIG.spawnInterval then
        spawnTimer = 0
        
        local activeCount = CountActiveTargets()
        
        -- 如果活动靶子少于最大数量，生成新靶子
        if activeCount < TARGET_CONFIG.maxActiveTargets then
            -- 如果少于最少数量，多生成几个
            local toSpawn = 1
            if activeCount < TARGET_CONFIG.minActiveTargets then
                toSpawn = math.min(3, TARGET_CONFIG.minActiveTargets - activeCount)
            end
            
            for _ = 1, toSpawn do
                SpawnRandomTarget()
            end
        end
    end
end

--- 处理靶子碰撞（由子弹系统调用）
function M.HandleCollision(targetNode, contactPosition)
    if not GameState.targetNodeMap then return false end
    
    local target = GameState.targetNodeMap[targetNode]
    if not target then return false end
    
    return M.Hit(target)
end

return M
