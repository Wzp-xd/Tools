--[[
================================================================================
main.lua 模块化拆分方案
================================================================================

编写日期: 2026-02-28
当前状态: main.lua 共 4657 行，远超 1500 行拆分阈值

================================================================================
一、现状分析
================================================================================

main.lua 当前承担了以下 10 个职责：

  区块                         行范围           行数    职责说明
  ─────────────────────────────────────────────────────────────────
  常量 + 全局变量               L47-276          230    配置映射、全部状态变量
  材质辅助函数                  L277-338          60    CreatePBRMat / CreateBoxPart / CreateStaticBox
  生命周期 / 菜单流程           L339-804         464    ShowMainMenu / ShowVictoryDialog / ShowDeathDialog
                                                       ShowExitDialog / ReturnToMenu / StartGame / Start / Stop
  场景创建                      L805-899          89    CreateScene（灯光、相机、天空盒）
  机甲创建                      L900-975          76    CreateMech（构建 + 动画 + 武器挂载）
  环境                          L976-1249        276    CreateEnvironment / CreateClouds / CreateDecorations
                                                       CreateBarriers
  敌人创建                      L1250-1406       151    SpawnEnemy / SpawnStaticVehicle / CreateEnemies
  HUD 创建                     L1407-1600        196    CreateGameHUD（UI 按钮布局）
  冲刺 + 喷射特效              L1605-1833        225    StartDashEffect / StopDashEffect / UpdateDashEffect
                                                       CreateJetTrail / StartJetEffect / StopJetEffect
  电磁炮特效                    L1834-2291       456    RailgunFX_StartCharge / _UpdateCharge / _StopCharge
                                                       RailgunFX_Fire / RailgunFX_Hit / _UpdateFireFX
  HandleUpdate（游戏主循环）     L2320-3508      1189    输入处理、移动、跳跃、冲刺、喷射、
                                                       武器射击、敌人更新、碰撞、死亡判定...
  锁定系统 + 锁定 UI           L3556-3945       388    UpdateLockOn / DrawOffScreenIndicators / DrawLockOnUI
  NanoVG HUD 渲染              L3946-4657       712    HandleNanoVGRender / DrawPlayerHPBar / DrawEnergyBar
                                                       DrawBoostIndicator / DrawAmmoHUD / DrawTacticalPanel
                                                       DrawInstructions / DrawExitButton / DrawRebellionHUD

最大痛点：HandleUpdate 单函数 1189 行，包含至少 8 个互不相关的逻辑分支。

已有模块（共 14 个文件、10088 行）：
  config.lua(611)  weapons.lua(1280)  weapon_manager.lua(173)  shield_system.lua(172)
  mech_builder.lua(769)  mech_animator.lua(691)  elite_ai.lua(963)  rebel_ai.lua(779)
  melee_ai.lua(214)  vehicle_builder.lua(215)  armory_screen.lua(1131)
  menu.lua(885)  sound_manager.lua(250)  sound_config.lua(101)  debug_viewer.lua(970)


================================================================================
二、拆分目标
================================================================================

  1. main.lua 降至 800 行以内（仅保留 Start/Stop + 胶水逻辑）
  2. 每个新模块单一职责、接口清晰，可独立理解和修改
  3. 不改变任何运行行为，纯结构重构
  4. 模块间通过 require 返回值 + 注入参数通信，避免隐式全局变量


================================================================================
三、拆分方案（7 个新模块）
================================================================================

  新文件                   来源行范围        预估行数   职责
  ─────────────────────────────────────────────────────────────────
  game_state.lua           L83-276           ~230      游戏状态变量集中管理
  scene_builder.lua        L277-338,805-899  ~150      场景创建（灯光、天空盒、材质工具）
  environment.lua          L976-1249         ~280      竞技场、云层、装饰物、屏障
  enemy_spawner.lua        L1250-1406        ~160      敌人 / 载具生成与重生队列
  vfx_dash_jet.lua         L1605-1833        ~230      冲刺 + 喷射模式视觉特效
  railgun_fx.lua           L1834-2291        ~460      电磁炮蓄力 / 发射 / 命中特效
  hud_renderer.lua         L3556-4657        ~1100     锁定系统 + 全部 NanoVG HUD 绘制
  ─────────────────────────────────────────────────────────────────
  （合计约 2610 行从 main.lua 移出）

  main.lua 剩余内容（约 750 行）：
    - require 所有模块
    - Start() / Stop()
    - CreateMech()（76 行，与 mech_builder 强耦合，保留）
    - CreateGameHUD()（196 行，UI 按钮布局，保留或后续再拆）
    - HandleUpdate()（拆分后约 500 行：仅保留输入→调用各模块 update）
    - HandlePostUpdate() / HandlePhysicsPreStep()
    - 生命周期函数（ShowMainMenu / StartGame / ReturnToMenu 等）


================================================================================
四、各模块详细设计
================================================================================

----------------------------------------------------------------------
4.1  game_state.lua  —— 游戏状态中心
----------------------------------------------------------------------

职责：集中管理所有共享状态变量，其他模块通过 GS.xxx 读写

接口设计：
  local GS = {}

  -- 游戏阶段
  GS.MENU     = "menu"
  GS.PLAYING  = "playing"
  GS.DEBUG    = "debug"
  GS.ARMORY   = "armory"
  GS.current  = GS.MENU

  -- 核心引用
  GS.scene       = nil   ---@type Scene
  GS.tpCamera    = nil   ---@type ThirdPersonCameraInstance
  GS.mechNode    = nil   ---@type Node
  GS.kcc         = nil   ---@type KinematicCharacterController
  GS.character   = nil   ---@type CharacterComponent

  -- 能量系统
  GS.energy        = CONFIG.MaxEnergy
  GS.isBoosting    = false
  GS.jumpStartTime = 0
  GS.didJump       = false

  -- 冲刺系统
  GS.isDashing     = false
  GS.dashTimer     = 0
  GS.dashDir       = Vector3.ZERO
  GS.lastDashTime  = -999
  -- ...（其他状态变量同理迁移）

  -- 玩家
  GS.playerHp    = 3000
  GS.playerMaxHp = 3000
  GS.playerDead  = false

  -- 敌人
  GS.enemies        = {}
  GS.respawnQueue   = {}
  GS.elite          = nil
  GS.meleeEnemies   = {}
  GS.rebellionState = nil

  -- 武器
  GS.playerWeapons = nil

  -- NanoVG
  GS.vg = nil

  function GS.Reset()
    -- 重置全部游戏状态到初始值（StartGame / ReturnToMenu 时调用）
  end

  return GS

迁移来源：main.lua L83-276 全部全局变量
其他模块改动：将散落在各处的裸全局变量访问改为 GS.xxx


----------------------------------------------------------------------
4.2  scene_builder.lua  —— 场景 & 材质工具
----------------------------------------------------------------------

职责：创建基础场景（灯光 / 相机 / 天空盒）+ 通用材质工厂函数

接口设计：
  local SceneBuilder = {}

  --- 创建 PBR 材质（从 main.lua L287 迁移）
  function SceneBuilder.CreatePBRMat(color, metallic, roughness, emissive) end

  --- 创建方块部件（从 main.lua L306 迁移）
  function SceneBuilder.CreateBoxPart(parent, name, pos, scale, mat) end

  --- 创建带碰撞的静态方块（从 main.lua L323 迁移）
  function SceneBuilder.CreateStaticBox(scene, name, pos, scale, mat) end

  --- 创建基础场景（从 main.lua CreateScene L809 迁移）
  --- 包含：物理世界、灯光、天空盒
  --- 返回 scene, cameraNode
  function SceneBuilder.CreateScene() end

  return SceneBuilder

迁移来源：main.lua L277-338 + L805-899


----------------------------------------------------------------------
4.3  environment.lua  —— 竞技场环境
----------------------------------------------------------------------

职责：地面、围墙、云层、装饰物、动态屏障

接口设计：
  local Environment = {}

  --- 创建竞技场地面和围墙（从 main.lua CreateEnvironment L976 迁移）
  function Environment.Create(scene, levelConfig) end

  --- 创建云层（从 main.lua CreateClouds L1071 迁移）
  function Environment.CreateClouds(scene) end

  --- 创建装饰物（从 main.lua CreateDecorations L1139 迁移）
  function Environment.CreateDecorations(scene, levelConfig) end

  --- 创建场地屏障（从 main.lua CreateBarriers L1211 迁移）
  --- 返回 barriers 表
  function Environment.CreateBarriers(scene) end

  --- 更新屏障透明度（每帧调用，根据玩家距离渐变）
  function Environment.UpdateBarriers(barriers, playerPos, dt) end

  return Environment

迁移来源：main.lua L976-1249


----------------------------------------------------------------------
4.4  enemy_spawner.lua  —— 敌人生成管理
----------------------------------------------------------------------

职责：生成/重生普通敌人、静态载具靶标、管理出生点

接口设计：
  local EnemySpawner = {}

  -- 出生点数据（从 main.lua spawnPoints_ 迁移）
  EnemySpawner.spawnPoints = { ... }

  --- 在指定位置生成敌人（从 main.lua SpawnEnemy L1258 迁移）
  function EnemySpawner.SpawnEnemy(scene, pos, yaw) end

  --- 生成静态载具靶标（从 main.lua SpawnStaticVehicle L1299 迁移）
  function EnemySpawner.SpawnStaticVehicle(scene, pos, yaw, vehicleType) end

  --- 根据关卡配置生成全部敌人（从 main.lua CreateEnemies L1364 迁移）
  function EnemySpawner.CreateAll(scene, levelConfig, GS) end

  --- 处理重生队列（在 HandleUpdate 中调用）
  function EnemySpawner.UpdateRespawns(scene, dt, GS) end

  --- 获取随机出生点（距离玩家 50~200m）
  function EnemySpawner.RandomSpawnAroundPlayer(playerPos) end

  return EnemySpawner

迁移来源：main.lua L1250-1406


----------------------------------------------------------------------
4.5  vfx_dash_jet.lua  —— 冲刺 & 喷射视觉特效
----------------------------------------------------------------------

职责：冲刺拖尾 / 爆发动画、喷射模式双喷口拖尾

接口设计：
  local VFX = {}

  --- 冲刺特效
  function VFX.StartDash(mechJoints) end       -- L1642
  function VFX.StopDash() end                  -- L1697
  function VFX.UpdateDash(dt) end              -- L1712

  --- 喷射特效
  function VFX.StartJet(bodyNode) end          -- L1780
  function VFX.StopJet() end                   -- L1814
  function VFX.UpdateJet(dt) end               -- L1820

  return VFX

迁移来源：main.lua L1605-1833
内部状态：dashTrailNodeL/R_, dashBurstNode_, jetTrailNodeL/R_ 等全部私有化


----------------------------------------------------------------------
4.6  railgun_fx.lua  —— 电磁炮视觉特效
----------------------------------------------------------------------

职责：电磁炮蓄力光效、发射光柱/冲击波、命中电弧特效

接口设计：
  local RailgunFX = {}

  --- 开始蓄力特效（左/右肩独立）
  function RailgunFX.StartCharge(side, weaponNode) end      -- L1864

  --- 更新蓄力（每帧调用）
  function RailgunFX.UpdateCharge(dt, chargePct, side) end  -- L1940

  --- 停止蓄力
  function RailgunFX.StopCharge(side) end                   -- L2002（原前置声明）

  --- 发射瞬间特效
  function RailgunFX.Fire(targetPos, side) end              -- L2022

  --- 命中特效
  function RailgunFX.Hit(hitPos) end                        -- L2102

  --- 更新残留特效淡出（每帧调用）
  function RailgunFX.UpdateFireFX(dt) end                   -- L2190

  return RailgunFX

迁移来源：main.lua L1834-2291
内部状态：railgunFX_, railgunFXL_, railgunFireFX_, railgunHitFX_ 全部私有化


----------------------------------------------------------------------
4.7  hud_renderer.lua  —— 锁定系统 + NanoVG HUD
----------------------------------------------------------------------

职责：
  1. 锁定系统逻辑（UpdateLockOn、FindLockOnTarget）
  2. 全部 NanoVG 绘制（能量条、弹药弧、战术面板、锁定 UI 等）

接口设计：
  local HUD = {}

  --- 初始化（设置 NanoVG 句柄、字体等）
  function HUD.Init(vg) end

  --- 锁定系统
  function HUD.FindLockOnTarget(enemies, mechNode, exclude) end  -- L2299
  function HUD.UpdateLockOn(dt, GS) end                          -- L3562

  --- NanoVG 主渲染入口（绑定 NanoVGRender 事件）
  function HUD.Render(eventType, eventData, GS) end              -- L3950

  --- 各 HUD 元素（内部调用，可按需导出）
  -- HUD.DrawPlayerHPBar(w, h, GS)
  -- HUD.DrawEnergyBar(w, h, GS)
  -- HUD.DrawBoostIndicator(w, h, GS)
  -- HUD.DrawAmmoHUD(w, h, GS)
  -- HUD.DrawTacticalPanel(w, h, GS)
  -- HUD.DrawLockOnUI(w, h, GS)
  -- HUD.DrawOffScreenIndicators(w, h, GS)
  -- HUD.DrawExitButton(w, h, GS)
  -- HUD.DrawRebellionHUD(w, h, GS)
  -- HUD.DrawInstructions(w)

  return HUD

迁移来源：main.lua L3556-4657（锁定系统 + NanoVG HUD 渲染）


================================================================================
五、HandleUpdate 拆分策略
================================================================================

HandleUpdate 是最大的单函数（1189 行），拆分策略如下：

把 HandleUpdate 内部的逻辑按职责拆成子函数，保留在 main.lua 中：

  function HandleUpdate(eventType, eventData)
      if GS.current ~= GS.PLAYING or not GS.character then return end
      local dt = eventData["TimeStep"]:GetFloat()

      UpdateExitButton(dt)               -- ~30 行  退出按钮点击检测
      UpdateInput(dt)                    -- ~120 行  输入采集（WASD/鼠标/按钮状态）
      UpdateMovement(dt)                 -- ~150 行  地面移动 + 阻尼
      UpdateJumpAndBoost(dt)             -- ~100 行  跳跃 / 推进飞行
      UpdateDash(dt)                     -- ~80 行   冲刺逻辑
      UpdateJetMode(dt)                  -- ~180 行  喷射模式（C键切换 / 3D飞行）
      UpdateWeapons(dt)                  -- ~200 行  武器射击 / 蓄力 / 飞弹锁定
      UpdateEnemies(dt)                  -- ~150 行  敌人 AI / 伤害 / 死亡 / 重生
      UpdateMechAnimation(dt)            -- ~30 行   机甲动画状态
      UpdateCamera(dt)                   -- ~30 行   相机跟随
      UpdateMisc(dt)                     -- ~40 行   屏障、能量恢复、脚步声等

      VFX.UpdateDash(dt)                 -- 冲刺特效
      VFX.UpdateJet(dt)                  -- 喷射特效
      RailgunFX.UpdateFireFX(dt)         -- 电磁炮残留特效
  end

这样 HandleUpdate 本身降至约 20 行的调度代码，各子函数 30-200 行不等，
可读性大幅提升。

子函数暂时保留在 main.lua 内（作为 local function），如果后续某个
子系统继续膨胀（如 UpdateWeapons），可进一步提取为独立模块。


================================================================================
六、拆分后文件结构预览
================================================================================

  scripts/
  ├── main.lua              ~750 行   入口 + 生命周期 + HandleUpdate 调度
  ├── game_state.lua         ~230 行   共享状态变量
  ├── scene_builder.lua      ~150 行   场景创建 + 材质工具
  ├── environment.lua        ~280 行   竞技场环境
  ├── enemy_spawner.lua      ~160 行   敌人生成
  ├── vfx_dash_jet.lua       ~230 行   冲刺/喷射特效
  ├── railgun_fx.lua         ~460 行   电磁炮特效
  ├── hud_renderer.lua       ~1100 行  锁定系统 + NanoVG HUD
  │
  ├── config.lua             611 行   （已有，不变）
  ├── weapons.lua            1280 行  （已有，不变）
  ├── weapon_manager.lua     173 行   （已有，不变）
  ├── shield_system.lua      172 行   （已有，不变）
  ├── mech_builder.lua       769 行   （已有，不变）
  ├── mech_animator.lua      691 行   （已有，不变）
  ├── elite_ai.lua           963 行   （已有，不变）
  ├── rebel_ai.lua           779 行   （已有，不变）
  ├── melee_ai.lua           214 行   （已有，不变）
  ├── vehicle_builder.lua    215 行   （已有，不变）
  ├── armory_screen.lua      1131 行  （已有，不变）
  ├── menu.lua               885 行   （已有，不变）
  ├── sound_manager.lua      250 行   （已有，不变）
  ├── sound_config.lua       101 行   （已有，不变）
  ├── debug_viewer.lua       970 行   （已有，不变）
  └── weapon_defs.lua        515 行   （已有，不变）


================================================================================
七、执行顺序（按依赖关系排列）
================================================================================

  步骤   操作                     风险    说明
  ────────────────────────────────────────────────────────────────
  1     创建 game_state.lua       低     纯数据，无逻辑依赖
  2     创建 scene_builder.lua    低     独立工具函数
  3     创建 environment.lua      低     仅依赖 scene_builder
  4     创建 enemy_spawner.lua    低     仅依赖 game_state
  5     创建 vfx_dash_jet.lua     中     需要访问 mechJoints_
  6     创建 railgun_fx.lua       中     需要访问武器节点
  7     创建 hud_renderer.lua     中     需要访问大量 GS 状态
  8     拆分 HandleUpdate         高     最大改动，最后执行
  ────────────────────────────────────────────────────────────────

每一步完成后单独构建测试，确保不引入回归问题。


================================================================================
八、注意事项
================================================================================

  1. 前置声明问题
     main.lua 中 RailgunFX_StopCharge / RailgunFX_UpdateFireFX / RailgunFX_Hit
     是 local 前置声明。提取为模块后自然解决（通过 require 获取）。

  2. 全局函数引用
     ShowVictoryDialog / ShowDeathDialog / ReturnToMenu 等被 AI 模块通过
     全局函数名调用。拆分后需确保这些函数仍然暴露在全局作用域，
     或改为通过回调注入到 AI 模块。

  3. hud_renderer.lua 仍有 1100 行
     如果后续需要进一步拆分，可以按 HUD 元素类型再拆：
       hud_bars.lua       — 血条 / 能量条 / 推进指示
       hud_ammo.lua       — 弹药弧线
       hud_tactical.lua   — 战术面板
       hud_lockon.lua     — 锁定 UI + 屏幕边缘指示

  4. game_state.lua 的替代方案
     如果不喜欢中心化状态对象，也可以不创建 game_state.lua，
     而是让各模块自己持有私有状态，通过 init()/update() 参数传递。
     但这会增加 main.lua 的参数传递代码量。

================================================================================
--]]
