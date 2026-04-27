-- ============================================
-- Field Comments:
--   Count: 数量
--   ID: ID
--   PointCreate: 在指定点创建
--   PointEnemy: 在敌人出生点创建
--   PointTarget: 目标位置编号
--   Reward: 击杀奖励/单位
--   TimePulse: 间隔
--   TimeStart: 出怪开始时间
--   UnitID: 单位
-- ============================================

local Data = {
['关卡1-1'] = {
	{
		Count = 5,
		GridID = "关卡1-1",
		ID = 1,
		PointEnemy = 1,
		PointTarget = 1,
		Reward = {10, 0},
		TimePulse = 3,
		TimeStart = 10,
		UnitID = "怪物1",
	},
	{
		Count = 3,
		GridID = "关卡1-1",
		ID = 2,
		PointEnemy = 2,
		PointTarget = 1,
		Reward = {0, 5},
		TimePulse = 1,
		TimeStart = 20,
		UnitID = "怪物2",
	},
	{
		Count = 1,
		GridID = "关卡1-1",
		ID = 3,
		PointCreate = {2, 4},
		PointTarget = 1,
		Reward = {30},
		TimeStart = 25,
		UnitID = "怪物3",
	},
},
}
return Data
