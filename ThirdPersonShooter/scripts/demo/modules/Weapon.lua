-- ============================================================================
-- Weapon.lua - 武器系统
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Audio = require "modules.Audio"

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
local WEAPONS = Config.WEAPONS
local WEAPON_ORDER = Config.WEAPON_ORDER

--- 递归为节点及其所有子节点的 StaticModel 启用阴影
---@param node Node
local function EnableShadowsRecursive(node)
    if not node then return end
    
    -- 为当前节点的 StaticModel 启用阴影
    local model = node:GetComponent("StaticModel")
    if model then
        model.castShadows = true
    end
    
    -- 递归处理所有子节点
    for i = 0, node:GetNumChildren() - 1 do
        EnableShadowsRecursive(node:GetChild(i))
    end
end

--- 创建枪口调试球（红色球体显示发射位置）
local function CreateMuzzleDebugSphere()
    if not CONFIG.DebugShowMuzzlePosition then return end
    if not GameState.muzzleNode then return end
    
    -- 移除旧的调试球
    local oldDebug = GameState.muzzleNode:GetChild("MuzzleDebug")
    if oldDebug then
        oldDebug:Remove()
    end
    
    -- 创建红色调试球
    local debugNode = GameState.muzzleNode:CreateChild("MuzzleDebug")
    debugNode.scale = Vector3(0.05, 0.05, 0.05)  -- 5cm 直径的球
    
    local model = debugNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.0, 0.0, 0.7)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(2.0, 0.0, 0.0)))
    model:SetMaterial(mat)
end

--- 创建手持武器模型
function M.CreateGun()
    -- 枪挂载在相机节点下
    GameState.gunNode = GameState.cameraNode:CreateChild("Gun")
    
    -- 根据左右手设置初始位置
    M.UpdateGunHandedness()
    
    -- 初始构建使用默认武器（手枪）
    M.BuildGunModel(WEAPONS["pistol"])
    
    print("Gun created, handedness: " .. (GameState.isLeftHanded and "Left" or "Right"))
end

--- 根据武器配置构建枪械模型
--- @param weapon table 武器配置
function M.BuildGunModel(weapon)
    if not GameState.gunNode then return end
    if not weapon or not weapon.model then return end
    
    -- 清除现有的子节点（除了位置信息）
    local children = {}
    for i = 0, GameState.gunNode:GetNumChildren() - 1 do
        table.insert(children, GameState.gunNode:GetChild(i))
    end
    for _, child in ipairs(children) do
        child:Remove()
    end
    
    local m = weapon.model
    
    -- ========== Prefab 模型加载 ==========
    if m.isPrefab then
        -- 使用 Scene:Instantiate 加载 prefab
        local prefabNode = GameState.scene:Instantiate(m.prefabPath, Vector3.ZERO, Quaternion.IDENTITY)
        if prefabNode then
            -- 将 prefab 作为 gunNode 的子节点
            prefabNode:SetParent(GameState.gunNode)
            prefabNode.name = "PrefabModel"
            
            -- 应用缩放
            if m.scale then
                prefabNode.scale = m.scale
            end
            
            -- 应用位置偏移
            if m.positionOffset then
                prefabNode.position = m.positionOffset
            end
            
            -- 应用旋转偏移
            if m.rotationOffset then
                prefabNode.rotation = m.rotationOffset
            end
            
            -- 为 prefab 中所有 StaticModel 启用阴影
            EnableShadowsRecursive(prefabNode)
            
            -- 创建枪口节点（作为 prefabNode 的子节点，继承其变换）
            GameState.muzzleNode = prefabNode:CreateChild("Muzzle")
            if m.muzzleOffset then
                GameState.muzzleNode.position = m.muzzleOffset
            else
                GameState.muzzleNode.position = Vector3(0, 0, 0.5)
            end
            
            -- 创建枪口调试球
            CreateMuzzleDebugSphere()
            
            print("Prefab gun model loaded: " .. weapon.nameZh .. ", muzzle at: " .. tostring(GameState.muzzleNode.position))
        else
            print("Error: Failed to load prefab: " .. tostring(m.prefabPath))
        end
        return
    end
    
    -- 非 prefab 模型：创建模型容器节点（支持位置偏移）
    local modelContainer = GameState.gunNode:CreateChild("ModelContainer")
    if m.positionOffset then
        modelContainer.position = m.positionOffset
    end
    
    -- 创建枪身材质
    local gunMat = Material:new()
    
    -- 如果有贴图，使用带贴图的 PBR 材质
    if m.hasTexture and m.textureFile then
        local texture = cache:GetResource("Texture2D", m.textureFile)
        if texture then
            texture:SetFilterMode(FILTER_TRILINEAR)
            gunMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRDiff.xml"))
            gunMat:SetTexture(TU_DIFFUSE, texture)
            gunMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
            print("Loaded texture: " .. m.textureFile)
        else
            gunMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
            gunMat:SetShaderParameter("MatDiffColor", Variant(m.color))
            print("Failed to load texture: " .. m.textureFile)
        end
    else
        gunMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        gunMat:SetShaderParameter("MatDiffColor", Variant(m.color))
    end
    gunMat:SetShaderParameter("Metallic", Variant(0.9))
    gunMat:SetShaderParameter("Roughness", Variant(0.3))
    
    -- 强调色材质（木纹/握把）
    local accentMat = Material:new()
    accentMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    accentMat:SetShaderParameter("MatDiffColor", Variant(m.accentColor))
    accentMat:SetShaderParameter("Metallic", Variant(0.1))
    accentMat:SetShaderParameter("Roughness", Variant(0.7))
    
    -- 枪身主体
    local bodyNode = modelContainer:CreateChild("Body")
    bodyNode.scale = Vector3(m.bodyWidth, m.bodyHeight, m.bodyLength)
    bodyNode.position = Vector3(0, 0, m.bodyLength / 2)
    
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bodyModel:SetMaterial(gunMat)
    bodyModel.castShadows = true
    
    -- 枪管
    local barrelStartZ = m.bodyLength
    if m.isDoubleBarrel then
        -- 霰弹枪双管
        for i = -1, 1, 2 do
            local barrelNode = modelContainer:CreateChild("Barrel" .. i)
            -- 圆柱体旋转90°后，Y轴变为Z方向，所以Y=长度，X和Z=直径
            barrelNode.scale = Vector3(m.barrelRadius * 2, m.barrelLength, m.barrelRadius * 2)
            barrelNode.position = Vector3(i * m.barrelSpacing, m.bodyHeight * 0.2, barrelStartZ + m.barrelLength / 2)
            barrelNode.rotation = Quaternion(90, Vector3.RIGHT)
            
            local barrelModel = barrelNode:CreateComponent("StaticModel")
            barrelModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            barrelModel:SetMaterial(gunMat)
            barrelModel.castShadows = true
        end
    else
        -- 单管
        local barrelNode = modelContainer:CreateChild("Barrel")
        -- 圆柱体旋转90°后，Y轴变为Z方向，所以Y=长度，X和Z=直径
        barrelNode.scale = Vector3(m.barrelRadius * 2, m.barrelLength, m.barrelRadius * 2)
        barrelNode.position = Vector3(0, m.bodyHeight * 0.2, barrelStartZ + m.barrelLength / 2)
        barrelNode.rotation = Quaternion(90, Vector3.RIGHT)
        
        local barrelModel = barrelNode:CreateComponent("StaticModel")
        barrelModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        barrelModel:SetMaterial(gunMat)
        barrelModel.castShadows = true
    end
    
    -- 握把
    local gripNode = modelContainer:CreateChild("Grip")
    gripNode.scale = Vector3(m.gripWidth, m.gripHeight, m.gripWidth * 1.5)
    gripNode.position = Vector3(0, -m.gripHeight / 2 - m.bodyHeight / 2 + 0.02, 0.02)
    gripNode.rotation = Quaternion(-15, Vector3.RIGHT)
    
    local gripModel = gripNode:CreateComponent("StaticModel")
    gripModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    gripModel:SetMaterial(accentMat)
    gripModel.castShadows = true
    
    -- 枪托（如果有）
    if m.hasStock then
        local stockNode = modelContainer:CreateChild("Stock")
        stockNode.scale = Vector3(m.bodyWidth * 0.8, m.bodyHeight * 1.2, m.stockLength)
        stockNode.position = Vector3(0, -m.bodyHeight * 0.1, -m.stockLength / 2)
        
        local stockModel = stockNode:CreateComponent("StaticModel")
        stockModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        stockModel:SetMaterial(accentMat)
        stockModel.castShadows = true
    end
    
    -- 弹匣（如果有）
    if m.hasMagazine then
        local magNode = modelContainer:CreateChild("Magazine")
        magNode.scale = Vector3(m.magWidth, m.magHeight, m.magWidth * 1.5)
        magNode.position = Vector3(0, -m.magHeight / 2 - m.bodyHeight / 2, m.bodyLength * 0.4)
        
        local magModel = magNode:CreateComponent("StaticModel")
        magModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        magModel:SetMaterial(gunMat)
        magModel.castShadows = true
    end
    
    -- ========== AK47 特有细节组件 ==========
    if m.isAK47 then
        -- 创建金属材质（用于机匣、导气管等）
        local metalMat = Material:new()
        metalMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        metalMat:SetShaderParameter("MatDiffColor", Variant(m.metalColor or Color(0.06, 0.06, 0.07, 1.0)))
        metalMat:SetShaderParameter("Metallic", Variant(0.95))
        metalMat:SetShaderParameter("Roughness", Variant(0.25))
        
        -- 钢色材质（枪管、机匣）
        local steelMat = Material:new()
        steelMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        steelMat:SetShaderParameter("MatDiffColor", Variant(m.steelColor or Color(0.18, 0.18, 0.20, 1.0)))
        steelMat:SetShaderParameter("Metallic", Variant(0.85))
        steelMat:SetShaderParameter("Roughness", Variant(0.35))
        
        -- 黄铜材质（子弹可见部分、装饰）
        local brassMat = Material:new()
        brassMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        brassMat:SetShaderParameter("MatDiffColor", Variant(m.brassColor or Color(0.72, 0.45, 0.20, 1.0)))
        brassMat:SetShaderParameter("Metallic", Variant(0.9))
        brassMat:SetShaderParameter("Roughness", Variant(0.3))
        
        -- 深木材质（握把）
        local darkWoodMat = Material:new()
        darkWoodMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        darkWoodMat:SetShaderParameter("MatDiffColor", Variant(m.darkWoodColor or Color(0.35, 0.20, 0.10, 1.0)))
        darkWoodMat:SetShaderParameter("Metallic", Variant(0.05))
        darkWoodMat:SetShaderParameter("Roughness", Variant(0.75))
        
        -- 橡胶材质（枪托垫）
        local rubberMat = Material:new()
        rubberMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        rubberMat:SetShaderParameter("MatDiffColor", Variant(m.rubberColor or Color(0.08, 0.08, 0.08, 1.0)))
        rubberMat:SetShaderParameter("Metallic", Variant(0.0))
        rubberMat:SetShaderParameter("Roughness", Variant(0.9))
        
        -- 1. 机匣盖（Receiver Cover）- 枪身上方的金属盖
        if m.hasReceiverCover then
            local coverNode = modelContainer:CreateChild("ReceiverCover")
            local coverLength = m.receiverCoverLength or 0.20
            coverNode.scale = Vector3(m.bodyWidth * 0.9, 0.018, coverLength)
            coverNode.position = Vector3(0, m.bodyHeight / 2 + 0.012, m.bodyLength * 0.35)
            
            local coverModel = coverNode:CreateComponent("StaticModel")
            coverModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            coverModel:SetMaterial(metalMat)
            coverModel.castShadows = true
            
            -- 机匣盖上的棱线装饰
            for i = -1, 1, 2 do
                local ridgeNode = modelContainer:CreateChild("CoverRidge" .. i)
                ridgeNode.scale = Vector3(0.004, 0.008, coverLength * 0.8)
                ridgeNode.position = Vector3(i * m.bodyWidth * 0.35, m.bodyHeight / 2 + 0.025, m.bodyLength * 0.35)
                
                local ridgeModel = ridgeNode:CreateComponent("StaticModel")
                ridgeModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                ridgeModel:SetMaterial(metalMat)
            end
        end
        
        -- 2. 护木（Handguard）- 枪管下方的木质护手
        if m.hasHandguard then
            local handguardLength = m.handguardLength or 0.18
            local handguardNode = modelContainer:CreateChild("Handguard")
            handguardNode.scale = Vector3(m.bodyWidth * 1.1, 0.045, handguardLength)
            handguardNode.position = Vector3(0, m.bodyHeight * 0.1, m.bodyLength + handguardLength * 0.4)
            
            local handguardModel = handguardNode:CreateComponent("StaticModel")
            handguardModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            handguardModel:SetMaterial(accentMat)  -- 木纹材质
            handguardModel.castShadows = true
            
            -- 护木上的散热槽装饰
            for i = 1, 3 do
                local slotNode = modelContainer:CreateChild("HandguardSlot" .. i)
                slotNode.scale = Vector3(m.bodyWidth * 1.15, 0.008, 0.015)
                slotNode.position = Vector3(0, m.bodyHeight * 0.1 + 0.028, m.bodyLength + handguardLength * 0.2 + i * 0.035)
                
                local slotModel = slotNode:CreateComponent("StaticModel")
                slotModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                slotModel:SetMaterial(metalMat)
            end
        end
        
        -- 3. 导气管座（Gas Block）- 枪管上方的凸起
        if m.hasGasBlock then
            local gasBlockPos = m.gasBlockPos or 0.65
            local gasBlockZ = m.bodyLength + m.barrelLength * gasBlockPos
            
            -- 导气管座主体
            local gasBlockNode = modelContainer:CreateChild("GasBlock")
            gasBlockNode.scale = Vector3(0.025, m.gasBlockHeight or 0.025, 0.035)
            gasBlockNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius + 0.012, gasBlockZ)
            
            local gasBlockModel = gasBlockNode:CreateComponent("StaticModel")
            gasBlockModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            gasBlockModel:SetMaterial(metalMat)
            gasBlockNode.castShadows = true
            
            -- 导气管（连接导气管座到机匣）
            local gasTubeNode = modelContainer:CreateChild("GasTube")
            local gasTubeLength = gasBlockZ - m.bodyLength - 0.02
            gasTubeNode.scale = Vector3(0.008, 0.008, gasTubeLength)
            gasTubeNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius + 0.02, m.bodyLength + gasTubeLength / 2 + 0.01)
            
            local gasTubeModel = gasTubeNode:CreateComponent("StaticModel")
            gasTubeModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            gasTubeModel:SetMaterial(metalMat)
        end
        
        -- 4. 准星（Front Sight）- 枪管前端的瞄准器
        if m.hasFrontSight then
            local frontSightZ = m.bodyLength + m.barrelLength * 0.9
            local frontSightHeight = m.frontSightHeight or 0.035
            
            -- 准星底座
            local frontSightBaseNode = modelContainer:CreateChild("FrontSightBase")
            frontSightBaseNode.scale = Vector3(0.025, 0.015, 0.025)
            frontSightBaseNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius + 0.008, frontSightZ)
            
            local frontSightBaseModel = frontSightBaseNode:CreateComponent("StaticModel")
            frontSightBaseModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            frontSightBaseModel:SetMaterial(metalMat)
            
            -- 准星立柱
            local frontSightPostNode = modelContainer:CreateChild("FrontSightPost")
            frontSightPostNode.scale = Vector3(0.006, frontSightHeight, 0.006)
            frontSightPostNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius + 0.015 + frontSightHeight / 2, frontSightZ)
            
            local frontSightPostModel = frontSightPostNode:CreateComponent("StaticModel")
            frontSightPostModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            frontSightPostModel:SetMaterial(metalMat)
            
            -- 准星尖端
            local frontSightTipNode = modelContainer:CreateChild("FrontSightTip")
            frontSightTipNode.scale = Vector3(0.004, 0.012, 0.004)
            frontSightTipNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius + 0.015 + frontSightHeight + 0.006, frontSightZ)
            
            local frontSightTipModel = frontSightTipNode:CreateComponent("StaticModel")
            frontSightTipModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            frontSightTipModel:SetMaterial(metalMat)
            
            -- 准星保护翼（两侧）
            for i = -1, 1, 2 do
                local wingNode = modelContainer:CreateChild("FrontSightWing" .. i)
                wingNode.scale = Vector3(0.004, frontSightHeight * 0.7, 0.012)
                wingNode.position = Vector3(i * 0.012, m.bodyHeight * 0.2 + m.barrelRadius + 0.015 + frontSightHeight * 0.35, frontSightZ)
                
                local wingModel = wingNode:CreateComponent("StaticModel")
                wingModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                wingModel:SetMaterial(metalMat)
            end
        end
        
        -- 5. 照门（Rear Sight）- 机匣后部的瞄准器
        if m.hasRearSight then
            local rearSightZ = m.bodyLength * (1 - (m.rearSightPos or 0.15))
            local rearSightHeight = m.rearSightHeight or 0.025
            
            -- 照门底座
            local rearSightBaseNode = modelContainer:CreateChild("RearSightBase")
            rearSightBaseNode.scale = Vector3(0.035, 0.012, 0.025)
            rearSightBaseNode.position = Vector3(0, m.bodyHeight / 2 + 0.032, rearSightZ)
            
            local rearSightBaseModel = rearSightBaseNode:CreateComponent("StaticModel")
            rearSightBaseModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            rearSightBaseModel:SetMaterial(metalMat)
            
            -- 照门叶片（U型缺口的两侧）
            for i = -1, 1, 2 do
                local leafNode = modelContainer:CreateChild("RearSightLeaf" .. i)
                leafNode.scale = Vector3(0.004, rearSightHeight, 0.015)
                leafNode.position = Vector3(i * 0.010, m.bodyHeight / 2 + 0.038 + rearSightHeight / 2, rearSightZ)
                
                local leafModel = leafNode:CreateComponent("StaticModel")
                leafModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                leafModel:SetMaterial(metalMat)
            end
        end
        
        -- 6. 枪口制退器（Muzzle Brake）
        if m.hasMuzzleBrake then
            local muzzleZ = m.bodyLength + m.barrelLength
            local brakeLength = m.muzzleBrakeLength or 0.04
            
            -- 制退器主体（比枪管略粗）
            local brakeNode = modelContainer:CreateChild("MuzzleBrake")
            brakeNode.scale = Vector3(m.barrelRadius * 3.5, brakeLength, m.barrelRadius * 3.5)
            brakeNode.position = Vector3(0, m.bodyHeight * 0.2, muzzleZ + brakeLength / 2)
            brakeNode.rotation = Quaternion(90, Vector3.RIGHT)
            
            local brakeModel = brakeNode:CreateComponent("StaticModel")
            brakeModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            brakeModel:SetMaterial(metalMat)
            brakeModel.castShadows = true
            
            -- 制退器开口（斜向上的切口装饰）
            for i = 1, 2 do
                local slotNode = modelContainer:CreateChild("BrakeSlot" .. i)
                slotNode.scale = Vector3(m.barrelRadius * 4, 0.006, 0.012)
                slotNode.position = Vector3(0, m.bodyHeight * 0.2 + m.barrelRadius * 1.2, muzzleZ + i * 0.012)
                slotNode.rotation = Quaternion(15, Vector3.FORWARD)
                
                local slotModel = slotNode:CreateComponent("StaticModel")
                slotModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                slotModel:SetMaterial(gunMat)  -- 用枪身颜色显示槽口
            end
        end
        
        -- 7. 枪身侧面凸起（选择开关、拉机柄等细节）
        -- 拉机柄（右侧）
        local chargingHandleNode = modelContainer:CreateChild("ChargingHandle")
        chargingHandleNode.scale = Vector3(0.025, 0.012, 0.018)
        chargingHandleNode.position = Vector3(m.bodyWidth / 2 + 0.012, m.bodyHeight * 0.3, m.bodyLength * 0.45)
        
        local chargingHandleModel = chargingHandleNode:CreateComponent("StaticModel")
        chargingHandleModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        chargingHandleModel:SetMaterial(metalMat)
        
        -- 快慢机（左侧）
        local selectorNode = modelContainer:CreateChild("Selector")
        selectorNode.scale = Vector3(0.035, 0.008, 0.012)
        selectorNode.position = Vector3(-m.bodyWidth / 2 - 0.008, m.bodyHeight * 0.2, m.bodyLength * 0.3)
        
        local selectorModel = selectorNode:CreateComponent("StaticModel")
        selectorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        selectorModel:SetMaterial(metalMat)
        
        -- 弹匣卡笋
        local magReleaseNode = modelContainer:CreateChild("MagRelease")
        magReleaseNode.scale = Vector3(0.015, 0.015, 0.008)
        magReleaseNode.position = Vector3(m.bodyWidth / 2 + 0.005, -m.bodyHeight * 0.3, m.bodyLength * 0.42)
        
        local magReleaseModel = magReleaseNode:CreateComponent("StaticModel")
        magReleaseModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        magReleaseModel:SetMaterial(metalMat)
        
        -- 8. 扳机和扳机护圈
        if m.hasTrigger then
            -- 扳机护圈（环形保护）
            local triggerGuardNode = modelContainer:CreateChild("TriggerGuard")
            triggerGuardNode.scale = Vector3(0.008, 0.035, 0.05)
            triggerGuardNode.position = Vector3(0, -m.bodyHeight / 2 - 0.02, m.bodyLength * 0.25)
            
            local triggerGuardModel = triggerGuardNode:CreateComponent("StaticModel")
            triggerGuardModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            triggerGuardModel:SetMaterial(metalMat)
            
            -- 扳机护圈底部
            local triggerGuardBottomNode = modelContainer:CreateChild("TriggerGuardBottom")
            triggerGuardBottomNode.scale = Vector3(0.008, 0.008, 0.04)
            triggerGuardBottomNode.position = Vector3(0, -m.bodyHeight / 2 - 0.035, m.bodyLength * 0.25)
            
            local triggerGuardBottomModel = triggerGuardBottomNode:CreateComponent("StaticModel")
            triggerGuardBottomModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            triggerGuardBottomModel:SetMaterial(metalMat)
            
            -- 扳机本体
            local triggerNode = modelContainer:CreateChild("Trigger")
            triggerNode.scale = Vector3(0.006, 0.022, 0.012)
            triggerNode.position = Vector3(0, -m.bodyHeight / 2 - 0.015, m.bodyLength * 0.25)
            triggerNode.rotation = Quaternion(-20, Vector3.RIGHT)  -- 略微倾斜
            
            local triggerModel = triggerNode:CreateComponent("StaticModel")
            triggerModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            triggerModel:SetMaterial(brassMat)  -- 黄铜色扳机
        end
        
        -- 9. 抛壳口
        if m.hasEjectionPort then
            -- 抛壳口凹槽（右侧）
            local ejectionPortNode = modelContainer:CreateChild("EjectionPort")
            ejectionPortNode.scale = Vector3(0.006, 0.025, 0.04)
            ejectionPortNode.position = Vector3(m.bodyWidth / 2 + 0.002, m.bodyHeight * 0.15, m.bodyLength * 0.55)
            
            local ejectionPortModel = ejectionPortNode:CreateComponent("StaticModel")
            ejectionPortModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            ejectionPortModel:SetMaterial(steelMat)  -- 钢色内部
            
            -- 抛壳口边框上
            local ejectionTopNode = modelContainer:CreateChild("EjectionTop")
            ejectionTopNode.scale = Vector3(0.008, 0.006, 0.045)
            ejectionTopNode.position = Vector3(m.bodyWidth / 2 + 0.003, m.bodyHeight * 0.3, m.bodyLength * 0.55)
            
            local ejectionTopModel = ejectionTopNode:CreateComponent("StaticModel")
            ejectionTopModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            ejectionTopModel:SetMaterial(metalMat)
            
            -- 可见的黄铜子弹（在抛壳口内）
            local bulletVisibleNode = modelContainer:CreateChild("BulletVisible")
            bulletVisibleNode.scale = Vector3(0.008, 0.008, 0.025)
            bulletVisibleNode.position = Vector3(m.bodyWidth / 2 - 0.005, m.bodyHeight * 0.12, m.bodyLength * 0.55)
            
            local bulletVisibleModel = bulletVisibleNode:CreateComponent("StaticModel")
            bulletVisibleModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            bulletVisibleModel:SetMaterial(brassMat)  -- 黄铜色子弹
        end
        
        -- 10. 枪托细节
        if m.hasStock and m.hasStockDetails then
            -- 枪托垫（橡胶）
            local buttpadNode = modelContainer:CreateChild("Buttpad")
            buttpadNode.scale = Vector3(m.bodyWidth * 0.85, m.bodyHeight * 1.3, 0.015)
            buttpadNode.position = Vector3(0, -m.bodyHeight * 0.1, -(m.stockLength or 0.18) - 0.008)
            
            local buttpadModel = buttpadNode:CreateComponent("StaticModel")
            buttpadModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            buttpadModel:SetMaterial(rubberMat)  -- 橡胶材质
            
            -- 枪托上的金属加强片
            local stockPlateNode = modelContainer:CreateChild("StockPlate")
            stockPlateNode.scale = Vector3(0.035, 0.008, (m.stockLength or 0.18) * 0.6)
            stockPlateNode.position = Vector3(0, m.bodyHeight * 0.4, -(m.stockLength or 0.18) * 0.35)
            
            local stockPlateModel = stockPlateNode:CreateComponent("StaticModel")
            stockPlateModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            stockPlateModel:SetMaterial(metalMat)
            
            -- 枪托侧面装饰线（两侧）
            for i = -1, 1, 2 do
                local stockLineNode = modelContainer:CreateChild("StockLine" .. i)
                stockLineNode.scale = Vector3(0.004, 0.015, (m.stockLength or 0.18) * 0.7)
                stockLineNode.position = Vector3(i * m.bodyWidth * 0.35, 0, -(m.stockLength or 0.18) * 0.4)
                
                local stockLineModel = stockLineNode:CreateComponent("StaticModel")
                stockLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                stockLineModel:SetMaterial(darkWoodMat)  -- 深木色
            end
        end
        
        -- 11. 背带环
        if m.hasSlingMount then
            -- 前背带环（枪管下方）
            local frontSlingNode = modelContainer:CreateChild("FrontSling")
            frontSlingNode.scale = Vector3(0.012, 0.018, 0.008)
            frontSlingNode.position = Vector3(0, -0.02, m.bodyLength + 0.08)
            
            local frontSlingModel = frontSlingNode:CreateComponent("StaticModel")
            frontSlingModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            frontSlingModel:SetMaterial(metalMat)
            
            -- 后背带环（枪托底部）
            local rearSlingNode = modelContainer:CreateChild("RearSling")
            rearSlingNode.scale = Vector3(0.012, 0.018, 0.008)
            rearSlingNode.position = Vector3(0, -m.bodyHeight * 0.8, -(m.stockLength or 0.18) * 0.7)
            
            local rearSlingModel = rearSlingNode:CreateComponent("StaticModel")
            rearSlingModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            rearSlingModel:SetMaterial(metalMat)
        end
        
        -- 12. 弯曲弹匣增强（AK47特有的弧形弹匣）
        if m.hasCurvedMag and m.hasMagazine then
            -- 弹匣前端突出部分（模拟弧度）
            local magFrontNode = modelContainer:CreateChild("MagFront")
            magFrontNode.scale = Vector3(m.magWidth * 0.9, m.magHeight * 0.3, m.magWidth * 0.8)
            magFrontNode.position = Vector3(0, -m.magHeight * 0.7 - m.bodyHeight / 2, m.bodyLength * 0.4 + m.magWidth * 0.8)
            magFrontNode.rotation = Quaternion(-15, Vector3.RIGHT)
            
            local magFrontModel = magFrontNode:CreateComponent("StaticModel")
            magFrontModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            magFrontModel:SetMaterial(steelMat)  -- 钢色弹匣
            
            -- 弹匣底部加强筋
            local magRibNode = modelContainer:CreateChild("MagRib")
            magRibNode.scale = Vector3(m.magWidth * 1.05, 0.008, m.magWidth * 1.2)
            magRibNode.position = Vector3(0, -m.magHeight - m.bodyHeight / 2 + 0.01, m.bodyLength * 0.4)
            
            local magRibModel = magRibNode:CreateComponent("StaticModel")
            magRibModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            magRibModel:SetMaterial(metalMat)
            
            -- 弹匣可见子弹（顶部）
            local magBulletNode = modelContainer:CreateChild("MagBullet")
            magBulletNode.scale = Vector3(0.006, 0.006, 0.018)
            magBulletNode.position = Vector3(0, -m.bodyHeight / 2 - 0.01, m.bodyLength * 0.4)
            
            local magBulletModel = magBulletNode:CreateComponent("StaticModel")
            magBulletModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            magBulletModel:SetMaterial(brassMat)  -- 黄铜色子弹
        end
        
        -- 13. 握把纹理细节
        -- 握把侧面防滑纹（两侧）
        for i = -1, 1, 2 do
            for j = 1, 4 do
                local gripLineNode = modelContainer:CreateChild("GripLine" .. i .. "_" .. j)
                gripLineNode.scale = Vector3(0.003, 0.012, 0.004)
                gripLineNode.position = Vector3(
                    i * (m.gripWidth / 2 + 0.001),
                    -m.gripHeight / 2 - m.bodyHeight / 2 + 0.02 - j * 0.015,
                    0.02
                )
                
                local gripLineModel = gripLineNode:CreateComponent("StaticModel")
                gripLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                gripLineModel:SetMaterial(darkWoodMat)
            end
        end
        
        -- 14. 枪身装饰细节
        -- 枪身侧面螺丝/铆钉装饰
        for i = -1, 1, 2 do
            local rivetNode = modelContainer:CreateChild("Rivet" .. i)
            rivetNode.scale = Vector3(0.006, 0.006, 0.003)
            rivetNode.position = Vector3(i * (m.bodyWidth / 2 + 0.002), m.bodyHeight * 0.1, m.bodyLength * 0.6)
            
            local rivetModel = rivetNode:CreateComponent("StaticModel")
            rivetModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            rivetModel:SetMaterial(brassMat)  -- 黄铜色铆钉
        end
        
        -- 枪身顶部加强筋
        local topRibNode = modelContainer:CreateChild("TopRib")
        topRibNode.scale = Vector3(0.008, 0.006, m.bodyLength * 0.4)
        topRibNode.position = Vector3(0, m.bodyHeight / 2 + 0.003, m.bodyLength * 0.65)
        
        local topRibModel = topRibNode:CreateComponent("StaticModel")
        topRibModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        topRibModel:SetMaterial(steelMat)
        
        print("AK47 detailed model built with " .. GameState.gunNode:GetNumChildren() .. " components")
    else
        -- 非AK47的普通瞄准镜
        local sightNode = modelContainer:CreateChild("Sight")
        sightNode.scale = Vector3(0.015, 0.025, 0.015)
        sightNode.position = Vector3(0, m.bodyHeight / 2 + 0.015, m.bodyLength * 0.3)
        
        local sightModel = sightNode:CreateComponent("StaticModel")
        sightModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        sightModel:SetMaterial(gunMat)
    end
    
    -- 枪口节点（子弹发射点）
    GameState.muzzleNode = modelContainer:CreateChild("Muzzle")
    local muzzleZ = barrelStartZ + m.barrelLength
    -- 如果有制退器，枪口在制退器末端
    if m.hasMuzzleBrake then
        muzzleZ = muzzleZ + (m.muzzleBrakeLength or 0.04)
    end
    GameState.muzzleNode.position = Vector3(0, m.bodyHeight * 0.2, muzzleZ)
    
    -- 创建枪口调试球
    CreateMuzzleDebugSphere()
    
    print("Gun model built: " .. weapon.nameZh .. ", muzzle at: " .. tostring(GameState.muzzleNode.position))
end

--- 更新枪械位置（根据左右手状态）
function M.UpdateGunHandedness()
    -- 根据左右手决定水平偏移方向
    local horizontalOffset = GameState.isLeftHanded and -CONFIG.GunOffsetRight or CONFIG.GunOffsetRight
    
    -- 腰射位置
    GameState.gunBasePos = Vector3(
        horizontalOffset,           -- 左侧或右侧
        -CONFIG.GunOffsetDown,      -- 下方
        CONFIG.GunOffsetForward     -- 前方
    )
    
    -- 瞄准位置（屏幕中心偏下）
    GameState.gunAdsPos = Vector3(
        CONFIG.AdsOffsetRight,      -- 中心
        -CONFIG.AdsOffsetDown,      -- 下方
        CONFIG.AdsOffsetForward     -- 前方
    )
    
    -- 如果没有切换动画在进行，直接更新位置
    if GameState.handSwitchTransition <= 0 then
        GameState.gunNode.position = GameState.gunBasePos
    end
end

--- 切换左右手持枪（带动画）
function M.ToggleHandedness()
    -- 如果已经在切换中，忽略
    if GameState.handSwitchTransition > 0 then return end
    
    -- 记录切换前后状态
    GameState.handSwitchFromLeft = GameState.isLeftHanded
    GameState.handSwitchToLeft = not GameState.isLeftHanded
    
    -- 启动切换动画
    GameState.handSwitchTransition = 1.0
    
    print("Switching to " .. (GameState.handSwitchToLeft and "Left" or "Right") .. " hand...")
end

--- 开始瞄准 (ADS)
function M.StartAiming()
    if GameState.isAiming then return end
    GameState.isAiming = true
    print("Aiming...")
end

--- 停止瞄准
function M.StopAiming()
    if not GameState.isAiming then return end
    GameState.isAiming = false
    print("Hip fire...")
end

--- 获取当前是否在瞄准状态
function M.IsAiming()
    return GameState.isAiming
end

--- 初始化武器
---@param weaponId string 武器ID
function M.InitWeapon(weaponId)
    local weapon = WEAPONS[weaponId]
    if not weapon then
        print("Error: Unknown weapon: " .. tostring(weaponId))
        return
    end
    
    GameState.currentWeaponId = weaponId
    GameState.currentWeapon = weapon
    GameState.currentAmmo = weapon.magSize
    GameState.reserveAmmo = weapon.reserveAmmo
    GameState.burstShotCount = 0
    GameState.isReloading = false
    GameState.reloadTimer = 0
    GameState.fireCooldown = 0
    
    -- 更新枪械模型
    M.BuildGunModel(weapon)
    
    print("Weapon switched to: " .. weapon.name .. " (" .. GameState.currentAmmo .. "/" .. GameState.reserveAmmo .. ")")
end

--- 开始武器切换动画
---@param weaponId string 目标武器ID
local function StartWeaponSwitch(weaponId)
    -- 如果已经在切换中，忽略
    if GameState.isSwitchingWeapon then return end
    -- 如果目标武器与当前相同，忽略
    if weaponId == GameState.currentWeaponId then return end
    -- 验证武器存在
    if not WEAPONS[weaponId] then return end
    
    -- 开始切换动画
    GameState.isSwitchingWeapon = true
    GameState.weaponSwitchProgress = 0
    GameState.weaponSwitchPendingId = weaponId
    
    print("Switching to " .. WEAPONS[weaponId].nameZh .. "...")
end

--- 切换到下一把武器
function M.SwitchToNextWeapon()
    -- 如果正在切换，忽略
    if GameState.isSwitchingWeapon then return end
    
    local currentIndex = 1
    for i, id in ipairs(WEAPON_ORDER) do
        if id == GameState.currentWeaponId then
            currentIndex = i
            break
        end
    end
    
    local nextIndex = (currentIndex % #WEAPON_ORDER) + 1
    StartWeaponSwitch(WEAPON_ORDER[nextIndex])
end

--- 切换到指定武器（按数字键）
---@param index number 武器索引（1-6）
function M.SwitchToWeaponByIndex(index)
    -- 如果正在切换，忽略
    if GameState.isSwitchingWeapon then return end
    
    if index >= 1 and index <= #WEAPON_ORDER then
        local weaponId = WEAPON_ORDER[index]
        StartWeaponSwitch(weaponId)
    end
end

--- 切换到指定武器（按武器ID）
---@param weaponId string 武器ID
function M.SwitchToWeaponById(weaponId)
    -- 如果正在切换，忽略
    if GameState.isSwitchingWeapon then return end
    
    -- 检查武器是否存在
    if WEAPONS[weaponId] then
        StartWeaponSwitch(weaponId)
    end
end

--- 检查是否可以射击
---@return boolean 是否可以射击
function M.CanShoot()
    -- 切换武器时不能射击
    if GameState.isSwitchingWeapon then return false end
    -- 换弹时不能射击
    if GameState.isReloading then return false end
    return true
end

--- 开始换弹
function M.StartReload()
    if GameState.isReloading then return end
    if not GameState.currentWeapon then return end
    if GameState.currentAmmo >= GameState.currentWeapon.magSize then return end  -- 弹匣已满
    if GameState.reserveAmmo <= 0 then 
        print("No ammo!")
        return 
    end
    
    GameState.isReloading = true
    GameState.reloadTimer = GameState.currentWeapon.reloadTime
    
    -- 播放换弹音效
    Audio.PlaySfx("reload")
    
    -- 触发换弹动画
    GetPlayer().TriggerReloadAnimation()
    
    print("Reloading...")
end

--- 更新换弹状态
function M.UpdateReload(dt)
    if not GameState.isReloading then return end
    
    -- 换弹速度受游戏速度影响
    local gameSpeed = GameState.gameSpeed or 1.0
    GameState.reloadTimer = GameState.reloadTimer - dt * gameSpeed
    
    if GameState.reloadTimer <= 0 then
        -- 换弹完成
        local neededAmmo = GameState.currentWeapon.magSize - GameState.currentAmmo
        local ammoToAdd = math.min(neededAmmo, GameState.reserveAmmo)
        
        GameState.currentAmmo = GameState.currentAmmo + ammoToAdd
        GameState.reserveAmmo = GameState.reserveAmmo - ammoToAdd
        GameState.isReloading = false
        
        print("Reload complete: " .. GameState.currentAmmo .. "/" .. GameState.reserveAmmo)
    end
end

--- 充满弹药
function M.RefillAmmo()
    if not GameState.currentWeapon then return end
    
    -- 充满当前弹匣
    GameState.currentAmmo = GameState.currentWeapon.magSize
    -- 充满备用弹药
    GameState.reserveAmmo = GameState.currentWeapon.reserveAmmo
    
    -- 重置手榴弹数量
    GameState.grenadeCount = CONFIG.GrenadeMaxCount
    
    -- 取消换弹状态
    GameState.isReloading = false
    GameState.reloadTimer = 0
    
    -- 播放换弹音效作为提示
    Audio.PlaySfx("reload")
    
    print("Ammo refilled! " .. GameState.currentAmmo .. "/" .. GameState.reserveAmmo .. ", Grenades: " .. GameState.grenadeCount)
end

--- 平滑插值函数 (ease in-out)
local function smoothStep(t)
    return t * t * (3 - 2 * t)
end

--- 更新武器切换动画
---@param dt number 帧时间
function M.UpdateWeaponSwitch(dt)
    if not GameState.isSwitchingWeapon then return end
    
    -- 切换速度受游戏速度影响
    local gameSpeed = GameState.gameSpeed or 1.0
    local switchSpeed = 1.0 / CONFIG.WeaponSwitchTime * gameSpeed
    
    GameState.weaponSwitchProgress = GameState.weaponSwitchProgress + dt * switchSpeed
    
    -- 到达中点时切换武器模型
    if GameState.weaponSwitchProgress >= 0.5 and GameState.weaponSwitchPendingId then
        -- 直接初始化新武器（不触发新的切换动画）
        local weapon = WEAPONS[GameState.weaponSwitchPendingId]
        if weapon then
            GameState.currentWeaponId = GameState.weaponSwitchPendingId
            GameState.currentWeapon = weapon
            GameState.currentAmmo = weapon.magSize
            GameState.reserveAmmo = weapon.reserveAmmo
            GameState.isReloading = false
            GameState.reloadTimer = 0
            GameState.fireCooldown = 0
            
            -- 更新第一人称枪械模型
            M.BuildGunModel(weapon)
            
            -- 同步更新第三人称手持武器模型
            GetPlayer().SwitchHandWeapon(GameState.weaponSwitchPendingId)
            
            print("Weapon ready: " .. weapon.name .. " (" .. GameState.currentAmmo .. "/" .. GameState.reserveAmmo .. ")")
        end
        GameState.weaponSwitchPendingId = nil  -- 清除待切换ID，避免重复切换
    end
    
    -- 切换完成
    if GameState.weaponSwitchProgress >= 1.0 then
        GameState.weaponSwitchProgress = 0
        GameState.isSwitchingWeapon = false
        GameState.weaponSwitchPendingId = nil
    end
end

--- 更新枪械动画
function M.UpdateGunAnimation(dt)
    if not GameState.gunNode or not GameState.gunBasePos then return end
    
    -- ========== 0. 武器切换动画 ==========
    M.UpdateWeaponSwitch(dt)
    
    -- ========== 1. 左右手切换动画 ==========
    if GameState.handSwitchTransition > 0 then
        GameState.handSwitchTransition = GameState.handSwitchTransition - dt * CONFIG.HandSwitchSpeed
        
        if GameState.handSwitchTransition <= 0 then
            -- 动画完成，应用新的左右手状态
            GameState.handSwitchTransition = 0
            GameState.isLeftHanded = GameState.handSwitchToLeft
            M.UpdateGunHandedness()
            print("Switched to " .. (GameState.isLeftHanded and "Left" or "Right") .. " hand")
        else
            -- 动画进行中
            local progress = 1.0 - GameState.handSwitchTransition
            local smoothProgress = smoothStep(progress)
            
            -- 计算起始和结束位置
            local fromOffset = GameState.handSwitchFromLeft and -CONFIG.GunOffsetRight or CONFIG.GunOffsetRight
            local toOffset = GameState.handSwitchToLeft and -CONFIG.GunOffsetRight or CONFIG.GunOffsetRight
            
            local fromPos = Vector3(fromOffset, -CONFIG.GunOffsetDown, CONFIG.GunOffsetForward)
            local toPos = Vector3(toOffset, -CONFIG.GunOffsetDown, CONFIG.GunOffsetForward)
            
            -- 动画分两个阶段：
            -- 阶段1 (0-0.5): 枪下沉并向中间移动
            -- 阶段2 (0.5-1): 枪从中间移动到新位置并上升
            local dropY = -CONFIG.HandSwitchDropDistance
            local midX = 0  -- 中间位置（屏幕中心）
            
            if smoothProgress < 0.5 then
                -- 阶段1: 从起始位置到中间下方
                local phase1Progress = smoothProgress * 2  -- 0 -> 1
                local easePhase1 = smoothStep(phase1Progress)
                
                local currentX = fromPos.x + (midX - fromPos.x) * easePhase1
                local currentY = fromPos.y + dropY * easePhase1
                
                GameState.gunBasePos = Vector3(currentX, currentY, fromPos.z)
            else
                -- 阶段2: 从中间下方到目标位置
                local phase2Progress = (smoothProgress - 0.5) * 2  -- 0 -> 1
                local easePhase2 = smoothStep(phase2Progress)
                
                local currentX = midX + (toPos.x - midX) * easePhase2
                local currentY = (fromPos.y + dropY) + (-dropY) * easePhase2
                
                GameState.gunBasePos = Vector3(currentX, currentY, toPos.z)
            end
        end
    end
    
    -- ========== 2. 瞄准过渡动画 ==========
    local targetAimTransition = GameState.isAiming and 1.0 or 0.0
    
    if GameState.aimTransition ~= targetAimTransition then
        -- 使用武器特定的瞄准过渡时间（狙击镜使用scopeTransitionTime）
        local w = GameState.currentWeapon
        local transitionTime = 1.0 / CONFIG.AdsTransitionSpeed  -- 默认过渡时间
        if w and w.scopeTransitionTime then
            transitionTime = w.scopeTransitionTime
        end
        -- 计算瞄准速度：1.0 / transitionTime 表示每秒变化量
        local aimSpeed = (1.0 / transitionTime) * dt
        
        if GameState.isAiming then
            GameState.aimTransition = math.min(1.0, GameState.aimTransition + aimSpeed)
        else
            GameState.aimTransition = math.max(0.0, GameState.aimTransition - aimSpeed)
        end
    end
    
    -- ========== 3. 换弹动画 ==========
    -- 初始化换弹动画进度
    if GameState.reloadAnimProgress == nil then
        GameState.reloadAnimProgress = 0
    end
    
    -- 换弹动画：下降 -> 停留 -> 上升
    local reloadDropDistance = 0.25  -- 换弹时下移距离
    local reloadRotateAngle = 25     -- 换弹时向下旋转角度（度）
    local reloadAnimSpeed = 4.0      -- 动画速度
    
    if GameState.isReloading then
        -- 正在换弹，枪下移
        if GameState.reloadAnimProgress < 1.0 then
            GameState.reloadAnimProgress = math.min(1.0, GameState.reloadAnimProgress + dt * reloadAnimSpeed)
        end
    else
        -- 换弹完成，枪上移恢复
        if GameState.reloadAnimProgress > 0 then
            GameState.reloadAnimProgress = math.max(0, GameState.reloadAnimProgress - dt * reloadAnimSpeed)
        end
    end
    
    -- ========== 4. 计算最终位置 ==========
    -- 基础位置（考虑瞄准状态）
    local smoothAim = smoothStep(GameState.aimTransition)
    local basePos = Vector3(
        GameState.gunBasePos.x + (GameState.gunAdsPos.x - GameState.gunBasePos.x) * smoothAim,
        GameState.gunBasePos.y + (GameState.gunAdsPos.y - GameState.gunBasePos.y) * smoothAim,
        GameState.gunBasePos.z + (GameState.gunAdsPos.z - GameState.gunBasePos.z) * smoothAim
    )
    
    -- 换弹动画偏移（平滑下移 + 向下旋转）
    local reloadOffset = Vector3.ZERO
    local reloadRotation = 0  -- 换弹旋转角度
    if GameState.reloadAnimProgress > 0 then
        local smoothReload = smoothStep(GameState.reloadAnimProgress)
        reloadOffset = Vector3(0, -reloadDropDistance * smoothReload, 0)
        reloadRotation = reloadRotateAngle * smoothReload  -- 向下旋转（正值=枪口向下）
    end
    
    -- 武器切换动画偏移（下沉 + 旋转）
    local weaponSwitchOffset = Vector3.ZERO
    local weaponSwitchRotation = 0
    if GameState.isSwitchingWeapon and GameState.weaponSwitchProgress > 0 then
        -- 0-0.5: 收起武器（下沉），0.5-1: 拿出武器（上升）
        local progress = GameState.weaponSwitchProgress
        local animProgress
        if progress < 0.5 then
            -- 收起阶段：0->1
            animProgress = smoothStep(progress * 2)
        else
            -- 拿出阶段：1->0
            animProgress = smoothStep((1.0 - progress) * 2)
        end
        
        weaponSwitchOffset = Vector3(0, -CONFIG.WeaponSwitchDropDistance * animProgress, 0)
        weaponSwitchRotation = CONFIG.WeaponSwitchRotateAngle * animProgress
    end
    
    -- 后坐力动画偏移（受游戏速度影响）
    local gameSpeed = GameState.gameSpeed or 1.0
    local recoilOffset = Vector3.ZERO
    if GameState.gunRecoilTime > 0 then
        GameState.gunRecoilTime = GameState.gunRecoilTime - dt * 8 * gameSpeed
        if GameState.gunRecoilTime < 0 then GameState.gunRecoilTime = 0 end
        
        -- 后坐力偏移（瞄准时后坐力更小）
        local recoilScale = 1.0 - smoothAim * 0.5  -- 瞄准时后坐力减少50%
        recoilOffset = Vector3(0, 0, -0.05 * GameState.gunRecoilTime * recoilScale)
    end
    
    -- 应用最终位置
    GameState.gunNode.position = basePos + reloadOffset + weaponSwitchOffset + recoilOffset
    
    -- 应用旋转（换弹 + 武器切换）
    local totalRotation = reloadRotation + weaponSwitchRotation
    if totalRotation > 0 then
        GameState.gunNode.rotation = Quaternion(totalRotation, Vector3.RIGHT)
    else
        GameState.gunNode.rotation = Quaternion.IDENTITY
    end
    
    -- ========== 4. 更新相机 FOV ==========
    if GameState.camera then
        -- 计算基础 FOV（考虑子弹时间）
        local fovMult = GameState.bulletTimeFovMultiplier or 0
        local baseFov = CONFIG.CameraFov + (CONFIG.BulletTimeFov - CONFIG.CameraFov) * fovMult
        
        -- 使用武器特定的瞄准FOV（狙击镜使用scopeFov，普通武器使用AdsFov）
        local w = GameState.currentWeapon
        local adsFov = CONFIG.AdsFov
        if w and w.hasScope and w.scopeFov then
            adsFov = w.scopeFov
        end
        
        -- 从基础 FOV 插值到瞄准 FOV（直接使用 smoothAim，与瞄准速度一致）
        local targetFov = baseFov + (adsFov - baseFov) * smoothAim
        GameState.camera.fov = targetFov
    end
    
    -- ========== 5. 狙击镜瞄准时隐藏枪械模型 ==========
    local w = GameState.currentWeapon
    if w and w.hasScope and w.hideModelOnAds and GameState.gunNode then
        -- 当完全瞄准时隐藏枪械（smoothAim > 0.95）
        local shouldHide = smoothAim > 0.95
        
        -- 使用缩放隐藏（scale=0 隐藏，恢复原始缩放显示）
        if shouldHide then
            GameState.gunNode.scale = Vector3(0, 0, 0)
        else
            -- 恢复正常缩放
            GameState.gunNode.scale = Vector3(1, 1, 1)
        end
        
        -- 保存狙击镜状态供UI使用
        GameState.scopeActive = shouldHide
        GameState.scopeProgress = smoothAim
    else
        -- 非狙击枪始终显示模型
        if GameState.gunNode then
            GameState.gunNode.scale = Vector3(1, 1, 1)
        end
        GameState.scopeActive = false
        GameState.scopeProgress = 0
    end
end

--- 触发后坐力（脉冲式：上跳→恢复，可被中断）
function M.TriggerRecoil()
    local w = GameState.currentWeapon
    if not w then return end
    
    -- 触发枪口后坐动画
    GameState.gunRecoilTime = 1.0
    
    -- ========== 脉冲式后坐力系统 ==========
    -- 计算上跳量（加大距离，使用 2.5 倍系数）
    local kickMultiplier = 2.5
    local pitchKick = (w.recoilPitchMin + math.random() * (w.recoilPitchMax - w.recoilPitchMin)) * kickMultiplier
    local yawKick = (w.recoilYawMin + math.random() * (w.recoilYawMax - w.recoilYawMin)) * kickMultiplier
    
    -- 记录当前位置作为起点（保留100%当前上跳，从当前位置继续）
    GameState.recoilStartPitch = GameState.pitch
    GameState.recoilStartYaw = GameState.yaw
    
    -- 计算峰值（上跳最高点）
    -- pitch 减小 = 镜头向上看
    GameState.recoilPeakPitch = GameState.pitch - pitchKick
    GameState.recoilPeakYaw = GameState.yaw + yawKick
    
    -- 恢复终点在 hold 超时后计算（在 UpdateRecoil 中）
    -- 这里只需要开始上跳阶段
    GameState.recoilPhase = "kick"
    GameState.recoilProgress = 0
    
    -- 增加准心扩散（瞄准状态下扩散降低30%，跑步状态下扩散增加30%）
    local spreadAmount = w.crosshairSpreadPerShot
    if GameState.isAiming then
        spreadAmount = spreadAmount * 0.7
    elseif GameState.isRunning then
        spreadAmount = spreadAmount * 1.3
    end
    GameState.crosshairSpread = math.min(
        w.crosshairSpreadMax,
        GameState.crosshairSpread + spreadAmount
    )
    
    -- 触发镜头抖动
    GameState.cameraShakeTime = w.cameraShakeDuration
end

return M
