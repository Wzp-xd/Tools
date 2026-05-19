-- ============================================
-- 字段备注:
--   Scale: 尺寸
--   Offset: 偏移
--   Color: 改变颜色
-- ============================================

local Data = {
['劫掠者'] = {
    ID = "劫掠者",
    Key = "tower_marauder",
    Scale = 1,
    Sprite = [[Textures/towers/tower_marauder.png]],
},
['哥布林1'] = {
    ID = "哥布林1",
    Key = "enemy_goblin_recruit",
    Scale = 1,
    Sprite = [[Textures/enemies/goblin_recruit.png]],
},
['机枪兵'] = {
    ID = "机枪兵",
    Key = "tower_marine",
    Offset = {0, 0},
    Scale = 1,
    Sprite = [[Textures/towers/tower_marine.png]],
},
}
return Data
