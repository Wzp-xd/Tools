-- ============================================================================
-- CharacterAnimation.lua - 角色动画系统
-- 参考 22-third-person-shooter 示例实现
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"

local M = {}

-- ============================================================================
-- 武器类型枚举
-- ============================================================================

M.WeaponType = {
    NORMAL = 0,     -- 无武器
    RIFLE = 1,      -- 步枪
    DAGGER = 3,     -- 匕首
}

-- ============================================================================
-- 角色预制件和FSM配置
-- ============================================================================

M.CHARACTER_CONFIG = {
    -- 角色预制件路径 (使用 Demo 的角色，与 Unified.fsm 骨骼兼容)
    Prefab = "uuid://DEkZaUTQvLlCdjdIzpnHa4n-",
    
    -- 动画状态机配置
    FSM = "FSM/Unified.fsm",
    
    -- 角色尺寸
    Height = 1.8,
    Radius = 0.35,
    
    -- AimOffset 配置（上半身瞄准偏移）
    AimOffset = {
        bones = {
            { name = "Bip001 Spine", pitchWeight = 0.40, yawWeight = 0.40 },
            { name = "Bip001 Spine1", pitchWeight = 0.35, yawWeight = 0.35 },
            { name = "Bip001 Spine2", pitchWeight = 0.25, yawWeight = 0.25 },
        },
        maxPitch = 50,
        maxYaw = 30,
        smoothSpeed = 12,
    },
    
    -- 射击后恢复时间（禁止跑步）
    ShootRecoveryTime = 0.35,
}

-- ============================================================================
-- FSM 管理器
-- ============================================================================

--- 创建动画状态机管理器
---@param modelNode Node 模型节点
---@return table fsmManager
function M.CreateFSMManager(modelNode)
    local manager = {
        modelNode = modelNode,
        fsm = nil,
        aimOffset = nil,
        weaponType = M.WeaponType.RIFLE,  -- 默认持枪
        -- 射击状态追踪
        wasShooting = false,
        shootRecoveryTimer = 0,
        -- 转向状态追踪
        lastYaw = 0,
    }
    
    -- 确保 AnimationController 存在
    modelNode:GetOrCreateComponent("AnimationController")
    
    -- 创建动画状态机
    manager.fsm = modelNode:CreateComponent("AnimationStateMachine")
    
    -- 加载统一 FSM
    local fsmFile = cache:GetResource("JSONFile", M.CHARACTER_CONFIG.FSM)
    if fsmFile == nil then
        print("ERROR: FSM not found: " .. M.CHARACTER_CONFIG.FSM)
    else
        manager.fsm:LoadFromJSONFile(fsmFile)
        manager.fsm:Start()
        print("[CharacterAnimation] FSM loaded: " .. M.CHARACTER_CONFIG.FSM)
    end
    
    -- 创建 AimOffset 组件
    manager.aimOffset = modelNode:CreateComponent("AimOffset")
    for _, bone in ipairs(M.CHARACTER_CONFIG.AimOffset.bones) do
        manager.aimOffset:AddBone(bone.name, bone.pitchWeight, bone.yawWeight)
    end
    manager.aimOffset:SetMaxPitch(M.CHARACTER_CONFIG.AimOffset.maxPitch)
    manager.aimOffset:SetMaxYaw(M.CHARACTER_CONFIG.AimOffset.maxYaw)
    manager.aimOffset:SetSmoothSpeed(M.CHARACTER_CONFIG.AimOffset.smoothSpeed)
    manager.aimOffset:SetYawCompensation(0)
    manager.aimOffset:SetEnabled(true)  -- 默认启用（持枪状态）
    
    -- 设置初始武器类型为步枪
    if manager.fsm then
        manager.fsm:SetInt("weaponType", M.WeaponType.RIFLE)
    end
    
    return manager
end

-- ============================================================================
-- FSM 参数更新
-- ============================================================================

--- 根据角色状态更新 FSM 参数
---@param manager table FSM 管理器
---@param moveSpeed number 移动速度
---@param direction number 移动方向
---@param isGrounded boolean 是否在地面
---@param isJumping boolean 是否跳跃
---@param characterYaw number 角色 Y 轴旋转角度
function M.UpdateFSMFromMovement(manager, moveSpeed, direction, isGrounded, isJumping, characterYaw)
    if manager.fsm == nil then return end
    
    -- 当跳跃中且尚未离地时，强制设置为非地面状态
    local effectiveGrounded = isGrounded and not isJumping
    
    -- 检测原地转向
    if characterYaw then
        local yawDelta = characterYaw - manager.lastYaw
        -- 处理 -180/180 角度环绕
        if yawDelta > 180 then yawDelta = yawDelta - 360 end
        if yawDelta < -180 then yawDelta = yawDelta + 360 end
        
        local isTurning = moveSpeed < 0.1 and math.abs(yawDelta) > 0.5
        manager.fsm:SetBool("isTurning", isTurning)
        manager.lastYaw = characterYaw
    end
    
    manager.fsm:SetFloat("moveSpeed", moveSpeed)
    manager.fsm:SetFloat("direction", direction)
    manager.fsm:SetBool("isGrounded", effectiveGrounded)
    
    -- 每帧强制设置 weaponType，确保跳跃时上半身动画不被重置
    manager.fsm:SetInt("weaponType", manager.weaponType)
end

--- 设置蹲下状态
function M.SetCrouching(manager, isCrouching)
    if manager.fsm then
        manager.fsm:SetBool("isCrouching", isCrouching)
    end
end

--- 设置武器类型
function M.SetWeaponType(manager, weaponType)
    if manager.weaponType == weaponType then return end
    
    manager.weaponType = weaponType
    
    if manager.fsm then
        manager.fsm:SetInt("weaponType", weaponType)
    end
    
    -- 只有持武器时启用 AimOffset
    local isArmed = (weaponType ~= M.WeaponType.NORMAL)
    if manager.aimOffset then
        manager.aimOffset:SetEnabled(isArmed)
    end
end

--- 触发跳跃动画
function M.TriggerJump(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("jump")
    end
end

--- 触发射击动画
function M.TriggerShoot(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("shoot")
    end
end

--- 触发换弹动画
function M.TriggerReload(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("reload")
    end
end

--- 触发舞蹈动画
function M.TriggerDance(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("dance")
    end
end

--- 触发死亡动画
function M.TriggerDie(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("die")
    end
end

-- ============================================================================
-- AimOffset 更新
-- ============================================================================

--- 更新瞄准偏移
---@param manager table FSM 管理器
---@param pitch number 相机俯仰角
---@param yaw number 相机偏航角
---@param characterYaw number 角色 Y 轴旋转角度
function M.UpdateAimOffset(manager, pitch, yaw, characterYaw)
    if manager.aimOffset == nil or not manager.aimOffset.enabled then return end
    
    manager.aimOffset:SetTargetPitch(pitch)
    
    local relativeYaw = yaw - characterYaw
    while relativeYaw > 180 do relativeYaw = relativeYaw - 360 end
    while relativeYaw < -180 do relativeYaw = relativeYaw + 360 end
    manager.aimOffset:SetTargetYaw(relativeYaw)
end

-- ============================================================================
-- 射击状态检测
-- ============================================================================

--- 检查是否处于射击动画中
function M.IsInShootAnimation(manager)
    if manager.fsm == nil then return false end
    
    -- Unified.fsm: Base=0, LowerBody=1, UpperBody=2, FullBody=3
    local upperBodyState = manager.fsm:GetCurrentState(2)
    
    -- 检查是否在步枪射击状态
    return upperBodyState == "RifleShoot" or
           upperBodyState == "RifleCrouchShoot"
end

--- 更新射击状态和恢复计时器
function M.UpdateShootState(manager, dt)
    local currentlyShooting = M.IsInShootAnimation(manager)
    
    -- 检测射击动画结束 -> 开始恢复计时器
    if manager.wasShooting and not currentlyShooting then
        manager.shootRecoveryTimer = M.CHARACTER_CONFIG.ShootRecoveryTime
    end
    
    manager.wasShooting = currentlyShooting
    
    -- 倒计时恢复计时器
    if manager.shootRecoveryTimer > 0 then
        manager.shootRecoveryTimer = manager.shootRecoveryTimer - dt
    end
end

--- 检查是否正在射击或在射击后恢复期（应禁用跑步）
function M.IsShooting(manager)
    -- 正在射击动画中
    if M.IsInShootAnimation(manager) then
        return true
    end
    
    -- 在射击后恢复期
    if manager.shootRecoveryTimer > 0 then
        return true
    end
    
    return false
end

--- 检查是否持有武器
function M.IsArmed(manager)
    return manager.weaponType ~= M.WeaponType.NORMAL
end

return M
