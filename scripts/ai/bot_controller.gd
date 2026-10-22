extends Node
class_name BotController

## M20-Bot 管理器（服务器 only）：生成 bot 玩家并为每个 bot 挂 LimboAI 行为树。
##
## 架构（见设计文档 5.20）：
## - Bot = 虚拟 peer（id 9001 起）复用 level._add_player()，获得与真实玩家完全一致的
##   实例化路径（player.tscn / authority / Synchronizer / PlayersContainer）。
## - 行为树 = BTPlayer 子节点 + BehaviorTree 资源；首次启动代码组装并持久化为
##   resources/ai/bot_behavior_tree.tres，之后直接 load（用户可在编辑器可视化调整）。
## - 所有游戏行为（移动/攻击/任务/复活）全部复用玩家侧服务器权威接口，零新网络代码。
##
## 挂载时机：由 level.gd 在 start_host 成功后 / 客户端接入时调用 _ensure_bots() 创建本节点。

const BOT_ID_BASE := 9001
## M28：bot id 段上界（= BOT_ID_BASE + BOT_CONFIGS.size() - 1）。
## bot 判定一律走 PeerQuery.is_bot_peer（严禁无上界的 >= 9001——
## ENet 真人客户端 id 是大随机数，恒 >= 9001，会被误判成 bot）。
const BOT_ID_MAX := BOT_ID_BASE + 3 # 与 BOT_CONFIGS.size()-1 联动（4 个 bot → 9004）
const BOT_TREE_PATH := "res://resources/ai/bot_behavior_tree.tres"
const QUEST_GIVER_PATH := "/root/Level/Environment/QuestGiver"

## 任务脚本预加载（枚举/属性经预加载常量访问，不依赖全局类缓存扫描）
const CheckBotStateScript := preload("res://scripts/ai/tasks/bt_check_bot_state.gd")
const MoveToScript := preload("res://scripts/ai/tasks/bt_bot_move_to.gd")
const FindTargetScript := preload("res://scripts/ai/tasks/bt_bot_find_target.gd")
const AttackScript := preload("res://scripts/ai/tasks/bt_bot_attack.gd")
const QuestActionScript := preload("res://scripts/ai/tasks/bt_bot_quest_action.gd")
const RespawnScript := preload("res://scripts/ai/tasks/bt_bot_respawn.gd")

## Bot 配置（昵称 / 职业 / 外观肤色索引 / 性格）。与 Network.sanitize_* 同一字典格式。
## M24 性格：vengeful=恩怨分明 / easygoing=随和 / grudge=记仇 / loyal=忠诚，
## 数值表见 RelationshipManager.PERSONALITIES。
const BOT_CONFIGS: Array[Dictionary] = [
	{"nick": "铁颚", "class": "infantry", "skin": 0, "personality": "vengeful"},
	{"nick": "灰爪", "class": "mage", "skin": 1, "personality": "easygoing"},
	{"nick": "石心", "class": "infantry", "skin": 1, "personality": "grudge"},
	{"nick": "小暖", "class": "priest", "skin": 0, "personality": "loyal"},
]

## M25：bot 出生点 = 新手村内（任务官旁边、玩家复活点旁）。
## M33 修复（地形替换回归）：原先硬编码 BOT_SPAWN_POS z=74 是老底图村庄坐标，
## 村庄整体 z-200 搬迁后 bot 出生在 179m 外山坡（y≈13），直线趋近任务官要翻
## 60m 山崖 → 顶到 70m 高空悬停 + normalize 刷屏（full_run 实测）。
## 现改为动态跟随 level.get_respawn_point()——村庄/复活点今后无论搬到哪里，
## bot 自动同村出生，杜绝"漏搬出生点"类回归。
## 偏移量：复活点旁 (8~17, 4m)，横向散开防胶囊重叠（M20e）。
const BOT_SPAWN_OFFSET := Vector3(8.0, 0.0, 4.0)
## M48：bot 出生散开半径（米）。4 个 bot 按黄金角分布在**当地切平面**上，
## 两两间距 ≈ 1.2~2.0 × 半径 → 永不重叠。
## 旧的 `+ Vector3(i * 3.0, 0.0, 0.0)` 沿世界 X 轴排，而球面上世界 X 不是切向，
## 实测 4 个 bot 挤在 1.86~6.32m 内，视觉上叠成一团。
const BOT_SPAWN_RADIUS := 9.0
## 黄金角（= π(3 − √5)），连续点最均匀的螺旋角；与 level.get_spawn_point 同源。
const GOLDEN_ANGLE := 2.399963229728653

var _level: Node
var _spawned: bool = false


func _ready() -> void:
	if not multiplayer.is_server():
		return
	_level = get_parent()
	# 等一帧让 PlayersContainer / 各管理器就绪
	await get_tree().process_frame
	_spawn_bots()


func _spawn_bots() -> void:
	if _spawned or _level == null or not _level.has_method("_add_player"):
		return
	_spawned = true
	for i in BOT_CONFIGS.size():
		var bot_id := BOT_ID_BASE + i
		if _level.players_container.has_node(str(bot_id)):
			continue
		var bot: Node = _level._add_player(bot_id, BOT_CONFIGS[i])
		if bot == null:
			continue
		# M24：向好感度系统注册 bot 性格（"人性"原型入口）
		RelationshipManager.register_bot(bot_id, str(BOT_CONFIGS[i].get("personality", "easygoing")))
		if bot is CharacterBody3D:
			var bot_body := bot as CharacterBody3D
			# M20e：去掉对玩家层（层 1）的碰撞检测。
			# 事故：两个 bot 出生同一点（BOT_SPAWN_OFFSET 村内散开前），两个胶囊完全重叠，
			# move_and_slide 每帧执行 depenetration，双方互相螺旋推挤飞上天
			# （实测 +1.7m/帧 直飞 1000m+，v.y 恒 0 因为位移来自穿透恢复而非速度）。
			# 去掉层 1 检测后 bot 与 bot、bot 与真实玩家均无物理碰撞（WoW 玩家可互穿）。
			bot_body.collision_mask &= ~1
			# M24：再去掉层 3（怪物层）——事故：4 个 bot 集火时与目标怪物理互推，
			# 狼被推着满地跑，bot 永远进不了 3.2m 攻击圈（headless 实测 90s 零伤害）。
			# bot 攻击走服务器 request_attack 距离校验，无需物理接触。
			bot_body.collision_mask &= ~4
			# M48【球面出生点】旧代码两处地理错误，实测（tools/m48_body_probe.gd）：
			#   ① spawn_pos += Vector3(i*3, 0, 0) —— 世界 X 轴在球面上不是切向，
			#      4 个 bot 被挤到 1.86~6.32m 内挤成一团（看起来就是"重影"）；
			#   ② get_height(x, 0, z) 平面探针在球面彻底失效 → bot 悬空 2.4~7.8m。
			# 正解：复活点当地切平面上按黄金角散开 → 吸附球面 → 按模型底边落地。
			var base := BOT_SPAWN_OFFSET
			if _level.has_method("get_respawn_point"):
				base = _level.get_respawn_point()
			var up := Planet.up_at(base)
			var b := Planet.align_basis(up, Vector3.FORWARD)
			var ang := fmod(float(i) * GOLDEN_ANGLE, TAU)
			var spawn_pos := base \
				+ b.x * (cos(ang) * BOT_SPAWN_RADIUS) \
				+ b.z * (sin(ang) * BOT_SPAWN_RADIUS)
			spawn_pos = Planet.snap_to_surface(spawn_pos)
			bot_body.global_position = spawn_pos
			bot_body.velocity = Vector3.ZERO
			Planet.fit_ground(bot_body, 0.0)
		_attach_behavior_tree(bot)


## 挂 BTPlayer + 行为树到 bot 节点
func _attach_behavior_tree(bot: Node) -> void:
	if bot.has_node("BTPlayer"):
		return
	var tree := _load_or_build_tree()
	if tree == null:
		push_warning("M20-Bot: 行为树构建失败")
		return

	var bt_player := BTPlayer.new()
	bt_player.name = "BTPlayer"
	bt_player.behavior_tree = tree
	# 代码创建的节点 owner 为空，必须显式给场景根与 agent（见设计文档 6.3 坑①）
	bt_player.set_scene_root_hint(bot)
	bt_player.agent_node = NodePath("..")
	bot.add_child(bt_player)

	# 任务官引用写入黑板（供 MoveTo/TurnIn 分支用）
	var bb := bt_player.blackboard
	var giver := get_tree().current_scene.get_node_or_null(QUEST_GIVER_PATH)
	if giver != null:
		bb.set_var(&"quest_giver", giver)
	print("M20-Bot: %s 已挂载行为树" % bot.name)


## 首次组装并存盘；之后 load
func _load_or_build_tree() -> BehaviorTree:
	if ResourceLoader.exists(BOT_TREE_PATH):
		var loaded := load(BOT_TREE_PATH) as BehaviorTree
		if loaded != null:
			return loaded
	var tree := _build_tree()
	if tree == null:
		return null
	# 确保目录存在（首次保存时 resources/ai/ 可能尚未创建）
	var dir := DirAccess.open("res://resources")
	if dir != null and not dir.dir_exists("ai"):
		dir.make_dir_recursive("ai")
	var err := ResourceSaver.save(tree, BOT_TREE_PATH)
	if err != OK:
		push_warning("M20-Bot: 行为树保存失败 err=%d" % err)
	return tree


## 代码组装行为树（结构见设计文档 5.20 树形图）
func _build_tree() -> BehaviorTree:
	var root := BTSelector.new()

	# ── 分支1：死亡处理 ──
	var death_seq := BTSequence.new()
	death_seq.add_child(_make_check(CheckBotStateScript.Mode.DEAD))
	death_seq.add_child(_load_task(RespawnScript))
	root.add_child(death_seq)

	# ── 分支2：交付任务 ──
	var turnin_seq := BTSequence.new()
	turnin_seq.add_child(_make_check(CheckBotStateScript.Mode.QUEST_READY))
	turnin_seq.add_child(_make_move(&"quest_giver"))
	turnin_seq.add_child(_make_quest_action("turn_in"))
	root.add_child(turnin_seq)

	# ── 分支3：接取任务 ──
	var accept_seq := BTSequence.new()
	accept_seq.add_child(_make_check(CheckBotStateScript.Mode.QUEST_AVAILABLE))
	accept_seq.add_child(_make_move(&"quest_giver"))
	accept_seq.add_child(_make_quest_action("accept"))
	root.add_child(accept_seq)

	# ── 分支4：战斗循环 ──
	var combat_seq := BTSequence.new()
	combat_seq.add_child(_make_check(CheckBotStateScript.Mode.QUEST_ACTIVE))
	combat_seq.add_child(_load_task(FindTargetScript))
	combat_seq.add_child(_make_move(&"target_node"))
	combat_seq.add_child(_load_task(AttackScript))
	root.add_child(combat_seq)

	# ── 分支5：空闲待命 ──
	var idle_wait := BTWait.new()
	idle_wait.duration = 1.0
	root.add_child(idle_wait)

	var tree := BehaviorTree.new()
	tree.root_task = root
	tree.description = "M20-Bot 自动任务行为树：死亡→交付→接取→战斗→空闲"
	return tree


func _make_check(mode: int) -> BTTask:
	var t: Object = CheckBotStateScript.new()
	t.mode = mode
	return t


func _make_move(target_var: StringName) -> BTTask:
	var t: Object = MoveToScript.new()
	t.target_var = target_var
	return t


func _make_quest_action(action: String) -> BTTask:
	var t: Object = QuestActionScript.new()
	t.action = action
	return t


func _load_task(script: GDScript) -> BTTask:
	if script == null:
		push_warning("M20-Bot: 任务脚本为空")
		return null
	return script.new() as BTTask
