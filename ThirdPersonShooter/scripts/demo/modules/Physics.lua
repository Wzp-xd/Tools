-- ============================================================================
-- Physics.lua - 射线碰撞检测工具（简化版 - 仅保留射线检测）
-- ============================================================================
-- 注意：玩家和怪物的移动碰撞现在由引擎物理系统处理
-- 本模块仅保留用于子弹、手榴弹等射线检测的工具函数

local M = {}

-- ============================================================================
-- 射线碰撞检测函数
-- ============================================================================

--- 射线与球体相交检测
--- @param rayOrigin Vector3 射线起点
--- @param rayDir Vector3 射线方向（已归一化）
--- @param sphereCenter Vector3 球心
--- @param sphereRadius number 球半径
--- @return number|nil 返回交点距离，无交点返回nil
function M.RaySphereIntersect(rayOrigin, rayDir, sphereCenter, sphereRadius)
    local oc = rayOrigin - sphereCenter
    local a = rayDir:DotProduct(rayDir)
    local b = 2.0 * oc:DotProduct(rayDir)
    local c = oc:DotProduct(oc) - sphereRadius * sphereRadius
    
    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then
        return nil
    end
    
    local sqrtD = math.sqrt(discriminant)
    local t1 = (-b - sqrtD) / (2 * a)
    local t2 = (-b + sqrtD) / (2 * a)
    
    if t1 > 0.001 then
        return t1
    elseif t2 > 0.001 then
        return t2
    end
    
    return nil
end

--- 射线与 AABB 盒相交检测
--- @param rayOrigin Vector3 射线起点
--- @param rayDir Vector3 射线方向（已归一化）
--- @param boxMin Vector3 AABB 最小点
--- @param boxMax Vector3 AABB 最大点
--- @return number|nil 返回交点距离，无交点返回 nil
function M.RayAABBIntersect(rayOrigin, rayDir, boxMin, boxMax)
    local tmin = -math.huge
    local tmax = math.huge
    
    -- X 轴
    if math.abs(rayDir.x) > 0.0001 then
        local t1 = (boxMin.x - rayOrigin.x) / rayDir.x
        local t2 = (boxMax.x - rayOrigin.x) / rayDir.x
        if t1 > t2 then t1, t2 = t2, t1 end
        tmin = math.max(tmin, t1)
        tmax = math.min(tmax, t2)
    else
        if rayOrigin.x < boxMin.x or rayOrigin.x > boxMax.x then
            return nil
        end
    end
    
    -- Y 轴
    if math.abs(rayDir.y) > 0.0001 then
        local t1 = (boxMin.y - rayOrigin.y) / rayDir.y
        local t2 = (boxMax.y - rayOrigin.y) / rayDir.y
        if t1 > t2 then t1, t2 = t2, t1 end
        tmin = math.max(tmin, t1)
        tmax = math.min(tmax, t2)
    else
        if rayOrigin.y < boxMin.y or rayOrigin.y > boxMax.y then
            return nil
        end
    end
    
    -- Z 轴
    if math.abs(rayDir.z) > 0.0001 then
        local t1 = (boxMin.z - rayOrigin.z) / rayDir.z
        local t2 = (boxMax.z - rayOrigin.z) / rayDir.z
        if t1 > t2 then t1, t2 = t2, t1 end
        tmin = math.max(tmin, t1)
        tmax = math.min(tmax, t2)
    else
        if rayOrigin.z < boxMin.z or rayOrigin.z > boxMax.z then
            return nil
        end
    end
    
    if tmax < 0 or tmin > tmax then
        return nil
    end
    
    return tmin > 0 and tmin or tmax
end

--- 射线与圆柱体相交检测（用于检测怪物）
--- @param rayOrigin Vector3 射线起点
--- @param rayDir Vector3 射线方向（已归一化）
--- @param cylinderCenter Vector3 圆柱体中心位置
--- @param cylinderRadius number 圆柱体半径
--- @param cylinderHeight number 圆柱体高度
--- @return number|nil hitDist 击中距离
--- @return number|nil hitY 击中点的Y坐标（用于判断爆头）
function M.RayCylinderIntersect(rayOrigin, rayDir, cylinderCenter, cylinderRadius, cylinderHeight)
    local yBottom = cylinderCenter.y - cylinderHeight / 2
    local yTop = cylinderCenter.y + cylinderHeight / 2
    
    local ox = rayOrigin.x - cylinderCenter.x
    local oz = rayOrigin.z - cylinderCenter.z
    local dx = rayDir.x
    local dz = rayDir.z
    
    local a = dx * dx + dz * dz
    local b = 2 * (ox * dx + oz * dz)
    local c = ox * ox + oz * oz - cylinderRadius * cylinderRadius
    
    if a < 0.0001 then
        if c > 0 then return nil, nil end
        
        if rayDir.y > 0.0001 then
            local t = (yBottom - rayOrigin.y) / rayDir.y
            if t > 0 then return t, yBottom end
        elseif rayDir.y < -0.0001 then
            local t = (yTop - rayOrigin.y) / rayDir.y
            if t > 0 then return t, yTop end
        end
        return nil, nil
    end
    
    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then return nil, nil end
    
    local sqrtD = math.sqrt(discriminant)
    local t1 = (-b - sqrtD) / (2 * a)
    local t2 = (-b + sqrtD) / (2 * a)
    
    local hitT = nil
    local hitY = nil
    for _, t in ipairs({t1, t2}) do
        if t > 0.001 then
            local y = rayOrigin.y + rayDir.y * t
            if y >= yBottom and y <= yTop then
                if hitT == nil or t < hitT then
                    hitT = t
                    hitY = y
                end
            end
        end
    end
    
    if math.abs(rayDir.y) > 0.0001 then
        local tBottom = (yBottom - rayOrigin.y) / rayDir.y
        if tBottom > 0.001 then
            local hx = rayOrigin.x + rayDir.x * tBottom - cylinderCenter.x
            local hz = rayOrigin.z + rayDir.z * tBottom - cylinderCenter.z
            if hx * hx + hz * hz <= cylinderRadius * cylinderRadius then
                if hitT == nil or tBottom < hitT then
                    hitT = tBottom
                    hitY = yBottom
                end
            end
        end
        
        local tTop = (yTop - rayOrigin.y) / rayDir.y
        if tTop > 0.001 then
            local hx = rayOrigin.x + rayDir.x * tTop - cylinderCenter.x
            local hz = rayOrigin.z + rayDir.z * tTop - cylinderCenter.z
            if hx * hx + hz * hz <= cylinderRadius * cylinderRadius then
                if hitT == nil or tTop < hitT then
                    hitT = tTop
                    hitY = yTop
                end
            end
        end
    end
    
    return hitT, hitY
end

--- 射线检测所有碰撞体（墙壁和柱子）
--- @param rayOrigin Vector3 射线起点
--- @param rayDir Vector3 射线方向
--- @param maxDist number 最大检测距离
--- @param colliders table 碰撞体列表
--- @return number|nil hitDist 击中距离
--- @return Vector3|nil hitPoint 击中点
function M.RaycastColliders(rayOrigin, rayDir, maxDist, colliders)
    local closestDist = maxDist
    local hitPoint = nil
    
    for _, collider in ipairs(colliders) do
        local hitDist = M.RayAABBIntersect(rayOrigin, rayDir, collider.min, collider.max)
        if hitDist and hitDist > 0 and hitDist < closestDist then
            closestDist = hitDist
            hitPoint = rayOrigin + rayDir * hitDist
        end
    end
    
    if hitPoint then
        return closestDist, hitPoint
    end
    return nil, nil
end

--- 球体与球体碰撞检测
--- @param pos1 Vector3 球体1中心
--- @param radius1 number 球体1半径
--- @param pos2 Vector3 球体2中心
--- @param radius2 number 球体2半径
--- @return boolean 是否碰撞
function M.SphereSphereCollision(pos1, radius1, pos2, radius2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    local distSq = dx * dx + dy * dy + dz * dz
    local radiusSum = radius1 + radius2
    return distSq < radiusSum * radiusSum
end

--- 点与 AABB 碰撞检测
--- @param point Vector3 点位置
--- @param boxMin Vector3 AABB 最小点
--- @param boxMax Vector3 AABB 最大点
--- @return boolean 是否在 AABB 内部
function M.PointInAABB(point, boxMin, boxMax)
    return point.x >= boxMin.x and point.x <= boxMax.x
       and point.y >= boxMin.y and point.y <= boxMax.y
       and point.z >= boxMin.z and point.z <= boxMax.z
end

--- 球体与 AABB 碰撞检测
--- @param sphereCenter Vector3 球心
--- @param sphereRadius number 球半径
--- @param boxMin Vector3 AABB 最小点
--- @param boxMax Vector3 AABB 最大点
--- @return boolean 是否碰撞
function M.SphereAABBCollision(sphereCenter, sphereRadius, boxMin, boxMax)
    local closestX = math.max(boxMin.x, math.min(sphereCenter.x, boxMax.x))
    local closestY = math.max(boxMin.y, math.min(sphereCenter.y, boxMax.y))
    local closestZ = math.max(boxMin.z, math.min(sphereCenter.z, boxMax.z))
    
    local dx = sphereCenter.x - closestX
    local dy = sphereCenter.y - closestY
    local dz = sphereCenter.z - closestZ
    local distSq = dx * dx + dy * dy + dz * dz
    
    return distSq < sphereRadius * sphereRadius
end

return M
