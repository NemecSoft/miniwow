extends Node3D
## M39 诊断探针 2：bot 飞抵狩猎区后的行为链追踪（长跑 180s，每 5s 一行）。
##
## 关注点：
##   1. 黑板 quest_id / target_monster_id / target_node 的真实值与类型
##   2. bot 到目标怪的实测水平距离与 3D 距离
##   3. bot 的骑乘状态、位置、任务进度
##
## 用法（headless）：godot --headless --path . res://tools/m39_diag2.tscn

const MONSTERS_PATH := "Environment/Monsters"
const RUN_SEC := 180.0

var _level: Node3D
var _t := 0.0


func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	level._on_host_pressed("诊断员", "blue")
	await get_tree().create_timer(3.0).timeout
	while _t < RUN_SEC:
		await get_tree().create_timer(5.0).timeout
		_t += 5.0
		_trace()
	printerr("DIAG2: 结束")
	get_tree().quit(0)


func _trace() -> void:
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return
	for child in container.get_children():
		if not str(child.name).begins_with("90"):
			continue
		var b := child as Node3D
		var p := b.global_position
		var ride = b.get("mounted_vehicle")
		var bt := b.get_node_or_null("BTPlayer")
		var bb = bt.get("blackboard") if bt != null else null
		var qid := "-"
		var tmid := "-"
		var tnode := "-"
		var tdist := -1.0
		var tdy := 0.0
		if bb != null:
			qid = str(bb.get_var(&"quest_id", "<unset>"))
			tmid = str(bb.get_var(&"target_monster_id", "<unset>"))
			var tn = bb.get_var(&"target_node", null)
			if is_instance_valid(tn):
				var t3 := tn as Node3D
				tnode = str(tn.name)
				tdist = snappedf(Vector2(p.x, p.z).distance_to(
					Vector2(t3.global_position.x, t3.global_position.z)), 0.1)
				tdy = snappedf(p.y - t3.global_position.y, 0.1)
		printerr("DIAG2: t=" + str(int(_t)) + "s " + str(b.name)
			+ " pos=(" + str(int(p.x)) + "," + str(snappedf(p.y, 0.1)) + "," + str(int(p.z)) + ")"
			+ " 距村=" + str(int(Vector2(p.x, p.z).distance_to(Vector2(0, -130)))) + "m"
			+ " 骑=" + str(ride != null)
			+ " qid=" + qid + " tmid=" + tmid + " tgt=" + tnode
			+ " 水平=" + str(tdist) + "m dy=" + str(tdy)
			+ " 进度=" + str(b.get("_quest_progress")))
