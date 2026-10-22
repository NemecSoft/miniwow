extends Node

## M37：音频设置管理器（三档音量 + 静音，持久化 user://settings.cfg）。
##
## 架构（与 ThemeManager 同构的 autoload 设置类）：
##   · 总线布局：本项目没有 default_bus_layout.tres，默认只有 Master。
##     为做"总音量 / 音效 / 环境音"三档独立控制，在 _ready 运行期用
##     AudioServer.add_bus_at_index 动态创建 SFX、Ambient 两条子总线，
##     两者 send 到 Master —— Master 控总量，子总线控分类。
##     动态创建而非编辑总线布局文件，是为了让 headless 测试与老存档
##     都不依赖美术资源改动（M37 决策）。
##   · 音量模型：一律存"线性 0~1"（用户心智：滑块拉多响多少），
##     应用时转 dB。0 是真正的静音（-80dB），不是"最小声"。
##   · 持久化：复用 settings.cfg 的 [audio] 段（与 ThemeManager 的 [ui]
##     段共存，ConfigFile 合并写不会互相覆盖）。
##   · 静音开关是"独立布尔"而非音量=0 的别名：静音时保持滑块位置，
##     取消静音立刻恢复用户上次设定的响度。
##
## 铁律：总线创建必须幂等——autoload 可能因热重载/进主菜单再入树多次。

signal volumes_changed(master: float, sfx: float, ambient: float, music: float)
signal mute_changed(muted: bool)

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const KEY_MASTER := "master_volume"
const KEY_SFX := "sfx_volume"
const KEY_AMBIENT := "ambient_volume"
const KEY_MUTED := "muted"
const KEY_MUSIC := "music_volume"

const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"
## M43：背景音乐独立总线——WoW 里音乐与环境音是分开的两档，
## 玩家常想把"雨声/脚步"留着但音乐关小。
const MUSIC_BUS := &"Music"

## 静音 dB：Godot 惯例用 -80dB 代表完全听不见
const MUTE_DB := -80.0

## 线性 0~1 → dB。0 直接给 MUTE_DB（linear_to_db(0) = -inf 会导致插值异常）。
static func linear_to_db01(linear: float) -> float:
	if linear <= 0.001:
		return MUTE_DB
	return linear_to_db(linear)

var master_volume := 1.0
var sfx_volume := 1.0
var ambient_volume := 1.0
## 音乐默认 0.55：BGM 是背景，压过音效会盖住打击反馈
var music_volume := 0.55
var muted := false

var _suppress_signal := false ## 载入/静音切换时避免逐档 emit 抖动


func _ready() -> void:
	_ensure_buses()
	_load()
	_apply_all()


## 幂等建总线：已存在就跳过（autoload 重入不重复 add）
func _ensure_buses() -> void:
	for bus_name in [SFX_BUS, AMBIENT_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, MASTER_BUS)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value(AUDIO_SECTION, KEY_MASTER, 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(AUDIO_SECTION, KEY_SFX, 1.0)), 0.0, 1.0)
	ambient_volume = clampf(float(cfg.get_value(AUDIO_SECTION, KEY_AMBIENT, 1.0)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value(AUDIO_SECTION, KEY_MUSIC, 0.55)), 0.0, 1.0)
	muted = bool(cfg.get_value(AUDIO_SECTION, KEY_MUTED, false))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 读旧值合并（失败不阻塞，保证 [ui] 主题段不丢）
	cfg.set_value(AUDIO_SECTION, KEY_MASTER, master_volume)
	cfg.set_value(AUDIO_SECTION, KEY_SFX, sfx_volume)
	cfg.set_value(AUDIO_SECTION, KEY_AMBIENT, ambient_volume)
	cfg.set_value(AUDIO_SECTION, KEY_MUSIC, music_volume)
	cfg.set_value(AUDIO_SECTION, KEY_MUTED, muted)
	cfg.save(SETTINGS_PATH)


func _apply_all() -> void:
	_suppress_signal = true
	_apply_master()
	_apply_sfx()
	_apply_ambient()
	_apply_music()
	_suppress_signal = false
	volumes_changed.emit(master_volume, sfx_volume, ambient_volume, music_volume)
	mute_changed.emit(muted)


## 静音时三档总线一起压到 -80dB；取消静音恢复各自设定值。
## Master 也压 —— 这样连环境循环音都真静音，符合"静音"的直觉。
func _apply_master() -> void:
	_set_bus_db(MASTER_BUS, master_volume)
	_set_bus_db(SFX_BUS, sfx_volume)
	_set_bus_db(AMBIENT_BUS, ambient_volume)
	_set_bus_db(MUSIC_BUS, music_volume)


func _apply_master_only() -> void:
	_set_bus_db(MASTER_BUS, master_volume)


func _apply_sfx() -> void:
	_set_bus_db(SFX_BUS, sfx_volume)


func _apply_ambient() -> void:
	_set_bus_db(AMBIENT_BUS, ambient_volume)


func _apply_music() -> void:
	_set_bus_db(MUSIC_BUS, music_volume)


func _set_bus_db(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var db := MUTE_DB if muted else linear_to_db01(linear)
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, muted or linear <= 0.001)


# ---- 对外接口（UI 拖动时调用，内部自动持久化）----

func set_master_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(v, master_volume):
		return
	master_volume = v
	_apply_master_only()
	if not _suppress_signal:
		_save()
		volumes_changed.emit(master_volume, sfx_volume, ambient_volume, music_volume)


func set_sfx_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(v, sfx_volume):
		return
	sfx_volume = v
	_apply_sfx()
	if not _suppress_signal:
		_save()
		volumes_changed.emit(master_volume, sfx_volume, ambient_volume, music_volume)


func set_ambient_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(v, ambient_volume):
		return
	ambient_volume = v
	_apply_ambient()
	if not _suppress_signal:
		_save()
		volumes_changed.emit(master_volume, sfx_volume, ambient_volume, music_volume)


func set_music_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(v, music_volume):
		return
	music_volume = v
	_apply_music()
	if not _suppress_signal:
		_save()
		volumes_changed.emit(master_volume, sfx_volume, ambient_volume, music_volume)


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	_apply_all()
	_save()


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


## 供 UI 初始化：一次性取当前三档（避免逐个 getter 重复触发信号）
func get_volumes() -> Vector4:
	return Vector4(master_volume, sfx_volume, ambient_volume, music_volume)


## M37 取证：打印当前总线实际状态（dB / mute）——验证"拉到 0 真的静音"
func debug_dump_buses() -> void:
	for bus_name in [MASTER_BUS, SFX_BUS, AMBIENT_BUS, MUSIC_BUS]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			printerr("[M37-AUDIO] 总线 %s 不存在" % bus_name)
			continue
		printerr("[M37-AUDIO] 总线 %s: db=%.2f mute=%s 线性档 master=%.2f sfx=%.2f ambient=%.2f muted=%s" % [
			bus_name, AudioServer.get_bus_volume_db(idx),
			str(AudioServer.is_bus_mute(idx)),
			master_volume, sfx_volume, ambient_volume, str(muted)])


## 百分比文本（UI 标签用）
static func format_percent(linear: float) -> String:
	return "%d%%" % roundi(clampf(linear, 0.0, 1.0) * 100.0)