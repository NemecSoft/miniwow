extends Node

## 诊断：列出 Animation 的 key 读取相关方法（4.7 API 名）

func _ready() -> void:
	var anim := Animation.new()
	var methods := anim.get_method_list()
	for m in methods:
		var name: String = m["name"]
		if name.contains("key") or name.contains("interp") or name.contains("sample"):
			printerr("METHOD: ", name)
	get_tree().quit(0)
