---
name: multiplayer-save
description: "多人游戏存档与排行榜完整指南，融合架构设计原则与 UrhoX 云存档 API 实践。覆盖数据分层、三条链路分离（在线同步/离线恢复/晚加入重建）、clientCloud/serverCloud 选型与用法、排行榜、事务、断线重连、服务端子对象（Money/List/Message/Quota）、恢复期保护、数据版本兼容、一致性校验。Use when users need to (1) 设计或实现多人游戏的存档系统, (2) 使用 clientCloud 或 serverCloud 云变量 API, (3) 实现排行榜功能, (4) 处理多人游戏的断线重连和数据恢复, (5) 设计玩家数据与世界数据的分层管理, (6) 使用 BatchCommit 事务保证原子性, (7) 使用服务端子对象（货币/背包/配额/消息）, (8) 处理数据版本迁移和兼容性, (9) 设计恢复期保护防止数据覆盖, or any multiplayer save/load/leaderboard related tasks."
---

# serverCloud 多人存档实战指南

> 本指南专注 **serverCloud**（服务端权威模式）的存档设计。
> API 签名详见 `engine-docs/recipes/server-cloud-score.md`。

---

## 1. 域选择速查

| 我的数据是... | 用这个域 | 一句话原因 |
|--------------|---------|-----------|
| 需要排行榜的数值 | **Score.SetInt / Add** | 只有 iscores 参与 GetRankList |
| 货币（可能透支） | **Money** | Cost() 自动拦截余额不足 |
| 可消耗的道具 | **Item** | Use() 自动扣减数量 |
| 按天/周/月重置的计数 | **Quota** | 自动按周期刷新 |
| 玩家间收发的消息 | **Message** | 支持已读/未读标记 |
| 可增删改的列表 | **List** | 每条有独立 listId |
| 其他复合数据 | **Score.Set** | 存 table/string，不排行 |

**决策流程**：拿到一个数据，依次问——需要排行？是货币？是消耗品？需要周期重置？是消息？是动态列表？都不是则用 Score.Set。

**分层映射**：数据按职责可以分为四层，每层有推荐域：

| 分层 | 典型数据 | 推荐域 |
|------|---------|--------|
| 聚合层 | 等级、名字、总览配置 | Score.Set / Score.SetInt |
| 固定对象层 | 装备槽、技能树、建筑槽 | Score.Set（JSON blob） |
| 动态对象层 | 背包物品、宠物、订单 | List（每条有 listId） |
| 共享世界层 | 地图状态、公会基金 | 哨兵 UID + Score.Set / Money |

**详细决策流程和游戏类型映射** → [references/data-mapping.md](references/data-mapping.md)

---

## 2. 世界共享数据

serverCloud 按 userId 存储，世界数据怎么办？

| 策略 | 持久性 | 适用 |
|------|--------|------|
| **服务器内存** | ✗ | 对局制临时状态 |
| **哨兵 UID**（`WORLD_UID = 1`） | ✓ | 持久世界 |
| **房主托管 + 交接** | ✓ | 需归属权 |

```lua
-- 策略 B 最小示例：哨兵 UID
local WORLD_UID = 1
serverCloud:Set(WORLD_UID, "map_state", { seed = 12345, buildings = {...} })
serverCloud:Get(WORLD_UID, "map_state", {
    ok = function(scores) InitWorld(scores.map_state) end
})
```

**核心原则**：玩家数据按 uid 存，世界数据按哨兵 UID 存。两者边界必须清晰——世界共享状态不要挂在任何真实玩家名下。

**代码示例和详细权衡** → [references/server-patterns.md](references/server-patterns.md) §1

---

## 3. 限流预算

| 限制 | 值 |
|------|------|
| 读/写请求 | 各 300 次/分钟 |
| 数据吞吐 | 48 MB/分钟 |
| 单次 Batch | ≤1000 条操作 |

**速算**：`每人预算 ≈ 300 ÷ 在线玩家数` 次/分钟

核心优化：
1. **BatchGet/BatchSet** — 合并同一玩家的多个 key
2. **脏标记 + 定时保存** — 不要每次变化都写云端（5-10秒间隔）
3. **服务器内存缓存** — 进房时加载到内存，游戏中读写走内存

```lua
-- 脏标记最小示例
local playerDirty = {}
function MarkDirty(uid)
    if playerLoading[uid] then return end  -- 恢复期不标脏
    playerDirty[uid] = true
end
```

**预算计算表和完整模式** → [references/server-patterns.md](references/server-patterns.md) §2

---

## 4. 何时用 BatchCommit

| 场景 | 需要事务？ |
|------|-----------|
| 读取数据 | ✗ |
| 写单个值 | ✗ |
| 写多个值（同玩家） | △ BatchSet 够了 |
| **扣货币 + 加道具** | ✓ 必须 |
| **跨玩家转账/交易** | ✓ 必须 |
| 击杀奖励（多域联动） | ✓ 推荐 |

**支持的域**：Score + Money + List + Quota
**不支持**：Item、Message

```lua
-- 购买道具：扣金币 + 加物品，原子操作
local c = serverCloud:BatchCommit("Buy item")
c:MoneyCost(uid, "gold", price)
c:ListAdd(uid, "inventory", { name = itemName, level = 1 })
c:Commit({
    ok = function() SendToClient(conn, { action = "buy_ok" }) end,
    error = function(code, reason) SendToClient(conn, { action = "buy_fail", reason = reason }) end
})
```

**典型事务代码** → [references/server-patterns.md](references/server-patterns.md) §3

---

## 5. 玩家加载顺序

```
连接 → 获取 uid → IsOldPlayer → BatchGet 全量加载 → 版本迁移 → 重建索引 → 一致性校验 → 关闭恢复保护 → 就绪
```

五条规则：
1. **先识别再加载** — IsOldPlayer 区分新老玩家
2. **一次批量读取** — BatchGet 所有 key，不要分多次
3. **容错降级** — error 回调用默认值，不阻塞玩家
4. **离开即保存** — disconnect 立即 flush 脏数据
5. **缓存优先** — 重连先查服务器内存，再查云端

**完整生命周期代码（加入/离开/重连）** → [references/server-patterns.md](references/server-patterns.md) §4

---

## 6. 恢复期保护 🔴

**加载期间必须禁止标脏、定时保存和对外广播。**

恢复中的对象处于中间态：字段部分赋值、索引未重建。如果此时定时保存触发，会把空值/默认值覆盖回云端，导致数据永久损坏。

```lua
local playerLoading = {}  -- uid → true/false，按玩家粒度控制

function MarkDirty(uid)
    if playerLoading[uid] then return end  -- 恢复期不标脏
    playerDirty[uid] = true
end

function LoadPlayerData(uid, connection)
    playerLoading[uid] = true  -- 开启保护

    serverCloud:BatchGet(uid):Key("level"):Key("inventory"):Fetch({
        ok = function(scores, iscores)
            -- 恢复阶段（保护中）：赋值、迁移、重建索引、校验
            playerCache[uid] = { level = iscores.level or 1, inventory = scores.inventory or {} }
            MigratePlayerData(uid)
            ValidatePlayerData(uid)

            playerLoading[uid] = false  -- 关闭保护（必须在最后）
            SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
        end,
        error = function(code, reason)
            playerLoading[uid] = false  -- 错误时也要关闭
            playerCache[uid] = { level = 1, inventory = {} }
            SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
        end
    })
end
```

**要点**：
- 用 `playerLoading[uid]` 按玩家粒度控制，不阻塞其他玩家
- 嵌套回调时保护期覆盖整个回调链
- 定时保存循环也要检查 `not playerLoading[uid]`

**完整保护模式代码** → [references/server-patterns.md](references/server-patterns.md) §5

---

## 7. 动态对象持久化身份

**List 域的 `listId` 就是动态对象的持久化身份。必须保存它，建立运行时 ID 到 listId 的映射。**

```lua
local cropIdMap = {}  -- runtimeId → listId

-- 创建时保存 listId
serverCloud.list:Add(uid, "crops", cropData, {
    ok = function(listId) cropIdMap[runtimeId] = listId end
})

-- 修改和删除时用 listId 定位
serverCloud.list:Modify(uid, "crops", cropIdMap[runtimeId], updatedData)
serverCloud.list:Delete(uid, "crops", cropIdMap[runtimeId])
```

**常见错误**：不保存 listId → Modify/Delete 无法定位 → 只能不断 Add，数据膨胀。

**完整映射模式** → [references/design-principles.md](references/design-principles.md) §9

---

## 8. 数据版本兼容

**持久化数据必须携带版本号（`_v` 字段）。恢复时做逐版本递进迁移。**

```lua
local CURRENT_VERSION = 3

function MigrateCharacterData(data)
    local v = data._v or 1
    if v < 2 then data.talents = {} end           -- v1→v2
    if v < 3 then data.achievements = {} end       -- v2→v3
    data._v = CURRENT_VERSION
    return data
end
```

**要点**：
- 版本号放在数据内部，不依赖外部元数据
- 迁移后标脏，确保新格式被持久化
- 新增字段提供合理默认值，避免 nil 导致运行时报错

**完整版本迁移模式** → [references/design-principles.md](references/design-principles.md) §10

---

## 9. 强制保存时机

虽然平时应延迟合批（脏标记 + 定时器），但以下场景必须立即落盘：

| 场景 | serverCloud 操作 | 说明 |
|------|-----------------|------|
| 玩家退出/断线 | `BatchSet` 立即 flush | 离开后无法再补写 |
| 对局/副本结算 | `BatchCommit` | 结算奖励不可丢失 |
| 交易完成 | `BatchCommit` | 跨玩家原子操作 |
| 大额货币变动 | `Money.Add/Cost` | 即时写入，不走脏标记 |
| 动态对象被删除 | `List.Delete` | 删除不可逆，立即持久化 |
| 跨场景迁移 | flush 后再切 | 确保目标场景能读到最新数据 |

**口诀**：普通进度可以等定时器，关键资产和不可逆操作必须立即落盘。

---

## 10. 恢复后一致性校验

**恢复完成后，对关键数据做合法性检查，发现异常及时修正。**

| 检查项 | 说明 |
|--------|------|
| 数值范围 | 等级 ≥ 1、余额 ≥ 0 |
| 引用存在性 | 物品/技能是否存在于配置表 |
| 容量约束 | 背包不超过上限 |
| 时间合理性 | 时间戳不在遥远的未来 |
| 映射完整性 | listId 映射无孤立条目 |
| 版本一致性 | `_v` 已迁移到最新版本 |

校验在恢复保护关闭前执行，校验产生的修正通过 `playerDirty[uid] = true` 直接标脏。

**完整校验代码** → [references/server-patterns.md](references/server-patterns.md) §6

---

## 11. 架构原则

| # | 原则 | 一句话 |
|---|------|--------|
| 1 | 可重建状态 | 能从其他数据算出来的，不存 |
| 2 | 时间基线 | 存时间戳，不存剩余时间 |
| 3 | 数据边界 | 玩家数据 vs 世界数据，分开存 |
| 4 | 三链路分离 | 在线同步/离线恢复/晚加入，独立实现 |
| 5 | 脏标记+批量保存 | 不要每帧写云端 |
| 6 | 恢复顺序 | 被依赖的先加载 |
| 7 | 恢复期保护 🔴 | 加载期间禁止标脏和广播 |
| 8 | 强制保存时机 | 关键操作立即落盘 |
| 9 | 持久化身份 | 动态对象用 listId，不用数组下标 |
| 10 | 数据版本兼容 | 带 `_v` 字段，逐版本迁移 |
| 11 | 恢复后校验 | 加载完成后验证数据合法性 |

**详细说明和代码** → [references/design-principles.md](references/design-principles.md)

---

## 12. 常见陷阱

| 陷阱 | 正确做法 |
|------|---------|
| 用 `Set()` 存分数然后查排行榜，发现为空 | 排行榜只认 `SetInt`/`Add` 写入的 iscores |
| 先 `Get` 余额再判断能否扣款 | 直接 `Money.Cost()`，余额不足自动 error |
| 每次击杀都 `SetInt` 一次 | 内存计数 + `MarkDirty` + 定时 BatchSet |
| 把 Message 放进 BatchCommit | Message 和 Item 不支持事务 |
| 分多次 `Get` 读玩家数据 | 用 `BatchGet` 一次读完 |
| 不保存 List.Add 返回的 listId | 必须在回调中保存 listId 到映射表 |
| 加载期间定时保存触发，覆盖云端数据 🔴 | 恢复期保护：`playerLoading[uid]` 阻止标脏和保存 |
| 数据结构变了，老玩家读到旧格式崩溃 | 带 `_v` 版本号，恢复时逐版本迁移 |
| 恢复后不校验，脏数据导致运行时异常 | 恢复完成后执行一致性校验 |

---

## 13. 评审清单

设计或评审多人存档方案时，逐项检查：

- [ ] 排行榜数据是否用了 `SetInt`/`Add` 而非 `Set`？
- [ ] 多域联动操作是否用了 `BatchCommit`？事务中是否误用了 Item/Message？
- [ ] 是否有恢复期保护（加载期间禁止 MarkDirty 和定时保存）？
- [ ] 所有 `BatchGet` 回调是否有 error 降级（用默认值而非阻塞玩家）？
- [ ] 限流预算是否按最大在线人数计算过？
- [ ] 玩家数据和世界数据的边界是否清晰（世界数据不挂在真实玩家 uid 下）？
- [ ] 动态对象是否用 `listId` 做持久化身份（而非数组下标）？
- [ ] 持久化数据是否带版本号（`_v`），恢复函数是否处理旧版本？
- [ ] 是否有强制保存时机清单（断线/结算/交易/删除）？
- [ ] 恢复完成后是否执行了一致性校验？
- [ ] 在线同步、离线恢复、晚加入重建三条链路是否独立实现？

---

## 14. 参考导航

| 文档 | 内容 |
|------|------|
| [data-mapping.md](references/data-mapping.md) | 域能力对比、决策流程图、游戏类型映射、组合事务代码 |
| [server-patterns.md](references/server-patterns.md) | 世界数据策略、限流预算、BatchCommit 模式、加载生命周期、恢复期保护、一致性校验 |
| [design-principles.md](references/design-principles.md) | 11 条架构原则详解（含恢复保护、版本兼容、持久化身份、强制保存、一致性校验） |
| `engine-docs/recipes/server-cloud-score.md` | serverCloud 完整 API 签名 |
| `examples/23-server-cloud-score-leaderboard-api/` | 服务端 API 完整示例 |
