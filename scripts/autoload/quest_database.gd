extends Node

## MiniWoW 任务数据库（M4）：启动时扫描 resources/quests/*.tres 自动注册。
## 与 MonsterDatabase 同模式：数据驱动，新增任务不改代码。

var quests: Dictionary = {} # id -> QuestData


func _ready() -> void:
	var dir := DirAccess.open("res://resources/quests")
	if dir == null:
		push_warning("QuestDatabase: 无法打开 resources/quests 目录")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := "res://resources/quests/" + file_name
			var quest := load(path) as QuestData
			if quest and not quest.id.is_empty():
				quests[quest.id] = quest
			else:
				push_warning("QuestDatabase: 跳过无效任务资源 " + path)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("QuestDatabase: 已注册 %d 个任务" % quests.size())


func get_quest(quest_id: String) -> QuestData:
	return quests.get(quest_id) as QuestData


func get_all_quests() -> Array:
	return quests.values()
