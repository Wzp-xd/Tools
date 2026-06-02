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
-- 关卡配置（数据驱动）
-- ============================================================
-- 每关定义: tubes=总管数, colors=颜色数, empty=空管数
-- 规则: tubes = colors + empty
Config.levels = {
    -- 入门 (1-3): 3色5管
    { tubes = 5, colors = 3, empty = 2 },
    { tubes = 5, colors = 3, empty = 2 },
    { tubes = 5, colors = 3, empty = 2 },
    -- 进阶 (4-6): 4色6管
    { tubes = 6, colors = 4, empty = 2 },
    { tubes = 6, colors = 4, empty = 2 },
    { tubes = 6, colors = 4, empty = 2 },
    -- 中级 (7-8): 5色7管
    { tubes = 7, colors = 5, empty = 2 },
    { tubes = 7, colors = 5, empty = 2 },
    -- 高级 (9-10): 6色8管
    { tubes = 8, colors = 6, empty = 2 },
    { tubes = 8, colors = 6, empty = 2 },
    -- 困难 (11-12): 7色9管
    { tubes = 9, colors = 7, empty = 2 },
    { tubes = 9, colors = 7, empty = 2 },
    -- 大师 (13+): 8色10管
    { tubes = 10, colors = 8, empty = 2 },
}

-- 无限关卡生成规则（超过预设关卡后使用）
Config.infiniteLevelRule = {
    maxColors   = 10,     -- 最大颜色数
    maxTubes    = 14,     -- 最大管数
    emptyMin    = 2,      -- 最少空管数
    emptyMax    = 3,      -- 最多空管数（高难度可给3管）
    -- 每N关增加一个颜色
    colorIncreaseInterval = 3,
}

--- 获取关卡配置（支持无限关卡）
---@param level integer
---@return { tubes: integer, colors: integer, empty: integer }
function Config.getLevelConfig(level)
    if level <= #Config.levels then
        return Config.levels[level]
    end
    -- 无限关卡公式
    local rule = Config.infiniteLevelRule
    local extra = level - #Config.levels
    local colorsAdd = math.floor(extra / rule.colorIncreaseInterval)
    local baseColors = Config.levels[#Config.levels].colors
    local colors = math.min(baseColors + colorsAdd, rule.maxColors)
    -- 高难度偶尔给3个空管
    local empty = (extra > 6 and level % 5 == 0) and rule.emptyMax or rule.emptyMin
    local tubes = math.min(colors + empty, rule.maxTubes)
    -- 如果管数被限制，反推颜色数
    colors = tubes - empty
    return { tubes = tubes, colors = colors, empty = empty }
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
