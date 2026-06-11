-- ============================================================================
-- game_state.lua — 游戏共享状态中心
-- 所有模块通过 GS.xxx 读写共享状态
-- ============================================================================

local CONFIG = require "config"

local GS = {}

-- 游戏阶段常量
GS.MENU     = "menu"
GS.PLAYING  = "playing"
GS.DEBUG    = "debug"
GS.ARMORY   = "armory"
GS.current  = GS.MENU

-- ============================================================================
-- 常量（从配置文件读取，ApplyVariantStats 可能覆盖）
-- ============================================================================
GS.MAX_ENERGY           = CONFIG.MaxEnergy
GS.JUMP_COST            = CONFIG.JumpCost
GS.BOOST_COST_PER_SEC   = CONFIG.BoostCostPerSec
GS.ENERGY_REGEN_PER_SEC = CONFIG.EnergyRegenPerSec
GS.BOOST_DELAY          = CONFIG.BoostDelay
GS.BOOST_FORCE          = CONFIG.BoostForce
GS.GRAVITY              = CONFIG.Gravity
GS.MOVE_FORCE_FORWARD   = CONFIG.MoveForceForward
GS.MOVE_FORCE_LATERAL   = CONFIG.MoveForceLateral
GS.AIR_MOVE_FORCE       = CONFIG.AirMoveForce
GS.MAX_SPEED_FORWARD    = CONFIG.MaxSpeedForward
GS.MAX_SPEED_LATERAL    = CONFIG.MaxSpeedLateral
GS.GROUND_DAMPING       = CONFIG.GroundDamping
GS.AIR_DAMPING          = CONFIG.AirDamping
GS.DASH_IMPULSE         = CONFIG.DashImpulse
GS.DASH_DURATION         = CONFIG.DashDuration
GS.DASH_COOLDOWN        = CONFIG.DashCooldown
GS.DASH_ENERGY_COST     = CONFIG.DashEnergyCost
GS.JET_ACTIVATION_COST  = CONFIG.JetActivationCost
GS.JET_COST_PER_SEC     = CONFIG.JetCostPerSec
GS.JET_FORCE            = CONFIG.JetForce
GS.JET_MAX_SPEED        = CONFIG.JetMaxSpeed
GS.JET_DAMPING          = CONFIG.JetDamping
GS.JET_DASH_IMPULSE     = CONFIG.JetDashImpulse
GS.JET_DASH_DURATION    = CONFIG.JetDashDuration
GS.JET_DASH_COOLDOWN    = CONFIG.JetDashCooldown

-- 锁定系统常量
GS.LOCK_GAIN_RATE  = 50
GS.LOCK_DECAY_RATE = 200
GS.LOCK_MAX        = 100

-- ============================================================================
-- 核心引用
-- ============================================================================
---@type Scene
GS.scene       = nil
---@type ThirdPersonCameraInstance
GS.tpCamera    = nil
---@type CharacterComponent
GS.character   = nil
---@type Node
GS.mechNode    = nil
---@type KinematicCharacterController
GS.kcc         = nil

-- 机甲动画
GS.mechAnimator = nil
GS.mechJoints   = nil

-- 当前关卡配置
GS.currentLevel = nil

-- ============================================================================
-- 敌人系统
-- ============================================================================
GS.enemies         = {}
GS.respawnQueue    = {}
GS.enemyCounter    = 0
GS.RESPAWN_DELAY   = 5.0
GS.spawnPoints = {
    -- 近距离
    { pos = Vector3(15, 0, 15),   yaw = -135 },
    { pos = Vector3(-12, 0, 20),  yaw = -45 },
    { pos = Vector3(20, 0, -10),  yaw = 160 },
    { pos = Vector3(-18, 0, -15), yaw = 60 },
    { pos = Vector3(0, 0, 25),    yaw = 180 },
    { pos = Vector3(-8, 0, -30),  yaw = 30 },
    { pos = Vector3(25, 0, 5),    yaw = -90 },
    -- 中距离
    { pos = Vector3(80, 0, 70),   yaw = -135 },
    { pos = Vector3(-70, 0, 90),  yaw = -30 },
    { pos = Vector3(90, 0, -60),  yaw = 150 },
    { pos = Vector3(-85, 0, -70), yaw = 45 },
    { pos = Vector3(50, 0, 100),  yaw = -160 },
    -- 远距离
    { pos = Vector3(160, 0, 130), yaw = -120 },
    { pos = Vector3(-150, 0, 170),yaw = -60 },
    { pos = Vector3(200, 0, -120),yaw = 140 },
    { pos = Vector3(-180, 0, -160),yaw = 50 },
    { pos = Vector3(0, 0, 200),   yaw = 180 },
    { pos = Vector3(250, 0, 300), yaw = -90 },
    { pos = Vector3(-300, 0, 200),yaw = 0 },
}

-- HUD 缓动
GS.ammoHudCx = nil
GS.ammoHudCy = nil
GS.lastDt    = 0.016

-- NanoVG
GS.vg = nil

-- ============================================================================
-- 能量系统
-- ============================================================================
GS.energy        = GS.MAX_ENERGY
GS.jumpStartTime = 0
GS.isBoosting    = false
GS.didJump       = false

-- 水平速度
GS.mechHVel = Vector3.ZERO

-- ============================================================================
-- 冲刺系统
-- ============================================================================
GS.isDashing       = false
GS.dashTimer       = 0
GS.dashDir         = Vector3.ZERO
GS.lastDashTime    = -999
GS.shiftWasDown    = false
GS.dashTrailNodeL  = nil
GS.dashTrailNodeR  = nil
GS.dashBurstNode   = nil
GS.dashBurstAge    = 0
GS.dashTrailCleanup = nil

-- ============================================================================
-- 喷射系统
-- ============================================================================
GS.JET_COOLDOWN       = 30.0
GS.jetCooldownTimer   = 0
GS.jetTrailNodeL      = nil
GS.jetTrailNodeR      = nil
GS.isJetting          = false
GS.cWasDown           = false
GS.jetVel             = Vector3.ZERO
GS.jetPos             = Vector3.ZERO
GS.savedFallSpeed     = 55.0
GS.jetDashLastTime    = -999
GS.isJetDashing       = false
GS.jetDashTimer       = 0
GS.jetDashDir         = Vector3.ZERO
GS.aWasDown           = false
GS.dWasDown           = false
GS.stepSoundTimer     = 0
GS.STEP_INTERVAL      = 0.4
GS.jetEntryTime       = 0
GS.jetFlightYaw       = 0
GS.jetFlightPitch     = 0
GS.JET_FREE_TURN_TIME = 0.2
GS.JET_TURN_RATE      = 30.0

-- 能量恢复抑制
GS.energyRegenBlockTimer = 0

-- ============================================================================
-- 武器系统
-- ============================================================================
GS.playerWeapons = nil
GS.eWasDown      = false
GS.rWasDown      = false

-- 电磁炮蓄力（右肩）
GS.railgunCharging    = false
GS.railgunChargeTimer = 0
GS.railgunChargeTime  = 1.5

-- 电磁炮视觉特效
GS.railgunFX       = nil
GS.railgunFXL      = nil
GS.railgunFireFX   = {}
GS.railgunHitFX    = {}

-- 飞弹锁定（右肩）
GS.missileLockR        = false
GS.missileLockTargetsR = {}
GS.missileLockMaxR     = 3
GS.missileFireQueueR   = {}
GS.missileFireTimerR   = 0

-- 飞弹锁定（左肩）
GS.qWasDown            = false
GS.missileLockL        = false
GS.missileLockTargetsL = {}
GS.missileLockMaxL     = 3
GS.missileFireQueueL   = {}
GS.missileFireTimerL   = 0

-- 左肩电磁炮
GS.railgunChargingL    = false
GS.railgunChargeTimerL = 0
GS.railgunChargeTimeL  = 1.5

-- ============================================================================
-- UI 按钮引用
-- ============================================================================
GS.btnSL           = nil
GS.btnSR           = nil
GS.btnL            = nil
GS.btnR            = nil
GS.btnC            = nil
GS.btnSH           = nil
GS.btnSP           = nil
GS.btnLockOn       = nil
GS.btnSwitchTarget = nil

-- ============================================================================
-- 镜头锁定
-- ============================================================================
GS.cameraLockOn        = false
GS.cameraLockTarget    = nil
GS.lockOnBtnWasPressed = false
GS.switchBtnWasPressed = false

-- ============================================================================
-- 玩家
-- ============================================================================
GS.playerHp    = 3000
GS.playerMaxHp = 3000
GS.playerDead  = false

-- ============================================================================
-- 精英敌人
-- ============================================================================
GS.elite              = nil
GS.eliteRespawnTimer  = -1

-- 近战敌人
GS.meleeEnemies       = {}
GS.meleeRespawnQueue  = {}

-- 叛军系统
GS.rebellionState     = nil

-- ============================================================================
-- 场地屏障
-- ============================================================================
GS.barriers           = {}
GS.BARRIER_FADE_DIST  = 50
GS.BARRIER_SKY_HEIGHT = 300

-- ============================================================================
-- 弹窗
-- ============================================================================
GS.deathDialog  = nil
GS.exitDialog   = nil
GS.exitBtnRect  = { x = 0, y = 0, w = 0, h = 0 }

-- ============================================================================
-- ApplyVariantStats — 根据选中机体型号重算常量
-- ============================================================================
function GS.ApplyVariantStats()
    local v = CONFIG.MechVariants[CONFIG.SelectedVariant or "A"] or {}
    local function mul(key) return v[key] or 1.0 end

    GS.playerMaxHp         = math.floor(3000 * mul("hp"))
    GS.playerHp            = GS.playerMaxHp
    GS.MAX_ENERGY          = math.floor(CONFIG.MaxEnergy * mul("maxEnergy"))
    GS.ENERGY_REGEN_PER_SEC = CONFIG.EnergyRegenPerSec * mul("energyRegen")
    GS.MOVE_FORCE_FORWARD  = CONFIG.MoveForceForward * mul("moveForce")
    GS.MOVE_FORCE_LATERAL  = CONFIG.MoveForceLateral * mul("moveForce")
    GS.AIR_MOVE_FORCE      = CONFIG.AirMoveForce * mul("moveForce")
    GS.MAX_SPEED_FORWARD   = CONFIG.MaxSpeedForward * mul("maxSpeed")
    GS.MAX_SPEED_LATERAL   = CONFIG.MaxSpeedLateral * mul("maxSpeed")
    CONFIG._JumpSpeedMul   = mul("jumpSpeed")
    GS.BOOST_COST_PER_SEC  = CONFIG.BoostCostPerSec * mul("boostCost")
    GS.BOOST_FORCE         = Vector3(0, CONFIG.BoostForce.y * mul("boostForce"), 0)
    GS.DASH_IMPULSE        = CONFIG.DashImpulse * mul("dashImpulse")
    GS.DASH_DURATION       = CONFIG.DashDuration * mul("dashDuration")
    GS.DASH_ENERGY_COST    = CONFIG.DashEnergyCost * mul("dashEnergyCost")
    GS.JET_ACTIVATION_COST = CONFIG.JetActivationCost * mul("jetCost")
    GS.JET_COST_PER_SEC    = CONFIG.JetCostPerSec * mul("jetCost")
    GS.JET_FORCE           = CONFIG.JetForce * mul("jetForce")
    GS.JET_MAX_SPEED       = CONFIG.JetMaxSpeed * mul("jetMaxSpeed")
    GS.JET_DASH_IMPULSE    = CONFIG.JetDashImpulse * mul("jetDashImpulse")
    GS.energy              = GS.MAX_ENERGY

    print(string.format("[MechVariant] Applied variant %s: HP=%d Energy=%d MoveF=%.0f MaxSpd=%.1f DashI=%.0f JetF=%.0f",
        CONFIG.SelectedVariant, GS.playerMaxHp, GS.MAX_ENERGY,
        GS.MOVE_FORCE_FORWARD, GS.MAX_SPEED_FORWARD, GS.DASH_IMPULSE, GS.JET_FORCE))
end

-- ============================================================================
-- Reset — 重置所有游戏状态到初始值
-- ============================================================================
function GS.Reset()
    GS.mechNode    = nil
    GS.kcc         = nil
    GS.character   = nil
    GS.tpCamera    = nil
    GS.mechAnimator = nil
    GS.mechJoints  = nil
    GS.enemies     = {}
    GS.respawnQueue = {}
    GS.meleeEnemies = {}
    GS.meleeRespawnQueue = {}
    GS.barriers    = {}
    GS.elite       = nil
    GS.eliteRespawnTimer = -1
    GS.rebellionState = nil
    GS.playerDead  = false
    GS.playerHp    = GS.playerMaxHp
    GS.energy      = GS.MAX_ENERGY
    GS.energyRegenBlockTimer = 0
    GS.isJetting   = false
    GS.isDashing   = false
    GS.isBoosting  = false
    GS.cameraLockOn = false
    GS.cameraLockTarget = nil
    GS.jetCooldownTimer = 0
    GS.mechHVel    = Vector3.ZERO
    GS.jetVel      = Vector3.ZERO
    GS.missileFireQueueR   = {}
    GS.missileLockR        = false
    GS.missileLockTargetsR = {}
    GS.missileFireQueueL   = {}
    GS.missileLockL        = false
    GS.missileLockTargetsL = {}
    GS.railgunCharging     = false
    GS.railgunChargeTimer  = 0
    GS.railgunChargingL    = false
    GS.railgunChargeTimerL = 0
    GS.playerWeapons = nil
    GS.vg           = nil
    GS.ammoHudCx    = nil
    GS.ammoHudCy    = nil
    GS.deathDialog  = nil
    GS.exitDialog   = nil

    -- 按钮引用
    GS.btnSL = nil
    GS.btnSR = nil
    GS.btnL  = nil
    GS.btnR  = nil
    GS.btnC  = nil
    GS.btnSH = nil
    GS.btnSP = nil
    GS.btnLockOn = nil
    GS.btnSwitchTarget = nil
end

return GS
