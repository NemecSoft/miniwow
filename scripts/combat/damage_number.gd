class_name DamageNumber
extends Label3D

## 伤害飘字：纯表现层，收到服务器伤害广播后各客户端本地生成，互不信赖。

static func spawn(parent: Node, world_position: Vector3, amount: int, is_crit: bool, tint: Color = Color(1.0, 0.9, 0.3)) -> void:
	if parent == null:
		return
	var label := DamageNumber.new()
	label.text = str(amount)
	label.font = load("res://assets/fonts/Kurland.ttf")
	label.pixel_size = 0.09 if is_crit else 0.06
	label.modulate = Color(1.0, 0.55, 0.1) if is_crit else tint
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = world_position + Vector3(randf_range(-0.35, 0.35), randf_range(0, 0.4), randf_range(-0.35, 0.35))
	label.scale = Vector3.ONE * (1.4 if is_crit else 1.0)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector3(0, 1.4, 0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.tween_callback(label.queue_free)


## 受击抖动：原地弹一下，给"打中了"的反馈
static func shake(node: Node3D) -> void:
	if node == null:
		return
	var tween := node.create_tween()
	tween.tween_property(node, "scale", node.scale * 1.15, 0.05)
	tween.tween_property(node, "scale", node.scale, 0.08)
