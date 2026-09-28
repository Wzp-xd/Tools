# FPS 武器系统集成待办事项

> 将 `scripts/demo` 中的 FPS 武器系统集成到当前多人游戏中

## 📋 概述

**目标**: 将 demo 中的枪械、模型、射击、瞄准、子弹逻辑加入多人游戏

**源代码**: `scripts/demo/modules/`
- `Config.lua` - 武器配置（6把武器、后坐力、弹药等）
- `Weapon.lua` - 武器系统（切换、瞄准、换弹、后坐力）
- `Bullet.lua` - 子弹系统（物理/射线检测、发射、碰撞）
- `HitEffects.lua` - 击中特效（火花、弹孔、烟雾）
- `WeaponAttachment.lua` - 武器绑定到角色骨骼

**目标代码**: `scripts/network/`
- `Shared.lua` - 共享配置
- `Client.lua` - 客户端逻辑
- `Server.lua` - 服务端逻辑

---

## 🔧 集成任务

### 阶段 1: 配置系统

#### 1.1 武器配置集成 (Shared.lua)
- [ ] 将 `Config.WEAPONS` 武器表移植到 `Shared.Settings.Weapons`
- [ ] 将 `Config.WEAPON_ORDER` 移植
- [ ] 将 `Config.CASING_CONFIG` 弹壳配置移植
- [ ] 添加子弹相关配置（`BulletCollisionMode`, `MaxShootDistance` 等）

**需要添加的武器**:
| ID | 名称 | 类型 |
|----|------|------|
| g17 | G17手枪 | 手枪 |
| ak74 | AK74 | 突击步枪 |
| m4 | M4卡宾枪 | 突击步枪 |
| mp5 | MP5冲锋枪 | 冲锋枪 |
| sks | SKS狙击枪 | 狙击步枪 |
| sawed | 短管霰弹枪 | 霰弹枪 |

---

### 阶段 2: 模块文件创建

#### 2.1 创建 `scripts/network/modules/` 目录结构
- [ ] 创建 `modules/WeaponConfig.lua` - 武器配置
- [ ] 创建 `modules/WeaponAttachment.lua` - 武器绑定（适配 demo）
- [ ] 创建 `modules/HitEffects.lua` - 击中特效（适配 demo）
- [ ] 创建 `modules/BulletVisual.lua` - 子弹视觉效果（客户端专用）

---

### 阶段 3: 客户端更新 (Client.lua)

#### 3.1 武器模型系统
- [ ] 导入 `WeaponAttachment` 模块
- [ ] 在 `SetupPlayerAnimation()` 中添加武器附加
- [ ] 添加武器切换逻辑（数字键 1-6）
- [ ] 添加 `SwitchHandWeapon()` 函数

#### 3.2 射击系统
- [ ] 添加射击冷却（使用武器 `fireRate`）
- [ ] 添加弹药系统（`currentAmmo`, `reserveAmmo`）
- [ ] 添加换弹逻辑（R键触发）
- [ ] 添加自动射击支持（`automatic` 武器）

#### 3.3 瞄准系统 (ADS)
- [ ] 添加右键瞄准切换
- [ ] 添加相机配置切换（normal → armed → aiming）
- [ ] 添加 FOV 过渡动画
- [ ] 添加狙击镜特殊处理（`hasScope` 武器）

#### 3.4 后坐力系统
- [ ] 添加 `pendingRecoilPitch` 和 `pendingRecoilYaw`
- [ ] 在 `UpdateMouseLook()` 中应用后坐力
- [ ] 添加后坐力恢复逻辑

#### 3.5 准星系统 (NanoVG)
- [ ] 添加动态准星绘制
- [ ] 添加准星扩散（`crosshairSpread`）
- [ ] 添加准星恢复动画
- [ ] 瞄准时准星收缩

#### 3.6 击中特效
- [ ] 导入 `HitEffects` 模块
- [ ] 在 `HandleShootHit()` 中添加特效类型判断
- [ ] 添加火花、烟雾、弹孔效果
- [ ] 添加特效更新循环

#### 3.7 子弹视觉效果
- [ ] 添加子弹拖尾效果
- [ ] 添加枪口闪光
- [ ] 添加弹壳抛出效果

#### 3.8 UI 更新
- [ ] 添加弹药 HUD（当前弹匣/备用弹药）
- [ ] 添加武器名称显示
- [ ] 添加换弹进度条
- [ ] 添加狙击镜覆盖层

---

### 阶段 4: 服务端更新 (Server.lua)

#### 4.1 武器状态同步
- [ ] 添加 `serverCurrentWeapon_[roleId]` 追踪当前武器
- [ ] 添加 `serverAmmo_[roleId]` 追踪弹药状态
- [ ] 添加武器切换事件处理

#### 4.2 射击伤害计算
- [ ] 根据武器配置计算伤害（`weapon.damage`）
- [ ] 添加霰弹枪距离衰减
- [ ] 添加爆头判定（可选）

#### 4.3 网络事件扩展
- [ ] 添加 `WEAPON_SWITCH` 事件
- [ ] 添加 `RELOAD_START` / `RELOAD_COMPLETE` 事件
- [ ] 添加 `AMMO_UPDATE` 事件
- [ ] 扩展 `SHOOT_HIT` 事件（添加击中类型）

---

### 阶段 5: Shared.lua 扩展

#### 5.1 新增配置
```lua
Shared.Settings.Weapons = { ... }  -- 武器配置表
Shared.Settings.WeaponOrder = { ... }  -- 武器顺序
Shared.Settings.Bullet = { ... }  -- 子弹配置
Shared.Settings.Recoil = { ... }  -- 后坐力配置
```

#### 5.2 新增事件
```lua
Shared.EVENTS.WEAPON_SWITCH = "WeaponSwitch"
Shared.EVENTS.RELOAD_START = "ReloadStart"
Shared.EVENTS.RELOAD_COMPLETE = "ReloadComplete"
Shared.EVENTS.AMMO_UPDATE = "AmmoUpdate"
```

#### 5.3 新增变量
```lua
Shared.VARS.CURRENT_WEAPON = "CurrentWeapon"
Shared.VARS.CURRENT_AMMO = "CurrentAmmo"
```

---

## 📁 文件修改清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `network/Shared.lua` | 修改 | 添加武器配置 |
| `network/Client.lua` | 修改 | 添加武器/射击/瞄准系统 |
| `network/Server.lua` | 修改 | 添加武器伤害计算 |
| `network/modules/WeaponConfig.lua` | 新建 | 武器配置模块 |
| `network/modules/WeaponAttachment.lua` | 新建 | 武器绑定模块 |
| `network/modules/HitEffects.lua` | 新建 | 击中特效模块 |
| `network/modules/BulletVisual.lua` | 新建 | 子弹视觉模块 |

---

## 🎯 优先级排序

1. **P0 - 核心功能**（必须实现）
   - 武器配置集成
   - 武器模型绑定
   - 射击逻辑
   - 伤害计算

2. **P1 - 重要功能**
   - 弹药系统
   - 换弹逻辑
   - 武器切换
   - 准星系统

3. **P2 - 增强功能**
   - 后坐力系统
   - 击中特效
   - 子弹视觉
   - 瞄准系统

4. **P3 - 可选功能**
   - 弹壳抛出
   - 狙击镜覆盖
   - 弹药 HUD

---

## ⚠️ 注意事项

1. **多人同步**: 武器状态需要服务端权威，客户端只做预测
2. **性能**: 击中特效应有数量限制，避免大量粒子
3. **模块依赖**: 避免循环依赖（参考 demo 中的延迟加载模式）
4. **武器 Prefab**: 确保 prefab UUID 路径在多人环境可用

---

## 📅 实施顺序

```
Step 1: 创建 modules/ 目录和 WeaponConfig.lua
Step 2: 更新 Shared.lua 添加武器配置引用
Step 3: 创建 WeaponAttachment.lua（适配 demo）
Step 4: 更新 Client.lua 添加武器模型
Step 5: 创建 HitEffects.lua（适配 demo）
Step 6: 更新 Client.lua 添加射击和特效
Step 7: 更新 Server.lua 使用武器伤害
Step 8: 添加准星和后坐力
Step 9: 添加弹药和换弹系统
Step 10: 测试和调优
```

---

*文档创建时间: 2026-02-05*
*状态: 待实施*
