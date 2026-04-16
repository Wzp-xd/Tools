-- ============================================
-- 字段备注:
--   ID: ID
--   UnitID: 单位ID
--   Cost: 花费
--   CostAdd: 花费增加
--   RedeployCooldown: 重新放置冷却时间
-- ============================================

local Data = {
[1] = {
    BuildingID = "塔1",
    Cost = 10,
    CostAdd = 10,
    ID = 1,
    Level = 1,
    RedeployCooldown = 30,
    UnitID = "塔1-Lv1",
},
[2] = {
    BuildingID = "塔1",
    Cost = 12,
    CostAdd = 10,
    ID = 2,
    Level = 2,
    RedeployCooldown = 30,
    UnitID = "塔1-Lv2",
},
[3] = {
    BuildingID = "塔1",
    Cost = 14,
    CostAdd = 10,
    ID = 3,
    Level = 3,
    RedeployCooldown = 30,
    UnitID = "塔1-Lv3",
},
[4] = {
    BuildingID = "塔2",
    Cost = 10,
    CostAdd = 10,
    ID = 4,
    Level = 1,
    RedeployCooldown = 30,
    UnitID = "塔2-Lv1",
},
[1001005] = {
    BuildingID = "塔2",
    Cost = 12,
    CostAdd = 10,
    ID = 1001005,
    Level = 2,
    RedeployCooldown = 30,
    UnitID = "塔2-Lv2",
},
}
return Data
