-- ============================================================================
-- BOSS 战车构建器 - 大型履带战车 + 炮台(炮管+飞弹舱)
-- BossBuilder - Heavy Tracked War Machine with Turret
-- ============================================================================
-- 结构层级:
--   modelNode
--   ├── Hull (车体底盘, ~6m长 3.5m宽 1.2m高)
--   ├── TrackL / TrackR (两条履带)
--   ├── Superstructure (上层结构/炮塔基座)
--   └── TurretJoint ← 主炮塔 (绕Y轴yaw旋转)
--       ├── TurretLower/Mid/Upper (三层梯形炮塔)
--       ├── SubTurretJointL ← 左二级炮塔 (绕X轴pitch俯仰)
--       │   ├── BarrelUpL / BarrelDnL (2根炮管)
--       │   ├── FirePoint_UpL / FirePoint_DnL (炮弹发射点)
--       │   └── SubTurretRingL (内侧轴承环)
--       ├── SubTurretJointR ← 右二级炮塔 (绕X轴pitch俯仰)
--       │   ├── BarrelUpR / BarrelDnR (2根炮管)
--       │   ├── FirePoint_UpR / FirePoint_DnR (炮弹发射点)
--       │   └── SubTurretRingR (内侧轴承环)
--       ├── MissileBay + MissileTube1..4 (垂直飞弹舱)
--       └── MissilePoint1..4 (飞弹发射点, 方向+Y)
--
-- 返回值: modelNode, result
--   result.turret        主炮塔关节
--   result.subTurretL/R  二级炮塔关节
--   result.firePoints[]  4个炮弹发射点节点 (左上/左下/右上/右下)
--   result.missilePoints[] 4个飞弹发射点节点
--   result:SetTurretYaw(deg)          设置主炮塔水平角
--   result:SetSubTurretPitch(side,deg) 设置二级炮塔俯仰角
--   result:GetBarrelFireData()        获取4炮管发射点世界坐标+朝向
--   result:GetMissileFireData()       获取4飞弹发射点世界坐标+方向
--   result:AimAt(worldPos, side)      自动瞄准目标
-- ============================================================================

local BossBuilder = {}

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
        hull     = PBR(Color(0.14, 0.16, 0.12, 1.0), 0.7, 0.5),    -- 深橄榄绿车体
        armor    = PBR(Color(0.18, 0.20, 0.14, 1.0), 0.75, 0.45),   -- 略浅装甲板
        track    = PBR(Color(0.06, 0.06, 0.05, 1.0), 0.3, 0.85),    -- 深灰履带
        turret   = PBR(Color(0.16, 0.18, 0.13, 1.0), 0.8, 0.4),     -- 炮塔
        barrel   = PBR(Color(0.10, 0.10, 0.12, 1.0), 0.9, 0.25),    -- 金属炮管
        missile  = PBR(Color(0.12, 0.14, 0.10, 1.0), 0.6, 0.5),     -- 飞弹舱体
        mgMetal  = PBR(Color(0.08, 0.08, 0.10, 1.0), 0.85, 0.3),    -- 机枪金属
        accent   = PBR(Color(0.7, 0.15, 0.08, 1.0), 0.3, 0.6, Color(1.5, 0.3, 0.1)), -- 红色警示发光
        lens     = PBR(Color(0.1, 0.4, 0.5, 1.0), 0.1, 0.15, Color(0.3, 1.2, 1.5)),  -- 青色传感器
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
-- BOSS 战车构建 (~3.0m高, 6.0m长, 3.5m宽)
-- ============================================================================

--- 构建 BOSS 战车模型
---@param parentNode Node
---@return Node modelNode
---@return table joints
function BossBuilder.Build(parentNode)
    local m = GetMaterials()
    local modelNode = parentNode:CreateChild("BossModel")

    -- ==================================================================
    -- 底盘 (6.0 x 1.2 x 3.5)
    -- ==================================================================
    CreateBox(modelNode, "Hull", Vector3(0, 0.7, 0), Vector3(3.5, 1.2, 6.0), m.hull)

    -- 前部倾斜装甲 (楔形效果，用倾斜的 Box 模拟)
    CreateBox(modelNode, "FrontGlacis", Vector3(0, 0.9, 3.15), Vector3(3.3, 0.5, 0.6), m.armor,
        Quaternion(-20, Vector3.RIGHT))

    -- 后部装甲板
    CreateBox(modelNode, "RearPlate", Vector3(0, 0.7, -3.05), Vector3(3.3, 0.8, 0.1), m.armor)

    -- 侧裙板 (两侧)
    CreateBox(modelNode, "SidePlateL", Vector3(-1.95, 0.55, 0), Vector3(0.12, 0.7, 5.6), m.armor)
    CreateBox(modelNode, "SidePlateR", Vector3( 1.95, 0.55, 0), Vector3(0.12, 0.7, 5.6), m.armor)

    -- ==================================================================
    -- 履带 (左右各一条, 比坦克更长更宽, 加高)
    -- ==================================================================
    CreateBox(modelNode, "TrackL", Vector3(-2.05, 0.5, 0), Vector3(0.85, 1.0, 6.4), m.track)
    CreateBox(modelNode, "TrackR", Vector3( 2.05, 0.5, 0), Vector3(0.85, 1.0, 6.4), m.track)

    -- 履带滚轮装饰 (每侧6个)
    local wheelRot = Quaternion(90, Vector3.FORWARD)
    for i = 0, 5 do
        local zOff = -2.5 + i * 1.0
        CreateCylinder(modelNode, "WheelL" .. i, Vector3(-2.05, 0.5, zOff),
            Vector3(0.55, 0.7, 0.55), m.track, wheelRot)
        CreateCylinder(modelNode, "WheelR" .. i, Vector3( 2.05, 0.5, zOff),
            Vector3(0.55, 0.7, 0.55), m.track, wheelRot)
    end

    -- 前后驱动轮 (较大)
    CreateCylinder(modelNode, "DriveWheelLF", Vector3(-2.05, 0.65, 3.0),
        Vector3(0.65, 0.7, 0.65), m.mgMetal, wheelRot)
    CreateCylinder(modelNode, "DriveWheelRF", Vector3( 2.05, 0.65, 3.0),
        Vector3(0.65, 0.7, 0.65), m.mgMetal, wheelRot)
    CreateCylinder(modelNode, "DriveWheelLR", Vector3(-2.05, 0.65, -3.0),
        Vector3(0.65, 0.7, 0.65), m.mgMetal, wheelRot)
    CreateCylinder(modelNode, "DriveWheelRR", Vector3( 2.05, 0.65, -3.0),
        Vector3(0.65, 0.7, 0.65), m.mgMetal, wheelRot)

    -- ==================================================================
    -- 底盘机枪 (前部右侧)
    -- ==================================================================
    CreateBox(modelNode, "HullMGMount", Vector3(0.8, 1.35, 2.2), Vector3(0.3, 0.25, 0.4), m.mgMetal)
    local mgBarrelRot = Quaternion(90, Vector3.RIGHT)
    CreateCylinder(modelNode, "HullMGBarrel", Vector3(0.8, 1.35, 2.8),
        Vector3(0.06, 0.8, 0.06), m.barrel, mgBarrelRot)

    -- 机枪防盾
    CreateBox(modelNode, "HullMGShield", Vector3(0.8, 1.4, 2.35), Vector3(0.5, 0.35, 0.06), m.armor)

    -- ==================================================================
    -- 底盘细节
    -- ==================================================================
    -- 前灯 (两侧)
    CreateSphere(modelNode, "HeadlightL", Vector3(-1.2, 0.9, 3.05), Vector3(0.2, 0.2, 0.2), m.lens)
    CreateSphere(modelNode, "HeadlightR", Vector3( 1.2, 0.9, 3.05), Vector3(0.2, 0.2, 0.2), m.lens)

    -- 排气管 (后部两侧)
    CreateCylinder(modelNode, "ExhaustL", Vector3(-1.2, 0.9, -3.1),
        Vector3(0.2, 0.4, 0.2), m.mgMetal, Quaternion(90, Vector3.RIGHT))
    CreateCylinder(modelNode, "ExhaustR", Vector3( 1.2, 0.9, -3.1),
        Vector3(0.2, 0.4, 0.2), m.mgMetal, Quaternion(90, Vector3.RIGHT))

    -- 工具箱 (底盘后部两侧)
    CreateBox(modelNode, "ToolboxL", Vector3(-1.5, 1.35, -1.8), Vector3(0.5, 0.3, 0.8), m.armor)
    CreateBox(modelNode, "ToolboxR", Vector3( 1.5, 1.35, -1.8), Vector3(0.5, 0.3, 0.8), m.armor)

    -- ==================================================================
    -- 底座前方 & 前方上方机械结构装饰
    -- ==================================================================

    -- 前部推土铲/防撞杠 (底盘最前端底部)
    CreateBox(modelNode, "FrontBumper", Vector3(0, 0.25, 3.3), Vector3(3.6, 0.4, 0.15), m.armor)
    CreateBox(modelNode, "BumperBraceL", Vector3(-1.3, 0.35, 3.15), Vector3(0.1, 0.2, 0.35), m.mgMetal)
    CreateBox(modelNode, "BumperBraceR", Vector3( 1.3, 0.35, 3.15), Vector3(0.1, 0.2, 0.35), m.mgMetal)

    -- 前部液压缸 (推铲连接底盘, 左右各一)
    local hydrRot = Quaternion(-30, Vector3.RIGHT)
    CreateCylinder(modelNode, "HydraulicCylL", Vector3(-0.9, 0.45, 3.0),
        Vector3(0.08, 0.5, 0.08), m.mgMetal, hydrRot)
    CreateCylinder(modelNode, "HydraulicCylR", Vector3( 0.9, 0.45, 3.0),
        Vector3(0.08, 0.5, 0.08), m.mgMetal, hydrRot)
    -- 液压缸活塞杆 (更细)
    CreateCylinder(modelNode, "HydraulicRodL", Vector3(-0.9, 0.3, 3.2),
        Vector3(0.05, 0.35, 0.05), m.barrel, hydrRot)
    CreateCylinder(modelNode, "HydraulicRodR", Vector3( 0.9, 0.3, 3.2),
        Vector3(0.05, 0.35, 0.05), m.barrel, hydrRot)

    -- 前部拖车钩 (底盘前端中央底部)
    CreateBox(modelNode, "FrontTowMount", Vector3(0, 0.12, 3.1), Vector3(0.4, 0.12, 0.2), m.mgMetal)
    CreateCylinder(modelNode, "FrontTowHook", Vector3(0, 0.06, 3.25),
        Vector3(0.16, 0.06, 0.16), m.mgMetal)

    -- 前部传感器阵列 (前装甲上方, 左右各一组)
    CreateBox(modelNode, "SensorBoxL", Vector3(-1.0, 1.35, 2.7), Vector3(0.35, 0.2, 0.25), m.mgMetal)
    CreateSphere(modelNode, "SensorLensL", Vector3(-1.0, 1.35, 2.85), Vector3(0.12, 0.12, 0.06), m.lens)
    CreateBox(modelNode, "SensorBoxR", Vector3( 1.0, 1.35, 2.7), Vector3(0.35, 0.2, 0.25), m.mgMetal)
    CreateSphere(modelNode, "SensorLensR", Vector3( 1.0, 1.35, 2.85), Vector3(0.12, 0.12, 0.06), m.lens)

    -- 前上方管线束 (底盘顶部前方, 横向管线)
    local pipeRotX = Quaternion(90, Vector3.FORWARD)
    CreateCylinder(modelNode, "FrontPipeA", Vector3(0, 1.32, 1.8),
        Vector3(0.05, 2.4, 0.05), m.mgMetal, pipeRotX)
    CreateCylinder(modelNode, "FrontPipeB", Vector3(0, 1.38, 1.6),
        Vector3(0.04, 2.0, 0.04), m.track, pipeRotX)

    -- 管线固定夹 (沿管线每隔一段)
    for i = -1, 1 do
        CreateBox(modelNode, "PipeClamp" .. (i + 2), Vector3(i * 0.7, 1.35, 1.8),
            Vector3(0.08, 0.12, 0.06), m.mgMetal)
    end

    -- 前上方通风格栅 (底盘顶部, 发动机散热)
    CreateBox(modelNode, "VentGrille", Vector3(0, 1.32, 1.2), Vector3(1.2, 0.06, 0.5), m.mgMetal)
    -- 格栅条纹 (5根横条)
    for i = 0, 4 do
        local zG = 1.0 + i * 0.1
        CreateBox(modelNode, "VentSlat" .. i, Vector3(0, 1.36, zG),
            Vector3(1.1, 0.02, 0.03), m.barrel)
    end

    -- 前方防护栏杆 (上层结构前方, 连接底盘到上层)
    CreateCylinder(modelNode, "GuardRailPostL", Vector3(-1.35, 1.35, 1.5),
        Vector3(0.04, 0.35, 0.04), m.mgMetal)
    CreateCylinder(modelNode, "GuardRailPostR", Vector3( 1.35, 1.35, 1.5),
        Vector3(0.04, 0.35, 0.04), m.mgMetal)
    CreateCylinder(modelNode, "GuardRailBar", Vector3(0, 1.5, 1.5),
        Vector3(0.03, 2.7, 0.03), m.mgMetal, pipeRotX)

    -- ==================================================================
    -- 上层结构 (底盘中后部凸起方块, 炮塔基座)
    -- ==================================================================
    -- 凸起方块 (2.8 x 0.6 x 3.0, 位于底盘中后部)
    CreateBox(modelNode, "Superstructure", Vector3(0, 1.6, -0.6), Vector3(2.8, 0.6, 3.0), m.hull)
    -- 前部倾斜面
    CreateBox(modelNode, "SuperFrontSlope", Vector3(0, 1.55, 1.05), Vector3(2.6, 0.5, 0.4), m.armor,
        Quaternion(-25, Vector3.RIGHT))
    -- 侧面装甲
    CreateBox(modelNode, "SuperSideL", Vector3(-1.45, 1.6, -0.6), Vector3(0.1, 0.55, 2.8), m.armor)
    CreateBox(modelNode, "SuperSideR", Vector3( 1.45, 1.6, -0.6), Vector3(0.1, 0.55, 2.8), m.armor)

    -- ==================================================================
    -- 炮塔 (可旋转关节, 三层梯形: 下宽上窄)
    -- 安装在上层结构顶部 (y=1.6+0.3=1.9)
    -- ==================================================================
    local turretJoint = modelNode:CreateChild("TurretJoint")
    turretJoint.position = Vector3(0, 1.95, -0.6)

    -- 炮塔底座环
    CreateCylinder(turretJoint, "TurretRing", Vector3(0, 0, 0),
        Vector3(2.6, 0.15, 2.6), m.mgMetal)

    -- 第1层: 底座 (最宽, 2.8 x 0.7 x 2.4)
    CreateBox(turretJoint, "TurretLower", Vector3(0, 0.4, 0), Vector3(2.8, 0.7, 2.4), m.turret)

    -- 底座前部倾斜装甲
    CreateBox(turretJoint, "TurretFrontArmor", Vector3(0, 0.5, 1.3), Vector3(2.6, 0.6, 0.3), m.armor,
        Quaternion(-15, Vector3.RIGHT))

    -- 第1→2层过渡: 倾斜肩部装甲 (左右各一块, 向内收)
    CreateBox(turretJoint, "TurretSlopeL", Vector3(-1.3, 0.85, 0), Vector3(0.35, 0.25, 2.2), m.armor,
        Quaternion(20, Vector3.FORWARD))
    CreateBox(turretJoint, "TurretSlopeR", Vector3( 1.3, 0.85, 0), Vector3(0.35, 0.25, 2.2), m.armor,
        Quaternion(-20, Vector3.FORWARD))

    -- 第2层: 中段 (收窄, 2.2 x 0.8 x 2.0)
    CreateBox(turretJoint, "TurretMid", Vector3(0, 1.1, 0), Vector3(2.2, 0.8, 2.0), m.turret)

    -- 第2→3层过渡: 倾斜面
    CreateBox(turretJoint, "TurretMidSlopeL", Vector3(-1.0, 1.6, 0), Vector3(0.3, 0.2, 1.6), m.armor,
        Quaternion(18, Vector3.FORWARD))
    CreateBox(turretJoint, "TurretMidSlopeR", Vector3( 1.0, 1.6, 0), Vector3(0.3, 0.2, 1.6), m.armor,
        Quaternion(-18, Vector3.FORWARD))

    -- 第3层: 顶部 (最窄, 1.6 x 0.5 x 1.6)
    CreateBox(turretJoint, "TurretUpper", Vector3(0, 1.85, 0), Vector3(1.6, 0.5, 1.6), m.turret)

    -- 顶板
    CreateBox(turretJoint, "TurretRoof", Vector3(0, 2.15, -0.1), Vector3(1.4, 0.1, 1.4), m.armor)

    -- 指挥塔 (顶层后方)
    CreateCylinder(turretJoint, "CommanderCupola", Vector3(0, 2.35, -0.4),
        Vector3(0.6, 0.3, 0.6), m.turret)
    -- 观察窗
    CreateSphere(turretJoint, "CupolaLens", Vector3(0, 2.4, -0.05), Vector3(0.15, 0.15, 0.15), m.lens)

    -- 通信天线 (指挥塔上方)
    CreateCylinder(turretJoint, "Antenna", Vector3(0.15, 2.95, -0.4),
        Vector3(0.03, 0.8, 0.03), m.mgMetal)

    -- ==================================================================
    -- 炮塔正面装饰
    -- ==================================================================

    -- 中央观察窗口 (第2层正面, 带装甲护框)
    CreateBox(turretJoint, "ViewportFrame", Vector3(0, 1.1, 1.05),
        Vector3(0.7, 0.35, 0.08), m.mgMetal)
    CreateBox(turretJoint, "ViewportGlass", Vector3(0, 1.1, 1.1),
        Vector3(0.5, 0.2, 0.04), m.lens)

    -- 附加反应装甲模块 (第1层正面两侧, 各3块)
    for i = 0, 2 do
        local zOff = 1.18
        local yBase = 0.25 + i * 0.22
        CreateBox(turretJoint, "ERABlockL" .. i, Vector3(-0.85, yBase, zOff),
            Vector3(0.35, 0.16, 0.1), m.armor, Quaternion(-15, Vector3.RIGHT))
        CreateBox(turretJoint, "ERABlockR" .. i, Vector3( 0.85, yBase, zOff),
            Vector3(0.35, 0.16, 0.1), m.armor, Quaternion(-15, Vector3.RIGHT))
    end

    -- 探照灯 (第2层正面左右各一)
    CreateCylinder(turretJoint, "SearchlightL", Vector3(-0.75, 1.45, 1.05),
        Vector3(0.2, 0.15, 0.2), m.mgMetal, Quaternion(90, Vector3.RIGHT))
    CreateSphere(turretJoint, "SearchlightLensL", Vector3(-0.75, 1.45, 1.14),
        Vector3(0.16, 0.16, 0.08), m.lens)
    CreateCylinder(turretJoint, "SearchlightR", Vector3( 0.75, 1.45, 1.05),
        Vector3(0.2, 0.15, 0.2), m.mgMetal, Quaternion(90, Vector3.RIGHT))
    CreateSphere(turretJoint, "SearchlightLensR", Vector3( 0.75, 1.45, 1.14),
        Vector3(0.16, 0.16, 0.08), m.lens)

    -- 烟雾弹发射器 (第1层正面两侧, 每侧4管)
    local smokeRot = Quaternion(75, Vector3.RIGHT)
    for i = 0, 3 do
        local xOff = 0.12 * i
        CreateCylinder(turretJoint, "SmokeLauncherL" .. i,
            Vector3(-1.15 + xOff, 0.7, 1.3), Vector3(0.08, 0.2, 0.08), m.mgMetal, smokeRot)
        CreateCylinder(turretJoint, "SmokeLauncherR" .. i,
            Vector3( 0.65 + xOff, 0.7, 1.3), Vector3(0.08, 0.2, 0.08), m.mgMetal, smokeRot)
    end

    -- 拖钩 (第1层正面底部中央)
    CreateBox(turretJoint, "TowHookMount", Vector3(0, 0.15, 1.2),
        Vector3(0.3, 0.1, 0.12), m.mgMetal)
    CreateCylinder(turretJoint, "TowHookRing", Vector3(0, 0.08, 1.28),
        Vector3(0.14, 0.06, 0.14), m.mgMetal)

    -- ==================================================================
    -- 左右二级炮塔 (各含2根炮管, 共4根)
    -- 安装在主炮塔底层两侧, 控制俯仰角度(绕X轴旋转)
    -- 圆环轴承在内侧(与一级炮塔接触面)
    -- 一级炮塔控制水平旋转(yaw), 二级炮塔控制俯仰(pitch)
    -- ==================================================================
    local barrelRot = Quaternion(90, Vector3.RIGHT)

    local sides = {
        { name = "L", x = -2.1, ringDir = 1 },   -- 左侧, 圆环朝右(内侧)
        { name = "R", x =  2.1, ringDir = -1 },   -- 右侧, 圆环朝左(内侧)
    }
    for _, side in ipairs(sides) do
        -- 二级炮塔俯仰关节 (安装在主炮塔底层两侧)
        local subTurretJoint = turretJoint:CreateChild("SubTurretJoint" .. side.name)
        subTurretJoint.position = Vector3(side.x, 0.45, 0.2)

        -- 内侧轴承环 (与一级炮塔接触面, 竖直放置)
        local ringRot = Quaternion(90, Vector3.FORWARD)
        CreateCylinder(subTurretJoint, "SubTurretRing" .. side.name,
            Vector3(side.ringDir * 0.55, 0.3, 0), Vector3(1.1, 0.12, 1.1), m.mgMetal, ringRot)

        -- 二级炮塔壳体 (横向结构, 用于俯仰)
        CreateBox(subTurretJoint, "SubTurretBody" .. side.name,
            Vector3(0, 0.3, 0), Vector3(1.1, 0.8, 1.1), m.turret)
        -- 顶部收窄
        CreateBox(subTurretJoint, "SubTurretTop" .. side.name,
            Vector3(0, 0.8, 0), Vector3(0.9, 0.2, 0.9), m.turret)

        -- 前部倾斜装甲
        CreateBox(subTurretJoint, "SubTurretFront" .. side.name,
            Vector3(0, 0.35, 0.6), Vector3(1.0, 0.7, 0.12), m.armor,
            Quaternion(-12, Vector3.RIGHT))

        -- 炮管防盾
        CreateBox(subTurretJoint, "SubGunMantlet" .. side.name,
            Vector3(0, 0.35, 0.65), Vector3(0.85, 0.65, 0.2), m.armor)

        -- 上炮管
        CreateCylinder(subTurretJoint, "BarrelUp" .. side.name, Vector3(0, 0.5, 1.8),
            Vector3(0.14, 2.2, 0.14), m.barrel, barrelRot)
        -- 上炮口制退器
        CreateCylinder(subTurretJoint, "MuzzleUp" .. side.name, Vector3(0, 0.5, 3.0),
            Vector3(0.22, 0.25, 0.22), m.barrel, barrelRot)

        -- 下炮管
        CreateCylinder(subTurretJoint, "BarrelDn" .. side.name, Vector3(0, 0.2, 1.8),
            Vector3(0.14, 2.2, 0.14), m.barrel, barrelRot)
        -- 下炮口制退器
        CreateCylinder(subTurretJoint, "MuzzleDn" .. side.name, Vector3(0, 0.2, 3.0),
            Vector3(0.22, 0.25, 0.22), m.barrel, barrelRot)

        -- 观察镜 (炮塔顶部)
        CreateSphere(subTurretJoint, "SubTurretLens" .. side.name,
            Vector3(0, 0.95, 0.15), Vector3(0.14, 0.14, 0.14), m.lens)

        -- 炮弹发射点标记 (空节点, 位于炮口制退器前端)
        -- 炮口制退器 z=3.0, scale y=0.25(沿Z延伸), 前端 ≈ z=3.15
        local fpUp = subTurretJoint:CreateChild("FirePoint_Up" .. side.name)
        fpUp.position = Vector3(0, 0.5, 3.15)
        local fpDn = subTurretJoint:CreateChild("FirePoint_Dn" .. side.name)
        fpDn.position = Vector3(0, 0.2, 3.15)
    end

    -- ==================================================================
    -- 右侧 - 垂直飞弹发射舱 (炮塔后部, 避免与炮管重叠)
    -- ==================================================================
    local mzBase = -1.2  -- 飞弹舱中心 Z 坐标

    -- 飞弹舱主体 (竖直箱体, 加高)
    CreateBox(turretJoint, "MissileBay", Vector3(0.7, 1.3, mzBase), Vector3(1.0, 1.5, 1.2), m.missile)

    -- 舱盖 (顶部, 略向前倾斜表示发射角度)
    CreateBox(turretJoint, "MissileBayLid", Vector3(0.7, 2.1, mzBase + 0.05), Vector3(0.9, 0.08, 1.1), m.armor,
        Quaternion(5, Vector3.RIGHT))

    -- 飞弹发射管 (4根竖直管, 2x2 布局)
    local tubeOffsets = {
        Vector3(-0.2, 0, -0.2),
        Vector3( 0.2, 0, -0.2),
        Vector3(-0.2, 0,  0.2),
        Vector3( 0.2, 0,  0.2),
    }
    local missileFirePoints = {}
    for i, off in ipairs(tubeOffsets) do
        CreateCylinder(turretJoint, "MissileTube" .. i,
            Vector3(0.7 + off.x, 2.15, mzBase + off.z),
            Vector3(0.16, 0.15, 0.16), m.mgMetal)
        -- 飞弹发射点标记 (空节点, 管口顶端, 发射方向为 +Y 向上)
        local mp = turretJoint:CreateChild("MissilePoint" .. i)
        mp.position = Vector3(0.7 + off.x, 2.25, mzBase + off.z)
        missileFirePoints[i] = mp
    end

    -- 飞弹舱侧面加强筋
    CreateBox(turretJoint, "MissileBayRibF", Vector3(0.7, 1.3, mzBase + 0.65), Vector3(0.95, 0.06, 0.06), m.mgMetal)
    CreateBox(turretJoint, "MissileBayRibR", Vector3(0.7, 1.3, mzBase - 0.65), Vector3(0.95, 0.06, 0.06), m.mgMetal)
    CreateBox(turretJoint, "MissileBayRibM", Vector3(0.7, 1.7, mzBase + 0.65), Vector3(0.95, 0.06, 0.06), m.mgMetal)

    -- 飞弹舱红色警示灯
    CreateSphere(turretJoint, "MissileLight", Vector3(1.25, 1.6, mzBase), Vector3(0.12, 0.12, 0.12), m.accent)

    -- ==================================================================
    -- 关节与发射点表 (供动画/AI/战斗系统使用)
    -- ==================================================================
    local subL = turretJoint:GetChild("SubTurretJointL", false)
    local subR = turretJoint:GetChild("SubTurretJointR", false)

    local result = {
        -- ============ 关节 ============
        --- 主炮塔关节 (绕Y轴旋转控制水平yaw)
        turret = turretJoint,
        --- 左二级炮塔关节 (绕X轴旋转控制俯仰pitch)
        subTurretL = subL,
        --- 右二级炮塔关节 (绕X轴旋转控制俯仰pitch)
        subTurretR = subR,

        -- ============ 炮弹发射点 (4个) ============
        --- 发射点节点: 左上/左下/右上/右下
        firePoints = {
            subL:GetChild("FirePoint_UpL", false),
            subL:GetChild("FirePoint_DnL", false),
            subR:GetChild("FirePoint_UpR", false),
            subR:GetChild("FirePoint_DnR", false),
        },

        -- ============ 飞弹发射点 (4个) ============
        missilePoints = missileFirePoints,
    }

    --- 设置主炮塔水平朝向角 (度)
    ---@param yawDeg number 水平角度, 0=前方, 正值=右转
    function result:SetTurretYaw(yawDeg)
        self.turret.rotation = Quaternion(yawDeg, Vector3.UP)
    end

    --- 设置二级炮塔俯仰角 (度)
    ---@param side string "L" 或 "R"
    ---@param pitchDeg number 俯仰角度, 0=水平, 正值=上仰, 负值=下俯
    function result:SetSubTurretPitch(side, pitchDeg)
        local joint = (side == "L") and self.subTurretL or self.subTurretR
        joint.rotation = Quaternion(-pitchDeg, Vector3.RIGHT)
    end

    --- 获取4个炮管发射点的世界坐标和朝向
    ---@return table[] { { position: Vector3, direction: Vector3 }, ... }
    function result:GetBarrelFireData()
        local data = {}
        for i, fp in ipairs(self.firePoints) do
            data[i] = {
                position  = fp.worldPosition,
                direction = fp.worldRotation * Vector3.FORWARD,
            }
        end
        return data
    end

    --- 获取4个飞弹发射点的世界坐标 (发射方向固定为世界+Y向上)
    ---@return table[] { { position: Vector3, direction: Vector3 }, ... }
    function result:GetMissileFireData()
        local data = {}
        for i, mp in ipairs(self.missilePoints) do
            data[i] = {
                position  = mp.worldPosition,
                direction = mp.worldRotation * Vector3.UP,
            }
        end
        return data
    end

    --- 让主炮塔 + 指定侧二级炮塔瞄准世界坐标目标
    ---@param targetWorldPos Vector3 目标世界坐标
    ---@param side string "L" 或 "R" (使用哪侧炮塔瞄准)
    function result:AimAt(targetWorldPos, side)
        -- 计算目标在底盘局部空间的方向
        local turretWorldPos = self.turret.worldPosition
        local toTarget = targetWorldPos - turretWorldPos

        -- yaw: 水平角度 (XZ平面)
        local yaw = math.deg(math.atan(toTarget.x, toTarget.z))
        self:SetTurretYaw(yaw)

        -- pitch: 俯仰角 (使用二级炮塔关节的世界位置作为起点)
        local subJoint = (side == "L") and self.subTurretL or self.subTurretR
        local subWorldPos = subJoint.worldPosition
        local toTargetFromSub = targetWorldPos - subWorldPos
        -- 在主炮塔朝向的局部空间中计算前向距离和高度差
        local turretFwd = self.turret.worldRotation * Vector3.FORWARD
        local turretRight = self.turret.worldRotation * Vector3.RIGHT
        local fwd = toTargetFromSub:DotProduct(turretFwd)
        local up  = toTargetFromSub.y
        local pitch = math.deg(math.atan(up, math.max(fwd, 0.1)))
        self:SetSubTurretPitch(side, pitch)
    end

    return modelNode, result
end

return BossBuilder
