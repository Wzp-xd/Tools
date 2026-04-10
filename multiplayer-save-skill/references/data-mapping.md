# 数据映射指南：游戏数据 → serverCloud 域

> 核心问题：我的游戏数据该存到哪个域？

## 目录

1. [域能力对比](#1-域能力对比)
2. [决策流程](#2-决策流程)
3. [游戏类型映射](#3-游戏类型映射示例)
4. [组合事务模式](#4-组合事务模式)
5. [易错边界](#5-易错边界)

---

## 1. 域能力对比

| 域 | 数据类型 | 排行榜 | 事务 | 典型用途 |
|----|---------|--------|------|---------|
| **Score.Set** | 任意（table/string/number） | ✗ | ✓ ScoreSet | 复合配置、玩家档案、JSON blob |
| **Score.SetInt** | 整数 | ✓ | ✓ ScoreSetInt/AddInt | 积分、等级、击杀数——需要排行的数值 |
| **Money** | 整数 | ✗ | ✓ MoneyAdd/Cost | 货币（金币、钻石）——内置余额校验 |
| **List** | 任意（每条独立 listId） | ✗ | ✓ ListAdd/Modify/Delete | 背包、邮件列表、战斗日志——可增删改的有序集合 |
| **Item** | name+count+extra | ✗ | ✗ | 道具（可消耗）——内置数量管理和 Use 扣减 |
| **Quota** | 整数计数器 | ✗ | ✓ QuotaAdd/Reset | 每日签到、体力、周任务——自动按时间周期重置 |
| **Message** | 任意 | ✗ | ✗ | 玩家间邮件/礼物——支持已读/未读 |

**关键区别**：
- **Score.Set vs Score.SetInt**：只有 SetInt/Add 写入的 iscores 才能参与排行榜
- **Money vs Score.SetInt**：Money 的 `Cost()` 会自动校验余额不足并拒绝，Score 没有此保护
- **List vs Item**：List 是通用有序集合；Item 专为有数量、可消耗的道具设计

---

## 2. 决策流程

拿到一个需要持久化的游戏数据时，按以下顺序判断：

```
该数据需要排行榜吗？
  ├─ 是 → Score.SetInt / Add
  └─ 否 ↓

该数据是货币（需要余额保护）吗？
  ├─ 是 → Money
  └─ 否 ↓

该数据是可消耗道具（有数量、可 Use 扣减）吗？
  ├─ 是 → Item
  └─ 否 ↓

该数据需要按天/周/月自动重置吗？
  ├─ 是 → Quota
  └─ 否 ↓

该数据是玩家间收发的消息/邮件吗？
  ├─ 是 → Message
  └─ 否 ↓

该数据是可增删改的列表（背包、日志、装备列表）吗？
  ├─ 是 → List
  └─ 否 ↓

其他复合数据 → Score.Set（存 table/string）
```

**附加决策**：如果该操作需要和其他域联动（如扣货币+加道具），检查是否需要 `BatchCommit`。注意 Item 和 Message **不支持**事务。

---

## 3. 游戏类型映射示例

### 射击游戏（FPS/TPS）

| 游戏数据 | 域 | key 示例 | 说明 |
|---------|------|---------|------|
| 击杀数 | Score.SetInt | `kills` | 需要排行榜 |
| 最高连杀 | Score.SetInt | `max_streak` | 需要排行榜 |
| 金币 | Money | `gold` | 余额保护 |
| 武器库存 | List | `weapons` | 可增删 |
| 每日任务进度 | Quota | `daily_mission` | 每日重置 |
| 玩家设置 | Score.Set | `settings` | JSON blob |

### RPG

| 游戏数据 | 域 | key 示例 | 说明 |
|---------|------|---------|------|
| 等级 | Score.SetInt | `level` | 可排行 |
| 经验值 | Score.SetInt | `exp` | 可排行 |
| 金币/钻石 | Money | `gold` / `diamond` | 双货币，余额保护 |
| 背包物品 | List | `inventory` | 可增删改 |
| 消耗品（药水） | Item | `potion_hp` | Use 扣减 |
| 体力 | Quota | `stamina` | 每日刷新 |
| 邮件/礼物 | Message | `mail` | 玩家间收发 |
| 角色属性 | Score.Set | `character` | JSON blob，存 table |

### 休闲游戏

| 游戏数据 | 域 | key 示例 | 说明 |
|---------|------|---------|------|
| 最高分 | Score.SetInt | `high_score` | 排行榜核心 |
| 游戏币 | Money | `coin` | 余额保护 |
| 皮肤/道具 | List | `unlocked_skins` | 已解锁列表 |
| 每日奖励 | Quota | `daily_reward` | 每日1次 |
| 游戏配置 | Score.Set | `config` | JSON blob |

### 农场/经营类

| 游戏数据 | 域 | key 示例 | 说明 |
|---------|------|---------|------|
| 农场等级 | Score.SetInt | `farm_level` | 可排行 |
| 金币/钻石 | Money | `gold` / `gem` | 余额保护 |
| 农作物列表 | List | `crops` | 动态增删，每条有 listId |
| 动物列表 | List | `animals` | 同上 |
| 建筑配置 | Score.Set | `buildings` | 固定槽位，JSON blob |
| 每日收获次数 | Quota | `daily_harvest` | 每日重置 |
| 农场总览 | Score.Set | `farm_info` | 名字、创建时间等聚合信息 |

---

## 4. 组合事务模式

当一个游戏动作涉及多个域时，使用 `BatchCommit` 保证原子性。

### 购买道具 = Money.Cost + List.Add

```lua
function BuyItem(uid, itemName, price, conn)
    local c = serverCloud:BatchCommit("Buy item")
    c:MoneyCost(uid, "gold", price)
    c:ListAdd(uid, "inventory", { name = itemName, level = 1, acquiredAt = os.time() })
    c:Commit({
        ok = function()
            SendToClient(conn, { action = "buy_ok", item = itemName })
        end,
        error = function(code, reason)
            -- 余额不足时整个事务回滚，道具不会入库
            SendToClient(conn, { action = "buy_fail", reason = reason })
        end
    })
end
```

### 击杀奖励 = Score.AddInt + Money.Add + Quota.Add

```lua
function OnKillReward(killerUid, victimUid)
    local c = serverCloud:BatchCommit("Kill reward")
    c:ScoreAddInt(killerUid, "kills", 1)
    c:MoneyAdd(killerUid, "gold", 50)
    c:QuotaAdd(killerUid, "daily_kills", 1, 100, "day", 1)  -- 每日上限100
    c:Commit({
        ok = function()
            -- 更新内存缓存
            playerCache[killerUid].kills = playerCache[killerUid].kills + 1
        end
    })
end
```

### 升级 = Score.SetInt + Score.Set + Money.Add

```lua
function LevelUp(uid, newLevel, rewardGold)
    local c = serverCloud:BatchCommit("Level up")
    c:ScoreSetInt(uid, "level", newLevel)
    c:ScoreSet(uid, "character", {
        level = newLevel,
        maxHp = 100 + newLevel * 10,
        unlockedSkills = GetSkillsForLevel(newLevel),
    })
    c:MoneyAdd(uid, "gold", rewardGold)
    c:Commit({
        ok = function()
            playerCache[uid].level = newLevel
        end,
        error = function(code, reason)
            print("Level up failed:", reason)
        end
    })
end
```

### 赠送礼物（跨玩家）

```lua
function SendGift(senderUid, receiverUid, itemName, cost)
    local c = serverCloud:BatchCommit("Send gift")
    -- 从发送者扣费
    c:MoneyCost(senderUid, "gold", cost)
    -- 给接收者加道具
    c:ListAdd(receiverUid, "inventory", {
        name = itemName,
        from = senderUid,
        giftedAt = os.time(),
    })
    c:Commit({
        ok = function()
            print("Gift sent successfully")
        end,
        error = function(code, reason)
            -- 余额不足或其他错误，整个事务回滚
            print("Gift failed:", reason)
        end
    })
end
```

### 跨玩家交易 = Money 双向 + List 转移

```lua
function Trade(sellerUid, buyerUid, itemListId, itemData, price)
    local c = serverCloud:BatchCommit("Trade")
    c:MoneyCost(buyerUid, "gold", price)
    c:MoneyAdd(sellerUid, "gold", price)
    c:ListDelete(sellerUid, "inventory", itemListId)
    c:ListAdd(buyerUid, "inventory", itemData)
    c:Commit({
        ok = function() print("Trade complete") end,
        error = function(code, reason) print("Trade failed:", reason) end
    })
end
```

---

## 5. 易错边界

| 陷阱 | 说明 |
|------|------|
| **排行榜只认 iscores** | `Score.Set()` 写入 scores 表，**不参与排行**。必须用 `SetInt()` 或 `Add()` |
| **scores 和 iscores 是两张表** | `BatchGet` 回调返回 `scores, iscores` 两个 table，取值时注意从正确的表里取 |
| **Money.Cost 自带余额校验** | 余额不足直接触发 error 回调，不需要先 Get 再判断 |
| **Item 和 Message 不支持 BatchCommit** | 只有 Score、Money、List、Quota 可以放进事务 |
| **Quota 自动刷新** | 设置周期后（如 `"day"`）每日自动重置计数，不需要手动 Reset |
| **List.Add 返回 listId** | 后续 Modify/Delete 需要 listId，必须在回调中保存到内存映射 |
| **Set 覆盖整个 key** | `Score.Set(uid, "state", newTable)` 会整体覆盖，不是合并。如果只改一个字段，需先读再写或拆分 key |
| **BatchSet 不是事务** | `BatchSet` 只是合并网络请求，不保证原子性。需要原子性用 `BatchCommit` |
