# 多人视觉/交互同步约定（M27）

> 状态：生效中（2026-10-19，M27 起强制执行）
> 适用范围：一切跨端可见的实体——玩家（真人/bot）、载具（hover_couch）、
> 世界物品；一切跨端动作——骑乘、外观、动画、朝向。
> 前置约定：`conventions-spawn-ground.md`（C1~C6 贴地）、
> `conventions-mount-lifecycle.md`（M1~M8 生命周期）、M26 RPC 方向铁律。

---

## 0. 本轮事故记录（为什么立这份约定）

用户双开（host + join）实测，一次截图暴露四类问题：

| # | 用户原话 | 现象 |
|---|---------|------|
| A | "客户端按 x 上不了坐骑……按 E 也没用" | 客户端 X 召唤/E 上座全部静默失效 |
| B | "能看到主机位置，但看不到主机的坐骑" | 主机骑沙发飞行，客户端只见悬空滑行的人 |
| C | "主机自己选战士红色，自己看到电视头没颜色，客户机看到红色机器人" | 同一角色两端模型+颜色双裂 |
| D | "看不到对方的动作，朝向还是反的" | 远程角色僵住/背身 |

### 根因链（全部有代码级证据）

**A/B：沙发从未接入网络同步层（结构性缺失）**
- `Environment/Vehicles` 下**没有 MultiplayerSpawner**。沙发是
  `_summon_mount()` / `bot_summon_and_mount()` 在各端本地 instantiate 的。
- 客户端按 X → 本地造出 `couch_2`（`add_child(couch, true)` 的 `true` 在
  客户端不会广播）→ `couch.request_mount.rpc_id(1)` 按**发送方节点路径**
  寻的服务器 `Level/Environment/Vehicles/couch_2`——服务器没有这个节点 →
  rpc 静默失败。E 键同链路（`request_mount.rpc_id(1)` 寻的失败）。
- 主机按 X → 服务器造出 `couch_1`，无 spawner → 不广播 → 客户端无沙发节点。
- 结论：**"本地生成 + rpc 上座"架构从设计上就要求沙发节点各端存在**，
  而它从未被同步。单人模式一切正常，双端必炸。

**C：外观状态两裂**
- 模型裂：`_add_player()` 只读 player_info 的 nick/skin，**不读 class**；
  `Network.players` 注册信息里**没有 class 字段**。客户端经
  `_sync_registered_player` 创建主机玩家节点时 `player_class=""` →
  `use_alt_body=false` → 显示 GodotRobot；而主机本地早已选过职业
  （`sync_class.rpc` 只对**当时在线**的 peer 广播，迟加入者收不到）。
- 颜色裂：`set_player_skin()` 只给 GodotRobot 的 4 个 mesh
  （Bottom/Chest/Face/LimbsAndHead）换贴图，**完全不管 KayKit Mannequin**
  （`alt_visual`）。步兵职业换模型后皮肤设置静默丢失。
- 附带缺陷：`--auto host/--auto join` 联调通道硬编码皮肤
  blue/yellow，主菜单真实选择被丢弃，联调验证不到皮肤链路。

**D：朝向反 + 无动作**
- 朝向反：`_on_camera_turn()` 直接写 **Player 根节点** `rotation.y += dx`，
  而 Player 根 rotation **不在任何同步属性里**；`Body.apply_rotation()`
  又把父节点全局 yaw（含累计 dx）烘进 `GodotRobot3D:rotation` 这个
  **局部**角再同步出去 → 客户端父 yaw 缺 dx → 渲染朝向偏差 = -累计 dx。
  右键转过半圈，两端朝向正好相反。
- 无动作：`_physics_process` 的 mounted 分支直接 `return`，
  `set_mounted` 之后**再无任何 `_request_animation`** → 远程端永远 Idle。
- bot 不受 D 影响：bot 根 yaw 恒为 π（两端相同），局部角换算自洽。

---

## 1. 约定条款

### V1 载具必须经 MultiplayerSpawner 广播（唯一创建入口）

- 一切载具（hover_couch 及未来任何可骑乘物）**只能由服务器创建**：
  `vehicles.add_child(couch, true)` 且 `Environment/Vehicles` 下必须有
  MultiplayerSpawner（spawnable 含沙发场景）。服务器 add_child 即自动
  广播 spawn 消息，**含 late-join 重放**（新客户端上线即见场上全部载具）。
- **客户端严禁本地 instantiate 载具**。兜底造车、测试代码、临时脚本，
  一律不允许。客户端的唯一动作是发请求（见 V2）。
- 原因：本地造车 = 该节点只存在于一端；以其为发送方的任何 rpc
  都会在对端 "Node not found"（rpc 寻的 = 发送方节点路径，见 V8.3）。

### V2 骑乘交互一律"客户端请求 → 服务器权威执行 → 广播"

链路固定为四段，缺一段即视为 bug：

```
客户端输入（X/E）→ request_*.rpc_id(1, ...)
  → 服务器在权威节点上执行（创建/就座/摘座/收车，本地直调 server_* 方法）
  → 状态广播（seats 经 sync_seats.rpc_id 真实骑手；位置经玩家 Synchronizer）
  → 各端 set_mounted / 位置跟随
```

- 请求入口必须带**发送者身份校验**：
  `sender == 0（服务器本地）或 sender == 节点 multiplayer authority`，
  否则 return（防伪造/防串号）。
- 服务器执行时**禁止使用 `multiplayer.get_unique_id()` 当目标 peer**——
  服务器上它恒为 1。所有代召唤/代上座接口必须显式传 target peer id
  （如 `_summon_mount(target_id)`）。本轮 `_summon_mount` 若直接复用旧体，
  会给主机（peer 1）造车而不是请求者，属高危陷阱。
- X 召唤即骑：服务器创建 + 就位 + `server_mount_peer(target_id)` 本地直调，
  不走 loopback rpc（`request_mount.rpc_id(1)` 的 sender 归一会把
  请求者误判成 peer 1）。
- E 交互：Prompt 显隐、距离判定在沙发节点本地跑；客户端沙发节点来自
  spawner 广播（V1），链路自然闭合。

### V3 外观状态（职业/皮肤）权威源在服务器，迟加入者必须可初始化

- `Network.players[peer_id]` 注册信息是**外观权威副本**，字段：
  `nick / skin / class`。三字段缺一即视为不同步缺陷。
- 职业变更（`request_choose_class` 服务器分支）必须**同步回写**
  `players[authority]["class"]`；否则迟加入客户端拿到空 class。
- `_add_player()` 创建任何玩家节点（真人/bot/迟加入）时：
  nick/skin/class **三样全部从 player_info 初始化**。class 非空时
  本地设置 `player_class + _apply_class_base_stats() + _update_body_visual()`，
  **不走 rpc 回环**（_add_player 双端都跑，信息一致，广播反而制造时序竞态）。
- 在线期间的职业变更继续走 `sync_class.rpc` 全播（既有链路，V3 只管初始化）。

### V4 皮肤应用必须覆盖全部身体视觉

- `set_player_skin()` 对所有视觉换肤，一个都不能漏：
  - GodotRobot：`RobotArmature/Skeleton3D` 下 Bottom/Chest/Face/LimbsAndHead；
  - KayKit Mannequin（alt_visual）：递归子树中**主 SkinnedMesh3D**（身体），
    武器挂件（LazerSword/Handle 等 MeshInstance3D）不染。
- 新增身体视觉变体时，必须同步扩展 `set_player_skin()` 并在交付前
  双端截图验证（见 §3 验证清单）。

### V5 朝向同步：Player 根 rotation 是同步属性，不是本地私有状态

- `Body.apply_rotation()` 的世界→局部换算依赖**父节点全局 yaw**；
  只要父 yaw 有任何不同步的输入（典型：`_on_camera_turn` 的 `rotation.y += dx`），
  "同步局部角"就会把偏差烘焙进去，对端朝向必裂。
- **规则：玩家根节点 `rotation` 必须列入 player.tscn 的
  SceneReplicationConfig（广播模式）**。任何写 `rotation.y` 的代码，
  先确认该值在同步属性里；不在 = 朝向裂 bug。
- bot 根 yaw 恒定（π），不受本条约束，但一旦给 bot 加转身输入，
  同样必须把根 rotation 加进 BotSyncConfig。

### V6 动画广播必须覆盖全部状态机入口

- 所有改变视觉状态的入口（移动/跳跃/攻击/骑乘/格挡/冲刺）都必须经
  `_request_animation()` 上报（服务器权威 + `_server_publish_animation`
  广播），**不允许出现"只本地播放"的分支**。
- mounted 分支尤其高危：它 return 早，容易漏掉动画请求。
  骑乘中按载具速度播 Idle/Sprint（速度用座位跟随的位置差估计）。

### V7 RPC 方向标注铁律（承接 M26，违者Review打回）

| 方向 | 注解模式 | 函数体首行守卫 |
|------|---------|--------------|
| 服务器→客户端下发 | `@rpc("any_peer", "call_local", "reliable")` | `sender_id != 1 and not (sender_id == 0 and is_server()) → return` |
| 客户端→服务器请求 | `@rpc("any_peer", "call_local", "reliable")` + 调用处 `rpc_id(1)` | `not is_server() → return` + `sender == authority` 校验 |
| 沙发座位广播 | any_peer + 服务器守卫 | 只 `rpc_id` 真实骑手（pid<9001），禁全播 |

- `@rpc("authority")` **仅用于** authority 上行语义（如客户端上交世界物品），
  且 authority 必须真实在线。本轮 8 个"服务器下发"误标 authority 的
  修复（M26）是同类事故，不再允许。
- 沙发不是全局同步节点前，`_broadcast_seats` 的全播会刷
  "Node not found"（M26 已裁）；接入 spawner 后座位广播仍只发真实骑手。

### V8 Godot 4 网络 API 陷阱清单（本项目已全部踩过）

1. **`multiplayer.has_multiplayer_peer()` 恒为 true**——SceneTree 默认挂
   `OfflineMultiplayerPeer`。判"是否联机"的唯一正确写法：
   `peer == null or peer is OfflineMultiplayerPeer`。
   `is_server()` 在离线 peer 下返回 true（unique_id=1），不能单独用来
   判断"真的起了服"（起服失败时 bot 管理器仍会挂载）。
2. **ENet 走 UDP**。查端口占用必须 `netstat -p udp`；残留 join 客户端
   占着 UDP 8080 会让新 host 起不来（Error 20），且报错只进 push_warning。
3. **rpc 寻的 = 发送方节点路径**。从客户端本地节点发出的 rpc，
   服务器按同一路径找节点，找不到就静默失败/刷错。
   跨端交互必须从"双端都存在的节点"发出（玩家节点/服务器权威节点）。
4. **MultiplayerSynchronizer 属性路径**：`节点路径:属性名`，冒号只出现一次，
   多级节点用斜杠（`9001/GodotRobot3D:rotation`）。
5. **`get_meta()` 对缺失 key 必报引擎 ERROR**（null default 不豁免），
   一律 `has_meta()` 前置。
6. **`multiplayer.is_server()/get_unique_id()` 在无 peer 时报 ERROR**，
   需要 `has_multiplayer_peer()` 语义处改用 V8.1 的类型判据。
7. **迟加入者收不到历史 rpc**。任何"当时在线才广播"的状态，
   必须同时写入可持久读取的权威副本（V3 的 players 表），
   否则新客户端永远初始化不了。
8. **ENet 客户端 `connected_to_server` 与 unique_id 分配存在时序窗口**：
   `Network._on_connected_ok()` 不能假设即时 `get_unique_id()` 已是服务器
   分配的真实 id——必须轮询等待 `unique_id > 1`（最多 2s）再注册。
   若用默认值 1 注册，join 端把自己当 peer 1：本地玩家节点错占"1"槽位、
   所有 rpc 寻的服务器的"1"=host 角色（客户端在远程操控主机）、
   peer 2 在服务器从未注册（`_register_player` 的 `players.has(1)` 早退）。
   M27 事故 D 的深层根因，两轮双端联调被它伪装成"外观/骑乘 bug"。
9. **ENet 客户端 unique_id 是服务器分配的大随机数**（实测 922044945 这类），
   不是 2/3/4 连续号。一切"按 id 连续性"的假设（列表展示、诊断枚举、
   命名规则）都必须按任意正整数处理。

---

## 1-补. 交付前补充条款（M27 新增，与 V1~V8 同等强制）

### V10 节点创建必须幂等（两条创建路径竞态）

玩家节点有两条创建路径：MultiplayerSpawner 广播（服务器 add_child 触发）
和 `_add_player` 本地（Network 信号）。二者竞态顺序不定：
- spawner 先到：`_add_player` 发现节点已存在，**必须幂等补齐外观**
  （nick/skin/class），旧代码 early return 直接跳过初始化 =
  客户端远程玩家永远默认外观（事故 C 最后一环）。
- `_add_player` 先到：spawner 广播遇 `has_node` 冲突自行放弃
  （引擎报 ERR_INVALID_DATA，节点只存在一份，功能无损）。
- 补齐时 **fresh=false 不得覆盖已选职业**（远程节点可能已通过
  sync_class.rpc 选过）。

### V11 客户端不得本地回收同步实体

- 客户端侧的空车回收/超时销毁一律禁止——客户端沙发 seats 表收不到
  （sync_seats.rpc_id 只发真实骑手），按空表回收会毁掉正在骑乘中的沙发
  （实测 bot 沙发在客户端活不过 3 秒）。回收只认服务器
  `queue_free` → spawner despawn 广播。
- 同理：客户端的"兜底创建"一律禁止（V1）。

### V12 spawner 重复投递去重

沙发 authority 切换（sync_seats 的 set_multiplayer_authority）等事件会
触发 spawn 消息重发，引擎把第二个实例随机改名（couch_1436455457 这类）。
合法沙发名恒为 `couch_<peer_id>`——spawned 信号里按此模式去重，
非该模式一律 queue_free（保留先到者）。

### V13 bot/真人判定严禁用无上界数值段（M28 事故，用 PeerQuery）

- **严禁 `peer_id >= 9001 = bot`**——该假设源自 M25（ENet 客户端 id 还是
  2/3/4 小号时代）。M26 实测 ENet 客户端 unique_id 是服务器分配的大随机数
  （9 亿级），恒 >= 9001 → 所有真人客户端被误判成 bot。
- M28 实际事故：server_mount_peer 的 not_bot_only 检查把真人当 bot 拒绝
  上座（客户端按 X 召唤成功但永远骑不上）；同款雷还埋着：bot 座位钉位、
  sync_seats 广播目标（真人客户端收不到骑乘状态）、authority 切换、
  协作对/好感结算、怪物打草惊蛇——共 8 处，已全部统一改
  `PeerQuery.is_bot_peer()`（scripts/util/peer_query.gd）。
- 唯一可靠判据：bot id 段 = [9001, 9001+bot数-1]（与 BotController
  联动），真人 ENet id 撞进具体 4 个值的概率 ~10^-9，注释在案。
  **不要用 get_peers() 判**——客户端的 peers 视图只有服务器。
- 新增任何"bot 还是玩家"分支，一律 PeerQuery；Review 见 `>= 9001` 打回。

### V14 spawner 实体"先定位后入树"（spawn 快照只有一次机会）

- `add_child(node, true)` 瞬间引擎就序列化 spawn 快照（spawn=true 属性）
  发往各端——**入树之后才设置的位置不在快照里**。
- "召唤即骑"场景更致命：同一帧内 server_mount_peer → sync_seats →
  authority 切给骑手客户端 → 服务器的 position 广播**随即停止**——
  入树后设置的正确位置永远来不及送达。实测：客户端沙发 spawn 在
  (0,2.25,0)（instantiate 默认局部 0 + Environment 容器 y≈2.25 变换），
  玩家被拉回出生点骑"幽灵沙发"。
- **正确姿势**：先算好世界坐标 → `couch.position = container.to_local(world)`
  → 再 `add_child(node, true)`。入树后如需微调（复用路径），authority 仍
  在服务器时 always 广播可兜底；但**创建路径必须一步到位**。
- 同理 bot 沙发创建（bot_summon_and_mount）同款修复。

---

## 2. 架构现状图（修复后）

```
服务器（唯一权威）
├─ PlayersContainer（BotMultiplayerSpawner 广播）
│   ├─ "1" 主机玩家  authority=1
│   ├─ "<大随机id>" 客户端玩家 authority=<同 id>（ENet 分配，非 2/3/4！）
│   └─ "9001"~"9004" bot（BotMultiplayerSynchronizer 代播 position/rotation/player_class）
└─ Environment/Vehicles（VehicleMultiplayerSpawner 广播，M27 新增）
    ├─ couch_1 / couch_<peer_id> ...（按需创建，空车即毁，despawn 自动广播）
    └─ 每辆自带 MultiplayerSynchronizer（position/rotation 广播 + bot_only 变化广播）

外观权威副本：Network.players[id] = {nick, skin, class}（M27 补 class）
请求链路：客户端 X/E → rpc_id(1) → 服务器校验 sender==authority → server_* 直调
```

---

## 3. 交付前验证清单（骑乘/外观/同步类改动必查）

- [ ] 读代码确认：**没有任何客户端本地 instantiate 载具/世界实体**的路径
- [ ] 请求入口都有 `sender == authority`（或 sender==0）校验
- [ ] 服务器侧执行不用 `get_unique_id()` 当目标（显式传 peer id）
- [ ] `Network.players` 注册信息含 nick/skin/class 三字段，选职业有回写
- [ ] `set_player_skin()` 对每套身体视觉都有分支（新视觉=新分支）
- [ ] player.tscn SceneReplicationConfig 含 `.:rotation`
- [ ] mounted/飞行分支有 `_request_animation`
- [ ] `_add_player` 节点已存在时幂等补齐外观（V10），fresh 分支不覆盖已选职业
- [ ] 客户端无本地回收逻辑（V11）；spawner 有 spawned 去重（V12）
- [ ] `_on_connected_ok` 轮询等待 `unique_id > 1` 再注册（V8.8）
- [ ] 全代码无 `>= 9001` 式 bot 判定，一律 PeerQuery.is_bot_peer（V13）
- [ ] spawner 实体创建路径"先定位后入树"：add_child(true) 前 position
      已是最终局部坐标（V14）；创建后不再依赖 always 广播送达首帧位置
- [ ] 双端 `--auto host` + `--auto join` 实跑：SCRIPT ERROR=0、
      RPC 拒绝=0、两端数值打印一致（位置小数点后 6 位）
- [ ] 双端截图：客户端能看到对方坐骑本体、对方外观（模型+颜色）与
      主机本地一致、对方转身后朝向一致、攻击/骑乘有动作

## 4. 已知限制（记录在案，不在本轮范围）

- 客户端骑乘时坐的是"悬空沙发"——沙发模型已同步（M27），但沙发骑手
  座位绑定由玩家位置同步驱动，观感 OK；若未来要骑手在沙发上的
  局部姿态动画，需另立约定。
- 掉落物（ItemMultiplayerSpawner）同步后未做数值级取证（M27 顺带验证）。
- **late-join 启动窗口的 spawner 竞态 ERROR（引擎层，无脚本解）**：客户端
  加入瞬间，bot 沙发正处于"召唤→骑行→下客→回收"生命周期循环中（9002/9004
  在跑长途任务时最明显），late-join 的 spawn 历史重放与进行中的 despawn
  广播交叉到达——客户端先收到某沙发的 despawn 时，重放的 spawn 尚未处理完，
  `recv_nodes` 查无此 net_id → 引擎报 `ERR_UNAUTHORIZED`
  （on_despawn_receive）。实测特征：共 15 条、全部集中在 join 启动后
  数秒内（Godot 退出时才完整 flush，中途看会偏少）、之后 10 分钟运行
  零新增、SCRIPT ERROR=0、功能无损（节点只存在一份）。
  若未来要消除：只能在客户端维护 net_id 白名单或让服务器延后重放，
  均属引擎行为适配，收益低于复杂度，记录在案不修。
