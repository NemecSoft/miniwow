extends Node

## MiniWoW 声效管理器（M11）。
## 全局音效入口：play(key) 播 UI/本地反馈音（无空间衰减），
## play_3d(key, position) 在世界坐标播 3D 空间音（近大远小，播完自释放）。
## 纯表现原则：音效只在本端播放，不进 RPC——挂接点全部位于
## 已同步的信号/状态变化处，各端独立触发同一条音效。
## M14：spawn_effect 提供同样的"纯表现、播完自释放"入口给粒子特效
## （音效与特效同属表现层杂务，共用本 autoload 避免再造一个单例）。

## 音效库：key → wav 路径（文件源自 Sound FX Starter Pack Vol. 1，
## 已重命名拷入 assets/sfx/，语义化 key 与业务代码解耦）
## M18b-6：战斗类 key 全量切换到 roguelite 原版音频（用户要求"声音用原版的"），
## key 不变、业务代码零改动——roguelite 没有的音（盾挡/木桩/死亡/系统类）保留旧文件。
const _LIBRARY := {
	# —— 战斗（M18b-6 起为 roguelite 原版音频）——
	&"swing": "res://assets/sfx/combat/weapon-swing.ogg", # 原版挥剑声
	&"hit_flesh": "res://assets/sfx/combat/hit.ogg", # 原版命中闷响
	&"monster_pain": "res://assets/sfx/combat/hit.ogg", # 原版怪受击（与命中同源）
	&"monster_die": "res://assets/sfx/combat/monster_die.wav", # roguelite 无死亡音，保留
	&"heavy_punch": "res://assets/sfx/combat/metal-hit.ogg", # 踢击/处决 → 原版金属声
	&"shield_block": "res://assets/sfx/combat/shield_block.wav", # roguelite 无盾声，保留
	&"dummy_hit": "res://assets/sfx/combat/dummy_hit.wav", # M13：木桩木头声（保留）
	&"player_hit": "res://assets/sfx/combat/metal-hit.ogg", # 玩家受击 → 原版金属声
	# M18b-5：roguelite 战斗音效包（文件源自 godot-roguelite Assets/Audio）
	&"dash": "res://assets/sfx/combat/dash.ogg", # 冲刺破空声
	&"metal_hit": "res://assets/sfx/combat/metal-hit.ogg", # 步兵（铠甲）受击金属声
	&"hit_light": "res://assets/sfx/combat/hit.ogg", # KayKit 怪物受击闷响
	# —— 移动 ——
	&"footstep": "res://assets/sfx/movement/footstep.wav", # M13 变通版（保留不删，见 tools/make_footstep.py）
	&"footstep_0": "res://assets/sfx/movement/footstep_concrete_000.ogg", # M15：真脚步声（Jeheno 包）
	&"footstep_1": "res://assets/sfx/movement/footstep_concrete_001.ogg",
	&"footstep_2": "res://assets/sfx/movement/footstep_concrete_002.ogg",
	# —— 技能 ——
	&"heal": "res://assets/sfx/skills/heal.wav",
	&"holy_missile": "res://assets/sfx/skills/holy_missile.wav",
	&"fireball": "res://assets/sfx/skills/fireball.wav",
	&"frostbolt": "res://assets/sfx/skills/frostbolt.wav",
	&"arcane": "res://assets/sfx/skills/arcane.wav",
	# —— 物品 ——
	&"pickup": "res://assets/sfx/items/pickup.wav",
	&"equip": "res://assets/sfx/items/equip.wav",
	&"inventory_full": "res://assets/sfx/ui/error.wav",
	# —— UI ——
	&"ui_click": "res://assets/sfx/ui/click.wav",
	&"ui_hover": "res://assets/sfx/ui/hover.wav",
	&"ui_inventory": "res://assets/sfx/ui/inventory.wav",
	&"ui_close": "res://assets/sfx/ui/close.wav",
	# —— 系统 ——
	&"jump": "res://assets/sfx/system/jump.wav",
	&"low_hp": "res://assets/sfx/system/low_hp.wav",
	&"full_heal": "res://assets/sfx/system/full_heal.wav",
	&"quest_success": "res://assets/sfx/system/quest_success.wav",
	&"welcome": "res://assets/sfx/system/welcome.wav",
}

## 低血量/满血提示的全局冷却（毫秒），防止反复触发刷屏
const HP_ALERT_COOLDOWN_MSEC := 30000

## M15：脚步声随机轮播组（三条 concrete 脚步循环随机，避免机械重复感）
const FOOTSTEP_KEYS: Array[StringName] = [&"footstep_0", &"footstep_1", &"footstep_2"]

var _ui_player: AudioStreamPlayer
## 冷却基准初始化为"负冷却"：进程刚启动时 ticks_msec 很小，
## 若初始化为 0 会导致启动后 30 秒内血量提示被误判为冷却中
var _hp_alert_last_msec := -HP_ALERT_COOLDOWN_MSEC
## 测试模式：headless 无音频设备时仍可执行逻辑但不发声
var _muted := false


func _ready() -> void:
	# 环境循环音不属于"一次性事件音"，由 level 场景自带节点播放，不在本表内
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UiSfxPlayer"
	_ui_player.bus = &"Master"
	add_child(_ui_player)
	# headless（服务器/测试）下没有音频输出设备，静音避免无谓解码
	_muted = DisplayServer.get_name() == "headless"


## 播放全局 2D 音（UI 点击、系统提示等），同 key 连续触发会打断上一条（UI 音可接受）。
## volume_db：负值压低音量（脚步等环境感音效用）
func play(key: StringName, volume_db: float = 0.0) -> void:
	if _muted:
		return
	var stream := _get_stream(key)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()


## 在世界坐标播放 3D 音（怪物受击、掉落等），AudioStreamPlayer3D 播完自释放。
## unit_size 控制衰减速度：默认值在 2.5 米拾取距离/典型战斗距离下音量自然。
func play_3d(key: StringName, world_position: Vector3, unit_size: float = 8.0) -> void:
	if _muted:
		return
	var stream := _get_stream(key)
	if stream == null:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p3d := AudioStreamPlayer3D.new()
	p3d.stream = stream
	p3d.bus = &"Master"
	p3d.unit_size = unit_size
	p3d.max_db = 0.0
	tree.current_scene.add_child(p3d)
	p3d.global_position = world_position
	p3d.play()
	p3d.finished.connect(p3d.queue_free)


## M15：随机轮播组播放（脚步等循环音效防机械重复）。本地 2D 版
func play_random(keys: Array[StringName], volume_db: float = 0.0) -> void:
	if keys.is_empty():
		return
	play(keys[randi() % keys.size()], volume_db)


## M15：随机轮播组播放，3D 空间版
func play_3d_random(keys: Array[StringName], world_position: Vector3, unit_size: float = 8.0) -> void:
	if keys.is_empty():
		return
	play_3d(keys[randi() % keys.size()], world_position, unit_size)


## 血量类提示音（低血/满血）带全局冷却，返回是否真的播了
func play_hp_alert(key: StringName) -> bool:
	var now := Time.get_ticks_msec()
	if now - _hp_alert_last_msec < HP_ALERT_COOLDOWN_MSEC:
		return false
	_hp_alert_last_msec = now
	play(key)
	return true


## M14：在世界坐标生成一次性粒子特效（命中火花等）。
## 场景须挂 self_destroy_particles.gd（播完自毁）。headless 下跳过。
func spawn_effect(scene_path: String, world_position: Vector3) -> void:
	if _muted:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("SfxManager: 特效场景加载失败 %s" % scene_path)
		return
	var fx := scene.instantiate() as Node3D
	tree.current_scene.add_child(fx)
	fx.global_position = world_position


func _get_stream(key: StringName) -> AudioStream:
	if not _LIBRARY.has(key):
		push_warning("SfxManager: 未知音效 key '%s'" % key)
		return null
	var path: String = _LIBRARY[key]
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("SfxManager: 音效加载失败 %s" % path)
	return stream


## ===== UI 按钮统一挂钩 =====

## 给 root 子树内所有按钮挂点击音（幂等，已连过不重复）。建议 call_deferred 调用
## （等场景 UI 全部 ready，覆盖主菜单/暂停/背包/商店/任务等所有静态按钮）
func hook_buttons(root: Node) -> void:
	for btn in _find_buttons(root):
		if not btn.pressed.is_connected(_on_button_click):
			btn.pressed.connect(_on_button_click)


## 给 root 子树内所有按钮挂悬停音（幂等）。只对主菜单用——高频区域挂全局会吵
func hook_hover(root: Node) -> void:
	for btn in _find_buttons(root):
		if not btn.mouse_entered.is_connected(_on_button_hover):
			btn.mouse_entered.connect(_on_button_hover)


func _find_buttons(root: Node) -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	if root is BaseButton:
		result.append(root)
	for child in root.get_children():
		result.append_array(_find_buttons(child))
	return result


func _on_button_click() -> void:
	play(&"ui_click")


func _on_button_hover() -> void:
	play(&"ui_hover")
