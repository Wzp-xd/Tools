# 倒水游戏 - 进阶机制规划文档

> 参考 GearSort demo 的隐藏齿轮、锁定插板、临时插板、沉底插板机制，
> 为倒水排序游戏设计对应的进阶玩法。

---

## 一、机制对照表

| GearSort 机制 | 倒水对应机制 | 核心体验 |
|--------------|-------------|---------|
| Hidden Gear（隐藏齿轮） | **迷雾层**（Hidden Layer） | 信息不完全，需要策略性揭开 |
| Locked Peg（锁定插板） | **封印管**（Locked Tube） | 资源受限，需完成特定目标解锁 |
| Temp Peg（临时插板） | **临时管**（Temp Tube） | 有限容量中转站，必须在通关前清空 |
| Sink Peg（沉底插板） | **单向管**（Sink Tube） | 不可逆的战略选择 |

---

## 二、各机制详细设计

### 2.1 迷雾层（Hidden Layer）

**概念**: 试管底部若干层液体被"迷雾"遮盖，玩家看不到真实颜色。当上方液体被倒走、迷雾层成为最顶层时，自动揭开显示真实颜色。

**数据结构变化**:
```lua
-- tubes 中的颜色值扩展为：
-- 正常颜色: 1, 2, 3, ... (正整数)
-- 隐藏颜色: -1, -2, -3, ... (负数表示隐藏，绝对值为真实颜色)

-- 辅助常量
HIDDEN_MASK = -1  -- color < 0 表示隐藏

-- 判断是否隐藏
function isHidden(color) return color < 0 end

-- 获取真实颜色
function realColor(color) return math.abs(color) end
```

**规则**:
1. 隐藏层渲染为统一的深灰色/迷雾色（带问号或雾气效果）
2. 隐藏层**不可被倒出**——`getTopConsecutiveCount` 遇到隐藏层即停止计数
3. 当隐藏层因上方液体倒走而成为管顶时，**立即揭开**（负数变正数）
4. 揭开时播放短暂动画（雾气消散 + 颜色淡入）
5. 撤销无需特殊处理——快照中保存的是负数值，恢复快照自然还原隐藏状态

**对 GameState 的影响**:
- `getTopColor()`: 如果顶层是隐藏的，返回特殊标记（如 `0` 或 `"hidden"`）
- `getTopConsecutiveCount()`: 遇到隐藏层停止
- `canPour()`: 隐藏层在管顶时不可作为源
- `executePour()`: 倒出后检查新管顶是否为隐藏层，若是则揭开（负数变正数）
- `saveUndoState()` / `undo()`: 无需额外逻辑，快照天然保存隐藏状态

**⚠️ `realColor()` 必须覆盖的位置**（所有颜色比较都必须用 `realColor()`）:
```lua
-- canPour: 判断源/目标颜色是否匹配
if dstTop ~= nil and realColor(dstTop) ~= realColor(src[#src]) then return false end

-- getTopConsecutiveCount: 连续同色计数
if realColor(tube[i]) == realColor(topColor) and not isHidden(tube[i]) then ...

-- checkWin: 判断纯色管
local first = realColor(tube[1])
for j = 2, #tube do
    if realColor(tube[j]) ~= first then return false end
end
```

**渲染影响**:
- `Renderer/Liquid.lua`: 隐藏层使用统一颜色（深灰 + 半透明雾气纹理）
- 新增揭开动画（Alpha 淡入 + 问号粒子飘散）

---

### 2.2 封印管（Locked Tube）

**概念**: 部分试管被"封印"锁住，玩家不能对其执行任何操作（不能选中，不能作为源或目标）。当某个特定颜色被完全排序完成（某管满4层纯色）时，该封印管解锁。

**数据结构变化**:
```lua
-- config.lua 关卡配置（声明式数组）:
Config.levels[n] = {
    tubes = 8, colors = 5, empty = 2,
    locks = { { tube = "auto", color = "auto" } },  -- 生成器自动分配
}

-- GameState 运行时（O(1) 查找字典，由 loadLevel 时转换）:
self.locks = {}  -- { [tubeIdx] = colorIdx } 解锁条件：完成该颜色即解锁此管
```

> **配置 → 运行时转换**: `loadLevel()` 中将配置数组 `locks[]` 转为 `self.locks` 字典，供 `isLocked()` O(1) 查询。

**规则**:
1. 锁定管上方显示锁图标 + 解锁颜色提示（如彩色锁扣）
2. 锁定管**完全不可交互**——不可选中、不可作为源或目标
3. 解锁条件：场上任意一管完成了指定颜色的排序（4层纯色）
4. 解锁时播放动画（锁碎裂 + 管体亮起）
5. 解锁后立即检查管顶是否有隐藏层需要揭开

**对 GameState 的影响**:
- `canPour(src, dst)`: 如果 src 或 dst 被锁，返回 false
- `select(tubeIdx)`: 锁定管不可选中
- `executePour()` / `checkWin()`: 倒完后检查是否有管完成纯色 → 触发解锁
- 新增 `checkUnlocks()`: 扫描所有锁，检查解锁条件
- 新增 `isLocked(tubeIdx)`: 快捷判断

**关卡生成 - 死锁防护**:
- 锁定管内的液体不能包含"解锁钥匙色"（否则死锁）
- 解锁色**至少有 1 层**位于非锁定管的**顶部或近顶位置**（保证初始状态有操作空间）
- 封印管的解锁色**绝不能只存在于其他封印管中**
- 如果有多个封印管，它们的解锁色不能形成**循环依赖**（A 解锁需完成色X，B 解锁需完成色Y，但 X 全在 B 里、Y 全在 A 里）

**渲染影响**:
- 锁定管上方绘制锁链/锁图标
- 管体整体变暗 + 添加锁纹理叠加
- 解锁动画：锁碎裂粒子 + 管体 Alpha 恢复

---

### 2.3 临时管（Temp Tube）

**概念**: 容量有限的特殊试管，用于临时中转。通关时**必须为空**。支持容量叠加机制。

**容量叠加规则**:
| 获得临时管次数 | 效果 |
|--------------|------|
| 第 1 次 | 创建 1 个容量 1 的临时管 |
| 第 2 次 | 该管容量升为 2 |
| 第 3 次 | 该管容量升为 3 |
| 第 4 次 | 该管容量升为 4（已满级） |
| 第 5 次 | 创建新的容量 1 临时管 |
| 第 6 次 | 新管容量升为 2 ... |

**数据结构变化**:
```lua
-- GameState 新增字段:
self.tempTubes = {}  -- { [tubeIdx] = capacity } 临时管索引 → 当前容量

-- config.lua 关卡配置:
Config.levels[n] = {
    tubes = 9, colors = 6, empty = 2,
    tempTubeCount = 1,  -- 初始临时管数量（每个容量=1）
}
```

**规则**:
1. 临时管初始容量为 1，可通过叠加升至最大 4
2. 渲染为矮小的试管/烧杯/培养皿样式，高度随容量变化
3. 临时管**永远不算完成**——即使满管纯色也不触发"纯色完成"事件
4. **通关条件追加**：所有临时管必须为空
5. 玩家可通过金币/看广告在对局中**购买额外临时管**（触发叠加逻辑）

**对 GameState 的影响**:
- `canPour(src, dst)`: 目标为临时管时，检查当前容量上限
- `getPourCount()`: 目标为临时管时，受限于 `tempTubes[dstIdx]` 容量
- `checkWin()`: 所有临时管必须为空
- 新增 `isTempTube(tubeIdx)`: 判断
- 新增 `getTempCapacity(tubeIdx)`: 获取临时管当前容量
- 新增 `addTempTube()`: 购买道具时的叠加逻辑

```lua
--- 购买/获得临时管（叠加逻辑）
function GameState:addTempTube()
    -- 查找未满级的临时管
    for idx, cap in pairs(self.tempTubes) do
        if cap < 4 then
            self.tempTubes[idx] = cap + 1
            return idx  -- 返回升级的管索引
        end
    end
    -- 全部满级或无临时管，创建新管
    self.tubeCount = self.tubeCount + 1
    local newIdx = self.tubeCount
    self.tubes[newIdx] = {}
    self.tempTubes[newIdx] = 1
    return newIdx
end
```

**渲染影响**:
- 临时管高度随容量动态变化（1格→2格→3格→4格）
- 外形: 更宽更矮的培养皿/烧杯样式（与普通管区分）
- 底座: 特殊颜色底座 + 容量指示（如数字或刻度标记）
- 标签: 沙漏图标

---

### 2.4 单向管（Sink Tube）

**概念**: 只能往里倒，不能从中取出的特殊试管。一旦液体倒入，就无法再取回。倒入规则与普通管相同（颜色必须匹配）。

**数据结构变化**:
```lua
-- GameState 新增字段:
self.sinkTubes = {}  -- Set: { [tubeIdx] = true }

-- 关卡配置:
Config.levels[n] = {
    tubes = 10, colors = 7, empty = 2,
    sinkCount = 1,  -- 单向管数量（从空管中分配）
}
```

**规则**:
1. 单向管**只能接收**液体，不能被选为源
2. 倒入时**执行正常的颜色匹配规则**——只能倒入与管顶同色的液体（空管可接收任意色）
3. 渲染上添加"向下箭头"或"铁栅栏"视觉提示
4. 单向管满4层纯色算完成（可以作为排序终点）
5. 策略性高：由于颜色匹配规则存在，不会出现"误倒不同色导致死局"

**对 GameState 的影响**:
- `canPour(src, dst)`: 如果 src 是单向管，返回 false；目标为单向管时正常检查颜色匹配
- `select(tubeIdx)`: 单向管不可选中（作为源）
- 单向管可以作为目标被倒入（颜色匹配时）
- 新增 `isSinkTube(tubeIdx)`: 判断

**渲染影响**:
- 管口添加铁栅栏/向下箭头覆盖物
- 管体可能略微变暗或添加特殊边框
- 尝试选为源时播放摇头/锁定提示动画

---

## 三、通关条件（统一定义）

**通关判定规则**：场上存在 `colorCount` 个满 4 格纯色管（无论管类型），且所有临时管为空。

```lua
function GameState:checkWin()
    local layerCount = Config.tube.layerCount
    local completedCount = 0

    for i = 1, self.tubeCount do
        local tube = self.tubes[i]
        -- 临时管必须为空
        if self.tempTubes[i] then
            if #tube > 0 then return false end
        elseif #tube == layerCount then
            -- 任意类型管（普通/封印已解锁/单向）满4格纯色即计数
            local first = realColor(tube[1])
            local pure = true
            for j = 2, #tube do
                if realColor(tube[j]) ~= first then pure = false; break end
            end
            if pure then completedCount = completedCount + 1 end
        elseif #tube > 0 then
            -- 非空且不满，未完成
            return false
        end
    end

    return completedCount == self.colorCount
end
```

---

## 四、关卡配置（40关，与 GearSort 对齐）

直接采用 GearSort 的 40 关难度曲线和机制引入节奏，参数映射如下：

| GearSort 参数 | 倒水对应参数 | 说明 |
|--------------|-------------|------|
| `colorCount` | `colors` | 颜色数（每种颜色恰好 4 层） |
| `emptyPegs` | `empty` | 空管数（固定 2） |
| `lockedGroups` | `locks` | 封印管数（0/1/2） |
| `hiddenGears` | `hiddenLayers` | 迷雾层数 |
| `sinkPegs` | `sinkCount` | 单向管数 |
| `tempPeg` | `tempTubeCount` | 临时管数 |

> **管数上限**: 7×2 = 14 管。总管数 = colors + empty + locks ≤ 14

> **迷雾层上限公式**: `(colorCount - 3) × 3`（与 GearSort 一致，部分关卡为体验过渡可突破）

### 完整 40 关配置表

| 关卡 | 阶段 | 颜色 | 封印 | 迷雾 | 单向 | 临时 | 总管数 | 说明 |
|------|------|------|------|------|------|------|--------|------|
| L1 | 教程 | 1 | 0 | 0 | — | — | 3 | 手写教程关 |
| **阶段二：3色** |
| L2 | 入门 | 3 | 0 | 0 | — | — | 5 | 基础引入 |
| L3 | 入门 | 3 | 0 | 3 | — | — | 5 | **迷雾首次出现** |
| L4 | 入门 | 3 | 1 | 0 | — | — | 6 | **封印首次出现** |
| L5 | 入门 | 3 | 1 | 3 | — | — | 6 | 封印 + 迷雾 |
| **阶段三：4色** |
| L6 | 进阶 | 4 | 0 | 0 | — | — | 6 | 4色引入 |
| L7 | 进阶 | 4 | 0 | 3 | — | — | 6 | 迷雾 |
| L8 | 进阶 | 4 | 1 | 0 | — | — | 7 | 封印 |
| L9 | 进阶 | 4 | 0 | 6 | — | — | 6 | 高迷雾 |
| L10 | 进阶 | 4 | 1 | 0 | — | — | 7 | 封印过渡 |
| **阶段四：4色深化** |
| L11 | 中级 | 4 | 0 | 6 | — | — | 6 | 2管满隐 |
| L12 | 中级 | 4 | 1 | 3 | — | — | 7 | 封印 + 迷雾 |
| **阶段五：5色** |
| L13 | 中级 | 5 | 0 | 0 | — | — | 7 | 5色引入 |
| L14 | 中级 | 5 | 0 | 3 | — | — | 7 | 迷雾 |
| L15 | 高级 | 5 | 1 | 6 | — | — | 8 | 封印 + 高迷雾 |
| L16 | 高级 | 5 | 0 | 9 | — | — | 7 | 极高迷雾（体验过渡） |
| **阶段六：6色** |
| L17 | 高级 | 6 | 1 | 3 | — | — | 9 | 6色引入 |
| L18 | 困难 | 6 | 0 | 6 | — | — | 8 | 高迷雾 |
| L19 | 困难 | 6 | 2 | 0 | — | — | 10 | 双封印 |
| **阶段七：7色 + 临时管引入** |
| L20 | 困难 | 7 | 0 | 9 | — | 1 | 9+1 | **临时管首次出现** |
| L21 | 困难 | 7 | 0 | 6 | — | 1 | 9+1 | 迷雾 + 临时 |
| L22 | 挑战 | 7 | 2 | 0 | — | 1 | 11+1 | 双封印 + 临时 |
| **阶段八：8色** |
| L23 | 挑战 | 8 | 1 | 3 | — | 1 | 11+1 | 三重机制 |
| L24 | 挑战 | 8 | 0 | 6 | — | 1 | 10+1 | 高迷雾 + 临时 |
| L25 | 大师 | 8 | 1 | 6 | — | 1 | 11+1 | 封印 + 高迷雾 + 临时 |
| **阶段九：9色** |
| L26 | 大师 | 9 | 2 | 3 | — | 1 | 13+1 | 双封印 + 临时 |
| L27 | 大师 | 9 | 0 | 9 | — | 1 | 11+1 | 极高迷雾 |
| L28 | 大师 | 9 | 2 | 3 | — | 1 | 13+1 | 双封印 + 迷雾 |
| **阶段十：10色** |
| L29 | 专家 | 10 | 0 | 6 | — | 1 | 12+1 | 10色引入 |
| L30 | 专家 | 10 | 0 | 9 | — | 1 | 12+1 | 高迷雾 |
| L31 | 专家 | 10 | 2 | 0 | — | 1 | 14+1 | 双封印（管数上限） |
| L32 | 专家 | 10 | 0 | 15 | — | 1 | 12+1 | 极限迷雾 |
| **阶段十一：10色 + 单向管引入** |
| L33 | 地狱 | 10 | 2 | 6 | — | 1 | 14+1 | 双封印 + 高迷雾 |
| L34 | 地狱 | 10 | 0 | 9 | — | 1 | 12+1 | 极高迷雾 |
| L35 | 地狱 | 10 | 2 | 0 | 1 | 1 | 14+1 | **单向管首次出现** |
| L36 | 地狱 | 10 | 1 | 3 | — | 1 | 13+1 | 封印 + 迷雾 |
| **阶段十二：终极（全机制）** |
| L37 | 终极 | 10 | 2 | 0 | 1 | 1 | 14+1 | 双封印 + 单向 |
| L38 | 终极 | 10 | 0 | 6 | 1 | 1 | 12+1 | 高迷雾 + 单向 |
| L39 | 终极 | 10 | 1 | 6 | 1 | 1 | 13+1 | 全机制 |
| L40 | 终极 | 10 | 2 | 6 | 1 | 1 | 14+1 | **最终关·满配** |

> 注：总管数中 "+1" 表示额外的临时管（不计入常规管数上限）。

### 机制引入时间线

```
L1      教程（手写）
L3      迷雾层首次出现
L4      封印管首次出现
L20     临时管首次出现
L35     单向管首次出现
L40     全部机制满配
L41+    无限关卡（随机组合）
```

### 难度递进约束

- `lockedGroups` 最高 2
- `hiddenLayers` 最高 `(colorCount - 3) × 3`（部分过渡关可突破）
- `colorCount` 最高 10
- `sinkCount` 最高 1
- `tempTubeCount` 固定 1（玩家可通过购买叠加容量）

---

## 五、实现优先级与依赖关系

```
Phase 1: 迷雾层（最小改动，最大趣味提升）
  ├── 修改 GameState 支持负数颜色
  ├── 修改 canPour / getTopConsecutiveCount（使用 realColor）
  ├── 修改 Renderer/Liquid.lua 迷雾渲染
  ├── 添加揭开动画（加入动画队列）
  └── 修改 LevelGenerator 分配迷雾层

Phase 2: 封印管（中等改动，增加策略深度）
  ├── GameState 添加 locks 字段和解锁逻辑
  ├── 修改 canPour / select
  ├── 添加锁渲染和解锁动画（加入动画队列）
  ├── 修改 LevelGenerator 确保可解性（死锁防护规则）
  └── 实现动画链: 倒水 → 揭雾 → 解锁检查 → 解锁动画

Phase 3: 临时管（较小改动，增加辅助工具感）
  ├── GameState 添加 tempTubes 字段和容量叠加逻辑
  ├── 修改容量检查和胜利条件
  ├── 添加动态高度的临时管渲染样式
  └── 添加购买临时管的 UI（触发叠加）

Phase 4: 单向管（最小改动，增加紧张感）
  ├── GameState 添加 sinkTubes 字段
  ├── 修改 canPour / select（保留颜色匹配规则）
  ├── 添加铁栅栏渲染
  └── 修改 LevelGenerator
```

---

## 六、数据结构全览（改造后的 GameState）

```lua
function GameState.new()
    local self = setmetatable({}, GameState)
    
    -- 基础字段（已有）
    self.tubes = {}           -- { [tubeIdx] = { color1, color2, ... } }
    self.tubeCount = 0
    self.colorCount = 0
    self.selectedTube = nil
    self.level = 1
    self.isAnimating = false
    self.isWin = false
    self.undoStack = {}
    
    -- 新增字段
    self.locks = {}           -- { [tubeIdx] = unlockColorIdx }  运行时字典
    self.tempTubes = {}       -- { [tubeIdx] = capacity }        容量 1~4
    self.sinkTubes = {}       -- { [tubeIdx] = true }
    
    return self
end
```

**颜色编码约定**:
```
 正整数 (1, 2, 3, ...)  → 正常可见颜色
 负整数 (-1, -2, -3, ...) → 隐藏颜色（绝对值为真实色）
 0                         → 保留（不使用）
```

---

## 七、config.lua 关卡配置（与 GearSort 40 关 1:1 对齐）

```lua
Config.levels = {
    -- ========== L1: 教程关（手写）==========
    { type = "manual", colors = 1, tubes = 3, empty = 2,
      tubes_data = { {1,1,1}, {1}, {} } },  -- 把管2的1层移到管1

    -- ========== 阶段二：3色（L2-L5）==========
    { colors = 3, empty = 2 },                                          -- L2: 基础
    { colors = 3, empty = 2, hiddenLayers = 3 },                        -- L3: 迷雾引入
    { colors = 3, empty = 2, lockedCount = 1 },                         -- L4: 封印引入
    { colors = 3, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L5: 封印+迷雾

    -- ========== 阶段三：4色（L6-L10）==========
    { colors = 4, empty = 2 },                                          -- L6: 4色引入
    { colors = 4, empty = 2, hiddenLayers = 3 },                        -- L7: 迷雾
    { colors = 4, empty = 2, lockedCount = 1 },                         -- L8: 封印
    { colors = 4, empty = 2, hiddenLayers = 6 },                        -- L9: 高迷雾
    { colors = 4, empty = 2, lockedCount = 1 },                         -- L10: 封印过渡

    -- ========== 阶段四：4色深化（L11-L12）==========
    { colors = 4, empty = 2, hiddenLayers = 6 },                        -- L11: 2管满隐
    { colors = 4, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L12: 封印+迷雾

    -- ========== 阶段五：5色（L13-L16）==========
    { colors = 5, empty = 2 },                                          -- L13: 5色引入
    { colors = 5, empty = 2, hiddenLayers = 3 },                        -- L14: 迷雾
    { colors = 5, empty = 2, lockedCount = 1, hiddenLayers = 6 },       -- L15: 封印+高迷雾
    { colors = 5, empty = 2, hiddenLayers = 9 },                        -- L16: 极高迷雾（过渡）

    -- ========== 阶段六：6色（L17-L19）==========
    { colors = 6, empty = 2, lockedCount = 1, hiddenLayers = 3 },       -- L17: 6色引入
    { colors = 6, empty = 2, hiddenLayers = 6 },                        -- L18: 高迷雾
    { colors = 6, empty = 2, lockedCount = 2 },                         -- L19: 双封印

    -- ========== 阶段七：7色 + 临时管引入（L20-L22）==========
    { colors = 7, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                     -- L20: 临时管首现
    { colors = 7, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                     -- L21: 迷雾+临时
    { colors = 7, empty = 2, lockedCount = 2, tempTubeCount = 1 },                      -- L22: 双封印+临时

    -- ========== 阶段八：8色（L23-L25）==========
    { colors = 8, empty = 2, lockedCount = 1, hiddenLayers = 3, tempTubeCount = 1 },    -- L23: 三重
    { colors = 8, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                     -- L24: 高迷雾+临时
    { colors = 8, empty = 2, lockedCount = 1, hiddenLayers = 6, tempTubeCount = 1 },    -- L25: 封印+高迷雾+临时

    -- ========== 阶段九：9色（L26-L28）==========
    { colors = 9, empty = 2, lockedCount = 2, hiddenLayers = 3, tempTubeCount = 1 },    -- L26: 双封印+临时
    { colors = 9, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                     -- L27: 极高迷雾
    { colors = 9, empty = 2, lockedCount = 2, hiddenLayers = 3, tempTubeCount = 1 },    -- L28: 双封印+迷雾

    -- ========== 阶段十：10色（L29-L32）==========
    { colors = 10, empty = 2, hiddenLayers = 6, tempTubeCount = 1 },                    -- L29: 10色引入
    { colors = 10, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                    -- L30: 高迷雾
    { colors = 10, empty = 2, lockedCount = 2, tempTubeCount = 1 },                     -- L31: 双封印（管数上限）
    { colors = 10, empty = 2, hiddenLayers = 15, tempTubeCount = 1 },                   -- L32: 极限迷雾

    -- ========== 阶段十一：10色 + sink 引入（L33-L36）==========
    { colors = 10, empty = 2, lockedCount = 2, hiddenLayers = 6, tempTubeCount = 1 },                   -- L33: 双封印+高迷雾
    { colors = 10, empty = 2, hiddenLayers = 9, tempTubeCount = 1 },                                    -- L34: 极高迷雾
    { colors = 10, empty = 2, lockedCount = 2, sinkCount = 1, tempTubeCount = 1 },                      -- L35: 单向管首现
    { colors = 10, empty = 2, lockedCount = 1, hiddenLayers = 3, tempTubeCount = 1 },                   -- L36: 封印+迷雾

    -- ========== 阶段十二：终极（L37-L40）==========
    { colors = 10, empty = 2, lockedCount = 2, sinkCount = 1, tempTubeCount = 1 },                      -- L37: 双封印+单向
    { colors = 10, empty = 2, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },                     -- L38: 高迷雾+单向
    { colors = 10, empty = 2, lockedCount = 1, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },    -- L39: 全机制
    { colors = 10, empty = 2, lockedCount = 2, hiddenLayers = 6, sinkCount = 1, tempTubeCount = 1 },    -- L40: 最终关·满配
}

-- 管数由配置自动计算：tubes = colors + empty + lockedCount
-- 临时管额外追加，不计入 tubes 上限
```

**字段说明**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `colors` | int | 颜色数（每种恰好 4 层）|
| `empty` | int | 空管数（固定 2）|
| `lockedCount` | int? | 封印管数（0/1/2，默认 0）|
| `hiddenLayers` | int? | 迷雾层总数（默认 0）|
| `sinkCount` | int? | 单向管数（0/1，默认 0）|
| `tempTubeCount` | int? | 临时管数（0/1，默认 0）|
| `type` | string? | "manual" 为手写关，否则为生成关 |

---

## 八、无限关卡生成（31+）

与 GearSort 使用相同的配置和机制：基于 GearSort 的无限关卡生成规则，关卡参数按已有节奏递增，机制随机组合。

```lua
Config.infiniteLevelRule = {
    maxColors   = 10,
    maxTubes    = 14,
    emptyMin    = 2,
    emptyMax    = 3,
    colorIncreaseInterval = 3,
    
    -- 机制参数（与 GearSort 对齐）
    mechanics = {
        hiddenLayers = { min = 4, max = 12 },           -- 迷雾层数范围
        lockChance = 0.6,                               -- 封印管出现概率
        maxLocks = 2,                                   -- 最大封印管数
        tempTubeCount = 1,                              -- 临时管数量（固定）
        sinkChance = 0.4,                               -- 单向管出现概率
        sinkCount = 1,                                  -- 最大单向管数
    },
}

--- 获取无限关卡配置
function Config.getInfiniteLevelConfig(level)
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
    }

    -- 封印管（概率出现）
    if math.random() < mech.lockChance then
        local lockCount = math.random(1, mech.maxLocks)
        cfg.locks = {}
        for _ = 1, lockCount do
            table.insert(cfg.locks, { tube = "auto", color = "auto" })
        end
    end

    -- 单向管（概率出现）
    if math.random() < mech.sinkChance then
        cfg.sinkCount = mech.sinkCount
    end

    return cfg
end
```

---

## 九、LevelGenerator 改造要点

### 9.1 生成流程（改造后）

```
1. 基础生成（已有）:
   colorCount × 4 个颜色块 → 洗牌 → 分配到管中
   
2. 分配封印管（新增）:
   - 从有液体的管中选择目标管标记为 locked
   - 为其分配解锁颜色（不能是管内已有的颜色之一）
   - 确保解锁色在非锁定管中能被完成
   - ⚠️ 解锁色至少有 1 层位于非锁定管的顶部或近顶位置
   
3. 分配迷雾层（新增）:
   - 遍历非锁定管，将底部 1~3 层标记为隐藏（负数）
   - 永远不隐藏管顶层
   - 被锁定的管内也可以有隐藏层（30%概率）
   - 总隐藏层数不超过 hiddenLayers 配置值
   
4. 分配单向管（新增）:
   - 从空管中选取，标记为 sink
   
5. 分配临时管（新增）:
   - 额外创建 tempTubeCount 个容量为 1 的空管
   - 追加到管数组末尾
   
6. 可解性验证:
   - 确保非平凡（不是已完成状态）
   - 确保解锁色不在被锁管内（避免死锁）
   - 确保多个封印管不形成循环依赖
```

### 9.2 死锁防护

- 封印管的解锁色**绝不能只存在于其他封印管中**
- 如果有多个封印管，它们的解锁色不能形成**循环依赖**
- 解锁色至少有 1 层位于非锁定管的**顶部或次顶层**（确保初始可操作）

---

## 十、动画系统改造

### 10.1 动画队列支持

引入进阶机制后，单次操作可能触发**连锁动画**。`Animation.lua` 必须支持动画队列：

```
倒水动画 → [揭开迷雾动画] → [解锁检查] → [解锁动画] → [再次揭雾检查]
```

**队列设计**:
```lua
-- Animation 模块新增字段
self.queue = {}  -- { { type = "pour", ... }, { type = "reveal", ... }, ... }
self.currentAnim = nil

--- 入队动画
function Animation:enqueue(animData)
    table.insert(self.queue, animData)
end

--- 每帧更新：当前动画完成后自动推进下一个
function Animation:update(dt)
    if self.currentAnim then
        -- 更新当前动画...
        if self.currentAnim.finished then
            self.currentAnim = nil
            self:dequeue()  -- 推进下一个
        end
    end
end

--- 出队并启动
function Animation:dequeue()
    if #self.queue > 0 then
        self.currentAnim = table.remove(self.queue, 1)
        self.currentAnim:start()
    else
        -- 队列清空，通知 GameState 动画结束
        gameState.isAnimating = false
    end
end
```

**动画类型**:
| 类型 | 时长 | 触发条件 |
|------|------|---------|
| `pour` | 0.3~0.8s | 玩家操作倒水 |
| `reveal` | 0.4s | 倒水后管顶为隐藏层 |
| `unlock` | 0.6s | 完成纯色管且存在对应锁 |
| `win` | 1.2s | 通关 |

### 10.2 玩家快速操作的输入缓冲

引入连锁动画后，单次倒水可能触发 0.4s 揭雾 + 0.6s 解锁 = 总计 1.3s+ 的不可操作窗口。如果完全屏蔽输入，高频操作的熟练玩家会感觉"卡手"。需要引入**输入缓冲（Input Buffer）**机制，在保证状态一致性的前提下提升操作流畅度。

#### 设计原则

| 原则 | 说明 |
|------|------|
| 状态一致性优先 | 缓冲的操作必须基于**动画队列执行完毕后的最终状态**来校验合法性 |
| 缓冲深度有限 | 最多缓冲 **1 次完整操作**（选中源管 + 选中目标管），避免玩家误操作堆积 |
| 可取消 | 缓冲中的操作在执行前如果变为非法（如目标管被解锁后状态变化），静默丢弃并给出轻量提示 |
| 视觉反馈 | 缓冲的选中状态要有区别于正常选中的视觉提示（如半透明高亮） |

#### 状态机

```
┌─────────────────────────────────────────────────────────────┐
│                      输入状态机                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [IDLE] ──点击管──→ [SELECTED] ──点击目标──→ [POUR_EXEC]   │
│    ↑                    │                        │          │
│    │                    │点击自身/无效            │          │
│    │                    ↓                        │          │
│    │               [IDLE]                        │          │
│    │                                             │          │
│    │  ┌──────────动画播放中──────────┐           │          │
│    │  │                              │           │          │
│    │  │  [ANIMATING] ──点击管──→ [BUFFERED_SRC]  │          │
│    │  │       ↑         │            │           │          │
│    │  │       │         │     点击目标管          │          │
│    │  │       │         │            ↓           │          │
│    │  │       │         │    [BUFFERED_FULL]     │          │
│    │  │       │         │            │           │          │
│    │  └───────│─────────│────────────│───────────┘          │
│    │          │         │            │                      │
│    │          │    动画结束      动画结束                     │
│    │          │         │            │                      │
│    │          │         ↓            ↓                      │
│    │          │    丢弃缓冲     校验→执行或丢弃              │
│    │          │         │            │                      │
│    └──────────┴─────────┴────────────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 数据结构

```lua
-- Animation 模块新增字段
self.inputBuffer = {
    src = nil,       -- 缓冲的源管索引（玩家在动画中点击的第一个管）
    dst = nil,       -- 缓冲的目标管索引（玩家在动画中点击的第二个管）
    timestamp = 0,   -- 缓冲时间戳（用于超时丢弃）
}

-- 配置
local INPUT_BUFFER_TIMEOUT = 2.0  -- 缓冲超时（秒），超过则静默丢弃
local INPUT_BUFFER_MAX = 1        -- 最大缓冲操作数
```

#### 核心逻辑

```lua
--- 动画播放中收到玩家点击
function Animation:onTapDuringAnimation(tubeIdx)
    -- 1. 锁定管/封印管点击 → 忽略（即使缓冲也不允许选中非法源）
    if gameState:isLocked(tubeIdx) or gameState:isSinkTube(tubeIdx) then
        return
    end

    -- 2. 还没有缓冲源 → 记录为源
    if self.inputBuffer.src == nil then
        self.inputBuffer.src = tubeIdx
        self.inputBuffer.timestamp = os.clock()
        -- 视觉：半透明高亮该管（区别于正常选中）
        renderer:setBufferedHighlight(tubeIdx, true)
        return
    end

    -- 3. 已有缓冲源，本次点击为目标
    if tubeIdx == self.inputBuffer.src then
        -- 点击自身 → 取消缓冲
        renderer:setBufferedHighlight(self.inputBuffer.src, false)
        self.inputBuffer.src = nil
        return
    end

    self.inputBuffer.dst = tubeIdx
    -- 视觉：目标管也加半透明高亮
    renderer:setBufferedHighlight(tubeIdx, true)
end

--- 动画队列清空时调用（在 dequeue() 的 else 分支中）
function Animation:flushInputBuffer()
    local buf = self.inputBuffer

    -- 超时检查
    if buf.src and (os.clock() - buf.timestamp > INPUT_BUFFER_TIMEOUT) then
        self:clearInputBuffer()
        return
    end

    -- 只有源没有目标 → 转为正常选中状态
    if buf.src and not buf.dst then
        -- 基于最终状态校验源管是否仍可选
        if gameState:canSelect(buf.src) then
            gameState.selectedTube = buf.src
            renderer:setSelectedHighlight(buf.src, true)
        end
        self:clearInputBuffer()
        return
    end

    -- 源 + 目标都有 → 校验并执行
    if buf.src and buf.dst then
        -- ⚠️ 基于动画执行完毕后的真实状态校验
        if gameState:canPour(buf.src, buf.dst) then
            gameState:executePour(buf.src, buf.dst)  -- 触发新一轮动画
        else
            -- 非法操作 → 丢弃 + 轻量提示（管体短暂闪红）
            renderer:flashInvalid(buf.dst)
        end
        self:clearInputBuffer()
        return
    end
end

--- 清空缓冲
function Animation:clearInputBuffer()
    if self.inputBuffer.src then
        renderer:setBufferedHighlight(self.inputBuffer.src, false)
    end
    if self.inputBuffer.dst then
        renderer:setBufferedHighlight(self.inputBuffer.dst, false)
    end
    self.inputBuffer.src = nil
    self.inputBuffer.dst = nil
    self.inputBuffer.timestamp = 0
end
```

#### 修改 dequeue() 以集成输入缓冲

```lua
function Animation:dequeue()
    if #self.queue > 0 then
        self.currentAnim = table.remove(self.queue, 1)
        self.currentAnim:start()
    else
        -- 队列清空 → 先刷新输入缓冲，再决定是否进入 idle
        gameState.isAnimating = false
        self:flushInputBuffer()
    end
end
```

#### 与撤销的交互

| 场景 | 处理 |
|------|------|
| 动画中玩家点击撤销按钮 | **立即清空缓冲** + 清空动画队列 + 执行撤销（跳过剩余动画，直接恢复快照） |
| 缓冲操作执行后玩家撤销 | 正常撤销（缓冲操作已入 undoStack，与普通操作无区别） |

#### 视觉反馈规范

| 状态 | 视觉表现 |
|------|---------|
| 正常选中 | 管体上移 6px + 明亮高亮边框 |
| 缓冲选中（源） | 管体上移 3px + **半透明**高亮边框（alpha 0.5）+ 轻微脉冲 |
| 缓冲选中（目标） | 无位移 + 半透明虚线边框 |
| 缓冲操作被丢弃 | 管体短暂闪红 0.2s + 微震（shake 2px, 0.15s） |

#### 跳过动画（可选增强）

当动画队列中有 **3 个以上**待执行动画时，显示"跳过"按钮：

```lua
--- 跳过所有排队中的动画，立即应用最终状态
function Animation:skipAll()
    -- 立即完成当前动画（跳到终态）
    if self.currentAnim then
        self.currentAnim:finish()  -- 跳到终态，不播放中间帧
        self.currentAnim = nil
    end
    -- 清空队列，逐个应用状态变化但不播放动画
    while #self.queue > 0 do
        local anim = table.remove(self.queue, 1)
        anim:applyStateOnly()  -- 只更新数据，不渲染动画
    end
    gameState.isAnimating = false
    self:flushInputBuffer()
end
```

---

## 十一、渲染层面的改动

### 11.1 迷雾层渲染
- 颜色: `{ 45, 45, 55 }` (深灰)
- 叠加效果: 半透明白色问号图标 或 NanoVG 绘制雾气纹理
- 揭开动画: 0.4s，Alpha 从 1→0 的迷雾 overlay + 真实颜色 Alpha 0→1

### 11.2 封印管渲染
- 管体: 降低亮度到 40%，添加深色叠加
- 锁图标: 管口正上方绘制彩色锁（颜色 = 解锁色）
- 可选: 锁链环绕管身的装饰
- 解锁动画: 0.6s，锁碎裂粒子(8-12个) + 管体亮度恢复 + 轻微弹跳

### 11.3 临时管渲染
- 高度: 随容量动态变化（容量1=标准管1/4，容量4=标准管等高）
- 外形: 更宽更矮的培养皿/烧杯样式
- 底座: 特殊颜色底座 + 容量升级时的缩放动画
- 标签: 沙漏图标 + 容量数字指示

### 11.4 单向管渲染
- 管口: 添加向下箭头 ↓ 或铁栅栏遮罩
- 管身: 略带红色/警告色调
- 交互: 点击时如果试图选为源，播放摇头/锁定提示

---

## 十二、UI/UX 注意事项

1. **新手引导**: 每种新机制首次出现时，弹出简短教程提示
2. **视觉一致性**: 所有特殊效果使用统一的动画曲线和时长标准
3. **可达性**: 隐藏层不能只靠颜色区分，需有额外视觉标记（问号）
4. **撤销兼容**: 所有新机制都必须完整支持撤销操作
5. **道具系统**: 临时管可作为付费道具（支持叠加），重新开始/提示也是

---

## 十三、文件修改清单

| 文件 | 改动内容 |
|------|---------|
| `config.lua` | 新增机制相关配置项、扩展关卡表、无限关卡机制规则 |
| `GameState.lua` | 新增 locks/tempTubes/sinkTubes 字段、修改核心逻辑、统一 `realColor()` |
| `LevelGenerator.lua` | 新增封印/迷雾/单向/临时管分配逻辑、死锁防护 |
| `Animation.lua` | 新增动画队列系统、揭开动画、解锁动画 |
| `Renderer/init.lua` | 协调新增效果层渲染顺序 |
| `Renderer/Liquid.lua` | 迷雾层渲染 |
| `Renderer/GlassTube.lua` | 封印管暗化、锁图标、单向管栅栏、临时管动态高度 |
| `Renderer/Effects.lua` | 揭开粒子、解锁粒子 |
| `main.lua` | 临时管购买UI（含叠加逻辑）、新手引导弹窗、交互规则更新 |

---

## 十四、验收标准

- [ ] 迷雾层: 不可见 → 移走上层 → 自动揭开 → 可操作
- [ ] 封印管: 不可交互 → 完成指定色 → 解锁动画 → 可操作
- [ ] 临时管: 容量叠加（1→2→3→4→新管）→ 中转 → 通关时必须为空
- [ ] 单向管: 只进不出 → 颜色匹配规则正常 → 满管纯色算完成
- [ ] 通关判定: colorCount 个满4格纯色管（无论管类型）+ 临时管全空
- [ ] 撤销: 所有机制变化均可撤销（快照自然兼容）
- [ ] 动画队列: 倒水→揭雾→解锁 连锁动画顺序正确，不跳帧
- [ ] 死锁防护: 封印管解锁色可达、无循环依赖
- [ ] 无限关卡: 31+ 关正确应用随机机制组合
- [ ] 性能: 新增渲染不影响 60fps
