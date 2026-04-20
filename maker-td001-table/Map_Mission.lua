-- ============================================
-- 字段备注:
--   ID: ID
--   PointEnemy.1: 敌人出生点
--   PointPlayer.1: 玩家防守点
-- ============================================

local Data = {
['关卡1-1'] = {
    GridID = "场地1",
    ID = "关卡1-1",
    PointEnemy = {
        [1] = {1, 3},
        [2] = {1, 2},
        [3] = {1, 4},
    },
    PointPlayer = {
        [1] = {6, 3},
    },
    Spawn = "关卡1-1",
    TimeLimit = 600,
},
['关卡1-2'] = {
    GridID = "场地2",
    ID = "关卡1-2",
    Spawn = "关卡1-2",
    TimeLimit = 600,
},
['关卡1-3'] = {
    GridID = "场地3",
    ID = "关卡1-3",
    Spawn = "关卡1-3",
    TimeLimit = 600,
},
}
return Data
