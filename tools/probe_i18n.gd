extends SceneTree

# 一次性探测脚本：确认 Node.auto_translate_mode 属性在 4.7.2 是否存在

func _init() -> void:
	var props := ClassDB.class_get_property_list("Node", true)
	var found := false
	for p in props:
		if str(p.name) == "auto_translate_mode":
			found = true
			print("PROBE auto_translate_mode FOUND: ", p)
	if not found:
		print("PROBE auto_translate_mode NOT FOUND")
	# 顺带探测 Control 的 text 属性是否带 translation 标记
	var ctrl_props := ClassDB.class_get_property_list("Label", true)
	for p in ctrl_props:
		if str(p.name) == "text":
			print("PROBE Label.text: ", p)
	quit(0)
