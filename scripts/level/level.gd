extends Node3D

const MAX_CHAT_MESSAGE_LENGTH := 160
const MIN_NICKNAME_HEIGHT := 2.0
const MAX_NICKNAME_HEIGHT := 8.0

# MiniWoW：村庄复活点（死亡后"释放灵魂"回到这里满血复活）。
# M25：搬回新手村底图（Kaykit 中央村落，z=70）——村区物理地面实测 y≈2.25
# （probe_ground 物理射线扫描），+0.55 悬停防卡地。
# 2026-10-21：地形换官方 demo 后，新手村搬到平地 region (-1,-1)（z≈-200 一带），
# 出生点随迁（原 z=70 在 demo 无数据区外，get_height 返回 NaN 会竖起 clipmap 黑墙）
const RESPAWN_POINT := Vector3(0.0, 2.8, -130.0)
# MiniWoW：与商人交易的距离（米）与按键提示
const MERCHANT_INTERACT_RANGE := 3.0
# MiniWoW：与卫兵队长（任务官）交互的距离
const QUEST_INTERACT_RANGE := 3.0
# MiniWoW：与职业训练师交互的距离
const CLASS_TRAINER_INTERACT_RANGE := 3.0

@export var player_scene: PackedScene

var chat_visible := false
var inventory_visible := false
var player_list_visible := false
var _tab_held := false
var shop_visible := false
var quest_visible := false
var class_select_visible := false
## M19-DM：NPC 对话（Dialogue Manager balloon）进行中标志
var dialogue_visible := false

var _player_nickname_heights: Dictionary = {}
var _nickname_heights_requested := false
var _nickname_height_requesters: Dictionary = {}

@onready var players_container: Node3D = $PlayersContainer
@onready var main_menu: MainMenuUI = $MainMenuUI
## M16c：主菜单期间隐藏游戏 HUD（玩家框/技能栏/按键提示不属于登录页）
@onready var hud: CanvasLayer = $HUD
@onready var multiplayer_chat: MultiplayerChatUI = $MultiplayerChatUI
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var player_list_ui: PlayerListUI = $PlayerListUI
@onready var pause_menu: PauseMenuUI = $PauseMenuUI
@onready var shop_ui: ShopUI = $ShopUI
@onready var quest_ui: QuestUI = $QuestUI
@onready var class_select_ui: ClassSelectUI = $ClassSelectUI
## M37：世界地图（M 键）
@onready var world_map_ui: WorldMapUI = $WorldMapUI


func _ready():
	# M45：先把整个场景从平面坐标搬到球面（必须在 spawn 玩家之前）
	_planet_relocate_scene()
	after_ready()
	# M43：天气系统改为场景节点（scenes/environment/weather_system.tscn，
	# 挂在 Environment/WeatherSystem），不再在这里 preload 实例化——
	# 旧 M40 的 storm_system 只支持"雨 + 闪电"一种天气，已整体重写。
	# 切换：F5 循环五档天气 / F6 回晴；代码用
	# $Environment/WeatherSystem.set_weather(WeatherSystem.Kind.SNOW)
	# M40：飞机模型整合（主城上空巡航装饰飞行器）
	var air_veh: Node = preload("res://scenes/vehicles/air_vehicle.tscn").instantiate()
	add_child(air_veh)

	if DisplayServer.get_name() == "headless":
		Network.start_host("", "")
		# M20-Bot：headless 服务器起服后挂载 bot 管理器
		_ensure_bots()
		# M19 基座适配：独立服务器不需要天空/太阳/月亮（纯表现层），
		# Sky3D 提供 sky3d_enabled 总开关，关闭后不初始化天体系统
		var sky3d := get_node_or_null("Environment/Sky3D")
		if sky3d:
			sky3d.sky3d_enabled = false
	else:
		_setup_sky3d()

	# M10：命令行自动连接（双开联调，见设计文档 5.5）
	# 必须走无条件路径——曾经嵌在 _setup_sky3d() 内，Sky3D/tod 未就绪时
	# 提前 return 会把联调通道一起吞掉（M26 事故：双端静默停主菜单）。
	_auto_connect_if_requested()

	# M24：NPC/怪物静态坐标贴地兜底（地形异步创建，内部自等就绪）
	_snap_ground_actors()

	# M37：一次性取证参数 --map_shot（启动后自动打开世界地图）
	_map_shot_open()
	# M37：一次性取证参数 --audio_shot（启动后自动打开暂停菜单看音量控件）
	if OS.get_cmdline_user_args().has("--audio_shot"):
		await get_tree().create_timer(3.5).timeout
		_show_pause_menu()


## M25d：出生贴地约定（docs/conventions-spawn-ground.md 条款 C1~C5）。
## tscn 里的静态 y 一律是估算占位：村底图 GridMap 只覆盖 z 52~92（高 2.25），
## z>92 的怪脚下没有 GridMap，从 y=2.25 自由落体到下方 Terrain3D 表面
## ——用户实测"小怪出生就掉到地面去了"。Terrain3D 异步建地形，就绪后把
## 村 NPC 与全部怪物统一贴地（GroundQuery 物理射线优先），并回写怪物
## home_position（AI 巡逻/重生/归位全部锚定它，只挪位置不回写会被拽回旧高度）。
func _snap_ground_actors() -> void:
	## M45：球面版——不再用 GroundQuery/Terrain3D 射线，直接按解析高度贴球面。
	## NPC 与全部怪物统一贴地，并回写 home_position（AI 巡逻/重生锚定它）。
	var env := get_node_or_null("Environment")
	if env == null:
		return
	var actors: Array = []
	for npc_name in ["Merchant", "QuestGiver", "ClassTrainer", "Villager"]:
		var npc := env.get_node_or_null(npc_name)
		if npc is Node3D:
			actors.append(npc)
	var monsters := env.get_node_or_null("Monsters")
	if monsters:
		for child in monsters.get_children():
			if child is Node3D:
				actors.append(child)
	for n in actors:
		var body := n as Node3D
		var p := body.global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			continue
		var up := Planet.up_at(p)
		var surf: Vector3 = up * (Planet.RADIUS + Planet.mesh_height(up))
		var t := body.global_transform
		t.basis = Planet.align_basis(up, t.basis * Vector3.FORWARD)
		t.origin = surf + up * 0.05
		body.global_transform = t
		body.set("home_position", t.origin)


## M45：把 Environment 下的平面刚体整体旋转到球面。
##   · 每个节点当作一个刚体：整体 basis 的 Y 轴对齐当地法线，内部保持平面
##     （村庄/竞技场尺度 200m，球面 R=2200 的曲率误差只有约 0.5m，肉眼无感）
##   · 节点原有的局部 y 偏移（怪物/NPC 的悬空占位）沿法线方向保留
## M46：外域用不到艾泽拉斯的成品几何（村庄/竞技场/气球/城市/传送门）。
## 这些节点的坐标是平面世界坐标，在球面上会和程序化地形穿插，直接整棵子树关掉。
## 保留 NPC 与怪物（换坐标照样能交互/打怪），否则外域是个空星球没法验收。
const OUTLAND_HIDE := [
	"Arena", "BalloonArena", "KaykitArena", "KaykitArena2", "KaykitArena3",
	"TrainingArea", "CityZone", "HomeStarter", "PortalVillage", "HomePortal",
	"SignPost", "ItemContainer", "Effects",
	# 注意：Vehicles / Effects 不能在这里！坐骑是通用功能，
	# 列进来会把整棵子树 visible=false，外域按 X 召唤出来的车完全看不见
	# （用户 2026-10-22「坐骑给我弄去哪里了」）。
]


func _disable_subtree(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).visible = false
	# visible=false 不关物理：竞技场/村庄的碰撞体还会挡人，必须清掉层掩码
	if n is CollisionObject3D:
		(n as CollisionObject3D).set_deferred("collision_layer", 0)
		(n as CollisionObject3D).set_deferred("collision_mask", 0)
	for c in n.get_children():
		_disable_subtree(c)


func _planet_relocate_scene() -> void:
	var env := get_node_or_null("Environment")
	if env == null:
		return
	var outland := Planet.world_id() == "outland"
	# 旧平面世界里的坐标 → 球面。Monsters 原在 z=-1650（旧狩猎区，已超出新大陆），
	# 单独搬到地表（艾泽拉斯：地狱火半岛 z≈-640 / 外域：出生区旁 z≈-220）。
	var overrides := {
		"Monsters": Vector3(0.0, 0.0, -220.0 if outland else -640.0),
	}
	if outland:
		for nm in OUTLAND_HIDE:
			var nd := env.get_node_or_null(nm)
			if nd != null:
				_disable_subtree(nd)
		printerr("[Planet] 外域：已隐藏 %d 个艾泽拉斯专属节点" % OUTLAND_HIDE.size())
	for child in env.get_children():
		var cn := String(child.name)
		# Vehicles 是运行期装车的**逻辑容器**，自身必须是 identity：
		# 一旦被当刚体重定位到球面某处，_summon_mount 的 to_local() 全错。
		if cn == "Vehicles":
			(child as Node3D).global_transform = Transform3D.IDENTITY
			continue
		if cn == "TerrainStarter" or cn == "ForestStarter" \
				or cn == "WeatherSystem" or cn == "Sky3D":
			continue
		if outland and cn in OUTLAND_HIDE:
			continue
		if not (child is Node3D):
			continue
		var node := child as Node3D
		var t := node.transform
		var px := t.origin.x
		var pz := t.origin.z
		var py := t.origin.y
		if overrides.has(node.name):
			var ov: Vector3 = overrides[node.name]
			px = ov.x
			pz = ov.z
			py = ov.y
		var yaw := node.rotation.y
		var nt := Planet.plane_transform(px, pz, yaw)
		nt.origin += nt.basis.y * py
		node.global_transform = nt
	printerr("[Planet] 场景已重定位到球面（%s）" % Planet.display_name())


## M19：Sky3D 天文参数配置（tools/probe_sky3d.tscn 实测验证）。
## 官方默认 utc=7/经度 108 是作者所在地（泰国），不配会算出黑夜——
## 必须按东八区 + 北京经纬度设置。日期取系统当天，时间固定 9:00
## （多人全端一致要求确定性；动态昼夜等服务器统一时钟再开）。
## 注意不能在 tscn 里配：Sky3D 的 alias setter 在 tod 子节点就绪前会丢值。
func _setup_sky3d() -> void:
	var sky3d := get_node_or_null("Environment/Sky3D")
	if sky3d == null or sky3d.tod == null:
		return
	var tod = sky3d.tod
	var now := Time.get_datetime_dict_from_system()
	# 全部直接写 tod 属性（Sky3D 的 alias setter 会丢值），锁定正午不随时间流动
	tod.game_time_enabled = false
	tod.editor_time_enabled = false
	tod.utc = 8.0                          # 东八区
	tod.longitude = deg_to_rad(116.4)      # 北京经度
	tod.latitude = deg_to_rad(39.9)        # 北京纬度
	tod.day = now.day
	tod.month = now.month
	tod.year = now.year
	tod.current_time = 12.0                # 固定正午（阳光最足）

	# M10 注意：命令行自动连接已移至 _ready() 无条件路径（M26 修复）。
	# 曾经嵌在这里：Sky3D/tod 未就绪提前 return 会把联调通道一起吞掉。

	pause_menu.hide_menu()
	main_menu.show_menu()
	_update_hud_for_menu()
	multiplayer_chat.set_process_input(true)
	# M11：UI 音效——全场景按钮点击音 + 主菜单悬停音（deferred 等 UI 全 ready）
	call_deferred("_hook_ui_sounds")
	_start_ambient_loop()

	main_menu.host_pressed.connect(_on_host_pressed)
	main_menu.join_pressed.connect(_on_join_pressed)
	main_menu.quit_pressed.connect(_on_quit_pressed)
	pause_menu.resume_pressed.connect(_on_pause_resume_pressed)
	pause_menu.main_menu_pressed.connect(_on_pause_main_menu_pressed)
	pause_menu.quit_pressed.connect(_on_pause_quit_pressed)

	if inventory_ui:
		inventory_ui.inventory_closed.connect(_on_inventory_closed)

	if shop_ui:
		shop_ui.shop_closed.connect(_on_shop_closed)

	if quest_ui:
		quest_ui.quest_closed.connect(_on_quest_closed)

	if class_select_ui:
		class_select_ui.class_select_closed.connect(_on_class_select_closed)

	if multiplayer_chat:
		multiplayer_chat.message_sent.connect(_on_chat_message_sent)

	Network.server_disconnected.connect(_on_server_disconnected)
	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	multiplayer.peer_disconnected.connect(_remove_player)
	# M19-DM：NPC 对话开始/结束——同步鼠标模式与输入冻结
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	_update_mouse_mode()
	# M16c 修复：鼠标捕获（MOUSE_MODE_CAPTURED）状态下窗口失焦后，Windows 上
	# 点击任务栏图标经常无法把窗口切回来。失焦时主动释放鼠标捕获，
	# 重新聚焦时按 UI 状态恢复捕获。
	var window := get_window()
	if window:
		window.focus_exited.connect(_on_window_focus_lost)
		window.focus_entered.connect(_on_window_focus_regained)


func _on_window_focus_lost() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_window_focus_regained() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# M29b：alt+tab 切回后窗口可能仍处于最小化/隐藏状态（focus_entered 不代表
	# 窗口已还原）。此时 _update_mouse_mode 会恢复 CAPTURED——鼠标被锁但窗口
	# 不可见，正是"进程在、窗口不显示、鼠标隐藏锁定"的故障。先强制还原窗口
	# 并置前，再恢复鼠标模式。
	var win := get_window()
	if win != null:
		var mode := DisplayServer.window_get_mode(win.get_window_id())
		if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, win.get_window_id())
		win.move_to_foreground()
	_update_mouse_mode()


## M29b：应用级焦点兜底——窗口 focus_exited/entered 信号在某些切换方式
## （alt+tab 快速切换、全屏应用抢焦点、UAC 弹窗）下不触发或乱序，
## 应用级 NOTIFICATION 是更可靠的恢复点。
func _notification(what: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# M31f 取证：偶发静默退出——区分窗口关闭消息与 UI quit
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		printerr("PROBE-QUIT: WM_CLOSE_REQUEST (窗口关闭消息)")
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_window_focus_regained()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_window_focus_lost()


func _process(_delta: float) -> void:
	var can_show_player_list := (
		not main_menu.is_menu_visible() and not pause_menu.is_menu_visible() and multiplayer.has_multiplayer_peer()
	)
	var tab_now := Input.is_key_pressed(KEY_TAB)
	if tab_now and not _tab_held and can_show_player_list:
		# M19：Tab 按住改切换式（Toggle）
		player_list_visible = not player_list_visible
		if player_list_visible:
			_show_player_list()
		else:
			_hide_player_list()
	_tab_held = tab_now

	_update_merchant_prompt()
	_update_quest_prompt()
	_update_class_trainer_prompt()
	_world_label_fade_t += _delta
	if _world_label_fade_t >= WORLD_LABEL_FADE_INTERVAL:
		_world_label_fade_t = 0.0
		_fade_world_labels()


## M26：世界文字（NPC/怪物名牌、提示、复活点招牌）近距离淡出。
## 根因（探针实测，tools/probe_bigtext）：Label3D 的 pixel_size 是世界高度系数，
## 透视下屏幕占比 ∝ 1/距离——pixel 0.02 的名牌 35m 处 64px，6m 处 373px（半屏糊）。
## 村庄布局出生相机与 QuestGiver 头顶名牌仅 6m，实测屏幕被"卫兵队长·卡尔"的
## 局部巨字糊满（截图取证）；RespawnSign(pixel 0.07) 在 10m 处 784px 全屏糊。
## WoW 惯例：贴脸名牌淡隐。规则：<NEAR 淡出到 MIN_ALPHA，NEAR~FAR 线性恢复，
## >FAR 全显。每 0.15s 批量一次（场景树遍历，含动态生成的伤害数字/bot 昵称）。
const WORLD_LABEL_FADE_NEAR := 5.0
const WORLD_LABEL_FADE_FAR := 12.0
const WORLD_LABEL_FADE_MIN_ALPHA := 0.10
const WORLD_LABEL_FADE_INTERVAL := 0.15
var _world_label_fade_t := 0.0

func _fade_world_labels() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position
	var labels: Array[Node] = []
	_collect_world_labels(self, labels)
	for n in labels:
		var l := n as Label3D
		if l == null or not l.is_inside_tree():
			continue
		var d := l.global_position.distance_to(cam_pos)
		var target := 1.0
		if d < WORLD_LABEL_FADE_NEAR:
			target = WORLD_LABEL_FADE_MIN_ALPHA
		elif d < WORLD_LABEL_FADE_FAR:
			var k := (d - WORLD_LABEL_FADE_NEAR) / (WORLD_LABEL_FADE_FAR - WORLD_LABEL_FADE_NEAR)
			target = lerpf(WORLD_LABEL_FADE_MIN_ALPHA, 1.0, k)
		l.modulate.a = target


func _collect_world_labels(n: Node, out: Array[Node]) -> void:
	if n is Label3D:
		out.append(n)
	for c in n.get_children():
		_collect_world_labels(c, out)


## M5：本地玩家靠近职业训练师时显示"按 E 交谈（选择职业）"提示
func _update_class_trainer_prompt() -> void:
	if class_select_ui == null:
		return
	if class_select_visible or not multiplayer.has_multiplayer_peer():
		class_select_ui.set_prompt_visible(false)
		return
	var local_player := _get_local_player()
	if local_player == null or not local_player.attribute_set.is_alive():
		class_select_ui.set_prompt_visible(false)
		return
	class_select_ui.set_prompt_visible(_is_near_class_trainer(local_player))


## M3：本地玩家靠近商人时显示"按 E 交易"提示
func _update_merchant_prompt() -> void:
	if shop_ui == null:
		return
	if shop_visible or not multiplayer.has_multiplayer_peer():
		shop_ui.set_prompt_visible(false)
		return
	var local_player := _get_local_player()
	if local_player == null or not local_player.attribute_set.is_alive():
		shop_ui.set_prompt_visible(false)
		return
	shop_ui.set_prompt_visible(_is_near_merchant(local_player))


## M4：本地玩家靠近卫兵队长时显示"按 E 交谈"提示
func _update_quest_prompt() -> void:
	if quest_ui == null:
		return
	if quest_visible or not multiplayer.has_multiplayer_peer():
		quest_ui.set_prompt_visible(false)
		return
	var local_player := _get_local_player()
	if local_player == null or not local_player.attribute_set.is_alive():
		quest_ui.set_prompt_visible(false)
		return
	quest_ui.set_prompt_visible(_is_near_quest_giver(local_player))


func _is_near_merchant(player_node: Node3D) -> bool:
	for merchant in get_tree().get_nodes_in_group("merchants"):
		if merchant is Node3D:
			if player_node.global_position.distance_to((merchant as Node3D).global_position) <= MERCHANT_INTERACT_RANGE:
				return true
	return false


func _is_near_quest_giver(player_node: Node3D) -> bool:
	for giver in get_tree().get_nodes_in_group("quest_givers"):
		if giver is Node3D:
			if player_node.global_position.distance_to((giver as Node3D).global_position) <= QUEST_INTERACT_RANGE:
				return true
	return false


func _is_near_class_trainer(player_node: Node3D) -> bool:
	for trainer in get_tree().get_nodes_in_group("class_trainers"):
		if trainer is Node3D:
			if player_node.global_position.distance_to((trainer as Node3D).global_position) <= CLASS_TRAINER_INTERACT_RANGE:
				return true
	return false


## M12：靠近村民（巴巴婶婶）——距离判定与任务官一致
func _get_nearby_villager(player_node: Node3D) -> Villager:
	for npc in get_tree().get_nodes_in_group("villagers"):
		var v := npc as Villager
		if v and player_node.global_position.distance_to(v.global_position) <= QUEST_INTERACT_RANGE:
			return v
	return null


func after_ready():
	_start_scale_watchdog()  # M25：体型污染看门狗（见函数注释）
	# M27 条款 V1：沙发 spawner 投递去重——spawn 重复投递（authority 切换重发 /
	# 连接竞态）会让引擎把第二个实例随机改名（实测 couch_1436455457 这类），
	# 合法沙发名恒为 couch_<peer_id>；非该模式的一律销毁，保留先到者
	# （spawn 消息按序投递，先到实例用原名）。
	var vehicle_spawner := get_node_or_null("VehicleMultiplayerSpawner")
	if vehicle_spawner and not vehicle_spawner.spawned.is_connected(_on_vehicle_spawned):
		vehicle_spawner.spawned.connect(_on_vehicle_spawned)
	var ip_address: String
	if OS.has_feature("windows"):
		if OS.has_environment("COMPUTERNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")), IP.TYPE_IPV4)
	elif OS.has_feature("x11"):
		if OS.has_environment("HOSTNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("HOSTNAME")), IP.TYPE_IPV4)
	elif OS.has_feature("OSX"):
		if OS.has_environment("HOSTNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("HOSTNAME")), IP.TYPE_IPV4)
	main_menu.address_input.text = ip_address


func _on_server_disconnected():
	_reset_session_ui()


## M27：合法沙发名 couch_<peer_id>（bot 9001+/真人 peer id）。
## RegEx.create_from_string 不是 const 表达式，用预编译 var（仅初始化一次）。
var _couch_name_pattern: RegEx = null


func _on_vehicle_spawned(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _couch_name_pattern == null:
		# M30：放行 couch_N（悬浮沙发）与 car_N（街机飞车）两类载具
		_couch_name_pattern = RegEx.create_from_string("^(couch|car)_\\d+$")
	if not _couch_name_pattern.search(str(node.name)):
		node.queue_free()
		return


func _reset_session_ui() -> void:
	for child in players_container.get_children():
		child.queue_free()

	var loot_root := get_node_or_null("Environment/ItemContainer")
	if loot_root:
		for child in loot_root.get_children():
			child.queue_free()

	chat_visible = false
	inventory_visible = false
	_hide_player_list()
	_player_nickname_heights.clear()
	_nickname_heights_requested = false
	_nickname_height_requesters.clear()
	multiplayer_chat.close_chat()
	multiplayer_chat.clear_chat()
	if inventory_ui:
		inventory_ui.close_inventory()
		inventory_ui.current_player = null
	if shop_ui:
		shop_ui.close_shop()
		shop_visible = false
	if quest_ui:
		quest_ui.close_quest_log()
		quest_visible = false
	if class_select_ui:
		class_select_ui.close_panel()
		class_select_visible = false
	# M37：回主菜单时地图也要关掉（否则地图盖在登录页上）
	if world_map_ui and world_map_ui.is_map_visible():
		world_map_ui.close_map()
	_hide_pause_menu(false)
	main_menu.show_menu()
	_update_hud_for_menu()
	_update_mouse_mode()


func _on_player_connected(peer_id, player_info):
	var player = _add_player(peer_id, player_info)
	if multiplayer.is_server() and player:
		player.call_deferred("_sync_inventory_to_owner")
	if multiplayer.is_server():
		if peer_id != 1:
			call_deferred("_sync_nickname_heights_to_peer", peer_id)
		# M30：late-join 补发已破坏建筑（保持城区破坏状态一致）
		var city := get_node_or_null("Environment/CityZone")
		if city != null and city.has_method("sync_destroyed_to"):
			city.call_deferred("sync_destroyed_to", peer_id)
	elif not _nickname_heights_requested:
		_nickname_heights_requested = true
		call_deferred("_request_nickname_heights")
	_refresh_player_list()


## M10：命令行自动连接（仅本机联调）。`--auto host` 直接当主机；`--auto join`
## 延迟 1 秒加入本机（等 host 先起服）。不带参数时行为完全不变（主菜单手动点）。
func _auto_connect_if_requested() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := ""
	for i in range(args.size()):
		if args[i] == "--auto" and i + 1 < args.size():
			mode = args[i + 1]
	match mode:
		"host":
			# Godot 4 坑：SceneTree 默认挂 OfflineMultiplayerPeer（供单机 RPC），
			# has_multiplayer_peer() 恒为 true——曾用 not has_multiplayer_peer()
			# 判"未联机"，导致 --auto host 永远被跳过（M26 双端联调瘫痪事故：
			# 两端静默停主菜单，host 从未起服，join 客户端还占住 UDP 8080）。
			# 正确判据：peer 为 OfflineMultiplayerPeer / null 即未联机。
			var peer := multiplayer.get_multiplayer_peer()
			if peer == null or peer is OfflineMultiplayerPeer:
				# M27 条款 V3：皮肤跟随主菜单当前选项——旧版硬编码 "blue"/"yellow"，
				# 联调通道验不到皮肤同步链路（用户手动开房能选色，auto 不能）。
				var skin := "blue"
				if main_menu and main_menu.has_method("get_skin"):
					skin = main_menu.get_skin()
				_on_host_pressed("Host", skin)
		"join":
			await get_tree().create_timer(1.0).timeout
			var join_skin := "yellow"
			if main_menu and main_menu.has_method("get_skin"):
				join_skin = main_menu.get_skin()
			_on_join_pressed("Client", join_skin, Network.SERVER_ADDRESS)


func _on_host_pressed(nickname: String, skin: String):
	var error = Network.start_host(nickname, skin)
	if error:
		push_warning("Failed to host game. Error: " + str(error))
		main_menu.show_menu()
		_update_hud_for_menu()
		_update_mouse_mode()
		return
	main_menu.hide_menu()
	_update_hud_for_menu()
	_update_mouse_mode()
	# M20-Bot：主机开局成功 → 挂载 bot 管理器（幂等）
	_ensure_bots()


func _on_join_pressed(nickname: String, skin: String, address: String):
	var error = Network.join_game(nickname, skin, address)
	if error:
		push_warning("Failed to join game. Error: " + str(error))
		main_menu.show_menu()
		_update_hud_for_menu()
		_update_mouse_mode()
		return
	main_menu.hide_menu()
	_update_hud_for_menu()
	_update_mouse_mode()


## M20-Bot：服务器挂载 BotController（幂等，start_host 成功/客户端接入时调用）
func _ensure_bots() -> void:
	# M26：Godot 4 默认 OfflineMultiplayerPeer 使 has_multiplayer_peer() 恒真，
	# 真正的判据是 is_server()（离线 peer 下为 false，自动拦截单机误挂）。
	if not multiplayer.is_server():
		return
	if get_node_or_null("BotController") != null:
		return
	var ctrl := BotController.new()
	ctrl.name = "BotController"
	add_child(ctrl)


## M16c：HUD 跟随主菜单显隐——登录页只显示登录内容，不叠游戏 HUD
## M37：地图打开时也隐藏 HUD（技能栏/按键提示会压住地图底部）
func _update_hud_for_menu() -> void:
	if hud:
		hud.visible = not main_menu.is_menu_visible() and not world_map_ui.is_map_visible()


func _add_player(id: int, player_info: Dictionary) -> Character:
	if DisplayServer.get_name() == "headless" and id == 1:
		return null

	var player: Character = null
	if players_container.has_node(str(id)):
		# M27 条款 V3 修复（事故 C 最后一环）：节点可能已被 MultiplayerSpawner
		# 的 late-join 重放/广播先行创建——旧代码直接 early return，
		# nick/skin/class 初始化全部跳过，客户端远程玩家永远是默认外观
		# （class 空 → GodotRobot，即"客户机看到红色机器人"）。
		# 两条创建路径（spawner 广播 / _add_player 本地）必须殊途同归：
		# 已存在也要幂等补齐外观，且**已选过职业则不覆盖**。
		player = players_container.get_node(str(id)) as Character
		_apply_player_appearance(player, player_info, false)
		return player

	player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point(id)
	printerr("[SPAWN] id=%d 设 position=%s r=%.1f" % [id, str(player.position), player.position.length()])
	players_container.add_child(player, true)
	printerr("[SPAWN] id=%d 入树后 global=%s r=%.1f authority=%s physics=%s" % [
		id, str(player.global_position), player.global_position.length(),
		str(player.is_multiplayer_authority()), str(player.is_physics_processing())])

	# M25c：出生不发车（docs/conventions-mount-lifecycle.md 条款 M1）——
	# 所有角色（真人/bot）出生都没有飞行器，按 X / AI 自动召唤时才生成，
	# 且召唤即自动骑乘。原"每位玩家自动领取专属沙发"导致满地无人坐骑。

	_apply_player_appearance(player, player_info, true)
	_apply_player_nickname_height(id)
	if id == multiplayer.get_unique_id():
		var hud := get_node_or_null("HUD") as HUD
		if hud:
			hud.bind_player(player)
		# M5：首次进入游戏且未选职业 → 弹出职业选择（延迟一帧等玩家就绪）
		# M18b-1 修复：M14 的"开局默认战士"会把 is_empty 填上、弹窗永远不出现——
		# 被自动默认（meta 标记）的玩家也要弹，否则选不了步兵/法师/牧师。
		if player.player_class.is_empty() or player.has_meta("auto_defaulted_class"):
			call_deferred("_open_class_select", player)
	# M19：进世界常驻显示在线人数与列表（Tab 可收起/展开）
	if int(id) == multiplayer.get_unique_id():
		player_list_visible = true
		call_deferred("_show_player_list")
	return player


## M27 条款 V3：外观三件套（nick/skin/class）从 Network.players 权威副本初始化。
## 幂等：节点已存在（spawner 竞态胜出）时也调用；fresh=false 表示补齐场景，
## 此时**不覆盖已选职业**（远程节点可能已通过 sync_class.rpc 选过）。
func _apply_player_appearance(
	player: Character, player_info: Dictionary, fresh: bool
) -> void:
	if player == null:
		return
	var nick = Network.sanitize_nickname(str(player_info.get("nick", "")), "Player_" + str(player.name))
	if player.get_node_or_null("PlayerNick/Nickname") != null:
		player.nickname.text = nick

	var skin_enum = Network.sanitize_skin_value(player_info.get("skin", Character.SkinColor.BLUE))
	player.set_player_skin(skin_enum)
	# M27 条款 V3：class 非空且（新节点 或 该节点还没选过职业）时才本地直设。
	# _add_player 双端都跑、信息一致，不走 rpc 回环；已选职业不覆盖
	# （覆盖会把客户端抢先选好的职业打回空）。
	var class_id := str(player_info.get("class", ""))
	if not class_id.is_empty() and ClassDatabase.get_class_data(class_id) != null:
		if fresh or str(player.get("player_class")).is_empty():
			player.player_class = class_id
			player._apply_class_base_stats()
			player._update_body_visual()


## 出生点缓存：get_spawn_point 每加一个玩家都会调用，别每次都重扫 240m
var _respawn_cache := Vector3.INF


func get_respawn_point() -> Vector3:
	# 【M47】出生点必须是"平地 + 视野开阔"。
	# 旧版写死在面 0 的 (0,-130)，实测外域那里是冲沟谷底 —— 玩家一睁眼是
	# 两堵三十米土墙夹着天（用户说的"恐怖游戏"）。只按"最平"选点也不够：
	# 最平的点常常是坡脚，一样面壁。所以双标准：坡度要小，且要比周围高。
	if _respawn_cache != Vector3.INF and not _respawn_cache.is_equal_approx(Vector3.ZERO):
		return _respawn_cache
	var best := Vector2(0.0, -130.0)
	var best_score := 1e9
	var r := 0.0
	while r <= 240.0:
		for k in 20:
			var a := TAU * float(k) / 20.0
			var px: float = cos(a) * r
			var pz: float = -130.0 + sin(a) * r
			var d := Planet.dir_from_plane(px, pz)
			var h := Planet.mesh_height(d)
			# 低于水面/虚空的点直接排除
			if h < Planet.SEA_LEVEL + 8.0:
				continue
			var g := _grade_at(px, pz)
			if g > 0.13:
				continue
			# 坡度占主，高度占辅（站高一点视野好，不会面壁）
			var score: float = g * 30.0 - h * 0.012
			if score < best_score:
				best_score = score
				best = Vector2(px, pz)
		r += 20.0
	var bd := Planet.dir_from_plane(best.x, best.y)
	_respawn_cache = bd * (Planet.RADIUS + Planet.mesh_height(bd)) + bd * 2.2
	printerr("[Spawn] 落点 (%.0f, %.0f) 高 %.0f 评分 %.3f" % [
		best.x, best.y, Planet.mesh_height(bd), best_score])
	return _respawn_cache


## 平面坐标处的坡度近似（6 米步长的高度差 / 步长），越小越平
func _grade_at(px: float, pz: float) -> float:
	var h0 := Planet.mesh_height(Planet.dir_from_plane(px, pz))
	var e := 6.0
	var hx := Planet.mesh_height(Planet.dir_from_plane(px + e, pz))
	var hz := Planet.mesh_height(Planet.dir_from_plane(px, pz + e))
	return maxf(absf(hx - h0), absf(hz - h0)) / e


## M25：体型看门狗——项目没有任何"变大"机制，但实测出现过巨型 bot。
## 服务器每 2 秒扫一遍玩家/bot/怪：scale≠1 立即归位并打日志留证据。
## 已排除：代码无 scale 赋值、动画无 scale 轨道、升级成长只改属性——
## 污染源未明，看门狗先兜底，触发日志可定位是"谁、多大、何时"。
func _start_scale_watchdog() -> void:
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_scale_watchdog_tick)
	add_child(timer)


func _scale_watchdog_tick() -> void:
	# M26：is_server() 在无 peer（主菜单阶段）会向引擎报 ERROR——
	# Timer 2s 一跳，登录页白刷。必须先确认已连接。
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for container_path in ["PlayersContainer", "Environment/Monsters"]:
		var container := get_node_or_null(container_path)
		if container == null:
			continue
		for child in container.get_children():
			var n3 := child as Node3D
			# M25e：is_equal_approx 替代 == —— tween 插值残留（0.9999999）会让
			# == 判断偶发失败，误归位并刷屏（实测玩家 scale 打印 1.0 仍被归位）
			if n3 == null or n3.scale.is_equal_approx(Vector3.ONE):
				continue
			# M25e：死亡压扁窗口豁免——怪物 DEAD 期间 scale.y→0.1 是死亡表演
			# （monster.gd _update_alive_visual），respawn 时自动 ELASTIC 弹回 ONE。
			# 看门狗归位会一巴掌拍碎表演（实测抓到 (1.0, 0.1, 1.0)）。
			if child.get("monster_id") != null and int(child.get("state")) == int(Monster.State.DEAD):
				continue
			# M25f：死亡/复活动画窗口豁免（tween 时间戳，比 state 判据更稳——
			# 压扁先于 DEAD 置位、ELASTIC 回弹发生在 IDLE 态）
			if child.has_meta("_death_anim_until_msec") \
					and Time.get_ticks_msec() < int(child.get_meta("_death_anim_until_msec")):
				continue
			# M25e：受击抖动窗口豁免——shake 峰值锁死 1.15 且必回 1（damage_number.gd），
			# 2 秒一扫偶尔瞥见 1.0~1.12 的中间帧属合法表演，归位反打断抖动。
			if child.has_meta("_shake_until_msec") and Time.get_ticks_msec() < int(child.get_meta("_shake_until_msec")):
				continue
			printerr("SCALE_WATCHDOG: %s(name=%s nick=%s) scale=%s → 归位" % [
				container_path, child.name, str(child.get("nickname")), n3.scale])
			n3.scale = Vector3.ONE


func get_spawn_point(id: int) -> Vector3:
	# M45：在出生点的切平面上呈黄金角散开，再吸附回球面
	var base := get_respawn_point()
	var up := Planet.up_at(base)
	var b := Planet.align_basis(up, Vector3.FORWARD)
	var ang := fmod(float(id) * 2.399963229728653, 2.0 * PI)
	var off := b.x * cos(ang) * 10.0 + b.z * sin(ang) * 10.0
	var pos := base + off
	return Planet.snap_to_surface(pos + up * 0.5)


func _remove_player(id):
	_player_nickname_heights.erase(id)
	if not players_container.has_node(str(id)):
		call_deferred("_refresh_player_list")
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()
	# M25c 条款 M4：骑手退出必须摘座——玩家可能在骑乘中断线，
	# 不摘座的话沙发带着已消失的 peer 永远"有人骑"（违反 M3 无人骑不显示）
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v != null and v.has_method("server_remove_peer"):
			v.server_remove_peer(int(id))
	call_deferred("_refresh_player_list")


func _on_quit_pressed() -> void:
	printerr("PROBE-QUIT: _on_quit_pressed (UI 退出按钮)")
	Network.leave_game()
	get_tree().quit()


func toggle_chat():
	if main_menu.is_menu_visible() or is_gameplay_input_blocked():
		return

	multiplayer_chat.toggle_chat()
	chat_visible = multiplayer_chat.is_chat_visible()
	_update_mouse_mode()


func is_chat_visible() -> bool:
	return multiplayer_chat.is_chat_visible()


## M46：F8 切换星球（艾泽拉斯 ⇄ 外域）。
## 星球参数（半径 / 海平面 / 地形函数 / 配色 / 天空）全部在 PlanetProfile 里，
## 且必须在 TerrainStarter._ready 之前确定 → 没法热替换，只能落盘 + 重载场景。
## 另外 GDScript 的 static var 活到进程结束，reload_current_scene 不会重置，
## 所以必须显式 reset_world() 清缓存，否则重载后还是旧星球。
func _toggle_planet() -> void:
	var cur := Planet.world_id()
	var nxt := "outland" if cur == "azeroth" else "azeroth"
	Planet.save_planet_choice(nxt)
	Planet.reset_world()
	printerr("[Planet] 切换星球 %s → %s，重载场景…" % [cur, nxt])
	get_tree().reload_current_scene()


func _input(event):
	if event.is_action_pressed("pause"):
		_handle_pause_action()
		get_viewport().set_input_as_handled()
		return

	# M37：地图开关必须放在 gameplay 阻断检查之前——地图开着时
	# is_gameplay_input_blocked() 为 true，放后面就再也关不掉地图了。
	if event.is_action_pressed("toggle_map"):
		_toggle_world_map()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_toggle_world_map()
		get_viewport().set_input_as_handled()
		return

	# M46：F8 切换星球（艾泽拉斯 ⇄ 外域）。写盘后重载场景——
	# 星球参数必须在任何地形生成之前确定，没法热切换。
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		_toggle_planet()
		get_viewport().set_input_as_handled()
		return

	# M47：F9 切换光照方案（真实太阳 ⇄ 全球白天），热切换不用重载
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		var m := Planet.toggle_light_mode()
		printerr("[光照] 已切换为 %s" % Planet.light_mode_name(m))
		get_viewport().set_input_as_handled()
		return

	if is_gameplay_input_blocked():
		return

	if event.is_action_pressed("toggle_chat"):
		toggle_chat()
	elif chat_visible and multiplayer_chat.message.has_focus():
		pass
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug_add_item()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_debug_print_inventory()


func _on_chat_message_sent(message_text: String) -> void:
	chat_visible = multiplayer_chat.is_chat_visible()
	_update_mouse_mode()

	var trimmed_message = _sanitize_chat_message(message_text)
	if trimmed_message.is_empty():
		return

	if multiplayer.is_server():
		_broadcast_chat_message(multiplayer.get_unique_id(), trimmed_message)
	else:
		submit_chat_message.rpc_id(1, trimmed_message)


@rpc("any_peer", "reliable")
func submit_chat_message(message_text: String):
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var trimmed_message = _sanitize_chat_message(message_text)
	if trimmed_message.is_empty():
		return
	_broadcast_chat_message(sender_id, trimmed_message)


func _broadcast_chat_message(sender_id: int, message_text: String):
	var player_info = Network.players.get(sender_id, {})
	var nick = Network.sanitize_nickname(str(player_info.get("nick", "")), "Player_" + str(sender_id))
	show_chat_message.rpc(nick, message_text)


@rpc("authority", "call_local", "reliable")
## M11：sfx_key 可选——非空时各端随播报触发提示音（纯表现，各端独立播放）
func show_chat_message(nick: String, msg: String, sfx_key: StringName = &""):
	multiplayer_chat.add_message(nick, msg)
	if sfx_key != &"":
		SfxManager.play(sfx_key)


func _sanitize_chat_message(message_text: String) -> String:
	var clean = message_text.strip_edges()
	if clean.length() > MAX_CHAT_MESSAGE_LENGTH:
		clean = clean.substr(0, MAX_CHAT_MESSAGE_LENGTH)
	return clean


func toggle_inventory():
	if main_menu.is_menu_visible() or is_gameplay_input_blocked():
		return

	var local_player = _get_local_player()
	if not local_player:
		return

	inventory_visible = !inventory_visible
	if inventory_visible:
		inventory_ui.open_inventory(local_player)
		SfxManager.play(&"ui_inventory")
	else:
		inventory_ui.close_inventory()
		SfxManager.play(&"ui_close")
	_update_mouse_mode()


func is_inventory_visible() -> bool:
	return inventory_visible


## M11：UI 按钮音效挂钩（主菜单悬停音 + 全场景点击音）
func _hook_ui_sounds() -> void:
	SfxManager.hook_hover(main_menu)
	SfxManager.hook_buttons(self)


## M11：草原环境循环音（本地播放，无需网络同步；-12dB 压底不抢戏）
func _start_ambient_loop() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := load("res://assets/sfx/environment/grassy_field.wav") as AudioStream
	if stream == null:
		return
	var ambient := AudioStreamPlayer.new()
	ambient.name = "AmbientSfx"
	ambient.stream = stream
	# M37：环境循环音走 Ambient 子总线（与音效分开调）
	ambient.bus = &"Ambient"
	ambient.volume_db = -12.0
	add_child(ambient)
	# wav 导入默认不循环，用 finished 信号手动续播
	ambient.finished.connect(ambient.play)
	ambient.play()


## M3/M4/M5：E 键交互——就近优先：先卫兵队长（任务），再职业训练师，最后商人（交易）
func _try_interact() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var local_player := _get_local_player()
	if local_player == null or not local_player.attribute_set.is_alive():
		return
	if not quest_visible and _is_near_quest_giver(local_player):
		_open_quest_log(local_player)
		return
	if not class_select_visible and _is_near_class_trainer(local_player):
		_open_class_select(local_player)
		return
	if not shop_visible:
		_try_interact_with_merchant()
	# M12：村民最低优先级——前面都没命中且靠近村民时，挥手交谈（无面板）
	if not quest_visible and not class_select_visible and not shop_visible and not dialogue_visible:
		var villager := _get_nearby_villager(local_player)
		if villager:
			# M19-DM：E 键弹出 Dialogue Manager 对话（替代纯挥手）
			villager.start_dialogue()
			return


## M3：E 键交互——靠近商人则打开商店
func _try_interact_with_merchant() -> void:
	if not multiplayer.has_multiplayer_peer() or shop_visible:
		return
	var local_player := _get_local_player()
	if local_player == null or not local_player.attribute_set.is_alive():
		return
	if not _is_near_merchant(local_player):
		return
	_open_shop(local_player)


func _open_shop(player: Character) -> void:
	shop_visible = true
	shop_ui.open_shop(player)
	_update_mouse_mode()


func _on_shop_closed() -> void:
	shop_visible = false
	_update_mouse_mode()


func is_shop_visible() -> bool:
	return shop_visible


## M4：E 键交互——靠近卫兵队长则打开任务面板
func _open_quest_log(player: Character) -> void:
	quest_visible = true
	quest_ui.open_quest_log(player)
	_update_mouse_mode()


func _on_quest_closed() -> void:
	quest_visible = false
	_update_mouse_mode()


func is_quest_visible() -> bool:
	return quest_visible


## M5：E 键交互——靠近职业训练师（或首次进入）则打开职业选择
func _open_class_select(player: Character) -> void:
	if class_select_ui == null:
		return
	# 联调模式（--auto host/join）自动跳过职业选择，便于自动化验证直接进世界
	var args := OS.get_cmdline_user_args()
	var auto_mode := false
	for i in range(args.size()):
		if args[i] == "--auto" and i + 1 < args.size():
			auto_mode = true
	if auto_mode:
		class_select_visible = false
		return
	class_select_visible = true
	class_select_ui.open(player)
	_update_mouse_mode()


func _on_class_select_closed() -> void:
	class_select_visible = false
	_update_mouse_mode()


func is_class_select_visible() -> bool:
	return class_select_visible


func _show_player_list() -> void:
	if main_menu.is_menu_visible() or pause_menu.is_menu_visible() or not multiplayer.has_multiplayer_peer():
		return
	player_list_visible = true
	player_list_ui.show_players(Network.players, multiplayer.get_unique_id())


func _hide_player_list() -> void:
	player_list_visible = false
	if player_list_ui:
		player_list_ui.hide_players()


func _refresh_player_list() -> void:
	if player_list_visible and player_list_ui:
		player_list_ui.refresh_players(Network.players, multiplayer.get_unique_id())


func register_player_nickname_height(player_id: int, height: float) -> void:
	if not multiplayer.is_server() or player_id <= 0:
		return
	var normalized_height := _normalize_nickname_height(height)
	_store_and_apply_player_nickname_height(player_id, normalized_height)
	sync_player_nickname_height.rpc(player_id, normalized_height)


@rpc("authority", "reliable")
func sync_player_nickname_height(player_id: int, height: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_store_and_apply_player_nickname_height(player_id, _normalize_nickname_height(height))


func _request_nickname_heights() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	request_nickname_heights.rpc_id(1)


@rpc("any_peer", "reliable")
func request_nickname_heights() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0 or _nickname_height_requesters.has(requester_id):
		return
	_nickname_height_requesters[requester_id] = true
	_sync_nickname_heights_to_peer(requester_id)


func _sync_nickname_heights_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	for child in players_container.get_children():
		var player := child as Character
		if not player:
			continue
		var player_id := str(player.name).to_int()
		var height := float(_player_nickname_heights.get(player_id, player.get_current_nickname_height()))
		sync_player_nickname_height.rpc_id(peer_id, player_id, _normalize_nickname_height(height))


func _store_and_apply_player_nickname_height(player_id: int, height: float) -> void:
	if player_id <= 0:
		return
	_player_nickname_heights[player_id] = height
	_apply_player_nickname_height(player_id)


func _apply_player_nickname_height(player_id: int) -> void:
	if not _player_nickname_heights.has(player_id):
		return
	var player := players_container.get_node_or_null(str(player_id)) as Character
	if player:
		player.apply_synced_nickname_height(float(_player_nickname_heights[player_id]))


func _normalize_nickname_height(height: float) -> float:
	if is_nan(height) or is_inf(height):
		return MIN_NICKNAME_HEIGHT
	return clampf(height, MIN_NICKNAME_HEIGHT, MAX_NICKNAME_HEIGHT)


func _on_inventory_closed():
	inventory_visible = false
	_update_mouse_mode()


func is_gameplay_input_blocked() -> bool:
	return pause_menu.is_menu_visible() or shop_visible or quest_visible or class_select_visible or dialogue_visible or world_map_ui.is_map_visible()


## M37：M 键开关世界地图
func _toggle_world_map() -> void:
	if world_map_ui.is_map_visible():
		world_map_ui.close_map()
	else:
		# 地图打开时屏蔽其它面板输入（先关掉会打架的面板）
		if pause_menu.is_menu_visible():
			_hide_pause_menu()
		world_map_ui.open_map(self)
	_update_mouse_mode()
	_update_hud_for_menu()


## M37：一次性取证参数 --map_shot —— 启动后自动打开地图（验证渲染效果）
func _map_shot_open() -> void:
	if not OS.get_cmdline_user_args().has("--map_shot"):
		return
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(3.0).timeout
	_toggle_world_map()


func is_camera_input_blocked() -> bool:
	return is_gameplay_input_blocked() or inventory_visible or multiplayer_chat.is_chat_visible()

## M19-DM：NPC 对话开始——冻结游戏输入、释放鼠标（balloon 选项需要点击）
func _on_dialogue_started(_resource) -> void:
	dialogue_visible = true
	_update_mouse_mode()


## M19-DM：NPC 对话结束——恢复鼠标捕获与游戏输入
func _on_dialogue_ended(_resource) -> void:
	dialogue_visible = false
	_update_mouse_mode()


func _handle_pause_action() -> void:
	if inventory_visible:
		_close_inventory()
		return
	if shop_visible:
		shop_ui.close_shop()
		shop_visible = false
		_update_mouse_mode()
		return
	if quest_visible:
		quest_ui.close_quest_log()
		quest_visible = false
		_update_mouse_mode()
		return
	if class_select_visible:
		class_select_ui.close_panel()
		class_select_visible = false
		_update_mouse_mode()
		return
	if multiplayer_chat.is_chat_visible():
		_close_chat()
		return
	if world_map_ui.is_map_visible():
		world_map_ui.close_map()
		_update_mouse_mode()
		_update_hud_for_menu()
		return
	if pause_menu.is_menu_visible():
		_hide_pause_menu()
		return
	if main_menu.is_menu_visible() or not multiplayer.has_multiplayer_peer():
		return
	_show_pause_menu()


func _show_pause_menu() -> void:
	pause_menu.show_menu()
	_update_mouse_mode()


func _hide_pause_menu(restore_mouse_mode: bool = true) -> void:
	if not pause_menu.is_menu_visible():
		return
	pause_menu.hide_menu()
	if restore_mouse_mode:
		_update_mouse_mode()


func _close_chat() -> void:
	multiplayer_chat.close_chat()
	chat_visible = false
	_update_mouse_mode()


func _close_inventory() -> void:
	inventory_ui.close_inventory()
	inventory_visible = false
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var ui_requires_cursor := (
		main_menu.is_menu_visible()
		or pause_menu.is_menu_visible()
		or inventory_visible
		or shop_visible
		or quest_visible
		or class_select_visible
		or dialogue_visible
		or not multiplayer.has_multiplayer_peer()
	)
	if ui_requires_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_pause_resume_pressed() -> void:
	_hide_pause_menu()


func _on_pause_main_menu_pressed() -> void:
	_hide_pause_menu(false)
	Network.leave_game()
	if not main_menu.is_menu_visible():
		_reset_session_ui()


func _on_pause_quit_pressed() -> void:
	printerr("PROBE-QUIT: _on_pause_quit_pressed (暂停菜单退出)")
	Network.leave_game()
	get_tree().quit()


func update_local_inventory_display():
	if inventory_ui:
		inventory_ui.refresh_display()
	# M3：商店开着时同步刷新商品可购买状态与出售列表
	if shop_ui and shop_visible:
		shop_ui.refresh()


func _get_local_player() -> Character:
	var local_player_id = multiplayer.get_unique_id()
	if players_container.has_node(str(local_player_id)):
		return players_container.get_node(str(local_player_id)) as Character
	return null


func _debug_add_item():
	if not OS.is_debug_build() or not multiplayer.is_server():
		return
	var local_player = _get_local_player()
	if local_player:
		var test_items: Array[String] = []
		for item_id in ItemDatabase.get_all_items():
			test_items.append(str(item_id))
		if test_items.is_empty():
			return
		var random_item = test_items[randi() % test_items.size()]
		local_player.request_add_item.rpc_id(1, random_item, 1)


func _debug_print_inventory():
	var local_player = _get_local_player()
	if local_player and local_player.get_inventory():
		var inventory = local_player.get_inventory()
		print("=== Inventory Debug ===")
		for i in range(inventory.slots.size()):
			var slot = inventory.get_slot(i)
			if slot and not slot.is_empty():
				print("Slot ", i, ": ", slot.item_id, " x", slot.quantity)
		print("=====================")
	else:
		print("No inventory found for local player")
