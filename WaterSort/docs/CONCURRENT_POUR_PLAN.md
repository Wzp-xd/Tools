# 并发倒水系统设计方案（v2 修正版）

## 需求

当前：倒水动画期间所有瓶子不可操作（全局 `isAnimating` 锁）。

目标：
1. 正在倒水的**源瓶**和**目标瓶**不可被选为源瓶倒出
2. 其他瓶子可以正常选中、倒水
3. 允许多个瓶子**同时**向同一个瓶子倒水（只要颜色匹配且容量足够）

---

## 核心设计原则

1. **数据先行，动画后行** — 发起倒水时立即修改管数据（移除源层、写入目标层），动画仅为视觉表现
2. **目标管可接收不可倒出** — 目标管不用布尔锁，用接收计数器，阻止倒出但允许继续接收
3. **预期颜色追踪** — 记录目标管即将到达的顶色，后续倒入必须匹配预期色

---

## 核心改动

### 1. 管级锁定（区分源锁与接收状态）

```lua
-- GameState 新增字段
self.sourceLocked = {}   -- { [tubeIdx] = true } 正在作为源瓶倒出（不可选为源）
self.receivingCount = {} -- { [tubeIdx] = int }  正在接收的动画数（>0 时不可作为源）

-- 判断管是否可被选为源瓶
function GameState:canSelectAsSource(tubeIdx)
    if self.sourceLocked[tubeIdx] then return false end
    if (self.receivingCount[tubeIdx] or 0) > 0 then return false end
    return true
end

-- 判断管是否可作为目标（始终可以，只要颜色和容量允许）
-- 不需要额外锁检查，canPour 内部处理颜色和容量

function GameState:lockSource(tubeIdx)
    self.sourceLocked[tubeIdx] = true
end

function GameState:unlockSource(tubeIdx)
    self.sourceLocked[tubeIdx] = nil
end

function GameState:addReceiving(tubeIdx)
    self.receivingCount[tubeIdx] = (self.receivingCount[tubeIdx] or 0) + 1
end

function GameState:removeReceiving(tubeIdx)
    local c = (self.receivingCount[tubeIdx] or 0) - 1
    self.receivingCount[tubeIdx] = c > 0 and c or nil
end
```

### 2. 数据先行 — 发起时即提交状态变更

```lua
-- 发起倒水时立即执行：
function GameState:commitPour(srcIdx, dstIdx)
    local pourCount = self:getPourCount(srcIdx, dstIdx)
    if pourCount <= 0 then return nil end

    -- 推入 undo 快照（在数据变更前）
    self:pushUndo()

    -- 从源管顶部移除 pourCount 层
    local layers = {}
    for i = 1, pourCount do
        layers[i] = table.remove(self.tubes[srcIdx])
    end

    -- 写入目标管顶部
    for i = pourCount, 1, -1 do
        table.insert(self.tubes[dstIdx], layers[i])
    end

    -- 锁定源管、增加目标接收计数
    self:lockSource(srcIdx)
    self:addReceiving(dstIdx)

    return {
        srcIdx = srcIdx,
        dstIdx = dstIdx,
        pourCount = pourCount,
        layers = layers,  -- 动画渲染用（颜色信息）
    }
end
```

**优点**：所有后续逻辑（canPour、checkUnlocks、checkWin）始终基于准确的管数据，无时序错乱。

### 3. canPour 颜色匹配（基于实时数据）

由于数据先行，目标管的顶色始终是真实的当前顶色（含已提交但动画未完成的层）。无需额外的 `reservedColor` 追踪。

```lua
function GameState:canPour(srcIdx, dstIdx)
    -- 源管不能为空
    if #self.tubes[srcIdx] == 0 then return false end

    -- 源管不能是单向管
    if self.sinkTubes[srcIdx] then return false end

    -- 目标管容量检查（实时数据，无需预扣）
    local maxCap = self.tempTubes[dstIdx] or Config.tube.layerCount
    if #self.tubes[dstIdx] >= maxCap then return false end

    -- 目标管为空 → 可以倒
    if #self.tubes[dstIdx] == 0 then return true end

    -- 颜色匹配：源顶色 == 目标顶色（均取真实色）
    local srcTop = GameState.realColor(self.tubes[srcIdx][#self.tubes[srcIdx]])
    local dstTop = GameState.realColor(self.tubes[dstIdx][#self.tubes[dstIdx]])
    return srcTop == dstTop
end

function GameState:getPourCount(srcIdx, dstIdx)
    local maxCap = self.tempTubes[dstIdx] or Config.tube.layerCount
    local available = maxCap - #self.tubes[dstIdx]

    local srcTube = self.tubes[srcIdx]
    local topColor = GameState.realColor(srcTube[#srcTube])

    local count = 0
    for i = #srcTube, 1, -1 do
        if GameState.realColor(srcTube[i]) == topColor and count < available then
            count = count + 1
        else
            break
        end
    end
    return count
end
```

### 4. 动画系统 — 多活跃动画列表

```lua
-- Animation 改造
self.activeAnims = {}  -- { {srcIdx, dstIdx, pourCount, layers, progress, ...}, ... }

function Animation:startPour(pourInfo)
    -- pourInfo 来自 GameState:commitPour() 的返回值
    local anim = {
        type = "pour",
        srcIdx = pourInfo.srcIdx,
        dstIdx = pourInfo.dstIdx,
        pourCount = pourInfo.pourCount,
        layers = pourInfo.layers,
        progress = 0,
        -- ... 其他动画参数（倾斜角度、水流位置等）
    }
    table.insert(self.activeAnims, anim)
end

function Animation:update(dt)
    for i = #self.activeAnims, 1, -1 do
        local a = self.activeAnims[i]
        local done = self:updateSingle(a, dt)
        if done then
            self:onAnimComplete(a)
            table.remove(self.activeAnims, i)
        end
    end
end

function Animation:hasActiveAnims()
    return #self.activeAnims > 0
end
```

### 5. 动画完成后处理

```lua
function Animation:onAnimComplete(a)
    local game = self.game

    -- 1. 解锁源管、减少目标接收计数
    game:unlockSource(a.srcIdx)
    game:removeReceiving(a.dstIdx)

    -- 2. 后处理链（揭雾、解锁检查）
    game:revealTopIfHidden(a.srcIdx)
    local unlocked = game:checkUnlocks()
    if unlocked then
        game:revealTopIfHidden(unlocked.tubeIdx)
    end

    -- 3. 胜利检查（所有动画完成时才判定）
    if #self.activeAnims == 0 and game:checkWin() then
        game.isWin = true
        self:startWin()
    end
end
```

### 6. 交互逻辑（main.lua handleTubeTap）

```
点击瓶 T:
  if 无选中瓶:
      if T 可选为源 (canSelectAsSource + canSelect原有逻辑):
          选中 T
      else:
          抖动反馈
  else (已有选中瓶 S):
      if T == S → 取消选中
      if canPour(S, T):
          pourInfo = game:commitPour(S, T)   -- 数据立即提交
          anim:startPour(pourInfo)            -- 启动视觉动画
          取消选中
      else if T 可选为源:
          切换选中到 T（换选）
      else:
          抖动 T，取消选中
```

注意：不再检查目标管 busy 状态。只要 `canPour` 通过（颜色匹配 + 容量足够），就允许倒入。

---

## Undo 策略

**规则：有动画进行中时禁止 undo。**

原因：
- 数据已先行提交，动画只是视觉过渡
- 如果允许动画中 undo，需要取消所有进行中动画 + 回滚多步数据，极易出错
- 用户体验上，动画很短（<1秒），等动画结束再 undo 完全可接受

```lua
function handleUndo()
    if anim:hasActiveAnims() then
        -- 忽略或给出提示音
        return
    end
    game:popUndo()
end
```

---

## 渲染适配

### 多管同时倾斜

```lua
-- 渲染循环中：
-- 1. 正常渲染所有非动画中的管（使用实时管数据）
-- 2. 对每个 activeAnim，渲染对应源管的倾斜动画 + 水流粒子

-- 关键：源管数据已被移除，动画需要用 anim.layers 信息渲染"正在倒出的液体"
-- 目标管数据已写入，但动画期间目标管顶部新层可以用渐显/下落效果表现
```

### 源管渲染

源管数据已扣除层，静态渲染时自然少了顶部几层。倾斜动画额外渲染"飞出的液体"用 `anim.layers` 的颜色。

### 目标管渲染

目标管数据已写入新层，可以：
- **方案 A**（简单）：直接渲染完整数据，新层瞬间出现
- **方案 B**（细腻）：新层带一个短下落/渐入动画，动画期间用 alpha 过渡

---

## 实现步骤

1. **GameState 改造**：
   - 移除 `isAnimating` 全局锁
   - 添加 `sourceLocked`、`receivingCount`
   - 添加 `canSelectAsSource()`
   - 重写 `commitPour()` — 数据先行
   - 修改 `canPour()`、`getPourCount()` — 基于实时数据

2. **Animation 改造**：
   - `activeAnims` 列表替代单动画
   - `startPour(pourInfo)` 接收 commitPour 返回的信息
   - `update(dt)` 遍历更新
   - `onAnimComplete(a)` 解锁 + 后处理
   - `hasActiveAnims()` 供 undo/win 检查

3. **main.lua 交互改造**：
   - `handleTubeTap` 使用 `canSelectAsSource` 替代 busy 检查
   - 倒水流程：`commitPour` → `startPour`
   - Undo 按钮检查 `hasActiveAnims()`

4. **Renderer 适配**：
   - 支持多管同时倾斜（遍历 activeAnims）
   - 源管用扣除后数据 + 动画浮层
   - 目标管用完整数据（可选渐入效果）

5. **测试场景**：
   - A→C 动画中，B→C 发起（同色）→ 应成功
   - A→C 动画中，B→C 发起（异色）→ 应被 canPour 拒绝
   - A→C 动画中，点击 A → 不可选（sourceLocked）
   - A→C 动画中，点击 C 作为源 → 不可选（receivingCount > 0）
   - A→C 动画中按 undo → 忽略
   - 两个动画同帧完成 → 顺序执行 onAnimComplete，各自安全

---

## 边界情况

| 场景 | 处理 |
|------|------|
| A→C 动画中，B→C（同色） | canPour 检查 C 顶色（已含 A 的层）= B 顶色 → 允许 |
| A→C 动画中，B→C（异色） | canPour 检查 C 顶色 ≠ B 顶色 → 拒绝 |
| A→C 动画中，点击 C 想倒出 | canSelectAsSource → receivingCount>0 → 不可选 |
| A→C 动画中，点击 A 想倒出 | canSelectAsSource → sourceLocked → 不可选 |
| A→C 完成后 C 满了，B→C 检查 | #tubes[C] >= maxCap → canPour 返回 false |
| 两个动画同帧完成 | 逆序遍历 remove，各自 onAnimComplete 独立执行 |
| 动画中按 undo | hasActiveAnims() == true → 忽略 |
| 动画完成触发解锁，解锁管正在接收 | 解锁改 locks 表，不影响动画；接收完成后该管正常可用 |
| 揭雾触发新的 canPour 机会 | 玩家下次点击时自然可用，无需特殊处理 |
| 源管倒空后应可接收 | unlockSource 后，receivingCount=0，canSelectAsSource=true，也可做目标 |
