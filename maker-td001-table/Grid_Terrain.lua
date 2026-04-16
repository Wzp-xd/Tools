-- ============================================
-- 字段备注:
--   ID: ID
--   GridType: 地面类型，1，地面，2，高台，3，其他
--   WalkableGround: 地面可通行
--   WalkableSky: 天空可通行
-- ============================================

local Data = {
['土地'] = {
    GridType = 1,
    ID = "土地",
    WalkableGround = 1,
    WalkableSky = 1,
},
['草地'] = {
    GridType = 1,
    ID = "草地",
    WalkableGround = 1,
    WalkableSky = 1,
},
['高台-土'] = {
    GridType = 2,
    ID = "高台-土",
    WalkableGround = 0,
    WalkableSky = 1,
},
['高台-草'] = {
    GridType = 2,
    ID = "高台-草",
    WalkableGround = 0,
    WalkableSky = 1,
},
}
return Data
