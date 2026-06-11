-- ============================================================================
-- 精英敌人 AI 模块
-- Elite Enemy AI - State Machine + Weapon Scheduling + LOS
-- ============================================================================
-- 状态机:
--   idle     → 远离玩家，无交战
--   engage   → 中距离战斗（50~150m），保持距离
--   retreat  → 玩家过近（<50m），后退拉开距离
--   reposition → 太远（>150m），接近玩家
--
-- 移动能力:
--   横向漂移 + 多方向随机移动
--   弹丸检测闪避（dash dodge）
--   跳跃
--   喷射飞行（空中悬停战斗）
--
-- 武器调度:
--   机关枪: 连续射击 burst + cooldown 循环
--   RPG:    独立冷却计时器
--   飞弹:   独立冷却计时器 + 逐发队列
-- ============================================================================

local CONFIG = require "config"
local Weapons = require "weapons"
local WeaponManager = require "weapon_manager"
local WeaponDefs = require "weapon_defs"
local MechBuilder = require "mech_builder"
local MechAnimator = require "mech_animator"

local EliteAI = {}

-- AI 配置常量（从 CONFIG 读取）
local AI = CONFIG.EliteAI

-- ============================================================================
-- 生成精英敌人
-- ============================================================================

--- 生成精英敌人
---@param scene Scene
---@param eliteCfg table 关卡中的 eliteEnemy 配置
---@return table elite 精英敌人数据
function EliteAI.Spawn(scene, eliteCfg)
    local root = scene:CreateChild("EliteEnemy")
    root.position = eliteCfg.spawnPos
    root.rotation = Quaternion(eliteCfg.spawnYaw or 0, Vector3.UP)

    -- 构建机甲模型
    local modelNode, joints = MechBuilder.Build(root)
    local animator = MechAnimator.Create(joints)
    animator:Play("idle")

    -- 创建武器（owner = "enemy"，使用默认装备配置）
    local aiLoadout = EliteAI.RandomLoadout()
    local aiWeapons = WeaponManager.CreateWeaponsFromLoadout(aiLoadout, joints, "enemy")

    -- 确定 AI 类型（基于武器装备）
    local aiType = EliteAI.DetermineAIType(aiLoadout)
    local aiConfig = EliteAI.MakeAIConfig(aiType)

    -- 应用伤害倍率
    local dmgMult = eliteCfg.dmgMult or 1.0
    if dmgMult ~= 1.0 then
        for _, w in pairs(aiWeapons) do
            if type(w) == "table" and w.def then
                w.dmgMult = dmgMult
            end
        end
    end

    local elite = {
        node = root,
        modelNode = modelNode,
        joints = joints,
        animator = animator,

        -- 生命值
        hp = eliteCfg.hp or 500,
        maxHp = eliteCfg.maxHp or 500,
        dead = false,

        -- AI 类型 + 按实例配置
        aiType = aiType,        -- "standard" | "melee" | "aerial"
        ai = aiConfig,          -- per-instance config (metatable fallback to global AI)

        -- 武器 + 装备配置
        loadout = aiLoadout,
        weaponHandL = aiWeapons.handL,
        weaponHandR = aiWeapons.handR,
        weaponShoulderL = aiWeapons.shoulderL,
        weaponShoulderR = aiWeapons.shoulderR,

        -- AI 状态
        state = "idle",         -- idle / engage / retreat / reposition
        stateTimer = 0,         -- 当前状态持续时间

        -- 视线缓存
        hasLOS = false,
        losTimer = 0,

        -- 武器调度计时器
        engageTimer = 0,        -- 进入 engage 后的计时（控制初始延迟）
        mgFiring = false,       -- rapid 类武器连射状态
        mgBurstTimer = 0,       -- rapid 类连发/间歇计时
        rpgTimer = AI.RPG_InitialDelay,     -- 右手武器计时
        missileTimerR = AI.Missile_InitialDelay, -- 右肩武器计时
        missileTimerL = AI.Missile_InitialDelay + 2.0, -- 左肩武器计时（错开）

        -- 飞弹发射队列（右肩）
        missileQueueR = {},
        missileWeaponR = nil,
        missileFireTimerR = 0,

        -- 飞弹发射队列（左肩）
        missileQueueL = {},
        missileWeaponL = nil,
        missileFireTimerL = 0,

        -- 横向漂移 & 多方向移动
        lateralDir = 1,         -- 1=右, -1=左
        lateralTimer = 0,       -- 漂移方向切换计时
        moveAngle = 0,          -- 当前移动角度偏移（弧度）
        moveAngleTimer = 0,     -- 角度切换计时

        -- 闪避系统
        dodging = false,        -- 是否正在闪避中
        dodgeDir = Vector3.ZERO,-- 闪避方向
        dodgeTimer = 0,         -- 闪避剩余时间
        dodgeCooldownTimer = 0, -- 闪避冷却计时

        -- 跳跃系统
        velocityY = 0,          -- 垂直速度
        onGround = true,        -- 是否在地面
        jumpCooldownTimer = 0,  -- 跳跃冷却

        -- 喷射闪避系统（检测 RPG/飞弹时触发）
        jetDodging = false,             -- 是否正在喷射闪避
        jetDodgeDir = Vector3.ZERO,     -- 喷射闪避方向
        jetDodgeTimer = 0,              -- 喷射闪避剩余时间
        jetDodgeCooldownTimer = 0,      -- 喷射闪避冷却

        -- 飞行系统
        flying = false,         -- 是否在飞行状态
        flyTimer = 0,           -- 飞行剩余时间
        flyCooldownTimer = 0,   -- 飞行冷却
        flyVelocity = Vector3.ZERO, -- 飞行速度

        -- 重生配置
        spawnPos = Vector3(eliteCfg.spawnPos.x, eliteCfg.spawnPos.y, eliteCfg.spawnPos.z),
        spawnYaw = eliteCfg.spawnYaw or 0,
        dmgMult = dmgMult,      -- 保存伤害倍率供重生时使用

        -- 锁定系统兼容字段（让 HUD 锁定系统能识别）
        lockValue = 0,
        locked = false,
        screenX = 0.5,
        screenY = 0.5,
        dist = 999,
        screenSize = 64,
        isPrimary = false,
    }

    print(string.format("[EliteAI] Spawned at (%.0f, %.0f, %.0f) HP=%d Type=%s",
        eliteCfg.spawnPos.x, eliteCfg.spawnPos.y, eliteCfg.spawnPos.z, elite.hp, aiType))

    return elite
end

-- ============================================================================
-- 弹丸威胁检测
-- ============================================================================

--- 检测是否有玩家弹丸正朝向精英飞来
---@param elite table
---@return boolean hasThreat 是否有威胁
---@return Vector3|nil dodgeDir 建议闪避方向（垂直于弹丸飞行方向）
local function DetectProjectileThreat(elite)
    local projectiles = Weapons.GetProjectiles()
    if not projectiles then return false, nil end

    local myPos = elite.node.worldPosition + Vector3(0, 2.0, 0) -- 中心点偏上
    local detectR = AI.DodgeDetectRadius
    local detectAngleRad = math.rad(AI.DodgeDetectAngle)

    for _, p in ipairs(projectiles) do
        -- 只检测玩家的弹丸
        if p.owner == "player" and p.node then
            local pPos = p.node.worldPosition
            local toMe = myPos - pPos
            local dist = toMe:Length()

            if dist < detectR and dist > 1.0 then
                -- 弹丸飞行方向
                local pDir = p.node.worldDirection
                if pDir:Length() < 0.01 then
                    -- fallback: 使用速度方向
                    pDir = Vector3(0, 0, 1)
                end
                pDir = pDir:Normalized()

                -- 计算弹丸方向与"弹丸→我"方向的夹角
                local toMeNorm = toMe:Normalized()
                local dot = pDir:DotProduct(toMeNorm)

                -- dot > cos(angle) 意味着弹丸正朝我飞来
                if dot > math.cos(detectAngleRad) then
                    -- 计算闪避方向：垂直于弹丸飞行方向（取水平分量）
                    local perpRight = Vector3(pDir.z, 0, -pDir.x)
                    if perpRight:Length() < 0.01 then
                        perpRight = Vector3(1, 0, 0)
                    end
                    perpRight = perpRight:Normalized()

                    -- 随机选左或右
                    if math.random() > 0.5 then
                        perpRight = perpRight * -1
                    end

                    return true, perpRight
                end
            end
        end
    end

    return false, nil
end

--- 检测是否有玩家 RPG 或飞弹正朝向精英飞来（用于触发喷射闪避）
---@param elite table
---@return boolean hasThreat 是否有重型弹丸威胁
---@return Vector3|nil dodgeDir 建议喷射闪避方向
local function DetectHeavyProjectileThreat(elite)
    local projectiles = Weapons.GetProjectiles()
    if not projectiles then return false, nil end

    local myPos = elite.node.worldPosition + Vector3(0, 2.0, 0)
    local detectR = AI.JetDodgeDetectRadius
    local detectAngleRad = math.rad(AI.DodgeDetectAngle)

    for _, p in ipairs(projectiles) do
        if p.owner == "player" and p.node then
            -- 只检测爆炸性弹丸（有 blastRadius 的武器类型）
            local pDef = WeaponDefs.Get(p.weaponType)
            if not pDef or not pDef.blastRadius then
                goto continue
            end

            local pPos = p.node.worldPosition
            local toMe = myPos - pPos
            local dist = toMe:Length()

            if dist < detectR and dist > 1.0 then
                local pDir = p.node.worldDirection
                if pDir:Length() < 0.01 then
                    pDir = Vector3(0, 0, 1)
                end
                pDir = pDir:Normalized()

                local toMeNorm = toMe:Normalized()
                local dot = pDir:DotProduct(toMeNorm)

                if dot > math.cos(detectAngleRad) then
                    -- 闪避方向：垂直于弹丸飞行方向（水平）
                    local perpRight = Vector3(pDir.z, 0, -pDir.x)
                    if perpRight:Length() < 0.01 then
                        perpRight = Vector3(1, 0, 0)
                    end
                    perpRight = perpRight:Normalized()

                    if math.random() > 0.5 then
                        perpRight = perpRight * -1
                    end

                    return true, perpRight
                end
            end
            ::continue::
        end
    end

    return false, nil
end

-- ============================================================================
-- AI 状态机更新
-- ============================================================================

--- 更新精英 AI（每帧调用）
---@param elite table 精英敌人数据
---@param scene Scene
---@param playerPos Vector3 玩家世界坐标
---@param playerNode Node 玩家节点
---@param dt number 帧间隔
function EliteAI.Update(elite, scene, playerPos, playerNode, dt)
    if elite.dead then return end

    ---@diagnostic disable-next-line: redefined-local
    local AI = elite.ai   -- 按实例配置（遮蔽模块级 AI，通过 metatable 回退到默认值）

    local myPos = elite.node.worldPosition
    local toPlayer = playerPos - myPos
    local distToPlayer = toPlayer:Length()

    -- ================================================================
    -- 视线检测（带间隔缓存）
    -- ================================================================
    elite.losTimer = elite.losTimer + dt
    if elite.losTimer >= AI.LOSCheckInterval then
        elite.losTimer = 0
        elite.hasLOS = EliteAI.CheckLOS(scene, myPos + Vector3(0, 2.0, 0),
            playerPos + Vector3(0, 1.7, 0))
    end

    -- ================================================================
    -- 状态转换
    -- ================================================================
    elite.stateTimer = elite.stateTimer + dt

    if distToPlayer < AI.RangeMin then
        if elite.state ~= "retreat" then
            elite.state = "retreat"
            elite.stateTimer = 0
        end
    elseif distToPlayer > AI.RangeMax then
        if elite.state ~= "reposition" and elite.state ~= "engage" then
            elite.state = "reposition"
            elite.stateTimer = 0
        end
        if elite.state == "engage" and distToPlayer > AI.RangeMax + 20 then
            elite.state = "reposition"
            elite.stateTimer = 0
        end
    else
        if elite.state ~= "engage" then
            elite.state = "engage"
            elite.stateTimer = 0
            elite.engageTimer = 0
            elite.mgFiring = false
            elite.mgBurstTimer = 0
            elite.rpgTimer = AI.RPG_InitialDelay
            elite.missileTimerR = AI.Missile_InitialDelay
            elite.missileTimerL = AI.Missile_InitialDelay + 2.0
        end
    end

    -- ================================================================
    -- 朝向：始终面向玩家（水平）
    -- ================================================================
    local toPlayerFlat = Vector3(toPlayer.x, 0, toPlayer.z)
    local flatLen = toPlayerFlat:Length()
    if flatLen > 0.1 then
        toPlayerFlat = toPlayerFlat / flatLen
        local targetYaw = math.deg(math.atan(toPlayerFlat.x, toPlayerFlat.z))
        local currentRot = elite.node.rotation
        local currentFwd = currentRot * Vector3.FORWARD
        local currentYaw = math.deg(math.atan(currentFwd.x, currentFwd.z))
        local yawDiff = ((targetYaw - currentYaw + 180) % 360) - 180
        local maxTurn = AI.TurnSpeed * dt
        local actualTurn = math.max(-maxTurn, math.min(maxTurn, yawDiff))
        elite.node.rotation = Quaternion(currentYaw + actualTurn, Vector3.UP)
    end

    -- ================================================================
    -- 闪避冷却更新
    -- ================================================================
    if elite.dodgeCooldownTimer > 0 then
        elite.dodgeCooldownTimer = elite.dodgeCooldownTimer - dt
    end

    -- ================================================================
    -- 弹丸检测闪避
    -- ================================================================
    if not elite.dodging and elite.dodgeCooldownTimer <= 0 then
        local hasThreat, dodgeDir = DetectProjectileThreat(elite)
        if hasThreat and dodgeDir then
            -- 概率触发闪避
            if math.random() < AI.DodgeChance then
                elite.dodging = true
                elite.dodgeDir = dodgeDir
                elite.dodgeTimer = AI.DodgeDuration
                elite.dodgeCooldownTimer = AI.DodgeCooldown
            end
        end
    end

    -- ================================================================
    -- 喷射闪避冷却更新
    -- ================================================================
    if elite.jetDodgeCooldownTimer > 0 then
        elite.jetDodgeCooldownTimer = elite.jetDodgeCooldownTimer - dt
    end

    -- ================================================================
    -- RPG/飞弹检测 → 喷射闪避
    -- 条件：未在普通闪避、未在喷射闪避、未在飞行中、冷却完毕
    -- ================================================================
    if not elite.dodging and not elite.jetDodging and not elite.flying
        and elite.jetDodgeCooldownTimer <= 0 then
        local hasThreat, dodgeDir = DetectHeavyProjectileThreat(elite)
        if hasThreat and dodgeDir then
            if math.random() < AI.JetDodgeChance then
                elite.jetDodging = true
                elite.jetDodgeDir = dodgeDir
                elite.jetDodgeTimer = AI.JetDodgeDuration
                elite.jetDodgeCooldownTimer = AI.JetDodgeCooldown
            end
        end
    end

    -- ================================================================
    -- 移动逻辑
    -- ================================================================
    local moveDir = Vector3.ZERO
    local moveSpeed = AI.MoveSpeed

    if elite.dodging then
        -- 闪避移动（最高优先级）
        moveDir = elite.dodgeDir
        moveSpeed = AI.DodgeImpulse
        elite.dodgeTimer = elite.dodgeTimer - dt
        if elite.dodgeTimer <= 0 then
            elite.dodging = false
        end
    elseif elite.jetDodging then
        -- 喷射闪避（次高优先级，侧向高速移动）
        moveDir = elite.jetDodgeDir
        moveSpeed = AI.JetDodgeSpeed
        elite.jetDodgeTimer = elite.jetDodgeTimer - dt
        if elite.jetDodgeTimer <= 0 then
            elite.jetDodging = false
        end
    elseif elite.state == "retreat" then
        -- 远离玩家
        moveSpeed = AI.RetreatSpeed
        if flatLen > 0.1 then
            moveDir = toPlayerFlat * -1
        end
    elseif elite.state == "reposition" then
        -- 接近玩家
        if flatLen > 0.1 then
            moveDir = toPlayerFlat
        end
    elseif elite.state == "engage" then
        -- 多方向移动：横向漂移 + 随机角度偏移
        elite.lateralTimer = elite.lateralTimer + dt
        if elite.lateralTimer > 3.0 + math.random() * 2.0 then
            elite.lateralTimer = 0
            elite.lateralDir = -elite.lateralDir
        end

        -- 随机移动角度切换（绕玩家方向偏转）
        elite.moveAngleTimer = elite.moveAngleTimer + dt
        if elite.moveAngleTimer > 1.5 + math.random() * 2.0 then
            elite.moveAngleTimer = 0
            -- -60° ~ +60° 的随机偏转
            elite.moveAngle = (math.random() - 0.5) * math.rad(120)
        end

        -- 基础方向：机甲右方向 * lateralDir
        local myRight = elite.node.rotation * Vector3.RIGHT
        local baseDir = myRight * elite.lateralDir

        -- 加上角度偏移（绕 Y 轴旋转 baseDir）
        local cosA = math.cos(elite.moveAngle)
        local sinA = math.sin(elite.moveAngle)
        local rotatedDir = Vector3(
            baseDir.x * cosA - baseDir.z * sinA,
            0,
            baseDir.x * sinA + baseDir.z * cosA
        )

        moveDir = rotatedDir * AI.LateralDriftSpeed

        -- 距离微调
        if distToPlayer < AI.RangeIdeal - 10 then
            moveDir = moveDir - toPlayerFlat * 0.5
        elseif distToPlayer > AI.RangeIdeal + 10 then
            moveDir = moveDir + toPlayerFlat * 0.5
        end

        if moveDir:Length() > 0.01 then
            moveDir = moveDir:Normalized()
        end
    end

    -- ================================================================
    -- 跳跃系统
    -- ================================================================
    elite.jumpCooldownTimer = math.max(0, elite.jumpCooldownTimer - dt)

    if elite.onGround and not elite.flying and elite.jumpCooldownTimer <= 0 then
        -- 在地面时随机触发跳跃（engage 或 retreat 状态下）
        if elite.state == "engage" or elite.state == "retreat" then
            if math.random() < AI.JumpChance * dt then
                elite.velocityY = AI.JumpSpeed
                elite.onGround = false
                elite.jumpCooldownTimer = AI.JumpCooldown
            end
        end
    end

    -- ================================================================
    -- 飞行系统
    -- ================================================================
    elite.flyCooldownTimer = math.max(0, elite.flyCooldownTimer - dt)

    if not elite.flying then
        -- 尝试进入飞行状态（aerial 类型在所有战斗状态都可触发）
        local canTriggerFly = (elite.state == "engage")
            or (AI.JetAllStates and (elite.state == "retreat" or elite.state == "reposition"))
        if canTriggerFly and elite.flyCooldownTimer <= 0 then
            if math.random() < AI.JetChance * dt then
                elite.flying = true
                elite.flyTimer = AI.JetDuration
                elite.onGround = false
                elite.velocityY = AI.JetSpeed  -- 起飞初速度
                elite.flyVelocity = Vector3.ZERO
            end
        end
    else
        -- 飞行中
        elite.flyTimer = elite.flyTimer - dt
        local pos = elite.node.position

        -- 飞行高度控制
        if pos.y < AI.JetMinAltitude then
            -- 低于最低高度，加速上升
            elite.velocityY = math.max(elite.velocityY, AI.JetSpeed)
        elseif pos.y > AI.JetMaxAltitude then
            -- 高于最大高度，减速下降
            elite.velocityY = math.min(elite.velocityY, -AI.JetSpeed * 0.5)
        else
            -- 悬停范围内：小幅浮动
            local targetAlt = (AI.JetMinAltitude + AI.JetMaxAltitude) * 0.5
            local altErr = targetAlt - pos.y
            elite.velocityY = elite.velocityY + altErr * 2.0 * dt
            -- 阻尼
            elite.velocityY = elite.velocityY * (1.0 - AI.JetDamping * dt)
        end

        -- 飞行时间结束 → 下降着陆
        if elite.flyTimer <= 0 then
            elite.flying = false
            elite.flyCooldownTimer = AI.JetCooldown
            -- 不立即着陆，让重力处理
        end
    end

    -- ================================================================
    -- 应用移动 + 垂直物理
    -- ================================================================
    local pos = elite.node.position

    -- 水平移动
    if moveDir:Length() > 0.01 then
        local hMove = Vector3(moveDir.x, 0, moveDir.z) * moveSpeed * dt
        pos = pos + hMove
    end

    -- 垂直物理
    if elite.flying then
        -- 飞行模式：应用 velocityY，无重力
        pos.y = pos.y + elite.velocityY * dt
    else
        -- 非飞行：应用重力
        elite.velocityY = elite.velocityY + AI.JumpGravity * dt
        pos.y = pos.y + elite.velocityY * dt

        -- 地面碰撞
        if pos.y <= 0 then
            pos.y = 0
            elite.velocityY = 0
            elite.onGround = true
        else
            elite.onGround = false
        end
    end

    elite.node.position = pos

    -- ================================================================
    -- 动画
    -- ================================================================
    local animName = "idle"
    if elite.flying then
        animName = "fly"
    elseif not elite.onGround then
        animName = "jump"
    elseif elite.dodging or elite.jetDodging then
        -- 闪避/喷射闪避时根据方向选动画
        local dDir = elite.dodging and elite.dodgeDir or elite.jetDodgeDir
        local myRight = elite.node.rotation * Vector3.RIGHT
        local dot = dDir:DotProduct(myRight)
        if dot > 0 then
            animName = "move_r"
        else
            animName = "move_l"
        end
    elseif elite.state == "retreat" then
        animName = "move_b"
    elseif elite.state == "reposition" then
        animName = "move_f"
    elseif elite.state == "engage" then
        if elite.lateralDir > 0 then
            animName = "move_r"
        else
            animName = "move_l"
        end
    end
    elite.animator:Play(animName)
    elite.animator:Update(dt)

    -- ================================================================
    -- 武器调度（engage/retreat/reposition 状态 + 有视线时均可开火）
    -- ================================================================
    local canFire = (elite.state == "engage" or elite.state == "retreat" or elite.state == "reposition")
    if canFire then
        elite.engageTimer = elite.engageTimer + dt

        if elite.engageTimer > AI.InitialDelay and elite.hasLOS then
            local targetPos = playerPos + Vector3(0, 1.7, 0)

            -- 左手武器调度（rapid/burst/precision）
            EliteAI.UpdateHandL(elite, scene, targetPos, playerNode, dt)

            -- 右手武器调度（explosive/tracking/precision，排除 defensive）
            EliteAI.UpdateHandR(elite, scene, targetPos, playerNode, dt)

            -- 右肩武器调度
            EliteAI.UpdateShoulder(elite, scene, targetPos, playerNode, dt, "R")

            -- 左肩武器调度
            EliteAI.UpdateShoulder(elite, scene, targetPos, playerNode, dt, "L")
        end
    else
        elite.mgFiring = false
    end

    -- ================================================================
    -- 武器更新（连发/换弹/闪光）—— 所有状态都需要
    -- ================================================================
    local allWpns = { elite.weaponHandL, elite.weaponHandR,
                      elite.weaponShoulderL, elite.weaponShoulderR }
    for _, w in ipairs(allWpns) do
        Weapons.UpdateBurst(w, dt)
        Weapons.UpdateReload(w, dt)
        Weapons.UpdateMuzzleFlash(w, dt)
    end

    -- 右肩飞弹队列逐发发射
    if #elite.missileQueueR > 0 and elite.missileWeaponR then
        elite.missileFireTimerR = elite.missileFireTimerR - dt
        if elite.missileFireTimerR <= 0 then
            local t = table.remove(elite.missileQueueR, 1)
            local tPos = t.targetPos
            if t.targetNode then
                tPos = t.targetNode.worldPosition + Vector3(0, 1.7, 0)
            end
            Weapons.FireSingle(elite.missileWeaponR, scene, tPos, true, t.targetNode, 60)
            elite.missileFireTimerR = AI.Missile_BurstInterval
            if #elite.missileQueueR == 0 then
                elite.missileWeaponR = nil
            end
        end
    end

    -- 左肩飞弹队列逐发发射
    if #elite.missileQueueL > 0 and elite.missileWeaponL then
        elite.missileFireTimerL = elite.missileFireTimerL - dt
        if elite.missileFireTimerL <= 0 then
            local t = table.remove(elite.missileQueueL, 1)
            local tPos = t.targetPos
            if t.targetNode then
                tPos = t.targetNode.worldPosition + Vector3(0, 1.7, 0)
            end
            Weapons.FireSingle(elite.missileWeaponL, scene, tPos, true, t.targetNode, -60)
            elite.missileFireTimerL = AI.Missile_BurstInterval
            if #elite.missileQueueL == 0 then
                elite.missileWeaponL = nil
            end
        end
    end
end

-- ============================================================================
-- 武器调度子函数
-- ============================================================================

--- 左手武器调度（基于 category 自适应）
--- rapid: burst/cooldown 循环 | burst/precision: 定时射击
function EliteAI.UpdateHandL(elite, scene, targetPos, playerNode, dt)
    local wpn = elite.weaponHandL
    if not wpn or wpn.reloading then return end

    local def = wpn.def
    if not def then return end
    local cat = def.category

    if cat == "rapid" then
        -- burst/cooldown 循环（机关枪模式）
        elite.mgBurstTimer = elite.mgBurstTimer + dt
        if elite.mgFiring then
            Weapons.TryFire(wpn, scene, targetPos, true, playerNode)
            if elite.mgBurstTimer >= AI.MG_BurstDuration then
                elite.mgFiring = false
                elite.mgBurstTimer = 0
            end
        else
            local cooldown = AI.MG_CooldownMin + math.random() * (AI.MG_CooldownMax - AI.MG_CooldownMin)
            if elite.mgBurstTimer >= cooldown then
                elite.mgFiring = true
                elite.mgBurstTimer = 0
            end
        end
    else
        -- burst/precision 类：按武器射速定时射击
        elite.mgBurstTimer = elite.mgBurstTimer + dt
        local interval = 1.0 / (def.fireRate or 1.0)
        if elite.mgBurstTimer >= interval then
            Weapons.TryFire(wpn, scene, targetPos, true, playerNode)
            elite.mgBurstTimer = 0
        end
    end
end

--- 右手武器调度（基于 category 自适应）
--- defensive(shield): AI 跳过 | 其他: 定时射击
function EliteAI.UpdateHandR(elite, scene, targetPos, playerNode, dt)
    local wpn = elite.weaponHandR
    if not wpn or wpn.reloading then return end

    local def = wpn.def
    if not def then return end

    -- AI 不使用护盾
    if def.isShield or def.category == "defensive" then return end

    elite.rpgTimer = elite.rpgTimer - dt
    if elite.rpgTimer <= 0 then
        Weapons.TryFire(wpn, scene, targetPos, true, playerNode)
        elite.rpgTimer = AI.RPG_Cooldown
    end
end

--- 肩部武器调度（基于 category 自适应）
--- tracking + burstCount: 队列逐发 | 其他: 定时直射
---@param side string "R" 或 "L"
function EliteAI.UpdateShoulder(elite, scene, targetPos, playerNode, dt, side)
    local queue = side == "L" and elite.missileQueueL or elite.missileQueueR
    if #queue > 0 then return end

    local wpn = side == "L" and elite.weaponShoulderL or elite.weaponShoulderR
    if not wpn then return end

    local def = wpn.def
    if not def then return end

    local timerKey = "missileTimer" .. side
    elite[timerKey] = elite[timerKey] - dt
    if elite[timerKey] <= 0 then
        if wpn.reloading or wpn.ammo <= 0 or wpn.burstRemaining > 0 then
            elite[timerKey] = 1.0
            return
        end

        local yawOffset = side == "L" and -60 or 60

        if def.category == "tracking" and (def.burstCount or 0) > 1 then
            local newQueue = {}
            for i = 1, wpn.ammo do
                table.insert(newQueue, {
                    targetPos = Vector3(targetPos.x, targetPos.y, targetPos.z),
                    targetNode = playerNode,
                })
            end
            if side == "L" then
                elite.missileQueueL = newQueue
                elite.missileWeaponL = wpn
                elite.missileFireTimerL = 0
            else
                elite.missileQueueR = newQueue
                elite.missileWeaponR = wpn
                elite.missileFireTimerR = 0
            end
        else
            Weapons.TryFire(wpn, scene, targetPos, true, playerNode, yawOffset)
        end

        elite[timerKey] = AI.Missile_Cooldown
    end
end

-- ============================================================================
-- 随机装备生成
-- ============================================================================

--- 为 AI 生成随机武器装备
---@return table loadout { handL, handR, shoulderR }
function EliteAI.RandomLoadout()
    local loadout = {}
    for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
        local options = WeaponDefs.SLOTS[slot].options
        -- 过滤掉护盾（AI 不使用）
        local valid = {}
        for _, wType in ipairs(options) do
            local def = WeaponDefs.Get(wType)
            if def and not def.isShield then
                table.insert(valid, wType)
            end
        end
        if #valid > 0 then
            loadout[slot] = valid[math.random(1, #valid)]
        else
            loadout[slot] = options[1]  -- fallback
        end
    end
    print(string.format("[EliteAI] Random loadout: L=%s R=%s SL=%s SR=%s",
        loadout.handL, loadout.handR, loadout.shoulderL, loadout.shoulderR))
    return loadout
end

-- ============================================================================
-- AI 类型判定
-- ============================================================================

--- 根据武器装备决定 AI 类型
---@param loadout table 武器装备配置
---@return string aiType "standard" | "melee" | "aerial"
function EliteAI.DetermineAIType(loadout)
    -- 规则 1: 霰弹枪 → 近战型（最高优先级）
    if loadout.handL == "shotgun" then
        return "melee"
    end

    -- 规则 2: 装备 RPG / 肩扛火箭 → 35% 概率飞行型
    local hasExplosiveLauncher = (loadout.handR == "rpg")
        or (loadout.shoulderL == "shoulder_rpg")
        or (loadout.shoulderR == "shoulder_rpg")
    if hasExplosiveLauncher and math.random() < 0.35 then
        return "aerial"
    end

    return "standard"
end

--- 创建按实例的 AI 配置（通过 metatable 回退到全局 AI 默认值）
---@param aiType string
---@return table config
function EliteAI.MakeAIConfig(aiType)
    local overrides = (AI.TypeOverrides and AI.TypeOverrides[aiType]) or {}
    return setmetatable(overrides, { __index = AI })
end

-- ============================================================================
-- 视线检测
-- ============================================================================

--- 射线检测视线（仅检测静态场景遮挡）
---@param scene Scene
---@param fromPos Vector3
---@param toPos Vector3
---@return boolean
function EliteAI.CheckLOS(scene, fromPos, toPos)
    local pw = scene:GetComponent("PhysicsWorld")
    if not pw then return true end

    local dir = toPos - fromPos
    local dist = dir:Length()
    if dist < 0.1 then return true end
    dir = dir / dist

    local result = pw:RaycastSingle(Ray(fromPos, dir), dist, CollisionLayerStatic)
    if result and result.body then
        return false
    end
    return true
end

-- ============================================================================
-- 重生
-- ============================================================================

--- 重生精英敌人（重置状态和武器）
---@param elite table
---@param scene Scene
function EliteAI.Respawn(elite, scene)
    if elite.node then
        elite.node:Remove()
    end

    local root = scene:CreateChild("EliteEnemy")
    root.position = elite.spawnPos
    root.rotation = Quaternion(elite.spawnYaw, Vector3.UP)

    local modelNode, joints = MechBuilder.Build(root)
    local animator = MechAnimator.Create(joints)
    animator:Play("idle")

    local aiLoadout = EliteAI.RandomLoadout()
    local aiWeapons = WeaponManager.CreateWeaponsFromLoadout(aiLoadout, joints, "enemy")
    local aiType = EliteAI.DetermineAIType(aiLoadout)
    elite.loadout = aiLoadout
    elite.aiType = aiType
    elite.ai = EliteAI.MakeAIConfig(aiType)
    -- 应用伤害倍率（与 Spawn 一致）
    local dmgMult = elite.dmgMult or 1.0
    if dmgMult ~= 1.0 then
        for _, w in pairs(aiWeapons) do
            if type(w) == "table" and w.def then
                w.dmgMult = dmgMult
            end
        end
    end

    elite.weaponHandL = aiWeapons.handL
    elite.weaponHandR = aiWeapons.handR
    elite.weaponShoulderL = aiWeapons.shoulderL
    elite.weaponShoulderR = aiWeapons.shoulderR

    elite.node = root
    elite.modelNode = modelNode
    elite.joints = joints
    elite.animator = animator
    elite.hp = elite.maxHp
    elite.dead = false

    -- 重置 AI 状态
    elite.state = "idle"
    elite.stateTimer = 0
    elite.engageTimer = 0
    elite.hasLOS = false
    elite.losTimer = 0
    elite.mgFiring = false
    elite.mgBurstTimer = 0
    elite.rpgTimer = AI.RPG_InitialDelay
    elite.missileTimerR = AI.Missile_InitialDelay
    elite.missileTimerL = AI.Missile_InitialDelay + 2.0
    elite.missileQueueR = {}
    elite.missileWeaponR = nil
    elite.missileQueueL = {}
    elite.missileWeaponL = nil
    elite.lateralTimer = 0
    elite.moveAngle = 0
    elite.moveAngleTimer = 0

    -- 重置闪避/跳跃/飞行
    elite.dodging = false
    elite.dodgeDir = Vector3.ZERO
    elite.dodgeTimer = 0
    elite.dodgeCooldownTimer = 0
    elite.velocityY = 0
    elite.onGround = true
    elite.jumpCooldownTimer = 0
    elite.flying = false
    elite.flyTimer = 0
    elite.flyCooldownTimer = 0
    elite.flyVelocity = Vector3.ZERO

    print(string.format("[EliteAI] Respawned at (%.0f, %.0f, %.0f) HP=%d Type=%s",
        elite.spawnPos.x, elite.spawnPos.y, elite.spawnPos.z, elite.hp, elite.aiType))
end

return EliteAI
