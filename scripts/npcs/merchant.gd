class_name Merchant
extends CharacterBody3D

## MiniWoW 商人 NPC（M3）：村庄里的静态交易入口。
## 本身不可被打、无 AI；level.gd 每帧检测本地玩家距离，3 米内弹出"按 E 交易"提示。
## 服务器与所有客户端各自实例化（挂在 level.tscn  Environment 下），外观本地计算。

const PALETTE_PATH := "res://assets/characters/player/GodotRobotPaletteSwap/GodotYellowPalette.png"

@onready var anim_player: AnimationPlayer = $GodotRobot3D/AnimationPlayer


func _ready() -> void:
	add_to_group("merchants")
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
