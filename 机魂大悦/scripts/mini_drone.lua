-- ============================================================================
-- mini_drone.lua — 小型无人机敌人
-- BOSS一阶段放出的小型武装无人机（50HP、小机枪）
-- ============================================================================

local CONFIG = require "config"
local GS = require "game_state"
local SceneBuilder = require "scene_builder"
local Weapons = require "weapons"

local MiniDrone = {}

-- ============================================================================
-- 配置
-- ============================================================================

local AI = CONFIG.BossAI
local MOVE_SPEED = AI.MiniDroneMoveSpeed
local ORBIT_RADIUS = AI.MiniDroneOrbitRadius
local ALTITUDE_MIN = AI.MiniDroneAltitudeMin or 25.0
local ALTITUDE_MAX = AI.MiniDroneAltitudeMax or 40.0
local DEPLOY_DIST = AI.MiniDroneDeployDist or 30.0
local DEPLOY_SPEED = AI.MiniDroneDeploySpeed or 25.0
local MG_FIRE_RATE = AI.MiniDroneMGFireRate
local MG_DAMAGE = AI.MiniDroneMGDamage
local MG_BULLET_SPEED = AI.MiniDroneMGBulletSpeed
local MG_BURST_DUR = AI.MiniDroneMGBurstDur
local MG_COOLDOWN = AI.MiniDroneMGCooldown

-- ============================================================================
-- 死亡特效列表（模块级，统一更新清理）
-- ============================================================================

local deathEffects_ = {}

-- ============================================================================
-- 材质缓存
-- ============================================================================

local mats_ = nil

local function GetMaterials()
    if mats_ then return mats_ end
    local function PBR(c, m, r, e)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(c))
        mat:SetShaderParameter("Metallic", Variant(m))
        mat:SetShaderParameter("Roughness", Variant(r))
        if e then mat:SetShaderParameter("MatEmissiveColor", Variant(e)) end
        return mat
    end
    mats_ = {
        body    = PBR(Color(0.10, 0.10, 0.12, 1.0), 0.6, 0.5),
        arm     = PBR(Color(0.07, 0.07, 0.09, 1.0), 0.4, 0.6),
        rotor   = PBR(Color(0.15, 0.15, 0.18, 0.7), 0.3, 0.4),
        gun     = PBR(Color(0.08, 0.08, 0.10, 1.0), 0.9, 0.25),
        accent  = PBR(Color(0.8, 0.2, 0.1, 1.0), 0.3, 0.5, Color(2.0, 0.4, 0.2)),
    }
    return mats_
end

-- ============================================================================
-- 无人机构建
-- ============================================================================

--- 构建小型无人机3D模型（简化版四轴无人机，约1.5m宽）
---@param parentNode Node
---@return Node modelNode
---@return Node firePoint 发射点节点
local function BuildDroneModel(parentNode)
    local m = GetMaterials()
    local modelNode = parentNode:CreateChild("DroneModel")
    modelNode.scale = Vector3(2.0, 2.0, 2.0)  -- 200% 尺寸

    -- 中心机身（小方块 0.4x0.15x0.4）
    local bodyNode = modelNode:CreateChild("Body")
    bodyNode.scale = Vector3(0.4, 0.15, 0.4)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bodyModel:SetMaterial(m.body)
    bodyModel.castShadows = true

    -- 4个臂 + 旋翼盘
    local arms = {
        { name = "FL", yaw = -45 },
        { name = "FR", yaw = 45 },
        { name = "RL", yaw = -135 },
        { name = "RR", yaw = 135 },
    }
    for _, armDef in ipairs(arms) do
        local armPivot = modelNode:CreateChild("Arm_" .. armDef.name)
        armPivot.rotation = Quaternion(armDef.yaw, Vector3.UP)

        -- 臂杆
        local beam = armPivot:CreateChild("ArmBeam")
        beam.position = Vector3(0, 0, 0.45)
        beam.scale = Vector3(0.06, 0.04, 0.5)
        local bm = beam:CreateComponent("StaticModel")
        bm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        bm:SetMaterial(m.arm)
        bm.castShadows = true

        -- 旋翼盘
        local rotorNode = armPivot:CreateChild("Rotor")
        rotorNode.position = Vector3(0, 0.06, 0.7)
        rotorNode.scale = Vector3(0.5, 0.02, 0.5)
        local rm = rotorNode:CreateComponent("StaticModel")
        rm:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        rm:SetMaterial(m.rotor)
        rm.castShadows = false
    end

    -- 底部机枪
    local gunNode = modelNode:CreateChild("Gun")
    gunNode.position = Vector3(0, -0.12, 0.15)
    gunNode.scale = Vector3(0.05, 0.05, 0.25)
    local gm = gunNode:CreateComponent("StaticModel")
    gm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    gm:SetMaterial(m.gun)
    gm.castShadows = true

    -- 发射点
    local firePoint = modelNode:CreateChild("FirePoint")
    firePoint.position = Vector3(0, -0.12, 0.28)

    -- 红色指示灯
    local lightNode = modelNode:CreateChild("Indicator")
    lightNode.position = Vector3(0, 0.1, 0)
    lightNode.scale = Vector3(0.06, 0.06, 0.06)
    local lm = lightNode:CreateComponent("StaticModel")
    lm:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    lm:SetMaterial(m.accent)
    lm.castShadows = false

    -- 点光源标记
    local glowNode = modelNode:CreateChild("Glow")
    glowNode.position = Vector3(0, 0, 0)
    local glow = glowNode:CreateComponent("Light")
    glow.lightType = LIGHT_POINT
    glow.range = 3.0
    glow.color = Color(1.0, 0.3, 0.2)
    glow.brightness = 0.6
    glow.castShadows = false

    return modelNode, firePoint
end

-- ============================================================================
-- 生成
-- ============================================================================

--- 生成小型无人机
---@param scene Scene
---@param spawnPos Vector3
---@param hp number
---@param deployDir Vector3|nil 散开方向（从BOSS向外），nil则直接进入approach
---@return table drone
function MiniDrone.Spawn(scene, spawnPos, hp, deployDir)
    local root = scene:CreateChild("MiniDrone")
    root.position = spawnPos

    local modelNode, firePoint = BuildDroneModel(root)

    -- 创建简易机枪武器
    local mgWeapon = Weapons.CreateWeapon("machinegun", firePoint, "enemy")
    -- 覆盖伤害和速度
    if mgWeapon then
        mgWeapon.def = {
            damage = MG_DAMAGE,
            bulletSpeed = MG_BULLET_SPEED,
            bulletLife = 3.0,
            fireRate = 1.0 / MG_FIRE_RATE,  -- 间隔→次/秒
            spread = 0.03,
            tracking = false,
            bulletScale = Vector3(0.04, 0.04, 0.5),
            bulletColor = Color(1.0, 0.4, 0.1, 1.0),
            emissive = Color(3.0, 1.0, 0.2),
            muzzleFlashDur = 0.04,
            category = "rapid",
            burstCount = 1,
            magazineSize = 999,
            reloadTime = 0,
        }
        mgWeapon.ammo = 999
        mgWeapon.magazineSize = 999
    end

    -- 决定初始状态：有散开方向则先deploy，否则直接approach
    local initState = deployDir and "deploy" or "approach"

    local drone = {
        node = root,
        modelNode = modelNode,
        firePoint = firePoint,
        weapon = mgWeapon,
        hp = hp or 50,
        maxHp = hp or 50,
        dead = false,
        isMiniDrone = true,   -- 类型标记，防止被当作普通敌人重生

        -- AI 状态
        state = initState,        -- deploy | approach | orbit
        orbitAngle = math.random() * 360,
        orbitDir = (math.random() > 0.5) and 1 or -1,
        altitude = ALTITUDE_MIN + math.random() * (ALTITUDE_MAX - ALTITUDE_MIN),

        -- deploy 散开阶段数据
        deployDir = deployDir or Vector3.ZERO,
        deployTraveled = 0,  -- 已飞行的散开距离

        -- 武器调度
        firing = false,
        burstTimer = 0,
        cooldownTimer = 2.0 + math.random() * 2.0,  -- deploy后再开火

        -- 锁定系统兼容字段
        lockValue = 0,
        locked = false,
        screenX = 0.5,
        screenY = 0.5,
        dist = 999,
        visualHeight = 1.0,
        hitCenterY = 0,        -- 碰撞中心Y偏移（无人机节点本身就在空中，无需额外偏移）
        hitRadiusBonus = 2.0,  -- 额外碰撞半径（加到武器基础半径上，放大判定范围）
    }

    return drone
end

-- ============================================================================
-- 更新
-- ============================================================================

--- 更新单个小型无人机
---@param drone table
---@param dt number
---@param playerPos Vector3
function MiniDrone.Update(drone, dt, playerPos)
    if drone.dead then return end
    if not drone.node then return end

    local myPos = drone.node.worldPosition
    local toPlayer = playerPos - myPos
    local horizDist = math.sqrt(toPlayer.x * toPlayer.x + toPlayer.z * toPlayer.z)

    -- 朝向玩家
    local targetYaw = math.deg(math.atan(toPlayer.x, toPlayer.z))
    local curRot = drone.node.rotation
    local targetRot = Quaternion(targetYaw, Vector3.UP)
    drone.node.rotation = curRot:Slerp(targetRot, math.min(1.0, 5.0 * dt))

    -- 移动 AI
    if drone.state == "deploy" then
        -- 散开阶段：从BOSS位置向外飞行一段距离，同时爬升到巡航高度
        local step = DEPLOY_SPEED * dt
        drone.deployTraveled = drone.deployTraveled + step
        -- 水平方向散开
        local hMove = drone.deployDir * step
        -- 垂直方向爬升到巡航高度
        local targetAlt = drone.altitude  -- 目标飞行高度（绝对高度）
        local altDiff = targetAlt - myPos.y
        local vMove = Vector3(0, altDiff * 3.0 * dt, 0)
        drone.node.position = myPos + hMove + vMove

        -- 散开距离达到后，切换到 approach
        if drone.deployTraveled >= DEPLOY_DIST then
            drone.state = "approach"
        end
    elseif drone.state == "approach" then
        -- 接近玩家到轨道距离
        if horizDist > ORBIT_RADIUS + 5 then
            local moveDir = Vector3(toPlayer.x, 0, toPlayer.z):Normalized()
            local targetAlt = playerPos.y + drone.altitude
            local altDiff = targetAlt - myPos.y
            local vel = moveDir * MOVE_SPEED + Vector3(0, altDiff * 2.0, 0)
            drone.node.position = myPos + vel * dt
        else
            drone.state = "orbit"
        end
    elseif drone.state == "orbit" then
        -- 绕玩家盘旋（远距离、高空）
        drone.orbitAngle = drone.orbitAngle + drone.orbitDir * 40 * dt  -- 降低角速度，大圈更稳
        local rad = math.rad(drone.orbitAngle)
        local targetX = playerPos.x + math.cos(rad) * ORBIT_RADIUS
        local targetZ = playerPos.z + math.sin(rad) * ORBIT_RADIUS
        local targetAlt = playerPos.y + drone.altitude

        local targetPos = Vector3(targetX, targetAlt, targetZ)
        local moveDir2 = (targetPos - myPos)
        local moveDist2 = moveDir2:Length()
        if moveDist2 > 0.1 then
            moveDir2 = moveDir2:Normalized()
            local speed = math.min(MOVE_SPEED, moveDist2 * 3.0)
            drone.node.position = myPos + moveDir2 * speed * dt
        end
    end

    -- 轻微倾斜效果
    local vel = drone.node.position - myPos
    local tiltX = -vel.z * 8.0
    local tiltZ = vel.x * 8.0
    tiltX = math.max(-15, math.min(15, tiltX))
    tiltZ = math.max(-15, math.min(15, tiltZ))
    -- 混合倾斜到现有旋转
    local yawOnly = Quaternion(targetYaw, Vector3.UP)
    drone.node.rotation = yawOnly
        * Quaternion(tiltX, Vector3.RIGHT)
        * Quaternion(tiltZ, Vector3.FORWARD)

    -- 武器调度（deploy阶段不开火）
    if drone.state ~= "deploy" then
        if drone.firing then
            drone.burstTimer = drone.burstTimer - dt
            if drone.burstTimer <= 0 then
                drone.firing = false
                drone.cooldownTimer = MG_COOLDOWN + math.random() * 1.0
            else
                -- 射击
                MiniDrone.TryFire(drone, playerPos)
            end
        else
            drone.cooldownTimer = drone.cooldownTimer - dt
            if drone.cooldownTimer <= 0 and horizDist < ORBIT_RADIUS * 2.5 then
                drone.firing = true
                drone.burstTimer = MG_BURST_DUR
            end
        end
    end
end

--- 尝试射击
---@param drone table
---@param targetPos Vector3
function MiniDrone.TryFire(drone, targetPos)
    if not drone.weapon then return end
    local scene = GS.scene
    if not scene then return end

    -- 预判射击（简单）
    local firePos = drone.firePoint.worldPosition
    local toTarget = targetPos - firePos
    local dist = toTarget:Length()
    if dist < 1.0 then return end

    -- 添加散布的目标位置
    local aimPos = targetPos + Vector3(0, 1.5, 0)  -- 瞄准玩家胸部

    Weapons.TryFire(drone.weapon, scene, aimPos, false, nil, nil, nil)
end

-- ============================================================================
-- 受击
-- ============================================================================

--- 对小型无人机造成伤害
---@param drone table
---@param damage number
function MiniDrone.Damage(drone, damage)
    if drone.dead then return end
    drone.hp = drone.hp - damage
    if drone.hp <= 0 then
        drone.hp = 0
        drone.dead = true
        MiniDrone.OnDeath(drone)
    end
end

--- 死亡效果
---@param drone table
function MiniDrone.OnDeath(drone)
    if not drone.node then return end
    local scene = GS.scene
    local pos = drone.node.worldPosition

    -- 小爆炸闪光
    local flashNode = scene:CreateChild("DroneExplosion")
    flashNode.position = pos
    flashNode.scale = Vector3(1.5, 1.5, 1.5)
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, 0.8)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(6.0, 3.0, 0.5)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false

    -- 爆炸光
    local lightNode = scene:CreateChild("DroneExpLight")
    lightNode.position = pos
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = Color(1.0, 0.5, 0.1)
    lt.range = 6.0
    lt.brightness = 4.0
    lt.castShadows = false

    -- 注册闪光特效（0.4秒后移除）
    table.insert(deathEffects_, {
        type = "flash",
        node = flashNode,
        lightNode = lightNode,
        light = lt,
        mat = mat,
        age = 0,
        lifetime = 0.4,
    })

    -- 小碎片
    for i = 1, 6 do
        local dNode = scene:CreateChild("DroneDeb")
        dNode.position = pos
        local s = 0.05 + math.random() * 0.15
        dNode.scale = Vector3(s, s * 0.5, s)
        local dm = dNode:CreateComponent("StaticModel")
        dm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        dm:SetMaterial(GetMaterials().body)
        dm.castShadows = false

        local dir = Vector3(math.random() - 0.5, 0.5 + math.random(), math.random() - 0.5):Normalized()
        local speed = 5 + math.random() * 10

        table.insert(deathEffects_, {
            type = "debris",
            node = dNode,
            vel = dir * speed,
            rotSpeed = Vector3(
                (math.random() - 0.5) * 400,
                (math.random() - 0.5) * 400,
                (math.random() - 0.5) * 400
            ),
            age = 0,
            lifetime = 2.5,
        })
    end

    -- 移除无人机节点
    drone.node:Remove()
    drone.node = nil

    print("[MiniDrone] Drone destroyed!")
end

--- 更新所有死亡特效（闪光淡出、碎片飞散），由 boss_ai 每帧调用
function MiniDrone.UpdateEffects(dt)
    local i = 1
    while i <= #deathEffects_ do
        local fx = deathEffects_[i]
        fx.age = fx.age + dt

        if fx.age >= fx.lifetime then
            -- 超时移除
            if fx.node then fx.node:Remove() end
            if fx.lightNode then fx.lightNode:Remove() end
            table.remove(deathEffects_, i)
        else
            local progress = fx.age / fx.lifetime

            if fx.type == "flash" then
                -- 闪光膨胀 + 淡出
                local s = 1.5 * (1.0 + progress * 2.0)
                fx.node.scale = Vector3(s, s, s)
                local alpha = 0.8 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, alpha)))
                local emFade = math.max(0, 1.0 - progress * 2.5)
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(6.0 * emFade, 3.0 * emFade, 0.5 * emFade)))
                if fx.light then
                    fx.light.brightness = 4.0 * (1.0 - progress)
                end
            elseif fx.type == "debris" then
                -- 碎片重力飞散
                fx.vel = fx.vel + Vector3(0, -15.0 * dt, 0)
                local p = fx.node.position + fx.vel * dt
                if p.y < 0.1 then
                    p.y = 0.1
                    fx.vel.x = fx.vel.x * 0.5
                    fx.vel.y = -fx.vel.y * 0.2
                    fx.vel.z = fx.vel.z * 0.5
                end
                fx.node.position = p
                fx.node.rotation = fx.node.rotation
                    * Quaternion(fx.rotSpeed.x * dt, Vector3.RIGHT)
                    * Quaternion(fx.rotSpeed.y * dt, Vector3.UP)
                -- 后半段缩小
                if progress > 0.5 then
                    local shrink = 1.0 - (progress - 0.5) * 2.0
                    local sc = fx.node.scale * math.max(0.1, shrink)
                    fx.node.scale = sc
                end
            end

            i = i + 1
        end
    end
end

-- ============================================================================
-- 清理
-- ============================================================================

function MiniDrone.Clear()
    -- 清理残留特效
    for _, fx in ipairs(deathEffects_) do
        if fx.node then fx.node:Remove() end
        if fx.lightNode then fx.lightNode:Remove() end
    end
    deathEffects_ = {}
    mats_ = nil
end

return MiniDrone
