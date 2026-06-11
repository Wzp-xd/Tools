-- ============================================================================
-- 机甲构建器 - 层级关节结构
-- MechBuilder - Hierarchical Joint Structure for Animation
-- ============================================================================
-- 将原本平铺的方块机甲改为层级关节结构，支持程序化动画。
-- 关节层级:
--   modelNode
--   ├── Body (上半身组)
--   │   ├── Torso, ChestPlate, Head, Visor, Backpack, Boosters, Waist
--   │   ├── ShoulderL_Joint → ShoulderL, UpperArmL, ElbowL_Joint → ForearmL
--   │   └── ShoulderR_Joint → ShoulderR, UpperArmR, ElbowR_Joint → ForearmR
--   ├── HipL_Joint → ThighL, KneeL_Joint → ShinL, FootL
--   └── HipR_Joint → ThighR, KneeR_Joint → ShinR, FootR
-- ============================================================================

local MechBuilder = {}

-- ============================================================================
-- 材质辅助函数
-- ============================================================================

--- 创建 PBR 材质
---@param color Color
---@param metallic number
---@param roughness number
---@param emissive Color|nil
---@return Material
local function CreatePBRMat(color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    if emissive then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    return mat
end

--- 创建方块部件
---@param parent Node
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param mat Material
---@return Node
local function CreateBoxPart(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

-- ============================================================================
-- 默认材质
-- ============================================================================

local materialsCache_ = {}  -- 按变体 ID 缓存材质

--- 获取/创建材质集（支持变体颜色）
---@param variantId string|nil 变体 ID（nil 使用默认）
---@return table
local function GetMaterials(variantId)
    local key = variantId or "_default"
    if materialsCache_[key] then return materialsCache_[key] end

    -- 获取变体颜色配置
    local CONFIG = require("config")
    local variant = variantId and CONFIG.MechVariants[variantId]
    local c = variant and variant.colors

    -- 默认颜色
    local bodyColor   = c and Color(c.body[1], c.body[2], c.body[3], 1.0)
                           or Color(0.22, 0.24, 0.28, 1.0)
    local armorColor  = c and Color(c.armor[1], c.armor[2], c.armor[3], 1.0)
                           or Color(0.5, 0.12, 0.08, 1.0)
    local jointColor  = c and Color(c.joint[1], c.joint[2], c.joint[3], 1.0)
                           or Color(0.08, 0.08, 0.1, 1.0)
    local visorColor  = c and Color(c.visor[1], c.visor[2], c.visor[3], 1.0)
                           or Color(0.1, 0.4, 0.5, 1.0)
    local visorEmissive = c and c.visorEmissive
                             and Color(c.visorEmissive[1], c.visorEmissive[2], c.visorEmissive[3])
                             or Color(0.3, 1.5, 2.5)

    local mats = {
        body    = CreatePBRMat(bodyColor, 0.85, 0.3),
        armor   = CreatePBRMat(armorColor, 0.7, 0.35),
        joint   = CreatePBRMat(jointColor, 0.9, 0.2),
        visor   = CreatePBRMat(visorColor, 0.0, 0.1, visorEmissive),
        nozzle  = CreatePBRMat(Color(0.04, 0.04, 0.05, 1.0), 0.1, 0.85),
        flameCore = CreatePBRMat(
            Color(1.0, 0.9, 0.6, 0.9), 0.0, 0.1,
            Color(6.0, 4.0, 1.0)
        ),
        flameOuter = CreatePBRMat(
            Color(1.0, 0.4, 0.1, 0.7), 0.0, 0.1,
            Color(4.0, 1.5, 0.3)
        ),
    }
    -- 火焰材质设置透明
    mats.flameCore:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mats.flameOuter:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))

    materialsCache_[key] = mats
    return mats
end

--- 创建喷口 + 火焰效果
---@param parent Node 父节点
---@param name string 名称前缀
---@param pos Vector3 喷口位置（相对于父节点）
---@param flameDir Vector3 火焰喷射方向（单位向量）
---@param flameLen number 火焰长度
---@param variantId string|nil 变体 ID
---@return Node nozzleNode 喷口节点
---@return Node flameNode 火焰节点（控制 enabled）
local function CreateThruster(parent, name, pos, flameDir, flameLen, variantId)
    local mats = GetMaterials(variantId)

    -- 从 Cylinder 默认朝向 (Y-up) 旋转到喷射方向
    local rot = Quaternion(Vector3.UP, flameDir)

    -- 喷口（小圆柱，朝向喷射方向）
    local nozzle = parent:CreateChild(name .. "_Nozzle")
    nozzle.position = pos
    nozzle.rotation = rot
    nozzle.scale = Vector3(0.12, 0.15, 0.12)
    local nozzleModel = nozzle:CreateComponent("StaticModel")
    nozzleModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    nozzleModel:SetMaterial(mats.nozzle)
    nozzleModel.castShadows = false

    -- 火焰容器（用于整体显隐，旋转后局部 Y 轴 = 喷射方向）
    local flameGroup = parent:CreateChild(name .. "_Flame")
    flameGroup.position = pos
    flameGroup.rotation = rot

    -- 火焰内核（亮黄色，细长）—— 沿局部 Y 轴延伸
    local core = flameGroup:CreateChild("Core")
    core.position = Vector3(0, flameLen * 0.45, 0)
    core.scale = Vector3(0.06, flameLen * 0.8, 0.06)
    local coreModel = core:CreateComponent("StaticModel")
    coreModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    coreModel:SetMaterial(mats.flameCore)
    coreModel.castShadows = false

    -- 火焰外层（橙红色，稍粗）
    local outer = flameGroup:CreateChild("Outer")
    outer.position = Vector3(0, flameLen * 0.35, 0)
    outer.scale = Vector3(0.10, flameLen * 0.6, 0.10)
    local outerModel = outer:CreateComponent("StaticModel")
    outerModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    outerModel:SetMaterial(mats.flameOuter)
    outerModel.castShadows = false

    -- 默认隐藏火焰
    flameGroup:SetDeepEnabled(false)

    return nozzle, flameGroup
end

-- ============================================================================
-- 构建层级机甲
-- ============================================================================

--- 构建层级关节结构的机甲模型
--- 返回 modelNode 和关节引用表
---@param parent Node 父节点
---@param variantId string|nil 变体 ID（nil 使用默认配色）
---@return Node modelNode 模型根节点
---@return table joints 关节引用 { body, shoulderL, shoulderR, elbowL, elbowR, hipL, hipR, kneeL, kneeR }
function MechBuilder.Build(parent, variantId)
    local mats = GetMaterials(variantId)
    local modelNode = parent:CreateChild("ModelNode")

    -- joints 引用表
    local joints = {}

    -- ====================================================================
    -- Body 组 (上半身 + 手臂)
    -- Body 节点位于 y=0，自身不偏移，动画时整体摆动/倾斜
    -- ====================================================================
    local body = modelNode:CreateChild("Body")
    body.position = Vector3(0, 0, 0)
    joints.body = body

    -- 躯干三段式结构: 胸肌 → 腹部 → 胯部
    -- 胸肌（主体装甲块，宽厚）
    CreateBoxPart(body, "Chest",      Vector3(0, 2.08, 0),      Vector3(0.95, 0.48, 0.60), mats.armor)
    -- 腹部（收窄的机械腰，过渡段）
    CreateBoxPart(body, "Abdomen",    Vector3(0, 1.72, 0),      Vector3(0.55, 0.24, 0.40), mats.joint)
    -- 胯部（承载腿部的骨盆块）
    CreateBoxPart(body, "Pelvis",     Vector3(0, 1.48, 0),      Vector3(0.72, 0.26, 0.48), mats.body)

    -- 肩部横轴（连接躯干与手臂的水平结构杆）
    CreateBoxPart(body, "ShoulderAxis", Vector3(0, 2.10, 0),    Vector3(1.44, 0.08, 0.10), mats.joint)

    -- 头部（缩小）
    CreateBoxPart(body, "Head",       Vector3(0, 2.52, 0),      Vector3(0.36, 0.30, 0.36), mats.body)
    CreateBoxPart(body, "Visor",      Vector3(0, 2.54, 0.17),   Vector3(0.30, 0.07, 0.04), mats.visor)

    -- 背包（对齐胸部）
    CreateBoxPart(body, "Backpack",   Vector3(0, 2.05, -0.38),  Vector3(0.65, 0.55, 0.22), mats.armor)
    -- 背部推进器（对齐背包下沿）
    CreateBoxPart(body, "BoosterL",   Vector3(-0.20, 1.68, -0.45), Vector3(0.18, 0.20, 0.10), mats.joint)
    CreateBoxPart(body, "BoosterR",   Vector3(0.20, 1.68, -0.45), Vector3(0.18, 0.20, 0.10), mats.joint)

    -- ====================================================================
    -- 左臂: ShoulderL_Joint → 肩甲 + 上臂 + ElbowL_Joint → 前臂
    -- ShoulderL_Joint 绝对位置 = (-0.95, 1.925, 0)
    -- ====================================================================
    local shoulderLJoint = body:CreateChild("ShoulderL_Joint")
    shoulderLJoint.position = Vector3(-0.72, 2.10, 0)
    joints.shoulderL = shoulderLJoint

    -- 肩甲
    CreateBoxPart(shoulderLJoint, "ShoulderL", Vector3(0, 0.22, 0), Vector3(0.42, 0.36, 0.52), mats.armor)
    -- 上臂
    CreateBoxPart(shoulderLJoint, "UpperArmL", Vector3(0, -0.22, 0), Vector3(0.26, 0.44, 0.26), mats.joint)

    -- 肘关节: 相对于肩关节 = (0, -0.44, 0)，旋转90°使前臂默认朝前
    local elbowLJoint = shoulderLJoint:CreateChild("ElbowL_Joint")
    elbowLJoint.position = Vector3(0, -0.44, 0)
    elbowLJoint.rotation = Quaternion(90, Vector3.RIGHT)
    joints.elbowL = elbowLJoint

    -- 前臂（肘关节已旋转，局部-Y=世界+Z，沿Z向前延伸）
    CreateBoxPart(elbowLJoint, "ForearmL", Vector3(0, -0.22, 0), Vector3(0.23, 0.44, 0.30), mats.body)

    -- ====================================================================
    -- 右臂: ShoulderR_Joint → 肩甲 + 上臂 + ElbowR_Joint → 前臂
    -- ShoulderR_Joint 绝对位置 = (0.82, 1.925, 0)
    -- ====================================================================
    local shoulderRJoint = body:CreateChild("ShoulderR_Joint")
    shoulderRJoint.position = Vector3(0.72, 2.10, 0)
    joints.shoulderR = shoulderRJoint

    CreateBoxPart(shoulderRJoint, "ShoulderR", Vector3(0, 0.22, 0), Vector3(0.42, 0.36, 0.52), mats.armor)
    CreateBoxPart(shoulderRJoint, "UpperArmR", Vector3(0, -0.22, 0), Vector3(0.26, 0.44, 0.26), mats.joint)

    local elbowRJoint = shoulderRJoint:CreateChild("ElbowR_Joint")
    elbowRJoint.position = Vector3(0, -0.44, 0)
    elbowRJoint.rotation = Quaternion(90, Vector3.RIGHT)
    joints.elbowR = elbowRJoint

    -- 前臂（肘关节已旋转，局部-Y=世界+Z，沿Z向前延伸）
    CreateBoxPart(elbowRJoint, "ForearmR", Vector3(0, -0.22, 0), Vector3(0.23, 0.44, 0.30), mats.body)

    -- ====================================================================
    -- 左腿: HipL_Joint → 大腿 + KneeL_Joint → 小腿 + 脚
    -- 注意: 腿不挂在 Body 下，挂在 modelNode 下，上半身摆动不影响腿
    -- ====================================================================
    local hipLJoint = modelNode:CreateChild("HipL_Joint")
    hipLJoint.position = Vector3(-0.32, 1.30, 0)
    joints.hipL = hipLJoint

    -- 大腿（加长 +0.12）
    CreateBoxPart(hipLJoint, "ThighL", Vector3(0, -0.31, 0), Vector3(0.34, 0.62, 0.38), mats.body)

    -- 膝关节（下移匹配加长大腿）
    local kneeLJoint = hipLJoint:CreateChild("KneeL_Joint")
    kneeLJoint.position = Vector3(0, -0.62, 0)
    joints.kneeL = kneeLJoint

    -- 小腿（加长 +0.13）
    CreateBoxPart(kneeLJoint, "ShinL", Vector3(0, -0.34, 0.04), Vector3(0.28, 0.68, 0.40), mats.joint)
    -- 脚（下移匹配加长小腿）
    CreateBoxPart(kneeLJoint, "FootL", Vector3(0, -0.64, 0.12), Vector3(0.35, 0.08, 0.52), mats.body)

    -- ====================================================================
    -- 右腿: HipR_Joint → 大腿 + KneeR_Joint → 小腿 + 脚
    -- ====================================================================
    local hipRJoint = modelNode:CreateChild("HipR_Joint")
    hipRJoint.position = Vector3(0.32, 1.30, 0)
    joints.hipR = hipRJoint

    CreateBoxPart(hipRJoint, "ThighR", Vector3(0, -0.31, 0), Vector3(0.34, 0.62, 0.38), mats.body)

    local kneeRJoint = hipRJoint:CreateChild("KneeR_Joint")
    kneeRJoint.position = Vector3(0, -0.62, 0)
    joints.kneeR = kneeRJoint

    CreateBoxPart(kneeRJoint, "ShinR", Vector3(0, -0.34, 0.04), Vector3(0.28, 0.68, 0.40), mats.joint)
    CreateBoxPart(kneeRJoint, "FootR", Vector3(0, -0.64, 0.12), Vector3(0.35, 0.08, 0.52), mats.body)

    -- ====================================================================
    -- 武器挂载点
    -- ====================================================================

    -- 左手武器挂载（前臂前端）
    -- 肘关节旋转 Quaternion(90, RIGHT) 使局部 -Y = 前方
    -- 武器模型沿 +Z 构建，需反旋转 -90° 让挂载点局部 +Z 对齐前臂前方
    local weaponMountL = elbowLJoint:CreateChild("WeaponMount_HandL")
    weaponMountL.position = Vector3(0, -0.44, 0)
    weaponMountL.rotation = Quaternion(-90, Vector3.RIGHT)
    joints.weaponMountHandL = weaponMountL

    -- 右手武器挂载（前臂前端）
    local weaponMountR = elbowRJoint:CreateChild("WeaponMount_HandR")
    weaponMountR.position = Vector3(0, -0.44, 0)
    weaponMountR.rotation = Quaternion(-90, Vector3.RIGHT)
    joints.weaponMountHandR = weaponMountR

    -- 左肩武器挂载（躯干左上方靠后，背包左侧）
    local weaponMountSL = body:CreateChild("WeaponMount_ShoulderL")
    weaponMountSL.position = Vector3(-0.55, 2.42, -0.28)
    weaponMountSL.scale = Vector3(1, 1, 1)
    joints.weaponMountShoulderL = weaponMountSL

    -- 右肩武器挂载（躯干右上方靠后，背包右侧）
    local weaponMountSR = body:CreateChild("WeaponMount_ShoulderR")
    weaponMountSR.position = Vector3(0.55, 2.42, -0.28)
    weaponMountSR.scale = Vector3(1, 1, 1)
    joints.weaponMountShoulderR = weaponMountSR

    -- ====================================================================
    -- 喷口 & 火焰
    -- ====================================================================

    -- 背部喷口 x2（挂在 Body 下，位于现有 Booster 下方，斜向后下方喷射）
    local backDir = Vector3(0, -0.5, -1):Normalized()
    local _, backFlameL = CreateThruster(body, "BackThrusterL",
        Vector3(-0.20, 1.58, -0.50), backDir, 0.6, variantId)
    local _, backFlameR = CreateThruster(body, "BackThrusterR",
        Vector3(0.20, 1.58, -0.50), backDir, 0.6, variantId)

    -- 左小腿喷口（挂在 KneeL_Joint 下，外侧斜向左下方喷射）
    local legDirL = Vector3(-1, -0.5, 0):Normalized()
    local _, legFlameL = CreateThruster(kneeLJoint, "LegThrusterL",
        Vector3(-0.2, -0.2, 0.04), legDirL, 0.45, variantId)

    -- 右小腿喷口（挂在 KneeR_Joint 下，外侧斜向右下方喷射）
    local legDirR = Vector3(1, -0.5, 0):Normalized()
    local _, legFlameR = CreateThruster(kneeRJoint, "LegThrusterR",
        Vector3(0.2, -0.2, 0.04), legDirR, 0.45, variantId)

    -- 火焰节点引用
    joints.backFlameL = backFlameL
    joints.backFlameR = backFlameR
    joints.legFlameL  = legFlameL
    joints.legFlameR  = legFlameR

    -- 保存火焰原始 scale（用于喷射模式动态放大）
    joints.backFlameBaseScale = Vector3(backFlameL.scale)
    joints.legFlameBaseScale  = Vector3(legFlameL.scale)

    -- ====================================================================
    -- 变体装饰物
    -- ====================================================================
    if variantId then
        local CONFIG = require("config")
        local variant = CONFIG.MechVariants[variantId]
        local decos = variant and variant.decorations
        if decos then
            for _, deco in ipairs(decos) do
                if deco.type == "antenna" then
                    -- A型：双肩通信天线（细长圆柱 + 顶部小球）
                    local antMat = CreatePBRMat(Color(0.6, 0.65, 0.7, 1.0), 0.9, 0.2)
                    local tipMat = CreatePBRMat(
                        Color(0.2, 0.5, 1.0, 1.0), 0.0, 0.1,
                        Color(0.5, 1.5, 4.0)
                    )
                    local sides = deco.side == "both" and { shoulderLJoint, shoulderRJoint } or { shoulderRJoint }
                    for si, sj in ipairs(sides) do
                        local xSign = (si == 1 and deco.side == "both") and -1 or 1
                        local antNode = sj:CreateChild("Antenna")
                        antNode.position = Vector3(xSign * 0.15, 0.55, -0.1)
                        antNode.scale = Vector3(0.04, 0.6, 0.04)
                        local antModel = antNode:CreateComponent("StaticModel")
                        antModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
                        antModel:SetMaterial(antMat)
                        antModel.castShadows = false

                        local tipNode = sj:CreateChild("AntennaTip")
                        tipNode.position = Vector3(xSign * 0.15, 0.88, -0.1)
                        tipNode.scale = Vector3(0.07, 0.07, 0.07)
                        local tipModel = tipNode:CreateComponent("StaticModel")
                        tipModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
                        tipModel:SetMaterial(tipMat)
                        tipModel.castShadows = false
                    end

                elseif deco.type == "spoiler" then
                    -- B型：背部扰流翼（轻量化速度感）
                    local spoilerMat = mats.armor
                    -- 中央横杆
                    local barNode = body:CreateChild("SpoilerBar")
                    barNode.position = Vector3(0, 2.42, -0.48)
                    barNode.scale = Vector3(1.6, 0.06, 0.2)
                    local barModel = barNode:CreateComponent("StaticModel")
                    barModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    barModel:SetMaterial(spoilerMat)
                    barModel.castShadows = true
                    -- 左支柱
                    local strutL = body:CreateChild("SpoilerStrutL")
                    strutL.position = Vector3(-0.35, 2.22, -0.45)
                    strutL.rotation = Quaternion(15, Vector3.RIGHT)
                    strutL.scale = Vector3(0.05, 0.35, 0.05)
                    local strutLModel = strutL:CreateComponent("StaticModel")
                    strutLModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
                    strutLModel:SetMaterial(mats.joint)
                    strutLModel.castShadows = false
                    -- 右支柱
                    local strutR = body:CreateChild("SpoilerStrutR")
                    strutR.position = Vector3(0.35, 2.22, -0.45)
                    strutR.rotation = Quaternion(15, Vector3.RIGHT)
                    strutR.scale = Vector3(0.05, 0.35, 0.05)
                    local strutRModel = strutR:CreateComponent("StaticModel")
                    strutRModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
                    strutRModel:SetMaterial(mats.joint)
                    strutRModel.castShadows = false

                elseif deco.type == "wings" then
                    -- C型：背部飞行翼（展开的三角翼）
                    local wingMat = mats.armor
                    local wingAccent = CreatePBRMat(
                        Color(0.7, 0.55, 0.15, 1.0), 0.0, 0.1,
                        Color(2.0, 1.5, 0.3)
                    )
                    -- 左翼
                    local wingL = body:CreateChild("WingL")
                    wingL.position = Vector3(-0.65, 2.08, -0.48)
                    wingL.rotation = Quaternion(-20, Vector3.FORWARD)
                    wingL.scale = Vector3(0.7, 0.04, 0.4)
                    local wingLModel = wingL:CreateComponent("StaticModel")
                    wingLModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    wingLModel:SetMaterial(wingMat)
                    wingLModel.castShadows = true
                    -- 左翼发光条
                    local stripL = body:CreateChild("WingStripL")
                    stripL.position = Vector3(-0.85, 2.03, -0.40)
                    stripL.rotation = Quaternion(-20, Vector3.FORWARD)
                    stripL.scale = Vector3(0.35, 0.02, 0.08)
                    local stripLModel = stripL:CreateComponent("StaticModel")
                    stripLModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    stripLModel:SetMaterial(wingAccent)
                    stripLModel.castShadows = false
                    -- 右翼
                    local wingR = body:CreateChild("WingR")
                    wingR.position = Vector3(0.65, 2.08, -0.48)
                    wingR.rotation = Quaternion(20, Vector3.FORWARD)
                    wingR.scale = Vector3(0.7, 0.04, 0.4)
                    local wingRModel = wingR:CreateComponent("StaticModel")
                    wingRModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    wingRModel:SetMaterial(wingMat)
                    wingRModel.castShadows = true
                    -- 右翼发光条
                    local stripR = body:CreateChild("WingStripR")
                    stripR.position = Vector3(0.85, 2.03, -0.40)
                    stripR.rotation = Quaternion(20, Vector3.FORWARD)
                    stripR.scale = Vector3(0.35, 0.02, 0.08)
                    local stripRModel = stripR:CreateComponent("StaticModel")
                    stripRModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    stripRModel:SetMaterial(wingAccent)
                    stripRModel.castShadows = false

                elseif deco.type == "shoulderArmor" then
                    -- D型：肩部额外重装护甲板
                    local heavyMat = mats.armor
                    -- 左肩额外护甲
                    local extraL = shoulderLJoint:CreateChild("ExtraArmorL")
                    extraL.position = Vector3(-0.12, 0.35, 0)
                    extraL.scale = Vector3(0.6, 0.12, 0.7)
                    local extraLModel = extraL:CreateComponent("StaticModel")
                    extraLModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    extraLModel:SetMaterial(heavyMat)
                    extraLModel.castShadows = true
                    -- 左肩侧裙甲
                    local skirtL = shoulderLJoint:CreateChild("SkirtArmorL")
                    skirtL.position = Vector3(-0.28, 0.1, 0)
                    skirtL.scale = Vector3(0.08, 0.5, 0.55)
                    local skirtLModel = skirtL:CreateComponent("StaticModel")
                    skirtLModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    skirtLModel:SetMaterial(heavyMat)
                    skirtLModel.castShadows = true
                    -- 右肩额外护甲
                    local extraR = shoulderRJoint:CreateChild("ExtraArmorR")
                    extraR.position = Vector3(0.12, 0.35, 0)
                    extraR.scale = Vector3(0.6, 0.12, 0.7)
                    local extraRModel = extraR:CreateComponent("StaticModel")
                    extraRModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    extraRModel:SetMaterial(heavyMat)
                    extraRModel.castShadows = true
                    -- 右肩侧裙甲
                    local skirtR = shoulderRJoint:CreateChild("SkirtArmorR")
                    skirtR.position = Vector3(0.28, 0.1, 0)
                    skirtR.scale = Vector3(0.08, 0.5, 0.55)
                    local skirtRModel = skirtR:CreateComponent("StaticModel")
                    skirtRModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    skirtRModel:SetMaterial(heavyMat)
                    skirtRModel.castShadows = true
                end
            end
        end
    end

    print("[MechBuilder] Hierarchical mech built with joints and thrusters (variant: " .. (variantId or "default") .. ")")
    return modelNode, joints
end

-- ============================================================================
-- 死亡效果系统（模型绑定）
-- ============================================================================

local DEATH_DEBRIS_LIFE = 4.0  -- 零件飞散持续时间

-- 全局飞散列表（所有机甲共享）
local allDebris_ = {}       -- { node, vel, rotVel, life, age, isExplosion, ... }
local allChainExp_ = {}     -- { timer, pos, size, scene }

--- 递归收集节点树中所有带 StaticModel 的视觉节点
---@param node Node
---@param list table
local function CollectVisualParts(node, list)
    local model = node:GetComponent("StaticModel")
    if model then
        table.insert(list, node)
    end
    for i = 0, node:GetNumChildren(false) - 1 do
        CollectVisualParts(node:GetChild(i), list)
    end
end

--- 播放机甲死亡效果：零件四散飞溅 + 多重爆炸
--- 可用于玩家和敌人的任意机甲
---@param mechRootNode Node 机甲根节点（含 ModelNode 子节点）
function MechBuilder.PlayDeathEffect(mechRootNode)
    if not mechRootNode then return end

    local modelNode = mechRootNode:GetChild("ModelNode", true)
        or mechRootNode:GetChild("TankModel", true)
        or mechRootNode:GetChild("HeliModel", true)
    if not modelNode then return end

    local scene = mechRootNode:GetScene()
    if not scene then return end

    -- 中心位置（根据模型类型调整高度）
    local isVehicle = modelNode.name == "TankModel" or modelNode.name == "HeliModel"
    local centerY = isVehicle and 0.8 or 2.0
    local centerPos = mechRootNode.worldPosition + Vector3(0, centerY, 0)

    -- 收集所有带模型的视觉节点
    local parts = {}
    CollectVisualParts(modelNode, parts)

    -- 过滤掉火焰/喷口等特效节点
    local scatterParts = {}
    for _, part in ipairs(parts) do
        local name = part.name
        if not (name:find("Flame") or name:find("Nozzle") or name:find("Trail")
                or name:find("Core") or name:find("Outer")) then
            table.insert(scatterParts, part)
        end
    end

    -- 为每个零件创建独立的飞散节点
    for _, part in ipairs(scatterParts) do
        local worldPos = part.worldPosition
        local worldRot = part.worldRotation
        local worldScale = part.worldScale

        local srcModel = part:GetComponent("StaticModel")
        if not srcModel then goto continue end
        local srcMdl = srcModel:GetModel()
        local srcMat = srcModel:GetMaterial(0)
        if not srcMdl then goto continue end

        local debrisNode = scene:CreateChild("Debris_" .. part.name)
        debrisNode.worldPosition = worldPos
        debrisNode.worldRotation = worldRot
        debrisNode.scale = worldScale

        local debrisModel = debrisNode:CreateComponent("StaticModel")
        debrisModel:SetModel(srcMdl)
        if srcMat then
            debrisModel:SetMaterial(srcMat)
        end
        debrisModel.castShadows = false

        -- 从中心向外的随机抛射速度
        local toPartDir = (worldPos - centerPos)
        if toPartDir:Length() < 0.01 then
            toPartDir = Vector3(math.random() - 0.5, math.random(), math.random() - 0.5)
        end
        toPartDir = toPartDir:Normalized()

        local radialSpeed = 6.0 + math.random() * 8.0
        local vel = toPartDir * radialSpeed
            + Vector3(
                (math.random() - 0.5) * 4.0,
                3.0 + math.random() * 5.0,
                (math.random() - 0.5) * 4.0
            )

        local rotVel = Vector3(
            (math.random() - 0.5) * 720,
            (math.random() - 0.5) * 720,
            (math.random() - 0.5) * 720
        )

        table.insert(allDebris_, {
            node = debrisNode,
            vel = vel,
            rotVel = rotVel,
            life = DEATH_DEBRIS_LIFE,
            age = 0,
        })

        ::continue::
    end

    -- 隐藏原始机甲模型
    modelNode:SetDeepEnabled(false)

    -- 主爆炸
    local mainExpNode = scene:CreateChild("DeathExplosion")
    mainExpNode.position = centerPos
    local expScale = 4.0
    mainExpNode.scale = Vector3(expScale, expScale, expScale)
    local expModel = mainExpNode:CreateComponent("StaticModel")
    expModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local expMat = Material:new()
    expMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    expMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.1, 0.9)))
    expMat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 4.0, 1.0)))
    expMat:SetShaderParameter("Metallic", Variant(0.0))
    expMat:SetShaderParameter("Roughness", Variant(0.1))
    expModel:SetMaterial(expMat)
    expModel.castShadows = false

    table.insert(allDebris_, {
        node = mainExpNode,
        vel = Vector3.ZERO,
        rotVel = Vector3.ZERO,
        life = 0.6,
        age = 0,
        isExplosion = true,
        mat = expMat,
        maxScale = 8.0,
        initScale = expScale,
        color = Color(1.0, 0.6, 0.1),
    })

    -- 连锁小爆炸
    for i = 1, 5 do
        local offset = Vector3(
            (math.random() - 0.5) * 4.0,
            (math.random() - 0.5) * 3.0 + 1.5,
            (math.random() - 0.5) * 4.0
        )
        table.insert(allChainExp_, {
            timer = 0.1 + math.random() * 0.4,
            pos = centerPos + offset,
            size = 1.5 + math.random() * 2.5,
            scene = scene,
        })
    end

    print("[MechBuilder] Death effect triggered: " .. #scatterParts .. " parts scattered")
end

--- 更新所有死亡飞散效果（每帧调用一次）
---@param dt number
function MechBuilder.UpdateDeathEffects(dt)
    local gravity = Vector3(0, -15.0, 0)

    -- 更新飞散零件
    local i = 1
    while i <= #allDebris_ do
        local d = allDebris_[i]
        d.age = d.age + dt

        if d.age >= d.life then
            d.node:Remove()
            table.remove(allDebris_, i)
        elseif d.isExplosion then
            local progress = d.age / d.life
            local scaleFactor = d.initScale + (d.maxScale - d.initScale) * math.min(1.0, progress * 3.0)
            d.node.scale = Vector3(scaleFactor, scaleFactor, scaleFactor)
            local alpha = 0.9 * (1.0 - progress)
            local c = d.color
            d.mat:SetShaderParameter("MatDiffColor", Variant(Color(c.r, c.g, c.b, alpha)))
            local emMul = math.max(0, 8.0 * (1.0 - progress * 2.0))
            d.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(c.r * emMul, c.g * emMul, c.b * emMul * 0.5)))
            i = i + 1
        else
            d.vel = d.vel + gravity * dt
            d.node.position = d.node.position + d.vel * dt

            local rx = d.rotVel.x * dt
            local ry = d.rotVel.y * dt
            local rz = d.rotVel.z * dt
            d.node.rotation = d.node.rotation * Quaternion(rx, Vector3.RIGHT)
                * Quaternion(ry, Vector3.UP) * Quaternion(rz, Vector3.FORWARD)

            -- 地面碰撞
            if d.node.position.y < 0.1 then
                local p = d.node.position
                d.node.position = Vector3(p.x, 0.1, p.z)
                d.vel = Vector3(d.vel.x * 0.5, math.abs(d.vel.y) * 0.2, d.vel.z * 0.5)
                d.rotVel = d.rotVel * 0.5
            end

            -- 淡出缩小（最后1秒）
            local fadeStart = d.life - 1.0
            if d.age > fadeStart then
                local fadeT = (d.age - fadeStart) / 1.0
                local s = d.node.scale
                local shrink = 1.0 - fadeT * 0.8
                d.node.scale = Vector3(s.x * shrink, s.y * shrink, s.z * shrink)
            end

            i = i + 1
        end
    end

    -- 更新连锁爆炸
    local j = 1
    while j <= #allChainExp_ do
        local ex = allChainExp_[j]
        ex.timer = ex.timer - dt
        if ex.timer <= 0 then
            local expNode = ex.scene:CreateChild("ChainExplosion")
            expNode.position = ex.pos
            local s = ex.size * 0.4
            expNode.scale = Vector3(s, s, s)
            local model = expNode:CreateComponent("StaticModel")
            model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
            local mat = Material:new()
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.5, 0.1, 0.85)))
            mat:SetShaderParameter("MatEmissiveColor", Variant(Color(6.0, 3.0, 0.8)))
            mat:SetShaderParameter("Metallic", Variant(0.0))
            mat:SetShaderParameter("Roughness", Variant(0.1))
            model:SetMaterial(mat)
            model.castShadows = false

            table.insert(allDebris_, {
                node = expNode,
                vel = Vector3.ZERO,
                rotVel = Vector3.ZERO,
                life = 0.45,
                age = 0,
                isExplosion = true,
                mat = mat,
                maxScale = ex.size,
                initScale = s,
                color = Color(1.0, 0.5, 0.1),
            })

            table.remove(allChainExp_, j)
        else
            j = j + 1
        end
    end
end

--- 是否有正在播放的死亡效果
---@return boolean
function MechBuilder.HasActiveDeathEffects()
    return #allDebris_ > 0 or #allChainExp_ > 0
end

return MechBuilder
