# 服务端模式：世界数据 / 限流 / 原子性 / 加载顺序 / 恢复保护 / 一致性校验

> serverCloud 实战中的六个核心挑战及解决方案。

## 目录

1. [世界共享数据](#1-世界共享数据)
2. [限流策略](#2-限流策略)
3. [原子性与 BatchCommit](#3-原子性与-batchcommit)
4. [加载顺序与玩家生命周期](#4-加载顺序与玩家生命周期)
5. [恢复期保护](#5-恢复期保护)
6. [恢复后一致性校验](#6-恢复后一致性校验)

---

## 1. 世界共享数据

### 问题

serverCloud 的所有操作都需要 `userId` 作为第一个参数。但"世界数据"（房间配置、公共资源、全局事件）不属于任何玩家。

### 三种策略

| 策略 | 持久性 | 复杂度 | 适用场景 |
|------|--------|--------|---------|
| A. 服务器内存 | ✗ 进程重启丢失 | 低 | 对局内临时状态（计分板、倒计时） |
| B. 哨兵 UID | ✓ 持久 | 中 | 持久世界数据（地图状态、公告、赛季配置） |
| C. 房主托管 + 交接 | ✓ 持久 | 高 | 需要归属权的世界数据 |

### 策略 A：服务器内存（推荐用于对局制）

最简单——世界数据只存在服务器 Lua 变量中，不写 serverCloud。

```lua
-- Server.lua
local worldState = {
    roundTimer = 180,
    scoreBoard = {},
    spawnPoints = {},
}

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    worldState.roundTimer = worldState.roundTimer - dt
    -- 广播给所有客户端...
end
```

**优点**：零云端读写、无限流风险、无延迟
**缺点**：服务器重启即丢失——仅适合对局制（一局结束数据就没用了）

### 策略 B：哨兵 UID（推荐用于持久世界）

选一个固定的"假用户 ID"代表世界，用它存取世界数据。

```lua
local WORLD_UID = 1  -- 不会与真实玩家冲突的固定值

-- 写入世界数据
serverCloud:Set(WORLD_UID, "map_state", {
    seed = 12345,
    buildings = { {x=10, z=20, type="house"} },
})

-- 读取世界数据
serverCloud:Get(WORLD_UID, "map_state", {
    ok = function(scores, iscores)
        local mapState = scores.map_state
        -- 初始化世界...
    end
})

-- 世界货币（如公会基金）
serverCloud.money:Add(WORLD_UID, "guild_fund", 1000)
```

**优点**：持久、支持所有 serverCloud 功能（包括 BatchCommit）
**缺点**：哨兵 UID 的读写也消耗限流配额；理论上可能与未来的真实 UID 冲突（实践中极小概率）

**UID 选择建议**：
- 用小整数（如 1、2、3）——真实 UID 通常是大数字
- 不同世界实例用不同 UID（如 `WORLD_UID = roomId`），但注意 UID 会永久占用云端存储

### 策略 C：房主托管 + 交接

世界数据存在房主（host）的 UID 下。房主离开时，数据交接给新房主。

```lua
local hostUid = nil

function OnPlayerJoined(uid, connection)
    if hostUid == nil then
        hostUid = uid
        -- 从该玩家名下加载世界数据
        serverCloud:Get(hostUid, "world_data", {
            ok = function(scores) InitWorld(scores.world_data) end
        })
    end
end

function OnPlayerLeft(uid)
    if uid == hostUid then
        -- 交接：保存到新房主名下
        local newHost = GetNextPlayer()
        if newHost then
            serverCloud:Set(newHost, "world_data", currentWorldState)
            hostUid = newHost
        end
    end
end
```

**优点**：无需假 UID
**缺点**：交接逻辑复杂；如果所有玩家同时掉线，世界数据留在前房主名下（需要额外恢复逻辑）

---

## 2. 限流策略

### 预算一览

| 限制 | 值 | 超限行为 |
|------|------|---------|
| 读请求 | 300 次/分钟 | error(-429) |
| 写请求 | 300 次/分钟 | error(-429) |
| 数据吞吐 | 48 MB/分钟 | error(-429) |
| 单次 Batch 操作数 | 1000 条 | error(-429) |

### 每玩家预算计算

```
单玩家读预算 = 300 ÷ 在线玩家数 ÷ 读操作种类数 (次/分钟)
单玩家写预算 = 300 ÷ 在线玩家数 ÷ 写操作种类数 (次/分钟)
```

| 玩家数 | 每人读预算 | 每人写预算 | 说明 |
|--------|-----------|-----------|------|
| 2 | 150 次/分 | 150 次/分 | 宽裕 |
| 4 | 75 次/分 | 75 次/分 | 较宽裕 |
| 8 | 37 次/分 | 37 次/分 | 需注意 |
| 16 | 18 次/分 | 18 次/分 | 必须批量 |
| 50 | 6 次/分 | 6 次/分 | 必须严格控制 |
| 100 | 3 次/分 | 3 次/分 | 极端，仅事件驱动 |

### 优化手段

#### 1. BatchGet 合并读取

```lua
-- ❌ 3 次读请求
serverCloud:Get(uid, "level", cb1)
serverCloud:Get(uid, "gold", cb2)
serverCloud:Get(uid, "kills", cb3)

-- ✅ 1 次读请求
serverCloud:BatchGet(uid)
    :Key("level"):Key("gold"):Key("kills")
    :Fetch(cb)
```

#### 2. BatchSet 合并写入

```lua
-- ❌ 3 次写请求
serverCloud:SetInt(uid, "level", 10)
serverCloud:SetInt(uid, "gold", 500)
serverCloud:Add(uid, "kills", 1)

-- ✅ 1 次写请求
serverCloud:BatchSet(uid)
    :SetInt("level", 10)
    :SetInt("gold", 500)
    :Add("kills", 1)
    :Save("Update stats")
```

#### 3. 脏标记 + 定时批量保存

对于频繁变化的数据（如位置、分数），不要每次变化都写云端。

```lua
local playerDirty = {}  -- uid → true/false
local SAVE_INTERVAL = 10  -- 每10秒批量保存一次
local saveTimer = 0

function MarkDirty(uid)
    playerDirty[uid] = true
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    saveTimer = saveTimer + dt
    if saveTimer >= SAVE_INTERVAL then
        saveTimer = 0
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
end
```

#### 4. 服务器内存缓存

```lua
local playerCache = {}  -- uid → data table

-- 进房时一次性加载到内存
function OnPlayerJoined(uid)
    serverCloud:BatchGet(uid):Key("score"):Key("state"):Fetch({
        ok = function(scores, iscores)
            playerCache[uid] = {
                score = iscores.score or 0,
                state = scores.state or {},
            }
        end
    })
end

-- 游戏中读写都走内存，不访问云端
function GetPlayerScore(uid)
    return playerCache[uid].score  -- 零云端开销
end

function AddPlayerScore(uid, delta)
    playerCache[uid].score = playerCache[uid].score + delta
    MarkDirty(uid)  -- 标记脏，等批量保存
end
```

---

## 3. 原子性与 BatchCommit

### 决策表：何时需要事务？

| 场景 | 是否需要 BatchCommit | 原因 |
|------|---------------------|------|
| 读取玩家数据 | ✗ | 读操作无副作用 |
| 更新单个值 | ✗ | 单次写入本身是原子的 |
| 更新同一玩家的多个值 | △ 用 BatchSet 即可 | BatchSet 已足够 |
| 扣货币 + 加道具 | ✓ **必须** | 防止扣了钱没给货 |
| 跨玩家转账 | ✓ **必须** | 防止一方扣了另一方没加 |
| 击杀：加分 + 加金 + 记日志 | ✓ **推荐** | 保证一致性 |
| 升级：改等级 + 加奖励 | ✓ **推荐** | 防止等级改了奖励没发 |
| 发邮件 | ✗ | Message 不支持 BatchCommit |
| 消耗道具 | ✗ | Item.Use 不支持 BatchCommit |

### BatchCommit 支持的域

| 域 | 可用操作 |
|----|---------|
| Score | ScoreSet, ScoreSetInt, ScoreAddInt, ScoreDelete, ScoreDeleteInt |
| Money | MoneyAdd, MoneyCost |
| List | ListAdd, ListModify, ListModifyKey, ListDelete |
| Quota | QuotaAdd, QuotaReset |

**不支持**：Item、Message

### 典型事务

#### 购买道具

```lua
local c = serverCloud:BatchCommit("Buy item")
c:MoneyCost(uid, "gold", price)
c:ListAdd(uid, "inventory", {name = itemName, level = 1})
c:Commit({
    ok = function() SendToClient(conn, {action = "buy_ok"}) end,
    error = function(code, reason)
        -- 余额不足时整个事务回滚
        SendToClient(conn, {action = "buy_fail", reason = reason})
    end
})
```

#### 击杀奖励

```lua
local c = serverCloud:BatchCommit("Kill reward")
c:ScoreAddInt(killerUid, "kills", 1)
c:MoneyAdd(killerUid, "gold", 50)
c:QuotaAdd(killerUid, "daily_kills", 1, 100, "day", 1)
c:Commit()
```

#### 跨玩家交易

```lua
function Trade(sellerUid, buyerUid, itemName, price)
    local c = serverCloud:BatchCommit("Trade")
    c:MoneyCost(buyerUid, "gold", price)
    c:MoneyAdd(sellerUid, "gold", price)
    c:ListAdd(buyerUid, "inventory", {name = itemName})
    c:Commit({
        ok = function() print("Trade complete") end,
        error = function(code, reason) print("Trade failed:", reason) end
    })
end
```

---

## 4. 加载顺序与玩家生命周期

### 玩家加入流程

```
客户端连接
  ↓
[1] 获取 uid
  uid = connection.identity["user_id"]:GetInt64()
  ↓
[2] 判断新老玩家（可选）
  serverCloud:IsOldPlayer(uid, ...)
  ↓
[3] 批量加载玩家数据
  serverCloud:BatchGet(uid):Key(...):Fetch(...)
  ↓
[4] 加载完成 → 初始化玩家 → 通知客户端就绪
```

### 回调串联模式

```lua
function OnClientConnected(connection)
    local uid = connection.identity["user_id"]:GetInt64()

    -- 步骤1：检查新老玩家
    serverCloud:IsOldPlayer(uid, {
        ok = function(isOld)
            if not isOld then
                InitNewPlayer(uid, connection)
            else
                LoadPlayerData(uid, connection)
            end
        end,
        error = function(code, reason)
            -- 查询失败也尝试加载（容错）
            LoadPlayerData(uid, connection)
        end
    })
end

function InitNewPlayer(uid, connection)
    local c = serverCloud:BatchCommit("Init new player")
    c:ScoreSetInt(uid, "level", 1)
    c:MoneyAdd(uid, "gold", 1000)  -- 新手礼包
    c:Commit({
        ok = function()
            LoadPlayerData(uid, connection)
        end
    })
end

function LoadPlayerData(uid, connection)
    serverCloud:BatchGet(uid)
        :Key("level"):Key("gold"):Key("kills")
        :Key("settings")
        :Fetch({
            ok = function(scores, iscores)
                playerCache[uid] = {
                    level = iscores.level or 1,
                    gold = iscores.gold or 0,
                    kills = iscores.kills or 0,
                    settings = scores.settings or {},
                }
                SendToClient(connection, {
                    action = "player_ready",
                    data = playerCache[uid]
                })
            end,
            error = function(code, reason)
                print("Load failed:", reason)
                playerCache[uid] = {level = 1, gold = 0, kills = 0, settings = {}}
                SendToClient(connection, {action = "player_ready", data = playerCache[uid]})
            end
        })
end
```

### 玩家离开流程

```lua
function OnClientDisconnected(connection)
    local uid = connection.identity["user_id"]:GetInt64()
    if playerDirty[uid] then
        SavePlayerData(uid)
    end
    playerCache[uid] = nil
    playerDirty[uid] = nil
end

function SavePlayerData(uid)
    local data = playerCache[uid]
    if not data then return end
    serverCloud:BatchSet(uid)
        :SetInt("level", data.level)
        :SetInt("kills", data.kills)
        :Set("settings", data.settings)
        :Save("Player disconnect save")
    -- 金币用 Money 域，增减在游戏事件时已写入
end
```

### 断线重连

```lua
function OnClientReconnected(connection)
    local uid = connection.identity["user_id"]:GetInt64()

    if playerCache[uid] then
        -- 服务器还有缓存 → 直接恢复
        SendToClient(connection, {
            action = "player_ready",
            data = playerCache[uid]
        })
    else
        -- 缓存已清理 → 重新从云端加载
        LoadPlayerData(uid, connection)
    end
end
```

### 加载顺序原则

1. **先识别再加载**：先 IsOldPlayer，再决定初始化还是加载
2. **一次批量读取**：用 BatchGet 把所有 key 一次读完，不要分多次
3. **容错降级**：error 回调中用默认值继续，不要阻塞玩家进入
4. **离开即保存**：disconnect 时立即 flush 脏数据，不要等定时器
5. **缓存优先**：重连时优先用服务器内存缓存，其次才从云端拉取

---

## 5. 恢复期保护

### 问题

玩家加载数据时（BatchGet 回调链执行期间），对象处于中间态：字段部分赋值、索引未重建、引用未建立。如果此时定时保存触发或 MarkDirty 生效，会把空值/默认值覆盖回云端，导致数据损坏。

### 解决方案：恢复保护标记

在恢复期间禁止三件事：标脏、定时保存、对外广播。

```lua
local playerLoading = {}  -- uid → true/false，按玩家粒度控制

function MarkDirty(uid)
    if playerLoading[uid] then return end  -- 恢复期不标脏
    playerDirty[uid] = true
end

function BroadcastPlayerChange(uid, action, data)
    if playerLoading[uid] then return end  -- 恢复期不广播
    BroadcastToAll({ action = action, uid = uid, data = data })
end
```

### 完整加载流程（带恢复保护）

```lua
function LoadPlayerData(uid, connection)
    playerLoading[uid] = true  -- 开启保护

    serverCloud:BatchGet(uid)
        :Key("level"):Key("inventory"):Key("settings"):Key("crops")
        :Fetch({
            ok = function(scores, iscores)
                -- === 恢复阶段（保护中）===
                playerCache[uid] = {
                    level = iscores.level or 1,
                    inventory = scores.inventory or {},
                    settings = scores.settings or {},
                    crops = scores.crops or {},
                }

                -- 版本迁移（见 design-principles §10）
                MigratePlayerData(uid)

                -- 重建索引
                RebuildListIdMappings(uid)

                -- 一致性校验（见 §6）
                ValidatePlayerData(uid)

                -- === 恢复完成 ===
                playerLoading[uid] = false  -- 关闭保护（必须在最后）

                -- 现在才安全：通知客户端、启用自动保存
                SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
            end,
            error = function(code, reason)
                playerLoading[uid] = false  -- 错误时也要关闭保护
                -- 降级处理
                playerCache[uid] = { level = 1, inventory = {}, settings = {}, crops = {} }
                SendToClient(connection, { action = "player_ready", data = playerCache[uid] })
            end
        })
end
```

### 定时保存中的保护检查

```lua
function FlushDirtyPlayers()
    for uid, dirty in pairs(playerDirty) do
        if dirty and not playerLoading[uid] then  -- 跳过正在恢复的玩家
            serverCloud:BatchSet(uid)
                :SetInt("score", playerCache[uid].score)
                :Set("state", playerCache[uid].state)
                :Save("Periodic save")
            playerDirty[uid] = false
        end
    end
end
```

### 多玩家并发注意

上面用 `playerLoading[uid]` 做按玩家粒度的保护，而不是全局 `isRestoring` 标记。这样当玩家 A 正在加载时，不会阻塞玩家 B 的正常保存和广播。

---

## 6. 恢复后一致性校验

### 问题

云端数据可能因 bug、版本迁移遗漏、网络中断写入不完整等原因存在不一致。恢复后盲目信任数据会导致运行时异常。

### 推荐检查项

| 检查类型 | 检查内容 | 修复策略 |
|----------|---------|---------|
| 数值范围 | 等级 ≥ 1、经验 ≥ 0 | 自动修正到合法最小值 |
| 引用存在性 | 背包物品是否存在于配置表 | 移除无效条目，记录日志 |
| 容量约束 | 背包不超过等级对应上限 | 记录日志，不自动截断（交给人工） |
| 时间合理性 | 时间戳不在遥远的未来 | 修正为当前时间 |
| 映射完整性 | listId 映射无孤立条目 | 清理孤立映射 |
| 版本一致性 | `_v` 字段已迁移到最新版本 | 触发迁移流程 |

### 代码示例

```lua
function ValidatePlayerData(uid)
    local data = playerCache[uid]
    local needFix = false

    -- 1. 数值范围
    if data.level and data.level < 1 then
        print(string.format("[WARN] uid=%d level=%d, reset to 1", uid, data.level))
        data.level = 1
        needFix = true
    end

    -- 2. 引用存在性：背包物品是否在配置表中
    if data.inventory then
        local validItems = {}
        for _, item in ipairs(data.inventory) do
            if ItemConfig[item.name] then
                table.insert(validItems, item)
            else
                print(string.format("[WARN] uid=%d removed invalid item: %s", uid, tostring(item.name)))
                needFix = true
            end
        end
        if needFix then data.inventory = validItems end
    end

    -- 3. 时间合理性
    if data.lastLoginAt and data.lastLoginAt > os.time() + 60 then
        data.lastLoginAt = os.time()
        needFix = true
    end

    -- 4. 动态对象映射完整性
    if data.crops then
        for i = #data.crops, 1, -1 do
            local crop = data.crops[i]
            if not crop.listId then
                print(string.format("[WARN] uid=%d crop missing listId, removing", uid))
                table.remove(data.crops, i)
                needFix = true
            end
        end
    end

    if needFix then
        MarkDirty(uid)  -- 此时 playerLoading 已关闭，MarkDirty 生效
    end
end
```

### 调用时机

一致性校验必须在**恢复保护关闭之前的最后一步**执行，在 `playerLoading[uid] = false` 之前调用。这样校验产生的 MarkDirty 能正常生效（因为校验本身就是恢复流程的一部分，校验结果需要被保存）。

```lua
-- 正确顺序：
MigratePlayerData(uid)       -- 先迁移
RebuildListIdMappings(uid)   -- 再重建索引
ValidatePlayerData(uid)      -- 再校验（此时 playerLoading 仍为 true）
playerLoading[uid] = false   -- 最后关闭保护
-- ValidatePlayerData 中的 MarkDirty 需要特殊处理：
-- 直接设置 playerDirty[uid] = true，绕过 MarkDirty 的保护检查
```

**修正后的 ValidatePlayerData**：

```lua
function ValidatePlayerData(uid)
    -- ... 校验逻辑同上 ...
    if needFix then
        playerDirty[uid] = true  -- 直接标脏，不走 MarkDirty（因为仍在恢复保护中）
    end
end
```
