extends Node

## 怪物注册表（autoload）。启动时扫描 resources/monsters/ 下全部 .tres。

var _monsters := {}


func _ready() -> void:
	var dir := DirAccess.open("res://resources/monsters")
	if dir == null:
		push_error("MonsterDatabase: 找不到 res://resources/monsters 目录")
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var data := load("res://resources/monsters/" + file_name) as MonsterData
		if data and not data.id.is_empty():
			_monsters[data.id] = data
	print("MonsterDatabase: 已加载 %d 种怪物" % _monsters.size())


func get_monster(monster_id: String) -> MonsterData:
	return _monsters.get(monster_id)


func get_all_monsters() -> Array:
	return _monsters.values()
