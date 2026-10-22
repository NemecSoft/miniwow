extends Node

## M43 探针：验证背景音乐真的在播、循环属性已开、Music 总线存在。
func _ready() -> void:
	var idx := AudioServer.get_bus_index(&"Music")
	printerr("BGM: Music 总线 idx=", idx, " db=", AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0)
	var s := load("res://assets/audio/music/bgm_village.ogg") as AudioStream
	printerr("BGM: 资源类=", s.get_class() if s != null else "null", " 时长=", snappedf(s.get_length(), 0.01) if s != null else 0.0)
	await get_tree().create_timer(2.0).timeout
	printerr("BGM: playing=", MusicPlayer.is_playing(), " track=", MusicPlayer.current_track())
	var p := MusicPlayer.get_node_or_null("BgmPlayer") as AudioStreamPlayer
	if p != null and p.stream != null:
		var ls = p.stream.get("loop")
		printerr("BGM: 播放器 bus=", p.bus, " stream.loop=", str(ls), " volume_db=", snappedf(p.volume_db, 0.1))
		printerr("BGM: position=", snappedf(p.get_playback_position(), 0.01), "/", snappedf(p.stream.get_length(), 0.01))
	printerr("BGM: AudioSettings.music=", AudioSettings.music_volume)
	printerr("BGM: 结束")
	get_tree().quit(0)
