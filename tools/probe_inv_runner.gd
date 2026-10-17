extends Node

func _ready() -> void:
	var scene := load("res://scenes/level/player.tscn") as PackedScene
	var player := scene.instantiate()
	player.name = "1"
	get_tree().root.add_child.call_deferred(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var inv: Object = player.get("player_inventory")
	print("PROBE: 激活格数=%d 初始空格=%d" % [inv.get_active_slot_count(), inv.get_first_empty_slot()])
	var bone := ItemDatabase.get_item("bone")
	print("PROBE: bone stackable=%s max_stack=%s id=%s" % [
		str(bone.stackable), str(bone.max_stack), bone.id])
	for i in range(20):
		var remaining: int = inv.add_item(bone, 1)
		var empty_slot: int = inv.get_first_empty_slot()
		print("PROBE: 第%02d次 add bone remaining=%d 空格位=%d" % [i, remaining, empty_slot])
		if empty_slot < 0:
			break
	# 逐格状态
	for i in range(inv.get_active_slot_count()):
		var slot: Object = inv.get_slot(i)
		print("PROBE: 槽%d item_id='%s' qty=%d" % [i, str(slot.get("item_id")), int(slot.get("quantity"))])
	get_tree().quit(0)
