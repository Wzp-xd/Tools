-- ============================================================================
-- WeaponAttachment.lua - 武器绑定系统
-- 将武器模型附加到角色手部骨骼
-- ============================================================================

local GameState = require "modules.GameState"
local Config = require "modules.Config"

local M = {}

-- ============================================================================
-- 手部骨骼配置（所有武器共用）
-- ============================================================================

M.HAND_BONES = {
    "Bip001 R Hand",
    "Bip01 R Hand", 
    "R Hand",
    "RightHand",
    "hand_R",
}

-- ============================================================================
-- 第三人称武器显示配置（覆盖 Config.lua 中的第一人称配置）
-- ============================================================================

M.THIRD_PERSON_OVERRIDES = {
    -- 通用配置
    default = {
        positionOffset = Vector3(0, 0, 0),
        rotationOffset = Quaternion(90, Vector3.UP),  -- 向左旋转 90 度
        scaleMultiplier = 0.8,  -- 80% 缩放
    },
    -- 特定武器的覆盖配置（如果需要）
    -- g17 = { positionOffset = Vector3(0, 0.02, 0) },
}

-- ============================================================================
-- 武器附件数据结构
-- ============================================================================

---@class WeaponAttachment
---@field node Node 武器模型节点
---@field weaponNode Node|nil 武器模型节点（兼容旧代码）
---@field handBone Bone 绑定的手部骨骼
---@field boneNode Node 骨骼对应的场景节点
---@field config table 武器配置
---@field weaponId string 武器 ID（对应 Config.WEAPONS 中的键）
---@field muzzleNode Node|nil 枪口节点（用于子弹发射位置）
---@field ejectionNode Node|nil 抛壳口节点（用于弹壳抛出位置）

-- ============================================================================
-- 核心函数
-- ============================================================================

--- 查找手部骨骼
---@param modelNode Node 角色模型节点
---@param boneNames string[] 骨骼名称列表（按优先级）
---@return Bone|nil bone 找到的骨骼
---@return Node|nil boneNode 骨骼对应的节点
local function FindHandBone(modelNode, boneNames)
    print("[WeaponAttachment] Searching for hand bone in modelNode: " .. modelNode.name)
    
    -- 获取 AnimatedModel 组件（递归查找）
    local animModel = nil
    local searchNode = modelNode
    
    -- 尝试在当前节点
    animModel = modelNode:GetComponent("AnimatedModel")
    if animModel then
        print("[WeaponAttachment] Found AnimatedModel on: " .. modelNode.name)
    end
    
    -- 尝试在第一个子节点
    if not animModel then
        local firstChild = modelNode:GetChild(0)
        if firstChild then
            animModel = firstChild:GetComponent("AnimatedModel")
            if animModel then
                searchNode = firstChild
                print("[WeaponAttachment] Found AnimatedModel on child: " .. firstChild.name)
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
                    print("[WeaponAttachment] Found AnimatedModel on grandchild: " .. secondChild.name)
                end
            end
        end
    end
    
    if not animModel then
        print("[WeaponAttachment] ERROR: AnimatedModel not found in node hierarchy")
        -- 打印节点层级帮助调试
        print("[WeaponAttachment] Node hierarchy:")
        print("  - " .. modelNode.name)
        local numChildren = modelNode:GetNumChildren(false)
        for i = 0, numChildren - 1 do
            local child = modelNode:GetChild(i)
            if child then
                print("    - " .. child.name)
                local numGrandChildren = child:GetNumChildren(false)
                for j = 0, math.min(numGrandChildren - 1, 5) do
                    local grandChild = child:GetChild(j)
                    if grandChild then
                        print("      - " .. grandChild.name)
                    end
                end
            end
        end
        return nil, nil
    end
    
    -- 获取骨骼
    local skeleton = animModel:GetSkeleton()
    if not skeleton then
        print("[WeaponAttachment] ERROR: Skeleton not found")
        return nil, nil
    end
    
    local numBones = skeleton:GetNumBones()
    print("[WeaponAttachment] Skeleton has " .. numBones .. " bones")
    
    -- 先打印所有骨骼名称（方便调试）
    print("[WeaponAttachment] All bones:")
    for i = 0, numBones - 1 do
        local bone = skeleton:GetBone(i)
        if bone then
            local hasNode = bone.node and "YES" or "NO"
            print("  [" .. i .. "] " .. bone.name .. " (node: " .. hasNode .. ")")
        end
    end
    
    -- 按优先级查找骨骼
    for _, boneName in ipairs(boneNames) do
        local bone = skeleton:GetBone(boneName)
        if bone and bone.node then
            print("[WeaponAttachment] Found hand bone: " .. boneName)
            return bone, bone.node
        end
    end
    
    print("[WeaponAttachment] WARNING: No matching hand bone found in list")
    return nil, nil
end

--- 创建测试立方体
local function CreateTestBox(parentNode, name, color, scale, position)
    local boxNode = parentNode:CreateChild(name)
    local model = boxNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatEmissiveColor", Variant(Color(color.r * 0.5, color.g * 0.5, color.b * 0.5)))
    model:SetMaterial(material)
    
    boxNode.scale = scale
    boxNode.position = position
    
    return boxNode
end

--- 将武器附加到角色手部
---@param modelNode Node 角色模型节点
---@param weaponId string 武器 ID（对应 Config.WEAPONS 中的键，如 "g17", "ak74"）
---@return WeaponAttachment|nil attachment 武器附件，失败返回 nil
function M.AttachWeapon(modelNode, weaponId)
    -- 从 Config.WEAPONS 获取武器配置
    local weaponConfig = Config.WEAPONS[weaponId]
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
    
    print("[WeaponAttachment] Hand bone found: " .. bone.name)
    print("[WeaponAttachment] Loading weapon prefab: " .. modelConfig.prefabPath)
    
    -- 加载武器 prefab
    local weaponNode = GameState.scene:InstantiateXML(
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
    
    -- 获取第三人称覆盖配置
    local tpOverride = M.THIRD_PERSON_OVERRIDES[weaponId] or M.THIRD_PERSON_OVERRIDES.default
    
    -- 应用缩放（原始缩放 * 第三人称倍率）
    local baseScale = modelConfig.scale or Vector3(1, 1, 1)
    local scaleMultiplier = tpOverride.scaleMultiplier or 1.5
    if type(baseScale) == "userdata" then
        -- Vector3 类型
        weaponNode.scale = baseScale * scaleMultiplier
    else
        -- 数字类型
        local s = baseScale * scaleMultiplier
        weaponNode.scale = Vector3(s, s, s)
    end
    print("[WeaponAttachment] Weapon attached! Scale: " .. tostring(weaponNode.scale))
    
    -- 创建枪口节点（作为武器的子节点）
    local muzzleNode = weaponNode:CreateChild("Muzzle")
    if modelConfig.muzzleOffset then
        muzzleNode.position = modelConfig.muzzleOffset
    else
        muzzleNode.position = Vector3(0, 0, -0.3)  -- 默认枪口位置
    end
    print("[WeaponAttachment] Muzzle node created at local: " .. tostring(muzzleNode.position))
    
    -- 创建抛壳口节点
    local ejectionNode = weaponNode:CreateChild("EjectionPort")
    if modelConfig.ejectionPortOffset then
        ejectionNode.position = modelConfig.ejectionPortOffset
    else
        ejectionNode.position = Vector3(0.04, 0.04, -0.1)  -- 默认抛壳口位置
    end
    
    return {
        node = weaponNode,
        weaponNode = nil,  -- 不再需要单独的武器节点引用
        handBone = bone,
        boneNode = boneNode,
        config = tpOverride,
        weaponId = weaponId,
        muzzleNode = muzzleNode,
        ejectionNode = ejectionNode,
    }
end

--- 更新武器位置（在 PostUpdate 中调用，此时骨骼位置已更新）
---@param attachment WeaponAttachment 武器附件
function M.UpdatePosition(attachment)
    if not attachment or not attachment.boneNode then
        return
    end
    
    -- 获取骨骼的当前世界位置和旋转
    local boneWorldPos = attachment.boneNode.worldPosition
    local boneWorldRot = attachment.boneNode.worldRotation
    
    -- 应用配置的偏移量（在骨骼局部空间中）
    local config = attachment.config
    local offsetPos = config.positionOffset or Vector3.ZERO
    local offsetRot = config.rotationOffset or Quaternion.IDENTITY
    
    -- 计算最终世界位置：骨骼位置 + 旋转后的偏移
    local finalPos = boneWorldPos + boneWorldRot * offsetPos
    local finalRot = boneWorldRot * offsetRot
    
    -- 更新测试方块节点
    if attachment.node then
        attachment.node.worldPosition = finalPos
        attachment.node.worldRotation = finalRot
    end
    
    -- 同时更新武器节点（如果存在）
    if attachment.weaponNode then
        attachment.weaponNode.worldPosition = finalPos
        attachment.weaponNode.worldRotation = finalRot
    end
end

--- 移除武器附件
---@param attachment WeaponAttachment 武器附件
function M.DetachWeapon(attachment)
    if attachment and attachment.node then
        attachment.node:Remove()
        print("[WeaponAttachment] Weapon detached")
    end
end

--- 更新武器偏移（用于调试）
---@param attachment WeaponAttachment 武器附件
---@param posOffset Vector3 位置偏移
---@param rotOffset Quaternion 旋转偏移
function M.UpdateOffset(attachment, posOffset, rotOffset)
    if attachment and attachment.node then
        attachment.node.position = posOffset
        attachment.node.rotation = rotOffset
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

return M
