-- ============================================================================
-- Standalone.lua - 单机模式
-- 当多人模式禁用时使用，提供完整的单人游戏体验
-- ============================================================================

local Standalone = {}
local Shared = require("network.Shared")

require "LuaScripts/Utilities/Sample"
require "LuaScripts/Utilities/Touch"
require "urhox-libs.UI.GameHUD"
require "urhox-libs.Camera.ThirdPersonCamera"

-- ============================================================================
-- 变量
-- ============================================================================

---@type Scene
local scene_ = nil
---@type ThirdPersonCameraInstance
local tpCamera_ = nil
---@type CharacterComponent
local character_ = nil
---@type AnimationStateMachine
local stateMachine_ = nil
---@type AimOffset
local aimOffset_ = nil

-- 游戏状态
local isArmed_ = false
local isAiming_ = false
local isCrouching_ = false
local lastYaw_ = 0

-- NanoVG 准星
local nvgContext_ = nil

-- 快捷引用
local Settings = Shared.Settings

-- ============================================================================
-- 入口
-- ============================================================================

function Standalone.Start()
    SampleStart()

    CreateScene()
    CreateCharacter()
    CreateInstructions()
    CreateGameHUD()
    SubscribeToEvents()

    -- FPS/TPS游戏必须设置相对鼠标模式
    SampleInitMouseMode(MM_RELATIVE)

    print("=== Third Person Shooter - Standalone Mode ===")
    print("WASD: Move | Shift: Run | Space: Jump")
    print("Q: Toggle Rifle | LMB: Shoot | RMB: Aim | R: Reload")
end

function Standalone.Stop()
    if nvgContext_ ~= nil then
        nvgDelete(nvgContext_)
        nvgContext_ = nil
    end
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    scene_ = Shared.CreateScene(false)

    -- 创建第三人称相机
    tpCamera_ = ThirdPersonCamera.Create(scene_, {
        modes = {
            normal = Settings.Camera.normal,
            armed = Settings.Camera.armed,
            aiming = Settings.Camera.aiming,
        },
        transitionSpeed = Settings.Camera.transitionSpeed,
        farClip = Settings.Camera.farClip,
    })
    renderer:SetViewport(0, Viewport:new(scene_, tpCamera_:GetCamera()))
end

-- ============================================================================
-- 角色创建
-- ============================================================================

function CreateCharacter()
    local objectNode = scene_:CreateChild("Player")
    objectNode:SetPosition(Settings.Player.StartPos)

    -- 创建模型节点
    local modelNode = objectNode:CreateChild("ModelNode")

    -- 加载预制体
    local prefabFile = cache:GetResource("XMLFile", Settings.Player.Prefab)
    if prefabFile then
        local success = modelNode:LoadXML(prefabFile:GetRoot())
        if success then
            print("Character prefab loaded: " .. Settings.Player.Prefab)
        end
    end

    -- 确保有 AnimationController
    modelNode:GetOrCreateComponent("AnimationController")

    -- 创建动画状态机（统一 FSM）
    stateMachine_ = modelNode:CreateComponent("AnimationStateMachine")

    local unifiedFSM = cache:GetResource("JSONFile", Settings.FSM.Unified)
    if unifiedFSM then
        stateMachine_:LoadFromJSONFile(unifiedFSM)
        stateMachine_:Start()
        -- 默认无武器状态
        stateMachine_:SetInt("weaponType", Settings.WeaponType.NORMAL)
        print("AnimationStateMachine started with Unified FSM")
    else
        print("ERROR: Unified FSM not found: " .. Settings.FSM.Unified)
    end

    -- 创建 AimOffset 组件
    aimOffset_ = modelNode:CreateComponent("AimOffset")
    aimOffset_:AddBone("Bip001 Spine", 0.40, 0.40)
    aimOffset_:AddBone("Bip001 Spine1", 0.35, 0.35)
    aimOffset_:AddBone("Bip001 Spine2", 0.25, 0.25)
    aimOffset_:SetMaxPitch(60)
    aimOffset_:SetMaxYaw(60)  -- 增大上半身偏转范围，更好对齐镜头
    aimOffset_:SetSmoothSpeed(25)  -- 加快上半身跟随镜头速度

    -- 创建刚体
    local body = objectNode:CreateComponent("RigidBody")
    body:SetCollisionLayerAndMask(CollisionLayerCharacter, CollisionMaskCharacter)
    body:SetMass(1)
    body:SetLinearFactor(Vector3.ZERO)
    body:SetAngularFactor(Vector3.ZERO)
    body:SetCollisionEventMode(COLLISION_ALWAYS)

    -- 创建碰撞形状（胶囊体）
    local shape = objectNode:CreateComponent("CollisionShape")
    shape:SetCapsule(Settings.Player.Radius * 2, Settings.Player.Height,
                     Vector3(0.0, Settings.Player.Height / 2, 0.0))

    -- 创建运动学角色控制器
    local kinematicController = objectNode:CreateComponent("KinematicCharacterController")
    kinematicController:SetCollisionLayerAndMask(CollisionLayerKinematic, CollisionMaskKinematic)
    kinematicController:SetJumpSpeed(8.0)

    -- 创建角色组件
    character_ = objectNode:CreateComponent("CharacterComponent")
    character_:SetAirControlFactor(Settings.Player.AirControlFactor)
    character_:SetEnableWalkMode(Settings.Player.EnableWalkMode)
end

--- 设置武器类型（通过 Unified FSM 的 weaponType 参数切换动画）
---@param weaponType number Settings.WeaponType 枚举值
function SetWeaponType(weaponType)
    if stateMachine_ == nil then return end
    stateMachine_:SetInt("weaponType", weaponType)
end

--- 设置蹲下状态（调整移动速度、碰撞盒高度和 FSM 参数）
---@param crouching boolean 是否蹲下
function SetCrouchState(crouching)
    if character_ == nil then return end

    if crouching then
        -- 蹲下：降低速度
        character_:SetWalkSpeed(Settings.Player.WalkSpeed * Settings.Player.CrouchSpeedMultiplier)
        character_:SetRunSpeed(Settings.Player.RunSpeed * Settings.Player.CrouchSpeedMultiplier)
    else
        -- 站立：恢复速度
        character_:SetWalkSpeed(Settings.Player.WalkSpeed)
        character_:SetRunSpeed(Settings.Player.RunSpeed)
    end

    -- 设置 FSM 蹲下参数
    if stateMachine_ then
        stateMachine_:SetBool("isCrouching", crouching)
    end
end

-- ============================================================================
-- UI 创建
-- ============================================================================

function CreateInstructions()
    local instructionText = ui.root:CreateChild("Text")
    instructionText.text =
        "WASD: 移动 | Shift: 走路 | Ctrl: 蹲下 | Space: 跳跃\n" ..
        "Q: 切换持枪 | 左键: 射击 | 右键: 瞄准 | R: 换弹"
    instructionText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 15)
    instructionText.textAlignment = HA_CENTER
    instructionText.horizontalAlignment = HA_CENTER
    instructionText.verticalAlignment = VA_TOP
    instructionText:SetPosition(0, 10)
end

function CreateGameHUD()
    GameHUD.Initialize()
    GameHUD.SetControls(character_.controls)

    -- 创建 HUD
    GameHUD.Create({
        enableJump = true,
        enableRun = true,
        enableCrouch = true,
        enableShooter = true,
        onCrouch = function(crouching)
            isCrouching_ = crouching
            SetCrouchState(crouching)
        end,
        onArm = function(armed)
            isArmed_ = armed
            SetWeaponType(armed and Settings.WeaponType.RIFLE or Settings.WeaponType.NORMAL)
            tpCamera_:SetMode(armed and "armed" or "normal")

            -- 持枪时角色面向相机方向
            if armed then
                local characterNode = character_:GetNode()
                characterNode.worldRotation = Quaternion(0, character_.controls.yaw, 0)
            end
        end,
        onShoot = function()
            if stateMachine_ then
                stateMachine_:SetTrigger("shoot")
            end
        end,
        onReload = function()
            if stateMachine_ then
                stateMachine_:SetTrigger("reload")
            end
        end,
        onAimChange = function(aiming)
            isAiming_ = aiming
            if aiming then
                tpCamera_:SetMode("aiming")
            else
                tpCamera_:SetMode(isArmed_ and "armed" or "normal")
            end
        end,
    })

    -- 启用触摸视角控制
    GameHUD.EnableTouchLook({
        camera = tpCamera_:GetNode(),
    })

    -- 创建 NanoVG 准星
    nvgContext_ = nvgCreate(1)
    if nvgContext_ then
        SubscribeToEvent(nvgContext_, "NanoVGRender", "HandleCrosshairRender")
    end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    UnsubscribeFromEvent("SceneUpdate")
end

function HandleUpdate(eventType, eventData)
    if character_ == nil then return end

    -- 触摸输入更新
    if touchEnabled then
        UpdateTouches(character_.controls)
    end

    if ui.focusElement == nil then
        -- PC 端鼠标控制视角
        if not touchEnabled then
            character_.controls.yaw = character_.controls.yaw + input.mouseMoveX * Settings.Input.MouseSensitivity
            character_.controls.pitch = character_.controls.pitch + input.mouseMoveY * Settings.Input.MouseSensitivity
        end

        -- 限制俯仰角
        character_.controls.pitch = Clamp(character_.controls.pitch, -80.0, 80.0)

        -- 战斗模式设置
        character_.autoRotateToMoveDir = not isArmed_
        character_.rotationSpeed = isArmed_ and 720.0 or 1440.0  -- 持枪时加快旋转速度

        -- 射击（PC端）
        if isArmed_ then
            if input:GetMouseButtonPress(MOUSEB_LEFT) then
                if stateMachine_ then
                    stateMachine_:SetTrigger("shoot")
                end
            end
            if input:GetKeyPress(KEY_R) then
                if stateMachine_ then
                    stateMachine_:SetTrigger("reload")
                end
            end
            isAiming_ = input:GetMouseButtonDown(MOUSEB_RIGHT)

            -- 更新瞄准时的相机模式
            if isAiming_ then
                tpCamera_:SetMode("aiming")
            elseif tpCamera_:GetMode() == "aiming" then
                tpCamera_:SetMode("armed")
            end
        end
    end
end

function HandlePostUpdate(eventType, eventData)
    if character_ == nil then return end

    local timeStep = eventData["TimeStep"]:GetFloat()

    -- 更新动画状态机参数
    if stateMachine_ then
        local characterNode = character_:GetNode()
        local moveSpeed = character_:GetMoveSpeed()
        local isGrounded = character_:IsOnGround()
        local isJumping = character_:IsJumping()

        if character_:IsJumpStarted() then
            stateMachine_:SetTrigger("jump")
        end

        local effectiveGrounded = isGrounded and not isJumping

        -- 计算移动方向（相对于角色朝向的角度偏移）
        local direction = 0
        if moveSpeed > 0.1 then
            local kcc = characterNode:GetComponent("KinematicCharacterController")
            if kcc then
                local velocity = kcc:GetLinearVelocity()
                local playerYaw = characterNode.worldRotation:YawAngle()
                local moveAngle = math.deg(math.atan(velocity.x, velocity.z))
                direction = moveAngle - playerYaw
                while direction > 180 do direction = direction - 360 end
                while direction < -180 do direction = direction + 360 end
                -- 向后移动时反转方向
                if math.abs(direction) > 100 then
                    if direction > 0 then
                        direction = direction - 180
                    else
                        direction = direction + 180
                    end
                end
            end
        end

        stateMachine_:SetFloat("moveSpeed", moveSpeed)
        stateMachine_:SetFloat("direction", direction)
        stateMachine_:SetBool("isGrounded", effectiveGrounded)
        stateMachine_:SetBool("isCrouching", isCrouching_)

        -- 检测原地转向
        local characterYaw = characterNode.worldRotation:YawAngle()
        local yawDelta = characterYaw - lastYaw_
        if yawDelta > 180 then yawDelta = yawDelta - 360 end
        if yawDelta < -180 then yawDelta = yawDelta + 360 end
        local isTurning = moveSpeed < 0.1 and math.abs(yawDelta) > 0.5
        stateMachine_:SetBool("isTurning", isTurning)
        lastYaw_ = characterYaw
    end

    -- 更新 AimOffset
    if aimOffset_ then
        aimOffset_:SetEnabled(isArmed_)
        if isArmed_ then
            local cameraNode = tpCamera_:GetNode()
            local cameraPitch = cameraNode.worldRotation:PitchAngle()
            aimOffset_:SetTargetPitch(cameraPitch)

            local characterNode = character_:GetNode()
            local characterYaw = characterNode.worldRotation:YawAngle()
            local cameraYaw = cameraNode.worldRotation:YawAngle()
            local relativeYaw = cameraYaw - characterYaw

            while relativeYaw > 180 do relativeYaw = relativeYaw - 360 end
            while relativeYaw < -180 do relativeYaw = relativeYaw + 360 end

            aimOffset_:SetTargetYaw(relativeYaw)
        end
    end

    -- 更新第三人称相机
    local characterNode = character_:GetNode()
    tpCamera_:Update(timeStep, characterNode, character_.controls.yaw, character_.controls.pitch)
end

-- ============================================================================
-- 准星渲染
-- ============================================================================

function HandleCrosshairRender(eventType, eventData)
    if not isArmed_ or nvgContext_ == nil then
        return
    end

    local gfx = GetGraphics()
    local width = gfx:GetWidth()
    local height = gfx:GetHeight()

    nvgBeginFrame(nvgContext_, width, height, 1.0)
    DrawCrosshair(nvgContext_, width / 2, height / 2)
    nvgEndFrame(nvgContext_)
end

function DrawCrosshair(ctx, cx, cy)
    local size = isAiming_ and 8 or 12
    local gap = isAiming_ and 3 or 4
    local thickness = 2

    local r, g, b, a = 255, 255, 255, 200
    if isAiming_ then
        r, g, b, a = 255, 50, 50, 255
    end

    nvgStrokeColor(ctx, nvgRGBA(r, g, b, a))
    nvgStrokeWidth(ctx, thickness)
    nvgFillColor(ctx, nvgRGBA(r, g, b, a))

    -- 十字准星
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - gap - size)
    nvgLineTo(ctx, cx, cy - gap)
    nvgMoveTo(ctx, cx, cy + gap)
    nvgLineTo(ctx, cx, cy + gap + size)
    nvgMoveTo(ctx, cx - gap - size, cy)
    nvgLineTo(ctx, cx - gap, cy)
    nvgMoveTo(ctx, cx + gap, cy)
    nvgLineTo(ctx, cx + gap + size, cy)
    nvgStroke(ctx)

    -- 中心点
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, isAiming_ and 1.5 or 2)
    nvgFill(ctx)
end

return Standalone
