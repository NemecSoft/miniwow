extends Node

# 探针 v2：用字符串 API 探测 LimboAI GDExtension 加载状态
# 不用裸标识符（编译期顺序问题），全部走 ClassDB.class_exists / load

func _ready() -> void:
	var ok := true

	# 1. 主动加载 gdextension 清单（模拟编辑器发现机制）
	var gdext_path := "res://addons/limboai/bin/limboai.gdextension"
	if ResourceLoader.exists(gdext_path):
		var res: Resource = load(gdext_path)
		print("gdextension resource loaded: ", res != null, " class=", res.get_class() if res else "null")
	else:
		print("gdextension file NOT FOUND: ", gdext_path)
		ok = false

	# 2. ClassDB 字符串检查
	for cls in ["BTPlayer", "BehaviorTree", "Blackboard", "LimboState", "BTSelector", "BTSequence"]:
		var exists := ClassDB.class_exists(cls)
		print("ClassDB has '%s': %s" % [cls, exists])
		if not exists:
			ok = false

	# 3. 若类存在则实例化
	if ClassDB.class_exists("BTPlayer"):
		var player: Object = ClassDB.instantiate("BTPlayer")
		print("BTPlayer instance: ", player)
		if player == null:
			ok = false
		else:
			player.free()

	print("=== LimboAI 加载结果: %s ===" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
