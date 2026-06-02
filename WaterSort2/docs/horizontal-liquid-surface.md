# 倾斜试管液面保持水平 — 设计文档

## 问题描述

当试管倾斜时，液体表面应该保持水平（受重力影响）。目前的实现中，`drawTube` 在 NanoVG 的旋转变换内部绘制液体，导致液面随试管一起旋转，视觉上不正确。

## 当前渲染管线

```
main.lua HandleNanoVGRender:
    nvgSave → nvgTranslate(pivot) → nvgRotate(angle) → nvgTranslate(-pivot)
        TubeRenderer.drawTube(...)    ← 所有内容都在旋转坐标系内
            _drawShadow
            _drawInnerBack
            _drawInnerAO
            Scissor clip
            _drawLiquidSlot (桶形液体)  ← 液面随管壁一起旋转（BUG）
            _drawLiquidShading
            _drawFillColumn
            Restore scissor
            _drawGlassWall
            _drawBallHighlight
            _drawRim
            _drawLiquidSurface          ← 液面椭圆也随管壁旋转（BUG）
    nvgRestore
```

## 几何分析

在旋转坐标系（随管壁旋转）中，世界水平面变成一条斜线：

```
                ↑ Y (局部)
                |    /  世界水平线
                |   /   斜率 = tan(tiltAngle)
                |  /    (当管顺时针旋转时)
                | /
    ────────────+────────── X (局部)
                |
```

- 管顺时针旋转 `angle` 度时，局部坐标中水平线斜率 = `tan(angle)`
- 方向：顺时针旋转（正角度）→ 水平线在局部坐标中从左到右**上升**
- 对于管内液面：在局部坐标中，液面应为一条斜线而非水平线

### 关键公式

设管中心 X 轴为原点（cx），倾斜角为 `angle`（弧度），则：

```
局部坐标中水面 Y 偏移(x) = -(x - cx) * tan(angle)
```

- `x` 是管壁内 X 坐标（范围 [innerX, innerX + innerWidth]）
- 负号是因为在局部坐标中，管向右倾斜时，液面左高右低

### 液面高度约束

倾斜改变的是液面形状，不改变液体体积。体积守恒意味着：
- 斜面通过液体段中点时，面积不变（水平截面积一阶近似等于矩形，中心线处体积对称）
- 简化处理：**斜面仍通过原水平液面中心**（即 slotY 不变），只是两侧一高一低

### 边界情况：液面接触管壁顶部/底部

当倾斜角较大时，斜面可能超出液体段的顶部或底部：
- 左端液面 `Y_left = centerY - halfWidth * tan(angle)`
- 右端液面 `Y_right = centerY + halfWidth * tan(angle)`
- 需要 clamp 到 [slotBottom, straightTop] 范围

当前 `tiltAngle = 40°` + `innerWidth ≈ 44px` → 半宽 22px → 偏移 ≈ `22 * tan(40°) ≈ 18.5px`
每格高度 `slotHeight = 55px`，所以偏移不会超出单格高度，无需复杂裁剪。

## 设计方案

### 核心思路：传递 tiltAngle 到 drawTube，在局部坐标系内绘制斜面

不改变现有的 NanoVG 旋转变换架构。在 `drawTube` 的 `opts` 中新增 `tiltAngle` 参数，液体绘制函数内部用 `tan(tiltAngle)` 计算斜面。

### 影响范围

| 函数 | 修改内容 |
|------|---------|
| `drawTube` | 接收 `opts.tiltAngle`，传递给液体绘制函数 |
| `_drawLiquidSlot` | 顶弧从水平线改为斜线 |
| `_drawLiquidSurface` | 椭圆液面改为斜线+透视效果 |
| `_drawLiquidShading` | 液面上缘跟随斜面 |
| `main.lua` | 向 drawTube opts 传递 tiltAngle |

### 实现细节

#### 1. `_drawLiquidSlot` 修改

当前顶弧是：左上圆角 → 半椭圆弧（右到左）→ 右上圆角，全部在同一 Y 坐标。

修改后顶弧变为斜线：
- 左端 Y = `topY - halfSlant`（上移）
- 右端 Y = `topY + halfSlant`（下移）
- `halfSlant = innerRadius * tan(tiltAngle)`
- 最顶层液体组的"顶弧"改为斜线连接（去掉椭圆弧，用直线+轻微曲线）

对于非最顶层的液体组：底弧和顶弧保持原样（液体内部分层线不需要斜面效果）。

**只有最顶层可见液体的顶面需要斜面处理。**

#### 2. `_drawLiquidSurface` 修改

当前是水平椭圆，改为斜线截面：
- 在局部坐标中，液面不再是椭圆，而是倾斜的截面
- 简化处理：当 `|tiltAngle| > 1°` 时，跳过椭圆液面，改为在 `_drawLiquidSlot` 中直接绘制斜面高光

#### 3. 顶层组斜面路径

```
     leftY ●──────────────────● rightY    ← 斜线液面
           │                  │
           │   liquid body    │
           │                  │
           ●──── 底弧 ────────●
```

左壁从 `leftY` 向下，右壁从 `rightY` 向下。
顶面是从右端到左端的直线（或带微微弯曲的 Bezier 弧模拟液面张力）。

## 数据流

```
main.lua
  ├── pour.tiltAngle (AnimationManager 提供)
  └── drawTube(vg, x, y, tube, { ..., tiltAngle = angle })
        └── _drawLiquidSlot(..., tiltAngle)
              └── 最顶层组使用斜面路径
        └── _drawLiquidSurface(..., tiltAngle)
              └── 大倾斜角时用斜线高光替代椭圆
```

## 简化约束

1. **只影响最顶层液面** — 内部分层线保持水平（视觉上多色液体分层线在倾斜时也应该是水平的，但考虑到只有几度的弧面差异且在管壁遮挡下不明显，简化处理）
2. **体积守恒用中心对称近似** — 斜面通过原水平面中心
3. **不处理溢出** — 当前 tiltAngle=40°，偏移约18.5px，不超过 slotHeight=55px
4. **保持桶形路径闭合** — 底弧不变，只修改顶面路径
