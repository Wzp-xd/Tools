-- ============================================
-- 字段备注:
--   ID: ID
--   Name: Name
--   Icon: 图标
--   Type: 建筑分类
--   ShowName: 显示名字
--   DeployType: 放置类型（1，地面，2，高台，0，所有）
--   SlotCost: 占用格子数
--   SellStart: 初始存货
--   SellMax: 存货上限
--   SellCooldownStart: 开局CD
--   SellCooldown: 后续的补货CD
-- ============================================

local Data = {
['劫掠者'] = {
    DeployType = "1",
    ID = "劫掠者",
    Name = "劫掠者",
    SellCooldown = 15,
    SellCooldownStart = 0,
    SellMax = 5,
    SellStart = 1,
    SlotCost = 2,
},
['医疗兵'] = {
    DeployType = "1",
    ID = "医疗兵",
    Name = "医疗兵",
    SellCooldown = 15,
    SellCooldownStart = 0,
    SellMax = 5,
    SellStart = 1,
    SlotCost = 2,
},
['坦克'] = {
    DeployType = "1",
    ID = "坦克",
    Name = "坦克",
    SellCooldown = 20,
    SellCooldownStart = 60,
    SellMax = 3,
    SellStart = 0,
    SlotCost = 3,
},
['大和'] = {
    DeployType = "1",
    ID = "大和",
    Name = "大和",
    SellCooldown = 60,
    SellCooldownStart = 150,
    SellMax = 1,
    SellStart = 0,
    SlotCost = 6,
},
['女妖'] = {
    DeployType = "1",
    ID = "女妖",
    Name = "女妖",
    SellCooldown = 30,
    SellCooldownStart = 90,
    SellMax = 3,
    SellStart = 0,
    SlotCost = 3,
},
['机枪兵'] = {
    DeployType = "1",
    ID = "机枪兵",
    Name = "机枪兵",
    SellCooldown = 10,
    SellCooldownStart = 0,
    SellMax = 10,
    SellStart = 1,
    SlotCost = 1,
},
['歌利亚'] = {
    DeployType = "1",
    ID = "歌利亚",
    Name = "歌利亚",
    SellCooldown = 20,
    SellCooldownStart = 60,
    SellMax = 3,
    SellStart = 0,
    SlotCost = 3,
},
['火蝠'] = {
    DeployType = "1",
    ID = "火蝠",
    Name = "火蝠",
    SellCooldown = 15,
    SellCooldownStart = 0,
    SellMax = 5,
    SellStart = 1,
    SlotCost = 2,
},
['维京'] = {
    DeployType = "1",
    ID = "维京",
    Name = "维京",
    SellCooldown = 30,
    SellCooldownStart = 90,
    SellMax = 3,
    SellStart = 0,
    SlotCost = 3,
},
['雷神'] = {
    DeployType = "1",
    ID = "雷神",
    Name = "雷神",
    SellCooldown = 40,
    SellCooldownStart = 120,
    SellMax = 2,
    SellStart = 0,
    SlotCost = 4,
},
}
return Data
