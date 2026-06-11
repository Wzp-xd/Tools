-- ============================================================================
-- 机甲程序化动画系统
-- MechAnimator - Procedural Animation System
-- ============================================================================
-- 基于正弦波的程序化关节动画，无需骨骼动画文件。
-- 通过旋转关节节点实现行走、奔跑、跳跃、飞行等动画。
--
-- 支持的动画:
--   idle        - 待机（微小呼吸起伏）
--   move_f      - 前进
--   move_fl     - 左前
--   move_fr     - 右前
--   move_l      - 左移
--   move_r      - 右移
--   move_b      - 后退
--   move_bl     - 左后
--   move_br     - 右后
--   jump        - 跳跃（蹲下→伸展）
--   fly         - 飞行（流线型姿态）
--   attack      - 攻击（举枪射击）
-- ============================================================================

local MechAnimator = {}
MechAnimator.__index = MechAnimator

-- ============================================================================
-- 动画名称常量
-- ============================================================================

MechAnimator.ANIM_IDLE    = "idle"
MechAnimator.ANIM_JUMP    = "jump"
MechAnimator.ANIM_FLY     = "fly"
MechAnimator.ANIM_ATTACK  = "attack"

-- 8 方向移动动画 ID（行走）
MechAnimator.ANIM_MOVE_F  = "move_f"
MechAnimator.ANIM_MOVE_FL = "move_fl"
MechAnimator.ANIM_MOVE_FR = "move_fr"
MechAnimator.ANIM_MOVE_L  = "move_l"
MechAnimator.ANIM_MOVE_R  = "move_r"
MechAnimator.ANIM_MOVE_B  = "move_b"
MechAnimator.ANIM_MOVE_BL = "move_bl"
MechAnimator.ANIM_MOVE_BR = "move_br"

-- ============================================================================
-- 动画列表（供 config/UI 使用）
-- ============================================================================

MechAnimator.ANIM_LIST = {
    { name = "待机 Idle",         id = "idle",         loop = true },
    { name = "前进 Forward",      id = "move_f",       loop = true },
    { name = "左前 Forward-Left", id = "move_fl",      loop = true },
    { name = "右前 Forward-Right",id = "move_fr",      loop = true },
    { name = "左移 Left",         id = "move_l",       loop = true },
    { name = "右移 Right",        id = "move_r",       loop = true },
    { name = "后退 Backward",     id = "move_b",       loop = true },
    { name = "左后 Backward-Left",id = "move_bl",      loop = true },
    { name = "右后 Backward-Right",id = "move_br",     loop = true },
    { name = "跳跃 Jump",         id = "jump",         loop = false },
    { name = "飞行 Fly",          id = "fly",          loop = true },
    { name = "攻击 Attack",       id = "attack",       loop = false },
}

-- 8 方向预设向量（本地空间 x,z）
local DIR_PRESETS = {
    move_f  = { 0,  1 },
    move_fl = {-1,  1 },
    move_fr = { 1,  1 },
    move_l  = {-1,  0 },
    move_r  = { 1,  0 },
    move_b  = { 0, -1 },
    move_bl = {-1, -1 },
    move_br = { 1, -1 },
}

-- ============================================================================
-- 构造与初始化
-- ============================================================================

--- 创建动画器实例
---@param joints table 来自 MechBuilder.Build() 的关节引用
---@return table animator 动画器实例
function MechAnimator.Create(joints)
    local self = setmetatable({}, MechAnimator)
    self.joints = joints
    self.currentAnim = "idle"
    self.animTime = 0
    self.blendTime = 0
    self.blendDuration = 0.2
    self.prevPose = nil
    self.isPlaying = true

    -- 非关节键名（不参与姿态混合，单独控制）
    self.skipNames = {
        backFlameL = true, backFlameR = true,
        legFlameL = true, legFlameR = true,
        backFlameBaseScale = true, legFlameBaseScale = true,
        weaponMountHandL = true, weaponMountHandR = true,
        weaponMountShoulderR = true,
    }
    self.boostActive = false  -- 推进状态（按住跳跃时背部喷口常亮）
    self.jetActive = false    -- 喷射模式（C键，背部喷口更大火焰）

    -- 手部射击瞄准状态
    self.firingLeft = false           -- 左手是否正在射击
    self.firingRight = false          -- 右手是否正在射击
    ---@type Vector3|nil
    self.aimTargetPos = nil           -- 瞄准的世界坐标目标位置
    ---@type Node|nil
    self.mechRootNode = nil           -- 机甲根节点（用于世界→本地坐标转换）
    self.aimBlendL = 0                -- 左手瞄准混合因子（0~1）
    self.aimBlendR = 0                -- 右手瞄准混合因子（0~1）
    self.aimBlendSpeed = 8.0          -- 混合速度

    -- 保存初始旋转（Identity），用于 reset
    self.initialRotations = {}
    self.initialPositions = {}
    for name, node in pairs(joints) do
        if not self.skipNames[name] then
            self.initialRotations[name] = Quaternion(node.rotation)
            self.initialPositions[name] = Vector3(node.position)
        end
    end

    return self
end

--- 播放指定动画
---@param animId string 动画 ID
---@param fadeTime number|nil 过渡时间（默认 0.2 秒）
function MechAnimator:Play(animId, fadeTime)
    if self.currentAnim == animId then return end

    -- 保存当前姿态用于混合过渡
    self.prevPose = self:CapturePose()
    self.currentAnim = animId
    self.animTime = 0
    self.blendTime = 0
    self.blendDuration = fadeTime or 0.2
    self.isPlaying = true
    print("[MechAnimator] Playing: " .. animId)
end

--- 停止动画，恢复初始姿态
function MechAnimator:Stop()
    self.isPlaying = false
    self.currentAnim = "idle"
    self.animTime = 0
    self:ResetPose()
end

--- 恢复初始姿态
function MechAnimator:ResetPose()
    for name, node in pairs(self.joints) do
        if self.initialRotations[name] then
            node.rotation = Quaternion(self.initialRotations[name])
            node.position = Vector3(self.initialPositions[name])
        end
    end
    -- 关闭所有火焰
    local j = self.joints
    if j.backFlameL then j.backFlameL:SetDeepEnabled(false) end
    if j.backFlameR then j.backFlameR:SetDeepEnabled(false) end
    if j.legFlameL then j.legFlameL:SetDeepEnabled(false) end
    if j.legFlameR then j.legFlameR:SetDeepEnabled(false) end
end

--- 捕获当前姿态（相对于初始旋转的增量，跳过火焰节点）
---@return table pose 各关节相对旋转增量
function MechAnimator:CapturePose()
    local pose = {}
    for name, node in pairs(self.joints) do
        if self.initialRotations[name] then
            -- 提取相对于初始旋转的增量: delta = initRot^-1 * currentRot
            pose[name] = self.initialRotations[name]:Inverse() * Quaternion(node.rotation)
        end
    end
    return pose
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

--- 每帧更新动画
---@param dt number 帧时间
function MechAnimator:Update(dt)
    if not self.isPlaying then return end

    self.animTime = self.animTime + dt

    -- 计算目标姿态
    local targetPose = self:EvaluateAnim(self.currentAnim, self.animTime)

    -- 过渡混合
    if self.prevPose and self.blendTime < self.blendDuration then
        self.blendTime = self.blendTime + dt
        local t = math.min(1.0, self.blendTime / self.blendDuration)
        -- 平滑插值
        t = t * t * (3 - 2 * t)
        self:ApplyBlendedPose(self.prevPose, targetPose, t)
    else
        self.prevPose = nil
        self:ApplyPose(targetPose)
    end

    -- 手部射击瞄准 IK 覆盖
    self:UpdateAimIK(dt)

    -- 喷口火焰控制
    self:UpdateThrusters()
end

--- 手部射击瞄准 IK 覆盖
--- 射击时上臂抬起朝向敌人，小臂反向补偿保持始终向前
---@param dt number
function MechAnimator:UpdateAimIK(dt)
    -- 更新射击混合因子
    local targetL = self.firingLeft and 1.0 or 0.0
    local targetR = self.firingRight and 1.0 or 0.0
    self.aimBlendL = self.aimBlendL + (targetL - self.aimBlendL) * math.min(1.0, self.aimBlendSpeed * dt)
    self.aimBlendR = self.aimBlendR + (targetR - self.aimBlendR) * math.min(1.0, self.aimBlendSpeed * dt)

    if not self.aimTargetPos or not self.mechRootNode then return end

    local j = self.joints
    local targetWorld = self.aimTargetPos

    -- 左手：射击时上臂瞄准 + 小臂补偿
    if self.aimBlendL > 0.01 and j.shoulderL and j.elbowL then
        self:ApplyArmAim(j.shoulderL, j.elbowL, "elbowL", targetWorld, self.aimBlendL)
    end

    -- 右手：射击时上臂瞄准 + 小臂补偿
    if self.aimBlendR > 0.01 and j.shoulderR and j.elbowR then
        self:ApplyArmAim(j.shoulderR, j.elbowR, "elbowR", targetWorld, self.aimBlendR)
    end
end

--- 上臂朝向目标 + 小臂反向补偿（始终保持向前）
--- 上臂抬起多少，小臂就向下旋转多少，让小臂始终相对身体向前伸出
---@param shoulderJoint Node
---@param elbowJoint Node
---@param elbowName string 关节名称（"elbowL" 或 "elbowR"）
---@param targetWorld Vector3
---@param blend number 0~1 混合因子
function MechAnimator:ApplyArmAim(shoulderJoint, elbowJoint, elbowName, targetWorld, blend)
    -- 肩关节的世界位置
    local shoulderWorldPos = shoulderJoint.worldPosition

    -- 目标方向（世界空间）
    local toTarget = targetWorld - shoulderWorldPos
    if toTarget:Length() < 0.1 then return end
    local aimDirWorld = toTarget:Normalized()

    -- 将目标方向转换到肩关节父级（身体）的本地空间
    local parentNode = shoulderJoint.parent
    if not parentNode then return end
    local parentWorldRot = parentNode.worldRotation
    local parentInvRot = parentWorldRot:Inverse()
    local aimDirLocal = (parentInvRot * aimDirWorld):Normalized()

    -- 手臂自然下垂方向是 -Y（上臂沿 Y 负方向延伸）
    -- 瞄准时将 -Y 旋转到 aimDirLocal
    local armRestDir = Vector3(0, -1, 0)
    local aimRot = Quaternion(armRestDir, aimDirLocal)

    -- 肘关节初始旋转
    local elbowInitRot = self.initialRotations[elbowName]
    if not elbowInitRot then return end

    -- 1. 应用肩关节混合
    local curShoulderRot = shoulderJoint.rotation
    local blendedShoulderRot = curShoulderRot:Slerp(aimRot, blend)
    shoulderJoint.rotation = blendedShoulderRot

    -- 2. 小臂反向补偿：抵消肩关节旋转，保持小臂始终向前
    --    前臂方向 = shoulderRot * elbowRot * (0,-1,0)
    --    要让前臂方向 = 身体前方 (0,0,1)
    --    即 elbowRot * (0,-1,0) = shoulderRot⁻¹ * (0,0,1)
    --    用 restDir → targetDir 的增量旋转 * elbowInitRot
    local bodyForwardInShoulder = (blendedShoulderRot:Inverse() * Vector3(0, 0, 1)):Normalized()
    local restDir = (elbowInitRot * Vector3(0, -1, 0)):Normalized()  -- = (0,0,1)
    local compensateDelta = Quaternion(restDir, bodyForwardInShoulder)
    local compensatedElbowRot = compensateDelta * elbowInitRot

    -- 与当前动画姿态混合
    local curElbowRot = elbowJoint.rotation
    elbowJoint.rotation = curElbowRot:Slerp(compensatedElbowRot, blend)
end

--- 根据当前动画控制喷口火焰显隐
function MechAnimator:UpdateThrusters()
    local animId = self.currentAnim
    local dir = DIR_PRESETS[animId]

    -- 默认全部关闭
    local backOn = false
    local legLOn = false  -- 左腿喷口（向左喷，右移时启用）
    local legROn = false  -- 右腿喷口（向右喷，左移时启用）

    -- 推进状态：背部喷口常亮
    if self.boostActive then
        backOn = true
    end

    if dir then
        local dx, dz = dir[1], dir[2]
        -- 背部喷口：前进方向有分量时启用 (move_f, move_fl, move_fr)
        if dz > 0 then
            backOn = true
        end
        -- 左腿喷口（向左喷射）：向右移动时启用
        if dx > 0 then
            legLOn = true
        end
        -- 右腿喷口（向右喷射）：向左移动时启用
        if dx < 0 then
            legROn = true
        end
    end

    -- 喷射模式：所有喷口常亮 + 火焰大幅放大
    if self.jetActive then
        backOn = true
        legLOn = true
        legROn = true
    end

    -- 应用到火焰节点
    local j = self.joints
    if j.backFlameL then j.backFlameL:SetDeepEnabled(backOn) end
    if j.backFlameR then j.backFlameR:SetDeepEnabled(backOn) end
    if j.legFlameL then j.legFlameL:SetDeepEnabled(legLOn) end
    if j.legFlameR then j.legFlameR:SetDeepEnabled(legROn) end

    -- 喷射模式下火焰大幅放大
    if j.backFlameBaseScale then
        local baseBack = j.backFlameBaseScale
        if self.jetActive then
            local bigBack = Vector3(baseBack.x * 4.0, baseBack.y * 4.0, baseBack.z * 4.0)
            if j.backFlameL then j.backFlameL.scale = bigBack end
            if j.backFlameR then j.backFlameR.scale = bigBack end
        else
            if j.backFlameL then j.backFlameL.scale = baseBack end
            if j.backFlameR then j.backFlameR.scale = baseBack end
        end
    end
    if j.legFlameBaseScale then
        local baseLeg = j.legFlameBaseScale
        if self.jetActive then
            local bigLeg = Vector3(baseLeg.x * 5.0, baseLeg.y * 5.0, baseLeg.z * 5.0)
            if j.legFlameL then j.legFlameL.scale = bigLeg end
            if j.legFlameR then j.legFlameR.scale = bigLeg end
        else
            if j.legFlameL then j.legFlameL.scale = baseLeg end
            if j.legFlameR then j.legFlameR.scale = baseLeg end
        end
    end
end

--- 应用姿态到关节
---@param pose table
function MechAnimator:ApplyPose(pose)
    for name, rot in pairs(pose) do
        local node = self.joints[name]
        if node then
            -- 在初始旋转基础上叠加动画旋转（支持肘关节等有默认旋转的关节）
            local initRot = self.initialRotations[name]
            if initRot then
                node.rotation = initRot * rot
            else
                node.rotation = rot
            end
        end
    end
end

--- 应用混合姿态
---@param poseA table 起始姿态
---@param poseB table 目标姿态
---@param t number 混合因子 0~1
function MechAnimator:ApplyBlendedPose(poseA, poseB, t)
    local identity = Quaternion()
    for name, node in pairs(self.joints) do
        if self.initialRotations[name] then
            -- poseA/poseB 都是相对于初始旋转的增量，无值时为 Identity（无偏移）
            local rotA = poseA[name] or identity
            local rotB = poseB[name] or identity
            node.rotation = self.initialRotations[name] * rotA:Slerp(rotB, t)
        end
    end
end

-- ============================================================================
-- 动画求值
-- ============================================================================

--- 根据动画 ID 和时间计算各关节旋转
---@param animId string
---@param t number 累计时间
---@return table pose 关节名→Quaternion 的映射
function MechAnimator:EvaluateAnim(animId, t)
    if animId == "idle" then
        return self:EvalIdle(t)
    elseif animId == "jump" then
        return self:EvalJump(t)
    elseif animId == "fly" then
        return self:EvalFly(t)
    elseif animId == "attack" then
        return self:EvalAttack(t)
    else
        -- 8 方向移动：查预设表
        local dir = DIR_PRESETS[animId]
        if dir then
            local len = math.sqrt(dir[1] * dir[1] + dir[2] * dir[2])
            local dx, dz = 0, 0
            if len > 0 then dx = dir[1] / len; dz = dir[2] / len end
            return self:EvalDirectionalMove(t, dx, dz)
        end
    end
    return self:EvalIdle(t)
end

-- ============================================================================
-- 具体动画实现
-- ============================================================================

--- 待机动画：微小呼吸起伏
function MechAnimator:EvalIdle(t)
    local breathCycle = math.sin(t * 1.5) -- 慢呼吸
    local pose = {}

    -- 上半身微微起伏
    pose.body = Quaternion(breathCycle * 1.0, Vector3.RIGHT)

    -- 手臂轻微摆动
    pose.shoulderL = Quaternion(breathCycle * 2.0, Vector3.RIGHT)
    pose.shoulderR = Quaternion(-breathCycle * 2.0, Vector3.RIGHT)
    pose.elbowL = Quaternion(breathCycle * 1.5 - 5, Vector3.RIGHT)
    pose.elbowR = Quaternion(-breathCycle * 1.5 - 5, Vector3.RIGHT)

    -- 腿保持不动
    pose.hipL = Quaternion(0, Vector3.RIGHT)
    pose.hipR = Quaternion(0, Vector3.RIGHT)
    pose.kneeL = Quaternion(0, Vector3.RIGHT)
    pose.kneeR = Quaternion(0, Vector3.RIGHT)

    return pose
end

--- 8 方向移动动画：滑轮滑行风格
--- 身体向移动方向倾斜，腿沿移动方向一前一后跨开
---@param t number 时间
---@param dx number 本地空间 X 方向 (-1~1)，正=右
---@param dz number 本地空间 Z 方向 (-1~1)，正=前
function MechAnimator:EvalDirectionalMove(t, dx, dz)
    local pose = {}

    -- 身体倾斜：前后用 pitch (RIGHT轴)，左右用 roll (FORWARD轴)
    local leanPitch = dz * 12    -- 前进时前倾，后退时后仰
    local leanRoll  = -dx * 10   -- 右移时右倾，左移时左倾
    pose.body = Quaternion(leanPitch, Vector3.RIGHT)
             * Quaternion(leanRoll, Vector3.FORWARD)

    -- 腿跨步方向：沿移动方向，左腿在前，右腿在后
    -- 前腿：髋部向移动方向旋转（前迈）
    -- 后腿：髋部反方向旋转（后撑）
    local strideFwd = 15    -- 前腿角度
    local strideBck = -10   -- 后腿角度
    local kneeFwd = 20      -- 前腿膝盖弯曲
    local kneeBck = 12      -- 后腿膝盖弯曲

    -- 髋部绕 RIGHT 轴旋转控制前后迈步
    -- 髋部绕 UP 轴旋转控制脚尖朝向（跟随移动方向偏转）
    -- 后方对角移动时，腿部朝向与纯侧移一致
    local legDx, legDz = dx, dz
    if dz < 0 and math.abs(dx) > 0.01 then
        legDz = 0
    end
    local yawOffset = math.atan(legDx, legDz)
    local yawDeg = math.deg(yawOffset)

    -- 腿部倾斜：向移动方向倾斜
    local hipRoll = -dx * 6

    -- 后退时脚尖外八字展开（左脚向左偏，右脚向右偏）
    local splayL = 0
    local splayR = 0
    if dz < 0 then
        local splayAngle = -dz * 15
        splayL = -splayAngle
        splayR = splayAngle
    end

    -- 左腿前跨
    pose.hipL = Quaternion(strideFwd, Vector3.RIGHT)
              * Quaternion(yawDeg * 0.3 + splayL, Vector3.UP)
              * Quaternion(hipRoll, Vector3.FORWARD)
    -- 右腿后撑
    pose.hipR = Quaternion(strideBck, Vector3.RIGHT)
              * Quaternion(yawDeg * 0.3 + splayR, Vector3.UP)
              * Quaternion(hipRoll, Vector3.FORWARD)

    pose.kneeL = Quaternion(kneeFwd, Vector3.RIGHT)
    pose.kneeR = Quaternion(kneeBck, Vector3.RIGHT)

    -- 手臂向移动反方向摆开保持平衡
    local armPitch = 15 - dz * 5   -- 后退时手臂更前伸
    local armRoll  = -dx * 8       -- 侧移时手臂反向展
    pose.shoulderL = Quaternion(armPitch, Vector3.RIGHT)
                   * Quaternion(8 + armRoll, Vector3.FORWARD)
    pose.shoulderR = Quaternion(armPitch, Vector3.RIGHT)
                   * Quaternion(-8 + armRoll, Vector3.FORWARD)

    pose.elbowL = Quaternion(-15, Vector3.RIGHT)
    pose.elbowR = Quaternion(-15, Vector3.RIGHT)

    return pose
end

--- 跳跃动画：蹲下 → 伸展 → 空中
function MechAnimator:EvalJump(t)
    local pose = {}

    if t < 0.2 then
        -- 阶段 1: 蹲下蓄力 (0 ~ 0.2s)
        local p = t / 0.2
        local crouch = p * p -- 加速蹲下

        pose.body = Quaternion(10 * crouch, Vector3.RIGHT)
        pose.hipL = Quaternion(35 * crouch, Vector3.RIGHT)
        pose.hipR = Quaternion(35 * crouch, Vector3.RIGHT)
        pose.kneeL = Quaternion(-50 * crouch, Vector3.RIGHT)
        pose.kneeR = Quaternion(-50 * crouch, Vector3.RIGHT)
        pose.shoulderL = Quaternion(20 * crouch, Vector3.RIGHT)
        pose.shoulderR = Quaternion(20 * crouch, Vector3.RIGHT)
        pose.elbowL = Quaternion(-15 * crouch, Vector3.RIGHT)
        pose.elbowR = Quaternion(-15 * crouch, Vector3.RIGHT)

    elseif t < 0.5 then
        -- 阶段 2: 伸展起跳 (0.2 ~ 0.5s)
        local p = (t - 0.2) / 0.3
        local extend = math.sin(p * math.pi * 0.5) -- 快速伸展

        pose.body = Quaternion(10 - 18 * extend, Vector3.RIGHT)
        pose.hipL = Quaternion(35 - 45 * extend, Vector3.RIGHT)
        pose.hipR = Quaternion(35 - 45 * extend, Vector3.RIGHT)
        pose.kneeL = Quaternion(-50 + 50 * extend, Vector3.RIGHT)
        pose.kneeR = Quaternion(-50 + 50 * extend, Vector3.RIGHT)
        pose.shoulderL = Quaternion(20 - 50 * extend, Vector3.RIGHT)
        pose.shoulderR = Quaternion(20 - 50 * extend, Vector3.RIGHT)
        pose.elbowL = Quaternion(-15 + 5 * extend, Vector3.RIGHT)
        pose.elbowR = Quaternion(-15 + 5 * extend, Vector3.RIGHT)

    else
        -- 阶段 3: 空中滞空 (0.5s+)
        local hover = math.sin((t - 0.5) * 2.0) * 3.0

        pose.body = Quaternion(-8 + hover, Vector3.RIGHT)
        pose.hipL = Quaternion(-10 + hover * 2, Vector3.RIGHT)
        pose.hipR = Quaternion(-10 - hover * 2, Vector3.RIGHT)
        pose.kneeL = Quaternion(-15, Vector3.RIGHT)
        pose.kneeR = Quaternion(-15, Vector3.RIGHT)
        pose.shoulderL = Quaternion(-30 + hover * 3, Vector3.RIGHT)
        pose.shoulderR = Quaternion(-30 - hover * 3, Vector3.RIGHT)
        pose.elbowL = Quaternion(-10, Vector3.RIGHT)
        pose.elbowR = Quaternion(-10, Vector3.RIGHT)
    end

    return pose
end

--- 飞行动画：流线型向前俯冲姿态
function MechAnimator:EvalFly(t)
    local pose = {}
    local wobble = math.sin(t * 3.0) -- 飞行中的轻微摆动

    -- 身体大幅前倾
    pose.body = Quaternion(35 + wobble * 2, Vector3.RIGHT)

    -- 手臂向后伸展（流线型）
    pose.shoulderL = Quaternion(40 + wobble * 5, Vector3.RIGHT)
    pose.shoulderR = Quaternion(40 - wobble * 5, Vector3.RIGHT)
    pose.elbowL = Quaternion(15, Vector3.RIGHT)
    pose.elbowR = Quaternion(15, Vector3.RIGHT)

    -- 腿向后伸展 + 向外张开（让腿部喷口清晰可见）
    pose.hipL = Quaternion(25 + wobble * 3, Vector3.RIGHT)
               * Quaternion(-15, Vector3.FORWARD)  -- 左腿向外张开
    pose.hipR = Quaternion(25 - wobble * 3, Vector3.RIGHT)
               * Quaternion(15, Vector3.FORWARD)   -- 右腿向外张开
    pose.kneeL = Quaternion(-10, Vector3.RIGHT)
    pose.kneeR = Quaternion(-10, Vector3.RIGHT)

    return pose
end

--- 攻击动画：右臂举枪射击（抬臂→射击连发后坐力→收枪）
function MechAnimator:EvalAttack(t)
    local pose = {}

    if t < 0.25 then
        -- 阶段 1: 抬枪瞄准 (0 ~ 0.25s)
        local p = t / 0.25
        local raise = p * p * (3 - 2 * p)  -- smoothstep 平滑抬起

        -- 身体微蹲稳定，略向左转让出右臂射击线
        pose.body = Quaternion(5 * raise, Vector3.RIGHT)
                 * Quaternion(-6 * raise, Vector3.UP)

        -- 右臂向前举枪：肩部前伸 + 抬起
        pose.shoulderR = Quaternion(-75 * raise, Vector3.RIGHT)
                       * Quaternion(8 * raise, Vector3.FORWARD)
        pose.elbowR = Quaternion(-15 * raise, Vector3.RIGHT)

        -- 左臂辅助托枪
        pose.shoulderL = Quaternion(-50 * raise, Vector3.RIGHT)
                       * Quaternion(-15 * raise, Vector3.FORWARD)
        pose.elbowL = Quaternion(-30 * raise, Vector3.RIGHT)

        -- 腿微蹲
        pose.hipL = Quaternion(10 * raise, Vector3.RIGHT)
        pose.hipR = Quaternion(10 * raise, Vector3.RIGHT)
        pose.kneeL = Quaternion(-15 * raise, Vector3.RIGHT)
        pose.kneeR = Quaternion(-15 * raise, Vector3.RIGHT)

    elseif t < 1.05 then
        -- 阶段 2: 连发射击（3 发，每发 ~0.2s 后坐力循环 + 间隔）(0.25 ~ 1.05s)
        local fireTime = t - 0.25  -- 射击阶段内的时间
        -- 每发节奏: 0.00~0.10 后坐, 0.10~0.27 回位
        local shotCycle = fireTime % 0.27
        local recoil = 0
        if shotCycle < 0.06 then
            -- 快速后坐冲击
            recoil = shotCycle / 0.06
        elseif shotCycle < 0.14 then
            -- 保持后坐
            recoil = 1.0
        else
            -- 缓慢回位
            recoil = 1.0 - (shotCycle - 0.14) / 0.13
        end
        recoil = math.max(0, math.min(1, recoil))

        -- 身体被后坐力微推
        pose.body = Quaternion(5 - recoil * 3, Vector3.RIGHT)
                 * Quaternion(-6 + recoil * 2, Vector3.UP)

        -- 右臂举枪姿态 + 后坐力
        pose.shoulderR = Quaternion(-75 + recoil * 8, Vector3.RIGHT)
                       * Quaternion(8 - recoil * 3, Vector3.FORWARD)
        pose.elbowR = Quaternion(-15 + recoil * 5, Vector3.RIGHT)

        -- 左臂托枪随后坐力微动
        pose.shoulderL = Quaternion(-50 + recoil * 4, Vector3.RIGHT)
                       * Quaternion(-15 + recoil * 2, Vector3.FORWARD)
        pose.elbowL = Quaternion(-30 + recoil * 3, Vector3.RIGHT)

        -- 腿保持蹲姿稳定
        pose.hipL = Quaternion(10, Vector3.RIGHT)
        pose.hipR = Quaternion(10, Vector3.RIGHT)
        pose.kneeL = Quaternion(-15, Vector3.RIGHT)
        pose.kneeR = Quaternion(-15, Vector3.RIGHT)

    else
        -- 阶段 3: 收枪恢复 (1.05s+)
        local p = math.min(1.0, (t - 1.05) / 0.35)
        local ease = p * p * (3 - 2 * p)  -- smoothstep

        pose.body = Quaternion(5 * (1 - ease), Vector3.RIGHT)
                 * Quaternion(-6 * (1 - ease), Vector3.UP)

        pose.shoulderR = Quaternion(-75 * (1 - ease), Vector3.RIGHT)
                       * Quaternion(8 * (1 - ease), Vector3.FORWARD)
        pose.elbowR = Quaternion(-15 * (1 - ease), Vector3.RIGHT)

        pose.shoulderL = Quaternion(-50 * (1 - ease), Vector3.RIGHT)
                       * Quaternion(-15 * (1 - ease), Vector3.FORWARD)
        pose.elbowL = Quaternion(-30 * (1 - ease), Vector3.RIGHT)

        pose.hipL = Quaternion(10 * (1 - ease), Vector3.RIGHT)
        pose.hipR = Quaternion(10 * (1 - ease), Vector3.RIGHT)
        pose.kneeL = Quaternion(-15 * (1 - ease), Vector3.RIGHT)
        pose.kneeR = Quaternion(-15 * (1 - ease), Vector3.RIGHT)
    end

    return pose
end

return MechAnimator
