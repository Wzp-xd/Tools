-- ============================================================================
-- enemy_spawner.lua — 敌人生成管理
-- 从 main.lua L1250-1406 提取
-- ============================================================================

local CONFIG = require "config"
local GS = require "game_state"
local MechBuilder = require "mech_builder"
local MechAnimator = require "mech_animator"
local MeleeAI = require "melee_ai"
local VehicleBuilder = require "vehicle_builder"
local Weapons = require "weapons"

local EnemySpawner = {}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 给生成点加随机水平偏移，避免敌人重叠
---@param pos Vector3
---@return Vector3
local function RandomOffsetPos(pos)
    local ox = (math.random() - 0.5) * 6
    local oz = (math.random() - 0.5) * 6
    return Vector3(pos.x + ox, pos.y, pos.z + oz)
end

--- 基于玩家位置生成随机出生点（距离50~200m，Y=30m空投）
---@return Vector3 pos
---@return number yaw
function EnemySpawner.RandomSpawnAroundPlayer()
    local playerPos = GS.mechNode and GS.mechNode.worldPosition or Vector3(0, 0, 0)
    local dist = 50 + math.random() * 150
    local angle = math.random() * 2 * math.pi
    local x = playerPos.x + math.cos(angle) * dist
    local z = playerPos.z + math.sin(angle) * dist
    local yaw = math.deg(math.atan(playerPos.x - x, playerPos.z - z))
    return Vector3(x, 30, z), yaw
end

-- ============================================================================
-- 生成
-- ============================================================================

--- 在指定位置生成单个敌人
---@param pos Vector3
---@param yaw number
---@return table enemy
function EnemySpawner.SpawnEnemy(pos, yaw)
    local scene = GS.scene
    GS.enemyCounter = GS.enemyCounter + 1
    local enemyRoot = scene:CreateChild("Enemy_" .. GS.enemyCounter)
    enemyRoot.position = pos
    enemyRoot.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints = MechBuilder.Build(enemyRoot)
    local animator = MechAnimator.Create(joints)
    animator:Play("idle")

    -- 敌人机体发光效果
    local glowNode = enemyRoot:CreateChild("EnemyGlow")
    glowNode.position = Vector3(0, 1.8, 0)
    local glowLight = glowNode:CreateComponent("Light")
    glowLight.lightType = LIGHT_POINT
    glowLight.range = 2.0
    glowLight.color = Color(1.0, 0.3, 0.2)
    glowLight.brightness = 0.4
    glowLight.castShadows = false

    local enemy = {
        node = enemyRoot,
        animator = animator,
        joints = joints,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        hp = 100,
        maxHp = 100,
    }
    table.insert(GS.enemies, enemy)
    return enemy
end

--- 生成无AI静态载具（坦克/直升机）作为靶标
---@param pos Vector3
---@param yaw number
---@param vehicleType string "tank"|"helicopter"
---@return table enemy
function EnemySpawner.SpawnStaticVehicle(pos, yaw, vehicleType)
    local scene = GS.scene
    GS.enemyCounter = GS.enemyCounter + 1
    local root = scene:CreateChild("Vehicle_" .. vehicleType .. "_" .. GS.enemyCounter)
    root.position = pos
    root.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints
    local hp, visualHeight
    if vehicleType == "tank" then
        modelNode, joints = VehicleBuilder.BuildTank(root)
        hp = 40
        visualHeight = 1.6
    else
        modelNode, joints = VehicleBuilder.BuildHelicopter(root)
        hp = 10
        visualHeight = 2.0
        root.position = Vector3(pos.x, 15 + math.random() * 10, pos.z)
    end

    -- 红色标记光
    local glowNode = root:CreateChild("VehicleGlow")
    glowNode.position = Vector3(0, visualHeight * 0.5, 0)
    local glowLight = glowNode:CreateComponent("Light")
    glowLight.lightType = LIGHT_POINT
    glowLight.range = 3.0
    glowLight.color = Color(1.0, 0.3, 0.2)
    glowLight.brightness = 0.5
    glowLight.castShadows = false

    local enemy = {
        node = root,
        joints = joints,
        vehicleType = vehicleType,
        visualHeight = visualHeight,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        hp = hp,
        maxHp = hp,
    }
    table.insert(GS.enemies, enemy)
    return enemy
end

--- 根据关卡配置生成全部敌人
function EnemySpawner.CreateAll()
    local enemyCount = (GS.currentLevel and GS.currentLevel.enemyCount) or 5
    for i = 1, enemyCount do
        local pos, yaw = EnemySpawner.RandomSpawnAroundPlayer()
        EnemySpawner.SpawnEnemy(pos, yaw)
    end

    -- 生成近战敌人
    local spawnMelee = true
    if GS.currentLevel and GS.currentLevel.hasMelee == false then
        spawnMelee = false
    end
    if spawnMelee then
        local meleeCount = CONFIG.MeleeAI.SpawnCount or 3
        for i = 1, meleeCount do
            local pos, yaw = EnemySpawner.RandomSpawnAroundPlayer()
            local meleeEnemy = MeleeAI.Spawn(GS.scene, pos, yaw)
            table.insert(GS.enemies, meleeEnemy)
            table.insert(GS.meleeEnemies, meleeEnemy)
        end
    end

    -- 生成静态载具靶标
    if GS.currentLevel and GS.currentLevel.staticVehicles then
        local sv = GS.currentLevel.staticVehicles
        for i = 1, (sv.tanks or 0) do
            local pos, yaw = EnemySpawner.RandomSpawnAroundPlayer()
            EnemySpawner.SpawnStaticVehicle(pos, yaw, "tank")
        end
        for i = 1, (sv.helicopters or 0) do
            local pos, yaw = EnemySpawner.RandomSpawnAroundPlayer()
            EnemySpawner.SpawnStaticVehicle(pos, yaw, "helicopter")
        end
    end

    print("[Game] Created " .. #GS.enemies .. " enemies (" .. #GS.meleeEnemies .. " melee)")
    Weapons.SetEnemies(GS.enemies)
end

return EnemySpawner
