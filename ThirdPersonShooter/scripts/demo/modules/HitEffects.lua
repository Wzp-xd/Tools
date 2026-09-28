-- ============================================================================
-- HitEffects.lua - 击中特效系统
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Audio = require "modules.Audio"

local M = {}

local CONFIG = Config.CONFIG

--- 创建击中特效（火花飞溅 + 闪光 + 烟雾）
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
function M.CreateHitEffect(hitPos, bulletDir)
    -- 播放击中敌人音效
    Audio.PlaySfx("hit_enemy", { position = hitPos })
    
    -- 1. 创建中心闪光
    M.CreateHitFlash(hitPos)
    
    -- 2. 创建火花粒子
    M.CreateSparks(hitPos, bulletDir)
    
    -- 3. 创建烟雾效果
    M.CreateSmoke(hitPos)
end

--- 创建墙壁/柱子撞击特效（灰色火花 + 碎片 + 弹孔 + 拖尾火花）
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线（可选，默认使用子弹反方向）
function M.CreateWallHitEffect(hitPos, bulletDir, hitNormal)
    -- 播放击中墙壁音效
    Audio.PlaySfx("hit_wall", { position = hitPos })
    
    -- 创建弹孔
    M.CreateBulletHole(hitPos, bulletDir, hitNormal)
    
    -- 小型闪光
    local flashNode = GameState.scene:CreateChild("WallFlash")
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
    table.insert(GameState.effects, effect)
    
    -- 灰色碎片/尘土
    local debrisCount = 8
    for i = 1, debrisCount do
        local debrisNode = GameState.scene:CreateChild("Debris")
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
        table.insert(GameState.effects, debrisEffect)
    end
    
    -- 拖尾火花（明亮的橙黄色火花，带轨迹）
    M.CreateTrailingSparks(hitPos, bulletDir, hitNormal)
end

--- 创建拖尾火花效果（明亮火花 + 拖尾轨迹）
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线
function M.CreateTrailingSparks(hitPos, bulletDir, hitNormal)
    local sparkCount = 6 + math.random(4)  -- 6-10 个拖尾火花
    local normal = hitNormal or (bulletDir * (-1)):Normalized()
    
    for i = 1, sparkCount do
        local sparkNode = GameState.scene:CreateChild("TrailingSpark")
        sparkNode.position = hitPos
        
        -- 火花头部尺寸
        local size = 0.015 + math.random() * 0.02
        sparkNode.scale = Vector3(size, size, size)
        
        -- 火花模型（明亮的发光球）
        local sparkModel = sparkNode:CreateComponent("StaticModel")
        sparkModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        -- 明亮的橙黄色发光材质
        local colorVar = math.random()
        local sparkMat = Material:new()
        sparkMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        sparkMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.7 + colorVar * 0.3, 0.2, 1.0)))
        sparkMat:SetShaderParameter("Metallic", Variant(0.9))
        sparkMat:SetShaderParameter("Roughness", Variant(0.1))
        sparkMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 3.0 + colorVar * 2.0, 0.5)))
        sparkModel:SetMaterial(sparkMat)
        
        -- 计算反弹方向（基于法线反射 + 随机偏移）
        local reflectDir = normal
        local randomOffset = Vector3(
            (math.random() - 0.5) * 1.5,
            math.random() * 0.8 + 0.2,  -- 偏向上方
            (math.random() - 0.5) * 1.5
        )
        local sparkDir = (reflectDir + randomOffset):Normalized()
        local sparkSpeed = 4 + math.random() * 6  -- 较快的速度
        
        -- 拖尾火花效果数据
        local sparkEffect = {
            node = sparkNode,
            effectType = "trailingspark",
            lifetime = 0,
            maxLifetime = 0.4 + math.random() * 0.4,  -- 0.4-0.8秒
            velocity = sparkDir * sparkSpeed,
            gravity = -8,  -- 轻微重力
            startScale = size,
            trailTimer = 0,
            trailInterval = 0.02,  -- 每0.02秒生成一个拖尾粒子
            baseColor = { r = 1.0, g = 0.7 + colorVar * 0.3, b = 0.2 },
            emissiveIntensity = 5.0,
        }
        table.insert(GameState.effects, sparkEffect)
    end
end

--- 创建拖尾粒子（单个拖尾点）
---@param position Vector3 位置
---@param baseColor table 基础颜色 {r, g, b}
---@param size number 尺寸
function M.CreateTrailParticle(position, baseColor, size)
    local trailNode = GameState.scene:CreateChild("SparkTrail")
    trailNode.position = position
    
    local trailSize = size * 0.6  -- 拖尾比火花头小
    trailNode.scale = Vector3(trailSize, trailSize, trailSize)
    
    local trailModel = trailNode:CreateComponent("StaticModel")
    trailModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    -- 拖尾材质（半透明，逐渐变暗）
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
        maxLifetime = 0.15,  -- 拖尾快速消失
        startScale = trailSize,
        material = trailMat,
        baseColor = baseColor,
        baseAlpha = 0.8,
    }
    table.insert(GameState.effects, trailEffect)
end

--- 创建击中闪光（明亮的中心光点）
function M.CreateHitFlash(hitPos)
    local flashNode = GameState.scene:CreateChild("HitFlash")
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
    table.insert(GameState.effects, effect)
end

--- 创建火花粒子（多个小球向外飞散）
function M.CreateSparks(hitPos, bulletDir)
    local sparkCount = 12
    
    for i = 1, sparkCount do
        local sparkNode = GameState.scene:CreateChild("Spark")
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
        table.insert(GameState.effects, effect)
    end
end

--- 创建烟雾效果（多个逐渐扩散消失的灰色球体）
function M.CreateSmoke(hitPos)
    local smokeCount = 5
    
    for i = 1, smokeCount do
        local smokeNode = GameState.scene:CreateChild("Smoke")
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
        table.insert(GameState.effects, effect)
    end
end

--- 创建墙壁黑色烟雾效果（持续5秒）
---@param hitPos Vector3 击中位置
function M.CreateWallSmoke(hitPos)
    local smokeCount = 8
    
    for i = 1, smokeCount do
        local smokeNode = GameState.scene:CreateChild("WallSmoke")
        -- 初始位置在击中点附近随机偏移
        smokeNode.position = hitPos + Vector3(
            (math.random() - 0.5) * 0.15,
            (math.random() - 0.5) * 0.15,
            (math.random() - 0.5) * 0.15
        )
        
        -- 初始尺寸较小
        local size = 0.08 + math.random() * 0.06
        smokeNode.scale = Vector3(size, size, size)
        
        local model = smokeNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        
        -- 黑色/深灰色烟雾材质
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        local darkness = 0.05 + math.random() * 0.1  -- 深黑到深灰
        mat:SetShaderParameter("MatDiffColor", Variant(Color(darkness, darkness, darkness, 0.7)))
        mat:SetShaderParameter("Metallic", Variant(0.0))
        mat:SetShaderParameter("Roughness", Variant(1.0))
        model:SetMaterial(mat)
        
        -- 烟雾缓慢上升并扩散
        local effect = {
            node = smokeNode,
            effectType = "wallsmoke",
            lifetime = 0,
            maxLifetime = 4.0 + math.random() * 2.0,  -- 4-6秒（平均5秒）
            velocity = Vector3(
                (math.random() - 0.5) * 0.3,
                0.2 + math.random() * 0.3,  -- 缓慢上升
                (math.random() - 0.5) * 0.3
            ),
            startScale = size,
            endScale = size * 4,  -- 扩散到4倍大小
            material = mat,
            baseAlpha = 0.7,
        }
        table.insert(GameState.effects, effect)
    end
end

--- 创建弹孔效果（贴合表面的圆形标记，5秒后逐渐消失）
---@param hitPos Vector3 击中位置
---@param bulletDir Vector3 子弹方向
---@param hitNormal Vector3|nil 碰撞表面法线（可选）
function M.CreateBulletHole(hitPos, bulletDir, hitNormal)
    -- 检查弹孔开关
    if not CONFIG.ShowBulletHoles then
        return
    end
    
    -- 如果没有提供法线，使用子弹反方向作为近似法线
    local normal = hitNormal or (bulletDir * (-1)):Normalized()
    
    -- 创建弹孔节点
    local holeNode = GameState.scene:CreateChild("BulletHole")
    
    -- 弹孔尺寸（直径约 5-8 厘米）
    local holeSize = 0.05 + math.random() * 0.03
    
    -- 将弹孔稍微偏移出表面，避免 z-fighting
    holeNode.position = hitPos + normal * 0.002
    
    -- 使弹孔朝向法线方向（使用扁平圆柱体）
    -- 圆柱体默认沿 Y 轴，需要旋转使其沿法线方向
    holeNode.rotation = Quaternion(Vector3.UP, normal)
    
    -- 缩放：XZ 平面为弹孔大小，Y 为厚度（非常薄）
    holeNode.scale = Vector3(holeSize, 0.001, holeSize)
    
    -- 添加圆柱体模型作为弹孔
    local model = holeNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    -- 创建弹孔材质（深色，带一点焦痕效果）
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    
    -- 弹孔颜色：深灰到黑色，中心更深
    local darkness = 0.05 + math.random() * 0.05
    mat:SetShaderParameter("MatDiffColor", Variant(Color(darkness, darkness, darkness, 0.9)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.95))
    model:SetMaterial(mat)
    
    -- 添加焦痕边缘（稍大一点的浅色环）
    local burnNode = holeNode:CreateChild("BurnMark")
    burnNode.scale = Vector3(1.5, 1.0, 1.5)  -- 相对于父节点放大
    burnNode.position = Vector3(0, -0.5, 0)   -- 稍微向后偏移避免重叠
    
    local burnModel = burnNode:CreateComponent("StaticModel")
    burnModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local burnMat = Material:new()
    burnMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    local burnColor = 0.15 + math.random() * 0.1
    burnMat:SetShaderParameter("MatDiffColor", Variant(Color(burnColor, burnColor * 0.9, burnColor * 0.8, 0.7)))
    burnMat:SetShaderParameter("Metallic", Variant(0.0))
    burnMat:SetShaderParameter("Roughness", Variant(0.9))
    burnModel:SetMaterial(burnMat)
    
    -- 弹孔特效数据
    local effect = {
        node = holeNode,
        effectType = "bullethole",
        lifetime = 0,
        maxLifetime = 5.0,           -- 5秒后开始消失
        fadeStartTime = 5.0,         -- 开始淡出的时间
        fadeDuration = 1.0,          -- 淡出持续时间
        material = mat,              -- 保存材质引用用于修改透明度
        burnMaterial = burnMat,      -- 焦痕材质
        baseAlpha = 0.9,             -- 基础透明度
        burnBaseAlpha = 0.7,         -- 焦痕基础透明度
    }
    table.insert(GameState.effects, effect)
end

--- 更新所有特效
function M.Update(dt)
    -- 获取游戏速度（子弹时间等功能）
    local gameSpeed = GameState.gameSpeed or 1.0
    local scaledDt = dt * gameSpeed
    
    local toRemove = {}
    
    for i, effect in ipairs(GameState.effects) do
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
                
            elseif effect.effectType == "wallsmoke" then
                -- 黑色烟雾：缓慢上升、扩散、逐渐淡出
                effect.node.position = effect.node.position + effect.velocity * scaledDt
                
                -- 烟雾扩散
                local scale = effect.startScale + (effect.endScale - effect.startScale) * progress
                effect.node.scale = Vector3(scale, scale, scale)
                
                -- 逐渐淡出（后半段开始淡出）
                if progress > 0.3 then
                    local fadeProgress = (progress - 0.3) / 0.7  -- 0到1
                    local currentAlpha = effect.baseAlpha * (1 - fadeProgress)
                    if effect.material then
                        local darkness = 0.08
                        effect.material:SetShaderParameter("MatDiffColor", 
                            Variant(Color(darkness, darkness, darkness, currentAlpha)))
                    end
                end
            
            elseif effect.effectType == "trailingspark" then
                -- 拖尾火花：移动 + 重力 + 生成拖尾粒子
                effect.velocity = effect.velocity + Vector3(0, effect.gravity * scaledDt, 0)
                effect.node.position = effect.node.position + effect.velocity * scaledDt
                
                -- 火花逐渐变小
                local scale = effect.startScale * (1 - progress * 0.5)
                effect.node.scale = Vector3(scale, scale, scale)
                
                -- 生成拖尾粒子
                effect.trailTimer = effect.trailTimer + scaledDt
                if effect.trailTimer >= effect.trailInterval then
                    effect.trailTimer = 0
                    M.CreateTrailParticle(effect.node.position, effect.baseColor, effect.startScale)
                end
            
            elseif effect.effectType == "sparktrail" then
                -- 拖尾粒子：快速淡出并缩小
                local fadeProgress = progress
                local scale = effect.startScale * (1 - fadeProgress * 0.8)
                effect.node.scale = Vector3(scale, scale, scale)
                
                -- 更新透明度和发光强度
                if effect.material and effect.baseColor then
                    local alpha = effect.baseAlpha * (1 - fadeProgress)
                    local emissiveFade = 1 - fadeProgress
                    effect.material:SetShaderParameter("MatDiffColor", 
                        Variant(Color(effect.baseColor.r, effect.baseColor.g, effect.baseColor.b, alpha)))
                    effect.material:SetShaderParameter("MatEmissiveColor", 
                        Variant(Color(effect.baseColor.r * 3 * emissiveFade, effect.baseColor.g * 2 * emissiveFade, effect.baseColor.b * 0.5 * emissiveFade)))
                end
                
            elseif effect.effectType == "bullethole" then
                -- 弹孔效果：5秒后开始淡出
                local totalLifetime = effect.fadeStartTime + effect.fadeDuration
                
                if effect.lifetime >= effect.fadeStartTime then
                    -- 计算淡出进度 (0 -> 1)
                    local fadeProgress = (effect.lifetime - effect.fadeStartTime) / effect.fadeDuration
                    fadeProgress = math.min(fadeProgress, 1.0)
                    
                    -- 计算当前透明度
                    local currentAlpha = effect.baseAlpha * (1 - fadeProgress)
                    local burnAlpha = effect.burnBaseAlpha * (1 - fadeProgress)
                    
                    -- 更新弹孔材质透明度
                    if effect.material then
                        local darkness = 0.05
                        effect.material:SetShaderParameter("MatDiffColor", 
                            Variant(Color(darkness, darkness, darkness, currentAlpha)))
                    end
                    
                    -- 更新焦痕材质透明度
                    if effect.burnMaterial then
                        local burnColor = 0.15
                        effect.burnMaterial:SetShaderParameter("MatDiffColor", 
                            Variant(Color(burnColor, burnColor * 0.9, burnColor * 0.8, burnAlpha)))
                    end
                end
                
                -- 完全淡出后移除
                if effect.lifetime >= totalLifetime then
                    table.insert(toRemove, i)
                    effect.node:Remove()
                end
                -- 跳过下面的通用 maxLifetime 检查
                goto continue
            end
            
            if effect.lifetime >= effect.maxLifetime then
                table.insert(toRemove, i)
                effect.node:Remove()
            end
        else
            table.insert(toRemove, i)
        end
        ::continue::
    end
    
    for i = #toRemove, 1, -1 do
        table.remove(GameState.effects, toRemove[i])
    end
end

--- 清除所有特效
function M.ClearAll()
    for _, effect in ipairs(GameState.effects) do
        if effect.node then
            effect.node:Remove()
        end
    end
    GameState.effects = {}
end

return M
