extends Node

## M24：bot 好感度"人性"系统（服务器权威）。
## 设计原型（用户定义）：bot 有性格，与玩家一起做任务会累积好感/厌恶；
## 厌恶到一定程度有概率倒戈（打怪时帮怪打玩家），好感高的 bot 会主动助战。
##
## 协作判定：同一只怪在时间窗内被"某玩家"和"某 bot"都攻击过 → 记一次协作对。
## 任务完成结算 → 协作中的 bot 按性格加好感；协作中 bot 阵亡 → 按性格加厌恶。
## 持久化：user://social.cfg（Godot ConfigFile 格式）。

const CFG_PATH := "user://social.cfg"
const CFG_SECTION_PREFIX := "bot_"

## 协作时间窗（秒）：同怪被双方先后攻击都算协作
const COOP_WINDOW_SEC := 60.0
## 背叛底线：厌恶达到此值才可能倒戈（用户选定"底线+线性"方案）
const BETRAY_HATE_FLOOR := 50
## 背叛概率 = (厌恶 - 底线) * 此系数（厌恶100 → 50% 概率）
const BETRAY_CHANCE_PER_POINT := 0.01
## 助战门槛：好感达到此值的 bot 会在玩家被怪攻击时反击该怪
const ASSIST_FAVOR_THRESHOLD := 80
## 好感/厌恶数值上限
const STAT_CAP := 500

## 性格表：一起做任务完成/失败（bot 阵亡）时的好感/厌恶增量（用户原型+补充两种）
const PERSONALITIES := {
	"vengeful": {"name": "恩怨分明", "favor_on_complete": 100, "hate_on_fail": 120},
	"easygoing": {"name": "随和", "favor_on_complete": 30, "hate_on_fail": 0},
	"grudge": {"name": "记仇", "favor_on_complete": 40, "hate_on_fail": 80},
	"loyal": {"name": "忠诚", "favor_on_complete": 80, "hate_on_fail": 40},
}

## 关系表：bot_peer -> player_peer -> {"favor": int, "hate": int}
var _rel: Dictionary = {}
## bot_peer -> 性格 id
var _personality: Dictionary = {}
## 协作对（去重集合）：key = "%d|%d" % [bot_peer, player_peer]
var _coop_pairs: Dictionary = {}
## 怪物命中记录：monster_instance_id -> {peer -> 上次命中 Unix 秒}
var _monster_hits: Dictionary = {}
## 已报告死亡的 bot（防重复结算）
var _dead_reported: Dictionary = {}


func _ready() -> void:
	_load()


func register_bot(bot_peer: int, personality_id: String) -> void:
	_personality[bot_peer] = personality_id
	if not _rel.has(bot_peer):
		_rel[bot_peer] = {}
	_save()


## 玩家攻击了怪（怪物 apply_combat_damage 服务器侧调用）
func record_monster_hit(monster: Node, attacker_peer: int) -> void:
	if attacker_peer <= 0 or not multiplayer.is_server():
		return
	var mid := monster.get_instance_id()
	var now := Time.get_unix_time_from_system()
	if not _monster_hits.has(mid):
		_monster_hits[mid] = {}
	var hits: Dictionary = _monster_hits[mid]
	# 清理该怪过期记录
	for peer in hits.keys():
		if now - float(hits[peer]) > COOP_WINDOW_SEC:
			hits.erase(peer)
	hits[attacker_peer] = now
	# 同怪既有玩家又有 bot → 记协作对（M28：bot 判定改 PeerQuery，
	# 旧 >=9001 把 ENet 大随机 id 的真人客户端误判成 bot）
	var players: Array = []
	var bots: Array = []
	for peer in hits:
		if PeerQuery.is_bot_peer(int(peer)):
			bots.append(int(peer))
		else:
			players.append(int(peer))
	var best_pair := _coop_pairs.size()
	for b in bots:
		for p in players:
			_coop_pairs["%d|%d" % [b, p]] = true
	if _coop_pairs.size() != best_pair:
		printerr("HIT_DIAG: %s 新协作对 players=%s bots=%s" % [monster.name, players, bots])  # 临时诊断


## 查询协作伙伴（双向）：peer 是玩家 → 返回协作 bot 列表；peer 是 bot → 返回协作玩家列表
func _coop_partners_for(peer: int) -> Array:
	var result: Array = []
	for key in _coop_pairs:
		var parts := str(key).split("|")
		if int(parts[0]) == peer:
			result.append(int(parts[1]))
		elif int(parts[1]) == peer:
			result.append(int(parts[0]))
	return result


func _clear_coop_for(peer: int) -> void:
	for key in _coop_pairs.keys():
		var parts := str(key).split("|")
		if int(parts[0]) == peer or int(parts[1]) == peer:
			_coop_pairs.erase(key)


## 任务完成（request_turn_in_quest 成功后调用，玩家/bot 皆可交）：
## 协作对中"bot 对玩家"按 bot 性格加好感——任一方交任务都结算。
func on_quest_completed(actor: Node) -> void:
	if not multiplayer.is_server():
		return
	var actor_peer := actor.get_multiplayer_authority()
	var actor_name := str(actor.get("nickname"))
	printerr("TURNIN_DIAG: actor=%s(%d) partners=%s" % [
		actor_name, actor_peer, _coop_partners_for(actor_peer)])  # 临时诊断
	for partner_peer in _coop_partners_for(actor_peer):
		# 协作对固定为 (bot, player)，按 PeerQuery.is_bot_peer 判角色（M28 修正）
		var partner_is_bot := PeerQuery.is_bot_peer(partner_peer)
		var bot_peer: int = partner_peer if partner_is_bot else actor_peer
		var player_peer: int = actor_peer if partner_is_bot else partner_peer
		var pid := str(_personality.get(bot_peer, "easygoing"))
		var gain := int(PERSONALITIES[pid].favor_on_complete)
		_add_stat(bot_peer, player_peer, "favor", gain)
		_chat("人情", "%s 与 %s 一同完成任务，好感 +%d（%s）" % [
			_bot_name(bot_peer), actor_name, gain, PERSONALITIES[pid].name])
	_clear_coop_for(actor_peer)
	_save()


## bot 阵亡（bt_bot_respawn 复活前调用）：协作中的"任务失败"，按性格加厌恶
func on_bot_died(bot: Node) -> void:
	if not multiplayer.is_server():
		return
	var bot_peer := bot.get_multiplayer_authority()
	if _dead_reported.has(bot_peer):
		return
	_dead_reported[bot_peer] = true
	for key in _coop_pairs.keys():
		var parts := str(key).split("|")
		if int(parts[0]) != bot_peer:
			continue
		var player_peer := int(parts[1])
		var pid := str(_personality.get(bot_peer, "easygoing"))
		var gain := int(PERSONALITIES[pid].hate_on_fail)
		if gain > 0:
			_add_stat(bot_peer, player_peer, "hate", gain)
			_chat("人情", "%s 在协作中阵亡，对玩家心生 %s（厌恶 +%d）" % [
				_bot_name(bot_peer), PERSONALITIES[pid].name, gain])
		_coop_pairs.erase(key)
	_save()


## bot 复活后清除死亡标记（bt_bot_respawn 成功后调用）
func clear_dead(bot_peer: int) -> void:
	_dead_reported.erase(bot_peer)


## 怪物攻击了玩家（monster._deal_attack 服务器侧调用）：
## 1) 好感≥门槛的 bot 反击该怪（助战）
## 2) 厌恶≥底线的 bot 按概率倒戈帮怪打玩家
func on_player_attacked_by_monster(monster: Node, player: Node) -> void:
	if not multiplayer.is_server():
		return
	var player_peer := player.get_multiplayer_authority()
	for bot_peer in _personality:
		var bot := _find_bot(bot_peer)
		if bot == null or not is_instance_valid(bot):
			continue
		var attrs: Node = bot.get("attribute_set")
		if attrs == null or not attrs.is_alive():
			continue
		var favor := get_stat(bot_peer, player_peer, "favor")
		var hate := get_stat(bot_peer, player_peer, "hate")
		if favor >= ASSIST_FAVOR_THRESHOLD:
			# 助战：反击攻击玩家的怪
			bot.request_attack(str(bot.get_path_to(monster)), "basic_attack")
		elif hate >= BETRAY_HATE_FLOOR:
			var chance := float(hate - BETRAY_HATE_FLOOR) * BETRAY_CHANCE_PER_POINT
			if randf() < chance:
				bot.request_attack(str(bot.get_path_to(player)), "basic_attack")
				_chat("人情", "%s 对你倒戈相向！（厌恶 %d）" % [_bot_name(bot_peer), hate])


func get_stat(bot_peer: int, player_peer: int, key: String) -> int:
	if not _rel.has(bot_peer):
		return 0
	return int(_rel[bot_peer].get(player_peer, {}).get(key, 0))


func _add_stat(bot_peer: int, player_peer: int, key: String, amount: int) -> void:
	if not _rel.has(bot_peer):
		_rel[bot_peer] = {}
	if not _rel[bot_peer].has(player_peer):
		_rel[bot_peer][player_peer] = {"favor": 0, "hate": 0}
	var entry: Dictionary = _rel[bot_peer][player_peer]
	entry[key] = clampi(int(entry.get(key, 0)) + amount, 0, STAT_CAP)


func _save() -> void:
	var cfg := ConfigFile.new()
	for bot_peer in _rel:
		for player_peer in _rel[bot_peer]:
			var key := "%s%d_%d" % [CFG_SECTION_PREFIX, bot_peer, player_peer]
			cfg.set_value("social", key, _rel[bot_peer][player_peer])
	cfg.save(CFG_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	if not cfg.has_section("social"):
		return
	for key in cfg.get_section_keys("social"):
		var rest := key.trim_prefix(CFG_SECTION_PREFIX)
		var parts := rest.split("_")
		if parts.size() != 2:
			continue
		var bot_peer := int(parts[0])
		var player_peer := int(parts[1])
		if not _rel.has(bot_peer):
			_rel[bot_peer] = {}
		_rel[bot_peer][player_peer] = cfg.get_value("social", key, {"favor": 0, "hate": 0})


## 按 peer 找 bot 玩家节点（服务器侧 PlayersContainer 直查）
func _find_bot(bot_peer: int) -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var container := scene.get_node_or_null("PlayersContainer")
	if container == null:
		return null
	return container.get_node_or_null(str(bot_peer))


func _bot_name(bot_peer: int) -> String:
	var bot := _find_bot(bot_peer)
	if bot != null:
		return str(bot.get("nickname"))
	return "bot%d" % bot_peer


## 系统聊天广播（与 level.show_chat_message 同通道）
func _chat(sender: String, text: String) -> void:
	printerr("SOCIAL: [%s] %s" % [sender, text])  # 服务器日志（headless 验证用）
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("show_chat_message"):
		scene.show_chat_message.rpc(tr(sender), tr(text), &"system")
