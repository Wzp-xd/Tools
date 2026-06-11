-- ============================================================================
-- 装甲核心V风格机甲游戏 - 基础场景 v2
-- Armored Core V Style Mech Game - Basic Scene v2
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
local RailgunFX_StopCharge
local RailgunFX_UpdateFireFX
local RailgunFX_Hit

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

--- 创建带碰撞的静态方块
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param mat Material
---@return Node
local function CreateStaticBox(name, pos, scale, mat)
    local node = scene_:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    local body = node:CreateComponent("RigidBody")
    body.collisionLayer = CollisionLayerStatic
    body.collisionMask = CollisionMaskStatic
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3.ONE)
    return node
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

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    local victoryDialog = UI.Panel {
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
    UI.SetRoot(victoryDialog)
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
    playerWeapons_ = nil
    vg_ = nil
    ammoHudCx_ = nil
    ammoHudCy_ = nil
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
    print("=== Armored Core V - " .. levelName .. " Started ===")
end

function Start()
    SampleStart()
    print("=== Armored Core V - v2 Started ===")
    ShowMainMenu()
end

function Stop()
    Menu.Shutdown()
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    scene_ = Scene:new()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("PhysicsWorld")
    scene_:CreateComponent("DebugRenderer")

    -- 第三人称相机
    tpCamera_ = ThirdPersonCamera.Create(scene_, {
        modes = {
            normal = {
                distance = CONFIG.CameraDistance,
                offset = CONFIG.CameraOffset,
                fov = CONFIG.CameraFov,
            },
        },
        farClip = CONFIG.CameraFarClip,
    })
    renderer:SetViewport(0, Viewport:new(scene_, tpCamera_:GetCamera()))

    -- 光照（根据关卡配置选择 LightGroup，降低亮度营造战斗氛围）
    local sceneCfg = currentLevel_ and currentLevel_.scene or nil
    local lgPath = (sceneCfg and sceneCfg.lightGroup) or "LightGroup/Daytime.xml"
    local lightGroupFile = cache:GetResource("XMLFile", lgPath)
    if lightGroupFile then
        local lgNode = scene_:CreateChild("LightGroup")
        lgNode:LoadXML(lightGroupFile:GetRoot())
        -- 覆盖雾效（如果关卡有自定义雾配置）
        if sceneCfg and sceneCfg.fog then
            local zone = lgNode:GetComponent("Zone")
            if not zone then
                zone = lgNode:GetChild("Zone", true)
                if zone then zone = zone:GetComponent("Zone") end
            end
            if zone then
                local fc = sceneCfg.fog.color
                zone.fogColor = Color(fc[1], fc[2], fc[3])
                zone.fogStart = sceneCfg.fog.start or 150.0
                zone.fogEnd = sceneCfg.fog.fogEnd or 400.0
            end
        end
        -- 降低 LightGroup 中的光照亮度（关卡可通过 lightMult 覆盖，默认 0.4）
        local lMult = (sceneCfg and sceneCfg.lightMult) or 0.4
        local zone = lgNode:GetComponent("Zone")
        if not zone then
            local zChild = lgNode:GetChild("Zone", true)
            if zChild then zone = zChild:GetComponent("Zone") end
        end
        if zone then
            local ac = zone.ambientColor
            zone.ambientColor = Color(ac.r * lMult, ac.g * lMult, ac.b * lMult)
        end
        -- 降低方向光亮度
        local dirLightNode = lgNode:GetChild("DirectionalLight", true)
            or lgNode:GetChild("Light", true)
            or lgNode:GetChild("Sun", true)
        if dirLightNode then
            local dl = dirLightNode:GetComponent("Light")
            if dl then
                dl.brightness = (dl.brightness or 1.0) * lMult
            end
        end
    else
        local zoneNode = scene_:CreateChild("Zone")
        local zone = zoneNode:CreateComponent("Zone")
        zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
        zone.ambientColor = Color(0.1, 0.1, 0.14)
        zone.fogColor = Color(0.15, 0.17, 0.22)
        zone.fogStart = 150.0
        zone.fogEnd = 400.0
        local lightNode = scene_:CreateChild("DirectionalLight")
        lightNode.direction = Vector3(0.6, -1.0, 0.8)
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_DIRECTIONAL
        light.color = Color(0.35, 0.33, 0.3)
        light.castShadows = true
        light.shadowBias = BiasParameters(0.00025, 0.5)
        light.shadowCascade = CascadeParameters(10.0, 50.0, 200.0, 0.0, 0.8)
    end

    -- 地面（根据关卡配置选择颜色）
    local gc = (sceneCfg and sceneCfg.groundColor) or { 0.12, 0.12, 0.14 }
    local gMetal = (sceneCfg and sceneCfg.groundMetallic) or 0.0
    local gRough = (sceneCfg and sceneCfg.groundRoughness) or 0.85
    local groundMat = CreatePBRMat(Color(gc[1], gc[2], gc[3], 1.0), gMetal, gRough)
    CreateStaticBox("Ground", Vector3(0, -0.5, 0), Vector3(CONFIG.GroundSize, 1, CONFIG.GroundSize), groundMat)
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

function CreateEnvironment()
    -- 根据关卡配置选择建筑材质颜色
    local sceneCfg = currentLevel_ and currentLevel_.scene or nil
    local bcA = (sceneCfg and sceneCfg.buildingColorA) or { 0.18, 0.18, 0.2 }
    local bcB = (sceneCfg and sceneCfg.buildingColorB) or { 0.25, 0.22, 0.2 }
    local bmA = (sceneCfg and sceneCfg.buildingMetallicA) or 0.1
    local bmB = (sceneCfg and sceneCfg.buildingMetallicB) or 0.0
    local buildingMat = CreatePBRMat(Color(bcA[1], bcA[2], bcA[3], 1.0), bmA, 0.7)
    local wallMat     = CreatePBRMat(Color(bcB[1], bcB[2], bcB[3], 1.0), bmB, 0.8)

    local buildings = {
        -- 中心区域（原有）
        { pos = Vector3(30, 4, 30),     scale = Vector3(8, 8, 8) },
        { pos = Vector3(-25, 3, 35),    scale = Vector3(6, 6, 10) },
        { pos = Vector3(35, 5, -20),    scale = Vector3(10, 10, 6) },
        { pos = Vector3(-30, 2.5, -25), scale = Vector3(5, 5, 5) },
        { pos = Vector3(0, 1.5, 40),    scale = Vector3(15, 3, 3) },
        { pos = Vector3(-40, 3, 0),     scale = Vector3(4, 6, 12) },
        { pos = Vector3(20, 1, -35),    scale = Vector3(12, 2, 4) },

        -- 近距离扩展（50~100m）
        { pos = Vector3(70, 6, 60),     scale = Vector3(12, 12, 12) },
        { pos = Vector3(-80, 4, 50),    scale = Vector3(8, 8, 16) },
        { pos = Vector3(60, 3, -70),    scale = Vector3(6, 6, 6) },
        { pos = Vector3(-60, 5, -80),   scale = Vector3(10, 10, 8) },
        { pos = Vector3(90, 2, 0),      scale = Vector3(20, 4, 4) },
        { pos = Vector3(-90, 3.5, 20),  scale = Vector3(5, 7, 14) },
        { pos = Vector3(0, 4, -90),     scale = Vector3(8, 8, 8) },
        { pos = Vector3(50, 1.5, 80),   scale = Vector3(14, 3, 6) },

        -- 中距离区域（100~200m）
        { pos = Vector3(150, 8, 120),   scale = Vector3(16, 16, 16) },
        { pos = Vector3(-140, 6, 160),  scale = Vector3(12, 12, 20) },
        { pos = Vector3(180, 5, -100),  scale = Vector3(10, 10, 10) },
        { pos = Vector3(-120, 10, -150),scale = Vector3(14, 20, 14) },
        { pos = Vector3(100, 3, 180),   scale = Vector3(20, 6, 6) },
        { pos = Vector3(-180, 4, 0),    scale = Vector3(8, 8, 24) },
        { pos = Vector3(0, 7, 160),     scale = Vector3(10, 14, 10) },
        { pos = Vector3(160, 3, 160),   scale = Vector3(6, 6, 6) },
        { pos = Vector3(-160, 5, -100), scale = Vector3(12, 10, 8) },

        -- 远距离区域（200~400m）
        { pos = Vector3(300, 12, 200),  scale = Vector3(20, 24, 20) },
        { pos = Vector3(-250, 8, 300),  scale = Vector3(16, 16, 16) },
        { pos = Vector3(350, 6, -150),  scale = Vector3(12, 12, 12) },
        { pos = Vector3(-300, 10, -250),scale = Vector3(18, 20, 14) },
        { pos = Vector3(200, 4, -300),  scale = Vector3(24, 8, 8) },
        { pos = Vector3(-200, 7, 250),  scale = Vector3(10, 14, 18) },
        { pos = Vector3(250, 5, 350),   scale = Vector3(8, 10, 8) },
        { pos = Vector3(-350, 6, 100),  scale = Vector3(14, 12, 10) },
        { pos = Vector3(0, 15, 350),    scale = Vector3(20, 30, 20) },
        { pos = Vector3(0, 8, -300),    scale = Vector3(30, 16, 6) },

        -- 边缘区域（350~450m）
        { pos = Vector3(400, 10, 400),  scale = Vector3(16, 20, 16) },
        { pos = Vector3(-400, 8, 350),  scale = Vector3(12, 16, 12) },
        { pos = Vector3(420, 6, -300),  scale = Vector3(10, 12, 10) },
        { pos = Vector3(-380, 12, -400),scale = Vector3(20, 24, 16) },
        { pos = Vector3(350, 4, 0),     scale = Vector3(30, 8, 8) },
        { pos = Vector3(-420, 5, -50),  scale = Vector3(8, 10, 20) },
        { pos = Vector3(100, 6, -420),  scale = Vector3(12, 12, 12) },
        { pos = Vector3(-100, 4, 400),  scale = Vector3(16, 8, 10) },
    }

    local noBuildings = currentLevel_ and currentLevel_.noBuildings
    local clearX = currentLevel_ and currentLevel_.buildingClearX or 0
    for i, b in ipairs(buildings) do
        if not noBuildings then
            -- 过滤出生点连线走廊内的建筑（|X| - 半宽 < clearX）
            if clearX > 0 and math.abs(b.pos.x) - b.scale.x * 0.5 < clearX then
                -- 跳过走廊内的建筑
            else
                local mat = (i % 2 == 0) and wallMat or buildingMat
                CreateStaticBox("Building" .. i, b.pos, b.scale, mat)
            end
        end
    end

    -- ================================================================
    -- 关卡装饰物
    -- ================================================================
    CreateDecorations()

    -- ================================================================
    -- 天空云层
    -- ================================================================
    CreateClouds()

    -- ================================================================
    -- 场地屏障（透明墙壁 + 天花板）
    -- ================================================================
    CreateBarriers()
end

--- 在远处高空生成云层（变形球体聚簇）
function CreateClouds()
    -- 云层参数
    local CLOUD_MIN_DIST    = 200   -- 最近距离（米）
    local CLOUD_MAX_DIST    = 600   -- 最远距离（米）
    local CLOUD_MIN_HEIGHT  = 120   -- 最低高度（米）
    local CLOUD_MAX_HEIGHT  = 260   -- 最高高度（米）
    local CLOUD_COUNT       = 25    -- 云朵数量
    local BLOBS_MIN         = 5     -- 每朵云最少球体数
    local BLOBS_MAX         = 12    -- 每朵云最多球体数

    -- 云材质（半透明白色 PBR，粗糙度极高模拟蓬松感）
    local cloudMat = Material:new()
    cloudMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    cloudMat:SetShaderParameter("MatDiffColor", Variant(Color(0.95, 0.95, 0.97, 0.55)))
    cloudMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.6, 0.6, 0.7)))
    cloudMat:SetShaderParameter("Metallic", Variant(0.0))
    cloudMat:SetShaderParameter("Roughness", Variant(1.0))

    local sphereModel = cache:GetResource("Model", "Models/Sphere.mdl")
    local totalBlobs = 0

    for c = 1, CLOUD_COUNT do
        -- 云朵中心位置
        local angle = math.random() * math.pi * 2
        local dist = CLOUD_MIN_DIST + math.random() * (CLOUD_MAX_DIST - CLOUD_MIN_DIST)
        local height = CLOUD_MIN_HEIGHT + math.random() * (CLOUD_MAX_HEIGHT - CLOUD_MIN_HEIGHT)
        local cx = math.cos(angle) * dist
        local cz = math.sin(angle) * dist

        -- 云朵整体尺度（远处的云更大，保持视觉一致性）
        local distRatio = (dist - CLOUD_MIN_DIST) / (CLOUD_MAX_DIST - CLOUD_MIN_DIST)
        local baseSize = 30 + distRatio * 50  -- 30~80米基础半径（200%）

        local cloudRoot = scene_:CreateChild("Cloud_" .. c)
        cloudRoot.position = Vector3(cx, height, cz)

        -- 生成聚簇球体
        local blobCount = BLOBS_MIN + math.random(0, BLOBS_MAX - BLOBS_MIN)
        for b = 1, blobCount do
            local blobNode = cloudRoot:CreateChild("Blob")

            -- 球体在云朵内的偏移（扁平椭球分布：水平展开、竖直压扁）
            local ox = (math.random() - 0.5) * baseSize * 2.0
            local oy = (math.random() - 0.5) * baseSize * 0.4
            local oz = (math.random() - 0.5) * baseSize * 1.6
            blobNode.position = Vector3(ox, oy, oz)

            -- 变形缩放：水平拉伸、竖直压扁（模拟真实云团形态）
            local sx = (0.6 + math.random() * 0.8) * baseSize * 0.35
            local sy = sx * (0.25 + math.random() * 0.25)  -- Y方向压扁到 25%~50%
            local sz = (0.6 + math.random() * 0.8) * baseSize * 0.35
            blobNode.scale = Vector3(sx, sy, sz)

            -- 随机旋转增加多样性
            blobNode.rotation = Quaternion(math.random() * 360, Vector3.UP)

            local model = blobNode:CreateComponent("StaticModel")
            model:SetModel(sphereModel)
            model:SetMaterial(cloudMat)
            model.castShadows = false
        end
        totalBlobs = totalBlobs + blobCount
    end

    print("[Clouds] Generated " .. CLOUD_COUNT .. " clouds (" .. totalBlobs .. " sphere blobs)")
end

--- 根据关卡配置生成装饰物
function CreateDecorations()
    local sceneCfg = currentLevel_ and currentLevel_.scene or nil
    local decos = sceneCfg and sceneCfg.decorations
    if not decos then return end

    for i, d in ipairs(decos) do
        local node = scene_:CreateChild("Deco" .. i)
        node.position = Vector3(d.pos[1], d.pos[2], d.pos[3])
        node.scale = Vector3(d.scale[1], d.scale[2], d.scale[3])

        -- 旋转（可选）
        if d.rotation then
            node.rotation = Quaternion(d.rotation[1], d.rotation[2], d.rotation[3])
        end

        -- 模型
        local modelPath = "Models/" .. d.model .. ".mdl"
        local sm = node:CreateComponent("StaticModel")
        sm:SetModel(cache:GetResource("Model", modelPath))
        sm.castShadows = true

        -- PBR 材质
        local c = d.color or { 0.5, 0.5, 0.5 }
        local emissive = d.emissive and Color(d.emissive[1], d.emissive[2], d.emissive[3]) or nil
        local mat = CreatePBRMat(
            Color(c[1], c[2], c[3], 1.0),
            d.metallic or 0.0,
            d.roughness or 0.5,
            emissive
        )
        sm:SetMaterial(mat)
    end

    print(string.format("[Scene] Created %d decorations", #decos))
end

--- 创建单个屏障面
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param getDistFunc function(playerPos) → number
local function CreateBarrierPanel(name, pos, scale, getDistFunc)
    local node = scene_:CreateChild(name)
    node.position = pos
    node.scale = scale

    -- 视觉模型（透明材质）
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 1.0, 0.4, 0.0)))  -- 初始完全透明
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0, 0, 0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false

    -- 物理碰撞
    local body = node:CreateComponent("RigidBody")
    body.collisionLayer = CollisionLayerStatic
    body.collisionMask = CollisionMaskStatic
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3.ONE)

    table.insert(barriers_, {
        node = node,
        mat = mat,
        getDistance = getDistFunc,
    })
end

function CreateBarriers()
    barriers_ = {}
    local half = CONFIG.GroundSize / 2     -- 500
    local wallH = BARRIER_SKY_HEIGHT       -- 300
    local wallThick = 2                    -- 厚度 2m

    -- 北墙 (Z = +half)
    CreateBarrierPanel("Barrier_N",
        Vector3(0, wallH / 2, half + wallThick / 2),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallH, wallThick),
        function(p) return half - p.z end)

    -- 南墙 (Z = -half)
    CreateBarrierPanel("Barrier_S",
        Vector3(0, wallH / 2, -half - wallThick / 2),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallH, wallThick),
        function(p) return p.z + half end)

    -- 东墙 (X = +half)
    CreateBarrierPanel("Barrier_E",
        Vector3(half + wallThick / 2, wallH / 2, 0),
        Vector3(wallThick, wallH, CONFIG.GroundSize + wallThick * 2),
        function(p) return half - p.x end)

    -- 西墙 (X = -half)
    CreateBarrierPanel("Barrier_W",
        Vector3(-half - wallThick / 2, wallH / 2, 0),
        Vector3(wallThick, wallH, CONFIG.GroundSize + wallThick * 2),
        function(p) return p.x + half end)

    -- 天花板 (Y = wallH)
    CreateBarrierPanel("Barrier_Sky",
        Vector3(0, wallH + wallThick / 2, 0),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallThick, CONFIG.GroundSize + wallThick * 2),
        function(p) return wallH - p.y end)

    print(string.format("[Game] Created %d barriers (half=%.0f, height=%.0f)", #barriers_, half, wallH))
end

-- ============================================================================
-- 敌人创建
-- ============================================================================

--- 在指定位置生成单个敌人
---@param pos Vector3
---@param yaw number
---@return table enemy
local function SpawnEnemy(pos, yaw)
    enemyCounter_ = enemyCounter_ + 1
    local enemyRoot = scene_:CreateChild("Enemy_" .. enemyCounter_)
    enemyRoot.position = pos
    enemyRoot.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints = MechBuilder.Build(enemyRoot)
    local animator = MechAnimator.Create(joints)
    animator:Play("idle")

    -- 敌人机体发光效果（微弱红色 PointLight）
    local glowNode = enemyRoot:CreateChild("EnemyGlow")
    glowNode.position = Vector3(0, 1.8, 0)
    local glowLight = glowNode:CreateComponent("Light")
    glowLight.lightType = LIGHT_POINT
    glowLight.range = 2.0
    glowLight.color = Color(1.0, 0.3, 0.2)  -- 暗红色
    glowLight.brightness = 0.4
    glowLight.castShadows = false

    local enemy = {
        node = enemyRoot,
        animator = animator,
        joints = joints,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        hp = 100,
        maxHp = 100,
    }
    table.insert(enemies_, enemy)
    return enemy
end

--- 生成无AI静态载具（坦克/直升机）作为靶标
---@param pos Vector3
---@param yaw number
---@param vehicleType string "tank"|"helicopter"
---@return table enemy
local function SpawnStaticVehicle(pos, yaw, vehicleType)
    enemyCounter_ = enemyCounter_ + 1
    local root = scene_:CreateChild("Vehicle_" .. vehicleType .. "_" .. enemyCounter_)
    root.position = pos
    root.rotation = Quaternion(yaw, Vector3.UP)

    local modelNode, joints
    local hp, visualHeight
    if vehicleType == "tank" then
        modelNode, joints = VehicleBuilder.BuildTank(root)
        hp = 40
        visualHeight = 1.6
    else
        modelNode, joints = VehicleBuilder.BuildHelicopter(root)
        hp = 10
        visualHeight = 2.0
        -- 直升机悬停在空中
        root.position = Vector3(pos.x, 15 + math.random() * 10, pos.z)
    end

    -- 红色标记光
    local glowNode = root:CreateChild("VehicleGlow")
    glowNode.position = Vector3(0, visualHeight * 0.5, 0)
    local glowLight = glowNode:CreateComponent("Light")
    glowLight.lightType = LIGHT_POINT
    glowLight.range = 3.0
    glowLight.color = Color(1.0, 0.3, 0.2)
    glowLight.brightness = 0.5
    glowLight.castShadows = false

    local enemy = {
        node = root,
        joints = joints,
        vehicleType = vehicleType,
        visualHeight = visualHeight,
        lockValue = 0,
        locked = false,
        screenX = 0,
        screenY = 0,
        dist = 999,
        hp = hp,
        maxHp = hp,
    }
    table.insert(enemies_, enemy)
    return enemy
end

--- 给生成点加随机水平偏移，避免敌人重叠
local function RandomOffsetPos(pos)
    local ox = (math.random() - 0.5) * 6  -- ±3m
    local oz = (math.random() - 0.5) * 6
    return Vector3(pos.x + ox, pos.y, pos.z + oz)
end

--- 基于玩家位置生成随机出生点（距离50~200m，Y=30m空投）
local function RandomSpawnAroundPlayer()
    local playerPos = mechNode_ and mechNode_.worldPosition or Vector3(0, 0, 0)
    local dist = 50 + math.random() * 150  -- 50~200m
    local angle = math.random() * 2 * math.pi
    local x = playerPos.x + math.cos(angle) * dist
    local z = playerPos.z + math.sin(angle) * dist
    local yaw = math.deg(math.atan(playerPos.x - x, playerPos.z - z))  -- 面朝玩家
    return Vector3(x, 30, z), yaw
end

function CreateEnemies()
    local enemyCount = (currentLevel_ and currentLevel_.enemyCount) or 5
    for i = 1, enemyCount do
        local pos, yaw = RandomSpawnAroundPlayer()
        SpawnEnemy(pos, yaw)
    end

    -- 生成近战敌人（受关卡 hasMelee 配置控制）
    local spawnMelee = true
    if currentLevel_ and currentLevel_.hasMelee == false then
        spawnMelee = false
    end
    if spawnMelee then
        local meleeCount = CONFIG.MeleeAI.SpawnCount or 3
        for i = 1, meleeCount do
            local pos, yaw = RandomSpawnAroundPlayer()
            local meleeEnemy = MeleeAI.Spawn(scene_, pos, yaw)
            table.insert(enemies_, meleeEnemy)
            table.insert(meleeEnemies_, meleeEnemy)
        end
    end

    -- 生成静态载具靶标（受关卡 staticVehicles 配置控制）
    if currentLevel_ and currentLevel_.staticVehicles then
        local sv = currentLevel_.staticVehicles
        for i = 1, (sv.tanks or 0) do
            local pos, yaw = RandomSpawnAroundPlayer()
            SpawnStaticVehicle(pos, yaw, "tank")
        end
        for i = 1, (sv.helicopters or 0) do
            local pos, yaw = RandomSpawnAroundPlayer()
            SpawnStaticVehicle(pos, yaw, "helicopter")
        end
    end

    print("[Game] Created " .. #enemies_ .. " enemies (" .. #meleeEnemies_ .. " melee)")
    Weapons.SetEnemies(enemies_)
end

-- ============================================================================
-- HUD（NanoVG 绘制能量条）
-- ============================================================================

function CreateHUD()
    vg_ = nvgCreate(1)
    nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

function CreateGameHUD()
    -- 检测触控平台，设置全局 touchEnabled（Sample.lua 定义但需手动初始化）
    local platform = GetNativePlatform()
    if platform == "Android" or platform == "iOS" or platform == "Web" then
        touchEnabled = true
    end

    GameHUD.Initialize()
    GameHUD.SetControls(character_.controls)
    -- 只启用跳跃（GameHUD内部），crouch/run 由下方自定义按钮处理
    local hudComponents = GameHUD.Create({
        enableJump = false,
        enableRun = false,
        enableCrouch = false,
    })
    GameHUD.EnableTouchLook({
        camera = tpCamera_:GetNode(),
    })

    -- 右下角功能按钮（环形布局：L居中，SR/R/SH/SP/C环绕）
    local bigR = 96                    -- L 中心按钮半径（最大）
    local smallR = 64                  -- 周围按钮半径
    local orbit = bigR + smallR + 20   -- 环绕轨道半径（中心到周围按钮中心）
    local margin = 30                  -- 距屏幕边缘
    -- 整体锚点：以 L 按钮中心为基准，从右下角偏移
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

    -- TGT — 镜头锁定按钮（R 按钮上方 150）
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

    -- SW — 切换锁定目标按钮（TGT 按钮左侧，初始隐藏）
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
-- 冲刺特效
-- ============================================================================

--- 创建冲刺拖尾材质（无光照加法混合）
---@param color Color
---@return Material
local function CreateDashTrailMat(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAdd.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    return mat
end

--- 在指定肩膀关节上创建一条冲刺拖尾
---@param parentJoint Node
---@param name string
---@return Node
local function CreateDashShoulderTrail(parentJoint, name)
    local trailNode = parentJoint:CreateChild(name)
    trailNode.position = Vector3(0, 0.3, 0)  -- 肩甲上方

    local ribbon = trailNode:CreateComponent("RibbonTrail")
    ribbon.material = CreateDashTrailMat(Color(0.3, 0.8, 1.0, 0.9))
    ribbon.width = 0.24           -- 原 1.2 降低 80%
    ribbon.lifetime = 0.15
    ribbon.vertexDistance = 0.3
    ribbon.startColor = Color(0.4, 0.85, 1.0, 0.9)
    ribbon.endColor = Color(0.1, 0.4, 0.8, 0.0)
    ribbon.startScale = 1.0
    ribbon.endScale = 0.2
    ribbon.sorted = true
    ribbon.emitting = true
    return trailNode
end

--- 冲刺开始时创建特效
function StartDashEffect()
    if not mechNode_ or not mechJoints_ then return end

    -- 1) 双肩拖尾：绑定在左右肩关节上
    if dashTrailNodeL_ then dashTrailNodeL_:Remove() dashTrailNodeL_ = nil end
    if dashTrailNodeR_ then dashTrailNodeR_:Remove() dashTrailNodeR_ = nil end

    if mechJoints_.shoulderL then
        dashTrailNodeL_ = CreateDashShoulderTrail(mechJoints_.shoulderL, "DashTrailL")
    end
    if mechJoints_.shoulderR then
        dashTrailNodeR_ = CreateDashShoulderTrail(mechJoints_.shoulderR, "DashTrailR")
    end

    -- 2) 起始爆发：在脚部位置创建一个迅速膨胀并消失的球
    if dashBurstNode_ then
        dashBurstNode_:Remove()
        dashBurstNode_ = nil
    end
    dashBurstNode_ = scene_:CreateChild("DashBurst")
    dashBurstNode_.position = mechNode_.worldPosition + Vector3(0, 0.3, 0)
    dashBurstNode_.scale = Vector3(0.5, 0.5, 0.5)

    local burstModel = dashBurstNode_:CreateComponent("StaticModel")
    burstModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local burstMat = Material:new()
    burstMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    burstMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.7, 1.0, 0.6)))
    burstMat:SetShaderParameter("MatEmissiveColor", Variant(Color(1.5, 3.0, 5.0)))
    burstMat:SetShaderParameter("Metallic", Variant(0.0))
    burstMat:SetShaderParameter("Roughness", Variant(0.1))
    burstModel:SetMaterial(burstMat)
    burstModel.castShadows = false

    dashBurstAge_ = 0
end

--- 停止单条冲刺拖尾并放入清理队列
---@param trailNode Node|nil
local function StopDashTrail(trailNode)
    if not trailNode then return end
    if scene_ then
        local worldPos = trailNode.worldPosition
        trailNode.parent = scene_
        trailNode.position = worldPos
        local ribbon = trailNode:GetComponent("RibbonTrail")
        if ribbon then ribbon.emitting = false end
        if not dashTrailCleanup_ then dashTrailCleanup_ = {} end
        table.insert(dashTrailCleanup_, { node = trailNode, age = 0 })
    else
        trailNode:Remove()
    end
end

--- 冲刺结束时停止特效
function StopDashEffect()
    StopDashTrail(dashTrailNodeL_)
    dashTrailNodeL_ = nil
    StopDashTrail(dashTrailNodeR_)
    dashTrailNodeR_ = nil

    -- 爆发节点由 UpdateDashEffect 自然消失，但如果还在也直接移除
    if dashBurstNode_ then
        dashBurstNode_:Remove()
        dashBurstNode_ = nil
    end
end

--- 更新冲刺爆发特效动画（在 HandleUpdate 中调用）
---@param dt number
function UpdateDashEffect(dt)
    -- 更新起始爆发球：快速膨胀 + 淡出
    if dashBurstNode_ then
        dashBurstAge_ = dashBurstAge_ + dt
        local burstLife = 0.125  -- 爆发持续 0.125 秒
        if dashBurstAge_ >= burstLife then
            dashBurstNode_:Remove()
            dashBurstNode_ = nil
        else
            local progress = dashBurstAge_ / burstLife
            -- 球体膨胀到 3 倍大小
            local s = 0.5 + progress * 2.5
            dashBurstNode_.scale = Vector3(s, s * 0.6, s)
            -- 淡出：降低 alpha 和发光
            local alpha = 0.6 * (1.0 - progress)
            local emMul = 5.0 * (1.0 - progress * progress)
            local model = dashBurstNode_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.7, 1.0, alpha)))
                    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.3 * emMul, 0.6 * emMul, 1.0 * emMul)))
                end
            end
        end
    end

    -- 清理已停止发射的拖尾残留节点
    if dashTrailCleanup_ then
        for i = #dashTrailCleanup_, 1, -1 do
            local entry = dashTrailCleanup_[i]
            entry.age = entry.age + dt
            if entry.age > 0.25 then  -- 0.25 秒后删除（大于 ribbon.lifetime=0.15）
                entry.node:Remove()
                table.remove(dashTrailCleanup_, i)
            end
        end
    end
end

-- ============================================================================
-- 喷射模式特效
-- ============================================================================

--- 在背部喷口位置创建一条细长拖尾
---@param parent Node 挂载父节点（Body）
---@param name string 节点名
---@param localPos Vector3 喷口局部坐标
---@return Node trailNode
local function CreateJetTrail(parent, name, localPos)
    local node = parent:CreateChild(name)
    node.position = localPos

    local ribbon = node:CreateComponent("RibbonTrail")
    ribbon.material = CreateDashTrailMat(Color(1.0, 0.45, 0.05, 0.9))
    ribbon.width = 0.35             -- 细长拖尾
    ribbon.lifetime = 0.5           -- 较长残影
    ribbon.vertexDistance = 0.15
    ribbon.startColor = Color(1.0, 0.6, 0.15, 0.95)
    ribbon.endColor  = Color(1.0, 0.15, 0.0, 0.0)
    ribbon.startScale = 1.0
    ribbon.endScale = 0.05
    ribbon.sorted = true
    ribbon.emitting = true
    return node
end

--- 喷射模式开始时创建特效：两根细长拖尾绑定背部双喷口
function StartJetEffect()
    if not mechNode_ or not mechAnimator_ then return end

    -- 找到 Body 节点（喷口的父节点）
    local body = mechAnimator_.joints and mechAnimator_.joints.body
    if not body then body = mechNode_ end

    -- 清除旧拖尾
    if jetTrailNodeL_ then jetTrailNodeL_:Remove(); jetTrailNodeL_ = nil end
    if jetTrailNodeR_ then jetTrailNodeR_:Remove(); jetTrailNodeR_ = nil end

    -- 背部喷口位置（与 mech_builder 中 BackThrusterL/R 一致）
    jetTrailNodeL_ = CreateJetTrail(body, "JetTrailL", Vector3(-0.25, 1.62, -0.68))
    jetTrailNodeR_ = CreateJetTrail(body, "JetTrailR", Vector3( 0.25, 1.62, -0.68))
end

--- 停止单条拖尾并放入清理队列
---@param trailNode Node|nil
local function DetachJetTrail(trailNode)
    if not trailNode then return end
    if scene_ then
        local worldPos = trailNode.worldPosition
        trailNode.parent = scene_
        trailNode.position = worldPos
        local ribbon = trailNode:GetComponent("RibbonTrail")
        if ribbon then ribbon.emitting = false end
        if not dashTrailCleanup_ then dashTrailCleanup_ = {} end
        table.insert(dashTrailCleanup_, { node = trailNode, age = 0 })
    else
        trailNode:Remove()
    end
end

--- 喷射模式结束时停止特效
function StopJetEffect()
    DetachJetTrail(jetTrailNodeL_); jetTrailNodeL_ = nil
    DetachJetTrail(jetTrailNodeR_); jetTrailNodeR_ = nil
end

--- 更新喷射特效（拖尾自动跟随，无需额外更新）
function UpdateJetEffect(dt)
    -- 拖尾由 RibbonTrail 自动驱动，无需手动更新
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    -- PhysicsPreStep：在 CharacterComponent.FixedUpdate 之后运行
    -- （因为 CharacterComponent 在 CreateMech 中先注册，我们后注册）
    -- 用来覆盖 CharacterComponent 设置的 SetWalkDirection(ZERO)
    SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")
    UnsubscribeFromEvent("SceneUpdate")
end

-- ============================================================================
-- 电磁炮 3D 视觉特效系统
-- ============================================================================

--- 创建一个发光材质球体节点
---@param parent Node
---@param name string
---@param pos Vector3
---@param scale number
---@param color Color
---@param emissive Color
---@return table { node, mat }
local function CreateGlowSphere(parent, name, pos, scale, color, emissive)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = Vector3(scale, scale, scale)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false
    return { node = node, mat = mat }
end

--- 开始蓄力特效
local function RailgunFX_StartCharge(side)
    side = side or "R"
    local wpnKey = side == "L" and "shoulderL" or "shoulderR"
    if not playerWeapons_ or not playerWeapons_[wpnKey] then return end
    local wpnNode = playerWeapons_[wpnKey].weaponNode
    if not wpnNode then return end

    local fx = {}

    -- 1. 能量核心发光球（两轨之间，随蓄力增大）
    fx.chargeGlow = CreateGlowSphere(wpnNode, "RG_ChargeGlow",
        Vector3(0, 0, 0.1), 0.02,
        Color(0.3, 0.6, 1.0, 0.5), Color(2.0, 4.0, 8.0))

    -- 2. 枪口聚焦光球
    fx.muzzleGlow = CreateGlowSphere(wpnNode, "RG_MuzzleGlow",
        Vector3(0, 0, 0.38), 0.02,
        Color(0.5, 0.8, 1.0, 0.3), Color(1.0, 2.0, 4.0))

    -- 3. 导轨间电弧火花（小型发光方块，随机抖动）
    fx.sparks = {}
    for i = 1, 6 do
        local zPos = -0.1 + (i / 7) * 0.48
        local sparkNode = wpnNode:CreateChild("RG_Spark" .. i)
        sparkNode.position = Vector3(0, 0, zPos)
        sparkNode.scale = Vector3(0.001, 0.001, 0.001)
        local sModel = sparkNode:CreateComponent("StaticModel")
        sModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        local sMat = Material:new()
        sMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        sMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 1.0)))
        sMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 8.0, 15.0)))
        sMat:SetShaderParameter("Metallic", Variant(0.0))
        sMat:SetShaderParameter("Roughness", Variant(0.0))
        sModel:SetMaterial(sMat)
        sModel.castShadows = false
        table.insert(fx.sparks, { node = sparkNode, baseZ = zPos })
    end

    -- 4. 导轨间发光平面（薄 Box，随蓄力增亮）
    local planeNode = wpnNode:CreateChild("RG_ChargePlane")
    planeNode.position = Vector3(0, 0, 0.2)  -- 两轨之间中心
    planeNode.scale = Vector3(0.24, 0.001, 0.001)  -- 初始极薄极短，仅保留宽度
    local pModel = planeNode:CreateComponent("StaticModel")
    pModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local pMat = Material:new()
    pMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    pMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, 0.0)))
    pMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.0, 0.0, 0.0)))
    pMat:SetShaderParameter("Metallic", Variant(0.0))
    pMat:SetShaderParameter("Roughness", Variant(0.0))
    pModel:SetMaterial(pMat)
    pModel.castShadows = false
    fx.chargePlane = { node = planeNode, mat = pMat }

    -- 5. 蓄力点光源
    local lightNode = wpnNode:CreateChild("RG_ChargeLight")
    lightNode.position = Vector3(0, 0, 0.2)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(0.4, 0.7, 1.0)
    light.range = 0.5
    light.brightness = 0.5
    light.castShadows = false
    fx.chargeLight = { node = lightNode, light = light }

    if side == "L" then
        railgunFXL_ = fx
    else
        railgunFX_ = fx
    end
end

--- 更新蓄力特效（每帧调用）
---@param dt number
---@param chgPct number 0~1 蓄力进度
local function RailgunFX_UpdateCharge(dt, chgPct, side)
    local fxRef = (side == "L") and railgunFXL_ or railgunFX_
    if not fxRef then return end
    local t = os.clock()

    -- 1. 核心发光球：随蓄力增大 + 脉冲
    if fxRef.chargeGlow then
        local s = 0.16 * chgPct
        fxRef.chargeGlow.node.scale = Vector3(s, s, s)
        local pulse = 1.0 + 0.3 * math.sin(t * 15)
        local em = chgPct * pulse
        fxRef.chargeGlow.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(2.0 * em, 4.0 * em, 8.0 * em)))
        fxRef.chargeGlow.mat:SetShaderParameter("MatDiffColor",
            Variant(Color(0.3, 0.6, 1.0, 0.3 + 0.5 * chgPct)))
    end

    -- 2. 枪口聚焦球：二次增长 + 快速脉冲
    if fxRef.muzzleGlow then
        local ms = 0.12 * chgPct * chgPct
        fxRef.muzzleGlow.node.scale = Vector3(ms, ms, ms)
        local pulse = 1.0 + 0.5 * math.sin(t * 20)
        local em = chgPct * chgPct * pulse
        fxRef.muzzleGlow.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(3.0 * em, 5.0 * em, 10.0 * em)))
    end

    -- 3. 电弧火花：在导轨间随机跳动
    if fxRef.sparks then
        for _, spark in ipairs(fxRef.sparks) do
            local jitterY = (math.random() - 0.5) * 0.08
            local jitterX = (math.random() - 0.5) * 0.02
            spark.node.position = Vector3(jitterX, jitterY, spark.baseZ + (math.random() - 0.5) * 0.05)
            local visible = math.random() < chgPct
            if visible then
                local sz = 0.016 + 0.016 * chgPct
                spark.node.scale = Vector3(sz, sz, 0.04 + 0.06 * chgPct)
            else
                spark.node.scale = Vector3(0.001, 0.001, 0.001)
            end
        end
    end

    -- 4. 导轨间发光平面：随蓄力变长、变亮
    if fxRef.chargePlane then
        local planeLen = 1.2 * chgPct  -- Z 方向逐渐延伸到导轨全长
        local pulse = 1.0 + 0.2 * math.sin(t * 12)
        fxRef.chargePlane.node.scale = Vector3(0.24, 0.005, math.max(0.001, planeLen))
        local emStr = chgPct * chgPct * pulse
        fxRef.chargePlane.mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(3.0 * emStr, 6.0 * emStr, 12.0 * emStr)))
        fxRef.chargePlane.mat:SetShaderParameter("MatDiffColor",
            Variant(Color(0.3, 0.6, 1.0, 0.15 + 0.6 * chgPct)))
    end

    -- 5. 点光源：范围和亮度随蓄力增加
    if fxRef.chargeLight then
        fxRef.chargeLight.light.range = 0.5 + 3.0 * chgPct
        fxRef.chargeLight.light.brightness = 0.5 + 3.0 * chgPct
    end
end

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

--- 发射瞬间特效（枪口闪光 + 光柱 + 冲击波）
---@param targetPos Vector3|nil 目标位置，nil 则沿武器朝向
local function RailgunFX_Fire(targetPos, side)
    side = side or "R"
    local wpnKey = side == "L" and "shoulderL" or "shoulderR"
    if not playerWeapons_ or not playerWeapons_[wpnKey] then return end
    local weapon = playerWeapons_[wpnKey]
    local spawnPos = weapon.mountNode.worldPosition
    local fwd
    if targetPos then
        fwd = (targetPos - spawnPos):Normalized()
    else
        fwd = weapon.mountNode.worldRotation * Vector3.FORWARD
    end

    -- 1. 枪口爆闪（大型高亮球体）
    local flashNode = scene_:CreateChild("RG_Flash")
    flashNode.position = spawnPos + fwd * 0.5
    flashNode.scale = Vector3(0.8, 0.8, 0.8)
    local fModel = flashNode:CreateComponent("StaticModel")
    fModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local fMat = Material:new()
    fMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    fMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 0.9)))
    fMat:SetShaderParameter("MatEmissiveColor", Variant(Color(15.0, 20.0, 30.0)))
    fMat:SetShaderParameter("Metallic", Variant(0.0))
    fMat:SetShaderParameter("Roughness", Variant(0.0))
    fModel:SetMaterial(fMat)
    fModel.castShadows = false
    table.insert(railgunFireFX_, { node = flashNode, mat = fMat, age = 0, life = 0.25,
        type = "flash", maxScale = 2.5 })

    -- 2. 光柱（沿发射方向的细长光束）
    local beamNode = scene_:CreateChild("RG_Beam")
    beamNode.position = spawnPos + fwd * 25.0  -- 中心在前方25米
    beamNode.rotation = Quaternion(Vector3.FORWARD, fwd)
    beamNode.scale = Vector3(3.0, 3.0, 50.0)  -- 粗光束50米
    local bModel = beamNode:CreateComponent("StaticModel")
    bModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bMat = Material:new()
    bMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    bMat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, 0.7)))
    bMat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 12.0, 20.0)))
    bMat:SetShaderParameter("Metallic", Variant(0.0))
    bMat:SetShaderParameter("Roughness", Variant(0.0))
    bModel:SetMaterial(bMat)
    bModel.castShadows = false
    table.insert(railgunFireFX_, { node = beamNode, mat = bMat, age = 0, life = 0.3,
        type = "beam", initAlpha = 0.7 })

    -- 3. 冲击波环（枪口位置水平扩散环）
    local ringNode = scene_:CreateChild("RG_Ring")
    ringNode.position = spawnPos + fwd * 0.3
    ringNode.rotation = Quaternion(Vector3.UP, fwd) -- 环面朝向射击方向
    ringNode.scale = Vector3(0.3, 0.02, 0.3)
    local rModel = ringNode:CreateComponent("StaticModel")
    rModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local rMat = Material:new()
    rMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rMat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 1.0, 0.5)))
    rMat:SetShaderParameter("MatEmissiveColor", Variant(Color(4.0, 6.0, 10.0)))
    rMat:SetShaderParameter("Metallic", Variant(0.0))
    rMat:SetShaderParameter("Roughness", Variant(0.0))
    rModel:SetMaterial(rMat)
    rModel.castShadows = false
    table.insert(railgunFireFX_, { node = ringNode, mat = rMat, age = 0, life = 0.35,
        type = "ring", maxScale = 5.0 })

    -- 4. 发射闪光点光源（短暂的强光）
    local flashLightNode = scene_:CreateChild("RG_FireLight")
    flashLightNode.position = spawnPos + fwd * 1.0
    local flashLight = flashLightNode:CreateComponent("Light")
    flashLight.lightType = LIGHT_POINT
    flashLight.color = Color(0.6, 0.8, 1.0)
    flashLight.range = 15.0
    flashLight.brightness = 5.0
    flashLight.castShadows = false
    table.insert(railgunFireFX_, { node = flashLightNode, age = 0, life = 0.2,
        type = "light", light = flashLight })
end

--- 电磁炮命中特效（电弧放电 + 冲击波 + 闪光）
---@param hitPos Vector3 命中位置
RailgunFX_Hit = function(hitPos)
    if not scene_ then return end

    -- 1. 电弧核心球（高亮发光球体，电磁冲击中心）
    local coreNode = scene_:CreateChild("RGHit_Core")
    coreNode.position = hitPos
    coreNode.scale = Vector3(0.6, 0.6, 0.6)
    local cModel = coreNode:CreateComponent("StaticModel")
    cModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local cMat = Material:new()
    cMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    cMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, 0.95)))
    cMat:SetShaderParameter("MatEmissiveColor", Variant(Color(20.0, 30.0, 50.0)))
    cMat:SetShaderParameter("Metallic", Variant(0.0))
    cMat:SetShaderParameter("Roughness", Variant(0.0))
    cModel:SetMaterial(cMat)
    cModel.castShadows = false
    table.insert(railgunHitFX_, {
        node = coreNode, mat = cMat, age = 0, life = 0.4,
        type = "core", maxScale = 2.0,
    })

    -- 2. 电弧分支（6条随机方向的细长光柱，模拟电弧放电）
    for j = 1, 6 do
        local arcNode = scene_:CreateChild("RGHit_Arc")
        arcNode.position = hitPos
        -- 随机方向
        local rx = math.random() * 2.0 - 1.0
        local ry = math.random() * 1.5 - 0.3  -- 稍偏上
        local rz = math.random() * 2.0 - 1.0
        local dir = Vector3(rx, ry, rz):Normalized()
        arcNode.rotation = Quaternion(Vector3.FORWARD, dir)
        local arcLen = 1.5 + math.random() * 2.0
        arcNode.scale = Vector3(0.06, 0.06, arcLen)
        local aModel = arcNode:CreateComponent("StaticModel")
        aModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        local aMat = Material:new()
        aMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        aMat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, 0.8)))
        aMat:SetShaderParameter("MatEmissiveColor", Variant(Color(10.0, 15.0, 25.0)))
        aMat:SetShaderParameter("Metallic", Variant(0.0))
        aMat:SetShaderParameter("Roughness", Variant(0.0))
        aModel:SetMaterial(aMat)
        aModel.castShadows = false
        table.insert(railgunHitFX_, {
            node = arcNode, mat = aMat, age = 0, life = 0.2 + math.random() * 0.15,
            type = "arc", initLen = arcLen,
        })
    end

    -- 3. 冲击波环（水平扩散电磁脉冲环）
    local ringNode = scene_:CreateChild("RGHit_Ring")
    ringNode.position = hitPos
    ringNode.scale = Vector3(0.4, 0.02, 0.4)
    local rModel = ringNode:CreateComponent("StaticModel")
    rModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local rMat = Material:new()
    rMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, 0.6)))
    rMat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 8.0, 15.0)))
    rMat:SetShaderParameter("Metallic", Variant(0.0))
    rMat:SetShaderParameter("Roughness", Variant(0.0))
    rModel:SetMaterial(rMat)
    rModel.castShadows = false
    table.insert(railgunHitFX_, {
        node = ringNode, mat = rMat, age = 0, life = 0.35,
        type = "ring", maxScale = 4.0,
    })

    -- 4. 冲击点光源（短暂蓝白强光）
    local lightNode = scene_:CreateChild("RGHit_Light")
    lightNode.position = hitPos
    local hitLight = lightNode:CreateComponent("Light")
    hitLight.lightType = LIGHT_POINT
    hitLight.color = Color(0.5, 0.7, 1.0)
    hitLight.range = 12.0
    hitLight.brightness = 6.0
    hitLight.castShadows = false
    table.insert(railgunHitFX_, {
        node = lightNode, age = 0, life = 0.3,
        type = "light", light = hitLight,
    })

    print("[RailgunFX] Hit effect at " .. tostring(hitPos))
end

--- 更新发射后残留特效（淡出 + 清理）
---@param dt number
RailgunFX_UpdateFireFX = function(dt)
    local i = 1
    while i <= #railgunFireFX_ do
        local fx = railgunFireFX_[i]
        fx.age = fx.age + dt

        if fx.age >= fx.life then
            fx.node:Remove()
            table.remove(railgunFireFX_, i)
        else
            local progress = fx.age / fx.life

            if fx.type == "flash" then
                -- 枪口闪光：快速膨胀 + 淡出
                local s = 0.8 + (fx.maxScale - 0.8) * math.min(1.0, progress * 4.0)
                fx.node.scale = Vector3(s, s, s)
                local alpha = 0.9 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, alpha)))
                local em = math.max(0, 15.0 * (1.0 - progress * 2.0))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.3, em * 2.0)))

            elseif fx.type == "beam" then
                -- 光柱：淡出 + 收缩
                local alpha = fx.initAlpha * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, alpha)))
                local em = math.max(0, 8.0 * (1.0 - progress * 1.5))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))
                local shrink = 0.9 * (1.0 - progress * 0.7)
                fx.node.scale = Vector3(shrink, shrink, 50.0)

            elseif fx.type == "ring" then
                -- 冲击波环：向外扩散 + 淡出
                local expand = 0.3 + fx.maxScale * progress
                fx.node.scale = Vector3(expand, 0.02 * (1.0 - progress), expand)
                local alpha = 0.5 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 1.0, alpha)))
                local em = math.max(0, 4.0 * (1.0 - progress))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))

            elseif fx.type == "light" then
                -- 闪光灯：亮度快速衰减
                fx.light.brightness = 5.0 * (1.0 - progress)
                fx.light.range = 15.0 * (1.0 - progress * 0.5)
            end

            i = i + 1
        end
    end

    -- 更新命中特效
    local j = 1
    while j <= #railgunHitFX_ do
        local hfx = railgunHitFX_[j]
        hfx.age = hfx.age + dt

        if hfx.age >= hfx.life then
            hfx.node:Remove()
            table.remove(railgunHitFX_, j)
        else
            local prog = hfx.age / hfx.life

            if hfx.type == "core" then
                -- 核心球：快速膨胀 + 淡出
                local s = 0.6 + (hfx.maxScale - 0.6) * math.min(1.0, prog * 3.0)
                hfx.node.scale = Vector3(s, s, s)
                local alpha = 0.95 * (1.0 - prog)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.9, 1.0, alpha)))
                local em = math.max(0, 20.0 * (1.0 - prog * 1.5))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))

            elseif hfx.type == "arc" then
                -- 电弧：快速闪烁 + 收缩消失
                local flicker = (math.sin(hfx.age * 80.0) * 0.5 + 0.5)  -- 高频闪烁
                local alpha = 0.8 * (1.0 - prog) * (0.5 + flicker * 0.5)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.5, 0.8, 1.0, alpha)))
                local em = math.max(0, 10.0 * (1.0 - prog))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.5, em * 2.5)))
                -- 收缩到消失
                local shrink = math.max(0.01, 1.0 - prog * 1.2)
                hfx.node.scale = Vector3(0.06 * shrink, 0.06 * shrink, hfx.initLen * shrink)

            elseif hfx.type == "ring" then
                -- 冲击波环：向外扩散 + 淡出
                local expand = 0.4 + hfx.maxScale * prog
                hfx.node.scale = Vector3(expand, 0.02 * (1.0 - prog), expand)
                local alpha = 0.6 * (1.0 - prog)
                hfx.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.6, 1.0, alpha)))
                local em = math.max(0, 5.0 * (1.0 - prog))
                hfx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 1.6, em * 3.0)))

            elseif hfx.type == "light" then
                -- 点光源：亮度快速衰减
                hfx.light.brightness = 6.0 * (1.0 - prog)
                hfx.light.range = 12.0 * (1.0 - prog * 0.5)
            end

            j = j + 1
        end
    end
end

-- ============================================================================
-- 镜头锁定 - 目标搜索
-- ============================================================================

--- 寻找最佳锁定目标（按距离排序，跳过当前目标和死亡目标）
---@param excludeEnemy table|nil 要排除的敌人（用于切换目标时跳过当前目标）
---@return table|nil enemy 找到的目标，或 nil
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

---@param eventType string
---@param eventData UpdateEventData
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
        if clicked and exitBtnRect_.w > 0 then
            if cx >= exitBtnRect_.x and cx <= exitBtnRect_.x + exitBtnRect_.w
                and cy >= exitBtnRect_.y and cy <= exitBtnRect_.y + exitBtnRect_.h then
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

    -- 死亡后只更新飞散效果，跳过所有输入处理
    if playerDead_ then
        MechBuilder.UpdateDeathEffects(dt)
        -- 敌人动画继续更新
        for _, enemy in ipairs(enemies_) do
            enemy.animator:Update(dt)
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
        -- 普通敌人/坦克重力下落（直升机悬停不受重力）
        if enemy.vehicleType ~= "helicopter" and not enemy.dead then
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
            -- 播放死亡效果（零件飞散+爆炸）
            if enemy.vehicleType then
                VehicleBuilder.PlayDeathEffect(enemy.node)
            else
                MechBuilder.PlayDeathEffect(enemy.node)
            end
            SoundManager.PlaySFX3D("death_explosion", enemy.node.worldPosition, 10, 200)

            -- 精英敌人走独立重生逻辑
            if enemy == elite_ then
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
            else
                -- 普通敌人：基于玩家位置随机生成，空投掉落
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

-- ============================================================================
-- 锁定系统
-- ============================================================================

--- 更新所有敌人的锁定状态
---@param dt number
function UpdateLockOn(dt)
    local camera = tpCamera_:GetCamera()
    local camNode = tpCamera_:GetNode()
    local camPos = camNode.worldPosition
    local camFwd = camNode.worldRotation * Vector3.FORWARD
    local pw = scene_:GetComponent("PhysicsWorld")
    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr

    for _, enemy in ipairs(enemies_) do
        local vh = enemy.visualHeight or 3.5
        local targetPos = enemy.node.worldPosition + Vector3(0, vh * 0.5, 0)  -- 重心高度
        local toTarget = targetPos - camPos
        local dist = toTarget:Length()

        -- 是否在相机前方
        local inFront = toTarget:DotProduct(camFwd) > 0

        -- 屏幕坐标检查
        local onScreen = false
        local sx, sy = 0.5, 0.5
        if inFront then
            local sp = camera:WorldToScreenPoint(targetPos)
            sx, sy = sp.x, sp.y
            onScreen = sx >= 0.02 and sx <= 0.98 and sy >= 0.02 and sy <= 0.98
        end

        -- 遮挡检测（仅对屏幕内目标做射线检测）
        local visible = onScreen
        if visible and pw then
            local ray = Ray(camPos, toTarget:Normalized())
            local result = pw:RaycastSingle(ray, dist - 0.5, CollisionLayerStatic)
            if result and result.body then
                visible = false
            end
        end

        -- 更新锁定值
        if visible then
            enemy.lockValue = math.min(LOCK_MAX, enemy.lockValue + LOCK_GAIN_RATE * dt)
        else
            enemy.lockValue = math.max(0, enemy.lockValue - LOCK_DECAY_RATE * dt)
        end

        -- 锁定状态：达到满值时进入锁定，降到 0 才解除
        if enemy.lockValue >= LOCK_MAX then
            enemy.locked = true
        elseif enemy.lockValue <= 0 then
            enemy.locked = false
        end

        -- 计算敌人在屏幕上的投影大小（用脚底和头顶两点）
        local screenSize = 64
        if inFront then
            local bottomPos = enemy.node.worldPosition
            local topPos = bottomPos + Vector3(0, vh, 0)  -- 敌人视觉高度
            local spBottom = camera:WorldToScreenPoint(bottomPos)
            local spTop = camera:WorldToScreenPoint(topPos)
            local pixelH = math.abs(spBottom.y - spTop.y)  -- 归一化屏幕高度差
            screenSize = pixelH * screenH * 0.5  -- 半高作为圆半径基准
        end

        enemy.screenX = sx
        enemy.screenY = sy
        enemy.dist = dist
        enemy.onScreen = onScreen
        enemy.inFront = inFront
        enemy.screenSize = math.max(32, screenSize)
        enemy.isPrimary = false
    end

    -- 主要目标：锁定值 > 0 且离屏幕中心最近的单位
    local bestEnemy = nil
    local bestScreenDist = math.huge
    for _, enemy in ipairs(enemies_) do
        if enemy.lockValue > 0 then
            local dx = enemy.screenX - 0.5
            local dy = enemy.screenY - 0.5
            local sd = dx * dx + dy * dy
            if sd < bestScreenDist then
                bestScreenDist = sd
                bestEnemy = enemy
            end
        end
    end
    if bestEnemy then
        bestEnemy.isPrimary = true
    end
end

--- 绘制屏幕边缘敌人方向指示箭头
---@param w number 屏幕逻辑宽度
---@param h number 屏幕逻辑高度
function DrawOffScreenIndicators(w, h)
    local margin = 40        -- 距屏幕边缘距离
    local arrowSize = 10     -- 三角箭头大小
    local cx, cy = w / 2, h / 2

    -- 获取相机变换用于计算视空间方向
    local camNode = tpCamera_ and tpCamera_:GetNode()
    if not camNode then return end
    local camInvRot = camNode.worldRotation:Inverse()

    -- 相机水平前方方向（用于计算水平夹角）
    local camFwd = camNode.worldRotation * Vector3.FORWARD
    local camFwdFlat = Vector3(camFwd.x, 0, camFwd.z)
    local camFwdFlatLen = camFwdFlat:Length()
    if camFwdFlatLen > 0.001 then camFwdFlat = camFwdFlat / camFwdFlatLen end

    local angle120 = math.rad(120)
    local angleRange = math.rad(60)  -- 120°→180° 的过渡区间

    for _, enemy in ipairs(enemies_) do
        if enemy.dead or enemy.onScreen then goto continue end

        local enemyPos = enemy.node.worldPosition
        local camPos = camNode.worldPosition
        local toEnemyFlat = Vector3(enemyPos.x - camPos.x, 0, enemyPos.z - camPos.z)
        local flatLen = toEnemyFlat:Length()
        if flatLen < 0.1 then goto continue end

        -- 计算水平夹角（相对相机前方）
        local toEnemyFlatNorm = toEnemyFlat / flatLen
        local dotH = camFwdFlat:DotProduct(toEnemyFlatNorm)
        local angleFromFwd = math.acos(math.max(-1, math.min(1, dotH)))

        -- Y轴权重：0~120°=100%, 120~180°线性降至0%
        local yWeight = 1.0
        if angleFromFwd > angle120 then
            yWeight = math.max(0, 1.0 - (angleFromFwd - angle120) / angleRange)
        end

        -- 水平方向（不受俯仰影响，始终正确）
        local viewDirFlat = camInvRot * toEnemyFlat
        local dx_h = viewDirFlat.x
        local dy_h = -viewDirFlat.z
        local lenH = math.sqrt(dx_h * dx_h + dy_h * dy_h)
        if lenH > 0.001 then dx_h, dy_h = dx_h / lenH, dy_h / lenH end

        -- 3D方向（含Y轴，前方敌人垂直偏移更准确）
        local vh = enemy.visualHeight or 3.5
        local toEnemy3D = Vector3(toEnemyFlat.x, (enemyPos.y + vh * 0.5) - camPos.y, toEnemyFlat.z)
        local viewDir3D = camInvRot * toEnemy3D
        local dx_3d = viewDir3D.x
        local dy_3d = -viewDir3D.y
        local len3D = math.sqrt(dx_3d * dx_3d + dy_3d * dy_3d)
        if len3D > 0.001 then dx_3d, dy_3d = dx_3d / len3D, dy_3d / len3D end

        -- 混合：yWeight 控制 Y 轴影响程度
        local dx = dx_h * (1 - yWeight) + dx_3d * yWeight
        local dy = dy_h * (1 - yWeight) + dy_3d * yWeight

        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.001 then goto continue end
        local ndx, ndy = dx / len, dy / len

        -- 沿方向射线与屏幕边缘求交，确定箭头位置
        local ax, ay = cx, cy
        local edgeL, edgeR = margin, w - margin
        local edgeT, edgeB = margin, h - margin
        -- 射线参数化: P = center + t * dir, 求最小正t使其到达边缘
        local tMin = math.huge
        if ndx > 0.001 then
            tMin = math.min(tMin, (edgeR - cx) / ndx)
        elseif ndx < -0.001 then
            tMin = math.min(tMin, (edgeL - cx) / ndx)
        end
        if ndy > 0.001 then
            tMin = math.min(tMin, (edgeB - cy) / ndy)
        elseif ndy < -0.001 then
            tMin = math.min(tMin, (edgeT - cy) / ndy)
        end
        ax = cx + ndx * tMin
        ay = cy + ndy * tMin

        -- 箭头颜色：根据距离渐变（近=亮红，远=暗红）
        local distFade = math.max(0.4, 1.0 - enemy.dist / 300)
        local alpha = math.floor(200 * distFade)

        -- 绘制三角箭头（朝外）
        local angle = math.atan(ndy, ndx)
        local tipX = ax + math.cos(angle) * arrowSize
        local tipY = ay + math.sin(angle) * arrowSize
        local baseX1 = ax + math.cos(angle + 2.5) * arrowSize
        local baseY1 = ay + math.sin(angle + 2.5) * arrowSize
        local baseX2 = ax + math.cos(angle - 2.5) * arrowSize
        local baseY2 = ay + math.sin(angle - 2.5) * arrowSize

        nvgBeginPath(vg_)
        nvgMoveTo(vg_, tipX, tipY)
        nvgLineTo(vg_, baseX1, baseY1)
        nvgLineTo(vg_, baseX2, baseY2)
        nvgClosePath(vg_)
        nvgFillColor(vg_, nvgRGBA(255, 80, 60, alpha))
        nvgFill(vg_)

        ::continue::
    end
end

--- 绘制锁定 UI（在 NanoVG 渲染中调用）
---@param w number 屏幕逻辑宽度
---@param h number 屏幕逻辑高度
function DrawLockOnUI(w, h)
    for _, enemy in ipairs(enemies_) do
        if enemy.lockValue <= 0 then goto continue end

        local sx = enemy.screenX * w
        local sy = enemy.screenY * h
        local dist = enemy.dist

        -- 圆形半径自适应敌人屏幕投影大小
        local radius = enemy.screenSize

        local progress = enemy.lockValue / LOCK_MAX
        local locked = enemy.locked
        local isPrimary = enemy.isPrimary

        -- 颜色：锁定中青色，锁定完成红色
        local cr, cg, cb
        if locked then
            cr, cg, cb = 255, 40, 40
        else
            cr, cg, cb = 40, 200, 255
        end

        -- 线宽和字号随半径缩放（统一粗细）
        local baseStroke = math.max(1, radius * 0.03)
        local arcStroke = math.max(1.2, radius * 0.04)
        local fontSize = math.max(10, radius * 0.25)

        -- 外圈底环（半透明）
        nvgBeginPath(vg_)
        nvgCircle(vg_, sx, sy, radius)
        nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, 50))
        nvgStrokeWidth(vg_, baseStroke)
        nvgStroke(vg_)

        -- 进度弧线（从顶部顺时针）
        if progress > 0.01 then
            local startAngle = -math.pi / 2
            local endAngle = startAngle + math.pi * 2 * progress
            nvgBeginPath(vg_)
            nvgArc(vg_, sx, sy, radius, startAngle, endAngle, NVG_CW)
            nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, 220))
            nvgStrokeWidth(vg_, arcStroke)
            nvgStroke(vg_)
        end

        -- 主要目标：对角瞄准框装饰（旋转 45°，线段自身旋转 90°）
        if isPrimary then
            local tickLen = radius * 0.25
            local gap = radius + baseStroke * 2
            local s45 = 0.7071
            local gd = gap * s45
            local t1x, t1y = tickLen * s45, tickLen * s45

            nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, 200))
            nvgStrokeWidth(vg_, baseStroke)
            -- 右上 /
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, sx + gd - t1x, sy - gd + t1y)
            nvgLineTo(vg_, sx + gd + t1x, sy - gd - t1y)
            nvgStroke(vg_)
            -- 左下 /
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, sx - gd - t1x, sy + gd + t1y)
            nvgLineTo(vg_, sx - gd + t1x, sy + gd - t1y)
            nvgStroke(vg_)
            -- 左上 \
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, sx - gd - t1x, sy - gd - t1y)
            nvgLineTo(vg_, sx - gd + t1x, sy - gd + t1y)
            nvgStroke(vg_)
            -- 右下 \
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, sx + gd - t1x, sy + gd - t1y)
            nvgLineTo(vg_, sx + gd + t1x, sy + gd + t1y)
            nvgStroke(vg_)
        end

        -- 飞弹多目标锁定标记：在已被飞弹锁定的目标上显示导弹图标
        -- 右肩锁定标记（左侧菱形）
        if missileLockR_ then
            local missileCount = 0
            for _, t in ipairs(missileLockTargetsR_) do
                if t.enemy == enemy then missileCount = missileCount + 1 end
            end
            if missileCount > 0 then
                local mkSize = math.max(8, radius * 0.2)
                nvgBeginPath(vg_)
                nvgMoveTo(vg_, sx - radius - mkSize * 2, sy - mkSize)
                nvgLineTo(vg_, sx - radius - mkSize, sy)
                nvgLineTo(vg_, sx - radius - mkSize * 2, sy + mkSize)
                nvgLineTo(vg_, sx - radius - mkSize * 3, sy)
                nvgClosePath(vg_)
                nvgFillColor(vg_, nvgRGBA(255, 200, 40, 220))
                nvgFill(vg_)

                nvgFontFace(vg_, "sans")
                nvgFontSize(vg_, math.max(10, mkSize * 1.5))
                nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg_, nvgRGBA(255, 200, 40, 255))
                nvgText(vg_, sx - radius - mkSize * 2, sy + mkSize * 2,
                    string.format("SR x%d", missileCount))
            end
        end
        -- 左肩锁定标记（右侧菱形）
        if missileLockL_ then
            local missileCount = 0
            for _, t in ipairs(missileLockTargetsL_) do
                if t.enemy == enemy then missileCount = missileCount + 1 end
            end
            if missileCount > 0 then
                local mkSize = math.max(8, radius * 0.2)
                nvgBeginPath(vg_)
                nvgMoveTo(vg_, sx + radius + mkSize * 2, sy - mkSize)
                nvgLineTo(vg_, sx + radius + mkSize * 3, sy)
                nvgLineTo(vg_, sx + radius + mkSize * 2, sy + mkSize)
                nvgLineTo(vg_, sx + radius + mkSize, sy)
                nvgClosePath(vg_)
                nvgFillColor(vg_, nvgRGBA(100, 200, 255, 220))
                nvgFill(vg_)

                nvgFontFace(vg_, "sans")
                nvgFontSize(vg_, math.max(10, mkSize * 1.5))
                nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg_, nvgRGBA(100, 200, 255, 255))
                nvgText(vg_, sx + radius + mkSize * 2, sy + mkSize * 2,
                    string.format("SL x%d", missileCount))
            end
        end

        -- 距离文字
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, fontSize)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg_, nvgRGBA(cr, cg, cb, 180))
        nvgText(vg_, sx, sy + radius + fontSize * 0.3, string.format("%dm", math.floor(dist)))

        -- 精英标记 / 叛军类型标签
        if enemy == elite_ then
            nvgFontSize(vg_, math.max(11, fontSize * 0.8))
            nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg_, nvgRGBA(255, 200, 40, 220))
            nvgText(vg_, sx, sy - radius - fontSize * 0.2, "ELITE")
        elseif enemy.rebelType then
            local label = enemy.rebelType == "tank" and "TANK" or "HELI"
            nvgFontSize(vg_, math.max(10, fontSize * 0.7))
            nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg_, nvgRGBA(255, 120, 60, 200))
            nvgText(vg_, sx, sy - radius - fontSize * 0.2, label)
        elseif enemy.meleeType then
            nvgFontSize(vg_, math.max(10, fontSize * 0.7))
            nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg_, nvgRGBA(255, 60, 60, 220))
            nvgText(vg_, sx, sy - radius - fontSize * 0.2, "MELEE")
        end

        ::continue::
    end

    -- 飞弹锁定模式全局提示
    if missileLockR_ or missileLockL_ then
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, 16)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local yOff = 40
        if missileLockR_ then
            nvgFillColor(vg_, nvgRGBA(255, 200, 40, 220))
            nvgText(vg_, w / 2, yOff,
                string.format("SR LOCK %d/%d - Release E to fire",
                    #missileLockTargetsR_, missileLockMaxR_))
            yOff = yOff + 20
        end
        if missileLockL_ then
            nvgFillColor(vg_, nvgRGBA(100, 200, 255, 220))
            nvgText(vg_, w / 2, yOff,
                string.format("SL LOCK %d/%d - Release Q to fire",
                    #missileLockTargetsL_, missileLockMaxL_))
        end
    end
end

-- ============================================================================
-- NanoVG HUD 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if gameState_ ~= GAME_STATE_PLAYING then return end
    if vg_ == nil then return end

    local dpr = graphics:GetDPR()
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    nvgBeginFrame(vg_, w, h, dpr)

    if not exitDialog_ then
        DrawPlayerHPBar(w, h)
        DrawEnergyBar(w, h)
        DrawBoostIndicator(w, h)
        DrawAmmoHUD(w, h)
        DrawTacticalPanel(w, h)
        DrawInstructions(w)
        DrawLockOnUI(w, h)
        DrawOffScreenIndicators(w, h)
        DrawExitButton(w, h)
        if rebellionState_ then DrawRebellionHUD(w, h) end
    end

    nvgEndFrame(vg_)
end

--- 绘制玩家生命值条（左上角）
function DrawPlayerHPBar(w, h)
    local shortSide = math.min(w, h)
    local barW = shortSide * 0.3
    local barH = shortSide * 0.016
    local barX = (w - barW) / 2
    local barY = h - shortSide * 0.08
    local pct = playerHp_ / playerMaxHp_

    -- 外框背景
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX - 2, barY - 2, barW + 4, barH + 4, 5)
    nvgFillColor(vg_, nvgRGBA(10, 10, 20, 170))
    nvgFill(vg_)

    -- 边框
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX - 1, barY - 1, barW + 2, barH + 2, 4)
    nvgStrokeColor(vg_, nvgRGBA(180, 60, 60, 160))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)

    -- 填充（绿→红渐变）
    if pct > 0.005 then
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, barX, barY, barW * pct, barH, 3)
        local cr = math.floor(255 * (1.0 - pct))
        local cg = math.floor(200 * pct)
        local grad = nvgLinearGradient(vg_, barX, barY, barX + barW * pct, barY,
            nvgRGBA(cr, cg + 40, 30, 230), nvgRGBA(cr + 20, cg, 20, 230))
        nvgFillPaint(vg_, grad)
        nvgFill(vg_)
    end

    -- HP 数值文字
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, shortSide * 0.013)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(220, 220, 240, 210))
    nvgText(vg_, barX + barW / 2, barY + barH / 2,
        string.format("HP  %d / %d", math.max(0, math.floor(playerHp_)), playerMaxHp_))


end

--- 绘制能量条
function DrawEnergyBar(w, h)
    local shortSide = math.min(w, h)
    local barW = shortSide * 0.3
    local barH = shortSide * 0.018
    local barX = (w - barW) / 2
    local barY = h - shortSide * 0.05
    local pct = energy_ / MAX_ENERGY

    -- 外框背景
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX - 2, barY - 2, barW + 4, barH + 4, 6)
    nvgFillColor(vg_, nvgRGBA(10, 10, 20, 170))
    nvgFill(vg_)

    -- 边框
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX - 1, barY - 1, barW + 2, barH + 2, 5)
    nvgStrokeColor(vg_, nvgRGBA(70, 110, 170, 160))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)

    -- 填充
    if pct > 0.005 then
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, barX, barY, barW * pct, barH, 4)
        if isBoosting_ then
            local grad = nvgLinearGradient(vg_, barX, barY, barX + barW * pct, barY,
                nvgRGBA(255, 180, 40, 240), nvgRGBA(255, 90, 20, 240))
            nvgFillPaint(vg_, grad)
        else
            local grad = nvgLinearGradient(vg_, barX, barY, barX + barW * pct, barY,
                nvgRGBA(40, 160, 255, 230), nvgRGBA(80, 210, 255, 230))
            nvgFillPaint(vg_, grad)
        end
        nvgFill(vg_)
    end

    -- 能量数值文字
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, shortSide * 0.013)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(220, 235, 255, 210))
    nvgText(vg_, w / 2, barY + barH / 2,
        string.format("ENERGY  %d / %d", math.floor(energy_), MAX_ENERGY))

    -- 能量不足警告
    if energy_ < JUMP_COST then
        nvgFontSize(vg_, shortSide * 0.012)
        nvgFillColor(vg_, nvgRGBA(255, 80, 60, 200))
        nvgText(vg_, w / 2, barY + barH + shortSide * 0.014, "ENERGY LOW")
    end
end

--- 绘制推进/冲刺状态指示
function DrawBoostIndicator(w, h)
    local shortSide = math.min(w, h)
    local barY = h - shortSide * 0.08
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, shortSide * 0.016)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

    if isJetting_ then
        nvgFillColor(vg_, nvgRGBA(60, 200, 255, 240))
        nvgText(vg_, w / 2, barY - shortSide * 0.008, ">>> JET <<<")
    elseif isDashing_ then
        nvgFillColor(vg_, nvgRGBA(100, 255, 180, 230))
        nvgText(vg_, w / 2, barY - shortSide * 0.008, ">>> DASH <<<")
    elseif isBoosting_ then
        nvgFillColor(vg_, nvgRGBA(255, 180, 40, 230))
        nvgText(vg_, w / 2, barY - shortSide * 0.008, ">>> BOOST <<<")
    end

    -- 冲刺冷却指示
    local cdRemain = DASH_COOLDOWN - (time.elapsedTime - lastDashTime_)
    if cdRemain > 0 and not isDashing_ then
        nvgFontSize(vg_, shortSide * 0.012)
        nvgFillColor(vg_, nvgRGBA(180, 180, 200, 150))
        nvgText(vg_, w / 2, barY - shortSide * 0.024, string.format("DASH CD %.1fs", cdRemain))
    end

    -- 喷射冷却指示
    if jetCooldownTimer_ > 0 and not isJetting_ then
        nvgFontSize(vg_, shortSide * 0.012)
        nvgFillColor(vg_, nvgRGBA(60, 180, 255, 180))
        nvgText(vg_, w / 2, barY - shortSide * 0.042, string.format("JET CD %.1fs", jetCooldownTimer_))
    end

    -- 电磁炮蓄力进度已移至弹药弧线HUD中显示

    -- 护盾状态
    local shieldStatus = ShieldSystem.GetStatus()
    if shieldStatus then
        local sBarW = shortSide * 0.12
        local sBarH = shortSide * 0.008
        local sX = w / 2 - sBarW / 2
        local sY = barY - shortSide * 0.085
        local sPct = 1.0 - shieldStatus.progress  -- 剩余时间

        -- 背景
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, sX - 1, sY - 1, sBarW + 2, sBarH + 2, 3)
        nvgFillColor(vg_, nvgRGBA(10, 10, 30, 170))
        nvgFill(vg_)

        -- 填充（青色）
        if sPct > 0.01 then
            nvgBeginPath(vg_)
            nvgRoundedRect(vg_, sX, sY, sBarW * sPct, sBarH, 2)
            nvgFillColor(vg_, nvgRGBA(40, 180, 255, 220))
            nvgFill(vg_)
        end

        -- 标签
        nvgFontSize(vg_, shortSide * 0.011)
        nvgFillColor(vg_, nvgRGBA(80, 200, 255, 220))
        local absorbRemain = shieldStatus.maxAbsorb - shieldStatus.absorbed
        nvgText(vg_, w / 2, sY - shortSide * 0.006,
            string.format("SHIELD %d HP", math.floor(absorbRemain)))
    end
end

--- 绘制弧形弹药 HUD（屏幕中央准星周围）
--- 4 段弧线: 上方=手部武器, 下方=肩部武器
--- 白色=可射击(弹药比例), 红色=换弹中(装填进度，从下往上填充)
function DrawAmmoHUD(w, h)
    local shortSide = math.min(w, h)
    -- 目标中心：对齐主目标屏幕位置，无目标时回退到屏幕中心
    local targetCx, targetCy = w / 2, h / 2
    for _, enemy in ipairs(enemies_) do
        if enemy.isPrimary and enemy.lockValue > 0 then
            targetCx = enemy.screenX * w
            targetCy = enemy.screenY * h
            break
        end
    end

    -- 缓动插值（指数衰减）
    if ammoHudCx_ == nil then
        ammoHudCx_ = targetCx
        ammoHudCy_ = targetCy
    else
        local speed = 8.0
        local dt = lastDt_
        local t = 1.0 - math.exp(-speed * dt)
        ammoHudCx_ = ammoHudCx_ + (targetCx - ammoHudCx_) * t
        ammoHudCy_ = ammoHudCy_ + (targetCy - ammoHudCy_) * t
    end
    local cx, cy = ammoHudCx_, ammoHudCy_
    local innerRadius = h * 0.15     -- 内层半径（手部武器）
    local outerRadius = h * 0.19     -- 外层半径（肩部武器）
    local strokeW = math.max(6, h * 0.008)
    -- 角度定义（以上方0°顺时针计算，转换为NanoVG: NVG = user - 90°）
    -- 右侧: 用户135°→90° = NanoVG 45°→0°（从下向上填充）
    -- 左侧: 用户225°→270° = NanoVG 135°→180°（从上向下填充）
    local arcs = {
        -- 内层左 (左手武器): 225°→270°
        { start = math.rad(135), fin = math.rad(180), weapon = playerWeapons_ and playerWeapons_.handL,     radius = innerRadius, fromEnd = false },
        -- 内层右 (右手武器): 135°→90°
        { start = math.rad(0),   fin = math.rad(45),  weapon = playerWeapons_ and playerWeapons_.handR,     radius = innerRadius, fromEnd = true },
        -- 外层左 (左肩武器): 225°→270°
        { start = math.rad(135), fin = math.rad(180), weapon = playerWeapons_ and playerWeapons_.shoulderL, radius = outerRadius, fromEnd = false, isLeftShoulder = true },
        -- 外层右 (右肩武器): 135°→90°
        { start = math.rad(0),   fin = math.rad(45),  weapon = playerWeapons_ and playerWeapons_.shoulderR, radius = outerRadius, fromEnd = true },
    }

    nvgLineCap(vg_, NVG_ROUND)

    -- 内圈底层完整圆环（1像素）
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, innerRadius)
    nvgStrokeColor(vg_, nvgRGBA(220, 235, 255, 40))
    nvgStrokeWidth(vg_, 1.0)
    nvgStroke(vg_)

    -- 计算玩家与主目标的距离（用于超射程变暗）
    local targetDist = math.huge
    if mechNode_ then
        local playerPos = mechNode_.worldPosition
        for _, enemy in ipairs(enemies_) do
            if enemy.isPrimary and enemy.lockValue > 0 and enemy.node then
                targetDist = (enemy.node.worldPosition - playerPos):Length()
                break
            end
        end
    end

    for _, arc in ipairs(arcs) do
        local weapon = arc.weapon
        if not weapon then goto continue end

        -- 判断是否超出武器射程
        local outOfRange = false
        if weapon.def and targetDist < math.huge then
            local maxRange = weapon.def.bulletSpeed * weapon.def.bulletLife
            if targetDist > maxRange then
                outOfRange = true
            end
        end

        local span = arc.fin - arc.start
        local progress, cr, cg, cb

        -- 判断是否为电磁炮蓄力中
        local isRailgunCharging = (railgunCharging_ and weapon == (playerWeapons_ and playerWeapons_.shoulderR))
            or (railgunChargingL_ and weapon == (playerWeapons_ and playerWeapons_.shoulderL))

        if isRailgunCharging then
            -- 蓄力中: 蓝色, 进度 = 蓄力完成度
            if arc.isLeftShoulder then
                progress = math.min(1.0, railgunChargeTimerL_ / railgunChargeTimeL_)
            else
                progress = math.min(1.0, railgunChargeTimer_ / railgunChargeTime_)
            end
            cr, cg, cb = 80, 160, 255
        elseif weapon.reloading then
            -- 换弹中: 红色, 进度 = 装填完成度
            progress = 1.0 - (weapon.reloadTimer / weapon.reloadTime)
            cr, cg, cb = 255, 165, 30
        else
            -- 可射击: 白色, 进度 = 剩余弹药比例
            progress = weapon.ammo / weapon.magazineSize
            cr, cg, cb = 220, 235, 255
        end

        -- 超出射程时整体变暗（透明度衰减）
        local alphaScale = 1.0
        if outOfRange then
            alphaScale = 0.25
        end

        local r = arc.radius

        -- 背景弧（暗色轮廓）
        nvgBeginPath(vg_)
        nvgArc(vg_, cx, cy, r, arc.start, arc.fin, NVG_CW)
        nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, math.floor(20 * alphaScale)))
        nvgStrokeWidth(vg_, strokeW)
        nvgStroke(vg_)

        -- 填充弧（从底部向上）
        if progress > 0.01 then
            local fillStart, fillEnd
            if arc.fromEnd then
                fillStart = arc.fin - span * progress
                fillEnd = arc.fin
            else
                fillStart = arc.start
                fillEnd = arc.start + span * progress
            end

            nvgBeginPath(vg_)
            nvgArc(vg_, cx, cy, r, fillStart, fillEnd, NVG_CW)
            if isRailgunCharging then
                -- 蓄力弧线: 蓝色渐变发光效果
                local chargeAlpha = math.floor((200 + 55 * progress) * alphaScale)
                nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, chargeAlpha))
                nvgStrokeWidth(vg_, strokeW * (1.0 + 0.5 * progress))
            else
                nvgStrokeColor(vg_, nvgRGBA(cr, cg, cb, math.floor(168 * alphaScale)))
                nvgStrokeWidth(vg_, strokeW)
            end
            nvgStroke(vg_)
        end

        -- 蓄力百分比文字（仅电磁炮蓄力时）
        if isRailgunCharging then
            nvgFontSize(vg_, shortSide * 0.012)
            nvgFillColor(vg_, nvgRGBA(120, 200, 255, math.floor(220 * alphaScale)))
            nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labelX = cx + r * math.cos(arc.fin) + strokeW * 2
            local labelY = cy + r * math.sin(arc.fin)
            nvgText(vg_, labelX, labelY, string.format("%d%%", math.floor(progress * 100)))
        end

        ::continue::
    end

    -- 主目标生命值弧线（上方120°，外层之外）
    local primaryEnemy = nil
    for _, enemy in ipairs(enemies_) do
        if enemy.isPrimary and enemy.lockValue > 0 then
            primaryEnemy = enemy
            break
        end
    end
    if primaryEnemy then
        local hpRatio = primaryEnemy.hp / primaryEnemy.maxHp
        local hpRadius = innerRadius  -- 与内层武器弧对齐
        local hpSpan = math.rad(60)
        local hpStart = math.rad(-90) - hpSpan / 2   -- 上方居中
        local hpEnd = math.rad(-90) + hpSpan / 2

        -- 颜色插值: 淡绿(120,230,120) → 红(255,50,30)
        local hr = math.floor(120 + (255 - 120) * (1.0 - hpRatio))
        local hg = math.floor(230 + (50 - 230) * (1.0 - hpRatio))
        local hb = math.floor(120 + (30 - 120) * (1.0 - hpRatio))

        -- 背景弧
        nvgBeginPath(vg_)
        nvgArc(vg_, cx, cy, hpRadius, hpStart, hpEnd, NVG_CW)
        nvgStrokeColor(vg_, nvgRGBA(hr, hg, hb, 20))
        nvgStrokeWidth(vg_, strokeW)
        nvgStroke(vg_)

        -- 填充弧（从两端向中心收缩 = 从中心向两端展开）
        if hpRatio > 0.01 then
            local fillHalf = hpSpan * hpRatio / 2
            local center = math.rad(-90)
            nvgBeginPath(vg_)
            nvgArc(vg_, cx, cy, hpRadius, center - fillHalf, center + fillHalf, NVG_CW)
            nvgStrokeColor(vg_, nvgRGBA(hr, hg, hb, 180))
            nvgStrokeWidth(vg_, strokeW)
            nvgStroke(vg_)
        end
    end

    -- 中央准星小十字
    local crossSize = 4
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, cx - crossSize, cy)
    nvgLineTo(vg_, cx + crossSize, cy)
    nvgMoveTo(vg_, cx, cy - crossSize)
    nvgLineTo(vg_, cx, cy + crossSize)
    nvgStrokeColor(vg_, nvgRGBA(200, 220, 255, 96))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)
end

--- 绘制左侧战术信息面板（科幻风格）
function DrawTacticalPanel(w, h)
    if not mechNode_ then return end

    local shortSide = math.min(w, h)
    -- 面板尺寸 & 位置（退出按钮下方）
    local panelW = shortSide * 0.22
    local panelH = shortSide * 0.38
    local px = shortSide * 0.02
    local py = 62  -- 退出按钮(12+40)下方留 10px 间距

    -- 斜切角大小
    local cut = 8

    -- ── 背景面板（带斜切角） ──
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, px + cut, py)
    nvgLineTo(vg_, px + panelW, py)
    nvgLineTo(vg_, px + panelW, py + panelH - cut)
    nvgLineTo(vg_, px + panelW - cut, py + panelH)
    nvgLineTo(vg_, px, py + panelH)
    nvgLineTo(vg_, px, py + cut)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(5, 12, 25, 140))
    nvgFill(vg_)

    -- 边框（青色）
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, px + cut, py)
    nvgLineTo(vg_, px + panelW, py)
    nvgLineTo(vg_, px + panelW, py + panelH - cut)
    nvgLineTo(vg_, px + panelW - cut, py + panelH)
    nvgLineTo(vg_, px, py + panelH)
    nvgLineTo(vg_, px, py + cut)
    nvgClosePath(vg_)
    nvgStrokeColor(vg_, nvgRGBA(60, 180, 220, 90))
    nvgStrokeWidth(vg_, 1.0)
    nvgStroke(vg_)

    -- 左上角高亮短线装饰
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, px, py + cut)
    nvgLineTo(vg_, px + cut, py)
    nvgLineTo(vg_, px + cut + panelW * 0.3, py)
    nvgStrokeColor(vg_, nvgRGBA(80, 210, 255, 180))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)

    -- 右下角高亮短线装饰
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, px + panelW, py + panelH - cut)
    nvgLineTo(vg_, px + panelW - cut, py + panelH)
    nvgLineTo(vg_, px + panelW - cut - panelW * 0.25, py + panelH)
    nvgStrokeColor(vg_, nvgRGBA(80, 210, 255, 180))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)

    -- ── 标题栏 ──
    local titleY = py + 6
    local titleH = shortSide * 0.026
    -- 标题底部分隔线
    local sepY = titleY + titleH + 4
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, px + 6, sepY)
    nvgLineTo(vg_, px + panelW - 6, sepY)
    nvgStrokeColor(vg_, nvgRGBA(60, 180, 220, 70))
    nvgStrokeWidth(vg_, 0.8)
    nvgStroke(vg_)
    -- 标题左侧小菱形图标
    local iconX = px + 12
    local iconY = titleY + titleH * 0.5
    local iconR = titleH * 0.18
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, iconX, iconY - iconR)
    nvgLineTo(vg_, iconX + iconR, iconY)
    nvgLineTo(vg_, iconX, iconY + iconR)
    nvgLineTo(vg_, iconX - iconR, iconY)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(80, 220, 255, 200))
    nvgFill(vg_)
    -- 标题文字
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, titleH)
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(140, 220, 255, 220))
    nvgText(vg_, iconX + iconR + 6, iconY, "TACTICAL DATA")

    -- ── 数据区 ──
    local pos = mechNode_.worldPosition
    local yaw = 0
    if character_ then yaw = character_.controls.yaw end
    -- 归一化到 0~360
    yaw = yaw % 360
    if yaw < 0 then yaw = yaw + 360 end

    -- 敌人数量
    local enemyCount = 0
    for _, e in ipairs(enemies_) do
        if e.hp and e.hp > 0 then
            enemyCount = enemyCount + 1
        end
    end

    -- 方向标签
    local function YawToCompass(deg)
        -- 0=N, 90=E, 180=S, 270=W
        local dirs = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                       "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" }
        local idx = math.floor((deg + 11.25) / 22.5) % 16 + 1
        return dirs[idx]
    end

    local labelSize = shortSide * 0.017
    local valueSize = shortSide * 0.024
    local rowH = shortSide * 0.055
    local dataX = px + 14
    local dataValX = px + panelW - 12
    local startY = sepY + rowH * 0.55

    local rows = {
        { label = "COORD S/N", value = string.format("%.1f / %.1f", pos.x, pos.z) },
        { label = "ALTITUDE",  value = string.format("%.1f m", pos.y) },
        { label = "HEADING",   value = string.format("%03.0f\xC2\xB0 %s", yaw, YawToCompass(yaw)) },
        { label = "HOSTILES",  value = tostring(enemyCount), alert = enemyCount > 0 },
    }

    for i, row in ipairs(rows) do
        local ry = startY + (i - 1) * rowH

        -- 行分隔点线（非首行）
        if i > 1 then
            nvgBeginPath(vg_)
            local dotY = ry - rowH * 0.22
            local dotStart = dataX
            local dotEnd = px + panelW - 12
            local dotStep = 4
            for dx = dotStart, dotEnd, dotStep do
                nvgRect(vg_, dx, dotY, 1.5, 0.5)
            end
            nvgFillColor(vg_, nvgRGBA(60, 160, 200, 50))
            nvgFill(vg_)
        end

        -- 标签
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, labelSize)
        nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg_, nvgRGBA(80, 160, 200, 160))
        nvgText(vg_, dataX, ry, row.label)

        -- 数值
        nvgFontSize(vg_, valueSize)
        nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if row.alert then
            -- 敌人数 > 0 时脉冲闪烁
            local pulse = math.floor(math.abs(math.sin(os.clock() * 3.0)) * 80 + 175)
            nvgFillColor(vg_, nvgRGBA(255, 80, 60, pulse))
        else
            nvgFillColor(vg_, nvgRGBA(200, 240, 255, 220))
        end
        nvgText(vg_, dataValX, ry, row.value)
    end

    -- ── 底部扫描线动画装饰 ──
    local scanLineY = py + panelH - 22
    local scanPhase = (os.clock() * 0.3) % 1.0  -- 0~1 循环
    local scanX = px + 6 + (panelW - 12) * scanPhase
    local scanGradW = panelW * 0.15
    nvgBeginPath(vg_)
    nvgRect(vg_, px + 6, scanLineY, panelW - 12, 1)
    nvgFillColor(vg_, nvgRGBA(40, 140, 180, 30))
    nvgFill(vg_)
    -- 扫描亮点
    nvgBeginPath(vg_)
    nvgRect(vg_, scanX - scanGradW * 0.5, scanLineY, scanGradW, 1)
    nvgFillColor(vg_, nvgRGBA(80, 220, 255, 120))
    nvgFill(vg_)

    -- 底部状态文字
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, shortSide * 0.013)
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg_, nvgRGBA(60, 160, 200, 100))
    nvgText(vg_, px + 8, scanLineY + 4, "SYS ONLINE")
    -- 右侧闪烁圆点
    local dotAlpha = math.floor(math.abs(math.sin(os.clock() * 2.0)) * 140 + 60)
    nvgBeginPath(vg_)
    nvgCircle(vg_, px + panelW - 14, scanLineY + 10, 3)
    nvgFillColor(vg_, nvgRGBA(60, 220, 180, dotAlpha))
    nvgFill(vg_)
end

--- 绘制操作提示
function DrawInstructions(w)
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, 12)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg_, nvgRGBA(200, 220, 255, 140))
    nvgText(vg_, w / 2, 8, "WASD: 移动 | 鼠标: 视角 | Space: 跳跃/推进 | Shift: 冲刺 | C: 喷射 | T: 测试死亡")
end

--- 绘制左上角退出按钮
function DrawExitButton(w, h)
    if exitDialog_ then return end  -- 弹窗已显示时不画按钮

    local btnW = 40
    local btnH = 40
    local margin = 12
    local bx = margin
    local by = margin

    -- 保存按钮区域（逻辑坐标）
    exitBtnRect_.x = bx
    exitBtnRect_.y = by
    exitBtnRect_.w = btnW
    exitBtnRect_.h = btnH

    -- 半透明背景
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, bx, by, btnW, btnH, 6)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg_)

    -- 边框
    nvgStrokeColor(vg_, nvgRGBA(180, 190, 220, 120))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)

    -- X 图标
    local cx = bx + btnW / 2
    local cy = by + btnH / 2
    local iconSize = 8
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, cx - iconSize, cy - iconSize)
    nvgLineTo(vg_, cx + iconSize, cy + iconSize)
    nvgMoveTo(vg_, cx + iconSize, cy - iconSize)
    nvgLineTo(vg_, cx - iconSize, cy + iconSize)
    nvgStrokeColor(vg_, nvgRGBA(220, 225, 240, 220))
    nvgStrokeWidth(vg_, 2.5)
    nvgStroke(vg_)
end

--- 叛军关卡波次进度 HUD（右上角）
function DrawRebellionHUD(w, h)
    local st = rebellionState_
    if not st then return end

    local panelW = 160
    local panelH = 70
    local px = w - panelW - 12
    local py = 60

    -- 半透明背景面板
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, px, py, panelW, panelH, 6)
    nvgFillColor(vg_, nvgRGBA(10, 10, 20, 160))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBA(255, 120, 60, 120))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)

    -- 标题
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, 13)
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg_, nvgRGBA(255, 180, 80, 230))
    local waveLabel
    if st.isContinuous then
        waveLabel = "SUPPRESSION"
    else
        waveLabel = string.format("WAVE %d / %d", st.currentWave or 0, st.totalWaves or 0)
    end
    nvgText(vg_, px + 8, py + 6, waveLabel)

    -- 击杀进度
    nvgFontSize(vg_, 12)
    nvgFillColor(vg_, nvgRGBA(220, 220, 230, 200))
    local killTarget = st.killsToWin or st.totalToSpawn
    local killLabel = string.format("击杀: %d / %d", st.totalKills, killTarget)
    nvgText(vg_, px + 8, py + 24, killLabel)

    -- 击杀进度条
    local barX = px + 8
    local barY = py + 42
    local barW = panelW - 16
    local barH = 6
    local pct = killTarget > 0 and (st.totalKills / killTarget) or 0

    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX, barY, barW, barH, 3)
    nvgFillColor(vg_, nvgRGBA(40, 40, 50, 180))
    nvgFill(vg_)

    if pct > 0.005 then
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, barX, barY, barW * pct, barH, 3)
        nvgFillColor(vg_, nvgRGBA(255, 140, 50, 230))
        nvgFill(vg_)
    end

    -- 存活敌人数量
    local aliveCount = 0
    for _, e in ipairs(enemies_) do
        if e.rebelType and not e.dead then aliveCount = aliveCount + 1 end
    end
    nvgFontSize(vg_, 11)
    nvgFillColor(vg_, nvgRGBA(180, 190, 210, 180))
    nvgText(vg_, px + 8, py + 54, string.format("场上: %d", aliveCount))
end
