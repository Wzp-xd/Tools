-- ============================================================================
-- vfx_dash_jet.lua — 冲刺 & 喷射视觉特效
-- 从 main.lua L1605-1833 提取
-- ============================================================================

local GS = require "game_state"

local VFX = {}

-- ============================================================================
-- 冲刺拖尾材质
-- ============================================================================

--- 创建冲刺拖尾材质（无光照加法混合）
---@param color Color
---@return Material
local function CreateDashTrailMat(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAdd.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    return mat
end

--- 在指定肩膀关节上创建一条冲刺拖尾
---@param parentJoint Node
---@param name string
---@return Node
local function CreateDashShoulderTrail(parentJoint, name)
    local trailNode = parentJoint:CreateChild(name)
    trailNode.position = Vector3(0, 0.3, 0)

    local ribbon = trailNode:CreateComponent("RibbonTrail")
    ribbon.material = CreateDashTrailMat(Color(0.3, 0.8, 1.0, 0.9))
    ribbon.width = 0.24
    ribbon.lifetime = 0.15
    ribbon.vertexDistance = 0.3
    ribbon.startColor = Color(0.4, 0.85, 1.0, 0.9)
    ribbon.endColor = Color(0.1, 0.4, 0.8, 0.0)
    ribbon.startScale = 1.0
    ribbon.endScale = 0.2
    ribbon.sorted = true
    ribbon.emitting = true
    return trailNode
end

-- ============================================================================
-- 冲刺特效
-- ============================================================================

--- 冲刺开始时创建特效
function VFX.StartDash()
    if not GS.mechNode or not GS.mechJoints then return end

    -- 1) 双肩拖尾
    if GS.dashTrailNodeL then GS.dashTrailNodeL:Remove(); GS.dashTrailNodeL = nil end
    if GS.dashTrailNodeR then GS.dashTrailNodeR:Remove(); GS.dashTrailNodeR = nil end

    if GS.mechJoints.shoulderL then
        GS.dashTrailNodeL = CreateDashShoulderTrail(GS.mechJoints.shoulderL, "DashTrailL")
    end
    if GS.mechJoints.shoulderR then
        GS.dashTrailNodeR = CreateDashShoulderTrail(GS.mechJoints.shoulderR, "DashTrailR")
    end

    -- 2) 起始爆发球
    if GS.dashBurstNode then
        GS.dashBurstNode:Remove()
        GS.dashBurstNode = nil
    end
    GS.dashBurstNode = GS.scene:CreateChild("DashBurst")
    GS.dashBurstNode.position = GS.mechNode.worldPosition + Vector3(0, 0.3, 0)
    GS.dashBurstNode.scale = Vector3(0.5, 0.5, 0.5)

    local burstModel = GS.dashBurstNode:CreateComponent("StaticModel")
    burstModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local burstMat = Material:new()
    burstMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    burstMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.7, 1.0, 0.6)))
    burstMat:SetShaderParameter("MatEmissiveColor", Variant(Color(1.5, 3.0, 5.0)))
    burstMat:SetShaderParameter("Metallic", Variant(0.0))
    burstMat:SetShaderParameter("Roughness", Variant(0.1))
    burstModel:SetMaterial(burstMat)
    burstModel.castShadows = false

    GS.dashBurstAge = 0
end

--- 停止单条冲刺拖尾并放入清理队列
---@param trailNode Node|nil
local function StopDashTrail(trailNode)
    if not trailNode then return end
    if GS.scene then
        local worldPos = trailNode.worldPosition
        trailNode.parent = GS.scene
        trailNode.position = worldPos
        local ribbon = trailNode:GetComponent("RibbonTrail")
        if ribbon then ribbon.emitting = false end
        if not GS.dashTrailCleanup then GS.dashTrailCleanup = {} end
        table.insert(GS.dashTrailCleanup, { node = trailNode, age = 0 })
    else
        trailNode:Remove()
    end
end

--- 冲刺结束时停止特效
function VFX.StopDash()
    StopDashTrail(GS.dashTrailNodeL)
    GS.dashTrailNodeL = nil
    StopDashTrail(GS.dashTrailNodeR)
    GS.dashTrailNodeR = nil

    if GS.dashBurstNode then
        GS.dashBurstNode:Remove()
        GS.dashBurstNode = nil
    end
end

--- 更新冲刺爆发特效动画（每帧调用）
---@param dt number
function VFX.UpdateDash(dt)
    -- 更新起始爆发球
    if GS.dashBurstNode then
        GS.dashBurstAge = GS.dashBurstAge + dt
        local burstLife = 0.125
        if GS.dashBurstAge >= burstLife then
            GS.dashBurstNode:Remove()
            GS.dashBurstNode = nil
        else
            local progress = GS.dashBurstAge / burstLife
            local s = 0.5 + progress * 2.5
            GS.dashBurstNode.scale = Vector3(s, s * 0.6, s)
            local alpha = 0.6 * (1.0 - progress)
            local emMul = 5.0 * (1.0 - progress * progress)
            local model = GS.dashBurstNode:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.7, 1.0, alpha)))
                    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.3 * emMul, 0.6 * emMul, 1.0 * emMul)))
                end
            end
        end
    end

    -- 清理已停止发射的拖尾残留节点
    if GS.dashTrailCleanup then
        for i = #GS.dashTrailCleanup, 1, -1 do
            local entry = GS.dashTrailCleanup[i]
            entry.age = entry.age + dt
            if entry.age > 0.25 then
                entry.node:Remove()
                table.remove(GS.dashTrailCleanup, i)
            end
        end
    end
end

-- ============================================================================
-- 喷射特效
-- ============================================================================

--- 在背部喷口位置创建一条细长拖尾
---@param parent Node
---@param name string
---@param localPos Vector3
---@return Node
local function CreateJetTrail(parent, name, localPos)
    local node = parent:CreateChild(name)
    node.position = localPos

    local ribbon = node:CreateComponent("RibbonTrail")
    ribbon.material = CreateDashTrailMat(Color(1.0, 0.45, 0.05, 0.9))
    ribbon.width = 0.35
    ribbon.lifetime = 0.5
    ribbon.vertexDistance = 0.15
    ribbon.startColor = Color(1.0, 0.6, 0.15, 0.95)
    ribbon.endColor  = Color(1.0, 0.15, 0.0, 0.0)
    ribbon.startScale = 1.0
    ribbon.endScale = 0.05
    ribbon.sorted = true
    ribbon.emitting = true
    return node
end

--- 喷射模式开始时创建特效
function VFX.StartJet()
    if not GS.mechNode or not GS.mechAnimator then return end

    local body = GS.mechAnimator.joints and GS.mechAnimator.joints.body
    if not body then body = GS.mechNode end

    -- 清除旧拖尾
    if GS.jetTrailNodeL then GS.jetTrailNodeL:Remove(); GS.jetTrailNodeL = nil end
    if GS.jetTrailNodeR then GS.jetTrailNodeR:Remove(); GS.jetTrailNodeR = nil end

    -- 背部喷口位置
    GS.jetTrailNodeL = CreateJetTrail(body, "JetTrailL", Vector3(-0.25, 1.62, -0.68))
    GS.jetTrailNodeR = CreateJetTrail(body, "JetTrailR", Vector3( 0.25, 1.62, -0.68))
end

--- 停止单条拖尾并放入清理队列
---@param trailNode Node|nil
local function DetachJetTrail(trailNode)
    if not trailNode then return end
    if GS.scene then
        local worldPos = trailNode.worldPosition
        trailNode.parent = GS.scene
        trailNode.position = worldPos
        local ribbon = trailNode:GetComponent("RibbonTrail")
        if ribbon then ribbon.emitting = false end
        if not GS.dashTrailCleanup then GS.dashTrailCleanup = {} end
        table.insert(GS.dashTrailCleanup, { node = trailNode, age = 0 })
    else
        trailNode:Remove()
    end
end

--- 喷射模式结束时停止特效
function VFX.StopJet()
    DetachJetTrail(GS.jetTrailNodeL); GS.jetTrailNodeL = nil
    DetachJetTrail(GS.jetTrailNodeR); GS.jetTrailNodeR = nil
end

--- 更新喷射特效（拖尾自动跟随）
function VFX.UpdateJet(dt)
    -- RibbonTrail 自动驱动，无需手动更新
end

return VFX
