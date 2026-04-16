-- ============================================
-- 瀛楁澶囨敞:
--   Count: 数量
--   ID: ID
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
		TimePulse = 2,
		TimeStart = 0,
		UnitID = "怪物1",
	},
	{
		Count = 3,
		GridID = "关卡1-1",
		ID = 2,
		TimePulse = 0.1,
		TimeStart = 6,
		UnitID = "怪物2",
	},
	{
		Count = 1,
		GridID = "关卡1-1",
		ID = 3,
		TimeStart = 15,
		UnitID = "怪物3",
	},
},
}
return Data
