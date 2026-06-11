-- ============================================================================
-- boss_ai.lua — BOSS 战 AI 主模块
-- 双阶段状态机：Phase1(合体空中) → Transition(坠落) → Phase2(战车地面)
-- ============================================================================
--
-- API:
--   BossAI.Spawn(scene, levelCfg, enemies)  → bossEnemy (enemy-compatible)
--   BossAI.Update(dt, playerPos, mechNode)
--   BossAI.GetPhase()  → "phase1" | "transition" | "phase2" | "dead" | nil
--   BossAI.GetHP()     → current, max
--   BossAI.Clear()
-- ============================================================================

local CONFIG       = require "config"
local GS           = require "game_state"
local Weapons      = require "weapons"
local BossBuilder  = require "boss_builder"
local Boss2Builder = require "boss2_builder"
local MiniDrone    = require "mini_drone"
local DestructibleBuilding = require "destructible_building"
local SceneBuilder = require "scene_builder"

local BossAI = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local phase_      = nil     -- "phase1" | "transition" | "phase2" | "dead"
local bossEnemy_  = nil     -- enemy-compatible 表（插入 enemies_ 列表）
local cfg_        = nil     -- bossBattle config 引用
local scene_      = nil
local enemies_    = nil     -- 外部 enemies_ 列表引用

-- === Phase1 (合体空中形态) ===
local bossRootNode_   = nil   -- 空根节点（碰撞球 + 位置/yaw 控制）
local droneNode_      = nil   -- 无人机模型节点（缩放 + 视觉倾斜）
local droneModel_     = nil   -- 无人机 modelNode
local droneResult_    = nil   -- Boss2Builder result
local tankModel_      = nil   -- 战车 modelNode（挂在无人机上）
local tankResult_     = nil   -- BossBuilder result

-- 轨道运动
local orbitAngle_     = 0
local orbitDir_       = 1
local orbitCenter_    = Vector3.ZERO
local targetAltitude_ = 25
local smoothVel_      = Vector3.ZERO   -- 平滑速度（用于倾斜计算）
local smoothRoll_     = 0              -- 平滑侧倾角
local smoothPitch_    = 0              -- 平滑俯仰角

-- 机枪调度
local mgFiring_       = false
local mgBurstTimer_   = 0
local mgCooldownTimer_ = 2.0

-- 飞弹调度
local missileCooldown_ = 0
local missileBurstCount_ = 0        -- 当前连射轮次（0~3）
local missileBurstInterval_ = 0.5   -- 连射轮次间隔（秒）

-- 小无人机调度
local droneSpawnTimer_ = 10.0   -- 初始延迟10秒
local miniDrones_      = {}     -- 活跃小无人机列表

-- Phase1 战车炮塔
local p1TurretYaw_      = 0
local p1SubPitchL_      = 0
local p1SubPitchR_      = 0
local p1CannonWeaponL_  = nil
local p1CannonWeaponR_  = nil
local p1CannonTimer_    = 3.0
local p1CannonSide_     = "L"

-- 无人机武器
local droneWeapons_    = {}     -- 4 把机枪武器实例
local missileWeapon_   = nil    -- 飞弹武器实例（复用 vertical_missile）

-- === Transition (过渡阶段) ===
local transTimer_       = 0
local transExplosions_  = 0
local transNextExpTime_ = 0
local transFallStart_   = nil
local tankFallNode_     = nil   -- 战车过渡时的独立节点
local transDebris_      = {}    -- 过渡碎片

-- === Phase2 (战车地面形态) ===
local tankNode_         = nil   -- 战车根节点
local tankGroundResult_ = nil   -- BossBuilder result (phase2)

-- 地面移动
local tankYaw_          = 0
local tankMoveState_    = "approach"  -- approach | circle | retreat
local tankCircleDir_    = 1
local tankCircleTimer_  = 0

-- 炮塔追踪
local turretYaw_        = 0
local subTurretPitchL_  = 0
local subTurretPitchR_  = 0

-- Phase2 武器
local cannonWeaponL_    = nil
local cannonWeaponR_    = nil
local frontMgWeapon_    = nil
local p2MissileWeapon_  = nil

-- Phase2 武器调度
local cannonTimer_      = 0
local cannonSide_       = "L"
local frontMgFiring_    = false
local frontMgBurstTimer_ = 0
local frontMgCooldownTimer_ = 3.0
local p2MissileTimer_   = 0
local p2MissileBurstCount_ = 0      -- Phase2 飞弹连射轮次（0~3）

-- ============================================================================
-- 材质
-- ============================================================================

local debrisMat_ = nil
local function GetDebrisMat()
    if debrisMat_ then return debrisMat_ end
    debrisMat_ = SceneBuilder.CreatePBRMat(
        Color(0.10, 0.10, 0.12, 1.0), 0.5, 0.6)
    return debrisMat_
end

-- ============================================================================
-- 辅助
-- ============================================================================

--- 角度插值（考虑 ±180 环绕）
local function LerpAngle(from, to, t)
    local diff = to - from
    while diff > 180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end
    return from + diff * math.min(1.0, t)
end

--- 限速角度追踪
local function TrackAngle(current, target, speed, dt)
    local diff = target - current
    while diff > 180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end
    local maxStep = speed * dt
    if math.abs(diff) < maxStep then
        return target
    end
    return current + (diff > 0 and maxStep or -maxStep)
end

--- 水平距离
local function HorizDist(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

--- 水平方向角（度）
local function YawTo(from, to)
    local dx = to.x - from.x
    local dz = to.z - from.z
    return math.deg(math.atan(dx, dz))
end

--- 递归收集节点树中所有带 StaticModel 的零件信息（世界坐标/旋转/缩放/模型/材质）
---@param node Node
---@param list table
local function CollectParts(node, list)
    local sm = node:GetComponent("StaticModel")
    if sm then
        local mdl = sm:GetModel()
        local mat = sm:GetMaterial(0)
        if mdl then
            table.insert(list, {
                worldPos = node.worldPosition,
                worldRot = node.worldRotation,
                worldScale = node.worldScale,
                model = mdl,
                material = mat,
            })
        end
    end
    for i = 0, node:GetNumChildren(false) - 1 do
        CollectParts(node:GetChild(i), list)
    end
end

--- BOSS 零件飞散效果：将节点树的所有模型零件变成独立物理碎片
---@param rootNode Node 要爆炸的 BOSS 根节点
---@param centerPos Vector3 爆炸中心（用于计算飞散方向）
---@param explosionForce number|nil 爆炸力度（默认 20）
local function ExplodeBossNode(rootNode, centerPos, explosionForce)
    local force = explosionForce or 20
    local parts = {}
    CollectParts(rootNode, parts)

    for _, p in ipairs(parts) do
        local debris = scene_:CreateChild("BossPart")
        debris.position = p.worldPos
        debris.rotation = p.worldRot
        debris.scale = p.worldScale

        local sm = debris:CreateComponent("StaticModel")
        sm:SetModel(p.model)
        if p.material then sm:SetMaterial(p.material) end
        sm.castShadows = false

        -- 物理：刚体 + 碰撞盒
        local body = debris:CreateComponent("RigidBody")
        local massBase = p.worldScale.x * p.worldScale.y * p.worldScale.z
        body:SetMass(math.max(0.1, math.min(2.0, massBase * 0.5)))

        -- 飞散方向：从爆炸中心向外 + 随机扰动 + 上抛
        local dir = p.worldPos - centerPos
        if dir:Length() < 0.1 then
            dir = Vector3(math.random() - 0.5, 0.5, math.random() - 0.5)
        end
        dir = dir:Normalized()
        local scatter = Vector3(
            (math.random() - 0.5) * 0.4,
            0.3 + math.random() * 0.5,
            (math.random() - 0.5) * 0.4
        )
        local finalDir = (dir + scatter):Normalized()
        local speed = force * (0.6 + math.random() * 0.8)
        body:SetLinearVelocity(finalDir * speed)

        -- 随机旋转
        body:SetAngularVelocity(Vector3(
            (math.random() - 0.5) * 10,
            (math.random() - 0.5) * 10,
            (math.random() - 0.5) * 10
        ))

        -- 碰撞形状（简单 Box 近似）
        local shape = debris:CreateComponent("CollisionShape")
        shape:SetBox(Vector3.ONE)
    end

    print(string.format("[BossAI] Exploded %d parts from %s", #parts, rootNode.name))
end

-- 前向声明（local 函数在调用点之后定义）
local StartTransition
local StartPhase2

-- ============================================================================
-- 生成
-- ============================================================================

--- 生成 BOSS（合体形态）
---@param sceneRef Scene
---@param levelCfg table 关卡配置（含 bossBattle 字段）
---@param enemiesRef table 敌人列表引用
---@return table bossEnemy (enemy-compatible)
function BossAI.Spawn(sceneRef, levelCfg, enemiesRef)
    scene_ = sceneRef
    cfg_ = levelCfg.bossBattle
    enemies_ = enemiesRef
    phase_ = "phase1"

    local p1 = cfg_.phase1

    -- === 构建合体模型 ===
    -- 空根节点：控制位置/yaw，挂载碰撞球
    bossRootNode_ = scene_:CreateChild("BossRoot")
    bossRootNode_.position = Vector3(0, p1.altitude, 100)  -- 从远处出场

    -- 无人机模型节点：作为根节点子节点，负责缩放和视觉倾斜
    droneNode_ = bossRootNode_:CreateChild("BossDrone")
    droneNode_.scale = Vector3(2.0, 2.0, 2.0)  -- 200% 整体缩放（战车作为子节点自动继承）

    droneModel_, droneResult_ = Boss2Builder.Build(droneNode_)

    -- 战车挂载到无人机上
    local tankParent = droneNode_:CreateChild("TankMount")
    tankModel_, tankResult_ = BossBuilder.Build(tankParent)
    droneResult_:MountBoss(tankModel_)

    -- === 创建武器 ===
    -- 4 把无人机机枪
    droneWeapons_ = {}
    for i = 1, 4 do
        local w = Weapons.CreateWeapon("machinegun", droneResult_.firePoints[i], "enemy")
        if w then
            w.def = {
                damage = p1.mgDamage,
                bulletSpeed = p1.mgBulletSpeed,
                bulletLife = 3.0,
                fireRate = 1.0 / p1.mgFireRate,  -- fireRate = 次/秒
                spread = 0.04,
                tracking = false,
                bulletScale = Vector3(0.04, 0.04, 0.6),
                bulletColor = Color(1.0, 0.3, 0.1, 1.0),
                emissive = Color(3.0, 0.8, 0.2),
                muzzleFlashDur = 0.04,
                category = "rapid",
                burstCount = 1,
                magazineSize = 999,
                reloadTime = 0,
            }
            w.ammo = 999
            w.magazineSize = 999
            droneWeapons_[i] = w
        end
    end

    -- 飞弹武器（使用战车的飞弹发射点）
    local missileFPs = tankResult_:GetMissileFireData()
    if #tankResult_.missilePoints >= 1 then
        missileWeapon_ = Weapons.CreateWeapon("vertical_missile", tankResult_.missilePoints[1], "enemy")
        if missileWeapon_ then
            missileWeapon_.ammo = 999
            missileWeapon_.magazineSize = 999
        end
    end

    -- === Phase1 战车炮塔武器（合体时向下俯射） ===
    local tankFps = tankResult_.firePoints
    if tankFps[1] then
        p1CannonWeaponL_ = Weapons.CreateWeapon("tank_cannon", tankFps[1], "enemy")
        if p1CannonWeaponL_ then
            p1CannonWeaponL_.def.damage = p1.cannonDamage or 50
            p1CannonWeaponL_.def.bulletSpeed = p1.cannonBulletSpeed or 80
            p1CannonWeaponL_.ammo = 999
            p1CannonWeaponL_.magazineSize = 999
        end
    end
    if tankFps[3] then
        p1CannonWeaponR_ = Weapons.CreateWeapon("tank_cannon", tankFps[3], "enemy")
        if p1CannonWeaponR_ then
            p1CannonWeaponR_.def.damage = p1.cannonDamage or 50
            p1CannonWeaponR_.def.bulletSpeed = p1.cannonBulletSpeed or 80
            p1CannonWeaponR_.ammo = 999
            p1CannonWeaponR_.magazineSize = 999
        end
    end

    -- === Phase1 碰撞球（挂在空根节点上，供射线检测/锁定使用） ===
    local collBody = bossRootNode_:CreateComponent("RigidBody")
    collBody.collisionLayer = CollisionLayerStatic
    collBody.collisionMask = 0  -- 不参与物理碰撞，仅射线检测
    collBody.kinematic = true   -- 运动学模式，不受重力/物理影响
    local collShape = bossRootNode_:CreateComponent("CollisionShape")
    collShape:SetSphere(24.0, Vector3(0, 0, 0))  -- 根节点 scale=1.0，直接用世界半径 24m

    -- === 初始化轨道运动 ===
    orbitAngle_ = math.random() * 360
    orbitDir_ = (math.random() > 0.5) and 1 or -1
    orbitCenter_ = Vector3.ZERO
    targetAltitude_ = p1.altitude

    -- 武器调度初始化
    mgFiring_ = false
    mgBurstTimer_ = 0
    mgCooldownTimer_ = 2.0 + math.random()
    missileCooldown_ = p1.missileCooldown * 0.5  -- 首次飞弹稍快
    missileBurstCount_ = 0
    p1TurretYaw_ = 0
    p1SubPitchL_ = 0
    p1SubPitchR_ = 0
    p1CannonTimer_ = p1.cannonCooldown or 3.0
    p1CannonSide_ = "L"
    droneSpawnTimer_ = 10.0  -- 初始延迟10秒
    miniDrones_ = {}
    smoothVel_ = Vector3.ZERO
    smoothRoll_ = 0
    smoothPitch_ = 0

    -- === 创建 enemy-compatible 表 ===
    bossEnemy_ = {
        node = bossRootNode_,  -- 指向根节点（碰撞球所在节点），射线/锁定通过父链匹配
        hp = p1.hp,
        maxHp = p1.maxHp,
        dead = false,
        isBoss = true,
        bossPhase = "phase1",

        -- HUD 兼容
        lockValue = 0,
        locked = false,
        screenX = 0.5,
        screenY = 0.5,
        dist = 999,
        visualHeight = 8.0,
        hitCenterY = 0,        -- BOSS节点本身就在空中，无需额外Y偏移
        hitRadiusBonus = 6.0,  -- 大碰撞判定范围，更容易被弹丸命中
    }

    -- 将 BOSS 加入敌人列表（供锁定系统和弹丸命中检测使用）
    table.insert(enemies_, bossEnemy_)

    print(string.format("[BossAI] BOSS spawned! Phase1 HP=%d/%d", p1.hp, p1.maxHp))
    return bossEnemy_
end

-- ============================================================================
-- Phase1: 合体空中形态
-- ============================================================================

local function UpdatePhase1(dt, playerPos, mechNode)
    local p1 = cfg_.phase1

    -- === 轨道运动 ===
    -- 以玩家为中心缓慢盘旋
    orbitCenter_ = Vector3(playerPos.x, 0, playerPos.z)

    -- 改变轨道方向（随机）
    if math.random() < 0.002 then
        orbitDir_ = -orbitDir_
    end

    local orbitSpeed = (p1.moveSpeed / p1.orbitRadius) * 57.3  -- rad/s → deg/s
    orbitAngle_ = orbitAngle_ + orbitDir_ * orbitSpeed * dt

    local rad = math.rad(orbitAngle_)
    local targetX = orbitCenter_.x + math.cos(rad) * p1.orbitRadius
    local targetZ = orbitCenter_.z + math.sin(rad) * p1.orbitRadius
    local targetY = p1.altitude

    local targetPos = Vector3(targetX, targetY, targetZ)
    local myPos = bossRootNode_.worldPosition
    local moveDir = targetPos - myPos
    local moveDist = moveDir:Length()

    -- 使用连续插值追踪目标，避免启停抖动
    local lerpFactor = math.min(1.0, 3.0 * dt)  -- 平滑追踪系数
    local newPos = myPos + (targetPos - myPos) * lerpFactor
    -- 限制最大速度
    local maxStep = p1.moveSpeed * dt
    local actualDelta = newPos - myPos
    local actualDist = actualDelta:Length()
    if actualDist > maxStep then
        newPos = myPos + actualDelta:Normalized() * maxStep
    end
    bossRootNode_.position = newPos

    -- === 速度平滑 ===
    -- 用帧无关的速度向量（单位/秒），而非帧位移
    local frameVel = (newPos - myPos)
    if dt > 0.0001 then
        frameVel = frameVel * (1.0 / dt)  -- 转换为速度（单位/秒）
    end
    local velSmooth = math.min(1.0, 5.0 * dt)
    smoothVel_ = smoothVel_ * (1.0 - velSmooth) + frameVel * velSmooth

    -- === 朝向玩家 ===
    local yawToPlayer = YawTo(myPos, playerPos)

    -- === 倾斜效果（基于平滑速度） ===
    local fwd = Quaternion(yawToPlayer, Vector3.UP) * Vector3.FORWARD
    local right = Quaternion(yawToPlayer, Vector3.UP) * Vector3.RIGHT
    local lateralSpeed = smoothVel_:DotProduct(right)
    local forwardSpeed = smoothVel_:DotProduct(fwd)

    -- 用速度占最大速度的比例来映射倾斜角
    local rollTarget = -(lateralSpeed / math.max(p1.moveSpeed, 1)) * p1.tiltAngle
    rollTarget = math.max(-p1.tiltAngle, math.min(p1.tiltAngle, rollTarget))
    local pitchTarget = -(forwardSpeed / math.max(p1.moveSpeed, 1)) * p1.tiltAngle * 0.5
    pitchTarget = math.max(-p1.tiltAngle * 0.5, math.min(p1.tiltAngle * 0.5, pitchTarget))

    -- 平滑插值倾斜角度
    local tiltSmooth = math.min(1.0, 4.0 * dt)
    smoothRoll_ = smoothRoll_ + (rollTarget - smoothRoll_) * tiltSmooth
    smoothPitch_ = smoothPitch_ + (pitchTarget - smoothPitch_) * tiltSmooth

    -- 根节点：仅 yaw（朝向玩家），碰撞球不受倾斜影响
    bossRootNode_.rotation = Quaternion(yawToPlayer, Vector3.UP)
    -- 模型子节点：视觉倾斜（pitch/roll），相对于根节点的本地旋转
    droneNode_.rotation = Quaternion(smoothPitch_, Vector3.RIGHT)
        * Quaternion(smoothRoll_, Vector3.FORWARD)

    -- === 机枪瞄准 ===
    local aimPos = playerPos + Vector3(0, 2.0, 0)  -- 玩家胸部
    droneResult_:AimGunsAt(aimPos)

    -- === 机枪调度 ===
    local horizDist = HorizDist(myPos, playerPos)
    if mgFiring_ then
        mgBurstTimer_ = mgBurstTimer_ - dt
        if mgBurstTimer_ <= 0 then
            mgFiring_ = false
            mgCooldownTimer_ = p1.mgCooldown + math.random() * 1.0
        else
            -- 射击: 4把机枪轮流
            for i = 1, 4 do
                if droneWeapons_[i] then
                    Weapons.TryFire(droneWeapons_[i], scene_, aimPos, false, nil, nil, nil)
                end
            end
        end
    else
        mgCooldownTimer_ = mgCooldownTimer_ - dt
        if mgCooldownTimer_ <= 0 and horizDist < p1.orbitRadius * 5 then
            mgFiring_ = true
            mgBurstTimer_ = p1.mgBurstDur
        end
    end

    -- === Phase1 战车炮塔追踪（向下俯射玩家） ===
    if tankResult_ and tankResult_.turret then
        -- 主炮塔 yaw 追踪：相对于根节点的 yaw（根节点只含 yaw，无倾斜）
        local rootWorldYaw = yawToPlayer  -- bossRootNode_ 的 yaw 就是 yawToPlayer
        local turretWorldYaw = YawTo(tankResult_.turret.worldPosition, playerPos)
        local targetTurretLocalYaw = turretWorldYaw - rootWorldYaw
        while targetTurretLocalYaw > 180 do targetTurretLocalYaw = targetTurretLocalYaw - 360 end
        while targetTurretLocalYaw < -180 do targetTurretLocalYaw = targetTurretLocalYaw + 360 end
        p1TurretYaw_ = TrackAngle(p1TurretYaw_, targetTurretLocalYaw, p1.turretYawSpeed or 45, dt)
        tankResult_:SetTurretYaw(p1TurretYaw_)

        -- 二级炮塔 pitch 追踪（综合机身倾斜角度）
        -- SetSubTurretPitch 约定: 正值=上仰, 负值=下俯
        -- smoothPitch_ 约定同上: 正值=抬头, 负值=低头
        -- 炮管世界 pitch ≈ 机身 smoothPitch_ + 炮塔本地 subPitch
        -- 因此：所需的炮塔本地 pitch = 目标世界 pitch - 机身 smoothPitch_
        local turretWorldPos = tankResult_.turret.worldPosition
        local toPlayer = playerPos + Vector3(0, 1.7, 0) - turretWorldPos
        local turretFwd = tankResult_.turret.worldRotation * Vector3.FORWARD
        local horizFwd = Vector3(turretFwd.x, 0, turretFwd.z):Normalized()
        local horizDot = toPlayer.x * horizFwd.x + toPlayer.z * horizFwd.z
        -- 目标世界俯仰角: atan(y, horiz) → 正=上仰, 负=下俯
        local targetWorldPitch = math.deg(math.atan(toPlayer.y, math.max(0.1, math.abs(horizDot))))
        -- 减去机身倾斜得到炮塔本地需要的俯仰角
        local targetLocalPitch = targetWorldPitch - smoothPitch_

        -- 二级炮塔俯仰限制: 正=上仰, 负=下俯 → 最多下俯5度, 上仰30度
        local minPitch = p1.turretMinPitch or -5.0
        local maxPitch = p1.turretMaxPitch or 30.0
        local clampedPitch = math.max(minPitch, math.min(maxPitch, targetLocalPitch))

        p1SubPitchL_ = TrackAngle(p1SubPitchL_, clampedPitch, p1.turretPitchSpeed or 30, dt)
        p1SubPitchR_ = TrackAngle(p1SubPitchR_, clampedPitch, p1.turretPitchSpeed or 30, dt)
        tankResult_:SetSubTurretPitch("L", p1SubPitchL_)
        tankResult_:SetSubTurretPitch("R", p1SubPitchR_)

        -- === Phase1 火炮发射条件 ===
        -- 1. 炮管已接近目标角度（跟踪误差小）
        local pitchError = math.abs(p1SubPitchL_ - clampedPitch)
        local yawError = math.abs(p1TurretYaw_ - targetTurretLocalYaw)
        while yawError > 180 do yawError = yawError - 360 end
        yawError = math.abs(yawError)
        -- 2. 目标pitch没有被clamp截断（即目标确实在可瞄准范围内）
        local pitchInRange = math.abs(targetLocalPitch - clampedPitch) < 1.0
        -- 3. yaw 和 pitch 都接近目标
        local canFire = pitchError < 3.0 and yawError < 3.0 and pitchInRange

        -- 调试数据：炮塔开火条件（通过 GS 中转，避免循环依赖）
        if GS then
            GS._bossTurretDebug = {
                targetWorldPitch = targetWorldPitch,
                smoothPitch = smoothPitch_,
                targetLocalPitch = targetLocalPitch,
                clampedPitch = clampedPitch,
                minPitch = minPitch,
                maxPitch = maxPitch,
                pitchError = pitchError,
                yawError = yawError,
                pitchInRange = pitchInRange,
                canFire = canFire,
                p1TurretYaw = p1TurretYaw_,
                p1SubPitchL = p1SubPitchL_,
            }
        end

        p1CannonTimer_ = p1CannonTimer_ - dt
        if p1CannonTimer_ <= 0 and canFire then
            if p1CannonSide_ == "L" and p1CannonWeaponL_ then
                Weapons.FireSingle(p1CannonWeaponL_, scene_, aimPos, false, mechNode, nil, nil)
                p1CannonSide_ = "R"
            elseif p1CannonSide_ == "R" and p1CannonWeaponR_ then
                Weapons.FireSingle(p1CannonWeaponR_, scene_, aimPos, false, mechNode, nil, nil)
                p1CannonSide_ = "L"
            end
            p1CannonTimer_ = (p1.cannonCooldown or 3.0) * 0.5
        end
    end

    -- === 飞弹调度（连续3轮齐射） ===
    missileCooldown_ = missileCooldown_ - dt
    if missileCooldown_ <= 0 and missileWeapon_ then
        -- 从 4 个飞弹发射点依次发射
        local fpData = tankResult_:GetMissileFireData()
        for idx = 1, math.min(p1.missileCount, #fpData) do
            missileWeapon_.mountNode = tankResult_.missilePoints[idx]
            Weapons.FireSingle(missileWeapon_, scene_, aimPos, false, mechNode, nil, nil)
        end
        missileBurstCount_ = missileBurstCount_ + 1
        if missileBurstCount_ >= 3 then
            missileCooldown_ = p1.missileCooldown
            missileBurstCount_ = 0
        else
            missileCooldown_ = missileBurstInterval_
        end
        print(string.format("[BossAI] Phase1: Missiles round %d/3!", missileBurstCount_ == 0 and 3 or missileBurstCount_))
    end

    -- === 小无人机调度 ===
    droneSpawnTimer_ = droneSpawnTimer_ - dt
    if droneSpawnTimer_ <= 0 then
        -- 清理已死亡的无人机
        local alive = 0
        for j = #miniDrones_, 1, -1 do
            if miniDrones_[j].dead then
                -- 从 enemies_ 中移除
                for ei = #enemies_, 1, -1 do
                    if enemies_[ei] == miniDrones_[j] then
                        table.remove(enemies_, ei)
                        break
                    end
                end
                table.remove(miniDrones_, j)
            else
                alive = alive + 1
            end
        end

        if alive < p1.droneMaxAlive then
            -- 固定5个一波，从BOSS位置生成，传递散开方向
            local canSpawn = p1.droneMaxAlive - alive
            local batchSize = math.min(5, canSpawn)
            for si = 1, batchSize do
                -- 从BOSS当前位置生成
                local spawnPos = Vector3(myPos.x, myPos.y, myPos.z)
                -- 每个无人机散开方向不同（均匀分布 + 随机偏移）
                local deployAngle = (si / batchSize) * math.pi * 2 + math.random() * 0.5
                local deployDir = Vector3(math.sin(deployAngle), 0, math.cos(deployAngle))
                local drone = MiniDrone.Spawn(scene_, spawnPos, p1.droneHP, deployDir)
                table.insert(miniDrones_, drone)
                table.insert(enemies_, drone)
            end
            Weapons.SetEnemies(enemies_)
            print(string.format("[BossAI] Mini drone swarm spawned! Batch: %d, Alive: %d/%d",
                batchSize, alive + batchSize, p1.droneMaxAlive))
        end
        droneSpawnTimer_ = p1.droneSpawnInterval
    end

    -- === 更新小无人机 ===
    for _, md in ipairs(miniDrones_) do
        if not md.dead then
            MiniDrone.Update(md, dt, playerPos)
        end
    end

    -- === HP 检测 → 进入过渡阶段 ===
    if bossEnemy_.hp <= 0 then
        bossEnemy_.hp = 0
        StartTransition(playerPos)
    end
end

-- ============================================================================
-- Transition: 无人机爆炸 → 战车坠落
-- ============================================================================

StartTransition = function(playerPos)
    phase_ = "transition"
    bossEnemy_.bossPhase = "transition"
    transTimer_ = 0
    transExplosions_ = 0
    transNextExpTime_ = 0
    transDebris_ = {}

    local dronePos = bossRootNode_.worldPosition

    -- 战车从无人机脱离 → 独立节点（保持与合体时相同的缩放）
    tankFallNode_ = scene_:CreateChild("TankFalling")
    tankFallNode_.position = dronePos
    tankFallNode_.scale = Vector3(2.0, 2.0, 2.0)  -- 200% 缩放，与合体形态一致

    -- 重建战车模型（或者从无人机上分离）
    -- 最简单的方式：隐藏无人机，在 tankFallNode 上重建战车
    local newTankModel, newTankResult = BossBuilder.Build(tankFallNode_)
    transFallStart_ = Vector3(dronePos.x, dronePos.y, dronePos.z)

    -- 停止所有小无人机
    for _, md in ipairs(miniDrones_) do
        if not md.dead then
            md.dead = true
            MiniDrone.OnDeath(md)
        end
    end
    -- 从 enemies_ 中移除所有小无人机
    for j = #enemies_, 1, -1 do
        if enemies_[j] ~= bossEnemy_ and enemies_[j].node == nil then
            table.remove(enemies_, j)
        end
    end
    for j = #miniDrones_, 1, -1 do
        for ei = #enemies_, 1, -1 do
            if enemies_[ei] == miniDrones_[j] then
                table.remove(enemies_, ei)
                break
            end
        end
    end
    miniDrones_ = {}

    -- 无人机 BOSS 零件飞散（使用实际模型零件）
    ExplodeBossNode(bossRootNode_, dronePos, 25)

    -- 移除根节点（droneNode_ 作为子节点一并删除）
    bossRootNode_:Remove()
    bossRootNode_ = nil
    droneNode_ = nil
    droneModel_ = nil
    droneResult_ = nil
    tankModel_ = nil
    tankResult_ = nil
    droneWeapons_ = {}
    missileWeapon_ = nil
    p1CannonWeaponL_ = nil
    p1CannonWeaponR_ = nil

    -- 更新 bossEnemy_ 节点引用到坠落战车
    bossEnemy_.node = tankFallNode_

    print("[BossAI] Phase1 destroyed → Transition started!")
end

local function UpdateTransition(dt, playerPos)
    local trans = cfg_.transition
    transTimer_ = transTimer_ + dt

    -- === 战车坠落 ===
    local fallProgress = math.min(1.0, transTimer_ / trans.fallDuration)
    -- 使用缓入缓出（加速落体效果）
    local eased = fallProgress * fallProgress  -- quadratic ease-in
    local startY = transFallStart_.y
    local endY = 0  -- 地面
    local curY = startY + (endY - startY) * eased

    tankFallNode_.position = Vector3(transFallStart_.x, math.max(0, curY), transFallStart_.z)

    -- 坠落时轻微摇晃
    local shake = (1.0 - fallProgress) * 5.0
    tankFallNode_.rotation = Quaternion(
        math.sin(transTimer_ * 8) * shake, Vector3.RIGHT
    ) * Quaternion(
        math.sin(transTimer_ * 6) * shake * 0.5, Vector3.FORWARD
    )

    -- === 更新碎片 ===
    local i = 1
    while i <= #transDebris_ do
        local d = transDebris_[i]
        d.age = d.age + dt

        if d.isFlash then
            if d.age > 0.5 then
                d.node:Remove()
                if d.lightNode then d.lightNode:Remove() end
                table.remove(transDebris_, i)
            else
                local progress = d.age / 0.5
                local s = d.node.scale.x * (1.0 + progress * 2.0)
                d.node.scale = Vector3(s, s, s)
                local alpha = 0.8 * (1.0 - progress)
                d.mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, alpha)))
                local emFade = math.max(0, 1.0 - progress * 2.0)
                d.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0 * emFade, 4.0 * emFade, 1.0 * emFade)))
                if d.light then
                    d.light.brightness = 5.0 * (1.0 - progress)
                end
                i = i + 1
            end
        else
            if d.age > 4.0 then
                d.node:Remove()
                table.remove(transDebris_, i)
            else
                d.vel = d.vel + Vector3(0, -15.0 * dt, 0)
                local pos = d.node.position + d.vel * dt
                if pos.y < 0.1 then
                    pos.y = 0.1
                    d.vel.x = d.vel.x * 0.6
                    d.vel.y = -d.vel.y * 0.25
                    d.vel.z = d.vel.z * 0.6
                end
                d.node.position = pos
                d.node.rotation = d.node.rotation
                    * Quaternion(d.rotSpeed.x * dt, Vector3.RIGHT)
                    * Quaternion(d.rotSpeed.y * dt, Vector3.UP)
                    * Quaternion(d.rotSpeed.z * dt, Vector3.FORWARD)
                -- 缩小淡出
                if d.age > 2.5 then
                    local fade = (d.age - 2.5) / 1.5
                    local sc = d.node.scale * (1.0 - fade * 0.6)
                    d.node.scale = sc
                end
                i = i + 1
            end
        end
    end

    -- === 过渡完成 → 进入 Phase2 ===
    if fallProgress >= 1.0 and transTimer_ > trans.fallDuration + 0.5 then
        StartPhase2()
    end
end

-- ============================================================================
-- Phase2: 战车地面形态
-- ============================================================================

StartPhase2 = function()
    phase_ = "phase2"

    local p2 = cfg_.phase2

    -- 用 tankFallNode_ 作为 Phase2 的战车根节点
    tankNode_ = tankFallNode_
    tankFallNode_ = nil

    -- 重置旋转（坠落摇晃归零）
    tankNode_.rotation = Quaternion.IDENTITY
    tankNode_.position = Vector3(tankNode_.position.x, 0, tankNode_.position.z)

    -- 获取已经 Build 过的 result（需要重建以获取正确引用）
    -- tankNode_ 已有子节点 BossModel（在 StartTransition 中创建的）
    -- 我们需要重新获取 result 的方法对象
    -- 最简方案：移除旧子节点，重建
    local children = {}
    for i = 0, tankNode_:GetNumChildren(false) - 1 do
        children[#children + 1] = tankNode_:GetChild(i)
    end
    for _, c in ipairs(children) do
        c:Remove()
    end

    local newModel, newResult = BossBuilder.Build(tankNode_)
    tankGroundResult_ = newResult

    -- 添加碰撞体（让玩家弹丸射线检测可以命中地面物体）
    local collBody = tankNode_:CreateComponent("RigidBody")
    collBody.collisionLayer = CollisionLayerStatic
    collBody.collisionMask = 0  -- 不和其他物体碰撞，仅用于射线检测
    local collShape = tankNode_:CreateComponent("CollisionShape")
    collShape:SetBox(Vector3(3.5, 3.0, 6.0), Vector3(0, 1.5, 0))

    -- 初始化朝向
    tankYaw_ = math.deg(math.atan(tankNode_.position.x, tankNode_.position.z)) + 180
    tankNode_.rotation = Quaternion(tankYaw_, Vector3.UP)
    turretYaw_ = 0
    subTurretPitchL_ = 0
    subTurretPitchR_ = 0

    -- 创建 Phase2 武器
    -- 左右火炮（使用二级炮塔发射点）
    local fps = tankGroundResult_.firePoints
    if fps[1] then
        cannonWeaponL_ = Weapons.CreateWeapon("tank_cannon", fps[1], "enemy")
        if cannonWeaponL_ then
            cannonWeaponL_.def.damage = p2.cannonDamage
            cannonWeaponL_.def.bulletSpeed = p2.cannonBulletSpeed
            cannonWeaponL_.ammo = 999
            cannonWeaponL_.magazineSize = 999
        end
    end
    if fps[3] then
        cannonWeaponR_ = Weapons.CreateWeapon("tank_cannon", fps[3], "enemy")
        if cannonWeaponR_ then
            cannonWeaponR_.def.damage = p2.cannonDamage
            cannonWeaponR_.def.bulletSpeed = p2.cannonBulletSpeed
            cannonWeaponR_.ammo = 999
            cannonWeaponR_.magazineSize = 999
        end
    end

    -- 车前机枪（挂载在底盘前方）
    local mgMount = tankNode_:GetChild("BossModel", false)
    if mgMount then
        local hullMgBarrel = mgMount:GetChild("HullMGBarrel", false)
        if hullMgBarrel then
            local fpNode = hullMgBarrel:CreateChild("FrontMGFirePoint")
            fpNode.position = Vector3(0, 0.5, 0)  -- 炮管前端
            frontMgWeapon_ = Weapons.CreateWeapon("machinegun", fpNode, "enemy")
            if frontMgWeapon_ then
                frontMgWeapon_.def = {
                    damage = p2.frontMgDamage,
                    bulletSpeed = 100,
                    bulletLife = 3.0,
                    fireRate = 1.0 / p2.frontMgFireRate,
                    spread = 0.05,
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
                frontMgWeapon_.ammo = 999
                frontMgWeapon_.magazineSize = 999
            end
        end
    end

    -- 飞弹
    if tankGroundResult_.missilePoints[1] then
        p2MissileWeapon_ = Weapons.CreateWeapon("vertical_missile", tankGroundResult_.missilePoints[1], "enemy")
        if p2MissileWeapon_ then
            p2MissileWeapon_.ammo = 999
            p2MissileWeapon_.magazineSize = 999
        end
    end

    -- 武器调度重置
    cannonTimer_ = 1.5  -- 初始短延迟
    cannonSide_ = "L"
    frontMgFiring_ = false
    frontMgBurstTimer_ = 0
    frontMgCooldownTimer_ = 2.0 + math.random()
    p2MissileTimer_ = p2.missileCooldown * 0.5

    -- 移动状态
    tankMoveState_ = "approach"
    tankCircleDir_ = (math.random() > 0.5) and 1 or -1
    tankCircleTimer_ = 3.0 + math.random() * 3.0

    -- 更新 bossEnemy_
    bossEnemy_.node = tankNode_
    bossEnemy_.hp = p2.hp
    bossEnemy_.maxHp = p2.maxHp
    bossEnemy_.dead = false
    bossEnemy_.bossPhase = "phase2"
    bossEnemy_.visualHeight = 4.5

    -- 更新 enemies_ 引用
    Weapons.SetEnemies(enemies_)

    print(string.format("[BossAI] Phase2 started! HP=%d/%d", p2.hp, p2.maxHp))
end

local function UpdatePhase2(dt, playerPos, mechNode)
    local p2 = cfg_.phase2
    local myPos = tankNode_.worldPosition
    local horizDist = HorizDist(myPos, playerPos)
    local yawToPlayer = YawTo(myPos, playerPos)

    -- === 车体移动 AI ===
    local desiredYaw = tankYaw_
    local moveSpeed = 0

    if tankMoveState_ == "approach" then
        -- 接近玩家
        if horizDist > 40 then
            desiredYaw = yawToPlayer
            moveSpeed = p2.moveSpeed
        else
            tankMoveState_ = "circle"
            tankCircleTimer_ = 4.0 + math.random() * 3.0
        end
    elseif tankMoveState_ == "circle" then
        -- 绕玩家侧移
        tankCircleTimer_ = tankCircleTimer_ - dt
        if tankCircleTimer_ <= 0 then
            tankCircleDir_ = -tankCircleDir_
            tankCircleTimer_ = 3.0 + math.random() * 4.0
            -- 偶尔切换到接近
            if math.random() < 0.3 then
                tankMoveState_ = "approach"
            end
        end
        desiredYaw = yawToPlayer + tankCircleDir_ * 80
        moveSpeed = p2.moveSpeed * 0.7

        if horizDist < 20 then
            tankMoveState_ = "retreat"
        elseif horizDist > 80 then
            tankMoveState_ = "approach"
        end
    elseif tankMoveState_ == "retreat" then
        -- 后退
        desiredYaw = yawToPlayer + 180
        moveSpeed = p2.moveSpeed * 0.8
        if horizDist > 50 then
            tankMoveState_ = "circle"
            tankCircleTimer_ = 3.0 + math.random() * 3.0
        end
    end

    -- 限速转向
    tankYaw_ = TrackAngle(tankYaw_, desiredYaw, p2.turnSpeed, dt)
    tankNode_.rotation = Quaternion(tankYaw_, Vector3.UP)

    -- 移动
    if moveSpeed > 0 then
        local fwd = Quaternion(tankYaw_, Vector3.UP) * Vector3.FORWARD
        local newPos = myPos + fwd * moveSpeed * dt
        newPos.y = 0  -- 保持地面
        tankNode_.position = newPos
        -- BOSS 碾压附近建筑
        DestructibleBuilding.DamageAt(newPos + Vector3(0, 2, 0), 9999, 8.0)
    end

    -- === 炮塔追踪 ===
    -- 计算主炮塔应瞄准的 yaw（相对于车体）
    local turretWorldYaw = yawToPlayer
    local targetTurretLocalYaw = turretWorldYaw - tankYaw_
    while targetTurretLocalYaw > 180 do targetTurretLocalYaw = targetTurretLocalYaw - 360 end
    while targetTurretLocalYaw < -180 do targetTurretLocalYaw = targetTurretLocalYaw + 360 end

    turretYaw_ = TrackAngle(turretYaw_, targetTurretLocalYaw, p2.turretYawSpeed, dt)
    tankGroundResult_:SetTurretYaw(turretYaw_)

    -- 计算二级炮塔俯仰角（相对于炮塔朝向）
    local turretWorldPos = tankGroundResult_.turret.worldPosition
    local toPlayer = playerPos + Vector3(0, 1.7, 0) - turretWorldPos
    local turretFwd = tankGroundResult_.turret.worldRotation * Vector3.FORWARD
    local fwdDist = math.max(1.0, math.sqrt(toPlayer.x * toPlayer.x + toPlayer.z * toPlayer.z))
    local targetPitch = math.deg(math.atan(toPlayer.y, fwdDist))
    targetPitch = math.max(-10, math.min(p2.turretMaxPitch, targetPitch))

    subTurretPitchL_ = TrackAngle(subTurretPitchL_, targetPitch, p2.turretPitchSpeed, dt)
    subTurretPitchR_ = TrackAngle(subTurretPitchR_, targetPitch, p2.turretPitchSpeed, dt)
    tankGroundResult_:SetSubTurretPitch("L", subTurretPitchL_)
    tankGroundResult_:SetSubTurretPitch("R", subTurretPitchR_)

    -- === 火炮调度（左右交替） ===
    local aimPos = playerPos + Vector3(0, 1.7, 0)
    cannonTimer_ = cannonTimer_ - dt
    if cannonTimer_ <= 0 then
        if cannonSide_ == "L" and cannonWeaponL_ then
            Weapons.FireSingle(cannonWeaponL_, scene_, aimPos, false, mechNode, nil, nil)
            cannonSide_ = "R"
        elseif cannonSide_ == "R" and cannonWeaponR_ then
            Weapons.FireSingle(cannonWeaponR_, scene_, aimPos, false, mechNode, nil, nil)
            cannonSide_ = "L"
        end
        cannonTimer_ = p2.cannonCooldown * 0.5  -- 每门炮冷却的一半（交替所以总周期 = cannonCooldown）
    end

    -- === 车前机枪调度 ===
    if frontMgFiring_ then
        frontMgBurstTimer_ = frontMgBurstTimer_ - dt
        if frontMgBurstTimer_ <= 0 then
            frontMgFiring_ = false
            frontMgCooldownTimer_ = p2.frontMgCooldown + math.random() * 1.0
        else
            if frontMgWeapon_ then
                Weapons.TryFire(frontMgWeapon_, scene_, aimPos, false, nil, nil, nil)
            end
        end
    else
        frontMgCooldownTimer_ = frontMgCooldownTimer_ - dt
        if frontMgCooldownTimer_ <= 0 and horizDist < 300 then
            frontMgFiring_ = true
            frontMgBurstTimer_ = p2.frontMgBurstDur
        end
    end

    -- === 飞弹调度（连续3轮齐射） ===
    p2MissileTimer_ = p2MissileTimer_ - dt
    if p2MissileTimer_ <= 0 and p2MissileWeapon_ then
        local fpData = tankGroundResult_:GetMissileFireData()
        for idx = 1, math.min(p2.missileCount, #fpData) do
            p2MissileWeapon_.mountNode = tankGroundResult_.missilePoints[idx]
            Weapons.FireSingle(p2MissileWeapon_, scene_, aimPos, false, mechNode, nil, nil)
        end
        p2MissileBurstCount_ = p2MissileBurstCount_ + 1
        if p2MissileBurstCount_ >= 3 then
            p2MissileTimer_ = p2.missileCooldown
            p2MissileBurstCount_ = 0
        else
            p2MissileTimer_ = missileBurstInterval_
        end
        print(string.format("[BossAI] Phase2: Missiles round %d/3!", p2MissileBurstCount_ == 0 and 3 or p2MissileBurstCount_))
    end

    -- === HP 检测 → 死亡 ===
    -- 不在这里设置 dead = true，让 main.lua 的死亡循环统一处理
    if bossEnemy_.hp <= 0 then
        bossEnemy_.hp = 0
        print("[BossAI] Phase2 HP depleted, awaiting death handling")
    end
end

-- ============================================================================
-- 主更新
-- ============================================================================

--- 每帧更新 BOSS AI
---@param dt number
---@param playerPos Vector3
---@param mechNode Node
function BossAI.Update(dt, playerPos, mechNode)
    if not phase_ then return end

    if phase_ == "phase1" then
        UpdatePhase1(dt, playerPos, mechNode)
    elseif phase_ == "transition" then
        UpdateTransition(dt, playerPos)
    elseif phase_ == "phase2" then
        UpdatePhase2(dt, playerPos, mechNode)
    end
    -- "dead" → 不做任何更新

    -- 更新小无人机死亡特效（闪光淡出、碎片飞散）
    MiniDrone.UpdateEffects(dt)
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 获取当前阶段
---@return string|nil "phase1"|"transition"|"phase2"|"dead"|nil
function BossAI.GetPhase()
    return phase_
end

--- 获取当前 HP
---@return number current
---@return number max
function BossAI.GetHP()
    if not bossEnemy_ then return 0, 0 end
    return bossEnemy_.hp, bossEnemy_.maxHp
end

--- 获取 bossEnemy 引用
---@return table|nil
function BossAI.GetEnemy()
    return bossEnemy_
end

-- ============================================================================
-- BOSS 死亡（由 main.lua 调用）
-- ============================================================================

--- Phase2 HP 耗尽后调用，处理死亡效果和状态转换
function BossAI.OnBossDeath()
    phase_ = "dead"
    if bossEnemy_ then
        bossEnemy_.bossPhase = "dead"
    end

    -- 战车 BOSS 零件飞散（使用实际模型零件）
    if tankNode_ then
        local tankPos = tankNode_.worldPosition
        ExplodeBossNode(tankNode_, tankPos, 20)
        -- 移除战车原始节点
        tankNode_:Remove()
        tankNode_ = nil

        -- 爆炸闪光
        local flashNode = scene_:CreateChild("BossDeathFlash")
        flashNode.position = tankPos + Vector3(0, 2, 0)
        local light = flashNode:CreateComponent("Light")
        light.lightType = LIGHT_POINT
        light.range = 50
        light.color = Color(1, 0.6, 0.2)
        light.brightness = 10
    end

    -- 清理存活的小无人机
    for _, md in ipairs(miniDrones_) do
        if md.node and not md.dead then
            MiniDrone.OnDeath(md)
        end
    end
    miniDrones_ = {}

    print("[BossAI] BOSS death effects triggered!")
end

-- ============================================================================
-- 清理
-- ============================================================================

function BossAI.Clear()
    -- 清理小无人机
    for _, md in ipairs(miniDrones_) do
        if md.node then md.node:Remove() end
    end
    miniDrones_ = {}
    MiniDrone.Clear()

    -- 清理过渡碎片
    for _, d in ipairs(transDebris_) do
        if d.node then d.node:Remove() end
        if d.lightNode then d.lightNode:Remove() end
    end
    transDebris_ = {}

    -- 清理节点
    if bossRootNode_ then bossRootNode_:Remove(); bossRootNode_ = nil end
    droneNode_ = nil  -- droneNode_ 是 bossRootNode_ 的子节点，已随父节点一并删除
    if tankFallNode_ then tankFallNode_:Remove(); tankFallNode_ = nil end
    if tankNode_ then tankNode_:Remove(); tankNode_ = nil end

    -- 重置状态
    phase_ = nil
    bossEnemy_ = nil
    cfg_ = nil
    scene_ = nil
    enemies_ = nil
    droneModel_ = nil
    droneResult_ = nil
    tankModel_ = nil
    tankResult_ = nil
    tankGroundResult_ = nil
    droneWeapons_ = {}
    missileWeapon_ = nil
    p1CannonWeaponL_ = nil
    p1CannonWeaponR_ = nil
    cannonWeaponL_ = nil
    cannonWeaponR_ = nil
    frontMgWeapon_ = nil
    p2MissileWeapon_ = nil
    debrisMat_ = nil

    print("[BossAI] Cleared.")
end

return BossAI
