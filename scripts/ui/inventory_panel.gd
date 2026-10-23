class_name InventoryPanel
extends Control
## Ventana de la mochila: cuadrícula de casillas, monedas y detalle del objeto
## bajo el cursor. Se abre y cierra desde Main (tecla del Input Map "inventory").

const COLUMNS := 6
const SLOT_SIZE := 64

var _inventory: Inventory
var _icons: Array[TextureRect] = []
var _glyphs: Array[Label] = []
var _counts: Array[Label] = []
var _coins_label: Label
var _detail_name: Label
var _detail_desc: Label


func setup(inventory: Inventory) -> void:
	_inventory = inventory
	visible = false

	var parts := UiKit.build_modal(self, 0, 30, 0.6)
	var column: VBoxContainer = parts["content"]
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	var header := UiKit.modal_header("Mochila", "COSECHAS Y RECOMPENSAS", close)
	_coins_label = UiKit.label("", 15, UiKit.INK_ACCENT)
	_coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_coins_label)
	header.move_child(_coins_label, header.get_child_count() - 2)
	column.add_child(header)
	column.add_child(UiKit.divider())

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for i in Inventory.SLOT_COUNT:
		grid.add_child(_build_slot(i))

	column.add_child(UiKit.divider())
	_detail_name = UiKit.label("", 15, UiKit.INK)
	column.add_child(_detail_name)
	_detail_desc = UiKit.label("", 13, UiKit.INK_SOFT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE + 6), 38)
	column.add_child(_detail_desc)
	column.add_child(UiKit.label("I / ESC  CERRAR", 11, UiKit.INK_FAINT))

	_inventory.changed.connect(_refresh)
	_refresh()


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func open() -> void:
	_refresh()
	_show_detail(-1)
	visible = true


func close() -> void:
	visible = false


func _build_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#E9BE8A"), 3, UiKit.INK, 2))
	slot.mouse_entered.connect(_show_detail.bind(index))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(holder)

	var icon := TextureRect.new()
	UiKit.full_rect(icon)
	icon.offset_left = 7
	icon.offset_top = 5
	icon.offset_right = -7
	icon.offset_bottom = -9
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	_icons.append(icon)

	var glyph := UiKit.label("", 18, Color.WHITE)
	UiKit.full_rect(glyph)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph)
	_glyphs.append(glyph)

	var count := UiKit.label("", 12, UiKit.INK)
	count.anchor_left = 1.0
	count.anchor_right = 1.0
	count.anchor_top = 1.0
	count.anchor_bottom = 1.0
	count.offset_left = -30
	count.offset_right = -5
	count.offset_top = -19
	count.offset_bottom = -3
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_color_override("font_outline_color", UiKit.PAPER_LIGHT)
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	_counts.append(count)
	return slot


func _refresh() -> void:
	if _inventory == null or _icons.is_empty():
		return
	_coins_label.text = "MONEDAS  %d" % _inventory.coins
	for i in Inventory.SLOT_COUNT:
		var slot: Dictionary = _inventory.slots[i]
		if slot.is_empty():
			_icons[i].texture = null
			_glyphs[i].text = ""
			_counts[i].text = ""
			continue
		var id := String(slot["id"])
		var texture := ItemDb.icon(id)
		_icons[i].texture = texture
		if texture == null:
			_glyphs[i].text = ItemDb.abbreviation(id)
			_glyphs[i].add_theme_color_override("font_color", ItemDb.color(id))
		else:
			_glyphs[i].text = ""
		var amount := int(slot["count"])
		_counts[i].text = str(amount) if amount > 1 else ""


func _show_detail(index: int) -> void:
	if index < 0 or index >= _inventory.slots.size() or _inventory.slots[index].is_empty():
		_detail_name.text = ""
		_detail_desc.text = "Pasa el cursor sobre un objeto para ver su descripción."
		return
	var id := String(_inventory.slots[index]["id"])
	_detail_name.text = ItemDb.display_name(id)
	_detail_desc.text = ItemDb.description(id)
