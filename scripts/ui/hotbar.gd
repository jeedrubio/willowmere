class_name Hotbar
extends Control
## Barra rápida visible con selección por números o clic y la energía del jugador.

signal slot_selected(index: int)

const SLOT_WIDTH := 48
const SLOT_HEIGHT := 46

var _inventory: Inventory
var _energy: Energy
var _slot_panels: Array[PanelContainer] = []
var _slot_glyphs: Array[Label] = []
var _slot_counts: Array[Label] = []
var _energy_bar: ProgressBar
var _energy_label: Label
var _selected_label: Label


func setup(inventory: Inventory, energy: Energy) -> void:
	_inventory = inventory
	_energy = energy
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_inventory.changed.connect(_refresh)
	_energy.changed.connect(_on_energy_changed)
	_refresh()
	_on_energy_changed(_energy.current, Energy.MAX_ENERGY)


func set_energy(current: int, maximum: int) -> void:
	_on_energy_changed(current, maximum)


func _build() -> void:
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -218
	card.offset_top = -114
	card.offset_right = 218
	card.offset_bottom = -14
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#142336"), 12, UiKit.COLOR_BORDER, 1))
	add_child(card)
	var margin := UiKit.margin(9, 9, 7, 7)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var energy_row := HBoxContainer.new()
	energy_row.add_theme_constant_override("separation", 8)
	column.add_child(energy_row)
	_energy_label = UiKit.label("ENERGÍA  100 / 100", 9, UiKit.COLOR_MINT)
	_energy_label.custom_minimum_size = Vector2(103, 0)
	energy_row.add_child(_energy_label)
	_selected_label = UiKit.label("PICO", 9, UiKit.COLOR_ACCENT)
	_selected_label.custom_minimum_size = Vector2(112, 0)
	_selected_label.clip_text = true
	energy_row.add_child(_selected_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0
	_energy_bar.max_value = Energy.MAX_ENERGY
	_energy_bar.value = Energy.MAX_ENERGY
	_energy_bar.show_percentage = false
	_energy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_energy_bar.custom_minimum_size = Vector2(0, 11)
	energy_row.add_child(_energy_bar)

	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 3)
	column.add_child(slots_row)
	for i in Inventory.HOTBAR_SIZE:
		var slot := _build_slot(i)
		slots_row.add_child(slot)
		_slot_panels.append(slot)


func _build_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_slot_input.bind(index))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(holder)

	var key_label := UiKit.label(str(index + 1), 8, UiKit.COLOR_FAINT)
	key_label.position = Vector2(3, 1)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(key_label)

	var glyph := UiKit.label("", 16, UiKit.COLOR_TEXT)
	UiKit.full_rect(glyph)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph)
	_slot_glyphs.append(glyph)

	var count := UiKit.label("", 8, UiKit.COLOR_TEXT)
	count.anchor_left = 1.0
	count.anchor_right = 1.0
	count.anchor_top = 1.0
	count.anchor_bottom = 1.0
	count.offset_left = -22
	count.offset_right = -3
	count.offset_top = -14
	count.offset_bottom = -2
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	_slot_counts.append(count)
	return slot


func _refresh() -> void:
	if _inventory == null:
		return
	var selected_item := _inventory.selected_item()
	_selected_label.text = ItemDb.display_name(selected_item).to_upper() if not selected_item.is_empty() else "SIN OBJETO"
	for i in _slot_panels.size():
		var item_id := _inventory.hotbar[i]
		var selected := i == _inventory.selected_hotbar_slot
		var fill := Color("#274443") if selected else Color("#0E1B2B")
		var border := UiKit.COLOR_MINT if selected else UiKit.COLOR_BORDER
		_slot_panels[i].add_theme_stylebox_override("panel", UiKit.panel_style(fill, 7, border, 2 if selected else 1))
		if item_id.is_empty():
			_slot_glyphs[i].text = ""
			_slot_counts[i].text = ""
			continue
		_slot_glyphs[i].text = ItemDb.abbreviation(item_id)
		_slot_glyphs[i].add_theme_color_override("font_color", ItemDb.color(item_id))
		var amount := _inventory.count(item_id)
		_slot_counts[i].text = str(amount) if ItemDb.is_seed(item_id) else ""


func _on_energy_changed(current: int, maximum: int) -> void:
	if _energy_bar == null:
		return
	_energy_bar.max_value = maximum
	_energy_bar.value = current
	_energy_label.text = "ENERGÍA  %d / %d" % [current, maximum]
	_energy_label.add_theme_color_override("font_color", UiKit.COLOR_RED if current <= 20 else UiKit.COLOR_MINT)


func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(index)
		accept_event()
