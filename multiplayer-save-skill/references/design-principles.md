# 架构设计原则

> 从多人游戏存档设计中提炼的 11 条 serverCloud 相关原则。

---

## 1. 可重建状态原则

**只持久化不可从其他数据重建的状态。**

| 存 | 不存 |
|----|------|
| 玩家等级、金币、背包 | 当前生命值（可从等级+装备重算） |
| 建筑位置和类型 | 建筑的视觉表现（客户端渲染） |
| 技能解锁列表 | 技能冷却计时器（运行时状态） |
| 交易记录 | UI 动画状态 |

**判断方法**：如果服务器重启后能从已存数据重新计算出来，就不需要存。

```lua
-- ✅ 存：核心身份和进度
serverCloud:BatchSet(uid)
    :SetInt("level", 10)
    :Set("skills", { "fireball", "heal" })
    :Save("Core data")

-- ❌ 不存：可重建的派生值
-- currentHp = baseHp + equipment.hpBonus  ← 运行时重算即可
-- dps = calculateDPS(level, weapon)       ← 纯函数推导
```

---

## 2. 时间基线原则

**存储事件发生的时间戳，而非剩余时间。**

剩余时间会随着保存时刻不同而不同，恢复后必然不准确。时间戳是绝对值，任何时刻读取都能算出正确的剩余时间。

```lua
-- ❌ 错误：存剩余时间
serverCloud:Set(uid, "crop", { remainSec = 120 })
-- 问题：保存时剩120秒，但恢复时可能已过了60秒，状态不一致

-- ✅ 正确：存时间戳
serverCloud:Set(uid, "crop", {
    plantedAt = os.time(),        -- 种下时间
    growDuration = 300,           -- 总生长时间（秒）
    lastWateredAt = os.time(),    -- 上次浇水时间
})
-- 恢复时：elapsed = os.time() - plantedAt，随时可算出正确进度
```

**延伸**：建筑建造、冷却、每日重置、buff 过期都应存时间戳而非倒计时。

---

## 3. 数据边界原则

**玩家数据与世界数据必须明确分层，不可混存。**

| 层次 | 归属 | serverCloud 存储方式 | 示例 |
|------|------|---------------------|------|
| 玩家数据 | 某个 uid | `serverCloud:Set(uid, ...)` | 等级、金币、背包 |
| 世界数据 | 无归属 | 服务器内存 或 哨兵 UID | 地图状态、公共资源池 |

**为什么重要**：
- 玩家离开时只清理玩家数据，世界数据不受影响
- 新玩家加入时不需要从其他玩家的数据中提取世界信息
- 服务器可以独立管理世界生命周期

**常见错误**：把世界共享状态（如公会基金、地图建筑）存在房主 uid 下。房主退出后世界数据跟着清理，其他玩家看到空世界。

详见 [server-patterns.md](server-patterns.md) §1 世界共享数据。

---

## 4. 三链路分离原则

**在线同步、离线恢复、晚加入重建——三条路径的逻辑必须独立。**

| 链路 | 触发时机 | 数据来源 | 特点 |
|------|---------|---------|------|
| 在线同步 | 游戏运行中 | 服务器内存 | 实时、增量、低延迟 |
| 离线恢复 | 服务器重启 | serverCloud | 全量拉取、回调串联 |
| 晚加入重建 | 新玩家中途加入 | 服务器内存快照 | 一次性发送当前状态 |

```lua
-- 链路1：在线同步 — 增量广播变化
function OnCropGrow(uid, cropId, newStage)
    BroadcastToAll({ action = "crop_update", cropId = cropId, stage = newStage })
    MarkDirty(uid)
end

-- 链路2：离线恢复 — 从 serverCloud 全量重建
function RestorePlayer(uid, connection)
    serverCloud:BatchGet(uid):Key("crops"):Fetch({
        ok = function(scores)
            RebuildCropsFromSave(uid, scores.crops)
        end
    })
end

-- 链路3：晚加入 — 从服务器内存发送快照
function OnLateJoin(uid, connection)
    local snapshot = BuildWorldSnapshot()  -- 当前内存状态
    SendToClient(connection, { action = "world_snapshot", data = snapshot })
end
```

**核心**：不要让三条链路共用同一段代码——它们的数据源、时序、错误处理都不同。

---

## 5. 脏标记 + 批量保存原则

**不要每次状态变化都写云端。标记脏 → 定时批量保存。**

高频写入（如每帧更新分数）会迅速耗尽 300 次/分钟的写入配额。

```lua
local playerDirty = {}  -- uid → true
local SAVE_INTERVAL = 10

function MarkDirty(uid)
    if isRestoring then return end  -- 恢复期不标脏（见原则7）
    playerDirty[uid] = true
end

function FlushDirtyPlayers()
    for uid, dirty in pairs(playerDirty) do
        if dirty then
            serverCloud:BatchSet(uid)
                :SetInt("score", playerCache[uid].score)
                :Set("state", playerCache[uid].state)
                :Save("Periodic save")
            playerDirty[uid] = false
        end
    end
end
```

**保存时机**：
- 定时器（每 5-10 秒）
- 玩家离开（立即 flush）
- 对局结束（最终结算）
- 关键事件（大额交易、重要道具获取）

完整时机清单见原则 8。

---

## 6. 恢复顺序原则

**加载数据时必须遵守依赖关系：被依赖的先加载，依赖者后加载。**

推荐顺序：

```
1. 账号基础信息（等级、名字、权限）
2. 容器/槽位（背包大小、装备槽数量）
3. 固定对象（建筑、技能树）
4. 动态对象（背包物品、宠物、订单）
5. 重建索引和映射（listId → 运行时对象）
6. 开放自动保存和外部事件
```

在 serverCloud 中，因为所有读操作都是异步回调，恢复顺序通过**回调嵌套**实现：

```lua
function LoadPlayerData(uid, connection)
    -- 第一步：加载基础信息（决定后续要加载哪些 key）
    serverCloud:BatchGet(uid):Key("level"):Key("farm_info"):Fetch({
        ok = function(scores, iscores)
            local level = iscores.level or 1
            local farmInfo = scores.farm_info or {}

            -- 第二步：根据等级/农场信息决定加载哪些动态数据
            local keys = { "inventory", "settings" }
            if level >= 5 then table.insert(keys, "guild_data") end

            local bg = serverCloud:BatchGet(uid)
            for _, k in ipairs(keys) do bg:Key(k) end
            bg:Fetch({
                ok = function(scores2)
                    -- 第三步：重建完整状态
                    BuildPlayerState(uid, iscores, scores, scores2)
                    OnLoadComplete(uid, connection)
                end
            })
        end
    })
end
```

**注意**：大多数情况下一次 BatchGet 就够了（把所有 key 一次读完）。只有当后续加载的 key **依赖前面的结果来决定**时，才需要嵌套回调。

---

## 7. 恢复期保护原则 🔴

**恢复期间必须关闭自动保存和对外广播，防止中间态被误写或误播。**

恢复过程中对象经历大量中间态：字段部分赋值、引用尚未建立、索引未重建。如果此时：
- 定时保存触发 → 把半成品状态覆盖回云端，导致数据损坏
- MarkDirty 生效 → 空值/默认值被标记为变更，下次保存时覆盖真实数据
- 对外广播 → 其他玩家收到不完整的状态快照

```lua
local isRestoring = false  -- 恢复保护标记

function MarkDirty(uid)
    if isRestoring then return end  -- 恢复期不标脏
    playerDirty[uid] = true
end

function BroadcastChange(action, data)
    if isRestoring then return end  -- 恢复期不广播
    BroadcastToAll({ action = action, data = data })
end

function LoadPlayerData(uid, connection)
    isRestoring = true  -- 开启保护

    serverCloud:BatchGet(uid):Key("level"):Key("inventory"):Key("settings"):Fetch({
        ok = function(scores, iscores)
            -- 重建状态（期间所有 MarkDirty 和广播被抑制）
            playerCache[uid] = {
                level = iscores.level or 1,
                inventory = scores.inventory or {},
                settings = scores.settings or {},
            }
            RebuildIndices(uid)

            isRestoring = false  -- 关闭保护（必须在最后）

            -- 现在才安全：通知客户端就绪、启用自动保存
            SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
        end,
        error = function(code, reason)
            isRestoring = false
            -- 降级处理...
        end
    })
end
```

**要点**：
- `isRestoring` 必须在**所有恢复回调完成后**才设为 false
- 如果有嵌套回调（原则6），保护期覆盖整个嵌套链
- 定时保存循环中也应检查：`if isRestoring then return end`

---

## 8. 强制保存时机原则

**虽然平时应延迟合批，但以下场景必须立即或尽快落盘。**

| 场景 | serverCloud 操作 | 说明 |
|------|-----------------|------|
| 玩家退出/断线 | `BatchSet` 立即 flush | 离开后无法再补写 |
| 对局/副本结算 | `BatchCommit` | 结算奖励不可丢失 |
| 交易完成 | `BatchCommit` | 跨玩家原子操作 |
| 大额货币变动 | `Money.Add/Cost` | 即时写入，不走脏标记 |
| 动态对象被删除 | `List.Delete` | 删除操作不可逆，立即持久化 |
| 重要道具获取 | `BatchCommit` 或立即 `BatchSet` | 防止掉线丢物品 |
| 跨场景/跨服迁移 | flush 后再切 | 确保目标场景能读到最新数据 |

```lua
-- 通用原则：关键操作直接写，不走 MarkDirty
function OnTrade(sellerUid, buyerUid, itemListId, itemData, price)
    -- 不 MarkDirty，直接 BatchCommit
    local c = serverCloud:BatchCommit("Trade")
    c:MoneyCost(buyerUid, "gold", price)
    c:MoneyAdd(sellerUid, "gold", price)
    c:ListDelete(sellerUid, "inventory", itemListId)
    c:ListAdd(buyerUid, "inventory", itemData)
    c:Commit({ ... })
end

-- 玩家离开时强制 flush
function OnPlayerDisconnect(uid)
    if playerDirty[uid] then
        FlushPlayer(uid)  -- 立即写入，不等定时器
    end
    playerCache[uid] = nil
    playerDirty[uid] = nil
end
```

**口诀**：普通进度可以等定时器，关键资产和不可逆操作必须立即落盘。

---

## 9. 动态对象持久化身份原则

**动态对象必须有稳定的持久化身份，不能只靠运行时索引。**

在 serverCloud 中，`List` 域的每条记录都有一个 `listId`，这就是动态对象的持久化身份。必须在 `List.Add` 的回调中保存这个 listId，并建立运行时对象与 listId 的映射。

```lua
-- 运行时映射表
local cropIdMap = {}  -- runtimeId → listId

-- 创建动态对象时保存 listId
function PlantCrop(uid, slotIndex, cropType)
    local runtimeId = GenerateRuntimeId()
    local cropData = { type = cropType, slot = slotIndex, plantedAt = os.time() }

    serverCloud.list:Add(uid, "crops", cropData, {
        ok = function(listId)
            -- 建立映射：运行时ID → 持久化ID
            cropIdMap[runtimeId] = listId
            cropData.listId = listId  -- 也存一份在内存中
        end
    })
end

-- 修改动态对象时用 listId 定位
function WaterCrop(uid, runtimeId)
    local listId = cropIdMap[runtimeId]
    if not listId then return end  -- 安全检查

    serverCloud.list:Modify(uid, "crops", listId, {
        lastWateredAt = os.time(),
    })
end

-- 删除动态对象时用 listId 精确删除
function HarvestCrop(uid, runtimeId)
    local listId = cropIdMap[runtimeId]
    if not listId then return end

    serverCloud.list:Delete(uid, "crops", listId, {
        ok = function()
            cropIdMap[runtimeId] = nil
        end
    })
end
```

**常见错误**：
- 用数组下标当 ID → 删除一个元素后所有后续下标偏移
- 不保存 listId → 后续 Modify/Delete 无法定位目标记录
- 用随机数当持久化 ID → 重启后映射丢失

**恢复时重建映射**：加载 List 数据后，遍历每条记录的 listId，重建 `cropIdMap`。

---

## 10. 数据版本兼容原则

**持久化数据必须携带版本号，恢复函数能处理旧版本。**

serverCloud 以 KV 存储，数据结构在长期迭代中必然变更（加字段、改含义、拆分/合并 key）。如果不做版本管理，老玩家回归时会读到旧结构的数据，导致字段缺失或类型错误。

```lua
local CURRENT_VERSION = 3

-- 存储时带版本号
function SavePlayerState(uid)
    serverCloud:Set(uid, "character", {
        _v = CURRENT_VERSION,
        name = playerCache[uid].name,
        class = playerCache[uid].class,
        talents = playerCache[uid].talents,      -- v2 新增
        achievements = playerCache[uid].achievements, -- v3 新增
    })
end

-- 恢复时做版本迁移
function MigrateCharacterData(data)
    local v = data._v or 1

    if v < 2 then
        -- v1 → v2：新增 talents 字段
        data.talents = {}
    end

    if v < 3 then
        -- v2 → v3：新增 achievements 字段
        data.achievements = {}
        -- v2 的 skillPoints 拆分为 talentPoints + skillPoints
        if data.skillPoints then
            data.talentPoints = math.floor(data.skillPoints / 2)
            data.skillPoints = data.skillPoints - data.talentPoints
        end
    end

    data._v = CURRENT_VERSION
    return data
end

-- 在加载回调中使用
function OnDataLoaded(scores)
    local character = scores.character or { _v = 1 }
    character = MigrateCharacterData(character)
    playerCache[uid].character = character
    MarkDirty(uid)  -- 迁移后标脏，下次保存时写入新版本
end
```

**要点**：
- 版本号放在数据内部（如 `_v` 字段），不依赖外部元数据
- 迁移函数必须是**逐版本递进**的（v1→v2→v3），不要跳版本
- 迁移后立即 MarkDirty，确保新格式被持久化
- 新增字段提供合理默认值，避免 nil 导致运行时报错

---

## 11. 恢复后一致性校验原则

**恢复完成后，必须对关键数据做一致性检查，发现异常及时修正。**

云端数据可能因 bug、版本迁移遗漏、网络中断导致不一致。恢复后盲目信任数据是危险的。

```lua
function ValidatePlayerData(uid)
    local data = playerCache[uid]
    local needFix = false

    -- 1. 数值合法性：余额不为负
    if data.level and data.level < 1 then
        data.level = 1
        needFix = true
    end

    -- 2. 引用完整性：背包物品是否存在于配置表
    if data.inventory then
        local validItems = {}
        for _, item in ipairs(data.inventory) do
            if ItemConfig[item.name] then
                table.insert(validItems, item)
            else
                print(string.format("[WARN] uid=%d invalid item removed: %s", uid, item.name))
                needFix = true
            end
        end
        data.inventory = validItems
    end

    -- 3. 容量约束：背包不超过上限
    local maxSlots = GetMaxInventorySlots(data.level)
    if data.inventory and #data.inventory > maxSlots then
        print(string.format("[WARN] uid=%d inventory overflow: %d/%d", uid, #data.inventory, maxSlots))
        -- 不自动截断——记录日志，人工处理
    end

    -- 4. 时间合理性：时间戳不在未来
    if data.lastLoginAt and data.lastLoginAt > os.time() + 60 then
        data.lastLoginAt = os.time()
        needFix = true
    end

    if needFix then
        MarkDirty(uid)
    end
end

-- 在恢复流程最末尾调用
function OnLoadComplete(uid, connection)
    isRestoring = false
    ValidatePlayerData(uid)  -- 校验在恢复保护关闭后执行
    SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
end
```

**推荐检查项**：
| 检查项 | 说明 |
|--------|------|
| 数值范围 | 等级 ≥ 1、余额 ≥ 0、经验值 ≥ 0 |
| 引用存在性 | 物品/技能是否存在于配置表 |
| 容量约束 | 背包/槽位不超过上限 |
| 时间合理性 | 时间戳不在遥远的未来 |
| 映射完整性 | listId 映射表是否有孤立条目 |
| 版本一致性 | 数据版本号是否已迁移到最新 |
