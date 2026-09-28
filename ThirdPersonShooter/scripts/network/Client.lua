-- ============================================================================
-- Client.lua - 多人游戏客户端逻辑
-- 处理玩家输入、动画、相机、UI渲染
-- ============================================================================

local Client = {}
local Shared = require("network.Shared")
local WeaponConfig = require "network.modules.WeaponConfig"
local WeaponAttachment = require "network.modules.WeaponAttachment"
local HitEffects = require "network.modules.HitEffects"
local Bullet = require "network.modules.Bullet"
local WeaponDebugUI = require "network.modules.WeaponDebugUI"

require "LuaScripts/Utilities/Sample"
require "LuaScripts/Utilities/Touch"
require "urhox-libs.UI.GameHUD"

-- ============================================================================
-- 变量
-- ============================================================================

local scene_ = nil
local cameraNode_ = nil
local myRoleNode_ = nil

-- 相机控制
local yaw_ = 0.0
local pitch_ = 0.0

-- 相机状态
local currentCameraDistance_ = 5.0
local currentCameraOffset_ = Vector3(0, 1.7, 0)
local currentCameraFOV_ = 45.0

-- 玩家状态
local health_ = 100
local maxHealth_ = 100
local isDead_ = false
local isAiming_ = false
local isArmed_ = true
local isCrouching_ = false
local mousePaused_ = false  -- ESC 暂停鼠标锁定

-- 武器状态
local currentWeaponId_ = nil
local weaponAttachment_ = nil
local ammoMag_ = 0
local ammoReserve_ = 0
local isReloading_ = false
local pendingReloadAnim_ = false  -- 延迟到 PostUpdate 触发换弹动画
local reloadTimer_ = 0

-- 自定义 HUD 按钮引用
local fireButton_ = nil
local fireButtonLeft_ = nil  -- 左侧辅助开火按钮
local jumpButton_ = nil
local walkButton_ = nil      -- 蹲下按钮
local runButton_ = nil        -- 走路/跑步切换按钮
local wasFireTouchPressed_ = false  -- 上帧开火按钮触摸状态（用于半自动武器边缘检测）

-- 武器选择面板
local weaponPanelOpen_ = false       -- 面板是否展开
local weaponPanelItems_ = {}         -- 面板中武器项的点击区域 {x, y, w, h, weaponId}

-- 后坐力系统（新版：向上60度扇形内随机方向，移动后回弹）
local recoilState_ = {
    currentPitch = 0,       -- 当前后坐力偏移（度，负=向上）
    currentYaw = 0,
    targetPitch = 0,        -- 目标后坐力偏移（峰值位置）
    targetYaw = 0,
    startPitch = 0,         -- 本次射击开始时的位置（用于恢复）
    startYaw = 0,
    kickPitch = 0,          -- 本次射击的跳跃量
    kickYaw = 0,
    phase = "idle",         -- "idle" | "kick" | "hold" | "recover"
    timer = 0,              -- 后坐力计时器
    kickDuration = 0.08,    -- kick 阶段持续时间
    holdTimer = 0,          -- hold 阶段计时器
    holdDuration = 0.12,    -- hold 阶段持续时间（等待下一发）
    recoverDuration = 0.30, -- recover 阶段持续时间
}

-- 准星扩散（单位：角度/度）
local crosshairSpreadDeg_ = 0
local crosshairSpreadMaxDeg_ = 10.0  -- 默认最大散布角度
local crosshairSpreadRecoveryDeg_ = WeaponConfig.SHOOTING.CrosshairRecoverySpeed or 8.0
local shotCounter_ = 0  -- 连射计数器（第1、4、7...枪0散布）

-- 准星击中反馈
local crosshairHitTimer_ = 0
local CROSSHAIR_HIT_DURATION = 0.15

-- 伤害闪红效果
local damageFlashAlpha_ = 0
local lastHealth_ = 100

-- 动画管理
local playerAnimData_ = {}
-- 其他玩家的武器附件 { [nodeId] = WeaponAttachment }
local otherWeapons_ = {}

-- 命中特效
local hitEffects_ = {}

-- 目标球恢复计时器
local targetResetTimers_ = {}

-- 射击冷却
local shootCooldown_ = 0.0

-- 测试模式（显示调试信息）
local debugMode_ = false
local debugMuzzleNode_ = nil  -- 枪口位置可视化节点

-- 第一人称枪械系统（瞄准时使用）
local fpGunNode_ = nil        -- 第一人称枪械节点（挂在 cameraNode_ 下）
local fpMuzzleNode_ = nil     -- 第一人称枪口节点
local aimTransition_ = 0      -- 瞄准过渡进度 (0=腰射, 1=完全瞄准)
local AIM_TRANSITION_SPEED = 8.0  -- 瞄准过渡速度

-- 第一人称枪械位置配置
local FP_GUN_BASE_POS = Vector3(0.25, -0.25, 0.25)   -- 腰射位置（相对相机）
local FP_GUN_ADS_POS = Vector3(0.0, -0.052, 0.25)    -- 瞄准位置（屏幕中心偏下，不遮挡准心）

-- 狙击镜状态
local scopeActive_ = false   -- 狙击镜是否完全激活（显示scope UI）
local scopeProgress_ = 0     -- 狙击镜过渡进度 (0~1)

-- NanoVG
local nvgCtx_ = nil
local fontNormal_ = -1

-- 状态
local pendingNodeId_ = 0
local pendingRoleNodes_ = {}
local needSendReady_ = false
local needBindControls_ = true
local pendingCallbacks_ = {}

-- 服务器日志
local serverLogs_ = {}          -- { {msg=string, time=number}, ... }
local SERVER_LOG_MAX = 15       -- 最多显示条数
local SERVER_LOG_DURATION = 8.0 -- 每条日志显示秒数

-- 快捷引用
local Settings = Shared.Settings
local EVENTS = Shared.EVENTS
local CTRL = Shared.CTRL
local VARS = Shared.VARS

-- ============================================================================
-- 入口
-- ============================================================================

function Client.Start()
    SampleStart()

    Shared.RegisterEvents()
    scene_ = Shared.CreateScene(false)

    SetupNanoVG()
    SetupCamera()
    SetupGameHUD()

    input.mouseMode = MM_RELATIVE

    SubscribeToEvent(EVENTS.ASSIGN_ROLE, "HandleAssignRole")
    SubscribeToEvent(EVENTS.HEALTH_UPDATE, "HandleHealthUpdate")
    SubscribeToEvent(EVENTS.PLAYER_DIED, "HandlePlayerDied")
    SubscribeToEvent(EVENTS.PLAYER_RESPAWN, "HandlePlayerRespawn")
    SubscribeToEvent(EVENTS.WEAPON_SWITCH, "HandleWeaponSwitch")
    SubscribeToEvent(EVENTS.HIT_EFFECT, "HandleHitEffect")
    SubscribeToEvent(EVENTS.BULLET_CREATE, "HandleBulletCreate")
    SubscribeToEvent(EVENTS.BULLET_HIT, "HandleBulletHit")
    SubscribeToEvent(EVENTS.TARGET_SYNC, "HandleTargetSync")
    SubscribeToEvent(EVENTS.SERVER_LOG, "HandleServerLog")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate")
    SubscribeToEvent(scene_, "NodeAdded", "HandleNodeAdded")

    -- 初始化子弹系统
    Bullet.Init(scene_)
    
    -- 初始化调试可视化
    SetupDebugVisualization()

    local serverConn = network:GetServerConnection()
    if serverConn then
        serverConn.scene = scene_
    end

    needSendReady_ = true
    print("[Client] Started")
end

function Client.Stop()
    if nvgCtx_ ~= nil then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
end

-- ============================================================================
-- 设置
-- ============================================================================

function SetupNanoVG()
    nvgCtx_ = nvgCreate(1)
    if nvgCtx_ == nil then
        print("[Client] ERROR: Failed to create NanoVG context")
        return
    end

    fontNormal_ = nvgCreateFont(nvgCtx_, "sans", "Fonts/MiSans-Regular.ttf")
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")
    
    -- 初始化武器调试UI
    WeaponDebugUI.Init(nvgCtx_, fontNormal_)
end

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera", LOCAL)
    local camera = cameraNode_:CreateComponent("Camera", LOCAL)
    camera.nearClip = 0.01
    camera.farClip = Settings.Camera.farClip
    camera.fov = Settings.Camera.normal.fov

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

function SetupDebugVisualization()
    if not debugMode_ then return end
    
    -- 创建枪口位置可视化节点（绿色小球）
    debugMuzzleNode_ = scene_:CreateChild("DebugMuzzle", LOCAL)
    debugMuzzleNode_.scale = Vector3(0.05, 0.05, 0.05)
    
    local model = debugMuzzleNode_:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 1.0, 0.2, 1.0)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.0, 2.0, 0.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(1.0))
    model:SetMaterial(mat)
    model.castShadows = false
    
    debugMuzzleNode_.enabled = false
    
    print("[Client] Debug mode enabled - showing collision boxes and muzzle position")
end

function SetupGameHUD()
    GameHUD.Initialize()

    -- 只启用摇杆，所有右侧按钮由自定义创建
    GameHUD.Create({
        enableJump = false,
        enableRun = false,
        enableShooter = false,
    })

    -- 启用准心渲染（角色始终持枪）
    GameHUD.SetArmed(true)

    -- ========== 自定义右侧按钮布局 ==========
    -- 开火键为中心，2倍大（radius=120），按住拖动可旋转镜头并持续开火
    -- 周围4个小按钮（radius=55）从左下到右上：装弹、瞄准、跳跃、步行

    local fireCX, fireCY = -250, -260  -- 开火键中心（距右下角，向左上移动）
    local smallR = 55

    -- 1) 开火按钮（2倍大，拖动旋转镜头 + 持续开火）
    -- 注意: 不设置 mouseBinding，避免移动端触摸合成鼠标事件导致误射
    -- PC 端鼠标射击由 UpdateMovement 中 input:GetMouseButtonDown(MOUSEB_LEFT) 处理
    fireButton_ = VirtualControls.CreateButton({
        position = Vector2(fireCX, fireCY),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = 120,
        label = "Fire",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {255, 100, 100},
        pressedColor = {255, 150, 150},
        on_press = function()
            if isDead_ then return end
            if not isArmed_ or isReloading_ then return end
            local data = myRoleNode_ and playerAnimData_[myRoleNode_.ID]
            if data and data.fsm then
                data.fsm:SetTrigger("shoot")
            end
        end,
    })

    -- 覆写开火按钮的触摸处理，实现拖动旋转镜头
    local origTouchBegin = getmetatable(fireButton_).__index.handleTouchBegin
    local fireTouchLastX, fireTouchLastY = 0, 0

    function fireButton_:handleTouchBegin(touchId, x, y)
        local result = origTouchBegin(self, touchId, x, y)
        if result then
            fireTouchLastX = x
            fireTouchLastY = y
        end
        return result
    end

    function fireButton_:handleTouchMove(touchId, x, y)
        if self.touchId ~= touchId then return false end
        local dx = x - fireTouchLastX
        local dy = y - fireTouchLastY
        fireTouchLastX = x
        fireTouchLastY = y
        -- 屏幕像素 → 镜头旋转（与 TouchLookArea 灵敏度一致）
        local screenH = graphics:GetHeight()
        local camera = cameraNode_ and cameraNode_:GetComponent("Camera")
        local fov = camera and camera.fov or 45.0
        local sensitivity = 2.0 * fov / screenH
        yaw_ = yaw_ + dx * sensitivity
        pitch_ = pitch_ + dy * sensitivity
        pitch_ = Shared.Clamp(pitch_, -89.0, 89.0)
        return true
    end

    -- 2) 装弹按钮（左下偏左）
    VirtualControls.CreateButton({
        position = Vector2(fireCX - 230, fireCY + 140),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "Reload",
        keyBinding = "R",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {100, 255, 100},
        pressedColor = {150, 255, 150},
        on_press = function()
            if isDead_ then return end
            if not isArmed_ or isReloading_ then return end
            local weaponCfg = GetCurrentWeaponConfig()
            if weaponCfg and ammoMag_ < weaponCfg.magSize and ammoReserve_ > 0 then
                StartReload()
            end
        end,
    })

    -- 3) 瞄准按钮（左上）
    VirtualControls.CreateButton({
        position = Vector2(fireCX - 250, fireCY - 130),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "Aim",
        toggle = true,
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {100, 150, 255},
        pressedColor = {150, 200, 255},
        on_toggle = function(toggled)
            if isDead_ then return end
            if not isArmed_ or isReloading_ then return end
            isAiming_ = toggled
            GameHUD.SetAiming(isAiming_)
        end,
    })

    -- 4) 跳跃按钮（左上偏上）
    jumpButton_ = VirtualControls.CreateButton({
        position = Vector2(fireCX - 100, fireCY - 260),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "Jump",
        keyBinding = "SPACE",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {100, 200, 255},
        pressedColor = {150, 230, 255},
    })

    -- 5) 走路/跑步切换按钮（蹲下按钮上方）
    runButton_ = VirtualControls.CreateButton({
        position = Vector2(fireCX + 150, fireCY - 330),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "Walk",
        keyBinding = "SHIFT",
        toggle = true,
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {180, 180, 255},
        pressedColor = {220, 220, 255},
    })

    -- 5.5) 蹲下按钮（Walk按钮下方）
    walkButton_ = VirtualControls.CreateButton({
        position = Vector2(fireCX + 150, fireCY - 190),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = smallR,
        label = "Crouch",
        keyBinding = "C",
        toggle = true,
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {255, 180, 100},
        pressedColor = {255, 220, 150},
    })

    -- 6) 左侧辅助开火按钮（屏幕左侧中间偏下，方便左手开火）
    fireButtonLeft_ = VirtualControls.CreateButton({
        position = Vector2(120, 80),
        alignment = {HA_LEFT, VA_CENTER},
        radius = 60,
        label = "Fire",
        opacity = 0.35,
        activeOpacity = 0.8,
        alwaysShow = true,
        color = {255, 100, 100},
        pressedColor = {255, 150, 150},
        on_press = function()
            if isDead_ then return end
            if not isArmed_ or isReloading_ then return end
            local data = myRoleNode_ and playerAnimData_[myRoleNode_.ID]
            if data and data.fsm then
                data.fsm:SetTrigger("shoot")
            end
        end,
    })

    -- 7) 换枪按钮（左侧开火键上方）
    VirtualControls.CreateButton({
        position = Vector2(120, -60),
        alignment = {HA_LEFT, VA_CENTER},
        radius = 40,
        label = "Gun",
        keyBinding = "G",
        opacity = 0.35,
        activeOpacity = 0.8,
        alwaysShow = true,
        color = {200, 180, 100},
        pressedColor = {240, 220, 150},
        on_press = function()
            if isDead_ then return end
            weaponPanelOpen_ = not weaponPanelOpen_
        end,
    })

    -- 触摸视角控制（全屏背景，优先级低于按钮）
    GameHUD.EnableTouchLook({
        camera = cameraNode_,
        onLook = function(deltaYaw, deltaPitch)
            yaw_ = yaw_ + deltaYaw
            pitch_ = pitch_ + deltaPitch
            pitch_ = Shared.Clamp(pitch_, -89.0, 89.0)
        end,
    })
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function HandleAssignRole(eventType, eventData)
    local nodeId = eventData["NodeId"]:GetUInt()
    local roleNode = scene_:GetNode(nodeId)
    if roleNode then
        BindToRole(roleNode)
    else
        pendingNodeId_ = nodeId
    end
end

function BindToRole(roleNode)
    myRoleNode_ = roleNode
    yaw_ = roleNode.rotation:YawAngle()
    print("[Client] Bound to role: " .. roleNode.name)

    -- 为自己的角色设置动画和模型
    DelayOneFrame(function()
        if myRoleNode_ then
            SetupPlayerAnimation(myRoleNode_)
        end
    end)
end

function HandleNodeAdded(eventType, eventData)
    local node = eventData["Node"]:GetPtr("Node")
    if node and node.replicated then
        table.insert(pendingRoleNodes_, node.ID)
    end
end

function HandleHealthUpdate(eventType, eventData)
    local nodeId = eventData["NodeId"]:GetUInt()
    local currentHealth = eventData["Health"]:GetInt()
    local maxHealthVal = eventData["MaxHealth"]:GetInt()

    if myRoleNode_ and nodeId == myRoleNode_.ID then
        -- 检测是否受到伤害（血量减少）
        if currentHealth < health_ then
            -- 触发屏幕闪红效果，伤害越大闪得越强
            local damage = health_ - currentHealth
            local flashIntensity = math.min(0.6, 0.2 + damage / 100)
            damageFlashAlpha_ = flashIntensity
        end
        
        health_ = currentHealth
        maxHealth_ = maxHealthVal
        lastHealth_ = currentHealth
        if health_ <= 0 then isDead_ = true end
    end
end

function HandlePlayerDied(eventType, eventData)
    local victimId = eventData["VictimId"]:GetUInt()
    print("[Client] HandlePlayerDied received: victimId=" .. victimId)

    -- 如果是自己死亡，先恢复模型可见性（确保死亡动画在可见节点上播放）
    if myRoleNode_ and victimId == myRoleNode_.ID then
        isDead_ = true
        isAiming_ = false
        -- 重置第一人称模式
        aimTransition_ = 0
        lastFPModeState_ = false
        if fpGunNode_ then fpGunNode_.enabled = false end
        SetLocalPlayerModelVisible(true)
    end

    -- 为所有玩家触发死亡动画（包括自己和其他玩家）
    TriggerDeathAnimation(victimId)

    if myRoleNode_ and victimId == myRoleNode_.ID then
        print("[Client] You died!")
    end
end

function HandlePlayerRespawn(eventType, eventData)
    local nodeId = eventData["NodeId"]:GetUInt()
    local currentHealth = eventData["Health"]:GetInt()
    local maxHealthVal = eventData["MaxHealth"]:GetInt()

    print("[Client] HandlePlayerRespawn received: nodeId=" .. nodeId .. " HP=" .. currentHealth .. "/" .. maxHealthVal)

    -- 为所有玩家重置死亡动画
    ResetDeathAnimation(nodeId)

    if myRoleNode_ and nodeId == myRoleNode_.ID then
        isDead_ = false
        health_ = currentHealth
        maxHealth_ = maxHealthVal
        -- 重生后保持端枪状态（由服务器同步的 IS_ARMED 变量决定）
        print("[Client] You respawned!")
    end
end

-- 处理服务器发送的创建子弹消息
function HandleBulletCreate(eventType, eventData)
    local bulletId = eventData["BulletId"]:GetInt()
    local startX = eventData["StartX"]:GetFloat()
    local startY = eventData["StartY"]:GetFloat()
    local startZ = eventData["StartZ"]:GetFloat()
    local dirX = eventData["DirX"]:GetFloat()
    local dirY = eventData["DirY"]:GetFloat()
    local dirZ = eventData["DirZ"]:GetFloat()
    local speed = eventData["Speed"]:GetFloat()
    local weaponId = eventData["WeaponId"]:GetString()
    local shooterNodeId = eventData["ShooterNodeId"]:GetInt()

    local startPos = Vector3(startX, startY, startZ)
    local direction = Vector3(dirX, dirY, dirZ)

    -- 获取武器配置
    local weaponCfg = WeaponConfig.WEAPONS[weaponId]

    -- 判断是否是本地玩家的子弹
    local isLocalBullet = myRoleNode_ and shooterNodeId == myRoleNode_.ID

    -- 创建枪口闪光（绑定在对应玩家的枪口节点上）
    if isLocalBullet then
        -- 本地玩家：使用自己的枪口节点
        local isScopeWpn = weaponCfg and weaponCfg.hasScope and weaponCfg.hideModelOnAds
        if isAiming_ and isScopeWpn and cameraNode_ then
            Bullet.CreateMuzzleFlash(cameraNode_.worldPosition + cameraNode_.worldDirection * 0.5)
        elseif isAiming_ and fpMuzzleNode_ then
            Bullet.CreateMuzzleFlash(nil, fpMuzzleNode_)
        elseif weaponAttachment_ and weaponAttachment_.muzzleNode then
            Bullet.CreateMuzzleFlash(nil, weaponAttachment_.muzzleNode)
        else
            Bullet.CreateMuzzleFlash(startPos)
        end
    else
        -- 其他玩家：使用其武器的枪口节点
        local otherAttachment = otherWeapons_[shooterNodeId]
        if otherAttachment and otherAttachment.muzzleNode then
            Bullet.CreateMuzzleFlash(nil, otherAttachment.muzzleNode)
        else
            Bullet.CreateMuzzleFlash(startPos)
        end
    end
    
    -- 创建视觉子弹（服务器同步的子弹，不进行本地碰撞检测）
    Bullet.CreateBulletFromServer(startPos, direction, speed, bulletId, weaponCfg)
    
    -- 只有本地玩家的子弹才创建弹壳效果
    if isLocalBullet and weaponAttachment_ and weaponAttachment_.weaponNode then
        local ejectionPos = WeaponAttachment.GetEjectionPosition(weaponAttachment_)
        if ejectionPos then
            local gunRotation = weaponAttachment_.weaponNode.worldRotation
            Bullet.CreateEjectedCasing(ejectionPos, gunRotation, false)
        end
    end
end

-- 处理服务器发送的子弹命中消息
function HandleBulletHit(eventType, eventData)
    local bulletId = eventData["BulletId"]:GetInt()
    local hitX = eventData["HitX"]:GetFloat()
    local hitY = eventData["HitY"]:GetFloat()
    local hitZ = eventData["HitZ"]:GetFloat()
    local normalX = eventData["NormalX"]:GetFloat()
    local normalY = eventData["NormalY"]:GetFloat()
    local normalZ = eventData["NormalZ"]:GetFloat()
    local hitType = eventData["HitType"]:GetString()
    local targetId = eventData["TargetId"]:GetInt()

    local hitPos = Vector3(hitX, hitY, hitZ)
    local hitNormal = Vector3(normalX, normalY, normalZ)

    -- 获取子弹方向（在移除前获取）
    local bulletDir = Bullet.GetBulletDirection(bulletId) or Vector3(0, 0, 1)

    -- 移除对应的视觉子弹
    Bullet.RemoveBulletById(bulletId)

    -- 根据命中类型创建效果
    if hitType == "player" then
        -- 玩家命中效果由 HIT_EFFECT 事件处理
    elseif hitType == "target" then
        -- 击中目标球
        HitEffects.CreateHitEffect(scene_, hitEffects_, hitPos, bulletDir)
        ChangeTargetColorById(targetId)
    else
        -- 击中墙壁/环境
        HitEffects.CreateWallHitEffect(scene_, hitEffects_, hitPos, bulletDir, hitNormal)
    end
end

-- 处理服务器发送的移动靶位置同步
function HandleTargetSync(eventType, eventData)
    local count = eventData["Count"]:GetInt()
    local serverTime = eventData["ServerTime"]:GetFloat()
    
    -- 计算服务器与本地时间差
    local localTime = time.elapsedTime
    local timeDiff = serverTime - localTime
    
    -- 同步移动靶位置
    for i = 1, count do
        local target = Shared.MovingTargets[i]
        if target and target.node then
            local x = eventData["X" .. i]:GetFloat()
            local y = eventData["Y" .. i]:GetFloat()
            local z = eventData["Z" .. i]:GetFloat()
            local serverPhase = eventData["Phase" .. i]:GetFloat()
            
            -- 直接更新节点位置到服务器同步的位置
            local serverPos = Vector3(x, y, z)
            target.node.position = serverPos
            
            -- 更新刚体变换（防止物理同步问题）
            local body = target.node:GetComponent("RigidBody")
            if body then
                body:SetTransform(serverPos, target.node.rotation)
            end
            
            -- 同步相位偏移（确保后续运动一致）
            target.phaseOffset = serverPhase
        end
    end
end

-- 处理服务器日志
function HandleServerLog(eventType, eventData)
    local msg = eventData["Msg"]:GetString()
    print(msg)  -- 同时输出到本地控制台
    table.insert(serverLogs_, { msg = msg, time = SERVER_LOG_DURATION })
    if #serverLogs_ > SERVER_LOG_MAX then
        table.remove(serverLogs_, 1)
    end
end

-- 根据ID查找靶子并变色
function ChangeTargetColorById(targetId)
    if targetId <= 0 then return end
    
    -- 从注册表中查找靶子节点
    local node = Shared.TargetRegistry[targetId]
    if not node then return end
    
    local model = node:GetComponent("StaticModel")
    if model then
        -- 创建黄色材质
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.9, 0.2, 1.0)))
        mat:SetShaderParameter("Roughness", Variant(0.3))
        mat:SetShaderParameter("Metallic", Variant(0.5))
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.5, 0.4, 0)))
        model:SetMaterial(mat)

        -- 添加恢复计时器（0.1秒后变回原色）
        targetResetTimers_[node.ID] = { node = node, time = 0.1, isMoving = (node.name == "MovingTarget") }
    end
end

-- 更新目标球恢复计时器
function UpdateTargetResetTimers(dt)
    local toRemove = {}
    for nodeId, data in pairs(targetResetTimers_) do
        data.time = data.time - dt
        if data.time <= 0 then
            -- 恢复原色（移动靶蓝色，静态靶红色）
            local node = data.node
            if node then
                local model = node:GetComponent("StaticModel")
                if model then
                    local mat = Material:new()
                    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
                    if data.isMoving then
                        -- 移动靶恢复蓝色
                        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.7, 0.9, 1.0)))
                        mat:SetShaderParameter("Roughness", Variant(0.4))
                        mat:SetShaderParameter("Metallic", Variant(0.2))
                    else
                        -- 静态靶恢复红色
                        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.2, 0.2, 1.0)))
                        mat:SetShaderParameter("Roughness", Variant(0.5))
                        mat:SetShaderParameter("Metallic", Variant(0.1))
                    end
                    model:SetMaterial(mat)
                end
            end
            table.insert(toRemove, nodeId)
        end
    end
    for _, nodeId in ipairs(toRemove) do
        targetResetTimers_[nodeId] = nil
    end
end

-- 获取节点的武器状态
function IsNodeArmed(node)
    local armedVar = node:GetVar(VARS.IS_ARMED)
    if armedVar:IsEmpty() then return false end
    return armedVar:GetBool()
end

-- ============================================================================
-- 动画设置
-- ============================================================================

function SetupPlayerAnimation(roleNode)
    local nodeId = roleNode.ID
    if playerAnimData_[nodeId] then return true end

    local modelNode = roleNode:GetChild("ModelNode")
    if modelNode == nil then
        -- 从预制体加载模型
        local prefabFile = cache:GetResource("XMLFile", Settings.Player.Prefab)
        if prefabFile then
            modelNode = Node()
            modelNode:LoadXML(prefabFile:GetRoot())
            modelNode.name = "ModelNode"
            modelNode.parent = roleNode
            modelNode.position = Vector3.ZERO
            modelNode.rotation = Quaternion.IDENTITY
        else
            print("[Client] ERROR: Failed to load prefab")
            return false
        end
    end

    modelNode:GetOrCreateComponent("AnimationController", LOCAL)

    -- 创建动画状态机（统一 FSM）
    local stateMachine = modelNode:CreateComponent("AnimationStateMachine", LOCAL)
    local unifiedFSM = cache:GetResource("JSONFile", Settings.FSM.Unified)

    if unifiedFSM then
        stateMachine:LoadFromJSONFile(unifiedFSM)
        stateMachine:Start()
        stateMachine:SetInt("weaponType", Settings.WeaponType.NORMAL)
    else
        print("[Client] ERROR: Unified FSM not found")
    end

    -- 创建 AimOffset
    local aimOffset = modelNode:CreateComponent("AimOffset", LOCAL)
    aimOffset:AddBone("Bip001 Spine", 0.40, 0.40)
    aimOffset:AddBone("Bip001 Spine1", 0.35, 0.35)
    aimOffset:AddBone("Bip001 Spine2", 0.25, 0.25)
    aimOffset:SetMaxPitch(60)
    aimOffset:SetMaxYaw(60)  -- 增大上半身偏转范围，更好对齐镜头
    aimOffset:SetSmoothSpeed(25)  -- 加快上半身跟随镜头速度
    aimOffset:SetEnabled(false)

    playerAnimData_[nodeId] = {
        fsm = stateMachine,
        unifiedFSM = unifiedFSM,
        isArmed = false,
        aimOffset = aimOffset,
        modelNode = modelNode,
        lastYaw = 0,
    }

    print("[Client] SetupPlayerAnimation: " .. roleNode.name)
    return true
end

-- ============================================================================
-- 死亡动画
-- ============================================================================

--- 触发死亡动画（通过 FSM 状态机的 die trigger 播放）
function TriggerDeathAnimation(nodeId)
    local data = playerAnimData_[nodeId]
    if data == nil then
        print("[Client] WARN: TriggerDeathAnimation - no animData for node: " .. nodeId)
        return
    end
    if data.isDying then
        print("[Client] WARN: TriggerDeathAnimation - already dying for node: " .. nodeId)
        return
    end

    data.isDying = true

    -- 禁用 AimOffset
    if data.aimOffset then
        data.aimOffset:SetEnabled(false)
    end

    -- 通过 FSM 的 die trigger 切换到 FullBody 层的 Death 状态
    if data.fsm then
        data.fsm:SetTrigger("die")
        print("[Client] FSM die trigger set for node: " .. nodeId)
    else
        print("[Client] ERROR: No FSM for death animation, node: " .. nodeId)
    end
end

--- 重置死亡动画，恢复正常状态（重新加载 FSM 回到默认状态）
function ResetDeathAnimation(nodeId)
    local data = playerAnimData_[nodeId]
    if data == nil then
        print("[Client] WARN: ResetDeathAnimation - no animData for node: " .. nodeId)
        return
    end
    if not data.isDying then
        print("[Client] WARN: ResetDeathAnimation - not dying for node: " .. nodeId)
        return
    end

    data.isDying = false

    -- 重新加载统一 FSM，彻底重置所有层回到默认状态（清除 Death 状态）
    if data.fsm and data.unifiedFSM then
        data.fsm:LoadFromJSONFile(data.unifiedFSM)
        data.fsm:Start()
        -- 恢复武器类型
        local weaponType = data.isArmed and Settings.WeaponType.RIFLE or Settings.WeaponType.NORMAL
        data.fsm:SetInt("weaponType", weaponType)
        print("[Client] FSM reloaded for respawn, node: " .. nodeId)
    end

    -- 恢复 AimOffset
    if data.aimOffset then
        data.aimOffset:SetEnabled(data.isArmed)
    end

    print("[Client] Death animation reset for node: " .. nodeId)
end

function SetPlayerArmed(nodeId, armed)
    local data = playerAnimData_[nodeId]
    if data == nil then return end

    if data.isArmed == armed then return end
    data.isArmed = armed

    -- 通过 weaponType 参数切换动画（无需重新加载 FSM）
    if data.fsm then
        local weaponType = armed and Settings.WeaponType.RIFLE or Settings.WeaponType.NORMAL
        data.fsm:SetInt("weaponType", weaponType)
    end

    -- 启用/禁用 AimOffset
    if data.aimOffset then
        data.aimOffset:SetEnabled(armed)
    end

    -- 装备/卸下武器
    if myRoleNode_ and nodeId == myRoleNode_.ID then
        if armed then
            EquipWeapon(Settings.Combat.DefaultWeapon)
        else
            UnequipWeapon()
        end
    end
end

-- ============================================================================
-- 第一人称枪械系统（瞄准模式）
-- ============================================================================

--- 递归为节点及其子节点的 StaticModel 启用阴影
local function EnableShadowsRecursiveFP(node)
    if not node then return end
    local model = node:GetComponent("StaticModel")
    if model then model.castShadows = true end
    for i = 0, node:GetNumChildren() - 1 do
        EnableShadowsRecursiveFP(node:GetChild(i))
    end
end

--- 创建/重建第一人称枪械模型
function CreateFPGun(weaponId)
    if not cameraNode_ then return end

    local weaponCfg = WeaponConfig.WEAPONS[weaponId]
    if not weaponCfg then return end
    local m = weaponCfg.model
    if not m then return end

    -- 移除旧的第一人称枪械
    DestroyFPGun()

    -- 创建枪械节点，挂在相机下（与 demo Weapon.lua 一致的方式）
    fpGunNode_ = cameraNode_:CreateChild("FPGun")
    fpGunNode_.position = FP_GUN_ADS_POS

    if m.isPrefab then
        -- 使用 InstantiateXML + LOCAL 加载 prefab（客户端专属，不会被网络同步）
        local prefabNode = scene_:InstantiateXML(m.prefabPath, Vector3.ZERO, Quaternion.IDENTITY, LOCAL)
        if prefabNode then
            prefabNode:SetParent(fpGunNode_)
            prefabNode.name = "FPModel"
            -- 使用 FP 专用参数（m.fp），与 TP 手骨参数（m.positionOffset 等）完全不同
            local fp = m.fp or {}
            prefabNode.scale = fp.scale or Vector3(1.2, 1.2, 1.2)
            prefabNode.rotation = fp.rotationOffset or Quaternion(180, Vector3.UP)
            if fp.positionOffset then
                prefabNode.position = fp.positionOffset
            end
            EnableShadowsRecursiveFP(prefabNode)

            -- 枪口节点
            fpMuzzleNode_ = prefabNode:CreateChild("FPMuzzle")
            fpMuzzleNode_.position = m.muzzleOffset or Vector3(0, 0, 0.5)
            print("[FPGun] Prefab loaded OK via InstantiateXML LOCAL: " .. weaponCfg.name)
        else
            print("[FPGun] ERROR: Failed to load prefab: " .. tostring(m.prefabPath))
        end
    else
        -- 程序化枪械模型（简化版，使用 Box 表示枪身）
        local modelContainer = fpGunNode_:CreateChild("FPModelContainer")
        -- 注意: 不应用 m.positionOffset（那是第三人称手骨对齐偏移）

        local gunMat = Material:new()
        gunMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        gunMat:SetShaderParameter("MatDiffColor", Variant(m.color or Color(0.15, 0.15, 0.18, 1.0)))
        gunMat:SetShaderParameter("Metallic", Variant(0.9))
        gunMat:SetShaderParameter("Roughness", Variant(0.3))

        -- 枪身
        local bodyNode = modelContainer:CreateChild("Body")
        bodyNode.scale = Vector3(m.bodyWidth, m.bodyHeight, m.bodyLength)
        bodyNode.position = Vector3(0, 0, m.bodyLength / 2)
        local bodyModel = bodyNode:CreateComponent("StaticModel")
        bodyModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        bodyModel:SetMaterial(gunMat)
        bodyModel.castShadows = true

        -- 枪管
        local barrelStartZ = m.bodyLength
        local barrelNode = modelContainer:CreateChild("Barrel")
        barrelNode.scale = Vector3(m.barrelRadius * 2, m.barrelLength, m.barrelRadius * 2)
        barrelNode.position = Vector3(0, m.bodyHeight * 0.2, barrelStartZ + m.barrelLength / 2)
        barrelNode.rotation = Quaternion(90, Vector3.RIGHT)
        local barrelModel = barrelNode:CreateComponent("StaticModel")
        barrelModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        barrelModel:SetMaterial(gunMat)
        barrelModel.castShadows = true

        -- 握把
        local accentMat = Material:new()
        accentMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        accentMat:SetShaderParameter("MatDiffColor", Variant(m.accentColor or Color(0.35, 0.2, 0.1, 1.0)))
        accentMat:SetShaderParameter("Metallic", Variant(0.1))
        accentMat:SetShaderParameter("Roughness", Variant(0.7))

        local gripNode = modelContainer:CreateChild("Grip")
        gripNode.scale = Vector3(m.gripWidth, m.gripHeight, m.gripWidth * 1.5)
        gripNode.position = Vector3(0, -m.gripHeight / 2 - m.bodyHeight / 2 + 0.02, 0.02)
        gripNode.rotation = Quaternion(-15, Vector3.RIGHT)
        local gripModel = gripNode:CreateComponent("StaticModel")
        gripModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        gripModel:SetMaterial(accentMat)
        gripModel.castShadows = true

        -- 枪口节点
        local muzzleZ = barrelStartZ + m.barrelLength
        if m.hasMuzzleBrake then
            muzzleZ = muzzleZ + (m.muzzleBrakeLength or 0.04)
        end
        fpMuzzleNode_ = modelContainer:CreateChild("FPMuzzle")
        fpMuzzleNode_.position = Vector3(0, m.bodyHeight * 0.2, muzzleZ)
    end

    print("[Client] FP gun created for weapon: " .. weaponCfg.name)
end

--- 销毁第一人称枪械
function DestroyFPGun()
    if fpGunNode_ then
        fpGunNode_:Remove()
        fpGunNode_ = nil
        fpMuzzleNode_ = nil
    end
end

--- 设置本地玩家角色模型的可见性（仅影响本地客户端显示）
--- 只隐藏渲染组件（AnimatedModel），保持节点和 FSM/AnimationController 始终运行
function SetLocalPlayerModelVisible(visible)
    if not myRoleNode_ then return end
    local data = playerAnimData_[myRoleNode_.ID]
    if not data or not data.modelNode then return end

    -- 递归设置所有渲染组件的可见性，不禁用节点本身
    SetDrawablesEnabled(data.modelNode, visible)

    -- 同时控制第三人称武器可见性
    if weaponAttachment_ then
        WeaponAttachment.SetVisible(weaponAttachment_, visible)
    end
end

--- 递归启用/禁用节点及其子节点上的所有渲染组件（AnimatedModel / StaticModel）
function SetDrawablesEnabled(node, enabled)
    local animModel = node:GetComponent("AnimatedModel")
    if animModel then
        animModel.enabled = enabled
    end
    local staticModel = node:GetComponent("StaticModel")
    if staticModel then
        staticModel.enabled = enabled
    end
    local numChildren = node:GetNumChildren()
    for i = 0, numChildren - 1 do
        SetDrawablesEnabled(node:GetChild(i), enabled)
    end
end

local lastFPModeState_ = false  -- 上一帧的第一人称模式状态

--- 更新第一人称枪械位置和瞄准过渡
function UpdateFPGun(dt)
    -- 瞄准状态：持枪 + 按住右键
    local shouldShow = isArmed_ and isAiming_

    -- 更新瞄准过渡（进入平滑，退出瞬间）
    if shouldShow then
        if aimTransition_ < 1.0 then
            aimTransition_ = math.min(1.0, aimTransition_ + AIM_TRANSITION_SPEED * dt)
        end
    else
        aimTransition_ = 0
    end

    -- 判断是否为狙击镜武器（瞄准时跳过 FP 枪模型，直接进入瞄准镜）
    local weaponCfg = currentWeaponId_ and WeaponConfig.WEAPONS[currentWeaponId_]
    local isScopeWeapon = weaponCfg and weaponCfg.hasScope and weaponCfg.hideModelOnAds

    -- 状态切换时创建/销毁 FP 枪（避免 enabled 状态不可靠的问题）
    if shouldShow ~= lastFPModeState_ then
        lastFPModeState_ = shouldShow
        if shouldShow then
            if isScopeWeapon then
                -- 狙击镜武器：不创建 FP 枪，直接进入瞄准镜
                scopeActive_ = true
                scopeProgress_ = 1
                aimTransition_ = 1.0
            else
                -- 普通武器：创建 FP 枪
                if not fpGunNode_ and currentWeaponId_ then
                    CreateFPGun(currentWeaponId_)
                end
            end
        else
            -- 退出瞄准
            DestroyFPGun()
            scopeActive_ = false
            scopeProgress_ = 0
        end
        SetLocalPlayerModelVisible(not shouldShow)
    end

    -- 狙击镜状态管理（非狙击镜武器使用渐进过渡）
    if not isScopeWeapon then
        if weaponCfg and weaponCfg.hasScope and shouldShow then
            scopeProgress_ = aimTransition_
            scopeActive_ = aimTransition_ > 0.95
        elseif not isScopeWeapon then
            scopeActive_ = false
            scopeProgress_ = 0
        end
    end
end

-- ============================================================================
-- 武器系统
-- ============================================================================

--- 装备武器
function EquipWeapon(weaponId)
    if currentWeaponId_ == weaponId and weaponAttachment_ then
        return
    end

    -- 切换武器时先强制退出瞄准模式
    isAiming_ = false
    aimTransition_ = 0
    lastFPModeState_ = false

    -- 先卸下当前武器
    UnequipWeapon()

    -- 获取武器配置
    local weaponCfg = WeaponConfig.WEAPONS[weaponId]
    if not weaponCfg then
        print("[Client] ERROR: Unknown weapon: " .. tostring(weaponId))
        return
    end

    -- 查找模型节点
    local data = playerAnimData_[myRoleNode_.ID]
    if not data or not data.modelNode then
        print("[Client] ERROR: No model node for weapon attachment")
        return
    end

    -- 附加武器模型（第三人称，其他玩家可见）
    weaponAttachment_ = WeaponAttachment.AttachWeapon(scene_, data.modelNode, weaponId)
    if weaponAttachment_ then
        currentWeaponId_ = weaponId
        ammoMag_ = weaponCfg.magSize
        ammoReserve_ = weaponCfg.magSize * 3
        isReloading_ = false
        reloadTimer_ = 0
        crosshairSpreadDeg_ = 0

        -- FP 枪械延迟到瞄准时创建（避免 InstantiateXML 节点 enabled 状态问题）
        DestroyFPGun()
        shotCounter_ = 0
        print("[Client] Equipped weapon: " .. weaponCfg.name)
        
        -- 通知调试UI武器切换
        WeaponDebugUI.OnWeaponChanged(weaponId)
    else
        print("[Client] ERROR: Failed to attach weapon: " .. weaponId)
    end
end

--- 卸下武器
function UnequipWeapon()
    if weaponAttachment_ then
        WeaponAttachment.DetachWeapon(weaponAttachment_)
        weaponAttachment_ = nil
    end
    -- 销毁第一人称枪械
    DestroyFPGun()
    aimTransition_ = 0

    currentWeaponId_ = nil
    ammoMag_ = 0
    ammoReserve_ = 0

    -- 确保角色模型恢复可见
    SetLocalPlayerModelVisible(true)
end

--- 获取当前武器配置
function GetCurrentWeaponConfig()
    if currentWeaponId_ then
        return WeaponConfig.WEAPONS[currentWeaponId_]
    end
    return nil
end

--- 处理武器切换事件
function HandleWeaponSwitch(eventType, eventData)
    local nodeId = eventData["NodeId"]:GetUInt()
    local weaponId = eventData["WeaponId"]:GetString()

    if myRoleNode_ and nodeId == myRoleNode_.ID then
        EquipWeapon(weaponId)
    else
        -- 其他玩家：创建/更新第三人称武器模型
        AttachOtherPlayerWeapon(nodeId, weaponId)
    end
end

--- 为其他玩家附加武器模型
function AttachOtherPlayerWeapon(nodeId, weaponId)
    -- 先移除旧武器
    if otherWeapons_[nodeId] then
        WeaponAttachment.DetachWeapon(otherWeapons_[nodeId])
        otherWeapons_[nodeId] = nil
    end

    local data = playerAnimData_[nodeId]
    if not data or not data.modelNode then
        -- 模型还没准备好，记录待处理
        if not data then return end
        return
    end

    local attachment = WeaponAttachment.AttachWeapon(scene_, data.modelNode, weaponId)
    if attachment then
        otherWeapons_[nodeId] = attachment
    end
end

--- 处理击中特效事件
function HandleHitEffect(eventType, eventData)
    local hitX = eventData["HitX"]:GetFloat()
    local hitY = eventData["HitY"]:GetFloat()
    local hitZ = eventData["HitZ"]:GetFloat()
    local dirX = eventData["DirX"]:GetFloat()
    local dirY = eventData["DirY"]:GetFloat()
    local dirZ = eventData["DirZ"]:GetFloat()
    local isEnemy = eventData["IsEnemy"]:GetBool()

    local hitPos = Vector3(hitX, hitY, hitZ)
    local bulletDir = Vector3(dirX, dirY, dirZ)

    if isEnemy then
        -- 击中敌方角色：红色血液飞溅
        HitEffects.CreateBloodEffect(scene_, hitEffects_, hitPos, bulletDir)
        -- 触发准星击中反馈
        crosshairHitTimer_ = CROSSHAIR_HIT_DURATION
    else
        HitEffects.CreateWallHitEffect(scene_, hitEffects_, hitPos, bulletDir)
    end
end

--- 应用后坐力（脉冲式：kick → hold → recover，只恢复最后一枪的跳跃距离）
function ApplyRecoil()
    local weaponCfg = GetCurrentWeaponConfig()
    if not weaponCfg then return end

    -- 后坐力强度系数
    local kickMultiplier = 1.0
    local magnitudeMin = (weaponCfg.recoilPitchMin or 0.3) * kickMultiplier
    local magnitudeMax = (weaponCfg.recoilPitchMax or 0.6) * kickMultiplier
    local magnitude = magnitudeMin + math.random() * (magnitudeMax - magnitudeMin)

    -- 在上方60度扇形内随机选择方向（以正上方为中心，左右各30度）
    local angleRange = 60  -- 扇形角度（度）
    local randomAngle = (math.random() - 0.5) * angleRange  -- -30 到 +30 度
    local angleRad = math.rad(randomAngle)

    -- 计算 pitch 和 yaw 分量（pitch 为负值表示向上看）
    local pitchKick = -magnitude * math.cos(angleRad)  -- 负值=向上
    local yawKick = magnitude * math.sin(angleRad)     -- 左右偏移

    -- 记录当前位置作为起点（用于恢复）
    recoilState_.startPitch = recoilState_.currentPitch
    recoilState_.startYaw = recoilState_.currentYaw

    -- 记录本次跳跃量
    recoilState_.kickPitch = pitchKick
    recoilState_.kickYaw = yawKick

    -- 计算峰值位置（从当前位置 + 跳跃量）
    recoilState_.targetPitch = recoilState_.currentPitch + pitchKick
    recoilState_.targetYaw = recoilState_.currentYaw + yawKick

    -- 开始 kick 阶段
    recoilState_.phase = "kick"
    recoilState_.timer = 0
    recoilState_.holdTimer = 0

    -- 准心散布始终平滑累积（零散布只影响弹道，不影响准心UI）
    local spreadIncreaseDeg = weaponCfg.crosshairSpreadPerShot or 2.0
    local spreadMaxDeg = weaponCfg.crosshairSpreadMax or crosshairSpreadMaxDeg_
    crosshairSpreadDeg_ = math.min(crosshairSpreadDeg_ + spreadIncreaseDeg, spreadMaxDeg)
end

--- 更新后坐力（脉冲式：kick → hold → recover，只恢复最后一枪的跳跃距离）
function UpdateRecoil(dt)
    -- 准星扩散恢复（始终运行，不受后坐力阶段限制）
    if crosshairSpreadDeg_ > 0 then
        local weaponCfg = GetCurrentWeaponConfig()
        local recoverySpeedDeg = crosshairSpreadRecoveryDeg_
        if weaponCfg and weaponCfg.crosshairRecoverySpeed then
            recoverySpeedDeg = weaponCfg.crosshairRecoverySpeed
        end
        local wasPositive = crosshairSpreadDeg_ > 0
        crosshairSpreadDeg_ = math.max(0, crosshairSpreadDeg_ - recoverySpeedDeg * dt)
        if wasPositive and crosshairSpreadDeg_ <= 0 then
            shotCounter_ = 0
        end
    end

    if recoilState_.phase == "idle" then
        return
    end

    local prevPitch = recoilState_.currentPitch
    local prevYaw = recoilState_.currentYaw

    if recoilState_.phase == "kick" then
        -- 阶段1：瞬间完成，直接跳到峰值
        recoilState_.currentPitch = recoilState_.targetPitch
        recoilState_.currentYaw = recoilState_.targetYaw
        recoilState_.phase = "hold"
        recoilState_.holdTimer = 0

    elseif recoilState_.phase == "hold" then
        -- 阶段2：保持在峰值位置，等待下一发或超时
        recoilState_.holdTimer = recoilState_.holdTimer + dt
        
        if recoilState_.holdTimer >= recoilState_.holdDuration then
            -- hold 超时，开始恢复
            recoilState_.phase = "recover"
            recoilState_.timer = 0
        end
        -- 如果在 hold 期间射击，ApplyRecoil() 会中断并开始新的 kick

    elseif recoilState_.phase == "recover" then
        -- 阶段3：恢复到起始位置（只恢复最后一枪的跳跃距离）
        -- 如果玩家主动移动了镜头，立即停止恢复运动
        local mouseMove = input.mouseMove
        if math.abs(mouseMove.x) > 0 or math.abs(mouseMove.y) > 0 then
            recoilState_.phase = "idle"
            recoilState_.timer = 0
        else
            recoilState_.timer = recoilState_.timer + dt
            local t = math.min(recoilState_.timer / recoilState_.recoverDuration, 1.0)
            -- ease-in-out 缓动（平滑恢复）
            local easeT = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2

            -- 从峰值位置恢复到起始位置（不是恢复到0！）
            recoilState_.currentPitch = recoilState_.targetPitch + (recoilState_.startPitch - recoilState_.targetPitch) * easeT
            recoilState_.currentYaw = recoilState_.targetYaw + (recoilState_.startYaw - recoilState_.targetYaw) * easeT

            if recoilState_.timer >= recoilState_.recoverDuration then
                -- 恢复完成，回到起始位置
                recoilState_.currentPitch = recoilState_.startPitch
                recoilState_.currentYaw = recoilState_.startYaw
                recoilState_.phase = "idle"
                recoilState_.timer = 0
            end
        end
    end

    -- 应用后坐力变化到视角（增量方式）
    local deltaPitch = recoilState_.currentPitch - prevPitch
    local deltaYaw = recoilState_.currentYaw - prevYaw
    pitch_ = pitch_ + deltaPitch
    yaw_ = yaw_ + deltaYaw

end

--- 发送射击请求到服务器
function SendShootRequest()
    if not weaponAttachment_ then return end
    if not cameraNode_ then return end
    
    local camera = cameraNode_:GetComponent("Camera")
    if not camera then return end
    
    local weaponCfg = GetCurrentWeaponConfig()
    if not weaponCfg then return end
    
    -- 获取物理世界
    local physicsWorld = scene_:GetComponent("PhysicsWorld")
    
    -- 使用屏幕中心射线获取瞄准目标点（传入角色位置，过滤角色后方的碰撞）
    local charPos = myRoleNode_ and myRoleNode_.position or nil
    local targetPoint, hitResult = Bullet.GetAimTargetPoint(camera, physicsWorld, charPos)
    
    -- 获取枪口位置
    local muzzlePos
    local isScopeWeapon = weaponCfg.hasScope and weaponCfg.hideModelOnAds
    if isAiming_ and isScopeWeapon then
        -- 狙击镜武器瞄准时没有 FP 枪模型，直接从相机位置发射
        muzzlePos = cameraNode_.worldPosition + cameraNode_.worldDirection * 0.5
    elseif isAiming_ and fpMuzzleNode_ then
        -- FP 模式：从枪口位置发射
        muzzlePos = fpMuzzleNode_.worldPosition
    else
        muzzlePos = WeaponAttachment.GetMuzzlePosition(weaponAttachment_)
        if not muzzlePos then
            muzzlePos = weaponAttachment_.weaponNode and weaponAttachment_.weaponNode.worldPosition or cameraNode_.worldPosition
        end
    end
    
    -- 计算从枪口到目标点的基础方向
    local baseDirection = (targetPoint - muzzlePos):Normalized()
    
    -- 应用散布（准星扩散 + 武器固有散布，单位：角度）
    -- 零散布枪（第1、4、7…枪）弹道散布为0，但准心UI不受影响
    local isZeroSpreadShot = (shotCounter_ % 3 == 1)
    local bulletSpreadDeg = isZeroSpreadShot and 0 or crosshairSpreadDeg_
    local weaponSpreadDeg = isZeroSpreadShot and 0 or (weaponCfg.spreadAngle or 0)
    local finalDirection = Bullet.ApplySpreadDeg(baseDirection, bulletSpreadDeg, weaponSpreadDeg)
    
    -- 注意：枪口闪光和弹壳现在在 HandleBulletCreate 中创建
    -- 这样可以确保只有服务器确认的射击才会显示效果
    
    -- 发送射击请求到服务器
    local eventData = VariantMap()
    eventData["MuzzleX"] = Variant(muzzlePos.x)
    eventData["MuzzleY"] = Variant(muzzlePos.y)
    eventData["MuzzleZ"] = Variant(muzzlePos.z)
    eventData["DirX"] = Variant(finalDirection.x)
    eventData["DirY"] = Variant(finalDirection.y)
    eventData["DirZ"] = Variant(finalDirection.z)
    eventData["WeaponId"] = Variant(currentWeaponId_)
    eventData["SpreadDeg"] = Variant(crosshairSpreadDeg_)
    
    network:GetServerConnection():SendRemoteEvent(EVENTS.SHOOT_REQUEST, true, eventData)
end

--- 切换到下一把武器
function SwitchToNextWeapon()
    local order = WeaponConfig.WEAPON_ORDER
    local currentIndex = 1

    for i, wid in ipairs(order) do
        if wid == currentWeaponId_ then
            currentIndex = i
            break
        end
    end

    local nextIndex = (currentIndex % #order) + 1
    local nextWeaponId = order[nextIndex]

    -- 发送切换武器请求到服务器
    local serverConn = network:GetServerConnection()
    if serverConn then
        local eventData = VariantMap()
        eventData["WeaponId"] = Variant(nextWeaponId)
        serverConn:SendRemoteEvent(EVENTS.WEAPON_SWITCH, true, eventData)
    end

    EquipWeapon(nextWeaponId)
end

-- ============================================================================
-- 更新循环
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    ProcessPendingCallbacks()
    HandleWeaponPanelInput()
    UpdateTargetResetTimers(dt)
    UpdateRecoil(dt)
    HitEffects.Update(hitEffects_, dt)
    Shared.UpdateMovingTargets(dt)  -- 更新移动靶
    
    -- 更新准星击中反馈计时器
    if crosshairHitTimer_ > 0 then
        crosshairHitTimer_ = crosshairHitTimer_ - dt
    end

    -- 更新服务器日志倒计时
    for i = #serverLogs_, 1, -1 do
        serverLogs_[i].time = serverLogs_[i].time - dt
        if serverLogs_[i].time <= 0 then
            table.remove(serverLogs_, i)
        end
    end
    
    -- 更新伤害闪红效果（快速淡出）
    if damageFlashAlpha_ > 0 then
        damageFlashAlpha_ = damageFlashAlpha_ - dt * 2.0  -- 0.5秒淡出
        if damageFlashAlpha_ < 0 then damageFlashAlpha_ = 0 end
    end
    
    -- 更新子弹系统
    local physicsWorld = scene_:GetComponent("PhysicsWorld")
    Bullet.Update(dt, physicsWorld, function(hitPos, hitNormal, hitNode)
        -- 子弹命中回调：根据击中目标类型创建不同特效
        local isCharacter = false
        
        -- 检查是否击中角色（向上遍历查找带 IS_ROLE 变量的节点）
        local checkNode = hitNode
        while checkNode do
            local isRoleVar = checkNode:GetVar(VARS.IS_ROLE)
            if not isRoleVar:IsEmpty() and isRoleVar:GetBool() then
                isCharacter = true
                break
            end
            checkNode = checkNode.parent
        end
        
        if isCharacter then
            -- 击中角色：红色血液飞溅
            local bulletDir = cameraNode_ and (cameraNode_.worldRotation * Vector3.FORWARD) or Vector3.FORWARD
            HitEffects.CreateBloodEffect(scene_, hitEffects_, hitPos, bulletDir)
            -- 触发准星击中反馈
            crosshairHitTimer_ = CROSSHAIR_HIT_DURATION
        else
            -- 击中墙壁/物体：普通弹孔特效
            HitEffects.CreateWallHitEffect(scene_, hitEffects_, hitPos, hitNormal)
        end
    end)

    -- 处理待处理的复制节点
    if #pendingRoleNodes_ > 0 then
        local nodesToCheck = pendingRoleNodes_
        pendingRoleNodes_ = {}
        for _, nodeId in ipairs(nodesToCheck) do
            local node = scene_:GetNode(nodeId)
            if node then
                local isRoleVar = node:GetVar(VARS.IS_ROLE)
                if not isRoleVar:IsEmpty() and isRoleVar:GetBool() then
                    if not playerAnimData_[nodeId] then
                        if SetupPlayerAnimation(node) then
                            -- 非本地玩家：附加默认武器
                            if not myRoleNode_ or nodeId ~= myRoleNode_.ID then
                                if not otherWeapons_[nodeId] then
                                    AttachOtherPlayerWeapon(nodeId, Settings.Combat.DefaultWeapon)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 检查待处理节点
    if pendingNodeId_ ~= 0 then
        local roleNode = scene_:GetNode(pendingNodeId_)
        if roleNode then
            pendingNodeId_ = 0
            BindToRole(roleNode)
        end
    end

    local serverConn = network:GetServerConnection()

    -- 绑定 GameHUD 到网络控制
    if needBindControls_ and serverConn then
        needBindControls_ = false
        GameHUD.SetControls(serverConn.controls)
    end

    -- 发送 Ready 事件（只有成功发送后才设为 false，否则继续重试）
    if needSendReady_ and serverConn then
        serverConn:SendRemoteEvent(EVENTS.CLIENT_READY, true)
        needSendReady_ = false
        print("[Client] CLIENT_READY sent to server")
    end

    if myRoleNode_ == nil then return end
    if isDead_ then return end

    UpdateMouseLook(dt)
    UpdateMovement(dt)
end

function HandlePostUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    UpdateFPGun(dt)

    -- 处理延迟的换弹动画触发（在 UpdateFPGun 确保模型可见之后）
    if pendingReloadAnim_ then
        pendingReloadAnim_ = false
        if myRoleNode_ then
            local data = playerAnimData_[myRoleNode_.ID]
            if data and data.fsm then
                data.fsm:SetTrigger("reload")
            end
        end
    end

    UpdateCamera(dt)
    UpdateAllAnimations()
    UpdateWeaponPosition()
    UpdateDebugVisualization()
end

function HandlePostRenderUpdate(eventType, eventData)
    -- 测试模式下仅绘制物理碰撞盒
    if Settings.Debug.ShowPhysics and not debugMode_ then
        local physicsWorld = scene_:GetComponent("PhysicsWorld")
        if physicsWorld then
            physicsWorld:DrawDebugGeometry(true)
        end
        return
    end

    if not debugMode_ then return end
    
    local debug = scene_:GetComponent("DebugRenderer")
    if not debug then return end

    -- 绘制物理碰撞盒
    local physicsWorld = scene_:GetComponent("PhysicsWorld")
    if physicsWorld then
        physicsWorld:DrawDebugGeometry(true)
    end

    -- 绘制头部/身体判定区域
    local playerHeight = Settings.Player.Height          -- 1.8
    local crouchDelta = Settings.Player.CrouchHeightDelta  -- 0.3
    local headColor = Color(1, 0, 0, 1)                  -- 红色 = 头部
    local bodyColor = Color(0, 1, 0, 1)                  -- 绿色 = 身体
    local dividerColor = Color(1, 1, 0, 1)               -- 黄色 = 分界线

    for nodeId, data in pairs(playerAnimData_) do
        local node = scene_:GetNode(nodeId)
        if node then
            local basePos = node.position
            -- 蹲下时高度和爆头判定同步降低（本地玩家用本地状态，其他角色从节点变量读取）
            local isCrouching
            if myRoleNode_ and nodeId == myRoleNode_.ID then
                isCrouching = isCrouching_
            else
                local crouchVar = node:GetVar(VARS.IS_CROUCHING)
                isCrouching = (not crouchVar:IsEmpty()) and crouchVar:GetBool() or false
            end
            local effectiveHeight = isCrouching and (playerHeight - crouchDelta) or playerHeight
            local headThreshold = effectiveHeight * 0.83
            local headY = basePos.y + headThreshold
            local topY = basePos.y + effectiveHeight

            -- 分界线：黄色圆环标记头部/身体分界
            local radius = Settings.Player.Radius
            debug:AddCircle(Vector3(basePos.x, headY, basePos.z),
                Vector3.UP, radius, dividerColor, 32, false)

            -- 头部区域：红色球体
            local headCenter = Vector3(basePos.x, (headY + topY) / 2, basePos.z)
            local headRadius = (topY - headY) / 2
            debug:AddSphere(Sphere(headCenter, headRadius), headColor, false)

            -- 身体区域：绿色线段标记两侧轮廓
            local bodyBottom = Vector3(basePos.x, basePos.y, basePos.z)
            local bodyTop = Vector3(basePos.x, headY, basePos.z)
            -- 前后左右四条竖线
            for _, offset in ipairs({
                Vector3(radius, 0, 0), Vector3(-radius, 0, 0),
                Vector3(0, 0, radius), Vector3(0, 0, -radius),
            }) do
                debug:AddLine(bodyBottom + offset, bodyTop + offset, bodyColor, false)
            end

            -- 身体底部圆环
            debug:AddCircle(bodyBottom, Vector3.UP, radius, bodyColor, 32, false)
        end
    end
end

function UpdateDebugVisualization()
    if not debugMode_ then return end
    
    -- 更新枪口位置可视化
    if debugMuzzleNode_ and weaponAttachment_ then
        local muzzlePos = WeaponAttachment.GetMuzzlePosition(weaponAttachment_)
        if muzzlePos and muzzlePos ~= Vector3.ZERO then
            debugMuzzleNode_.enabled = true
            debugMuzzleNode_.worldPosition = muzzlePos
        else
            debugMuzzleNode_.enabled = false
        end
    elseif debugMuzzleNode_ then
        debugMuzzleNode_.enabled = false
    end
end

function UpdateWeaponPosition()
    if weaponAttachment_ then
        -- 如果调试UI激活，使用调试值覆盖
        if WeaponDebugUI.IsEnabled() then
            -- 临时覆盖modelConfig的值
            if weaponAttachment_.modelConfig then
                weaponAttachment_.modelConfig.positionOffset = WeaponDebugUI.GetPositionOffset()
                weaponAttachment_.modelConfig.muzzleOffset = WeaponDebugUI.GetMuzzleOffset()
            end
            -- 更新缩放
            if weaponAttachment_.node then
                local baseScale = WeaponDebugUI.GetScale()
                local tpOverride = WeaponAttachment.THIRD_PERSON_OVERRIDES[currentWeaponId_] or WeaponAttachment.THIRD_PERSON_OVERRIDES.default
                local scaleMultiplier = tpOverride.scaleMultiplier or 1.0
                weaponAttachment_.node.scale = baseScale * scaleMultiplier
            end
            -- 更新枪口节点位置
            if weaponAttachment_.muzzleNode then
                weaponAttachment_.muzzleNode.position = WeaponDebugUI.GetMuzzleOffset()
            end
        end
        WeaponAttachment.UpdatePosition(weaponAttachment_)
    end

    -- 更新其他玩家的武器位置
    for nodeId, attachment in pairs(otherWeapons_) do
        WeaponAttachment.UpdatePosition(attachment)
    end
end

function UpdateMouseLook(dt)
    -- ESC 暂停鼠标锁定，点击画面恢复
    -- 检测方式1: GetKeyPress 直接检测 ESC 按键（Update 阶段）
    -- 检测方式2: InputExtensions 在 KeyUp 事件中会将 mouseMode 设为 MM_FREE
    --           由于 GetKeyPress 与 KeyUp 时序不同，可能漏检，所以同时检测模式变化作为兜底
    if not mousePaused_ then
        if input:GetKeyPress(KEY_ESCAPE) or input.mouseMode == MM_FREE then
            mousePaused_ = true
            input.mouseMode = MM_FREE
            input.mouseVisible = true
        end
    end

    if mousePaused_ then
        if input:GetMouseButtonPress(MOUSEB_LEFT) then
            mousePaused_ = false
            input.mouseMode = MM_RELATIVE
        end
        return
    end

    -- 如果武器调试UI正在使用，切换鼠标模式
    local debugUIActive = WeaponDebugUI.IsEnabled()
    
    if debugUIActive then
        -- 调试UI激活时使用绝对鼠标模式
        if input.mouseMode ~= MM_ABSOLUTE then
            input.mouseMode = MM_ABSOLUTE
        end
        
        -- 处理鼠标事件
        local mousePos = input.mousePosition
        local isMouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)
        WeaponDebugUI.HandleMouseMove(mousePos.x, mousePos.y, isMouseDown)
        
        if input:GetMouseButtonPress(MOUSEB_LEFT) then
            WeaponDebugUI.HandleMouseDown(mousePos.x, mousePos.y, MOUSEB_LEFT)
        end
    else
        -- 正常游戏时使用相对鼠标模式
        if input.mouseMode ~= MM_RELATIVE then
            input.mouseMode = MM_RELATIVE
        end
        
        local mouseMove = input.mouseMove
        -- FOV 越低灵敏度越低，保持瞄准手感一致
        local fovScale = currentCameraFOV_ / Settings.Camera.normal.fov
        local sens = Settings.Input.MouseSensitivity * fovScale
        yaw_ = yaw_ + mouseMove.x * sens
        pitch_ = pitch_ + mouseMove.y * sens
        pitch_ = Shared.Clamp(pitch_, -89.0, 89.0)
    end
    
    -- F3 切换调试模式
    if input:GetKeyPress(KEY_F3) then
        debugMode_ = not debugMode_
        print("[Client] Debug mode: " .. (debugMode_ and "ON" or "OFF"))
        
        -- 立即隐藏调试节点
        if not debugMode_ and debugMuzzleNode_ then
            debugMuzzleNode_.enabled = false
        end
        
        -- 显示/隐藏武器调试球
        if weaponAttachment_ and weaponAttachment_.weaponNode then
            local debugSphere = weaponAttachment_.weaponNode:GetChild("DebugSphere", false)
            if debugSphere then
                debugSphere.enabled = debugMode_
            end
        end
    end
    
    -- F4 切换武器调试UI
    if input:GetKeyPress(KEY_F4) then
        local enabled = WeaponDebugUI.Toggle()
        print("[Client] Weapon Debug UI: " .. (enabled and "ON" or "OFF"))
    end
end

function UpdateMovement(dt)
    if myRoleNode_ == nil then return end

    local serverConn = network:GetServerConnection()
    if serverConn == nil then return end

    local controls = serverConn.controls
    controls.yaw = yaw_
    controls.pitch = pitch_

    -- 获取当前武器配置
    local weaponCfg = GetCurrentWeaponConfig()
    local fireRate = weaponCfg and weaponCfg.fireRate or 0.15

    -- 瞄准控制（PC端右键按住瞄准，换弹期间禁止瞄准）
    -- 移动端瞄准通过 Aim 切换按钮处理（toggle 模式）
    if isArmed_ and not isReloading_ then
        -- PC端：右键按住 → 瞄准，松开 → 退出（覆盖移动端 toggle 状态）
        if input:GetMouseButtonPress(MOUSEB_RIGHT) then
            isAiming_ = true
        elseif not input:GetMouseButtonDown(MOUSEB_RIGHT) and input.mouseMode == MM_RELATIVE then
            -- 仅在 PC 模式（鼠标锁定）下，松开右键退出瞄准
            isAiming_ = false
        end
    else
        isAiming_ = false
    end

    -- 射击控制（持枪时）
    -- 自动武器：按住连发；非自动武器：点击单发
    -- 支持触摸开火按钮（fireButton_）
    local isAutomatic = weaponCfg and weaponCfg.automatic or false
    local isShooting = false
    local debugUIActive = WeaponDebugUI.IsEnabled()
    local fireTouchDown = (fireButton_ ~= nil and fireButton_.isTouchPressed)
        or (fireButtonLeft_ ~= nil and fireButtonLeft_.isTouchPressed)
    local fireTouchJustPressed = fireTouchDown and not wasFireTouchPressed_
    wasFireTouchPressed_ = fireTouchDown
    -- 移动端触摸会被合成为鼠标左键事件，需要区分平台避免误射
    local isMobile = VirtualControls.IsMobile()
    if isArmed_ and not isReloading_ and not debugUIActive then
        if isAutomatic then
            if isMobile then
                isShooting = fireTouchDown
            else
                isShooting = input:GetMouseButtonDown(MOUSEB_LEFT) or fireTouchDown
            end
        else
            if isMobile then
                isShooting = fireTouchJustPressed
            else
                isShooting = input:GetMouseButtonPress(MOUSEB_LEFT) or fireTouchJustPressed
            end
        end
    end
    controls:Set(CTRL.SHOOT, isShooting)

    -- 跳跃、蹲下、走路控制（自定义按钮 + 键盘）
    local isJumping = jumpButton_ ~= nil and jumpButton_.isPressed
    controls:Set(CTRL.JUMP, isJumping)
    local crouchPressed = walkButton_ ~= nil and walkButton_.isPressed
    isCrouching_ = crouchPressed
    controls:Set(CTRL.CROUCH, crouchPressed)
    -- 走路/跑步切换：按下 Shift（toggle）时发送 RUN 标志，服务器端反转处理
    local walkPressed = runButton_ ~= nil and runButton_.isPressed
    controls:Set(CTRL.RUN, walkPressed)

    -- 射击冷却
    if shootCooldown_ > 0 then
        shootCooldown_ = shootCooldown_ - dt
    end

    -- 换弹计时
    if isReloading_ then
        reloadTimer_ = reloadTimer_ - dt
        if reloadTimer_ <= 0 then
            isReloading_ = false
            if weaponCfg then
                local reloadAmount = math.min(weaponCfg.magSize - ammoMag_, ammoReserve_)
                ammoMag_ = ammoMag_ + reloadAmount
                ammoReserve_ = ammoReserve_ - reloadAmount
                
                -- 通知服务器换弹完成
                local eventData = VariantMap()
                eventData["WeaponId"] = Variant(currentWeaponId_)
                eventData["AmmoMag"] = Variant(ammoMag_)
                eventData["AmmoReserve"] = Variant(ammoReserve_)
                network:GetServerConnection():SendRemoteEvent(EVENTS.WEAPON_RELOAD, true, eventData)
            end
        end
    end

    -- 触发射击（调试UI打开时禁止）
    local canShoot = false
    if isArmed_ and not isReloading_ and shootCooldown_ <= 0 and not debugUIActive then
        if isAutomatic then
            if isMobile then
                canShoot = fireTouchDown
            else
                canShoot = input:GetMouseButtonDown(MOUSEB_LEFT) or fireTouchDown
            end
        else
            if isMobile then
                canShoot = fireTouchJustPressed
            else
                canShoot = input:GetMouseButtonPress(MOUSEB_LEFT) or fireTouchJustPressed
            end
        end
    end
    
    if canShoot then
        if ammoMag_ > 0 then
            shootCooldown_ = fireRate
            ammoMag_ = ammoMag_ - 1

            -- 触发射击动画
            local nodeId = myRoleNode_.ID
            local data = playerAnimData_[nodeId]
            if data and data.fsm then
                data.fsm:SetTrigger("shoot")
            end

            -- 递增连射计数（在 SendShootRequest 之前，用于零散布判定）
            shotCounter_ = shotCounter_ + 1

            -- 发送射击请求到服务器（服务器创建子弹后同步给客户端）
            SendShootRequest()

            -- 应用后坐力
            ApplyRecoil()
        elseif ammoReserve_ > 0 then
            -- 自动换弹
            StartReload()
        end
    end

    -- 手动换弹
    if isArmed_ and input:GetKeyPress(KEY_R) and not isReloading_ then
        if ammoMag_ < (weaponCfg and weaponCfg.magSize or 30) and ammoReserve_ > 0 then
            StartReload()
        end
    end

    -- 切换武器（滚轮或数字键）
    if isArmed_ then
        -- 使用 mouseMoveWheel 而非 mouseMove.z
        if input.mouseMoveWheel ~= 0 then
            SwitchToNextWeapon()
            weaponPanelOpen_ = false
        end

        -- 数字键快速切换
        for i = 1, #WeaponConfig.WEAPON_ORDER do
            if input:GetKeyPress(KEY_1 + i - 1) then
                local weaponId = WeaponConfig.WEAPON_ORDER[i]
                if weaponId and weaponId ~= currentWeaponId_ then
                    -- 发送切换武器请求到服务器
                    local serverConn = network:GetServerConnection()
                    if serverConn then
                        local eventData = VariantMap()
                        eventData["WeaponId"] = Variant(weaponId)
                        serverConn:SendRemoteEvent(EVENTS.WEAPON_SWITCH, true, eventData)
                    end
                    EquipWeapon(weaponId)
                end
                weaponPanelOpen_ = false
                break
            end
        end
    end
end

--- 开始换弹
function StartReload()
    local weaponCfg = GetCurrentWeaponConfig()
    if not weaponCfg then return end

    -- 1. 先退出瞄准模式，恢复第三人称模型可见
    if isAiming_ or lastFPModeState_ then
        isAiming_ = false
        aimTransition_ = 0
        lastFPModeState_ = false
        scopeActive_ = false
        scopeProgress_ = 0
        DestroyFPGun()
        SetLocalPlayerModelVisible(true)
    end

    -- 2. 设置换弹状态
    isReloading_ = true
    reloadTimer_ = weaponCfg.reloadTime or 2.0

    -- 3. 标记待触发换弹动画（延迟到 PostUpdate 中处理，确保模型和 FSM 状态完全就绪）
    pendingReloadAnim_ = true
end

function UpdateCamera(dt)
    if myRoleNode_ == nil or cameraNode_ == nil then return end

    -- 瞄准时切换到第一人称视角
    local inFPMode = aimTransition_ > 0.01

    if inFPMode then
        -- === 第一人称模式（瞄准时） ===
        -- 目标：相机在角色头部位置，朝前方看
        local t = aimTransition_ * aimTransition_ * (3 - 2 * aimTransition_)  -- smoothstep

        -- 第一人称相机参数（蹲下时降低高度）
        local crouchDelta = isCrouching_ and Settings.Player.CrouchHeightDelta or 0
        local fpOffset = Vector3(0, Settings.Player.Height - 0.1 - crouchDelta, 0)  -- 眼睛位置（角色头顶略下）
        -- 狙击镜使用 scopeFov，普通武器使用瞄准FOV
        local weaponCfg = currentWeaponId_ and WeaponConfig.WEAPONS[currentWeaponId_]
        local fpFov = Settings.Camera.aiming.fov
        if weaponCfg and weaponCfg.hasScope and weaponCfg.scopeFov then
            fpFov = weaponCfg.scopeFov
        end
        local fpDistance = 0  -- 第一人称：距离为0

        -- 第三人称目标参数
        local tpConfig = isArmed_ and Settings.Camera.armed or Settings.Camera.normal
        local tpOffset = tpConfig.offset
        local tpFov = tpConfig.fov
        local tpDistance = tpConfig.distance

        -- 从第三人称平滑过渡到第一人称
        local lerpFactor = 1.0 - math.exp(-Settings.Camera.transitionSpeed * dt)
        local blendedOffset = currentCameraOffset_:Lerp(fpOffset, lerpFactor)
        local blendedFov = Lerp(currentCameraFOV_, fpFov, lerpFactor)
        local blendedDistance = Lerp(currentCameraDistance_, fpDistance, lerpFactor)

        currentCameraOffset_ = blendedOffset
        currentCameraFOV_ = blendedFov
        currentCameraDistance_ = blendedDistance

        -- 应用 FOV
        local camera = cameraNode_:GetComponent("Camera")
        if camera then
            camera.fov = currentCameraFOV_
        end

        -- 计算相机位置
        local rot = Quaternion(yaw_, Vector3.UP)
        local dir = rot * Quaternion(pitch_, Vector3.RIGHT)
        local eyePos = myRoleNode_.position + currentCameraOffset_

        if currentCameraDistance_ > 0.05 then
            -- 过渡中：仍有些距离
            local rayDir = dir * Vector3(0, 0, -1)
            cameraNode_.position = eyePos + rayDir * currentCameraDistance_
        else
            -- 完全第一人称：相机在眼睛位置
            cameraNode_.position = eyePos
        end
        cameraNode_.rotation = dir
    else
        -- === 第三人称模式（正常/持枪） ===
        local targetConfig
        if isArmed_ then
            targetConfig = Settings.Camera.armed
        else
            targetConfig = Settings.Camera.normal
        end

        -- 蹲下时相机 offset 高度降低
        local targetOffset = targetConfig.offset
        if isCrouching_ then
            targetOffset = Vector3(targetOffset.x, targetOffset.y - Settings.Player.CrouchHeightDelta, targetOffset.z)
        end

        -- 平滑过渡
        local lerpFactor = 1.0 - math.exp(-Settings.Camera.transitionSpeed * dt)
        currentCameraDistance_ = Lerp(currentCameraDistance_, targetConfig.distance, lerpFactor)
        currentCameraOffset_ = currentCameraOffset_:Lerp(targetOffset, lerpFactor)
        currentCameraFOV_ = Lerp(currentCameraFOV_, targetConfig.fov, lerpFactor)

        -- 应用 FOV
        local camera = cameraNode_:GetComponent("Camera")
        if camera then
            camera.fov = currentCameraFOV_
        end

        -- 计算相机位置
        local rot = Quaternion(yaw_, Vector3.UP)
        local dir = rot * Quaternion(pitch_, Vector3.RIGHT)
        local aimPoint = myRoleNode_.position + rot * currentCameraOffset_
        local rayDir = dir * Vector3(0, 0, -1)
        local distance = currentCameraDistance_

        -- 墙壁碰撞检测
        local physicsWorld = scene_:GetComponent("PhysicsWorld")
        if physicsWorld then
            local result = physicsWorld:RaycastSingle(Ray(aimPoint, rayDir), distance, 1)
            if result.body then
                distance = math.max(1.0, result.distance - 0.2)
            end
        end

        cameraNode_.position = aimPoint + rayDir * distance
        cameraNode_.rotation = dir
    end
end

function UpdateAllAnimations()
    for nodeId, data in pairs(playerAnimData_) do
        local roleNode = scene_:GetNode(nodeId)
        if roleNode then
            -- 死亡中的角色跳过动画参数更新
            if data.isDying then
                goto continue
            end

            local character = roleNode:GetComponent("CharacterComponent")
            if character and data.fsm then
                -- 同步武器状态
                local nodeArmed = IsNodeArmed(roleNode)
                if data.isArmed ~= nodeArmed then
                    SetPlayerArmed(nodeId, nodeArmed)
                end

                -- 更新本地 isArmed 状态
                if myRoleNode_ and roleNode.ID == myRoleNode_.ID then
                    isArmed_ = nodeArmed
                end

                -- 更新动画参数
                local moveSpeed = character.moveSpeed
                data.fsm:SetFloat("moveSpeed", moveSpeed)
                data.fsm:SetBool("isGrounded", character.onGround)

                -- 设置蹲下状态（本地玩家用本地状态，其他玩家/NPC从节点变量读取）
                if myRoleNode_ and roleNode.ID == myRoleNode_.ID then
                    data.fsm:SetBool("isCrouching", isCrouching_)
                else
                    local crouchVar = roleNode:GetVar(VARS.IS_CROUCHING)
                    local remoteCrouch = (not crouchVar:IsEmpty()) and crouchVar:GetBool() or false
                    data.fsm:SetBool("isCrouching", remoteCrouch)
                end

                -- 计算移动方向
                local direction = 0
                if moveSpeed > 0.1 then
                    local kcc = roleNode:GetComponent("KinematicCharacterController")
                    if kcc then
                        local velocity = kcc:GetLinearVelocity()
                        local playerYaw = roleNode.worldRotation:YawAngle()
                        local moveAngle = math.deg(math.atan(velocity.x, velocity.z))
                        direction = moveAngle - playerYaw
                        while direction > 180 do direction = direction - 360 end
                        while direction < -180 do direction = direction + 360 end
                        if math.abs(direction) > 100 then
                            if direction > 0 then
                                direction = direction - 180
                            else
                                direction = direction + 180
                            end
                        end
                    end
                end
                data.fsm:SetFloat("direction", direction)

                -- 检测原地转向
                local characterYaw = roleNode.worldRotation:YawAngle()
                local yawDelta = characterYaw - (data.lastYaw or 0)
                if yawDelta > 180 then yawDelta = yawDelta - 360 end
                if yawDelta < -180 then yawDelta = yawDelta + 360 end
                local isTurning = moveSpeed < 0.1 and math.abs(yawDelta) > 0.5
                data.fsm:SetBool("isTurning", isTurning)
                data.lastYaw = characterYaw

                if character.jumpStarted then
                    data.fsm:SetTrigger("jump")
                end

                -- 更新 AimOffset
                if data.aimOffset then
                    data.aimOffset:SetEnabled(data.isArmed)
                    if data.isArmed then
                        local aPitch, aYaw
                        if myRoleNode_ and roleNode.ID == myRoleNode_.ID then
                            aPitch = pitch_
                            aYaw = yaw_
                        else
                            -- 其他玩家：从 CharacterComponent 读取同步的 pitch/yaw
                            aPitch = character.controls.pitch
                            aYaw = character.controls.yaw
                        end
                        data.aimOffset:SetTargetPitch(aPitch)
                        local characterYaw = roleNode.worldRotation:YawAngle()
                        local relativeYaw = aYaw - characterYaw
                        while relativeYaw > 180 do relativeYaw = relativeYaw - 360 end
                        while relativeYaw < -180 do relativeYaw = relativeYaw + 360 end
                        data.aimOffset:SetTargetYaw(relativeYaw)
                    end
                end
            end
        else
            playerAnimData_[nodeId] = nil
            -- 清理离开玩家的武器附件
            if otherWeapons_[nodeId] then
                WeaponAttachment.DetachWeapon(otherWeapons_[nodeId])
                otherWeapons_[nodeId] = nil
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- 命中特效（已迁移到 HitEffects 模块）
-- ============================================================================
-- 特效创建和更新由 HitEffects 模块处理

-- ============================================================================
-- NanoVG UI
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if nvgCtx_ == nil then return end

    local gfx = GetGraphics()
    local width = gfx:GetWidth()
    local height = gfx:GetHeight()

    nvgBeginFrame(nvgCtx_, width, height, 1.0)

    -- 绘制伤害闪红效果（在最底层）
    if damageFlashAlpha_ > 0 then
        DrawDamageFlash(nvgCtx_, width, height)
    end

    DrawHealthBar(nvgCtx_, width, height)
    if isArmed_ then
        if scopeActive_ then
            DrawSniperScope(nvgCtx_, width, height)
        else
            DrawCrosshair(nvgCtx_, width / 2, height / 2)
        end
        DrawAmmoDisplay(nvgCtx_, width, height)
    end
    if isDead_ then
        DrawDeathScreen(nvgCtx_, width, height)
    end
    if debugMode_ then
        DrawDebugInfo(nvgCtx_, width, height)
    end
    if weaponPanelOpen_ then
        DrawWeaponPanel(nvgCtx_, width, height)
    end
    if #serverLogs_ > 0 then
        DrawServerLogs(nvgCtx_, width, height)
    end
    
    -- 绘制武器调试UI
    WeaponDebugUI.Render(nvgCtx_)

    nvgEndFrame(nvgCtx_)
end

function DrawHealthBar(ctx, width, height)
    local barWidth, barHeight = 200, 20
    local x, y = 20, height - 50
    local healthPercent = health_ / maxHealth_

    -- 背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x, y, barWidth, barHeight, 4)
    nvgFillColor(ctx, nvgRGBA(50, 50, 50, 180))
    nvgFill(ctx)

    -- 血条颜色
    local r, g, b = 200, 50, 50
    if healthPercent > 0.5 then r, g, b = 50, 200, 50
    elseif healthPercent > 0.25 then r, g, b = 200, 200, 50 end

    -- 血条
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x + 2, y + 2, (barWidth - 4) * healthPercent, barHeight - 4, 2)
    nvgFillColor(ctx, nvgRGBA(r, g, b, 220))
    nvgFill(ctx)

    -- 文字
    if fontNormal_ ~= -1 then
        nvgFontFaceId(ctx, fontNormal_)
        nvgFontSize(ctx, 16)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(ctx, x + barWidth / 2, y + barHeight / 2, health_ .. " / " .. maxHealth_)
    end
end

-- 绘制伤害闪红效果
function DrawDamageFlash(ctx, width, height)
    local alpha = math.floor(damageFlashAlpha_ * 255)
    
    -- 全屏红色渐变遮罩（边缘更红，中心透明）
    local cx, cy = width / 2, height / 2
    local radius = math.max(width, height)
    
    -- 径向渐变：中心透明，边缘红色
    local innerColor = nvgRGBA(255, 0, 0, 0)
    local outerColor = nvgRGBA(200, 0, 0, alpha)
    local gradient = nvgRadialGradient(ctx, cx, cy, radius * 0.3, radius, innerColor, outerColor)
    
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, width, height)
    nvgFillPaint(ctx, gradient)
    nvgFill(ctx)
end

-- 将角度转换为屏幕像素（基于 FOV 和屏幕高度）
function AngleToPixels(angleDeg, screenHeight, fovDeg)
    -- 公式: pixels = tan(angle) * (screenHeight / 2) / tan(fov / 2)
    local angleRad = math.rad(angleDeg)
    local fovRad = math.rad(fovDeg)
    return math.tan(angleRad) * (screenHeight / 2) / math.tan(fovRad / 2)
end

--- 绘制狙击镜瞄准UI（黑色遮罩+圆形瞄准镜）
function DrawSniperScope(ctx, screenW, screenH)
    if not scopeActive_ then return end

    local cx = screenW / 2
    local cy = screenH / 2

    -- 瞄准镜半径（基于屏幕短边）
    local scopeRadius = math.min(screenW, screenH) * 0.4

    -- 1. 黑色遮罩（整个屏幕挖掉中心圆）
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, screenW, screenH)
    nvgPathWinding(ctx, NVG_HOLE)
    nvgCircle(ctx, cx, cy, scopeRadius)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 255))
    nvgFill(ctx)

    -- 2. 瞄准镜边框
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, scopeRadius)
    nvgStrokeWidth(ctx, 4)
    nvgStrokeColor(ctx, nvgRGBA(30, 30, 35, 255))
    nvgStroke(ctx)

    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, scopeRadius - 3)
    nvgStrokeWidth(ctx, 1)
    nvgStrokeColor(ctx, nvgRGBA(60, 60, 70, 255))
    nvgStroke(ctx)

    -- 3. 十字准星
    local crossLen = scopeRadius * 0.8
    local crossGap = 15
    local crossWidth = 1.5

    nvgStrokeWidth(ctx, crossWidth)
    nvgStrokeColor(ctx, nvgRGBA(20, 20, 20, 255))

    -- 水平线（左）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - crossLen, cy)
    nvgLineTo(ctx, cx - crossGap, cy)
    nvgStroke(ctx)
    -- 水平线（右）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx + crossGap, cy)
    nvgLineTo(ctx, cx + crossLen, cy)
    nvgStroke(ctx)
    -- 垂直线（上）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - crossLen)
    nvgLineTo(ctx, cx, cy - crossGap)
    nvgStroke(ctx)
    -- 垂直线（下）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy + crossGap)
    nvgLineTo(ctx, cx, cy + crossLen)
    nvgStroke(ctx)

    -- 4. 刻度线
    local tickSpacing = scopeRadius * 0.15
    local tickLen = 8
    nvgStrokeWidth(ctx, 1)

    for i = 1, 4 do
        local offset = i * tickSpacing
        -- 左侧
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx - crossGap - offset, cy - tickLen / 2)
        nvgLineTo(ctx, cx - crossGap - offset, cy + tickLen / 2)
        nvgStroke(ctx)
        -- 右侧
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx + crossGap + offset, cy - tickLen / 2)
        nvgLineTo(ctx, cx + crossGap + offset, cy + tickLen / 2)
        nvgStroke(ctx)
    end

    -- 垂直刻度（下方，用于测距）
    for i = 1, 4 do
        local offset = i * tickSpacing
        local tLen = tickLen * (1 - i * 0.15)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx - tLen / 2, cy + crossGap + offset)
        nvgLineTo(ctx, cx + tLen / 2, cy + crossGap + offset)
        nvgStroke(ctx)
    end

    -- 5. 中心红点
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, 2)
    nvgFillColor(ctx, nvgRGBA(255, 50, 50, 255))
    nvgFill(ctx)

    -- 6. 镜片暗角效果
    local innerRadius = scopeRadius * 0.7
    local gradient = nvgRadialGradient(ctx, cx, cy, innerRadius, scopeRadius,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 60))
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, scopeRadius)
    nvgFillPaint(ctx, gradient)
    nvgFill(ctx)
end

function DrawCrosshair(ctx, cx, cy)
    -- 获取屏幕尺寸和 FOV
    local gfx = GetGraphics()
    local screenHeight = gfx:GetHeight()
    local fov = currentCameraFOV_ or 45.0
    
    -- 将散布角度转换为像素
    local spreadPixels = AngleToPixels(crosshairSpreadDeg_, screenHeight, fov)
    
    -- 限制准心扩散最大为画面高度的 5%
    local maxSpreadPixels = screenHeight * 0.05
    spreadPixels = math.min(spreadPixels, maxSpreadPixels)
    
    -- 动态参数
    local size = isAiming_ and 12 or 18
    local thickness = 2.5
    local baseGap = isAiming_ and 4 or 8
    local gap = baseGap + spreadPixels
    
    -- 击中反馈：颜色和大小变化
    local isHit = crosshairHitTimer_ > 0
    local hitProgress = isHit and (crosshairHitTimer_ / CROSSHAIR_HIT_DURATION) or 0
    
    -- 基础颜色（科技蓝）
    local r, g, b = 80, 200, 255
    if isHit then
        -- 击中时变为亮红色
        r = 255
        g = math.floor(80 + 120 * (1 - hitProgress))
        b = math.floor(80 * (1 - hitProgress))
    elseif isAiming_ then
        -- 瞄准时变为橙色
        r, g, b = 255, 150, 50
    end
    
    -- 击中时准星收缩
    local hitScale = 1.0 - hitProgress * 0.3
    local currentGap = gap * hitScale
    local currentSize = size * (1.0 + hitProgress * 0.2)
    
    -- ========== 主十字线 ==========
    nvgStrokeWidth(ctx, thickness)
    nvgStrokeColor(ctx, nvgRGBA(r, g, b, 255))
    nvgLineCap(ctx, NVG_ROUND)
    
    -- 上
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - currentGap - currentSize)
    nvgLineTo(ctx, cx, cy - currentGap)
    nvgStroke(ctx)
    -- 下
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy + currentGap)
    nvgLineTo(ctx, cx, cy + currentGap + currentSize)
    nvgStroke(ctx)
    -- 左
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - currentGap - currentSize, cy)
    nvgLineTo(ctx, cx - currentGap, cy)
    nvgStroke(ctx)
    -- 右
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx + currentGap, cy)
    nvgLineTo(ctx, cx + currentGap + currentSize, cy)
    nvgStroke(ctx)
    
    -- ========== 斜角装饰线（科幻风格）==========
    local cornerOffset = currentGap * 0.7
    local cornerLen = 6
    nvgStrokeWidth(ctx, 1.5)
    nvgStrokeColor(ctx, nvgRGBA(r, g, b, 150))
    
    -- 四个斜角
    local corners = {
        { cx - cornerOffset, cy - cornerOffset, -1, -1 },
        { cx + cornerOffset, cy - cornerOffset,  1, -1 },
        { cx - cornerOffset, cy + cornerOffset, -1,  1 },
        { cx + cornerOffset, cy + cornerOffset,  1,  1 },
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, c[1], c[2])
        nvgLineTo(ctx, c[1] + c[3] * cornerLen, c[2] + c[4] * cornerLen)
        nvgStroke(ctx)
    end
    
    -- ========== 中心点 ==========
    -- 中心亮点
    local dotRadius = isHit and 3.5 or 2.5
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, dotRadius)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgFill(ctx)
    
    -- 中心小圆环
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, 5)
    nvgStrokeColor(ctx, nvgRGBA(r, g, b, 180))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
end

function DrawAmmoDisplay(ctx, width, height)
    if not currentWeaponId_ then return end

    local weaponCfg = GetCurrentWeaponConfig()
    if not weaponCfg then return end

    local x = width - 200
    local y = height - 80

    if fontNormal_ ~= -1 then
        nvgFontFaceId(ctx, fontNormal_)

        -- 武器名称
        nvgFontSize(ctx, 16)
        nvgFillColor(ctx, nvgRGBA(200, 200, 200, 200))
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(ctx, x, y, weaponCfg.nameZh or weaponCfg.name)

        -- 弹药数量
        nvgFontSize(ctx, 32)
        local ammoColor = ammoMag_ > 0 and nvgRGBA(255, 255, 255, 255) or nvgRGBA(255, 100, 100, 255)
        nvgFillColor(ctx, ammoColor)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(ctx, x, y + 20, tostring(ammoMag_))

        -- 备弹
        nvgFontSize(ctx, 20)
        nvgFillColor(ctx, nvgRGBA(150, 150, 150, 200))
        nvgText(ctx, x + 50, y + 28, "/ " .. tostring(ammoReserve_))

        -- 换弹提示
        if isReloading_ then
            nvgFontSize(ctx, 14)
            nvgFillColor(ctx, nvgRGBA(255, 200, 100, 255))
            nvgText(ctx, x, y + 55, "换弹中...")
        elseif ammoMag_ == 0 and ammoReserve_ > 0 then
            nvgFontSize(ctx, 14)
            nvgFillColor(ctx, nvgRGBA(255, 100, 100, 255))
            nvgText(ctx, x, y + 55, "按 R 换弹")
        end
    end
end

function DrawDeathScreen(ctx, width, height)
    -- 红色遮罩
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, width, height)
    nvgFillColor(ctx, nvgRGBA(100, 0, 0, 150))
    nvgFill(ctx)

    if fontNormal_ ~= -1 then
        nvgFontFaceId(ctx, fontNormal_)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        nvgFontSize(ctx, 48)
        nvgFillColor(ctx, nvgRGBA(255, 50, 50, 255))
        nvgText(ctx, width / 2, height / 2 - 30, "YOU DIED")

        nvgFontSize(ctx, 24)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
        nvgText(ctx, width / 2, height / 2 + 30, "等待重生...")
    end
end

-- ============================================================================
-- 武器选择面板
-- ============================================================================

function DrawServerLogs(ctx, width, height)
    local lineH = 18
    local x = 10
    local y = 80  -- 左上角偏下，避开其他 UI

    nvgFontFaceId(ctx, fontNormal_)
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    for i, entry in ipairs(serverLogs_) do
        -- 最后 1 秒淡出
        local alpha = entry.time < 1.0 and math.floor(entry.time * 200) or 200
        -- 半透明背景条
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, 500, lineH)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.4)))
        nvgFill(ctx)
        -- 文字
        nvgFillColor(ctx, nvgRGBA(120, 255, 120, alpha))
        nvgText(ctx, x + 4, y + 2, entry.msg)
        y = y + lineH
    end
end

function DrawWeaponPanel(ctx, width, height)
    if fontNormal_ == -1 then return end

    -- 面板布局参数
    local itemW = 180
    local itemH = 52
    local gap = 6
    local weaponOrder = WeaponConfig.WEAPON_ORDER
    local count = #weaponOrder
    local panelPad = 10
    local panelH = count * itemH + (count - 1) * gap + panelPad * 2
    local panelW = itemW + panelPad * 2

    -- 面板位置：左侧换枪按钮上方展开（屏幕左侧）
    local panelX = 30
    local panelBottomY = height / 2 - 100  -- 换枪按钮上方
    local panelY = panelBottomY - panelH

    -- 半透明背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX, panelY, panelW, panelH, 8)
    nvgFillColor(ctx, nvgRGBA(20, 22, 30, 220))
    nvgFill(ctx)

    -- 边框
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX, panelY, panelW, panelH, 8)
    nvgStrokeWidth(ctx, 1.5)
    nvgStrokeColor(ctx, nvgRGBA(100, 110, 130, 180))
    nvgStroke(ctx)

    -- 记录每个武器项的区域（供触摸检测用）
    weaponPanelItems_ = {}

    for i, wid in ipairs(weaponOrder) do
        local cfg = WeaponConfig.WEAPONS[wid]
        if not cfg then goto continue end

        local ix = panelX + panelPad
        local iy = panelY + panelPad + (i - 1) * (itemH + gap)

        -- 是否选中
        local selected = (wid == currentWeaponId_)

        -- 背景
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, ix, iy, itemW, itemH, 6)
        if selected then
            nvgFillColor(ctx, nvgRGBA(80, 140, 255, 100))
        else
            nvgFillColor(ctx, nvgRGBA(50, 55, 70, 150))
        end
        nvgFill(ctx)

        -- 选中高亮边框
        if selected then
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix, iy, itemW, itemH, 6)
            nvgStrokeWidth(ctx, 2)
            nvgStrokeColor(ctx, nvgRGBA(80, 180, 255, 220))
            nvgStroke(ctx)
        end

        -- 序号
        nvgFontFaceId(ctx, fontNormal_)
        nvgFontSize(ctx, 14)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(160, 170, 190, 200))
        nvgText(ctx, ix + 8, iy + 6, tostring(i))

        -- 武器名称
        nvgFontSize(ctx, 18)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if selected then
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(ctx, nvgRGBA(220, 220, 230, 230))
        end
        nvgText(ctx, ix + 28, iy + itemH / 2, cfg.nameZh or cfg.name)

        -- 武器类型标签（右侧）
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(140, 150, 170, 180))
        local typeLabel = cfg.automatic and "Auto" or "Semi"
        if cfg.bulletsPerShot and cfg.bulletsPerShot > 1 then
            typeLabel = "SG"
        end
        nvgText(ctx, ix + itemW - 10, iy + itemH / 2, typeLabel)

        -- 记录点击区域
        table.insert(weaponPanelItems_, {
            x = ix, y = iy, w = itemW, h = itemH, weaponId = wid
        })

        ::continue::
    end
end

--- 处理武器面板触摸/鼠标点击
local weaponPanelTouches_ = {}  -- 已知的触摸 ID 集合，用于检测新触摸

function HandleWeaponPanelInput()
    if not weaponPanelOpen_ then
        weaponPanelTouches_ = {}
        return
    end
    if #weaponPanelItems_ == 0 then return end

    local clickX, clickY = nil, nil

    -- PC 端鼠标点击（GetMouseButtonPress = 刚按下这一帧）
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        local pos = input.mousePosition
        clickX = pos.x
        clickY = pos.y
    end

    -- 移动端：检测新触摸（上帧不存在、本帧出现的 touchID）
    local currentTouches = {}
    local numTouches = input.numTouches
    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        local tid = touch.touchID
        currentTouches[tid] = true
        -- 如果是新触摸且未被 VirtualControls 占用
        if not weaponPanelTouches_[tid] and not VirtualControls.IsTouchOccupied(tid) then
            clickX = touch.position.x
            clickY = touch.position.y
        end
    end
    weaponPanelTouches_ = currentTouches

    if not clickX then return end

    -- 检查点击是否在某个武器项上
    local hitWeapon = false
    for _, item in ipairs(weaponPanelItems_) do
        if clickX >= item.x and clickX <= item.x + item.w
            and clickY >= item.y and clickY <= item.y + item.h then
            -- 选中该武器
            if item.weaponId ~= currentWeaponId_ then
                local serverConn = network:GetServerConnection()
                if serverConn then
                    local evtData = VariantMap()
                    evtData["WeaponId"] = Variant(item.weaponId)
                    serverConn:SendRemoteEvent(EVENTS.WEAPON_SWITCH, true, evtData)
                end
                EquipWeapon(item.weaponId)
            end
            weaponPanelOpen_ = false  -- 选择任何武器（含当前武器）都关闭面板
            hitWeapon = true
            break
        end
    end

    -- 点击面板外部 → 关闭面板
    if not hitWeapon then
        local firstItem = weaponPanelItems_[1]
        local lastItem = weaponPanelItems_[#weaponPanelItems_]
        local panelX = firstItem.x - 10
        local panelY = firstItem.y - 10
        local panelR = firstItem.x + firstItem.w + 10
        local panelB = lastItem.y + lastItem.h + 10
        if clickX < panelX or clickX > panelR or clickY < panelY or clickY > panelB then
            weaponPanelOpen_ = false
        end
    end
end

function DrawDebugInfo(ctx, width, height)
    if fontNormal_ == -1 then return end
    
    nvgFontFaceId(ctx, fontNormal_)
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    
    local x = 10
    local y = 10
    local lineHeight = 18
    
    -- 背景（动态高度：基础120 + 角色数据区域）
    local animCount = 0
    for _ in pairs(playerAnimData_) do animCount = animCount + 1 end
    local bgHeight = 160 + (animCount + 1) * 18
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x - 5, y - 5, 280, bgHeight, 4)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
    nvgFill(ctx)
    
    -- 标题
    nvgFillColor(ctx, nvgRGBA(100, 255, 100, 255))
    nvgText(ctx, x, y, "[DEBUG MODE] F3 关闭")
    y = y + lineHeight
    
    -- 碰撞盒状态
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
    nvgText(ctx, x, y, "碰撞盒: 显示中 (绿色线框)")
    y = y + lineHeight
    
    -- 枪口位置
    local muzzleStatus = "未装备武器"
    if weaponAttachment_ then
        local muzzlePos = WeaponAttachment.GetMuzzlePosition(weaponAttachment_)
        if muzzlePos then
            muzzleStatus = string.format("(%.2f, %.2f, %.2f)", muzzlePos.x, muzzlePos.y, muzzlePos.z)
        end
    end
    nvgText(ctx, x, y, "枪口位置: " .. muzzleStatus)
    y = y + lineHeight
    
    -- 准星扩散
    nvgText(ctx, x, y, string.format("准星扩散: %.2f°", crosshairSpreadDeg_))
    y = y + lineHeight
    
    -- 后坐力
    nvgText(ctx, x, y, string.format("后坐力: P=%.2f Y=%.2f [%s]", 
        recoilState_.currentPitch, recoilState_.currentYaw, recoilState_.phase))
    y = y + lineHeight
    
    -- 瞄准状态
    nvgText(ctx, x, y, "瞄准: " .. (isAiming_ and "是" or "否") .. " | 持枪: " .. (isArmed_ and "是" or "否"))
    y = y + lineHeight + 5

    -- 所有角色的 isDying 状态
    nvgFillColor(ctx, nvgRGBA(255, 200, 0, 255))
    nvgText(ctx, x, y, "[角色死亡状态]")
    y = y + lineHeight
    local count = 0
    for nodeId, data in pairs(playerAnimData_) do
        count = count + 1
        local nodeName = "?"
        if scene_ then
            local n = scene_:GetNode(nodeId)
            if n then nodeName = n.name end
        end
        local dyingStr = data.isDying and "DYING" or "alive"
        local color = data.isDying and nvgRGBA(255, 80, 80, 255) or nvgRGBA(100, 255, 100, 255)
        nvgFillColor(ctx, color)
        nvgText(ctx, x, y, string.format("%s (id=%d): %s", nodeName, nodeId, dyingStr))
        y = y + lineHeight
    end
    if count == 0 then
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 150))
        nvgText(ctx, x, y, "(无角色数据)")
    end
end

-- ============================================================================
-- 延迟执行
-- ============================================================================

function DelayOneFrame(callback)
    table.insert(pendingCallbacks_, callback)
end

function ProcessPendingCallbacks()
    if #pendingCallbacks_ > 0 then
        local callbacks = pendingCallbacks_
        pendingCallbacks_ = {}
        for _, cb in ipairs(callbacks) do cb() end
    end
end

-- ============================================================================
-- 全局入口（引擎要求）
-- ============================================================================

function Start()
    Client.Start()
end

function Stop()
    Client.Stop()
end

return Client
