extends Node

## 职业注册表（autoload）。启动时加载 resources/classes/ 下的全部职业资源。

const CLASS_PATHS := {
	"warrior": "res://resources/classes/warrior.tres",
	"mage": "res://resources/classes/mage.tres",
	"priest": "res://resources/classes/priest.tres",
	"infantry": "res://resources/classes/infantry.tres",
}

var _classes := {}


func _ready() -> void:
	for class_id in CLASS_PATHS:
		var class_data := load(CLASS_PATHS[class_id]) as ClassData
		if class_data:
			_classes[class_id] = class_data


## 注意：不能叫 get_class()——会覆盖 Object 原生方法（LevelData 同款坑）
func get_class_data(class_id: String) -> ClassData:
	return _classes.get(class_id)


func get_all_classes() -> Array:
	return _classes.values()
