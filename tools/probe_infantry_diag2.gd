extends Node

## M18b-3 诊断2：全树扫描玩家下全部 MeshInstance3D + 全局位置，找出隐藏 armature 后
## 仍然渲染的红蓝机器人是谁。
## 运行方式：godot --path . res://tools/probe_infantry_diag2.tscn

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
	body.set("use_alt_body", true)
	player.global_position = Vector3(40, 0.2, 40)
	await get_tree().process_frame
	await get_tree().process_frame

	printerr("玩家 global=", player.global_position)
	printerr("=== 玩家全树 MeshInstance3D（visible_in_tree=true 的）===")
	for mesh in player.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.is_visible_in_tree():
			printerr("  ", m.global_position, " ", m.get_path_to(m), " aabb=", m.get_aabb())
	printerr("=== GodotRobot3D 子树 MeshInstance（含隐藏）===")
	var robot3d: Node = player.get_node("GodotRobot3D")
	for mesh in robot3d.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		printerr("  visible=", m.is_visible_in_tree(), " pos=", m.global_position,
			" path=", robot3d.get_path_to(m))
	printerr("=== 玩家下所有子节点（顶层）===")
	for child in player.get_children():
		printerr("  ", child.name, " [", child.get_class(), "]")
	_extra_dump(body)
	get_tree().quit(0)

func _extra_dump(body: Node) -> void:
	var alt := body.get("alt_visual") as Node3D
	for mesh in alt.find_children("MannequinLarge_*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		var surf0 := m.get_active_material(0)
		printerr("MESH ", m.name, " override=", m.material_override,
			" active0=", surf0, " rd=", surf0.resource_path if surf0 else "none")
