-- ============================================================================
-- Scene.lua - 场景创建 (CS Iceworld - 使用引擎物理系统)
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"

local M = {}

local CONFIG = Config.CONFIG

-- 贴图缓存
local textures = {}

--- 加载贴图资源
local function LoadTextures()
    textures.floor = cache:GetResource("Texture2D", "水泥地面_20260130084402.png")
    if textures.floor then
        textures.floor:SetFilterMode(FILTER_TRILINEAR)
    end
    
    textures.wall = cache:GetResource("Texture2D", "水泥墙壁_20260130084425.png")
    if textures.wall then
        textures.wall:SetFilterMode(FILTER_TRILINEAR)
    end
    
    textures.crate = cache:GetResource("Texture2D", "木箱_20260115020533.png")
    if textures.crate then
        textures.crate:SetFilterMode(FILTER_TRILINEAR)
    end
end

--- 创建带贴图的材质
local function CreateTexturedMaterial(texture, tileU, tileV)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/Diff.xml"))
    if texture then
        mat:SetTexture(TU_DIFFUSE, texture)
    end
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    return mat
end

--- 创建 PBR 纯色材质
local function CreatePBRMaterial(color, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.5))
    return mat
end

--- 为节点添加静态物理碰撞体（Box）
---@param node Node 节点
---@param size Vector3 碰撞体尺寸（实际就是 node.scale）
local function AddStaticBoxCollider(node, size)
    -- 静态刚体 (mass = 0)
    local body = node:CreateComponent("RigidBody")
    body.mass = 0
    body.friction = 0.0  -- 无摩擦力（冰面效果）
    body.restitution = 0.0
    body.collisionLayer = GameState.COLLISION_LAYER.ENVIRONMENT  -- 环境碰撞层
    body.collisionMask = 0xFFFFFFFF  -- 与所有层碰撞
    
    -- 碰撞形状
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3(1,1,1))
    
    -- 注册到 GameState.colliders（用于子弹射线检测，保留兼容）
    local pos = node.position
    local halfSize = Vector3(size.x / 2, size.y / 2, size.z / 2)
    table.insert(GameState.colliders, {
        min = Vector3(pos.x - halfSize.x, pos.y - halfSize.y, pos.z - halfSize.z),
        max = Vector3(pos.x + halfSize.x, pos.y + halfSize.y, pos.z + halfSize.z),
        type = "static"
    })
end

--- 创建场景
function M.Create()
    GameState.scene = Scene()
    
    -- 清空碰撞体列表（用于子弹射线检测）
    GameState.colliders = {}
    
    -- 创建八叉树（用于空间查询）
    GameState.scene:CreateComponent("Octree")
    
    -- 创建物理世界
    GameState.physicsWorld = GameState.scene:CreateComponent("PhysicsWorld")
    GameState.physicsWorld.gravity = Vector3(0, CONFIG.Gravity, 0)
    
    -- 创建调试渲染器
    GameState.debugRenderer = GameState.scene:CreateComponent("DebugRenderer")
    
    -- 加载贴图
    LoadTextures()
    
    -- 加载光照预设
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = GameState.scene:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())
    
    -- 创建天空盒
    M.CreateSkybox()
    
    -- 创建地面
    M.CreateIceworldFloor()
    
    -- 创建中央掩体
    M.CreateCenterCover()
    
    -- 创建边界墙壁
    M.CreateWalls()
    
    -- 创建角落木箱
    M.CreateCornerCrates()
    
    print("CS Iceworld scene created with engine physics")
end

--- 创建天空盒
function M.CreateSkybox()
    local skyNode = GameState.scene:CreateChild("Sky")
    skyNode.scale = Vector3(300, 300, 300)
    
    local model = skyNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.55, 0.7, 0.9, 1.0)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.5, 0.6, 0.8, 1.0)))
    mat.cullMode = CULL_CW
    model:SetMaterial(mat)
end

--- 创建 Iceworld 地面布局
function M.CreateIceworldFloor()
    local halfSize = CONFIG.ArenaSize / 2
    local platformHeight = 1.5
    local floorThickness = 0.5
    
    -- 水泥地面材质
    local floorMat
    if textures.floor then
        floorMat = CreateTexturedMaterial(textures.floor, 8, 8)
    else
        floorMat = CreatePBRMaterial(Color(0.5, 0.5, 0.5, 1.0), 0.0, 0.85)
    end
    
    -- 主地面
    local floorNode = GameState.scene:CreateChild("MainFloor")
    floorNode.position = Vector3(0, -floorThickness / 2, 0)
    floorNode.scale = Vector3(CONFIG.ArenaSize, floorThickness, CONFIG.ArenaSize)
    
    local model = floorNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(floorMat)
    model.castShadows = true
    
    -- 地面物理碰撞
    AddStaticBoxCollider(floorNode, Vector3(CONFIG.ArenaSize, floorThickness, CONFIG.ArenaSize))
    


    -- 四个角落凸起平台
    local cornerSize = 8
    local cornerOffset = halfSize - cornerSize / 2
    
    local platformMat
    if textures.wall then
        platformMat = CreateTexturedMaterial(textures.wall, 2, 2)
    else
        platformMat = CreatePBRMaterial(Color(0.5, 0.5, 0.5, 1.0), 0.0, 0.85)
    end
end

--- 创建中央围栏区域（4个围栏，每个中间放一个白色靶子）
function M.CreateCenterCover()
    local fenceHeight = 2.0    -- 围栏高度
    local fenceThickness = 0.2 -- 围栏厚度
    local fenceSize = 12.0     -- 围栏内部尺寸（正方形边长）
    local fenceSpacing = 12.0  -- 围栏之间的间距
    
    -- 半透明玻璃材质
    local fenceMat = Material:new()
    fenceMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    fenceMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.85, 0.9, 0.3)))  -- 淡蓝色，30%不透明
    fenceMat:SetShaderParameter("Metallic", Variant(0.1))
    fenceMat:SetShaderParameter("Roughness", Variant(0.05))  -- 非常光滑
    
    -- 4个围栏的中心位置（Y=-1 让靶子低1米）
    local fenceCenters = {
        Vector3(fenceSpacing, -1, fenceSpacing),
        Vector3(fenceSpacing, -1, -fenceSpacing),
        Vector3(-fenceSpacing, -1, fenceSpacing),
        Vector3(-fenceSpacing, -1, -fenceSpacing),
    }
    
    -- 记录围栏中心位置，用于生成白色靶子
    M.fenceCenters = fenceCenters
    
    for i, center in ipairs(fenceCenters) do
        local halfSize = fenceSize / 2
        local halfThick = fenceThickness / 2
        
        -- 围栏的4面墙
        local walls = {
            -- 前墙 (Z+)
            { 
                pos = Vector3(center.x, fenceHeight/2, center.z + halfSize + halfThick), 
                scale = Vector3(fenceSize + fenceThickness * 2, fenceHeight, fenceThickness) 
            },
            -- 后墙 (Z-)
            { 
                pos = Vector3(center.x, fenceHeight/2, center.z - halfSize - halfThick), 
                scale = Vector3(fenceSize + fenceThickness * 2, fenceHeight, fenceThickness) 
            },
            -- 左墙 (X-)
            { 
                pos = Vector3(center.x - halfSize - halfThick, fenceHeight/2, center.z), 
                scale = Vector3(fenceThickness, fenceHeight, fenceSize) 
            },
            -- 右墙 (X+)
            { 
                pos = Vector3(center.x + halfSize + halfThick, fenceHeight/2, center.z), 
                scale = Vector3(fenceThickness, fenceHeight, fenceSize) 
            },
        }
        
        for j, wall in ipairs(walls) do
            local wallNode = GameState.scene:CreateChild("Fence" .. i .. "_Wall" .. j)
            wallNode.position = wall.pos
            wallNode.scale = wall.scale
            
            local model = wallNode:CreateComponent("StaticModel")
            model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            model:SetMaterial(fenceMat)
            model.castShadows = true
            
            AddStaticBoxCollider(wallNode, wall.scale)
        end
    end
end

--- 创建墙壁
function M.CreateWalls()
    local wallHeight = 6
    local wallThickness = 1.0
    local halfSize = CONFIG.ArenaSize / 2
    
    -- 使用水泥墙贴图
    local wallMat
    if textures.wall then
        wallMat = CreateTexturedMaterial(textures.wall, 6, 2)
    else
        wallMat = CreatePBRMaterial(Color(0.5, 0.5, 0.5, 1.0), 0.0, 0.85)
    end
    
    local walls = {
        { pos = Vector3(0, wallHeight/2, halfSize + wallThickness/2), scale = Vector3(CONFIG.ArenaSize + wallThickness * 2, wallHeight, wallThickness) },
        { pos = Vector3(0, wallHeight/2, -halfSize - wallThickness/2), scale = Vector3(CONFIG.ArenaSize + wallThickness * 2, wallHeight, wallThickness) },
        { pos = Vector3(-halfSize - wallThickness/2, wallHeight/2, 0), scale = Vector3(wallThickness, wallHeight, CONFIG.ArenaSize) },
        { pos = Vector3(halfSize + wallThickness/2, wallHeight/2, 0), scale = Vector3(wallThickness, wallHeight, CONFIG.ArenaSize) },
    }
    
    for i, wall in ipairs(walls) do
        local wallNode = GameState.scene:CreateChild("SnowWall" .. i)
        wallNode.position = wall.pos
        wallNode.scale = wall.scale
        
        local model = wallNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(wallMat)
        model.castShadows = true
        
        AddStaticBoxCollider(wallNode, wall.scale)
    end
end

--- 创建角落木箱
function M.CreateCornerCrates()
    do return end
    local crateSize = 1.2
    local platformHeight = 1.5
    local halfSize = CONFIG.ArenaSize / 2
    local cornerOffset = halfSize - 4
    
    local crateMat
    if textures.crate then
        crateMat = CreateTexturedMaterial(textures.crate, 1, 1)
    else
        crateMat = CreatePBRMaterial(Color(0.45, 0.32, 0.2, 1.0), 0.0, 0.7)
    end
    
    local cratePositions = {
        Vector3(-cornerOffset, platformHeight + crateSize * 0.75, -cornerOffset),
        Vector3(cornerOffset, platformHeight + crateSize * 0.75, -cornerOffset),
        Vector3(-cornerOffset, platformHeight + crateSize * 0.75, cornerOffset),
        Vector3(cornerOffset, platformHeight + crateSize * 0.75, cornerOffset),
    }
    
    for i, pos in ipairs(cratePositions) do
        local crateNode = GameState.scene:CreateChild("Crate" .. i)
        crateNode.position = pos
        crateNode.scale = Vector3(crateSize, crateSize * 1.5, crateSize)
        
        local model = crateNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(crateMat)
        model.castShadows = true
        
        AddStaticBoxCollider(crateNode, Vector3(crateSize, crateSize * 1.5, crateSize))
    end
end

return M
