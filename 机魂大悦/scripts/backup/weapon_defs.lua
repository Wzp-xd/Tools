-- ============================================================================
-- 武器策划案 - 全武器数据定义
-- Weapon Design Document - All Weapon Data Definitions
-- ============================================================================
--
-- 武器槽位:
--   handL     - 左手 (鼠标左键 / 按住连射)
--   handR     - 右手 (鼠标右键 / 按住使用)
--   shoulderR - 右肩 (E键 / 锁定-释放 或 蓄力-释放 或 直射)
--
-- 共 11 种武器:
--   左手(3): machinegun, shotgun, pistol
--   右手(3): rpg, shield, homing_handgun
--   肩部(4): missile, vertical_missile, shoulder_rpg, railgun
-- ============================================================================

local WeaponDefs = {}

-- ============================================================================
-- 槽位定义
-- ============================================================================

WeaponDefs.SLOTS = {
    handL = {
        label = "左手武器",
        key = "LMB",
        inputType = "hold",           -- 按住连射
        options = { "machinegun", "shotgun", "pistol" },
    },
    handR = {
        label = "右手武器",
        key = "RMB",
        inputType = "hold",           -- 按住使用
        options = { "rpg", "shield", "homing_handgun" },
    },
    shoulderL = {
        label = "左肩武器",
        key = "Q",
        inputType = "lock_release",
        options = { "missile", "vertical_missile", "shoulder_rpg", "railgun" },
    },
    shoulderR = {
        label = "右肩武器",
        key = "E",
        inputType = "lock_release",   -- 锁定释放（追踪型）/ 蓄力释放（电磁炮）/ 直射（肩部RPG）
        options = { "missile", "vertical_missile", "shoulder_rpg", "railgun" },
    },
}

-- 槽位显示顺序
WeaponDefs.SLOT_ORDER = { "handL", "handR", "shoulderL", "shoulderR" }

-- ============================================================================
-- 武器定义
-- ============================================================================

WeaponDefs.DEFS = {

    -- ========================================================================
    -- 左手武器（LMB 按住连射）
    -- ========================================================================

    --- 机关枪: 高射速自动武器，持续输出中距离火力
    machinegun = {
        name = "Machine Gun",
        nameZH = "机关枪",
        slot = "handL",
        category = "rapid",

        -- 战斗参数
        fireRate = 10.0,            -- 每秒 10 发
        bulletSpeed = 200.0,        -- 弹速 200 m/s
        bulletLife = 1.5,           -- 存活 1.5s（射程 300m）
        damage = 10,                -- 单发伤害
        spread = 0.01,              -- 散布 0.01 弧度
        tracking = false,
        magazineSize = 40,
        reloadTime = 2.0,

        -- 弹丸视觉
        bulletScale = Vector3(0.16, 0.16, 0.8),
        bulletColor = Color(1.0, 0.9, 0.3, 1.0),
        emissive = Color(4.0, 3.0, 0.5),
        muzzleFlashDur = 0.04,

        -- UI 展示数据
        stats = {
            dps = 50, range = "300m", accuracy = "中等", type = "动能",
        },
        description = "高射速自动武器，稳定输出中距离火力。\n弹匣 40 发，换弹 2 秒。\n适合持续压制和中距离交战。",
        usage = "按住鼠标左键连续射击。R 键手动换弹。",
    },

    --- 霰弹枪: 近距离爆发，8 弹丸散射
    shotgun = {
        name = "Shotgun",
        nameZH = "霰弹枪",
        slot = "handL",
        category = "burst",

        fireRate = 1.2,             -- 每秒 1.2 发
        bulletSpeed = 180.0,
        bulletLife = 0.6,           -- 短射程（约 108m）
        damage = 16,                -- 每颗弹丸 16 伤害
        pelletCount = 8,            -- 每发 8 颗弹丸
        spread = 0.04,              -- 散布（弧度）
        tracking = false,
        magazineSize = 6,
        reloadTime = 3.0,

        bulletScale = Vector3(0.12, 0.12, 0.3),
        bulletColor = Color(1.0, 0.7, 0.3, 1.0),
        emissive = Color(3.0, 2.0, 0.5),
        muzzleFlashDur = 0.08,

        stats = {
            dps = 76, range = "100m", accuracy = "低", type = "动能",
        },
        description = "近距离毁灭者。每发散射 8 颗弹丸，\n单次爆发伤害 64。\n近距离交战的不二之选，但远距离效果差。",
        usage = "按住鼠标左键射击。适合近距离冲锋使用。",
    },

    --- 手枪: 精准射击，快速换弹
    pistol = {
        name = "Pistol",
        nameZH = "手枪",
        slot = "handL",
        category = "precision",

        fireRate = 3.0,
        bulletSpeed = 250.0,        -- 最快手部弹速
        bulletLife = 2.0,           -- 射程 500m
        damage = 50,                -- 高单发伤害
        spread = 0.003,             -- 极高精度
        tracking = false,
        magazineSize = 12,
        reloadTime = 1.5,           -- 快速换弹

        bulletScale = Vector3(0.12, 0.12, 0.7),
        bulletColor = Color(0.8, 0.9, 1.0, 1.0),
        emissive = Color(2.0, 2.5, 4.0),
        muzzleFlashDur = 0.05,

        stats = {
            dps = 75, range = "500m", accuracy = "高", type = "动能",
        },
        description = "精准手枪。高精度、快换弹补偿较低射速。\n适合中远距离精确打击。",
        usage = "按住鼠标左键射击。精度极高，适合点射。",
    },

    -- ========================================================================
    -- 右手武器（RMB 按住使用）
    -- ========================================================================

    --- RPG: 直线弹道 + 撞击爆炸 + 范围伤害
    rpg = {
        name = "RPG",
        nameZH = "RPG火箭筒",
        slot = "handR",
        category = "explosive",

        fireRate = 0.5,
        bulletSpeed = 120.0,
        bulletLife = 5.0,
        damage = 80,                -- 直击伤害
        spread = 0.0,
        tracking = false,
        magazineSize = 1,
        reloadTime = 10.0,
        blastRadius = 15.0,         -- 爆炸半径 15m
        blastDamage = 50,           -- 范围伤害

        bulletScale = Vector3(0.5, 0.5, 2.4),
        bulletColor = Color(0.5, 0.5, 0.5, 1.0),
        emissive = Color(1.0, 0.4, 0.1),
        trailColor = Color(1.0, 0.5, 0.2, 0.6),
        muzzleFlashDur = 0.1,

        stats = {
            dps = 65, range = "600m", accuracy = "高", type = "爆破",
        },
        description = "重型火箭筒。直击 80 + 范围 50 伤害，\n15 米爆炸半径。\n高伤害但射速极慢，需精确瞄准。",
        usage = "按住鼠标右键发射。单发弹匣，换弹 10 秒。",
    },

    --- 能量盾: 3 秒内吸收伤害的防御武器
    shield = {
        name = "Energy Shield",
        nameZH = "能量盾",
        slot = "handR",
        category = "defensive",

        isShield = true,            -- 标记为非射弹武器
        shieldDuration = 3.0,       -- 护盾持续时间
        shieldCooldown = 8.0,       -- 冷却时间
        shieldAbsorb = 200,         -- 最大吸收伤害
        shieldColor = Color(0.2, 0.6, 1.0, 0.4),
        shieldEmissive = Color(0.5, 1.5, 3.0),

        -- 弹匣参数（用于 HUD 兼容）
        fireRate = 0,
        tracking = false,
        magazineSize = 1,
        reloadTime = 12.0,          -- 映射为冷却时间（+50%）
        muzzleFlashDur = 0,
        damage = 0,
        spread = 0,
        bulletSpeed = 0,
        bulletLife = 0,
        bulletScale = Vector3(0, 0, 0),
        bulletColor = Color(0, 0, 0, 0),
        emissive = Color(0, 0, 0),

        stats = {
            dps = 0, range = "自身", accuracy = "N/A", type = "防御",
        },
        description = "能量护盾。激活后 3 秒内可吸收最多 200 伤害。\n冷却 8 秒。\n面对高爆发伤害时的救命稻草。",
        usage = "按住鼠标右键激活护盾。护盾期间无法使用右手武器攻击。",
    },

    --- 追踪手枪: 自动追踪弹丸
    homing_handgun = {
        name = "Homing Handgun",
        nameZH = "飞弹枪",
        slot = "handR",
        category = "tracking",

        fireRate = 2.0,
        bulletSpeed = 100.0,
        maxSpeed = 140.0,
        bulletLife = 3.0,
        damage = 10,
        spread = 0.0,
        tracking = true,
        magazineSize = 3,
        reloadTime = 4.0,

        -- 追踪参数（无上升阶段，直接追踪）
        initialTurnRate = 360.0,
        finalTurnRate = 60.0,
        turnRateDecayTime = 0.8,
        launchTime = 0,             -- 无上升阶段

        bulletScale = Vector3(0.2, 0.2, 1.0),
        bulletColor = Color(0.4, 0.8, 1.0, 1.0),
        emissive = Color(1.0, 2.5, 4.0),
        trailColor = Color(0.3, 0.7, 1.0, 0.5),
        muzzleFlashDur = 0.06,

        stats = {
            dps = 40, range = "420m", accuracy = "自动追踪", type = "能量",
        },
        description = "智能飞弹枪。弹丸自动追踪锁定目标，\n伤害较低但命中率极高。\n适合对付高机动目标。",
        usage = "按住鼠标右键对锁定目标射击。弹丸自动追踪。",
    },

    -- ========================================================================
    -- 肩部武器（E 键操作）
    -- ========================================================================

    --- 斜射飞弹: 斜向上升后追踪目标，6 连发
    missile = {
        name = "Diagonal Missile",
        nameZH = "斜射飞弹",
        slot = "shoulderR",
        category = "tracking",

        fireRate = 1.5,
        burstCount = 6,
        burstInterval = 0.1,
        bulletSpeed = 90.0,
        maxSpeed = 90.0,
        bulletLife = 4.0,
        damage = 15,
        spread = 0.0,
        tracking = true,
        magazineSize = 6,
        reloadTime = 10.0,
        initialTurnRate = 480.0,
        finalTurnRate = 15.0,
        turnRateDecayTime = 1.0,
        launchTime = 0.1,
        launchUpAngle = 60.0,

        bulletScale = Vector3(0.4, 0.4, 1.8),
        bulletColor = Color(0.6, 0.6, 0.65, 1.0),
        emissive = Color(1.0, 0.3, 0.1),
        trailColor = Color(1.0, 0.6, 0.2, 0.8),
        muzzleFlashDur = 0.08,

        stats = {
            dps = 27, range = "360m", accuracy = "追踪", type = "爆破",
        },
        description = "斜向 60° 发射飞弹，3 发连射。\n按住 E 选择多个目标，松开发射。\n发射后飞弹具有追踪效果。",
        usage = "按住 E 键选择多个目标，松开 E 键发射。飞弹发射后自动追踪锁定目标。",
    },

    --- 垂直飞弹: 近乎垂直发射，从顶部攻击
    vertical_missile = {
        name = "Vertical Missile",
        nameZH = "垂直飞弹",
        slot = "shoulderR",
        category = "tracking",

        fireRate = 1.0,
        burstCount = 4,
        burstInterval = 0.15,
        bulletSpeed = 70.0,
        maxSpeed = 110.0,
        bulletLife = 10.0,
        damage = 23,
        spread = 0.0,
        tracking = true,
        magazineSize = 4,
        reloadTime = 12.0,
        initialTurnRate = 900.0,    -- 高初始转向（85°俯冲需快速调转）
        finalTurnRate = 60.0,       -- 持续追踪能力
        turnRateDecayTime = 2.0,    -- 更长高转向窗口
        launchTime = 1.0,           -- 垂直上升1秒后转入追踪
        launchUpAngle = 85.0,       -- 几乎垂直
        blastRadius = 10.0,
        blastDamage = 15,

        bulletScale = Vector3(0.44, 0.44, 2.0),
        bulletColor = Color(0.5, 0.55, 0.6, 1.0),
        emissive = Color(0.8, 0.3, 0.1),
        trailColor = Color(0.9, 0.5, 0.15, 0.7),
        muzzleFlashDur = 0.08,

        stats = {
            dps = 15, range = "550m", accuracy = "追踪", type = "爆破",
        },
        description = "85° 垂直发射飞弹，上升1秒后俯冲攻击。\n按住 E 选择多个目标，松开发射。\n发射后飞弹具有追踪效果，极难闪避。",
        usage = "按住 E 键选择多个目标，松开 E 键发射。飞弹垂直升空1秒后自动追踪俯冲。",
    },

    --- 肩扛火箭: 最大爆炸范围，直射无追踪
    shoulder_rpg = {
        name = "Shoulder RPG",
        nameZH = "肩扛火箭",
        slot = "shoulderR",
        category = "explosive",

        fireRate = 0.3,
        bulletSpeed = 150.0,
        bulletLife = 4.0,
        damage = 100,               -- 最高单发伤害
        spread = 0.0,
        tracking = false,           -- 直线，无追踪
        magazineSize = 1,
        reloadTime = 15.0,
        blastRadius = 20.0,         -- 最大爆炸半径
        blastDamage = 70,

        bulletScale = Vector3(0.6, 0.6, 3.0),
        bulletColor = Color(0.4, 0.4, 0.42, 1.0),
        emissive = Color(1.2, 0.5, 0.1),
        trailColor = Color(1.0, 0.4, 0.1, 0.7),
        muzzleFlashDur = 0.12,

        stats = {
            dps = 51, range = "600m", accuracy = "高", type = "爆破",
        },
        description = "重型肩扛火箭。直击 100 + 范围 70 伤害，\n20 米爆炸半径，全武器中最大。\n无追踪，需精确瞄准。",
        usage = "按 E 键直接发射。无需锁定，直线飞行。",
    },

    --- 电磁炮: 蓄力发射超高速穿透钢针
    railgun = {
        name = "Railgun",
        nameZH = "电磁炮",
        slot = "shoulderR",
        category = "precision",

        fireRate = 0.25,
        bulletSpeed = 500.0,        -- 超高速
        bulletLife = 2.0,
        damage = 75,                -- 单体伤害（降低50%）
        spread = 0.0,
        tracking = false,
        magazineSize = 1,
        reloadTime = 8.0,

        -- 特殊机制
        chargeTime = 1.5,           -- 蓄力时间 1.5 秒
        piercing = true,            -- 穿透目标

        bulletScale = Vector3(0.08, 0.08, 4.0),   -- 细长钢针（2倍）
        bulletColor = Color(0.6, 0.8, 1.0, 1.0),
        emissive = Color(2.0, 4.0, 8.0),         -- 亮蓝白光
        trailColor = Color(0.4, 0.7, 1.0, 0.8),
        muzzleFlashDur = 0.15,

        stats = {
            dps = 18, range = "1000m", accuracy = "完美", type = "电磁",
        },
        description = "电磁加速器。蓄力 1.5 秒后发射超高速钢针，\n150 伤害 + 穿透目标。\n全武器中最高单体伤害，但蓄力期间无法移动射击。",
        usage = "按住 E 键蓄力（1.5 秒），蓄满自动发射。蓄力未满松手不会发射。",
    },

    -- ========================================================================
    -- 叛军载具武器（AI专用，不可装备）
    -- ========================================================================

    --- 坦克主炮: 低伤害版RPG
    tank_cannon = {
        name = "Tank Cannon",
        nameZH = "坦克主炮",
        slot = "none",
        category = "explosive",

        fireRate = 0.2,
        bulletSpeed = 100.0,
        bulletLife = 5.0,
        damage = 30,
        spread = 0.005,
        tracking = false,
        magazineSize = 1,
        reloadTime = 6.0,
        blastRadius = 8.0,
        blastDamage = 15,

        bulletScale = Vector3(0.4, 0.4, 1.6),
        bulletColor = Color(0.6, 0.5, 0.3, 1.0),
        emissive = Color(2.0, 1.2, 0.3),
        trailColor = Color(0.8, 0.5, 0.2, 0.6),
        muzzleFlashDur = 0.1,
    },

    --- 坦克机枪: 低伤害机枪
    tank_mg = {
        name = "Tank MG",
        nameZH = "坦克机枪",
        slot = "none",
        category = "rapid",

        fireRate = 8.0,
        bulletSpeed = 180.0,
        bulletLife = 1.2,
        damage = 2,
        spread = 0.02,
        tracking = false,
        magazineSize = 60,
        reloadTime = 3.0,

        bulletScale = Vector3(0.1, 0.1, 0.6),
        bulletColor = Color(1.0, 0.8, 0.2, 1.0),
        emissive = Color(3.0, 2.0, 0.3),
        muzzleFlashDur = 0.03,
    },

    --- 直升机机枪: 低伤害高射速
    heli_mg = {
        name = "Helicopter MG",
        nameZH = "直升机机枪",
        slot = "none",
        category = "rapid",

        fireRate = 12.0,
        bulletSpeed = 200.0,
        bulletLife = 1.5,
        damage = 2,
        spread = 0.025,
        tracking = false,
        magazineSize = 80,
        reloadTime = 4.0,

        bulletScale = Vector3(0.1, 0.1, 0.5),
        bulletColor = Color(1.0, 0.9, 0.3, 1.0),
        emissive = Color(3.0, 2.5, 0.5),
        muzzleFlashDur = 0.03,
    },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取指定槽位的可用武器列表
---@param slot string "handL"|"handR"|"shoulderR"
---@return string[]
function WeaponDefs.GetSlotOptions(slot)
    local slotDef = WeaponDefs.SLOTS[slot]
    return slotDef and slotDef.options or {}
end

--- 获取武器定义
---@param weaponType string
---@return table|nil
function WeaponDefs.Get(weaponType)
    return WeaponDefs.DEFS[weaponType]
end

--- 获取武器的显示名称
---@param weaponType string
---@return string
function WeaponDefs.GetDisplayName(weaponType)
    local def = WeaponDefs.DEFS[weaponType]
    if not def then return weaponType end
    return def.nameZH or def.name or weaponType
end

--- 验证武器是否可以装备到指定槽位
---@param weaponType string
---@param slot string
---@return boolean
function WeaponDefs.CanEquipToSlot(weaponType, slot)
    local options = WeaponDefs.GetSlotOptions(slot)
    for _, opt in ipairs(options) do
        if opt == weaponType then return true end
    end
    return false
end

return WeaponDefs
