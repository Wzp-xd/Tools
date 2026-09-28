-- ============================================================================
-- Shared.lua - 多人游戏共享代码
-- 包含配置、工具函数、场景创建等服务端/客户端共用逻辑
-- ============================================================================

local WeaponConfig = require "network.modules.WeaponConfig"

local Shared = {}

-- 导出武器配置供其他模块使用
Shared.WeaponConfig = WeaponConfig

-- ============================================================================
-- 游戏配置
-- ============================================================================

Shared.Settings = {
    -- 玩家配置
    Player = {
        Prefab = "uuid://DEkZaUTQvLlCdjdIzpnHa4n-",
        Height = 1.8,
        Radius = 0.35,
        WalkSpeed = 0.025,
        RunSpeed = 0.1,
        CrouchHeightDelta = 0.3,       -- 蹲下时高度降低量（碰撞盒、镜头、爆头判定均降低此值）
        CrouchSpeedMultiplier = 0.5,  -- 蹲下时速度倍率
        AirControlFactor = 1.0,  -- 空中完全控制移动方向
        EnableWalkMode = true,
        StartPos = Vector3(0, 1, 0),
    },

    -- FSM 配置（统一状态机，通过 weaponType 参数切换动画）
    FSM = {
        Unified = "FSM/Unified.fsm",
    },

    -- 武器类型枚举（对应 Unified.fsm 中的 weaponType 参数）
    WeaponType = {
        NORMAL = 0,     -- 无武器
        RIFLE = 1,      -- 步枪
        DAGGER = 3,     -- 匕首
    },

    -- 相机配置
    Camera = {
        normal = { distance = 5.0, offset = Vector3(0, 1.7, 0), fov = 45.0 },
        armed = { distance = 4.0, offset = Vector3(0.6, 1.6, 0), fov = 45.0 },
        aiming = { distance = 2.0, offset = Vector3(0.4, 1.5, 0), fov = 32.0 },
        transitionSpeed = 8.0,
        farClip = 300.0,
    },

    -- 战斗配置
    Combat = {
        MaxHealth = 100,
        RespawnTime = 3.0,
        DefaultWeapon = "g17",  -- 默认武器（1号枪）
        BallisticMode = true,  -- true=弹道模式（逐帧射线检测）, false=射线模式（即时判定，弹道仅做表现，速度x10）
    },

    -- 输入灵敏度
    Input = {
        MouseSensitivity = 0.1,
    },

    -- 调试配置
    Debug = {
        ShowPhysics = false,  -- 显示物理碰撞盒（测试模式）
    },

    -- 网络配置
    Network = {
        MaxPlayers = 4,
    },

    -- 出生点
    SpawnPoints = {
        Vector3(-15, 1.0, -15),
        Vector3(15, 1.0, -15),
        Vector3(-15, 1.0, 15),
        Vector3(15, 1.0, 15),
    },
}

-- 控制按钮标志（匹配 C++ CTRL_* 常量）
Shared.CTRL = {
    FORWARD = 1,
    BACK = 2,
    LEFT = 4,
    RIGHT = 8,
    JUMP = 16,
    RUN = 32,
    SHOOT = 64,
    CROUCH = 128,
}

-- 网络事件
Shared.EVENTS = {
    CLIENT_READY = "ClientReady",
    ASSIGN_ROLE = "AssignRole",
    HEALTH_UPDATE = "HealthUpdate",
    PLAYER_DIED = "PlayerDied",
    PLAYER_RESPAWN = "PlayerRespawn",
    TOGGLE_ARMED = "ToggleArmed",
    WEAPON_SWITCH = "WeaponSwitch",    -- 切换武器
    WEAPON_RELOAD = "WeaponReload",    -- 换弹
    HIT_EFFECT = "HitEffect",          -- 击中特效同步
    SHOOT_REQUEST = "ShootRequest",    -- 射击请求（客户端 → 服务器）
    BULLET_CREATE = "BulletCreate",    -- 创建子弹（服务器 → 客户端）
    BULLET_HIT = "BulletHit",          -- 子弹命中（服务器 → 客户端）
    TARGET_SYNC = "TargetSync",        -- 移动靶位置同步（服务器 → 客户端）
    SERVER_LOG = "ServerLog",          -- 服务器日志转发（服务器 → 客户端）
}

-- 节点变量（用于网络同步）
Shared.VARS = {
    IS_ROLE = "IsRole",
    IS_ARMED = "IsArmed",
    WEAPON_ID = "WeaponId",      -- 当前武器 ID
    AMMO_MAG = "AmmoMag",        -- 弹匣剩余
    AMMO_RESERVE = "AmmoReserve", -- 备弹
    IS_CROUCHING = "IsCrouching", -- 蹲下状态
}

-- ============================================================================
-- 工具函数
-- ============================================================================

function Shared.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

--- 生成随机水平偏移，避免多个角色出生在同一位置叠加
local function RandomHorizontalOffset(pos)
    local ox = (math.random() - 0.5) * 4  -- -2 ~ +2 米
    local oz = (math.random() - 0.5) * 4
    return Vector3(pos.x + ox, pos.y, pos.z + oz)
end

function Shared.GetRandomSpawnPoint()
    local index = math.random(1, #Shared.Settings.SpawnPoints)
    return RandomHorizontalOffset(Shared.Settings.SpawnPoints[index])
end

function Shared.GetSpawnPointByIndex(index)
    local i = ((index - 1) % #Shared.Settings.SpawnPoints) + 1
    return RandomHorizontalOffset(Shared.Settings.SpawnPoints[i])
end

-- ============================================================================
-- 材质创建
-- ============================================================================

function Shared.CreatePBRMaterial(color, metallic, roughness)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 1.0)))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(metallic))
    material:SetShaderParameter("Roughness", Variant(roughness))
    return material
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function Shared.CreateScene(isServer)
    local scene = Scene()

    scene:CreateComponent("Octree", LOCAL)
    scene:CreateComponent("DebugRenderer", LOCAL)

    local physicsWorld = scene:CreateComponent("PhysicsWorld", LOCAL)
    physicsWorld:SetGravity(Vector3(0, -20.0, 0))

    -- 客户端创建光照
    if not isServer then
        Shared.CreateLighting(scene)
    end

    -- 创建地图
    Shared.CreateMap(scene, isServer)

    return scene
end

function Shared.CreateLighting(scene)
    -- 环境区域
    local zoneNode = scene:CreateChild("Zone", LOCAL)
    local zone = zoneNode:CreateComponent("Zone", LOCAL)
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.4, 0.4, 0.4)
    zone.fogColor = Color(0.6, 0.7, 0.8)
    zone.fogStart = 80.0
    zone.fogEnd = 200.0

    -- 太阳光
    local lightNode = scene:CreateChild("DirectionalLight", LOCAL)
    lightNode.direction = Vector3(0.6, -1.0, 0.8)
    local light = lightNode:CreateComponent("Light", LOCAL)
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(0.9, 0.85, 0.8)
    light.castShadows = true
    light.shadowBias = BiasParameters(0.00025, 0.5)
    light.shadowCascade = CascadeParameters(10.0, 50.0, 200.0, 0.0, 0.8)
end

-- ============================================================================
-- 地图创建
-- ============================================================================

function Shared.CreateMap(scene, isServer)
    local mapSize = 50
    local halfSize = mapSize / 2
    local wallHeight = 3.0

    -- 地面
    local floor = scene:CreateChild("Floor", LOCAL)
    floor.position = Vector3(0, -0.5, 0)
    floor.scale = Vector3(mapSize, 1, mapSize)
    if not isServer then
        local floorModel = floor:CreateComponent("StaticModel", LOCAL)
        floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        floorModel:SetMaterial(Shared.CreatePBRMaterial(Color(0.3, 0.3, 0.35), 0.0, 0.8))
    end
    local floorBody = floor:CreateComponent("RigidBody", LOCAL)
    floorBody:SetCollisionLayer(1)
    local floorShape = floor:CreateComponent("CollisionShape", LOCAL)
    floorShape:SetBox(Vector3(1, 1, 1))

    -- 边界墙
    Shared.CreateWall(scene, Vector3(0, wallHeight / 2, -halfSize), Vector3(mapSize, wallHeight, 1), isServer)
    Shared.CreateWall(scene, Vector3(0, wallHeight / 2, halfSize), Vector3(mapSize, wallHeight, 1), isServer)
    Shared.CreateWall(scene, Vector3(-halfSize, wallHeight / 2, 0), Vector3(1, wallHeight, mapSize), isServer)
    Shared.CreateWall(scene, Vector3(halfSize, wallHeight / 2, 0), Vector3(1, wallHeight, mapSize), isServer)

    -- 掩体
    Shared.CreateCover(scene, Vector3(0, 1, 0), Vector3(5, 2, 5), Color(0.5, 0.4, 0.3), isServer)
    Shared.CreateCover(scene, Vector3(-12, 0.75, -12), Vector3(3, 1.5, 3), Color(0.4, 0.5, 0.4), isServer)
    Shared.CreateCover(scene, Vector3(12, 0.75, -12), Vector3(3, 1.5, 3), Color(0.4, 0.5, 0.4), isServer)
    Shared.CreateCover(scene, Vector3(-12, 0.75, 12), Vector3(3, 1.5, 3), Color(0.4, 0.5, 0.4), isServer)
    Shared.CreateCover(scene, Vector3(12, 0.75, 12), Vector3(3, 1.5, 3), Color(0.4, 0.5, 0.4), isServer)

    -- 长墙掩体
    Shared.CreateCover(scene, Vector3(0, 0.75, 10), Vector3(8, 1.5, 0.5), Color(0.45, 0.45, 0.5), isServer)
    Shared.CreateCover(scene, Vector3(0, 0.75, -10), Vector3(8, 1.5, 0.5), Color(0.45, 0.45, 0.5), isServer)

    -- 目标球（服务端和客户端都创建，服务端用于碰撞检测）
    Shared.CreateTarget(scene, Vector3(18, 1.5, 18), isServer)
    Shared.CreateTarget(scene, Vector3(-18, 1.5, 18), isServer)
    Shared.CreateTarget(scene, Vector3(18, 1.5, -18), isServer)
    Shared.CreateTarget(scene, Vector3(-18, 1.5, -18), isServer)

    -- 移动靶（蓝色，左右移动）
    Shared.MovingTargets = {}  -- 移动靶已禁用
end

function Shared.CreateWall(scene, position, size, isServer)
    local wall = scene:CreateChild("Wall", LOCAL)
    wall.position = position
    wall.scale = size

    if not isServer then
        local model = wall:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(Shared.CreatePBRMaterial(Color(0.4, 0.4, 0.45), 0.0, 0.7))
    end

    local body = wall:CreateComponent("RigidBody", LOCAL)
    body:SetCollisionLayer(1)
    local shape = wall:CreateComponent("CollisionShape", LOCAL)
    shape:SetBox(Vector3(1, 1, 1))
end

function Shared.CreateCover(scene, position, size, color, isServer)
    local cover = scene:CreateChild("Cover", LOCAL)
    cover.position = position
    cover.scale = size

    if not isServer then
        local model = cover:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(Shared.CreatePBRMaterial(color, 0.1, 0.6))
        model.castShadows = true
    end

    local body = cover:CreateComponent("RigidBody", LOCAL)
    body:SetCollisionLayer(1)
    local shape = cover:CreateComponent("CollisionShape", LOCAL)
    shape:SetBox(Vector3(1, 1, 1))
end

-- 靶子ID管理（客户端和服务器使用相同的ID序列）
Shared.nextTargetId = 1
Shared.TargetRegistry = {}  -- ID -> node 映射

function Shared.CreateTarget(scene, position, isServer)
    local targetNode = scene:CreateChild("Target", LOCAL)
    targetNode.position = position
    targetNode.scale = Vector3(1, 1, 1)
    
    -- 分配唯一ID
    local targetId = Shared.nextTargetId
    Shared.nextTargetId = Shared.nextTargetId + 1
    targetNode:SetVar("TargetId", Variant(targetId))
    Shared.TargetRegistry[targetId] = targetNode

    -- 客户端创建可见模型
    if not isServer then
        local model = targetNode:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.2, 0.2, 1.0)))
        mat:SetShaderParameter("Roughness", Variant(0.5))
        mat:SetShaderParameter("Metallic", Variant(0.1))
        model:SetMaterial(mat)
        model.castShadows = true
    end

    -- 服务端和客户端都添加物理碰撞体（用于射线检测）
    local body = targetNode:CreateComponent("RigidBody", LOCAL)
    body:SetCollisionLayer(64)  -- TARGET 碰撞层
    local shape = targetNode:CreateComponent("CollisionShape", LOCAL)
    shape:SetSphere(1.0)  -- 球体半径
    
    return targetNode
end

-- 移动靶数据存储
Shared.MovingTargets = {}

function Shared.CreateMovingTarget(scene, position, moveAxis, moveRange, moveSpeed, isServer)
    local targetNode = scene:CreateChild("MovingTarget", LOCAL)
    targetNode.position = position
    targetNode.scale = Vector3(1, 1, 1)
    
    -- 分配唯一ID
    local targetId = Shared.nextTargetId
    Shared.nextTargetId = Shared.nextTargetId + 1
    targetNode:SetVar("TargetId", Variant(targetId))
    Shared.TargetRegistry[targetId] = targetNode

    -- 客户端创建可见模型
    if not isServer then
        local model = targetNode:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.7, 0.9, 1.0)))  -- 蓝色区分
        mat:SetShaderParameter("Roughness", Variant(0.4))
        mat:SetShaderParameter("Metallic", Variant(0.2))
        model:SetMaterial(mat)
        model.castShadows = true
    end

    -- 服务端和客户端都添加物理碰撞体（用于射线检测）
    local body = targetNode:CreateComponent("RigidBody", LOCAL)
    body:SetCollisionLayer(64)  -- TARGET 碰撞层
    body.kinematic = true  -- 运动学刚体，手动控制位置
    local shape = targetNode:CreateComponent("CollisionShape", LOCAL)
    shape:SetSphere(1.0)

    -- 存储移动参数（使用固定相位偏移，确保客户端和服务器一致）
    local index = #Shared.MovingTargets + 1
    table.insert(Shared.MovingTargets, {
        node = targetNode,
        basePos = position,
        axis = moveAxis or Vector3.RIGHT,  -- 移动轴
        range = moveRange or 5.0,           -- 移动范围
        speed = moveSpeed or 2.0,           -- 移动速度
        phaseOffset = index * math.pi / 2,  -- 固定相位偏移（基于索引）
    })

    return targetNode
end

-- 更新所有移动靶位置（使用绝对时间确保客户端和服务器同步）
function Shared.UpdateMovingTargets(dt)
    -- 使用引擎的绝对时间，确保客户端和服务器计算结果一致
    local currentTime = time.elapsedTime
    
    for _, target in ipairs(Shared.MovingTargets) do
        if target.node then
            -- 基于绝对时间计算相位，而不是累积 dt
            local phase = currentTime * target.speed + target.phaseOffset
            local offset = math.sin(phase) * target.range
            local newPos = target.basePos + target.axis * offset
            target.node.position = newPos
            
            -- 同步刚体位置（kinematic 刚体需要手动同步）
            local body = target.node:GetComponent("RigidBody")
            if body then
                body:SetTransform(newPos, target.node.rotation)
            end
        end
    end
end

-- ============================================================================
-- 注册远程事件
-- ============================================================================

function Shared.RegisterEvents()
    for _, eventName in pairs(Shared.EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

return Shared
