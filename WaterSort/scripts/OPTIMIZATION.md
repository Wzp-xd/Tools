# 水排序游戏 - 代码优化方案

## 项目现状

| 文件 | 行数 | 职责 |
|------|------|------|
| main.lua | 416 | 入口、UI 构建、游戏主循环、Canvas 渲染、动画源试管绘制 |
| Renderer.lua | 1174 | 试管渲染（玻璃外壳、液体层、倾斜水面、水流、粒子、文字） |
| Animation.lua | 273 | 动画状态机（倾倒、抖动、选中偏移、胜利粒子） |
| GameState.lua | 177 | 游戏逻辑（选管、倒水判定、胜利检测、撤销） |
| LevelGenerator.lua | 124 | 关卡生成（洗牌 + 混乱度评分） |
| config.lua | 240 | 配置表（几何、交互、动画、颜色主题、关卡数据） |
| **合计** | **2404** | |

---

## 一、模块化拆分建议

### 1.1 Renderer.lua (1174 行) - 建议拆分

当前 `Renderer.lua` 承担了所有绘制职责，超过 1000 行阈值，建议按功能拆分：

| 新模块 | 提取内容 | 预估行数 |
|--------|---------|---------|
| `Renderer/GlassTube.lua` | 玻璃外壳绘制（tubeOutlinePath、drawShadow、drawInnerBack、drawInnerAO、drawGlassWall、drawRim、drawBottomHighlight） | ~280 |
| `Renderer/Liquid.lua` | 静态液体层 + 分界椭圆 + 液面椭圆（drawStaticTubeLayers、drawBoundaryEllipse、drawLiquidSurfaceEllipse） | ~200 |
| `Renderer/TiltedWater.lua` | 倾斜水面绘制（drawTiltedWater + computeRotatedOutline + findHorizontalIntersections + Sutherland-Hodgman 裁剪） | ~350 |
| `Renderer/Effects.lua` | 水流 + 胜利粒子 + 文字（drawWaterStream、drawWinParticles、drawWinText） | ~120 |
| `Renderer/init.lua` | 公共接口 + 布局计算 + 几何工具（getTubePositions、deriveTubeParams、semiEllipseCW 等） | ~220 |

**好处**：
- 每个文件 < 350 行，易于定位和修改
- 修改液体效果不需要翻阅玻璃渲染代码
- 未来扩展（如添加新的容器形状）更加灵活

### 1.2 main.lua (416 行) - 建议提取 InputHandler

`main.lua` 中 `GameCanvas:drawAnimSource` 方法（~90 行）本质上是动画渲染逻辑，与 UI 入口混在一起。建议：

| 新模块 | 提取内容 | 预估行数 |
|--------|---------|---------|
| `InputHandler.lua` | hitTestTube + handleTubeTap + 点击事件分发 | ~60 |

提取后 main.lua 只保留：UI 构建 + 引擎入口 + Update 循环。

---

## 二、性能优化建议

### 2.1 deriveTubeParams 缓存失效机制

**现状**：`_cachedParams` 一旦计算就永不更新，但如果未来支持动态修改 `Config.tube` 参数（如管宽变化），缓存会过期。

**建议**：当前不需改动（Config 是静态的），但可在 Config 中加一个 version 计数器，deriveTubeParams 对比 version 判断是否需重算。优先级低。

### 2.2 Renderer.getTubePositions 每帧重复计算

**现状**：每帧 Render 和 hitTestTube 各调用一次 `getTubePositions`，都做数学计算。

**建议**：缓存布局结果，仅在 tubeCount 或 canvas 尺寸变化时重算：

```lua
local _posCache = { w = 0, h = 0, count = 0, result = nil }

function Renderer.getTubePositions(canvasW, canvasH, tubeCount)
    if _posCache.w == canvasW and _posCache.h == canvasH and _posCache.count == tubeCount then
        return _posCache.result
    end
    -- ... 计算 ...
    _posCache = { w = canvasW, h = canvasH, count = tubeCount, result = positions }
    return positions
end
```

**收益**：减少每帧数十次乘除法运算（管数多时更明显）。

### 2.3 drawTiltedWater 中的轮廓采样和裁剪

**现状**：每帧对动画源管重新生成 10 点椭圆弧 + Sutherland-Hodgman 多次裁剪。

**建议**：
- 椭圆弧采样点数 (SAMPLES=10) 在当前管径下已足够，不建议增加
- 如果性能成为瓶颈，可将 `computeRotatedOutline` 的结果缓存到 anim 对象中，仅当角度变化超过阈值时重算
- 当前管数 <= 14，性能不是问题，优先级低

### 2.4 NanoVG 路径复用

**现状**：`drawGlassWall` 中同一个 `tubeOutlinePath` 被绘制 6 次（底色 + 4 层渐变 + 描边），每次都重新构建贝塞尔路径。

**建议**：NanoVG 不支持路径缓存（每帧重绘），这是该 API 的固有限制。但可以考虑：
- 将多层渐变合并为更少的 pass（例如用多段 nvgLinearGradient 叠加替代独立 fill）
- 当前帧率若 > 60fps，无需优化

---

## 三、代码质量优化

### 3.1 魔法数字提取到 Config

以下硬编码值散落在代码中，建议收入 `Config`：

| 位置 | 硬编码值 | 建议配置项 |
|------|---------|-----------|
| Renderer.lua:drawBoundaryEllipse | `0.80`, `0.35` | `liquid.boundaryRadiusRatio`, `liquid.boundaryDarken` |
| Renderer.lua:drawLiquidSurfaceEllipse | `0.90`, `+40` | `liquid.surfaceRadiusRatio`, `liquid.surfaceBrighten` |
| main.lua:选中光圈 | `8`, `6`, `5`, `3` | `render.selectGlowOffsetY`, `render.selectGlowInnerPad` |
| main.lua:hitTestTube | `padX=8`, `padY=12` | `interaction.hitPadX`, `interaction.hitPadY` |

### 3.2 drawAnimSource 可读性

`GameCanvas:drawAnimSource`（main.lua:175-260）包含大量 pour phase 分支计算，建议：
- 将坐标计算逻辑提取为 `Animation:getSourceTransform(positions, layout)` 方法
- 返回 `{ cx, cy, angle, pivotWX, pivotWY }` 结构

### 3.3 重复的颜色变暗/变亮逻辑

`drawBoundaryEllipse` 和 `drawLiquidSurfaceEllipse` 中都有手动 clamp 颜色计算：

```lua
math.floor(clamp(color[1] * 0.35, 0, 255))
math.floor(clamp(color[1] + 40, 0, 255))
```

**建议**：提取为工具函数：

```lua
local function darkenColor(color, factor)
    return {
        math.floor(clamp(color[1] * factor, 0, 255)),
        math.floor(clamp(color[2] * factor, 0, 255)),
        math.floor(clamp(color[3] * factor, 0, 255)),
    }
end

local function lightenColor(color, amount)
    return {
        math.floor(clamp(color[1] + amount, 0, 255)),
        math.floor(clamp(color[2] + amount, 0, 255)),
        math.floor(clamp(color[3] + amount, 0, 255)),
    }
end
```

### 3.4 LevelGenerator 可解性保证

**现状**：`generateQuality` 使用"混乱度评分"选择布局，但不保证关卡可解。

**建议**：添加 BFS/DFS 可解性验证（可选，因为水排序谜题在有 2 个空管时几乎总是可解）：

```lua
--- 简单可解性检查（有限步 DFS）
function LevelGenerator.isSolvable(tubes, maxSteps)
    -- BFS 搜索是否存在解法
    -- 状态空间可能较大，建议限制 maxSteps = 200
end
```

优先级低 —— 当前 2 空管 + 混乱度筛选已能提供良好体验。

---

## 四、功能扩展建议（非必须）

| 功能 | 说明 | 复杂度 |
|------|------|--------|
| 音效系统 | 倒水声、选中声、胜利声 | 低 |
| 主题切换 UI | config.lua 已有 pastel 主题，但没有切换入口 | 低 |
| 关卡进度存档 | 使用 File API 保存当前关卡 | 低 |
| 提示系统 | 高亮可倒的试管对 | 中 |
| 管数动态变化动画 | 关卡切换时管子的入场/退场动画 | 中 |

---

## 五、优先级排序

| 优先级 | 优化项 | 收益 |
|--------|--------|------|
| P0 | Renderer.lua 模块化拆分 | 可维护性大幅提升 |
| P1 | 魔法数字提取到 Config | 配置集中、调参方便 |
| P1 | getTubePositions 缓存 | 性能微优化 + 代码整洁 |
| P2 | 颜色工具函数提取 | 减少重复代码 |
| P2 | drawAnimSource 重构 | 可读性提升 |
| P3 | InputHandler 提取 | main.lua 更清晰 |
| P3 | 可解性验证 | 用户体验保障 |

---

## 六、建议执行顺序

1. **Renderer.lua 拆分为 5 个子模块**（P0，影响最大）
2. **魔法数字收入 Config + 颜色工具函数**（P1，一起做）
3. **getTubePositions 缓存**（P1）
4. **drawAnimSource 重构为 Animation 方法**（P2）
5. **InputHandler 提取**（P3，可选）
