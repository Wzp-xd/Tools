--- Config.lua — 所有常量配置：颜色、几何参数、4 阶段动画参数
local Config = {}

Config.CAPACITY = 4

-- 倒水模式："droplet"（液滴飞行）| "stream"（倾倒水流）
Config.POUR_MODE = "stream"

Config.COLORS = {
    { 240,  50,  50 },  -- 1 红：明亮鲜红
    {  50, 110, 245 },  -- 2 蓝：明亮天蓝
    {  80, 200,  60 },  -- 3 绿：鲜翠绿
    { 255, 210,  40 },  -- 4 黄：明亮柠檬黄
    { 170,  60, 220 },  -- 5 紫：亮丽紫
    { 255, 140,  30 },  -- 6 橙：鲜亮橙
    {  40, 210, 220 },  -- 7 青：明亮青
    { 245, 100, 150 },  -- 8 粉：亮粉红
}

Config.TUBE = {
    tubeWidth       = 50,      -- 试管外径宽度（px）60→50
    wallThickness   = 3,       -- 管壁厚度（px）4→3
    slotHeight      = 55,      -- 每格标准高度（px）40→55
    bottomSlotRatio = 0.75,    -- 底部一格在直筒段占标准高度的比例 0.8→0.75
    topPadding      = 15,      -- 管口内顶部空白区域高度（px）10→15
    ballHeight      = 28,      -- 球底高度（px）25→28
    ellipticity     = 0.30,    -- 椭圆度（0~1）0.35→0.30
    liquidAlpha   = 240,     -- 液柱统一透明度 210→240
    gap           = 14,      -- 试管间距（px）20→14

    -- 3D 视觉增强：玻璃管壁
    glass = {
        mainHighlightAlpha  = 35,    -- 主高光带（降低，让液体纯色可见）
        secHighlightAlpha   = 12,    -- 次高光带（降低）
        edgeDarkAlpha       = 18,    -- 边缘暗线（降低）
        ballHighlightAlpha  = 30,    -- 球底高光点
        ballHighlightSize   = 0.35,  -- 高光点大小
        rimRingAlpha        = 40,    -- 管口厚度环
        baseTintColor       = { 40, 60, 100 },  -- 管壁蓝色调底色
        baseTintAlpha       = 0,                 -- 底色关闭，让中间区域完全透明
    },

    -- 3D 视觉增强：液体
    liquid = {
        edgeDarkAlpha       = 58,    -- 边缘暗化 40→58
        edgeWidth           = 0.22,  -- 暗化宽度 0.20→0.22
        highlightAlpha      = 42,    -- 高光带 25→42
        highlightWidth      = 0.10,  -- 高光宽度 0.08→0.10
        highlightPos        = 0.20,  -- 高光位置 0.22→0.20
        surfaceRingAlpha    = 55,    -- 液面描边环 50→55
        surfaceSpotAlpha    = 70,    -- 液面光斑 60→70
        surfaceSpotSize     = 0.18,  -- 光斑大小 0.15→0.18
    },

    -- 3D 视觉增强：环境光遮蔽
    ao = {
        rimShadowHeight     = 8,     -- 管口内沿 AO 高度 5→8
        rimShadowAlpha      = 75,    -- 管口内沿 AO alpha 60→75
        ballJointAlpha      = 50,    -- 球底交汇处 AO 40→50
        ballJointHeight     = 4,     -- 球底交汇处 AO 高度 3→4
    },
}

Config.ANIM = {
    select = {
        liftY    = 8,
        duration = 0.1,
    },

    -- ===== 4 阶段倒水动画 =====
    pour = {
        -- 阶段 1: 上升（液滴从液面原位出现，上升到管口上方，同时液面逐渐下降消失）
        riseDuration   = 0.25,

        -- 阶段 2: 飞行（贝塞尔弧线）
        flyDuration    = 0.30,
        arcPeakH       = 50,

        -- 阶段 3: 融入（液滴接触目标管液面）
        mergeDuration  = 0.12,

        -- 阶段 4: 填充（液柱从管口下落到目标层位）
        fillDuration   = 0.20,
    },

    -- 液滴形变（飞行阶段椭圆宽高比随 t 变化）
    droplet = {
        baseWidth   = 0.6,
        minAspect   = 0.5,
        maxAspect   = 1.4,
        rotateSpeed = 3.0,
    },

    -- 目标管涟漪（液滴融入后）
    ripple = {
        amplitude  = 4.0,
        frequency  = 16,
        damping    = 5.0,
    },

    -- 阻尼正弦波抖动
    wobble = {
        amplitude = 3.0,
        frequency = 12,
        damping   = 4.5,
    },

    shake = {
        amplitude = 4,
        frequency = 20,
        duration  = 0.3,
    },

    -- 液面水花粒子（液滴入水时）
    splash = {
        count       = 6,       -- 粒子数量
        speed       = 80,      -- 初始飞射速度（px/s）
        gravity     = 280,     -- 重力加速度（px/s²）
        lifetime    = 0.45,    -- 粒子寿命（秒）
        minRadius   = 1.5,     -- 最小粒子半径
        maxRadius   = 3.0,     -- 最大粒子半径
        spreadAngle = 140,     -- 扩散角度范围（度，以正上方为中心）
    },

    glow = {
        color   = { 100, 180, 255 },
        alpha   = 100,
        feather = 6,
    },

    -- ===== 倾倒水流模式（stream）=====
    stream = {
        -- 阶段 1: 倾斜（源管向目标管方向旋转）
        tiltDuration    = 0.30,
        tiltAngle       = 40,        -- 最大倾斜角度（度）

        -- 阶段 2: 水流（液体持续从管口流向目标管）
        streamDuration  = 0.55,

        -- 阶段 3: 归位（水流断流 + 源管复位）
        settleDuration  = 0.30,

        -- 阶段 4: 填充（复用 droplet fill 逻辑）
        fillDuration    = 0.20,

        -- 水流视觉参数
        streamStartW    = 0.35,      -- 管口处水流宽度（相对内径比例）
        streamEndW      = 0.12,      -- 入水处水流宽度
        streamSegments  = 16,        -- 水流路径采样段数
        streamWobbleAmp = 1.5,       -- 水流横向波动幅度（px）
        streamWobbleSpd = 18,        -- 波动频率
        streamGravity   = 450,       -- 水流重力（px/s²）

        -- 抬升参数（确保倾斜后管口高于目标管口）
        liftMargin      = 20,        -- 管口抬起后距目标管口的最小间距（px）

        -- 断流小液滴
        dripCount       = 3,
        dripSpeed       = 50,
        dripGravity     = 350,
        dripLifetime    = 0.35,
        dripMinRadius   = 1.5,
        dripMaxRadius   = 3.0,
    },
}

-- 初始固定数据（用于重置）
Config.INITIAL_TUBES = {
    { 1, 3, 2, 1 },
    { 2, 1, 3, 2 },
    { 3, 2, 1, 3 },
    {},
    {},
}

return Config
