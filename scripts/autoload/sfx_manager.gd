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
	# —— 战斗（M18b：保留 roguelite 原版音频，Magic UI 库无对应，不替换） ——
	&"swing": "res://assets/sfx/combat/weapon-swing.ogg", # 原版挥剑声（保留）
	&"hit_flesh": "res://assets/sfx/combat/hit.ogg", # 原版命中闷响（保留）
	&"monster_pain": "res://assets/sfx/combat/hit.ogg", # 原版怪受击（保留）
	&"monster_die": "res://assets/sfx/combat/monster_die.wav", # roguelite 无死亡音（保留）
	&"heavy_punch": "res://assets/sfx/combat/metal-hit.ogg", # 踢击/处决（保留）
	&"shield_block": "res://assets/sfx/combat/shield_block.wav", # roguelite 无盾声（保留）
	&"dummy_hit": "res://assets/sfx/combat/dummy_hit.wav", # 木桩木头声（保留）
	&"player_hit": "res://assets/sfx/combat/metal-hit.ogg", # 玩家受击（保留）
	&"metal_hit": "res://assets/sfx/combat/metal-hit.ogg", # 铠甲受击（保留）
	&"hit_light": "res://assets/sfx/combat/hit.ogg", # KayKit 怪受击（保留）
	# —— 移动（保留原版脚步声，库无对应） ——
	&"footstep": "res://assets/sfx/movement/footstep.wav",
	&"footstep_0": "res://assets/sfx/movement/footstep_concrete_000.ogg",
	&"footstep_1": "res://assets/sfx/movement/footstep_concrete_001.ogg",
	&"footstep_2": "res://assets/sfx/movement/footstep_concrete_002.ogg",
	&"grassy_field": "res://assets/sfx/environment/grassy_field.wav", # 环境底噪（保留）
	# —— 载具引擎（保留原版，库无对应） ——
	&"vehicle_electric": "res://assets/audio/vehicle/electric-drive.wav",
	&"vehicle_jet": "res://assets/audio/vehicle/jet-loop.wav",
	# —— 战斗动作（Magic UI 风声近似原 weapon-swing/dash） ——
	&"swing_fx": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_light_sirens_call.wav", # 挥击破空（Magic UI whoosh）
	&"dash": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_neutral_phantom.wav", # 冲刺破空（Magic UI whoosh）
	# —— 技能（Magic UI 法术音，整体替换原 skills/*.wav） ——
	&"heal": "res://assets/sfx/magic_ui/magicui_magspel_potion_health_boost.wav", # 治疗
	&"fireball": "res://assets/sfx/magic_ui/magicui_magpoof_poof_large_neutral_big_bang.wav", # 火球爆发
	&"frostbolt": "res://assets/sfx/magic_ui/magicui_magpoof_poof_small_light_mystic.wav", # 冰晶
	&"arcane": "res://assets/sfx/magic_ui/magicui_magpoof_poof_large_light_slammer.wav", # 奥术
	&"holy_missile": "res://assets/sfx/magic_ui/magicui_magpoof_poof_large_light_secret_loot.wav", # 神圣飞弹
	# —— 物品 ——
	&"pickup": "res://assets/sfx/magic_ui/magicui_uimisc_reward_normal_green_drop.wav", # 拾取
	&"equip": "res://assets/sfx/magic_ui/magicui_uimisc_confirm_anvil.wav", # 装备
	&"chest": "res://assets/sfx/magic_ui/magicui_doorwood_chest_open_loot_surprise.wav", # 宝箱开启
	# —— UI ——
	&"ui_click": "res://assets/sfx/magic_ui/magicui_uiclick_select_choice.wav", # 按钮点击
	&"ui_hover": "res://assets/sfx/magic_ui/magicui_uiclick_focus_hover.wav", # 按钮悬停
	&"ui_inventory": "res://assets/sfx/magic_ui/magicui_uimisc_menu_open_small_skilltree.wav", # 背包打开
	&"ui_close": "res://assets/sfx/magic_ui/magicui_uimisc_menu_close_small_mystique.wav", # 界面关闭
	&"inventory_full": "res://assets/sfx/magic_ui/magicui_uimisc_invalid_blocked.wav", # 无效操作
	# —— 系统 ——
	&"quest_success": "res://assets/sfx/magic_ui/magicui_uimisc_quest_complete_complete.wav", # 任务完成
	&"welcome": "res://assets/sfx/magic_ui/magicui_uiclick_select_welcome.wav", # 欢迎
	&"jump": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_neutral_passby.wav", # 跳跃
	&"low_hp": "res://assets/sfx/magic_ui/magicui_uimisc_notification_watch_out.wav", # 低血警告
	&"full_heal": "res://assets/sfx/magic_ui/magicui_magspel_potion_health_refresh.wav", # 满血
	# —— 施法前摇（新增，Magic UI whoosh） ——
	&"cast_fire": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_light_enchanted_whisp.wav", # 火球前摇
	&"cast_frost": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_light_shimmer.wav", # 冰前摇
	&"cast_arcane": "res://assets/sfx/magic_ui/magicui_dsgnwhsh_whoosh_light_flourish.wav", # 奥术前摇
	# —— 进度 / 奖励 / 交易（新增） ——
	&"level_up": "res://assets/sfx/magic_ui/magicui_magpoof_level_up_ascend.wav", # 升级
	&"reward": "res://assets/sfx/magic_ui/magicui_uimisc_reward_magic_wizardry.wav", # 获得奖励
	&"coin": "res://assets/sfx/magic_ui/magicui_objcoin_buy_coin_toss.wav", # 金币交易
	&"quest_accept": "res://assets/sfx/magic_ui/magicui_uimisc_quest_accept_start.wav", # 任务接受
	&"notification": "res://assets/sfx/magic_ui/magicui_uimisc_notification_mystic_orb.wav", # 通知
	&"teleport": "res://assets/sfx/magic_ui/magicui_magpoof_poof_large_neutral_phantom_whisper.wav", # 传送
	&"thunder": "res://assets/sfx/magic_ui/magicui_magpoof_poof_large_dark_voidthorn_curse.wav", # 暴风雨雷声
}

## 低血量/满血提示的全局冷却（毫秒），防止反复触发刷屏
const HP_ALERT_COOLDOWN_MSEC := 30000

## ===== M43：3D 音频空间化参数 =====
## 用户问题：「现在声音没有空间感，怎么远处打击的声音我都能听到？」
## 根因有两层：
## ① 大量世界事件走了 play()（2D 全局播放，压根没有距离衰减）——
##    最典型的是 bot 的攻击音：bot 由服务器代播动画，权限 id 是 9004 而不是本地玩家，
##    于是地图另一头 bot 的挥剑/技能声以全音量灌进本地耳朵。
## ② play_3d() 的 unit_size 默认 8 米且 max_distance=0（=不限距离），
##    衰减太慢、又没有远距离低通，远处声音只是"小一点"而不是"远"。
## 现在：近处（自己的动作）走 2D 保清晰，其余一律 3D + 距离剔除 + 低通 + 多普勒。
const SFX_MAX_DISTANCE := 55.0        ## 超过该距离直接不播（省 CPU，彻底静音）
const SFX_FILTER_CUTOFF_HZ := 3000.0  ## 远处截止频率（近处会插值回 ~20kHz，听感"发闷"= 远）
const SFX_DEFAULT_UNIT_SIZE := 5.0    ## 衰减基准距离（8 米太远，5 米更像真人耳）

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
	# M37：走 SFX 子总线（AudioSettings 运行期创建），与"总音量 Master"分层控制
	_ui_player.bus = &"SFX"
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
## unit_size：衰减基准距离（米）。值越小衰减越快，越"贴耳"。
## M43：新增 ① 超距剔除 ② 逆距离衰减 ③ 远距离低通（空间感的关键）
##       ④ 多普勒 ⑤ max_distance 兜底。
func play_3d(key: StringName, world_position: Vector3, unit_size: float = SFX_DEFAULT_UNIT_SIZE) -> void:
	if _muted:
		return
	if not (is_finite(world_position.x) and is_finite(world_position.y) and is_finite(world_position.z)):
		return
	# 超距直接不播：这是"远处打击声听不到"的硬保证。
	# 相机不存在时（极少：headless/切场景瞬间）放行，避免整局静音。
	var cam := _current_camera()
	if cam != null and cam.global_position.distance_to(world_position) > SFX_MAX_DISTANCE:
		return
	var stream := _get_stream(key)
	if stream == null:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p3d := AudioStreamPlayer3D.new()
	p3d.stream = stream
	p3d.bus = &"SFX"
	p3d.unit_size = maxf(unit_size, 0.5)
	p3d.max_db = 0.0
	p3d.max_distance = SFX_MAX_DISTANCE
	# 逆距离模型（默认是 INVERSE_DISTANCE 的宽松版，远处仍偏响）
	p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# 低通：近处约 20kHz（清脆），远处压到 3kHz（闷），这是"距离感"的主要听感来源
	# 注意 Godot 4 已移除 attenuation_filter_enabled（3.x 才有），写它会 Invalid set index
	p3d.attenuation_filter_cutoff_hz = SFX_FILTER_CUTOFF_HZ
	p3d.attenuation_filter_db = -18.0
	p3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p3d.panning_strength = 1.0
	tree.current_scene.add_child(p3d)
	p3d.global_position = world_position
	p3d.play()
	p3d.finished.connect(p3d.queue_free)


## M43：世界事件通用入口——按"离相机远近"自动选择播放方式。
## 近距离（自己的动作、脚下的掉落）走 2D：第三人称相机在身后几米，
## 若也走 3D，自己的挥剑声会被自己的弹簧臂距离衰减掉，听感反而变小。
## 其余一律 3D，由 play_3d 做衰减/低通/超距剔除。
func play_world(key: StringName, world_position: Vector3, near_distance := 4.0, unit_size: float = SFX_DEFAULT_UNIT_SIZE) -> void:
	if _muted:
		return
	if not (is_finite(world_position.x) and is_finite(world_position.y) and is_finite(world_position.z)):
		return
	var cam := _current_camera()
	if cam != null and cam.global_position.distance_to(world_position) <= near_distance:
		play(key)
		return
	play_3d(key, world_position, unit_size)


## 当前监听相机（Godot 用它作为 3D 音频的听者位置）
func _current_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	var vp := tree.root.get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


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
