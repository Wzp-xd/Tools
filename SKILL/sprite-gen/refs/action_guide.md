# 动作描述编写规则 (Action Guide)

> Agent 写 anims.json 的 action 字段时必读。规则 + 示例。

## 核心原则

Kling i2v 以设定图作为首帧和尾帧输入，**角色一致性已由图片控制**，不需要文字描述角色外观。Prompt 只需要做一件事：**告诉模型角色要做什么动作**。

### 三条铁律

**1. 不描述角色外观**

首帧/尾帧图片已经完整定义了角色的样子。文字描述角色反而可能和图片冲突。

```
✗ "A dark slate-blue round plump crow-like bird performing..."
✓ "The bird performs..."  （甚至 "The character performs..." 就够了）
```

**2. 只描述动作概念，不编排关键帧**

只说"做什么动作"，让模型自己决定怎么动。越规定死细节，模型越容易生成不自然的东西。

```
✗ "The bird first pulls its head backward charging up, then thrusts 
   its neck forward in a sharp strike, beak fully extended..."

✓ "The bird performs a quick sharp pecking strike forward in mid-air, 
   then returns to hovering."
```

**3. 不描述角色设定里没有的新物体/特效**

只描述角色自身的体态变化。不暗示"产生新东西",不提及任何视觉特效。

```
✗ "impact burst at the beak tip"    ← 凭空出现了星芒/水花
✗ "dust cloud at feet"              ← 凭空出现了灰尘
✗ "energy glow around fist"         ← 凭空出现了特效
✓ "strikes forward with beak"       ← 只描述嘴巴的运动
```

---

## 游戏动画风格（所有动画通用）

Kling 默认生成"影视级"自然运动（幅度小、节奏匀）。**游戏精灵动画需要迪士尼/街机风格**：动作夸张、节奏鲜明。

### 4 条风格铁律

**1. 夸张（Exaggeration）** — 幅度比现实大 2-3 倍。

```
✗ "walks forward naturally"
✓ "strides forward with exaggerated bouncy steps, body bobbing up and down"
```

**2. 干脆利落（Snappy）** — 快速、果断、有弹性。

```
✗ "slowly raises fist and extends forward"
✓ "snaps fist forward in a lightning-fast punch"
```

**3. 对比节奏（Contrast）** — 蓄力慢 → 爆发极快 → 收招有惯性。不要全程一个速度。

**4. 剪影可读（Silhouette）** — 纯黑剪影下一眼可辨。肢体充分展开。

### 风格关键词（写 action 时按需选用）

| 类别 | 关键词 |
|------|--------|
| 夸张 | `exaggerated`, `over-the-top`, `big bold motion`, `dramatic` |
| 速度 | `snappy`, `lightning-fast`, `explosive`, `punchy`, `sharp` |
| 迪士尼 | `cartoon-style`, `squash and stretch`, `bouncy`, `springy` |
| 力量感 | `powerful`, `heavy impact`, `forceful`, `with tremendous weight` |

---

## 动作描述示例

### 循环动画

| 动画 | action 写法 | 备注 |
|------|------------|------|
| fly_flap | `hovers in mid-air, wings flapping up and down in big exaggerated sweeps with a bouncy springy rhythm` | 翅膀幅度要大 |
| ground_idle | `stands on the ground, body slightly swaying with a lively breathing rhythm, full of personality` | |
| run | `sprints forward at high speed with exaggerated bouncy strides, arms pumping wildly, body leaning forward aggressively` | 大步幅+前倾 |
| walk | `walks forward with exaggerated bouncy steps, body bobbing dramatically up and down with each confident stride` | 弹跳感 |
| bounce_move | `bounces forward with big springy exaggerated hops, squashing on landing and stretching on takeoff` | squash & stretch |

### 单次动画

| 动画 | action 写法 | 备注 |
|------|------------|------|
| dash | `suddenly rockets forward in a lightning-fast explosive burst, body stretching into a torpedo shape with tremendous speed, then snaps back to still pose` | 冲刺 |
| attack_punch | `throws one devastating explosive punch forward, fist shooting out at lightning speed with whole body driving behind it` | 攻击类 |
| attack_slash | `swings weapon forward in one explosive lightning-fast slash with full-body follow-through` | 攻击类 |
| hurt | `suddenly jolts backward in pain with an exaggerated full-body flinch, hunching inward dramatically, then gradually straightens back up` | 禁止提及外部攻击者 |
| jump | `one single jump, no root motion: crouches down low then explosively springs upward with powerful exaggerated force, body stretching at the peak, then drops back down` | squash & stretch |

### 过渡动画

| 动画 | action 写法 | 备注 |
|------|------------|------|
| land | `descends and lands on the ground, folding wings and settling into a standing pose` | |
| takeoff | ⚡ 复用 land 倒放 | 不需要单独生成 |

**⚡ 倒放复用原则：** 互为逆向的过渡动画只需制作一个方向，另一个在引擎中倒序播放。
