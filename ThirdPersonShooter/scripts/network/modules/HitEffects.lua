-- ============================================================================
-- HitEffects.lua - 击中特效系统（多人游戏版）
-- 适配自 demo 版本，使用传入的 scene 和 effects 数组
-- ============================================================================

local M = {}

-- 特效配置
M.CONFIG = {
    ShowBulletHoles = true,
    BulletHoleLifetime = 5.0,
    BulletHoleFadeDuration = 1.0,
}

-- ============================================================================
-- 核心函数
-- ============================================================================

--- 创建击中特效（敌人被击中时）
---@param scene Scene 场景对象
---@param effects table 特效数组（用于管理生命周期）
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
function M.CreateHitEffect(scene, effects, hitPos, bulletDir)
    -- 1. 创建中心闪光
    M.CreateHitFlash(scene, effects, hitPos)
    
    -- 2. 创建火花粒子
    M.CreateSparks(scene, effects, hitPos, bulletDir)
    
    -- 3. 创建烟雾效果
    M.CreateSmoke(scene, effects, hitPos)
end

--- 创建血液飞溅特效（角色被击中时）
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
function M.CreateBloodEffect(scene, effects, hitPos, bulletDir)
    -- 1. 创建红色中心闪光
    M.CreateBloodFlash(scene, effects, hitPos)
    
    -- 2. 创建血液粒子飞溅
    M.CreateBloodSplatter(scene, effects, hitPos, bulletDir)
    
    -- 3. 创建血雾效果
    M.CreateBloodMist(scene, effects, hitPos)
end

--- 创建血液中心闪光
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
function M.CreateBloodFlash(scene, effects, hitPos)
    local flashNode = scene:CreateChild("BloodFlash", LOCAL)
    flashNode.position = hitPos
    flashNode.scale = Vector3(0.25, 0.25, 0.25)
    
    local model = flashNode:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.1, 0.1, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.5))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(1.5, 0.2, 0.1)))
    model:SetMaterial(mat)
    model.castShadows = false
    
    local effect = {
        node = flashNode,
        effectType = "flash",
        lifetime = 0,
        maxLifetime = 0.1,
        startScale = 0.25,
        endScale = 0.4,
    }
    table.insert(effects, effect)
end

--- 创建血液粒子飞溅
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
function M.CreateBloodSplatter(scene, effects, hitPos, bulletDir)
    local particleCount = 15 + math.random(10)
    
    for i = 1, particleCount do
        local particleNode = scene:CreateChild("BloodParticle", LOCAL)
        particleNode.position = hitPos
        
        -- 不同大小的血滴
        local size = 0.015 + math.random() * 0.035
        particleNode.scale = Vector3(size, size, size)
        
        local model = particleNode:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        -- 深浅不同的红色
        local redVar = 0.6 + math.random() * 0.4
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(redVar, 0.05, 0.05, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(0.2))
        mat:SetShaderParameter("Roughness", Variant(0.6))
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(redVar * 0.3, 0.02, 0.02)))
        model:SetMaterial(mat)
        model.castShadows = false
        
        -- 主要沿子弹方向飞溅，加上随机偏移
        local reflectDir = bulletDir:Normalized()
        local randomOffset = Vector3(
            (math.random() - 0.5) * 1.5,
            (math.random() - 0.5) * 1.5 + 0.3,
            (math.random() - 0.5) * 1.5
        )
        local particleDir = (reflectDir + randomOffset):Normalized()
        local particleSpeed = 2 + math.random() * 4
        
        local effect = {
            node = particleNode,
            effectType = "spark",
            lifetime = 0,
            maxLifetime = 0.4 + math.random() * 0.3,
            velocity = particleDir * particleSpeed,
            gravity = -12,
            startScale = size,
        }
        table.insert(effects, effect)
    end
end

--- 创建血雾效果
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
function M.CreateBloodMist(scene, effects, hitPos)
    local mistCount = 6
    
    for i = 1, mistCount do
        local mistNode = scene:CreateChild("BloodMist", LOCAL)
        mistNode.position = hitPos + Vector3(
            (math.random() - 0.5) * 0.15,
            (math.random() - 0.5) * 0.15,
            (math.random() - 0.5) * 0.15
        )
        
        local size = 0.08 + math.random() * 0.06
        mistNode.scale = Vector3(size, size, size)
        
        local model = mistNode:CreateComponent("StaticModel", LOCAL)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        local redIntensity = 0.4 + math.random() * 0.3
        mat:SetShaderParameter("MatDiffColor", Variant(Color(redIntensity, 0.02, 0.02, 0.5)))
        mat:SetShaderParameter("Metallic", Variant(0.0))
        mat:SetShaderParameter("Roughness", Variant(1.0))
        model:SetMaterial(mat)
        model.castShadows = false
        
        local effect = {
            node = mistNode,
            effectType = "smoke",
            lifetime = 0,
            maxLifetime = 0.6 + math.random() * 0.3,
            velocity = Vector3(
                (math.random() - 0.5) * 0.4,
                0.3 + math.random() * 0.3,
                (math.random() - 0.5) * 0.4
            ),
            startScale = size,
            endScale = size * 2.5,
        }
        table.insert(effects, effect)
    end
end

--- 创建墙壁撞击特效
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线
function M.CreateWallHitEffect(scene, effects, hitPos, bulletDir, hitNormal)
    -- 创建弹孔
    M.CreateBulletHole(scene, effects, hitPos, bulletDir, hitNormal)
    
    -- 小型闪光
    local flashNode = scene:CreateChild("WallFlash")
    flashNode.position = hitPos
    flashNode.scale = Vector3(0.15, 0.15, 0.15)
    
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.9, 0.7, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.5))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.5, 1.5)))
    model:SetMaterial(mat)
    
    local effect = {
        node = flashNode,
        effectType = "flash",
        lifetime = 0,
        maxLifetime = 0.05,
        startScale = 0.15,
        endScale = 0.25,
    }
    table.insert(effects, effect)
    
    -- 灰色碎片
    local debrisCount = 3
    for i = 1, debrisCount do
        local debrisNode = scene:CreateChild("Debris")
        debrisNode.position = hitPos
        
        local size = 0.02 + math.random() * 0.02
        debrisNode.scale = Vector3(size, size, size)
        
        local debrisModel = debrisNode:CreateComponent("StaticModel")
        debrisModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        
        local gray = 0.3 + math.random() * 0.3
        local debrisMat = Material:new()
        debrisMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        debrisMat:SetShaderParameter("MatDiffColor", Variant(Color(gray, gray, gray, 1.0)))
        debrisMat:SetShaderParameter("Metallic", Variant(0.0))
        debrisMat:SetShaderParameter("Roughness", Variant(0.9))
        debrisModel:SetMaterial(debrisMat)
        
        local reflectDir = bulletDir * (-1)
        local randomOffset = Vector3(
            (math.random() - 0.5) * 2,
            (math.random() - 0.5) * 2 + 0.3,
            (math.random() - 0.5) * 2
        )
        local debrisDir = (reflectDir + randomOffset):Normalized()
        local debrisSpeed = 2 + math.random() * 3
        
        local debrisEffect = {
            node = debrisNode,
            effectType = "spark",
            lifetime = 0,
            maxLifetime = 0.2 + math.random() * 0.2,
            velocity = debrisDir * debrisSpeed,
            gravity = -12,
            startScale = size,
        }
        table.insert(effects, debrisEffect)
    end
    
    -- 拖尾火花
    M.CreateTrailingSparks(scene, effects, hitPos, bulletDir, hitNormal)
end

--- 创建拖尾火花效果
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线
function M.CreateTrailingSparks(scene, effects, hitPos, bulletDir, hitNormal)
    local sparkCount = 2 + math.random(2)
    local normal = hitNormal or (bulletDir * (-1)):Normalized()
    
    for i = 1, sparkCount do
        local sparkNode = scene:CreateChild("TrailingSpark")
        sparkNode.position = hitPos
        
        local size = 0.015 + math.random() * 0.02
        sparkNode.scale = Vector3(size, size, size)
        
        local sparkModel = sparkNode:CreateComponent("StaticModel")
        sparkModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        local colorVar = math.random()
        local sparkMat = Material:new()
        sparkMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        sparkMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.7 + colorVar * 0.3, 0.2, 1.0)))
        sparkMat:SetShaderParameter("Metallic", Variant(0.9))
        sparkMat:SetShaderParameter("Roughness", Variant(0.1))
        sparkMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 3.0 + colorVar * 2.0, 0.5)))
        sparkModel:SetMaterial(sparkMat)
        
        local reflectDir = normal
        local randomOffset = Vector3(
            (math.random() - 0.5) * 1.5,
            math.random() * 0.8 + 0.2,
            (math.random() - 0.5) * 1.5
        )
        local sparkDir = (reflectDir + randomOffset):Normalized()
        local sparkSpeed = 4 + math.random() * 6
        
        local sparkEffect = {
            node = sparkNode,
            effectType = "trailingspark",
            lifetime = 0,
            maxLifetime = 0.4 + math.random() * 0.4,
            velocity = sparkDir * sparkSpeed,
            gravity = -8,
            startScale = size,
            trailTimer = 0,
            trailInterval = 0.02,
            baseColor = { r = 1.0, g = 0.7 + colorVar * 0.3, b = 0.2 },
            emissiveIntensity = 5.0,
            scene = scene,  -- 保存 scene 引用用于创建拖尾
            effects = effects,
        }
        table.insert(effects, sparkEffect)
    end
end

--- 创建拖尾粒子
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param position Vector3 位置
---@param baseColor table 基础颜色
---@param size number 尺寸
function M.CreateTrailParticle(scene, effects, position, baseColor, size)
    local trailNode = scene:CreateChild("SparkTrail")
    trailNode.position = position
    
    local trailSize = size * 0.6
    trailNode.scale = Vector3(trailSize, trailSize, trailSize)
    
    local trailModel = trailNode:CreateComponent("StaticModel")
    trailModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local trailMat = Material:new()
    trailMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    trailMat:SetShaderParameter("MatDiffColor", Variant(Color(baseColor.r, baseColor.g, baseColor.b, 0.8)))
    trailMat:SetShaderParameter("Metallic", Variant(0.5))
    trailMat:SetShaderParameter("Roughness", Variant(0.3))
    trailMat:SetShaderParameter("MatEmissiveColor", Variant(Color(baseColor.r * 3, baseColor.g * 2, baseColor.b * 0.5)))
    trailModel:SetMaterial(trailMat)
    
    local trailEffect = {
        node = trailNode,
        effectType = "sparktrail",
        lifetime = 0,
        maxLifetime = 0.15,
        startScale = trailSize,
        material = trailMat,
        baseColor = baseColor,
        baseAlpha = 0.8,
    }
    table.insert(effects, trailEffect)
end

--- 创建击中闪光
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
function M.CreateHitFlash(scene, effects, hitPos)
    local flashNode = scene:CreateChild("HitFlash")
    flashNode.position = hitPos
    flashNode.scale = Vector3(0.3, 0.3, 0.3)
    
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.9, 0.6, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.5))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 6.0, 2.0)))
    model:SetMaterial(mat)
    
    local effect = {
        node = flashNode,
        effectType = "flash",
        lifetime = 0,
        maxLifetime = 0.08,
        startScale = 0.3,
        endScale = 0.5,
    }
    table.insert(effects, effect)
end

--- 创建火花粒子
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
function M.CreateSparks(scene, effects, hitPos, bulletDir)
    local sparkCount = 12
    
    for i = 1, sparkCount do
        local sparkNode = scene:CreateChild("Spark")
        sparkNode.position = hitPos
        
        local size = 0.02 + math.random() * 0.03
        sparkNode.scale = Vector3(size, size, size)
        
        local model = sparkNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        local colorVar = math.random()
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5 + colorVar * 0.4, 0.1, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(0.8))
        mat:SetShaderParameter("Roughness", Variant(0.2))
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 1.5 + colorVar, 0.2)))
        model:SetMaterial(mat)
        
        local reflectDir = bulletDir * (-1)
        local randomOffset = Vector3(
            (math.random() - 0.5) * 2,
            (math.random() - 0.5) * 2 + 0.5,
            (math.random() - 0.5) * 2
        )
        local sparkDir = (reflectDir + randomOffset):Normalized()
        local sparkSpeed = 3 + math.random() * 5
        
        local effect = {
            node = sparkNode,
            effectType = "spark",
            lifetime = 0,
            maxLifetime = 0.3 + math.random() * 0.3,
            velocity = sparkDir * sparkSpeed,
            gravity = -15,
            startScale = size,
        }
        table.insert(effects, effect)
    end
end

--- 创建烟雾效果
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
function M.CreateSmoke(scene, effects, hitPos)
    local smokeCount = 5
    
    for i = 1, smokeCount do
        local smokeNode = scene:CreateChild("Smoke")
        smokeNode.position = hitPos + Vector3(
            (math.random() - 0.5) * 0.1,
            (math.random() - 0.5) * 0.1,
            (math.random() - 0.5) * 0.1
        )
        
        local size = 0.05 + math.random() * 0.05
        smokeNode.scale = Vector3(size, size, size)
        
        local model = smokeNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        local gray = 0.3 + math.random() * 0.2
        mat:SetShaderParameter("MatDiffColor", Variant(Color(gray, gray, gray, 0.6)))
        mat:SetShaderParameter("Metallic", Variant(0.0))
        mat:SetShaderParameter("Roughness", Variant(1.0))
        model:SetMaterial(mat)
        
        local effect = {
            node = smokeNode,
            effectType = "smoke",
            lifetime = 0,
            maxLifetime = 0.5 + math.random() * 0.3,
            velocity = Vector3(
                (math.random() - 0.5) * 0.5,
                0.5 + math.random() * 0.5,
                (math.random() - 0.5) * 0.5
            ),
            startScale = size,
            endScale = size * 3,
        }
        table.insert(effects, effect)
    end
end

--- 创建弹孔效果
---@param scene Scene 场景对象
---@param effects table 特效数组
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线
function M.CreateBulletHole(scene, effects, hitPos, bulletDir, hitNormal)
    if not M.CONFIG.ShowBulletHoles then
        return
    end
    
    local normal = hitNormal or (bulletDir * (-1)):Normalized()
    local holeNode = scene:CreateChild("BulletHole")
    local holeSize = 0.05 + math.random() * 0.03
    
    holeNode.position = hitPos + normal * 0.002
    holeNode.rotation = Quaternion(Vector3.UP, normal)
    holeNode.scale = Vector3(holeSize, 0.001, holeSize)
    
    local model = holeNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    local darkness = 0.05 + math.random() * 0.05
    mat:SetShaderParameter("MatDiffColor", Variant(Color(darkness, darkness, darkness, 0.9)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.95))
    model:SetMaterial(mat)
    
    -- 焦痕边缘
    local burnNode = holeNode:CreateChild("BurnMark")
    burnNode.scale = Vector3(1.5, 1.0, 1.5)
    burnNode.position = Vector3(0, -0.5, 0)
    
    local burnModel = burnNode:CreateComponent("StaticModel")
    burnModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local burnMat = Material:new()
    burnMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    local burnColor = 0.15 + math.random() * 0.1
    burnMat:SetShaderParameter("MatDiffColor", Variant(Color(burnColor, burnColor * 0.9, burnColor * 0.8, 0.7)))
    burnMat:SetShaderParameter("Metallic", Variant(0.0))
    burnMat:SetShaderParameter("Roughness", Variant(0.9))
    burnModel:SetMaterial(burnMat)
    
    local effect = {
        node = holeNode,
        effectType = "bullethole",
        lifetime = 0,
        maxLifetime = M.CONFIG.BulletHoleLifetime + M.CONFIG.BulletHoleFadeDuration,
        fadeStartTime = M.CONFIG.BulletHoleLifetime,
        fadeDuration = M.CONFIG.BulletHoleFadeDuration,
        material = mat,
        burnMaterial = burnMat,
        baseAlpha = 0.9,
        burnBaseAlpha = 0.7,
    }
    table.insert(effects, effect)
end

--- 更新所有特效
---@param effects table 特效数组
---@param dt number 帧时间
---@param gameSpeed number|nil 游戏速度倍率（可选，默认 1.0）
function M.Update(effects, dt, gameSpeed)
    gameSpeed = gameSpeed or 1.0
    local scaledDt = dt * gameSpeed
    
    local toRemove = {}
    
    for i, effect in ipairs(effects) do
        if effect.node then
            effect.lifetime = effect.lifetime + scaledDt
            local progress = effect.lifetime / effect.maxLifetime
            
            if effect.effectType == "flash" then
                local scale = effect.startScale + (effect.endScale - effect.startScale) * progress
                effect.node.scale = Vector3(scale, scale, scale)
                
            elseif effect.effectType == "spark" then
                effect.velocity = effect.velocity + Vector3(0, effect.gravity * scaledDt, 0)
                effect.node.position = effect.node.position + effect.velocity * scaledDt
                local scale = effect.startScale * (1 - progress * 0.8)
                effect.node.scale = Vector3(scale, scale, scale)
                
            elseif effect.effectType == "smoke" then
                effect.node.position = effect.node.position + effect.velocity * scaledDt
                local scale = effect.startScale + (effect.endScale - effect.startScale) * progress
                effect.node.scale = Vector3(scale, scale, scale)
                
            elseif effect.effectType == "trailingspark" then
                effect.velocity = effect.velocity + Vector3(0, effect.gravity * scaledDt, 0)
                effect.node.position = effect.node.position + effect.velocity * scaledDt
                
                local scale = effect.startScale * (1 - progress * 0.5)
                effect.node.scale = Vector3(scale, scale, scale)
                
                -- 生成拖尾粒子
                effect.trailTimer = effect.trailTimer + scaledDt
                if effect.trailTimer >= effect.trailInterval and effect.scene and effect.effects then
                    effect.trailTimer = 0
                    M.CreateTrailParticle(effect.scene, effect.effects, effect.node.position, effect.baseColor, effect.startScale)
                end
                
            elseif effect.effectType == "sparktrail" then
                local fadeProgress = progress
                local scale = effect.startScale * (1 - fadeProgress * 0.8)
                effect.node.scale = Vector3(scale, scale, scale)
                
                if effect.material and effect.baseColor then
                    local alpha = effect.baseAlpha * (1 - fadeProgress)
                    local emissiveFade = 1 - fadeProgress
                    effect.material:SetShaderParameter("MatDiffColor", 
                        Variant(Color(effect.baseColor.r, effect.baseColor.g, effect.baseColor.b, alpha)))
                    effect.material:SetShaderParameter("MatEmissiveColor", 
                        Variant(Color(effect.baseColor.r * 3 * emissiveFade, effect.baseColor.g * 2 * emissiveFade, effect.baseColor.b * 0.5 * emissiveFade)))
                end
                
            elseif effect.effectType == "bullethole" then
                if effect.lifetime >= effect.fadeStartTime then
                    local fadeProgress = (effect.lifetime - effect.fadeStartTime) / effect.fadeDuration
                    fadeProgress = math.min(fadeProgress, 1.0)
                    
                    local currentAlpha = effect.baseAlpha * (1 - fadeProgress)
                    local burnAlpha = effect.burnBaseAlpha * (1 - fadeProgress)
                    
                    if effect.material then
                        local darkness = 0.05
                        effect.material:SetShaderParameter("MatDiffColor", 
                            Variant(Color(darkness, darkness, darkness, currentAlpha)))
                    end
                    
                    if effect.burnMaterial then
                        local burnColor = 0.15
                        effect.burnMaterial:SetShaderParameter("MatDiffColor", 
                            Variant(Color(burnColor, burnColor * 0.9, burnColor * 0.8, burnAlpha)))
                    end
                end
            end
            
            if effect.lifetime >= effect.maxLifetime then
                table.insert(toRemove, i)
                effect.node:Remove()
            end
        else
            table.insert(toRemove, i)
        end
    end
    
    -- 从后往前移除
    for i = #toRemove, 1, -1 do
        table.remove(effects, toRemove[i])
    end
end

--- 清除所有特效
---@param effects table 特效数组
function M.ClearAll(effects)
    for _, effect in ipairs(effects) do
        if effect.node then
            effect.node:Remove()
        end
    end
    -- 清空数组
    for i = #effects, 1, -1 do
        effects[i] = nil
    end
end

return M
