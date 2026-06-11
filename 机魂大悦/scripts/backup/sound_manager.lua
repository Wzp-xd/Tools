-- ============================================================================
-- 音频管理器 - Sound Manager
-- 统一管理 BGM 和音效的加载与播放
-- ============================================================================

local SoundConfig = require "sound_config"

local SoundManager = {}

---@type Scene
local bgmScene_ = nil
---@type Node
local bgmNode_ = nil
---@type SoundSource
local bgmSource_ = nil
local currentBGM_ = ""

---@type Scene
local sfxScene_ = nil
---@type Node
local sfxNode_ = nil

---@type table<string, Sound>
local sfxCache_ = {}

-- ============================================================================
-- 初始化
-- ============================================================================

--- 确保 BGM 子系统已初始化（独立于游戏场景，避免场景销毁时 BGM 中断）
local function EnsureBGMReady()
    if bgmSource_ then return true end
    -- BGM 使用独立 Scene，不受游戏场景销毁影响
    bgmScene_ = Scene:new()
    bgmNode_ = bgmScene_:CreateChild("BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = "Music"
    bgmSource_.gain = 0.5
    return true
end

--- 初始化音频管理器（绑定游戏场景用于 3D SFX）
---@param scene Scene
function SoundManager.Init(scene)
    -- BGM 独立初始化
    EnsureBGMReady()

    -- SFX 节点挂在游戏场景上（支持 3D 空间音效）
    sfxScene_ = scene
    sfxNode_ = scene:CreateChild("SFX")

    print("[SoundManager] Initialized")
end

-- ============================================================================
-- BGM
-- ============================================================================

--- 播放 BGM（自动循环）
---@param key string BGM 配置键名（如 "menu", "battle1"）
function SoundManager.PlayBGM(key)
    EnsureBGMReady()
    local cfg = SoundConfig.BGM[key]
    if not cfg then
        print("[SoundManager] Unknown BGM key: " .. tostring(key))
        return
    end
    if currentBGM_ == key and bgmSource_:IsPlaying() then return end

    local sound = cache:GetResource("Sound", cfg.path)
    if not sound then
        print("[SoundManager] Failed to load BGM: " .. cfg.path)
        return
    end
    sound.looped = true
    bgmSource_:Stop()
    bgmSource_.gain = cfg.gain
    bgmSource_:Play(sound)
    currentBGM_ = key
    print("[SoundManager] Playing BGM: " .. cfg.name .. " (" .. key .. ")")
end

--- 播放随机战斗 BGM
function SoundManager.PlayRandomBattleBGM()
    local keys = SoundConfig.BattleBGMKeys
    local key = keys[math.random(1, #keys)]
    SoundManager.PlayBGM(key)
end

--- 停止 BGM
function SoundManager.StopBGM()
    if bgmSource_ then
        bgmSource_:Stop()
        currentBGM_ = ""
    end
end

--- 清理游戏场景相关资源（在场景销毁前调用）
function SoundManager.OnSceneDestroy()
    -- 循环音效挂在 sfxNode_ 上，场景销毁后引用失效
    loopSources_ = {}
    sfxNode_ = nil
    sfxScene_ = nil
end

--- 设置 BGM 音量
---@param gain number 0.0 ~ 1.0
function SoundManager.SetBGMGain(gain)
    if bgmSource_ then
        bgmSource_.gain = gain
    end
end

-- ============================================================================
-- SFX
-- ============================================================================

--- 获取或缓存音效资源
---@param sfxKey string
---@return Sound|nil
local function GetSFX(sfxKey)
    if sfxCache_[sfxKey] then return sfxCache_[sfxKey] end
    local cfg = SoundConfig.SFX[sfxKey]
    if not cfg then return nil end
    local sound = cache:GetResource("Sound", cfg.path)
    if sound then
        sfxCache_[sfxKey] = sound
    end
    return sound
end

--- 播放 2D 音效（无空间定位）
---@param sfxKey string 音效配置键名
function SoundManager.PlaySFX(sfxKey)
    -- 2D 音效优先挂在游戏场景 SFX 节点上；场景不存在时用 BGM 独立场景
    local node = sfxNode_ or bgmNode_
    if not node then
        EnsureBGMReady()
        node = bgmNode_
    end
    if not node then return end
    local sound = GetSFX(sfxKey)
    if not sound then return end
    local cfg = SoundConfig.SFX[sfxKey]

    local src = node:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = cfg.gain
    src.autoRemoveMode = REMOVE_COMPONENT
    src:Play(sound)
end

--- 播放 3D 音效（空间定位）
---@param sfxKey string 音效配置键名
---@param position Vector3 世界坐标
---@param nearDist number|nil 近距离（默认 5）
---@param farDist number|nil 远距离（默认 100）
function SoundManager.PlaySFX3D(sfxKey, position, nearDist, farDist)
    if not sfxNode_ then return end
    local sound = GetSFX(sfxKey)
    if not sound then return end
    local cfg = SoundConfig.SFX[sfxKey]

    local node = sfxNode_:GetScene():CreateChild("SFX3D")
    node.position = position
    local src = node:CreateComponent("SoundSource3D")
    src.soundType = "Effect"
    src.gain = cfg.gain
    src:SetDistanceAttenuation(nearDist or 5, farDist or 100, 1.0)
    src.autoRemoveMode = REMOVE_NODE
    src:Play(sound)
end

--- 通过武器 key 播放开火音效
---@param weaponKey string weapon_defs 中的武器 key
---@param position Vector3|nil 3D 位置（nil 则播放 2D）
function SoundManager.PlayWeaponFire(weaponKey, position)
    if not SoundConfig.weaponSFXEnabled then return end
    local sfxKey = SoundConfig.WeaponFireSFX[weaponKey]
    if not sfxKey then return end
    if position then
        SoundManager.PlaySFX3D(sfxKey, position)
    else
        SoundManager.PlaySFX(sfxKey)
    end
end

--- 通过武器 key 播放爆炸音效
---@param weaponKey string
---@param position Vector3
function SoundManager.PlayWeaponExplosion(weaponKey, position)
    if not SoundConfig.weaponSFXEnabled then return end
    local sfxKey = SoundConfig.WeaponExplosionSFX[weaponKey]
    if not sfxKey then return end
    if position then
        SoundManager.PlaySFX3D(sfxKey, position, 10, 200)
    else
        SoundManager.PlaySFX(sfxKey)
    end
end

-- ============================================================================
-- 循环 SFX（用于持续音效，如喷射引擎声）
-- ============================================================================

---@type table<string, SoundSource>
local loopSources_ = {}

--- 开始循环播放音效（如果已在播放则忽略）
---@param handle string 唯一标识（如 "jet_loop"）
---@param sfxKey string 音效配置键名
---@param gain number|nil 音量覆盖
function SoundManager.StartLoop(handle, sfxKey, gain)
    if loopSources_[handle] then return end -- 已在播放
    local node = sfxNode_ or bgmNode_
    if not node then
        EnsureBGMReady()
        node = bgmNode_
    end
    if not node then return end
    local sound = GetSFX(sfxKey)
    if not sound then return end
    sound.looped = true
    local cfg = SoundConfig.SFX[sfxKey]
    local src = node:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = gain or (cfg and cfg.gain) or 0.5
    src:Play(sound)
    loopSources_[handle] = src
end

--- 停止循环音效
---@param handle string
function SoundManager.StopLoop(handle)
    local src = loopSources_[handle]
    if src then
        src:Stop()
        loopSources_[handle] = nil
    end
end

--- 停止全部循环音效
function SoundManager.StopAllLoops()
    for h, src in pairs(loopSources_) do
        src:Stop()
    end
    loopSources_ = {}
end

return SoundManager
