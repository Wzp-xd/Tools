-- ============================================================================
-- environment.lua — 竞技场环境（建筑、云层、装饰物、屏障）
-- 从 main.lua L976-1249 提取
-- ============================================================================

local CONFIG = require "config"
local GS = require "game_state"
local SceneBuilder = require "scene_builder"

local Environment = {}

-- ============================================================================
-- 建筑
-- ============================================================================

--- 创建竞技场环境（建筑群）
function Environment.Create()
    local scene = GS.scene
    local sceneCfg = GS.currentLevel and GS.currentLevel.scene or nil

    local bcA = (sceneCfg and sceneCfg.buildingColorA) or { 0.18, 0.18, 0.2 }
    local bcB = (sceneCfg and sceneCfg.buildingColorB) or { 0.25, 0.22, 0.2 }
    local bmA = (sceneCfg and sceneCfg.buildingMetallicA) or 0.1
    local bmB = (sceneCfg and sceneCfg.buildingMetallicB) or 0.0
    local buildingMat = SceneBuilder.CreatePBRMat(Color(bcA[1], bcA[2], bcA[3], 1.0), bmA, 0.7)
    local wallMat     = SceneBuilder.CreatePBRMat(Color(bcB[1], bcB[2], bcB[3], 1.0), bmB, 0.8)

    local buildings = {
        -- 中心区域
        { pos = Vector3(30, 4, 30),     scale = Vector3(8, 8, 8) },
        { pos = Vector3(-25, 3, 35),    scale = Vector3(6, 6, 10) },
        { pos = Vector3(35, 5, -20),    scale = Vector3(10, 10, 6) },
        { pos = Vector3(-30, 2.5, -25), scale = Vector3(5, 5, 5) },
        { pos = Vector3(0, 1.5, 40),    scale = Vector3(15, 3, 3) },
        { pos = Vector3(-40, 3, 0),     scale = Vector3(4, 6, 12) },
        { pos = Vector3(20, 1, -35),    scale = Vector3(12, 2, 4) },
        -- 近距离扩展（50~100m）
        { pos = Vector3(70, 6, 60),     scale = Vector3(12, 12, 12) },
        { pos = Vector3(-80, 4, 50),    scale = Vector3(8, 8, 16) },
        { pos = Vector3(60, 3, -70),    scale = Vector3(6, 6, 6) },
        { pos = Vector3(-60, 5, -80),   scale = Vector3(10, 10, 8) },
        { pos = Vector3(90, 2, 0),      scale = Vector3(20, 4, 4) },
        { pos = Vector3(-90, 3.5, 20),  scale = Vector3(5, 7, 14) },
        { pos = Vector3(0, 4, -90),     scale = Vector3(8, 8, 8) },
        { pos = Vector3(50, 1.5, 80),   scale = Vector3(14, 3, 6) },
        -- 中距离区域（100~200m）
        { pos = Vector3(150, 8, 120),   scale = Vector3(16, 16, 16) },
        { pos = Vector3(-140, 6, 160),  scale = Vector3(12, 12, 20) },
        { pos = Vector3(180, 5, -100),  scale = Vector3(10, 10, 10) },
        { pos = Vector3(-120, 10, -150),scale = Vector3(14, 20, 14) },
        { pos = Vector3(100, 3, 180),   scale = Vector3(20, 6, 6) },
        { pos = Vector3(-180, 4, 0),    scale = Vector3(8, 8, 24) },
        { pos = Vector3(0, 7, 160),     scale = Vector3(10, 14, 10) },
        { pos = Vector3(160, 3, 160),   scale = Vector3(6, 6, 6) },
        { pos = Vector3(-160, 5, -100), scale = Vector3(12, 10, 8) },
        -- 远距离区域（200~400m）
        { pos = Vector3(300, 12, 200),  scale = Vector3(20, 24, 20) },
        { pos = Vector3(-250, 8, 300),  scale = Vector3(16, 16, 16) },
        { pos = Vector3(350, 6, -150),  scale = Vector3(12, 12, 12) },
        { pos = Vector3(-300, 10, -250),scale = Vector3(18, 20, 14) },
        { pos = Vector3(200, 4, -300),  scale = Vector3(24, 8, 8) },
        { pos = Vector3(-200, 7, 250),  scale = Vector3(10, 14, 18) },
        { pos = Vector3(250, 5, 350),   scale = Vector3(8, 10, 8) },
        { pos = Vector3(-350, 6, 100),  scale = Vector3(14, 12, 10) },
        { pos = Vector3(0, 15, 350),    scale = Vector3(20, 30, 20) },
        { pos = Vector3(0, 8, -300),    scale = Vector3(30, 16, 6) },
        -- 边缘区域（350~450m）
        { pos = Vector3(400, 10, 400),  scale = Vector3(16, 20, 16) },
        { pos = Vector3(-400, 8, 350),  scale = Vector3(12, 16, 12) },
        { pos = Vector3(420, 6, -300),  scale = Vector3(10, 12, 10) },
        { pos = Vector3(-380, 12, -400),scale = Vector3(20, 24, 16) },
        { pos = Vector3(350, 4, 0),     scale = Vector3(30, 8, 8) },
        { pos = Vector3(-420, 5, -50),  scale = Vector3(8, 10, 20) },
        { pos = Vector3(100, 6, -420),  scale = Vector3(12, 12, 12) },
        { pos = Vector3(-100, 4, 400),  scale = Vector3(16, 8, 10) },
    }

    local noBuildings = GS.currentLevel and GS.currentLevel.noBuildings
    local clearX = GS.currentLevel and GS.currentLevel.buildingClearX or 0
    for i, b in ipairs(buildings) do
        if not noBuildings then
            if clearX > 0 and math.abs(b.pos.x) - b.scale.x * 0.5 < clearX then
                -- 跳过走廊内的建筑
            else
                local mat = (i % 2 == 0) and wallMat or buildingMat
                SceneBuilder.CreateStaticBox(scene, "Building" .. i, b.pos, b.scale, mat)
            end
        end
    end

    -- 装饰物、云层、屏障
    Environment.CreateDecorations()
    Environment.CreateClouds()
    Environment.CreateBarriers()
end

-- ============================================================================
-- 云层
-- ============================================================================

--- 在远处高空生成云层（变形球体聚簇）
function Environment.CreateClouds()
    local scene = GS.scene
    local CLOUD_MIN_DIST    = 200
    local CLOUD_MAX_DIST    = 600
    local CLOUD_MIN_HEIGHT  = 120
    local CLOUD_MAX_HEIGHT  = 260
    local CLOUD_COUNT       = 25
    local BLOBS_MIN         = 5
    local BLOBS_MAX         = 12

    local cloudMat = Material:new()
    cloudMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    cloudMat:SetShaderParameter("MatDiffColor", Variant(Color(0.95, 0.95, 0.97, 0.55)))
    cloudMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.6, 0.6, 0.7)))
    cloudMat:SetShaderParameter("Metallic", Variant(0.0))
    cloudMat:SetShaderParameter("Roughness", Variant(1.0))

    local sphereModel = cache:GetResource("Model", "Models/Sphere.mdl")
    local totalBlobs = 0

    for c = 1, CLOUD_COUNT do
        local angle = math.random() * math.pi * 2
        local dist = CLOUD_MIN_DIST + math.random() * (CLOUD_MAX_DIST - CLOUD_MIN_DIST)
        local height = CLOUD_MIN_HEIGHT + math.random() * (CLOUD_MAX_HEIGHT - CLOUD_MIN_HEIGHT)
        local cx = math.cos(angle) * dist
        local cz = math.sin(angle) * dist

        local distRatio = (dist - CLOUD_MIN_DIST) / (CLOUD_MAX_DIST - CLOUD_MIN_DIST)
        local baseSize = 30 + distRatio * 50

        local cloudRoot = scene:CreateChild("Cloud_" .. c)
        cloudRoot.position = Vector3(cx, height, cz)

        local blobCount = BLOBS_MIN + math.random(0, BLOBS_MAX - BLOBS_MIN)
        for b = 1, blobCount do
            local blobNode = cloudRoot:CreateChild("Blob")
            local ox = (math.random() - 0.5) * baseSize * 2.0
            local oy = (math.random() - 0.5) * baseSize * 0.4
            local oz = (math.random() - 0.5) * baseSize * 1.6
            blobNode.position = Vector3(ox, oy, oz)

            local sx = (0.6 + math.random() * 0.8) * baseSize * 0.35
            local sy = sx * (0.25 + math.random() * 0.25)
            local sz = (0.6 + math.random() * 0.8) * baseSize * 0.35
            blobNode.scale = Vector3(sx, sy, sz)
            blobNode.rotation = Quaternion(math.random() * 360, Vector3.UP)

            local model = blobNode:CreateComponent("StaticModel")
            model:SetModel(sphereModel)
            model:SetMaterial(cloudMat)
            model.castShadows = false
        end
        totalBlobs = totalBlobs + blobCount
    end

    print("[Clouds] Generated " .. CLOUD_COUNT .. " clouds (" .. totalBlobs .. " sphere blobs)")
end

-- ============================================================================
-- 装饰物
-- ============================================================================

--- 根据关卡配置生成装饰物
function Environment.CreateDecorations()
    local scene = GS.scene
    local sceneCfg = GS.currentLevel and GS.currentLevel.scene or nil
    local decos = sceneCfg and sceneCfg.decorations
    if not decos then return end

    for i, d in ipairs(decos) do
        local node = scene:CreateChild("Deco" .. i)
        node.position = Vector3(d.pos[1], d.pos[2], d.pos[3])
        node.scale = Vector3(d.scale[1], d.scale[2], d.scale[3])

        if d.rotation then
            node.rotation = Quaternion(d.rotation[1], d.rotation[2], d.rotation[3])
        end

        local modelPath = "Models/" .. d.model .. ".mdl"
        local sm = node:CreateComponent("StaticModel")
        sm:SetModel(cache:GetResource("Model", modelPath))
        sm.castShadows = true

        local c = d.color or { 0.5, 0.5, 0.5 }
        local emissive = d.emissive and Color(d.emissive[1], d.emissive[2], d.emissive[3]) or nil
        local mat = SceneBuilder.CreatePBRMat(
            Color(c[1], c[2], c[3], 1.0),
            d.metallic or 0.0,
            d.roughness or 0.5,
            emissive
        )
        sm:SetMaterial(mat)
    end

    print(string.format("[Scene] Created %d decorations", #decos))
end

-- ============================================================================
-- 屏障
-- ============================================================================

--- 创建单个屏障面
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param getDistFunc function
local function CreateBarrierPanel(name, pos, scale, getDistFunc)
    local scene = GS.scene
    local node = scene:CreateChild(name)
    node.position = pos
    node.scale = scale

    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 1.0, 0.4, 0.0)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0, 0, 0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false

    local body = node:CreateComponent("RigidBody")
    body.collisionLayer = CollisionLayerStatic
    body.collisionMask = CollisionMaskStatic
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3.ONE)

    table.insert(GS.barriers, {
        node = node,
        mat = mat,
        getDistance = getDistFunc,
    })
end

--- 创建场地屏障（透明墙壁 + 天花板）
function Environment.CreateBarriers()
    GS.barriers = {}
    local half = CONFIG.GroundSize / 2
    local wallH = GS.BARRIER_SKY_HEIGHT
    local wallThick = 2

    -- 北墙 (Z = +half)
    CreateBarrierPanel("Barrier_N",
        Vector3(0, wallH / 2, half + wallThick / 2),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallH, wallThick),
        function(p) return half - p.z end)

    -- 南墙 (Z = -half)
    CreateBarrierPanel("Barrier_S",
        Vector3(0, wallH / 2, -half - wallThick / 2),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallH, wallThick),
        function(p) return p.z + half end)

    -- 东墙 (X = +half)
    CreateBarrierPanel("Barrier_E",
        Vector3(half + wallThick / 2, wallH / 2, 0),
        Vector3(wallThick, wallH, CONFIG.GroundSize + wallThick * 2),
        function(p) return half - p.x end)

    -- 西墙 (X = -half)
    CreateBarrierPanel("Barrier_W",
        Vector3(-half - wallThick / 2, wallH / 2, 0),
        Vector3(wallThick, wallH, CONFIG.GroundSize + wallThick * 2),
        function(p) return p.x + half end)

    -- 天花板 (Y = wallH)
    CreateBarrierPanel("Barrier_Sky",
        Vector3(0, wallH + wallThick / 2, 0),
        Vector3(CONFIG.GroundSize + wallThick * 2, wallThick, CONFIG.GroundSize + wallThick * 2),
        function(p) return wallH - p.y end)

    print(string.format("[Game] Created %d barriers (half=%.0f, height=%.0f)", #GS.barriers, half, wallH))
end

-- ============================================================================
-- 屏障透明度更新（每帧调用）
-- ============================================================================

--- 根据玩家距离更新屏障透明度
---@param playerPos Vector3
---@param dt number
function Environment.UpdateBarriers(playerPos, dt)
    for _, barrier in ipairs(GS.barriers) do
        local dist = barrier.getDistance(playerPos)
        local alpha = 0
        if dist < GS.BARRIER_FADE_DIST then
            alpha = (1.0 - dist / GS.BARRIER_FADE_DIST) * 0.6
        end
        barrier.mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 1.0, 0.4, alpha)))
        if alpha > 0.01 then
            local emStr = alpha * 2.0
            barrier.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.1 * emStr, 0.8 * emStr, 0.2 * emStr)))
        else
            barrier.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0, 0, 0)))
        end
    end
end

return Environment
