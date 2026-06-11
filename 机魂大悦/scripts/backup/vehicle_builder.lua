-- ============================================================================
-- 载具构建器 - 坦克和直升机程序化模型
-- VehicleBuilder - Procedural Tank & Helicopter Models
-- ============================================================================

local MechBuilder = require "mech_builder"

local VehicleBuilder = {}

-- ============================================================================
-- 材质
-- ============================================================================

local mats_ = nil

---@return table
local function GetMaterials()
    if mats_ then return mats_ end
    local function PBR(c, m, r, e)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(c))
        mat:SetShaderParameter("Metallic", Variant(m))
        mat:SetShaderParameter("Roughness", Variant(r))
        if e then mat:SetShaderParameter("MatEmissiveColor", Variant(e)) end
        return mat
    end
    mats_ = {
        -- 坦克
        tankBody   = PBR(Color(0.18, 0.22, 0.12, 1.0), 0.7, 0.45),   -- 橄榄绿
        tankTrack  = PBR(Color(0.08, 0.08, 0.06, 1.0), 0.3, 0.8),    -- 深灰履带
        tankBarrel = PBR(Color(0.12, 0.12, 0.14, 1.0), 0.9, 0.25),   -- 金属炮管
        tankTurret = PBR(Color(0.20, 0.24, 0.14, 1.0), 0.75, 0.4),   -- 略浅绿炮塔
        -- 直升机
        heliBody   = PBR(Color(0.25, 0.27, 0.25, 1.0), 0.6, 0.45),   -- 军灰
        heliGlass  = PBR(Color(0.1, 0.2, 0.3, 0.7), 0.0, 0.1, Color(0.2, 0.5, 0.8)),
        heliRotor  = PBR(Color(0.10, 0.10, 0.12, 1.0), 0.8, 0.3),    -- 深色旋翼
        heliTail   = PBR(Color(0.22, 0.24, 0.22, 1.0), 0.5, 0.5),
    }
    -- 玻璃半透明
    mats_.heliGlass:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    return mats_
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function CreateBox(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = false
    return node
end

local function CreateCylinder(parent, name, pos, scale, mat, rot)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    if rot then node.rotation = rot end
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    model:SetMaterial(mat)
    model.castShadows = false
    return node
end

-- ============================================================================
-- 坦克构建 (~1.6m高, 3.0m长, 2.0m宽)
-- ============================================================================

--- 构建坦克模型
---@param parentNode Node
---@return Node modelNode
---@return table joints
function VehicleBuilder.BuildTank(parentNode)
    local m = GetMaterials()
    local modelNode = parentNode:CreateChild("TankModel")

    -- 车体 (3.0 x 0.7 x 2.0)
    local hull = CreateBox(modelNode, "Hull", Vector3(0, 0.45, 0), Vector3(2.0, 0.7, 3.0), m.tankBody)

    -- 履带 (左右两侧)
    CreateBox(modelNode, "TrackL", Vector3(-1.1, 0.3, 0), Vector3(0.35, 0.5, 3.2), m.tankTrack)
    CreateBox(modelNode, "TrackR", Vector3( 1.1, 0.3, 0), Vector3(0.35, 0.5, 3.2), m.tankTrack)

    -- 车轮装饰 (每侧4个)
    local wheelRot = Quaternion(90, Vector3.FORWARD)
    for i = 0, 3 do
        local zOff = -1.2 + i * 0.8
        CreateCylinder(modelNode, "WheelL" .. i, Vector3(-1.1, 0.25, zOff), Vector3(0.3, 0.1, 0.3), m.tankTrack, wheelRot)
        CreateCylinder(modelNode, "WheelR" .. i, Vector3( 1.1, 0.25, zOff), Vector3(0.3, 0.1, 0.3), m.tankTrack, wheelRot)
    end

    -- 炮塔 (可旋转关节)
    local turretJoint = modelNode:CreateChild("TurretJoint")
    turretJoint.position = Vector3(0, 0.8, -0.1)
    local turret = CreateBox(turretJoint, "Turret", Vector3(0, 0.3, 0), Vector3(1.4, 0.5, 1.2), m.tankTurret)

    -- 炮管
    local barrelRot = Quaternion(90, Vector3.RIGHT)
    local barrel = CreateCylinder(turretJoint, "Barrel", Vector3(0, 0.25, 1.0), Vector3(0.12, 1.0, 0.12), m.tankBarrel, barrelRot)

    -- 炮管末端武器挂载点
    local mountMain = turretJoint:CreateChild("WeaponMount_Main")
    mountMain.position = Vector3(0, 0.25, 2.0)

    -- 机枪座 (炮塔顶部)
    CreateBox(turretJoint, "MGMount", Vector3(0.3, 0.6, -0.1), Vector3(0.1, 0.15, 0.2), m.tankBarrel)
    local mgBarrel = CreateCylinder(turretJoint, "MGBarrel", Vector3(0.3, 0.6, 0.2), Vector3(0.04, 0.3, 0.04), m.tankBarrel, barrelRot)
    local mountMG = turretJoint:CreateChild("WeaponMount_MG")
    mountMG.position = Vector3(0.3, 0.6, 0.5)

    -- 装甲板装饰（贴合车体表面，挂在 modelNode 下避免继承 hull 缩放）
    CreateBox(modelNode, "FrontPlate", Vector3(0, 0.35, 1.55), Vector3(1.8, 0.35, 0.06), m.tankTurret)
    CreateBox(modelNode, "RearPlate",  Vector3(0, 0.35, -1.55), Vector3(1.8, 0.35, 0.06), m.tankTrack)

    local joints = {
        turret = turretJoint,
        barrel = barrel,
        weaponMountMain = mountMain,
        weaponMountMG = mountMG,
    }

    return modelNode, joints
end

-- ============================================================================
-- 直升机构建 (~2.0m机身, 4.0m长, 旋翼跨度5.0m)
-- ============================================================================

--- 构建直升机模型
---@param parentNode Node
---@return Node modelNode
---@return table joints
function VehicleBuilder.BuildHelicopter(parentNode)
    local m = GetMaterials()
    local modelNode = parentNode:CreateChild("HeliModel")

    -- 机身 (4.0 x 1.2 x 1.5)
    local fuselage = CreateBox(modelNode, "Fuselage", Vector3(0, 0.6, 0), Vector3(1.5, 1.2, 4.0), m.heliBody)

    -- 驾驶舱 (前部, 略微倾斜)
    local cockpit = CreateBox(modelNode, "Cockpit", Vector3(0, 0.5, 1.8), Vector3(1.3, 0.8, 1.0), m.heliBody)
    -- 驾驶舱玻璃
    CreateBox(modelNode, "CockpitGlass", Vector3(0, 0.65, 2.35), Vector3(1.1, 0.5, 0.1), m.heliGlass)

    -- 尾梁
    CreateBox(modelNode, "TailBoom", Vector3(0, 0.5, -2.8), Vector3(0.4, 0.4, 2.6), m.heliTail)

    -- 尾旋翼
    local tailRotorHub = modelNode:CreateChild("TailRotorJoint")
    tailRotorHub.position = Vector3(0.25, 0.55, -4.0)
    tailRotorHub.rotation = Quaternion(90, Vector3.FORWARD)
    local tailRotor = CreateBox(tailRotorHub, "TailRotor", Vector3.ZERO, Vector3(0.05, 0.8, 0.15), m.heliRotor)

    -- 主旋翼
    local mainRotorHub = modelNode:CreateChild("MainRotorJoint")
    mainRotorHub.position = Vector3(0, 1.35, 0)
    -- 旋翼轴
    CreateCylinder(modelNode, "RotorShaft", Vector3(0, 1.2, 0), Vector3(0.08, 0.2, 0.08), m.heliRotor)
    -- 旋翼叶片 (两片十字)
    local mainRotor1 = CreateBox(mainRotorHub, "MainBlade1", Vector3.ZERO, Vector3(5.0, 0.03, 0.25), m.heliRotor)
    local mainRotor2 = CreateBox(mainRotorHub, "MainBlade2", Vector3.ZERO, Vector3(0.25, 0.03, 5.0), m.heliRotor)

    -- 起落架
    CreateBox(modelNode, "SkidL", Vector3(-0.7, -0.15, 0), Vector3(0.06, 0.06, 2.5), m.heliRotor)
    CreateBox(modelNode, "SkidR", Vector3( 0.7, -0.15, 0), Vector3(0.06, 0.06, 2.5), m.heliRotor)
    CreateBox(modelNode, "SkidStrutLF", Vector3(-0.7, 0.1, 0.6), Vector3(0.05, 0.5, 0.05), m.heliRotor)
    CreateBox(modelNode, "SkidStrutLR", Vector3(-0.7, 0.1, -0.6), Vector3(0.05, 0.5, 0.05), m.heliRotor)
    CreateBox(modelNode, "SkidStrutRF", Vector3( 0.7, 0.1, 0.6), Vector3(0.05, 0.5, 0.05), m.heliRotor)
    CreateBox(modelNode, "SkidStrutRR", Vector3( 0.7, 0.1, -0.6), Vector3(0.05, 0.5, 0.05), m.heliRotor)

    -- 武器挂载 (机头下方)
    local mountMG = modelNode:CreateChild("WeaponMount_MG")
    mountMG.position = Vector3(0, 0.1, 2.0)
    -- 枪管装饰
    local gunRot = Quaternion(90, Vector3.RIGHT)
    CreateCylinder(modelNode, "NoseGun", Vector3(0, 0.1, 2.2), Vector3(0.06, 0.4, 0.06), m.heliRotor, gunRot)

    -- 挂架装饰 (两侧)
    CreateBox(modelNode, "PylonL", Vector3(-0.9, 0.3, -0.3), Vector3(0.6, 0.12, 0.3), m.heliBody)
    CreateBox(modelNode, "PylonR", Vector3( 0.9, 0.3, -0.3), Vector3(0.6, 0.12, 0.3), m.heliBody)

    local joints = {
        mainRotor = mainRotorHub,
        tailRotor = tailRotorHub,
        weaponMountMG = mountMG,
        fuselage = fuselage,
    }

    return modelNode, joints
end

-- ============================================================================
-- 死亡效果 - 复用 MechBuilder
-- ============================================================================

--- 播放载具死亡爆炸效果
---@param node Node
function VehicleBuilder.PlayDeathEffect(node)
    MechBuilder.PlayDeathEffect(node)
end

--- 更新死亡效果（委托给 MechBuilder）
---@param dt number
function VehicleBuilder.UpdateDeathEffects(dt)
    -- MechBuilder.UpdateDeathEffects 已在 main.lua 中调用
end

return VehicleBuilder
