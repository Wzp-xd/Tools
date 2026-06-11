-- ============================================================================
-- melee_ai.lua — 近战型敌人 AI
-- 主动冲向玩家进行近距离缠斗
-- ============================================================================

local MechBuilder = require "mech_builder"
local MechAnimator = require "mech_animator"
local Weapons = require "weapons"
local CONFIG = require "config"

local MeleeAI = {}

local AI = CONFIG.MeleeAI

local meleeCounter_ = 0

-- ============================================================================
-- 生成
-- ============================================================================

--- 生成一个近战型敌人
---@param scene Scene
---@param pos Vector3
---@param yaw number
---@return table enemy
function MeleeAI.Spawn(scene, pos, yaw)
    meleeCounter_ = meleeCounter_ + 1
    local root = scene:CreateChild("MeleeEnemy_" .. meleeCounter_)
    root.position = pos
    root.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints = MechBuilder.Build(root)
    local animator = MechAnimator.Create(joints)
    animator:Play("idle")

    local enemy = {
        node = root,
        animator = animator,
        joints = joints,
        meleeType = true,

        -- 战斗属性
        hp = AI.HP,
        maxHp = AI.MaxHP,
        dead = false,

        -- 锁定系统兼容字段
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        visualHeight = 3.5,

        -- AI 状态
        aiState = "approach",   -- approach / attack / cooldown / circle
        stateTimer = 0,
        attackCooldown = 0,
        attackDealt = false,

        -- 绕行
        circleDir = (math.random() > 0.5) and 1 or -1,
        circleTimer = 0,
    }

    return enemy
end

-- ============================================================================
-- AI 更新
-- ============================================================================

--- 每帧更新近战 AI
---@param enemy table
---@param scene Scene
---@param playerPos Vector3
---@param playerNode Node
---@param dt number
function MeleeAI.Update(enemy, scene, playerPos, playerNode, dt)
    if enemy.dead then return end

    local myPos = enemy.node.worldPosition
    local toPlayer = playerPos - myPos
    toPlayer.y = 0
    local distToPlayer = toPlayer:Length()
    local toPlayerDir = distToPlayer > 0.1 and toPlayer:Normalized() or Vector3.FORWARD

    -- ================================================================
    -- 面向玩家（平滑转向）
    -- ================================================================
    local targetYaw = math.deg(math.atan(toPlayerDir.x, toPlayerDir.z))
    local currentFwd = enemy.node.rotation * Vector3.FORWARD
    local currentYaw = math.deg(math.atan(currentFwd.x, currentFwd.z))
    local yawDiff = ((targetYaw - currentYaw + 180) % 360) - 180
    local maxTurn = AI.TurnSpeed * dt
    local actualTurn = math.max(-maxTurn, math.min(maxTurn, yawDiff))
    enemy.node.rotation = Quaternion(currentYaw + actualTurn, Vector3.UP)

    -- ================================================================
    -- 冷却计时
    -- ================================================================
    if enemy.attackCooldown > 0 then
        enemy.attackCooldown = enemy.attackCooldown - dt
    end

    -- ================================================================
    -- 状态转换
    -- ================================================================
    if enemy.aiState == "approach" then
        if distToPlayer <= AI.AttackRange and enemy.attackCooldown <= 0 then
            enemy.aiState = "attack"
            enemy.stateTimer = 0
            enemy.attackDealt = false
        end

    elseif enemy.aiState == "attack" then
        enemy.stateTimer = enemy.stateTimer + dt
        -- 前摇结束，造成伤害
        if enemy.stateTimer >= AI.AttackWindup and not enemy.attackDealt then
            if distToPlayer <= AI.AttackRange * 1.5 then
                Weapons.DamagePlayer(AI.AttackDamage)
                print(string.format("[MeleeAI] Melee hit! dmg=%d dist=%.1f", AI.AttackDamage, distToPlayer))
            end
            enemy.attackDealt = true
        end
        -- 攻击动画结束
        if enemy.stateTimer >= AI.AttackDuration then
            enemy.aiState = "cooldown"
            enemy.stateTimer = 0
            enemy.attackCooldown = AI.AttackCooldown
        end

    elseif enemy.aiState == "cooldown" then
        enemy.stateTimer = enemy.stateTimer + dt
        if enemy.stateTimer >= 0.3 then
            if distToPlayer > AI.EngageRange then
                enemy.aiState = "approach"
            else
                enemy.aiState = "circle"
                enemy.stateTimer = 0
                enemy.circleTimer = 0
            end
        end

    elseif enemy.aiState == "circle" then
        -- 随机换方向
        enemy.circleTimer = enemy.circleTimer + dt
        local changeDur = AI.CircleDirChangeMin + math.random() * (AI.CircleDirChangeMax - AI.CircleDirChangeMin)
        if enemy.circleTimer >= changeDur then
            enemy.circleDir = -enemy.circleDir
            enemy.circleTimer = 0
        end
        -- 冷却结束且足够近 → 攻击
        if enemy.attackCooldown <= 0 and distToPlayer <= AI.AttackRange then
            enemy.aiState = "attack"
            enemy.stateTimer = 0
            enemy.attackDealt = false
        end
        -- 太远 → 重新冲锋
        if distToPlayer > AI.EngageRange then
            enemy.aiState = "approach"
        end
    end

    -- ================================================================
    -- 移动
    -- ================================================================
    local pos = enemy.node.position
    local moveDir = Vector3.ZERO
    local moveSpeed = 0

    if enemy.aiState == "approach" then
        moveDir = toPlayerDir
        moveSpeed = AI.ApproachSpeed

    elseif enemy.aiState == "circle" then
        -- 垂直于玩家方向 + 距离修正
        local perpDir = Vector3(toPlayerDir.z, 0, -toPlayerDir.x) * enemy.circleDir
        moveDir = perpDir
        local idealDist = (AI.AttackRange + AI.CircleRange) * 0.5
        if distToPlayer > idealDist + 2 then
            moveDir = moveDir + toPlayerDir * 0.5
        elseif distToPlayer < idealDist - 2 then
            moveDir = moveDir - toPlayerDir * 0.5
        end
        if moveDir:Length() > 0.01 then
            moveDir = moveDir:Normalized()
        end
        moveSpeed = AI.CircleSpeed
    end
    -- attack / cooldown 状态不移动

    if moveDir:Length() > 0.01 then
        pos = pos + moveDir * moveSpeed * dt
    end
    pos.y = 0  -- 始终贴地
    enemy.node.position = pos

    -- ================================================================
    -- 动画
    -- ================================================================
    local animName = "idle"
    if enemy.aiState == "approach" then
        animName = "move_f"
    elseif enemy.aiState == "circle" then
        animName = enemy.circleDir > 0 and "move_r" or "move_l"
    elseif enemy.aiState == "attack" then
        animName = "attack"
    end
    enemy.animator:Play(animName)
    enemy.animator:Update(dt)
end

return MeleeAI
