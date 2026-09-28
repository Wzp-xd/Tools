-- ============================================================================
-- Player.lua - 玩家系统（第三人称角色 + 动画）
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local Audio = require "modules.Audio"
local CharacterAnimation = require "modules.CharacterAnimation"
local WeaponAttachment = require "modules.WeaponAttachment"

local M = {}

local CONFIG = Config.CONFIG
local WEAPON_ORDER = Config.WEAPON_ORDER

-- ============================================================================
-- 第三人称相机配置
-- ============================================================================

M.CAMERA_CONFIG = {
    -- 相机模式配置
    modes = {
        normal = { distance = 5.0, offset = Vector3(0, 1.7, 0), fov = 45.0 },
        armed = { distance = 4.0, offset = Vector3(0.6, 1.6, 0), fov = 45.0 },
        aiming = { distance = 2.0, offset = Vector3(0.4, 1.5, 0), fov = 32.0 },
    },
    transitionSpeed = 8.0,
}

-- ============================================================================
-- 玩家数据
-- ============================================================================

-- 角色动画管理器
M.fsmManager = nil
-- 模型节点
M.modelNode = nil
-- 第三人称相机
M.tpCamera = nil
-- 是否蹲下
M.isCrouching = false
-- 武器附件
---@type WeaponAttachment|nil
M.weaponAttachment = nil

--- 创建玩家
function M.Create()
    -- 创建玩家节点
    GameState.playerNode = GameState.scene:CreateChild("Player")
    GameState.playerNode.position = Vector3(0, CONFIG.PlayerHeight / 2 + 0.5, -(CONFIG.MaxShootDistance/2-5))
    
    -- 添加刚体组件（动态物理）
    GameState.playerBody = GameState.playerNode:CreateComponent("RigidBody")
    GameState.playerBody.mass = 80.0  -- 80kg
    GameState.playerBody.friction = 0.3
    GameState.playerBody.restitution = 0.0
    GameState.playerBody.angularFactor = Vector3.ZERO  -- 禁止旋转
    GameState.playerBody.linearDamping = 0.0
    GameState.playerBody.collisionLayer = GameState.COLLISION_LAYER.PLAYER
    GameState.playerBody.collisionMask = GameState.COLLISION_MASK.PLAYER
    
    -- 添加胶囊碰撞体
    local shape = GameState.playerNode:CreateComponent("CollisionShape")
    shape:SetCapsule(CONFIG.PlayerRadius * 2, CONFIG.PlayerHeight, Vector3(0, CONFIG.PlayerHeight / 2, 0))
    
    -- ========================================================================
    -- 创建角色模型（第三人称可见）
    -- ========================================================================
    M.modelNode = GameState.playerNode:CreateChild("ModelNode")
    
    -- 加载角色预制件
    local prefabFile = cache:GetResource("XMLFile", CharacterAnimation.CHARACTER_CONFIG.Prefab)
    if prefabFile then
        local success = M.modelNode:LoadXML(prefabFile:GetRoot())
        if success then
            print("[Player] Character prefab loaded: " .. CharacterAnimation.CHARACTER_CONFIG.Prefab)
        else
            print("ERROR: Failed to load character prefab")
        end
    else
        print("ERROR: Character prefab not found: " .. CharacterAnimation.CHARACTER_CONFIG.Prefab)
    end
    
    -- 创建动画状态机管理器
    M.fsmManager = CharacterAnimation.CreateFSMManager(M.modelNode)
    
    -- ========================================================================
    -- 附加武器到手部（使用 WEAPON_ORDER 中的第一把武器）
    -- ========================================================================
    local initialWeaponId = WEAPON_ORDER[1] or "g17"
    M.weaponAttachment = WeaponAttachment.AttachWeapon(M.modelNode, initialWeaponId)
    if M.weaponAttachment then
        print("[Player] Weapon attached to hand: " .. initialWeaponId)
    else
        print("[Player] WARNING: Failed to attach weapon: " .. initialWeaponId)
    end
    
    -- ========================================================================
    -- 创建第三人称相机
    -- ========================================================================
    require "urhox-libs.Camera.ThirdPersonCamera"
    
    M.tpCamera = ThirdPersonCamera.Create(GameState.scene, {
        modes = M.CAMERA_CONFIG.modes,
        transitionSpeed = M.CAMERA_CONFIG.transitionSpeed,
    })
    
    -- 保存相机引用
    GameState.cameraNode = M.tpCamera:GetNode()
    GameState.camera = M.tpCamera:GetCamera()
    
    -- 设置初始相机模式为持枪模式
    M.tpCamera:SetMode("armed")
    
    -- 创建颜色分级组件（用于子弹时间对比度调整）
    ---@diagnostic disable-next-line: param-type-mismatch
    GameState.colorGrading = GameState.cameraNode:CreateComponent("ColorGrading")
    GameState.colorGrading:ResetToDefaults()
    GameState.colorGrading.colorGradingEnabled = false
    
    -- 设置视口
    local viewport = Viewport:new(GameState.scene, GameState.camera)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
    
    -- 初始化玩家生命值
    GameState.playerHealth = CONFIG.MaxHealth
    GameState.isDead = false
    
    print("[Player] Third-person character created at: " .. tostring(GameState.playerNode.position))
end

--- 检测玩家是否在地面上
function M.IsGrounded()
    if not GameState.physicsWorld or not GameState.playerNode then
        return false
    end
    
    local playerPos = GameState.playerNode.position
    local rayStart = Vector3(playerPos.x, playerPos.y + 0.1, playerPos.z)
    local rayDir = Vector3(0, -1, 0)
    local ray = Ray(rayStart, rayDir)
    
    local result = GameState.physicsWorld:RaycastSingle(ray, 0.3, 0xFFFFFFFF)
    
    if result.body then
        return true
    end
    
    return false
end

--- 移动玩家（使用物理速度）
function M.Move(moveDir, dt)
    if not GameState.playerBody or GameState.isDead then return end
    
    local gameSpeed = GameState.gameSpeed or 1.0
    
    -- 速度倍率计算
    local speedMultiplier = 1.0
    if GameState.isAiming then
        speedMultiplier = 0.6
    elseif GameState.isRunning then
        -- 射击后恢复期禁止跑步
        if M.fsmManager and CharacterAnimation.IsShooting(M.fsmManager) then
            speedMultiplier = 1.0  -- 强制步行
        else
            speedMultiplier = 1.25
        end
    end
    local moveSpeed = CONFIG.MoveSpeed * speedMultiplier * gameSpeed
    
    local velocity = GameState.playerBody.linearVelocity
    local targetVelX = moveDir.x * moveSpeed
    local targetVelZ = moveDir.z * moveSpeed
    
    local accel = 50.0 * gameSpeed
    local newVelX = velocity.x + (targetVelX - velocity.x) * math.min(1.0, accel * dt)
    local newVelZ = velocity.z + (targetVelZ - velocity.z) * math.min(1.0, accel * dt)
    
    GameState.playerBody.linearVelocity = Vector3(newVelX, velocity.y, newVelZ)
end

--- 跳跃
function M.Jump()
    if not GameState.playerBody or GameState.isDead then return end
    
    if M.IsGrounded() then
        local gameSpeed = GameState.gameSpeed or 1.0
        local jumpSpeed = CONFIG.JumpSpeed * gameSpeed
        
        local velocity = GameState.playerBody.linearVelocity
        GameState.playerBody.linearVelocity = Vector3(velocity.x, jumpSpeed, velocity.z)
        
        -- 触发跳跃动画
        if M.fsmManager then
            CharacterAnimation.TriggerJump(M.fsmManager)
        end
    end
end

--- 停止水平移动
function M.StopMovement()
    if not GameState.playerBody then return end
    
    local velocity = GameState.playerBody.linearVelocity
    GameState.playerBody.linearVelocity = Vector3(velocity.x * 0.8, velocity.y, velocity.z * 0.8)
end

--- 玩家受伤
function M.TakeDamage(damage)
    if GameState.isDead then return end
    
    GameState.playerHealth = GameState.playerHealth - damage
    GameState.lastDamageTime = time.elapsedTime
    
    GameState.damageFlashAlpha = 0.6
    
    Audio.PlaySfx("player_hurt")
    
    if GameState.playerHealth <= 0 then
        GameState.playerHealth = 0
        M.Die()
    end
end

--- 玩家死亡
function M.Die()
    if GameState.isDead then return end
    
    GameState.isDead = true
    GameState.deathTime = time.elapsedTime
    
    -- 触发死亡动画
    if M.fsmManager then
        CharacterAnimation.TriggerDie(M.fsmManager)
    end
    
    Audio.PlaySfx("player_death")
end

--- 玩家重生
function M.Respawn()
    GameState.isDead = false
    GameState.playerHealth = CONFIG.MaxHealth
    
    GameState.playerNode.position = Vector3(0, CONFIG.PlayerHeight / 2 + 0.5, -10)
    if GameState.playerBody then
        GameState.playerBody.linearVelocity = Vector3.ZERO
    end
    
    GameState.yaw = 0
    GameState.pitch = 0
    
    if GameState.currentWeapon then
        GameState.currentAmmo = GameState.currentWeapon.magSize
        GameState.reserveAmmo = GameState.currentWeapon.reserveAmmo
    end
    GameState.isReloading = false
    GameState.reloadTimer = 0
    GameState.grenadeCount = CONFIG.GrenadeMaxCount
end

--- 更新生命回复
function M.UpdateHealth(dt)
    if GameState.isDead then return end
    
    local timeSinceDamage = time.elapsedTime - GameState.lastDamageTime
    if timeSinceDamage >= CONFIG.HealthRegenDelay then
        if GameState.playerHealth < CONFIG.MaxHealth then
            GameState.playerHealth = GameState.playerHealth + CONFIG.HealthRegenRate * dt
            if GameState.playerHealth > CONFIG.MaxHealth then
                GameState.playerHealth = CONFIG.MaxHealth
            end
        end
    end
end

--- 更新动画系统（每帧调用）
function M.UpdateAnimation(dt)
    if not M.fsmManager or GameState.isDead then return end
    
    -- 更新射击状态
    CharacterAnimation.UpdateShootState(M.fsmManager, dt)
    
    -- 计算移动速度和方向
    local velocity = GameState.playerBody and GameState.playerBody.linearVelocity or Vector3.ZERO
    local horizontalVelocity = Vector3(velocity.x, 0, velocity.z)
    local moveSpeed = horizontalVelocity:Length()
    
    -- 计算移动方向（相对于角色朝向）
    -- direction 表示下半身朝向相对于角色前方的角度偏移
    -- 正值 = 向右偏移，负值 = 向左偏移
    local direction = 0
    if moveSpeed > 0.1 then
        local playerYaw = GameState.playerNode.rotation:YawAngle()
        local moveAngle = math.deg(math.atan2(velocity.x, velocity.z))
        -- 计算移动方向相对于角色朝向的角度
        direction = moveAngle - playerYaw
        -- 归一化到 -180 到 180
        while direction > 180 do direction = direction - 360 end
        while direction < -180 do direction = direction + 360 end
        
        -- 只在向后方移动时反转左右方向
        -- 前方范围扩大到 200 度（-100 到 100），避免边界切换抖动
        if math.abs(direction) > 100 then
            if direction > 0 then
                -- 右后方移动 → 下半身朝左前方
                direction = direction - 180  -- 例如：135 → -45
            else
                -- 左后方移动 → 下半身朝右前方
                direction = direction + 180  -- 例如：-135 → 45
            end
        end
    end
    
    local isGrounded = M.IsGrounded()
    local isJumping = not isGrounded and velocity.y > 0
    local characterYaw = GameState.playerNode.rotation:YawAngle()
    
    -- 更新 FSM 参数
    CharacterAnimation.UpdateFSMFromMovement(
        M.fsmManager,
        moveSpeed,
        direction,
        isGrounded,
        isJumping,
        characterYaw
    )
    
    -- 更新蹲下状态
    CharacterAnimation.SetCrouching(M.fsmManager, M.isCrouching)
end

--- 更新相机（在 PostUpdate 中调用）
function M.UpdateCamera(dt)
    if not M.tpCamera or not GameState.playerNode then return end
    
    -- 更新相机模式
    local mode = "armed"  -- 默认持枪模式
    if GameState.isAiming then
        mode = "aiming"
    end
    M.tpCamera:SetMode(mode)
    
    -- 更新相机位置和方向
    M.tpCamera:Update(dt, GameState.playerNode, GameState.yaw, GameState.pitch)
    
    -- 更新角色朝向（始终面向相机方向）
    GameState.playerNode.rotation = Quaternion(GameState.yaw, Vector3.UP)
    
    -- 更新武器位置（骨骼位置在 PostUpdate 时已更新）
    if M.weaponAttachment then
        WeaponAttachment.UpdatePosition(M.weaponAttachment)
    end
    
    -- 更新 AimOffset（上半身朝向）
    if M.fsmManager then
        local cameraPitch = GameState.pitch
        local cameraYaw = GameState.yaw
        local characterYaw = GameState.playerNode.rotation:YawAngle()
        CharacterAnimation.UpdateAimOffset(M.fsmManager, cameraPitch, cameraYaw, characterYaw)
    end
end

--- 触发射击动画
function M.TriggerShootAnimation()
    if M.fsmManager then
        CharacterAnimation.TriggerShoot(M.fsmManager)
    end
end

--- 触发换弹动画
function M.TriggerReloadAnimation()
    if M.fsmManager then
        CharacterAnimation.TriggerReload(M.fsmManager)
    end
end

--- 切换蹲下状态
function M.ToggleCrouch()
    M.isCrouching = not M.isCrouching
end

--- 获取手持武器的枪口节点（用于子弹发射位置）
---@return Node|nil muzzleNode 枪口节点，如果没有武器则返回 nil
function M.GetWeaponMuzzleNode()
    if M.weaponAttachment and M.weaponAttachment.muzzleNode then
        return M.weaponAttachment.muzzleNode
    end
    return nil
end

--- 获取手持武器的抛壳口节点（用于弹壳抛出位置）
---@return Node|nil ejectionNode 抛壳口节点，如果没有武器则返回 nil
function M.GetWeaponEjectionNode()
    if M.weaponAttachment and M.weaponAttachment.ejectionNode then
        return M.weaponAttachment.ejectionNode
    end
    return nil
end

--- 获取手持武器节点
---@return Node|nil weaponNode 武器节点，如果没有武器则返回 nil
function M.GetWeaponNode()
    if M.weaponAttachment and M.weaponAttachment.node then
        return M.weaponAttachment.node
    end
    return nil
end

--- 切换第三人称手持武器模型
---@param weaponId string 武器 ID（对应 Config.WEAPONS 中的键）
function M.SwitchHandWeapon(weaponId)
    if not M.modelNode then
        print("[Player] ERROR: modelNode not initialized")
        return
    end
    
    -- 移除当前武器
    if M.weaponAttachment then
        WeaponAttachment.DetachWeapon(M.weaponAttachment)
        M.weaponAttachment = nil
    end
    
    -- 附加新武器
    M.weaponAttachment = WeaponAttachment.AttachWeapon(M.modelNode, weaponId)
    if M.weaponAttachment then
        print("[Player] Hand weapon switched to: " .. weaponId)
    else
        print("[Player] WARNING: Failed to switch hand weapon to: " .. weaponId)
    end
end

--- 获取当前手持武器 ID
---@return string|nil weaponId 当前武器 ID
function M.GetHandWeaponId()
    if M.weaponAttachment then
        return M.weaponAttachment.weaponId
    end
    return nil
end

return M
