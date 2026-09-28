-- ============================================================================
-- GameState.lua - 游戏全局状态管理
-- ============================================================================

local M = {}

-- ============================================================================
-- 碰撞层定义（用于物理碰撞检测）
-- ============================================================================
M.COLLISION_LAYER = {
    ENVIRONMENT = 1,    -- 环境（地面、墙壁、障碍物）
    MONSTER = 2,        -- 怪物身体
    MONSTER_HEAD = 4,   -- 怪物头部（用于爆头检测）
    BULLET = 8,         -- 子弹
    PLAYER = 16,        -- 玩家
    GRENADE = 32,       -- 手榴弹
    TARGET = 64,        -- 靶子
}

-- 碰撞掩码（定义每种物体与哪些层碰撞）
-- 注意：碰撞检测需要双方的 layer 都在对方的 mask 中
M.COLLISION_MASK = {
    -- 子弹与环境、怪物身体、怪物头部、靶子碰撞
    BULLET = 1 + 2 + 4 + 64,  -- ENVIRONMENT + MONSTER + MONSTER_HEAD + TARGET
    -- 怪物与环境、玩家、其他怪物、子弹碰撞
    MONSTER = 1 + 2 + 8 + 16,  -- ENVIRONMENT + MONSTER + BULLET + PLAYER
    -- 怪物头部与子弹碰撞
    MONSTER_HEAD = 8,  -- BULLET
    -- 玩家与环境、怪物碰撞
    PLAYER = 1 + 2,  -- ENVIRONMENT + MONSTER
    -- 靶子与子弹碰撞
    TARGET = 8,  -- BULLET
}

-- 引擎全局引用
---@type Scene
M.scene = nil
---@type PhysicsWorld
M.physicsWorld = nil      -- 物理世界
---@type Node
M.cameraNode = nil
---@type Camera
M.camera = nil
---@type ColorGrading
M.colorGrading = nil       -- 颜色分级组件（用于子弹时间对比度调整）
---@type Node
M.playerNode = nil
---@type Node
M.gunNode = nil           -- 枪模型节点
---@type Node
M.muzzleNode = nil        -- 枪口节点（子弹发射点）

-- NanoVG 上下文
M.nvg = nil
M.nvgFont = -1

-- 游戏阶段
M.GAME_PHASE = {
    MENU = 1,       -- 主菜单
    PLAYING = 2,    -- 游戏中
    GAME_OVER = 3,  -- 游戏结束
}
M.gamePhase = 1     -- 当前游戏阶段（默认主菜单）

-- 游戏计时
M.gameDuration = 60.0    -- 游戏时长（秒）
M.gameTimer = 0          -- 游戏计时器
M.gameStartTime = 0      -- 游戏开始时间

-- 游戏统计
M.shotsHit = 0           -- 命中次数（用于计算命中率）

-- 游戏状态
M.yaw = 0              -- 水平旋转角度
M.pitch = 0            -- 垂直旋转角度
M.score = 0            -- 分数
M.targetsHit = 0       -- 击中靶子数
M.totalShots = 0       -- 总射击次数
M.fireCooldown = 0     -- 射击冷却计时

-- 武器状态
M.currentWeaponId = "pistol"  -- 当前武器ID
M.currentWeapon = nil         -- 当前武器配置引用
M.currentAmmo = 0             -- 当前弹匣剩余弹药
M.reserveAmmo = 0             -- 备用弹药
M.isReloading = false         -- 是否正在换弹
M.reloadTimer = 0             -- 换弹计时器
M.isLeftHanded = false        -- 是否左手持枪（false=右手，true=左手）

-- 玩家物理状态
M.playerVelocityY = 0  -- 玩家垂直速度
M.isGrounded = true    -- 是否在地面上
M.isPlayerMoving = false  -- 玩家是否在移动（用于准心恢复加速）
M.isRunning = false       -- 玩家是否在跑步（Shift键）

-- 玩家生命状态
M.playerHealth = 100       -- 当前生命值
M.isDead = false           -- 是否死亡
M.lastDamageTime = 0       -- 上次受伤时间（用于回血延迟）
M.deathTime = 0            -- 死亡时间（用于重生倒计时）
M.damageFlashAlpha = 0     -- 受伤红色滤镜透明度 (0-1)

-- 枪械动画
M.gunRecoilTime = 0    -- 后坐力动画时间
M.gunBasePos = nil     -- 枪的基础位置（腰射位置）
M.gunAdsPos = nil      -- 枪的瞄准位置（ADS位置）

-- 瞄准状态 (ADS - Aim Down Sights)
M.isAiming = false           -- 是否正在瞄准
M.aimTransition = 0          -- 瞄准过渡进度 (0=腰射, 1=瞄准)
M.aimTransitionSpeed = 8.0   -- 瞄准过渡速度

-- 左右手切换动画
M.handSwitchTransition = 0   -- 切换过渡进度 (0=完成, 1=切换中)
M.handSwitchFromLeft = false -- 切换前是否左手
M.handSwitchToLeft = false   -- 切换后是否左手
M.handSwitchSpeed = 6.0      -- 切换过渡速度

-- 武器切换动画
M.weaponSwitchProgress = 0       -- 切换进度 (0=未切换, 0-0.5=收起, 0.5-1=拿出)
M.weaponSwitchPendingId = nil    -- 待切换的武器ID
M.isSwitchingWeapon = false      -- 是否正在切换武器

-- 后坐力系统
M.recoilPitch = 0      -- 当前后坐力导致的 pitch 偏移（度）
M.recoilYaw = 0        -- 当前后坐力导致的 yaw 偏移（度）
M.crosshairSpread = 0  -- 当前准心扩散值（像素）
M.burstShotCount = 0   -- 连续射击计数（准心归零时重置，用于零散布间隔判定）
M.cameraShakeTime = 0  -- 镜头抖动剩余时间
M.cameraShakeOffset = Vector3.ZERO  -- 镜头抖动偏移

-- 脉冲式后坐力系统（上跳→停留→恢复）
M.recoilPhase = "idle"      -- 当前阶段: "idle", "kick", "hold", "recover"
M.recoilProgress = 0        -- 当前阶段进度 (0-1)
M.recoilKickDuration = 0.08 -- 上跳阶段持续时间（快速上跳）
M.recoilHoldTimer = 0       -- 停留阶段计时器
M.recoilHoldDuration = 0.15 -- 停留时间（等待下一发，超时才恢复）
M.recoilRecoverDuration = 0.35 -- 恢复阶段持续时间（慢慢恢复）
-- 后坐力动画关键帧
M.recoilStartPitch = 0      -- 起始 pitch
M.recoilStartYaw = 0        -- 起始 yaw
M.recoilPeakPitch = 0       -- 峰值 pitch (上跳最高点)
M.recoilPeakYaw = 0         -- 峰值 yaw
M.recoilEndPitch = 0        -- 结束 pitch (恢复后，有随机偏移)
M.recoilEndYaw = 0          -- 结束 yaw
-- 兼容旧系统（准星扩散仍使用）
M.pendingRecoilPitch = 0    -- 已废弃，保留兼容
M.pendingRecoilYaw = 0      -- 已废弃，保留兼容
M.basePitch = 0             -- 已废弃，保留兼容

-- 子弹管理
M.bullets = {}
M.bulletDataMap = {}  -- 子弹节点 -> 子弹数据映射（用于碰撞回调）

-- 弹壳管理
M.casings = {}  -- 弹壳列表 { node, velocity, lifetime, spin }

-- 特效管理
M.effects = {}         -- 击中特效列表

-- 手榴弹管理
M.grenades = {}        -- 手榴弹列表 { node, velocity, fuseTime, exploded }
M.grenadeCount = 5     -- 当前手榴弹数量
M.grenadeCooldown = 0  -- 投掷冷却计时器

-- 靶子管理
M.targets = {}
M.targetNodeMap = {}  -- 靶子节点 -> 靶子数据映射（用于碰撞回调）

-- 怪物管理
M.monsters = {}  -- { node, health, attackCooldown, alive, isStatic }
M.monsterNodeMap = {}  -- 怪物节点 -> 怪物数据映射（用于碰撞回调）
M.dynamicMonsterEnabled = false   -- 动态敌人开关（默认关闭）
M.staticMonsterEnabled = true     -- 静态敌人开关（默认开启）
M.showMonsterColliders = false    -- 显示怪物碰撞体（调试用）

-- 碰撞体管理（墙壁和柱子）
M.colliders = {}  -- AABB 碰撞体列表 { min, max, type }

-- 辅助准心（枪口实际击中点）
M.gunAimPoint = nil        -- 枪口射线实际击中点（3D世界坐标）
M.gunAimScreenPos = nil    -- 枪口击中点的屏幕坐标
M.gunAimVisible = true     -- 是否显示辅助准心

-- 调试渲染
M.debugRenderer = nil      -- 调试渲染器
M.debugGunRayStart = nil   -- 调试用：枪口射线起点
M.debugGunRayEnd = nil     -- 调试用：枪口射线终点（预计碰撞点）

-- 屏幕尺寸
M.screenWidth = 0
M.screenHeight = 0

-- 音效系统
M.bgmHandle = nil          -- 背景音乐句柄
M.soundEnabled = true      -- 音效开关

-- 游戏速度（子弹时间等功能通过修改此变量实现减速）
M.gameSpeed = 1.0          -- 1.0 = 正常速度，0.1 = 10倍减速

-- 子弹时间系统
M.bulletTimeActive = false     -- 是否激活子弹时间
M.bulletTimeTimer = 0          -- 子弹时间计时器（真实时间）
M.bulletTimeDuration = 8.0     -- 子弹时间总持续时间（秒）
M.bulletTimeEaseIn = 0.2       -- 缓入时间（秒）
M.bulletTimeEaseOut = 0.2      -- 缓出时间（秒）
M.bulletTimeScale = 0.1        -- 子弹时间内的时间缩放（1/10 速度）
M.bulletTimeCooldown = 0       -- 子弹时间冷却计时器
M.bulletTimeCooldownMax = 15.0 -- 子弹时间冷却总时长（秒）
M.bulletTimeFovMultiplier = 1.0 -- 子弹时间 FOV 缩放系数（0=正常，1=子弹时间FOV）

--- 重置所有状态
function M.Reset()
    M.yaw = 0
    M.pitch = 0
    M.score = 0
    M.targetsHit = 0
    M.totalShots = 0
    M.shotsHit = 0
    M.fireCooldown = 0
    M.gameTimer = 0
    M.gameStartTime = 0
    
    M.playerVelocityY = 0
    M.isGrounded = true
    M.isPlayerMoving = false
    
    M.playerHealth = 100
    M.isDead = false
    M.lastDamageTime = 0
    M.deathTime = 0
    M.damageFlashAlpha = 0
    
    M.gunRecoilTime = 0
    M.recoilPitch = 0
    M.recoilYaw = 0
    M.crosshairSpread = 0
    M.burstShotCount = 0
    M.cameraShakeTime = 0
    M.cameraShakeOffset = Vector3.ZERO
    -- 脉冲式后坐力重置
    M.recoilPhase = "idle"
    M.recoilProgress = 0
    M.recoilHoldTimer = 0
    M.recoilStartPitch = 0
    M.recoilStartYaw = 0
    M.recoilPeakPitch = 0
    M.recoilPeakYaw = 0
    M.recoilEndPitch = 0
    M.recoilEndYaw = 0
    -- 兼容旧系统
    M.pendingRecoilPitch = 0
    M.pendingRecoilYaw = 0
    M.basePitch = 0
    
    M.bullets = {}
    M.bulletDataMap = {}
    M.casings = {}
    M.effects = {}
    M.grenades = {}
    M.grenadeCount = 5
    M.grenadeCooldown = 0
    M.targets = {}
    M.targetNodeMap = {}
    M.monsters = {}
    M.monsterNodeMap = {}
    M.colliders = {}
    
    -- 重置游戏速度和子弹时间
    M.gameSpeed = 1.0
    M.bulletTimeActive = false
    M.bulletTimeTimer = 0
    M.bulletTimeCooldown = 0
end

return M
