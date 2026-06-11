-- ============================================================================
-- 武器外观系统 - 每种武器的独立 3D 模型构建
-- Weapon Visuals - Unique 3D model for each weapon type
-- ============================================================================
-- 每种武器使用引擎基础几何体（Box/Cylinder/Cone/Sphere）拼装，
-- 配合 PBR 材质呈现独特外观。
-- ============================================================================

local WeaponVisuals = {}

-- ============================================================================
-- 材质工具
-- ============================================================================

--- 创建 PBR 不透明材质
---@param color Color
---@param metallic number
---@param roughness number
---@param emissiveColor Color|nil
---@return Material
local function CreatePBRMat(color, metallic, roughness, emissiveColor)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    if emissiveColor then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissiveColor))
    end
    return mat
end

--- 创建 PBR 透明材质
---@param color Color
---@param metallic number
---@param roughness number
---@param emissiveColor Color|nil
---@return Material
local function CreatePBRAlphaMat(color, metallic, roughness, emissiveColor)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    if emissiveColor then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissiveColor))
    end
    return mat
end

-- ============================================================================
-- 部件工具
-- ============================================================================

--- 创建 Box 部件
local function AddBox(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

--- 创建 Cylinder 部件
local function AddCylinder(parent, name, pos, scale, mat, rotation)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    if rotation then node.rotation = rotation end
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

--- 创建 Cone 部件
local function AddCone(parent, name, pos, scale, mat, rotation)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    if rotation then node.rotation = rotation end
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

--- 创建 Sphere 部件
local function AddSphere(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

-- Cylinder 默认 Y-up，旋转到 Z-forward
local ROT_Z_FWD = Quaternion(90, Vector3.RIGHT)
-- Cone 默认 Y-up，旋转到 Z-forward（尖端朝前）
local ROT_CONE_FWD = Quaternion(90, Vector3.RIGHT)

-- ============================================================================
-- 通用材质（复用）
-- ============================================================================

local matCache_ = nil

local function GetMats()
    if matCache_ then return matCache_ end
    matCache_ = {
        -- 基础金属
        darkMetal   = CreatePBRMat(Color(0.15, 0.15, 0.18, 1.0), 0.9, 0.25),
        gunmetal    = CreatePBRMat(Color(0.22, 0.24, 0.28, 1.0), 0.85, 0.3),
        lightMetal  = CreatePBRMat(Color(0.6, 0.62, 0.65, 1.0), 0.8, 0.25),
        silverWhite = CreatePBRMat(Color(0.75, 0.78, 0.82, 1.0), 0.7, 0.2),
        -- 着色金属
        matteBlack  = CreatePBRMat(Color(0.06, 0.06, 0.08, 1.0), 0.3, 0.7),
        brass       = CreatePBRMat(Color(0.72, 0.55, 0.2, 1.0), 0.8, 0.35),
        militaryGreen = CreatePBRMat(Color(0.22, 0.28, 0.15, 1.0), 0.4, 0.55),
        desertTan   = CreatePBRMat(Color(0.65, 0.55, 0.35, 1.0), 0.4, 0.5),
        darkOlive   = CreatePBRMat(Color(0.2, 0.25, 0.12, 1.0), 0.5, 0.5),
        -- 红色/橙色
        redTip      = CreatePBRMat(Color(0.7, 0.15, 0.1, 1.0), 0.3, 0.4),
        darkTip     = CreatePBRMat(Color(0.1, 0.1, 0.12, 1.0), 0.5, 0.5),
        -- 发光
        orangeGlow  = CreatePBRMat(Color(1.0, 0.6, 0.2, 1.0), 0.0, 0.1, Color(4.0, 2.0, 0.3)),
        blueGlow    = CreatePBRMat(Color(0.3, 0.6, 1.0, 1.0), 0.0, 0.1, Color(1.0, 2.5, 5.0)),
        cyanGlow    = CreatePBRMat(Color(0.2, 0.8, 0.9, 1.0), 0.0, 0.1, Color(0.5, 2.0, 3.0)),
        brightBlueGlow = CreatePBRMat(Color(0.5, 0.7, 1.0, 1.0), 0.0, 0.1, Color(2.0, 4.0, 8.0)),
        -- 透明
        shieldBlue  = CreatePBRAlphaMat(Color(0.2, 0.5, 1.0, 0.3), 0.0, 0.1, Color(0.5, 1.5, 3.0)),
    }
    return matCache_
end

-- ============================================================================
-- 武器构建函数
-- ============================================================================

--- 机关枪: Cylinder 枪管 + Box 机匣 + Cone 枪口制退器
function WeaponVisuals.CreateMachinegun(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_machinegun")
    wpn.position = Vector3(0, 0, 0.75)

    -- 枪管（Cylinder，Z 方向延伸）
    AddCylinder(wpn, "Barrel", Vector3(0, 0, 0.15), Vector3(0.105, 0.75, 0.105), mats.gunmetal, ROT_Z_FWD)
    -- 机匣
    AddBox(wpn, "Receiver", Vector3(0, 0, -0.36), Vector3(0.24, 0.21, 0.54), mats.darkMetal)
    -- 枪口制退器
    AddCone(wpn, "Muzzle", Vector3(0, 0, 0.84), Vector3(0.15, 0.18, 0.15), mats.orangeGlow, ROT_CONE_FWD)

    return wpn
end

--- 霰弹枪: Box 宽机匣 + 2x Cylinder 双管 + Box 护木
function WeaponVisuals.CreateShotgun(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_shotgun")
    wpn.position = Vector3(0, 0, 0.66)

    -- 宽机匣
    AddBox(wpn, "Receiver", Vector3(0, 0, -0.24), Vector3(0.36, 0.27, 0.6), mats.matteBlack)
    -- 双管（上下排列）
    AddCylinder(wpn, "BarrelTop", Vector3(0, 0.075, 0.24), Vector3(0.09, 0.6, 0.09), mats.gunmetal, ROT_Z_FWD)
    AddCylinder(wpn, "BarrelBot", Vector3(0, -0.075, 0.24), Vector3(0.09, 0.6, 0.09), mats.gunmetal, ROT_Z_FWD)
    -- 护木（前方下部）
    AddBox(wpn, "Grip", Vector3(0, -0.15, 0.06), Vector3(0.18, 0.12, 0.36), mats.brass)

    return wpn
end

--- 手枪: Box 紧凑枪身 + Cylinder 短管 + Box 扳机护圈
function WeaponVisuals.CreatePistol(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_pistol")
    wpn.position = Vector3(0, 0, 0.54)

    -- 枪身
    AddBox(wpn, "Body", Vector3(0, 0, 0), Vector3(0.18, 0.24, 0.48), mats.silverWhite)
    -- 短枪管
    AddCylinder(wpn, "Barrel", Vector3(0, 0.03, 0.3), Vector3(0.06, 0.24, 0.06), mats.lightMetal, ROT_Z_FWD)
    -- 扳机护圈
    AddBox(wpn, "TriggerGuard", Vector3(0, -0.135, -0.06), Vector3(0.09, 0.06, 0.18), mats.darkMetal)
    -- 蓝色发光指示
    AddSphere(wpn, "Indicator", Vector3(0, 0.12, -0.12), Vector3(0.045, 0.045, 0.045), mats.blueGlow)

    return wpn
end

--- RPG: Cylinder 发射管 + Box 瞄具 + Cone 弹头
function WeaponVisuals.CreateRPG(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_rpg")
    wpn.position = Vector3(0, 0, 0.54)

    -- 发射管
    AddCylinder(wpn, "Tube", Vector3(0, 0, 0), Vector3(0.21, 0.9, 0.21), mats.militaryGreen, ROT_Z_FWD)
    -- 瞄具
    AddBox(wpn, "Sight", Vector3(0, 0.24, -0.15), Vector3(0.12, 0.12, 0.18), mats.darkMetal)
    -- 弹头（前端突出）
    AddCone(wpn, "Warhead", Vector3(0, 0, 0.84), Vector3(0.18, 0.24, 0.18), mats.redTip, ROT_CONE_FWD)
    -- 握把
    AddBox(wpn, "Grip", Vector3(0, -0.24, -0.24), Vector3(0.12, 0.18, 0.24), mats.darkMetal)

    return wpn
end

--- 能量盾: Sphere 半球发射器 + Box 基座
function WeaponVisuals.CreateShield(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_shield")
    wpn.position = Vector3(0, 0, 0.45)

    -- 基座
    AddBox(wpn, "Base", Vector3(0, 0, -0.12), Vector3(0.3, 0.24, 0.3), mats.darkMetal)
    -- 半球发射器
    AddSphere(wpn, "Emitter", Vector3(0, 0, 0.12), Vector3(0.24, 0.18, 0.24), mats.cyanGlow)
    -- 侧翼
    AddBox(wpn, "WingL", Vector3(-0.18, 0, 0), Vector3(0.06, 0.18, 0.24), mats.lightMetal)
    AddBox(wpn, "WingR", Vector3(0.18, 0, 0), Vector3(0.06, 0.18, 0.24), mats.lightMetal)

    return wpn
end

--- 追踪手枪: Box 棱角枪身 + Cylinder 管 + Sphere 传感器 + Box 天线
function WeaponVisuals.CreateHomingHandgun(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_homing_handgun")
    wpn.position = Vector3(0, 0, 0.54)

    -- 棱角枪身
    AddBox(wpn, "Body", Vector3(0, 0, 0), Vector3(0.21, 0.3, 0.6), mats.silverWhite)
    -- 枪管
    AddCylinder(wpn, "Barrel", Vector3(0, 0.03, 0.36), Vector3(0.075, 0.18, 0.075), mats.lightMetal, ROT_Z_FWD)
    -- 传感器球（顶部发光）
    AddSphere(wpn, "Sensor", Vector3(0, 0.18, 0.12), Vector3(0.09, 0.09, 0.09), mats.cyanGlow)
    -- 侧天线
    AddBox(wpn, "Antenna", Vector3(0.135, 0.09, -0.12), Vector3(0.03, 0.12, 0.09), mats.darkMetal)

    return wpn
end

--- 斜射飞弹: Box 荚舱（保持与原版一致的整体尺寸）
function WeaponVisuals.CreateMissile(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_missile")
    wpn.position = Vector3(0, 0, 0.1)
    wpn.scale = Vector3(0.7, 0.7, 0.7)  -- 缩小 30%

    -- 发射荚舱主体
    AddBox(wpn, "Pod", Vector3(0, 0, 0), Vector3(0.88, 0.64, 1.2), mats.darkMetal)
    -- 3 个发射口（前端凹陷效果用深色小方块模拟）
    for i = 1, 3 do
        local y = (i - 2) * 0.2
        AddBox(wpn, "Port" .. i, Vector3(0, y, 0.56), Vector3(0.16, 0.16, 0.12), mats.matteBlack)
    end
    -- 侧面标识条
    AddBox(wpn, "Stripe", Vector3(0.4, 0, 0), Vector3(0.06, 0.48, 1.0), mats.redTip)

    return wpn
end

--- 垂直飞弹: Box 竖向荚舱 + 4x Cylinder 弹头 + Box 底座
function WeaponVisuals.CreateVerticalMissile(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_vertical_missile")
    wpn.position = Vector3(0, 0, 0)
    wpn.scale = Vector3(0.6, 0.6, 0.6)

    -- 底座板
    AddBox(wpn, "BasePlate", Vector3(0, -0.32, 0), Vector3(0.88, 0.16, 0.88), mats.darkMetal)
    -- 竖向荚舱主体
    AddBox(wpn, "Pod", Vector3(0, 0.32, 0), Vector3(0.8, 1.12, 0.8), mats.darkOlive)
    -- 4 个弹头（顶部 2x2 排列）
    local offsets = {
        Vector3(-0.16, 0.88, -0.16), Vector3(0.16, 0.88, -0.16),
        Vector3(-0.16, 0.88, 0.16),  Vector3(0.16, 0.88, 0.16),
    }
    for i, off in ipairs(offsets) do
        AddCone(wpn, "MissileTip" .. i, off, Vector3(0.12, 0.24, 0.12), mats.redTip)
    end

    return wpn
end

--- 肩扛火箭: Cylinder 大型发射管 + Box 肩托 + Cone 整流罩
function WeaponVisuals.CreateShoulderRPG(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_shoulder_rpg")
    wpn.position = Vector3(0, 0, 0.48)

    -- 大型发射管
    AddCylinder(wpn, "Tube", Vector3(0, 0, 0), Vector3(0.36, 1.4, 0.36), mats.desertTan, ROT_Z_FWD)
    -- 肩托（后部）
    AddBox(wpn, "Brace", Vector3(0, -0.24, -0.88), Vector3(0.4, 0.24, 0.48), mats.darkMetal)
    -- 整流罩（前端）
    AddCone(wpn, "Nosecone", Vector3(0, 0, 1.36), Vector3(0.32, 0.4, 0.32), mats.darkTip, ROT_CONE_FWD)
    -- 瞄准器
    AddBox(wpn, "Sight", Vector3(0, 0.4, 0.2), Vector3(0.12, 0.16, 0.2), mats.darkMetal)

    return wpn
end

--- 电磁炮: 2x Cylinder 平行导轨 + Box 电容器 + Sphere 能量核心
function WeaponVisuals.CreateRailgun(mountNode)
    local mats = GetMats()
    local wpn = mountNode:CreateChild("Weapon_railgun")
    wpn.position = Vector3(0, 0, 0.6)

    -- 上导轨
    AddCylinder(wpn, "RailTop", Vector3(0, 0.16, 0.2), Vector3(0.1, 1.4, 0.1), mats.gunmetal, ROT_Z_FWD)
    -- 下导轨
    AddCylinder(wpn, "RailBot", Vector3(0, -0.16, 0.2), Vector3(0.1, 1.4, 0.1), mats.gunmetal, ROT_Z_FWD)
    -- 电容器方块（后部）
    AddBox(wpn, "Capacitor", Vector3(0, 0, -0.6), Vector3(0.4, 0.32, 0.56), mats.darkMetal)
    -- 能量核心（两轨之间的发光球）
    AddSphere(wpn, "EnergyCore", Vector3(0, 0, 0.4), Vector3(0.16, 0.16, 0.16), mats.brightBlueGlow)
    -- 前端聚焦环
    AddCylinder(wpn, "FocusRing", Vector3(0, 0, 1.2), Vector3(0.2, 0.06, 0.2), mats.lightMetal, ROT_Z_FWD)

    return wpn
end

-- ============================================================================
-- 分发表
-- ============================================================================

local BUILDERS = {
    machinegun       = WeaponVisuals.CreateMachinegun,
    shotgun          = WeaponVisuals.CreateShotgun,
    pistol           = WeaponVisuals.CreatePistol,
    rpg              = WeaponVisuals.CreateRPG,
    shield           = WeaponVisuals.CreateShield,
    homing_handgun   = WeaponVisuals.CreateHomingHandgun,
    missile          = WeaponVisuals.CreateMissile,
    vertical_missile = WeaponVisuals.CreateVerticalMissile,
    shoulder_rpg     = WeaponVisuals.CreateShoulderRPG,
    railgun          = WeaponVisuals.CreateRailgun,
}

--- 创建武器的 3D 外观模型
---@param weaponType string
---@param mountNode Node
---@return Node|nil
function WeaponVisuals.Create(weaponType, mountNode)
    local builder = BUILDERS[weaponType]
    if builder then
        return builder(mountNode)
    end
    print("[WeaponVisuals] Unknown weapon type: " .. tostring(weaponType))
    return nil
end

--- 清除材质缓存（场景销毁时调用）
function WeaponVisuals.ClearCache()
    matCache_ = nil
end

return WeaponVisuals
