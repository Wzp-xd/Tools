-- ============================================================================
-- 能量盾系统 - 右手防御武器
-- Shield System - Energy shield for damage absorption
-- ============================================================================
-- 激活后创建可视护盾球体，持续时间内吸收伤害。
-- 冷却完毕后可再次使用。HUD 使用 reloading 状态显示冷却。
-- ============================================================================

local ShieldSystem = {}

---@type table|nil 当前激活的护盾状态
local activeShield_ = nil

--- 激活护盾
---@param weapon table 护盾武器实例（def.isShield == true）
---@param mechNode Node 机甲节点（护盾附着）
---@param currentEnergy number 当前能量值
---@param maxEnergy number 最大能量值
---@return boolean success 是否成功激活
---@return number cost 消耗的能量值（成功时 > 0）
function ShieldSystem.Activate(weapon, mechNode, currentEnergy, maxEnergy)
    if not weapon or not weapon.def.isShield then return false, 0 end
    -- 冷却中无法激活
    if weapon.reloading then return false, 0 end
    -- 已激活不重复
    if activeShield_ then return false, 0 end
    -- 能量不足（需要30%能量）
    local energyCost = maxEnergy * 0.3
    if currentEnergy < energyCost then return false, 0 end

    -- 创建护盾视觉效果（半透明球体包裹机甲）
    local shieldNode = mechNode:CreateChild("ShieldBubble")
    shieldNode.position = Vector3(0, 1.7, 0)  -- 机甲中心偏移
    local radius = 2.5
    shieldNode.scale = Vector3(radius, radius, radius)

    local model = shieldNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    local def = weapon.def
    mat:SetShaderParameter("MatDiffColor", Variant(def.shieldColor or Color(0.2, 0.6, 1.0, 0.3)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(def.shieldEmissive or Color(0.5, 1.5, 3.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false

    activeShield_ = {
        weapon = weapon,
        node = shieldNode,
        model = model,
        mat = mat,
        maxAbsorb = def.shieldAbsorb or 200,
        absorbed = 0,
        duration = def.shieldDuration or 3.0,
        age = 0,
    }

    -- 消耗弹药（标记使用）
    weapon.ammo = 0

    print(string.format("[Shield] Activated! absorb=%d duration=%.1fs cost=%.0f energy",
        activeShield_.maxAbsorb, activeShield_.duration, energyCost))

    return true, energyCost
end

--- 护盾是否激活中
---@return boolean
function ShieldSystem.IsActive()
    return activeShield_ ~= nil
end

--- 尝试用护盾吸收伤害
---@param damage number 传入伤害值
---@return number 剩余伤害（护盾吸收后）
function ShieldSystem.AbsorbDamage(damage)
    if not activeShield_ then return damage end

    local remaining = activeShield_.maxAbsorb - activeShield_.absorbed
    if remaining <= 0 then return damage end

    local absorbed = math.min(damage, remaining)
    activeShield_.absorbed = activeShield_.absorbed + absorbed

    print(string.format("[Shield] Absorbed %.0f dmg (%.0f/%.0f)",
        absorbed, activeShield_.absorbed, activeShield_.maxAbsorb))

    -- 吸收满了提前破碎
    if activeShield_.absorbed >= activeShield_.maxAbsorb then
        ShieldSystem.Deactivate(true)
    end

    return damage - absorbed
end

--- 更新护盾状态（每帧调用）
---@param dt number
function ShieldSystem.Update(dt)
    if not activeShield_ then return end

    activeShield_.age = activeShield_.age + dt

    -- 时间到，护盾消散
    if activeShield_.age >= activeShield_.duration then
        ShieldSystem.Deactivate(false)
        return
    end

    -- 视觉效果：随时间闪烁/透明度变化
    local progress = activeShield_.age / activeShield_.duration
    local absorbRatio = activeShield_.absorbed / activeShield_.maxAbsorb
    local alpha = 0.3 * (1.0 - progress * 0.5) * (1.0 - absorbRatio * 0.3)

    -- 脉冲效果
    local pulse = 1.0 + math.sin(activeShield_.age * 8.0) * 0.1
    local r = 2.5 * pulse
    activeShield_.node.scale = Vector3(r, r, r)

    local c = activeShield_.weapon.def.shieldColor or Color(0.2, 0.6, 1.0, 0.3)
    activeShield_.mat:SetShaderParameter("MatDiffColor",
        Variant(Color(c.r, c.g, c.b, alpha)))
end

--- 强制关闭护盾
---@param broken boolean 是否被打破（true = 爆碎效果）
function ShieldSystem.Deactivate(broken)
    if not activeShield_ then return end

    -- 移除护盾节点
    if activeShield_.node then
        activeShield_.node:Remove()
    end

    -- 进入冷却（使用 weapon 的 reloading 机制）
    local weapon = activeShield_.weapon
    weapon.reloading = true
    weapon.reloadTimer = weapon.def.shieldCooldown or 8.0
    weapon.reloadTime = weapon.def.shieldCooldown or 8.0

    if broken then
        print("[Shield] Broken by damage!")
    else
        print("[Shield] Duration expired.")
    end

    activeShield_ = nil
end

--- 清理（场景切换时调用）
function ShieldSystem.Clear()
    if activeShield_ and activeShield_.node then
        activeShield_.node:Remove()
    end
    activeShield_ = nil
end

--- 获取当前护盾状态（供 HUD 显示）
---@return table|nil { absorbed, maxAbsorb, duration, age, progress }
function ShieldSystem.GetStatus()
    if not activeShield_ then return nil end
    return {
        absorbed = activeShield_.absorbed,
        maxAbsorb = activeShield_.maxAbsorb,
        duration = activeShield_.duration,
        age = activeShield_.age,
        progress = activeShield_.age / activeShield_.duration,
    }
end

return ShieldSystem
