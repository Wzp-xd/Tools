# 试管几何与液体渲染设计方案 v3

## 0. 变更记录

| 版本 | 变更 |
|------|------|
| v1 | 初始设计 |
| v2 | 修复 11 个设计缺陷：Bézier 球底、ellipticity 全面适用、推导值延迟计算、参数约束、液体统一着色等 |
| v3 | 桶形液体槽（消除 alpha 叠加色差）；新增 `semiEllipseRTL` 弧；管壁/衬底改用上半椭圆弧闭合（消除水平切线）；移除 sin 波浪特效；渲染管线扩展为 9 步 |

---

## 1. 整体结构

试管是一个 3D 圆柱容器的正面 2D 投影。从上到下由三个区域组成：

```
        ╭─────────╮          ← 管口椭圆（ellipticity 控制扁度）
       ╭┤         ├╮
       │╰─────────╯│        ← rimEllipseH * 2（管口椭圆完整可见高度）
       │           │
       │           │
       │  直筒区域  │        ← bodyHeight（液柱在此绘制）
       │           │
       │           │
       ╰───╲   ╱───╯
            ╲ ╱              ← ballHeight（球底，Bézier 半椭圆弧）
             V
```

---

## 2. 核心参数定义

### 2.1 Config.TUBE 参数表

```lua
Config.TUBE = {
    tubeWidth     = 50,      -- 试管外径宽度（px），2D 投影中的水平宽度
    wallThickness = 4,       -- 玻璃管壁厚度（px），内径 = tubeWidth - 2*wallThickness
    bodyHeight    = 144,     -- 直筒段高度（px），液柱所在区域
    ballHeight    = 25,      -- 球底高度（px），Bézier 半椭圆弧的垂直跨度
    ellipticity   = 0.35,    -- 椭圆度（0.0~1.0），管口和液面的短轴与长轴之比
    liquidAlpha   = 210,     -- 液柱统一透明度（0~255）
    gap           = 20,      -- 相邻试管间距（px）
}
```

### 2.2 推导参数

**所有推导值必须在布局时（`calcPositions` / `drawTube` 入口）从 Config 当前值实时计算，不得在模块加载时缓存。**

```lua
-- 基础几何推导
local outerRadius   = TUBE.tubeWidth / 2                      -- 外半径
local innerWidth    = TUBE.tubeWidth - 2 * TUBE.wallThickness -- 内径宽度
local innerRadius   = innerWidth / 2                           -- 内半径
local slotHeight    = TUBE.bodyHeight / CAPACITY               -- 每格液柱高度

-- 椭圆推导
local rimEllipseRX  = outerRadius                              -- 管口椭圆水平半径（外壁）
local rimEllipseRY  = outerRadius * TUBE.ellipticity           -- 管口椭圆垂直半径
local liqEllipseRX  = innerRadius                              -- 液面椭圆水平半径（内壁）
local liqEllipseRY  = innerRadius * TUBE.ellipticity           -- 液面椭圆垂直半径

-- 球底推导（Bézier 参数）
local outerBallRX   = outerRadius                              -- 外球底水平半径
local outerBallRY   = TUBE.ballHeight                          -- 外球底垂直半径（即 ballHeight）
local innerBallRX   = innerRadius                              -- 内球底水平半径
local innerBallRY   = TUBE.ballHeight - TUBE.wallThickness     -- 内球底垂直半径

-- 总高度
local totalHeight   = rimEllipseRY * 2 + TUBE.bodyHeight + TUBE.ballHeight
```

### 2.3 参数约束

| 约束 | 条件 | 原因 |
|------|------|------|
| `wallThickness > 0` | 管壁不能为 0 | 否则无管壁可见 |
| `tubeWidth > 2 * wallThickness` | 内径 > 0 | 否则无内部空间 |
| `ballHeight >= wallThickness` | 内球底高度 > 0 | 否则内球底垂直半径为 0 或负值 |
| `0.0 <= ellipticity <= 1.0` | 短轴不超过长轴 | 0=纯直线，1=半圆 |
| `bodyHeight >= CAPACITY` | 每格至少 1px | 否则液格不可见 |
| `0 <= liquidAlpha <= 255` | 有效 alpha 范围 | — |

### 2.4 椭圆度（ellipticity）详解

`ellipticity` 控制圆形截面在 2D 投影中显示为多"扁"的椭圆：

```
ellipticity = 0.0:  ──────────  纯直线（完全正面无透视）
ellipticity = 0.2:  ╌╌╌╌╌╌╌╌╌  很浅的椭圆
ellipticity = 0.35: ───╲  ╱───  自然的 3D 透视感（推荐）
ellipticity = 0.5:  ╲      ╱   较深的椭圆
ellipticity = 1.0:  (  半圆  )  完整半圆（俯视 90 度）
```

影响范围：
- **管口形状**：管口渲染为椭圆，RY = `outerRadius * ellipticity`
- **液面形状**：每层液柱顶面/底面是椭圆弧，RY = `innerRadius * ellipticity`
- **球底不受影响**：球底由 `ballHeight` 独立控制（可以 ≠ outerRadius）

---

## 3. 试管几何剖面

```
            ← tubeWidth →
      ← wt →            ← wt →
            ← innerWidth →

Y0  ┌──────────────────────────┐ ....... 管口椭圆顶边
    │      ╭──────────╮        │         ↑
Y1  │      │ (暗色开口) │        │         rimEllipseRY * 2
    │      ╰──────────╯        │         ↓
Y2  ├──────────────────────────┤ ....... 直筒段起始
    │ ▓ │                  │ ▓ │         ↑
    │ ▓ │     slot 4       │ ▓ │         │
    │ ▓ │──────────────────│ ▓ │         │
    │ ▓ │     slot 3       │ ▓ │         bodyHeight
    │ ▓ │──────────────────│ ▓ │         = slotHeight × CAPACITY
    │ ▓ │     slot 2       │ ▓ │         │
    │ ▓ │──────────────────│ ▓ │         │
    │ ▓ │     slot 1       │ ▓ │         ↓
Y3  ├───┤──────────────────├───┤ ....... 直筒段底部（球底弧起始）
    │    ╲                ╱    │         ↑
    │     ╲              ╱     │         ballHeight
    │      ╲            ╱      │         ↓
Y4  └───────╲──────────╱───────┘ ....... 试管最低点

         ▓ = 玻璃管壁（wallThickness）
```

**Y 坐标推导**（以试管左上角 `(x, y)` 为原点）：

```
Y0 = y                                              -- 管口椭圆顶边
Y1 = y + rimEllipseRY                               -- 管口椭圆中心
Y2 = y + rimEllipseRY * 2                           -- 直筒段起始 = straightTop
Y3 = Y2 + bodyHeight                                -- 直筒段底部 = straightBottom = 球底弧起始
Y4 = Y3 + ballHeight                                -- 试管最低点 = tubeBottom

totalHeight = (Y4 - Y0) = rimEllipseRY * 2 + bodyHeight + ballHeight
```

---

## 4. Bézier 半椭圆弧

### 4.1 为什么需要 Bézier

`nvgArc(cx, cy, r, startAngle, endAngle)` 只能绘制**正圆弧**。当 `ballHeight ≠ outerRadius` 时（即垂直半径 ≠ 水平半径），需要用 Bézier 曲线近似半椭圆。

### 4.2 Kappa 常量

四分之一椭圆可以用一条三次 Bézier 曲线精确近似，控制点偏移系数为：

```
kappa = 0.5522847498    -- 4 * (sqrt(2) - 1) / 3
```

### 4.3 semiEllipseCW — 从左到右的半椭圆弧（顺时针，向下凸）

给定椭圆中心 `(cx, cy)`，水平半径 `rx`，垂直半径 `ry`：

```
        (cx-rx, cy)                    (cx+rx, cy)
             L ─────────────────────── R
             │                         │
             │    Bézier 控制点        │
             │                         │
             └────── (cx, cy+ry) ──────┘
                         B (底部)
```

用途：球底弧（外/内）、桶形液体底弧

```lua
--- 绘制半椭圆弧（从 L 到 R，经过 B，顺时针方向）
--- 起点 (cx - rx, cy)：由上层 moveTo/lineTo 到达
--- 终点 (cx + rx, cy)
local function semiEllipseCW(vg, cx, cy, rx, ry)
    local k = 0.5522847498
    -- 左侧四分之一弧：L → B
    nvgBezierTo(vg,
        cx - rx,       cy + ry * k,
        cx - rx * k,   cy + ry,
        cx,            cy + ry)
    -- 右侧四分之一弧：B → R
    nvgBezierTo(vg,
        cx + rx * k,   cy + ry,
        cx + rx,       cy + ry * k,
        cx + rx,       cy)
end
```

### 4.4 semiEllipseRTL — 从右到左的半椭圆弧（向下凸）

用途：桶形液体顶弧（封闭桶形路径的上半部分）

```
        (cx-rx, cy)                    (cx+rx, cy)
             L ─────────────────────── R
             │                         │
             │    Bézier 控制点        │
             │                         │
             └────── (cx, cy+ry) ──────┘
                         B (底部)
```

路径方向：从 R → B → L（与 semiEllipseCW 方向相反）

```lua
--- 绘制半椭圆弧（从 R 到 L，经过 B，用于桶形顶弧）
--- 起点 (cx + rx, cy)：由上层 moveTo/lineTo 到达
--- 终点 (cx - rx, cy)
local function semiEllipseRTL(vg, cx, cy, rx, ry)
    local k = 0.5522847498
    -- 右侧四分之一弧：R → B
    nvgBezierTo(vg,
        cx + rx,       cy + ry * k,
        cx + rx * k,   cy + ry,
        cx,            cy + ry)
    -- 左侧四分之一弧：B → L
    nvgBezierTo(vg,
        cx - rx * k,   cy + ry,
        cx - rx,       cy + ry * k,
        cx - rx,       cy)
end
```

### 4.5 特殊情况

- 当 `ballHeight == outerRadius` 时，Bézier 结果与 `nvgArc` 完全一致（退化为正圆弧）
- 当 `ballHeight < outerRadius` 时，底部更扁（宽大于高）
- 当 `ballHeight > outerRadius` 时，底部更尖（高大于宽）

### 4.6 内球底弧

内球底（液体填充和管内衬底使用）参数：

```
innerBallRX = innerRadius                            -- 内半径
innerBallRY = ballHeight - wallThickness             -- 减去管壁厚度

-- 弧中心 Y 坐标 = straightBottom（与外弧相同起始 Y）
-- 弧最低点 Y = straightBottom + innerBallRY
```

调用方式：

```lua
semiEllipseCW(vg, cx, straightBottom, innerBallRX, innerBallRY)
```

---

## 5. 液体渲染规则

### 5.1 液体分层模型

液体由下到上分为 `CAPACITY`（4）个逻辑格（slot），每格一种颜色。

### 5.2 桶形液体槽（Barrel-shaped Slots）

**v3 核心变更**：每个 slot 不再是矩形，而是一个完整的**桶形封闭路径**。

```
       ╭─ ─ ─ ─ ─ ─ ─ ─╮
      (   顶弧 (RTL)      )    ← semiEllipseRTL，向下凹
       ╰─ ─ ─ ─ ─ ─ ─ ─╯
       │                  │
       │  slot N 色块区域  │
       │                  │
       ╭─ ─ ─ ─ ─ ─ ─ ─╮
      (   底弧 (CW)       )    ← semiEllipseCW，向下凹
       ╰─ ─ ─ ─ ─ ─ ─ ─╯
```

**关键设计**：
- 相邻 slot 的交界处共享**同一条椭圆弧曲线**：上层的底弧与下层的顶弧完全重合
- 每个 slot 是独立封闭路径，不依赖其他 slot 的绘制
- 无重叠区域，从根本上消除 alpha 叠加导致的色差问题

**路径构建**（单个 slot）：

```
左上角 A ──→ 左壁向下 ──→ 底弧 ──→ 右壁向上 ──→ 顶弧 ──→ 回到 A

A ─────────────────── D      A, D: slotY（顶边 Y）
│                     │
│    桶形液体色块      │
│                     │
B ─────────────────── C      B, C: slotBottom（底边 Y）
     ╲             ╱
      ╲  底弧 CW  ╱         semiEllipseCW: B → 弧底 → C
       ╲_________╱

     ╱  顶弧 RTL  ╲         semiEllipseRTL: D → 弧底 → A
    ╱_____________╲
```

### 5.3 底层 slot（slot 1）特殊处理

底层 slot 的底弧使用**球底弧**而非液面椭圆弧：

```lua
if isBottom then
    -- 左壁延伸到球底弧起点
    nvgLineTo(vg, innerX, straightBottom)
    -- 球底 Bézier 弧（rx=innerRadius, ry=innerBallRY）
    semiEllipseCW(vg, cx, straightBottom, innerR, innerBallRY)
    nvgLineTo(vg, innerX + innerW, topY)
else
    -- 非底层：底弧为液面椭圆弧
    nvgLineTo(vg, innerX, slotBottom)
    semiEllipseCW(vg, cx, slotBottom, innerR, liqEllipseRY)
    nvgLineTo(vg, innerX + innerW, topY)
end
-- 顶弧统一使用 semiEllipseRTL
semiEllipseRTL(vg, cx, topY, innerR, liqEllipseRY)
```

### 5.4 alpha 叠加问题与桶形方案的优势

**问题**（v1/v2 矩形方案）：
- 相邻 slot 的分界线是水平直线
- 液面椭圆弧绘制在 slot 矩形之上
- 弧线区域与相邻 slot 存在**视觉重叠**
- 当 `liquidAlpha < 255` 时，重叠区域的颜色由两层 alpha 混合产生，形成色差条带

**解决**（v3 桶形方案）：
- 每个 slot 是完整封闭路径，底弧和顶弧作为路径边界的一部分
- 相邻 slot 共享完全相同的弧线曲线（上层底弧 = 下层顶弧），无间隙也无重叠
- 即使 `liquidAlpha < 255`，每个像素只被填充一次，不存在 alpha 叠加

### 5.5 顶层液面高光

最顶层 slot 上方绘制一个椭圆，模拟 3D 液面高光效果：

```lua
nvgBeginPath(vg)
nvgEllipse(vg, x + w / 2, ellipseCY, w / 2, liqEllipseRY)
nvgFillColor(vg, nvgRGBA(
    clampC(c[1] + 40), clampC(c[2] + 40), clampC(c[3] + 40), 160))
nvgFill(vg)
```

高光椭圆受 wobble 偏移和 ripple 动画影响：

```lua
local totalOff = wobbleOff + rippleOff
local ellipseCY = slotTopY + totalOff
```

> **注意**：v2 中的 sin 波浪叠加效果已在 v3 中移除。仅保留椭圆高光 + wobble/ripple 动画。

### 5.6 顶层液面的渲染时机

顶层液面高光在**管口椭圆之后**绘制（渲染管线第 8 步），避免被管口内圈的深色椭圆填充遮挡。绘制时使用独立的 Scissor 裁剪区域。

---

## 6. 管壁轮廓路径（`_tubeOutlinePath`）

管壁外轮廓使用单一连续封闭路径（用于高光渐变和描边）。

**v3 变更**：路径顶部不再使用水平线 + `nvgClosePath()` 闭合，而是使用**上半椭圆弧**，与管口外圈椭圆完全吻合。

```
路径流程（顺时针）：

          ╭─── 上半椭圆弧 ───╮
         ╱                     ╲
       A                         F
       │                         │     A/F: rimCY（管口椭圆中心 Y）
       │                         │     A→B: 左直筒壁
       │                         │     B→C→D: 底部 Bézier 半椭圆弧
       B                         E     D→E→F→A: 右筒壁 + 上半椭圆弧
       │                         │
       │                         │
        ╲   Bézier 半弧       ╱
         ╲                   ╱
          ╲                 ╱
           ╲_______________╱
        C         D        (弧底)
```

**关键坐标**：
- `rimCY = straightTop - rimEllipseRY`（管口椭圆中心 Y）
- 路径起点/终点在 `rimCY`，而非 `straightTop`
- 上半椭圆弧：右 → 顶 → 左（两段 Bézier 曲线，与管口外圈重合）

```lua
function _tubeOutlinePath(vg, x, straightTop, straightBottom, cx, outerR, ballH, tubeW, rimEllipseRY)
    local leftWall  = x
    local rightWall = x + tubeW
    local rimCY = straightTop - rimEllipseRY

    nvgMoveTo(vg, leftWall, rimCY)
    nvgLineTo(vg, leftWall, straightBottom)
    semiEllipseCW(vg, cx, straightBottom, outerR, ballH)
    nvgLineTo(vg, rightWall, rimCY)
    -- 上半椭圆弧闭合（右 → 顶 → 左），与管口外圈椭圆吻合
    nvgBezierTo(vg,
        rightWall,             rimCY - rimEllipseRY * KAPPA,
        cx + outerR * KAPPA,   rimCY - rimEllipseRY,
        cx,                    rimCY - rimEllipseRY)
    nvgBezierTo(vg,
        cx - outerR * KAPPA,   rimCY - rimEllipseRY,
        leftWall,              rimCY - rimEllipseRY * KAPPA,
        leftWall,              rimCY)
    nvgClosePath(vg)
end
```

---

## 7. 管口椭圆（`_drawRim`）

管口由两个同心椭圆 + 上沿高光弧组成：

```lua
function _drawRim(vg, cx, straightTop, outerR, innerR, ellipticity)
    local outerRY = outerR * ellipticity
    local innerRY = innerR * ellipticity
    local rimCY = straightTop - outerRY   -- 椭圆中心 Y

    -- 外圈（玻璃边缘高光描边）
    nvgEllipse(vg, cx, rimCY, outerR, outerRY)
    nvgStroke(vg)

    -- 内圈（暗色管口开口填充）
    nvgEllipse(vg, cx, rimCY, innerR, innerRY)
    nvgFill(vg)

    -- 管口上沿高光弧线（Bézier 上半椭圆弧：左 → 顶 → 右）
    nvgMoveTo(vg, cx - outerR, rimCY)
    nvgBezierTo(vg, ...)  -- 两段上半弧
    nvgStroke(vg)
end
```

---

## 8. 管内衬底（`_drawInnerBack`）

深色背景，使用 Bézier 内球底弧。

**v3 变更**：顶部闭合方式从水平线改为**上半椭圆弧**，与管口内圈椭圆吻合。

```lua
function _drawInnerBack(vg, cx, innerX, topY, bottomY, innerR, innerBallRY, rimEllipseRY, liqEllipseRY)
    local rimCY = topY - rimEllipseRY   -- 与管口椭圆共用中心

    nvgBeginPath(vg)
    nvgMoveTo(vg, innerX, rimCY)
    nvgLineTo(vg, innerX, bottomY)
    -- 内球底 Bézier 弧
    semiEllipseCW(vg, cx, bottomY, innerR, innerBallRY)
    nvgLineTo(vg, innerX + innerR * 2, rimCY)
    -- 上半椭圆弧闭合（右 → 顶 → 左），使用 liqEllipseRY 与管口内圈吻合
    nvgBezierTo(vg,
        innerX + innerR * 2,       rimCY - liqEllipseRY * KAPPA,
        cx + innerR * KAPPA,       rimCY - liqEllipseRY,
        cx,                        rimCY - liqEllipseRY)
    nvgBezierTo(vg,
        cx - innerR * KAPPA,       rimCY - liqEllipseRY,
        innerX,                    rimCY - liqEllipseRY * KAPPA,
        innerX,                    rimCY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 200))
    nvgFill(vg)
end
```

**注意**：衬底使用 `liqEllipseRY`（内径椭圆半径），管壁轮廓使用 `rimEllipseRY`（外径椭圆半径），确保各自与对应的管口椭圆完全吻合。

---

## 9. 渲染管线（绘制顺序）

渲染管线共 **9 步**，每步的层级关系和依赖关系如下：

```
第 1 步  阴影            ─ 管底下方，柔和投影
第 2 步  管内衬底         ─ 深色背景（Bézier 内弧 + 上半椭圆弧闭合）
第 3 步  Scissor 裁剪    ─ 限制液体绘制区域（含上方余量）
第 4 步  桶形液体层       ─ 从底到顶绘制桶形封闭路径（球底弧 / 液面弧 + semiEllipseRTL 顶弧）
第 5 步  隆起效果         ─ 倒水动画的液面隆起（Bézier 弧形 bulge）
         ─── 释放 Scissor ───
第 6 步  玻璃管壁         ─ 半透明渐变 + 高光 + 描边（Bézier 外弧 + 上半椭圆弧闭合）
第 7 步  管口椭圆         ─ 外圈高光描边 + 内圈暗色填充 + 上沿高光弧
第 8 步  顶层液面高光      ─ 椭圆高光（独立 Scissor，在管口之后绘制）
第 9 步  选中发光         ─ 条件渲染：选中时管壁外发光
```

### Scissor 裁剪策略

液体层（第 3~5 步）使用 NanoVG Scissor 裁剪，确保液体不溢出管内轮廓：

```lua
local surfaceMargin = liqEllipseRY + 10   -- 椭圆半高 + wobble/ripple 余量
nvgIntersectScissor(vg, innerX, straightTop - surfaceMargin,
    innerWidth, surfaceMargin + bodyHeight + innerBallRY)
```

- `surfaceMargin` 向上扩展裁剪区域，为顶弧的椭圆弧线 + wobble/ripple 偏移留出空间
- 球底超出矩形 scissor 范围的处理：球底填充使用 Bézier 路径自身裁剪（路径天然限制在弧线内）
- 顶层液面高光（第 8 步）使用**独立的 Scissor**，在管口椭圆之后绘制

### 为什么液面高光在管口之后绘制（第 8 步）

管口椭圆的内圈暗色填充（`nvgRGBA(8, 8, 18, 220)`）会遮挡位于管口区域的液面高光。将液面高光移至管口之后绘制，确保高光叠加在管口内圈之上，视觉上正确呈现"管口内液面可见"的效果。

---

## 10. 推导值计算时机

**问题**：v1 代码在模块顶部执行推导计算，这些值在 `require` 时固化，运行时修改 Config 不会生效。

**解决方案**：封装推导计算为函数，在每次需要时调用。

```lua
local function deriveTubeParams()
    local T = Config.TUBE
    local outerRadius   = T.tubeWidth / 2
    local innerWidth    = T.tubeWidth - 2 * T.wallThickness
    local innerRadius   = innerWidth / 2
    local slotHeight    = T.bodyHeight / Config.CAPACITY
    local rimEllipseRY  = outerRadius * T.ellipticity
    local liqEllipseRY  = innerRadius * T.ellipticity
    local innerBallRY   = T.ballHeight - T.wallThickness
    local totalHeight   = rimEllipseRY * 2 + T.bodyHeight + T.ballHeight

    return {
        outerRadius  = outerRadius,
        innerWidth   = innerWidth,
        innerRadius  = innerRadius,
        slotHeight   = slotHeight,
        rimEllipseRY = rimEllipseRY,
        liqEllipseRY = liqEllipseRY,
        innerBallRY  = innerBallRY,
        totalHeight  = totalHeight,
    }
end
```

---

## 11. AnimationManager 适配

`AnimationManager.triggerPour` 中使用推导值计算管口高度：

```lua
local rimEllipseRY = Config.TUBE.tubeWidth / 2 * Config.TUBE.ellipticity
toY = toPos.y + rimEllipseRY * 2
```

---

## 12. Config.TUBE 完整结构

```lua
Config.TUBE = {
    tubeWidth     = 50,      -- 试管外径宽度（px）
    wallThickness = 4,       -- 管壁厚度（px）
    bodyHeight    = 144,     -- 直筒段高度（px）= slotHeight × CAPACITY
    ballHeight    = 25,      -- 球底高度（px）= Bézier 弧垂直跨度
    ellipticity   = 0.35,    -- 椭圆度（0~1），管口和液面的椭圆扁度
    liquidAlpha   = 210,     -- 液柱统一透明度（0~255）
    gap           = 20,      -- 试管间距（px）
}
```

---

## 13. 与 v2 的差异对照

| 维度 | v2 | v3 |
|------|-----|-----|
| **液体 slot 形状** | 矩形色块 + 独立椭圆液面 | 桶形封闭路径（底弧 + 左壁 + 顶弧 + 右壁） |
| **液体交界处理** | 矩形边界 + 椭圆弧叠加（存在 alpha 色差） | 相邻桶共享弧线，无重叠 |
| **半椭圆弧工具** | 仅 `semiEllipseCW`（左→右） | 新增 `semiEllipseRTL`（右→左，桶形顶弧） |
| **管壁轮廓闭合** | 水平线 + `nvgClosePath()` | 上半椭圆弧（与管口外圈吻合） |
| **管内衬底闭合** | 水平线 + `nvgClosePath()` | 上半椭圆弧（与管口内圈吻合） |
| **sin 波浪特效** | 有（§5.5 sin 波浪叠加） | 已移除 |
| **顶层液面** | 与液柱在同一步绘制 | 第 8 步，在管口之后绘制 |
| **渲染管线步数** | 6 步 | 9 步 |
| **Scissor 策略** | 基本裁剪 | 含 `surfaceMargin` 上方余量 |
| **`_tubeOutlinePath` 参数** | 6 个 | 8 个（新增 `tubeW`, `rimEllipseRY`） |
| **`_drawInnerBack` 参数** | 6 个 | 8 个（新增 `rimEllipseRY`, `liqEllipseRY`） |
| **`_drawGlassWall` 参数** | 7 个 | 8 个（新增 `rimEllipseRY`） |

---

## 14. 文件清单

| 文件 | 职责 |
|------|------|
| `Config.lua` | TUBE 参数表 + ANIM 动画参数 + COLORS 颜色表 + INITIAL_TUBES 初始数据 |
| `TubeRenderer.lua` | `semiEllipseCW` + `semiEllipseRTL` + `deriveTubeParams` + 所有 `_draw*` 方法 + 9 步渲染管线 |
| `AnimationManager.lua` | 5 阶段倒水动画 + 推导值适配 |
| `GameState.lua` | 游戏逻辑（slot 管理、胜负判断） |
| `InputHandler.lua` | 输入处理（选中、倒水触发） |
| `main.lua` | 入口（场景初始化、事件绑定） |

---

## 15. 参数效果预览

调整参数时的视觉效果变化：

| 参数变化 | 视觉效果 |
|---------|---------|
| `tubeWidth` ↑ | 试管整体变宽 |
| `wallThickness` ↑ | 管壁变厚，内部空间变小 |
| `bodyHeight` ↑ | 试管变长 |
| `ballHeight` ↑ | 球底变深（更尖） |
| `ballHeight` ↓ | 球底变浅（更扁） |
| `ballHeight = outerRadius` | 球底为精确半圆 |
| `ellipticity` ↑ | 管口和液面椭圆更深（更强 3D 感），桶形弧线更明显 |
| `ellipticity = 0` | 管口和液面为直线（退化为矩形 slot） |
| `liquidAlpha` ↑ | 液体更不透明 |
| `liquidAlpha` ↓ | 液体更透明，管壁纹理更可见 |
