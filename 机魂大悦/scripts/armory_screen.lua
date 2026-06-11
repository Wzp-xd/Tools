-- ============================================================================
-- 整备机体界面 - 武器装备选择
-- Armory Screen - Weapon loadout configuration
-- ============================================================================

local WeaponDefs = require "weapon_defs"
local WeaponManager = require "weapon_manager"
local CONFIG = require "config"

local Armory = {}

---@type Widget|nil
local rootWidget_ = nil
---@type table|nil UI 模块引用
local UI_ = nil
---@type function|nil 返回回调
local onBack_ = nil

-- 当前选中的槽位和武器（用于详情面板）
local selectedSlot_ = "handL"
local selectedWeapon_ = nil

-- 界面模式："weapons" 武器装备 / "chassis" 机体选择
local screenMode_ = "weapons"

-- ============================================================================
-- 自适应布局参数
-- ============================================================================

--- 获取当前屏幕逻辑尺寸和布局参数
---@return table layout 布局参数
local function GetLayout()
    local dpr = graphics:GetDPR()
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    local isPortrait = h > w
    local isNarrow = w < 600  -- 逻辑宽度小于600视为窄屏

    return {
        isPortrait = isPortrait,
        isNarrow = isNarrow,
        screenW = w,
        screenH = h,
        -- 字体缩放
        titleSize = isNarrow and 17 or 20,
        subtitleSize = isNarrow and 10 or 11,
        labelSize = isNarrow and 13 or 15,
        detailTitleSize = isNarrow and 18 or 22,
        detailLabelSize = isNarrow and 12 or 14,
        statLabelSize = isNarrow and 11 or 13,
        -- 间距
        paddingH = isNarrow and 8 or 16,
        tabHeight = isNarrow and 38 or 44,
        itemHeight = isNarrow and 40 or 48,
        -- 内容区布局
        contentDir = (isPortrait or isNarrow) and "column" or "row",
        listWidth = (isPortrait or isNarrow) and "100%" or "35%",
        listMaxHeight = (isPortrait or isNarrow) and "40%" or nil,
    }
end

-- ============================================================================
-- 颜色主题
-- ============================================================================

local COLORS = {
    bg = { 12, 14, 25, 248 },
    panelBg = { 20, 24, 40, 240 },
    panelBorder = { 60, 80, 140, 150 },
    slotActive = { 50, 100, 200, 230 },
    slotInactive = { 35, 40, 60, 220 },
    weaponSelected = { 40, 80, 160, 200 },
    weaponHover = { 45, 55, 80, 220 },
    weaponNormal = { 30, 35, 55, 200 },
    textTitle = { 100, 200, 255, 255 },
    textNormal = { 200, 210, 230, 220 },
    textDim = { 140, 150, 170, 180 },
    textAccent = { 80, 180, 255, 255 },
    equipped = { 60, 200, 120, 255 },
    statBar = { 60, 140, 255, 200 },
    statBarBg = { 30, 35, 55, 150 },
}

-- ============================================================================
-- 性能数据可视化
-- ============================================================================

--- 创建性能条
---@param label string
---@param value number 0~100
---@param layout table|nil 布局参数
---@return Widget
local function CreateStatBar(label, value, layout)
    local L = layout or GetLayout()
    local pct = math.min(100, math.max(0, value))
    return UI_.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        height = L.isNarrow and 24 or 28,
        gap = L.isNarrow and 4 or 8,
        children = {
            UI_.Label {
                text = label,
                fontSize = L.statLabelSize,
                fontColor = COLORS.textDim,
                width = L.isNarrow and 44 or 56,
            },
            UI_.Panel {
                flex = 1,
                height = L.isNarrow and 6 or 8,
                backgroundColor = COLORS.statBarBg,
                borderRadius = 4,
                overflow = "hidden",
                children = {
                    UI_.Panel {
                        width = pct .. "%",
                        height = "100%",
                        backgroundColor = COLORS.statBar,
                        borderRadius = 4,
                    },
                },
            },
            UI_.Label {
                text = tostring(math.floor(pct)),
                fontSize = L.isNarrow and 10 or 12,
                fontColor = COLORS.textDim,
                width = L.isNarrow and 22 or 28,
                textAlign = "right",
            },
        },
    }
end

-- ============================================================================
-- 武器详情面板
-- ============================================================================

--- 创建武器详情面板（内联式，嵌入列表中）
---@param weaponType string|nil
---@return Widget|nil
local function CreateWeaponDetail(weaponType)
    if not weaponType then return nil end

    local def = WeaponDefs.Get(weaponType)
    if not def then return nil end

    local stats = def.stats or {}

    -- 计算性能条数值（基于策划数据归一化到 0-100）
    local dpsNorm = math.min(100, (stats.dps or 0) / 1.0)
    local rangeVal = 0
    if stats.range then
        local num = tonumber(stats.range:match("%d+"))
        rangeVal = num and math.min(100, num / 10) or 0
    end
    local accVal = 0
    local accText = stats.accuracy or ""
    if accText == "完美" or accText == "自动追踪" then accVal = 100
    elseif accText == "高" then accVal = 80
    elseif accText == "中等" then accVal = 55
    elseif accText == "低" then accVal = 30
    end

    local detailChildren = {}

    -- 武器名称
    table.insert(detailChildren, UI_.Label {
        text = (def.nameZH or def.name) .. "  " .. (stats.type or ""),
        fontSize = 16,
        fontWeight = "bold",
        fontColor = COLORS.textTitle,
        marginBottom = 6,
    })

    -- 性能条
    table.insert(detailChildren, CreateStatBar("DPS", dpsNorm))
    table.insert(detailChildren, CreateStatBar("射程", rangeVal))
    table.insert(detailChildren, CreateStatBar("精度", accVal))

    -- 描述
    if def.description then
        table.insert(detailChildren, UI_.Label {
            text = def.description,
            fontSize = 13,
            fontColor = COLORS.textNormal,
            marginTop = 8,
        })
    end

    -- 操作说明
    if def.usage then
        table.insert(detailChildren, UI_.Label {
            text = "操作: " .. def.usage,
            fontSize = 12,
            fontColor = COLORS.textAccent,
            marginTop = 4,
        })
    end

    return UI_.Panel {
        width = "100%",
        flexDirection = "column",
        paddingAll = 14,
        marginTop = 4,
        marginBottom = 4,
        backgroundColor = { 25, 35, 60, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 100, 180, 150 },
        children = detailChildren,
    }
end

-- ============================================================================
-- 武器列表项
-- ============================================================================

--- 创建武器选择项
---@param weaponType string
---@param slot string
---@param isEquipped boolean
---@return Widget
local function CreateWeaponItem(weaponType, slot, isEquipped)
    local def = WeaponDefs.Get(weaponType)
    if not def then return UI_.Panel {} end

    local isSelected = (selectedWeapon_ == weaponType)
    local bgColor = isSelected and COLORS.weaponSelected
        or (isEquipped and { 35, 60, 45, 220 } or COLORS.weaponNormal)

    return UI_.Button {
        width = "100%",
        minHeight = 64,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 16,
        paddingRight = 16,
        paddingTop = 10,
        paddingBottom = 10,
        backgroundColor = bgColor,
        hoverBackgroundColor = COLORS.weaponHover,
        borderRadius = 8,
        borderWidth = isEquipped and 2 or 0,
        borderColor = COLORS.equipped,
        onClick = function(self)
            selectedWeapon_ = weaponType
            -- 装备该武器
            WeaponManager.SetSlotWeapon(slot, weaponType)
            -- 重建界面刷新状态
            Armory.Refresh()
        end,
        children = {
            -- 武器名称
            UI_.Panel {
                flex = 1,
                flexShrink = 1,
                flexDirection = "column",
                gap = 3,
                children = {
                    UI_.Label {
                        text = def.nameZH or def.name,
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = isEquipped and COLORS.equipped or COLORS.textNormal,
                    },
                    UI_.Label {
                        text = string.format("DPS:%s  %s", def.stats and def.stats.dps or "?", def.stats and def.stats.range or ""),
                        fontSize = 12,
                        fontColor = COLORS.textDim,
                    },
                },
            },
            -- 装备标记
            isEquipped and UI_.Label {
                text = "已装备",
                fontSize = 12,
                fontColor = COLORS.equipped,
            } or nil,
        },
    }
end

-- ============================================================================
-- 槽位标签
-- ============================================================================

--- 创建槽位选择标签
---@param slot string
---@param label string
---@param layout table 布局参数
---@return Widget
local function CreateSlotTab(slot, label, layout)
    local L = layout
    local isActive = (selectedSlot_ == slot)
    return UI_.Button {
        text = label,
        fontSize = L.labelSize,
        fontWeight = isActive and "bold" or "normal",
        flex = 1,
        height = L.tabHeight,
        backgroundColor = isActive and COLORS.slotActive or COLORS.slotInactive,
        textColor = isActive and { 255, 255, 255, 255 } or COLORS.textDim,
        hoverBackgroundColor = isActive and COLORS.slotActive or { 45, 55, 80, 230 },
        borderRadius = 8,
        onClick = function(self)
            selectedSlot_ = slot
            selectedWeapon_ = WeaponManager.GetSlotWeapon(slot)
            Armory.Refresh()
        end,
    }
end

-- ============================================================================
-- 机体型号 UI
-- ============================================================================

--- 属性显示名映射
local STAT_LABELS = {
    { key = "hp",             label = "生命值" },
    { key = "maxEnergy",      label = "能量上限" },
    { key = "energyRegen",    label = "能量恢复" },
    { key = "moveForce",      label = "地面推力" },
    { key = "maxSpeed",       label = "最大速度" },
    { key = "jumpSpeed",      label = "跳跃能力" },
    { key = "boostForce",     label = "推进力" },
    { key = "boostCost",      label = "推进耗能" },
    { key = "dashImpulse",    label = "冲刺力度" },
    { key = "dashDuration",   label = "冲刺时长" },
    { key = "dashEnergyCost", label = "冲刺耗能" },
    { key = "jetForce",       label = "喷射推力" },
    { key = "jetMaxSpeed",    label = "喷射极速" },
    { key = "jetCost",        label = "喷射耗能" },
    { key = "jetDashImpulse", label = "喷射冲刺" },
}

--- 判断乘数是消耗型（数值越低越好）
local COST_KEYS = { boostCost = true, dashEnergyCost = true, jetCost = true }

--- 创建属性对比行
---@param label string
---@param multiplier number
---@param isCost boolean 是否为消耗型（低=好）
---@param layout table|nil 布局参数
local function CreateStatRow(label, multiplier, isCost, layout)
    local L = layout or GetLayout()
    local diff = multiplier - 1.0
    local text, color
    if math.abs(diff) < 0.01 then
        text = "—"
        color = COLORS.textDim
    else
        local isGood = isCost and (diff < 0) or (not isCost and diff > 0)
        local arrow = diff > 0 and "↑" or "↓"
        text = string.format("%s%.0f%%", arrow, math.abs(diff) * 100)
        color = isGood and { 80, 230, 140, 255 } or { 255, 100, 90, 255 }
    end

    return UI_.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        height = L.isNarrow and 24 or 28,
        children = {
            UI_.Label {
                text = label,
                fontSize = L.statLabelSize,
                fontColor = COLORS.textDim,
                width = L.isNarrow and 56 or 70,
            },
            -- 条形图背景
            UI_.Panel {
                flex = 1,
                height = L.isNarrow and 6 or 8,
                backgroundColor = COLORS.statBarBg,
                borderRadius = 4,
                overflow = "hidden",
                children = {
                    UI_.Panel {
                        width = math.floor(math.min(100, multiplier * 50)) .. "%",
                        height = "100%",
                        backgroundColor = color,
                        borderRadius = 4,
                    },
                },
            },
            UI_.Label {
                text = text,
                fontSize = L.statLabelSize,
                fontColor = color,
                width = L.isNarrow and 40 or 50,
                textAlign = "right",
            },
        },
    }
end

--- 创建机体型号卡片
---@param variantId string "A"/"B"/"C"/"D"
---@return Widget
local function CreateChassisCard(variantId)
    local v = CONFIG.MechVariants[variantId]
    if not v then return UI_.Panel {} end

    local isSelected = (CONFIG.SelectedVariant == variantId)
    local vColor = v.color or { 200, 200, 200 }
    local bgColor = isSelected and { vColor[1] * 0.2, vColor[2] * 0.2, vColor[3] * 0.2, 220 }
        or COLORS.weaponNormal

    return UI_.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingAll = 14,
        gap = 12,
        minHeight = 68,
        backgroundColor = bgColor,
        hoverBackgroundColor = COLORS.weaponHover,
        borderRadius = 10,
        borderWidth = isSelected and 2 or 0,
        borderColor = { vColor[1], vColor[2], vColor[3], 200 },
        onClick = function(self)
            CONFIG.SelectedVariant = variantId
            Armory.Refresh()
        end,
        children = {
            -- 型号代号圆圈
            UI_.Panel {
                width = 44, height = 44,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { vColor[1], vColor[2], vColor[3], isSelected and 200 or 80 },
                borderRadius = 22,
                children = {
                    UI_.Label {
                        text = variantId,
                        fontSize = 22,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                        textAlign = "center",
                    },
                },
            },
            -- 名称 + 简介
            UI_.Panel {
                flex = 1,
                flexShrink = 1,
                flexDirection = "column",
                gap = 3,
                children = {
                    UI_.Label {
                        text = v.name,
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = isSelected and { vColor[1], vColor[2], vColor[3], 255 } or COLORS.textNormal,
                    },
                    UI_.Label {
                        text = v.desc,
                        fontSize = 12,
                        fontColor = COLORS.textDim,
                    },
                },
            },
            -- 已选择标记
            isSelected and UI_.Label {
                text = "已选择",
                fontSize = 12,
                fontColor = COLORS.equipped,
            } or nil,
        },
    }
end

--- 创建机体详情面板（内联式，嵌入列表中）
---@param variantId string
---@param layout table|nil 布局参数
---@return Widget|nil
local function CreateChassisDetail(variantId, layout)
    local L = layout or GetLayout()
    local v = CONFIG.MechVariants[variantId]
    if not v then return nil end

    local vColor = v.color or { 200, 200, 200 }

    local rows = {}
    -- 标题
    table.insert(rows, UI_.Label {
        text = v.name .. "  性能参数",
        fontSize = L.labelSize + 1, fontWeight = "bold",
        fontColor = { vColor[1], vColor[2], vColor[3], 255 },
        marginBottom = L.isNarrow and 4 or 6,
    })

    -- 属性对比行
    for _, entry in ipairs(STAT_LABELS) do
        local mul = v[entry.key] or 1.0
        table.insert(rows, CreateStatRow(entry.label, mul, COST_KEYS[entry.key] or false, L))
    end

    return UI_.Panel {
        width = "100%",
        flexDirection = "column",
        paddingAll = L.isNarrow and 10 or 14,
        marginTop = 4,
        marginBottom = 4,
        backgroundColor = { 25, 35, 60, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { vColor[1] * 0.5, vColor[2] * 0.5, vColor[3] * 0.5, 150 },
        children = rows,
    }
end

-- ============================================================================
-- 主界面构建
-- ============================================================================

--- 创建模式切换标签
---@param mode string "weapons"/"chassis"
---@param label string
---@param layout table 布局参数
---@return Widget
local function CreateModeTab(mode, label, layout)
    local L = layout
    local isActive = (screenMode_ == mode)
    return UI_.Button {
        text = label,
        fontSize = L.labelSize,
        fontWeight = isActive and "bold" or "normal",
        flex = 1,
        height = L.tabHeight,
        backgroundColor = isActive and COLORS.slotActive or { 25, 30, 50, 220 },
        textColor = isActive and { 255, 255, 255, 255 } or COLORS.textDim,
        hoverBackgroundColor = isActive and COLORS.slotActive or { 40, 50, 70, 230 },
        borderRadius = 8,
        onClick = function(self)
            screenMode_ = mode
            Armory.Refresh()
        end,
    }
end

--- 创建左侧武器名字列表项（紧凑，仅显示名字和装备状态）
---@param weaponType string
---@param slot string
---@param isEquipped boolean
---@param layout table 布局参数
---@return Widget
local function CreateWeaponListItem(weaponType, slot, isEquipped, layout)
    local L = layout
    local def = WeaponDefs.Get(weaponType)
    if not def then return UI_.Panel {} end

    local isSelected = (selectedWeapon_ == weaponType)
    local bgColor = isSelected and COLORS.weaponSelected
        or (isEquipped and { 35, 60, 45, 220 } or COLORS.weaponNormal)

    return UI_.Button {
        width = "100%",
        height = L.itemHeight,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = L.isNarrow and 10 or 14,
        paddingRight = L.isNarrow and 10 or 14,
        backgroundColor = bgColor,
        hoverBackgroundColor = COLORS.weaponHover,
        borderRadius = 8,
        borderWidth = isSelected and 2 or (isEquipped and 1 or 0),
        borderColor = isSelected and COLORS.textAccent or COLORS.equipped,
        onClick = function(self)
            selectedWeapon_ = weaponType
            -- 点击即装备
            WeaponManager.SetSlotWeapon(slot, weaponType)
            Armory.Refresh()
        end,
        children = {
            UI_.Label {
                text = def.nameZH or def.name,
                fontSize = L.labelSize,
                fontWeight = (isSelected or isEquipped) and "bold" or "normal",
                fontColor = isEquipped and COLORS.equipped or COLORS.textNormal,
                flex = 1,
                flexShrink = 1,
            },
            isEquipped and UI_.Label {
                text = "✓",
                fontSize = L.isNarrow and 12 or 14,
                fontColor = COLORS.equipped,
            } or nil,
        },
    }
end

--- 创建右侧武器详情面板
---@param weaponType string|nil
---@param slot string
---@param layout table 布局参数
---@return Widget
local function CreateWeaponDetailPanel(weaponType, slot, layout)
    local L = layout
    if not weaponType then
        return UI_.Panel {
            flex = 1,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI_.Label {
                    text = "选择一个武器查看详情",
                    fontSize = L.detailLabelSize,
                    fontColor = COLORS.textDim,
                },
            },
        }
    end

    local def = WeaponDefs.Get(weaponType)
    if not def then return UI_.Panel { flex = 1 } end

    local stats = def.stats or {}
    local equippedWeapon = WeaponManager.GetSlotWeapon(slot)
    local isEquipped = (weaponType == equippedWeapon)

    -- 计算性能条数值
    local dpsNorm = math.min(100, (stats.dps or 0) / 1.0)
    local rangeVal = 0
    if stats.range then
        local num = tonumber(stats.range:match("%d+"))
        rangeVal = num and math.min(100, num / 10) or 0
    end
    local accVal = 0
    local accText = stats.accuracy or ""
    if accText == "完美" or accText == "自动追踪" then accVal = 100
    elseif accText == "高" then accVal = 80
    elseif accText == "中等" then accVal = 55
    elseif accText == "低" then accVal = 30
    end

    local detailChildren = {}

    -- 武器名称 + 类型
    table.insert(detailChildren, UI_.Label {
        text = (def.nameZH or def.name),
        fontSize = L.detailTitleSize,
        fontWeight = "bold",
        fontColor = COLORS.textTitle,
        marginBottom = 4,
    })

    if stats.type then
        table.insert(detailChildren, UI_.Label {
            text = stats.type,
            fontSize = L.statLabelSize,
            fontColor = COLORS.textAccent,
            marginBottom = L.isNarrow and 8 or 12,
        })
    end

    -- 性能条
    table.insert(detailChildren, CreateStatBar("DPS", dpsNorm, L))
    table.insert(detailChildren, CreateStatBar("射程", rangeVal, L))
    table.insert(detailChildren, CreateStatBar("精度", accVal, L))

    -- 描述
    if def.description then
        table.insert(detailChildren, UI_.Label {
            text = def.description,
            fontSize = L.detailLabelSize,
            fontColor = COLORS.textNormal,
            marginTop = L.isNarrow and 8 or 12,
        })
    end

    -- 操作说明
    if def.usage then
        table.insert(detailChildren, UI_.Label {
            text = "操作: " .. def.usage,
            fontSize = L.statLabelSize,
            fontColor = COLORS.textAccent,
            marginTop = L.isNarrow and 4 or 6,
        })
    end

    -- 已装备状态提示
    local hintText = isEquipped and "已装备"
        or (L.isPortrait and "点击列表选择武器即可装备" or "点击左侧列表选择武器即可装备")
    table.insert(detailChildren, UI_.Panel {
        width = "100%",
        height = L.isNarrow and 32 or 40,
        marginTop = L.isNarrow and 10 or 16,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = isEquipped and { 35, 60, 45, 220 } or { 30, 35, 55, 150 },
        borderRadius = 8,
        borderWidth = isEquipped and 1 or 0,
        borderColor = COLORS.equipped,
        children = {
            UI_.Label {
                text = hintText,
                fontSize = L.detailLabelSize,
                fontColor = isEquipped and COLORS.equipped or COLORS.textDim,
            },
        },
    })

    return UI_.Panel {
        flex = 1,
        flexDirection = "column",
        paddingAll = L.isNarrow and 12 or 18,
        overflow = "scroll",
        children = detailChildren,
    }
end

--- 构建武器模式内容（自适应：横屏左右分栏，竖屏上下分栏）
---@param layout table 布局参数
local function BuildWeaponsContent(layout)
    local L = layout
    local options = WeaponDefs.GetSlotOptions(selectedSlot_)
    local equippedWeapon = WeaponManager.GetSlotWeapon(selectedSlot_)
    if not selectedWeapon_ then
        selectedWeapon_ = equippedWeapon
    end

    -- 武器名字列表
    local listChildren = {}
    for _, wType in ipairs(options) do
        table.insert(listChildren, CreateWeaponListItem(wType, selectedSlot_, wType == equippedWeapon, L))
    end

    -- 列表面板属性
    local listPanel = {
        flexDirection = "column",
        gap = L.isNarrow and 3 or 4,
        paddingAll = L.isNarrow and 6 or 10,
        overflow = "scroll",
        backgroundColor = { 15, 18, 32, 240 },
        children = listChildren,
    }
    -- 横屏：固定宽度 + 右边框；竖屏：限制最大高度
    if L.contentDir == "row" then
        listPanel.width = L.listWidth
        listPanel.borderRightWidth = 1
        listPanel.borderColor = COLORS.panelBorder
    else
        listPanel.width = "100%"
        listPanel.maxHeight = L.listMaxHeight
        listPanel.borderBottomWidth = 1
        listPanel.borderColor = COLORS.panelBorder
    end

    return {
        -- 武器槽位标签
        UI_.Panel {
            width = "100%",
            height = L.isNarrow and 44 or 52,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = L.isNarrow and 6 or 10,
            paddingLeft = L.paddingH, paddingRight = L.paddingH,
            paddingTop = 4, paddingBottom = 4,
            children = {
                CreateSlotTab("handL", "左手", L),
                CreateSlotTab("handR", "右手", L),
                CreateSlotTab("shoulderL", "左肩", L),
                CreateSlotTab("shoulderR", "右肩", L),
            },
        },
        -- 自适应分栏
        UI_.Panel {
            flex = 1,
            flexDirection = L.contentDir,
            gap = 2,
            children = {
                -- 列表区
                UI_.Panel(listPanel),
                -- 详情区
                UI_.Panel {
                    flex = 1,
                    flexDirection = "column",
                    backgroundColor = COLORS.panelBg,
                    children = {
                        CreateWeaponDetailPanel(selectedWeapon_, selectedSlot_, L),
                    },
                },
            },
        },
    }
end

--- 创建左侧机体名字列表项
---@param variantId string
---@param layout table 布局参数
---@return Widget
local function CreateChassisListItem(variantId, layout)
    local L = layout
    local v = CONFIG.MechVariants[variantId]
    if not v then return UI_.Panel {} end

    local isSelected = (CONFIG.SelectedVariant == variantId)
    local vColor = v.color or { 200, 200, 200 }
    local bgColor = isSelected and { vColor[1] * 0.25, vColor[2] * 0.25, vColor[3] * 0.25, 230 }
        or COLORS.weaponNormal
    local circleSize = L.isNarrow and 22 or 28

    return UI_.Button {
        width = "100%",
        height = L.itemHeight,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = L.isNarrow and 10 or 14,
        paddingRight = L.isNarrow and 10 or 14,
        backgroundColor = bgColor,
        hoverBackgroundColor = COLORS.weaponHover,
        borderRadius = 8,
        borderWidth = isSelected and 2 or 0,
        borderColor = { vColor[1], vColor[2], vColor[3], 200 },
        onClick = function(self)
            CONFIG.SelectedVariant = variantId
            Armory.Refresh()
        end,
        children = {
            -- 型号代号
            UI_.Panel {
                width = circleSize, height = circleSize,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { vColor[1], vColor[2], vColor[3], isSelected and 180 or 60 },
                borderRadius = math.floor(circleSize / 2),
                marginRight = L.isNarrow and 6 or 10,
                children = {
                    UI_.Label {
                        text = variantId,
                        fontSize = L.isNarrow and 11 or 14,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                        textAlign = "center",
                    },
                },
            },
            UI_.Label {
                text = v.name,
                fontSize = L.labelSize,
                fontWeight = isSelected and "bold" or "normal",
                fontColor = isSelected and { vColor[1], vColor[2], vColor[3], 255 } or COLORS.textNormal,
                flex = 1,
                flexShrink = 1,
            },
            isSelected and UI_.Label {
                text = "✓",
                fontSize = L.isNarrow and 12 or 14,
                fontColor = COLORS.equipped,
            } or nil,
        },
    }
end

--- 创建右侧机体详情面板
---@param variantId string|nil
---@param layout table 布局参数
---@return Widget
local function CreateChassisDetailPanel(variantId, layout)
    local L = layout
    if not variantId then
        return UI_.Panel {
            flex = 1,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI_.Label {
                    text = "选择一个机体查看详情",
                    fontSize = L.detailLabelSize,
                    fontColor = COLORS.textDim,
                },
            },
        }
    end

    local v = CONFIG.MechVariants[variantId]
    if not v then return UI_.Panel { flex = 1 } end

    local vColor = v.color or { 200, 200, 200 }
    local rows = {}

    -- 机体名称
    table.insert(rows, UI_.Label {
        text = v.name,
        fontSize = L.detailTitleSize,
        fontWeight = "bold",
        fontColor = { vColor[1], vColor[2], vColor[3], 255 },
        marginBottom = 4,
    })

    -- 简介
    table.insert(rows, UI_.Label {
        text = v.desc,
        fontSize = L.statLabelSize,
        fontColor = COLORS.textDim,
        marginBottom = L.isNarrow and 8 or 14,
    })

    -- 性能参数标题
    table.insert(rows, UI_.Label {
        text = "性能参数",
        fontSize = L.labelSize,
        fontWeight = "bold",
        fontColor = COLORS.textNormal,
        marginBottom = L.isNarrow and 4 or 8,
    })

    -- 属性对比行
    for _, entry in ipairs(STAT_LABELS) do
        local mul = v[entry.key] or 1.0
        table.insert(rows, CreateStatRow(entry.label, mul, COST_KEYS[entry.key] or false, L))
    end

    return UI_.Panel {
        flex = 1,
        flexDirection = "column",
        paddingAll = L.isNarrow and 12 or 18,
        overflow = "scroll",
        children = rows,
    }
end

--- 构建机体选择模式内容（自适应：横屏左右分栏，竖屏上下分栏）
---@param layout table 布局参数
local function BuildChassisContent(layout)
    local L = layout
    local listChildren = {}
    for _, vid in ipairs(CONFIG.MechVariantOrder) do
        table.insert(listChildren, CreateChassisListItem(vid, L))
    end

    -- 列表面板属性
    local listPanel = {
        flexDirection = "column",
        gap = L.isNarrow and 3 or 4,
        paddingAll = L.isNarrow and 6 or 10,
        overflow = "scroll",
        backgroundColor = { 15, 18, 32, 240 },
        children = listChildren,
    }
    -- 横屏：固定宽度 + 右边框；竖屏：限制最大高度
    if L.contentDir == "row" then
        listPanel.width = L.listWidth
        listPanel.borderRightWidth = 1
        listPanel.borderColor = COLORS.panelBorder
    else
        listPanel.width = "100%"
        listPanel.maxHeight = L.listMaxHeight
        listPanel.borderBottomWidth = 1
        listPanel.borderColor = COLORS.panelBorder
    end

    return {
        -- 自适应分栏
        UI_.Panel {
            flex = 1,
            flexDirection = L.contentDir,
            gap = 2,
            children = {
                -- 列表区
                UI_.Panel(listPanel),
                -- 详情区
                UI_.Panel {
                    flex = 1,
                    flexDirection = "column",
                    backgroundColor = COLORS.panelBg,
                    children = {
                        CreateChassisDetailPanel(CONFIG.SelectedVariant, L),
                    },
                },
            },
        },
    }
end

--- 构建完整界面
local function BuildScreen()
    WeaponManager.Init()
    local L = GetLayout()

    -- 顶部概览文字
    local loadout = WeaponManager.GetLoadout()
    local variantName = ""
    local vData = CONFIG.MechVariants[CONFIG.SelectedVariant or "A"]
    if vData then variantName = vData.name end
    local summaryText = string.format("机体: %s  |  左手: %s  |  右手: %s  |  左肩: %s  |  右肩: %s",
        variantName,
        WeaponDefs.GetDisplayName(loadout.handL),
        WeaponDefs.GetDisplayName(loadout.handR),
        WeaponDefs.GetDisplayName(loadout.shoulderL),
        WeaponDefs.GetDisplayName(loadout.shoulderR))

    -- 根据模式构建内容区
    local contentChildren = screenMode_ == "chassis" and BuildChassisContent(L) or BuildWeaponsContent(L)

    -- 组装主布局子元素列表
    local mainChildren = {
        -- 顶部标题栏
        UI_.Panel {
            width = "100%",
            minHeight = L.isNarrow and 44 or 52,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = L.paddingH,
            paddingRight = L.isNarrow and 8 or 12,
            paddingTop = L.isNarrow and 4 or 8,
            paddingBottom = L.isNarrow and 4 or 8,
            backgroundColor = { 15, 18, 30, 250 },
            borderBottomWidth = 1,
            borderColor = { 50, 60, 100, 120 },
            children = {
                -- 返回按钮（左上角）
                UI_.Button {
                    text = "返回",
                    width = L.isNarrow and 56 or 72,
                    height = L.isNarrow and 32 or 40,
                    fontSize = L.labelSize,
                    backgroundColor = { 60, 40, 40, 220 },
                    textColor = { 255, 180, 160, 255 },
                    hoverBackgroundColor = { 80, 50, 50, 230 },
                    borderRadius = 8,
                    marginRight = L.isNarrow and 8 or 12,
                    onClick = function(self)
                        local cb = onBack_
                        Armory.Hide()
                        if cb then cb() end
                    end,
                },
                -- 标题+摘要
                UI_.Panel {
                    flex = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI_.Label {
                            text = "整备机体",
                            fontSize = L.titleSize,
                            fontWeight = "bold",
                            fontColor = COLORS.textTitle,
                        },
                        UI_.Label {
                            text = summaryText,
                            fontSize = L.subtitleSize,
                            fontColor = COLORS.textDim,
                        },
                    },
                },
            },
        },

        -- 模式切换标签
        UI_.Panel {
            width = "100%",
            height = L.isNarrow and 46 or 56,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = L.isNarrow and 6 or 10,
            paddingLeft = L.isNarrow and 8 or 12,
            paddingRight = L.isNarrow and 8 or 12,
            paddingTop = L.isNarrow and 4 or 6,
            paddingBottom = L.isNarrow and 4 or 6,
            backgroundColor = { 12, 15, 28, 240 },
            children = {
                CreateModeTab("weapons", "武器装备", L),
                CreateModeTab("chassis", "机体选择", L),
            },
        },
    }

    -- 追加内容区子元素
    for _, child in ipairs(contentChildren) do
        table.insert(mainChildren, child)
    end

    rootWidget_ = UI_.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = COLORS.bg,
        paddingLeft = 64,
        paddingRight = 64,
        children = mainChildren,
    }

    UI_.SetRoot(rootWidget_)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 显示整备界面
---@param uiModule table UI 模块引用（从 Menu.GetUI() 获取）
---@param backCallback function 返回按钮回调
function Armory.Show(uiModule, backCallback)
    UI_ = uiModule
    onBack_ = backCallback
    screenMode_ = "weapons"
    selectedSlot_ = "handL"
    selectedWeapon_ = WeaponManager.GetSlotWeapon("handL")

    -- 切换鼠标模式
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    BuildScreen()
end

--- 刷新界面（武器选择变更后调用）
function Armory.Refresh()
    if rootWidget_ then
        rootWidget_:Destroy()
        rootWidget_ = nil
    end
    BuildScreen()
end

--- 隐藏整备界面
function Armory.Hide()
    if rootWidget_ then
        rootWidget_:Destroy()
        rootWidget_ = nil
    end
    UI_ = nil
    onBack_ = nil
end

return Armory
