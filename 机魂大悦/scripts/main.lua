-- ============================================================================
-- 机魂大悦 - 机甲动作游戏
-- Mech Soul Deluxe - Mech Action Game
--
-- 功能:
--   - 主菜单（测试模式下可进入调试模式查看模型和动画）
--   - 100×100 米方形竞技场地面
--   - 方块拼装的可操控机甲（约 3.5 米高）
--   - 机甲始终面朝相机方向（战斗模式）
--   - 空中可自由操控方向
--   - 能量系统（100点）：跳跃消耗10点
--   - 长按跳跃推进飞行：起跳0.2秒后持续按住跳跃键→向上推进
--   - NanoVG 能量条 HUD
--
-- 操作:
--   WASD: 移动 | 鼠标: 视角 | Space: 跳跃
--   长按 Space: 推进飞行（消耗能量）
-- ============================================================================

require "LuaScripts/Utilities/Sample"
require "LuaScripts/Utilities/Touch"
require "urhox-libs.UI.GameHUD"
require "urhox-libs.Camera.ThirdPersonCamera"

local CONFIG = require "config"
local Weapons = require "weapons"
local WeaponManager = require "weapon_manager"
local ShieldSystem = require "shield_system"
local Menu = require "menu"
local DebugViewer = require "debug_viewer"
local MechBuilder = require "mech_builder"
local MechAnimator = require "mech_animator"
local EliteAI = require "elite_ai"
local RebelAI = require "rebel_ai"
local MeleeAI = require "melee_ai"
local VehicleBuilder = require "vehicle_builder"
local Armory = require "armory_screen"
local SoundManager = require "sound_manager"
local BossAI = require "boss_ai"
local MiniDrone = require "mini_drone"
local DestructibleBuilding = require "destructible_building"

-- 模块化代码
local GS = require "game_state"
local SceneBuilder = require "scene_builder"
local Environment = require "environment"
local EnemySpawner = require "enemy_spawner"
local VFX = require "vfx_dash_jet"
local RailgunFX = require "railgun_fx"
local HUD = require "hud_renderer"

-- 游戏状态
local GAME_STATE_MENU = "menu"
local GAME_STATE_PLAYING = "playing"
local GAME_STATE_DEBUG = "debug"
local GAME_STATE_ARMORY = "armory"
local gameState_ = GAME_STATE_MENU

-- ============================================================================
-- 常量（从配置文件读取）
-- ============================================================================

local MAX_ENERGY = CONFIG.MaxEnergy
local JUMP_COST = CONFIG.JumpCost
local BOOST_COST_PER_SEC = CONFIG.BoostCostPerSec
local ENERGY_REGEN_PER_SEC = CONFIG.EnergyRegenPerSec
local BOOST_DELAY = CONFIG.BoostDelay
local BOOST_FORCE = CONFIG.BoostForce
local GRAVITY = CONFIG.Gravity
local MOVE_FORCE_FORWARD = CONFIG.MoveForceForward
local MOVE_FORCE_LATERAL = CONFIG.MoveForceLateral
local AIR_MOVE_FORCE = CONFIG.AirMoveForce
local MAX_SPEED_FORWARD = CONFIG.MaxSpeedForward
local MAX_SPEED_LATERAL = CONFIG.MaxSpeedLateral
local GROUND_DAMPING = CONFIG.GroundDamping
local AIR_DAMPING = CONFIG.AirDamping
local DASH_IMPULSE = CONFIG.DashImpulse
local DASH_DURATION = CONFIG.DashDuration
local DASH_COOLDOWN = CONFIG.DashCooldown
local DASH_ENERGY_COST = CONFIG.DashEnergyCost
local JET_ACTIVATION_COST = CONFIG.JetActivationCost
local JET_COST_PER_SEC = CONFIG.JetCostPerSec
local JET_FORCE = CONFIG.JetForce
local JET_MAX_SPEED = CONFIG.JetMaxSpeed
local JET_DAMPING = CONFIG.JetDamping
local JET_DASH_IMPULSE = CONFIG.JetDashImpulse
local JET_DASH_DURATION = CONFIG.JetDashDuration
local JET_DASH_COOLDOWN = CONFIG.JetDashCooldown

-- 锁定系统
local LOCK_GAIN_RATE = 50       -- 可见时每秒锁定值增加
local LOCK_DECAY_RATE = 200     -- 不可见时每秒锁定值衰减
local LOCK_MAX = 100            -- 锁定完成阈值

-- ============================================================================
-- 全局变量
-- ============================================================================

---@type Scene
local scene_ = nil
---@type ThirdPersonCameraInstance
local tpCamera_ = nil
---@type CharacterComponent
local character_ = nil
---@type Node
local mechNode_ = nil
---@type KinematicCharacterController
local kcc_ = nil

-- 机甲动画
local mechAnimator_ = nil
local mechJoints_ = nil

-- 敌人列表 { node, animator, joints }
local enemies_ = {}
local respawnQueue_ = {}   -- 待重生队列 { {timer, pos, yaw}, ... }
local enemyCounter_ = 0    -- 敌人编号计数器
local RESPAWN_DELAY = 5.0  -- 死亡后重生延迟（秒）
local spawnPoints_ = {
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
local ammoHudCx_ = nil   -- 弹药UI缓动当前X
local ammoHudCy_ = nil   -- 弹药UI缓动当前Y
local lastDt_ = 0.016    -- 上一帧时间步长（供NanoVG渲染用）

-- NanoVG
local vg_ = nil

-- 能量系统
local energy_ = MAX_ENERGY
local jumpStartTime_ = 0       -- 本次起跳的时间戳
local isBoosting_ = false       -- 是否正在推进
local didJump_ = false          -- 本次腾空是否由跳跃触发（用于推进判定）

-- 水平速度（自追踪，不依赖 KCC 内部状态）
local mechHVel_ = Vector3.ZERO

-- 冲刺系统
local isDashing_ = false
local dashTimer_ = 0
local dashDir_ = Vector3.ZERO
local lastDashTime_ = -999
local shiftWasDown_ = false     -- 上一帧 Shift 状态，用于检测按下瞬间
local dashTrailNodeL_ = nil     -- 冲刺拖尾节点（左肩）
local dashTrailNodeR_ = nil     -- 冲刺拖尾节点（右肩）
local dashBurstNode_ = nil      -- 冲刺起始爆发节点
local dashBurstAge_ = 0         -- 爆发效果计时
local dashTrailCleanup_ = nil   -- 已停止发射的拖尾待清理列表

-- 喷射系统（C键切换，3D 自由飞行）
local JET_COOLDOWN = 30.0       -- 喷射冷却时间（秒）
local jetCooldownTimer_ = 0     -- 喷射冷却倒计时（>0 表示冷却中）
local jetTrailNodeL_ = nil      -- 喷射拖尾节点（左喷口）
local jetTrailNodeR_ = nil      -- 喷射拖尾节点（右喷口）
local isJetting_ = false
local cWasDown_ = false         -- 上一帧 C 键状态
local jetVel_ = Vector3.ZERO    -- 喷射模式下的 3D 速度
local jetPos_ = Vector3.ZERO    -- 喷射模式下独立追踪的位置（不依赖 mechNode_.position）
local savedFallSpeed_ = 55.0    -- 进入喷射前保存的最大下落速度
local jetDashLastTime_ = -999   -- 喷射模式上次突进时间
local isJetDashing_ = false     -- 喷射突进是否进行中
local jetDashTimer_ = 0         -- 喷射突进计时器
local jetDashDir_ = Vector3.ZERO -- 喷射突进方向
local aWasDown_ = false         -- 上一帧 A 键状态
local dWasDown_ = false         -- 上一帧 D 键状态
local stepSoundTimer_ = 0       -- 脚步声计时器
local STEP_INTERVAL = 0.4       -- 脚步声间隔（秒）
local jetEntryTime_ = 0         -- 进入喷射模式的时间
local jetFlightYaw_ = 0         -- 当前飞行偏航角（度）
local jetFlightPitch_ = 0       -- 当前飞行俯仰角（度）
local JET_FREE_TURN_TIME = 0.2  -- 自由转向时间窗口
local JET_TURN_RATE = 30.0      -- 转向速度限制（度/秒）

-- 能量恢复抑制（退出C模式/冲刺后短暂禁止恢复能量）
local energyRegenBlockTimer_ = 0  -- >0 时禁止能量恢复

-- 武器系统
---@type table|nil { handL, handR, shoulderR }
local playerWeapons_ = nil  -- 玩家武器实例表
local eWasDown_ = false
local rWasDown_ = false

-- 电磁炮蓄力系统
local railgunCharging_ = false       -- 是否正在蓄力
local railgunChargeTimer_ = 0        -- 蓄力计时器
local railgunChargeTime_ = 1.5       -- 蓄力所需时间（从 def 读取）

-- 电磁炮视觉特效（右肩/左肩独立）
local railgunFX_ = nil               -- 右肩 { chargeGlow, muzzleGlow, sparks, chargeLight }
local railgunFXL_ = nil              -- 左肩 { chargeGlow, muzzleGlow, sparks, chargeLight }
local railgunFireFX_ = {}            -- 发射后的残留特效（闪光、光柱）
local railgunHitFX_ = {}             -- 电磁炮命中特效（电弧、冲击波）

-- 前置声明（定义在 HandleUpdate 之前，ReturnToMenu 需要引用）

-- 飞弹多目标锁定系统（右肩）
local missileLockR_ = false         -- 右肩是否在锁定中
local missileLockTargetsR_ = {}     -- 右肩锁定目标列表
local missileLockMaxR_ = 3          -- 右肩最大锁定数
local missileFireQueueR_ = {}       -- 右肩发射队列
local missileFireTimerR_ = 0        -- 右肩发射间隔计时器

-- 飞弹多目标锁定系统（左肩）
local qWasDown_ = false
local missileLockL_ = false
local missileLockTargetsL_ = {}
local missileLockMaxL_ = 3
local missileFireQueueL_ = {}
local missileFireTimerL_ = 0

-- 左肩电磁炮蓄力
local railgunChargingL_ = false
local railgunChargeTimerL_ = 0
local railgunChargeTimeL_ = 1.5

-- 右下角功能按钮引用（SL/SR/L/R/C/SH/SP）
local btnSL_ = nil    -- 左肩武器 (Q)
local btnSR_ = nil    -- 右肩武器 (E)
local btnL_ = nil     -- 左手武器 (LMB)
local btnR_ = nil     -- 右手武器 (RMB)
local btnC_ = nil     -- 喷射 (C)
local btnSH_ = nil    -- 冲刺 (Shift)
local btnSP_ = nil    -- 跳跃 (Space)
local btnLockOn_ = nil   -- 镜头锁定按钮
local btnSwitchTarget_ = nil  -- 切换锁定目标按钮

-- 镜头锁定系统
local cameraLockOn_ = false          -- 是否处于镜头锁定模式
local cameraLockTarget_ = nil        -- 当前锁定的敌人对象
local lockOnBtnWasPressed_ = false   -- 锁定按钮上一帧状态
local switchBtnWasPressed_ = false   -- 切换按钮上一帧状态

-- 玩家生命值
local playerHp_ = 3000
local playerMaxHp_ = 3000
local playerDead_ = false
local victoryShown_ = false
local victoryDialog_ = nil

-- 精英敌人
local elite_ = nil           -- 精英敌人数据（EliteAI 模块管理）
local eliteRespawnTimer_ = -1  -- 精英重生计时器（<0 表示不在重生中）

-- 近战敌人系统
local meleeEnemies_ = {}             -- 近战敌人引用列表
local meleeRespawnQueue_ = {}        -- 近战敌人重生队列 { timer, pos, yaw }

-- 叛军系统
local rebellionState_ = nil      -- 叛军波次状态（RebelAI 模块管理）

-- 场地屏障
local barriers_ = {}          -- { node, mat, getDistance(playerPos) }
local prevEnemyCount_ = 0     -- 用于检测 BOSS 生成/击杀小无人机后 enemies_ 列表变动
local BARRIER_FADE_DIST = 50  -- 开始显现的距离（米）
local BARRIER_SKY_HEIGHT = 300 -- 天空屏障高度

-- 死亡弹窗
local deathDialog_ = nil

-- 退出确认弹窗
local exitDialog_ = nil

-- 退出按钮区域（逻辑坐标，用于点击检测）
local exitBtnRect_ = { x = 0, y = 0, w = 0, h = 0 }

-- 死亡效果由 MechBuilder 模块管理（MechBuilder.PlayDeathEffect / UpdateDeathEffects）

-- ============================================================================
-- 前置声明（这些函数在别名定义之前被 ReturnToMenu 引用）
local RailgunFX_StopCharge
local RailgunFX_UpdateFireFX
local RailgunFX_Hit

-- 材质辅助函数
-- ============================================================================

-- 材质工具函数（已移至 scene_builder.lua）
local CreatePBRMat = SceneBuilder.CreatePBRMat
local function CreateBoxPart(parent, name, pos, scale, mat)
    return SceneBuilder.CreateBoxPart(parent, name, pos, scale, mat)
end
local function CreateStaticBox(name, pos, scale, mat)
    return SceneBuilder.CreateStaticBox(scene_, name, pos, scale, mat)
end


-- ============================================================================
-- 生命周期
-- ============================================================================

--- 当前关卡配置
local currentLevel_ = nil

--- 显示主菜单
local function ShowMainMenu()
    gameState_ = GAME_STATE_MENU
    SoundManager.PlayBGM("menu")
    Menu.Show({
        onStartLevel = function(levelIndex)
            currentLevel_ = CONFIG.Levels[levelIndex]
            StartGame()
        end,
        onDebugMode = CONFIG.debugModeEnabled and function()
            EnterDebugMode()
        end or nil,
        onArmory = function()
            gameState_ = GAME_STATE_ARMORY
            Armory.Show(Menu.GetUI(), function()
                ShowMainMenu()
            end)
        end,
    })
end

--- 显示死亡弹窗
--- 显示胜利弹窗
function ShowVictoryDialog()
    local UI = Menu.GetUI()

    victoryShown_ = true

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    victoryDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 120 },
        children = {
            UI.Panel {
                width = 320,
                flexDirection = "column",
                alignItems = "center",
                paddingTop = 32, paddingBottom = 28,
                paddingLeft = 28, paddingRight = 28,
                gap = 16,
                backgroundColor = { 20, 22, 35, 240 },
                borderWidth = 1,
                borderColor = { 40, 200, 120, 180 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "VICTORY",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = { 40, 220, 120, 240 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "敌方机体已被击毁",
                        fontSize = 14,
                        fontColor = { 180, 210, 185, 180 },
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    UI.Button {
                        text = "返回主菜单",
                        variant = "primary",
                        width = 200,
                        height = 44,
                        fontSize = 16,
                        onClick = function(self)
                            SoundManager.PlaySFX("ui_click")
                            ReturnToMenu()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(victoryDialog_)
end

--- 显示死亡弹窗
function ShowDeathDialog()
    local UI = Menu.GetUI()

    -- 释放鼠标
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    deathDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 120 },
        children = {
            UI.Panel {
                width = 320,
                flexDirection = "column",
                alignItems = "center",
                paddingTop = 32, paddingBottom = 28,
                paddingLeft = 28, paddingRight = 28,
                gap = 16,
                backgroundColor = { 20, 22, 35, 240 },
                borderWidth = 1,
                borderColor = { 255, 60, 40, 180 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "DESTROYED",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = { 255, 60, 40, 240 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "机体已被击毁",
                        fontSize = 14,
                        fontColor = { 180, 185, 210, 180 },
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    UI.Button {
                        text = "返回主菜单",
                        variant = "primary",
                        width = 200,
                        height = 44,
                        fontSize = 16,
                        onClick = function(self)
                            SoundManager.PlaySFX("ui_click")
                            ReturnToMenu()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(deathDialog_)
end

--- 显示退出确认弹窗
function ShowExitDialog()
    if exitDialog_ then return end

    local UI = Menu.GetUI()

    -- 释放鼠标
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    exitDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 120 },
        children = {
            UI.Panel {
                width = 300,
                flexDirection = "column",
                alignItems = "center",
                paddingTop = 28, paddingBottom = 24,
                paddingLeft = 24, paddingRight = 24,
                gap = 20,
                backgroundColor = { 20, 22, 35, 240 },
                borderWidth = 1,
                borderColor = { 100, 160, 255, 180 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "确认退出",
                        fontSize = 22,
                        fontWeight = "bold",
                        fontColor = { 220, 225, 240, 240 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "确定要返回主菜单吗？",
                        fontSize = 14,
                        fontColor = { 180, 185, 210, 180 },
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        children = {
                            UI.Button {
                                text = "取消",
                                width = 110,
                                height = 40,
                                fontSize = 15,
                                onClick = function(self)
                                    SoundManager.PlaySFX("ui_click")
                                    CloseExitDialog()
                                end,
                            },
                            UI.Button {
                                text = "确认退出",
                                variant = "primary",
                                width = 110,
                                height = 40,
                                fontSize = 15,
                                onClick = function(self)
                                    SoundManager.PlaySFX("ui_click")
                                    CloseExitDialog()
                                    ReturnToMenu()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    UI.SetRoot(exitDialog_)
end

--- 关闭退出确认弹窗
function CloseExitDialog()
    if exitDialog_ then
        exitDialog_:Destroy()
        exitDialog_ = nil
    end
    -- 恢复鼠标锁定
    if gameState_ == GAME_STATE_PLAYING and not playerDead_ then
        SampleInitMouseMode(MM_RELATIVE)
    end
end

--- 关闭死亡弹窗并返回主菜单
function ReturnToMenu()
    -- 同步状态到 GS（供模块清理使用）
    GS.gameState = GAME_STATE_MENU
    GS.current = GS.MENU
    GS.scene = nil
    GS.mechNode = nil
    GS.enemies = {}
    GS.playerWeapons = nil
    
    -- 清理音频场景引用（在场景销毁前）
    SoundManager.OnSceneDestroy()

    -- 恢复鼠标
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    -- 销毁弹窗
    if deathDialog_ then
        deathDialog_:Destroy()
        deathDialog_ = nil
    end
    if exitDialog_ then
        exitDialog_:Destroy()
        exitDialog_ = nil
    end
    if victoryDialog_ then
        victoryDialog_:Destroy()
        victoryDialog_ = nil
    end
    -- 清理场景
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end
    -- 重置状态
    mechNode_ = nil
    kcc_ = nil
    character_ = nil
    tpCamera_ = nil
    mechAnimator_ = nil
    mechJoints_ = nil
    enemies_ = {}
    respawnQueue_ = {}
    meleeEnemies_ = {}
    meleeRespawnQueue_ = {}
    barriers_ = {}
    elite_ = nil
    eliteRespawnTimer_ = -1
    rebellionState_ = nil
    playerDead_ = false
    victoryShown_ = false
    playerHp_ = playerMaxHp_
    energy_ = MAX_ENERGY
    energyRegenBlockTimer_ = 0
    isJetting_ = false
    isDashing_ = false
    isBoosting_ = false
    cameraLockOn_ = false
    cameraLockTarget_ = nil
    -- 清理冲刺特效
    if dashTrailNodeL_ then dashTrailNodeL_:Remove() dashTrailNodeL_ = nil end
    if dashTrailNodeR_ then dashTrailNodeR_:Remove() dashTrailNodeR_ = nil end
    if dashBurstNode_ then dashBurstNode_:Remove() dashBurstNode_ = nil end
    if dashTrailCleanup_ then
        for _, entry in ipairs(dashTrailCleanup_) do entry.node:Remove() end
        dashTrailCleanup_ = nil
    end
    -- 清理喷射特效和冷却
    if jetTrailNode_ then jetTrailNode_:Remove() jetTrailNode_ = nil end
    if jetGlowNode_ then jetGlowNode_:Remove() jetGlowNode_ = nil end
    jetCooldownTimer_ = 0
    mechHVel_ = Vector3.ZERO
    jetVel_ = Vector3.ZERO
    missileFireQueueR_ = {}
    missileLockR_ = false
    missileLockTargetsR_ = {}
    missileFireQueueL_ = {}
    missileLockL_ = false
    missileLockTargetsL_ = {}
    railgunCharging_ = false
    railgunChargeTimer_ = 0
    railgunChargingL_ = false
    railgunChargeTimerL_ = 0
    RailgunFX_StopCharge("R")
    RailgunFX_StopCharge("L")
    for _, fx in ipairs(railgunFireFX_) do fx.node:Remove() end
    railgunFireFX_ = {}
    for _, hfx in ipairs(railgunHitFX_) do hfx.node:Remove() end
    railgunHitFX_ = {}
    ShieldSystem.Clear()
    BossAI.Clear()
    DestructibleBuilding.Clear()
    playerWeapons_ = nil
    GS.playerWeapons = nil
    vg_ = nil
    GS.vg = nil
    ammoHudCx_ = nil
    ammoHudCy_ = nil
    GS.ammoHudCx = nil
    GS.ammoHudCy = nil
    -- 取消事件订阅
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("PhysicsPreStep")
    UnsubscribeFromEvent("NanoVGRender")
    -- 清理 GameHUD
    GameHUD.Shutdown()
    -- 返回主菜单
    ShowMainMenu()
end

--- 进入调试模式
function EnterDebugMode()
    gameState_ = GAME_STATE_DEBUG
    DebugViewer.Enter(function()
        -- 返回主菜单的回调
        ShowMainMenu()
    end)
end

--- 根据选中的机体型号乘数重算所有 local 常量
local function ApplyVariantStats()
    local v = CONFIG.MechVariants[CONFIG.SelectedVariant or "A"] or {}
    local function mul(key) return v[key] or 1.0 end

    -- 生命值
    playerMaxHp_ = math.floor(3000 * mul("hp"))
    playerHp_    = playerMaxHp_

    -- 能量
    MAX_ENERGY           = math.floor(CONFIG.MaxEnergy * mul("maxEnergy"))
    ENERGY_REGEN_PER_SEC = CONFIG.EnergyRegenPerSec * mul("energyRegen")

    -- 移动
    MOVE_FORCE_FORWARD = CONFIG.MoveForceForward * mul("moveForce")
    MOVE_FORCE_LATERAL = CONFIG.MoveForceLateral * mul("moveForce")
    AIR_MOVE_FORCE     = CONFIG.AirMoveForce * mul("moveForce")
    MAX_SPEED_FORWARD  = CONFIG.MaxSpeedForward * mul("maxSpeed")
    MAX_SPEED_LATERAL  = CONFIG.MaxSpeedLateral * mul("maxSpeed")

    -- 跳跃 & 推进
    CONFIG._JumpSpeedMul = mul("jumpSpeed")
    BOOST_COST_PER_SEC = CONFIG.BoostCostPerSec * mul("boostCost")
    BOOST_FORCE = Vector3(0, CONFIG.BoostForce.y * mul("boostForce"), 0)

    -- 冲刺
    DASH_IMPULSE     = CONFIG.DashImpulse * mul("dashImpulse")
    DASH_DURATION    = CONFIG.DashDuration * mul("dashDuration")
    DASH_ENERGY_COST = CONFIG.DashEnergyCost * mul("dashEnergyCost")

    -- 喷射
    JET_ACTIVATION_COST = CONFIG.JetActivationCost * mul("jetCost")
    JET_COST_PER_SEC    = CONFIG.JetCostPerSec * mul("jetCost")
    JET_FORCE           = CONFIG.JetForce * mul("jetForce")
    JET_MAX_SPEED       = CONFIG.JetMaxSpeed * mul("jetMaxSpeed")
    JET_DASH_IMPULSE    = CONFIG.JetDashImpulse * mul("jetDashImpulse")

    energy_ = MAX_ENERGY

    print(string.format("[MechVariant] Applied variant %s: HP=%d Energy=%d MoveF=%.0f MaxSpd=%.1f DashI=%.0f JetF=%.0f",
        CONFIG.SelectedVariant, playerMaxHp_, MAX_ENERGY,
        MOVE_FORCE_FORWARD, MAX_SPEED_FORWARD, DASH_IMPULSE, JET_FORCE))
end

--- 启动游戏
function StartGame()
    gameState_ = GAME_STATE_PLAYING
    SoundManager.PlayRandomBattleBGM()

    -- 同步所有局部变量到 GS（供模块使用）
    GS.gameState = gameState_
    GS.current = GS.PLAYING
    GS.scene = scene_
    GS.mechNode = mechNode_
    GS.enemies = enemies_
    GS.playerWeapons = playerWeapons_
    GS.playerHp = playerHp_
    GS.playerMaxHp = playerMaxHp_
    GS.energy = energy_
    -- GS.mechState = mechState_  -- TODO: mechState_ 需要定义或移除
    GS.character = character_
    GS.currentLevel = currentLevel_

    -- 应用机体型号属性
    ApplyVariantStats()

    -- 应用关卡配置覆盖默认值
    if currentLevel_ then
        if currentLevel_.groundSize then
            CONFIG.GroundSize = currentLevel_.groundSize
        end
        if currentLevel_.mechStartPos then
            CONFIG.MechStartPos = currentLevel_.mechStartPos
        end
    end

    CreateScene()
    CreateMech()
    CreateEnvironment()

    -- 根据关卡配置决定是否创建敌人
    local spawnEnemies = true
    if currentLevel_ and currentLevel_.hasEnemies == false then
        spawnEnemies = false
    end
    if spawnEnemies then
        CreateEnemies()
    end

    -- 精英敌人生成
    elite_ = nil
    eliteRespawnTimer_ = -1
    if currentLevel_ and currentLevel_.eliteEnemy and currentLevel_.eliteEnemy.enabled then
        elite_ = EliteAI.Spawn(scene_, currentLevel_.eliteEnemy)
        -- 精英敌人加入 enemies_ 列表（让锁定系统/HUD/弹丸命中都能识别）
        table.insert(enemies_, elite_)
        Weapons.SetEnemies(enemies_)
    end

    -- 叛军关卡生成
    rebellionState_ = nil
    if currentLevel_ and currentLevel_.rebellion and currentLevel_.rebellion.enabled then
        rebellionState_ = RebelAI.InitLevel(scene_, currentLevel_.rebellion, enemies_)
        Weapons.SetEnemies(enemies_)
    end

    -- BOSS 战生成
    if currentLevel_ and currentLevel_.bossBattle and currentLevel_.bossBattle.enabled then
        -- 创建可破坏楼房群
        DestructibleBuilding.CreateAll(scene_)
        -- 生成 BOSS（内部会将 bossEnemy 插入 enemies_ 列表）
        BossAI.Spawn(scene_, currentLevel_, enemies_)
        Weapons.SetEnemies(enemies_)
        print("[BossAI] Boss battle initialized")
    end

    -- 注册玩家信息（供敌方弹丸命中检测）
    Weapons.SetPlayerInfo({
        node = mechNode_,
        getHP = function() return playerHp_ end,
        setHP = function(v)
            -- 护盾吸收：计算实际伤害
            if ShieldSystem.IsActive() then
                local incomingDmg = playerHp_ - v  -- 传入的是扣减后的值
                if incomingDmg > 0 then
                    local remaining = ShieldSystem.AbsorbDamage(incomingDmg)
                    playerHp_ = playerHp_ - remaining
                    return
                end
            end
            playerHp_ = v
        end,
        isJetting = function() return isJetting_ end,
    })

    CreateHUD()
    CreateGameHUD()
    SubscribeToEvents()
    SampleInitMouseMode(MM_RELATIVE)
    local levelName = currentLevel_ and currentLevel_.name or "Unknown"
    print("=== 机魂大悦 - " .. levelName .. " Started ===")
end

function Start()
    SampleStart()
    print("=== 机魂大悦 Started ===")
    ShowMainMenu()
end

function Stop()
    Menu.Shutdown()
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    SceneBuilder.CreateScene()
    scene_ = GS.scene
    cameraNode_ = GS.cameraNode
    tpCamera_ = GS.tpCamera
end


-- ============================================================================
-- 机甲创建
-- ============================================================================

function CreateMech()
    mechNode_ = scene_:CreateChild("Mech")
    mechNode_.position = CONFIG.MechStartPos

    -- 使用 MechBuilder 构建层级关节机甲（根据选择的变体应用颜色和装饰）
    local modelNode, joints = MechBuilder.Build(mechNode_, CONFIG.SelectedVariant)
    mechJoints_ = joints
    mechAnimator_ = MechAnimator.Create(joints)
    GS.mechNode = mechNode_
    GS.mechJoints = mechJoints_
    GS.mechAnimator = mechAnimator_

    -- 物理
    local body = mechNode_:CreateComponent("RigidBody")
    body:SetCollisionLayerAndMask(CollisionLayerCharacter, CollisionMaskCharacter)
    body:SetMass(1)
    body:SetLinearFactor(Vector3.ZERO)
    body:SetAngularFactor(Vector3.ZERO)
    body:SetCollisionEventMode(COLLISION_ALWAYS)

    local shape = mechNode_:CreateComponent("CollisionShape")
    shape:SetCapsule(1.3, 3.2, Vector3(0, 1.6, 0))

    -- KCC
    kcc_ = mechNode_:CreateComponent("KinematicCharacterController")
    kcc_:SetCollisionLayerAndMask(CollisionLayerKinematic, CollisionMaskKinematic)
    kcc_:SetJumpSpeed(CONFIG.JumpSpeed * (CONFIG._JumpSpeedMul or 1.0))
    kcc_:SetGravity(GRAVITY)

    -- 角色组件（walkSpeed=0，不让 CharacterComponent 驱动水平移动）
    -- 水平移动由 PhysicsPreStep 中直接调 SetWalkDirection 实现
    character_ = mechNode_:CreateComponent("CharacterComponent")
    character_:SetWalkSpeed(0)
    character_:SetRunSpeed(0)

    -- 战斗模式：机甲始终面朝相机方向（禁用 CharacterComponent 的平滑旋转，由 Update 直接设置）
    character_.autoRotateToMoveDir = false
    character_.rotationSpeed = 0

    -- 音频管理器初始化
    SoundManager.Init(scene_)

    -- 注册武器音效回调
    Weapons.SetOnFireCallback(function(weaponKey, position)
        SoundManager.PlayWeaponFire(weaponKey, position)
    end)
    Weapons.SetOnExplosionCallback(function(weaponKey, position)
        SoundManager.PlayWeaponExplosion(weaponKey, position)
    end)
    Weapons.SetOnHitCallback(function(weaponKey, position)
        if weaponKey == "railgun" then
            RailgunFX_Hit(position)
        end
    end)

    -- 武器创建（基于装备管理器的配置）
    WeaponManager.Init()
    playerWeapons_ = WeaponManager.CreateWeapons(mechJoints_)
    GS.playerWeapons = playerWeapons_

    -- 设置 animator 的机甲根节点引用（用于手部瞄准 IK）
    mechAnimator_.mechRootNode = mechNode_

    -- 机体发光效果（微弱 PointLight）
    local glowNode = mechNode_:CreateChild("MechGlow")
    glowNode.position = Vector3(0, 1.8, 0)  -- 胸部高度
    local glowLight = glowNode:CreateComponent("Light")
    glowLight.lightType = LIGHT_POINT
    glowLight.range = 2.0
    glowLight.color = Color(0.4, 0.6, 1.0)  -- 淡蓝色
    glowLight.brightness = 0.6
    glowLight.castShadows = false

    print("Mech created: combat mode (always face camera)")
end

-- ============================================================================
-- 环境
-- ============================================================================

-- 环境创建（已移至 environment.lua）
function CreateEnvironment() Environment.Create() end
function CreateBarriers() Environment.CreateBarriers() end


--- 在远处高空生成云层（变形球体聚簇）

--- 根据关卡配置生成装饰物


-- ============================================================================
-- 敌人创建
-- ============================================================================

--- 在指定位置生成单个敌人
---@param pos Vector3
---@param yaw number
---@return table enemy
-- 敌人生成（已移至 enemy_spawner.lua）
local function SpawnEnemy(pos, yaw) return EnemySpawner.SpawnEnemy(pos, yaw) end
local function SpawnStaticVehicle(pos, yaw, vt) return EnemySpawner.SpawnStaticVehicle(pos, yaw, vt) end
local function RandomSpawnAroundPlayer() return EnemySpawner.RandomSpawnAroundPlayer() end
function CreateEnemies() EnemySpawner.CreateAll() end


--- 给生成点加随机水平偏移，避免敌人重叠

--- 基于玩家位置生成随机出生点（距离50~200m，Y=30m空投）


-- ============================================================================
-- HUD（NanoVG 绘制能量条）
-- ============================================================================

function CreateHUD()
    vg_ = nvgCreate(1)
    GS.vg = vg_
    nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
end

function CreateGameHUD()
    -- 检测触控平台
    local platform = GetNativePlatform()
    if platform == "Android" or platform == "iOS" or platform == "Web" then
        touchEnabled = true
    end

    GameHUD.Initialize()
    GameHUD.SetControls(character_.controls)
    local hudComponents = GameHUD.Create({
        enableJump = false,
        enableRun = false,
        enableCrouch = false,
    })
    GameHUD.EnableTouchLook({
        camera = tpCamera_:GetNode(),
    })

    -- 右下角功能按钮（环形布局：L居中，SR/R/SH/SP/C环绕）
    local bigR = 96
    local smallR = 64
    local orbit = bigR + smallR + 20
    local margin = 30
    local anchorX = -(bigR + orbit + smallR + margin)
    local anchorY = -(bigR + orbit + smallR + margin)

    -- L — 中心（最大按钮，主射击）
    btnL_ = VirtualControls.CreateButton({
        position = Vector2(anchorX, anchorY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = bigR,
        label = "L",
        mouseBinding = not touchEnabled and "LMB" or nil,
        alwaysShow = true,
        color = {255, 120, 80},
        pressedColor = {255, 180, 140},
    })

    -- SL — 左上（约10点钟方向）
    local slAngle = math.rad(-55)
    btnSL_ = VirtualControls.CreateButton({
        position = Vector2(anchorX + math.sin(slAngle) * orbit, anchorY - math.cos(slAngle) * orbit),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "SL",
        keyBinding = "Q",
        alwaysShow = true,
        color = {100, 200, 255},
        pressedColor = {150, 230, 255},
    })

    -- SR — 上方（12点钟方向）
    btnSR_ = VirtualControls.CreateButton({
        position = Vector2(anchorX, anchorY - orbit),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "SR",
        keyBinding = "E",
        alwaysShow = true,
        color = {100, 200, 255},
        pressedColor = {150, 230, 255},
    })

    -- R — 右上（约2点钟方向）
    local rAngle = math.rad(55)
    btnR_ = VirtualControls.CreateButton({
        position = Vector2(anchorX + math.sin(rAngle) * orbit, anchorY - math.cos(rAngle) * orbit),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "R",
        mouseBinding = not touchEnabled and "RMB" or nil,
        alwaysShow = true,
        color = {255, 120, 80},
        pressedColor = {255, 180, 140},
    })

    -- SH — 右下（约4点钟方向）
    local shAngle = math.rad(125)
    btnSH_ = VirtualControls.CreateButton({
        position = Vector2(anchorX + math.sin(shAngle) * orbit, anchorY - math.cos(shAngle) * orbit),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "SH",
        keyBinding = "SHIFT",
        alwaysShow = true,
        color = {100, 255, 180},
        pressedColor = {150, 255, 220},
    })

    -- SP — 下方（约6点钟方向偏右）
    local spAngle = math.rad(175)
    local spX = anchorX + math.sin(spAngle) * orbit
    local spY = anchorY - math.cos(spAngle) * orbit
    btnSP_ = VirtualControls.CreateButton({
        position = Vector2(spX, spY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "SP",
        keyBinding = "SPACE",
        alwaysShow = true,
        color = {200, 220, 255},
        pressedColor = {230, 240, 255},
    })

    -- C — 左下（与SP底部对齐，偏左）
    btnC_ = VirtualControls.CreateButton({
        position = Vector2(anchorX - orbit * 0.7, spY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "C",
        keyBinding = "C",
        alwaysShow = true,
        color = {60, 200, 255},
        pressedColor = {120, 230, 255},
    })

    -- TGT — 镜头锁定按钮
    local lockOnR = 48
    local rPosX = anchorX + math.sin(rAngle) * orbit
    local rPosY = anchorY - math.cos(rAngle) * orbit
    btnLockOn_ = VirtualControls.CreateButton({
        position = Vector2(rPosX, rPosY - 250),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = lockOnR,
        label = "TGT",
        alwaysShow = true,
        color = {200, 160, 40},
        pressedColor = {255, 220, 80},
    })

    -- SW — 切换锁定目标按钮（初始隐藏）
    btnSwitchTarget_ = VirtualControls.CreateButton({
        position = Vector2(rPosX - 80, rPosY - 250),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = lockOnR,
        label = "SW",
        alwaysShow = false,
        color = {160, 200, 40},
        pressedColor = {220, 255, 80},
    })

    -- 为所有右下角按钮添加拖动旋转镜头功能
    local camera = tpCamera_:GetNode():GetComponent("Camera")
    local fov = camera and camera.fov or 45.0
    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr
    local dragLookSens = 4.0 * fov / screenH

    local function EnableDragLook(btn)
        if not btn then return end
        local origBegin = btn.handleTouchBegin
        btn.handleTouchBegin = function(self, touchId, x, y)
            local result = origBegin(self, touchId, x, y)
            if result then
                self._dragLastX = x
                self._dragLastY = y
            end
            return result
        end
        btn.handleTouchMove = function(self, touchId, x, y)
            if self.touchId ~= touchId then return false end
            if self._dragLastX then
                local dx = (x - self._dragLastX) / dpr * dragLookSens
                local dy = (y - self._dragLastY) / dpr * dragLookSens
                if character_ then
                    character_.controls.yaw = character_.controls.yaw + dx
                    character_.controls.pitch = character_.controls.pitch + dy
                end
            end
            self._dragLastX = x
            self._dragLastY = y
            return true
        end
    end

    EnableDragLook(btnL_)
    EnableDragLook(btnR_)
    EnableDragLook(btnSL_)
    EnableDragLook(btnSR_)
    EnableDragLook(btnSH_)
    EnableDragLook(btnSP_)
    EnableDragLook(btnC_)
    EnableDragLook(btnLockOn_)
    EnableDragLook(btnSwitchTarget_)
end


-- ============================================================================
-- 事件
-- ============================================================================

-- ============================================================================
-- 冲刺/喷射特效（移至 VFX 模块）
-- ============================================================================

-- 冲刺/喷射特效桥接函数
function StartDashEffect() VFX.StartDash() end
function StopDashEffect() VFX.StopDash() end
function UpdateDashEffect(dt) VFX.UpdateDash(dt) end
function StartJetEffect() VFX.StartJet() end
function StopJetEffect() VFX.StopJet() end
function UpdateJetEffect(dt) VFX.UpdateJet(dt) end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end


-- ============================================================================
-- 电磁炮 3D 视觉特效系统
-- ============================================================================

-- 电磁炮特效（已移至 railgun_fx.lua）
local function RailgunFX_StartCharge(side) RailgunFX.StartCharge(side) end
local function RailgunFX_UpdateCharge(dt, chgPct, side) RailgunFX.UpdateCharge(dt, chgPct, side) end
RailgunFX_StopCharge = function(side) RailgunFX.StopCharge(side) end
local function RailgunFX_Fire(targetPos, side) RailgunFX.Fire(targetPos, side) end
RailgunFX_Hit = function(hitPos) RailgunFX.Hit(hitPos) end
RailgunFX_UpdateFireFX = function(dt) RailgunFX.UpdateFireFX(dt) end


--- 开始蓄力特效


--- 停止蓄力特效（清理所有节点）
RailgunFX_StopCharge = function(side)
    local fxRef = (side == "L") and railgunFXL_ or railgunFX_
    if not fxRef then return end
    if fxRef.chargeGlow then fxRef.chargeGlow.node:Remove() end
    if fxRef.muzzleGlow then fxRef.muzzleGlow.node:Remove() end
    if fxRef.sparks then
        for _, s in ipairs(fxRef.sparks) do s.node:Remove() end
    end
    if fxRef.chargePlane then fxRef.chargePlane.node:Remove() end
    if fxRef.chargeLight then fxRef.chargeLight.node:Remove() end
    if side == "L" then
        railgunFXL_ = nil
    else
        railgunFX_ = nil
    end
end


--- 寻找最近的存活敌人作为锁定目标
---@param excludeEnemy table|nil 排除的敌人
---@return table|nil
function FindLockOnTarget(excludeEnemy)
    if not mechNode_ then return nil end
    local myPos = mechNode_.worldPosition
    local bestEnemy = nil
    local bestDist = math.huge
    for _, enemy in ipairs(enemies_) do
        if enemy ~= excludeEnemy and not enemy.dead and enemy.hp > 0 then
            local dist = (enemy.node.worldPosition - myPos):Length()
            if dist < bestDist then
                bestDist = dist
                bestEnemy = enemy
            end
        end
    end
    return bestEnemy
end

function HandleUpdate(eventType, eventData)
    if gameState_ ~= GAME_STATE_PLAYING then return end
    if character_ == nil then return end

    local dt = eventData["TimeStep"]:GetFloat()

    -- 退出按钮点击检测（鼠标/触控均支持）
    if not exitDialog_ and not playerDead_ then
        local clicked = false
        local cx, cy = 0, 0
        local dpr = graphics:GetDPR()
        if touchEnabled then
            -- 触控：检测触摸按下
            for i = 0, input:GetNumTouches() - 1 do
                local state = input:GetTouch(i)
                if state.delta.x == 0 and state.delta.y == 0 then
                    -- 刚按下的触摸（无移动）
                    cx = state.position.x / dpr
                    cy = state.position.y / dpr
                    clicked = true
                    break
                end
            end
        else
            if input:GetMouseButtonPress(MOUSEB_LEFT) then
                cx = input.mousePosition.x / dpr
                cy = input.mousePosition.y / dpr
                clicked = true
            end
        end
        if clicked and GS.exitBtnRect.w > 0 then
            if cx >= GS.exitBtnRect.x and cx <= GS.exitBtnRect.x + GS.exitBtnRect.w
                and cy >= GS.exitBtnRect.y and cy <= GS.exitBtnRect.y + GS.exitBtnRect.h then
                ShowExitDialog()
            end
        end
    end

    -- 退出弹窗显示时，跳过游戏输入（仅更新必要的视觉效果）
    if exitDialog_ then
        Weapons.UpdateProjectiles(dt)
        Weapons.UpdateExplosions(dt)
        Weapons.UpdateMuzzleFX(dt)
        Weapons.UpdateTrailCleanup(dt)
        RailgunFX_UpdateFireFX(dt)
        return
    end

    -- 胜利弹窗显示时，跳过游戏输入
    if victoryShown_ then
        Weapons.UpdateProjectiles(dt)
        Weapons.UpdateExplosions(dt)
        Weapons.UpdateMuzzleFX(dt)
        Weapons.UpdateTrailCleanup(dt)
        RailgunFX_UpdateFireFX(dt)
        return
    end

    -- 死亡后只更新飞散效果，跳过所有输入处理
    if playerDead_ then
        MechBuilder.UpdateDeathEffects(dt)
        -- 敌人动画继续更新
        for _, enemy in ipairs(enemies_) do
            if enemy.animator then
                enemy.animator:Update(dt)
            end
        end
        Weapons.UpdateProjectiles(dt)
        Weapons.UpdateExplosions(dt)
        Weapons.UpdateMuzzleFX(dt)
        Weapons.UpdateTrailCleanup(dt)
        RailgunFX_UpdateFireFX(dt)
        RailgunFX_StopCharge("R")  -- 死亡时停止蓄力特效
        RailgunFX_StopCharge("L")
        return
    end

    -- 测试: T 键触发玩家死亡（已禁用）
    -- if input:GetKeyPress(KEY_T) then
    --     playerHp_ = 0
    -- end

    -- 触摸输入
    if touchEnabled then
        UpdateTouches(character_.controls)
    end

    -- 视角控制
    if ui.focusElement == nil then
        if not touchEnabled then
            character_.controls.yaw = character_.controls.yaw + input.mouseMoveX * YAW_SENSITIVITY
            character_.controls.pitch = character_.controls.pitch + input.mouseMoveY * YAW_SENSITIVITY
        end
        character_.controls.pitch = Clamp(character_.controls.pitch, -80.0, 80.0)
    end

    -- ================================================================
    -- 镜头锁定系统输入处理
    -- ================================================================
    -- 锁定按钮：触摸用 isPressed 边沿检测，键盘用 GetKeyPress
    local lockOnBtnDown = btnLockOn_ and btnLockOn_.isPressed
    local lockOnJust = (lockOnBtnDown and not lockOnBtnWasPressed_) or input:GetKeyPress(KEY_T)
    lockOnBtnWasPressed_ = lockOnBtnDown or false

    -- 切换按钮：同理
    local switchBtnDown = btnSwitchTarget_ and btnSwitchTarget_.isPressed
    local switchJust = (switchBtnDown and not switchBtnWasPressed_) or input:GetKeyPress(KEY_TAB)
    switchBtnWasPressed_ = switchBtnDown or false

    if lockOnJust then
        if cameraLockOn_ then
            -- 退出锁定模式
            cameraLockOn_ = false
            cameraLockTarget_ = nil
            if btnSwitchTarget_ then
                btnSwitchTarget_.alwaysShow = false
                btnSwitchTarget_:_updateShouldShow()
            end
        else
            -- 进入锁定模式：寻找最近的存活敌人
            local target = FindLockOnTarget(nil)
            if target then
                cameraLockOn_ = true
                cameraLockTarget_ = target
                if btnSwitchTarget_ then
                    btnSwitchTarget_.alwaysShow = true
                    btnSwitchTarget_:_updateShouldShow()
                end
            end
        end
    end

    -- 切换锁定目标
    if cameraLockOn_ and switchJust then
        local newTarget = FindLockOnTarget(cameraLockTarget_)
        if newTarget then
            cameraLockTarget_ = newTarget
        end
    end

    -- 锁定目标死亡时自动搜索新目标
    if cameraLockOn_ and cameraLockTarget_ then
        if cameraLockTarget_.dead or cameraLockTarget_.hp <= 0 then
            local newTarget = FindLockOnTarget(nil)
            if newTarget then
                cameraLockTarget_ = newTarget
            else
                cameraLockOn_ = false
                cameraLockTarget_ = nil
                if btnSwitchTarget_ then
                    btnSwitchTarget_.alwaysShow = false
                    btnSwitchTarget_:_updateShouldShow()
                end
            end
        end
    end

    -- 锁定模式：平滑调整 yaw/pitch 朝向目标
    if cameraLockOn_ and cameraLockTarget_ and not cameraLockTarget_.dead then
        local vh = cameraLockTarget_.visualHeight or 3.5
        local targetPos = cameraLockTarget_.node.worldPosition + Vector3(0, vh * 0.5, 0)
        local mechPos = mechNode_.worldPosition + Vector3(0, 2.0, 0)
        local toTarget = targetPos - mechPos
        local dist = toTarget:Length()
        if dist > 0.1 then
            -- 计算目标 yaw（水平角度）
            local targetYaw = math.deg(math.atan(toTarget.x, toTarget.z))
            -- 计算目标 pitch（垂直角度）
            local horizDist = math.sqrt(toTarget.x * toTarget.x + toTarget.z * toTarget.z)
            local targetPitch = -math.deg(math.atan(toTarget.y, horizDist))

            -- 平滑插值（锁定跟踪速度）
            local lockSpeed = 8.0 * dt
            -- Yaw 环绕插值
            local yawDiff = targetYaw - character_.controls.yaw
            yawDiff = ((yawDiff + 180) % 360) - 180
            character_.controls.yaw = character_.controls.yaw + yawDiff * lockSpeed
            -- Pitch 插值
            local pitchDiff = targetPitch - character_.controls.pitch
            character_.controls.pitch = character_.controls.pitch + pitchDiff * lockSpeed
            character_.controls.pitch = Clamp(character_.controls.pitch, -80.0, 80.0)
        end
    end

    -- 朝向：喷射模式朝飞行方向（含俯仰），常规模式朝相机方向
    if isJetting_ then
        mechNode_.rotation = Quaternion(jetFlightYaw_, Vector3.UP)
                           * Quaternion(jetFlightPitch_, Vector3.RIGHT)
    else
        mechNode_.rotation = Quaternion(character_.controls.yaw, Vector3.UP)
    end

    -- ================================================================
    -- C 键切换喷射模式
    -- ================================================================
    -- 不使用按钮内置冷却阻止输入，游戏逻辑自行判断冷却
    if btnC_ and btnC_.cooldownRemaining > 0 then
        btnC_.cooldownRemaining = 0
    end
    local cDown = (btnC_ and btnC_.isPressed) or input:GetKeyDown(KEY_C)
    local cJustPressed = cDown and not cWasDown_
    cWasDown_ = cDown

    if cJustPressed then
        if isJetting_ then
            -- 已在喷射中：无论冷却状态，允许退出
        elseif energy_ < JET_ACTIVATION_COST or jetCooldownTimer_ > 0 then
            -- 未在喷射且能量不足或冷却中，无法启动
            cJustPressed = false
        end
    end

    if cJustPressed then
        isJetting_ = not isJetting_
        if isJetting_ then
            energy_ = energy_ - JET_ACTIVATION_COST
            StartJetEffect()
            SoundManager.StartLoop("jet_loop", "boost_jet", 0.4)
            -- 进入喷射：彻底冻结 KCC 内部运动状态
            local curPos = mechNode_.position
            savedFallSpeed_ = kcc_:GetFallSpeed()  -- 保存原始最大下落速度
            kcc_:SetGravity(Vector3.ZERO)
            kcc_:SetFallSpeed(0)
            kcc_:SetLinearVelocity(Vector3.ZERO)
            kcc_:SetWalkDirection(Vector3.ZERO)
            kcc_:Warp(curPos)
            jetVel_ = mechHVel_
            jetPos_ = curPos  -- 记录喷射起始位置
            mechHVel_ = Vector3.ZERO
            -- 重置按键状态，避免进入喷射瞬间误触发突进
            aWasDown_ = input:GetKeyDown(KEY_A)
            dWasDown_ = input:GetKeyDown(KEY_D)
            -- 初始化飞行方向为当前视角方向，记录进入时间
            jetFlightYaw_ = character_.controls.yaw
            jetFlightPitch_ = character_.controls.pitch
            jetEntryTime_ = time.elapsedTime
            isBoosting_ = false
            if isDashing_ then StopDashEffect() end
            isDashing_ = false
            isJetDashing_ = false
        else
            -- 退出喷射：恢复重力和最大下落速度
            local curPos = mechNode_.position
            kcc_:SetFallSpeed(savedFallSpeed_)  -- 恢复原始最大下落速度
            kcc_:SetLinearVelocity(Vector3.ZERO)
            kcc_:SetWalkDirection(Vector3.ZERO)
            kcc_:Warp(curPos)
            kcc_:SetGravity(GRAVITY)
            mechHVel_ = Vector3(jetVel_.x, 0, jetVel_.z)
            jetVel_ = Vector3.ZERO
            StopJetEffect()
            SoundManager.StopLoop("jet_loop")
            jetCooldownTimer_ = JET_COOLDOWN
            energyRegenBlockTimer_ = 1.0  -- 退出C模式后1秒内禁止恢复能量
        end
    end

    -- ================================================================
    -- 读取移动输入
    -- ================================================================
    local moveDir = Vector3.ZERO
    if input:GetKeyDown(KEY_W) then moveDir = moveDir + Vector3.FORWARD end
    if input:GetKeyDown(KEY_S) then moveDir = moveDir + Vector3.BACK end
    if input:GetKeyDown(KEY_A) then moveDir = moveDir + Vector3.LEFT end
    if input:GetKeyDown(KEY_D) then moveDir = moveDir + Vector3.RIGHT end
    if character_.controls:IsDown(CTRL_FORWARD) then moveDir = moveDir + Vector3.FORWARD end
    if character_.controls:IsDown(CTRL_BACK) then moveDir = moveDir + Vector3.BACK end
    if character_.controls:IsDown(CTRL_LEFT) then moveDir = moveDir + Vector3.LEFT end
    if character_.controls:IsDown(CTRL_RIGHT) then moveDir = moveDir + Vector3.RIGHT end

    local hasInput = moveDir:Length() > 0.01
    if hasInput then
        moveDir = moveDir:Normalized()
    end

    local yawRot = Quaternion(character_.controls.yaw, Vector3.UP)
    local worldMoveDir = yawRot * moveDir

    if isJetting_ then
        -- ==============================================================
        -- 喷射模式：能量消耗
        -- ==============================================================
        energy_ = math.max(0, energy_ - JET_COST_PER_SEC * dt)
        if energy_ <= 0 then
            -- 能量耗尽，强制退出喷射
            local curPos = mechNode_.position
            kcc_:SetFallSpeed(savedFallSpeed_)
            kcc_:SetLinearVelocity(Vector3.ZERO)
            kcc_:SetWalkDirection(Vector3.ZERO)
            kcc_:Warp(curPos)
            kcc_:SetGravity(GRAVITY)
            mechHVel_ = Vector3(jetVel_.x, 0, jetVel_.z)
            jetVel_ = Vector3.ZERO
            isJetting_ = false
            StopJetEffect()
            SoundManager.StopLoop("jet_loop")
            jetCooldownTimer_ = JET_COOLDOWN
            energyRegenBlockTimer_ = 1.0  -- 退出C模式后1秒内禁止恢复能量
        end
    end -- 能量耗尽退出后跳过喷射逻辑

    if isJetting_ then
        -- ==============================================================
        -- 喷射模式：前后持续推进，左右为瞬间突进
        -- ==============================================================
        local camRot = yawRot * Quaternion(character_.controls.pitch, Vector3.RIGHT)

        -- 转向：yaw 和 pitch 分别以最多 30°/s 向镜头方向对齐
        local desiredYaw = character_.controls.yaw
        local desiredPitch = character_.controls.pitch
        local jetElapsed = time.elapsedTime - jetEntryTime_
        local maxTurn = JET_TURN_RATE * dt

        if jetElapsed <= JET_FREE_TURN_TIME then
            jetFlightYaw_ = desiredYaw
            jetFlightPitch_ = desiredPitch
        else
            -- Yaw 对齐（处理角度环绕 -180~180）
            local yawDiff = desiredYaw - jetFlightYaw_
            -- 归一化到 -180 ~ 180
            yawDiff = ((yawDiff + 180) % 360) - 180
            if math.abs(yawDiff) > 0.01 then
                local clampedYaw = math.max(-maxTurn, math.min(maxTurn, yawDiff))
                jetFlightYaw_ = jetFlightYaw_ + clampedYaw
            end

            -- Pitch 对齐
            local pitchDiff = desiredPitch - jetFlightPitch_
            if math.abs(pitchDiff) > 0.01 then
                local clampedPitch = math.max(-maxTurn, math.min(maxTurn, pitchDiff))
                jetFlightPitch_ = jetFlightPitch_ + clampedPitch
            end
        end

        -- 从飞行 yaw/pitch 构建飞行方向并推进
        local flightRot = Quaternion(jetFlightYaw_, Vector3.UP)
                        * Quaternion(jetFlightPitch_, Vector3.RIGHT)
        local jetFlightDir = (flightRot * Vector3.FORWARD):Normalized()
        local thrustMul = 1.0 + moveDir.z
        local jetMoveDir = jetFlightDir * thrustMul
        if input:GetKeyDown(KEY_SPACE) or (btnSP_ and btnSP_.isPressed) then
            jetMoveDir = jetMoveDir + Vector3.UP
        end
        if jetMoveDir:Length() > 0.01 then
            jetMoveDir = jetMoveDir:Normalized()
            jetVel_ = jetVel_ + jetMoveDir * JET_FORCE * dt
        end

        -- 左右突进（A/D 按下瞬间触发，持续衰减冲量，有冷却）
        local aDown = input:GetKeyDown(KEY_A) or character_.controls:IsDown(CTRL_LEFT)
        local dDown = input:GetKeyDown(KEY_D) or character_.controls:IsDown(CTRL_RIGHT)
        local aJust = aDown and not aWasDown_
        local dJust = dDown and not dWasDown_
        aWasDown_ = aDown
        dWasDown_ = dDown

        local now = time.elapsedTime
        if (aJust or dJust) and not isJetDashing_ and (now - jetDashLastTime_) > JET_DASH_COOLDOWN then
            local dashSign = 0
            if aJust then dashSign = -1 end
            if dJust then dashSign = 1 end
            jetDashDir_ = yawRot * Vector3(dashSign, 0, 0)
            isJetDashing_ = true
            jetDashTimer_ = 0
            jetDashLastTime_ = now
        end

        if isJetDashing_ then
            jetDashTimer_ = jetDashTimer_ + dt
            if jetDashTimer_ < JET_DASH_DURATION then
                local progress = jetDashTimer_ / JET_DASH_DURATION
                local strength = JET_DASH_IMPULSE * (1 - progress)
                jetVel_ = jetVel_ + jetDashDir_ * strength * dt
            else
                isJetDashing_ = false
            end
        end

        -- 限速
        local jetSpeed = jetVel_:Length()
        if jetSpeed > JET_MAX_SPEED then
            jetVel_ = jetVel_ * (JET_MAX_SPEED / jetSpeed)
        end

        -- 清除 CTRL，禁止 CharacterComponent 驱动
        character_.controls:Set(CTRL_FORWARD, false)
        character_.controls:Set(CTRL_BACK, false)
        character_.controls:Set(CTRL_LEFT, false)
        character_.controls:Set(CTRL_RIGHT, false)
        character_.controls:Set(CTRL_JUMP, false)

    else
        -- ==============================================================
        -- 常规模式：冲量驱动水平移动
        -- ==============================================================
        local onGround = character_:IsOnGround()

        -- 加速：施力到 mechHVel_
        if hasInput then
            if onGround then
                local forwardDir = yawRot * Vector3.FORWARD
                local rightDir = yawRot * Vector3.RIGHT
                mechHVel_ = mechHVel_ + forwardDir * (moveDir.z * MOVE_FORCE_FORWARD * dt)
                                      + rightDir * (moveDir.x * MOVE_FORCE_LATERAL * dt)
            else
                mechHVel_ = mechHVel_ + worldMoveDir * AIR_MOVE_FORCE * dt
            end
        end

        -- 分轴阻尼 + 限速
        local fwd = yawRot * Vector3.FORWARD
        local rgt = yawRot * Vector3.RIGHT
        local vFwd = mechHVel_:DotProduct(fwd)
        local vRgt = mechHVel_:DotProduct(rgt)

        if not isDashing_ then
            local damping = onGround and GROUND_DAMPING or AIR_DAMPING
            local factor = math.max(0, 1 - damping * dt)
            local hasForwardInput = math.abs(moveDir.z) > 0.01
            local hasLateralInput = math.abs(moveDir.x) > 0.01
            if not hasForwardInput then vFwd = vFwd * factor end
            if not hasLateralInput then vRgt = vRgt * factor end
        end

        vFwd = math.max(-MAX_SPEED_FORWARD, math.min(MAX_SPEED_FORWARD, vFwd))
        vRgt = math.max(-MAX_SPEED_LATERAL, math.min(MAX_SPEED_LATERAL, vRgt))

        mechHVel_ = fwd * vFwd + rgt * vRgt

        -- 脚步声
        if onGround and not isDashing_ and mechHVel_:Length() > 1.0 then
            stepSoundTimer_ = stepSoundTimer_ + dt
            if stepSoundTimer_ >= STEP_INTERVAL then
                stepSoundTimer_ = stepSoundTimer_ - STEP_INTERVAL
                SoundManager.PlaySFX("mech_step")
            end
        else
            stepSoundTimer_ = 0
        end

        -- 清除方向 CTRL 标志
        character_.controls:Set(CTRL_FORWARD, false)
        character_.controls:Set(CTRL_BACK, false)
        character_.controls:Set(CTRL_LEFT, false)
        character_.controls:Set(CTRL_RIGHT, false)

        -- 手动设置跳跃标志（GameHUD 跳跃按钮已禁用）
        local spaceDown = input:GetKeyDown(KEY_SPACE) or (btnSP_ and btnSP_.isPressed)
        character_.controls:Set(CTRL_JUMP, spaceDown)

        -- ==============================================================
        -- 能量系统 & 推进逻辑
        -- ==============================================================
        local jumpHeld = spaceDown or character_.controls:IsDown(CTRL_JUMP)

        -- 能量恢复抑制计时器递减
        if energyRegenBlockTimer_ > 0 then
            energyRegenBlockTimer_ = energyRegenBlockTimer_ - dt
        end

        if onGround then
            if energyRegenBlockTimer_ <= 0 and not ShieldSystem.IsActive() then
                energy_ = math.min(MAX_ENERGY, energy_ + ENERGY_REGEN_PER_SEC * dt)
            end
            isBoosting_ = false

            if character_.controls:IsDown(CTRL_JUMP) then
                if energy_ >= JUMP_COST then
                    energy_ = energy_ - JUMP_COST
                    jumpStartTime_ = time.elapsedTime
                    didJump_ = true
                else
                    character_.controls:Set(CTRL_JUMP, false)
                end
            else
                didJump_ = false
            end
        else
            if not didJump_ and jumpHeld then
                -- 从平台坠落（非跳跃）时按住跳跃，也启动推进计时
                didJump_ = true
                jumpStartTime_ = time.elapsedTime
            end

            if didJump_ then
                local airTime = time.elapsedTime - jumpStartTime_

                if jumpHeld and airTime > BOOST_DELAY and energy_ > 0 then
                    isBoosting_ = true
                    kcc_:ApplyImpulse(BOOST_FORCE * dt)
                    energy_ = math.max(0, energy_ - BOOST_COST_PER_SEC * dt)
                else
                    isBoosting_ = false
                end

                if energy_ <= 0 then
                    isBoosting_ = false
                end
            end
        end

        -- ==============================================================
        -- 冲刺逻辑
        -- ==============================================================
        local shiftDown = (btnSH_ and btnSH_.isPressed) or input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT)
        local shiftJustPressed = shiftDown and not shiftWasDown_
        shiftWasDown_ = shiftDown

        if shiftJustPressed and not isDashing_
            and energy_ >= DASH_ENERGY_COST
            and (time.elapsedTime - lastDashTime_) > DASH_COOLDOWN then

            if hasInput then
                dashDir_ = worldMoveDir:Normalized()
            else
                dashDir_ = (yawRot * Vector3.FORWARD):Normalized()
            end
            dashDir_.y = 0
            dashDir_ = dashDir_:Normalized()

            isDashing_ = true
            dashTimer_ = 0
            lastDashTime_ = time.elapsedTime
            energy_ = energy_ - DASH_ENERGY_COST
            energyRegenBlockTimer_ = 0.5  -- 冲刺后0.5秒内禁止恢复能量

            -- 冲刺音效 + 特效
            SoundManager.PlaySFX("boost_jet")
            StartDashEffect()
        end

        if isDashing_ then
            dashTimer_ = dashTimer_ + dt
            if dashTimer_ < DASH_DURATION then
                local progress = dashTimer_ / DASH_DURATION
                local strength = DASH_IMPULSE * (1 - progress)
                mechHVel_ = mechHVel_ + dashDir_ * strength * dt
            else
                isDashing_ = false
                StopDashEffect()
            end
        end
    end -- if isJetting_

    -- ================================================================
    -- 动画状态判断（8方向移动，空中也适用）
    -- ================================================================
    if mechAnimator_ then
        local onGround = character_:IsOnGround()
        local targetAnim = "idle"

        if isJetting_ then
            targetAnim = "fly"
        elseif hasInput then
            -- 有方向输入时，地面和空中都使用方向移动动画（空中喷口也会喷射）
            local mx = moveDir.x
            local mz = moveDir.z
            local threshold = 0.3

            if mz > threshold then
                if mx > threshold then
                    targetAnim = "move_fr"
                elseif mx < -threshold then
                    targetAnim = "move_fl"
                else
                    targetAnim = "move_f"
                end
            elseif mz < -threshold then
                if mx > threshold then
                    targetAnim = "move_br"
                elseif mx < -threshold then
                    targetAnim = "move_bl"
                else
                    targetAnim = "move_b"
                end
            else
                if mx > threshold then
                    targetAnim = "move_r"
                elseif mx < -threshold then
                    targetAnim = "move_l"
                else
                    targetAnim = "move_f"
                end
            end
        elseif not onGround then
            targetAnim = "jump"
        end

        -- 按住跳跃键时背部喷口常亮
        local jumpHeldForFlame = input:GetKeyDown(KEY_SPACE) or (btnSP_ and btnSP_.isPressed) or character_.controls:IsDown(CTRL_JUMP)
        mechAnimator_.boostActive = jumpHeldForFlame and not onGround
        -- 喷射模式（C键）：背部喷口更大火焰
        mechAnimator_.jetActive = isJetting_

        mechAnimator_:Play(targetAnim)
        mechAnimator_:Update(dt)
    end

    -- 敌人动画更新 + 重力下落
    for _, enemy in ipairs(enemies_) do
        if enemy.animator then
            enemy.animator:Update(dt)
        end
        -- 直升机旋翼旋转
        if enemy.vehicleType == "helicopter" and enemy.joints then
            if enemy.joints.mainRotor then
                enemy.joints.mainRotor:Rotate(Quaternion(720 * dt, Vector3.UP))
            end
            if enemy.joints.tailRotor then
                enemy.joints.tailRotor:Rotate(Quaternion(1200 * dt, Vector3.UP))
            end
        end
        -- 普通敌人/坦克重力下落（直升机和小无人机悬停不受重力）
        if enemy.vehicleType ~= "helicopter" and not enemy.isMiniDrone and not enemy.isBoss and not enemy.dead then
            local pos = enemy.node.position
            if pos.y > 0 then
                -- 初始化下落速度
                if not enemy.fallSpeed then enemy.fallSpeed = 0 end
                enemy.fallSpeed = enemy.fallSpeed + 9.81 * dt
                pos.y = pos.y - enemy.fallSpeed * dt
                if pos.y <= 0 then
                    pos.y = 0
                    enemy.fallSpeed = 0
                end
                enemy.node.position = pos
            end
        end
    end

    -- ================================================================
    -- 武器系统
    -- ================================================================
    -- 获取主要目标信息
    local primaryTarget = nil
    local primaryTargetPos = nil
    local primaryLocked = false
    for _, enemy in ipairs(enemies_) do
        -- 计算敌人速度（用于预判射击）
        local curPos = enemy.node.worldPosition
        if enemy.prevPos then
            if dt > 0.001 then
                enemy.velocity = (curPos - enemy.prevPos) * (1.0 / dt)
            end
        else
            enemy.velocity = Vector3(0, 0, 0)
        end
        enemy.prevPos = Vector3(curPos.x, curPos.y, curPos.z)

        if enemy.isPrimary then
            primaryTarget = enemy
            local pvh = enemy.visualHeight or 3.5
            primaryTargetPos = enemy.node.worldPosition + Vector3(0, pvh * 0.5, 0)
            primaryLocked = enemy.locked
        end
    end

    -- 无主目标时朝准星方向射击（相机前方 100m）
    if not primaryTargetPos then
        local camNode = tpCamera_:GetNode()
        primaryTargetPos = camNode.worldPosition
            + (camNode.worldRotation * Vector3.FORWARD) * 100.0
    end

    local primaryNode = primaryTarget and primaryTarget.node or nil
    local primaryVelocity = primaryTarget and primaryTarget.velocity or nil

    -- 上半身转向主目标（半角追踪，最大 ±45°）—— 喷射模式下不转向，必须在手部射击之前以便计算射击角度限制
    if mechJoints_ and mechJoints_.body and primaryTarget and not isJetting_ then
        local mechPos = mechNode_.worldPosition
        local toTarget = primaryTargetPos - mechPos
        toTarget.y = 0 -- 只取水平分量
        local dist2D = toTarget:Length()
        if dist2D > 0.01 then
            toTarget = toTarget / dist2D -- 归一化
            -- 机甲当前朝向（由 yaw_ 决定）
            local mechFwd = Quaternion(character_.controls.yaw, Vector3.UP) * Vector3.FORWARD
            -- 计算有符号夹角（度）
            local dot = mechFwd:DotProduct(toTarget)
            dot = math.max(-1, math.min(1, dot))
            local angle = math.deg(math.acos(dot))
            -- 叉积判断方向（左手坐标系，Y分量正=目标在右侧）
            local cross = mechFwd:CrossProduct(toTarget)
            if cross.y < 0 then angle = -angle end
            -- 取一半角度，限制 ±45°
            local halfAngle = angle * 0.5
            halfAngle = math.max(-45, math.min(45, halfAngle))
            -- 叠加到 body 节点的当前旋转上
            local bodyNode = mechJoints_.body
            bodyNode.rotation = Quaternion(halfAngle, Vector3.UP) * bodyNode.rotation
        end
    end

    -- 手部武器射击角度限制：水平角度超过上半身朝向 45° 时无法射击
    local canFireHand = true
    if mechJoints_ and mechJoints_.body then
        local bodyWorldFwd = mechJoints_.body.worldRotation * Vector3.FORWARD
        bodyWorldFwd.y = 0
        local bodyFwdLen = bodyWorldFwd:Length()
        if bodyFwdLen > 0.01 then
            bodyWorldFwd = bodyWorldFwd / bodyFwdLen
            local toTarget = primaryTargetPos - mechNode_.worldPosition
            toTarget.y = 0
            local targetDist = toTarget:Length()
            if targetDist > 0.01 then
                toTarget = toTarget / targetDist
                local dot = bodyWorldFwd:DotProduct(toTarget)
                dot = math.max(-1, math.min(1, dot))
                local aimAngle = math.deg(math.acos(dot))
                if aimAngle > 45 then
                    canFireHand = false
                end
            end
        end
    end

    -- 鼠标左键/触控 → 左手（机关枪）
    -- 触控模式下只通过虚拟按钮触发，避免任意触摸被映射为 MOUSEB_LEFT 导致误射
    local firingLeft = false
    if touchEnabled then
        firingLeft = btnL_ and btnL_.isPressed
    else
        firingLeft = (btnL_ and btnL_.isPressed) or input:GetMouseButtonDown(MOUSEB_LEFT)
    end
    if firingLeft and canFireHand and playerWeapons_ then
        Weapons.TryFire(playerWeapons_.handL, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
    end
    -- 鼠标右键/触控 → 右手武器
    local firingRight = false
    if touchEnabled then
        firingRight = btnR_ and btnR_.isPressed
    else
        firingRight = (btnR_ and btnR_.isPressed) or input:GetMouseButtonDown(MOUSEB_RIGHT)
    end
    if firingRight and canFireHand and playerWeapons_ then
        local handR = playerWeapons_.handR
        if handR and handR.def.isShield then
            -- 能量盾：按下即激活（需要30%能量）
            local ok, cost = ShieldSystem.Activate(handR, mechNode_, energy_, MAX_ENERGY)
            if ok then
                energy_ = energy_ - cost
            end
        else
            Weapons.TryFire(handR, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
        end
    end

    -- 手部射击瞄准状态传递给动画器（角度超限时不做瞄准姿态）
    if mechAnimator_ then
        mechAnimator_.firingLeft = firingLeft and canFireHand
        mechAnimator_.firingRight = firingRight and canFireHand
        mechAnimator_.aimTargetPos = primaryTargetPos
    end

    -- E键 → 肩部武器（根据武器类型不同行为）
    local eDown = (btnSR_ and btnSR_.isPressed) or input:GetKeyDown(KEY_E)
    local eJust = eDown and not eWasDown_
    local eReleased = not eDown and eWasDown_
    eWasDown_ = eDown

    local shoulderW = playerWeapons_ and playerWeapons_.shoulderR or nil
    local shoulderCategory = shoulderW and shoulderW.def.category or ""

    if shoulderCategory == "tracking" then
        -- ==== 追踪类武器（missile, vertical_missile）：锁定-释放模式 ====
        if eJust and not missileLockR_ and #missileFireQueueR_ == 0 then
            if shoulderW and not shoulderW.reloading and shoulderW.ammo > 0
                and shoulderW.burstRemaining <= 0 then
                missileLockR_ = true
                missileLockTargetsR_ = {}
                missileLockMaxR_ = math.min(3, shoulderW.ammo)
            end
        end

        if primaryTarget then
            if missileLockR_ then
                local alreadyLocked = false
                for _, t in ipairs(missileLockTargetsR_) do
                    if t.enemy == primaryTarget then alreadyLocked = true; break end
                end
                if not alreadyLocked and #missileLockTargetsR_ < missileLockMaxR_ then
                    local mvh = primaryTarget.visualHeight or 3.5
                    table.insert(missileLockTargetsR_, {
                        enemy = primaryTarget,
                        node = primaryTarget.node,
                        pos = primaryTarget.node.worldPosition + Vector3(0, mvh * 0.5, 0),
                    })
                end
            end
        end

        if missileLockR_ and eReleased then
            if #missileLockTargetsR_ > 0 and shoulderW then
                missileFireQueueR_ = {}
                local ammo = shoulderW.ammo
                local n = #missileLockTargetsR_
                for i = 1, ammo do
                    local t = missileLockTargetsR_[((i - 1) % n) + 1]
                    table.insert(missileFireQueueR_, { targetPos = t.pos, targetNode = t.node })
                end
                missileFireTimerR_ = 0
            end
            missileLockR_ = false
            missileLockTargetsR_ = {}
        end

        if #missileFireQueueR_ > 0 and shoulderW then
            missileFireTimerR_ = missileFireTimerR_ - dt
            if missileFireTimerR_ <= 0 then
                local t = table.remove(missileFireQueueR_, 1)
                local tPos = t.targetPos
                if t.targetNode then
                    local tvh = 3.5
                    for _, e in ipairs(enemies_) do
                        if e.node == t.targetNode then tvh = e.visualHeight or 3.5; break end
                    end
                    tPos = t.targetNode.worldPosition + Vector3(0, tvh * 0.5, 0)
                end
                Weapons.FireSingle(shoulderW, scene_, tPos, true, t.targetNode, 60)
                missileFireTimerR_ = shoulderW.def.burstInterval or 0.1
            end
        end

    elseif shoulderCategory == "precision" and shoulderW.def.chargeTime then
        -- ==== 电磁炮：点击E开始蓄力，蓄满自动发射 ====
        if railgunCharging_ then
            -- 正在蓄力中，持续计时
            railgunChargeTimer_ = railgunChargeTimer_ + dt
            -- 更新蓄力视觉特效
            local chgPct = math.min(1.0, railgunChargeTimer_ / railgunChargeTime_)
            RailgunFX_UpdateCharge(dt, chgPct)
            -- 蓄力完成，自动发射
            if railgunChargeTimer_ >= railgunChargeTime_ then
                RailgunFX_StopCharge()
                RailgunFX_Fire(primaryTargetPos)
                Weapons.TryFire(shoulderW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
                railgunCharging_ = false
                railgunChargeTimer_ = 0
            end
        elseif eJust and shoulderW and not shoulderW.reloading and shoulderW.ammo > 0 then
            -- 点击E启动蓄力
            railgunCharging_ = true
            railgunChargeTimer_ = 0
            railgunChargeTime_ = shoulderW.def.chargeTime or 1.5
            RailgunFX_StartCharge()
        end

    elseif shoulderCategory == "explosive" then
        -- ==== 肩扛火箭（shoulder_rpg）：按E直接发射 ====
        if eJust and shoulderW then
            Weapons.TryFire(shoulderW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
        end

    else
        -- ==== 其他类型：按E直接发射 ====
        if eJust and shoulderW then
            Weapons.TryFire(shoulderW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
        end
    end

    -- Q键 → 左肩武器（逻辑与右肩镜像）
    local qDown = (btnSL_ and btnSL_.isPressed) or input:GetKeyDown(KEY_Q)
    local qJust = qDown and not qWasDown_
    local qReleased = not qDown and qWasDown_
    qWasDown_ = qDown

    local shoulderLW = playerWeapons_ and playerWeapons_.shoulderL or nil
    local shoulderLCat = shoulderLW and shoulderLW.def.category or ""

    if shoulderLCat == "tracking" then
        -- ==== 追踪类武器（missile, vertical_missile）：锁定-释放模式 ====
        if qJust and not missileLockL_ and #missileFireQueueL_ == 0 then
            if shoulderLW and not shoulderLW.reloading and shoulderLW.ammo > 0
                and shoulderLW.burstRemaining <= 0 then
                missileLockL_ = true
                missileLockTargetsL_ = {}
                missileLockMaxL_ = math.min(3, shoulderLW.ammo)
            end
        end

        if primaryTarget then
            if missileLockL_ then
                local alreadyLocked = false
                for _, t in ipairs(missileLockTargetsL_) do
                    if t.enemy == primaryTarget then alreadyLocked = true; break end
                end
                if not alreadyLocked and #missileLockTargetsL_ < missileLockMaxL_ then
                    local mvh = primaryTarget.visualHeight or 3.5
                    table.insert(missileLockTargetsL_, {
                        enemy = primaryTarget,
                        node = primaryTarget.node,
                        pos = primaryTarget.node.worldPosition + Vector3(0, mvh * 0.5, 0),
                    })
                end
            end
        end

        if missileLockL_ and qReleased then
            if #missileLockTargetsL_ > 0 and shoulderLW then
                missileFireQueueL_ = {}
                local ammo = shoulderLW.ammo
                local n = #missileLockTargetsL_
                for i = 1, ammo do
                    local t = missileLockTargetsL_[((i - 1) % n) + 1]
                    table.insert(missileFireQueueL_, { targetPos = t.pos, targetNode = t.node })
                end
                missileFireTimerL_ = 0
            end
            missileLockL_ = false
            missileLockTargetsL_ = {}
        end

        if #missileFireQueueL_ > 0 and shoulderLW then
            missileFireTimerL_ = missileFireTimerL_ - dt
            if missileFireTimerL_ <= 0 then
                local t = table.remove(missileFireQueueL_, 1)
                local tPos = t.targetPos
                if t.targetNode then
                    local tvh = 3.5
                    for _, e in ipairs(enemies_) do
                        if e.node == t.targetNode then tvh = e.visualHeight or 3.5; break end
                    end
                    tPos = t.targetNode.worldPosition + Vector3(0, tvh * 0.5, 0)
                end
                Weapons.FireSingle(shoulderLW, scene_, tPos, true, t.targetNode, -60)
                missileFireTimerL_ = shoulderLW.def.burstInterval or 0.1
            end
        end

    elseif shoulderLCat == "precision" and shoulderLW.def.chargeTime then
        -- ==== 电磁炮：点击Q开始蓄力，蓄满自动发射 ====
        if railgunChargingL_ then
            railgunChargeTimerL_ = railgunChargeTimerL_ + dt
            local chgPct = math.min(1.0, railgunChargeTimerL_ / railgunChargeTimeL_)
            RailgunFX_UpdateCharge(dt, chgPct, "L")
            if railgunChargeTimerL_ >= railgunChargeTimeL_ then
                RailgunFX_StopCharge("L")
                RailgunFX_Fire(primaryTargetPos, "L")
                Weapons.TryFire(shoulderLW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
                railgunChargingL_ = false
                railgunChargeTimerL_ = 0
            end
        elseif qJust and shoulderLW and not shoulderLW.reloading and shoulderLW.ammo > 0 then
            railgunChargingL_ = true
            railgunChargeTimerL_ = 0
            railgunChargeTimeL_ = shoulderLW.def.chargeTime or 1.5
            RailgunFX_StartCharge("L")
        end

    elseif shoulderLCat == "explosive" then
        -- ==== 肩扛火箭：按Q直接发射 ====
        if qJust and shoulderLW then
            Weapons.TryFire(shoulderLW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
        end

    else
        -- ==== 其他类型：按Q直接发射 ====
        if qJust and shoulderLW then
            Weapons.TryFire(shoulderLW, scene_, primaryTargetPos, primaryLocked, primaryNode, nil, primaryVelocity)
        end
    end

    -- 更新换弹计时
    -- R键/触控手动换弹（所有武器）
    local rDown = input:GetKeyDown(KEY_R)
    if rDown and not rWasDown_ then
        WeaponManager.ReloadAll(playerWeapons_)
    end
    rWasDown_ = rDown

    -- 批量更新所有武器（装填、连发、闪光）
    WeaponManager.UpdateAllWeapons(playerWeapons_, dt)

    -- 更新护盾系统
    ShieldSystem.Update(dt)

    -- 更新弹药飞行（含命中检测）
    Weapons.UpdateProjectiles(dt)

    -- 更新爆炸效果
    Weapons.UpdateExplosions(dt)

    -- 更新枪口闪光/发射特效
    Weapons.UpdateMuzzleFX(dt)

    -- 更新残留拖尾/粒子清理
    Weapons.UpdateTrailCleanup(dt)

    -- 更新电磁炮发射残留特效（光柱、冲击波淡出）
    RailgunFX_UpdateFireFX(dt)

    -- 武器闪光已在 WeaponManager.UpdateAllWeapons 中更新

    -- ================================================================
    -- 冲刺特效更新
    -- ================================================================
    UpdateDashEffect(dt)

    -- ================================================================
    -- 喷射冷却计时 & 特效更新
    -- ================================================================
    if jetCooldownTimer_ > 0 then
        jetCooldownTimer_ = math.max(0, jetCooldownTimer_ - dt)
    end
    UpdateJetEffect(dt)

    -- ================================================================
    -- 屏障透明度更新
    -- ================================================================
    if #barriers_ > 0 then
        local playerPos = mechNode_.worldPosition
        for _, b in ipairs(barriers_) do
            local dist = b.getDistance(playerPos)
            local alpha = 0
            if dist < BARRIER_FADE_DIST then
                -- 距离越近越不透明，最近时 alpha=0.25
                local t = 1.0 - math.max(0, dist / BARRIER_FADE_DIST)
                alpha = t * 0.25
            end
            b.mat:SetShaderParameter("MatDiffColor",
                Variant(Color(0.2, 1.0, 0.4, alpha)))
            local em = alpha * 4.0
            b.mat:SetShaderParameter("MatEmissiveColor",
                Variant(Color(0.1 * em, 0.8 * em, 0.2 * em)))
        end
    end

    -- ================================================================
    -- 精英 AI 更新
    -- ================================================================
    if elite_ and not elite_.dead then
        local playerCenter = mechNode_.worldPosition
        EliteAI.Update(elite_, scene_, playerCenter, mechNode_, dt)
    end

    -- 近战 AI 更新
    for _, me in ipairs(meleeEnemies_) do
        if not me.dead then
            MeleeAI.Update(me, scene_, mechNode_.worldPosition, mechNode_, dt)
        end
    end

    -- 叛军 AI 更新
    if rebellionState_ then
        local prevCount = #enemies_
        RebelAI.Update(rebellionState_, scene_, mechNode_.worldPosition, mechNode_, dt)
        -- 如果新生成了敌人，重新注册列表
        if #enemies_ ~= prevCount then
            Weapons.SetEnemies(enemies_)
        end
    end

    -- BOSS AI 更新
    if BossAI.GetPhase() then
        BossAI.Update(dt, mechNode_.worldPosition, mechNode_)
        -- BOSS 可能生成/击杀小无人机，刷新列表
        if #enemies_ ~= prevEnemyCount_ then
            Weapons.SetEnemies(enemies_)
        end
    end
    prevEnemyCount_ = #enemies_

    -- 可破坏楼房更新
    DestructibleBuilding.Update(dt)

    -- 精英重生计时
    if eliteRespawnTimer_ >= 0 then
        eliteRespawnTimer_ = eliteRespawnTimer_ - dt
        if eliteRespawnTimer_ < 0 then
            EliteAI.Respawn(elite_, scene_)
            -- 重新加入 enemies_ 列表
            table.insert(enemies_, elite_)
            Weapons.SetEnemies(enemies_)
            print("[EliteAI] Respawned! Total enemies: " .. #enemies_)
        end
    end

    -- ================================================================
    -- 敌人死亡检测 + 重生
    -- ================================================================
    for i = #enemies_, 1, -1 do
        local enemy = enemies_[i]
        if enemy.hp <= 0 and not enemy.dead then
            enemy.dead = true

            -- BOSS 敌人死亡（特殊处理，不走标准死亡效果）
            if enemy.isBoss then
                local phase = BossAI.GetPhase()
                if phase == "phase1" or phase == "transition" then
                    -- Phase1 HP 耗尽 → BossAI.Update 会自行触发转阶段
                    -- 重置 dead 标记让 BossAI 继续管理
                    enemy.dead = false
                    print("[BossAI] Phase1 HP depleted → transition will trigger")
                else
                    -- Phase2 HP 耗尽 → BOSS 彻底击败
                    table.remove(enemies_, i)
                    BossAI.OnBossDeath()
                    SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                    print("[BossAI] BOSS defeated → Victory!")
                    ShowVictoryDialog()
                end

            -- 精英敌人走独立重生逻辑
            elseif enemy == elite_ then
                -- 播放死亡效果
                MechBuilder.PlayDeathEffect(enemy.node)
                SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                table.remove(enemies_, i)
                if currentLevel_ and currentLevel_.noRespawn then
                    -- 不刷新模式：击败精英即胜利
                    elite_ = nil
                    print("[EliteAI] Destroyed, noRespawn=true → Victory!")
                    ShowVictoryDialog()
                else
                    eliteRespawnTimer_ = CONFIG.EliteAI.RespawnDelay
                    print(string.format("[EliteAI] Destroyed, respawn in %.0fs", CONFIG.EliteAI.RespawnDelay))
                end
            elseif enemy.rebelType then
                -- 叛军载具：不重生，计数击杀
                VehicleBuilder.PlayDeathEffect(enemy.node)
                SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                table.remove(enemies_, i)
                enemy.node:Remove()
                if rebellionState_ then
                    -- totalKills 由 RebelAI.Update 自动统计 dead 数量
                    local kills = rebellionState_.totalKills + 1 -- 预估（下帧 Update 会重算）
                    local target = rebellionState_.killsToWin or rebellionState_.totalToSpawn
                    print(string.format("[RebelAI] %s destroyed! Kills: %d/%d",
                        enemy.rebelType, kills, target))
                    -- 检查胜利
                    if kills >= target then
                        print("[RebelAI] All rebels eliminated → Victory!")
                        ShowVictoryDialog()
                    end
                end
            elseif enemy.meleeType then
                -- 近战敌人：从追踪列表移除，加入重生队列
                MechBuilder.PlayDeathEffect(enemy.node)
                SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                table.remove(enemies_, i)
                for mi = #meleeEnemies_, 1, -1 do
                    if meleeEnemies_[mi] == enemy then
                        table.remove(meleeEnemies_, mi)
                        break
                    end
                end
                local rPos, rYaw = RandomSpawnAroundPlayer()
                table.insert(meleeRespawnQueue_, {
                    timer = CONFIG.MeleeAI.RespawnDelay,
                    pos = rPos,
                    yaw = rYaw,
                })
                enemy.node:Remove()
                print(string.format("[MeleeAI] Melee enemy destroyed, respawn in %.0fs", CONFIG.MeleeAI.RespawnDelay))
            elseif enemy.vehicleType then
                -- 静态载具：重生同类型载具
                VehicleBuilder.PlayDeathEffect(enemy.node)
                SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                local rPos, rYaw = RandomSpawnAroundPlayer()
                table.insert(respawnQueue_, {
                    timer = RESPAWN_DELAY,
                    pos = rPos,
                    yaw = rYaw,
                    vehicleType = enemy.vehicleType,
                })
                table.remove(enemies_, i)
                enemy.node:Remove()
                print(string.format("[Game] %s destroyed, respawn in %.0fs", enemy.vehicleType, RESPAWN_DELAY))
            elseif enemy.isMiniDrone then
                -- 小无人机：播放无人机爆炸效果，不重生
                local dronePos = enemy.node and enemy.node.worldPosition or Vector3.ZERO
                MiniDrone.OnDeath(enemy)  -- 内部会移除 node
                SoundManager.PlaySFX3D("death_explosion", dronePos, 6, 100)
                table.remove(enemies_, i)
                print("[MiniDrone] Mini drone destroyed by player")
            else
                -- 普通敌人：基于玩家位置随机生成，空投掉落
                MechBuilder.PlayDeathEffect(enemy.node)
                SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)
                local rPos, rYaw = RandomSpawnAroundPlayer()
                table.insert(respawnQueue_, { timer = RESPAWN_DELAY, pos = rPos, yaw = rYaw })
                -- 从敌人列表中移除
                table.remove(enemies_, i)
                -- 延迟删除节点（飞散零件已独立，原节点可安全删除）
                enemy.node:Remove()
                print(string.format("[Game] Enemy destroyed, respawn in %.0fs", RESPAWN_DELAY))
            end
        end
    end

    -- 更新重生计时器
    for i = #respawnQueue_, 1, -1 do
        local r = respawnQueue_[i]
        r.timer = r.timer - dt
        if r.timer <= 0 then
            if r.vehicleType then
                SpawnStaticVehicle(r.pos, r.yaw, r.vehicleType)
            else
                SpawnEnemy(r.pos, r.yaw)
            end
            table.remove(respawnQueue_, i)
            print("[Game] Enemy respawned! Total: " .. #enemies_)
        end
    end

    -- 近战敌人重生队列
    for i = #meleeRespawnQueue_, 1, -1 do
        local r = meleeRespawnQueue_[i]
        r.timer = r.timer - dt
        if r.timer <= 0 then
            local me = MeleeAI.Spawn(scene_, r.pos, r.yaw)
            table.insert(enemies_, me)
            table.insert(meleeEnemies_, me)
            table.remove(meleeRespawnQueue_, i)
            print("[MeleeAI] Melee enemy respawned! Total melee: " .. #meleeEnemies_)
        end
    end

    -- ================================================================
    -- 玩家死亡检测
    -- ================================================================
    if not playerDead_ and playerHp_ <= 0 then
        playerDead_ = true
        MechBuilder.PlayDeathEffect(mechNode_)
        SoundManager.PlaySFX3D("death_explosion", mechNode_.worldPosition, 10, 200)
        -- 禁用物理控制
        if kcc_ then
            kcc_:SetGravity(Vector3.ZERO)
            kcc_:SetWalkDirection(Vector3.ZERO)
            kcc_:SetLinearVelocity(Vector3.ZERO)
        end
        print("[Game] Player destroyed!")
        -- 显示死亡弹窗
        ShowDeathDialog()
    end

    -- 更新死亡飞散效果（玩家和敌人共享）
    MechBuilder.UpdateDeathEffects(dt)

end

---@param eventType string
---@param eventData PhysicsPreStepEventData
function HandlePhysicsPreStep(eventType, eventData)
    if gameState_ ~= GAME_STATE_PLAYING then return end
    if kcc_ == nil or playerDead_ then return end
    local dt = eventData["TimeStep"]:GetFloat()
    if isJetting_ then
        -- 喷射模式：通过 SetWalkDirection 驱动移动，KCC 内部做碰撞检测
        -- gravity=ZERO + fallSpeed=0，Y 轴移动不受干扰
        kcc_:SetWalkDirection(jetVel_ * dt)
    else
        -- 常规模式：覆盖 CharacterComponent 的 SetWalkDirection(ZERO)
        kcc_:SetWalkDirection(mechHVel_ * dt)
    end
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandlePostUpdate(eventType, eventData)
    if gameState_ ~= GAME_STATE_PLAYING then return end
    if character_ == nil then return end
    local timeStep = eventData["TimeStep"]:GetFloat()
    lastDt_ = timeStep

    -- 死亡后冻结相机
    if playerDead_ then return end

    -- 根据俯仰角动态调整相机 Z 偏移
    local pitch = character_.controls.pitch
    local dynamicZ = 0
    if pitch < -30 then
        -- 向上看：pitch -30 ~ -70，Z 从 0 到 -6
        dynamicZ = -6.0 * math.min(1.0, ((-pitch) - 30) / 40.0)
    elseif pitch > 30 then
        -- 向下看：pitch 30 ~ 80，Z 从 0 到 6
        dynamicZ = 6.0 * math.min(1.0, (pitch - 30) / 50.0)
    end
    local mode = tpCamera_._modes and tpCamera_._modes[tpCamera_._currentMode]
    if mode then
        mode.offset = Vector3(0, 4.0, dynamicZ)
        tpCamera_._isTransitioning = true
    end

    tpCamera_:Update(timeStep, mechNode_, character_.controls.yaw, character_.controls.pitch)

    -- 锁定系统在相机更新后计算，避免UI延迟
    UpdateLockOn(timeStep)
end


-- 锁定系统（已移至 hud_renderer.lua）
function UpdateLockOn(dt) HUD.UpdateLockOn(dt) end

function HandleNanoVGRender(eventType, eventData)
    -- 同步每帧状态到 GS（供 HUD 模块读取）
    GS.lastDt = lastDt_
    GS.energy = energy_
    GS.playerHp = playerHp_
    GS.playerMaxHp = playerMaxHp_
    GS.exitDialog = exitDialog_
    GS.isBoosting = isBoosting_
    GS.isDashing = isDashing_
    GS.isJetting = isJetting_
    GS.jetCooldownTimer = jetCooldownTimer_
    GS.lastDashTime = lastDashTime_
    GS.railgunCharging = railgunCharging_
    GS.railgunChargingL = railgunChargingL_
    GS.railgunChargeTimer = railgunChargeTimer_
    GS.railgunChargeTimerL = railgunChargeTimerL_
    GS.railgunChargeTime = railgunChargeTime_
    GS.railgunChargeTimeL = railgunChargeTimeL_
    GS.missileLockR = missileLockR_
    GS.missileLockL = missileLockL_
    GS.missileLockTargetsR = missileLockTargetsR_
    GS.missileLockTargetsL = missileLockTargetsL_
    GS.missileLockMaxR = missileLockMaxR_
    GS.missileLockMaxL = missileLockMaxL_
    GS.elite = elite_
    GS.rebellionState = rebellionState_

    HUD.Render(eventType, eventData)
end
