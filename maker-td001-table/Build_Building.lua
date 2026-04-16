-- ============================================
-- 字段备注:
--   ID: ID
--   Name: Name
--   Icon: 图标
--   Type: 建筑分类
--   ShowName: 显示名字
--   DeployType: 放置类型（1，地面，2，高台，0，所有）
-- ============================================

local Data = {
['塔1'] = {
    DeployType = "1",
    ID = "塔1",
    Name = "塔1",
},
['塔2'] = {
    DeployType = "1",
    ID = "塔2",
    Name = "塔2",
},
['塔3'] = {
    DeployType = "2",
    ID = "塔3",
    Name = "塔3",
},
['塔4'] = {
    DeployType = "2",
    ID = "塔4",
    Name = "塔4",
},
['塔5'] = {
    DeployType = "0",
    ID = "塔5",
    Name = "塔5",
},
}
return Data
