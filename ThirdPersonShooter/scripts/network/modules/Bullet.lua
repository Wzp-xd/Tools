-- ============================================================================
-- Bullet.lua - 子弹系统（多人游戏客户端版）
-- 处理子弹轨迹、散布、枪口闪光等视觉效果
-- ============================================================================

local WeaponConfig = require "network.modules.WeaponConfig"
local Shared = require "network.Shared"

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

M.CONFIG = {
    MaxShootDistance = 100.0,     -- 最大射击距离
    BulletSpeed = 150.0,          -- 默认子弹速度（米/秒）
    BulletRadius = 0.02,          -- 子弹半径
    BulletLifetime = 3.0,         -- 子弹最大生命周期
    MuzzleFlashLifetime = 0.05,   -- 枪口闪光时间
}

-- 弹壳配置
M.CASING_CONFIG = {
    baseRadius = 0.004,           -- 弹壳半径
    baseLength = 0.015,           -- 弹壳长度
    ejectionSpeed = 3.0,          -- 抛出速度
    ejectionAngleRight = 60,      -- 向右抛出角度
    ejectionAngleUp = 30,         -- 向上抛出角度
    spinSpeed = 1500,             -- 旋转速度（度/秒）
    gravity = -9.81,              -- 重力
    lifetime = 2.0,               -- 生命周期
    brassColor = Color(0.72, 0.45, 0.20, 1.0),  -- 黄铜色
}

-- ============================================================================
-- 状态
-- ============================================================================

local bullets_ = {}      -- 子弹列表
local casings_ = {}      -- 弹壳列表
local scene_ = nil       -- 场景引用

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init(scene)
    scene_ = scene
    bullets_ = {}
    casings_ = {}
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 基于方向向量构建本地坐标系（用于散布计算）
---@param direction Vector3 方向向量（已归一化）
---@return Vector3 localRight 本地右向量
---@return Vector3 localUp 本地上向量
function M.GetLocalAxes(direction)
    local refUp = Vector3.UP
    if math.abs(direction.y) > 0.99 then
        refUp = Vector3.FORWARD
    end
    
    local localRight = direction:CrossProduct(refUp):Normalized()
    local localUp = localRight:CrossProduct(direction):Normalized()
    
    return localRight, localUp
end

--- 创建 RibbonTrail 拖尾材质（无贴图，自发光）
local function CreateRibbonTrailMaterial()
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.3, 1.0)))
    mat:SetCullMode(CULL_NONE)  -- 双面渲染
    return mat
end

-- ============================================================================
-- 瞄准射线计算
-- ============================================================================

--- 判断命中点是否在蹲下角色的空气区域（碰撞胶囊未缩小的上半部分）
---@param node Node 被命中的节点
---@param hitPos Vector3 命中位置
---@return boolean 是否为空气区域命中
local function IsCrouchAirZoneHit(node, hitPos)
    if not string.find(node.name or "", "Role_") then
        return false
    end
    local crouchVar = node:GetVar(Shared.VARS.IS_CROUCHING)
    local isCrouching = (not crouchVar:IsEmpty()) and crouchVar:GetBool() or false
    if not isCrouching then
        return false
    end
    local relY = hitPos.y - node.position.y
    local effectiveHeight = Shared.Settings.Player.Height - Shared.Settings.Player.CrouchHeightDelta
    return relY > effectiveHeight
end

--- 从屏幕中心获取瞄准目标点
---@param camera Camera 相机组件
---@param physicsWorld PhysicsWorld 物理世界
---@param characterPos Vector3|nil 角色位置（用于过滤角色后方的碰撞）
---@return Vector3 targetPoint 目标点
---@return table|nil hitResult 命中结果（如果有）
function M.GetAimTargetPoint(camera, physicsWorld, characterPos)
    local screenCenter = Vector2(0.5, 0.5)
    local cameraRay = camera:GetScreenRay(screenCenter.x, screenCenter.y)
    local targetPoint = cameraRay.origin + cameraRay.direction * M.CONFIG.MaxShootDistance
    
    local hitResult = nil
    if physicsWorld then
        -- mask: ENVIRONMENT(1) + MONSTER(2) + MONSTER_HEAD(4) + TARGET(64) = 71
        local results = physicsWorld:Raycast(cameraRay, M.CONFIG.MaxShootDistance, 71)
        for j = 1, #results do
            local r = results[j]
            if r.body then
                local node = r.body:GetNode()
                -- 跳过蹲下角色碰撞胶囊的空气区域
                if not IsCrouchAirZoneHit(node, r.position) then
                    -- 过滤角色后方的碰撞：只接受在角色前方的命中
                    local accept = true
                    if characterPos then
                        local cameraToChar = characterPos - cameraRay.origin
                        local minDistance = cameraToChar:DotProduct(cameraRay.direction)
                        if r.distance < minDistance then
                            accept = false
                        end
                    end
                    if accept then
                        targetPoint = r.position
                        hitResult = {
                            position = r.position,
                            normal = r.normal,
                            node = node,
                            distance = r.distance,
                        }
                        break
                    end
                end
            end
        end
    end
    
    return targetPoint, hitResult
end

--- 计算带散布的射击方向（角度单位版本）
---@param baseDirection Vector3 基础方向
---@param crosshairSpreadDeg number 准星扩散角度（度）
---@param weaponSpreadDeg number 武器固有散布角度（度）
---@return Vector3 direction 最终方向
function M.ApplySpreadDeg(baseDirection, crosshairSpreadDeg, weaponSpreadDeg)
    local direction = baseDirection
    
    -- 准星扩散（射击后增加的扩散，单位：度）
    if crosshairSpreadDeg and crosshairSpreadDeg > 0 then
        local spreadRad = math.rad(crosshairSpreadDeg)
        local randomAngle = math.random() * math.pi * 2
        local randomRadius = math.random() * spreadRad
        local offsetYaw = math.cos(randomAngle) * randomRadius
        local offsetPitch = math.sin(randomAngle) * randomRadius
        
        local localRight, localUp = M.GetLocalAxes(direction)
        local spreadRotation = Quaternion(math.deg(offsetPitch), localRight) * 
                               Quaternion(math.deg(offsetYaw), localUp)
        direction = spreadRotation * direction
    end
    
    -- 武器固有散布（如霰弹枪，单位：度）
    if weaponSpreadDeg and weaponSpreadDeg > 0 then
        local spreadRad = math.rad(weaponSpreadDeg)
        local randomYaw = (math.random() - 0.5) * 2 * spreadRad
        local randomPitch = (math.random() - 0.5) * 2 * spreadRad
        
        local localRight, localUp = M.GetLocalAxes(direction)
        local spreadRotation = Quaternion(math.deg(randomPitch), localRight) * 
                               Quaternion(math.deg(randomYaw), localUp)
        direction = spreadRotation * direction
    end
    
    return direction
end

--- [已废弃] 计算带散布的射击方向（像素单位版本，保留兼容）
---@deprecated 使用 ApplySpreadDeg 代替
function M.ApplySpread(baseDirection, crosshairSpread, weaponSpreadAngle)
    -- 兼容旧接口：像素 * 0.15 = 角度
    local crosshairSpreadDeg = crosshairSpread and (crosshairSpread * 0.15) or 0
    return M.ApplySpreadDeg(baseDirection, crosshairSpreadDeg, weaponSpreadAngle)
end

-- ============================================================================
-- 子弹创建（视觉效果）
-- ============================================================================

--- 创建子弹（带拖尾效果）
---@param muzzlePos Vector3 枪口位置
---@param direction Vector3 射击方向
---@param weaponConfig table|nil 武器配置
function M.CreateBullet(muzzlePos, direction, weaponConfig)
    if not scene_ then return end
    
    local bulletSpeed = M.CONFIG.BulletSpeed
    local bulletRadius = M.CONFIG.BulletRadius
    
    if weaponConfig then
        bulletSpeed = weaponConfig.bulletSpeed or bulletSpeed
        bulletRadius = weaponConfig.bulletRadius or bulletRadius
    end
    
    local bulletNode = scene_:CreateChild("Bullet", LOCAL)
    bulletNode.position = muzzlePos
    bulletNode.scale = Vector3(bulletRadius * 2, bulletRadius * 2, bulletRadius * 2)
    
    -- 子弹模型（发光球体）
    local model = bulletNode:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.8))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.0, 0.0)))
    model:SetMaterial(mat)
    
    -- 添加 RibbonTrail 拖尾特效
    local trail = bulletNode:CreateComponent("RibbonTrail", LOCAL)
    trail:SetMaterial(CreateRibbonTrailMaterial())
    trail:SetTrailType(TT_FACE_CAMERA)      -- 面向相机
    trail:SetWidth(bulletRadius * 3)         -- 拖尾宽度
    trail:SetStartColor(Color(1.0, 0.8, 0.3, 1.0))   -- 起始颜色（亮黄）
    trail:SetEndColor(Color(1.0, 0.4, 0.1, 0.0))     -- 结束颜色（淡橙，透明）
    trail:SetStartScale(1.0)                 -- 起始缩放
    trail:SetEndScale(0.1)                   -- 结束缩放（逐渐变细）
    trail:SetLifetime(0.03)                  -- 拖尾生命周期（秒）
    trail:SetVertexDistance(0.05)            -- 顶点间隔
    trail:SetEmitting(true)                  -- 开始发射
    trail:SetSorted(true)                    -- 排序渲染
    
    -- 让子弹朝向飞行方向
    bulletNode.rotation = Quaternion(Vector3.FORWARD, direction)
    
    -- 子弹数据
    local bullet = {
        node = bulletNode,
        direction = direction,
        speed = bulletSpeed,
        startPosition = muzzlePos,
        prevPosition = muzzlePos,
        lifetime = 0,
        maxLifetime = M.CONFIG.BulletLifetime,
        maxDistance = M.CONFIG.MaxShootDistance,
        traveledDistance = 0,
        isLocalBullet = true,  -- 本地子弹，进行碰撞检测
    }
    
    table.insert(bullets_, bullet)
end

--- 创建服务器同步的视觉子弹（不进行本地碰撞检测）
---@param startPos Vector3 起始位置
---@param direction Vector3 方向
---@param speed number 速度
---@param bulletId number 子弹 ID（服务器分配）
---@param weaponConfig table|nil 武器配置
function M.CreateBulletFromServer(startPos, direction, speed, bulletId, weaponConfig)
    if not scene_ then return end
    
    local bulletRadius = M.CONFIG.BulletRadius
    if weaponConfig then
        bulletRadius = weaponConfig.bulletRadius or bulletRadius
    end
    
    local bulletNode = scene_:CreateChild("ServerBullet", LOCAL)
    bulletNode.position = startPos
    bulletNode.scale = Vector3(bulletRadius * 2, bulletRadius * 2, bulletRadius * 2)
    
    -- 子弹模型（发光球体）
    local model = bulletNode:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.8))
    mat:SetShaderParameter("Roughness", Variant(0.2))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(3.0, 2.0, 0.0)))
    model:SetMaterial(mat)
    
    -- 添加 RibbonTrail 拖尾特效
    local trail = bulletNode:CreateComponent("RibbonTrail", LOCAL)
    trail:SetMaterial(CreateRibbonTrailMaterial())
    trail:SetTrailType(TT_FACE_CAMERA)
    trail:SetWidth(bulletRadius * 3)
    trail:SetStartColor(Color(1.0, 0.8, 0.3, 1.0))
    trail:SetEndColor(Color(1.0, 0.4, 0.1, 0.0))
    trail:SetStartScale(1.0)
    trail:SetEndScale(0.1)
    trail:SetLifetime(0.03)
    trail:SetVertexDistance(0.05)
    trail:SetEmitting(true)
    trail:SetSorted(true)
    
    -- 让子弹朝向飞行方向
    bulletNode.rotation = Quaternion(Vector3.FORWARD, direction)
    
    -- 子弹数据
    local bullet = {
        id = bulletId,           -- 服务器分配的 ID
        node = bulletNode,
        direction = direction,
        speed = speed,
        startPosition = startPos,
        prevPosition = startPos,
        lifetime = 0,
        maxLifetime = M.CONFIG.BulletLifetime,
        maxDistance = M.CONFIG.MaxShootDistance,
        traveledDistance = 0,
        isServerBullet = true,   -- 服务器同步的子弹，不进行本地碰撞检测
    }
    
    table.insert(bullets_, bullet)
end

--- 根据 ID 移除子弹（服务器同步时调用）
---@param bulletId number 子弹 ID
function M.RemoveBulletById(bulletId)
    for i, bullet in ipairs(bullets_) do
        if bullet.id == bulletId then
            if bullet.node then
                bullet.node:Remove()
            end
            table.remove(bullets_, i)
            return
        end
    end
end

--- 获取子弹方向（用于命中特效）
---@param bulletId number 子弹ID
---@return Vector3|nil direction 子弹方向，未找到返回nil
function M.GetBulletDirection(bulletId)
    for _, bullet in ipairs(bullets_) do
        if bullet.id == bulletId then
            return bullet.direction
        end
    end
    return nil
end

--- 创建枪口闪光
---@param muzzlePos Vector3 枪口位置（当 parentNode 为 nil 时使用）
---@param parentNode Node|nil 枪口节点，传入时火光作为子节点绑定在枪口上
function M.CreateMuzzleFlash(muzzlePos, parentNode)
    if not scene_ then return end
    
    local flashNode
    if parentNode then
        flashNode = parentNode:CreateChild("MuzzleFlash", LOCAL)
        flashNode.position = Vector3.ZERO
    else
        flashNode = scene_:CreateChild("MuzzleFlash", LOCAL)
        flashNode.position = muzzlePos
    end
    flashNode.scale = Vector3(0.06, 0.06, 0.06)
    
    local model = flashNode:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.1, 1.0)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(5.0, 3.0, 0.5)))
    model:SetMaterial(mat)
    
    local flash = {
        node = flashNode,
        lifetime = 0,
        maxLifetime = M.CONFIG.MuzzleFlashLifetime,
        isFlash = true,
    }
    table.insert(bullets_, flash)
end

--- 创建抛出的弹壳
---@param ejectionPos Vector3 抛壳口位置
---@param gunRotation Quaternion 枪的旋转
---@param isLeftHanded boolean 是否左手持枪
function M.CreateEjectedCasing(ejectionPos, gunRotation, isLeftHanded)
    if not scene_ then return end
    
    local cfg = M.CASING_CONFIG
    
    local casingNode = scene_:CreateChild("Casing", LOCAL)
    casingNode.position = ejectionPos
    casingNode.scale = Vector3(cfg.baseRadius * 2, cfg.baseLength, cfg.baseRadius * 2)
    
    local model = casingNode:CreateComponent("StaticModel", LOCAL)
    model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(cfg.brassColor))
    mat:SetShaderParameter("Metallic", Variant(0.9))
    mat:SetShaderParameter("Roughness", Variant(0.3))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.3, 0.2, 0.05)))
    model:SetMaterial(mat)
    model.castShadows = false
    
    -- 计算抛出方向
    local rightDir = gunRotation * Vector3.RIGHT
    local upDir = gunRotation * Vector3.UP
    local backDir = gunRotation * Vector3.BACK
    
    local handednessSign = isLeftHanded and -1 or 1
    
    local ejectionDir = (
        rightDir * handednessSign * math.cos(math.rad(cfg.ejectionAngleRight)) +
        upDir * math.sin(math.rad(cfg.ejectionAngleUp)) +
        backDir * 0.3
    ):Normalized()
    
    -- 添加随机性
    local randomYaw = (math.random() - 0.5) * 20
    local randomPitch = (math.random() - 0.5) * 15
    local randomRotation = Quaternion(randomPitch, Vector3.RIGHT) * Quaternion(randomYaw, Vector3.UP)
    ejectionDir = randomRotation * ejectionDir
    
    local speed = cfg.ejectionSpeed * (0.8 + math.random() * 0.4)
    
    casingNode.rotation = Quaternion(math.random() * 360, Vector3.RIGHT) * 
                          Quaternion(math.random() * 360, Vector3.UP)
    
    local casing = {
        node = casingNode,
        velocity = ejectionDir * speed,
        lifetime = 0,
        maxLifetime = cfg.lifetime,
        spinAxis = Vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5):Normalized(),
        spinSpeed = cfg.spinSpeed * (0.7 + math.random() * 0.6),
    }
    
    table.insert(casings_, casing)
end

-- ============================================================================
-- 更新
-- ============================================================================

--- 更新子弹和弹壳
---@param dt number 帧时间
---@param physicsWorld PhysicsWorld|nil 物理世界（用于碰撞检测）
---@param onHit function|nil 命中回调（仅本地子弹使用）
function M.Update(dt, physicsWorld, onHit)
    -- 更新子弹
    local toRemove = {}
    
    for i, bullet in ipairs(bullets_) do
        if bullet.node then
            bullet.lifetime = bullet.lifetime + dt
            
            if bullet.isFlash then
                -- 枪口闪光
                if bullet.lifetime >= bullet.maxLifetime then
                    bullet.node:Remove()
                    table.insert(toRemove, i)
                end
            elseif bullet.isServerBullet then
                -- 服务器同步的子弹：只更新位置，不进行碰撞检测
                -- 碰撞由服务器处理，客户端通过 BULLET_HIT 事件接收结果
                local frameDistance = bullet.speed * dt
                local newPos = bullet.prevPosition + bullet.direction * frameDistance
                
                bullet.node.position = newPos
                bullet.prevPosition = newPos
                bullet.traveledDistance = bullet.traveledDistance + frameDistance
                
                -- 超过最大距离或生命周期时移除（安全检查）
                if bullet.traveledDistance >= bullet.maxDistance or 
                   bullet.lifetime >= bullet.maxLifetime then
                    bullet.node:Remove()
                    table.insert(toRemove, i)
                end
            else
                -- 本地子弹：进行碰撞检测
                local frameDistance = bullet.speed * dt
                local newPos = bullet.prevPosition + bullet.direction * frameDistance
                
                -- 射线检测碰撞（使用 Raycast 获取多个结果以跳过蹲下角色空气区域）
                local hit = false
                if physicsWorld then
                    local ray = Ray(bullet.prevPosition, bullet.direction)
                    -- mask: ENVIRONMENT(1) + MONSTER(2) + MONSTER_HEAD(4) + TARGET(64) = 71
                    local results = physicsWorld:Raycast(ray, frameDistance + 0.1, 71)
                    for j = 1, #results do
                        local r = results[j]
                        if r.body and r.distance <= frameDistance + 0.05 then
                            local node = r.body:GetNode()
                            if not IsCrouchAirZoneHit(node, r.position) then
                                hit = true
                                if onHit then
                                    onHit(r.position, r.normal, node)
                                end
                                break
                            end
                        end
                    end
                end
                
                if hit then
                    bullet.node:Remove()
                    table.insert(toRemove, i)
                else
                    bullet.node.position = newPos
                    bullet.prevPosition = newPos
                    bullet.traveledDistance = bullet.traveledDistance + frameDistance
                    
                    -- 超过最大距离或生命周期
                    if bullet.traveledDistance >= bullet.maxDistance or 
                       bullet.lifetime >= bullet.maxLifetime then
                        bullet.node:Remove()
                        table.insert(toRemove, i)
                    end
                end
            end
        else
            table.insert(toRemove, i)
        end
    end
    
    for i = #toRemove, 1, -1 do
        table.remove(bullets_, toRemove[i])
    end
    
    -- 更新弹壳
    toRemove = {}
    local cfg = M.CASING_CONFIG
    
    for i, casing in ipairs(casings_) do
        if casing.node then
            casing.lifetime = casing.lifetime + dt
            
            if casing.lifetime >= casing.maxLifetime then
                casing.node:Remove()
                table.insert(toRemove, i)
            else
                -- 应用重力
                casing.velocity = casing.velocity + Vector3(0, cfg.gravity * dt, 0)
                
                -- 更新位置
                casing.node.position = casing.node.position + casing.velocity * dt
                
                -- 旋转
                local spinAngle = casing.spinSpeed * dt
                local currentRot = casing.node.rotation
                local spinRot = Quaternion(spinAngle, casing.spinAxis)
                casing.node.rotation = spinRot * currentRot
                
                -- 淡出效果
                local fadeTime = 0.3
                local remaining = casing.maxLifetime - casing.lifetime
                if remaining < fadeTime then
                    local alpha = remaining / fadeTime
                    local scale = casing.node.scale * (0.5 + 0.5 * alpha)
                    casing.node.scale = scale
                end
            end
        else
            table.insert(toRemove, i)
        end
    end
    
    for i = #toRemove, 1, -1 do
        table.remove(casings_, toRemove[i])
    end
end

--- 清除所有子弹和弹壳
function M.ClearAll()
    for _, bullet in ipairs(bullets_) do
        if bullet.node then
            bullet.node:Remove()
        end
    end
    bullets_ = {}
    
    for _, casing in ipairs(casings_) do
        if casing.node then
            casing.node:Remove()
        end
    end
    casings_ = {}
end

return M
