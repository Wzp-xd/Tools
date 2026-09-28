-- ============================================================================
-- Bullet.lua - 子弹系统（使用引擎物理碰撞）
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Physics = require "modules.Physics"
local HitEffects = require "modules.HitEffects"
local Audio = require "modules.Audio"
local Weapon = require "modules.Weapon"
local Target = require "modules.Target"
local Monster = require "modules.Monster"

-- 延迟加载 Player 模块，避免循环依赖
---@type table
local Player = nil
local function GetPlayer()
    if not Player then
        Player = require "modules.Player"
    end
    return Player
end

local M = {}

local CONFIG = Config.CONFIG
local CASING_CONFIG = Config.CASING_CONFIG

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 基于方向向量构建本地坐标系（右向量和上向量）
--- 用于在任意方向上正确应用散布，避免方向接近坐标轴时散布失效
---@param direction Vector3 方向向量（已归一化）
---@return Vector3 localRight 本地右向量
---@return Vector3 localUp 本地上向量
function M.GetLocalAxes(direction)
    -- 选择一个不与 direction 平行的参考向量
    local refUp = Vector3.UP
    -- 如果 direction 接近垂直（与 UP 平行），使用 FORWARD 作为参考
    if math.abs(direction.y) > 0.99 then
        refUp = Vector3.FORWARD
    end
    
    -- 计算本地右向量（direction × refUp）
    local localRight = direction:CrossProduct(refUp):Normalized()
    -- 计算本地上向量（localRight × direction）
    local localUp = localRight:CrossProduct(direction):Normalized()
    
    return localRight, localUp
end

-- ============================================================================
-- 子弹物理碰撞处理
-- ============================================================================

--- 处理子弹碰撞事件（由 main.lua 的碰撞回调调用）
---@param bulletNode Node 子弹节点
---@param otherNode Node 被击中的节点
---@param contactPosition Vector3 碰撞点位置
---@param contactNormal Vector3|nil 碰撞表面法线（可选）
function M.HandleBulletCollision(bulletNode, otherNode, contactPosition, contactNormal)
    -- 获取子弹数据
    local bullet = GameState.bulletDataMap[bulletNode]
    if not bullet then return end
    if bullet.hasHit then return end  -- 已经处理过碰撞
    
    bullet.hasHit = true
    
    -- 使用实际速度方向（而非创建时保存的方向）
    -- 高速子弹在物理模拟中可能因 CCD 修正导致方向偏差
    if bullet.rigidBody then
        local velocity = bullet.rigidBody.linearVelocity
        local speed = velocity:Length()
        if speed > 0.1 then
            bullet.direction = velocity / speed  -- 归一化
        end
    end
    
    -- 判断击中类型
    local hitType = "environment"
    local monster = nil
    local isHeadshot = false
    
    -- 检查是否击中靶子（优先检测）
    if GameState.targetNodeMap then
        local target = GameState.targetNodeMap[otherNode]
        if target then
            -- 击中靶子
            if Target.HandleCollision(otherNode, contactPosition) then
                HitEffects.CreateHitEffect(contactPosition, bullet.direction)
                M.RemoveBullet(bullet)
                return
            else
                -- 靶子已经倒下，子弹穿过，不产生任何效果
                M.RemoveBullet(bullet)
                return
            end
        end
    end
    
    -- 检查是否击中怪物（通过节点映射查找）
    if GameState.monsterNodeMap then
        monster = GameState.monsterNodeMap[otherNode]
        if monster and monster.alive then
            hitType = "monster_body"
            
            -- 通过碰撞点位置判断是否爆头
            -- 如果碰撞点的 Y 坐标高于头部下边缘，则为爆头
            local monsterPos = monster.node.position
            local headBottomY = monsterPos.y + monster.headOffsetY - monster.headRadius
            
            if contactPosition.y >= headBottomY then
                isHeadshot = true
                hitType = "monster_head"
            end
        end
    end
    
    -- 计算击中距离（用于霰弹枪伤害衰减）
    local hitDistance = 0
    if bullet.startPosition then
        hitDistance = (contactPosition - bullet.startPosition):Length()
    end
    
    -- 处理击中效果
    if hitType == "monster_head" or hitType == "monster_body" then
        if monster and monster.alive then
            -- 创建击中特效
            HitEffects.CreateHitEffect(contactPosition, bullet.direction)
            
            -- 造成伤害
            Monster.Damage(monster, bullet.damage, isHeadshot, bullet.weaponId, hitDistance)
        end
    elseif hitType == "environment" then
        -- 击中环境（墙壁等）
        HitEffects.CreateWallHitEffect(contactPosition, bullet.direction, contactNormal)
        
        -- 测试模式：子弹击中障碍物后不立即消失，30秒后消失
        if CONFIG.DebugTestMode then
            -- 停止子弹运动
            if bullet.rigidBody then
                bullet.rigidBody.linearVelocity = Vector3.ZERO
                bullet.rigidBody.useGravity = false
            end
            -- 设置延迟删除时间
            bullet.hitTime = bullet.lifetime
            bullet.delayedRemoval = true
            bullet.delayedRemovalTime = CONFIG.DebugBulletHitLifetime or 30.0
            return  -- 不立即移除
        end
    end
    
    -- 移除子弹（非测试模式或击中怪物/靶子）
    M.RemoveBullet(bullet)
end

--- 移除子弹
function M.RemoveBullet(bullet)
    if bullet.node then
        -- 从映射表移除
        GameState.bulletDataMap[bullet.node] = nil
        -- 移除节点
        bullet.node:Remove()
        bullet.node = nil
    end
    bullet.removed = true
end

--- 清除所有子弹和弹壳
function M.ClearAll()
    -- 清除子弹
    for _, bullet in ipairs(GameState.bullets) do
        if bullet.node then
            bullet.node:Remove()
        end
    end
    GameState.bullets = {}
    GameState.bulletDataMap = {}
    
    -- 清除弹壳
    for _, casing in ipairs(GameState.casings) do
        if casing.node then
            casing.node:Remove()
        end
    end
    GameState.casings = {}
end

-- ============================================================================
-- 射击逻辑
-- ============================================================================

--- 射击
function M.Fire()
    -- 只有在游戏进行中才能射击
    if GameState.gamePhase ~= GameState.GAME_PHASE.PLAYING then return end
    
    if not GameState.currentWeapon then return end
    if GameState.fireCooldown > 0 then return end
    if GameState.isReloading then return end
    if GameState.isSwitchingWeapon then return end  -- 切换武器时不能射击
    
    if GameState.currentAmmo <= 0 then
        Audio.PlaySfx("empty_clip")
        Weapon.StartReload()
        return
    end
    
    local w = GameState.currentWeapon
    
    GameState.fireCooldown = w.fireRate
    GameState.currentAmmo = GameState.currentAmmo - 1
    GameState.totalShots = GameState.totalShots + 1
    
    Audio.PlayGunshotSound(GameState.currentWeaponId)
    
    -- 优先使用角色手持武器的枪口位置（第三人称）
    local muzzleWorldPos
    local playerMuzzle = GetPlayer().GetWeaponMuzzleNode()
    if playerMuzzle then
        muzzleWorldPos = playerMuzzle.worldPosition
    elseif GameState.muzzleNode then
        -- 回退到第一人称视角的枪口（兼容）
        muzzleWorldPos = GameState.muzzleNode.worldPosition
    else
        -- 如果都没有，使用相机位置
        muzzleWorldPos = GameState.cameraNode.worldPosition
    end
    
    -- 从屏幕中心发射射线获取瞄准目标点
    local screenCenter = Vector2(0.5, 0.5)
    local cameraRay = GameState.camera:GetScreenRay(screenCenter.x, screenCenter.y)
    local targetPoint = cameraRay.origin + cameraRay.direction * CONFIG.MaxShootDistance
    
    -- 使用物理射线检测获取更精确的目标点
    if GameState.physicsWorld then
        local result = GameState.physicsWorld:RaycastSingle(cameraRay, CONFIG.MaxShootDistance, 0xFFFFFFFF)
        if result.body then
            targetPoint = result.position
        end
    end
    
    local baseDirection = (targetPoint - muzzleWorldPos):Normalized()
    
    -- 递增连续射击计数，判断本枪是否为零散布
    GameState.burstShotCount = GameState.burstShotCount + 1
    local isZeroSpreadShot = false
    if w.zeroSpreadInterval and w.zeroSpreadInterval > 0 then
        -- 第1枪 (count=1)、第5枪 (count=5)、第9枪… 散布为0
        isZeroSpreadShot = ((GameState.burstShotCount - 1) % w.zeroSpreadInterval == 0)
    end
    
    for i = 1, w.bulletsPerShot do
        local direction = baseDirection
        
        -- 零散布枪跳过所有散布计算
        if not isZeroSpreadShot then
            -- 准心扩散
            if GameState.crosshairSpread > 0 then
                local spreadAngleDeg = GameState.crosshairSpread * 0.05
                local spreadRad = math.rad(spreadAngleDeg)
                local randomAngle = math.random() * math.pi * 2
                local randomRadius = math.random() * spreadRad
                local offsetYaw = math.cos(randomAngle) * randomRadius
                local offsetPitch = math.sin(randomAngle) * randomRadius
                
                -- 基于子弹方向构建本地坐标系，避免方向接近坐标轴时散布失效
                local localRight, localUp = M.GetLocalAxes(direction)
                local spreadRotation = Quaternion(math.deg(offsetPitch), localRight) * 
                                       Quaternion(math.deg(offsetYaw), localUp)
                direction = spreadRotation * direction
            end
            
            -- 武器固有散布（霰弹枪）
            if w.spreadAngle > 0 then
                local spreadRad = math.rad(w.spreadAngle)
                local randomYaw = (math.random() - 0.5) * 2 * spreadRad
                local randomPitch = (math.random() - 0.5) * 2 * spreadRad
                
                -- 基于子弹方向构建本地坐标系
                local localRight, localUp = M.GetLocalAxes(direction)
                local spreadRotation = Quaternion(math.deg(randomPitch), localRight) * 
                                       Quaternion(math.deg(randomYaw), localUp)
                direction = spreadRotation * direction
            end
        end
        
        -- 根据碰撞检测模式创建子弹
        if CONFIG.BulletCollisionMode == Config.BULLET_COLLISION_MODE.RAYCAST then
            -- 射线检测模式：立即判定命中，子弹仅作为视觉效果
            M.FireRaycastBullet(muzzleWorldPos, direction, w)
        else
            -- 物理碰撞模式（默认）
            M.CreateBullet(muzzleWorldPos, direction, w)
        end
    end
    
    GameState.gunRecoilTime = 0.1
    Weapon.TriggerRecoil()
    M.CreateMuzzleFlash()
    M.CreateEjectedCasing()  -- 抛出弹壳
    GetPlayer().TriggerShootAnimation()  -- 触发射击动画
    
    -- 射击后检查弹药，如果为0自动换弹
    if GameState.currentAmmo <= 0 and GameState.reserveAmmo > 0 then
        Weapon.StartReload()
    end
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 创建子弹拖尾材质
local function CreateTrailMaterial()
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.7, 0.2, 0.8)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(1.0))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.0, 0.3)))
    return mat
end

-- ============================================================================
-- 射线检测模式
-- ============================================================================

--- 射线检测模式：射击瞬间判定命中，子弹飞到目标时才触发效果
---@param muzzlePos Vector3 枪口位置
---@param direction Vector3 射击方向
---@param weapon table 武器配置
function M.FireRaycastBullet(muzzlePos, direction, weapon)
    -- 每帧检测模式：不预先确定命中，子弹实时检测碰撞
    local maxDistance = CONFIG.MaxShootDistance
    
    -- 创建视觉子弹，每帧进行射线检测
    M.CreateVisualBullet(muzzlePos, direction, weapon, maxDistance)
end

--- 处理射线检测模式子弹到达目标时的击中效果
---@param bullet table 子弹数据
---@return boolean shouldContinue 是否需要继续飞行（目标已失效）
function M.ProcessRaycastHit(bullet)
    local hitPos = bullet.targetPosition
    local hitNormal = bullet.hitNormal
    local hitNode = bullet.hitNode
    local direction = bullet.direction
    local hitDistance = bullet.targetDistance
    
    local hitType = nil
    
    -- 处理击中效果
    if hitNode then
        -- 检查是否击中靶子
        if GameState.targetNodeMap then
            local target = GameState.targetNodeMap[hitNode]
            if target then
                if Target.HandleCollision(hitNode, hitPos) then
                    HitEffects.CreateHitEffect(hitPos, direction)
                    hitType = "target"
                else
                    -- 靶子已经倒下，需要继续飞行
                    return true
                end
            end
        end
        
        -- 检查是否击中怪物
        if not hitType and GameState.monsterNodeMap then
            local monster = GameState.monsterNodeMap[hitNode]
            if monster then
                -- 确实是怪物节点
                if monster.alive then
                    hitType = "monster_body"
                    local isHeadshot = false
                    
                    -- 通过碰撞点位置判断是否爆头
                    local monsterPos = monster.node.position
                    local headBottomY = monsterPos.y + monster.headOffsetY - monster.headRadius
                    
                    if hitPos.y >= headBottomY then
                        isHeadshot = true
                        hitType = "monster_head"
                    end
                    
                    -- 创建击中特效
                    HitEffects.CreateHitEffect(hitPos, direction)
                    
                    -- 造成伤害
                    Monster.Damage(monster, bullet.damage, isHeadshot, bullet.weaponId, hitDistance)
                else
                    -- 怪物已经死亡，需要继续飞行
                    return true
                end
            end
            -- 如果 monster 是 nil，说明不是怪物节点，继续检查环境
        end
        
        -- 击中环境
        if not hitType then
            hitType = "environment"
            HitEffects.CreateWallHitEffect(hitPos, direction, hitNormal)
        end
    end
    
    return false
end

--- 创建纯视觉子弹（无物理组件，用于射线检测模式）
---@param muzzlePos Vector3 枪口位置
---@param direction Vector3 射击方向
---@param weapon table 武器配置
---@param maxDistance number 最大飞行距离
function M.CreateVisualBullet(muzzlePos, direction, weapon, maxDistance)
    local bulletNode = GameState.scene:CreateChild("VisualBullet")
    bulletNode.position = muzzlePos
    
    local radius = weapon.bulletRadius
    bulletNode.scale = Vector3(radius * 2, radius * 2, radius * 2)
    
    -- 添加视觉模型
    local model = bulletNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.8))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.0, 0.0)))
    model:SetMaterial(mat)
    
    -- 添加拖尾效果
    local parentScale = radius * 2
    
    -- 第一层拖尾
    local trailNode = bulletNode:CreateChild("Trail")
    local trailLength = 0.8
    local trailRadius = radius * 0.6
    local localTrailLength = trailLength / parentScale
    local localTrailRadius = trailRadius / parentScale
    
    trailNode.position = Vector3(0, 0, -0.5 - localTrailLength / 2)
    trailNode.scale = Vector3(localTrailRadius * 2, localTrailLength, localTrailRadius * 2)
    trailNode.rotation = Quaternion(90, Vector3.RIGHT)
    
    local trailModel = trailNode:CreateComponent("StaticModel")
    trailModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    trailModel:SetMaterial(CreateTrailMaterial())
    
    -- 第二层拖尾
    local trail2Node = bulletNode:CreateChild("Trail2")
    local trail2Length = 1.5
    local trail2Radius = radius * 0.3
    local localTrail2Length = trail2Length / parentScale
    local localTrail2Radius = trail2Radius / parentScale
    local trail1End = -0.5 - localTrailLength
    
    trail2Node.position = Vector3(0, 0, trail1End - localTrail2Length / 2)
    trail2Node.scale = Vector3(localTrail2Radius * 2, localTrail2Length, localTrail2Radius * 2)
    trail2Node.rotation = Quaternion(90, Vector3.RIGHT)
    
    local trail2Model = trail2Node:CreateComponent("StaticModel")
    trail2Model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local trail2Mat = Material:new()
    trail2Mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    trail2Mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, 0.5)))
    trail2Mat:SetShaderParameter("Metallic", Variant(0.0))
    trail2Mat:SetShaderParameter("Roughness", Variant(1.0))
    trail2Mat:SetShaderParameter("MatEmissiveColor", Variant(Color(2.0, 1.0, 0.1)))
    trail2Model:SetMaterial(trail2Mat)
    
    -- 让子弹朝向飞行方向
    bulletNode.rotation = Quaternion(Vector3.FORWARD, direction)
    
    -- 计算最大飞行时间
    local maxFlightTime = maxDistance / weapon.bulletSpeed
    
    -- 子弹数据（每帧射线检测模式）
    local bullet = {
        node = bulletNode,
        rigidBody = nil,  -- 无物理组件
        direction = direction,
        speed = weapon.bulletSpeed,
        startPosition = muzzlePos,
        prevPosition = muzzlePos,  -- 上一帧位置，用于每帧检测
        maxDistance = maxDistance,
        traveledDistance = 0,  -- 已飞行距离
        lifetime = 0,
        gameLifetime = 0,
        maxLifetime = maxFlightTime,
        damage = weapon.damage,
        weaponId = GameState.currentWeaponId,
        hasHit = false,
        removed = false,
        isRaycastBullet = true,  -- 标记为射线检测模式子弹
    }
    
    table.insert(GameState.bullets, bullet)
end

-- ============================================================================
-- 物理碰撞模式
-- ============================================================================

--- 创建子弹（使用物理系统）
function M.CreateBullet(muzzlePos, direction, weapon)
    local bulletNode = GameState.scene:CreateChild("Bullet")
    bulletNode.position = muzzlePos
    
    local radius = weapon.bulletRadius
    bulletNode.scale = Vector3(radius * 2, radius * 2, radius * 2)
    
    -- 添加视觉模型
    local model = bulletNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.8))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.0, 0.0)))
    model:SetMaterial(mat)
    
    -- ========== 添加拖尾效果 ==========
    -- 父节点缩放是 radius * 2，所有本地坐标需要除以这个值来得到正确的世界尺寸
    -- 球体模型直径 1 米，在本地坐标系中球体后缘在 z = -0.5
    local parentScale = radius * 2
    
    -- 第一层拖尾（紧贴球体后方）
    local trailNode = bulletNode:CreateChild("Trail")
    local trailLength = 0.8  -- 拖尾世界长度（米）
    local trailRadius = radius * 0.6  -- 拖尾半径（比子弹小）
    
    -- 转换为本地单位
    local localTrailLength = trailLength / parentScale
    local localTrailRadius = trailRadius / parentScale
    
    -- 拖尾中心位置：球体后缘(-0.5) - 拖尾半长
    trailNode.position = Vector3(0, 0, -0.5 - localTrailLength / 2)
    -- 圆柱体默认直径1高度1，缩放使其达到目标尺寸
    trailNode.scale = Vector3(localTrailRadius * 2, localTrailLength, localTrailRadius * 2)
    trailNode.rotation = Quaternion(90, Vector3.RIGHT)  -- 圆柱体旋转使其沿Z轴
    
    local trailModel = trailNode:CreateComponent("StaticModel")
    trailModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    trailModel:SetMaterial(CreateTrailMaterial())
    
    -- 第二层拖尾（接在第一层后面，更长更淡）
    local trail2Node = bulletNode:CreateChild("Trail2")
    local trail2Length = 1.5  -- 第二层拖尾世界长度（米）
    local trail2Radius = radius * 0.3
    
    local localTrail2Length = trail2Length / parentScale
    local localTrail2Radius = trail2Radius / parentScale
    
    -- 第二层拖尾中心位置：第一层拖尾末端 - 第二层拖尾半长
    local trail1End = -0.5 - localTrailLength  -- 第一层拖尾末端
    trail2Node.position = Vector3(0, 0, trail1End - localTrail2Length / 2)
    trail2Node.scale = Vector3(localTrail2Radius * 2, localTrail2Length, localTrail2Radius * 2)
    trail2Node.rotation = Quaternion(90, Vector3.RIGHT)
    
    local trail2Model = trail2Node:CreateComponent("StaticModel")
    trail2Model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local trail2Mat = Material:new()
    trail2Mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    trail2Mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, 0.5)))
    trail2Mat:SetShaderParameter("Metallic", Variant(0.0))
    trail2Mat:SetShaderParameter("Roughness", Variant(1.0))
    trail2Mat:SetShaderParameter("MatEmissiveColor", Variant(Color(2.0, 1.0, 0.1)))
    trail2Model:SetMaterial(trail2Mat)
    
    -- 让子弹朝向飞行方向
    bulletNode.rotation = Quaternion(Vector3.FORWARD, direction)
    
    -- ========== 添加物理组件 ==========
    local rigidBody = bulletNode:CreateComponent("RigidBody")
    rigidBody.mass = 0.1  -- 子弹质量（稍大一些更稳定）
    rigidBody.friction = 0.0
    rigidBody.restitution = 0.0
    rigidBody.linearDamping = 0.0
    rigidBody.angularDamping = 0.0
    rigidBody.useGravity = false  -- 子弹不受重力影响
    
    -- 碰撞层设置
    rigidBody.collisionLayer = GameState.COLLISION_LAYER.BULLET
    rigidBody.collisionMask = GameState.COLLISION_MASK.BULLET
    rigidBody.collisionEventMode = COLLISION_ALWAYS  -- 始终发送碰撞事件
    
    -- CCD（连续碰撞检测）- 防止高速子弹穿透
    -- 使用更大的 CCD 半径和更小的阈值来确保检测
    local collisionRadius = math.max(radius, 0.05)  -- 碰撞半径至少 0.05 米
    rigidBody.ccdRadius = collisionRadius
    rigidBody.ccdMotionThreshold = 0.01  -- 非常小的阈值，几乎总是启用 CCD
    
    -- 添加球形碰撞体（使用更大的碰撞半径）
    local shape = bulletNode:CreateComponent("CollisionShape")
    shape:SetSphere(collisionRadius * 2)  -- 参数是直径
    
    -- 调试：显示碰撞盒
    if CONFIG.DebugShowBulletCollider then
        local debugNode = bulletNode:CreateChild("DebugCollider")
        -- 碰撞体直径是 collisionRadius * 2
        -- 父节点缩放是 radius * 2（已在上方定义为 parentScale）
        -- 目标世界尺寸 = collisionRadius * 2（直径）
        -- 所需本地缩放 = 目标世界尺寸 / 父节点缩放
        local targetWorldSize = collisionRadius * 2
        local localScale = targetWorldSize / parentScale
        debugNode.scale = Vector3(localScale, localScale, localScale)
        
        local debugModel = debugNode:CreateComponent("StaticModel")
        debugModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        -- 半透明绿色材质
        local debugMat = Material:new()
        debugMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        debugMat:SetShaderParameter("MatDiffColor", Variant(Color(0.0, 1.0, 0.0, 0.25)))
        debugMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.0, 1.0, 0.0)))
        debugModel:SetMaterial(debugMat)
    end
    
    -- 设置子弹速度（受游戏速度影响）
    local gameSpeed = GameState.gameSpeed or 1.0
    rigidBody.linearVelocity = direction * weapon.bulletSpeed * gameSpeed
    
    -- 计算子弹生命周期：确保至少能飞 BulletMinRange 米
    -- 公式：lifetime = 距离 / max(速度, 1)
    local effectiveSpeed = math.max(weapon.bulletSpeed, 1.0)
    local maxLifetime = CONFIG.BulletMinRange / effectiveSpeed
    
    -- 子弹数据
    local bullet = {
        node = bulletNode,
        rigidBody = rigidBody,
        direction = direction,
        speed = weapon.bulletSpeed,
        startPosition = muzzlePos,  -- 记录起始位置（用于计算距离衰减）
        lifetime = 0,
        maxLifetime = maxLifetime,  -- 动态计算的生命周期
        damage = weapon.damage,
        weaponId = GameState.currentWeaponId,
        hasHit = false,
        removed = false,
    }
    
    table.insert(GameState.bullets, bullet)
    
    -- 注册到映射表（用于碰撞回调查找子弹数据）
    GameState.bulletDataMap[bulletNode] = bullet
end

--- 创建枪口闪光
function M.CreateMuzzleFlash()
    local flashNode = GameState.scene:CreateChild("MuzzleFlash")
    
    -- 优先使用角色手持武器的枪口位置
    local muzzleWorldPos
    local playerMuzzle = GetPlayer().GetWeaponMuzzleNode()
    if playerMuzzle then
        muzzleWorldPos = playerMuzzle.worldPosition
    elseif GameState.muzzleNode then
        muzzleWorldPos = GameState.muzzleNode.worldPosition
    else
        muzzleWorldPos = GameState.cameraNode.worldPosition
    end
    
    flashNode.position = muzzleWorldPos
    flashNode.scale = Vector3(0.15, 0.15, 0.15)
    
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.1, 1.0)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 3.0, 0.5)))
    model:SetMaterial(mat)
    
    local flash = {
        node = flashNode,
        direction = Vector3.ZERO,
        speed = 0,
        lifetime = 0,
        isFlash = true,
        maxLifetime = 0.05,
    }
    table.insert(GameState.bullets, flash)
end

--- 创建抛出的弹壳
function M.CreateEjectedCasing()
    local w = GameState.currentWeapon
    if not w or not w.model then return end
    
    local m = w.model
    
    -- 优先使用角色手持武器的抛壳口位置（第三人称）
    local playerEjection = GetPlayer().GetWeaponEjectionNode()
    local playerWeapon = GetPlayer().GetWeaponNode()
    
    local ejectionWorldPos
    local modelContainer
    
    if playerEjection and playerWeapon then
        -- 使用第三人称角色手持武器的抛壳口
        ejectionWorldPos = playerEjection.worldPosition
        modelContainer = playerWeapon
    else
        -- 回退到第一人称视角的枪（兼容）
        local ejectionOffset = m.ejectionPortOffset
        if not ejectionOffset then return end  -- 没有配置抛壳口则不生成
        
        -- 获取枪模型容器节点（用于计算世界坐标）
        local gunNode = GameState.gunNode
        if not gunNode then return end
        
        -- 找到模型容器节点（非 prefab 是 ModelContainer，prefab 是 PrefabModel）
        if m.isPrefab then
            modelContainer = gunNode:GetChild("PrefabModel")
        else
            modelContainer = gunNode:GetChild("ModelContainer")
        end
        
        if not modelContainer then
            -- 没有模型容器，使用枪节点本身
            modelContainer = gunNode
        end
        
        -- 根据左右手状态和模型配置翻转抛壳口 X 坐标
        local flipX = GameState.isLeftHanded
        -- prefab 旋转180度的模型需要额外翻转
        if m.ejectionFlipX then
            flipX = not flipX
        end
        
        local adjustedOffset = ejectionOffset
        if flipX then
            adjustedOffset = Vector3(-ejectionOffset.x, ejectionOffset.y, ejectionOffset.z)
        end
        
        -- 计算抛壳口世界坐标
        ejectionWorldPos = modelContainer:LocalToWorld(adjustedOffset)
    end
    
    -- 创建弹壳节点
    local casingNode = GameState.scene:CreateChild("Casing")
    casingNode.position = ejectionWorldPos
    
    -- 弹壳尺寸
    local scale = m.casingScale or 1.0
    local radius = CASING_CONFIG.baseRadius * scale
    local length = CASING_CONFIG.baseLength * scale
    
    -- 弹壳模型（圆柱体）
    casingNode.scale = Vector3(radius * 2, length, radius * 2)
    
    local model = casingNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    -- 黄铜材质
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(CASING_CONFIG.brassColor))
    mat:SetShaderParameter("Metallic", Variant(0.9))
    mat:SetShaderParameter("Roughness", Variant(0.3))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.3, 0.2, 0.05)))
    model:SetMaterial(mat)
    model.castShadows = false
    
    -- 计算抛出速度（相对于枪的朝向）
    -- 枪的右方向（考虑玩家和相机的旋转）
    local gunWorldRotation = modelContainer.worldRotation
    local rightDir = gunWorldRotation * Vector3.RIGHT
    local upDir = gunWorldRotation * Vector3.UP
    local backDir = gunWorldRotation * Vector3.BACK
    
    -- 根据左右手状态翻转抛壳方向
    -- 左手持枪时，弹壳向左抛出（rightDir 取反）
    local handednessSign = GameState.isLeftHanded and -1 or 1
    
    -- 如果模型配置了 ejectionFlipX（如 prefab 旋转180度），额外翻转方向
    if m.ejectionFlipX then
        handednessSign = handednessSign * -1
    end
    
    -- 组合抛出方向：主要向右上后方（左手时向左上后方）
    local ejectionDir = (
        rightDir * handednessSign * math.cos(math.rad(CASING_CONFIG.ejectionAngleRight)) +
        upDir * math.sin(math.rad(CASING_CONFIG.ejectionAngleUp)) +
        backDir * 0.3  -- 略微向后
    ):Normalized()
    
    -- 添加一些随机性
    local randomYaw = (math.random() - 0.5) * 20
    local randomPitch = (math.random() - 0.5) * 15
    local randomRotation = Quaternion(randomPitch, Vector3.RIGHT) * Quaternion(randomYaw, Vector3.UP)
    ejectionDir = randomRotation * ejectionDir
    
    -- 速度
    local speed = CASING_CONFIG.ejectionSpeed * (0.8 + math.random() * 0.4)
    local velocity = ejectionDir * speed
    
    -- 初始旋转（随机）
    casingNode.rotation = Quaternion(math.random() * 360, Vector3.RIGHT) * 
                          Quaternion(math.random() * 360, Vector3.UP)
    
    -- 弹壳数据
    local casing = {
        node = casingNode,
        velocity = velocity,
        lifetime = 0,
        maxLifetime = CASING_CONFIG.lifetime,
        spinAxis = Vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5):Normalized(),
        spinSpeed = CASING_CONFIG.spinSpeed * (0.7 + math.random() * 0.6),
    }
    
    table.insert(GameState.casings, casing)
end

--- 更新弹壳
function M.UpdateCasings(dt)
    local toRemove = {}
    local gameSpeed = GameState.gameSpeed or 1.0
    local frameDelta = dt * gameSpeed
    
    for i, casing in ipairs(GameState.casings) do
        if casing.node then
            casing.lifetime = casing.lifetime + frameDelta
            
            -- 超时移除
            if casing.lifetime >= casing.maxLifetime then
                casing.node:Remove()
                casing.node = nil
                table.insert(toRemove, i)
            else
                -- 应用重力
                casing.velocity = casing.velocity + Vector3(0, CASING_CONFIG.gravity * frameDelta, 0)
                
                -- 更新位置
                casing.node.position = casing.node.position + casing.velocity * frameDelta
                
                -- 旋转
                local spinAngle = casing.spinSpeed * frameDelta
                local currentRot = casing.node.rotation
                local spinRot = Quaternion(spinAngle, casing.spinAxis)
                casing.node.rotation = spinRot * currentRot
                
                -- 淡出效果（最后0.3秒）
                local fadeTime = 0.3
                local remaining = casing.maxLifetime - casing.lifetime
                if remaining < fadeTime then
                    local alpha = remaining / fadeTime
                    local scale = casing.node.scale * (0.5 + 0.5 * alpha)
                    casing.node.scale = scale
                end
            end
        else
            table.insert(toRemove, i)
        end
    end
    
    -- 从后向前移除
    for i = #toRemove, 1, -1 do
        table.remove(GameState.casings, toRemove[i])
    end
end

-- ============================================================================
-- 更新函数
-- ============================================================================

--- 更新子弹（现在主要处理生命周期和闪光效果）
function M.Update(dt)
    local toRemove = {}
    
    for i, bullet in ipairs(GameState.bullets) do
        if bullet.removed then
            table.insert(toRemove, i)
        elseif bullet.node then
            bullet.lifetime = bullet.lifetime + dt
            
            if bullet.isFlash then
                -- 枪口闪光效果（受游戏速度影响）
                local gameSpeed = GameState.gameSpeed or 1.0
                bullet.gameLifetime = (bullet.gameLifetime or 0) + dt * gameSpeed
                if bullet.gameLifetime >= bullet.maxLifetime then
                    table.insert(toRemove, i)
                    bullet.node:Remove()
                end
            elseif bullet.isRaycastBullet then
                -- 每帧射线检测模式：手动更新子弹位置并进行实时碰撞检测
                local gameSpeed = GameState.gameSpeed or 1.0
                local frameDelta = dt * gameSpeed
                bullet.gameLifetime = bullet.gameLifetime + frameDelta
                
                -- 计算新位置
                local frameDistance = bullet.speed * frameDelta
                local newPos = bullet.prevPosition + bullet.direction * frameDistance
                
                -- 从上一帧位置到当前位置进行射线检测
                local ray = Ray(bullet.prevPosition, bullet.direction)
                local result = GameState.physicsWorld:RaycastSingle(ray, frameDistance + 0.1, GameState.COLLISION_MASK.BULLET)
                
                if result.body and result.distance <= frameDistance + 0.05 then
                    -- 击中目标！
                    local hitPos = result.position
                    local hitNormal = result.normal
                    local hitNode = result.body:GetNode()
                    
                    -- 处理击中效果
                    local hitHandled = false
                    
                    -- 检查是否击中靶子
                    if GameState.targetNodeMap then
                        local target = GameState.targetNodeMap[hitNode]
                        if target then
                            if Target.HandleCollision(hitNode, hitPos) then
                                HitEffects.CreateHitEffect(hitPos, bullet.direction)
                                hitHandled = true
                            end
                        end
                    end
                    
                    -- 检查是否击中怪物
                    if not hitHandled and GameState.monsterNodeMap then
                        local monster = GameState.monsterNodeMap[hitNode]
                        if monster and monster.alive then
                            -- 判断是否爆头
                            local monsterPos = hitNode.worldPosition
                            local headHeight = monsterPos.y + CONFIG.MonsterHeight * 0.35
                            local isHeadshot = hitPos.y >= headHeight
                            
                            Monster.TakeDamage(monster, bullet.damage, isHeadshot, hitPos)
                            HitEffects.CreateHitEffect(hitPos, bullet.direction)
                            hitHandled = true
                        end
                    end
                    
                    -- 击中墙壁或其他物体
                    if not hitHandled then
                        HitEffects.CreateWallHitEffect(hitPos, bullet.direction, hitNormal)
                    end
                    
                    -- 移除子弹
                    bullet.hasHit = true
                    bullet.node:Remove()
                    bullet.node = nil
                    bullet.removed = true
                    table.insert(toRemove, i)
                else
                    -- 未击中，更新位置
                    bullet.node.position = newPos
                    bullet.prevPosition = newPos
                    bullet.traveledDistance = bullet.traveledDistance + frameDistance
                    
                    -- 超过最大距离，移除子弹
                    if bullet.traveledDistance >= bullet.maxDistance then
                        bullet.node:Remove()
                        bullet.node = nil
                        bullet.removed = true
                        table.insert(toRemove, i)
                    end
                end
            elseif bullet.delayedRemoval then
                -- 测试模式：子弹击中后延迟删除
                local timeSinceHit = bullet.lifetime - bullet.hitTime
                if timeSinceHit >= bullet.delayedRemovalTime then
                    M.RemoveBullet(bullet)
                    table.insert(toRemove, i)
                end
            else
                -- 物理子弹：实时更新速度以响应游戏速度变化
                if bullet.rigidBody and not bullet.hasHit then
                    local gameSpeed = GameState.gameSpeed or 1.0
                    local currentVel = bullet.rigidBody.linearVelocity
                    local currentSpeed = currentVel:Length()
                    if currentSpeed > 0.1 then
                        local currentDir = currentVel / currentSpeed
                        local targetSpeed = bullet.speed * gameSpeed
                        bullet.rigidBody.linearVelocity = currentDir * targetSpeed
                    end
                end
                
                -- 子弹生命周期检查（超时移除）
                -- 使用子弹自身的 maxLifetime（根据速度动态计算）
                local maxLife = bullet.maxLifetime or CONFIG.BulletLifetime
                if bullet.lifetime >= maxLife then
                    M.RemoveBullet(bullet)
                    table.insert(toRemove, i)
                end
            end
        else
            table.insert(toRemove, i)
        end
    end
    
    -- 从后向前移除
    for i = #toRemove, 1, -1 do
        table.remove(GameState.bullets, toRemove[i])
    end
    
    -- 更新弹壳
    M.UpdateCasings(dt)
end

--- 更新枪口瞄准点（用于 UI 准心显示）
function M.UpdateGunAimPoint()
    -- 初始化
    GameState.gunAimVisible = false
    
    -- 优先使用角色手持武器的枪口位置
    local muzzleWorldPos
    local playerMuzzle = GetPlayer().GetWeaponMuzzleNode()
    if playerMuzzle then
        muzzleWorldPos = playerMuzzle.worldPosition
    elseif GameState.muzzleNode then
        muzzleWorldPos = GameState.muzzleNode.worldPosition
    else
        -- 没有枪口节点，使用屏幕中心
        GameState.gunAimScreenPos = Vector2(GameState.screenWidth / 2, GameState.screenHeight / 2)
        GameState.gunAimVisible = true
        return
    end
    
    if not GameState.camera then
        GameState.gunAimScreenPos = Vector2(GameState.screenWidth / 2, GameState.screenHeight / 2)
        GameState.gunAimVisible = true
        return
    end
    
    -- 从相机发射射线
    local screenCenter = Vector2(0.5, 0.5)
    local cameraRay = GameState.camera:GetScreenRay(screenCenter.x, screenCenter.y)
    local cameraTargetPoint = cameraRay.origin + cameraRay.direction * CONFIG.MaxShootDistance
    
    -- 使用物理射线检测
    if GameState.physicsWorld then
        local result = GameState.physicsWorld:RaycastSingle(cameraRay, CONFIG.MaxShootDistance, 0xFFFFFFFF)
        if result.body then
            cameraTargetPoint = result.position
        end
    end
    
    -- 从枪口向目标点发射射线（使用已确定的 muzzleWorldPos）
    local gunDirection = (cameraTargetPoint - muzzleWorldPos):Normalized()
    local gunMaxDist = (cameraTargetPoint - muzzleWorldPos):Length()
    
    local gunHitPoint = cameraTargetPoint
    
    -- 使用物理射线检测枪口实际击中点
    if GameState.physicsWorld then
        local gunRay = Ray(muzzleWorldPos, gunDirection)
        local result = GameState.physicsWorld:RaycastSingle(gunRay, gunMaxDist, 0xFFFFFFFF)
        if result.body then
            gunHitPoint = result.position
        end
    end
    
    -- 存储枪口实际击中点
    GameState.gunAimPoint = gunHitPoint
    
    -- 将击中点投影到屏幕坐标
    local screenPos = GameState.camera:WorldToScreenPoint(GameState.gunAimPoint)
    if screenPos then
        -- 检查是否在屏幕范围内（归一化坐标 0-1）
        local inScreen = screenPos.x >= 0 and screenPos.x <= 1 and screenPos.y >= 0 and screenPos.y <= 1
        if inScreen then
            GameState.gunAimScreenPos = Vector2(
                screenPos.x * GameState.screenWidth,
                screenPos.y * GameState.screenHeight
            )
            GameState.gunAimVisible = true
        else
            GameState.gunAimScreenPos = Vector2(GameState.screenWidth / 2, GameState.screenHeight / 2)
            GameState.gunAimVisible = true
        end
    else
        GameState.gunAimScreenPos = Vector2(GameState.screenWidth / 2, GameState.screenHeight / 2)
        GameState.gunAimVisible = true
    end
end

-- ============================================================================
-- 旧的射线检测函数（保留用于兼容，但不再使用）
-- ============================================================================

--- 从屏幕中心发射射线检测（旧版本，保留兼容）
function M.RaycastFromScreenCenter()
    local screenCenter = Vector2(0.5, 0.5)
    local cameraRay = GameState.camera:GetScreenRay(screenCenter.x, screenCenter.y)
    local rayOrigin = cameraRay.origin
    local rayDir = cameraRay.direction
    
    local closestHit = nil
    local closestDist = CONFIG.MaxShootDistance
    local hitCollider = false
    
    -- 使用物理射线检测
    if GameState.physicsWorld then
        local result = GameState.physicsWorld:RaycastSingle(cameraRay, CONFIG.MaxShootDistance, 0xFFFFFFFF)
        if result.body then
            closestHit = {
                hitPoint = result.position,
                distance = result.distance,
                type = "physics"
            }
            closestDist = result.distance
        end
    end
    
    return closestHit, rayOrigin, rayDir, hitCollider
end

return M
