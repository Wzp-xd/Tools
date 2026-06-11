-- ============================================================================
-- destructible_building.lua — 可破坏楼房系统
-- BOSS战场地装饰楼房，受弹时碎裂+零件飞散
-- ============================================================================

local GS = require "game_state"
local SceneBuilder = require "scene_builder"

local DestructibleBuilding = {}

-- ============================================================================
-- 配置
-- ============================================================================

local BUILDING_HP = 60            -- 楼房生命值（易摧毁）
local DEBRIS_LIFETIME = 4.0       -- 碎片存活时间
local DEBRIS_GRAVITY = -15.0      -- 碎片重力
local DEBRIS_FADE_START = 2.5     -- 碎片开始淡出时间

-- ============================================================================
-- 状态
-- ============================================================================

local buildings_ = {}             -- 所有可破坏楼房
local debris_ = {}                -- 活跃碎片列表

-- ============================================================================
-- 材质缓存
-- ============================================================================
local matA_ = nil
local matB_ = nil
local matDebris_ = nil

local function EnsureMaterials()
    if matA_ then return end
    local sceneCfg = GS.currentLevel and GS.currentLevel.scene or nil
    local bcA = (sceneCfg and sceneCfg.buildingColorA) or { 0.20, 0.16, 0.12 }
    local bcB = (sceneCfg and sceneCfg.buildingColorB) or { 0.16, 0.14, 0.10 }
    matA_ = SceneBuilder.CreatePBRMat(Color(bcA[1], bcA[2], bcA[3], 1.0), 0.1, 0.7)
    matB_ = SceneBuilder.CreatePBRMat(Color(bcB[1], bcB[2], bcB[3], 1.0), 0.05, 0.8)
    matDebris_ = SceneBuilder.CreatePBRMat(Color(0.15, 0.12, 0.10, 1.0), 0.1, 0.8)
end

-- ============================================================================
-- 创建楼房
-- ============================================================================

--- 在场地中生成一组可破坏楼房
function DestructibleBuilding.CreateAll()
    local scene = GS.scene
    if not scene then return end
    EnsureMaterials()

    -- 楼房布局（BOSS战场地 600x600 范围内）
    local layouts = {
        -- 近距离掩体（玩家周围 30~50m）
        { pos = Vector3(40, 0, 30),    w = 8,  h = 12, d = 8 },
        { pos = Vector3(-35, 0, 40),   w = 6,  h = 10, d = 10 },
        { pos = Vector3(45, 0, -25),   w = 10, h = 14, d = 6 },
        { pos = Vector3(-40, 0, -35),  w = 7,  h = 8,  d = 7 },
        { pos = Vector3(20, 0, 50),    w = 6,  h = 10, d = 6 },
        { pos = Vector3(-20, 0, -50),  w = 8,  h = 12, d = 8 },
        { pos = Vector3(30, 0, -45),   w = 6,  h = 9,  d = 6 },
        { pos = Vector3(-50, 0, 20),   w = 7,  h = 11, d = 7 },
        -- 中近距离（60~100m）
        { pos = Vector3(80, 0, 70),    w = 12, h = 18, d = 10 },
        { pos = Vector3(-75, 0, 60),   w = 8,  h = 14, d = 12 },
        { pos = Vector3(90, 0, -50),   w = 10, h = 16, d = 8 },
        { pos = Vector3(-85, 0, -70),  w = 14, h = 20, d = 10 },
        { pos = Vector3(60, 0, 100),   w = 8,  h = 10, d = 8 },
        { pos = Vector3(-60, 0, -100), w = 10, h = 12, d = 10 },
        { pos = Vector3(70, 0, -90),   w = 8,  h = 14, d = 8 },
        { pos = Vector3(-70, 0, 85),   w = 10, h = 16, d = 10 },
        { pos = Vector3(100, 0, 30),   w = 8,  h = 12, d = 10 },
        { pos = Vector3(-100, 0, -30), w = 10, h = 14, d = 8 },
        { pos = Vector3(65, 0, -65),   w = 7,  h = 12, d = 9 },
        { pos = Vector3(-95, 0, 40),   w = 9,  h = 15, d = 7 },
        { pos = Vector3(50, 0, 80),    w = 8,  h = 11, d = 8 },
        { pos = Vector3(-50, 0, -80),  w = 10, h = 13, d = 8 },
        -- 中距离（120~180m）
        { pos = Vector3(150, 0, 120),  w = 16, h = 24, d = 14 },
        { pos = Vector3(-140, 0, 150), w = 12, h = 18, d = 12 },
        { pos = Vector3(160, 0, -100), w = 10, h = 16, d = 10 },
        { pos = Vector3(-150, 0, -130),w = 14, h = 22, d = 12 },
        { pos = Vector3(120, 0, -150), w = 12, h = 16, d = 10 },
        { pos = Vector3(-120, 0, 120), w = 10, h = 14, d = 12 },
        { pos = Vector3(130, 0, 0),    w = 10, h = 18, d = 8 },
        { pos = Vector3(-130, 0, 0),   w = 8,  h = 14, d = 10 },
        { pos = Vector3(140, 0, -50),  w = 12, h = 20, d = 10 },
        { pos = Vector3(-160, 0, 80),  w = 10, h = 16, d = 12 },
        { pos = Vector3(170, 0, 60),   w = 8,  h = 14, d = 8 },
        { pos = Vector3(-110, 0, -160),w = 12, h = 18, d = 10 },
        { pos = Vector3(100, 0, 160),  w = 10, h = 15, d = 10 },
        { pos = Vector3(-170, 0, -60), w = 8,  h = 12, d = 8 },
        -- 远距离（200~280m）
        { pos = Vector3(220, 0, 180),  w = 16, h = 28, d = 14 },
        { pos = Vector3(-200, 0, 220), w = 14, h = 22, d = 14 },
        { pos = Vector3(250, 0, -150), w = 12, h = 20, d = 12 },
        { pos = Vector3(-240, 0, -200),w = 16, h = 26, d = 14 },
        { pos = Vector3(180, 0, -240), w = 10, h = 18, d = 10 },
        { pos = Vector3(-180, 0, 250), w = 12, h = 20, d = 12 },
        { pos = Vector3(0, 0, 250),    w = 14, h = 24, d = 14 },
        { pos = Vector3(0, 0, -260),   w = 12, h = 20, d = 10 },
        { pos = Vector3(200, 0, -50),  w = 10, h = 16, d = 10 },
        { pos = Vector3(-220, 0, 100), w = 14, h = 22, d = 12 },
        { pos = Vector3(260, 0, 60),   w = 12, h = 18, d = 10 },
        { pos = Vector3(-260, 0, -100),w = 10, h = 20, d = 12 },
        { pos = Vector3(180, 0, 220),  w = 12, h = 16, d = 10 },
        { pos = Vector3(-180, 0, -180),w = 14, h = 24, d = 14 },
    }

    for i, layout in ipairs(layouts) do
        local yaw = math.random() * 360  -- 随机旋转
        DestructibleBuilding.Create(layout.pos, layout.w, layout.h, layout.d, i, yaw)
    end

    print("[DestructibleBuilding] Created " .. #buildings_ .. " destructible buildings")
end

--- 创建单个可破坏楼房
---@param basePos Vector3 楼房底部中心位置
---@param w number 宽度（X）
---@param h number 高度（Y）
---@param d number 深度（Z）
---@param index number 编号
---@param yaw number|nil 水平旋转角度（度）
function DestructibleBuilding.Create(basePos, w, h, d, index, yaw)
    local scene = GS.scene
    local root = scene:CreateChild("DestructBuilding_" .. index)
    root.position = basePos
    if yaw then
        root.rotation = Quaternion(yaw, Vector3.UP)
    end

    -- 楼房主体（带碰撞）
    local bodyNode = root:CreateChild("Body")
    bodyNode.position = Vector3(0, h * 0.5, 0)
    bodyNode.scale = Vector3(w, h, d)
    local model = bodyNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial((index % 2 == 0) and matB_ or matA_)
    model.castShadows = true

    -- 碰撞体（静态刚体）
    local body = bodyNode:CreateComponent("RigidBody")
    body.collisionLayer = CollisionLayerStatic
    body.collisionMask = CollisionMaskStatic
    local shape = bodyNode:CreateComponent("CollisionShape")
    shape:SetBox(Vector3.ONE)

    -- 窗户装饰（每层3x3窗户网格）
    local windowMat = SceneBuilder.CreatePBRMat(
        Color(0.05, 0.08, 0.12, 1.0), 0.1, 0.3,
        Color(0.1, 0.2, 0.3)  -- 微弱蓝色发光
    )
    local floorH = 3.5   -- 每层楼高度
    local floors = math.floor(h / floorH)
    local winW = w * 0.15
    local winH = floorH * 0.35
    for f = 1, floors do
        local fy = (f - 0.5) * floorH
        -- 正面和背面窗户
        for side = -1, 1, 2 do
            local zOff = side * (d * 0.5 + 0.05)
            for col = -1, 1 do
                local wx = col * w * 0.3
                local winNode = root:CreateChild("Window")
                winNode.position = Vector3(wx, fy, zOff)
                winNode.scale = Vector3(winW, winH, 0.1)
                local wm = winNode:CreateComponent("StaticModel")
                wm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                wm:SetMaterial(windowMat)
                wm.castShadows = false
            end
        end
    end

    local building = {
        node = root,
        bodyNode = bodyNode,
        hp = BUILDING_HP,
        maxHp = BUILDING_HP,
        destroyed = false,
        w = w, h = h, d = d,
        basePos = Vector3(basePos.x, basePos.y, basePos.z),
        index = index,
    }
    table.insert(buildings_, building)
    return building
end

-- ============================================================================
-- 伤害 & 破坏
-- ============================================================================

--- 对位置附近的楼房造成伤害
---@param hitPos Vector3 命中世界坐标
---@param damage number 伤害值
---@param blastRadius number 爆炸半径（0=直接命中）
function DestructibleBuilding.DamageAt(hitPos, damage, blastRadius)
    local radius = math.max(blastRadius, 3.0)
    for _, b in ipairs(buildings_) do
        if not b.destroyed then
            local center = b.node.worldPosition + Vector3(0, b.h * 0.5, 0)
            local dist = (center - hitPos):Length()
            -- 检测命中（考虑楼房尺寸）
            local hitRadius = math.max(b.w, b.d) * 0.5 + radius
            if dist < hitRadius then
                local dmgFactor = 1.0
                if dist > b.w * 0.5 then
                    dmgFactor = math.max(0.2, 1.0 - (dist - b.w * 0.5) / radius)
                end
                b.hp = b.hp - damage * dmgFactor
                if b.hp <= 0 then
                    DestructibleBuilding.Destroy(b)
                end
            end
        end
    end
end

--- 摧毁楼房 - 碎裂+零件飞散
---@param b table 楼房数据
function DestructibleBuilding.Destroy(b)
    if b.destroyed then return end
    b.destroyed = true

    local scene = GS.scene
    local center = b.node.worldPosition + Vector3(0, b.h * 0.5, 0)

    -- 生成碎片
    local debrisCount = math.floor(b.w * b.h * b.d * 0.02)  -- 根据体积计算碎片数
    debrisCount = math.max(8, math.min(30, debrisCount))

    for i = 1, debrisCount do
        -- 碎片随机位置（楼房内部随机点）
        local ox = (math.random() - 0.5) * b.w
        local oy = math.random() * b.h
        local oz = (math.random() - 0.5) * b.d
        local debrisPos = b.node.worldPosition + Vector3(ox, oy, oz)

        -- 碎片随机大小
        local sw = 0.5 + math.random() * 1.5
        local sh = 0.3 + math.random() * 1.0
        local sd = 0.5 + math.random() * 1.5

        -- 创建碎片节点
        local dNode = scene:CreateChild("Debris")
        dNode.position = debrisPos
        dNode.scale = Vector3(sw, sh, sd)
        dNode.rotation = Quaternion(math.random() * 360, Vector3.UP)
            * Quaternion(math.random() * 40 - 20, Vector3.RIGHT)

        local dm = dNode:CreateComponent("StaticModel")
        dm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        dm:SetMaterial(matDebris_)
        dm.castShadows = false

        -- 随机飞散速度（从中心向外爆炸）
        local dir = (debrisPos - center)
        if dir:Length() < 0.1 then
            dir = Vector3(math.random() - 0.5, 0.5, math.random() - 0.5)
        end
        dir = dir:Normalized()
        local speed = 8 + math.random() * 15
        local vel = dir * speed + Vector3(0, 5 + math.random() * 10, 0)

        table.insert(debris_, {
            node = dNode,
            vel = vel,
            rotSpeed = Vector3(
                (math.random() - 0.5) * 400,
                (math.random() - 0.5) * 400,
                (math.random() - 0.5) * 400
            ),
            age = 0,
            mat = matDebris_,
        })
    end

    -- 爆炸闪光
    local flashNode = scene:CreateChild("BuildingExplosion")
    flashNode.position = center
    local flashScale = math.max(b.w, b.d) * 0.5
    flashNode.scale = Vector3(flashScale, flashScale, flashScale)
    local flashModel = flashNode:CreateComponent("StaticModel")
    flashModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local flashMat = Material:new()
    flashMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    flashMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.2, 0.7)))
    flashMat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0, 4.0, 1.0)))
    flashMat:SetShaderParameter("Metallic", Variant(0.0))
    flashMat:SetShaderParameter("Roughness", Variant(0.1))
    flashModel:SetMaterial(flashMat)
    flashModel.castShadows = false

    -- 爆炸光源
    local lightNode = scene:CreateChild("BuildingExpLight")
    lightNode.position = center
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = Color(1.0, 0.5, 0.1)
    lt.range = math.max(b.w, b.h) * 1.5
    lt.brightness = 5.0
    lt.castShadows = false

    -- 记录爆炸特效用于更新
    table.insert(debris_, {
        node = flashNode,
        isFlash = true,
        age = 0,
        mat = flashMat,
        lightNode = lightNode,
        light = lt,
    })

    -- 移除楼房本体
    b.node:Remove()

    print(string.format("[DestructibleBuilding] Building #%d destroyed!", b.index))
end

-- ============================================================================
-- 更新
-- ============================================================================

--- 每帧更新碎片
---@param dt number
function DestructibleBuilding.Update(dt)
    local i = 1
    while i <= #debris_ do
        local d = debris_[i]
        d.age = d.age + dt

        if d.isFlash then
            -- 爆炸闪光淡出
            if d.age > 0.5 then
                d.node:Remove()
                if d.lightNode then d.lightNode:Remove() end
                table.remove(debris_, i)
            else
                local progress = d.age / 0.5
                local s = d.node.scale.x * (1.0 + progress * 2.0)
                d.node.scale = Vector3(s, s, s)
                local alpha = 0.7 * (1.0 - progress)
                d.mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.2, alpha)))
                local emFade = math.max(0, 1.0 - progress * 2.0)
                d.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(8.0 * emFade, 4.0 * emFade, 1.0 * emFade)))
                if d.light then
                    d.light.brightness = 5.0 * (1.0 - progress)
                end
                i = i + 1
            end
        else
            -- 碎片物理
            if d.age > DEBRIS_LIFETIME then
                d.node:Remove()
                table.remove(debris_, i)
            else
                -- 重力
                d.vel = d.vel + Vector3(0, DEBRIS_GRAVITY * dt, 0)
                -- 位移
                local pos = d.node.position + d.vel * dt
                -- 地面碰撞
                if pos.y < 0.1 then
                    pos.y = 0.1
                    d.vel.x = d.vel.x * 0.7
                    d.vel.y = -d.vel.y * 0.3  -- 弹跳衰减
                    d.vel.z = d.vel.z * 0.7
                    d.rotSpeed = d.rotSpeed * 0.5
                end
                d.node.position = pos
                -- 旋转
                local curRot = d.node.rotation
                d.node.rotation = curRot
                    * Quaternion(d.rotSpeed.x * dt, Vector3.RIGHT)
                    * Quaternion(d.rotSpeed.y * dt, Vector3.UP)
                    * Quaternion(d.rotSpeed.z * dt, Vector3.FORWARD)

                -- 淡出（通过缩小）
                if d.age > DEBRIS_FADE_START then
                    local fadeProgress = (d.age - DEBRIS_FADE_START) / (DEBRIS_LIFETIME - DEBRIS_FADE_START)
                    local s = d.node.scale * (1.0 - fadeProgress * 0.8)
                    d.node.scale = s
                end
                i = i + 1
            end
        end
    end
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 获取所有存活楼房列表
---@return table[]
function DestructibleBuilding.GetBuildings()
    return buildings_
end

--- 获取存活楼房数量
---@return number
function DestructibleBuilding.GetAliveCount()
    local count = 0
    for _, b in ipairs(buildings_) do
        if not b.destroyed then count = count + 1 end
    end
    return count
end

-- ============================================================================
-- 清理
-- ============================================================================

function DestructibleBuilding.Clear()
    for _, d in ipairs(debris_) do
        if d.node then d.node:Remove() end
        if d.lightNode then d.lightNode:Remove() end
    end
    debris_ = {}
    buildings_ = {}
    matA_ = nil
    matB_ = nil
    matDebris_ = nil
end

return DestructibleBuilding
