-- ============================================================================
-- 调试模式 - 模型查看器 & 动画预览
-- ============================================================================
-- 功能:
--   - 选择不同 3D 模型查看
--   - 选择并播放动画，查看效果
--   - 自由旋转相机围绕模型
--   - 返回主菜单
-- ============================================================================

local UI = require("urhox-libs/UI")
local CONFIG = require "config"
local MechBuilder = require "mech_builder"
local MechAnimator = require "mech_animator"
local WeaponVisuals = require "weapon_visuals"
local WeaponDefs = require "weapon_defs"
local SoundConfig = require "sound_config"
local SoundManager = require "sound_manager"

local DebugViewer = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Camera
local camera_ = nil
---@type Node
local modelRootNode_ = nil
---@type Node
local currentModelNode_ = nil
---@type AnimatedModel
local animatedModel_ = nil
---@type AnimationController
local animCtrl_ = nil

-- 程序化机甲
local mechJoints_ = nil
local mechAnimator_ = nil
local isProcedural_ = false

-- 武器预览
local isWeaponPreview_ = false
local weaponNodes_ = {}          -- { type = string, node = Node }
local selectedWeaponIdx_ = 0
local weaponDetailLabel_ = nil
local weaponDetailPanel_ = nil

-- UI
---@type Widget|nil
local uiRoot_ = nil
---@type Widget|nil
local animListPanel_ = nil
---@type Widget|nil
local modelInfoLabel_ = nil
---@type Widget|nil
local animInfoLabel_ = nil

-- 相机旋转
local camYaw_ = 0
local camPitch_ = 20
local camDistance_ = 5.0
local camTarget_ = Vector3(0, 1.0, 0)
local isDragging_ = false
local lastMouseX_ = 0
local lastMouseY_ = 0

-- 当前模型
local currentModelIndex_ = 1
local currentAnimIndex_ = 0
local currentAnimName_ = ""

-- 回调
local onBackCallback_ = nil

-- ============================================================================
-- 材质辅助函数
-- ============================================================================

local function CreatePBRMat(color, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    return mat
end

-- ============================================================================
-- 场景创建
-- ============================================================================

local function CreateDebugScene()
    scene_ = Scene:new()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 光照组
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    if lightGroupFile then
        local lgNode = scene_:CreateChild("LightGroup")
        lgNode:LoadXML(lightGroupFile:GetRoot())
    else
        local zoneNode = scene_:CreateChild("Zone")
        local zone = zoneNode:CreateComponent("Zone")
        zone.boundingBox = BoundingBox(Vector3(-100, -100, -100), Vector3(100, 100, 100))
        zone.ambientColor = Color(0.4, 0.4, 0.45)
        zone.fogColor = Color(0.3, 0.35, 0.4)
        zone.fogStart = 50.0
        zone.fogEnd = 100.0

        local lightNode = scene_:CreateChild("DirectionalLight")
        lightNode.direction = Vector3(0.5, -1.0, 0.6)
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_DIRECTIONAL
        light.color = Color(0.9, 0.88, 0.82)
        light.castShadows = true
        light.shadowBias = BiasParameters(0.00025, 0.5)
        light.shadowCascade = CascadeParameters(10.0, 50.0, 200.0, 0.0, 0.8)
    end

    -- 地板
    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.01, 0)
    floorNode.scale = Vector3(10, 0.02, 10)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(CreatePBRMat(Color(0.2, 0.2, 0.22, 1.0), 0.0, 0.85))
    floorModel.castShadows = false

    -- 网格参考线（用几个细长方块画十字线）
    local lineMat = CreatePBRMat(Color(0.35, 0.35, 0.4, 1.0), 0.0, 0.9)
    for i = -4, 4 do
        local lineX = scene_:CreateChild("GridX")
        lineX.position = Vector3(0, 0.001, i)
        lineX.scale = Vector3(10, 0.003, 0.01)
        local lxm = lineX:CreateComponent("StaticModel")
        lxm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        lxm:SetMaterial(lineMat)

        local lineZ = scene_:CreateChild("GridZ")
        lineZ.position = Vector3(i, 0.001, 0)
        lineZ.scale = Vector3(0.01, 0.003, 10)
        local lzm = lineZ:CreateComponent("StaticModel")
        lzm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        lzm:SetMaterial(lineMat)
    end

    -- 相机
    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.farClip = 100.0
    camera_.fov = 45.0

    renderer:SetViewport(0, Viewport:new(scene_, camera_))

    -- 模型根节点
    modelRootNode_ = scene_:CreateChild("ModelRoot")
end

-- ============================================================================
-- 模型加载
-- ============================================================================

local function ClearCurrentModel()
    if currentModelNode_ then
        currentModelNode_:Remove()
        currentModelNode_ = nil
    end
    animatedModel_ = nil
    animCtrl_ = nil
    mechJoints_ = nil
    mechAnimator_ = nil
    isProcedural_ = false
    isWeaponPreview_ = false
    weaponNodes_ = {}
    selectedWeaponIdx_ = 0
    currentAnimIndex_ = 0
    currentAnimName_ = ""
    WeaponVisuals.ClearCache()
end

local function LoadModel(modelIndex)
    ClearCurrentModel()
    currentModelIndex_ = modelIndex

    local modelDef = CONFIG.Models[modelIndex]
    if not modelDef then
        print("[DebugViewer] Model index out of range: " .. tostring(modelIndex))
        return
    end

    print("[DebugViewer] Loading model: " .. modelDef.name)

    currentModelNode_ = modelRootNode_:CreateChild("CurrentModel")
    currentModelNode_.position = Vector3(0, modelDef.heightOffset or 0, 0)
    currentModelNode_.scale = Vector3.ONE * (modelDef.scale or 1.0)

    -- 区分程序化模型和 prefab 模型
    if modelDef.procedural == "weapons" then
        -- 武器预览模式：展示所有武器
        isWeaponPreview_ = true
        weaponNodes_ = {}

        -- 收集所有武器类型
        local allWeapons = {}
        for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
            for _, wType in ipairs(WeaponDefs.SLOTS[slot].options) do
                table.insert(allWeapons, wType)
            end
        end

        -- 排成一排展示
        local spacing = 1.8
        local totalWidth = (#allWeapons - 1) * spacing
        local startX = -totalWidth / 2

        for i, wType in ipairs(allWeapons) do
            local mountNode = currentModelNode_:CreateChild("WeaponMount_" .. wType)
            mountNode.position = Vector3(startX + (i - 1) * spacing, 0.8, 0)
            mountNode.scale = Vector3(2.5, 2.5, 2.5)  -- 放大方便观看

            local weaponNode = WeaponVisuals.Create(wType, mountNode)
            table.insert(weaponNodes_, { type = wType, node = mountNode, visual = weaponNode })

            -- 底部添加小底座
            local baseNode = mountNode:CreateChild("Base")
            baseNode.position = Vector3(0, -0.25, 0)
            baseNode.scale = Vector3(0.25, 0.02, 0.25)
            local baseModel = baseNode:CreateComponent("StaticModel")
            baseModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            baseModel:SetMaterial(CreatePBRMat(Color(0.15, 0.15, 0.2, 1.0), 0.5, 0.5))
        end

        camDistance_ = 12.0
        camTarget_ = Vector3(0, 0.8, 0)
        print("[DebugViewer] Loaded weapon gallery: " .. #allWeapons .. " weapons")

    elseif modelDef.procedural == "mech" then
        -- 程序化机甲：使用 MechBuilder 构建
        isProcedural_ = true
        local modelNode, joints = MechBuilder.Build(currentModelNode_, CONFIG.SelectedVariant)
        mechJoints_ = joints
        mechAnimator_ = MechAnimator.Create(joints)
        -- 机甲高度约 3.5m，设置合适的相机参数
        camDistance_ = 8.0
        camTarget_ = Vector3(0, 1.75, 0)
        print("[DebugViewer] Loaded procedural mech model")
    else
        -- prefab / model 加载
        isProcedural_ = false
        local prefab = modelDef.prefab
        local loaded = false

        if prefab then
            -- 先尝试作为 XML prefab 加载
            local prefabFile = cache:GetResource("XMLFile", prefab)
            if prefabFile then
                loaded = currentModelNode_:LoadXML(prefabFile:GetRoot())
                if loaded then
                    print("[DebugViewer] Loaded via prefab: " .. prefab)
                end
            end

            -- 如果 XML 加载失败，尝试作为 Model 直接加载（.mdl 文件）
            if not loaded then
                local mdlRes = cache:GetResource("Model", prefab)
                if mdlRes then
                    animatedModel_ = currentModelNode_:CreateComponent("AnimatedModel")
                    animatedModel_:SetModel(mdlRes)
                    animCtrl_ = currentModelNode_:GetOrCreateComponent("AnimationController")
                    loaded = true
                    print("[DebugViewer] Loaded as Model directly: " .. prefab)
                end
            end
        end

        if not loaded then
            print("[DebugViewer] Failed to load model: " .. modelDef.name)
            return
        end

        -- 查找 AnimatedModel 组件（可能在子节点上，prefab 加载的情况）
        if not animatedModel_ then
            animatedModel_ = currentModelNode_:GetComponent("AnimatedModel")
            if not animatedModel_ then
                local children = currentModelNode_:GetChildren(true)
                for i = 0, children:Size() - 1 do
                    local child = children:At(i)
                    local am = child:GetComponent("AnimatedModel")
                    if am then
                        animatedModel_ = am
                        animCtrl_ = child:GetOrCreateComponent("AnimationController")
                        print("[DebugViewer] Found AnimatedModel on child: " .. child.name)
                        break
                    end
                end
            else
                if not animCtrl_ then
                    animCtrl_ = currentModelNode_:GetOrCreateComponent("AnimationController")
                end
            end
        end

        if not animatedModel_ then
            print("[DebugViewer] WARNING: No AnimatedModel found on model")
        end

        -- 根据模型尺寸调整相机距离
        if animatedModel_ then
            local bb = animatedModel_.boundingBox
            local size = bb.size
            local maxDim = math.max(size.x, size.y, size.z) * (modelDef.scale or 1.0)
            camDistance_ = math.max(3.0, maxDim * 2.5)
            camTarget_ = Vector3(0, size.y * (modelDef.scale or 1.0) * 0.45, 0)
        end
    end

    print("[DebugViewer] Model loaded: " .. modelDef.name)
end

-- ============================================================================
-- 动画播放
-- ============================================================================

local function PlayAnimation(animIndex)
    local modelDef = CONFIG.Models[currentModelIndex_]
    if not modelDef then return end

    if animIndex < 1 or animIndex > #modelDef.animations then
        print("[DebugViewer] Animation index out of range: " .. tostring(animIndex))
        return
    end

    local animDef = modelDef.animations[animIndex]
    currentAnimIndex_ = animIndex
    currentAnimName_ = animDef.name

    if isProcedural_ and mechAnimator_ then
        -- 程序化动画
        local animId = animDef.id or "idle"
        mechAnimator_:Play(animId, 0.2)
        print("[DebugViewer] Playing procedural animation: " .. animDef.name .. " (" .. animId .. ")")
    elseif animCtrl_ then
        -- prefab 动画
        print("[DebugViewer] Playing animation: " .. animDef.name .. " (" .. animDef.path .. ")")
        animCtrl_:PlayExclusive(animDef.path, 0, animDef.loop, 0.2)
    else
        print("[DebugViewer] No animation system available")
        return
    end

    if animInfoLabel_ then
        animInfoLabel_.text = "动画: " .. animDef.name .. (animDef.loop and " (循环)" or " (单次)")
    end
end

local function StopAllAnimations()
    if isProcedural_ and mechAnimator_ then
        mechAnimator_:Stop()
    elseif animCtrl_ then
        animCtrl_:StopAll(0.2)
    end
    currentAnimIndex_ = 0
    currentAnimName_ = ""
    if animInfoLabel_ then
        animInfoLabel_.text = "动画: 无"
    end
end

-- ============================================================================
-- 相机控制
-- ============================================================================

local function UpdateCamera()
    if not cameraNode_ then return end

    local yawRad = math.rad(camYaw_)
    local pitchRad = math.rad(camPitch_)

    local x = camDistance_ * math.cos(pitchRad) * math.sin(yawRad)
    local y = camDistance_ * math.sin(pitchRad)
    local z = camDistance_ * math.cos(pitchRad) * math.cos(yawRad)

    cameraNode_.position = camTarget_ + Vector3(x, y, z)
    cameraNode_:LookAt(camTarget_)
end

-- ============================================================================
-- UI 创建
-- ============================================================================

--- 选中某把武器，聚焦相机并显示详情
local function SelectWeapon(idx)
    if idx < 1 or idx > #weaponNodes_ then return end
    selectedWeaponIdx_ = idx
    local entry = weaponNodes_[idx]
    local wType = entry.type
    local def = WeaponDefs.Get(wType)
    if not def then return end

    -- 聚焦相机到选中武器
    local pos = entry.node.worldPosition
    camTarget_ = pos
    camDistance_ = 3.5

    -- 更新详情标签
    if weaponDetailLabel_ then
        local slotLabel = ""
        for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
            for _, opt in ipairs(WeaponDefs.SLOTS[slot].options) do
                if opt == wType then
                    slotLabel = WeaponDefs.SLOTS[slot].label .. " [" .. WeaponDefs.SLOTS[slot].key .. "]"
                    break
                end
            end
            if slotLabel ~= "" then break end
        end

        local lines = {
            def.nameZH or def.name,
            "槽位: " .. slotLabel,
            "伤害: " .. tostring(def.damage or 0),
            "射速: " .. string.format("%.1f/s", 1.0 / (def.fireRate or 1)),
            "射程: " .. tostring(def.range or 0) .. "m",
        }
        if def.pelletCount then
            table.insert(lines, "弹丸数: " .. tostring(def.pelletCount))
        end
        if def.blastRadius then
            table.insert(lines, "爆炸半径: " .. tostring(def.blastRadius) .. "m")
        end
        if def.chargeTime then
            table.insert(lines, "蓄力: " .. tostring(def.chargeTime) .. "s")
        end
        if def.piercing then
            table.insert(lines, "穿透: 是")
        end
        if def.isShield then
            table.insert(lines, "护盾吸收: " .. tostring(def.shieldAbsorb or 0))
            table.insert(lines, "持续: " .. tostring(def.shieldDuration or 0) .. "s")
        end
        if def.description then
            table.insert(lines, "")
            table.insert(lines, def.description)
        end
        weaponDetailLabel_.text = table.concat(lines, "\n")
    end

    if animInfoLabel_ then
        animInfoLabel_.text = "武器: " .. (def.nameZH or def.name)
    end
end

local function BuildAnimationList()
    if not animListPanel_ then return end
    animListPanel_:ClearChildren()

    local modelDef = CONFIG.Models[currentModelIndex_]
    if not modelDef then return end

    if isWeaponPreview_ then
        -- 武器预览模式：显示武器选择按钮
        local currentSlot = ""
        for i, entry in ipairs(weaponNodes_) do
            local wType = entry.type
            local def = WeaponDefs.Get(wType)
            local displayName = def and (def.nameZH or def.name) or wType

            -- 按槽位分组：插入分组标题
            local slotName = ""
            for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
                for _, opt in ipairs(WeaponDefs.SLOTS[slot].options) do
                    if opt == wType then slotName = slot break end
                end
                if slotName ~= "" then break end
            end
            if slotName ~= currentSlot then
                currentSlot = slotName
                local slotDef = WeaponDefs.SLOTS[slotName]
                animListPanel_:AddChild(UI.Label {
                    text = (slotDef and slotDef.label or slotName) .. " [" .. (slotDef and slotDef.key or "?") .. "]",
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = { 100, 200, 255, 220 },
                    marginTop = 6,
                    marginBottom = 2,
                })
            end

            local idx = i
            animListPanel_:AddChild(UI.Button {
                text = displayName,
                fontSize = 11,
                height = 32,
                backgroundColor = { 45, 50, 65, 220 },
                textColor = { 200, 210, 230, 255 },
                hoverBackgroundColor = { 60, 70, 100, 240 },
                pressedBackgroundColor = { 40, 100, 200, 250 },
                borderRadius = 4,
                onClick = function(self)
                    SelectWeapon(idx)
                end,
            })
        end

        -- "全部查看"按钮 - 恢复全景
        animListPanel_:AddChild(UI.Button {
            text = "全部查看",
            fontSize = 11,
            height = 32,
            marginTop = 8,
            backgroundColor = { 50, 80, 50, 220 },
            textColor = { 180, 255, 180, 255 },
            hoverBackgroundColor = { 60, 100, 60, 240 },
            pressedBackgroundColor = { 40, 120, 40, 250 },
            borderRadius = 4,
            onClick = function(self)
                selectedWeaponIdx_ = 0
                camDistance_ = 12.0
                camTarget_ = Vector3(0, 0.8, 0)
                if weaponDetailLabel_ then weaponDetailLabel_.text = "点击左侧武器查看详情" end
                if animInfoLabel_ then animInfoLabel_.text = "武器: 全部" end
            end,
        })
    else
        -- 普通模式：显示动画列表
        for i, animDef in ipairs(modelDef.animations) do
            local idx = i
            animListPanel_:AddChild(UI.Button {
                text = animDef.name,
                fontSize = 11,
                height = 32,
                backgroundColor = { 45, 50, 65, 220 },
                textColor = { 200, 210, 230, 255 },
                hoverBackgroundColor = { 60, 70, 100, 240 },
                pressedBackgroundColor = { 40, 100, 200, 250 },
                borderRadius = 4,
                onClick = function(self)
                    PlayAnimation(idx)
                end,
            })
        end
    end
end

local function CreateDebugUI()
    -- 构建模型选择下拉的选项
    local modelOptions = {}
    for i, m in ipairs(CONFIG.Models) do
        table.insert(modelOptions, { value = i, label = m.name })
    end

    -- 动画信息标签
    animInfoLabel_ = UI.Label {
        text = "动画: 无",
        fontSize = 12,
        fontColor = { 180, 200, 255, 220 },
    }

    -- 模型信息标签
    modelInfoLabel_ = UI.Label {
        text = "模型: " .. CONFIG.Models[currentModelIndex_].name,
        fontSize = 12,
        fontColor = { 180, 200, 255, 220 },
    }

    -- 动画滚动列表
    animListPanel_ = UI.Panel {
        flexDirection = "column",
        gap = 4,
        width = "100%",
    }

    -- 左侧面板
    local leftPanel = UI.Panel {
        position = "absolute",
        top = 10,
        left = 10,
        width = 230,
        maxHeight = "90%",
        flexDirection = "column",
        gap = 8,
        padding = 12,
        backgroundColor = { 20, 25, 40, 220 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 80, 130, 150 },
        children = {
            -- 标题
            UI.Label {
                text = "调试模式",
                fontSize = 16,
                fontWeight = "bold",
                fontColor = { 100, 200, 255, 255 },
                textAlign = "center",
            },

            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },

            -- 模型选择
            UI.Label {
                text = "选择模型",
                fontSize = 12,
                fontColor = { 150, 170, 200, 200 },
            },
            UI.Dropdown {
                options = modelOptions,
                value = currentModelIndex_,
                width = "100%",
                onChange = function(self, value, option)
                    LoadModel(value)
                    BuildAnimationList()
                    if modelInfoLabel_ then
                        modelInfoLabel_.text = "模型: " .. CONFIG.Models[value].name
                    end
                    -- 武器详情面板显示/隐藏
                    if weaponDetailPanel_ then
                        weaponDetailPanel_.display = isWeaponPreview_ and "flex" or "none"
                    end
                    if not isWeaponPreview_ then
                        StopAllAnimations()
                    end
                end,
            },

            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },

            -- 信息
            modelInfoLabel_,
            animInfoLabel_,

            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },

            -- 动画列表标题
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "动画列表",
                        fontSize = 12,
                        fontColor = { 150, 170, 200, 200 },
                    },
                    UI.Button {
                        text = "停止",
                        fontSize = 10,
                        height = 24,
                        width = 50,
                        backgroundColor = { 150, 50, 50, 200 },
                        textColor = { 255, 200, 200, 255 },
                        hoverBackgroundColor = { 180, 60, 60, 220 },
                        pressedBackgroundColor = { 120, 40, 40, 240 },
                        borderRadius = 4,
                        onClick = function(self)
                            StopAllAnimations()
                        end,
                    },
                },
            },

            -- 动画按钮滚动区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                width = "100%",
                maxHeight = 400,
                children = { animListPanel_ },
            },

            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },

            -- 音效试听
            UI.Label {
                text = "音效试听",
                fontSize = 12,
                fontColor = { 150, 170, 200, 200 },
            },
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                width = "100%",
                maxHeight = 300,
                children = {
                    UI.Panel {
                        flexDirection = "column",
                        gap = 4,
                        width = "100%",
                        children = (function()
                            local items = {}

                            -- BGM 分组
                            table.insert(items, UI.Label {
                                text = "BGM",
                                fontSize = 11,
                                fontWeight = "bold",
                                fontColor = { 255, 200, 80, 220 },
                                marginTop = 2,
                                marginBottom = 2,
                            })
                            -- 收集并按 key 排序
                            local bgmKeys = {}
                            for k in pairs(SoundConfig.BGM) do
                                table.insert(bgmKeys, k)
                            end
                            table.sort(bgmKeys)
                            for _, k in ipairs(bgmKeys) do
                                local cfg = SoundConfig.BGM[k]
                                local key = k
                                table.insert(items, UI.Button {
                                    text = (cfg.name or key) .. "  [" .. key .. "]",
                                    fontSize = 11,
                                    height = 32,
                                    backgroundColor = { 55, 50, 30, 220 },
                                    textColor = { 255, 220, 160, 255 },
                                    hoverBackgroundColor = { 80, 70, 40, 240 },
                                    pressedBackgroundColor = { 120, 100, 40, 250 },
                                    borderRadius = 4,
                                    onClick = function(self)
                                        SoundManager.PlayBGM(key)
                                    end,
                                })
                            end
                            -- 停止 BGM
                            table.insert(items, UI.Button {
                                text = "停止 BGM",
                                fontSize = 10,
                                height = 26,
                                backgroundColor = { 100, 40, 40, 200 },
                                textColor = { 255, 180, 180, 255 },
                                hoverBackgroundColor = { 130, 50, 50, 220 },
                                pressedBackgroundColor = { 90, 30, 30, 240 },
                                borderRadius = 4,
                                marginBottom = 6,
                                onClick = function(self)
                                    SoundManager.StopBGM()
                                end,
                            })

                            -- SFX 分组
                            table.insert(items, UI.Label {
                                text = "SFX",
                                fontSize = 11,
                                fontWeight = "bold",
                                fontColor = { 100, 220, 160, 220 },
                                marginTop = 2,
                                marginBottom = 2,
                            })
                            local sfxKeys = {}
                            for k in pairs(SoundConfig.SFX) do
                                table.insert(sfxKeys, k)
                            end
                            table.sort(sfxKeys)
                            for _, k in ipairs(sfxKeys) do
                                local key = k
                                table.insert(items, UI.Button {
                                    text = key,
                                    fontSize = 11,
                                    height = 32,
                                    backgroundColor = { 30, 50, 45, 220 },
                                    textColor = { 180, 240, 210, 255 },
                                    hoverBackgroundColor = { 40, 70, 60, 240 },
                                    pressedBackgroundColor = { 30, 110, 80, 250 },
                                    borderRadius = 4,
                                    onClick = function(self)
                                        SoundManager.PlaySFX(key)
                                    end,
                                })
                            end

                            return items
                        end)(),
                    },
                },
            },

            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },

            -- 返回按钮
            UI.Button {
                text = "返回主菜单",
                variant = "secondary",
                width = "100%",
                height = 36,
                fontSize = 13,
                onClick = function(self)
                    DebugViewer.Exit()
                    if onBackCallback_ then
                        onBackCallback_()
                    end
                end,
            },
        },
    }

    -- 武器详情面板（右上角，仅武器预览时有内容）
    weaponDetailLabel_ = UI.Label {
        text = "点击左侧武器查看详情",
        fontSize = 12,
        fontColor = { 200, 210, 230, 230 },
        lineHeight = 1.5,
    }

    weaponDetailPanel_ = UI.Panel {
        position = "absolute",
        top = 10,
        right = 10,
        width = 220,
        flexDirection = "column",
        gap = 6,
        padding = 12,
        backgroundColor = { 20, 25, 40, 220 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 80, 130, 150 },
        display = "none",
        children = {
            UI.Label {
                text = "武器详情",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = { 255, 200, 80, 255 },
            },
            UI.Divider { color = { 60, 80, 130, 100 }, spacing = 4 },
            weaponDetailLabel_,
        },
    }

    -- 右下角操作提示
    local helpPanel = UI.Panel {
        position = "absolute",
        bottom = 10,
        right = 10,
        padding = 8,
        backgroundColor = { 15, 18, 30, 180 },
        borderRadius = 6,
        children = {
            UI.Label {
                text = "鼠标左键拖拽: 旋转 | 滚轮: 缩放",
                fontSize = 11,
                fontColor = { 140, 160, 200, 180 },
            },
        },
    }

    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = { leftPanel, weaponDetailPanel_, helpPanel },
    }

    UI.SetRoot(uiRoot_)
    BuildAnimationList()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

local function HandleDebugUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 更新程序化动画
    if isProcedural_ and mechAnimator_ then
        mechAnimator_:Update(dt)
    end

    -- 武器预览：选中武器缓慢自旋转
    if isWeaponPreview_ and selectedWeaponIdx_ > 0 then
        local entry = weaponNodes_[selectedWeaponIdx_]
        if entry and entry.node then
            entry.node:Rotate(Quaternion(30 * dt, Vector3.UP))
        end
    end

    -- 鼠标拖拽旋转相机（仅当不在 UI 上时）
    if input:GetMouseButtonDown(MOUSEB_LEFT) then
        if not isDragging_ then
            -- 检查是否在 UI 上
            if UI.IsPointerOverUI() then
                return
            end
            isDragging_ = true
            lastMouseX_ = input.mousePosition.x
            lastMouseY_ = input.mousePosition.y
        end

        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local dx = mx - lastMouseX_
        local dy = my - lastMouseY_
        lastMouseX_ = mx
        lastMouseY_ = my

        camYaw_ = camYaw_ + dx * 0.3
        camPitch_ = Clamp(camPitch_ + dy * 0.3, -85, 85)
    else
        isDragging_ = false
    end

    -- 滚轮缩放
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and not UI.IsPointerOverUI() then
        camDistance_ = Clamp(camDistance_ - wheel * 0.15, 1.0, 20.0)
    end

    UpdateCamera()
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 进入调试模式
---@param onBack function 返回主菜单的回调
function DebugViewer.Enter(onBack)
    onBackCallback_ = onBack

    -- 设为普通鼠标
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    CreateDebugScene()
    CreateDebugUI()
    LoadModel(1)

    camYaw_ = 30
    camPitch_ = 15
    UpdateCamera()

    SubscribeToEvent("Update", HandleDebugUpdate)
    print("[DebugViewer] Debug mode entered")
end

--- 退出调试模式
function DebugViewer.Exit()
    UnsubscribeFromEvent("Update")
    ClearCurrentModel()

    if uiRoot_ then
        uiRoot_:Destroy()
        uiRoot_ = nil
    end
    animListPanel_ = nil
    modelInfoLabel_ = nil
    animInfoLabel_ = nil
    weaponDetailLabel_ = nil
    weaponDetailPanel_ = nil

    if scene_ then
        scene_:Remove()
        scene_ = nil
    end
    cameraNode_ = nil
    camera_ = nil
    modelRootNode_ = nil
    isDragging_ = false

    print("[DebugViewer] Debug mode exited")
end

return DebugViewer
