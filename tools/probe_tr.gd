extends SceneTree

func _init() -> void:
	var t_zh := Translation.new()
	t_zh.locale = "zh_CN"
	t_zh.add_message("创建主机", "创建主机")
	TranslationServer.add_translation(t_zh)
	var t_en := Translation.new()
	t_en.locale = "en_US"
	t_en.add_message("创建主机", "Create Host")
	TranslationServer.add_translation(t_en)

	TranslationServer.set_locale("en_US")
	var scene := load("res://scenes/ui/main_menu_ui.tscn") as PackedScene
	var ui := scene.instantiate()
	root.add_child(ui)
	var host_button := ui.get_node("MainContainer/MainMenu/Buttons/Host") as Button
	print("tscn Host button = ", host_button.text)

	# 再测 locale 切换时 tscn 文本是否刷新
	TranslationServer.set_locale("zh_CN")
	print("after switch Host button = ", host_button.text)
	TranslationServer.set_locale("en_US")
	print("after switch back Host button = ", host_button.text)

	# 运行时创建 Label：先入树再设属性
	var label := Label.new()
	root.add_child(label)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	label.text = "创建主机"
	print("runtime label (in-tree then set) = ", label.text)
	quit(0)
