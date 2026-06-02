-- sound_manager.lua
-- 音效统一管理模块
-- 支持一次性播放和循环播放

---@diagnostic disable: undefined-global
local SoundManager = {}

-- 音效路径映射
local SOUNDS = {
    -- 游戏核心
    gear_select   = "audio/sfx/gear_select.ogg",
    gear_place    = "audio/sfx/gear_place.ogg",
    move_invalid  = "audio/sfx/move_invalid.ogg",
    peg_unlock    = "audio/sfx/peg_unlock.ogg",
    peg_complete  = "audio/sfx/peg_complete.ogg",
    level_win     = "audio/sfx/level_win.ogg",
    level_lose    = "audio/sfx/level_lose.ogg",
    undo          = "audio/sfx/undo.ogg",
    reset         = "audio/sfx/reset.ogg",
    -- 游戏核心补充
    gear_rotate   = "audio/sfx/gear_rotate.ogg",
    gear_mesh     = "audio/sfx/gear_mesh.ogg",
    gear_remove   = "audio/sfx/gear_remove.ogg",
    combo_hit     = "audio/sfx/combo_hit.ogg",
    hint_show     = "audio/sfx/hint_show.ogg",
    star_collect  = "audio/sfx/star_collect.ogg",
    -- UI 交互
    level_select  = "audio/sfx/sfx_level_select.ogg",
    pause_open    = "audio/sfx/sfx_pause_open.ogg",
    pause_close   = "audio/sfx/sfx_pause_close.ogg",
    win_popup     = "audio/sfx/sfx_win_popup.ogg",
    lose_popup    = "audio/sfx/sfx_lose_popup.ogg",
    next_level    = "audio/sfx/sfx_next_level.ogg",
    back_menu     = "audio/sfx/sfx_back_menu.ogg",
    -- 通用按钮/UI
    btn_click     = "audio/sfx/btn_click.ogg",
    btn_hover     = "audio/sfx/btn_hover.ogg",
    btn_disabled  = "audio/sfx/btn_disabled.ogg",
    toggle_on     = "audio/sfx/toggle_on.ogg",
    toggle_off    = "audio/sfx/toggle_off.ogg",
    slider_tick   = "audio/sfx/slider_tick.ogg",
    -- 主菜单
    menu_start    = "audio/sfx/sfx_menu_start.ogg",
    tab_switch    = "audio/sfx/sfx_tab_switch.ogg",
    checkin_reward = "audio/sfx/sfx_checkin_reward.ogg",
    task_claim    = "audio/sfx/sfx_task_claim.ogg",
    coin_land     = "audio/sfx/sfx_coin_land.ogg",
    -- 视觉特效配音
    sparkle       = "audio/sfx/sparkle.ogg",
    whoosh        = "audio/sfx/whoosh.ogg",
    pop           = "audio/sfx/pop.ogg",
    shimmer       = "audio/sfx/shimmer.ogg",
    chain_break   = "audio/sfx/chain_break.ogg",
    countdown_tick = "audio/sfx/countdown_tick.ogg",
    countdown_warn = "audio/sfx/countdown_warn.ogg",
    -- 渲染特效
    unlock_reveal = "audio/sfx/sfx_unlock_reveal.ogg",
    peg_burst     = "audio/sfx/sfx_peg_burst.ogg",
    fireworks     = "audio/sfx/sfx_fireworks.ogg",
    -- 反馈与成就
    achievement_unlock = "audio/sfx/achievement_unlock.ogg",
    new_record    = "audio/sfx/new_record.ogg",
    rank_up       = "audio/sfx/rank_up.ogg",
    coin_collect  = "audio/sfx/coin_collect.ogg",
    reward_chest  = "audio/sfx/reward_chest.ogg",
    -- 氛围/环境
    ambient_tick  = "audio/sfx/ambient_tick.ogg",
    chapter_transition = "audio/sfx/chapter_transition.ogg",
    loading_spin  = "audio/sfx/loading_spin.ogg",
}

-- BGM 路径映射
local BGM = {
    menu    = "audio/bgm/bgm_menu.ogg",       -- 主菜单BGM
    game    = "audio/bgm/bgm_game.ogg",       -- 游戏内BGM
}

-- 预加载的 Sound 资源缓存
local soundCache_  = {}
-- 是否已初始化
local initialized_ = false

-- 定时删除列表：{ node, remaining }
local pending_ = {}

-- 循环播放中的音效：key -> { node, source }
local looping_ = {}

-- BGM 状态
local bgmNode_    = nil  -- BGM 场景节点
local bgmSource_  = nil  -- BGM SoundSource
local bgmCurrent_ = nil  -- 当前播放的 BGM key
local bgmVolume_  = 0.4  -- BGM 默认音量（比音效低一些）

-- 内部音频 Scene（纯 NanoVG 项目没有全局 scene，需自建）
local audioScene_ = nil

-- ---------------------------------------------------------------
-- 初始化：预加载所有音效资源
-- ---------------------------------------------------------------
--- 获取可用的 scene（优先全局 scene，否则用内部 audioScene_）
local function getScene()
    if scene then return scene end
    if not audioScene_ then
        audioScene_ = Scene()
        --print("[SoundManager] 全局 scene 为 nil，已创建内部 audioScene")
    end
    return audioScene_
end

function SoundManager.Init()
    if initialized_ then return end

    for key, path in pairs(SOUNDS) do
        local snd = cache:GetResource("Sound", path)
        if snd then
            soundCache_[key] = snd
        else
            --print("[SoundManager] 警告：音效资源未找到 - " .. path)
        end
    end

    initialized_ = true
    local n = 0
    for _ in pairs(soundCache_) do n = n + 1 end
    --print("[SoundManager] 初始化完成，已加载 " .. n .. " 个音效")
end

-- ---------------------------------------------------------------
-- 播放音效（一次性）
--   key    : SOUNDS 表中的键名
--   volume : 音量 0.0~1.0，默认 1.0
-- ---------------------------------------------------------------
function SoundManager.Play(key, volume)
    if not initialized_ then SoundManager.Init() end

    local snd = soundCache_[key]
    if not snd then
        --print("[SoundManager] 音效不存在：" .. tostring(key))
        return
    end

    -- 每个音效创建独立的场景节点
    local node = getScene():CreateChild("_SFX_" .. key)
    local src  = node:CreateComponent("SoundSource")
    src.gain   = volume or 1.0
    src:Play(snd)

    --print("[SoundManager] ▶ SFX: " .. key .. " | vol=" .. string.format("%.2f", volume or 1.0) .. " | len=" .. string.format("%.2fs", snd.length))

    -- 按音效时长 + 0.1s 缓冲后删除节点
    local lifetime = (snd.length > 0) and (snd.length + 0.1) or 3.0
    pending_[#pending_ + 1] = { node = node, remaining = lifetime }
end

-- ---------------------------------------------------------------
-- 循环播放音效
--   key    : SOUNDS 表中的键名
--   volume : 音量 0.0~1.0，默认 1.0
-- 如果该 key 已在循环播放中，则不重复创建
-- ---------------------------------------------------------------
function SoundManager.PlayLoop(key, volume)
    if not initialized_ then SoundManager.Init() end
    if looping_[key] then return end -- 已在播放

    local snd = soundCache_[key]
    if not snd then
        --print("[SoundManager] 音效不存在：" .. tostring(key))
        return
    end

    snd.looped = true

    local node = getScene():CreateChild("_SFX_LOOP_" .. key)
    local src  = node:CreateComponent("SoundSource")
    src.gain   = volume or 1.0
    src:Play(snd)

    looping_[key] = { node = node, source = src }
    --print("[SoundManager] ▶ LOOP START: " .. key .. " | vol=" .. string.format("%.2f", volume or 1.0))
end

-- ---------------------------------------------------------------
-- 停止循环播放
--   key : 之前通过 PlayLoop 播放的键名
-- ---------------------------------------------------------------
function SoundManager.StopLoop(key)
    local entry = looping_[key]
    if not entry then return end

    entry.source:Stop()
    entry.node:Remove()
    looping_[key] = nil
    --print("[SoundManager] ■ LOOP STOP: " .. key)
end

-- ---------------------------------------------------------------
-- 停止所有循环音效
-- ---------------------------------------------------------------
function SoundManager.StopAllLoops()
    for key, entry in pairs(looping_) do
        entry.source:Stop()
        entry.node:Remove()
    end
    looping_ = {}
end

-- ---------------------------------------------------------------
-- 帧更新：倒计时删除已播放完毕的节点（在 main.lua HandleUpdate 中调用）
-- ---------------------------------------------------------------
function SoundManager.Update(dt)
    if #pending_ == 0 then return end
    local i = 1
    while i <= #pending_ do
        local p = pending_[i]
        p.remaining = p.remaining - dt
        if p.remaining <= 0 then
            p.node:Remove()
            table.remove(pending_, i)
        else
            i = i + 1
        end
    end
end

-- ---------------------------------------------------------------
-- BGM 播放
--   key    : BGM 表中的键名 ("menu" / "game")
--   volume : 音量 0.0~1.0，默认 0.4
-- 如果已经在播放同一首 BGM，则不重复切换
-- ---------------------------------------------------------------
function SoundManager.PlayBGM(key, volume)
    if not initialized_ then SoundManager.Init() end

    if bgmCurrent_ == key then
        --print("[SoundManager] BGM 已在播放中，跳过：" .. key)
        return
    end

    local path = BGM[key]
    if not path then
        --print("[SoundManager] ✘ BGM key 不存在：" .. tostring(key))
        return
    end

    local snd = cache:GetResource("Sound", path)
    if not snd then
        --print("[SoundManager] ✘ BGM 资源文件未找到：" .. path)
        return
    end
    snd.looped = true

    -- 停止旧 BGM
    if bgmCurrent_ then
        --print("[SoundManager] ■ BGM STOP: " .. bgmCurrent_ .. " → 切换到 " .. key)
    end
    SoundManager.StopBGM()

    -- 创建新 BGM 节点
    bgmNode_   = getScene():CreateChild("_BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = SOUND_MUSIC
    bgmSource_.gain = volume or bgmVolume_
    bgmSource_:Play(snd)
    bgmCurrent_ = key

    --print("[SoundManager] ▶ BGM START: " .. key .. " | vol=" .. string.format("%.2f", volume or bgmVolume_) .. " | len=" .. string.format("%.1fs", snd.length) .. " | looped=true")
end

-- ---------------------------------------------------------------
-- 停止 BGM
-- ---------------------------------------------------------------
function SoundManager.StopBGM()
    if bgmSource_ then
        bgmSource_:Stop()
    end
    if bgmNode_ then
        bgmNode_:Remove()
    end
    local was = bgmCurrent_
    bgmNode_   = nil
    bgmSource_ = nil
    bgmCurrent_ = nil
    if was then
        --print("[SoundManager] ■ BGM STOPPED: " .. was)
    end
end

-- ---------------------------------------------------------------
-- 设置 BGM 音量（不中断播放）
-- ---------------------------------------------------------------
function SoundManager.SetBGMVolume(volume)
    bgmVolume_ = volume
    if bgmSource_ then
        bgmSource_.gain = volume
    end
end

-- ---------------------------------------------------------------
-- 获取当前 BGM key（用于判断当前场景）
-- ---------------------------------------------------------------
function SoundManager.GetCurrentBGM()
    return bgmCurrent_
end

return SoundManager
