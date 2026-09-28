-- ============================================================================
-- Monster.lua - 怪物系统（使用引擎物理）
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Audio = require "modules.Audio"
local UI = require "modules.UI"

local M = {}

-- 猪头人小兵模型和动画配置
local MONSTER_MODEL = {
    prefab = "uuid://BuMYIfzUEQ6WeJw4XluyfWmX",
    animations = {
        idle = "uuid://Bpw9Qeu4LaxqFlzPpwndyob0",    -- Idle
        move = "uuid://BdtVkeb5UshZFxP7XWLzV-kH",    -- Move
        attack = "uuid://C0kf-aUuuJWZsverF_CZc1-3",  -- Attack01
    },
    scale = 1.0,  -- 模型缩放
    attackHitDelay = 0.6,  -- 攻击前摇时间（秒），伤害在此时间后生效
}

local CONFIG = Config.CONFIG

--- 切换动态怪物
function M.ToggleDynamic()
    GameState.dynamicMonsterEnabled = not GameState.dynamicMonsterEnabled
    if GameState.dynamicMonsterEnabled then
        M.Create(false)  -- 创建动态怪物
        print("Dynamic monsters enabled")
    else
        M.ClearByType(false)
        print("Dynamic monsters disabled")
    end
end

--- 切换静态怪物
function M.ToggleStatic()
    GameState.staticMonsterEnabled = not GameState.staticMonsterEnabled
    if GameState.staticMonsterEnabled then
        M.Create(true)  -- 创建静态怪物
        print("Static monsters enabled")
    else
        M.ClearByType(true)
        print("Static monsters disabled")
    end
end

--- 清除所有怪物
function M.ClearAll()
    for _, monster in ipairs(GameState.monsters) do
        if monster.node then
            monster.node:Remove()
        end
    end
    GameState.monsters = {}
    GameState.monsterNodeMap = {}  -- 清理节点映射
end

--- 按类型清除怪物
function M.ClearByType(isStatic)
    local remaining = {}
    for _, monster in ipairs(GameState.monsters) do
        if monster.isStatic == isStatic then
            if monster.node then
                monster.node:Remove()
            end
        else
            table.insert(remaining, monster)
        end
    end
    GameState.monsters = remaining
end

--- 创建怪物
function M.Create(isStatic)
    local count = isStatic and CONFIG.StaticMonsterMaxCount or CONFIG.MonsterCount
    for i = 1, count do
        M.Spawn(isStatic)
    end
end

--- 获取当前静态怪物数量
function M.GetStaticMonsterCount()
    local count = 0
    for _, monster in ipairs(GameState.monsters) do
        if monster.isStatic and monster.alive then
            count = count + 1
        end
    end
    return count
end

--- 检查生成位置与怪物的碰撞
function M.CheckSpawnMonsterCollision(pos, radius)
    for _, monster in ipairs(GameState.monsters) do
        if monster.alive and monster.node then
            local monsterPos = monster.node.position
            local dx = pos.x - monsterPos.x
            local dz = pos.z - monsterPos.z
            local minDist = radius * 2
            if dx * dx + dz * dz < minDist * minDist then
                return true
            end
        end
    end
    return false
end

--- 在随机位置生成怪物（从空中掉落）
function M.Spawn(isStatic)
    local playerPos = GameState.playerNode.position
    local arenaHalf = CONFIG.ArenaSize / 2 - 2
    local minZ = 5
    local maxAttempts = 30
    local monsterRadius = CONFIG.MonsterSize
    local attempts = 0
    local spawnPos
    local validPosition = false
    
    -- 空中生成高度（从高处掉落，避免卡在障碍物里）
    local spawnHeight = 10.0
    
    -- 静态敌人只在外围6米范围内生成
    local edgeWidth = 6.0
    
    repeat
        if isStatic then
            -- 静态敌人：只在场景外围6米范围内（四边中选一边）
            local side = math.random(1, 4)
            local edgeMin = arenaHalf - edgeWidth  -- 外围区域的内边界
            
            if side == 1 then
                -- 北边（+Z）
                spawnPos = Vector3(
                    (math.random() * 2 - 1) * arenaHalf,
                    spawnHeight,
                    edgeMin + math.random() * edgeWidth
                )
            elseif side == 2 then
                -- 南边（-Z）
                spawnPos = Vector3(
                    (math.random() * 2 - 1) * arenaHalf,
                    spawnHeight,
                    -(edgeMin + math.random() * edgeWidth)
                )
            elseif side == 3 then
                -- 东边（+X）
                spawnPos = Vector3(
                    edgeMin + math.random() * edgeWidth,
                    spawnHeight,
                    (math.random() * 2 - 1) * arenaHalf
                )
            else
                -- 西边（-X）
                spawnPos = Vector3(
                    -(edgeMin + math.random() * edgeWidth),
                    spawnHeight,
                    (math.random() * 2 - 1) * arenaHalf
                )
            end
        else
            -- 动态敌人：整个场地范围
            spawnPos = Vector3(
                (math.random() * 2 - 1) * arenaHalf,
                spawnHeight,
                minZ + math.random() * (arenaHalf - minZ)
            )
        end
        attempts = attempts + 1
        
        -- 只检查水平距离
        local horizontalDist = Vector3(spawnPos.x - playerPos.x, 0, spawnPos.z - playerPos.z):Length()
        local distanceOk = horizontalDist >= CONFIG.MonsterSpawnRadius
        local monsterOk = not M.CheckSpawnMonsterCollision(spawnPos, monsterRadius)
        
        validPosition = distanceOk and monsterOk
    until validPosition or attempts >= maxAttempts
    
    M.CreateOne(spawnPos, #GameState.monsters + 1, isStatic)
end

--- 创建单个怪物
function M.CreateOne(position, index, isStatic)
    local monsterNode = GameState.scene:CreateChild("Monster" .. index)
    monsterNode.position = position
    monsterNode.scale = Vector3.ONE * MONSTER_MODEL.scale
    
    local bodyRadius = CONFIG.MonsterSize * 0.5
    local bodyHeight = CONFIG.MonsterHeight * 0.7
    local headRadius = CONFIG.MonsterSize * 0.35
    local headOffsetY = bodyHeight + headRadius * 0.8
    
    -- 添加刚体组件（所有怪物都使用动态物理，可以掉落和碰撞）
    local rigidBody = monsterNode:CreateComponent("RigidBody")
    rigidBody.mass = 50.0  -- 50kg，动态物理
    rigidBody.friction = 0.3
    rigidBody.restitution = 0.0
    rigidBody.angularFactor = Vector3.ZERO  -- 禁止旋转
    rigidBody.linearDamping = 0.1
    rigidBody.collisionLayer = GameState.COLLISION_LAYER.MONSTER  -- 怪物身体碰撞层
    rigidBody.collisionMask = GameState.COLLISION_MASK.MONSTER    -- 与环境、玩家、其他怪物碰撞
    rigidBody.collisionEventMode = COLLISION_ALWAYS  -- 始终发送碰撞事件
    
    -- 添加胶囊碰撞体（中心偏移，让底部在节点原点）
    local shape = monsterNode:CreateComponent("CollisionShape")
    shape:SetCapsule(bodyRadius * 2, CONFIG.MonsterHeight, Vector3(0, CONFIG.MonsterHeight / 2, 0))
    
    -- 注意：不再添加头部 CollisionShape，爆头检测通过碰撞点 Y 坐标判断
    -- 这样避免了多个 CollisionShape 可能导致的物理引擎问题
    local headNode = nil
    local headRigidBody = nil
    
    -- 使用 Scene:Instantiate 加载猪头人小兵 prefab
    local modelNode = GameState.scene:Instantiate(MONSTER_MODEL.prefab, Vector3.ZERO, Quaternion.IDENTITY)
    if modelNode then
        modelNode.name = "Model"
        modelNode:SetParent(monsterNode)
        modelNode.position = Vector3.ZERO
        modelNode.rotation = Quaternion.IDENTITY
    end
    
    -- 查找 AnimationController（可能在 modelNode 或其子节点上）
    local animCtrl = nil
    if modelNode then
        -- 先尝试在 modelNode 上查找
        animCtrl = modelNode:GetComponent("AnimationController")
        
        -- 如果没找到，尝试在第一个子节点上查找
        if not animCtrl then
            local firstChild = modelNode:GetChild(0)
            if firstChild then
                animCtrl = firstChild:GetComponent("AnimationController")
            end
        end
        
        -- 如果还没有，在有 AnimatedModel 的节点上创建
        if not animCtrl then
            local animModel = modelNode:GetComponent("AnimatedModel")
            if animModel then
                animCtrl = modelNode:CreateComponent("AnimationController")
            else
                local firstChild = modelNode:GetChild(0)
                if firstChild and firstChild:GetComponent("AnimatedModel") then
                    animCtrl = firstChild:CreateComponent("AnimationController")
                end
            end
        end
    end
    
    -- 播放待机动画
    if animCtrl then
        animCtrl:PlayExclusive(MONSTER_MODEL.animations.idle, 0, true, 0.2)
    end
    
    local monster = {
        node = monsterNode,
        modelNode = modelNode,
        animCtrl = animCtrl,
        rigidBody = rigidBody,
        headNode = headNode,           -- 头部碰撞体节点
        headRigidBody = headRigidBody, -- 头部刚体引用
        health = CONFIG.MonsterHealth,
        attackCooldown = 0,
        alive = true,
        isStatic = isStatic or false,
        bodyRadius = bodyRadius,
        bodyHeight = bodyHeight,
        headRadius = headRadius,
        headOffsetY = headOffsetY,
        radius = bodyRadius,
        height = CONFIG.MonsterHeight,
        -- AI 状态
        strafeDir = 0,
        strafeTimer = math.random() * 1.5,
        jumpCooldown = math.random() * 2,
        -- 动画状态
        currentAnim = "idle",
        isAttacking = false,
        -- 攻击前摇
        attackHitTimer = 0,      -- 攻击命中倒计时
        attackHitPending = false, -- 是否有待判定的攻击伤害
        -- 碰撞体可视化
        colliderNode = nil,      -- 身体碰撞体可视化节点
        headColliderNode = nil,  -- 头部碰撞体可视化节点
    }
    table.insert(GameState.monsters, monster)
    
    -- 注册怪物节点映射（用于碰撞回调查找怪物数据）
    GameState.monsterNodeMap = GameState.monsterNodeMap or {}
    GameState.monsterNodeMap[monsterNode] = monster
    
    -- 如果碰撞体显示模式已开启，为新怪物创建碰撞体可视化
    if GameState.showMonsterColliders then
        M.CreateColliderVisual(monster)
    end
end

--- 检测怪物是否在地面上（使用物理射线）
function M.IsGrounded(monster)
    if not GameState.physicsWorld or not monster.node then
        return false
    end
    
    local pos = monster.node.position
    local rayStart = Vector3(pos.x, pos.y + 0.1, pos.z)
    local rayDir = Vector3(0, -1, 0)
    local ray = Ray(rayStart, rayDir)
    
    local result = GameState.physicsWorld:RaycastSingle(ray, 0.3, 0xFFFFFFFF)
    
    if result.body and result.body ~= monster.rigidBody then
        return true
    end
    
    return false
end

--- 怪物开始攻击（设置前摇，不立即造成伤害）
function M.Attack(monster)
    if not monster.alive then return end
    monster.attackCooldown = CONFIG.MonsterAttackCooldown
    
    -- 设置攻击前摇计时器
    monster.attackHitTimer = MONSTER_MODEL.attackHitDelay
    monster.attackHitPending = true
end

--- 执行攻击伤害判定
function M.ApplyAttackDamage(monster)
    if not monster.alive then return end
    
    -- 检查玩家是否仍在攻击范围内
    local monsterPos = monster.node.position
    local playerPos = GameState.playerNode.position
    local toPlayer = playerPos - monsterPos
    toPlayer.y = 0
    local distance = toPlayer:Length()
    
    -- 只有玩家仍在攻击范围内才造成伤害
    if distance <= CONFIG.MonsterAttackRange * 1.2 then  -- 稍微放宽一点判定
        local Player = require "modules.Player"
        Player.TakeDamage(CONFIG.MonsterDamage)
    end
end

--- 怪物受伤
function M.Damage(monster, damage, isHeadshot, weaponId, hitDistance)
    if not monster.alive then return end
    
    local actualDamage = damage
    
    -- 霰弹枪距离衰减
    if weaponId == "shotgun" and hitDistance then
        local weapon = Config.WEAPONS.shotgun
        if hitDistance <= weapon.falloffStartRange then
            actualDamage = damage
        elseif hitDistance >= weapon.falloffEndRange then
            actualDamage = damage * weapon.minDamagePercent
        else
            local falloffProgress = (hitDistance - weapon.falloffStartRange) / 
                                    (weapon.falloffEndRange - weapon.falloffStartRange)
            actualDamage = damage * (1 - falloffProgress * (1 - weapon.minDamagePercent))
        end
    end
    
    -- 爆头处理
    if isHeadshot then
        -- 步枪和手枪爆头直接击杀
        if weaponId == "rifle" or weaponId == "pistol" then
            actualDamage = monster.health  -- 直接击杀
        else
            -- 霰弹枪爆头双倍伤害（近距离内直接击杀）
            if weaponId == "shotgun" and hitDistance then
                local weapon = Config.WEAPONS.shotgun
                if hitDistance <= weapon.headshotMaxRange then
                    actualDamage = monster.health  -- 近距离爆头直接击杀
                else
                    actualDamage = actualDamage * 2
                end
            else
                actualDamage = actualDamage * 2
            end
        end
        Audio.PlaySfx("headshot")
    else
        Audio.PlaySfx("hit_enemy")
    end
    
    monster.health = monster.health - math.floor(actualDamage)
    
    if monster.health <= 0 then
        M.Kill(monster)
    end
end

--- 击杀怪物
function M.Kill(monster)
    if not monster.alive then return end
    
    monster.alive = false
    monster.dying = true
    monster.deathTime = 0
    monster.deathStartScale = monster.node.scale
    monster.deathStartPos = monster.node.position
    
    -- 禁用物理
    if monster.rigidBody then
        monster.rigidBody.mass = 0
        monster.rigidBody.linearVelocity = Vector3.ZERO
        monster.rigidBody.collisionMask = 0  -- 禁用碰撞
    end
    
    -- 禁用头部碰撞
    if monster.headRigidBody then
        monster.headRigidBody.collisionMask = 0
    end
    
    -- 移除碰撞体可视化
    M.RemoveColliderVisual(monster)
    
    Audio.PlaySfx("kill_enemy")
    GameState.score = GameState.score + CONFIG.MonsterKillScore
    UI.ShowScorePopup(CONFIG.MonsterKillScore)
end

--- 完成怪物死亡
function M.FinishDeath(monster)
    -- 清理节点映射
    if GameState.monsterNodeMap then
        if monster.node then
            GameState.monsterNodeMap[monster.node] = nil
        end
    end
    
    if monster.node then
        monster.node:Remove()
        monster.node = nil
    end
    
    -- 从列表移除
    for i, m in ipairs(GameState.monsters) do
        if m == monster then
            table.remove(GameState.monsters, i)
            break
        end
    end
    
    -- 重生怪物
    if monster.isStatic and GameState.staticMonsterEnabled then
        -- 静态怪物达到上限后不再重生
        if M.GetStaticMonsterCount() < CONFIG.StaticMonsterMaxCount then
            M.Spawn(true)
        end
    elseif not monster.isStatic and GameState.dynamicMonsterEnabled then
        M.Spawn(false)
    end
end

--- 更新死亡动画
function M.UpdateDeathAnimation(monster, dt)
    monster.deathTime = monster.deathTime + dt
    local progress = monster.deathTime / CONFIG.MonsterDeathDuration
    
    if progress >= 1.0 then
        monster.dying = false
        return
    end
    
    local easedProgress = 1 - (1 - progress) * (1 - progress)
    
    local startScale = monster.deathStartScale
    local targetScale = startScale * CONFIG.MonsterDeathShrink
    local currentScale = startScale + (targetScale - startScale) * easedProgress
    monster.node.scale = currentScale
    
    local startPos = monster.deathStartPos
    local sinkAmount = CONFIG.MonsterDeathSink * easedProgress
    monster.node.position = Vector3(startPos.x, startPos.y - sinkAmount, startPos.z)
    
    local rotationAmount = CONFIG.MonsterDeathRotation * easedProgress
    monster.node.rotation = Quaternion(rotationAmount, Vector3.UP)
end

--- 切换怪物动画
function M.PlayAnimation(monster, animName, loop)
    if not monster.animCtrl then return end
    if monster.currentAnim == animName then return end
    
    local animUri = MONSTER_MODEL.animations[animName]
    if animUri then
        monster.animCtrl:PlayExclusive(animUri, 0, loop ~= false, 0.2)
        monster.currentAnim = animName
    end
end

--- 更新单个怪物AI（使用物理移动）
function M.UpdateAI(monster, playerPos, dt)
    if not monster.rigidBody then return end
    
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    
    local monsterPos = monster.node.position
    local toPlayer = playerPos - monsterPos
    toPlayer.y = 0
    local distance = toPlayer:Length()
    
    -- 面向玩家
    if distance > 0.1 then
        local lookDir = toPlayer:Normalized()
        monster.node.rotation = Quaternion(Vector3.FORWARD, lookDir)
    end
    
    -- 静态怪物只看向玩家，不移动，播放待机动画
    if monster.isStatic then
        M.PlayAnimation(monster, "idle", true)
        return
    end
    
    -- 更新攻击冷却（受游戏速度影响）
    if monster.attackCooldown > 0 then
        monster.attackCooldown = monster.attackCooldown - dt * gameSpeed
    end
    
    -- 更新攻击前摇计时器（受游戏速度影响）
    if monster.attackHitPending then
        monster.attackHitTimer = monster.attackHitTimer - dt * gameSpeed
        if monster.attackHitTimer <= 0 then
            -- 前摇结束，执行伤害判定
            M.ApplyAttackDamage(monster)
            monster.attackHitPending = false
        end
    end
    
    -- 检查攻击动画是否结束
    if monster.isAttacking then
        if monster.animCtrl and not monster.animCtrl:IsPlaying(MONSTER_MODEL.animations.attack) then
            monster.isAttacking = false
            monster.attackHitPending = false  -- 动画结束时取消未判定的伤害
        else
            -- 攻击动画播放中，停止移动
            monster.rigidBody.linearVelocity = Vector3(0, monster.rigidBody.linearVelocity.y, 0)
            return
        end
    end
    
    -- 攻击检测
    if distance <= CONFIG.MonsterAttackRange then
        if monster.attackCooldown <= 0 then
            M.Attack(monster)
            -- 播放攻击动画
            M.PlayAnimation(monster, "attack", false)
            monster.isAttacking = true
        else
            -- 等待攻击冷却，播放待机动画
            M.PlayAnimation(monster, "idle", true)
        end
        -- 在攻击范围内停止移动
        monster.rigidBody.linearVelocity = Vector3(0, monster.rigidBody.linearVelocity.y, 0)
        return
    end
    
    -- 跳跃逻辑（冷却受游戏速度影响，但跳跃冲量不受影响）
    monster.jumpCooldown = monster.jumpCooldown - dt * gameSpeed
    if monster.jumpCooldown <= 0 and M.IsGrounded(monster) then
        if math.random() < CONFIG.MonsterJumpChance then
            local velocity = monster.rigidBody.linearVelocity
            -- 跳跃是瞬间冲量，不受 gameSpeed 影响
            monster.rigidBody.linearVelocity = Vector3(velocity.x, CONFIG.MonsterJumpForce, velocity.z)
        end
        monster.jumpCooldown = CONFIG.MonsterJumpCooldown + math.random() * 1.0
    end
    
    -- 随机横移（受游戏速度影响）
    monster.strafeTimer = monster.strafeTimer - dt * gameSpeed
    if monster.strafeTimer <= 0 then
        local rand = math.random()
        if rand < 0.3 then
            monster.strafeDir = -1
        elseif rand < 0.6 then
            monster.strafeDir = 1
        else
            monster.strafeDir = 0
        end
        monster.strafeTimer = CONFIG.MonsterStrafeInterval + math.random() * 0.5
    end
    
    -- 计算移动方向
    local forwardDir = toPlayer:Normalized()
    local strafeVec = Vector3(forwardDir.z, 0, -forwardDir.x) * monster.strafeDir
    local moveDir = (forwardDir + strafeVec * (CONFIG.MonsterStrafeSpeed / CONFIG.MonsterSpeed)):Normalized()
    
    -- 使用物理速度移动（受游戏速度影响）
    local currentVel = monster.rigidBody.linearVelocity
    local targetVelX = moveDir.x * CONFIG.MonsterSpeed * gameSpeed
    local targetVelZ = moveDir.z * CONFIG.MonsterSpeed * gameSpeed
    
    -- 平滑加速（加速度受游戏速度影响）
    local accel = 20.0 * gameSpeed
    local newVelX = currentVel.x + (targetVelX - currentVel.x) * math.min(1.0, accel * dt)
    local newVelZ = currentVel.z + (targetVelZ - currentVel.z) * math.min(1.0, accel * dt)
    
    monster.rigidBody.linearVelocity = Vector3(newVelX, currentVel.y, newVelZ)
    
    -- 播放移动动画
    M.PlayAnimation(monster, "move", true)
end

--- 更新所有怪物
function M.Update(dt)
    local playerPos = GameState.playerNode.position
    local toFinishDeath = {}
    
    for _, monster in ipairs(GameState.monsters) do
        if monster.alive then
            if not GameState.isDead then
                M.UpdateAI(monster, playerPos, dt)
            end
        elseif monster.dying then
            M.UpdateDeathAnimation(monster, dt)
            if not monster.dying then
                table.insert(toFinishDeath, monster)
            end
        end
    end
    
    for _, monster in ipairs(toFinishDeath) do
        M.FinishDeath(monster)
    end
end

-- ============================================================================
-- 碰撞体可视化（调试功能）
-- ============================================================================

-- 常见的头部骨骼节点名称列表
local HEAD_BONE_NAMES = {
    "Head", "head", "HEAD",
    "Bip001 Head", "Bip01 Head",
    "mixamorig:Head", "mixamorig_Head",
    "Head_M", "head_M",
    "Bone_Head", "bone_head",
    "Skeleton:Head",
}

--- 创建半透明材质
local function CreateColliderMaterial(color)
    local material = Material:new()
    local tech = cache:GetResource("Technique", "Techniques/NoTextureUnlitAlpha.xml")
    material:SetTechnique(0, tech)
    material:SetShaderParameter("MatDiffColor", Variant(color or Color(0, 1, 0, 0.3)))
    return material
end

--- 递归查找子节点（按名称）
local function FindChildRecursive(node, name)
    if not node then return nil end
    
    -- 先检查直接子节点
    local child = node:GetChild(name, false)
    if child then return child end
    
    -- 递归搜索所有子节点
    local numChildren = node:GetNumChildren(false)
    for i = 0, numChildren - 1 do
        local childNode = node:GetChild(i)
        local found = FindChildRecursive(childNode, name)
        if found then return found end
    end
    
    return nil
end

--- 查找头部骨骼节点
local function FindHeadBone(modelNode)
    if not modelNode then return nil end
    
    for _, boneName in ipairs(HEAD_BONE_NAMES) do
        local bone = FindChildRecursive(modelNode, boneName)
        if bone then
            print("Found head bone: " .. boneName)
            return bone
        end
    end
    
    return nil
end

--- 为单个怪物创建碰撞体可视化模型
function M.CreateColliderVisual(monster)
    if not monster.node or monster.colliderNode then return end
    
    -- 胶囊体参数（与 CollisionShape 一致）
    local diameter = CONFIG.MonsterSize  -- bodyRadius * 2
    local height = CONFIG.MonsterHeight
    local radius = diameter / 2
    
    -- 胶囊体 = 圆柱体（中间部分）+ 上下两个半球
    -- 圆柱体高度 = 总高度 - 直径（两个半球的高度）
    local cylinderHeight = height - diameter
    
    -- 创建碰撞体可视化的父节点
    local colliderNode = monster.node:CreateChild("ColliderVisual")
    colliderNode.position = Vector3(0, height / 2, 0)  -- 与碰撞体偏移一致
    monster.colliderNode = colliderNode
    
    local bodyMaterial = CreateColliderMaterial(Color(0, 1, 0, 0.3))  -- 绿色-身体
    local headMaterial = CreateColliderMaterial(Color(1, 0, 0, 0.4))  -- 红色-头部
    
    -- 中间圆柱体
    local cylinderNode = colliderNode:CreateChild("Cylinder")
    local cylinderModel = cylinderNode:CreateComponent("StaticModel")
    cylinderModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    cylinderModel:SetMaterial(bodyMaterial)
    -- Cylinder.mdl 默认高度 1，直径 1，需要缩放
    cylinderNode.scale = Vector3(diameter, cylinderHeight, diameter)
    
    -- 下半球（身体底部）
    local bottomSphereNode = colliderNode:CreateChild("BottomSphere")
    bottomSphereNode.position = Vector3(0, -cylinderHeight / 2, 0)
    local bottomSphereModel = bottomSphereNode:CreateComponent("StaticModel")
    bottomSphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    bottomSphereModel:SetMaterial(bodyMaterial)
    bottomSphereNode.scale = Vector3(diameter, diameter, diameter)
    
    -- 上半球（身体顶部，不是头部）
    local topSphereNode = colliderNode:CreateChild("TopSphere")
    topSphereNode.position = Vector3(0, cylinderHeight / 2, 0)
    local topSphereModel = topSphereNode:CreateComponent("StaticModel")
    topSphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    topSphereModel:SetMaterial(bodyMaterial)
    topSphereNode.scale = Vector3(diameter, diameter, diameter)
    
    -- ========== 头部碰撞体可视化（红色球体）==========
    local headRadius = monster.headRadius
    local headDiameter = headRadius * 2
    
    -- 尝试查找头部骨骼节点
    local headBone = FindHeadBone(monster.modelNode)
    
    if headBone then
        -- 绑定到头部骨骼节点
        local headColliderNode = headBone:CreateChild("HeadColliderVisual")
        headColliderNode.position = Vector3.ZERO  -- 骨骼位置即头部位置
        monster.headColliderNode = headColliderNode
        
        local headSphereModel = headColliderNode:CreateComponent("StaticModel")
        headSphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        headSphereModel:SetMaterial(headMaterial)
        -- 由于绑定到骨骼，需要考虑模型缩放（MONSTER_MODEL.scale = 1.0）
        headColliderNode.scale = Vector3(headDiameter, headDiameter, headDiameter)
        
        print("Head collider bound to bone")
    else
        -- 回退：使用固定偏移
        local headColliderNode = monster.node:CreateChild("HeadColliderVisual")
        headColliderNode.position = Vector3(0, monster.headOffsetY, 0)
        monster.headColliderNode = headColliderNode
        
        local headSphereModel = headColliderNode:CreateComponent("StaticModel")
        headSphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        headSphereModel:SetMaterial(headMaterial)
        headColliderNode.scale = Vector3(headDiameter, headDiameter, headDiameter)
        
        print("Head collider using fixed offset (no bone found)")
    end
end

--- 移除单个怪物的碰撞体可视化模型
function M.RemoveColliderVisual(monster)
    if monster.colliderNode then
        monster.colliderNode:Remove()
        monster.colliderNode = nil
    end
    if monster.headColliderNode then
        monster.headColliderNode:Remove()
        monster.headColliderNode = nil
    end
end

--- 切换碰撞体显示
function M.ToggleColliderDisplay()
    GameState.showMonsterColliders = not GameState.showMonsterColliders
    
    if GameState.showMonsterColliders then
        -- 显示所有怪物的碰撞体
        for _, monster in ipairs(GameState.monsters) do
            if monster.alive and monster.node then
                M.CreateColliderVisual(monster)
            end
        end
        print("Monster colliders: VISIBLE")
    else
        -- 隐藏所有怪物的碰撞体
        for _, monster in ipairs(GameState.monsters) do
            M.RemoveColliderVisual(monster)
        end
        print("Monster colliders: HIDDEN")
    end
end

return M
