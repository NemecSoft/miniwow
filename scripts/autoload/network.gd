extends Node

signal player_connected(peer_id, player_info)
signal server_disconnected

const SERVER_ADDRESS: String = "127.0.0.1"
## 端口可覆盖：调试探针（如 tools/walk_block_probe.gd）需要在不打扰
## 正在运行的游戏实例的前提下自己起一个 host。
static var SERVER_PORT: int = 8080
const MAX_PLAYERS: int = 10
const MAX_NICK_LENGTH := 24
const MAX_ADDRESS_LENGTH := 253

var players = {}
# M27 条款 V3：注册信息是外观权威副本，三字段缺一即视为不同步缺陷——
# 旧版只有 nick/skin，迟加入客户端拿不到主机职业（事故 C：模型双裂）。
var player_info = {"nick": "host", "skin": Character.SkinColor.BLUE, "class": ""}
var _session_active := false


func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)


func start_host(nickname: String, skin_color_str: String):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	if error:
		return error

	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_session_active = true

	player_info["nick"] = sanitize_nickname(nickname, "Host_" + str(multiplayer.get_unique_id()))
	player_info["skin"] = skin_str_to_e(skin_color_str)

	if DisplayServer.get_name() == "headless":
		return

	players[1] = player_info
	player_connected.emit(1, player_info)


func join_game(nickname: String, skin_color_str: String, address: String = SERVER_ADDRESS):
	address = sanitize_address(address)
	if address.is_empty():
		return ERR_INVALID_PARAMETER

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, SERVER_PORT)
	if error:
		return error

	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_session_active = true

	player_info["nick"] = sanitize_nickname(nickname, "Player_" + str(multiplayer.get_unique_id()))
	player_info["skin"] = skin_str_to_e(skin_color_str)


func _on_connected_ok():
	# M27 事故 D（最深层根因）：Godot 4 ENet 客户端在 connected_to_server 触发时
	# unique_id 可能还是 create_client 的默认值 1（服务器 id 分配确认消息尚未
	# 到达/处理）。曾因此引发连锁灾难：join 端把自己当 peer 1 → 本地玩家节点
	# 错占"1"槽位（host 角色被 spawner 重放时 ERR_INVALID_DATA 放弃）→
	# join 的所有 rpc（选职业/X 召唤/E 上座）寻的服务器的"1"=host 角色 →
	# 客户端实际在远程操控主机，且 peer 2 在服务器从未注册（_register_player
	# 的 players.has(1) 早退），服务器压根没有"2"节点（骑乘/交互全找不到目标）。
	# 修复：轮询等待服务器分配的真实 id（unique_id > 1）再注册，最多等 2 秒。
	var peer_id = multiplayer.get_unique_id()
	var waited := 0.0
	while peer_id <= 1 and waited < 2.0:
		await get_tree().create_timer(0.05).timeout
		peer_id = multiplayer.get_unique_id()
		waited += 0.05
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)
	_register_player.rpc_id(1, player_info)


func _on_player_connected(id):
	if not multiplayer.is_server():
		return
	for peer_id in players:
		_sync_registered_player.rpc_id(id, peer_id, players[peer_id])


@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	if not multiplayer.is_server():
		return
	if not (new_player_info is Dictionary):
		return
	var new_player_id = multiplayer.get_remote_sender_id()
	if new_player_id == 0:
		return
	if players.has(new_player_id):
		return
	var sanitized_info = sanitize_player_info(new_player_info, "Player_" + str(new_player_id))
	players[new_player_id] = sanitized_info
	player_connected.emit(new_player_id, sanitized_info)
	_sync_registered_player.rpc(new_player_id, sanitized_info)


func _on_player_disconnected(id):
	players.erase(id)


func _on_connection_failed():
	_finish_session()


func _on_server_disconnected():
	_finish_session()


func leave_game() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer:
		peer.close()
	_finish_session()


func _finish_session() -> void:
	var had_session := _session_active or multiplayer.multiplayer_peer != null or not players.is_empty()
	_session_active = false
	multiplayer.multiplayer_peer = null
	players.clear()
	if had_session:
		server_disconnected.emit()


func skin_str_to_e(s):
	match str(s).strip_edges().to_lower():
		"blue":
			return Character.SkinColor.BLUE
		"yellow":
			return Character.SkinColor.YELLOW
		"green":
			return Character.SkinColor.GREEN
		"red":
			return Character.SkinColor.RED
		_:
			return Character.SkinColor.BLUE


@rpc("authority", "reliable")
func _sync_registered_player(peer_id: int, registered_player_info: Dictionary):
	if multiplayer.is_server():
		return
	if players.has(peer_id):
		return
	var sanitized_info = sanitize_player_info(registered_player_info, "Player_" + str(peer_id))
	players[peer_id] = sanitized_info
	player_connected.emit(peer_id, sanitized_info)


func sanitize_player_info(info: Dictionary, fallback_nick: String) -> Dictionary:
	return {
		"nick": sanitize_nickname(str(info.get("nick", "")), fallback_nick),
		"skin": sanitize_skin_value(info.get("skin", Character.SkinColor.BLUE)),
		# M27 条款 V3：class 原样透传（合法性由 ClassDatabase 校验），
		# 空串 = 未选职业（进游戏后会弹选择界面）
		"class": str(info.get("class", "")),
	}


func sanitize_nickname(nickname: String, fallback: String) -> String:
	var clean := ""
	var last_was_space := false
	for i in range(nickname.length()):
		var codepoint := nickname.unicode_at(i)
		if codepoint <= 31 or codepoint == 127:
			if not last_was_space:
				clean += " "
				last_was_space = true
			continue

		var character := nickname.substr(i, 1)
		if character == " ":
			if last_was_space:
				continue
			last_was_space = true
		else:
			last_was_space = false
		clean += character

	clean = clean.strip_edges()
	if clean.is_empty():
		clean = fallback.strip_edges()
	if clean.length() > MAX_NICK_LENGTH:
		clean = clean.substr(0, MAX_NICK_LENGTH).strip_edges()
	if clean.is_empty():
		clean = "Player"
	return clean


func sanitize_address(address: String) -> String:
	var clean = address.strip_edges()
	if clean.is_empty():
		return SERVER_ADDRESS
	if clean.length() > MAX_ADDRESS_LENGTH:
		return ""
	if clean.contains("://") or clean.contains("/") or clean.contains("\\") or clean.contains(":"):
		return ""
	return clean


func sanitize_skin_value(value) -> Character.SkinColor:
	if value is int:
		match value:
			Character.SkinColor.BLUE, Character.SkinColor.YELLOW, Character.SkinColor.GREEN, Character.SkinColor.RED:
				return value
			_:
				return Character.SkinColor.BLUE
	return skin_str_to_e(str(value))
