class_name TradePanel
extends Control
## Ventana de comercio accesible desde la conversación con cualquier aldeano.

signal buy_seed_requested(seed_id: String)
signal sell_crop_requested(crop_id: String)
signal close_requested

const CROP_IDS := ["strawberry", "leek", "potato", "onion"]

var _inventory: Inventory
var _seller_name := ""
var _buy_buttons: Dictionary = {}
var _sell_buttons: Dictionary = {}


func setup(inventory: Inventory, seller_name: String) -> void:
	_inventory = inventory
	_seller_name = seller_name
	UiKit.full_rect(self)
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_inventory.changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var shade := ColorRect.new()
	UiKit.full_rect(shade)
	shade.color = Color(0.02, 0.05, 0.08, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.COLOR_CARD, 15, Color("#55717D"), 1))
	center.add_child(panel)
	var margin := UiKit.margin(22, 22, 18, 18)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(UiKit.label("MERCADO DE %s" % _seller_name.to_upper(), 17, UiKit.COLOR_TEXT))
	heading.add_child(UiKit.label("SEMILLAS Y COSECHAS", 9, UiKit.COLOR_ACCENT))
	header.add_child(heading)
	var close_button := UiKit.ghost_button("ESC  ×")
	close_button.custom_minimum_size = Vector2(72, 32)
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)
	content.add_child(UiKit.divider())

	content.add_child(UiKit.label("COMPRAR SEMILLAS · PAQUETES DE %d" % ItemDb.SEED_PACK_AMOUNT, 10, UiKit.COLOR_MINT))
	var seed_grid := GridContainer.new()
	seed_grid.columns = 2
	seed_grid.add_theme_constant_override("h_separation", 8)
	seed_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(seed_grid)
	for seed_id in ItemDb.SEED_TO_CROP:
		var button := UiKit.ghost_button("")
		button.custom_minimum_size = Vector2(270, 38)
		button.pressed.connect(_on_buy_pressed.bind(String(seed_id)))
		seed_grid.add_child(button)
		_buy_buttons[String(seed_id)] = button

	content.add_child(UiKit.divider())
	content.add_child(UiKit.label("VENDER COSECHAS · PRECIO POR UNIDAD", 10, UiKit.COLOR_ACCENT))
	var crop_grid := GridContainer.new()
	crop_grid.columns = 2
	crop_grid.add_theme_constant_override("h_separation", 8)
	crop_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(crop_grid)
	for crop_id in CROP_IDS:
		var button := UiKit.ghost_button("")
		button.custom_minimum_size = Vector2(270, 38)
		button.pressed.connect(_on_sell_pressed.bind(crop_id))
		crop_grid.add_child(button)
		_sell_buttons[crop_id] = button

	content.add_child(UiKit.label("Las herramientas se seleccionan con 1–8. Usa E junto a una parcela.", 9, UiKit.COLOR_FAINT))


func _refresh() -> void:
	if _inventory == null:
		return
	for seed_id in _buy_buttons:
		var button := _buy_buttons[seed_id] as Button
		button.text = "%d × %s  ·  %d monedas" % [ItemDb.SEED_PACK_AMOUNT, ItemDb.display_name(seed_id), ItemDb.SEED_PACK_PRICE]
		button.disabled = _inventory.coins < ItemDb.SEED_PACK_PRICE
	for crop_id in _sell_buttons:
		var amount := _inventory.count(String(crop_id))
		var button := _sell_buttons[crop_id] as Button
		button.text = "Vender 1 %s (x%d)  ·  %d c/u" % [ItemDb.display_name(String(crop_id)), amount, ItemDb.sell_price(String(crop_id))]
		button.disabled = amount <= 0


func _on_buy_pressed(seed_id: String) -> void:
	buy_seed_requested.emit(seed_id)


func _on_sell_pressed(crop_id: String) -> void:
	sell_crop_requested.emit(crop_id)


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_requested.emit()
