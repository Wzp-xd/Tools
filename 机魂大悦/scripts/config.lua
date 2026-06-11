-- ============================================================================
-- 机魂大悦 游戏配置文件
-- ============================================================================

local CONFIG = {
    -- ======================================================================
    -- 全局开关
    -- ======================================================================
    debugModeEnabled = true, -- 调试模式入口（true=主菜单显示, false=隐藏）

    -- ======================================================================
    -- 默认武器配置
    -- ======================================================================
    DefaultLoadout = {
        handL     = "machinegun",   -- 左手: 机关枪
        handR     = "rpg",          -- 右手: RPG
        shoulderL = "shoulder_rpg", -- 左肩: 肩扛火箭
        shoulderR = "missile",      -- 右肩: 斜射飞弹
    },

    -- ======================================================================
    -- 机体型号（乘数系统，未列出的字段默认 1.0）
    -- ======================================================================
    SelectedVariant = "A",

    MechVariantOrder = { "A", "B", "C", "D" },

    MechVariants = {
        A = {
            name = "标准型 / Standard",
            desc = "均衡机体，各项属性平衡，适合新手使用",
            color = { 100, 200, 255 },
            -- 全部 1.0（基准），无需列出
            -- 机体配色：冷蓝钢铁
            colors = {
                body    = { 0.22, 0.24, 0.28 },    -- 深灰蓝主体
                armor   = { 0.15, 0.35, 0.55 },    -- 钢蓝色装甲
                joint   = { 0.08, 0.08, 0.10 },    -- 深色关节
                visor   = { 0.1, 0.4, 0.5 },       -- 青色面罩
                visorEmissive = { 0.3, 1.5, 2.5 },
            },
            -- 装饰物：双肩天线
            decorations = {
                { type = "antenna", side = "both" },
            },
        },
        B = {
            name = "轻量型 / Lightweight",
            desc = "高机动低耐久，闪避冲刺专精，适合灵活走位",
            color = { 120, 255, 160 },
            hp = 0.6,
            maxSpeed = 1.4,
            moveForce = 1.25,
            dashImpulse = 1.5,
            dashDuration = 1.3,
            dashEnergyCost = 0.8,
            jetDashImpulse = 1.4,
            maxEnergy = 0.7,
            energyRegen = 0.7,
            -- 机体配色：翠绿轻装
            colors = {
                body    = { 0.15, 0.22, 0.15 },    -- 暗绿主体
                armor   = { 0.18, 0.50, 0.25 },    -- 翠绿装甲
                joint   = { 0.06, 0.10, 0.06 },    -- 深绿关节
                visor   = { 0.2, 0.6, 0.3 },       -- 绿色面罩
                visorEmissive = { 0.5, 3.0, 1.0 },
            },
            -- 装饰物：背部扰流翼
            decorations = {
                { type = "spoiler" },
            },
        },
        C = {
            name = "空战型 / Aerial",
            desc = "跳跃滞空增强，冲刺加强，适合空中战斗",
            color = { 255, 200, 80 },
            hp = 0.7,
            jumpSpeed = 1.3,
            boostCost = 0.6,
            boostForce = 1.2,
            jetCost = 0.7,
            jetForce = 1.15,
            dashImpulse = 1.3,
            dashEnergyCost = 0.7,
            -- 机体配色：金黄飞行
            colors = {
                body    = { 0.28, 0.24, 0.15 },    -- 暗金主体
                armor   = { 0.60, 0.45, 0.10 },    -- 金黄装甲
                joint   = { 0.10, 0.08, 0.04 },    -- 深棕关节
                visor   = { 0.5, 0.4, 0.1 },       -- 琥珀面罩
                visorEmissive = { 3.0, 2.0, 0.5 },
            },
            -- 装饰物：背部飞行翼
            decorations = {
                { type = "wings" },
            },
        },
        D = {
            name = "重装型 / Heavy",
            desc = "高耐久高能量，地面推力强，但飞行跳跃下降",
            color = { 255, 120, 100 },
            hp = 1.5,
            maxEnergy = 1.4,
            energyRegen = 1.3,
            moveForce = 1.2,
            maxSpeed = 1.1,
            jumpSpeed = 0.6,
            boostForce = 0.6,
            jetForce = 0.7,
            jetMaxSpeed = 0.7,
            jetCost = 1.3,
            -- 机体配色：赤红重甲
            colors = {
                body    = { 0.28, 0.15, 0.12 },    -- 暗红主体
                armor   = { 0.55, 0.12, 0.08 },    -- 深红装甲
                joint   = { 0.10, 0.05, 0.04 },    -- 深棕关节
                visor   = { 0.5, 0.1, 0.1 },       -- 红色面罩
                visorEmissive = { 3.0, 0.5, 0.3 },
            },
            -- 装饰物：肩部额外护甲板
            decorations = {
                { type = "shoulderArmor" },
            },
        },
    },

    -- ======================================================================
    -- 关卡配置
    -- ======================================================================
    Levels = {
        {
            name = "测试靶场",
            desc = "完整战斗测试",
            groundSize = 1000,
            hasEnemies = true,
            hasMelee = false,
            enemyCount = 3,
            staticVehicles = { tanks = 3, helicopters = 3 },
            scene = {
                lightGroup = "LightGroup/Daytime.xml",
                groundColor = { 0.12, 0.12, 0.14 },
                groundMetallic = 0.0,
                groundRoughness = 0.85,
                buildingColorA = { 0.18, 0.18, 0.2 },
                buildingColorB = { 0.25, 0.22, 0.2 },
                buildingMetallicA = 0.1,
                buildingMetallicB = 0.0,
                -- 靶标 + 标记锥
                decorations = {
                    -- 靶标（红白圆柱+球体）
                    { model = "Cylinder", pos = { 50, 1.5, 0 },   scale = { 0.6, 3, 0.6 },  color = { 0.8, 0.1, 0.1 }, metallic = 0.0, roughness = 0.6 },
                    { model = "Sphere",   pos = { 50, 3.2, 0 },   scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.9, 0.9 }, metallic = 0.0, roughness = 0.4 },
                    { model = "Cylinder", pos = { 80, 1.5, 40 },  scale = { 0.6, 3, 0.6 },  color = { 0.8, 0.1, 0.1 }, metallic = 0.0, roughness = 0.6 },
                    { model = "Sphere",   pos = { 80, 3.2, 40 },  scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.9, 0.9 }, metallic = 0.0, roughness = 0.4 },
                    { model = "Cylinder", pos = { -60, 1.5, 70 }, scale = { 0.6, 3, 0.6 },  color = { 0.8, 0.1, 0.1 }, metallic = 0.0, roughness = 0.6 },
                    { model = "Sphere",   pos = { -60, 3.2, 70 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.9, 0.9 }, metallic = 0.0, roughness = 0.4 },
                    -- 标记锥（橙色发光）
                    { model = "Cone", pos = { 20, 0.5, 20 },   scale = { 0.6, 1, 0.6 }, color = { 0.9, 0.4, 0.0 }, emissive = { 1.5, 0.6, 0.0 } },
                    { model = "Cone", pos = { -20, 0.5, -20 }, scale = { 0.6, 1, 0.6 }, color = { 0.9, 0.4, 0.0 }, emissive = { 1.5, 0.6, 0.0 } },
                    { model = "Cone", pos = { 40, 0.5, -30 },  scale = { 0.6, 1, 0.6 }, color = { 0.9, 0.4, 0.0 }, emissive = { 1.5, 0.6, 0.0 } },
                    { model = "Cone", pos = { -35, 0.5, 45 },  scale = { 0.6, 1, 0.6 }, color = { 0.9, 0.4, 0.0 }, emissive = { 1.5, 0.6, 0.0 } },
                },
            },
        },
        {
            name = "机甲对战",
            desc = "精英敌人测试",
            groundSize = 1000,
            mechStartPos = Vector3(0, 2, -100),
            hasEnemies = false,
            buildingClearX = 30,
            noRespawn = true,
            eliteEnemy = {
                enabled = true,
                spawnPos = Vector3(0, 0, 100),
                spawnYaw = 180,
                hp = 750,           -- 500 × 1.5（生命值提高50%）
                maxHp = 750,
                dmgMult = 2.0,      -- 伤害提高100%
            },
            scene = {
                lightGroup = "LightGroup/Dusk.xml",
                lightMult = 0.8,
                groundColor = { 0.18, 0.14, 0.12 },
                groundMetallic = 0.0,
                groundRoughness = 0.9,
                buildingColorA = { 0.25, 0.18, 0.16 },
                buildingColorB = { 0.20, 0.18, 0.20 },
                buildingMetallicA = 0.05,
                buildingMetallicB = 0.1,
                fog = { color = { 0.12, 0.10, 0.18 }, start = 120, fogEnd = 400 },
                -- 废墟残垣 + 发光路灯
                decorations = {
                    -- 倾斜残垣（破碎建筑碎片）
                    { model = "Box", pos = { 25, 1.5, 15 },   scale = { 6, 3, 1.5 }, color = { 0.12, 0.10, 0.08 }, roughness = 0.95, rotation = { 0, 25, 12 } },
                    { model = "Box", pos = { -35, 1.0, 50 },  scale = { 4, 2, 1.2 }, color = { 0.14, 0.10, 0.08 }, roughness = 0.95, rotation = { 8, -15, 0 } },
                    { model = "Box", pos = { 60, 0.8, -40 },  scale = { 3, 1.6, 5 }, color = { 0.10, 0.08, 0.07 }, roughness = 0.95, rotation = { -5, 40, 6 } },
                    { model = "Box", pos = { -70, 1.2, -30 }, scale = { 5, 2.4, 1.8 }, color = { 0.13, 0.09, 0.08 }, roughness = 0.95, rotation = { 3, -60, -8 } },
                    { model = "Box", pos = { 45, 0.6, 70 },   scale = { 2, 1.2, 7 }, color = { 0.11, 0.09, 0.07 }, roughness = 0.95, rotation = { -10, 70, 4 } },
                    -- 路灯（灯杆+发光灯头）
                    { model = "Cylinder", pos = { 30, 4, 30 },   scale = { 0.3, 8, 0.3 },  color = { 0.2, 0.2, 0.2 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { 30, 8.3, 30 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.7, 0.3 }, emissive = { 4.0, 3.0, 1.0 } },
                    { model = "Cylinder", pos = { -40, 4, -20 },  scale = { 0.3, 8, 0.3 },  color = { 0.2, 0.2, 0.2 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { -40, 8.3, -20 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.7, 0.3 }, emissive = { 4.0, 3.0, 1.0 } },
                    { model = "Cylinder", pos = { 70, 4, -60 },  scale = { 0.3, 8, 0.3 },  color = { 0.2, 0.2, 0.2 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { 70, 8.3, -60 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.7, 0.3 }, emissive = { 4.0, 3.0, 1.0 } },
                    { model = "Cylinder", pos = { -60, 4, 50 },  scale = { 0.3, 8, 0.3 },  color = { 0.2, 0.2, 0.2 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { -60, 8.3, 50 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.7, 0.3 }, emissive = { 4.0, 3.0, 1.0 } },
                    -- 远处的倾倒路灯（增加破败感）
                    { model = "Cylinder", pos = { 100, 2, 80 },  scale = { 0.3, 8, 0.3 }, color = { 0.15, 0.15, 0.15 }, metallic = 0.5, roughness = 0.6, rotation = { 0, 30, 55 } },
                    { model = "Cylinder", pos = { -90, 2, -70 }, scale = { 0.3, 8, 0.3 }, color = { 0.15, 0.15, 0.15 }, metallic = 0.5, roughness = 0.6, rotation = { 0, -45, -50 } },
                },
            },
        },
        {
            name = "镇压叛乱",
            desc = "清剿叛军坦克与直升机",
            groundSize = 1000,
            hasEnemies = false,
            noRespawn = true,
            rebellion = {
                enabled = true,
                spawnMode = "continuous",   -- 持续生成模式
                initialSpawn = 5,           -- 初始生成数量
                spawnInterval = 5.0,        -- 每次检测间隔（秒）
                spawnPerCheck = 5,          -- 每次最多补充数量
                maxAlive = 20,              -- 场上同时最多存活数
                maxTotal = 50,              -- 关卡最多生成总数
                killsToWin = 50,            -- 击杀此数通关
                tankHP = 40,
                tankMaxHP = 40,
                heliHP = 10,
                heliMaxHP = 10,
            },
            scene = {
                lightGroup = "LightGroup/Dusk.xml",
                groundColor = { 0.25, 0.20, 0.12 },
                groundMetallic = 0.0,
                groundRoughness = 0.9,
                buildingColorA = { 0.30, 0.22, 0.14 },
                buildingColorB = { 0.35, 0.28, 0.18 },
                buildingMetallicA = 0.15,
                buildingMetallicB = 0.05,
                -- 竞技场柱子 + 拱门
                decorations = {
                    -- 金属柱子（环绕竞技场）
                    { model = "Cylinder", pos = { 60, 5, 0 },    scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { -60, 5, 0 },   scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { 0, 5, 60 },    scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { 0, 5, -60 },   scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { 42, 5, 42 },   scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { -42, 5, 42 },  scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { 42, 5, -42 },  scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    { model = "Cylinder", pos = { -42, 5, -42 }, scale = { 1.2, 10, 1.2 },  color = { 0.5, 0.4, 0.25 }, metallic = 0.8, roughness = 0.3 },
                    -- 入口拱门（两柱+横梁）
                    { model = "Cylinder", pos = { 80, 6, 78 },   scale = { 1.5, 12, 1.5 },  color = { 0.4, 0.3, 0.15 }, metallic = 0.7, roughness = 0.35 },
                    { model = "Cylinder", pos = { 80, 6, 86 },   scale = { 1.5, 12, 1.5 },  color = { 0.4, 0.3, 0.15 }, metallic = 0.7, roughness = 0.35 },
                    { model = "Box",      pos = { 80, 12.5, 82 }, scale = { 2.0, 1.0, 10 },  color = { 0.45, 0.35, 0.2 }, metallic = 0.6, roughness = 0.4 },
                    -- 第二个拱门
                    { model = "Cylinder", pos = { -80, 6, -78 },  scale = { 1.5, 12, 1.5 },  color = { 0.4, 0.3, 0.15 }, metallic = 0.7, roughness = 0.35 },
                    { model = "Cylinder", pos = { -80, 6, -86 },  scale = { 1.5, 12, 1.5 },  color = { 0.4, 0.3, 0.15 }, metallic = 0.7, roughness = 0.35 },
                    { model = "Box",      pos = { -80, 12.5, -82 }, scale = { 2.0, 1.0, 10 }, color = { 0.45, 0.35, 0.2 }, metallic = 0.6, roughness = 0.4 },
                },
            },
        },
        {
            name = "精英对战",
            desc = "高强度精英机体对决",
            groundSize = 1000,
            mechStartPos = Vector3(0, 2, -100),
            hasEnemies = false,
            buildingClearX = 30,
            noRespawn = true,
            eliteEnemy = {
                enabled = true,
                spawnPos = Vector3(0, 0, 100),
                spawnYaw = 180,
                hp = 2000,          -- 500 × 4（生命值提高300%）
                maxHp = 2000,
                dmgMult = 4.0,      -- 伤害提高300%
            },
            scene = {
                lightGroup = "LightGroup/Dusk.xml",
                lightMult = 0.7,
                groundColor = { 0.14, 0.10, 0.16 },
                groundMetallic = 0.1,
                groundRoughness = 0.85,
                buildingColorA = { 0.22, 0.16, 0.24 },
                buildingColorB = { 0.16, 0.14, 0.20 },
                buildingMetallicA = 0.2,
                buildingMetallicB = 0.15,
                fog = { color = { 0.10, 0.06, 0.14 }, start = 100, fogEnd = 350 },
                decorations = {
                    -- 废墟残垣
                    { model = "Box", pos = { 30, 2, 20 },    scale = { 8, 4, 2 },   color = { 0.10, 0.07, 0.12 }, roughness = 0.95, rotation = { 0, 35, 8 } },
                    { model = "Box", pos = { -40, 1.5, 60 }, scale = { 5, 3, 1.5 }, color = { 0.12, 0.08, 0.10 }, roughness = 0.95, rotation = { 5, -20, 0 } },
                    { model = "Box", pos = { 70, 1.0, -50 }, scale = { 4, 2, 6 },   color = { 0.08, 0.06, 0.09 }, roughness = 0.95, rotation = { -3, 50, 5 } },
                    { model = "Box", pos = { -65, 1.5, -35 }, scale = { 6, 3, 2 },  color = { 0.11, 0.07, 0.10 }, roughness = 0.95, rotation = { 4, -55, -6 } },
                    -- 红色警示灯柱
                    { model = "Cylinder", pos = { 40, 4, 40 },    scale = { 0.3, 8, 0.3 },  color = { 0.15, 0.15, 0.15 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { 40, 8.3, 40 },  scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.2, 0.2 }, emissive = { 5.0, 0.5, 0.5 } },
                    { model = "Cylinder", pos = { -50, 4, -30 },  scale = { 0.3, 8, 0.3 },  color = { 0.15, 0.15, 0.15 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { -50, 8.3, -30 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.2, 0.2 }, emissive = { 5.0, 0.5, 0.5 } },
                    { model = "Cylinder", pos = { 65, 4, -55 },   scale = { 0.3, 8, 0.3 },  color = { 0.15, 0.15, 0.15 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { 65, 8.3, -55 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.2, 0.2 }, emissive = { 5.0, 0.5, 0.5 } },
                    { model = "Cylinder", pos = { -55, 4, 55 },   scale = { 0.3, 8, 0.3 },  color = { 0.15, 0.15, 0.15 }, metallic = 0.6, roughness = 0.5 },
                    { model = "Sphere",   pos = { -55, 8.3, 55 }, scale = { 0.8, 0.8, 0.8 }, color = { 0.9, 0.2, 0.2 }, emissive = { 5.0, 0.5, 0.5 } },
                    -- 倾倒灯柱
                    { model = "Cylinder", pos = { 95, 2, 75 },   scale = { 0.3, 8, 0.3 }, color = { 0.12, 0.12, 0.12 }, metallic = 0.5, roughness = 0.6, rotation = { 0, 25, 60 } },
                    { model = "Cylinder", pos = { -85, 2, -65 }, scale = { 0.3, 8, 0.3 }, color = { 0.12, 0.12, 0.12 }, metallic = 0.5, roughness = 0.6, rotation = { 0, -40, -55 } },
                },
            },
        },
        {
            name = "BOSS战",
            desc = "击败无人机+战车合体BOSS",
            groundSize = 600,
            mechStartPos = Vector3(0, 2, -80),
            hasEnemies = false,
            hasMelee = false,
            noRespawn = true,
            noBuildings = true,
            bossBattle = {
                enabled = true,
                -- 一阶段：合体形态（无人机+战车）
                phase1 = {
                    hp = 2000,
                    maxHp = 2000,
                    altitude = 25,          -- 盘旋高度（米）
                    moveSpeed = 18.0,       -- 空中移动速度
                    orbitRadius = 60,       -- 盘旋半径
                    tiltAngle = 20,         -- 移动倾斜角度
                    -- 机枪（无人机4挺）
                    mgFireRate = 0.12,      -- 机枪射击间隔
                    mgBurstDur = 3.0,       -- 连射时间
                    mgCooldown = 2.0,       -- 连射间歇
                    mgDamage = 32,          -- 单发伤害（×4）
                    mgBulletSpeed = 180,    -- 子弹速度
                    -- 飞弹（战车飞弹舱）
                    missileCooldown = 8.0,  -- 飞弹冷却
                    missileCount = 4,       -- 每次发射数量
                    missileDamage = 160,    -- 单发伤害（×4）
                    -- 战车炮塔（合体时向下俯射）
                    turretYawSpeed = 60.0,  -- 炮塔水平转速（度/秒）
                    turretPitchSpeed = 40.0,-- 炮塔俯仰转速
                    turretMinPitch = -30.0, -- 二级炮塔最大下俯角（-30度，高空俯射需要）
                    turretMaxPitch = 10.0,  -- 二级炮塔最大仰角
                    cannonCooldown = 3.0,   -- 火炮冷却
                    cannonDamage = 200,     -- 单发伤害（×4）
                    cannonBulletSpeed = 320, -- 炮弹速度
                    -- 小无人机
                    droneSpawnInterval = 25.0, -- 放出小无人机间隔
                    droneMaxAlive = 15,     -- 最多同时存活
                    droneHP = 35,
                },
                -- 阶段过渡
                transition = {
                    explosionCount = 12,    -- 无人机爆炸次数
                    fallDuration = 1.5,     -- 战车坠落时间
                    debrisCount = 20,       -- 碎片数量
                },
                -- 二阶段：战车地面战
                phase2 = {
                    hp = 1500,
                    maxHp = 1500,
                    moveSpeed = 18.0,       -- 地面移动速度
                    turnSpeed = 40.0,       -- 车体转向速度（度/秒）
                    -- 炮塔
                    turretYawSpeed = 45.0,  -- 炮塔水平转速（度/秒）
                    turretPitchSpeed = 30.0,-- 炮塔俯仰转速
                    turretMaxPitch = 70.0,  -- 炮塔仰角限制
                    -- 左右火炮
                    cannonCooldown = 2.5,   -- 火炮冷却
                    cannonDamage = 200,     -- 单发伤害（×4）
                    cannonBulletSpeed = 320, -- 炮弹速度
                    -- 车前机枪
                    frontMgFireRate = 0.1,
                    frontMgBurstDur = 4.0,
                    frontMgCooldown = 2.0,
                    frontMgDamage = 24,     -- ×4
                    -- 飞弹
                    missileCooldown = 10.0,
                    missileCount = 8,       -- ×2
                    missileDamage = 140,    -- ×4
                },
            },
            scene = {
                lightGroup = "LightGroup/Dusk.xml",
                lightMult = 0.6,
                groundColor = { 0.10, 0.08, 0.06 },
                groundMetallic = 0.0,
                groundRoughness = 0.9,
                buildingColorA = { 0.20, 0.16, 0.12 },
                buildingColorB = { 0.16, 0.14, 0.10 },
                buildingMetallicA = 0.1,
                buildingMetallicB = 0.05,
                fog = { color = { 0.08, 0.06, 0.04 }, start = 80, fogEnd = 300 },
            },
        },
    },

    -- BOSS 战 AI 配置
    BossAI = {
        -- 小型无人机
        MiniDroneMoveSpeed = 10.0,
        MiniDroneOrbitRadius = 50.0,      -- 轨道半径 50m（拉远距离）
        MiniDroneAltitudeMin = 25.0,      -- 最低飞行高度（直升机级别）
        MiniDroneAltitudeMax = 40.0,      -- 最高飞行高度
        MiniDroneDeployDist = 30.0,       -- 散开阶段飞行距离
        MiniDroneDeploySpeed = 25.0,      -- 散开阶段速度
        MiniDroneMGFireRate = 0.2,
        MiniDroneMGDamage = 20,       -- ×4
        MiniDroneMGBulletSpeed = 80,
        MiniDroneMGBurstDur = 2.0,
        MiniDroneMGCooldown = 3.0,
    },

    -- 叛军 AI 配置
    RebelAI = {
        -- 坦克
        TankMoveSpeed = 6.0,
        TankTurnSpeed = 60.0,
        TankRangeMin = 40,
        TankRangeIdeal = 100,
        TankRangeMax = 200,
        TankCannonCooldownMin = 4.0,
        TankCannonCooldownMax = 8.0,
        TankMG_BurstDuration = 2.0,
        TankMG_CooldownMin = 2.0,
        TankMG_CooldownMax = 4.0,
        -- 直升机
        HeliMoveSpeed = 12.0,
        HeliAltitudeMin = 30,
        HeliAltitudeMax = 60,
        HeliOrbitMin = 100,
        HeliOrbitMax = 200,
        HeliCircleSpeed = 15.0,
        HeliMG_BurstDuration = 3.0,
        HeliMG_CooldownMin = 2.0,
        HeliMG_CooldownMax = 4.0,
        -- 生成
        SpawnDistance = 460,
    },

    -- 精英 AI 配置
    EliteAI = {
        -- 距离阈值（米）
        RangeMin = 50,          -- 小于此距离会后退
        RangeIdeal = 100,       -- 理想交战距离
        RangeMax = 150,         -- 超过此距离会接近

        -- 移动速度（m/s）
        MoveSpeed = 8.0,
        RetreatSpeed = 10.0,
        TurnSpeed = 120.0,      -- 转向速度 度/秒
        LateralDriftSpeed = 3.0,-- 横向漂移速度

        -- 闪避（检测到弹丸时触发）
        DodgeDetectRadius = 30.0,   -- 弹丸威胁检测半径（米）
        DodgeDetectAngle = 45.0,    -- 弹丸朝向角度阈值（度，越小越精准）
        DodgeImpulse = 40.0,        -- 闪避瞬移速度（m/s）
        DodgeDuration = 0.3,        -- 闪避持续时间（秒）
        DodgeCooldown = 1.5,        -- 闪避冷却时间（秒）
        DodgeChance = 0.7,          -- 闪避触发概率 (0~1)

        -- 喷射闪避（检测到 RPG/飞弹时，侧向喷射移动躲避）
        JetDodgeSpeed = 60.0,       -- 喷射闪避速度（m/s）
        JetDodgeDuration = 0.5,     -- 喷射闪避持续时间（秒）
        JetDodgeCooldown = 3.0,     -- 喷射闪避冷却时间（秒）
        JetDodgeChance = 0.6,       -- 喷射闪避触发概率 (0~1)
        JetDodgeDetectRadius = 50.0,-- RPG/飞弹威胁检测半径（米）

        -- 跳跃
        JumpSpeed = 20.0,           -- 跳跃初速度（m/s）
        JumpCooldown = 3.0,         -- 跳跃冷却（秒）
        JumpChance = 0.3,           -- 每次冷却后随机跳跃概率
        JumpGravity = -20.0,        -- 跳跃重力

        -- 飞行（喷射）
        JetSpeed = 15.0,            -- 飞行上升/移动速度
        JetMaxAltitude = 35.0,      -- 最大飞行高度（降低，避免飞太高脱离战斗）
        JetMinAltitude = 10.0,      -- 飞行最低高度（悬停高度）
        JetDuration = 3.0,          -- 单次飞行最大持续时间（缩短，快速升空→攻击→降落）
        JetCooldown = 8.0,          -- 飞行冷却时间
        JetChance = 0.3,            -- 飞行触发概率
        JetDamping = 3.0,           -- 飞行空中阻力

        -- 初始交战延迟（秒，进入 engage 后多久开始攻击）
        InitialDelay = 0.5,

        -- 机关枪调度
        MG_BurstDuration = 4.0, -- 连发持续时间
        MG_CooldownMin = 0.2,   -- 连发间歇最小
        MG_CooldownMax = 0.6,   -- 连发间歇最大

        -- RPG 调度
        RPG_Cooldown = 3.0,
        RPG_InitialDelay = 1.5,

        -- 飞弹调度
        Missile_Cooldown = 6.0,
        Missile_InitialDelay = 2.5,
        Missile_BurstInterval = 0.15, -- 飞弹队列逐发间隔

        -- 视线检测间隔
        LOSCheckInterval = 0.2,

        -- 重生延迟
        RespawnDelay = 10.0,

        -- AI 类型参数覆盖（按武器装备自动选择）
        TypeOverrides = {
            -- 近战型：装备霰弹枪时激活，更近距离交战
            melee = {
                RangeMin = 20,              -- 后撤距离 20m（默认50）
                RangeIdeal = 40,            -- 理想交战距离 40m（默认100）
                RangeMax = 80,              -- 交战阈值 80m（默认150）
                MoveSpeed = 12.0,           -- 接近速度 +50%（默认8.0）
                RetreatSpeed = 12.0,        -- 后撤速度（默认10.0）
                LateralDriftSpeed = 5.0,    -- 横向漂移更快（默认3.0）
                JetChance = 0,              -- 不飞行
                JumpChance = 0.5,           -- 更频繁跳跃（默认0.3）
            },
            -- 飞行型：装备RPG/肩扛火箭时35%概率激活，长时间空中战斗
            aerial = {
                JetDuration = 6.0,          -- 飞行时间 2x（默认3.0）
                JetMaxAltitude = 50.0,      -- 更高上限（默认35.0）
                JetMinAltitude = 15.0,      -- 更高悬停（默认10.0）
                JetChance = 0.6,            -- 飞行概率 2x（默认0.3）
                JetCooldown = 4.0,          -- 冷却减半（默认8.0）
                JetSpeed = 18.0,            -- 起飞更快（默认15.0）
                JetAllStates = true,        -- 所有战斗状态可飞行（默认仅engage）
            },
        },
    },

    -- 近战 AI 配置
    MeleeAI = {
        ApproachSpeed = 14.0,       -- 冲锋速度（m/s）
        CircleSpeed = 6.0,          -- 绕行速度（m/s）
        TurnSpeed = 180.0,          -- 转向速度（度/秒）
        AttackRange = 5.0,          -- 攻击距离（米）
        CircleRange = 10.0,         -- 绕行距离（米）
        EngageRange = 20.0,         -- 超过此距离重新冲锋
        AttackWindup = 0.2,         -- 攻击前摇（秒）
        AttackDuration = 0.5,       -- 攻击动作总时长（秒）
        AttackCooldown = 0.8,       -- 攻击冷却（秒）
        AttackDamage = 25,          -- 单次伤害
        HP = 80,
        MaxHP = 80,
        CircleDirChangeMin = 2.0,   -- 换向最小间隔
        CircleDirChangeMax = 4.0,   -- 换向最大间隔
        RespawnDelay = 8.0,         -- 重生延迟（秒）
        SpawnCount = 3,             -- 生成数量
    },

    -- 场景（默认值，可被关卡覆盖）
    GroundSize = 1000,
    MechStartPos = Vector3(0, 2, 0),

    -- 相机
    CameraDistance = 10.0,
    CameraOffset = Vector3(0, 4.0, 0),
    CameraFov = 45.0,
    CameraFarClip = 1500.0,

    -- 运动（冲量驱动）
    JumpSpeed = 45.0,
    MoveForceForward = 800,
    MoveForceLateral = 400,
    AirMoveForce = 400,
    MaxSpeedForward = 28.0,
    MaxSpeedLateral = 10.0,
    GroundDamping = 5.0,
    AirDamping = 3.5,

    -- 能量系统
    MaxEnergy = 140,
    JumpCost = 8,
    BoostCostPerSec = 20,
    EnergyRegenPerSec = 70,
    BoostDelay = 0.1,
    BoostForce = Vector3(0, 800, 0),
    Gravity = Vector3(0, -30, 0),

    -- 冲刺
    DashImpulse = 3000.0,
    DashDuration = 0.5,
    DashCooldown = 0.35,
    DashEnergyCost = 12,

    -- 喷射（C键切换，向视角方向自由飞行）
    JetActivationCost = 25,   -- 启动喷射所需能量
    JetCostPerSec = 8,        -- 喷射每秒消耗能量
    JetForce = 900,
    JetMaxSpeed = 150.0,
    JetDamping = 7.0,
    JetDashImpulse = 1500.0,  -- 喷射模式左右突进瞬间冲量
    JetDashDuration = 0.3,    -- 喷射突进持续时间
    JetDashCooldown = 0.35,   -- 喷射突进冷却时间

    -- ======================================================================
    -- 可用模型列表（调试模式使用）
    -- ======================================================================
    Models = {
        {
            name = "机甲 (Mech - 程序化)",
            procedural = "mech",
            scale = 1.0,
            heightOffset = 0,
            -- 动画由 MechAnimator 提供，此处仅声明名称供 UI 显示
            animations = {
                { name = "待机 Idle",           id = "idle",    loop = true },
                { name = "前进 Forward",        id = "move_f",  loop = true },
                { name = "左前 Forward-Left",   id = "move_fl", loop = true },
                { name = "右前 Forward-Right",  id = "move_fr", loop = true },
                { name = "左移 Left",           id = "move_l",  loop = true },
                { name = "右移 Right",          id = "move_r",  loop = true },
                { name = "后退 Backward",       id = "move_b",  loop = true },
                { name = "左后 Backward-Left",  id = "move_bl", loop = true },
                { name = "右后 Backward-Right", id = "move_br", loop = true },
                { name = "跳跃 Jump",           id = "jump",    loop = false },
                { name = "飞行 Fly",            id = "fly",     loop = true },
                { name = "攻击 Attack",         id = "attack",  loop = false },
            },
        },
        {
            name = "DefaultMale (基础男性)",
            prefab = "DefaultMale/DefaultMale.prefab",
            scale = 1.0,
            heightOffset = 0,
            animations = {
                { name = "待机 Idle",       path = "DefaultMale/Animations/DefaultMale_Idle.ani",        loop = true },
                { name = "行走 Walk",       path = "DefaultMale/Animations/DefaultMale_Walk.ani",        loop = true },
                { name = "奔跑 Run",        path = "DefaultMale/Animations/DefaultMale_Run.ani",         loop = true },
                { name = "跳跃起步 JumpStart", path = "DefaultMale/Animations/DefaultMale_JumpStart.ani", loop = false },
                { name = "跳跃空中 JumpAir",   path = "DefaultMale/Animations/DefaultMale_JumpAir.ani",   loop = true },
                { name = "跳跃落地 JumpLand",  path = "DefaultMale/Animations/DefaultMale_JumpLanding.ani", loop = false },
                { name = "步枪待机 RifleIdle",  path = "DefaultMale/Animations/DefaultMale_RifleIdle.ani",  loop = true },
                { name = "步枪行走 RifleWalk",  path = "DefaultMale/Animations/DefaultMale_RifleWalk.ani",  loop = true },
                { name = "步枪奔跑 RifleRun",   path = "DefaultMale/Animations/DefaultMale_RifleRun.ani",   loop = true },
                { name = "步枪射击 RifleShoot",  path = "DefaultMale/Animations/DefaultMale_RifleShoot.ani", loop = false },
                { name = "步枪换弹 RifleReload", path = "DefaultMale/Animations/DefaultMale_RifleReload.ani", loop = false },
                { name = "欢乐舞蹈 HappyDance", path = "DefaultMale/Animations/DefaultMale_HappyDance.ani", loop = true },
                { name = "悲伤 Sad",        path = "DefaultMale/Animations/DefaultMale_Sad.ani",         loop = true },
                { name = "挥手 Wave",       path = "DefaultMale/Animations/DefaultMale_Wave.ani",        loop = true },
                { name = "死亡 Death",      path = "DefaultMale/Animations/DefaultMale_Death.ani",       loop = false },
            },
        },
        {
            name = "DefaultMale Base (uuid)",
            prefab = "uuid://DEkZaUTQvLlCdjdIzpnHa4n-",
            scale = 1.0,
            heightOffset = 0,
            animations = {
                { name = "待机 Idle",           path = "uuid://HIPCWSBd61v8PRI972Yksxzh", loop = true },
                { name = "前进 WalkFwd",        path = "uuid://HhyjGZvHN9uF8lRsGnN_J7jc", loop = true },
                { name = "后退 WalkBack",       path = "uuid://D1ZQufismDgjXSoKZLIPS0Ed", loop = true },
                { name = "左移 WalkLeft",       path = "uuid://E20NmRUGYWU3kHiXsgMpK6M9", loop = true },
                { name = "右移 WalkRight",      path = "uuid://FqnAEeCLvzfAfmj8w1mLT5wN", loop = true },
                { name = "奔跑前进 RunFwd",     path = "uuid://FshxoWge4mzIJ-wmBu0GK6Vs", loop = true },
                { name = "奔跑后退 RunBack",    path = "uuid://GbEQ4Yfi36owuXgXwLH-q9n-", loop = true },
                { name = "奔跑左 RunLeft",      path = "uuid://H3wCCfEG31uakcELQ_6sOJrS", loop = true },
                { name = "奔跑右 RunRight",     path = "uuid://HKwNmWgv0k-oOphSX0ABz_6q", loop = true },
                { name = "跳跃起步 JumpStart",  path = "uuid://HtKsAZlvLj2z6gaa-uUwgSNR", loop = false },
                { name = "跳跃空中 JumpAir",    path = "uuid://DXeeuc1cpg9jcUet7s7HXSSe", loop = true },
                { name = "跳跃落地 JumpLand",   path = "uuid://C2C10UxrN89PqguP2Okn5UFN", loop = false },
                { name = "步枪待机 RifleIdle",   path = "uuid://Fr-FWfmJepwZF0R_LPCTQPDI", loop = true },
                { name = "步枪行走 RifleWalk",   path = "uuid://AgKtoXJRWPQMEHMyolGMBXgi", loop = true },
                { name = "步枪奔跑 RifleRun",    path = "uuid://E1kk2aFklf8PKggO8l16aB8S", loop = true },
                { name = "步枪射击 RifleShoot",   path = "uuid://G5nP6crrRXCR2zaWoRa6AlV_", loop = false },
                { name = "步枪换弹 RifleReload",  path = "uuid://EGWfYfsi5tFVWp2x1-MD4_VF", loop = false },
                { name = "舞蹈 Dance",          path = "uuid://Bcznmcorg6vWe2rwVHE4GssL", loop = true },
                { name = "悲伤 Sad",            path = "uuid://Hm8O6cErEVxPtAEi-Ekkz6J2", loop = true },
                { name = "死亡 Death",          path = "uuid://EG2jgdmuO4kUBOCaWbz5S6i7", loop = false },
            },
        },
        {
            name = "Q版兔子怪",
            prefab = "uuid://F12SES4zQPcHEeguNU8_jQnV",
            scale = 2.0,
            heightOffset = 0,
            animations = {
                { name = "待机 Idle",     path = "uuid://EeMT0Q9KMZqHv9a70CAKRFYD", loop = true },
                { name = "默认待机 DmIdle", path = "uuid://B-cxYRsaHOc5n4bGfeBhyxQx", loop = true },
                { name = "行走 Walk",     path = "uuid://Gx8-ifcVu-o6mrw8JrJDOKwd", loop = true },
                { name = "移动 Move",     path = "uuid://AA9H0fCwGzE-acevexflV6k5", loop = true },
                { name = "攻击 Attack",   path = "uuid://DjR0ySSAfuQ32hC6KPaAOxfq", loop = false },
                { name = "技能 Skill",    path = "uuid://EzhYEapnl3LtK-irqf7AtM7X", loop = false },
                { name = "受击 Hit",      path = "uuid://CV0PWaVyQ_KSpNBbfzYHF0Ms", loop = false },
                { name = "死亡 Die",      path = "uuid://Fx1W-Q2AeLivvaRqFFEPzdQb", loop = false },
                { name = "着陆 Landing",  path = "uuid://CzdJURftUbVR6b1pvXR2Qwlp", loop = false },
                { name = "睡觉 Sleep",    path = "uuid://A4Kdefa0OXjolRnd7cwCjGS3", loop = true },
                { name = "眩晕 Vertigo",  path = "uuid://BLxVQWbEcNLEutBt0qb4sicM", loop = true },
                { name = "抚摸 Caress",   path = "uuid://A_vxKWJ-KeBDx92kMRWLuzH-", loop = true },
                { name = "吃东西 Eat",    path = "uuid://HlAsydZVUK3wTOE0hlw1gLAg", loop = true },
                { name = "锻造 Forging",  path = "uuid://Gb6TaUcl1TQtde7s2hU3Bteb", loop = true },
                { name = "起飞 Takeoff",  path = "uuid://HQi6OXO6qwe0FZr6ry3UjotT", loop = false },
                { name = "运输 Transport", path = "uuid://A4ft4Zv1FZPQ3Tw-T4CMolDT", loop = true },
            },
        },
        -- 武器预览
        {
            name = "武器库 (Weapons)",
            procedural = "weapons",
            scale = 1.0,
            heightOffset = 0,
            animations = {},
        },
        -- BOSS 战车
        {
            name = "BOSS 战车 (Heavy Tank)",
            procedural = "boss",
            scale = 1.0,
            heightOffset = 0,
            animations = {},
        },
        -- BOSS2 四轴无人机
        {
            name = "BOSS2 无人机 (Heavy Quadcopter)",
            procedural = "boss2",
            scale = 2.0,
            heightOffset = 0,
            animations = {},
        },
        -- BOSS 合体 (无人机 + 战车)
        {
            name = "BOSS 合体 (Drone + Tank)",
            procedural = "boss_combined",
            scale = 2.0,
            heightOffset = 0,
            animations = {},
        },
    },
}

return CONFIG
