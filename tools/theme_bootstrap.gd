@tool
extends Node
## M22 临时引导：编辑器模式下自动执行 ThemeGen 主题生成后退出。
## 生成完成后本 autoload 将从 project.godot 移除（一次性脚手架，不随项目发布）。

const THEME_SCRIPTS := [
	"res://themes/wow_theme.gd",
	"res://themes/sc2_theme.gd",
]


func _ready() -> void:
	if not Engine.is_editor_hint():
		return  # 运行时零开销（本 autoload 本来就是临时的）
	_run_gen.call_deferred()


func _run_gen() -> void:
	var ok := true
	for path in THEME_SCRIPTS:
		print("=== ThemeGen 生成：%s ===" % path)
		var script: Script = load(path)
		if script == null:
			push_error("主题脚本加载失败：%s" % path)
			ok = false
			continue
		var gen = script.new()  # 编辑器上下文允许实例化 EditorScript 子类
		gen._run()
	print("=== 主题生成完成（ok=%s）===" % ok)
	get_tree().quit(0 if ok else 1)
