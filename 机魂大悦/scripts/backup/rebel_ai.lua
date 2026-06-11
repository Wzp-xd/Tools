-- ============================================================================
-- 叛军 AI 模块 - 坦克 & 直升机 AI + 波次管理
-- Rebel AI - Tank & Helicopter AI + Wave System
-- ============================================================================
-- 坦克: 地面单位，炮塔追踪玩家，主炮+机枪
-- 直升机: 空中单位，环绕玩家飞行，机枪射击
-- 波次系统: 分波生成，清空当前波后触发下一波
-- ============================================================================

local CONFIG = require "config"
local Weapons = require "weapons"
local WeaponDefs = require "weapon_defs"
local VehicleBuilder = require "vehicle_builder"

local RebelAI = {}

-- ============================================================================
-- 常量
-- ============================================================================

local AI = CONFIG.RebelAI or {}

-- 默认值（防止 CONFIG 未配置时崩溃）
local TANK_MOVE_SPEED    = AI.TankMoveSpeed or 6.0
local TANK_TURN_SPEED    = AI.TankTurnSpeed or 60.0
local TANK_RANGE_MIN     = AI.TankRangeMin or 40
local TANK_RANGE_IDEAL   = AI.TankRangeIdeal or 100
local TANK_RANGE_MAX     = AI.TankRangeMax or 200
local TANK_CANNON_CD_MIN = AI.TankCannonCooldownMin or 4.0
local TANK_CANNON_CD_MAX = AI.TankCannonCooldownMax or 8.0
local TANK_MG_BURST_DUR  = AI.TankMG_BurstDuration or 2.0
local TANK_MG_CD_MIN     = AI.TankMG_CooldownMin or 2.0
local TANK_MG_CD_MAX     = AI.TankMG_CooldownMax or 4.0

local HELI_MOVE_SPEED    = AI.HeliMoveSpeed or 12.0
local HELI_ALT_MIN       = AI.HeliAltitudeMin or 30
local HELI_ALT_MAX       = AI.HeliAltitudeMax or 60
local HELI_ORBIT_MIN     = AI.HeliOrbitMin or 100
local HELI_ORBIT_MAX     = AI.HeliOrbitMax or 200
local HELI_CIRCLE_SPEED  = AI.HeliCircleSpeed or 15.0
local HELI_MG_BURST_DUR  = AI.HeliMG_BurstDuration or 3.0
local HELI_MG_CD_MIN     = AI.HeliMG_CooldownMin or 2.0
local HELI_MG_CD_MAX     = AI.HeliMG_CooldownMax or 4.0

local SPAWN_DIST         = AI.SpawnDistance or 460

-- 空操作 animator 存根
local NOOP_ANIMATOR = {
    Update = function(self, dt) end,
    Play   = function(self, name) end,
}

-- ============================================================================
-- 武器创建辅助
-- ============================================================================

--- 为载具创建武器实例
---@param weaponType string
---@param mountNode Node
---@return table weapon
local function CreateVehicleWeapon(weaponType, mountNode)
    local def = WeaponDefs.DEFS[weaponType]
    if not def then
        print("[RebelAI] WARNING: weapon type not found: " .. tostring(weaponType))
        return nil
    end
    local magazineSize = def.magazineSize or 999
    local weapon = {
        def = def,
        type = weaponType,
        owner = "enemy",
        ammo = magazineSize,
        magazineSize = magazineSize,
        reloading = false,
        reloadTimer = 0,
        reloadTime = def.reloadTime or 2.0,
        lastFireTime = -999,
        burstRemaining = 0,
        burstNextTime = 0,
        burstParams = nil,
        muzzleFlashTimer = 0,
        mountNode = mountNode,
    }
    return weapon
end

-- ============================================================================
-- 生成单个载具
-- ============================================================================

local vehicleCounter_ = 0

--- 生成坦克
---@param scene Scene
---@param pos Vector3
---@param yaw number
---@param hp number
---@param maxHp number
---@return table enemy
local function SpawnTank(scene, pos, yaw, hp, maxHp)
    vehicleCounter_ = vehicleCounter_ + 1
    local root = scene:CreateChild("Tank_" .. vehicleCounter_)
    root.position = pos
    root.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints = VehicleBuilder.BuildTank(root)

    -- 创建武器
    local wpnCannon = CreateVehicleWeapon("tank_cannon", joints.weaponMountMain)
    local wpnMG     = CreateVehicleWeapon("tank_mg", joints.weaponMountMG)

    local enemy = {
        -- 必要字段 (兼容 enemies_ 列表)
        node = root,
        hp = hp,
        maxHp = maxHp,
        dead = false,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        screenSize = 48,
        isPrimary = false,

        -- 扩展字段
        rebelType = "tank",
        visualHeight = 1.6,
        animator = NOOP_ANIMATOR,
        joints = joints,

        -- 武器
        wpnCannon = wpnCannon,
        wpnMG = wpnMG,

        -- AI 状态
        aiState = "approach",   -- approach / engage / retreat
        turretYaw = yaw,

        -- 武器计时器
        cannonTimer = TANK_CANNON_CD_MIN + math.random() * 2,
        mgFiring = false,
        mgBurstTimer = 0,

        -- 初始延迟
        engageDelay = 1.0 + math.random() * 2.0,
    }

    print(string.format("[RebelAI] Tank spawned at (%.0f, %.0f, %.0f) HP=%d",
        pos.x, pos.y, pos.z, hp))

    return enemy
end

--- 生成直升机
---@param scene Scene
---@param pos Vector3
---@param yaw number
---@param hp number
---@param maxHp number
---@return table enemy
local function SpawnHelicopter(scene, pos, yaw, hp, maxHp)
    vehicleCounter_ = vehicleCounter_ + 1
    local root = scene:CreateChild("Heli_" .. vehicleCounter_)
    root.position = pos
    root.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints = VehicleBuilder.BuildHelicopter(root)

    local wpnMG = CreateVehicleWeapon("heli_mg", joints.weaponMountMG)

    local enemy = {
        node = root,
        hp = hp,
        maxHp = maxHp,
        dead = false,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        screenSize = 48,
        isPrimary = false,

        rebelType = "heli",
        visualHeight = 2.0,
        animator = NOOP_ANIMATOR,
        joints = joints,

        wpnMG = wpnMG,

        aiState = "rising",     -- rising / orbit
        orbitAngle = math.random() * 360,
        orbitRadius = HELI_ORBIT_MIN + math.random() * (HELI_ORBIT_MAX - HELI_ORBIT_MIN),
        targetAlt = HELI_ALT_MIN + math.random() * (HELI_ALT_MAX - HELI_ALT_MIN),
        altTimer = math.random() * 3.0,

        mgFiring = false,
        mgBurstTimer = 0,

        engageDelay = 2.0 + math.random() * 2.0,

        -- 旋翼角度
        mainRotorAngle = 0,
        tailRotorAngle = 0,
    }

    print(string.format("[RebelAI] Helicopter spawned at (%.0f, %.0f, %.0f) HP=%d",
        pos.x, pos.y, pos.z, hp))

    return enemy
end

-- ============================================================================
-- 波次系统
-- ============================================================================

--- 初始化叛军关卡
---@param scene Scene
---@param rebellionCfg table
---@param enemiesList table
---@return table state
function RebelAI.InitLevel(scene, rebellionCfg, enemiesList)
    vehicleCounter_ = 0

    local isContinuous = rebellionCfg.spawnMode == "continuous"

    local state = {
        scene = scene,
        activeRebels = {},
        enemiesList = enemiesList,
        tankHP = rebellionCfg.tankHP or 60,
        tankMaxHP = rebellionCfg.tankMaxHP or 60,
        heliHP = rebellionCfg.heliHP or 40,
        heliMaxHP = rebellionCfg.heliMaxHP or 40,

        -- 通用状态
        totalKills = 0,
        waveActive = false,
        allSpawned = false,

        -- 生成模式
        isContinuous = isContinuous,
    }

    if isContinuous then
        -- 持续生成模式
        state.initialSpawn = rebellionCfg.initialSpawn or 5
        state.spawnInterval = rebellionCfg.spawnInterval or 5.0
        state.spawnPerCheck = rebellionCfg.spawnPerCheck or 5
        state.maxAlive = rebellionCfg.maxAlive or 20
        state.maxTotal = rebellionCfg.maxTotal or 50
        state.killsToWin = rebellionCfg.killsToWin or 50
        state.totalSpawned = 0          -- 已生成总数
        state.spawnTimer = 3.0          -- 首次生成延迟
        state.initialDone = false       -- 初始批次是否已生成
        state.totalToSpawn = state.maxTotal

        print(string.format("[RebelAI] Continuous mode: initial=%d, interval=%.0fs, perCheck=%d, maxAlive=%d, maxTotal=%d, killsToWin=%d",
            state.initialSpawn, state.spawnInterval, state.spawnPerCheck, state.maxAlive, state.maxTotal, state.killsToWin))
    else
        -- 波次模式
        state.waves = rebellionCfg.waves or {}
        state.currentWave = 0
        state.waveTimer = 3.0
        state.timeBetweenWaves = rebellionCfg.timeBetweenWaves or 5.0
        state.totalToSpawn = 0
        for _, wave in ipairs(state.waves) do
            state.totalToSpawn = state.totalToSpawn + (wave.tanks or 0) + (wave.helis or 0)
        end
        print(string.format("[RebelAI] Wave mode: %d waves, %d total enemies",
            #state.waves, state.totalToSpawn))
    end

    return state
end

--- 生成一波敌人
---@param state table
local function SpawnWave(state)
    local waveIdx = state.currentWave
    local wave = state.waves[waveIdx]
    if not wave then return end

    local scene = state.scene
    local tanks = wave.tanks or 0
    local helis = wave.helis or 0
    local total = tanks + helis

    -- 均匀分布在场地边缘一圈
    local angleStep = 360.0 / math.max(total, 1)
    local baseAngle = math.random() * 360

    local idx = 0
    for i = 1, tanks do
        local angle = math.rad(baseAngle + angleStep * idx)
        local spawnX = math.cos(angle) * SPAWN_DIST
        local spawnZ = math.sin(angle) * SPAWN_DIST
        local pos = Vector3(spawnX, 0, spawnZ)
        -- 面朝中心
        local toCenter = Vector3(-spawnX, 0, -spawnZ):Normalized()
        local yaw = math.deg(math.atan(toCenter.x, toCenter.z))

        local enemy = SpawnTank(scene, pos, yaw, state.tankHP, state.tankMaxHP)
        table.insert(state.activeRebels, enemy)
        table.insert(state.enemiesList, enemy)
        idx = idx + 1
    end

    for i = 1, helis do
        local angle = math.rad(baseAngle + angleStep * idx)
        local spawnX = math.cos(angle) * SPAWN_DIST
        local spawnZ = math.sin(angle) * SPAWN_DIST
        local pos = Vector3(spawnX, 2, spawnZ)
        local toCenter = Vector3(-spawnX, 0, -spawnZ):Normalized()
        local yaw = math.deg(math.atan(toCenter.x, toCenter.z))

        local enemy = SpawnHelicopter(scene, pos, yaw, state.heliHP, state.heliMaxHP)
        table.insert(state.activeRebels, enemy)
        table.insert(state.enemiesList, enemy)
        idx = idx + 1
    end

    print(string.format("[RebelAI] Wave %d spawned: %d tanks + %d helis", waveIdx, tanks, helis))
end

--- 持续生成模式：生成指定数量的敌人（坦克/直升机比例随进度变化）
---@param state table
---@param count number
local function SpawnContinuousBatch(state, count)
    if count <= 0 then return end
    local scene = state.scene

    -- 固定比例: 70%坦克, 30%直升机
    local heliChance = 0.3

    local angleStep = 360.0 / math.max(count, 1)
    local baseAngle = math.random() * 360

    local spawnedTanks, spawnedHelis = 0, 0

    for i = 0, count - 1 do
        local angle = math.rad(baseAngle + angleStep * i)
        local spawnX = math.cos(angle) * SPAWN_DIST
        local spawnZ = math.sin(angle) * SPAWN_DIST
        local toCenter = Vector3(-spawnX, 0, -spawnZ):Normalized()
        local yaw = math.deg(math.atan(toCenter.x, toCenter.z))

        local enemy
        if math.random() < heliChance then
            local pos = Vector3(spawnX, 2, spawnZ)
            enemy = SpawnHelicopter(scene, pos, yaw, state.heliHP, state.heliMaxHP)
            spawnedHelis = spawnedHelis + 1
        else
            local pos = Vector3(spawnX, 0, spawnZ)
            enemy = SpawnTank(scene, pos, yaw, state.tankHP, state.tankMaxHP)
            spawnedTanks = spawnedTanks + 1
        end
        table.insert(state.activeRebels, enemy)
        table.insert(state.enemiesList, enemy)
        state.totalSpawned = state.totalSpawned + 1
    end

    print(string.format("[RebelAI] Spawned batch: %d tanks + %d helis (total: %d/%d, alive: %d)",
        spawnedTanks, spawnedHelis, state.totalSpawned, state.maxTotal,
        RebelAI._countAlive(state)))
end

--- 统计存活数
function RebelAI._countAlive(state)
    local alive = 0
    for _, rebel in ipairs(state.activeRebels) do
        if not rebel.dead then alive = alive + 1 end
    end
    return alive
end

-- ============================================================================
-- 主更新
-- ============================================================================

--- 更新波次系统和所有叛军 AI
---@param state table
---@param scene Scene
---@param playerPos Vector3
---@param playerNode Node
---@param dt number
function RebelAI.Update(state, scene, playerPos, playerNode, dt)
    -- ================================================================
    -- 击杀统计（统一在此处理）
    -- ================================================================
    state.totalKills = 0
    for _, rebel in ipairs(state.activeRebels) do
        if rebel.dead then
            state.totalKills = state.totalKills + 1
        end
    end

    -- ================================================================
    -- 波次/生成管理
    -- ================================================================
    if state.isContinuous then
        -- 持续生成模式
        state.spawnTimer = state.spawnTimer - dt

        if not state.initialDone then
            -- 初始批次：延迟结束后生成 initialSpawn 个
            if state.spawnTimer <= 0 then
                local count = math.min(state.initialSpawn, state.maxTotal - state.totalSpawned)
                SpawnContinuousBatch(state, count)
                state.initialDone = true
                state.waveActive = true
                state.spawnTimer = state.spawnInterval
                print(string.format("[RebelAI] Initial batch spawned: %d", count))
            end
        else
            -- 定时检查：每 spawnInterval 秒补充
            if state.spawnTimer <= 0 and state.totalSpawned < state.maxTotal then
                local alive = RebelAI._countAlive(state)
                local canSpawn = math.min(
                    state.spawnPerCheck,                   -- 每次最多生成数
                    state.maxAlive - alive,                 -- 存活上限剩余
                    state.maxTotal - state.totalSpawned     -- 总数上限剩余
                )
                if canSpawn > 0 then
                    SpawnContinuousBatch(state, canSpawn)
                end
                state.spawnTimer = state.spawnInterval
            end
        end

        -- 判断是否全部生成完毕
        if state.totalSpawned >= state.maxTotal then
            state.allSpawned = true
        end

        -- 胜利条件: 击杀数 >= killsToWin
        if state.totalKills >= state.killsToWin then
            state.waveActive = false
            state.allSpawned = true
        end
    else
        -- 波次模式：清空当前波后再生成下一波
        if not state.waveActive then
            state.waveTimer = state.waveTimer - dt
            if state.waveTimer <= 0 then
                state.currentWave = state.currentWave + 1
                if state.currentWave <= #state.waves then
                    SpawnWave(state)
                    state.waveActive = true
                else
                    state.allSpawned = true
                end
            end
        end

        -- 检查当前波是否清空
        if state.waveActive then
            local anyAlive = false
            for _, rebel in ipairs(state.activeRebels) do
                if not rebel.dead then anyAlive = true; break end
            end
            if not anyAlive then
                state.waveActive = false
                state.activeRebels = {}
                if state.currentWave < #state.waves then
                    state.waveTimer = state.timeBetweenWaves
                    print(string.format("[RebelAI] Wave %d cleared! Next wave in %.0fs",
                        state.currentWave, state.timeBetweenWaves))
                else
                    state.allSpawned = true
                    print("[RebelAI] All waves cleared!")
                end
            end
        end
    end

    -- ================================================================
    -- 更新所有存活叛军 AI
    -- ================================================================
    for _, rebel in ipairs(state.activeRebels) do
        if not rebel.dead then
            if rebel.rebelType == "tank" then
                RebelAI.UpdateTank(rebel, scene, playerPos, playerNode, dt)
            else
                RebelAI.UpdateHeli(rebel, scene, playerPos, playerNode, dt)
            end
        end
    end
end

-- ============================================================================
-- 坦克 AI
-- ============================================================================

--- 更新单个坦克
---@param tank table
---@param scene Scene
---@param playerPos Vector3
---@param playerNode Node
---@param dt number
function RebelAI.UpdateTank(tank, scene, playerPos, playerNode, dt)
    local pos = tank.node.position
    local toPlayer = playerPos - pos
    toPlayer.y = 0
    local dist = toPlayer:Length()
    local toPlayerDir = dist > 0.1 and toPlayer:Normalized() or Vector3.FORWARD

    -- 面朝玩家方向的目标 yaw
    local targetYaw = math.deg(math.atan(toPlayerDir.x, toPlayerDir.z))

    -- 车体平滑转向
    local currentRot = tank.node.rotation
    local targetRot = Quaternion(targetYaw, Vector3.UP)
    local newRot = currentRot:Slerp(targetRot, math.min(1.0, TANK_TURN_SPEED * dt / 60.0))
    tank.node.rotation = newRot

    -- ================================================================
    -- 移动状态机
    -- ================================================================
    local moveDir = Vector3.ZERO

    if dist > TANK_RANGE_MAX then
        tank.aiState = "approach"
    elseif dist < TANK_RANGE_MIN then
        tank.aiState = "retreat"
    elseif tank.aiState == "approach" and dist < TANK_RANGE_IDEAL then
        tank.aiState = "engage"
    elseif tank.aiState == "retreat" and dist > TANK_RANGE_MIN + 20 then
        tank.aiState = "engage"
    end

    if tank.aiState == "approach" then
        moveDir = toPlayerDir
    elseif tank.aiState == "retreat" then
        moveDir = toPlayerDir * -1
    end
    -- engage: 不移动，原地射击

    -- 应用移动 (地面)
    if moveDir:Length() > 0.01 then
        pos = pos + moveDir * TANK_MOVE_SPEED * dt
        -- 限制在场地内
        local limit = SPAWN_DIST - 10
        pos.x = math.max(-limit, math.min(limit, pos.x))
        pos.z = math.max(-limit, math.min(limit, pos.z))
    end
    pos.y = 0  -- 始终在地面
    tank.node.position = pos

    -- ================================================================
    -- 炮塔追踪
    -- ================================================================
    if tank.joints.turret then
        local turretToPlayer = playerPos + Vector3(0, 1.7, 0) - tank.joints.turret.worldPosition
        local localDir = tank.node.rotation:Inverse() * turretToPlayer
        local turretTargetYaw = math.deg(math.atan(localDir.x, localDir.z))

        -- 平滑旋转
        local currentTurretRot = tank.joints.turret.rotation
        local targetTurretRot = Quaternion(turretTargetYaw, Vector3.UP)
        tank.joints.turret.rotation = currentTurretRot:Slerp(targetTurretRot,
            math.min(1.0, 90.0 * dt / 60.0))
    end

    -- ================================================================
    -- 武器射击 (需要进入交战范围 + 延迟)
    -- ================================================================
    tank.engageDelay = math.max(0, tank.engageDelay - dt)
    if tank.engageDelay > 0 then return end

    local targetPos = playerPos + Vector3(0, 1.7, 0)

    -- 主炮
    if tank.wpnCannon then
        tank.cannonTimer = tank.cannonTimer - dt
        if tank.cannonTimer <= 0 and dist < TANK_RANGE_MAX + 50 then
            Weapons.TryFire(tank.wpnCannon, scene, targetPos, true, playerNode)
            tank.cannonTimer = TANK_CANNON_CD_MIN + math.random() * (TANK_CANNON_CD_MAX - TANK_CANNON_CD_MIN)
        end
        Weapons.UpdateBurst(tank.wpnCannon, dt)
        Weapons.UpdateReload(tank.wpnCannon, dt)
        Weapons.UpdateMuzzleFlash(tank.wpnCannon, dt)
    end

    -- 机枪 (burst循环)
    if tank.wpnMG then
        tank.mgBurstTimer = tank.mgBurstTimer + dt
        if tank.mgFiring then
            if dist < TANK_RANGE_MAX + 30 then
                Weapons.TryFire(tank.wpnMG, scene, targetPos, true, playerNode)
            end
            if tank.mgBurstTimer >= TANK_MG_BURST_DUR then
                tank.mgFiring = false
                tank.mgBurstTimer = 0
            end
        else
            local cd = TANK_MG_CD_MIN + math.random() * (TANK_MG_CD_MAX - TANK_MG_CD_MIN)
            if tank.mgBurstTimer >= cd then
                tank.mgFiring = true
                tank.mgBurstTimer = 0
            end
        end
        Weapons.UpdateBurst(tank.wpnMG, dt)
        Weapons.UpdateReload(tank.wpnMG, dt)
        Weapons.UpdateMuzzleFlash(tank.wpnMG, dt)
    end
end

-- ============================================================================
-- 直升机 AI
-- ============================================================================

--- 更新单个直升机
---@param heli table
---@param scene Scene
---@param playerPos Vector3
---@param playerNode Node
---@param dt number
function RebelAI.UpdateHeli(heli, scene, playerPos, playerNode, dt)
    local pos = heli.node.position

    -- ================================================================
    -- 旋翼旋转动画
    -- ================================================================
    if heli.joints.mainRotor then
        heli.mainRotorAngle = (heli.mainRotorAngle + 720 * dt) % 360
        heli.joints.mainRotor.rotation = Quaternion(heli.mainRotorAngle, Vector3.UP)
    end
    if heli.joints.tailRotor then
        heli.tailRotorAngle = (heli.tailRotorAngle + 1080 * dt) % 360
        heli.joints.tailRotor.rotation = Quaternion(heli.tailRotorAngle, Vector3.UP)
    end

    -- ================================================================
    -- 移动
    -- ================================================================
    if heli.aiState == "rising" then
        -- 上升到目标高度
        pos.y = pos.y + HELI_MOVE_SPEED * dt
        if pos.y >= heli.targetAlt then
            pos.y = heli.targetAlt
            heli.aiState = "orbit"
        end
        -- 同时向中心移动
        local toCenterH = Vector3(-pos.x, 0, -pos.z)
        if toCenterH:Length() > heli.orbitRadius then
            local moveH = toCenterH:Normalized() * HELI_MOVE_SPEED * 0.5 * dt
            pos.x = pos.x + moveH.x
            pos.z = pos.z + moveH.z
        end
    elseif heli.aiState == "orbit" then
        -- 环绕玩家轨道飞行
        heli.orbitAngle = heli.orbitAngle + HELI_CIRCLE_SPEED * dt
        local rad = math.rad(heli.orbitAngle)
        local targetX = playerPos.x + math.cos(rad) * heli.orbitRadius
        local targetZ = playerPos.z + math.sin(rad) * heli.orbitRadius

        -- 平滑趋近轨道位置
        local dx = targetX - pos.x
        local dz = targetZ - pos.z
        local hSpeed = HELI_MOVE_SPEED * dt
        pos.x = pos.x + dx * math.min(1.0, hSpeed / math.max(1, math.sqrt(dx*dx + dz*dz)))
        pos.z = pos.z + dz * math.min(1.0, hSpeed / math.max(1, math.sqrt(dx*dx + dz*dz)))

        -- 高度微浮动
        heli.altTimer = heli.altTimer + dt
        local altTarget = heli.targetAlt + math.sin(heli.altTimer * 0.5) * 5.0
        pos.y = pos.y + (altTarget - pos.y) * math.min(1.0, 2.0 * dt)
    end

    -- 限制在场地内
    local limit = SPAWN_DIST - 10
    pos.x = math.max(-limit, math.min(limit, pos.x))
    pos.z = math.max(-limit, math.min(limit, pos.z))
    pos.y = math.max(5, pos.y)  -- 不低于5m

    heli.node.position = pos

    -- ================================================================
    -- 面朝玩家
    -- ================================================================
    local toPlayer = playerPos - pos
    toPlayer.y = 0
    if toPlayer:Length() > 0.1 then
        local targetYaw = math.deg(math.atan(toPlayer.x / toPlayer:Length(), toPlayer.z / toPlayer:Length()))
        local dir = toPlayer:Normalized()
        targetYaw = math.deg(math.atan(dir.x, dir.z))
        local currentRot = heli.node.rotation
        local targetRot = Quaternion(targetYaw, Vector3.UP)
        heli.node.rotation = currentRot:Slerp(targetRot, math.min(1.0, 3.0 * dt))
    end

    -- ================================================================
    -- 机身微倾斜
    -- ================================================================
    -- 在 orbit 状态向运动方向微前倾
    if heli.aiState == "orbit" then
        local pitchTilt = -5.0  -- 前倾5度
        local rollTilt = math.sin(math.rad(heli.orbitAngle)) * 8.0  -- 侧倾
        local baseRot = heli.node.rotation
        local tiltRot = Quaternion(pitchTilt, Vector3.RIGHT) * Quaternion(rollTilt, Vector3.FORWARD)
        -- 只对模型节点施加倾斜，不影响根节点朝向
        if heli.joints.fuselage then
            heli.joints.fuselage.rotation = tiltRot
        end
    end

    -- ================================================================
    -- 武器射击
    -- ================================================================
    heli.engageDelay = math.max(0, heli.engageDelay - dt)
    if heli.engageDelay > 0 then return end

    local targetPos = playerPos + Vector3(0, 1.7, 0)
    local dist = (playerPos - pos):Length()

    if heli.wpnMG then
        heli.mgBurstTimer = heli.mgBurstTimer + dt
        if heli.mgFiring then
            if dist < HELI_ORBIT_MAX + 50 then
                Weapons.TryFire(heli.wpnMG, scene, targetPos, true, playerNode)
            end
            if heli.mgBurstTimer >= HELI_MG_BURST_DUR then
                heli.mgFiring = false
                heli.mgBurstTimer = 0
            end
        else
            local cd = HELI_MG_CD_MIN + math.random() * (HELI_MG_CD_MAX - HELI_MG_CD_MIN)
            if heli.mgBurstTimer >= cd then
                heli.mgFiring = true
                heli.mgBurstTimer = 0
            end
        end
        Weapons.UpdateBurst(heli.wpnMG, dt)
        Weapons.UpdateReload(heli.wpnMG, dt)
        Weapons.UpdateMuzzleFlash(heli.wpnMG, dt)
    end
end

-- ============================================================================
-- 获取状态信息（供 HUD 显示）
-- ============================================================================

--- 获取叛军状态信息
---@param state table
---@return table info
function RebelAI.GetStatus(state)
    if not state then return nil end
    local alive = RebelAI._countAlive(state)

    if state.isContinuous then
        return {
            isContinuous = true,
            totalKills = state.totalKills,
            killsToWin = state.killsToWin,
            totalSpawned = state.totalSpawned,
            maxTotal = state.maxTotal,
            waveAlive = alive,
            allSpawned = state.allSpawned,
            waveActive = state.waveActive,
            totalToSpawn = state.maxTotal,
        }
    else
        return {
            isContinuous = false,
            currentWave = state.currentWave,
            totalWaves = #state.waves,
            totalKills = state.totalKills,
            totalToSpawn = state.totalToSpawn,
            waveAlive = alive,
            allSpawned = state.allSpawned,
            waveActive = state.waveActive,
            waveTimer = state.waveTimer,
        }
    end
end

return RebelAI
