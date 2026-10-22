extends Node
## M39：坐骑视觉设置（目前只有"坐骑光环"一项）。
##
## 与其它设置（主题/音量/语言）共用 user://settings.cfg，但放在独立的
## [vehicle] 段，互不干扰。
##
## 约定（沿用 ThemeManager / AudioSettings 的写法）：
##   · 用 Godot 的 ConfigFile API 读写（不用 Python configparser——
##     M21d 教训：无引号的 INI 输出会导致 Godot 解析报错）
##   · 字符串值必须带双引号（ConfigFile API 自动处理）
##   · 读取失败（文件不存在/损坏）→ 用默认值，不报错不阻塞

## M39：坐骑光环默认开启（需求："默认显示光环，在设置中可以开关"）
const DEFAULT_HOVER_HALO := true

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "vehicle"
const KEY_HOVER_HALO := "hover_halo_enabled"

## 开关变化时广播（各端本地生效，不走网络——纯客户端视觉偏好）
signal hover_halo_changed(enabled: bool)

var _hover_halo_enabled: bool = DEFAULT_HOVER_HALO


func _ready() -> void:
	_hover_halo_enabled = _load_hover_halo()


func is_hover_halo_enabled() -> bool:
	return _hover_halo_enabled


## 设置坐骑光环开关并持久化。返回最终生效值。
func set_hover_halo(enabled: bool) -> bool:
	_hover_halo_enabled = enabled
	_save_hover_halo(enabled)
	hover_halo_changed.emit(enabled)
	return _hover_halo_enabled


## 取反（UI 上的 CheckButton toggled 信号用）
func toggle_hover_halo() -> bool:
	return set_hover_halo(not _hover_halo_enabled)


func _load_hover_halo() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return DEFAULT_HOVER_HALO
	# 无该键时用默认值（首次运行 / 老存档）
	if not cfg.has_section_key(SECTION, KEY_HOVER_HALO):
		return DEFAULT_HOVER_HALO
	return bool(cfg.get_value(SECTION, KEY_HOVER_HALO, DEFAULT_HOVER_HALO))


func _save_hover_halo(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 读旧值合并（失败不阻塞）
	cfg.set_value(SECTION, KEY_HOVER_HALO, enabled)
	cfg.save(SETTINGS_PATH)


## ===== 载具数值配置（M53）=====
##
## 用户要求：「能设置的要可以直接通过设置就好，而不要凑数计算」。
## 飞行速度这类**玩法数值**不该是脚本里的 const —— 同一份构建，改
## user://settings.cfg 的 [vehicle] 段就能调，不用改代码重编。
##
## 用法：hover_couch 在 _ready 里读一次并缓存（避免每帧开文件）：
##     VehicleSettings.number("flight_speed", DEFAULT_FLIGHT_SPEED)
## 手动改法（settings.cfg）：
##     [vehicle]
##     flight_speed=60.0
##     boost_speed=260.0
##     hyper_speed=1400.0
##     vertical_speed=50.0
var _numbers := {}


## 读一个数值配置；没有该键就返回调用方给的默认值。
func number(key: String, default_value: float) -> float:
	if _numbers.has(key):
		return float(_numbers[key])
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	if not cfg.has_section_key(SECTION, key):
		return default_value
	var v: float = float(cfg.get_value(SECTION, key, default_value))
	_numbers[key] = v
	return v


## 写一个数值配置（下次进游戏生效）。返回最终值。
func set_number(key: String, value: float) -> float:
	_numbers[key] = value
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(SETTINGS_PATH)
	return value
