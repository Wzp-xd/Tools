-- ============================================================================
-- 音效配置表 - Sound Configuration
-- 所有 BGM 和音效的路径、音量、类型集中管理
-- ============================================================================

local SoundConfig = {}

-- ============================================================================
-- 全局开关
-- ============================================================================
SoundConfig.weaponSFXEnabled = false  -- 武器音效总开关（true=开启, false=关闭）
SoundConfig.allSFXEnabled = false     -- 全部音效总开关（true=开启, false=关闭），仅保留BGM

-- ============================================================================
-- BGM 配置
-- ============================================================================
SoundConfig.BGM = {
    menu = {
        path = "audio/bgm_menu.ogg",
        gain = 0.5,
        name = "Iron Requiem",
    },
    battle1 = {
        path = "audio/bgm_battle1.ogg",
        gain = 0.5,
        name = "Battle Zone Alpha",
    },
    battle2 = {
        path = "audio/bgm_battle2.ogg",
        gain = 0.5,
        name = "Steel Thunder",
    },
    battle3 = {
        path = "audio/bgm_battle3.ogg",
        gain = 0.5,
        name = "Chrome Cathedral",
    },
}

-- 战斗BGM列表（随机选择用）
SoundConfig.BattleBGMKeys = { "battle1", "battle2", "battle3" }

-- ============================================================================
-- 音效配置
-- ============================================================================
SoundConfig.SFX = {
    -- UI
    ui_click         = { path = "audio/sfx/ui_click.ogg",         gain = 0.6 },

    -- 左手武器
    machinegun_fire  = { path = "audio/sfx/machinegun_fire.ogg",  gain = 0.4 },
    shotgun_fire     = { path = "audio/sfx/shotgun_fire.ogg",     gain = 0.5 },
    pistol_fire      = { path = "audio/sfx/pistol_fire.ogg",      gain = 0.5 },

    -- 右手武器
    rpg_fire         = { path = "audio/sfx/rpg_fire.ogg",         gain = 0.6 },
    rpg_explosion    = { path = "audio/sfx/rpg_explosion.ogg",    gain = 0.7 },
    shield_activate  = { path = "audio/sfx/shield_activate.ogg",  gain = 0.5 },
    homing_fire      = { path = "audio/sfx/homing_fire.ogg",      gain = 0.5 },

    -- 肩部武器
    missile_launch   = { path = "audio/sfx/missile_launch.ogg",   gain = 0.6 },
    missile_explosion= { path = "audio/sfx/missile_explosion.ogg",gain = 0.7 },
    railgun_charge   = { path = "audio/sfx/railgun_charge.ogg",   gain = 0.5 },
    railgun_fire     = { path = "audio/sfx/railgun_fire.ogg",     gain = 0.8 },
    grenade_launch   = { path = "audio/sfx/grenade_launch.ogg",   gain = 0.5 },

    -- 机体动作
    mech_step        = { path = "audio/sfx/mech_step.ogg",        gain = 0.3 },
    boost_jet        = { path = "audio/sfx/boost_jet.ogg",        gain = 0.5 },
    death_explosion  = { path = "audio/sfx/death_explosion.ogg",  gain = 0.8 },
}

-- ============================================================================
-- 武器名 → 音效映射（weapon_defs 中的 key 对应 SFX key）
-- ============================================================================
SoundConfig.WeaponFireSFX = {
    machinegun          = "machinegun_fire",
    shotgun             = "shotgun_fire",
    pistol              = "pistol_fire",
    rpg                 = "rpg_fire",
    shield              = "shield_activate",
    homing_handgun      = "homing_fire",
    missile             = "missile_launch",
    vertical_missile    = "missile_launch",
    shoulder_rpg        = "rpg_fire",
    railgun             = "railgun_fire",
    explosive_launcher  = "grenade_launch",
    melee_mg            = "machinegun_fire",
    melee_smg           = "machinegun_fire",
}

-- 爆炸类武器的爆炸音效
SoundConfig.WeaponExplosionSFX = {
    rpg                 = "rpg_explosion",
    shoulder_rpg        = "rpg_explosion",
    missile             = "missile_explosion",
    vertical_missile    = "missile_explosion",
    explosive_launcher  = "rpg_explosion",
}

return SoundConfig
