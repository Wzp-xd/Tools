-- ============================================================
-- config.lua - 游戏配置表（所有可调参数集中管理）
-- ============================================================

local Config = {}

-- ============================================================
-- 试管几何参数
-- ============================================================
Config.tube = {
    width       = 50,       -- 管外径（对齐 WaterSortB）
    wall        = 3,        -- 管壁厚度
    gap         = 20,       -- 试管间水平间距
    rowGap      = 50,       -- 双行时上下行间距
    layerCount  = 4,        -- 每管层数

    -- 3D 几何参数
    slotHeight      = 45,       -- 每格标准高度
    topPadding      = 12,       -- 管口内顶部留白
    ellipticity     = 0.30,     -- 管口/底部椭圆度（RY/RX 比例）
    liquidAlpha     = 230,      -- 液体 alpha

    -- 3D 玻璃参数
    glass = {
        mainHighlightAlpha  = 35,
        secHighlightAlpha   = 12,
        edgeDarkAlpha       = 18,
        ballHighlightAlpha  = 30,
        ballHighlightSize   = 0.35,
        rimRingAlpha        = 40,
        baseTintColor       = { 40, 60, 100 },
        baseTintAlpha       = 0,
    },

    -- 3D 液体参数
    liquid = {
        surfaceRingAlpha    = 55,
        surfaceSpotAlpha    = 70,
        surfaceSpotSize     = 0.18,
        ellipticity         = 0.30,
        -- 椭圆缩放系数
        boundaryRXScale     = 0.80,     -- 分界椭圆 RX 占管内径比例
        surfaceRXScale      = 0.90,     -- 液面椭圆 RX 占管内径比例
        surfaceRingScale    = 0.85,     -- 描边环缩放
        boundaryDarken      = 0.35,     -- 分界暗色因子
        spotOffsetX         = 0.25,     -- 光斑水平偏移比例
        spotOffsetY         = 0.15,     -- 光斑垂直偏移比例
    },

    -- AO 参数
    ao = {
        rimShadowHeight     = 8,
        rimShadowAlpha      = 75,
        ballJointAlpha      = 50,
        ballJointHeight     = 4,
    },

    -- 迷雾层渲染参数
    fog = {
        color           = { 45, 45, 55 },
        alpha           = 230,
        questionAlpha   = 120,
        revealDuration  = 0.4,  -- 揭开动画时长(秒)
    },
}

-- ============================================================
-- 交互参数
-- ============================================================
Config.interaction = {
    selectOffset   = 22,       -- 选中试管上浮距离(px)
    selectAnimSpd  = 12,       -- 上浮动画速度因子
    shakeDuration  = 0.3,      -- 不可倒入时抖动时长(秒)
    shakeAmplitude = 5,        -- 抖动振幅(px)
    shakeFreq      = 7,        -- 抖动频率(cycles)
}

-- ============================================================
-- 倒水动画参数
-- ============================================================
Config.animation = {
    moveDuration   = 0.30,    -- 试管移动到目标位置时长
    tiltDuration   = 0.20,    -- 倾斜动画时长
    pourPerLayer   = 0.28,    -- 每层液体倒出时长
    returnDuration = 0.30,    -- 返回原位时长
    tiltAngleMin   = math.rad(18),   -- 满管时最小倾斜角
    tiltAngleMax   = math.rad(100),  -- 最大倾斜角上限
}

-- ============================================================
-- 胜利动画参数
-- ============================================================
Config.winEffect = {
    bounceDuration = 0.45,    -- 试管弹跳时长
    bounceDelay    = 0.07,    -- 相邻试管弹跳延迟
    bounceHeight   = 18,      -- 弹跳高度(px)
    particleCount  = 35,      -- 粒子数量
    particleMinVx  = -125,    -- 粒子水平速度范围
    particleMaxVx  = 125,
    particleMinVy  = -350,    -- 粒子垂直初速度范围
    particleMaxVy  = -80,
    particleMinSize = 5,
    particleMaxSize = 11,
    particleGravity = 450,    -- 粒子重力
    particleDecayMin = 0.5,
    particleDecayMax = 0.9,
}

-- ============================================================
-- 颜色主题（支持多主题切换）
-- ============================================================
Config.themes = {
    default = {
        name = "经典",
        colors = {
            { 240, 60,  60  },   -- 红（高饱和）
            { 55,  130, 240 },   -- 蓝
            { 60,  200, 80  },   -- 绿
            { 250, 210, 40  },   -- 黄
            { 180, 80,  220 },   -- 紫
            { 250, 145, 40  },   -- 橙
            { 40,  215, 215 },   -- 青
            { 250, 120, 170 },   -- 粉
            { 160, 110, 65  },   -- 棕
            { 185, 185, 195 },   -- 灰
            { 45,  85,  175 },   -- 深蓝
            { 210, 55,  210 },   -- 洋红
        },
        background = {
            gradientTop    = { 18, 22, 38, 255 },
            gradientBottom = { 28, 35, 55, 255 },
        },
        glass = {
            fillColor    = { 200, 215, 240, 40 },
            strokeColor  = { 170, 185, 210, 180 },
            rimColor     = { 170, 185, 210, 140 },
            highlightColor = { 255, 255, 255, 50 },
        },
        topBar = { 12, 16, 30, 255 },
    },
    pastel = {
        name = "柔和",
        colors = {
            { 255, 150, 150 },
            { 150, 190, 255 },
            { 150, 230, 160 },
            { 255, 235, 130 },
            { 210, 160, 240 },
            { 255, 200, 130 },
            { 130, 235, 235 },
            { 255, 180, 210 },
            { 190, 160, 130 },
            { 210, 210, 210 },
            { 130, 150, 210 },
            { 240, 140, 240 },
        },
        background = {
            gradientTop    = { 22, 26, 42, 255 },
            gradientBottom = { 32, 38, 58, 255 },
        },
        glass = {
            fillColor    = { 220, 225, 240, 40 },
            strokeColor  = { 190, 200, 220, 180 },
            rimColor     = { 190, 200, 220, 140 },
            highlightColor = { 255, 255, 255, 50 },
        },
        topBar = { 16, 20, 35, 255 },
    },
}

Config.currentTheme = "default"

--- 获取当前主题
---@return table
function Config.getTheme()
    return Config.themes[Config.currentTheme] or Config.themes.default
end

--- 获取颜色数组
---@return table[]
function Config.getColors()
    return Config.getTheme().colors
end

-- ============================================================
-- 关卡配置（40关 + 无限关卡，与 MECHANICS_PLAN.md 对齐）
-- ============================================================
-- 字段说明:
--   colors: 颜色数(每种恰好4层)
--   empty: 空管数(固定2)
--   hiddenLayers: 迷雾层总数(默认0)
--   lockedCount: 封印管数(0/1/2, 默认0)
--   sinkCount: 单向管数(0/1, 默认0)
--   tempTubeCount: 临时管数(0/1, 默认0)
--   type: "manual" 为手写关
Config.levels = {
    -- ========== L1: 教程关 ==========
    { type = "manual", colors = 1, empty = 1,
      tubes_data = { {1,1,1}, {1} } },

    -- ========== 阶段二：3色（L2-L5）==========
    { colors = 3, empty = 2 },                                          -- L2
    { colors = 3, empty = 2, hiddenLayers = 3 },                        -- L3: 迷雾引入
    { colors = 3, empty = 2, lockedCount = 1 },                         -- L4: 封印引入
    { colors = 3, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L5

    -- ========== 阶段三：4色（L6-L10）==========
    { colors = 4, empty = 2 },                                          -- L6
    { colors = 4, empty = 2, hiddenLayers = 3 },                        -- L7
    { colors = 4, empty = 2, lockedCount = 1 },                         -- L8
    { colors = 4, empty = 2, hiddenLayers = 6 },                        -- L9
    { colors = 4, empty = 2, lockedCount = 1 },                         -- L10

    -- ========== 阶段四：4色深化（L11-L12）==========
    { colors = 4, empty = 2, hiddenLayers = 6 },                        -- L11
    { colors = 4, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L12

    -- ========== 阶段五：5色（L13-L16）==========
    { colors = 5, empty = 2 },                                          -- L13
    { colors = 5, empty = 2, hiddenLayers = 3 },                        -- L14
    { colors = 5, empty = 2, lockedCount = 1, hiddenLayers = 6 },       -- L15
    { colors = 5, empty = 2, hiddenLayers = 9 },                        -- L16

    -- ========== 阶段六：6色（L17-L19）==========
    { colors = 6, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L17
    { colors = 6, empty = 2, hiddenLayers = 6 },                        -- L18
    { colors = 6, empty = 2, lockedCount = 2 },                         -- L19

    -- ========== 阶段七：7色 + 临时管（L20-L22）==========
    { colors = 7, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                     -- L20
    { colors = 7, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                     -- L21
    { colors = 7, empty = 2, lockedCount = 2, tempTubeCount = 1 },                      -- L22

    -- ========== 阶段八：8色（L23-L25）==========
    { colors = 8, empty = 2, lockedCount = 1, hiddenLayers = 3, tempTubeCount = 1 },    -- L23
    { colors = 8, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                     -- L24
    { colors = 8, empty = 2, lockedCount = 1, hiddenLayers = 6, tempTubeCount = 1 },    -- L25

    -- ========== 阶段九：9色（L26-L28）==========
    { colors = 9, empty = 2, lockedCount = 2, hiddenLayers = 3, tempTubeCount = 1 },    -- L26
    { colors = 9, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                     -- L27
    { colors = 9, empty = 2, lockedCount = 2, hiddenLayers = 3, tempTubeCount = 1 },    -- L28

    -- ========== 阶段十：10色（L29-L32）==========
    { colors = 10, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                    -- L29
    { colors = 10, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                    -- L30
    { colors = 10, empty = 2, lockedCount = 2, tempTubeCount = 1 },                     -- L31
    { colors = 10, empty = 2, hiddenLayers = 15, tempTubeCount = 1 },                   -- L32

    -- ========== 阶段十一：10色 + 单向管（L33-L36）==========
    { colors = 10, empty = 2, lockedCount = 2, hiddenLayers = 6, tempTubeCount = 1 },                   -- L33
    { colors = 10, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                                    -- L34
    { colors = 10, empty = 2, lockedCount = 2, sinkCount = 1, tempTubeCount = 1 },                      -- L35
    { colors = 10, empty = 2, lockedCount = 1, hiddenLayers = 3, tempTubeCount = 1 },                   -- L36

    -- ========== 阶段十二：终极（L37-L40）==========
    { colors = 10, empty = 2, lockedCount = 2, sinkCount = 1, tempTubeCount = 1 },                      -- L37
    { colors = 10, empty = 2, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },                     -- L38
    { colors = 10, empty = 2, lockedCount = 1, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },    -- L39
    { colors = 10, empty = 2, lockedCount = 2, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },    -- L40
}

-- 无限关卡生成规则（超过40关后使用）
Config.infiniteLevelRule = {
    maxColors   = 10,
    maxTubes    = 14,
    emptyMin    = 2,
    emptyMax    = 3,
    colorIncreaseInterval = 3,
    mechanics = {
        hiddenLayers = { min = 4, max = 12 },
        lockChance = 0.6,
        maxLocks = 2,
        tempTubeCount = 1,
        sinkChance = 0.4,
        sinkCount = 1,
    },
}

--- 获取关卡配置（支持无限关卡）
---@param level integer
---@return table
function Config.getLevelConfig(level)
    if level <= #Config.levels then
        local cfg = Config.levels[level]
        local colors = cfg.colors
        local empty = cfg.empty or 2
        local lockedCount = cfg.lockedCount or 0
        local tubes = colors + empty + lockedCount
        return {
            tubes = tubes,
            colors = colors,
            empty = empty,
            hiddenLayers = cfg.hiddenLayers or 0,
            lockedCount = lockedCount,
            sinkCount = cfg.sinkCount or 0,
            tempTubeCount = cfg.tempTubeCount or 0,
            type = cfg.type,
            tubes_data = cfg.tubes_data,
        }
    end
    -- 无限关卡公式
    local rule = Config.infiniteLevelRule
    local extra = level - #Config.levels
    local colorsAdd = math.floor(extra / rule.colorIncreaseInterval)
    local baseColors = Config.levels[#Config.levels].colors
    local colors = math.min(baseColors + colorsAdd, rule.maxColors)
    local empty = (extra > 6 and level % 5 == 0) and rule.emptyMax or rule.emptyMin
    local tubes = math.min(colors + empty, rule.maxTubes)
    colors = tubes - empty

    local mech = rule.mechanics
    local cfg = {
        tubes = tubes,
        colors = colors,
        empty = empty,
        hiddenLayers = math.random(mech.hiddenLayers.min, mech.hiddenLayers.max),
        tempTubeCount = mech.tempTubeCount,
        lockedCount = 0,
        sinkCount = 0,
    }
    if math.random() < mech.lockChance then
        cfg.lockedCount = math.random(1, mech.maxLocks)
    end
    if math.random() < mech.sinkChance then
        cfg.sinkCount = mech.sinkCount
    end
    return cfg
end

-- ============================================================
-- 渲染微调参数
-- ============================================================
Config.render = {
    selectGlowAlpha = 70,
    selectGlowInnerAlpha = 50,
    streamWidth     = 7,
    streamSegments  = 10,
    pourTipOffset   = 5,       -- 管口对齐到目标管时的间距
    pourAboveOffset = 30,      -- 源管管口在目标管口上方的距离
}

return Config
