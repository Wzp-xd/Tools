-- ============================================================================
-- Audio.lua - 音效系统
-- ============================================================================

local Config = require "modules.Config"
local GameState = require "modules.GameState"
local EffectsLib = require "urhox-libs.Effects.Effects"

local M = {}

local CONFIG = Config.CONFIG

--- 初始化音效系统
function M.Init()
    -- 尝试播放背景音乐
    -- GameState.bgmHandle = EffectsLib.PlaySoundLooped(GameState.scene, CONFIG.MusicPath, {
    --     gain = CONFIG.MusicVolume,
    -- })
    -- 
    -- if GameState.bgmHandle then
    --     print("Background music started: " .. CONFIG.MusicPath)
    -- else
    --     print("Note: Background music not found at " .. CONFIG.MusicPath)
    -- end
end

--- 播放音效
--- @param soundKey string 音效键名（对应 CONFIG.SoundPaths）
--- @param options table|nil 可选参数 {gain, position}
function M.PlaySfx(soundKey, options)
    do return end -- 暂时关闭播放音效
    if not GameState.soundEnabled then return end
    if not GameState.scene then return end
    
    local soundPath = CONFIG.SoundPaths[soundKey]
    if not soundPath then
        print("Warning: Unknown sound key: " .. tostring(soundKey))
        return
    end
    
    options = options or {}
    options.gain = (options.gain or 1.0) * CONFIG.SfxVolume
    
    EffectsLib.PlaySound(GameState.scene, soundPath, options)
end

--- 根据武器类型播放射击音效
--- @param weaponId string 武器ID
function M.PlayGunshotSound(weaponId)
    local soundKey = "gunshot_" .. weaponId
    if CONFIG.SoundPaths[soundKey] then
        M.PlaySfx(soundKey)
    else
        -- 默认使用手枪音效
        M.PlaySfx("gunshot_pistol")
    end
end

--- 切换音效开关
function M.ToggleSound()
    GameState.soundEnabled = not GameState.soundEnabled
    
    if GameState.bgmHandle then
        if GameState.soundEnabled then
            GameState.bgmHandle.source.gain = CONFIG.MusicVolume
        else
            GameState.bgmHandle.source.gain = 0
        end
    end
    
    print("Sound " .. (GameState.soundEnabled and "enabled" or "disabled"))
end

--- 停止所有音效
function M.StopAll()
    if GameState.bgmHandle then
        GameState.bgmHandle:Stop()
        GameState.bgmHandle = nil
    end
end

return M
