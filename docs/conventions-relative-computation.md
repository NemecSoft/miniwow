# C0 · 零凑数约定：一切用相对值计算

> **状态：最高优先级铁律，生效中（2026-10-22，M47 起强制执行）**
> **优先级：高于本项目其他一切约定与规范。任何与之冲突的写法，一律以本文为准。**
> 适用范围：所有坐标、朝向、尺寸、贴地、偏移、阈值、动画、光照、音效衰减、网络同步。
> 违反本文的代码，即使"测出来是对的"，也算缺陷，必须重写。

---

## 0. 原则原文

用户三次递进式批评，构成这条铁律：

> 第一次：「你总是说在说测量，这个不对，**碰撞和模型要一致，要自动算出来**，而不是测量，加一点减一点这种凑合。」
>
> 第二次：「**永远不要凑数，而是计算相对值！**」
>
> 第三次：「加一点减一点这种凑合，我不接受。」

核心一句话：

> **不要写"世界里的绝对数值"，要写"相对于某个语义锚点的表达式"。**
> 凡是需要"跑一次程序量出来的数字"才能成立的代码，都是错的。

---

## 1. 判据：什么算"凑数"

一条代码落进下面任一情形，就是凑数：

| # | 判据 | 典型形态 |
|---|---|---|
| J1 | **绝对坐标**：把一个数值直接当世界位置/偏移用 | `obj.position.y = 2.25`、`origin.y += 0.12` |
| J2 | **调参修形**：为了让画面/手感"看起来对"而反复微调常数 | `+ 0.20`、`* 1.02`、`gap < 0.35` |
| J3 | **双真值源**：同一个物理量有两套算法，靠人保证一致 | 解析式 `height_at()` + 渲染网格顶点 |
| J4 | **坐标系/单位混淆**：在 A 坐标系里算，却拿去 B 坐标系用 | 世界 Y 当"上"、`translated_local` 传已乘过 scale 的米数 |
| J5 | **经验值代替推导**：本可由几何关系算出，却抄了一个观测值 | 云的投影用 `EYEDIR.xz / EYEDIR.y` |

**反面判据**：如果删掉这个数字，函数就写不出来 —— 说明它是语义常量（如 `TAU`、`1440 分钟/天`），允许存在，但必须在文档里说明它的物理意义与来源。

---

## 2. 本项目真实反模式台账（有据可查）

这些都是本项目实际发生过的事故，留档作为负面教材。

### A1 · `Environment` 容器带平面时代的世界 Y 偏移
```
scenes/level/level.tscn:138
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.2542782, 0)
```
- 来历：平面地图时代"把地面抬高 2.25 米"。
- 在球面上：世界 Y 不是"上"，这等于把整棵环境子树沿世界 Y 平移 2.254 米。
- 后果：各点法线与世界 Y 夹角不同 → 悬空高度处处不同。出生点 `2.254 × (-0.162) = -0.365m`，与实测悬空 0.366m 完全一致。
- 定性：**J4 坐标系混淆**。正确写法是零偏移 —— 环境子树原点必须与星球球心重合，高度全部由半径表达。

### A2 · 广场整体抬 0.20 米（已废弃，列为禁例）
```
Arena/Geometry.global_position.y += 0.20   # 为了压住"绿斑"
```
- 后果：世界 Y 平移在球面上等于沿一个与当地法线无关的方向推整个平台，换位置就失效。为了压绿斑而抬地面，本质是"用一个错掩盖另一个错"。
- 定性：**J2 调参修形**。正解：平台与地形的高度关系必须由**同一份地表数据**推出，而不是加一个偏移去盖住穿模。

### A3 · 村庄道具的绝对 Y 抬升 —— ⚠️ **本人误判，已核查为合法，不得改动**
```
scripts/level/city_zone.gd:516   pt.origin.y += 0.12    # 地砖
scripts/level/city_zone.gd:519   tt.origin.y += 1.15    # 树
scripts/level/city_zone.gd:522   ct.origin.y += 4.1     # 建筑
scripts/level/city_zone.gd:564   tt.origin.y += 3.0
scripts/level/city_zone.gd:567   ht.origin.y += 6.1
```
- **初步判断（错误）**：这是 5 个"这个模型大约该抬多高"的魔法数，应改 `fit_ground`。
- **核查结论（正确）**：`level.gd:196-199` 对 `Environment` 的每个子节点做了：
  ```gdscript
  var nt := Planet.plane_transform(px, pz, yaw)
  nt.origin += nt.basis.y * py      # ← 平面 Y 被解释成"沿当地法线"
  node.global_transform = nt
  ```
  `CityZone` 不在排除名单里，因此**它的本地 Y 轴就是当地法线**。
  这 5 个数是「同一棵树内部部件的堆叠高度」（地砖半厚 0.12、树干中心 1.15、树冠中心 4.1…），
  属于 §1 判据末尾所说的**语义常量**：删掉就写不出这个结构，且数值来自 tsl 原版真值。
- **定性：合法，不是凑数。** 记在这里是为了防止以后"为了消灭凑数"把它改坏。

### A3-b · 由此得出的边界判据（最重要的产出）

**同样是 `origin.y += 1.15`，合法与否只取决于"这个 Y 轴指的是谁"：**

| 代码所在坐标系 | 本地 Y 的含义 | 判定 |
|---|---|---|
| `plane_transform()` 之后的节点内（如 `CityZone` 子树）| **当地法线** | ✅ 合法，是相对值 |
| 世界系（`global_position.y`、`Environment` 自身、`Environment` 的直系子节点）| 世界 Y（球面上**不是**"上"）| ❌ 凑数，见 A1/A2 |
| 未经重定位的平面容器（如 `Vehicles` 被强制 identity）| 平面 Y | ❌ 与世界系同义，必错 |

**判据一句话**：问"这条语句执行时，它所在的本地 Y 轴是否已被 `plane_transform` 对齐到当地法线？"
是 → 合法；否 → 凑数。

**正面示范（本项目已有，应作为模板）**：`level.gd:198` 的 `nt.origin += nt.basis.y * py`
—— 这是在把平面高度**正确地**解释为"沿当地法线抬 py 米"，而不是世界 Y 平移。

### A4 · 贴地靠"猜高度 + 阈值吸附"
```gdscript
# 旧实现（已删除）
var gap = r - ground_r
elif gap < 0.35 and velocity.dot(up) <= 0.05:   # 吸附阈值
    global_position = p - up * gap
if gap < -0.8:                                   # 穿模安全网
```
- 根因：地形没有碰撞体 → 只能解析式猜地面 → 与渲染网格差 0.3~5.4 米 → 只能用两个阈值兜。
- 定性：**J3 双真值源**。正解：碰撞体由渲染网格本身生成（`ArrayMesh.create_trimesh_shape()`），
  `is_on_floor()` 自然成立，**"地面在哪"这个问题从设计上消失**。
- 现状：已改。`_grounded = is_on_floor() or gap < 0.08`，0.08 仅作"星球尚未生成碰撞"的退化兜底，
  不是贴地手段。

### A5 · 云用世界坐标系做球面投影
```glsl
// 旧：addons/sky_3d/shaders/SkyMaterial.gdshader
vec3 clouds_pos = EYEDIR;
// render_cirrus_clouds() 里：pos.xz / pos.y
```
- 前提错误：`pos.xz / pos.y` 隐含"世界 Y 就是天顶"。
- 球面现实：当地天顶的世界 Y 分量只有 **-0.108**（不是 1），除法爆炸 → 天空出现从头顶放射的白色竖条纹。
- 定性：**J4 + J5**。正解：视线方向先转入**观察者当地坐标系**，天顶恒 `+1`，站在星球任何角落都一样。

### A6 · `translated_local` 传"算好 scale 的米数"
- 现象：`Transform3D.translated_local(offset)` 的偏移会被 basis 缩放**再乘一次**。
- 定性：**J4 单位混淆**。正解：传**网格本地坐标**（如圆柱半高 2.5），缩放交给 basis 一次完成。

### A7 · 球面世界里的"上"被当成 `Vector3.UP`
- 现象族：`rotation.y = ...` 想转朝向却拧了相机；`obj.global_position.y += x` 想抬高却横移；
  布局用 `(x, y, z)` 三元组却不知道哪个轴朝上。
- 定性：**J4**。铁律：**球面上唯一的"上"是 `up_at(pos)`（= 归一化位置）；"水平"是与它垂直的切平面。**

### A8 · 用世界 XZ 平面的 yaw 公式算朝向（M48，实测偏差 142°）
- 现象：`body.rotation.y = atan2(v.x, v.z) - parent.basis.get_euler().y`。
  平面地图上完全正确，球面上 **bot 背对运动方向跑**。探针实测：
  `v_yaw=+99.7° bodyYaw=-118.0° 差=+142.3°`。
- 根因：`atan2(v.x, v.z)` 求的是"速度在**世界 XZ 平面**上的方位角"，而球面上任何一点的
  水平面是**当地切平面**，两者可以差 90°（站在赤道 +X 侧时它们正交）。
  同理 `basis.get_euler().y` 只在"父节点绕世界 Y 轴旋转"时有意义，对球面上的任意基无定义。
- 定性：**J4 坐标系混淆**（世界轴 vs 当地基），与 A7 同源但表现更隐蔽——它不崩、只是慢慢拧。
- 正解（零推导，不用三角函数拼世界角）：目标本来就是父节点的子节点，
  **父节点 basis 已经是当地坐标系**（Y = 当地法线），把方向投影到它的切平面、
  在它自己的 x/z 轴上分解即可：

```gdscript
var pb := parent.global_transform.basis.orthonormalized()
var t := direction - pb.y * direction.dot(pb.y)   # 投影到父节点切平面
t = t.normalized()
rotation.y = atan2(t.dot(pb.x), t.dot(pb.z))       # body 局部 +Z = 模型正面
```

- **平面地图下父 basis 退化为单位基 → 公式退化为旧的 `atan2(v.x, v.z)`，零回归。**
  玩家根带 π 旋转、怪物根为 0 这类差异也自动消化（用的是完整 basis，不是抽出来的 yaw）。
- 复现/回归：`tools/m48_body_probe.gd` 的 `ORI[...]` 行，`差` 字段必须 **< 2°**。


### A9 · 地面射线写死 `collision_mask = 2`，看不见脚下真正踩的板（M53）
- 现象：走路时脚下拖出一条橙色烟雾带（用户："角色移动不对，有重影，飞行也有重影"）。
- 探针实测（`tools/m52_ground_probe.gd`）：
  - `_grounded` 在 120 帧里翻 **58 次**（静止 40 帧翻 0 次）
  - `LandParticles` 每帧生成一个，因为 `_was_airborne` 每帧被置位再清掉
- 根因链：广场地板 `KaykitArena/Floormap` 是 GridMap，碰撞落在 **layer 1（world_decor）**，
  而地面射线写死 `collision_mask = 2`（layer 2 = world）→ **射线看不见脚下那块板**，
  只能返回地形网格高度 → `gap` 恒为 0.316m → `gap < 0.08` 恒不成立 →
  接地状态 100% 押在会闪的 `is_on_floor()` 上。
- 定性：**J3 双真值源**（物理用玩家 mask=7 判定，逻辑用另一套写死层集合判定，两套不一致）。
- 正解：地面射线**直接用角色自己的 `collision_mask`**，只摘掉 actor 层：

```gdscript
const ACTOR_LAYER := 1 << 2          # project.godot: layer_3 = "actor"
q.collision_mask = collision_mask & ~ACTOR_LAYER   # "我能站什么"就是它
```

  修复后：`_grounded` 120 帧翻 **2 次**，落地粒子 **0**。
- 判据：**凡是写死层/组/路径的地方，都要问一句"这个集合会不会和另一个系统不一致"**。

### A10 · 接地阈值写死 `gap < 0.08`（M53）
- 现象：上一条修完仍偶发翻转——`gap` 实测在 **0.038~0.093m** 之间浮动（角色被
  `floor_snap_length` 吸在地面上，脚底与地面天然留一条缝），0.08 正好卡在浮动范围里。
- 定性：**J5 经验值代推导**。0.08 是"量一次拍下来的数"，换个胶囊/换个 snap 参数就失效。
- 正解：阈值由**引擎参数推导**，不写死：

```gdscript
_ground_gap_band = maxf(0.05, floor_snap_length * 0.5)   # 吸附带的一半以内必然贴地
_grounded = is_on_floor() or gap < _ground_gap_band
```

  修复后：120 帧翻 **0 次**，非接地帧 0/120。

### A11 · 每帧无条件写 `global_transform` 当"对齐球面"（M53）
- 现象：`_planet_frame_step` 每帧 `t.basis = Planet.align_basis(up, _fwd); global_transform = t`。
- 后果：物理服务器把角色当"瞬移"，`is_on_floor()` 被自己的写操作打乱。
  但它**不是**本次闪烁的主因（合并写入后翻转只从 58 降到 52）——
  真正主因是 A9/A10。留此条是为了记住"改之前先量"，别把相关当因果。
- 现状：改成**朝向变化 > 0.5°（肉眼不可辨）才写**，减少无意义重设：

```gdscript
const ALIGN_WRITE_MIN_ANGLE := 0.0087   # ≈ 0.5°
if _aligned.x.length_squared() < 0.5 \
        or _aligned.y.angle_to(target.y) > ALIGN_WRITE_MIN_ANGLE \
        or _aligned.z.angle_to(target.z) > ALIGN_WRITE_MIN_ANGLE:
    ...
```

  **反证**：把阈值调到 π（永不写）后角色直接陷进地里 0.46m —— 说明对齐本身必须做，
  只是不必每帧做。

### A12 · 血条位置/尺寸写死在场景文件里（M53）
- 现象：`player.tscn` 的 HealthBar `y=2.4 / scale=1.5`、`monster.tscn` 的 `y=2.6`；
  球面上换个位置就飘，且 `billboard` 枚举记错（1=全向，2=固定世界 Y）会把血条拉成竖条。
- 定性：**J1 绝对坐标 + J5 经验值**。
- 正解（`rogue_health_bar.gd:_fit_above_owner`）：
  - 高度 = 宿主**碰撞体顶**（胶囊/盒/柱）与**网格 AABB 顶**取大者 + 血条自身半高
    （蒙皮网格的 `mesh.get_aabb()` 是绑定姿势，实测玩家量出 1.01m，人实际 1.8m，不能单用）
  - 宽度 = 宿主宽度 × `BAR_WIDTH_RATIO`，且必须**均匀缩放**
    （非均匀缩放会把 billboard 平面拉歪，实测把 `scale.x` 单独压小后血条变成一根竖条）
- 复现：`tools/m50_ghost_probe.gd` 的 `n00_nohpbar.png` 对照帧（关掉血条前后对比）。


### A13 · 把"朝向角"当成世界标量，跨对象/跨端传递（M55，实测偏差 85.5°）
- 现象：用户连续三次反馈"飞行器朝向是错的"。截图里沙发横着挡在角色身前。
  探针实测 `tools/m55_couch_yaw_probe.gd`：
  `沙发前方 = (-0.198,-0.977,-0.078)` vs `身体正面 = (0.047,-0.009,-0.999)`，
  **夹角 85.5°**；换个位置再测又变成 20.7° —— **误差随位置变化**，这就是
  "有时看着对、有时歪着"的原因。
- 根因有两层，都是 A8 的同类复发（A8 只修了"身体自己算朝向"，没修"把朝向当数传出去"）：
  1. `_body_anchor_yaw()` 用 `atan2(basis.z.x, basis.z.z)` 求 yaw，再在 `_mount_basis()`
     里用 `Basis(Vector3.UP, yaw) * FORWARD` 还原。球面上世界 XZ 不是水平面，
     up 接近 ±X 时两者正交，误差直接吃满 90°。
  2. `hover_couch._turn_toward()` 插值用的"当前前方"取了 `basis.z`（+Z = 沙发**后方**），
     而 `align_basis(up, f)` 的 forward 参数决定的是 **-Z**。符号相反 → 稳态收敛到
     "沙发背对前进方向"，飞得越久越歪。
- 定性：**J4 坐标系混淆 + J3 双真值源**（同一朝向有"世界角"和"当地角"两套解释）。
- 正解：朝向角只能相对**当地切平面**表达，且编码与解码共用同一对纯函数
  （`planet.gd`）：`yaw_of(up, dir)` / `dir_of_yaw(up, yaw)` / `basis_from_yaw(up, yaw)`，
  参考轴统一为 `tangent_ref(up)`。任何要跨帧、跨对象、跨网络保存/传递的朝向都必须走这套。
- 复现/回归：`tools/m56_mount_yaw_probe.tscn`，6 个球面位置 × 4 个状态共 30 项断言，
  要求 **全部 < 2°**（当前实测 0.00°）。


### I-MOUNT · 骑乘朝向一致性（硬不变量，M55 用户明确要求）

> 用户原话：「角色和飞行器的朝向要保持一致」。
> 这不是"最好一致"，是**必须逐帧成立**的关系式。

| 项 | 规定 |
|---|---|
| 关系式 | `angle(身体正面 +Z, 载具前方 -Z) < 2°`，切平面内度量 |
| 驱动方向 | 移动方向 → **载具** → **角色**（单向）；禁止角色反向驱动载具 |
| 上座瞬间 | 载具按 `_body_anchor_yaw()`（= 身体正面）构造，天然 0°，所以 snap 不产生跳变 |
| 实现 | `player.gd` 骑乘分支每帧 `_body.snap_rotation_to(-载具.basis.z)`（不用 lerp） |
| 远端可见 | `GodotRobot3D:rotation` 已在 player.tscn 的同步列表里，远端一致 |
| 验收 | `tools/m56_mount_yaw_probe.tscn`：6 位置 × {静止/直飞/松手/转弯} 共 30 项 |

反例（都属于"看起来对，其实在拧"）：
- 用载具位移方向驱动角色（位移方向 ≠ 车头；转弯时车头先到、位移滞后）；
- 上座时把角色拧向相机（把 `_body_anchor_yaw` 写成根节点 `rotation.y`）；
- 载具静止时不写朝向（载具被同步/复用改过朝向，角色就停在旧方向）。


---

## 3. 正解：相对值三定律

### 定律一 · 单一真值源（Single Source of Truth）
每个物理量只能有**一份**权威数据。其他一切用法都必须由它推导，不允许"另算一份再对齐"。

| 物理量 | 唯一真值源 | 禁止 |
|---|---|---|
| 地形表面形状 | 渲染用的 `ArrayMesh` 顶点 | 另写解析式重算（A4） |
| 模型脚下的基准面 | 模型顶点 AABB 的 `min.y`（本地系） | 手写 `+1.15`（A3） |
| 当地"上"方向 | `Planet.up_at(pos)` | `Vector3.UP`（A7） |
| 星球尺寸 | `Planet.RADIUS` / `PlanetProfile` | 硬编码 2200 / 1500 |

### 定律二 · 相对锚点表达（Anchor-Relative）
不用绝对坐标描述物体，用"相对某个锚点的关系"描述：

```
错误：tree.position = Vector3(-34, 1.15, -1552)
正确：tree 放在 方向 dir 的表面上，沿当地法线抬起 tree 自身几何底边的高度
```

物体的位置 = **锚点 + 沿当地基向量的有向距离**。锚点必须是语义化的：
`地表`、`父节点`、`模型几何底边`、`骨骼挂点`、`载具座位`。

### 定律三 · 纯函数推导（Derive, Don't Store）
中间结果不要缓存成常数；每次从真值源算出来（必要时缓存**真值源本身**，而不是它的运算结果）。
- ✅ 允许：缓存渲染网格顶点数组（那是真值源）。
- ❌ 禁止：缓存"我算出来的地面高度偏移量"（那是结果）。

---

## 4. 球面空间 API 设计

目标：让"写凑数"在架构上**不可能**。所有定位只允许通过下面三层 API，禁止直接写 `position`。

### 4.1 L0 · 地表层（Surface Space）：`Planet`
已有的、且符合本原则的 API（保留）：

| API | 语义 | 为什么是对的 |
|---|---|---|
| `up_at(pos)` | 当地"上" | 由位置归一化推导，无常数 |
| `ground_pos(dir)` | 该方向的地表点 | `dir * (RADIUS + mesh_height(dir))`，全部相对 |
| `surface_pos(dir)` | 同上（语义别名） | 同上 |
| `snap_to_surface(pos)` | 径向吸附到地表 | 纯函数 |
| `dir_from_plane(x, z)` / `plane_of(dir)` | 平面 ↔ 球面坐标 | 显式转换，不混用 |
| `align_basis(up, forward)` | 构造 Y=法线 的正交基 | 由两个向量推出，无常数 |
| `plane_transform(x, z, yaw)` | 平面刚体 → 球面变换 | 迁移期专用，用于把旧布局搬上球面 |

### 4.2 L1 · 落位层（Placement Space）：新增，统一"贴到表面"
所有需要"站在表面上"的东西（建筑、树、道具、怪、NPC、载具、玩家的初始位置）
**只允许**调用同一个落位函数：

```gdscript
## 把一个节点放到 dir 方向的表面上。
##   dir      : 世界方向（决定落在球面哪个位置）
##   lift     : 沿当地法线的**相对**抬升（米）。默认 0 = 正好贴地。
##              注意：这里 0 就是"贴地"，不是"再加 0.12"。
##   yaw      : 绕当地法线的方位角（弧度），默认沿用节点当前朝向
##   ground_gap: 自动测得的"模型几何底边相对节点原点的偏移"，
##              由 fit_ground() 从模型 AABB 计算，禁止手填
static func place_on_surface(node: Node3D, dir: Vector3, yaw: float = NAN) -> void
```

配套的**几何对齐**函数（消灭 A3 那 5 个魔法数的关键）：

```gdscript
## 让模型的最低点正好落在它脚下的表面：
##   1) 遍历模型所有 MeshInstance3D 顶点，求本地系 min.y（真值源）
##   2) 节点沿当地法线抬起 (min.y 相对节点原点的投影) + lift
## 换模型、换星球、换坡度都自动正确，无需任何手填数值。
static func fit_ground(node: Node3D, lift: float = 0.0) -> void
```

> `fit_ground()` 解决的是「**一个整体刚体**放到星球表面时，它该抬多高」。
> 它**不解决**模型内部部件的堆叠（见 A3-b：那属于已对齐本地系里的语义常量，本来就对）。
> 二者边界：**整棵物件落到地表** → `fit_ground()`；**物件内部各部件相对摆放** → 本地常量。

### 4.3 L2 · 局部层（Local Space）：父节点坐标系
节点之间的相对关系（座位、挂点、武器、头顶血条）**一律用本地变换**：

```gdscript
# ✅ 正确：座位是载具的本地偏移，随车走；尺度由父节点 basis 一次施加
rider.global_transform = seat_marker.global_transform

# ❌ 错误：把本地偏移手动乘成世界米数再相加
rider.global_position = vehicle.global_position + Vector3(0, 1.2, 0)
```

规则：**能用 `global_transform * local_offset` 表达的，绝不手写分量加法。**

### 4.4 禁止清单（写进 CI 检查）

```gdscript
# 全部禁止出现在 scripts/ 内：
*.global_position.y += ...          # 世界 Y 不是"上"
*.position.y = <字面量>              # 绝对高度
Vector3.UP 作为方向基准（应 up_at）
<数字> 与 up 相乘/相加来"调整高度"   # 除 API 内部实现外
```

例外：`planet.gd` / 空间 API 自身实现、以及数学常量。

---

## 5. 提交前必答七问（评审清单）

任何涉及位置/朝向/尺寸/阈值的改动，提交前逐条自答，答不上就改到答得上：

1. **这个数字是从哪来的？** 是算出来的，还是我量出来/试出来的？（若是后者 → 不合格）
2. **它的锚点是什么？** 地表？父节点？模型底边？说不清 → 不合格。
3. **换一个位置还成立吗？** 把这个物体搬到星球另一面，还贴地吗？
4. **换一个模型/尺寸还成立吗？** 把树换成两倍高的树，还贴地吗？
5. **换一个星球还成立吗？** R=2200 与 R=1500 都成立吗？
6. **它和谁必须一致？** 如果"另一份算法"要和它对齐，就存在双真值源 → 必须合并。
7. **删掉它会不会崩？** 会崩说明它是语义常量（合法）；不会崩但画面变了 → 它是凑数（不合法）。

---

## 6. 自动化防呆

### 6.1 探针必须断言"关系"，不是断言"数字"
```gdscript
# ❌ 凑数式验收：把量到的值写死
assert(abs(gap - 0.37) < 0.01)

# ✅ 相对式验收：断言不变量
assert(absf(player.global_position.length() - Planet.ground_pos(dir).length()) < 0.05,
       "玩家必须站在地表上（容差仅为浮点误差）")
assert(is_on_floor(), "物理引擎必须判定为站在地面上")
```
判据：**断言里出现的应该是"两个量的关系"，而不是一个观测到的常数。**

### 6.2 恒等式自检（跨星球/跨位置）
把同一套断言在 `azeroth` / `outland` 两个星球、出生点/广场/山坡三个位置各跑一遍。
过一遍就是"相对值"，只在一个点上过就是"凑数"。

### 6.3 搜索式巡检
定期执行，凡是命中都需人工确认：
```bash
grep -rnE "\.y \+=|\.y = [0-9]|position\.y|Vector3\.UP" scripts/ --include=*.gd
# A13：任何"把朝向算成世界角"的写法（球面上最多差 90°）
grep -rnE "atan2\([^)]*\.x, ?[^)]*\.z\)|Basis\(Vector3\.UP, [a-z_]*(yaw|angle)" scripts/ --include=*.gd
```
输出 `yaw` / `angle` 的变量，追一遍它的**消费端**：
只要它被用来还原方向（`Basis(..., yaw)`、`sin/cos`、写 `rotation.y`），就必须改成
`Planet.yaw_of / dir_of_yaw / basis_from_yaw` 三件套（相对当地切平面）。

### 6.4 视觉验收的三条硬规矩（M48，用户两次退单后确立）

用户原话：**"你的检查方式不对，优化你自己的检查方式"**。此前的探针只量"离地多少米"、
只查本地玩家、只看静止状态 —— 三个都是**看不出问题**的检查。

1. **检查对象必须是"用户眼睛看到的那一份"**
   用户看的是双端画面，远端玩家和 bot 都在镜头里。
   只 dump 本地玩家 = 主动放弃 90% 的可疑对象。
   → 遍历 `PlayersContainer` **全部**子节点，逐个跑同一套断言。

2. **必须检查"视觉分组"，不是只检查"属性有没有设"**
   重影的唯一正确判据：把子树里所有 `is_visible_in_tree()` 的 `MeshInstance3D`
   按**所属模型**（`RobotArmature` / `InfantryVisual`）分组，**分组数 > 1 就是重影**。
   只读 `use_alt_body` / `alt_visible` 会被"属性看着对、实际两套都在渲"骗过去。

3. **必须制造一次可观测的状态变化，否则"看起来对"是巧合**
   验朝向同步时，只按 W 是没用的：出生朝向恰好等于前进方向，
   `body.rotation.y` 恒 0，同步彻底坏掉也看不出来。
   → 先按 W 再按 A，制造一次 **90° 转向**，看远端值有没有跟着跳。
   （M48 实测：修好前远端 `bodyY` 恒 `0.000`，修好后 `0.296 → 1.569 → 1.571`）

**工具**：`tools/m48_body_probe.gd`（单人 / 双端通用，`--auto host|join`）。
输出三类前缀，全部可直接核对的数值：`VIS[玩家]` 重影、`BODY[玩家]` 模型开关、
`ORI[玩家|阶段]` 朝向（`差` 字段即"身体朝向 vs 运动方向"，必须 < 2°）。


---

## 7. 整改台账

| 编号 | 位置 | 问题 | 状态 |
|---|---|---|---|
| A1 | `scenes/level/level.tscn` Environment | 世界 Y 偏移 2.254 | ✅ 已删 + `terrain_starter` 运行时兜底 |
| A4 | `player.gd` 贴地 | 猜高度 + 阈值吸附 | ✅ 已改碰撞体由网格生成 |
| A5 | `SkyMaterial.gdshader` 云 | 世界系做球面投影 | ✅ 已转当地坐标系 |
| A3 | `city_zone.gd` 516/519/522/564/567 | 5 处本地 Y 堆叠 | ✅ **核查为合法**（在 `plane_transform` 后的本地系内，Y=当地法线），**不得改动** |
| A2 | `Arena/Geometry` | 曾经的 `+0.20` 压绿斑 | ✅ 已确认无残留（`arena.tscn:85` 为 identity，无代码运行期改它）|
| — | 怪物刷点 | 平面坐标 `(-34,-1552)` 探不到地面 | ⬜ 待整改（改 `place_on_surface`）|
| A8 | `3d_godot_robot.gd` | `apply_rotation` 用世界 XZ yaw（偏差 142°） | ✅ 改父 basis 投影，实测差 < 2° |
| A7 | `bot_controller.gd` 出生点 | `Vector3(i*3,0,0)` 世界轴偏移 + 平面地形探针 | ✅ 改当地切平面黄金角 + `snap_to_surface` + `fit_ground` |
| — | `player.gd` 远端朝向 | 非 authority 早退 → 远端 `body.rotation.y` 从不更新 | ✅ 新增 `_net_body_yaw` RPC（10Hz），双端实测千分位一致 |
| A13 | `player.gd:_body_anchor_yaw` / `_mount_basis` | 世界 atan2 编码朝向（实测差 85.5°，随位置变化） | ✅ 改 `Planet.yaw_of/basis_from_yaw`，6 位置 30 断言全 0.00° |
| A13 | `hover_couch.gd:_turn_toward` | 插值基准取 `basis.z`（后方）而 target 是 -Z → 收敛到反向 | ✅ 改 `_turn_toward_dir(dir)`，车头↔位移实测 0.11° |
| A13 | `sports_car.gd:198/359` | 姿态回正用 `Quaternion(Vector3.UP, yaw)`（世界轴） | ⬜ 待改（球面上车会立起来；tsl 状态机，需单独回归）|
| A13 | `world_map_ui.gd:_player_facing_yaw` | 仍返回世界 yaw（当前仅作它用，圆盘箭头已走 `_facing_dir_on_disk`）| ⬜ 确认无调用后删除 |
| A13 | `monster.gd:655` / `partner.gd:95` | 转向用世界 atan2 | ⬜ 待改（怪物/小精灵在球面远端会歪）|

### 7.1 唯一真欠账：怪物刷点的正确改法（设计，未实施）

**现状（`monsters/monster.gd:138-146`）**
```gdscript
var h := GroundQuery.resolve(get_world_3d(), terrain_data, home_position, exclude)
if is_nan(h):
    printerr("SPAWN_WARN: ...")
    return
home_position.y = h + 0.05      # ← J1 绝对坐标 + J2 调参
global_position = home_position
```
**根因**：`Monsters` 是 `Environment` 的直系子节点，已被 `plane_transform()` 重定位到球面，
它的**本地 Y 是当地法线，世界 Y 不是**。而这里把本地坐标当世界坐标去打射线、又把世界 Y 写回，
两者语义不一致 → 39 个怪全部 `SPAWN_WARN`。

**正解（零射线、零偏移）**
```gdscript
var p3 := get_parent() as Node3D
var target := home_position
if p3 != null:
    target = p3.global_transform * home_position   # 本地 → 世界（唯一转换点）
target = Planet.snap_to_surface(target)            # 沿世界径向落到地表
global_position = target
Planet.fit_ground(self, 0.0)                       # 几何底边贴地，不再 +0.05
```
- 删掉 `GroundQuery` 射线、删掉 `+0.05`、删掉 `SPAWN_WARN` 分支（非法刷点改由
  `is_in_void()` 判定，而不是"探不到地面"）。
- **验收断言**：每个怪 `|怪物几何最低点 - 地表| < 0.05`，且**在 azeroth / outland 两个星球都成立**。
- **风险**：牵扯 39 个怪的落点，必须双端联调确认（位置全变属于预期，不能拿旧截图当基准）。

---

## 8. 一句话总结

> **代码里出现的每个数字，都必须是"某个语义锚点上的运算结果"，而不是"我试出来的数"。**
> 需要测量才能确定的，就说明设计还没做完 —— 回去改设计，不要写数值。
