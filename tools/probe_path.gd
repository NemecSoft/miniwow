extends Node

func _ready() -> void:
	var robot: Node3D = (load("res://scenes/monsters/robot_body.tscn") as PackedScene).instantiate()
	add_child(robot)
	var lib := (robot.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library(&"")
	printerr("库键名: ", ", ".join(lib.get_animation_list()))
	get_tree().quit(0)
