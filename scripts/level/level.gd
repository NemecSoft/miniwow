extends Node3D

const MAX_CHAT_MESSAGE_LENGTH := 160
const MIN_NICKNAME_HEIGHT := 2.0
const MAX_NICKNAME_HEIGHT := 8.0

# MiniWoW：村庄复活点（死亡后"释放灵魂"回到这里满血复活）
const RESPAWN_POINT := Vector3(0.0, 63.0, 320.0)
const COUCH_SCENE := preload("res://scenes/vehicles/hover_couch.tscn")
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
var _pending_couches := {}
var shop_visible := false
var quest_visible := false
var class_select_visible := false

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


func _ready():
	after_ready()

	if DisplayServer.get_name() == "headless":
		Network.start_host("", "")
		# M19 基座适配：独立服务器不需要天空/太阳/月亮（纯表现层），
		# Sky3D 提供 sky3d_enabled 总开关，关闭后不初始化天体系统
		var sky3d := get_node_or_null("Environment/Sky3D")
		if sky3d:
			sky3d.sky3d_enabled = false
	else:
		_setup_sky3d()


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

	# M10：命令行自动连接（双开联调，见设计文档 5.5）
	# 用法：godot --path . -- --auto host | --auto join（"--" 后为用户参数）
	_auto_connect_if_requested()

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
	_update_mouse_mode()


func _process(_delta: float) -> void:
	# M19：terrain 就绪后补发待发的专属沙发
	if not _pending_couches.is_empty():
		var starter := get_node_or_null("Environment/TerrainStarter")
		if starter != null and starter.terrain != null and starter.terrain.data != null:
			var pending: Dictionary = _pending_couches.duplicate()
			_pending_couches.clear()
			for pending_id in pending:
				var player_node := players_container.get_node_or_null(str(pending_id))
				if player_node != null:
					_dispatch_couch(int(pending_id), pending[pending_id])

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
			# headless 分支已起服，避免端口被二次占用
			if not multiplayer.has_multiplayer_peer():
				_on_host_pressed("Host", "blue")
		"join":
			await get_tree().create_timer(1.0).timeout
			_on_join_pressed("Client", "yellow", Network.SERVER_ADDRESS)


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


## M16c：HUD 跟随主菜单显隐——登录页只显示登录内容，不叠游戏 HUD
func _update_hud_for_menu() -> void:
	if hud:
		hud.visible = not main_menu.is_menu_visible()


func _add_player(id: int, player_info: Dictionary) -> Character:
	if DisplayServer.get_name() == "headless" and id == 1:
		return null

	if players_container.has_node(str(id)):
		return players_container.get_node(str(id)) as Character

	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point(id)
	players_container.add_child(player, true)

	# M19：每位玩家自动领取一台专属沙发飞行器
	_dispatch_couch(int(id), get_spawn_point(id))

	var nick = Network.sanitize_nickname(str(player_info.get("nick", "")), "Player_" + str(id))
	player.nickname.text = nick

	var skin_enum = Network.sanitize_skin_value(player_info.get("skin", Character.SkinColor.BLUE))
	player.set_player_skin(skin_enum)
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


func get_respawn_point() -> Vector3:
	return RESPAWN_POINT


func get_spawn_point(id: int) -> Vector3:
	var spawn_angle := fmod(float(id) * 2.399963229728653, 2.0 * PI)
	var spawn_point := Vector2.from_angle(spawn_angle) * 10
	# M19：出生点迁移到贫瘠之地南部平原（新 Terrain3D 地图，y 取地形高度）
	var pos := Vector3(RESPAWN_POINT.x + spawn_point.x, 0, RESPAWN_POINT.z + spawn_point.y)
	var starter := get_node_or_null("Environment/TerrainStarter")
	if starter and starter.terrain != null and starter.terrain.data != null:
		pos.y = starter.terrain.data.get_height(pos) + 0.5
	else:
		pos.y = 62.0
	return pos


## M19：为玩家生成专属沙发（terrain 未就绪时记入待发，就绪后补发）
func _dispatch_couch(id: int, spawn_base: Vector3) -> void:
	var starter := get_node_or_null("Environment/TerrainStarter")
	var vehicles_container := get_node_or_null("Environment/Vehicles")
	if vehicles_container == null or starter == null:
		return
	var couch_name := "couch_%d" % id
	if vehicles_container.has_node(couch_name):
		return
	if starter.terrain == null or starter.terrain.data == null:
		_pending_couches[id] = spawn_base
		return
	var couch := COUCH_SCENE.instantiate()
	couch.name = couch_name
	couch.position = Vector3(spawn_base.x + 6.0, spawn_base.y - 0.5, spawn_base.z - 6.0)
	vehicles_container.add_child(couch, true)


func _remove_player(id):
	_player_nickname_heights.erase(id)
	if not players_container.has_node(str(id)):
		call_deferred("_refresh_player_list")
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()
	# M19：回收该玩家的专属沙发
	var vehicles_container := get_node_or_null("Environment/Vehicles")
	if vehicles_container:
		var couch := vehicles_container.get_node_or_null("couch_%d" % int(id))
		if couch:
			couch.queue_free()
	call_deferred("_refresh_player_list")


func _on_quit_pressed() -> void:
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


func _input(event):
	if event.is_action_pressed("pause"):
		_handle_pause_action()
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
	if not quest_visible and not class_select_visible and not shop_visible:
		var villager := _get_nearby_villager(local_player)
		if villager:
			villager.say_hello()
			return
		# M15：伙伴最低优先级——靠近自己的小跟班按 E，它挥手
		for partner in get_tree().get_nodes_in_group("partners"):
			if partner is Node3D:
				if local_player.global_position.distance_to((partner as Node3D).global_position) <= 3.0:
					partner.say_hello()
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
	return pause_menu.is_menu_visible() or shop_visible or quest_visible or class_select_visible


func is_camera_input_blocked() -> bool:
	return is_gameplay_input_blocked() or inventory_visible or multiplayer_chat.is_chat_visible()


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
