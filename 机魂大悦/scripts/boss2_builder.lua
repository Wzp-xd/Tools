-- ============================================================================
-- BOSS2 大型四轴无人机构建器 - Heavy Armed Quadcopter Drone
-- Boss2Builder - Military Quadcopter with Mounted Machine Guns
-- ============================================================================
-- 结构层级:
--   modelNode
--   ├── Body (中央机身, 隐身涂装)
--   ├── CargoPlatform (顶部搭载平台, 可放置BOSS战车)
--   │   └── CargoMountPoint (战车挂载点节点)
--   ├── Arm_FL/FR/RL/RR (4条对角臂, 各自旋转yaw)
--   │   ├── ArmBeam + ArmStrut (臂结构)
--   │   ├── Motor + Rotor (顶部电机和旋翼)
--   │   └── GunYaw_XX ← 机枪云台yaw层 (绕Y轴水平旋转)
--   │       └── GunPitch_XX ← 机枪云台pitch层 (绕X轴俯仰)
--   │           ├── GunBody + GunBarrel + Muzzle (机枪)
--   │           └── FirePoint_XX (发射点)
--   ├── LandingGear (起落架)
--   └── Details (传感器, 天线, 导航灯)
--
-- 返回值: modelNode, result
--   result.gunYawJoints[]   4个机枪yaw关节 (水平旋转)
--   result.gunPitchJoints[] 4个机枪pitch关节 (俯仰旋转)
--   result.firePoints[]     4个机枪发射点节点
--   result.cargoMountPoint  顶部战车挂载点节点
--   result:SetGunYaw(index, deg)      设置指定机枪水平角
--   result:SetGunPitch(index, deg)    设置指定机枪俯仰角
--   result:GetGunFireData()           获取4机枪发射点世界坐标+朝向
--   result:AimGunAt(index, worldPos)  单独瞄准一把机枪到目标
--   result:AimGunsAt(worldPos)        所有机枪瞄准目标
--   result:MountBoss(bossModelNode)   在搭载平台上挂载BOSS战车
-- ============================================================================

local Boss2Builder = {}

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
        body    = PBR(Color(0.12, 0.12, 0.14, 1.0), 0.6, 0.5),     -- 深灰隐身机身
        arm     = PBR(Color(0.08, 0.08, 0.10, 1.0), 0.4, 0.6),     -- 碳纤维臂
        motor   = PBR(Color(0.10, 0.10, 0.12, 1.0), 0.85, 0.3),    -- 电机外壳
        rotor   = PBR(Color(0.18, 0.18, 0.20, 0.8), 0.3, 0.4),     -- 旋翼盘
        gun     = PBR(Color(0.10, 0.10, 0.10, 1.0), 0.9, 0.25),    -- 枪身金属
        barrel  = PBR(Color(0.08, 0.08, 0.10, 1.0), 0.9, 0.2),     -- 枪管
        armor   = PBR(Color(0.14, 0.14, 0.16, 1.0), 0.7, 0.45),    -- 装甲板
        sensor  = PBR(Color(0.1, 0.4, 0.5, 1.0), 0.1, 0.15, Color(0.3, 1.2, 1.5)),  -- 传感器
        accent  = PBR(Color(0.7, 0.15, 0.08, 1.0), 0.3, 0.6, Color(1.5, 0.3, 0.1)), -- 红色警示
        navG    = PBR(Color(0.1, 0.8, 0.1, 1.0), 0.1, 0.3, Color(0.2, 1.5, 0.2)),   -- 绿色导航灯
        navR    = PBR(Color(0.8, 0.1, 0.1, 1.0), 0.1, 0.3, Color(1.5, 0.2, 0.2)),   -- 红色导航灯
    }
    return mats_
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function CreateBox(parent, name, pos, scale, mat, rot)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    if rot then node.rotation = rot end
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
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
    model.castShadows = true
    return node
end

local function CreateSphere(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

-- ============================================================================
-- BOSS2 四轴无人机构建 (翼展~7m, 高~2.8m)
-- ============================================================================

--- 构建 BOSS2 四轴无人机模型
---@param parentNode Node
---@return Node modelNode
---@return table result
function Boss2Builder.Build(parentNode)
    local m = GetMaterials()
    local modelNode = parentNode:CreateChild("Boss2Model")

    local bodyY = 2.0  -- 机身中心高度 (悬停)

    -- ==================================================================
    -- 中央机身 (1.6 x 0.5 x 1.8, 前方略尖)
    -- ==================================================================
    CreateBox(modelNode, "BodyMain", Vector3(0, bodyY, 0), Vector3(1.6, 0.5, 1.8), m.body)

    -- 顶部装甲盖板
    CreateBox(modelNode, "BodyTop", Vector3(0, bodyY + 0.28, 0), Vector3(1.4, 0.06, 1.5), m.armor)

    -- 底部装甲板
    CreateBox(modelNode, "BodyBottom", Vector3(0, bodyY - 0.28, 0), Vector3(1.3, 0.06, 1.3), m.armor)

    -- 前部整流罩 (收窄, 略下倾)
    CreateBox(modelNode, "Nose", Vector3(0, bodyY - 0.02, 0.95),
        Vector3(0.8, 0.35, 0.3), m.body, Quaternion(-8, Vector3.RIGHT))

    -- 前部装甲尖角
    CreateBox(modelNode, "NoseTip", Vector3(0, bodyY - 0.05, 1.15),
        Vector3(0.4, 0.2, 0.15), m.armor, Quaternion(-12, Vector3.RIGHT))

    -- 后部尾翼 (竖直稳定翼)
    CreateBox(modelNode, "TailFinV", Vector3(0, bodyY + 0.3, -0.95),
        Vector3(0.08, 0.35, 0.25), m.armor)

    -- 后部尾翼 (水平)
    CreateBox(modelNode, "TailFinH", Vector3(0, bodyY + 0.15, -0.95),
        Vector3(0.7, 0.06, 0.2), m.armor)

    -- ==================================================================
    -- 机身传感器和细节
    -- ==================================================================

    -- 前置摄像头/瞄准传感器
    CreateSphere(modelNode, "FrontCamera", Vector3(0, bodyY - 0.12, 1.25),
        Vector3(0.2, 0.18, 0.15), m.sensor)

    -- 底部光电吊舱 (球形, 侦察/瞄准用)
    CreateSphere(modelNode, "OpticalPod", Vector3(0, bodyY - 0.45, 0.2),
        Vector3(0.4, 0.3, 0.4), m.sensor)
    -- 吊舱支架
    CreateCylinder(modelNode, "PodMount", Vector3(0, bodyY - 0.32, 0.2),
        Vector3(0.15, 0.08, 0.15), m.motor)

    -- ==================================================================
    -- 顶部搭载框架 (镂空桁架结构, 可放置BOSS战车)
    -- ==================================================================

    -- 纵向主梁 (两根承重工字梁, 对应战车履带位置)
    CreateBox(modelNode, "FrameBeamL", Vector3(-1.5, bodyY + 0.30, 0),
        Vector3(0.18, 0.12, 6.2), m.armor)
    CreateBox(modelNode, "FrameBeamR", Vector3(1.5, bodyY + 0.30, 0),
        Vector3(0.18, 0.12, 6.2), m.armor)

    -- 横向连接梁 (5根, 等间距)
    for i = -2, 2 do
        CreateBox(modelNode, "FrameCross" .. (i + 3), Vector3(0, bodyY + 0.30, i * 1.4),
            Vector3(3.2, 0.10, 0.12), m.motor)
    end

    -- 斜撑 (X形交叉加强, 前后各一组)
    for _, brace in ipairs({
        { x1 = -1.4, z1 = 1.5, x2 = 1.4, z2 = 2.8 },
        { x1 = 1.4, z1 = 1.5, x2 = -1.4, z2 = 2.8 },
        { x1 = -1.4, z1 = -2.8, x2 = 1.4, z2 = -1.5 },
        { x1 = 1.4, z1 = -2.8, x2 = -1.4, z2 = -1.5 },
    }) do
        local cx = (brace.x1 + brace.x2) / 2
        local cz = (brace.z1 + brace.z2) / 2
        local dx = brace.x2 - brace.x1
        local dz = brace.z2 - brace.z1
        local len = math.sqrt(dx * dx + dz * dz)
        local angle = math.deg(math.atan(dx, dz))
        CreateBox(modelNode, "FrameBrace", Vector3(cx, bodyY + 0.28, cz),
            Vector3(0.06, 0.06, len), m.motor, Quaternion(angle, Vector3.UP))
    end

    -- 四角限位挡块
    for _, g in ipairs({
        { x = -1.6, z = 2.9 }, { x = 1.6, z = 2.9 },
        { x = -1.6, z = -2.9 }, { x = 1.6, z = -2.9 },
    }) do
        CreateBox(modelNode, "FrameGuard", Vector3(g.x, bodyY + 0.42, g.z),
            Vector3(0.14, 0.18, 0.14), m.armor)
    end

    -- 液压锁定夹具 (4组, 用于固定战车履带)
    for _, clamp in ipairs({
        { x = -1.5, z = 1.8 }, { x = 1.5, z = 1.8 },
        { x = -1.5, z = -1.8 }, { x = 1.5, z = -1.8 },
    }) do
        -- 夹具底座
        CreateBox(modelNode, "ClampBase", Vector3(clamp.x, bodyY + 0.38, clamp.z),
            Vector3(0.22, 0.05, 0.28), m.motor)
        -- 夹具臂 (L形)
        CreateBox(modelNode, "ClampArm", Vector3(clamp.x, bodyY + 0.46, clamp.z),
            Vector3(0.06, 0.12, 0.18), m.gun)
    end

    -- 战车挂载点 (空节点, 战车会被放置于此)
    local cargoMountPoint = modelNode:CreateChild("CargoMountPoint")
    cargoMountPoint.position = Vector3(0, bodyY + 0.38, 0)

    -- 平台边缘的通信天线 (移到侧面, 不占中央空间)
    CreateCylinder(modelNode, "AntennaMain", Vector3(-1.9, bodyY + 0.55, -0.3),
        Vector3(0.03, 0.45, 0.03), m.motor)
    CreateSphere(modelNode, "AntennaTop", Vector3(-1.9, bodyY + 0.8, -0.3),
        Vector3(0.06, 0.06, 0.06), m.accent)

    -- 卫星通信天线 (移到侧面)
    CreateCylinder(modelNode, "SatDish", Vector3(1.9, bodyY + 0.48, -0.5),
        Vector3(0.2, 0.04, 0.2), m.armor)
    CreateCylinder(modelNode, "SatDishStalk", Vector3(1.9, bodyY + 0.42, -0.5),
        Vector3(0.04, 0.05, 0.04), m.motor)

    -- 导航灯
    CreateSphere(modelNode, "NavLightFront", Vector3(0, bodyY, 1.3),
        Vector3(0.08, 0.08, 0.08), m.navG)
    CreateSphere(modelNode, "NavLightRear", Vector3(0, bodyY, -1.0),
        Vector3(0.08, 0.08, 0.08), m.navR)
    CreateSphere(modelNode, "NavLightLeft", Vector3(-0.85, bodyY, 0),
        Vector3(0.06, 0.06, 0.06), m.navR)
    CreateSphere(modelNode, "NavLightRight", Vector3(0.85, bodyY, 0),
        Vector3(0.06, 0.06, 0.06), m.navG)

    -- 机身侧面进气格栅
    CreateBox(modelNode, "IntakeL", Vector3(-0.82, bodyY + 0.05, 0.2),
        Vector3(0.04, 0.2, 0.5), m.motor)
    CreateBox(modelNode, "IntakeR", Vector3(0.82, bodyY + 0.05, 0.2),
        Vector3(0.04, 0.2, 0.5), m.motor)

    -- 机身底部散热片
    for i = -2, 2 do
        CreateBox(modelNode, "HeatFin" .. (i + 3), Vector3(i * 0.2, bodyY - 0.32, -0.3),
            Vector3(0.03, 0.04, 0.4), m.motor)
    end

    -- ==================================================================
    -- 4条对角臂 + 电机 + 旋翼 + 机枪
    -- X构型: FL(-45°), FR(45°), RL(-135°), RR(135°)
    -- ==================================================================
    local armData = {
        { name = "FL", yaw = -45 },    -- 前左
        { name = "FR", yaw = 45 },     -- 前右
        { name = "RL", yaw = -135 },   -- 后左
        { name = "RR", yaw = 135 },    -- 后右
    }

    local gunYawJoints = {}
    local gunPitchJoints = {}
    local firePoints = {}
    local barrelRot = Quaternion(90, Vector3.RIGHT)

    for idx, arm in ipairs(armData) do
        -- 臂根节点 (位于机身中心, 按yaw旋转)
        local armNode = modelNode:CreateChild("Arm_" .. arm.name)
        armNode.position = Vector3(0, bodyY, 0)
        armNode.rotation = Quaternion(arm.yaw, Vector3.UP)

        -- ====== 臂结构 (沿局部+Z方向延伸) ======

        -- 主臂梁 (碳纤维方管)
        CreateBox(armNode, "ArmBeam_" .. arm.name,
            Vector3(0, 0, 1.3), Vector3(0.28, 0.15, 2.2), m.arm)

        -- 下部加强支撑
        CreateBox(armNode, "ArmStrut_" .. arm.name,
            Vector3(0, -0.12, 1.3), Vector3(0.14, 0.06, 1.8), m.armor)

        -- 臂根部加强筋 (与机身连接处)
        CreateBox(armNode, "ArmRoot_" .. arm.name,
            Vector3(0, 0, 0.3), Vector3(0.35, 0.2, 0.4), m.armor)

        -- 臂中段线缆护罩
        CreateBox(armNode, "ArmCover_" .. arm.name,
            Vector3(0, 0.1, 1.0), Vector3(0.18, 0.06, 0.8), m.motor)

        -- ====== 电机 + 多层旋翼结构 (臂末端顶部) ======
        local mz = 2.5  -- 电机中心Z位置

        -- 底层: 电机安装座 (宽法兰盘)
        CreateCylinder(armNode, "MotorBase_" .. arm.name,
            Vector3(0, -0.02, mz), Vector3(0.65, 0.06, 0.65), m.motor)

        -- 底层散热环 (带间隙的环形)
        CreateCylinder(armNode, "MotorBaseRing_" .. arm.name,
            Vector3(0, 0.02, mz), Vector3(0.72, 0.04, 0.72), m.armor)

        -- 电机主体 (多段圆柱叠加, 营造层次)
        CreateCylinder(armNode, "MotorLower_" .. arm.name,
            Vector3(0, 0.08, mz), Vector3(0.5, 0.10, 0.5), m.motor)
        CreateCylinder(armNode, "MotorMid_" .. arm.name,
            Vector3(0, 0.16, mz), Vector3(0.42, 0.08, 0.42), m.gun)
        CreateCylinder(armNode, "MotorUpper_" .. arm.name,
            Vector3(0, 0.24, mz), Vector3(0.5, 0.08, 0.5), m.motor)

        -- 电机散热片 (4片径向翅片)
        for fi = 0, 3 do
            local fAngle = fi * 90
            CreateBox(armNode, "MotorFin" .. fi .. "_" .. arm.name,
                Vector3(0, 0.14, mz), Vector3(0.58, 0.14, 0.04), m.motor,
                Quaternion(fAngle, Vector3.UP))
        end

        -- 电机顶盖
        CreateCylinder(armNode, "MotorCap_" .. arm.name,
            Vector3(0, 0.30, mz), Vector3(0.22, 0.06, 0.22), m.armor)

        -- ====== 旋翼层 (3层圆环+桨叶, 由下到上) ======

        -- 第1层: 下防护环 (大直径细环)
        CreateCylinder(armNode, "RotorGuardLow_" .. arm.name,
            Vector3(0, 0.30, mz), Vector3(2.1, 0.03, 2.1), m.arm)

        -- 第2层: 主旋翼盘 (半透明)
        CreateCylinder(armNode, "RotorDisc_" .. arm.name,
            Vector3(0, 0.36, mz), Vector3(2.0, 0.03, 2.0), m.rotor)

        -- 第3层: 上防护环 (稍小直径)
        CreateCylinder(armNode, "RotorGuardHigh_" .. arm.name,
            Vector3(0, 0.42, mz), Vector3(1.85, 0.03, 1.85), m.arm)

        -- 旋翼轴心毂
        CreateCylinder(armNode, "RotorHub_" .. arm.name,
            Vector3(0, 0.33, mz), Vector3(0.15, 0.10, 0.15), m.motor)

        -- 桨叶支撑臂 (6根径向辐条, 连接轴心到防护环)
        for si = 0, 5 do
            local sAngle = si * 60
            CreateBox(armNode, "RotorSpoke" .. si .. "_" .. arm.name,
                Vector3(0, 0.36, mz), Vector3(0.04, 0.04, 0.95), m.arm,
                Quaternion(sAngle, Vector3.UP))
        end

        -- 防护环垂直支柱 (4根, 连接上下环)
        for pi = 0, 3 do
            local pAngle = pi * 90 + 45
            local pr = 0.95  -- 略小于旋翼半径
            local px = math.sin(math.rad(pAngle)) * pr
            local pz2 = mz + math.cos(math.rad(pAngle)) * pr
            CreateCylinder(armNode, "GuardStrut" .. pi .. "_" .. arm.name,
                Vector3(px, 0.36, pz2), Vector3(0.03, 0.14, 0.03), m.arm)
        end

        -- 臂末端信号灯 (在防护环外侧)
        CreateSphere(armNode, "ArmLight_" .. arm.name,
            Vector3(0, 0.36, mz + 1.05), Vector3(0.06, 0.06, 0.06), m.accent)

        -- ====== 机枪双轴云台 (臂末端下方) ======
        -- 第1层: Yaw关节 (绕Y轴水平旋转)
        local gunYaw = armNode:CreateChild("GunYaw_" .. arm.name)
        gunYaw.position = Vector3(0, -0.22, 2.5)

        -- yaw层旋转轴承 (水平转盘)
        CreateCylinder(gunYaw, "GunYawRing_" .. arm.name,
            Vector3(0, 0.1, 0), Vector3(0.26, 0.06, 0.26), m.motor)

        -- 第2层: Pitch关节 (绕X轴俯仰旋转)
        local gunPitch = gunYaw:CreateChild("GunPitch_" .. arm.name)
        gunPitch.position = Vector3(0, 0, 0)

        -- pitch层旋转轴承 (侧面小圆柱)
        CreateCylinder(gunPitch, "GunPitchAxisL_" .. arm.name,
            Vector3(-0.12, 0.02, 0), Vector3(0.06, 0.06, 0.06), m.motor)
        CreateCylinder(gunPitch, "GunPitchAxisR_" .. arm.name,
            Vector3(0.12, 0.02, 0), Vector3(0.06, 0.06, 0.06), m.motor)

        -- 机枪主体
        CreateBox(gunPitch, "GunBody_" .. arm.name,
            Vector3(0, -0.02, 0.1), Vector3(0.22, 0.18, 0.45), m.gun)

        -- 机枪上方散热片
        CreateBox(gunPitch, "GunHeatSink_" .. arm.name,
            Vector3(0, 0.08, 0.15), Vector3(0.18, 0.04, 0.3), m.motor)

        -- 弹药箱 (侧面)
        CreateBox(gunPitch, "AmmoBox_" .. arm.name,
            Vector3(0.16, -0.02, -0.05), Vector3(0.1, 0.14, 0.22), m.armor)

        -- 弹链导管 (连接弹药箱到枪身)
        CreateCylinder(gunPitch, "AmmoFeed_" .. arm.name,
            Vector3(0.1, 0.02, 0.1), Vector3(0.04, 0.2, 0.04), m.motor,
            Quaternion(30, Vector3.FORWARD))

        -- 枪管
        CreateCylinder(gunPitch, "GunBarrel_" .. arm.name,
            Vector3(0, -0.02, 0.85), Vector3(0.06, 1.0, 0.06), m.barrel, barrelRot)

        -- 枪管散热护套 (多孔)
        CreateCylinder(gunPitch, "BarrelShroud_" .. arm.name,
            Vector3(0, -0.02, 0.55), Vector3(0.1, 0.4, 0.1), m.gun, barrelRot)

        -- 枪口消焰器
        CreateCylinder(gunPitch, "Muzzle_" .. arm.name,
            Vector3(0, -0.02, 1.4), Vector3(0.09, 0.12, 0.09), m.barrel, barrelRot)

        -- 瞄准传感器 (枪身上方)
        CreateBox(gunPitch, "GunSensor_" .. arm.name,
            Vector3(0, 0.12, 0.3), Vector3(0.1, 0.08, 0.15), m.motor)
        CreateSphere(gunPitch, "GunSensorLens_" .. arm.name,
            Vector3(0, 0.12, 0.4), Vector3(0.06, 0.06, 0.04), m.sensor)

        -- ====== 发射点标记 (枪口前端) ======
        local fp = gunPitch:CreateChild("FirePoint_" .. arm.name)
        fp.position = Vector3(0, -0.02, 1.5)

        gunYawJoints[idx] = gunYaw
        gunPitchJoints[idx] = gunPitch
        firePoints[idx] = fp
    end

    -- ==================================================================
    -- 起落架 (4组, 位于机身四角下方)
    -- ==================================================================
    local legData = {
        { name = "FL", x = -0.55, z = 0.65 },
        { name = "FR", x = 0.55,  z = 0.65 },
        { name = "RL", x = -0.55, z = -0.65 },
        { name = "RR", x = 0.55,  z = -0.65 },
    }
    for _, leg in ipairs(legData) do
        -- 斜支撑杆 (从机身向外下方延伸)
        CreateCylinder(modelNode, "LegStrut_" .. leg.name,
            Vector3(leg.x, bodyY - 0.6, leg.z), Vector3(0.05, 0.55, 0.05), m.arm,
            Quaternion(leg.x > 0 and 8 or -8, Vector3.FORWARD))

        -- 水平滑橇
        CreateBox(modelNode, "LegSkid_" .. leg.name,
            Vector3(leg.x * 1.15, bodyY - 0.9, leg.z), Vector3(0.06, 0.04, 0.6), m.arm)

        -- 减震器 (弹簧状, 用小圆柱模拟)
        CreateCylinder(modelNode, "LegDamper_" .. leg.name,
            Vector3(leg.x * 0.9, bodyY - 0.45, leg.z), Vector3(0.08, 0.15, 0.08), m.motor)
    end

    -- 前后滑橇横梁
    CreateBox(modelNode, "SkidCrossF",
        Vector3(0, bodyY - 0.9, 0.65), Vector3(1.35, 0.04, 0.05), m.arm)
    CreateBox(modelNode, "SkidCrossR",
        Vector3(0, bodyY - 0.9, -0.65), Vector3(1.35, 0.04, 0.05), m.arm)

    -- ==================================================================
    -- 机身下挂武器/设备挂架 (备用)
    -- ==================================================================
    CreateBox(modelNode, "WeaponPylonL", Vector3(-0.5, bodyY - 0.35, 0),
        Vector3(0.06, 0.12, 0.6), m.armor)
    CreateBox(modelNode, "WeaponPylonR", Vector3(0.5, bodyY - 0.35, 0),
        Vector3(0.06, 0.12, 0.6), m.armor)

    -- ==================================================================
    -- 关节与发射点表 (供AI/战斗系统使用)
    -- ==================================================================
    local result = {
        -- 4个机枪yaw关节 (绕Y轴水平旋转, 相对于臂方向)
        gunYawJoints = gunYawJoints,
        -- 4个机枪pitch关节 (绕X轴俯仰旋转)
        gunPitchJoints = gunPitchJoints,
        -- 4个机枪发射点节点
        firePoints = firePoints,
        -- 顶部战车挂载点
        cargoMountPoint = cargoMountPoint,
    }

    --- 设置指定机枪的水平偏转角 (度, 相对于臂默认方向)
    ---@param index number 机枪索引 1=FL, 2=FR, 3=RL, 4=RR
    ---@param yawDeg number 水平偏转角, 0=沿臂方向, 正值=右偏, 负值=左偏
    function result:SetGunYaw(index, yawDeg)
        self.gunYawJoints[index].rotation = Quaternion(yawDeg, Vector3.UP)
    end

    --- 设置指定机枪的俯仰角 (度)
    ---@param index number 机枪索引 1=FL, 2=FR, 3=RL, 4=RR
    ---@param pitchDeg number 俯仰角, 0=水平, 正值=下俯, 负值=上仰
    function result:SetGunPitch(index, pitchDeg)
        self.gunPitchJoints[index].rotation = Quaternion(pitchDeg, Vector3.RIGHT)
    end

    --- 获取4个机枪发射点的世界坐标和朝向
    ---@return table[] { { position: Vector3, direction: Vector3 }, ... }
    function result:GetGunFireData()
        local data = {}
        for i, fp in ipairs(self.firePoints) do
            data[i] = {
                position  = fp.worldPosition,
                direction = fp.worldRotation * Vector3.FORWARD,
            }
        end
        return data
    end

    --- 单独瞄准一把机枪到目标 (自动计算yaw+pitch)
    ---@param index number 机枪索引 1=FL, 2=FR, 3=RL, 4=RR
    ---@param targetWorldPos Vector3 目标世界坐标
    function result:AimGunAt(index, targetWorldPos)
        local yawJoint = self.gunYawJoints[index]
        local mountWorldPos = yawJoint.worldPosition
        local toTarget = targetWorldPos - mountWorldPos
        -- 将目标方向转换到臂的局部空间 (yaw关节的父节点是臂节点)
        local armWorldRot = yawJoint.parent.worldRotation
        local localDir = armWorldRot:Inverse() * toTarget
        -- localDir: x=左右, y=上下, z=沿臂前方
        -- 计算yaw (水平偏转, 在XZ平面)
        local yaw = math.deg(math.atan(localDir.x, math.max(math.abs(localDir.z), 0.1)))
        -- 计算pitch (俯仰, 考虑水平距离)
        local horizDist = math.sqrt(localDir.x * localDir.x + localDir.z * localDir.z)
        local pitch = -math.deg(math.atan(localDir.y, math.max(horizDist, 0.1)))
        -- 机枪仰角限制：最大上仰10度（pitch约定: 正=下俯, 负=上仰）
        pitch = math.max(-10.0, pitch)
        self:SetGunYaw(index, yaw)
        self:SetGunPitch(index, pitch)
    end

    --- 所有机枪瞄准同一个世界坐标目标
    ---@param targetWorldPos Vector3 目标世界坐标
    function result:AimGunsAt(targetWorldPos)
        for i = 1, 4 do
            self:AimGunAt(i, targetWorldPos)
        end
    end

    --- 在搭载平台上挂载BOSS战车节点
    ---@param bossNode Node 已构建好的BOSS战车模型根节点
    function result:MountBoss(bossNode)
        bossNode.parent = self.cargoMountPoint
        bossNode.position = Vector3.ZERO
        bossNode.rotation = Quaternion.IDENTITY
    end

    return modelNode, result
end

return Boss2Builder
