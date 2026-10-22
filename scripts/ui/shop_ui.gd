class_name ShopUI
extends CanvasLayer

## MiniWoW 商店界面（M3）：靠近商人按 E 打开。
## 左侧商品（买入价=物品价值），右侧背包（卖出价=价值一半）。
## 买卖全部走 RPC 到服务器权威结算；刷新由 level.update_local_inventory_display 驱动。

signal shop_closed

## 商人商品清单（按 id 引用 ItemDatabase，价格取物品价值）。
## M43：数据源上移到 ItemDatabase.MERCHANT_STOCK——服务端 request_buy_item 要用同一份
## 白名单做校验，两边共用避免"界面改了货架、服务端还认旧表"的错位。
const SHOP_STOCK: Array[String] = ItemDatabase.MERCHANT_STOCK

var current_player: Character = null

@onready var gold_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleBar/GoldLabel
@onready var stock_grid: GridContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/ItemLists/StockPanel/MarginContainer/VBoxContainer/ScrollContainer/StockGrid
@onready var sell_grid: GridContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/ItemLists/SellPanel/MarginContainer/VBoxContainer/ScrollContainer/SellGrid
@onready var sell_empty_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/ItemLists/SellPanel/MarginContainer/VBoxContainer/EmptyLabel
@onready var close_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var interact_prompt: Label = $InteractPrompt


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	visible = false
	interact_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func open_shop(player: Character) -> void:
	current_player = player
	if player and not player.gold_changed.is_connected(_on_gold_changed):
		player.gold_changed.connect(_on_gold_changed)
	refresh()
	visible = true


func close_shop() -> void:
	visible = false
	if current_player and current_player.gold_changed.is_connected(_on_gold_changed):
		current_player.gold_changed.disconnect(_on_gold_changed)
	current_player = null


func refresh() -> void:
	if current_player == null:
		return
	gold_label.text = tr("金币: %d") % current_player.gold
	_build_stock_grid()
	_build_sell_grid()


func set_prompt_visible(value: bool) -> void:
	interact_prompt.visible = value and not visible


func _on_close_pressed() -> void:
	close_shop()
	shop_closed.emit()


func _on_gold_changed(total: int) -> void:
	gold_label.text = tr("金币: %d") % total


func _build_stock_grid() -> void:
	for child in stock_grid.get_children():
		child.queue_free()
	for item_id in SHOP_STOCK:
		var item := ItemDatabase.get_item(item_id)
		if item == null:
			continue
		var button := _create_item_button(item, item.value, item.value > current_player.gold)
		button.pressed.connect(func(): _on_buy_pressed(item))
		stock_grid.add_child(button)


func _build_sell_grid() -> void:
	for child in sell_grid.get_children():
		child.queue_free()
	sell_empty_label.visible = true
	if current_player == null or current_player.get_inventory() == null:
		return
	var inventory := current_player.get_inventory()
	for i in range(inventory.get_active_slot_count()):
		var slot := inventory.get_slot(i)
		if slot.is_empty():
			continue
		var item := ItemDatabase.get_item(slot.item_id)
		if item == null or item.value <= 0:
			continue
		sell_empty_label.visible = false
		var slot_index := i # lambda 捕获中间变量，避免循环变量共享
		var button := _create_item_button(item, item.get_sell_price(), false)
		button.pressed.connect(func(): _on_sell_pressed(slot_index))
		sell_grid.add_child(button)


func _create_item_button(item: Item, price: int, is_disabled: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(210, 52)
	button.disabled = is_disabled

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = tr(item.name)
	name_label.add_theme_color_override("font_color", item.get_rarity_color())
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var price_label := Label.new()
	price_label.text = tr("%d 金币") % price
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	vbox.add_child(price_label)
	hbox.add_child(vbox)

	button.add_child(hbox)
	return button


func _on_buy_pressed(item: Item) -> void:
	if current_player == null:
		return
	current_player.request_buy_item.rpc_id(1, item.id)
	refresh() # 服务器权威值随后经 sync_inventory_to_owner/sync_player_gold 再次刷新


func _on_sell_pressed(slot_index: int) -> void:
	if current_player == null:
		return
	current_player.request_sell_item.rpc_id(1, slot_index)
	refresh()
