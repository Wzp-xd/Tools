-- ============================================================================
-- Grenade.lua - 手榴弹系统（使用引擎物理）
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"

local M = {}

local CONFIG = Config.CONFIG

--- 投掷手榴弹
function M.Throw()
    if GameState.grenadeCount <= 0 then
        print("No grenades!")
        return
    end
    
    if GameState.grenadeCooldown > 0 then
        return
    end
    
    GameState.grenadeCount = GameState.grenadeCount - 1
    GameState.grenadeCooldown = CONFIG.GrenadeCooldown
    
    local startPos = GameState.cameraNode.worldPosition
    
    local cameraRotation = Quaternion(GameState.pitch, Vector3.RIGHT) * Quaternion(GameState.yaw, Vector3.UP)
    local cameraForward = cameraRotation * Vector3.FORWARD
    local cameraRight = cameraRotation * Vector3.RIGHT
    
    local baseAngle = CONFIG.GrenadeThrowAngle
    local pitchFactor = GameState.pitch / 90.0
    local extraAngle = baseAngle * (1 - pitchFactor * 0.5)
    extraAngle = math.max(5, math.min(45, extraAngle))
    
    local throwDir = Quaternion(-extraAngle, cameraRight) * cameraForward
    throwDir = throwDir:Normalized()
    
    local grenadeNode = GameState.scene:CreateChild("Grenade")
    grenadeNode.position = startPos + cameraForward * 0.5
    
    local radius = CONFIG.GrenadeRadius
    grenadeNode.scale = Vector3(radius * 2, radius * 2, radius * 2)
    
    -- 添加刚体组件（动态物理）
    local rigidBody = grenadeNode:CreateComponent("RigidBody")
    rigidBody.mass = 0.5  -- 0.5kg
    rigidBody.friction = 0.5
    rigidBody.restitution = CONFIG.GrenadeBounce  -- 弹跳系数
    rigidBody.linearDamping = 0.1
    rigidBody.angularDamping = 0.3
    rigidBody.collisionLayer = 4  -- 手榴弹碰撞层
    rigidBody.collisionMask = 0xFFFFFFFF  -- 与所有层碰撞
    
    -- 设置初始速度（受游戏速度影响）
    local gameSpeed = GameState.gameSpeed or 1.0
    rigidBody.linearVelocity = throwDir * CONFIG.GrenadeThrowSpeed * gameSpeed
    
    -- 添加球形碰撞体
    local shape = grenadeNode:CreateComponent("CollisionShape")
    shape:SetSphere(1.0)  -- 使用单位球，配合节点缩放
    
    -- 视觉模型
    local model = grenadeNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.25, 0.1, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.3))
    mat:SetShaderParameter("Roughness", Variant(0.6))
    model:SetMaterial(mat)
    model.castShadows = true
    
    local grenade = {
        node = grenadeNode,
        rigidBody = rigidBody,
        fuseTime = CONFIG.GrenadeFuseTime,
        exploded = false,
        radius = radius,
    }
    table.insert(GameState.grenades, grenade)
    
    print("Grenade thrown! Remaining: " .. GameState.grenadeCount)
end

--- 爆炸手榴弹
function M.Explode(grenade)
    grenade.exploded = true
    local explosionPos = grenade.node.position
    
    grenade.node:Remove()
    grenade.node = nil
    
    M.CreateExplosionEffect(explosionPos)
    
    -- 对怪物造成伤害
    local Monster = require "modules.Monster"
    for _, monster in ipairs(GameState.monsters) do
        if monster.alive and monster.node then
            local monsterPos = monster.node.position
            local distance = (monsterPos - explosionPos):Length()
            
            if distance <= CONFIG.GrenadeExplosionRadius then
                local damage
                if distance <= CONFIG.GrenadeFullDamageRadius then
                    damage = CONFIG.GrenadeExplosionDamage
                else
                    local falloffDist = distance - CONFIG.GrenadeFullDamageRadius
                    local falloffRange = CONFIG.GrenadeExplosionRadius - CONFIG.GrenadeFullDamageRadius
                    local falloffPercent = falloffDist / falloffRange
                    local damagePercent = 1 - falloffPercent * (1 - CONFIG.GrenadeMinDamagePercent)
                    damage = CONFIG.GrenadeExplosionDamage * damagePercent
                end
                
                Monster.Damage(monster, math.floor(damage), false, "grenade", distance)
                
                -- 爆炸冲击力（推开怪物）
                if monster.rigidBody then
                    local pushDir = (monsterPos - explosionPos):Normalized()
                    local pushForce = 500 * (1 - distance / CONFIG.GrenadeExplosionRadius)
                    monster.rigidBody:ApplyImpulse(pushDir * pushForce)
                end
            end
        end
    end
    
    -- 对玩家造成伤害
    local playerPos = GameState.playerNode.position
    local playerDist = (playerPos - explosionPos):Length()
    if playerDist <= CONFIG.GrenadeExplosionRadius then
        local Player = require "modules.Player"
        local damage
        if playerDist <= CONFIG.GrenadeFullDamageRadius then
            damage = CONFIG.GrenadeExplosionDamage
        else
            local falloffDist = playerDist - CONFIG.GrenadeFullDamageRadius
            local falloffRange = CONFIG.GrenadeExplosionRadius - CONFIG.GrenadeFullDamageRadius
            local falloffPercent = falloffDist / falloffRange
            local damagePercent = 1 - falloffPercent * (1 - CONFIG.GrenadeMinDamagePercent)
            damage = CONFIG.GrenadeExplosionDamage * damagePercent
        end
        Player.TakeDamage(math.floor(damage))
        
        -- 爆炸冲击力（推开玩家）
        if GameState.playerBody then
            local pushDir = (playerPos - explosionPos):Normalized()
            local pushForce = 300 * (1 - playerDist / CONFIG.GrenadeExplosionRadius)
            GameState.playerBody:ApplyImpulse(pushDir * pushForce)
        end
    end
end

--- 创建爆炸特效
function M.CreateExplosionEffect(pos)
    local explosionRadius = CONFIG.GrenadeExplosionRadius  -- 7米
    
    -- 爆炸闪光核心（明亮的中心）
    local coreNode = GameState.scene:CreateChild("ExplosionCore")
    coreNode.position = pos
    local coreSize = explosionRadius * 0.3
    coreNode.scale = Vector3(coreSize, coreSize, coreSize)
    
    local coreModel = coreNode:CreateComponent("StaticModel")
    coreModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local coreMat = Material:new()
    coreMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    coreMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.9, 0.7, 1.0)))
    coreMat:SetShaderParameter("MatEmissiveColor", Variant(Color(15.0, 10.0, 3.0)))
    coreModel:SetMaterial(coreMat)
    
    local coreEffect = {
        node = coreNode,
        effectType = "flash",
        lifetime = 0,
        maxLifetime = 0.15,
        startScale = coreSize,
        endScale = coreSize * 2,
    }
    table.insert(GameState.effects, coreEffect)
    
    -- 爆炸扩散球（匹配爆炸范围）
    local flashNode = GameState.scene:CreateChild("ExplosionFlash")
    flashNode.position = pos
    local startSize = explosionRadius * 0.4
    flashNode.scale = Vector3(startSize, startSize, startSize)
    
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, 0.8)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 4.0, 0.5)))
    model:SetMaterial(mat)
    
    local effect = {
        node = flashNode,
        effectType = "flash",
        lifetime = 0,
        maxLifetime = 0.3,
        startScale = startSize,
        endScale = explosionRadius,  -- 扩散到爆炸范围
    }
    table.insert(GameState.effects, effect)
    
    -- 烟雾环
    local smokeNode = GameState.scene:CreateChild("ExplosionSmoke")
    smokeNode.position = pos
    local smokeStart = explosionRadius * 0.5
    smokeNode.scale = Vector3(smokeStart, smokeStart * 0.5, smokeStart)
    
    local smokeModel = smokeNode:CreateComponent("StaticModel")
    smokeModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local smokeMat = Material:new()
    smokeMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    smokeMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.25, 0.2, 0.6)))
    smokeMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.5, 0.3, 0.1)))
    smokeModel:SetMaterial(smokeMat)
    
    local smokeEffect = {
        node = smokeNode,
        effectType = "smoke",
        lifetime = 0,
        maxLifetime = 0.6,
        startScale = smokeStart,
        endScale = explosionRadius * 1.2,
        velocity = Vector3(0, 2.0, 0),  -- 向上飘动
    }
    table.insert(GameState.effects, smokeEffect)
    
    -- 火花（范围匹配爆炸半径）
    local sparkCount = 40
    for i = 1, sparkCount do
        local sparkNode = GameState.scene:CreateChild("ExplosionSpark")
        sparkNode.position = pos
        
        local size = 0.1 + math.random() * 0.2
        sparkNode.scale = Vector3(size, size, size)
        
        local sparkModel = sparkNode:CreateComponent("StaticModel")
        sparkModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        local sparkMat = Material:new()
        sparkMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        local colorVar = math.random()
        sparkMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.3 + colorVar * 0.5, 0.1, 1.0)))
        sparkMat:SetShaderParameter("MatEmissiveColor", Variant(Color(4.0, 1.5 + colorVar, 0.3)))
        sparkModel:SetMaterial(sparkMat)
        
        local dir = Vector3(
            (math.random() - 0.5) * 2,
            math.random() * 0.8 + 0.2,
            (math.random() - 0.5) * 2
        ):Normalized()
        
        -- 火花速度基于爆炸范围
        local sparkSpeed = explosionRadius * (1.0 + math.random() * 1.5)
        
        local sparkEffect = {
            node = sparkNode,
            effectType = "spark",
            lifetime = 0,
            maxLifetime = 0.4 + math.random() * 0.4,
            velocity = dir * sparkSpeed,
            gravity = -12,
            startScale = size,
        }
        table.insert(GameState.effects, sparkEffect)
    end
end

--- 更新手榴弹（只处理引信计时，物理由引擎处理）
function M.Update(dt)
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    
    -- 投掷冷却（受游戏速度影响）
    if GameState.grenadeCooldown > 0 then
        GameState.grenadeCooldown = GameState.grenadeCooldown - dt * gameSpeed
    end
    
    local toRemove = {}
    
    for i, grenade in ipairs(GameState.grenades) do
        if grenade.node and not grenade.exploded then
            -- 引信计时（受游戏速度影响）
            grenade.fuseTime = grenade.fuseTime - dt * gameSpeed
            
            -- 实时更新手榴弹速度以响应游戏速度变化
            if grenade.rigidBody then
                local currentVel = grenade.rigidBody.linearVelocity
                local currentSpeed = currentVel:Length()
                if currentSpeed > 0.5 then
                    local currentDir = currentVel / currentSpeed
                    -- 重力不受 gameSpeed 影响，只调整水平方向的速度分量
                    local horizontalVel = Vector3(currentVel.x, 0, currentVel.z)
                    local horizontalSpeed = horizontalVel:Length()
                    if horizontalSpeed > 0.1 then
                        local horizontalDir = horizontalVel / horizontalSpeed
                        local targetHorizontalSpeed = horizontalSpeed * gameSpeed / (grenade.lastGameSpeed or 1.0)
                        grenade.rigidBody.linearVelocity = Vector3(
                            horizontalDir.x * targetHorizontalSpeed,
                            currentVel.y,
                            horizontalDir.z * targetHorizontalSpeed
                        )
                    end
                end
                grenade.lastGameSpeed = gameSpeed
            end
            
            if grenade.fuseTime <= 0 then
                M.Explode(grenade)
                table.insert(toRemove, i)
            end
            -- 物理移动由引擎自动处理，无需手动更新位置
        elseif grenade.exploded then
            table.insert(toRemove, i)
        end
    end
    
    for i = #toRemove, 1, -1 do
        table.remove(GameState.grenades, toRemove[i])
    end
end

--- 清除所有手榴弹
function M.ClearAll()
    for _, grenade in ipairs(GameState.grenades) do
        if grenade.node then
            grenade.node:Remove()
        end
    end
    GameState.grenades = {}
end

return M
