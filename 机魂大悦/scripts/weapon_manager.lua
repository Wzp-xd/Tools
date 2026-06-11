-- ============================================================================
-- 装备管理器 - 武器装卸 & 配置持久化
-- Weapon Manager - Loadout management and weapon equip/unequip
-- ============================================================================

local Weapons = require "weapons"
local WeaponDefs = require "weapon_defs"
local WeaponVisuals = require "weapon_visuals"
local CONFIG = require "config"

local WeaponManager = {}

-- ============================================================================
-- 当前装备配置（运行时）
-- ============================================================================

---@type table<string, string> 当前装备 { handL = "machinegun", handR = "rpg", shoulderR = "missile" }
local currentLoadout_ = nil

--- 获取默认装备配置（从 config.lua）
---@return table<string, string>
local function GetDefaultLoadout()
    return {
        handL     = CONFIG.DefaultLoadout.handL,
        handR     = CONFIG.DefaultLoadout.handR,
        shoulderL = CONFIG.DefaultLoadout.shoulderL,
        shoulderR = CONFIG.DefaultLoadout.shoulderR,
    }
end

--- 初始化装备管理器（游戏启动时调用一次）
function WeaponManager.Init()
    if not currentLoadout_ then
        currentLoadout_ = GetDefaultLoadout()
    end
end

--- 获取当前装备配置的副本
---@return table<string, string>
function WeaponManager.GetLoadout()
    if not currentLoadout_ then
        currentLoadout_ = GetDefaultLoadout()
    end
    return {
        handL     = currentLoadout_.handL,
        handR     = currentLoadout_.handR,
        shoulderL = currentLoadout_.shoulderL,
        shoulderR = currentLoadout_.shoulderR,
    }
end

--- 设置某个槽位的武器
---@param slot string "handL"|"handR"|"shoulderR"
---@param weaponType string 武器类型 ID
---@return boolean 是否成功
function WeaponManager.SetSlotWeapon(slot, weaponType)
    if not WeaponDefs.CanEquipToSlot(weaponType, slot) then
        print(string.format("[WeaponManager] Cannot equip '%s' to slot '%s'", weaponType, slot))
        return false
    end
    if not currentLoadout_ then
        currentLoadout_ = GetDefaultLoadout()
    end
    currentLoadout_[slot] = weaponType
    return true
end

--- 获取某个槽位当前装备的武器类型
---@param slot string
---@return string
function WeaponManager.GetSlotWeapon(slot)
    if not currentLoadout_ then
        currentLoadout_ = GetDefaultLoadout()
    end
    return currentLoadout_[slot]
end

-- ============================================================================
-- 武器实例化（为机甲创建武器）
-- ============================================================================

--- 为玩家机甲创建所有武器实例
---@param mechJoints table 机甲关节（含 weaponMountHandL/HandR/ShoulderR）
---@param owner string|nil "player"（默认）或 "enemy"
---@return table playerWeapons { handL = weapon, handR = weapon, shoulderR = weapon }
function WeaponManager.CreateWeapons(mechJoints, owner)
    if not currentLoadout_ then
        currentLoadout_ = GetDefaultLoadout()
    end

    local weapons = {}

    -- 左手
    if mechJoints.weaponMountHandL and currentLoadout_.handL then
        weapons.handL = Weapons.CreateWeapon(currentLoadout_.handL, mechJoints.weaponMountHandL, owner)
    end

    -- 右手
    if mechJoints.weaponMountHandR and currentLoadout_.handR then
        weapons.handR = Weapons.CreateWeapon(currentLoadout_.handR, mechJoints.weaponMountHandR, owner)
    end

    -- 左肩
    if mechJoints.weaponMountShoulderL and currentLoadout_.shoulderL then
        weapons.shoulderL = Weapons.CreateWeapon(currentLoadout_.shoulderL, mechJoints.weaponMountShoulderL, owner)
    end

    -- 右肩
    if mechJoints.weaponMountShoulderR and currentLoadout_.shoulderR then
        weapons.shoulderR = Weapons.CreateWeapon(currentLoadout_.shoulderR, mechJoints.weaponMountShoulderR, owner)
    end

    return weapons
end

--- 为指定装备配置创建武器实例（用于 AI / 自定义配置）
---@param loadout table { handL, handR, shoulderR }
---@param mechJoints table
---@param owner string|nil
---@return table weapons
function WeaponManager.CreateWeaponsFromLoadout(loadout, mechJoints, owner)
    local weapons = {}

    if mechJoints.weaponMountHandL and loadout.handL then
        weapons.handL = Weapons.CreateWeapon(loadout.handL, mechJoints.weaponMountHandL, owner)
    end

    if mechJoints.weaponMountHandR and loadout.handR then
        weapons.handR = Weapons.CreateWeapon(loadout.handR, mechJoints.weaponMountHandR, owner)
    end

    if mechJoints.weaponMountShoulderL and loadout.shoulderL then
        weapons.shoulderL = Weapons.CreateWeapon(loadout.shoulderL, mechJoints.weaponMountShoulderL, owner)
    end

    if mechJoints.weaponMountShoulderR and loadout.shoulderR then
        weapons.shoulderR = Weapons.CreateWeapon(loadout.shoulderR, mechJoints.weaponMountShoulderR, owner)
    end

    return weapons
end

--- 批量更新所有武器的 Reload / Burst / MuzzleFlash
---@param weapons table { handL, handR, shoulderR }
---@param dt number
function WeaponManager.UpdateAllWeapons(weapons, dt)
    if not weapons then return end
    for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
        local w = weapons[slot]
        if w then
            Weapons.UpdateReload(w, dt)
            Weapons.UpdateBurst(w, dt)
            Weapons.UpdateMuzzleFlash(w, dt)
        end
    end
end

--- 手动换弹所有非满弹武器
---@param weapons table { handL, handR, shoulderR }
function WeaponManager.ReloadAll(weapons)
    if not weapons then return end
    for _, slot in ipairs(WeaponDefs.SLOT_ORDER) do
        local w = weapons[slot]
        if w and not w.reloading and w.ammo < w.magazineSize then
            w.reloading = true
            w.reloadTimer = w.reloadTime
            w.burstRemaining = 0
            w.burstParams = nil
        end
    end
end

return WeaponManager
