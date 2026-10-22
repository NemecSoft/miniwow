extends Node3D

## M40：飞机模型整合（CC0Tree SM_Airplane.fbx）。
## 作为主城上空巡航的装饰飞行器：绕中心缓慢盘旋，纯表现，不参与载具骑乘逻辑。

@export var center := Vector3(0.0, 48.0, -40.0)
@export var radius := 80.0
@export var height_sway := 6.0
@export var angular_speed := 0.12

var _t := 0.0


func _ready() -> void:
	_apply_paint()


## M41：SM_Airplane.fbx 没有内嵌材质，整机只有一个 surface 且默认纯白——
## 在主城上空就是一块 17 米的白板。补银灰金属漆：有高光和明暗层次，
## 既不刺眼的白，也不是死黑（M40 短剑同款处理）。
func _apply_paint() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.70, 0.73, 0.77)
	paint.metallic = 0.60
	paint.roughness = 0.26
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		m.material_override = paint


func _process(delta: float) -> void:
	_t += delta
	global_position = center + Vector3(
		cos(_t * angular_speed) * radius,
		sin(_t * 0.1) * height_sway,
		sin(_t * angular_speed) * radius
	)
	# 机头朝向飞行方向（切线）
	rotation.y = -_t * angular_speed + PI * 0.5
