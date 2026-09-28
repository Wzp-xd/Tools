-- ============================================================================
-- WeaponAttachment.lua - 武器绑定系统（多人游戏版）
-- 将武器模型附加到角色手部骨骼
-- 适配自 demo 版本，移除了 GameState 依赖
-- ============================================================================

local WeaponConfig = require "network.modules.WeaponConfig"

local M = {}

-- ============================================================================
-- 手部骨骼配置（所有武器共用）
-- ============================================================================

M.HAND_BONES = WeaponConfig.HAND_BONES

-- ============================================================================
-- 第三人称武器显示配置
-- ============================================================================

M.THIRD_PERSON_OVERRIDES = WeaponConfig.THIRD_PERSON_OVERRIDES

-- ============================================================================
-- 武器附件数据结构
-- ============================================================================

---@class WeaponAttachment
---@field node Node 武器模型节点
---@field handBone Bone 绑定的手部骨骼
---@field boneNode Node 骨骼对应的场景节点
---@field config table 武器配置
---@field weaponId string 武器 ID
---@field muzzleNode Node|nil 枪口节点
---@field ejectionNode Node|nil 抛壳口节点

-- ============================================================================
-- 核心函数
-- ============================================================================

--- 查找手部骨骼
---@param modelNode Node 角色模型节点
---@param boneNames string[] 骨骼名称列表（按优先级）
---@return Bone|nil bone 找到的骨骼
---@return Node|nil boneNode 骨骼对应的节点
local function FindHandBone(modelNode, boneNames)
    -- 获取 AnimatedModel 组件（递归查找）
    local animModel = nil
    local searchNode = modelNode
    
    -- 尝试在当前节点
    animModel = modelNode:GetComponent("AnimatedModel")
    if animModel then
        -- Found on current node
    end
    
    -- 尝试在第一个子节点
    if not animModel then
        local firstChild = modelNode:GetChild(0)
        if firstChild then
            animModel = firstChild:GetComponent("AnimatedModel")
            if animModel then
                searchNode = firstChild
            end
        end
    end
    
    -- 尝试在第二层子节点
    if not animModel then
        local firstChild = modelNode:GetChild(0)
        if firstChild then
            local secondChild = firstChild:GetChild(0)
            if secondChild then
                animModel = secondChild:GetComponent("AnimatedModel")
                if animModel then
                    searchNode = secondChild
                end
            end
        end
    end
    
    if not animModel then
        return nil, nil
    end
    
    -- 获取骨骼
    local skeleton = animModel:GetSkeleton()
    if not skeleton then
        return nil, nil
    end
    
    -- 按优先级查找骨骼
    for _, boneName in ipairs(boneNames) do
        local bone = skeleton:GetBone(boneName)
        if bone and bone.node then
            return bone, bone.node
        end
    end
    
    return nil, nil
end

--- 将武器附加到角色手部
---@param scene Scene 场景对象
---@param modelNode Node 角色模型节点
---@param weaponId string 武器 ID（如 "g17", "ak74"）
---@return WeaponAttachment|nil attachment 武器附件，失败返回 nil
function M.AttachWeapon(scene, modelNode, weaponId)
    -- 从 WeaponConfig 获取武器配置
    local weaponConfig = WeaponConfig.WEAPONS[weaponId]
    if not weaponConfig then
        print("[WeaponAttachment] ERROR: Unknown weapon ID: " .. tostring(weaponId))
        return nil
    end
    
    local modelConfig = weaponConfig.model
    if not modelConfig or not modelConfig.isPrefab then
        print("[WeaponAttachment] ERROR: Weapon " .. weaponId .. " is not a prefab weapon")
        return nil
    end
    
    -- 查找手部骨骼
    local bone, boneNode = FindHandBone(modelNode, M.HAND_BONES)
    if not boneNode then
        print("[WeaponAttachment] ERROR: Could not find hand bone for weapon attachment")
        return nil
    end
    
    -- 加载武器 prefab（使用传入的 scene 而非 GameState）
    local weaponNode = scene:InstantiateXML(
        modelConfig.prefabPath,
        boneNode.worldPosition,
        boneNode.worldRotation,
        LOCAL
    )
    
    if not weaponNode then
        print("[WeaponAttachment] ERROR: Failed to load weapon prefab: " .. modelConfig.prefabPath)
        return nil
    end
    
    weaponNode.name = "Weapon_" .. weaponId
    
    -- 【调试】在武器原点(0,0,0)添加蓝色半透明球体（默认隐藏，测试模式下显示）
    local debugSphere = weaponNode:CreateChild("DebugSphere")
    debugSphere.position = Vector3.ZERO
    debugSphere.scale = Vector3(0.05, 0.05, 0.05)
    debugSphere.enabled = false
    local sphereModel = debugSphere:CreateComponent("StaticModel")
    sphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    -- 创建蓝色半透明材质
    local debugMat = Material:new()
    debugMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    debugMat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 1.0, 0.5)))
    sphereModel:SetMaterial(debugMat)
    
    -- 获取第三人称覆盖配置
    local tpOverride = M.THIRD_PERSON_OVERRIDES[weaponId] or M.THIRD_PERSON_OVERRIDES.default
    
    -- 应用缩放
    local baseScale = modelConfig.scale or Vector3(1, 1, 1)
    local scaleMultiplier = tpOverride.scaleMultiplier or 1.5
    if type(baseScale) == "userdata" then
        weaponNode.scale = baseScale * scaleMultiplier
    else
        local s = baseScale * scaleMultiplier
        weaponNode.scale = Vector3(s, s, s)
    end
    
    -- 创建枪口节点
    local muzzleNode = weaponNode:CreateChild("Muzzle")
    if modelConfig.muzzleOffset then
        muzzleNode.position = modelConfig.muzzleOffset
    else
        muzzleNode.position = Vector3(0, 0, -0.3)
    end
    
    -- 创建抛壳口节点
    local ejectionNode = weaponNode:CreateChild("EjectionPort")
    if modelConfig.ejectionPortOffset then
        ejectionNode.position = modelConfig.ejectionPortOffset
    else
        ejectionNode.position = Vector3(0.04, 0.04, -0.1)
    end
    
    return {
        node = weaponNode,
        handBone = bone,
        boneNode = boneNode,
        config = tpOverride,
        modelConfig = modelConfig,  -- 添加武器模型配置
        weaponId = weaponId,
        muzzleNode = muzzleNode,
        ejectionNode = ejectionNode,
    }
end

--- 更新武器位置（在 PostUpdate 中调用）
---@param attachment WeaponAttachment 武器附件
function M.UpdatePosition(attachment)
    if not attachment or not attachment.boneNode then
        return
    end
    
    local boneWorldPos = attachment.boneNode.worldPosition
    local boneWorldRot = attachment.boneNode.worldRotation
    
    -- 使用武器模型配置中的偏移（WeaponConfig.lua 中定义）
    -- 偏移相对于骨骼局部坐标系（受骨骼旋转影响）
    local modelConfig = attachment.modelConfig
    local offsetPos = modelConfig and modelConfig.positionOffset or Vector3.ZERO
    local offsetRot = modelConfig and modelConfig.rotationOffset or Quaternion.IDENTITY
    
    local finalPos = boneWorldPos + boneWorldRot * offsetPos
    local finalRot = boneWorldRot * offsetRot
    
    if attachment.node then
        attachment.node.worldPosition = finalPos
        attachment.node.worldRotation = finalRot
    end
end

--- 移除武器附件
---@param attachment WeaponAttachment 武器附件
function M.DetachWeapon(attachment)
    if attachment and attachment.node then
        attachment.node:Remove()
    end
end

--- 设置武器可见性
---@param attachment WeaponAttachment 武器附件
---@param visible boolean 是否可见
function M.SetVisible(attachment, visible)
    if attachment and attachment.node then
        attachment.node.enabled = visible
    end
end

--- 获取枪口世界位置
---@param attachment WeaponAttachment 武器附件
---@return Vector3 position 枪口世界位置
function M.GetMuzzlePosition(attachment)
    if attachment and attachment.muzzleNode then
        return attachment.muzzleNode.worldPosition
    end
    return Vector3.ZERO
end

--- 获取枪口世界方向
---@param attachment WeaponAttachment 武器附件
---@return Vector3 direction 枪口朝向（世界坐标）
function M.GetMuzzleDirection(attachment)
    if attachment and attachment.muzzleNode then
        return attachment.muzzleNode.worldRotation * Vector3.FORWARD
    end
    return Vector3.FORWARD
end

--- 获取抛壳口世界位置
---@param attachment WeaponAttachment 武器附件
---@return Vector3 position 抛壳口世界位置
function M.GetEjectionPosition(attachment)
    if attachment and attachment.ejectionNode then
        return attachment.ejectionNode.worldPosition
    end
    return Vector3.ZERO
end

return M
