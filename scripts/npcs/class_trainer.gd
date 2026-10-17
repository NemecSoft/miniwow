class_name ClassTrainer
extends CharacterBody3D

## MiniWoW 职业训练师 NPC（M5）：村里的职业选择/重选点（职业训练师·薇拉）。
## 与商人/任务官同模式：静态、不可被打、无 AI；level.gd 每帧检测距离，3 米内弹"按 E 交谈"提示。
## 服务器与所有客户端各自实例化（挂在 level.tscn Environment 下），外观本地计算。

const PALETTE_PATH := "res://assets/characters/player/GodotRobotPaletteSwap/GodotPurplePalette.png"

@onready var anim_player: AnimationPlayer = $GodotRobot3D/AnimationPlayer


func _ready() -> void:
	add_to_group("class_trainers")
	_apply_skin()
	if anim_player and anim_player.has_animation(&"Idle"):
		anim_player.play(&"Idle")


func _apply_skin() -> void:
	var texture := load(PALETTE_PATH) as Texture2D
	if texture == null:
		return
	var skeleton := $GodotRobot3D/RobotArmature/Skeleton3D
	if skeleton == null:
		return
	for mesh_name in ["Bottom", "Chest", "Face", "LimbsAndHead"]:
		var mesh := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			var material := StandardMaterial3D.new()
			material.albedo_texture = texture
			mesh.set_surface_override_material(0, material)
