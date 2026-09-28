-- ============================================================================
-- Config.lua - 游戏配置常量
-- ============================================================================

local M = {}

-- ============================================================================
-- 枚举定义
-- ============================================================================

--- 子弹碰撞检测模式
M.BULLET_COLLISION_MODE = {
    PHYSICS = 1,   -- 物理碰撞 - 子弹有物理刚体，通过物理引擎检测碰撞
    RAYCAST = 2,   -- 射线检测 - 射击瞬间用射线判定命中，子弹仅作为视觉效果
}

-- ============================================================================
-- 游戏配置
-- ============================================================================

M.CONFIG = {
    Title = "3D Shooter Demo - Hip Fire",
    
    -- 玩家设置
    PlayerHeight = 1.8,          -- 玩家高度（米）
    PlayerRadius = 0.3,          -- 玩家碰撞半径
    MoveSpeed = 5.0,             -- 移动速度（米/秒）
    MouseSensitivity = 0.15,     -- 鼠标灵敏度
    
    -- 跳跃和重力设置
    Gravity = -20.0,             -- 重力加速度（米/秒²）
    JumpSpeed = 12.5,            -- 跳跃初速度（米/秒）- 可跳上约3.9米平台
    GroundCheckOffset = 0.05,    -- 地面检测容差
    
    -- 生命值设置
    MaxHealth = 100,             -- 最大生命值
    HealthRegenDelay = 5.0,      -- 受伤后开始回血的延迟（秒）
    HealthRegenRate = 10.0,      -- 回血速度（点/秒）
    
    -- 相机设置
    CameraNearClip = 0.1,
    CameraFarClip = 300.0,
    CameraFov = 60.0,
    BulletTimeFov = 75.0,        -- 子弹时间时的 FOV（度）
    
    -- 武器设置（腰射模式）
    GunOffsetRight = 0.25,       -- 枪在相机右侧的偏移
    GunOffsetDown = 0.25,        -- 枪在相机下方的偏移
    GunOffsetForward = 0.25,      -- 枪在相机前方的偏移
    MuzzleOffset = 0.4,          -- 枪口相对于枪中心的前方偏移
    
    -- 武器设置（瞄准模式 ADS）
    AdsOffsetRight = 0.0,        -- 瞄准时枪在相机中心
    AdsOffsetDown = 0.05,        -- 瞄准时枪在屏幕中心偏下
    AdsOffsetForward = 0.25,     -- 瞄准时枪更靠近相机
    AdsTransitionSpeed = 8.0,    -- 瞄准过渡速度
    AdsFov = 45.0,               -- 瞄准时 FOV（度）
    
    -- 左右手切换动画设置
    HandSwitchSpeed = 6.0,       -- 切换过渡速度
    HandSwitchDropDistance = 0.3,-- 切换时枪下沉距离
    
    -- 武器切换动画设置
    WeaponSwitchTime = 0.3,      -- 武器切换总时间（秒）- 加快
    WeaponSwitchDropDistance = 0.4, -- 切换时枪下沉距离
    WeaponSwitchRotateAngle = 30,   -- 切换时枪旋转角度（度）
    
    -- 通用设置
    RecoilRecoverySpeed = 10.0,  -- 后坐力恢复速度（度/秒）
    CrosshairRecoverySpeed = 50, -- 准心恢复速度（像素/秒）
    
    -- 特效设置
    ShowBulletHoles = true,      -- 是否显示弹孔
    
    -- 子弹碰撞检测模式（使用 BULLET_COLLISION_MODE 枚举）
    -- PHYSICS(1): 物理碰撞 - 子弹有物理刚体，通过物理引擎实时检测碰撞（更准确，支持移动目标）
    -- RAYCAST(2): 射线检测 - 射击瞬间用射线判定命中，子弹仅作为视觉效果（发射时就确定命中）
    BulletCollisionMode = 2,  -- BULLET_COLLISION_MODE.RAYCAST - 射线检测，发射时瞬间判定
    
    -- 后坐力缓动设置
    RecoilEaseSpeed = 25.0,      -- 后坐力应用速度（度/秒，越大越快应用）
    MaxUpwardPitch = -45.0,      -- 触发自动恢复的最大上仰角度（负数=向上看）
    PitchRecoverySpeed = 8.0,    -- 枪口过高时的恢复速度（度/秒）
    PitchRecoveryTarget = -15.0, -- 恢复的目标角度（负数=向上看）
    BulletLifetime = 3.0,        -- 子弹默认存活时间（秒）- 仅作为后备
    BulletMinRange = 100.0,      -- 子弹最小飞行距离（米）
    
    -- 射线检测设置
    MaxShootDistance = 50.0,     -- 最大射程（米）- 超过此距离无法命中
    
    -- 靶子设置
    TargetVisualRadius = 0.5,    -- 靶子视觉半径（方块半边长）
    TargetScore = 100,           -- 击中得分
    TargetCount = 8,             -- 靶子数量
    
    -- 怪物设置
    MonsterCount = 10,            -- 动态怪物数量
    StaticMonsterMaxCount = 20,  -- 静态怪物最大数量
    MonsterHealth = 50,          -- 怪物生命值
    MonsterSpeed = 3.0,          -- 怪物移动速度（米/秒）
    MonsterDamage = 15,          -- 怪物攻击伤害
    MonsterAttackRange = 1.5,    -- 怪物攻击范围（米）
    MonsterAttackCooldown = 1.0, -- 怪物攻击冷却（秒）
    MonsterSize = 0.8,           -- 怪物大小（半径）
    MonsterHeight = 1.9,         -- 怪物高度
    MonsterSpawnRadius = 15,     -- 怪物生成距离玩家的最小半径
    MonsterKillScore = 50,       -- 击杀怪物得分
    MonsterJumpForce = 6.0,      -- 怪物跳跃力度
    MonsterJumpCooldown = 2.5,   -- 怪物跳跃冷却（秒）
    MonsterJumpChance = 0.3,     -- 怪物每次冷却后跳跃概率
    MonsterStrafeSpeed = 2.0,    -- 怪物横向移动速度
    MonsterStrafeInterval = 1.0, -- 怪物改变横移方向的间隔
    
    -- 怪物死亡动画设置
    MonsterDeathDuration = 0.6,  -- 死亡动画持续时间（秒）
    MonsterDeathShrink = 0.1,    -- 死亡时缩小到的比例
    MonsterDeathSink = 0.5,      -- 死亡时下沉距离（米）
    MonsterDeathRotation = 360,  -- 死亡时旋转角度（度）
    
    -- 场景设置
    ArenaSize = 50,              -- 场地大小（加大）
    
    -- 手榴弹设置
    GrenadeRadius = 0.12,        -- 手榴弹半径（米）
    GrenadeThrowSpeed = 20.0,    -- 投掷初速度（米/秒）
    GrenadeThrowAngle = 30,      -- 投掷仰角（度）
    GrenadeFuseTime = 1.2,       -- 引信时间（秒）
    GrenadeExplosionRadius = 7.0, -- 爆炸半径（米）
    GrenadeFullDamageRadius = 3.5,-- 全额伤害半径（米）
    GrenadeMinDamagePercent = 0.2,-- 最远距离时最小伤害比例（20%）
    GrenadeExplosionDamage = 200, -- 爆炸伤害
    GrenadeGravity = -35.0,      -- 手榴弹重力
    GrenadeBounce = 0.6,         -- 弹跳系数（0-1）
    GrenadeCollisionDamping = 0.4, -- 碰撞后速度衰减系数
    GrenadeMaxCount = 10,         -- 最大手榴弹数量
    GrenadeCooldown = 0.5,       -- 投掷冷却（秒）
    
    -- 调试设置
    DebugShowGunRay = true,      -- 显示枪口射线和预计碰撞点
    DebugShowBulletCollider = false, -- 显示子弹碰撞盒
    DebugShowMuzzlePosition = false, -- 显示枪口发射位置（红球）
    DebugTestMode = true,        -- 测试模式：子弹击中障碍物后不立即消失
    DebugBulletHitLifetime = 30.0, -- 测试模式下子弹击中后存活时间（秒）
    
    -- 音效设置
    MusicVolume = 0.3,            -- 背景音乐音量
    SfxVolume = 0.6,              -- 音效音量
    MusicPath = "Music/bgm.ogg",  -- 背景音乐路径
    SoundPaths = {
        gunshot_pistol = "Sounds/gunshot_pistol.wav",
        gunshot_rifle = "Sounds/gunshot_rifle.wav",
        gunshot_shotgun = "Sounds/gunshot_shotgun.wav",
        gunshot_ak47 = "Sounds/gunshot_rifle.wav",  -- 复用步枪音效
        hit_enemy = "Sounds/hit_enemy.wav",
        hit_wall = "Sounds/hit_wall.wav",
        kill_enemy = "Sounds/kill_enemy.wav",
        headshot = "Sounds/headshot.wav",
        reload = "Sounds/reload.wav",
        empty_clip = "Sounds/empty_clip.wav",
        player_hurt = "Sounds/player_hurt.wav",
        player_death = "Sounds/player_death.wav",
    },
}

-- ============================================================================
-- 武器配置表
-- ============================================================================

M.WEAPONS = {
    -- 手枪：精准、低后坐力、中等射速
    pistol = {
        name = "Pistol",
        nameZh = "手枪",
        
        -- 弹药
        magSize = 12,            -- 弹匣容量
        reserveAmmo = 48,        -- 备用弹药
        reloadTime = 1.2,        -- 换弹时间（秒）
        
        -- 射击
        fireRate = 0.2,          -- 射击间隔（秒）
        automatic = false,       -- 是否自动射击
        bulletsPerShot = 1,      -- 每次射击子弹数
        spreadAngle = 0,         -- 散布角度（度）
        
        -- 子弹
        bulletSpeed = 1.0,       -- 子弹速度（米/秒）
        bulletRadius = 0.01,     -- 子弹半径（降低碰撞检测）
        damage = 25,             -- 伤害值
        
        -- 后坐力
        recoilPitchMin = 0.8,    -- 镜头向上偏移最小值（度）
        recoilPitchMax = 1.2,    -- 镜头向上偏移最大值（度）
        recoilYawMin = -0.2,     -- 镜头水平偏移最小值（度）
        recoilYawMax = 0.2,      -- 镜头水平偏移最大值（度）
        crosshairSpreadMax = 60, -- 准心最大扩散（像素）
        crosshairSpreadPerShot = 25, -- 每次射击准心扩散
        crosshairRecoverySpeed = 80, -- 准心恢复速度（像素/秒）- 手枪恢复较快
        cameraShakeIntensity = 0.01,
        cameraShakeDuration = 0.06,
        
        -- 模型参数
        model = {
            positionOffset = Vector3(0, 0, 0.15),  -- 位置偏移（向前0.15）
            bodyWidth = 0.04,     -- 枪身宽度
            bodyHeight = 0.10,    -- 枪身高度
            bodyLength = 0.18,    -- 枪身长度
            barrelRadius = 0.012, -- 枪管半径
            barrelLength = 0.12,  -- 枪管长度
            gripWidth = 0.03,     -- 握把宽度
            gripHeight = 0.08,    -- 握把高度
            color = Color(0.15, 0.15, 0.18, 1.0),  -- 枪身颜色（深灰）
            accentColor = Color(0.1, 0.1, 0.12, 1.0), -- 强调色
            -- 抛壳口配置（相对于枪模型容器的本地坐标）
            ejectionPortOffset = Vector3(0.03, 0.06, 0.10),  -- 右上方偏移
        },
    },
    
    -- 自动步枪：高射速、中等后坐力、连发
    rifle = {
        name = "Rifle",
        nameZh = "步枪",
        
        -- 弹药
        magSize = 30,            -- 弹匣容量
        reserveAmmo = 90,        -- 备用弹药
        reloadTime = 2.0,        -- 换弹时间（秒）
        
        -- 射击
        fireRate = 0.1,          -- 射击间隔（秒）
        automatic = true,        -- 是否自动射击
        bulletsPerShot = 1,      -- 每次射击子弹数
        spreadAngle = 0.5,       -- 散布角度（度）
        
        -- 子弹
        bulletSpeed = 10.0,      -- 子弹速度（米/秒）
        bulletRadius = 0.01,     -- 子弹半径（降低碰撞检测）
        damage = 20,             -- 伤害值
        
        -- 后坐力
        recoilPitchMin = 0.3,    -- 镜头向上偏移最小值（度）
        recoilPitchMax = 0.6,    -- 镜头向上偏移最大值（度）
        recoilYawMin = -0.15,    -- 镜头水平偏移最小值（度）
        recoilYawMax = 0.15,     -- 镜头水平偏移最大值（度）
        crosshairSpreadMax = 60, -- 准心最大扩散（像素）
        crosshairSpreadPerShot = 12, -- 每次射击准心扩散
        crosshairRecoverySpeed = 60, -- 准心恢复速度（像素/秒）- 步枪恢复中等
        cameraShakeIntensity = 0.008,
        cameraShakeDuration = 0.05,
        
        -- 模型参数（长枪身、细长枪管）
        model = {
            bodyWidth = 0.045,    -- 枪身宽度
            bodyHeight = 0.08,    -- 枪身高度
            bodyLength = 0.35,    -- 枪身长度（更长）
            barrelRadius = 0.010, -- 枪管半径（细）
            barrelLength = 0.25,  -- 枪管长度（更长）
            gripWidth = 0.025,    -- 握把宽度
            gripHeight = 0.10,    -- 握把高度
            hasStock = true,      -- 有枪托
            stockLength = 0.15,   -- 枪托长度
            hasMagazine = true,   -- 有弹匣
            magWidth = 0.025,     -- 弹匣宽度
            magHeight = 0.08,     -- 弹匣高度
            color = Color(0.12, 0.12, 0.14, 1.0),  -- 枪身颜色（深黑）
            accentColor = Color(0.2, 0.15, 0.1, 1.0), -- 强调色（木纹）
            -- 抛壳口配置
            ejectionPortOffset = Vector3(0.035, 0.05, 0.20),  -- 右上方偏移
        },
    },
    
    -- 霰弹枪：高伤害、高后坐力、多弹丸
    shotgun = {
        name = "Shotgun",
        nameZh = "霰弹枪",
        
        -- 弹药
        magSize = 6,             -- 弹匣容量
        reserveAmmo = 24,        -- 备用弹药
        reloadTime = 0.5,        -- 单发装填时间（秒）
        
        -- 射击
        fireRate = 0.8,          -- 射击间隔（秒）
        automatic = false,       -- 是否自动射击
        bulletsPerShot = 8,      -- 每次射击子弹数（散弹）
        spreadAngle = 5.0,       -- 散布角度（度）
        
        -- 子弹
        bulletSpeed = 150.0,     -- 子弹速度（米/秒）- 加快
        bulletRadius = 0.01,     -- 子弹半径（降低碰撞检测）
        damage = 25,             -- 单颗弹丸伤害（近距离满伤害）
        
        -- 霰弹枪距离衰减设置
        headshotMaxRange = 5.0,  -- 爆头秒杀的最大距离（米）
        falloffStartRange = 3.0, -- 伤害衰减起始距离（米）
        falloffEndRange = 15.0,  -- 伤害衰减结束距离（米）
        minDamagePercent = 0.2,  -- 最远距离时的最小伤害比例（20%）
        
        -- 后坐力
        recoilPitchMin = 2.5,    -- 镜头向上偏移最小值（度）
        recoilPitchMax = 3.5,    -- 镜头向上偏移最大值（度）
        recoilYawMin = -0.8,     -- 镜头水平偏移最小值（度）
        recoilYawMax = 0.8,      -- 镜头水平偏移最大值（度）
        crosshairSpreadMax = 90, -- 准心最大扩散（像素）
        crosshairSpreadPerShot = 40, -- 每次射击准心扩散
        crosshairRecoverySpeed = 30, -- 准心恢复速度（像素/秒）- 霰弹枪恢复较慢
        cameraShakeIntensity = 0.025,
        cameraShakeDuration = 0.12,
        
        -- 模型参数（粗壮、双管）
        model = {
            bodyWidth = 0.05,     -- 枪身宽度（粗）
            bodyHeight = 0.06,    -- 枪身高度
            bodyLength = 0.30,    -- 枪身长度
            barrelRadius = 0.018, -- 枪管半径（粗）
            barrelLength = 0.30,  -- 枪管长度
            isDoubleBarrel = true, -- 双管
            barrelSpacing = 0.025, -- 双管间距
            gripWidth = 0.035,    -- 握把宽度
            gripHeight = 0.10,    -- 握把高度
            hasStock = true,      -- 有枪托
            stockLength = 0.12,   -- 枪托长度
            color = Color(0.25, 0.18, 0.12, 1.0),  -- 枪身颜色（木纹棕）
            accentColor = Color(0.1, 0.1, 0.1, 1.0), -- 强调色（金属黑）
            -- 抛壳口配置（霰弹枪抛壳较大）
            ejectionPortOffset = Vector3(0.04, 0.04, 0.15),
            casingScale = 1.5,    -- 弹壳比例放大
        },
    },
    
    -- 机关枪：超高射速、大弹匣、低后坐力、大散布
    ak47 = {
        name = "Machine Gun",
        nameZh = "机关枪",
        
        -- 弹药
        magSize = 100,           -- 弹匣容量（大弹匣）
        reserveAmmo = 300,       -- 备用弹药
        reloadTime = 3.0,        -- 换弹时间（秒）- 弹匣大所以慢
        
        -- 射击
        fireRate = 0.05,         -- 射击间隔（秒）- 超高射速
        automatic = true,        -- 是否自动射击
        bulletsPerShot = 1,      -- 每次射击子弹数
        spreadAngle = 3.0,       -- 散布角度（度）- 大散布
        
        -- 子弹
        bulletSpeed = 180.0,     -- 子弹速度（米/秒）
        bulletRadius = 0.01,     -- 子弹半径（降低碰撞检测）
        damage = 15,             -- 伤害值 - 较低但射速快
        
        -- 后坐力（较小）
        recoilPitchMin = 0.15,   -- 镜头向上偏移最小值（度）
        recoilPitchMax = 0.3,    -- 镜头向上偏移最大值（度）
        recoilYawMin = -0.1,     -- 镜头水平偏移最小值（度）
        recoilYawMax = 0.1,      -- 镜头水平偏移最大值（度）
        crosshairSpreadMax = 100, -- 准心最大扩散（像素）- 大散布
        crosshairSpreadPerShot = 8, -- 每次射击准心扩散
        crosshairRecoverySpeed = 40, -- 准心恢复速度（像素/秒）
        cameraShakeIntensity = 0.006,
        cameraShakeDuration = 0.03,
        
        -- 模型参数（AK47 特征：弯曲弹匣、木质枪托和护木、丰富的结构细节）
        model = {
            bodyWidth = 0.05,     -- 枪身宽度
            bodyHeight = 0.07,    -- 枪身高度
            bodyLength = 0.38,    -- 枪身长度（更长）
            barrelRadius = 0.012, -- 枪管半径
            barrelLength = 0.22,  -- 枪管长度
            gripWidth = 0.028,    -- 握把宽度
            gripHeight = 0.10,    -- 握把高度
            hasStock = true,      -- 有枪托
            stockLength = 0.18,   -- 枪托长度
            hasMagazine = true,   -- 有弹匣
            magWidth = 0.028,     -- 弹匣宽度
            magHeight = 0.10,     -- 弹匣高度（AK47弹匣更长）
            hasTexture = false,   -- 不使用贴图，使用纯几何细节
            isAK47 = true,        -- AK47特殊标记，用于构建细节模型
            -- AK47特有结构参数
            hasGasBlock = true,   -- 导气管座
            gasBlockPos = 0.65,   -- 导气管座位置（相对于枪管长度）
            gasBlockHeight = 0.025, -- 导气管座高度
            hasHandguard = true,  -- 护木
            handguardLength = 0.18, -- 护木长度
            hasMuzzleBrake = true, -- 枪口制退器
            muzzleBrakeLength = 0.04, -- 制退器长度
            hasReceiverCover = true, -- 机匣盖
            receiverCoverLength = 0.20, -- 机匣盖长度
            hasFrontSight = true, -- 准星
            frontSightHeight = 0.035, -- 准星高度
            hasRearSight = true,  -- 照门
            rearSightHeight = 0.025, -- 照门高度
            rearSightPos = 0.15,  -- 照门位置（距枪身后端）
            -- 扳机和扳机护圈
            hasTrigger = true,
            triggerColor = Color(0.12, 0.12, 0.12, 1.0),
            -- 抛壳口
            hasEjectionPort = true,
            -- 枪托细节
            hasStockDetails = true,
            -- 弹匣弧度（AK47特有）
            hasCurvedMag = true,
            -- 背带环
            hasSlingMount = true,
            -- 颜色配置（丰富的多色系）
            color = Color(0.10, 0.08, 0.06, 1.0),  -- 枪身颜色（深棕黑）
            accentColor = Color(0.52, 0.32, 0.16, 1.0), -- 木纹棕色（护木、枪托）- 更温暖
            metalColor = Color(0.06, 0.06, 0.07, 1.0), -- 金属深黑
            brassColor = Color(0.72, 0.45, 0.20, 1.0), -- 黄铜色（子弹、部分金属件）
            darkWoodColor = Color(0.35, 0.20, 0.10, 1.0), -- 深木色（握把）
            steelColor = Color(0.18, 0.18, 0.20, 1.0), -- 钢色（枪管、机匣）
            rubberColor = Color(0.08, 0.08, 0.08, 1.0), -- 橡胶黑（枪托垫）
            -- 抛壳口配置
            ejectionPortOffset = Vector3(0.04, 0.05, 0.22),
        },
    },
    
    -- ========================================================================
    -- Prefab 武器（使用3D模型）
    -- ========================================================================
    
    -- G17 手枪（Glock 17）
    g17 = {
        name = "G17",
        nameZh = "G17手枪",
        
        magSize = 17,            -- 弹匣容量
        reserveAmmo = 68,        -- 备用弹药
        reloadTime = 1.2,        -- 换弹时间（秒）
        
        fireRate = 0.15,         -- 射击间隔（秒）
        automatic = false,       -- 半自动
        bulletsPerShot = 1,
        spreadAngle = 0.5,
        
        bulletSpeed = 360.0,     -- 翻倍: 180 -> 360
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 28,
        
        recoilPitchMin = 0.6,
        recoilPitchMax = 1.0,
        recoilYawMin = -0.15,
        recoilYawMax = 0.15,
        crosshairSpreadMax = 55,
        crosshairSpreadPerShot = 20,
        crosshairRecoverySpeed = 90,
        cameraShakeIntensity = 0.008,
        cameraShakeDuration = 0.05,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://BDdeKZPkArL7L2_1HP4Ua_0Z",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, 0, 0.25),
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.3),
            ejectionPortOffset = Vector3(0.03, 0.05, -0.08),
            ejectionFlipX = true,
        },
    },
    
    -- AK74 突击步枪
    ak74 = {
        name = "AK74",
        nameZh = "AK74",
        
        magSize = 30,
        reserveAmmo = 120,
        reloadTime = 2.0,
        
        fireRate = 0.1,
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 1.2,
        
        bulletSpeed = 400.0,     -- 翻倍: 200 -> 400
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 32,
        
        recoilPitchMin = 0.4,
        recoilPitchMax = 0.8,
        recoilYawMin = -0.25,
        recoilYawMax = 0.25,
        crosshairSpreadMax = 65,
        crosshairSpreadPerShot = 12,
        crosshairRecoverySpeed = 70,
        cameraShakeIntensity = 0.01,
        cameraShakeDuration = 0.05,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://EmgN-bDI-KjXtWAc9BDeu9Tt",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, -0.02, 0.2),  -- 向下移动0.02
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.5),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.15),
            ejectionFlipX = true,
        },
    },
    
    -- M4 突击步枪
    m4 = {
        name = "M4",
        nameZh = "M4卡宾枪",
        
        magSize = 30,
        reserveAmmo = 120,
        reloadTime = 1.8,
        
        fireRate = 0.08,
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 0.8,
        
        bulletSpeed = 440.0,     -- 翻倍: 220 -> 440
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 28,
        
        recoilPitchMin = 0.3,
        recoilPitchMax = 0.6,
        recoilYawMin = -0.2,
        recoilYawMax = 0.2,
        crosshairSpreadMax = 55,
        crosshairSpreadPerShot = 10,
        crosshairRecoverySpeed = 40,  -- 降低：75 -> 40，让散布积累更明显
        cameraShakeIntensity = 0.008,
        cameraShakeDuration = 0.04,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://FNY8mT7gkY7SeMroH_XZdRCL",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, -0.102, 0.2),  -- 向下移动0.102
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.5),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.15),
            ejectionFlipX = true,
        },
    },
    
    -- MP5 冲锋枪
    mp5 = {
        name = "MP5",
        nameZh = "MP5冲锋枪",
        
        magSize = 30,
        reserveAmmo = 150,
        reloadTime = 1.5,
        
        fireRate = 0.06,         -- 高射速
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 1.5,
        
        bulletSpeed = 320.0,     -- 翻倍: 160 -> 320
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 22,
        
        recoilPitchMin = 0.2,
        recoilPitchMax = 0.4,
        recoilYawMin = -0.15,
        recoilYawMax = 0.15,
        crosshairSpreadMax = 60,
        crosshairSpreadPerShot = 8,
        crosshairRecoverySpeed = 45,  -- 降低：85 -> 45，让散布积累更明显
        cameraShakeIntensity = 0.006,
        cameraShakeDuration = 0.03,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://Bs3mEfXc81rueELfuWV-jt5R",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, -0.05, 0.2),  -- 向下移动0.05
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.4),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.12),
            ejectionFlipX = true,
        },
    },
    
    -- SKS 半自动步枪
    sks = {
        name = "SKS",
        nameZh = "SKS狙击枪",
        
        magSize = 10,
        reserveAmmo = 60,
        reloadTime = 2.2,
        
        fireRate = 0.25,
        automatic = false,       -- 半自动
        bulletsPerShot = 1,
        spreadAngle = 0.3,
        zeroSpreadInterval = 4,  -- 每隔N枪下一枪散布为0（第1、5、9…枪零散布）
        
        bulletSpeed = 500.0,     -- 翻倍: 250 -> 500
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 55,             -- 高伤害
        
        recoilPitchMin = 1.0,
        recoilPitchMax = 1.5,
        recoilYawMin = -0.3,
        recoilYawMax = 0.3,
        crosshairSpreadMax = 20,       -- 最大散布1度 (20 * 0.05 = 1.0°)
        crosshairSpreadPerShot = 10,   -- 等比下调，2枪达到上限
        crosshairRecoverySpeed = 60,
        cameraShakeIntensity = 0.015,
        cameraShakeDuration = 0.08,
        
        -- 狙击镜配置
        hasScope = true,              -- 有瞄准镜
        scopeFov = 15,                -- 瞄准镜FOV
        hideModelOnAds = true,        -- 瞄准时隐藏枪械模型
        scopeTransitionTime = 0.1,    -- 瞄准镜过渡时间
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://AHWkKYqnA_HJHZ-c9TxNGFOK",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, -0.02, 0.2),  -- 向下移动0.02
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.55),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.18),
            ejectionFlipX = true,
        },
    },
    
    -- 短管霰弹枪
    sawed = {
        name = "Sawed-Off",
        nameZh = "短管霰弹枪",
        
        magSize = 2,             -- 双管
        reserveAmmo = 20,
        reloadTime = 1.8,
        
        fireRate = 0.5,
        automatic = false,
        bulletsPerShot = 12,     -- 霰弹
        spreadAngle = 8.0,       -- 大散布
        
        bulletSpeed = 280.0,     -- 翻倍: 140 -> 280
        bulletRadius = 0.01,     -- 降低碰撞检测
        damage = 18,             -- 每颗弹丸伤害
        
        headshotMaxRange = 4.0,
        falloffStartRange = 2.0,
        falloffEndRange = 10.0,
        minDamagePercent = 0.15,
        
        recoilPitchMin = 3.0,
        recoilPitchMax = 4.5,
        recoilYawMin = -1.0,
        recoilYawMax = 1.0,
        crosshairSpreadMax = 100,
        crosshairSpreadPerShot = 50,
        crosshairRecoverySpeed = 25,
        cameraShakeIntensity = 0.03,
        cameraShakeDuration = 0.15,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://DP5EqaxT1lC1c22CnsqhfwBK",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(0, 0, 0.2),
            rotationOffset = Quaternion(180, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.35),
            ejectionPortOffset = Vector3(0.04, 0.04, -0.1),
            ejectionFlipX = true,
            casingScale = 1.5,
        },
    },
}

-- 弹壳配置（全局）
M.CASING_CONFIG = {
    lifetime = 1.0,           -- 弹壳存活时间（秒）
    ejectionSpeed = 1.5,      -- 抛出速度（米/秒）- 降低
    ejectionAngleUp = 45,     -- 向上抛出角度（度）
    ejectionAngleRight = 30,  -- 向右抛出角度（度）
    spinSpeed = 720,          -- 旋转速度（度/秒）
    gravity = -15.0,          -- 弹壳重力
    baseRadius = 0.008,       -- 弹壳基础半径（米）- 增大
    baseLength = 0.025,       -- 弹壳基础长度（米）- 增大
    brassColor = Color(0.65, 0.45, 0.15, 1.0),  -- 深黄铜色
}

-- 武器顺序（用于切换）
-- 1-2号位: 新prefab武器（原5-6号移到前面）
-- 不重复：使用6种不同类型的武器
M.WEAPON_ORDER = { "g17", "ak74", "m4", "mp5", "sks", "sawed" }

return M
