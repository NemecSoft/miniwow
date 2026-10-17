extends Node

## M18b-3 诊断：打印步兵视觉切换的内部状态（为什么机器人没隐藏/Mannequin 没显示）
## 运行方式：godot --path . res://tools/probe_infantry_diag.tscn

func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player_instance := player_scene.instantiate() as CharacterBody3D
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	for i in range(30):
		await get_tree().physics_frame
	var player := players_container.get_node_or_null("1") as CharacterBody3D
	var body: Node = player.get("_body")

	printerr("=== 切换前 ===")
	_dump(body, player)
	body.set("use_alt_body", true)
	await get_tree().process_frame
	printerr("=== 切换后 ===")
	_dump(body, player)
	get_tree().quit(0)


func _dump(body: Node, player: Node) -> void:
	printerr("use_alt_body=", body.get("use_alt_body"))
	var alt := body.get("alt_visual") as Node3D
	printerr("alt_visual=", alt, " visible=", alt.visible if alt else "null")
	var ap := alt.get_node_or_null("VisualRoot/Mannequin/AnimationPlayer") if alt else null
	printerr("alt AnimationPlayer(外部查找)=", ap)
	var body_ap: AnimationPlayer = body.get("_alt_animation_player")
	printerr("Body._alt_animation_player(内部缓存)=", body_ap)
	if ap:
		printerr("  库动画数=", ap.get_animation_list().size(), " 有Idle=", ap.has_animation(&"Idle"))
	var mannequin := alt.get_node_or_null("VisualRoot/Mannequin") if alt else null
	if mannequin:
		printerr("Mannequin visible=", mannequin.visible, " pos=", (mannequin as Node3D).global_position)
		for mesh in mannequin.find_children("*", "MeshInstance3D", true, false):
			printerr("  mesh ", (mesh as MeshInstance3D).name,
				" visible=", (mesh as MeshInstance3D).is_visible_in_tree(),
				" aabb=", (mesh as MeshInstance3D).get_aabb())
	var arm := body.get_node_or_null("RobotArmature") as Node3D
	printerr("RobotArmature=", arm, " visible=", arm.visible if arm else "null")
	if arm:
		for mesh in arm.find_children("*", "MeshInstance3D", true, false):
			printerr("  robot-mesh ", (mesh as MeshInstance3D).name,
				" visible_in_tree=", (mesh as MeshInstance3D).is_visible_in_tree())
