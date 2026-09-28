-- ============================================================================
-- WeaponConfig.lua - 武器配置模块
-- 从 demo/modules/Config.lua 适配而来
-- ============================================================================
--
-- 【散布参数单位说明】
-- crosshairSpreadMax      - 最大散布角度（度）
-- crosshairSpreadPerShot  - 每发增加的散布角度（度）
-- crosshairRecoverySpeed  - 每秒恢复的散布角度（度/秒）
-- spreadAngle             - 武器固有散布角度（度）
--
-- 【UI 与实际散布一致性】
-- 最大散布角度约 2.5° ≈ 画面高度的 5%（FOV=45° 时）
-- 公式: pixels = tan(angle) * (screenHeight / 2) / tan(FOV / 2)
--
-- ============================================================================

local M = {}

-- ============================================================================
-- 武器配置表
-- ============================================================================

M.WEAPONS = {
    -- G17 手枪（Glock 17）
    g17 = {
        name = "G17",
        nameZh = "G17手枪",
        
        magSize = 17,
        reserveAmmo = 68,
        reloadTime = 1.2,
        
        fireRate = 0.15,
        automatic = false,
        bulletsPerShot = 1,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 360.0,
        damage = 28,
        
        recoilPitchMin = 0.6,
        recoilPitchMax = 1.0,
        recoilYawMin = -0.15,
        recoilYawMax = 0.15,
        crosshairSpreadMax = 0.5,      -- 最大散布角度（度）≈ 画面高度 2.6%
        crosshairSpreadPerShot = 0.1,  -- 每发增加（度）
        crosshairRecoverySpeed = 0.25,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.008,
        cameraShakeDuration = 0.05,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://BDdeKZPkArL7L2_1HP4Ua_0Z",
            scale = Vector3(1.8, 1.8, 1.8),
            positionOffset = Vector3(-0.2, 0.07, -0.05),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0.03, -0.15),
            ejectionPortOffset = Vector3(0.03, 0.05, -0.08),
            ejectionFlipX = true,
            -- 第一人称瞄准参数（与 TP 手骨参数完全不同）
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, 0, 0.25),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
    
    -- AK74 突击步枪
    ak74 = {
        name = "AK74",
        nameZh = "AK74",
        
        magSize = 30,
        reserveAmmo = 120,
        reloadTime = 2.0,
        
        fireRate = 0.08,
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 400.0,
        damage = 32,
        
        recoilPitchMin = 0.4,
        recoilPitchMax = 0.8,
        recoilYawMin = -0.25,
        recoilYawMax = 0.25,
        crosshairSpreadMax = 0.8,      -- 最大散布角度（度）≈ 画面高度 3.4%
        crosshairSpreadPerShot = 0.2, -- 每发增加（度）
        crosshairRecoverySpeed = 0.65,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.008,
        cameraShakeDuration = 0.04,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://EmgN-bDI-KjXtWAc9BDeu9Tt",
            scale = Vector3(1.2, 1.2, 1.2),
            positionOffset = Vector3(-0.21, 0.1, -0.05),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0, -0.51),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.15),
            ejectionFlipX = true,
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, -0.02, 0.2),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
    
    -- M4 突击步枪
    m4 = {
        name = "M4",
        nameZh = "M4卡宾枪",
        
        magSize = 30,
        reserveAmmo = 120,
        reloadTime = 1.8,
        
        fireRate = 0.07,
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 440.0,
        damage = 28,
        
        recoilPitchMin = 0.3,
        recoilPitchMax = 0.6,
        recoilYawMin = -0.2,
        recoilYawMax = 0.2,
        crosshairSpreadMax = 0.8,      -- 最大散布角度（度）≈ 画面高度 3.4%
        crosshairSpreadPerShot = 0.2, -- 每发增加（度）
        crosshairRecoverySpeed = 0.6,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.007,
        cameraShakeDuration = 0.035,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://FNY8mT7gkY7SeMroH_XZdRCL",
            scale = Vector3(1.5, 1.5, 1.5),
            positionOffset = Vector3(-0.31, 0.04, -0.04),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0.07, -0.43),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.15),
            ejectionFlipX = true,
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, -0.102, 0.2),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
    
    -- MP5 冲锋枪
    mp5 = {
        name = "MP5",
        nameZh = "MP5冲锋枪",
        
        magSize = 30,
        reserveAmmo = 150,
        reloadTime = 1.5,
        
        fireRate = 0.06,
        automatic = true,
        bulletsPerShot = 1,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 320.0,
        damage = 22,
        
        recoilPitchMin = 0.2,
        recoilPitchMax = 0.4,
        recoilYawMin = -0.15,
        recoilYawMax = 0.15,
        crosshairSpreadMax = 1,      -- 最大散布角度（度）≈ 画面高度 3.4%
        crosshairSpreadPerShot = 0.2, -- 每发增加（度）
        crosshairRecoverySpeed = 0.7,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.006,
        cameraShakeDuration = 0.03,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://Bs3mEfXc81rueELfuWV-jt5R",
            scale = Vector3(1.3, 1.3, 1.3),
            positionOffset = Vector3(-0.18, 0.09, -0.03),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0.02, -0.36),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.12),
            ejectionFlipX = true,
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, -0.05, 0.2),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
    
    -- SKS 半自动步枪
    sks = {
        name = "SKS",
        nameZh = "SKS狙击枪",
        
        magSize = 10,
        reserveAmmo = 60,
        reloadTime = 2.2,
        
        fireRate = 0.7,
        automatic = false,
        bulletsPerShot = 1,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 500.0,
        damage = 55,
        
        recoilPitchMin = 1.0,
        recoilPitchMax = 1.5,
        recoilYawMin = -0.3,
        recoilYawMax = 0.3,
        crosshairSpreadMax = 0.05,      -- 最大散布角度（度）≈ 画面高度 3.4%
        crosshairSpreadPerShot = 0.01, -- 每发增加（度）
        crosshairRecoverySpeed = 0.035,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.015,
        cameraShakeDuration = 0.08,
        
        hasScope = true,
        scopeFov = 15,
        hideModelOnAds = true,
        scopeTransitionTime = 0.1,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://AHWkKYqnA_HJHZ-c9TxNGFOK",
            scale = Vector3(1.3, 1.3, 1.3),
            positionOffset = Vector3(-0.34, 0.1, -0.04),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0.02, -0.59),
            ejectionPortOffset = Vector3(0.04, 0.05, -0.18),
            ejectionFlipX = true,
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, -0.02, 0.2),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
    
    -- 短管霰弹枪
    sawed = {
        name = "Sawed-Off",
        nameZh = "短管霰弹枪",
        
        magSize = 2,
        reserveAmmo = 20,
        reloadTime = 1.8,
        
        fireRate = 0.5,
        automatic = false,
        bulletsPerShot = 12,
        spreadAngle = 0.01,            -- 固有散布（度）
        
        bulletSpeed = 280.0,
        damage = 18,
        
        headshotMaxRange = 4.0,
        falloffStartRange = 2.0,
        falloffEndRange = 10.0,
        minDamagePercent = 0.15,
        
        recoilPitchMin = 3.0,
        recoilPitchMax = 4.5,
        recoilYawMin = -1.0,
        recoilYawMax = 1.0,
        crosshairSpreadMax = 2.5,      -- 最大散布角度（度）≈ 画面高度 5%
        crosshairSpreadPerShot = 1.3,  -- 每发增加（度）
        crosshairRecoverySpeed = 0.7,  -- 恢复速度（度/秒）
        cameraShakeIntensity = 0.03,
        cameraShakeDuration = 0.15,
        
        model = {
            isPrefab = true,
            prefabPath = "uuid://DP5EqaxT1lC1c22CnsqhfwBK",
            scale = Vector3(2.55, 2.55, 2.55),
            positionOffset = Vector3(-0.38, 0.11, -0.05),
            rotationOffset = Quaternion(90, Vector3.UP),
            muzzleOffset = Vector3(0, 0, -0.26),
            ejectionPortOffset = Vector3(0.04, 0.04, -0.1),
            ejectionFlipX = true,
            casingScale = 1.5,
            fp = {
                scale = Vector3(1.2, 1.2, 1.2),
                positionOffset = Vector3(0, 0, 0.2),
                rotationOffset = Quaternion(180, Vector3.UP),
            },
        },
    },
}

-- 武器顺序（用于切换）
M.WEAPON_ORDER = { "g17", "ak74", "m4", "mp5", "sks", "sawed" }

-- 弹壳配置
M.CASING_CONFIG = {
    lifetime = 1.0,
    ejectionSpeed = 1.5,
    ejectionAngleUp = 45,
    ejectionAngleRight = 30,
    spinSpeed = 720,
    gravity = -15.0,
    baseRadius = 0.008,
    baseLength = 0.025,
    brassColor = Color(0.65, 0.45, 0.15, 1.0),
}

-- 射击相关配置
M.SHOOTING = {
    MaxShootDistance = 100.0,
    CrosshairRecoverySpeed = 1.5,  -- 默认恢复速度（度/秒）
    RecoilRecoverySpeed = 10.0,
    RecoilEaseSpeed = 25.0,
}

-- 第三人称武器显示配置
M.THIRD_PERSON_OVERRIDES = {
    default = {
        positionOffset = Vector3(0, 0, 0),
        rotationOffset = Quaternion(0, Vector3.UP),
        scaleMultiplier = 0.8,
    },
}

-- 手部骨骼名称
M.HAND_BONES = {
    "Bip001 R Hand",
    "Bip01 R Hand", 
    "R Hand",
    "RightHand",
    "hand_R",
}

return M
