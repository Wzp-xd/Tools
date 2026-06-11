-- ============================================================================
-- scene_builder.lua — 场景创建 + 材质工具
-- 从 main.lua L277-338 + L805-899 提取
-- ============================================================================

local CONFIG = require "config"
local GS = require "game_state"

local SceneBuilder = {}

-- ============================================================================
-- 材质辅助函数
-- ============================================================================

--- 创建 PBR 材质
---@param color Color
---@param metallic number
---@param roughness number
---@param emissive Color|nil
---@return Material
function SceneBuilder.CreatePBRMat(color, metallic, roughness, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    if emissive then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    return mat
end

--- 创建方块部件（无碰撞）
---@param parent Node
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param mat Material
---@return Node
function SceneBuilder.CreateBoxPart(parent, name, pos, scale, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    return node
end

--- 创建带碰撞的静态方块
---@param scene Scene
---@param name string
---@param pos Vector3
---@param scale Vector3
---@param mat Material
---@return Node
function SceneBuilder.CreateStaticBox(scene, name, pos, scale, mat)
    local node = scene:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = true
    local body = node:CreateComponent("RigidBody")
    body.collisionLayer = CollisionLayerStatic
    body.collisionMask = CollisionMaskStatic
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3.ONE)
    return node
end

-- ============================================================================
-- 场景创建
-- ============================================================================

--- 创建基础场景（物理世界、灯光、相机、地面）
function SceneBuilder.CreateScene()
    local scene = Scene:new()
    scene:CreateComponent("Octree")
    scene:CreateComponent("PhysicsWorld")
    scene:CreateComponent("DebugRenderer")

    -- 第三人称相机
    local tpCam = ThirdPersonCamera.Create(scene, {
        modes = {
            normal = {
                distance = CONFIG.CameraDistance,
                offset = CONFIG.CameraOffset,
                fov = CONFIG.CameraFov,
            },
        },
        farClip = CONFIG.CameraFarClip,
    })
    renderer:SetViewport(0, Viewport:new(scene, tpCam:GetCamera()))

    -- 光照（根据关卡配置选择 LightGroup）
    local sceneCfg = GS.currentLevel and GS.currentLevel.scene or nil
    local lgPath = (sceneCfg and sceneCfg.lightGroup) or "LightGroup/Daytime.xml"
    local lightGroupFile = cache:GetResource("XMLFile", lgPath)
    if lightGroupFile then
        local lgNode = scene:CreateChild("LightGroup")
        lgNode:LoadXML(lightGroupFile:GetRoot())
        -- 覆盖雾效
        if sceneCfg and sceneCfg.fog then
            local zone = lgNode:GetComponent("Zone")
            if not zone then
                zone = lgNode:GetChild("Zone", true)
                if zone then zone = zone:GetComponent("Zone") end
            end
            if zone then
                local fc = sceneCfg.fog.color
                zone.fogColor = Color(fc[1], fc[2], fc[3])
                zone.fogStart = sceneCfg.fog.start or 150.0
                zone.fogEnd = sceneCfg.fog.fogEnd or 400.0
            end
        end
        -- 降低光照亮度
        local lMult = (sceneCfg and sceneCfg.lightMult) or 0.4
        local zone = lgNode:GetComponent("Zone")
        if not zone then
            local zChild = lgNode:GetChild("Zone", true)
            if zChild then zone = zChild:GetComponent("Zone") end
        end
        if zone then
            local ac = zone.ambientColor
            zone.ambientColor = Color(ac.r * lMult, ac.g * lMult, ac.b * lMult)
        end
        -- 降低方向光亮度
        local dirLightNode = lgNode:GetChild("DirectionalLight", true)
            or lgNode:GetChild("Light", true)
            or lgNode:GetChild("Sun", true)
        if dirLightNode then
            local dl = dirLightNode:GetComponent("Light")
            if dl then
                dl.brightness = (dl.brightness or 1.0) * lMult
            end
        end
    else
        local zoneNode = scene:CreateChild("Zone")
        local zone = zoneNode:CreateComponent("Zone")
        zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
        zone.ambientColor = Color(0.1, 0.1, 0.14)
        zone.fogColor = Color(0.15, 0.17, 0.22)
        zone.fogStart = 150.0
        zone.fogEnd = 400.0
        local lightNode = scene:CreateChild("DirectionalLight")
        lightNode.direction = Vector3(0.6, -1.0, 0.8)
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_DIRECTIONAL
        light.color = Color(0.35, 0.33, 0.3)
        light.castShadows = true
        light.shadowBias = BiasParameters(0.00025, 0.5)
        light.shadowCascade = CascadeParameters(10.0, 50.0, 200.0, 0.0, 0.8)
    end

    -- 地面
    local gc = (sceneCfg and sceneCfg.groundColor) or { 0.12, 0.12, 0.14 }
    local gMetal = (sceneCfg and sceneCfg.groundMetallic) or 0.0
    local gRough = (sceneCfg and sceneCfg.groundRoughness) or 0.85
    local groundMat = SceneBuilder.CreatePBRMat(Color(gc[1], gc[2], gc[3], 1.0), gMetal, gRough)
    SceneBuilder.CreateStaticBox(scene, "Ground", Vector3(0, -0.5, 0), Vector3(CONFIG.GroundSize, 1, CONFIG.GroundSize), groundMat)

    -- 写入 GS
    GS.scene = scene
    GS.tpCamera = tpCam

    return scene, tpCam
end

return SceneBuilder
