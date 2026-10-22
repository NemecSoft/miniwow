extends Node

## M43：背景音乐播放器（魔兽世界风格的循环 BGM）。
##
## 设计要点：
##   · 走独立的 Music 总线（AudioSettings 运行期创建），与音效/环境音分档控制；
##   · 循环是真循环（AudioStreamOggVorbis.loop = true），不是"播完再 play"——
##     后者在曲尾会有可闻缝隙；
##   · 进出战斗/场景切换一律淡入淡出，避免硬切"啪"声（BGM 最忌讳的瑕疵）；
##   · headless（专用服务器）完全不加载音频，省内存也避免无音频设备报错；
##   · 曲目表留扩展位：以后加战斗曲/夜晚曲只往 TRACKS 里加一条。
##
## 曲目由 tools/make_bgm.py 程序化合成（D 大调、66BPM、16 小节、弦乐+竖琴+长笛），
## 尾巴折回开头做到无缝循环——详见该脚本头部注释。

const TRACKS := {
	&"village": "res://assets/audio/music/bgm_village.ogg",
}

## 主菜单与游戏内用同一首田园曲；将来分场景时改这里即可
const DEFAULT_TRACK := &"village"
const FADE_IN_SEC := 3.0
const FADE_OUT_SEC := 1.6
const SILENT_DB := -60.0

var _player: AudioStreamPlayer
var _current: StringName = &""
var _fade: Tween
var _muted_env := false


func _ready() -> void:
	_muted_env = DisplayServer.get_name() == "headless"
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	_player.bus = &"Music"
	_player.volume_db = SILENT_DB
	add_child(_player)
	# 等一帧让 AudioSettings 建完总线再起播（autoload 顺序不保证）
	call_deferred("_auto_start")


func _auto_start() -> void:
	if _muted_env:
		return
	play_track(DEFAULT_TRACK)


## 播放指定曲目（同名曲目正在播则忽略，避免重复触发把曲子打回开头）
func play_track(key: StringName, fade_in := FADE_IN_SEC) -> void:
	if _muted_env:
		return
	if _current == key and _player.playing:
		return
	if not TRACKS.has(key):
		push_warning("MusicPlayer: 未知曲目 %s" % key)
		return
	var stream := load(str(TRACKS[key])) as AudioStream
	if stream == null:
		push_warning("MusicPlayer: 曲目加载失败 %s" % TRACKS[key])
		return
	# OGG 的 loop 属性必须在播放前设；改成副本避免污染资源缓存
	if stream is AudioStreamOggVorbis:
		var ogg := (stream as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		ogg.loop = true
		stream = ogg
	elif stream is AudioStreamMP3:
		var mp3 := (stream as AudioStreamMP3).duplicate() as AudioStreamMP3
		mp3.loop = true
		stream = mp3
	_current = key
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_fade_to(0.0, fade_in)


## 淡出停止（回主菜单/退出时用）
func stop(fade_out := FADE_OUT_SEC) -> void:
	if _player == null or not _player.playing:
		return
	_current = &""
	_fade_to(SILENT_DB, fade_out, true)


## 暂停/恢复（例如打开菜单时压低而不是静音）
func duck(level_db := -14.0, duration := 0.5) -> void:
	if _player == null:
		return
	_fade_to(level_db, duration)


func unduck(duration := 0.6) -> void:
	if _player == null:
		return
	_fade_to(0.0, duration)


func current_track() -> StringName:
	return _current


func is_playing() -> bool:
	return _player != null and _player.playing


func _fade_to(target_db: float, duration: float, stop_after := false) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if duration <= 0.01:
		_player.volume_db = target_db
		if stop_after:
			_player.stop()
		return
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", target_db, duration)
	if stop_after:
		_fade.tween_callback(_player.stop)
