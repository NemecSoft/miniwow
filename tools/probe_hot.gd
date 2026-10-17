extends Node

## HOT 诊断探针：直接 add_hot 验证 AttributeSet._physics_process 是否 tick

func _ready() -> void:
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player := player_scene.instantiate() as Character
	player.name = "1"
	get_tree().root.add_child.call_deferred(player)
	for i in range(30):
		await get_tree().process_frame
	var attrs := player.attribute_set
	print("PROBE: is_server=%s effects初始=%d" % [multiplayer.is_server(), attrs._effects.size()])
	attrs.apply_damage(60)
	var start_hp: int = attrs.hp
	attrs.add_hot(4, 5, 0.5)
	print("PROBE: add_hot后 effects=%d start_hp=%d max_hp=%d" % [attrs._effects.size(), start_hp, attrs.max_hp])
	for i in range(120):
		await get_tree().process_frame
		if i % 30 == 29:
			print("PROBE: 帧%d hp=%d effects=%d" % [i, attrs.hp, attrs._effects.size()])
	print("PROBE: 最终 hp=%d（起始 %d）" % [attrs.hp, start_hp])
	get_tree().quit(0)
