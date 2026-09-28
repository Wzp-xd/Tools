-- ============================================================================
-- Server.lua - 多人游戏服务端逻辑
-- 处理玩家连接、角色分配、战斗计算、状态同步
-- ============================================================================

local Server = {}
local Shared = require("network.Shared")
local WeaponConfig = require "network.modules.WeaponConfig"

require "LuaScripts/Utilities/Sample"

-- ============================================================================
-- Headless 模式 Mock
-- ============================================================================

if GetGraphics() == nil then
    local mockGraphics = {
        SetWindowIcon = function() end,
        SetWindowTitleAndIcon = function() end,
        GetWidth = function() return 1920 end,
        GetHeight = function() return 1080 end,
    }
    function GetGraphics() return mockGraphics end
    graphics = mockGraphics
    console = { background = {} }
    function GetConsole() return console end
    debugHud = {}
    function GetDebugHud() return debugHud end
end

-- ============================================================================
-- 变量
-- ============================================================================

local scene_ = nil
local maxPlayers_ = Shared.Settings.Network.MaxPlayers

-- 角色池（预创建）
local rolePool_ = {}
local roleAssignments_ = {}

-- 连接数据
local connectionRoles_ = {}
local serverConnections_ = {}

-- 游戏数据（按 roleId 索引）
local serverHealth_ = {}
local serverShootCooldown_ = {}

local serverWeapons_ = {}  -- 武器状态 { weaponId, ammoMag, ammoReserve }
local serverCrosshairSpread_ = {}  -- 准星扩散值（用于子弹散布计算）
local serverShotCounter_ = {}  -- 连射计数器（第1、4、7...枪0散布）
local serverCrouchState_ = {}  -- 蹲下状态（按 roleId 索引）
local HEAD_HITBOX_PREFIX = "HeadHitbox_"  -- 蹲下头部碰撞球前缀

-- 服务器端子弹列表（实时碰撞检测）
local serverBullets_ = {}
local bulletIdCounter_ = 0

-- 延迟回调
local pendingCallbacks_ = {}
local delayedCallbacks_ = {}

-- 移动靶同步计时器
local targetSyncTimer_ = 0
local TARGET_SYNC_INTERVAL = 0.5  -- 每0.5秒同步一次

-- 快捷引用
local Settings = Shared.Settings
local EVENTS = Shared.EVENTS
local CTRL = Shared.CTRL
local VARS = Shared.VARS

-- ============================================================================
-- 入口
-- ============================================================================

function Server.Start()
    SampleStart()

    Shared.RegisterEvents()
    scene_ = Shared.CreateScene(true)

    CreateRolePool()

    SubscribeToEvent(EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(EVENTS.WEAPON_SWITCH, "HandleWeaponSwitch")
    SubscribeToEvent(EVENTS.WEAPON_RELOAD, "HandleWeaponReload")
    SubscribeToEvent(EVENTS.SHOOT_REQUEST, "HandleShootRequest")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent("Update", "HandleUpdate")

    print("[Server] Started with " .. maxPlayers_ .. " max players")
end

function Server.Stop()
    print("[Server] Stopped")
end

-- ============================================================================
-- 蹲下头部碰撞球（爆头判定用）
-- ============================================================================

--- 创建或移除蹲下时的头部碰撞球
--- @param roleNode Node 角色根节点
--- @param roleId number 角色ID
--- @param enabled boolean true=创建 false=移除
function SetCrouchHeadHitbox(roleNode, roleId, enabled)
    local hitboxName = HEAD_HITBOX_PREFIX .. roleId
    local existing = roleNode:GetChild(hitboxName, false)

    if enabled then
        if existing then return end
        local hitboxNode = roleNode:CreateChild(hitboxName, LOCAL)
        hitboxNode.position = Vector3(0, 1.35, 0.3)

        local body = hitboxNode:CreateComponent("RigidBody", LOCAL)
        body:SetCollisionLayerAndMask(CollisionLayerCharacter, CollisionMaskCharacter)
        body.mass = 1.0
        body:SetLinearFactor(Vector3.ZERO)
        body:SetAngularFactor(Vector3.ZERO)
        body:SetTrigger(true)

        local shape = hitboxNode:CreateComponent("CollisionShape", LOCAL)
        shape:SetSphere(0.6)
    else
        if existing then
            existing:Remove()
        end
    end
end

-- ============================================================================
-- 角色池
-- ============================================================================

function CreateRolePool()
    for roleId = 1, maxPlayers_ do
        local spawnPos = Shared.GetSpawnPointByIndex(roleId)
        local roleNode = CreatePlayerRole(scene_, roleId, spawnPos)

        rolePool_[roleId] = roleNode
        roleAssignments_[roleId] = nil

        serverHealth_[roleId] = { current = Settings.Combat.MaxHealth, max = Settings.Combat.MaxHealth }
        serverShootCooldown_[roleId] = 0
        serverCrosshairSpread_[roleId] = 0  -- 准星扩散初始值
        serverShotCounter_[roleId] = 0  -- 连射计数器初始值
        -- NPC 50% 概率蹲下
        local startCrouching = math.random() < 0.5
        serverCrouchState_[roleId] = startCrouching
        roleNode:SetVar(VARS.IS_CROUCHING, Variant(startCrouching))
        if startCrouching then
            local character = roleNode:GetComponent("CharacterComponent")
            if character then
                character:SetWalkSpeed(Settings.Player.WalkSpeed * Settings.Player.CrouchSpeedMultiplier)
                character:SetRunSpeed(Settings.Player.RunSpeed * Settings.Player.CrouchSpeedMultiplier)
            end
            SetCrouchHeadHitbox(roleNode, roleId, true)
            print("[Server] Role_" .. roleId .. " starts crouching")
        end

        -- 初始化武器状态（使用默认武器）
        local defaultWeaponId = Settings.Combat.DefaultWeapon
        local weaponCfg = WeaponConfig.WEAPONS[defaultWeaponId]
        serverWeapons_[roleId] = {
            weaponId = defaultWeaponId,
            ammoMag = weaponCfg and weaponCfg.magSize or 30,
            ammoReserve = (weaponCfg and weaponCfg.magSize or 30) * 3,
        }

        print("[Server] Created Role_" .. roleId .. " (ID: " .. roleNode.ID .. ")")
    end
end

function CreatePlayerRole(scene, roleId, spawnPos)
    local roleNode = scene:CreateChild("Role_" .. roleId, REPLICATED)
    roleNode.position = spawnPos

    -- 刚体
    local body = roleNode:CreateComponent("RigidBody", REPLICATED)
    body:SetCollisionLayerAndMask(CollisionLayerCharacter, CollisionMaskCharacter)
    body.mass = 1.0
    body:SetLinearFactor(Vector3.ZERO)
    body:SetAngularFactor(Vector3.ZERO)
    body:SetCollisionEventMode(COLLISION_ALWAYS)

    -- 碰撞形状（身体）
    local shape = roleNode:CreateComponent("CollisionShape", REPLICATED)
    shape:SetCapsule(Settings.Player.Radius * 2, Settings.Player.Height,
                     Vector3(0, Settings.Player.Height / 2, 0))

    -- 运动学控制器
    local kcc = roleNode:CreateComponent("KinematicCharacterController", LOCAL)
    kcc:SetCollisionLayerAndMask(CollisionLayerKinematic, CollisionMaskKinematic)
    kcc:SetJumpSpeed(8.0)

    -- 角色组件
    local character = roleNode:CreateComponent("CharacterComponent", REPLICATED)
    character:SetWalkSpeed(Settings.Player.WalkSpeed)
    character:SetRunSpeed(Settings.Player.RunSpeed)
    character:SetEnableWalkMode(true)
    character.autoRotateToMoveDir = false

    -- 标记为角色节点
    roleNode:SetVar(VARS.IS_ROLE, Variant(true))
    roleNode:SetVar(VARS.IS_ARMED, Variant(true))  -- 默认端枪状态

    return roleNode
end

function FindFreeRole()
    for roleId = 1, maxPlayers_ do
        if roleAssignments_[roleId] == nil then
            return roleId
        end
    end
    return nil
end

function ResetRoleState(roleId)
    local roleNode = rolePool_[roleId]
    if roleNode == nil then return end

    roleNode.position = Shared.GetSpawnPointByIndex(roleId)

    serverHealth_[roleId] = { current = Settings.Combat.MaxHealth, max = Settings.Combat.MaxHealth }
    serverShootCooldown_[roleId] = 0
    serverCrosshairSpread_[roleId] = 0  -- 重置准星扩散
    serverShotCounter_[roleId] = 0  -- 重置连射计数

    local character = roleNode:GetComponent("CharacterComponent")
    if character then
        character.autoRotateToMoveDir = false
        character.rotationSpeed = 1440.0
    end

    -- NPC（无玩家控制）：50% 概率蹲下；玩家角色：始终站立
    local isCrouching = false
    if roleAssignments_[roleId] == nil then
        isCrouching = math.random() < 0.5
    end
    serverCrouchState_[roleId] = isCrouching
    roleNode:SetVar(VARS.IS_CROUCHING, Variant(isCrouching))
    SetCrouchHeadHitbox(roleNode, roleId, isCrouching)
    if character then
        if isCrouching then
            character:SetWalkSpeed(Settings.Player.WalkSpeed * Settings.Player.CrouchSpeedMultiplier)
            character:SetRunSpeed(Settings.Player.RunSpeed * Settings.Player.CrouchSpeedMultiplier)
        else
            character:SetWalkSpeed(Settings.Player.WalkSpeed)
            character:SetRunSpeed(Settings.Player.RunSpeed)
        end
    end
end

-- ============================================================================
-- 连接处理
-- ============================================================================

function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    BroadcastLog("[Server] ClientReady received")

    connection.scene = scene_

    local connKey = tostring(connection)
    local roleId = FindFreeRole()

    if roleId == nil then
        BroadcastLog("[Server] Server full, rejecting connection")
        connection:Disconnect()
        return
    end

    local roleNode = rolePool_[roleId]
    BroadcastLog("[Server] Assigning Role_" .. roleId .. " (ID: " .. roleNode.ID .. ")")

    roleAssignments_[roleId] = connKey
    connectionRoles_[connKey] = roleId
    serverConnections_[connKey] = connection

    roleNode:SetOwner(connection)
    ResetRoleState(roleId)

    -- 延迟发送角色分配
    local nodeId = roleNode.ID
    local conn = connection
    DelayOneFrame(function()
        local assignData = VariantMap()
        assignData["NodeId"] = Variant(nodeId)
        conn:SendRemoteEvent(EVENTS.ASSIGN_ROLE, true, assignData)
        BroadcastLog("[Server] Sent ASSIGN_ROLE, NodeId: " .. nodeId)

        -- 发送初始血量
        local health = serverHealth_[roleId]
        BroadcastHealthUpdate(nodeId, health.current, health.max)

        -- 向新加入的玩家同步所有已有角色的武器状态
        for otherRoleId, otherConnKey in pairs(roleAssignments_) do
            if otherConnKey and otherRoleId ~= roleId then
                local otherWeapon = serverWeapons_[otherRoleId]
                local otherNode = rolePool_[otherRoleId]
                if otherWeapon and otherNode then
                    local weaponData = VariantMap()
                    weaponData["NodeId"] = Variant(otherNode.ID)
                    weaponData["WeaponId"] = Variant(otherWeapon.weaponId)
                    conn:SendRemoteEvent(EVENTS.WEAPON_SWITCH, true, weaponData)
                end
            end
        end
    end)
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    local connKey = tostring(connection)

    local roleId = connectionRoles_[connKey]
    if roleId then
        roleAssignments_[roleId] = nil
        local roleNode = rolePool_[roleId]
        if roleNode then
            roleNode:SetOwner(nil)
        end
        ResetRoleState(roleId)
        BroadcastLog("[Server] Role_" .. roleId .. " released")
    end

    connectionRoles_[connKey] = nil
    serverConnections_[connKey] = nil
    BroadcastLog("[Server] Client disconnected")
end

-- ============================================================================
-- 武器状态
-- ============================================================================

function HandleWeaponSwitch(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local roleId = connectionRoles_[connKey]

    if roleId == nil then return end

    local weaponId = eventData["WeaponId"]:GetString()
    local weaponCfg = WeaponConfig.WEAPONS[weaponId]

    if not weaponCfg then
        BroadcastLog("[Server] Unknown weapon: " .. tostring(weaponId))
        return
    end

    -- 更新武器状态
    serverWeapons_[roleId] = {
        weaponId = weaponId,
        ammoMag = weaponCfg.magSize,
        ammoReserve = weaponCfg.magSize * 3,
    }

    -- 更新节点变量
    local roleNode = rolePool_[roleId]
    if roleNode then
        roleNode:SetVar(VARS.WEAPON_ID, Variant(weaponId))
    end

    -- 广播武器切换给所有客户端（包含 NodeId 以便客户端识别角色）
    local nodeId = roleNode and roleNode.ID or 0
    local switchData = VariantMap()
    switchData["NodeId"] = Variant(nodeId)
    switchData["WeaponId"] = Variant(weaponId)
    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.WEAPON_SWITCH, true, switchData)
    end

    BroadcastLog("[Server] Role_" .. roleId .. " switched to: " .. weaponCfg.name)
end

function HandleWeaponReload(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local roleId = connectionRoles_[connKey]

    if roleId == nil then return end

    local weaponId = eventData["WeaponId"]:GetString()
    local ammoMag = eventData["AmmoMag"]:GetInt()
    local ammoReserve = eventData["AmmoReserve"]:GetInt()

    -- 验证武器 ID
    local weaponState = serverWeapons_[roleId]
    if not weaponState or weaponState.weaponId ~= weaponId then
        BroadcastLog("[Server] Reload weapon mismatch for Role_" .. roleId)
        return
    end

    -- 服务器端验证：弹药数量不能超过上限
    local weaponCfg = WeaponConfig.WEAPONS[weaponId]
    if weaponCfg then
        ammoMag = math.min(ammoMag, weaponCfg.magSize)
        ammoReserve = math.max(0, ammoReserve)
    end

    -- 更新服务器端弹药状态
    weaponState.ammoMag = ammoMag
    weaponState.ammoReserve = ammoReserve

    BroadcastLog("[Server] Role_" .. roleId .. " reloaded " .. weaponId .. ": " .. ammoMag .. "/" .. ammoReserve)
end

-- ============================================================================
-- 服务器端子弹更新（实时碰撞检测）
-- ============================================================================

function UpdateServerBullets(dt)
    local physicsWorld = scene_:GetComponent("PhysicsWorld")
    if not physicsWorld then return end

    local toRemove = {}

    for i, bullet in ipairs(serverBullets_) do
        bullet.lifetime = bullet.lifetime + dt

        -- 计算本帧移动距离
        local frameDistance = bullet.speed * dt
        local newPos = bullet.position + bullet.direction * frameDistance

        -- 从上一帧位置到当前位置进行射线检测（使用 Raycast 获取多个结果以支持穿透蹲下空气区域）
        local ray = Ray(bullet.prevPosition, bullet.direction)
        local results = physicsWorld:Raycast(ray, frameDistance + 0.1, 0xFFFFFFFF)

        -- 遍历结果，跳过发射者和蹲下角色的空气区域
        local result = nil
        local hitRoleId, isHeadshot = nil, false
        local hitType = "wall"
        for j = 1, #results do
            local r = results[j]
            if r.body and r.distance <= frameDistance + 0.05 then
                local node = r.body:GetNode()
                if node ~= bullet.ownerNode then
                    local rId, hs = FindHitRole(node, bullet.ownerNode, r.position)
                    if rId then
                        result = r
                        hitRoleId, isHeadshot = rId, hs
                        hitType = "player"
                        break
                    elseif string.find(node.name or "", "Role_") or string.find(node.name or "", HEAD_HITBOX_PREFIX) then
                        -- 蹲下角色空气区域或自身头部碰撞球，跳过
                    else
                        result = r
                        if node.name == "Target" or node.name == "MovingTarget" then
                            hitType = "target"
                        end
                        break
                    end
                end
            end
        end

        if result then
            local hitPos = result.position
            local hitNormal = result.normal

            if hitRoleId then
                -- 爆头直接击杀，否则正常伤害
                local finalDamage = isHeadshot and 9999 or bullet.damage
                ApplyDamage(hitRoleId, finalDamage, bullet.ownerRoleId)
                if isHeadshot then
                    BroadcastLog("[Server] HEADSHOT! Role_" .. hitRoleId .. " killed instantly")
                end
                -- 广播血液效果
                BroadcastHitEffect(hitPos, bullet.direction, true)
            end
            
            -- 获取靶子ID（如果击中靶子）
            local targetId = 0
            if hitType == "target" then
                local idVar = result.body:GetNode():GetVar("TargetId")
                if not idVar:IsEmpty() then
                    targetId = idVar:GetInt()
                end
            end

            -- 广播子弹命中消息
            BroadcastBulletHit(bullet.id, hitPos, hitNormal, hitType, targetId)

            table.insert(toRemove, i)
        else
            -- 未命中，更新位置
            bullet.prevPosition = bullet.position
            bullet.position = newPos
            bullet.traveledDistance = bullet.traveledDistance + frameDistance

            -- 超过最大距离或生命周期，移除子弹
            if bullet.traveledDistance >= bullet.maxDistance or bullet.lifetime >= bullet.maxLifetime then
                table.insert(toRemove, i)
            end
        end
    end

    -- 从后向前移除
    for i = #toRemove, 1, -1 do
        table.remove(serverBullets_, toRemove[i])
    end
end

-- ============================================================================
-- 更新循环
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    ProcessPendingCallbacks()
    ProcessDelayedCallbacks()
    Shared.UpdateMovingTargets(dt)  -- 更新移动靶
    UpdateServerBullets(dt)         -- 更新服务器端子弹（实时碰撞检测）
    
    -- 定期同步移动靶位置
    targetSyncTimer_ = targetSyncTimer_ + dt
    if targetSyncTimer_ >= TARGET_SYNC_INTERVAL then
        targetSyncTimer_ = 0
        BroadcastTargetSync()
    end

    for roleId, connKey in pairs(roleAssignments_) do
        if connKey then
            local roleNode = rolePool_[roleId]
            local connection = serverConnections_[connKey]

            if connection and roleNode then
                -- 更新射击冷却
                if serverShootCooldown_[roleId] > 0 then
                    serverShootCooldown_[roleId] = serverShootCooldown_[roleId] - dt
                end

                -- 恢复准星扩散（使用武器特定的恢复速度）
                local currentSpread = serverCrosshairSpread_[roleId] or 0
                if currentSpread > 0 then
                    -- 获取武器特定的恢复速度
                    local weaponState = serverWeapons_[roleId]
                    local weaponCfg = weaponState and WeaponConfig.WEAPONS[weaponState.weaponId]
                    local recoverySpeed = weaponCfg and weaponCfg.crosshairRecoverySpeed 
                                          or WeaponConfig.SHOOTING.CrosshairRecoverySpeed
                    serverCrosshairSpread_[roleId] = math.max(0, currentSpread - recoverySpeed * dt)
                    if serverCrosshairSpread_[roleId] <= 0 then
                        serverShotCounter_[roleId] = 0  -- 散布归零时重置连射计数
                    end
                end

                MoveRole(roleNode, connection, roleId, dt)
                -- 射击现在通过 SHOOT_REQUEST 事件处理，不再在这里调用
            end
        end
    end
end

function MoveRole(roleNode, connection, roleId, dt)
    local character = roleNode:GetComponent("CharacterComponent")
    if character == nil then return end

    local controls = connection.controls
    local buttons = controls.buttons

    character.controls:Set(CTRL_FORWARD, (buttons & CTRL.FORWARD) ~= 0)
    character.controls:Set(CTRL_BACK, (buttons & CTRL.BACK) ~= 0)
    character.controls:Set(CTRL_LEFT, (buttons & CTRL.LEFT) ~= 0)
    character.controls:Set(CTRL_RIGHT, (buttons & CTRL.RIGHT) ~= 0)
    character.controls:Set(CTRL_JUMP, (buttons & CTRL.JUMP) ~= 0)
    -- 反转 RUN 控制：默认跑步，按住 Shift 变为走路
    character.controls:Set(CTRL_RUN, (buttons & CTRL.RUN) == 0)

    -- 处理蹲下状态（调整速度 + 碰撞盒高度）
    local wantCrouch = (buttons & CTRL.CROUCH) ~= 0
    local wasCrouching = serverCrouchState_[roleId] or false

    if wantCrouch ~= wasCrouching then
        serverCrouchState_[roleId] = wantCrouch
        roleNode:SetVar(VARS.IS_CROUCHING, Variant(wantCrouch))
        SetCrouchHeadHitbox(roleNode, roleId, wantCrouch)

        if wantCrouch then
            -- 蹲下：降低速度
            character:SetWalkSpeed(Settings.Player.WalkSpeed * Settings.Player.CrouchSpeedMultiplier)
            character:SetRunSpeed(Settings.Player.RunSpeed * Settings.Player.CrouchSpeedMultiplier)
        else
            -- 站立：恢复速度
            character:SetWalkSpeed(Settings.Player.WalkSpeed)
            character:SetRunSpeed(Settings.Player.RunSpeed)
        end
    end

    character.controls.yaw = controls.yaw
    character.controls.pitch = controls.pitch
end

-- ============================================================================
-- 处理客户端射击请求（新逻辑：客户端发送枪口位置和方向）
-- ============================================================================

function HandleShootRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    
    -- 获取角色信息
    local connKey = tostring(connection)
    local roleId = connectionRoles_[connKey]
    if not roleId then return end
    
    local roleNode = rolePool_[roleId]
    if not roleNode then return end
    
    -- 检查冷却
    if serverShootCooldown_[roleId] and serverShootCooldown_[roleId] > 0 then return end
    
    -- 检查血量
    local health = serverHealth_[roleId]
    if health == nil or health.current <= 0 then return end
    
    -- 获取当前武器配置
    local weaponState = serverWeapons_[roleId]
    if not weaponState then return end
    
    -- 使用客户端发送的武器 ID 验证
    local clientWeaponId = eventData["WeaponId"]:GetString()
    if clientWeaponId ~= weaponState.weaponId then
        BroadcastLog("[Server] Weapon mismatch: client=" .. clientWeaponId .. ", server=" .. weaponState.weaponId)
        return
    end
    
    local weaponCfg = WeaponConfig.WEAPONS[weaponState.weaponId]
    if not weaponCfg then return end
    
    -- 检查弹药（服务器端验证）
    if weaponState.ammoMag <= 0 then return end
    
    -- 消耗弹药
    weaponState.ammoMag = weaponState.ammoMag - 1
    
    -- 使用武器射速
    serverShootCooldown_[roleId] = weaponCfg.fireRate or 0.15
    
    -- 读取客户端发送的枪口位置和方向
    local muzzlePos = Vector3(
        eventData["MuzzleX"]:GetFloat(),
        eventData["MuzzleY"]:GetFloat(),
        eventData["MuzzleZ"]:GetFloat()
    )
    local shootDir = Vector3(
        eventData["DirX"]:GetFloat(),
        eventData["DirY"]:GetFloat(),
        eventData["DirZ"]:GetFloat()
    ):Normalized()
    
    -- 服务器端验证：枪口位置不能离角色太远（防作弊）
    local maxMuzzleDistance = 5.0  -- 最大允许的枪口到角色距离
    local distanceToRole = (muzzlePos - roleNode.position):Length()
    if distanceToRole > maxMuzzleDistance then
        BroadcastLog("[Server] Muzzle position too far from role: " .. distanceToRole)
        return
    end
    
    -- 获取武器参数
    local damage = weaponCfg.damage or 25
    local bulletsPerShot = weaponCfg.bulletsPerShot or 1
    local bulletSpeed = weaponCfg.bulletSpeed or 400.0
    
    -- 连射计数器：第1、4、7...枪（每3枪重置一次）0散布
    serverShotCounter_[roleId] = (serverShotCounter_[roleId] or 0) + 1
    if serverShotCounter_[roleId] % 3 == 1 then
        serverCrosshairSpread_[roleId] = 0
    else
        local crosshairSpreadDeg = serverCrosshairSpread_[roleId] or 0
        local spreadIncreaseDeg = weaponCfg.crosshairSpreadPerShot or 2.0
        local spreadMaxDeg = weaponCfg.crosshairSpreadMax or 10.0
        serverCrosshairSpread_[roleId] = math.min(crosshairSpreadDeg + spreadIncreaseDeg, spreadMaxDeg)
    end
    
    -- 获取物理世界（hitscan 模式需要）
    local physicsWorld = scene_:GetComponent("PhysicsWorld")

    -- 处理多发子弹（如霰弹枪）
    for bulletIndex = 1, bulletsPerShot do
        local bulletDir = shootDir
        
        -- 如果是多发子弹（如霰弹枪），添加额外的武器固有扩散
        if bulletsPerShot > 1 then
            local spread = weaponCfg.spreadAngle or 5
            local spreadRad = math.rad(spread)
            local randomYaw = (math.random() - 0.5) * 2 * spreadRad
            local randomPitch = (math.random() - 0.5) * 2 * spreadRad
            
            -- 构建本地坐标系
            local refUp = Vector3.UP
            if math.abs(bulletDir.y) > 0.99 then
                refUp = Vector3.FORWARD
            end
            local localRight = bulletDir:CrossProduct(refUp):Normalized()
            local localUp = localRight:CrossProduct(bulletDir):Normalized()
            
            local spreadRot = Quaternion(math.deg(randomPitch), localRight) * 
                              Quaternion(math.deg(randomYaw), localUp)
            bulletDir = (spreadRot * bulletDir):Normalized()
        end
        
        bulletIdCounter_ = bulletIdCounter_ + 1
        local currentBulletId = bulletIdCounter_

        if Settings.Combat.BallisticMode then
            -- ====== 弹道模式：逐帧射线检测（原有逻辑） ======
            local bullet = {
                id = currentBulletId,
                position = muzzlePos,
                prevPosition = muzzlePos,
                direction = bulletDir,
                speed = bulletSpeed,
                damage = damage,
                ownerRoleId = roleId,
                ownerNode = roleNode,
                lifetime = 0,
                maxLifetime = 100.0 / bulletSpeed,
                traveledDistance = 0,
                maxDistance = 100.0,
            }
            table.insert(serverBullets_, bullet)
            BroadcastBulletCreate(currentBulletId, muzzlePos, bulletDir, bulletSpeed, weaponState.weaponId, roleNode.ID)
        else
            -- ====== 射线模式（hitscan）：即时判定，弹道仅做表现 ======
            local maxDistance = 100.0
            local visualSpeed = bulletSpeed * 10

            -- 广播视觉子弹（速度x10，纯表现用）
            BroadcastBulletCreate(currentBulletId, muzzlePos, bulletDir, visualSpeed, weaponState.weaponId, roleNode.ID)

            -- 立即全距离射线检测（使用 Raycast 获取多个结果，跳过自身碰撞体）
            if physicsWorld then
                local ray = Ray(muzzlePos, bulletDir)
                local results = physicsWorld:Raycast(ray, maxDistance, 0xFFFFFFFF)

                -- 遍历结果，跳过自身节点和蹲下角色的空气区域，取第一个有效命中
                local result = nil
                local hitRoleId, isHeadshot = nil, false
                local hitType = "wall"
                for j = 1, #results do
                    local r = results[j]
                    if r.body then
                        local node = r.body:GetNode()
                        if node ~= roleNode then
                            local rId, hs = FindHitRole(node, roleNode, r.position)
                            if rId then
                                -- 有效命中角色
                                result = r
                                hitRoleId, isHeadshot = rId, hs
                                hitType = "player"
                                break
                            elseif string.find(node.name or "", "Role_") or string.find(node.name or "", HEAD_HITBOX_PREFIX) then
                                -- 命中了角色碰撞体但在有效高度之上（蹲下空气区域）或自身头部碰撞球，跳过继续检测
                            else
                                -- 命中墙壁/靶子等非角色物体
                                result = r
                                if node.name == "Target" or node.name == "MovingTarget" then
                                    hitType = "target"
                                end
                                break
                            end
                        end
                    end
                end

                if result then
                    local hitPos = result.position
                    local hitNormal = result.normal
                    local hitDistance = result.distance

                    if hitRoleId then
                        -- 爆头直接击杀，否则正常伤害
                        local finalDamage = isHeadshot and 9999 or damage
                        ApplyDamage(hitRoleId, finalDamage, roleId)
                        if isHeadshot then
                            BroadcastLog("[Server] HEADSHOT! Role_" .. hitRoleId .. " killed instantly")
                        end
                    end

                    local targetId = 0
                    if hitType == "target" then
                        local idVar = result.body:GetNode():GetVar("TargetId")
                        if not idVar:IsEmpty() then
                            targetId = idVar:GetInt()
                        end
                    end

                    -- 延迟发送命中消息，等视觉子弹飞到命中点
                    local flightTime = hitDistance / visualSpeed
                    local delayFrameCount = math.max(1, math.ceil(flightTime * 60))

                    local bId = currentBulletId
                    local hPos, hNormal, hType, tId = hitPos, hitNormal, hitType, targetId
                    local bDir, isE = bulletDir, (hitRoleId ~= nil)

                    DelayFrames(delayFrameCount, function()
                        if isE then
                            BroadcastHitEffect(hPos, bDir, true)
                        end
                        BroadcastBulletHit(bId, hPos, hNormal, hType, tId)
                    end)
                end
                -- 未命中：不发送 BULLET_HIT，客户端视觉子弹超过 maxDistance/maxLifetime 后自动移除
            end
        end
    end
end



-- 广播创建子弹消息
function BroadcastBulletCreate(bulletId, startPos, direction, speed, weaponId, shooterNodeId)
    local eventData = VariantMap()
    eventData["BulletId"] = Variant(bulletId)
    eventData["StartX"] = Variant(startPos.x)
    eventData["StartY"] = Variant(startPos.y)
    eventData["StartZ"] = Variant(startPos.z)
    eventData["DirX"] = Variant(direction.x)
    eventData["DirY"] = Variant(direction.y)
    eventData["DirZ"] = Variant(direction.z)
    eventData["Speed"] = Variant(speed)
    eventData["WeaponId"] = Variant(weaponId)
    eventData["ShooterNodeId"] = Variant(shooterNodeId)

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.BULLET_CREATE, true, eventData)
    end
end

-- 广播子弹命中消息
function BroadcastBulletHit(bulletId, hitPos, hitNormal, hitType, targetId)
    local eventData = VariantMap()
    eventData["BulletId"] = Variant(bulletId)
    eventData["HitX"] = Variant(hitPos.x)
    eventData["HitY"] = Variant(hitPos.y)
    eventData["HitZ"] = Variant(hitPos.z)
    eventData["NormalX"] = Variant(hitNormal.x)
    eventData["NormalY"] = Variant(hitNormal.y)
    eventData["NormalZ"] = Variant(hitNormal.z)
    eventData["HitType"] = Variant(hitType)  -- "wall", "player", "target"
    eventData["TargetId"] = Variant(targetId or 0)  -- 靶子ID（仅 target 类型有效）

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.BULLET_HIT, true, eventData)
    end
end

function BroadcastHitEffect(hitPos, bulletDir, isEnemy)
    local eventData = VariantMap()
    eventData["HitX"] = Variant(hitPos.x)
    eventData["HitY"] = Variant(hitPos.y)
    eventData["HitZ"] = Variant(hitPos.z)
    eventData["DirX"] = Variant(bulletDir.x)
    eventData["DirY"] = Variant(bulletDir.y)
    eventData["DirZ"] = Variant(bulletDir.z)
    eventData["IsEnemy"] = Variant(isEnemy)

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.HIT_EFFECT, true, eventData)
    end
end

-- ============================================================================
-- 伤害系统
-- ============================================================================

--- 判断命中节点属于哪个角色，以及是否爆头
--- 通过命中位置 Y 坐标判断：命中点高于角色头部阈值即为头部
--- 蹲下时爆头判定高度同步降低 CrouchHeightDelta
--- 返回 roleId, isHeadshot；未命中角色时返回 nil, false
local HEADSHOT_HEIGHT_STAND = Settings.Player.Height * 0.83  -- 站立：1.8 * 0.83 ≈ 1.49m
local HEADSHOT_HEIGHT_CROUCH = 1.2  -- 蹲下：1.2m~1.5m 为爆头区域

function FindHitRole(hitNode, excludeNode, hitPos)
    local nodeName = hitNode.name or ""

    -- 击中头部碰撞球 → 直接判定爆头
    if string.find(nodeName, HEAD_HITBOX_PREFIX) then
        local parentNode = hitNode.parent
        if parentNode and parentNode ~= excludeNode then
            for roleId, node in pairs(rolePool_) do
                if node == parentNode then
                    return roleId, true
                end
            end
        end
        return nil, false
    end

    -- 击中角色身体碰撞体
    if hitNode ~= excludeNode and string.find(nodeName, "Role_") then
        for roleId, node in pairs(rolePool_) do
            if node == hitNode then
                local isHeadshot = false
                local isCrouching = serverCrouchState_[roleId] or false

                if hitPos then
                    local relY = hitPos.y - node.position.y
                    -- 计算当前有效身体高度（蹲下时更矮）
                    local effectiveHeight = isCrouching
                        and (Settings.Player.Height - Settings.Player.CrouchHeightDelta)
                        or Settings.Player.Height
                    -- 命中点超过有效高度，视为未命中（子弹从蹲下角色头顶飞过）
                    if relY > effectiveHeight then
                        return nil, false
                    end

                    local headThreshold = isCrouching and HEADSHOT_HEIGHT_CROUCH or HEADSHOT_HEIGHT_STAND
                    isHeadshot = relY >= headThreshold
                end
                return roleId, isHeadshot
            end
        end
    end
    return nil, false
end

function ApplyDamage(victimRoleId, damage, attackerRoleId)
    local health = serverHealth_[victimRoleId]
    if health == nil then
        BroadcastLog("[Server] ApplyDamage SKIP: no health data for Role_" .. victimRoleId)
        return
    end
    if health.current <= 0 then
        BroadcastLog("[Server] ApplyDamage SKIP: Role_" .. victimRoleId .. " already dead (HP=" .. health.current .. ")")
        return
    end

    health.current = health.current - damage
    if health.current < 0 then health.current = 0 end

    local victimNode = rolePool_[victimRoleId]
    local nodeId = victimNode and victimNode.ID or 0

    BroadcastHealthUpdate(nodeId, health.current, health.max)

    BroadcastLog("[Server] Role_" .. victimRoleId .. " took " .. damage .. " damage, HP: " .. health.current)

    if health.current <= 0 then
        PlayerDied(victimRoleId, attackerRoleId)
    end
end

function BroadcastHealthUpdate(nodeId, current, max)
    local eventData = VariantMap()
    eventData["NodeId"] = Variant(nodeId)
    eventData["Health"] = Variant(current)
    eventData["MaxHealth"] = Variant(max)

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.HEALTH_UPDATE, true, eventData)
    end
end

function PlayerDied(victimRoleId, attackerRoleId)
    local victimNode = rolePool_[victimRoleId]
    if victimNode == nil then return end

    BroadcastLog("[Server] Role_" .. victimRoleId .. " died!")

    -- 死亡时将碰撞体高度降为 0，避免尸体叠加
    local shape = victimNode:GetComponent("CollisionShape")
    if shape then
        shape:SetCapsule(0, 0, Vector3.ZERO)
    end
    -- 移除头部碰撞球
    SetCrouchHeadHitbox(victimNode, victimRoleId, false)

    -- 通知所有客户端
    local eventData = VariantMap()
    eventData["VictimId"] = Variant(victimNode.ID)
    eventData["AttackerId"] = Variant(attackerRoleId or 0)

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.PLAYER_DIED, true, eventData)
    end

    -- 延迟重生
    local roleId = victimRoleId
    local respawnFrames = math.floor(Settings.Combat.RespawnTime * 60)
    DelayFrames(respawnFrames, function() RespawnPlayer(roleId) end)
end

function RespawnPlayer(roleId)
    local roleNode = rolePool_[roleId]
    local health = serverHealth_[roleId]

    if roleNode == nil or health == nil then return end

    -- 重置状态
    health.current = health.max
    roleNode.position = Shared.GetRandomSpawnPoint()

    -- 恢复碰撞体
    local shape = roleNode:GetComponent("CollisionShape")
    if shape then
        shape:SetCapsule(Settings.Player.Radius * 2, Settings.Player.Height,
                         Vector3(0, Settings.Player.Height / 2, 0))
    end

    -- 恢复头部碰撞球（如果角色仍然蹲着）
    local isCrouching = serverCrouchState_[roleId] or false
    SetCrouchHeadHitbox(roleNode, roleId, isCrouching)

    local nodeId = roleNode.ID

    -- 通知重生
    local eventData = VariantMap()
    eventData["NodeId"] = Variant(nodeId)
    eventData["Health"] = Variant(health.current)
    eventData["MaxHealth"] = Variant(health.max)

    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.PLAYER_RESPAWN, true, eventData)
    end

    BroadcastHealthUpdate(nodeId, health.current, health.max)
    BroadcastLog("[Server] Role_" .. roleId .. " respawned (NodeId=" .. nodeId .. ", HP=" .. health.current .. "/" .. health.max .. ")")
end

-- ============================================================================
-- 移动靶位置同步
-- ============================================================================

function BroadcastTargetSync()
    local targets = Shared.MovingTargets
    if #targets == 0 then return end
    
    local eventData = VariantMap()
    eventData["Count"] = Variant(#targets)
    eventData["ServerTime"] = Variant(time.elapsedTime)
    
    for i, target in ipairs(targets) do
        if target.node then
            local pos = target.node.position
            eventData["X" .. i] = Variant(pos.x)
            eventData["Y" .. i] = Variant(pos.y)
            eventData["Z" .. i] = Variant(pos.z)
            eventData["Phase" .. i] = Variant(target.phaseOffset)
        end
    end
    
    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.TARGET_SYNC, true, eventData)
    end
end

-- ============================================================================
-- 服务器日志转发
-- ============================================================================

--- 向所有客户端广播服务器日志
---@param msg string 日志消息
function BroadcastLog(msg)
    print(msg)
    local eventData = VariantMap()
    eventData["Msg"] = Variant(msg)
    for _, conn in pairs(serverConnections_) do
        conn:SendRemoteEvent(EVENTS.SERVER_LOG, true, eventData)
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

function DelayFrames(frames, callback)
    table.insert(delayedCallbacks_, { frames = frames, callback = callback })
end

function ProcessDelayedCallbacks()
    local i = 1
    while i <= #delayedCallbacks_ do
        local item = delayedCallbacks_[i]
        item.frames = item.frames - 1
        if item.frames <= 0 then
            item.callback()
            table.remove(delayedCallbacks_, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 全局入口（引擎要求）
-- ============================================================================

function Start()
    Server.Start()
end

function Stop()
    Server.Stop()
end

return Server
