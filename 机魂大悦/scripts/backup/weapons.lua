-- ============================================================================
-- 武器系统 - 机关枪 & 飞弹
-- Weapon System - Machine Gun & Missile
-- ============================================================================
--
-- 武器槽位:
--   handL     - 左手 (鼠标左键)
--   handR     - 右手 (鼠标右键)
--   shoulderL - 左肩 (Q键)
--   shoulderR - 右肩 (E键)
--
-- 武器类型:
--   machinegun - 机关枪: 高射速、无追踪、直线弹道
--   rpg        - RPG:    直线弹道、撞击爆炸、范围伤害
--   missile    - 飞弹:   低射速、锁定后追踪、未锁定直线飞行
-- ============================================================================

local WeaponDefs = require "weapon_defs"
local WeaponVisuals = require "weapon_visuals"

local Weapons = {}

-- 武器定义引用（从 weapon_defs.lua 加载）
Weapons.DEFS = WeaponDefs.DEFS

-- 音效回调（由外部注册）
---@type fun(weaponKey: string, position: Vector3)|nil
local onFireCallback_ = nil
---@type fun(weaponKey: string, position: Vector3)|nil
local onExplosionCallback_ = nil
---@type fun(weaponKey: string, position: Vector3)|nil
local onHitCallback_ = nil

--- 注册开火音效回调
function Weapons.SetOnFireCallback(callback)
    onFireCallback_ = callback
end

--- 注册爆炸音效回调
function Weapons.SetOnExplosionCallback(callback)
    onExplosionCallback_ = callback
end

--- 注册命中回调（用于武器特殊命中特效）
function Weapons.SetOnHitCallback(callback)
    onHitCallback_ = callback
end

-- ============================================================================
-- 武器实例
-- ============================================================================

--- 创建武器实例
---@param weaponType string "machinegun" 或 "missile"
---@param mountNode Node 挂载点节点
---@param owner string|nil "player"(默认) 或 "enemy"
---@return table weapon
function Weapons.CreateWeapon(weaponType, mountNode, owner)
    local def = Weapons.DEFS[weaponType]
    if not def then
        print("[Weapons] Unknown weapon type: " .. tostring(weaponType))
        return nil
    end

    -- 创建武器 3D 外观模型
    local weaponNode = WeaponVisuals.Create(weaponType, mountNode)
    if not weaponNode then
        -- 未知武器类型，回退到简易方块
        weaponNode = mountNode:CreateChild("Weapon_" .. weaponType)
        weaponNode.scale = Vector3(0.1, 0.1, 0.4)
        weaponNode.position = Vector3(0, 0, 0.2)
        local model = weaponNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.15, 0.18, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(0.9))
        mat:SetShaderParameter("Roughness", Variant(0.25))
        model:SetMaterial(mat)
        model.castShadows = true
    end

    local magazineSize = def.magazineSize or 999

    return {
        type = weaponType,
        def = def,
        mountNode = mountNode,
        weaponNode = weaponNode,
        lastFireTime = -999,
        muzzleFlashTimer = 0,
        -- 连发状态
        burstRemaining = 0,
        burstNextTime = 0,
        burstParams = nil,      -- { scene, targetPos, targetLocked, targetNode, launchYawOffset }
        -- 弹匣状态
        ammo = magazineSize,        -- 当前弹药数
        magazineSize = magazineSize, -- 弹匣容量
        reloading = false,          -- 是否正在换弹
        reloadTimer = 0,            -- 换弹剩余时间
        reloadTime = def.reloadTime or 2.0,  -- 换弹总时长
        owner = owner or "player",              -- 弹丸所有者
    }
end

-- ============================================================================
-- 弹药管理
-- ============================================================================

---@type table[] 活跃弹药列表
local projectiles_ = {}

---@type table[] 活跃爆炸效果列表
local explosions_ = {}

---@type table[] 敌人列表引用（由外部设置）
local enemies_ = {}

--- 设置敌人列表引用（在 main.lua 中调用）
---@param enemies table[]
function Weapons.SetEnemies(enemies)
    enemies_ = enemies
end

---@type table|nil 玩家信息 { node, getHP, setHP }
local playerInfo_ = nil

--- 设置玩家信息（用于敌方弹丸命中检测）
---@param info table { node: Node, getHP: function, setHP: function }
function Weapons.SetPlayerInfo(info)
    playerInfo_ = info
end

--- 对玩家造成直接伤害（近战攻击、环境伤害等）
---@param damage number 伤害值
function Weapons.DamagePlayer(damage)
    if not playerInfo_ then return end
    local dmg = damage
    -- 喷射状态下伤害减半
    if playerInfo_.isJetting and playerInfo_.isJetting() then
        dmg = dmg * 0.5
    end
    local curHP = playerInfo_.getHP()
    playerInfo_.setHP(math.max(0, curHP - dmg))
end

--- 命中半径配置
local HIT_RADIUS = {
    machinegun = 1.2,   -- 机关枪命中半径
    shotgun = 1.0,      -- 霰弹枪命中半径（单颗弹丸更小）
    pistol = 1.0,       -- 手枪命中半径
    rpg = 2.0,          -- RPG 命中半径
    shield = 1.0,       -- 能量盾（不射弹，占位）
    homing_handgun = 1.5, -- 追踪手枪命中半径
    missile = 2.5,      -- 飞弹命中半径（爆炸范围更大）
    vertical_missile = 2.5, -- 垂直飞弹命中半径
    shoulder_rpg = 2.5, -- 肩扛火箭命中半径
    railgun = 1.0,      -- 电磁炮命中半径（穿透细针）
}

--- RPG 范围伤害（距离线性衰减）
---@param pos Vector3 爆炸中心
---@param blastRadius number 爆炸半径
---@param blastDamage number 最大范围伤害
---@param directHitEnemy table|nil 直接命中的敌人（跳过）
---@param owner string|nil 弹丸所有者
local function ApplyBlastDamage(pos, blastRadius, blastDamage, directHitEnemy, owner)
    -- 玩家弹丸：伤害敌人
    if owner ~= "enemy" then
        for _, enemy in ipairs(enemies_) do
            if enemy == directHitEnemy then goto continue end
            local enemyCenter = enemy.node.worldPosition + Vector3(0, 1.7, 0)
            local diff = enemyCenter - pos
            local dist = diff:Length()
            if dist < blastRadius and enemy.hp then
                enemy.hp = math.max(0, enemy.hp - blastDamage)
                print(string.format("[RPG] Blast hit enemy at dist=%.1f dmg=%.0f hp=%d/%d", dist, blastDamage, enemy.hp, enemy.maxHp or 100))
            end
            ::continue::
        end
    end
    -- 敌方弹丸：伤害玩家
    if owner == "enemy" and playerInfo_ and playerInfo_.node then
        local playerCenter = playerInfo_.node.worldPosition + Vector3(0, 1.7, 0)
        local dist = (playerCenter - pos):Length()
        if dist < blastRadius then
            local finalDmg = blastDamage
            -- 喷射状态下伤害减半
            if playerInfo_.isJetting and playerInfo_.isJetting() then
                finalDmg = finalDmg * 0.5
            end
            local curHP = playerInfo_.getHP()
            playerInfo_.setHP(math.max(0, curHP - finalDmg))
            print(string.format("[Blast] Hit player at dist=%.1f dmg=%.0f", dist, finalDmg))
        end
    end
end

-- 前向声明（定义在后面，但 CreateExplosion 需要引用）
local CreateExplosionLight

--- 创建爆炸效果
---@param scene Scene
---@param pos Vector3
---@param size number 爆炸大小倍率
---@param color Color 爆炸颜色
local function CreateExplosion(scene, pos, size, color)
    local node = scene:CreateChild("Explosion")
    node.position = pos

    -- 爆炸球体
    local scale = size * 0.5
    node.scale = Vector3(scale, scale, scale)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.8)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(color.r * 5, color.g * 5, color.b * 3)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    model:SetMaterial(mat)
    model.castShadows = false

    table.insert(explosions_, {
        node = node,
        model = model,
        mat = mat,
        life = 0.35,       -- 爆炸持续时间
        age = 0,
        maxScale = size,    -- 最终膨胀大小
        initScale = scale,
        color = color,
    })

    -- 爆炸闪光点光源
    CreateExplosionLight(scene, pos, size)
end

--- 创建子弹材质
---@param color Color
---@param emissive Color
---@return Material
local function CreateBulletMat(color, emissive)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.1))
    mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    return mat
end

--- 创建拖尾材质（无光照加法混合）
---@param color Color 拖尾颜色
---@return Material
local function CreateTrailMat(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAdd.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    return mat
end

--- 创建烟雾粒子材质（无光照透明）
---@return Material
local function CreateSmokeMat()
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    return mat
end

---@type table[] 待清理的残留拖尾/粒子节点 { node, lifetime, age }
local trailCleanup_ = {}

-- ============================================================================
-- 枪口闪光 & 发射特效系统
-- ============================================================================

---@type table[] 活跃的枪口闪光/发射特效 { node, age, life, type, ... }
local muzzleFX_ = {}

--- 枪口闪光颜色配置（按武器类别）
local MUZZLE_COLORS = {
    rapid     = { flash = Color(1.0, 0.9, 0.3, 0.9), emit = Color(6.0, 4.0, 0.8),  light = Color(1.0, 0.85, 0.4) },
    burst     = { flash = Color(1.0, 0.7, 0.2, 0.9), emit = Color(8.0, 5.0, 1.0),  light = Color(1.0, 0.7, 0.3) },
    precision = { flash = Color(0.8, 0.9, 1.0, 0.9), emit = Color(3.0, 4.0, 6.0),  light = Color(0.7, 0.85, 1.0) },
    explosive = { flash = Color(1.0, 0.6, 0.2, 0.9), emit = Color(8.0, 4.0, 1.0),  light = Color(1.0, 0.6, 0.2) },
    tracking  = { flash = Color(0.3, 0.7, 1.0, 0.9), emit = Color(1.5, 3.5, 6.0),  light = Color(0.4, 0.7, 1.0) },
}

--- 创建枪口闪光特效（发光球 + 点光源）
---@param scene Scene
---@param pos Vector3 枪口世界坐标
---@param fwd Vector3 射击方向
---@param category string 武器类别
---@param intensity number 强度倍率（1.0=普通，2.0=强力）
local function CreateMuzzleFlashFX(scene, pos, fwd, category, intensity)
    local colors = MUZZLE_COLORS[category] or MUZZLE_COLORS.rapid
    local flashSize = 0.3 * intensity

    -- 发光球
    local flashNode = scene:CreateChild("MuzzleFlash")
    flashNode.position = pos + fwd * 0.3
    flashNode.scale = Vector3(flashSize, flashSize, flashSize)
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(colors.flash))
    mat:SetShaderParameter("MatEmissiveColor", Variant(colors.emit))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.0))
    model:SetMaterial(mat)
    model.castShadows = false
    table.insert(muzzleFX_, {
        node = flashNode, mat = mat, age = 0, life = 0.08 * intensity,
        type = "flash", maxScale = flashSize * 2.0, colors = colors, intensity = intensity,
    })

    -- 点光源
    local lightNode = scene:CreateChild("MuzzleLight")
    lightNode.position = pos + fwd * 0.5
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = colors.light
    lt.range = 6.0 * intensity
    lt.brightness = 3.0 * intensity
    lt.castShadows = false
    table.insert(muzzleFX_, {
        node = lightNode, age = 0, life = 0.1 * intensity,
        type = "light", light = lt, intensity = intensity,
    })
end

--- 创建霰弹枪散射闪光（更大更亮的多向闪光）
---@param scene Scene
---@param pos Vector3
---@param fwd Vector3
local function CreateShotgunFlashFX(scene, pos, fwd)
    local colors = MUZZLE_COLORS.burst

    -- 主闪光球（比普通的更大）
    local flashNode = scene:CreateChild("ShotgunFlash")
    flashNode.position = pos + fwd * 0.2
    flashNode.scale = Vector3(0.6, 0.6, 0.6)
    local model = flashNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.3, 0.9)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(12.0, 8.0, 2.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.0))
    model:SetMaterial(mat)
    model.castShadows = false
    table.insert(muzzleFX_, {
        node = flashNode, mat = mat, age = 0, life = 0.12,
        type = "flash", maxScale = 1.2, colors = colors, intensity = 2.0,
    })

    -- 锥形扩散环（模拟散射方向）
    local ringNode = scene:CreateChild("ShotgunRing")
    ringNode.position = pos + fwd * 0.8
    ringNode.rotation = Quaternion(Vector3.UP, fwd)
    ringNode.scale = Vector3(0.2, 0.01, 0.2)
    local rModel = ringNode:CreateComponent("StaticModel")
    rModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local rMat = Material:new()
    rMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.7, 0.2, 0.5)))
    rMat:SetShaderParameter("MatEmissiveColor", Variant(Color(6.0, 3.0, 0.5)))
    rMat:SetShaderParameter("Metallic", Variant(0.0))
    rMat:SetShaderParameter("Roughness", Variant(0.0))
    rModel:SetMaterial(rMat)
    rModel.castShadows = false
    table.insert(muzzleFX_, {
        node = ringNode, mat = rMat, age = 0, life = 0.15,
        type = "ring", maxScale = 1.5,
    })

    -- 强光
    local lightNode = scene:CreateChild("ShotgunLight")
    lightNode.position = pos + fwd * 0.5
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = colors.light
    lt.range = 10.0
    lt.brightness = 6.0
    lt.castShadows = false
    table.insert(muzzleFX_, {
        node = lightNode, age = 0, life = 0.12,
        type = "light", light = lt, intensity = 2.0,
    })
end

--- 创建飞弹发射烟雾（短暂尾焰 + 烟雾球）
---@param scene Scene
---@param pos Vector3
---@param fwd Vector3
local function CreateMissileLaunchFX(scene, pos, fwd)
    -- 尾焰闪光
    local flameNode = scene:CreateChild("MissileLaunchFlame")
    flameNode.position = pos - fwd * 0.3
    flameNode.scale = Vector3(0.4, 0.4, 0.4)
    local model = flameNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.6, 0.1, 0.8)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(10.0, 5.0, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.0))
    model:SetMaterial(mat)
    model.castShadows = false
    table.insert(muzzleFX_, {
        node = flameNode, mat = mat, age = 0, life = 0.2,
        type = "flash", maxScale = 0.8, colors = MUZZLE_COLORS.explosive, intensity = 1.5,
    })

    -- 发射光
    local lightNode = scene:CreateChild("MissileLaunchLight")
    lightNode.position = pos
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = Color(1.0, 0.6, 0.2)
    lt.range = 8.0
    lt.brightness = 4.0
    lt.castShadows = false
    table.insert(muzzleFX_, {
        node = lightNode, age = 0, life = 0.2,
        type = "light", light = lt, intensity = 1.5,
    })
end

--- 创建爆炸闪光灯（给 CreateExplosion 自动附加）
---@param scene Scene
---@param pos Vector3
---@param size number
CreateExplosionLight = function(scene, pos, size)
    local lightNode = scene:CreateChild("ExplosionLight")
    lightNode.position = pos
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    lt.color = Color(1.0, 0.6, 0.15)
    lt.range = math.max(8.0, size * 1.5)
    lt.brightness = math.max(3.0, size * 0.8)
    lt.castShadows = false
    table.insert(muzzleFX_, {
        node = lightNode, age = 0, life = 0.35,
        type = "light", light = lt, intensity = 2.0,
    })
end

--- 更新所有枪口闪光/发射特效
---@param dt number
function Weapons.UpdateMuzzleFX(dt)
    local i = 1
    while i <= #muzzleFX_ do
        local fx = muzzleFX_[i]
        fx.age = fx.age + dt
        if fx.age >= fx.life then
            fx.node:Remove()
            table.remove(muzzleFX_, i)
        else
            local progress = fx.age / fx.life
            if fx.type == "flash" then
                -- 快速膨胀 + 淡出
                local baseScale = fx.maxScale * 0.3
                local s = baseScale + (fx.maxScale - baseScale) * math.min(1.0, progress * 5.0)
                fx.node.scale = Vector3(s, s, s)
                local alpha = 0.9 * (1.0 - progress)
                local c = fx.colors or MUZZLE_COLORS.rapid
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(c.flash.r, c.flash.g, c.flash.b, alpha)))
                local emFade = math.max(0, 1.0 - progress * 2.0)
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(
                    c.emit.r * emFade, c.emit.g * emFade, c.emit.b * emFade)))
            elseif fx.type == "light" then
                -- 亮度衰减
                local inten = fx.intensity or 1.0
                fx.light.brightness = 3.0 * inten * (1.0 - progress)
                fx.light.range = fx.light.range * (1.0 - progress * 0.3)
            elseif fx.type == "ring" then
                -- 散射环扩散
                local expand = 0.2 + (fx.maxScale or 1.0) * progress
                fx.node.scale = Vector3(expand, 0.01 * (1.0 - progress), expand)
                local alpha = 0.5 * (1.0 - progress)
                fx.mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.7, 0.2, alpha)))
                local em = math.max(0, 6.0 * (1.0 - progress))
                fx.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(em, em * 0.5, em * 0.1)))
            end
            i = i + 1
        end
    end
end

--- 分离一个子节点到场景根并停止发射
---@param bulletNode Node
---@param scene Node
---@param childName string
local function DetachTrailChild(bulletNode, scene, childName)
    local child = bulletNode:GetChild(childName, false)
    if not child then return end

    local worldPos = child.worldPosition
    child.parent = scene
    child.position = worldPos

    local ribbon = child:GetComponent("RibbonTrail")
    if ribbon then
        ribbon.emitting = false
    end
    local emitter = child:GetComponent("ParticleEmitter")
    if emitter then
        emitter.emitting = false
    end

    table.insert(trailCleanup_, { node = child, lifetime = 2.0, age = 0 })
end

--- 移除弹丸节点，分离拖尾/烟雾子节点让残留轨迹自然消散
---@param p table 弹丸数据
local function RemoveProjectileNode(p)
    if not p.hasTrail then
        p.node:Remove()
        return
    end

    local scene = p.node:GetScene()
    if not scene then
        p.node:Remove()
        return
    end

    DetachTrailChild(p.node, scene, "RibbonTrail")
    DetachTrailChild(p.node, scene, "Smoke")

    p.node:Remove()
end

--- 内部发射函数：创建一枚弹药（不检查冷却，不设置连发）
---@param weapon table 武器实例
---@param scene Scene 场景
---@param targetPos Vector3|nil 目标世界坐标
---@param targetLocked boolean 目标是否已完成锁定
---@param targetNode Node|nil 锁定目标的节点（用于追踪）
---@param launchYawOffset number|nil 发射偏航角偏移（度）
---@param targetVelocity Vector3|nil 目标速度向量（用于预判射击）
local function FireProjectile(weapon, scene, targetPos, targetLocked, targetNode, launchYawOffset, targetVelocity)
    -- 消耗弹药
    weapon.ammo = weapon.ammo - 1
    weapon.muzzleFlashTimer = weapon.def.muzzleFlashDur

    -- 发射位置 = 武器挂载点的世界坐标
    local spawnPos = weapon.mountNode.worldPosition

    -- 开火音效回调
    if onFireCallback_ then
        onFireCallback_(weapon.type, spawnPos)
    end
    local mechFwd = weapon.mountNode.worldRotation * Vector3.FORWARD

    -- 非追踪武器：预判射击（lead targeting）
    -- 根据目标速度和弹丸飞行时间，射向目标未来位置
    if targetPos and targetVelocity and not weapon.def.tracking then
        local toTarget = targetPos - spawnPos
        local dist = toTarget:Length()
        if dist > 1.0 then
            local bulletSpd = weapon.def.bulletSpeed
            -- 迭代两次求解更精确的预判位置
            local travelTime = dist / bulletSpd
            local predictedPos = targetPos + targetVelocity * travelTime
            -- 第二次迭代：用预测位置重新算距离和时间
            local dist2 = (predictedPos - spawnPos):Length()
            travelTime = dist2 / bulletSpd
            predictedPos = targetPos + targetVelocity * travelTime
            targetPos = predictedPos
        end
    end

    -- 计算发射方向
    local fireDir
    local targetDir
    if targetPos then
        targetDir = (targetPos - spawnPos):Normalized()
    else
        targetDir = mechFwd
    end
    fireDir = Vector3(targetDir)

    -- 散布
    if weapon.def.spread > 0 then
        local spreadX = (math.random() - 0.5) * 2 * weapon.def.spread
        local spreadY = (math.random() - 0.5) * 2 * weapon.def.spread
        local right = fireDir:CrossProduct(Vector3.UP):Normalized()
        local up = right:CrossProduct(fireDir):Normalized()
        fireDir = (fireDir + right * spreadX + up * spreadY):Normalized()
    end

    -- 飞弹上升阶段：发射方向斜向上（可附带偏航偏移）
    local hasLaunchPhase = (weapon.def.launchTime or 0) > 0
    if hasLaunchPhase then
        local upAngle = weapon.def.launchUpAngle or 60.0
        local flatDir = Vector3(targetDir.x, 0, targetDir.z)
        if flatDir:Length() < 0.01 then flatDir = mechFwd end
        flatDir = flatDir:Normalized()

        if launchYawOffset and launchYawOffset ~= 0 then
            local yawRot = Quaternion(launchYawOffset, Vector3.UP)
            flatDir = (yawRot * flatDir):Normalized()
        end

        local rad = math.rad(upAngle)
        fireDir = (flatDir * math.cos(rad) + Vector3.UP * math.sin(rad)):Normalized()
    end

    -- 创建弹药节点
    local bulletNode = scene:CreateChild("Bullet")
    bulletNode.position = spawnPos
    bulletNode.rotation = Quaternion(Vector3.FORWARD, fireDir)
    bulletNode.scale = weapon.def.bulletScale

    local bulletModel = bulletNode:CreateComponent("StaticModel")
    bulletModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bulletModel:SetMaterial(CreateBulletMat(weapon.def.bulletColor, weapon.def.emissive))
    bulletModel.castShadows = false

    -- RibbonTrail 拖尾效果（所有带 trailColor 的武器自动生效）
    local trailNode = nil
    local tc = weapon.def.trailColor
    if tc then
        trailNode = bulletNode:CreateChild("RibbonTrail")
        local ribbon = trailNode:CreateComponent("RibbonTrail")
        ribbon.material = CreateTrailMat(tc)
        -- 根据武器类型调整拖尾参数
        local isHeavy = (weapon.type == "rpg" or weapon.type == "shoulder_rpg")
        local isMissile = (weapon.type == "missile" or weapon.type == "vertical_missile")
        ribbon.width = isHeavy and 0.2 or (isMissile and 0.15 or 0.1)
        ribbon.lifetime = isHeavy and 0.8 or 0.6
        ribbon.vertexDistance = isHeavy and 0.4 or 0.3
        ribbon.startColor = Color(tc.r, tc.g, tc.b, tc.a or 1.0)
        ribbon.endColor = Color(tc.r * 0.8, tc.g * 0.3, tc.b * 0.1, 0.0)
        ribbon.startScale = 1.0
        ribbon.endScale = isHeavy and 0.05 or 0.1
        ribbon.sorted = true
        ribbon.emitting = true

        -- RPG 类武器附带烟雾粒子
        if isHeavy then
            local smokeNode = bulletNode:CreateChild("Smoke")
            local emitter = smokeNode:CreateComponent("ParticleEmitter")
            local effect = ParticleEffect()
            effect.material = CreateSmokeMat()
            effect.numParticles = 64
            effect.emitterType = EMITTER_SPHERE
            effect.emitterSize = Vector3(0.15, 0.15, 0.15)
            effect.minDirection = Vector3(-0.3, 0.2, -0.3)
            effect.maxDirection = Vector3(0.3, 0.8, 0.3)
            effect.minVelocity = 0.5
            effect.maxVelocity = 1.5
            effect.minParticleSize = Vector2(0.4, 0.4)
            effect.maxParticleSize = Vector2(1.2, 1.2)
            effect.minTimeToLive = 0.8
            effect.maxTimeToLive = 1.8
            effect.minEmissionRate = 20
            effect.maxEmissionRate = 30
            effect.minRotationSpeed = -60
            effect.maxRotationSpeed = 60
            effect.sizeAdd = 0.8
            effect.dampingForce = 1.0
            effect:AddColorTime(Color(0.7, 0.7, 0.7, 0.4), 0.0)
            effect:AddColorTime(Color(0.5, 0.5, 0.5, 0.25), 0.4)
            effect:AddColorTime(Color(0.3, 0.3, 0.3, 0.0), 1.0)
            effect.sorted = true
            emitter.effect = effect
            emitter.emitting = true
        end
    end

    -- 弹药数据
    local def = weapon.def
    local proj = {
        node = bulletNode,
        dir = Vector3(fireDir),
        speed = def.bulletSpeed,
        maxSpeed = def.maxSpeed or def.bulletSpeed,
        life = def.bulletLife,
        age = 0,
        damage = def.damage * (weapon.dmgMult or 1.0),
        tracking = def.tracking,
        targetNode = targetLocked and targetNode or nil,
        fixedTargetPos = targetPos
            and Vector3(targetPos.x, targetPos.y, targetPos.z) or nil,
        weaponType = weapon.type,
        initialTurnRate = def.initialTurnRate or def.turnRate or 0,
        finalTurnRate = def.finalTurnRate or def.turnRate or 0,
        turnRateDecayTime = def.turnRateDecayTime or 1.0,
        trackingAge = 0,
        launchTime = def.launchTime or 0,
        launchAge = 0,
        inLaunchPhase = hasLaunchPhase,
        owner = weapon.owner or "player",
        dmgMult = weapon.dmgMult or 1.0,
        hasTrail = (trailNode ~= nil),
        piercing = def.piercing or false,
        hitTargets = {},            -- 穿透弹记录已命中目标
    }

    table.insert(projectiles_, proj)

    -- 枪口闪光特效（电磁炮有独立特效，跳过）
    if weapon.type ~= "railgun" then
        local category = weapon.def.category or "rapid"
        local wt = weapon.type
        if wt == "missile" or wt == "vertical_missile" then
            -- 飞弹类：尾焰 + 烟雾
            CreateMissileLaunchFX(scene, spawnPos, mechFwd)
        elseif wt == "rpg" or wt == "shoulder_rpg" or wt == "tank_cannon" then
            -- 爆破类：更强的枪口闪光
            CreateMuzzleFlashFX(scene, spawnPos, mechFwd, "explosive", 2.0)
        elseif wt ~= "shotgun" then
            -- 其他常规武器（机关枪/手枪/飞弹枪等）
            local intensity = (category == "tracking") and 1.2 or 1.0
            CreateMuzzleFlashFX(scene, spawnPos, mechFwd, category, intensity)
        end
        -- 霰弹枪闪光在 TryFire 中统一处理（含散射弹丸后）
    end
end

--- 内部：创建额外弹丸（用于霰弹枪散射，不消耗弹药）
---@param weapon table
---@param scene Scene
---@param spawnPos Vector3
---@param baseDir Vector3
---@param targetLocked boolean
---@param targetNode Node|nil
---@param targetPos Vector3|nil
local function FirePellet(weapon, scene, spawnPos, baseDir, targetLocked, targetNode, targetPos)
    local def = weapon.def

    -- 每颗弹丸独立散布
    local fireDir = Vector3(baseDir)
    if def.spread > 0 then
        local spreadX = (math.random() - 0.5) * 2 * def.spread
        local spreadY = (math.random() - 0.5) * 2 * def.spread
        local right = fireDir:CrossProduct(Vector3.UP):Normalized()
        local up = right:CrossProduct(fireDir):Normalized()
        fireDir = (fireDir + right * spreadX + up * spreadY):Normalized()
    end

    local bulletNode = scene:CreateChild("Pellet")
    bulletNode.position = spawnPos
    bulletNode.rotation = Quaternion(Vector3.FORWARD, fireDir)
    bulletNode.scale = def.bulletScale

    local bulletModel = bulletNode:CreateComponent("StaticModel")
    bulletModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bulletModel:SetMaterial(CreateBulletMat(def.bulletColor, def.emissive))
    bulletModel.castShadows = false

    table.insert(projectiles_, {
        node = bulletNode,
        dir = Vector3(fireDir),
        speed = def.bulletSpeed,
        maxSpeed = def.maxSpeed or def.bulletSpeed,
        life = def.bulletLife,
        age = 0,
        damage = def.damage * (weapon.dmgMult or 1.0),
        tracking = false,
        targetNode = nil,
        fixedTargetPos = nil,
        weaponType = weapon.type,
        initialTurnRate = 0,
        finalTurnRate = 0,
        turnRateDecayTime = 1.0,
        trackingAge = 0,
        launchTime = 0,
        launchAge = 0,
        inLaunchPhase = false,
        owner = weapon.owner or "player",
        dmgMult = weapon.dmgMult or 1.0,
        hasTrail = false,
        piercing = false,
        hitTargets = {},
    })
end

--- 尝试发射武器（处理冷却 + 连发初始化）
---@param weapon table 武器实例
---@param scene Scene 场景
---@param targetPos Vector3|nil 目标世界坐标
---@param targetLocked boolean 目标是否已完成锁定
---@param targetNode Node|nil 锁定目标的节点（用于追踪）
---@param launchYawOffset number|nil 发射偏航角偏移（度）
---@param targetVelocity Vector3|nil 目标速度向量（用于预判射击）
---@return boolean 是否成功发射
function Weapons.TryFire(weapon, scene, targetPos, targetLocked, targetNode, launchYawOffset, targetVelocity)
    if not weapon then return false end

    -- 换弹中无法射击
    if weapon.reloading then return false end

    -- 弹药耗尽，自动开始换弹
    if weapon.ammo <= 0 then
        weapon.reloading = true
        weapon.reloadTimer = weapon.reloadTime
        weapon.burstRemaining = 0
        weapon.burstParams = nil
        return false
    end

    -- 连发进行中时不允许重新触发
    if weapon.burstRemaining > 0 then return false end

    local now = time.elapsedTime
    local interval = 1.0 / weapon.def.fireRate
    if (now - weapon.lastFireTime) < interval then
        return false
    end

    -- 发射第一枚
    FireProjectile(weapon, scene, targetPos, targetLocked, targetNode, launchYawOffset, targetVelocity)

    -- 霰弹散射：额外弹丸（不消耗弹药，共享同一次射击）
    local pelletCount = weapon.def.pelletCount or 1
    if pelletCount > 1 then
        local spawnPos = weapon.mountNode.worldPosition
        local mechFwd = weapon.mountNode.worldRotation * Vector3.FORWARD
        local baseDir = targetPos and (targetPos - spawnPos):Normalized() or mechFwd
        for _ = 2, pelletCount do
            FirePellet(weapon, scene, spawnPos, baseDir, targetLocked, targetNode, targetPos)
        end
        -- 霰弹枪散射闪光（所有弹丸发射后统一产生一次大闪光）
        CreateShotgunFlashFX(scene, spawnPos, baseDir)
    end

    -- 连发：队列剩余枚数（需确保弹匣够用）
    local burstCount = weapon.def.burstCount or 1
    local remaining = math.min(burstCount - 1, weapon.ammo)  -- 剩余弹药限制连发数
    if remaining > 0 then
        weapon.burstRemaining = remaining
        weapon.burstNextTime = now + (weapon.def.burstInterval or 0.1)
        weapon.burstParams = {
            scene = scene,
            targetPos = targetPos and Vector3(targetPos.x, targetPos.y, targetPos.z) or nil,
            targetLocked = targetLocked,
            targetNode = targetNode,
            launchYawOffset = launchYawOffset,
            targetVelocity = targetVelocity and Vector3(targetVelocity.x, targetVelocity.y, targetVelocity.z) or nil,
        }
    else
        weapon.lastFireTime = now
        -- 打完最后一发，自动换弹
        if weapon.ammo <= 0 then
            weapon.reloading = true
            weapon.reloadTimer = weapon.reloadTime
        end
    end

    return true
end

--- 发射单发弹药（不触发连发逻辑，用于多目标队列发射）
---@param weapon table 武器实例
---@param scene Scene 场景
---@param targetPos Vector3|nil 目标世界坐标
---@param targetLocked boolean 目标是否已完成锁定
---@param targetNode Node|nil 锁定目标的节点（用于追踪）
---@param launchYawOffset number|nil 发射偏航角偏移（度）
---@param targetVelocity Vector3|nil 目标速度向量（用于预判射击）
---@return boolean 是否成功发射
function Weapons.FireSingle(weapon, scene, targetPos, targetLocked, targetNode, launchYawOffset, targetVelocity)
    if not weapon then return false end
    if weapon.reloading then return false end
    if weapon.ammo <= 0 then
        weapon.reloading = true
        weapon.reloadTimer = weapon.reloadTime
        return false
    end

    FireProjectile(weapon, scene, targetPos, targetLocked, targetNode, launchYawOffset, targetVelocity)
    weapon.lastFireTime = time.elapsedTime

    if weapon.ammo <= 0 then
        weapon.reloading = true
        weapon.reloadTimer = weapon.reloadTime
    end
    return true
end

--- 更新连发队列（每帧调用）
---@param weapon table 武器实例
---@param dt number
function Weapons.UpdateBurst(weapon, dt)
    if not weapon then return end
    if weapon.burstRemaining <= 0 then return end
    if weapon.reloading then return end

    -- 弹药耗尽，终止连发并换弹
    if weapon.ammo <= 0 then
        weapon.burstRemaining = 0
        weapon.burstParams = nil
        weapon.lastFireTime = time.elapsedTime
        weapon.reloading = true
        weapon.reloadTimer = weapon.reloadTime
        return
    end

    local now = time.elapsedTime
    if now >= weapon.burstNextTime then
        local p = weapon.burstParams
        FireProjectile(weapon, p.scene, p.targetPos, p.targetLocked, p.targetNode, p.launchYawOffset, p.targetVelocity)
        weapon.burstRemaining = weapon.burstRemaining - 1

        if weapon.burstRemaining > 0 then
            -- 连发继续，但检查弹药
            if weapon.ammo <= 0 then
                weapon.burstRemaining = 0
                weapon.burstParams = nil
                weapon.lastFireTime = now
                weapon.reloading = true
                weapon.reloadTimer = weapon.reloadTime
            else
                weapon.burstNextTime = now + (weapon.def.burstInterval or 0.1)
            end
        else
            -- 连发完毕，设置冷却起点
            weapon.lastFireTime = now
            weapon.burstParams = nil
            -- 连发结束后弹药耗尽，自动换弹
            if weapon.ammo <= 0 then
                weapon.reloading = true
                weapon.reloadTimer = weapon.reloadTime
            end
        end
    end
end

--- 更新换弹计时（每帧调用）
---@param weapon table 武器实例
---@param dt number
function Weapons.UpdateReload(weapon, dt)
    if not weapon then return end
    if not weapon.reloading then return end

    weapon.reloadTimer = weapon.reloadTimer - dt
    if weapon.reloadTimer <= 0 then
        weapon.reloading = false
        weapon.reloadTimer = 0
        weapon.ammo = weapon.magazineSize
    end
end

--- 更新所有弹药
---@param dt number
function Weapons.UpdateProjectiles(dt)
    local i = 1
    while i <= #projectiles_ do
        local p = projectiles_[i]
        p.age = p.age + dt

        if p.age >= p.life then
            -- 超时移除（有爆炸半径的武器超时也触发爆炸）
            local def = Weapons.DEFS[p.weaponType]
            if def and def.blastRadius then
                local bPos = p.node.worldPosition
                CreateExplosion(p.node:GetScene(), bPos, def.blastRadius, Color(1.0, 0.4, 0.05))
                local bDmg = (def.blastDamage or 0) * (p.dmgMult or 1.0)
                ApplyBlastDamage(bPos, def.blastRadius, bDmg, nil, p.owner)
                if onExplosionCallback_ then onExplosionCallback_(p.weaponType, bPos) end
            end
            RemoveProjectileNode(p)
            table.remove(projectiles_, i)
        else
            local moveDist = p.speed * dt

            -- 上升阶段：直线飞行，不追踪（时间判定）
            if p.inLaunchPhase then
                p.launchAge = p.launchAge + dt
                if p.launchAge >= p.launchTime then
                    p.inLaunchPhase = false  -- 切换到追踪阶段
                    p.trackingAge = 0        -- 重置追踪计时
                end
            else
                -- 追踪逻辑（仅上升阶段结束后）
                if p.tracking then
                    -- 确定追踪目标位置：锁定 → 移动目标，未锁定 → 固定位置
                    local trackTarget = nil
                    if p.targetNode then
                        local tvh = 1.7
                        for _, e in ipairs(enemies_) do
                            if e.node == p.targetNode then tvh = (e.visualHeight or 3.5) * 0.5; break end
                        end
                        trackTarget = p.targetNode.worldPosition + Vector3(0, tvh, 0)
                    elseif p.fixedTargetPos then
                        trackTarget = p.fixedTargetPos
                    end

                    if trackTarget then
                        p.trackingAge = p.trackingAge + dt

                        local toTarget = (trackTarget - p.node.worldPosition):Normalized()
                        local curDir = p.dir
                        local dot = curDir:DotProduct(toTarget)
                        local angle = math.deg(math.acos(math.max(-1, math.min(1, dot))))

                        -- 转向速率：角度差 < 5° 时立刻降至最低，否则按时间衰减
                        local currentTurnRate
                        if angle < 5.0 then
                            currentTurnRate = p.finalTurnRate
                        elseif p.trackingAge < p.turnRateDecayTime then
                            local t = p.trackingAge / p.turnRateDecayTime
                            currentTurnRate = p.initialTurnRate + (p.finalTurnRate - p.initialTurnRate) * t
                        else
                            currentTurnRate = p.finalTurnRate
                        end

                        -- 限速转向
                        local maxTurn = currentTurnRate * dt
                        local cross = curDir:CrossProduct(toTarget)

                        if angle > 0.1 then
                            local actualTurn = math.min(maxTurn, angle)
                            local axis = cross:Normalized()
                            if axis:Length() > 0.01 then
                                local rot = Quaternion(actualTurn, axis)
                                p.dir = (rot * curDir):Normalized()
                            end
                        end

                        -- 追踪时加速到最大速度
                        if p.speed < p.maxSpeed then
                            p.speed = math.min(p.maxSpeed, p.speed + 30.0 * dt)
                        end
                    end
                end
            end

            -- 场景碰撞检测（射线检测，移动前执行）
            local bulletPosBefore = p.node.worldPosition
            local scene = p.node:GetScene()
            local pw = scene:GetComponent("PhysicsWorld")
            local hitScene = false
            local hitPos = nil

            if pw then
                local ray = Ray(bulletPosBefore, p.dir)
                local result = pw:RaycastSingle(ray, moveDist + 0.1, CollisionLayerStatic)
                if result and result.body then
                    hitScene = true
                    hitPos = result.position
                end
            end

            if hitScene then
                -- 命中场景物体，创建爆炸效果
                local def = Weapons.DEFS[p.weaponType]
                if def and def.blastRadius then
                    CreateExplosion(scene, hitPos, def.blastRadius, Color(1.0, 0.4, 0.05))
                    local bDmg = (def.blastDamage or 0) * (p.dmgMult or 1.0)
                    ApplyBlastDamage(hitPos, def.blastRadius, bDmg, nil, p.owner)
                    if onExplosionCallback_ then onExplosionCallback_(p.weaponType, hitPos) end
                else
                    CreateExplosion(scene, hitPos, 0.6, Color(1.0, 0.7, 0.2))
                end
                RemoveProjectileNode(p)
                table.remove(projectiles_, i)
            else
                -- 移动
                local move = p.dir * moveDist
                p.node.position = bulletPosBefore + move
                p.node.rotation = Quaternion(Vector3.FORWARD, p.dir)

                -- 命中检测（线段-球体检测，解决高速弹丸穿透问题）
                local hitRadius = HIT_RADIUS[p.weaponType] or 1.5
                local bulletPosAfter = p.node.worldPosition
                local hitTarget = false

                if p.owner ~= "enemy" then
                    -- 玩家弹丸：检测敌人
                    for _, enemy in ipairs(enemies_) do
                        -- 穿透弹：跳过已命中的目标
                        if p.piercing and p.hitTargets[enemy] then goto continue_enemy end

                        local enemyCenter = enemy.node.worldPosition + Vector3(0, 1.7, 0)
                        -- 线段 AB 与目标球体的最近距离检测
                        local ab = bulletPosAfter - bulletPosBefore
                        local ae = enemyCenter - bulletPosBefore
                        local abLenSq = ab:DotProduct(ab)
                        local distSq
                        if abLenSq < 0.001 then
                            -- 几乎未移动，退化为点检测
                            distSq = ae:DotProduct(ae)
                        else
                            local t = math.max(0, math.min(1, ae:DotProduct(ab) / abLenSq))
                            local closest = bulletPosBefore + ab * t
                            local diff = enemyCenter - closest
                            distSq = diff:DotProduct(diff)
                        end
                        if distSq < hitRadius * hitRadius then
                            local def = Weapons.DEFS[p.weaponType]
                            local dmg = p.damage or (def and def.damage or 5)
                            if enemy.hp then
                                enemy.hp = math.max(0, enemy.hp - dmg)
                                print(string.format("[Weapons] %s hit enemy, dmg=%.1f, hp=%.0f/%d", def.name, dmg, enemy.hp, enemy.maxHp or 100))
                            end
                            local hitPt = bulletPosAfter
                            if def and def.blastRadius then
                                CreateExplosion(scene, hitPt, def.blastRadius, Color(1.0, 0.4, 0.05))
                                local bDmg = (def.blastDamage or 0) * (p.dmgMult or 1.0)
                                ApplyBlastDamage(hitPt, def.blastRadius, bDmg, enemy, p.owner)
                                if onExplosionCallback_ then onExplosionCallback_(p.weaponType, hitPt) end
                            else
                                CreateExplosion(scene, hitPt, 1.0, Color(1.0, 0.8, 0.3))
                            end
                            -- 命中回调（用于武器特殊命中特效，如电磁炮电弧）
                            if onHitCallback_ then onHitCallback_(p.weaponType, hitPt) end

                            if p.piercing then
                                p.hitTargets[enemy] = true  -- 记录已命中，继续飞行
                            else
                                hitTarget = true
                                break
                            end
                        end
                        ::continue_enemy::
                    end
                else
                    -- 敌方弹丸：检测玩家
                    if playerInfo_ and playerInfo_.node then
                        local playerCenter = playerInfo_.node.worldPosition + Vector3(0, 1.7, 0)
                        -- 线段-球体检测（同上）
                        local ab = bulletPosAfter - bulletPosBefore
                        local ae = playerCenter - bulletPosBefore
                        local abLenSq = ab:DotProduct(ab)
                        local distSq
                        if abLenSq < 0.001 then
                            distSq = ae:DotProduct(ae)
                        else
                            local t = math.max(0, math.min(1, ae:DotProduct(ab) / abLenSq))
                            local closest = bulletPosBefore + ab * t
                            local diff = playerCenter - closest
                            distSq = diff:DotProduct(diff)
                        end
                        if distSq < hitRadius * hitRadius then
                            local def = Weapons.DEFS[p.weaponType]
                            local dmg = p.damage or (def and def.damage or 5)
                            -- 喷射状态下伤害减半
                            if playerInfo_.isJetting and playerInfo_.isJetting() then
                                dmg = dmg * 0.5
                            end
                            local curHP = playerInfo_.getHP()
                            playerInfo_.setHP(math.max(0, curHP - dmg))
                            print(string.format("[Weapons] %s hit player, dmg=%.1f", def.name, dmg))
                            if def and def.blastRadius then
                                CreateExplosion(scene, bulletPosAfter, def.blastRadius, Color(1.0, 0.4, 0.05))
                                local blastDmg = (def.blastDamage or 0) * (p.dmgMult or 1.0)
                                ApplyBlastDamage(bulletPosAfter, def.blastRadius, blastDmg, nil, p.owner)
                                if onExplosionCallback_ then onExplosionCallback_(p.weaponType, bulletPosAfter) end
                            else
                                CreateExplosion(scene, bulletPosAfter, 1.0, Color(1.0, 0.8, 0.3))
                            end
                            hitTarget = true
                        end
                    end
                end

                if hitTarget then
                    RemoveProjectileNode(p)
                    table.remove(projectiles_, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

--- 更新爆炸效果
---@param dt number
function Weapons.UpdateExplosions(dt)
    local i = 1
    while i <= #explosions_ do
        local e = explosions_[i]
        e.age = e.age + dt

        if e.age >= e.life then
            e.node:Remove()
            table.remove(explosions_, i)
        else
            local progress = e.age / e.life

            -- 膨胀：从初始大小快速膨胀到最大
            local scaleFactor = e.initScale + (e.maxScale - e.initScale) * math.min(1.0, progress * 3.0)
            e.node.scale = Vector3(scaleFactor, scaleFactor, scaleFactor)

            -- 淡出：透明度从 0.8 衰减到 0
            local alpha = 0.8 * (1.0 - progress)
            local c = e.color
            e.mat:SetShaderParameter("MatDiffColor", Variant(Color(c.r, c.g, c.b, alpha)))

            -- 发光衰减
            local emissiveMul = math.max(0, 5.0 * (1.0 - progress * 2.0))
            e.mat:SetShaderParameter("MatEmissiveColor", Variant(Color(c.r * emissiveMul, c.g * emissiveMul, c.b * emissiveMul * 0.6)))

            i = i + 1
        end
    end
end

--- 更新武器闪光效果
---@param weapon table
---@param dt number
function Weapons.UpdateMuzzleFlash(weapon, dt)
    if not weapon then return end
    if weapon.muzzleFlashTimer > 0 then
        weapon.muzzleFlashTimer = weapon.muzzleFlashTimer - dt
    end
end

--- 更新残留拖尾/粒子节点的生命周期（自然消散后清理）
---@param dt number
function Weapons.UpdateTrailCleanup(dt)
    local i = 1
    while i <= #trailCleanup_ do
        local t = trailCleanup_[i]
        t.age = t.age + dt
        if t.age >= t.lifetime then
            if t.node then
                t.node:Remove()
            end
            table.remove(trailCleanup_, i)
        else
            i = i + 1
        end
    end
end

--- 获取活跃弹药数量
---@return number
function Weapons.GetProjectileCount()
    return #projectiles_
end

--- 获取活跃弹丸列表引用（只读，供 AI 检测来袭弹丸）
---@return table[]
function Weapons.GetProjectiles()
    return projectiles_
end

--- 清除所有弹药、爆炸效果和残留拖尾
function Weapons.ClearAll()
    for _, p in ipairs(projectiles_) do
        if p.node then
            p.node:Remove()
        end
    end
    projectiles_ = {}
    for _, e in ipairs(explosions_) do
        if e.node then
            e.node:Remove()
        end
    end
    explosions_ = {}
    for _, t in ipairs(trailCleanup_) do
        if t.node then
            t.node:Remove()
        end
    end
    trailCleanup_ = {}
    -- 清理枪口闪光/发射特效
    for _, fx in ipairs(muzzleFX_) do
        if fx.node then fx.node:Remove() end
    end
    muzzleFX_ = {}
    -- 清理武器外观材质缓存
    WeaponVisuals.ClearCache()
end

return Weapons
