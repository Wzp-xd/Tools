-- ============================================================================
-- railgun_fx.lua — 电磁炮视觉特效系统
-- 从 main.lua L1834-2291 提取
-- ============================================================================

local GS = require "game_state"

local RailgunFX = {}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 创建一个发光材质球体节点
---@param parent Node
---@param name string
---@param pos Vector3
---@param scale number
---@param color Color
---@param emissive Color
---@return table { node, mat }
local function CreateGlowSphere(parent, name, pos, scale, color, emissive)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = Vector3(scale, scale, scale)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false
    return { node = node, mat = mat }
end

-- ============================================================================
-- 蓄力特效
-- ============================================================================

--- 开始蓄力特效
---@param side string "L"|"R"
function RailgunFX.StartCharge(side)
    side = side or "R"
    local wpnKey = side == "L" and "shoulderL" or "shoulderR"
    if not GS.playerWeapons or not GS.playerWeapons[wpnKey] then return end
    local wpnNode = GS.playerWeapons[wpnKey].weaponNode
    if not wpnNode then return end

    local fx = {}

    -- 1. 能量核心发光球
    fx.chargeGlow = CreateGlowSphere(wpnNode, "RG_ChargeGlow",
        Vector3(0, 0, 0.1), 0.02,
        Color(0.3, 0.6, 1.0, 0.5), Color(2.0, 4.0, 8.0))

    -- 2. 枪口聚焦光球
    fx.muzzleGlow = CreateGlowSphere(wpnNode, "RG_MuzzleGlow",
        Vector3(0, 0, 0.38), 0.02,
        Color(0.5, 0.8, 1.0, 0.3), Color(1.0, 2.0, 4.0))

    -- 3. 导轨间电弧火花
    fx.sparks = {}
    for i = 1, 6 do
        local zPos = -0.1 + (i / 7) * 0.48
        local sparkNode = wpnNode:CreateChild("RG_Spark" .. i)
        sparkNode.position = Vector3(0, 0, zPos)
        sparkNode.scale = Vector3(0.001, 0.001, 0.001)
        local sModel = sparkNode:CreateComponent("StaticModel")
        sModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        local sMat = Material:new()
        sMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        sMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 1.0)))
        sMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 8.0, 15.0)))
        sMat:SetShaderParameter("Metallic", Variant(0.0))
        sMat:SetShaderParameter("Roughness", Variant(0.0))
        sModel:SetMaterial(sMat)
        sModel.castShadows = false
        table.insert(fx.sparks, { node = sparkNode, baseZ = zPos })
    end

    -- 4. 导轨间发光平面
    local planeNode = wpnNode:CreateChild("RG_ChargePlane")
    planeNode.position = Vector3(0, 0, 0.2)
    planeNode.scale = Vector3(0.24, 0.001, 0.001)
    local pModel = planeNode:CreateComponent("StaticModel")
    pModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local pMat = Material:new()
    pMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    pMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, 0.0)))
    pMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.0, 0.0, 0.0)))
    pMat:SetShaderParameter("Metallic", Variant(0.0))
    pMat:SetShaderParameter("Roughness", Variant(0.0))
    pModel:SetMaterial(pMat)
    pModel.castShadows = false
    fx.chargePlane = { node = planeNode, mat = pMat }

    -- 5. 蓄力点光源
    local lightNode = wpnNode:CreateChild("RG_ChargeLight")
    lightNode.position = Vector3(0, 0, 0.2)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(0.4, 0.7, 1.0)
    light.range = 0.5
    light.brightness = 0.5
    light.castShadows = false
    fx.chargeLight = { node = lightNode, light = light }

    if side == "L" then
        GS.railgunFXL = fx
    else
        GS.railgunFX = fx
    end
end

--- 更新蓄力特效（每帧调用）
---@param dt number
---@param chgPct number 0~1 蓄力进度
---@param side string "L"|"R"
function RailgunFX.UpdateCharge(dt, chgPct, side)
    local fxRef = (side == "L") and GS.railgunFXL or GS.railgunFX
    if not fxRef then return end
    local t = os.clock()

    -- 1. 核心发光球
    if fxRef.chargeGlow then
        local s = 0.16 * chgPct
        fxRef.chargeGlow.node.scale = Vector3(s, s, s)
        local pulse = 1.0 + 0.3 * math.sin(t * 15)
        local em = chgPct * pulse
        fxRef.chargeGlow.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(2.0 * em, 4.0 * em, 8.0 * em)))
        fxRef.chargeGlow.mat:SetShaderParameter("MatDiffColor",
            Variant(Color(0.3, 0.6, 1.0, 0.3 + 0.5 * chgPct)))
    end

    -- 2. 枪口聚焦球
    if fxRef.muzzleGlow then
        local ms = 0.12 * chgPct * chgPct
        fxRef.muzzleGlow.node.scale = Vector3(ms, ms, ms)
        local pulse = 1.0 + 0.5 * math.sin(t * 20)
        local em = chgPct * chgPct * pulse
        fxRef.muzzleGlow.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(3.0 * em, 5.0 * em, 10.0 * em)))
    end

    -- 3. 电弧火花
    if fxRef.sparks then
        for _, spark in ipairs(fxRef.sparks) do
            local jitterY = (math.random() - 0.5) * 0.08
            local jitterX = (math.random() - 0.5) * 0.02
            spark.node.position = Vector3(jitterX, jitterY, spark.baseZ + (math.random() - 0.5) * 0.05)
            local visible = math.random() < chgPct
            if visible then
                local sz = 0.016 + 0.016 * chgPct
                spark.node.scale = Vector3(sz, sz, 0.04 + 0.06 * chgPct)
            else
                spark.node.scale = Vector3(0.001, 0.001, 0.001)
            end
        end
    end

    -- 4. 导轨间发光平面
    if fxRef.chargePlane then
        local planeLen = 1.2 * chgPct
        local pulse = 1.0 + 0.2 * math.sin(t * 12)
        fxRef.chargePlane.node.scale = Vector3(0.24, 0.005, math.max(0.001, planeLen))
        local emStr = chgPct * chgPct * pulse
        fxRef.chargePlane.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(3.0 * emStr, 6.0 * emStr, 12.0 * emStr)))
        fxRef.chargePlane.mat:SetShaderParameter("MatDiffColor",
            Variant(Color(0.3, 0.6, 1.0, 0.15 + 0.6 * chgPct)))
    end

    -- 5. 点光源
    if fxRef.chargeLight then
        fxRef.chargeLight.light.range = 0.5 + 3.0 * chgPct
        fxRef.chargeLight.light.brightness = 0.5 + 3.0 * chgPct
    end
end

--- 停止蓄力特效（清理所有节点）
---@param side string "L"|"R"
function RailgunFX.StopCharge(side)
    local fxRef = (side == "L") and GS.railgunFXL or GS.railgunFX
    if not fxRef then return end
    if fxRef.chargeGlow then fxRef.chargeGlow.node:Remove() end
    if fxRef.muzzleGlow then fxRef.muzzleGlow.node:Remove() end
    if fxRef.sparks then
        for _, s in ipairs(fxRef.sparks) do s.node:Remove() end
    end
    if fxRef.chargePlane then fxRef.chargePlane.node:Remove() end
    if fxRef.chargeLight then fxRef.chargeLight.node:Remove() end
    if side == "L" then
        GS.railgunFXL = nil
    else
        GS.railgunFX = nil
    end
end

-- ============================================================================
-- 发射特效
-- ============================================================================

--- 发射瞬间特效（枪口闪光 + 光柱 + 冲击波）
---@param targetPos Vector3|nil
---@param side string "L"|"R"
function RailgunFX.Fire(targetPos, side)
    side = side or "R"
    local wpnKey = side == "L" and "shoulderL" or "shoulderR"
    if not GS.playerWeapons or not GS.playerWeapons[wpnKey] then return end
    local weapon = GS.playerWeapons[wpnKey]
    local spawnPos = weapon.mountNode.worldPosition
    local fwd
    if targetPos then
        fwd = (targetPos - spawnPos):Normalized()
    else
        fwd = weapon.mountNode.worldRotation * Vector3.FORWARD
    end
    local scene = GS.scene

    -- 1. 枪口爆闪
    local flashNode = scene:CreateChild("RG_Flash")
    flashNode.position = spawnPos + fwd * 0.5
    flashNode.scale = Vector3(0.8, 0.8, 0.8)
    local fModel = flashNode:CreateComponent("StaticModel")
    fModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local fMat = Material:new()
    fMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    fMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 0.9)))
    fMat:SetShaderParameter("MatEmissiveColor", Variant(Color(15.0, 20.0, 30.0)))
    fMat:SetShaderParameter("Metallic", Variant(0.0))
    fMat:SetShaderParameter("Roughness", Variant(0.0))
    fModel:SetMaterial(fMat)
    fModel.castShadows = false
    table.insert(GS.railgunFireFX, { node = flashNode, mat = fMat, age = 0, life = 0.25,
        type = "flash", maxScale = 2.5 })

    -- 2. 光柱
    local beamNode = scene:CreateChild("RG_Beam")
    beamNode.position = spawnPos + fwd * 25.0
    beamNode.rotation = Quaternion(Vector3.FORWARD, fwd)
    beamNode.scale = Vector3(3.0, 3.0, 50.0)
    local bModel = beamNode:CreateComponent("StaticModel")
    bModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bMat = Material:new()
    bMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    bMat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, 0.7)))
    bMat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 12.0, 20.0)))
    bMat:SetShaderParameter("Metallic", Variant(0.0))
    bMat:SetShaderParameter("Roughness", Variant(0.0))
    bModel:SetMaterial(bMat)
    bModel.castShadows = false
    table.insert(GS.railgunFireFX, { node = beamNode, mat = bMat, age = 0, life = 0.3,
        type = "beam", initAlpha = 0.7 })

    -- 3. 冲击波环
    local ringNode = scene:CreateChild("RG_Ring")
    ringNode.position = spawnPos + fwd * 0.3
    ringNode.rotation = Quaternion(Vector3.UP, fwd)
    ringNode.scale = Vector3(0.3, 0.02, 0.3)
    local rModel = ringNode:CreateComponent("StaticModel")
    rModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local rMat = Material:new()
    rMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rMat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 1.0, 0.5)))
    rMat:SetShaderParameter("MatEmissiveColor", Variant(Color(4.0, 6.0, 10.0)))
    rMat:SetShaderParameter("Metallic", Variant(0.0))
    rMat:SetShaderParameter("Roughness", Variant(0.0))
    rModel:SetMaterial(rMat)
    rModel.castShadows = false
    table.insert(GS.railgunFireFX, { node = ringNode, mat = rMat, age = 0, life = 0.35,
        type = "ring", maxScale = 5.0 })

    -- 4. 发射闪光点光源
    local flashLightNode = scene:CreateChild("RG_FireLight")
    flashLightNode.position = spawnPos + fwd * 1.0
    local flashLight = flashLightNode:CreateComponent("Light")
    flashLight.lightType = LIGHT_POINT
    flashLight.color = Color(0.6, 0.8, 1.0)
    flashLight.range = 15.0
    flashLight.brightness = 5.0
    flashLight.castShadows = false
    table.insert(GS.railgunFireFX, { node = flashLightNode, age = 0, life = 0.2,
        type = "light", light = flashLight })
end

-- ============================================================================
-- 命中特效
-- ============================================================================

--- 电磁炮命中特效（电弧放电 + 冲击波 + 闪光）
---@param hitPos Vector3
function RailgunFX.Hit(hitPos)
    if not GS.scene then return end
    local scene = GS.scene

    -- 1. 电弧核心球
    local coreNode = scene:CreateChild("RGHit_Core")
    coreNode.position = hitPos
    coreNode.scale = Vector3(0.6, 0.6, 0.6)
    local cModel = coreNode:CreateComponent("StaticModel")
    cModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local cMat = Material:new()
    cMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    cMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 0.95)))
    cMat:SetShaderParameter("MatEmissiveColor", Variant(Color(20.0, 30.0, 50.0)))
    cMat:SetShaderParameter("Metallic", Variant(0.0))
    cMat:SetShaderParameter("Roughness", Variant(0.0))
    cModel:SetMaterial(cMat)
    cModel.castShadows = false
    table.insert(GS.railgunHitFX, {
        node = coreNode, mat = cMat, age = 0, life = 0.4,
        type = "core", maxScale = 2.0,
    })

    -- 2. 电弧分支（6条）
    for j = 1, 6 do
        local arcNode = scene:CreateChild("RGHit_Arc")
        arcNode.position = hitPos
        local rx = math.random() * 2.0 - 1.0
        local ry = math.random() * 1.5 - 0.3
        local rz = math.random() * 2.0 - 1.0
        local dir = Vector3(rx, ry, rz):Normalized()
        arcNode.rotation = Quaternion(Vector3.FORWARD, dir)
        local arcLen = 1.5 + math.random() * 2.0
        arcNode.scale = Vector3(0.06, 0.06, arcLen)
        local aModel = arcNode:CreateComponent("StaticModel")
        aModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        local aMat = Material:new()
        aMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        aMat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, 0.8)))
        aMat:SetShaderParameter("MatEmissiveColor", Variant(Color(10.0, 15.0, 25.0)))
        aMat:SetShaderParameter("Metallic", Variant(0.0))
        aMat:SetShaderParameter("Roughness", Variant(0.0))
        aModel:SetMaterial(aMat)
        aModel.castShadows = false
        table.insert(GS.railgunHitFX, {
            node = arcNode, mat = aMat, age = 0, life = 0.2 + math.random() * 0.15,
            type = "arc", initLen = arcLen,
        })
    end

    -- 3. 冲击波环
    local ringNode = scene:CreateChild("RGHit_Ring")
    ringNode.position = hitPos
    ringNode.scale = Vector3(0.4, 0.02, 0.4)
    local rModel = ringNode:CreateComponent("StaticModel")
    rModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local rMat = Material:new()
    rMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, 0.6)))
    rMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 8.0, 15.0)))
    rMat:SetShaderParameter("Metallic", Variant(0.0))
    rMat:SetShaderParameter("Roughness", Variant(0.0))
    rModel:SetMaterial(rMat)
    rModel.castShadows = false
    table.insert(GS.railgunHitFX, {
        node = ringNode, mat = rMat, age = 0, life = 0.35,
        type = "ring", maxScale = 4.0,
    })

    -- 4. 冲击点光源
    local lightNode = scene:CreateChild("RGHit_Light")
    lightNode.position = hitPos
    local hitLight = lightNode:CreateComponent("Light")
    hitLight.lightType = LIGHT_POINT
    hitLight.color = Color(0.5, 0.7, 1.0)
    hitLight.range = 12.0
    hitLight.brightness = 6.0
    hitLight.castShadows = false
    table.insert(GS.railgunHitFX, {
        node = lightNode, age = 0, life = 0.3,
        type = "light", light = hitLight,
    })

    print("[RailgunFX] Hit effect at " .. tostring(hitPos))
end

-- ============================================================================
-- 残留特效更新
-- ============================================================================

--- 更新发射后残留特效（淡出 + 清理）
---@param dt number
function RailgunFX.UpdateFireFX(dt)
    -- 发射特效
    local i = 1
    while i <= #GS.railgunFireFX do
        local fx = GS.railgunFireFX[i]
        fx.age = fx.age + dt

        if fx.age >= fx.life then
            fx.node:Remove()
            table.remove(GS.railgunFireFX, i)
        else
            local progress = fx.age / fx.life

            if fx.type == "flash" then
                local s = 0.8 + (fx.maxScale - 0.8) * math.min(1.0, progress * 4.0)
                fx.node.scale = Vector3(s, s, s)
                local alpha = 0.9 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, alpha)))
                local em = math.max(0, 15.0 * (1.0 - progress * 2.0))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.3, em * 2.0)))

            elseif fx.type == "beam" then
                local alpha = fx.initAlpha * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, alpha)))
                local em = math.max(0, 8.0 * (1.0 - progress * 1.5))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))
                local shrink = 0.9 * (1.0 - progress * 0.7)
                fx.node.scale = Vector3(shrink, shrink, 50.0)

            elseif fx.type == "ring" then
                local expand = 0.3 + fx.maxScale * progress
                fx.node.scale = Vector3(expand, 0.02 * (1.0 - progress), expand)
                local alpha = 0.5 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 1.0, alpha)))
                local em = math.max(0, 4.0 * (1.0 - progress))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))

            elseif fx.type == "light" then
                fx.light.brightness = 5.0 * (1.0 - progress)
                fx.light.range = 15.0 * (1.0 - progress * 0.5)
            end

            i = i + 1
        end
    end

    -- 命中特效
    local j = 1
    while j <= #GS.railgunHitFX do
        local hfx = GS.railgunHitFX[j]
        hfx.age = hfx.age + dt

        if hfx.age >= hfx.life then
            hfx.node:Remove()
            table.remove(GS.railgunHitFX, j)
        else
            local prog = hfx.age / hfx.life

            if hfx.type == "core" then
                local s = 0.6 + (hfx.maxScale - 0.6) * math.min(1.0, prog * 3.0)
                hfx.node.scale = Vector3(s, s, s)
                local alpha = 0.95 * (1.0 - prog)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, alpha)))
                local em = math.max(0, 20.0 * (1.0 - prog * 1.5))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))

            elseif hfx.type == "arc" then
                local flicker = (math.sin(hfx.age * 80.0) * 0.5 + 0.5)
                local alpha = 0.8 * (1.0 - prog) * (0.5 + flicker * 0.5)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, alpha)))
                local em = math.max(0, 10.0 * (1.0 - prog))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))
                local shrink = math.max(0.01, 1.0 - prog * 1.2)
                hfx.node.scale = Vector3(0.06 * shrink, 0.06 * shrink, hfx.initLen * shrink)

            elseif hfx.type == "ring" then
                local expand = 0.4 + hfx.maxScale * prog
                hfx.node.scale = Vector3(expand, 0.02 * (1.0 - prog), expand)
                local alpha = 0.6 * (1.0 - prog)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, alpha)))
                local em = math.max(0, 5.0 * (1.0 - prog))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.6, em * 3.0)))

            elseif hfx.type == "light" then
                hfx.light.brightness = 6.0 * (1.0 - prog)
                hfx.light.range = 12.0 * (1.0 - prog * 0.5)
            end

            j = j + 1
        end
    end
end

return RailgunFX
