class_name LeaderboardMenu
extends Control
## Marcador de jugadores (datos del servidor SQLite local, vía el autoload DBManager).
## Muestra los 10 mejores y, si el jugador activo está más abajo, su propia fila al final.

signal closed

const TOP_ROWS := 10
## Columnas: título, ancho mínimo y alineación. La de "Jugador" ocupa el espacio sobrante.
const COLUMNS := [
	{"title": "#", "width": 40, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"title": "JUGADOR", "width": 190, "align": HORIZONTAL_ALIGNMENT_LEFT, "expand": true},
	{"title": "PUNTOS", "width": 88, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"title": "MONEDAS", "width": 88, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"title": "OBJETOS", "width": 84, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"title": "ENCARGOS", "width": 92, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"title": "TIEMPO", "width": 84, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]
const MEDAL_COLORS := [Color("#B8860B"), Color("#6C7C86"), Color("#A0522D")]

var _db: Node = null
var _table_holder: VBoxContainer
var _name_input: LineEdit


func _ready() -> void:
	_db = get_tree().root.get_node_or_null("DBManager")
	var parts := UiKit.build_modal(self, 800, 55)
	var content: VBoxContainer = parts["content"]
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	content.add_child(UiKit.modal_header("Marcador", "WILLOWMERE  /  MEJORES JUGADORES", closed.emit))
	content.add_child(UiKit.divider())

	var table_card := UiKit.section_card(content, 16, 8)
	_table_holder = VBoxContainer.new()
	_table_holder.custom_minimum_size = Vector2(0, 330)
	_table_holder.add_theme_constant_override("separation", 6)
	table_card.add_child(_table_holder)

	content.add_child(UiKit.divider())
	content.add_child(_build_player_row())
	content.add_child(UiKit.wrapped_label(
			"Cambiar de jugador reinicia las estadísticas del marcador (no la mochila ni los encargos).",
			11, UiKit.INK_FAINT, 720))

	if _db == null:
		_show_message("La base de datos no está disponible en esta escena.", UiKit.INK_BAD)
	else:
		_db.leaderboard_updated.connect(_on_leaderboard_updated)
		_show_message("Consultando el marcador...", UiKit.INK_SOFT)
		_db.consultar_leaderboard()
	UiKit.fade_in(self)


func _build_player_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption := UiKit.label("Jugador activo", 13, UiKit.INK_SOFT)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_name_input = UiKit.line_edit("Nombre del jugador", 14)
	_name_input.custom_minimum_size = Vector2(0, 42)
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.max_length = 20
	if _db != null:
		_name_input.text = String(_db.jugador_nombre)
	_name_input.text_submitted.connect(func(_text: String) -> void: _change_player())
	row.add_child(_name_input)
	var change_button := UiKit.primary_button("Cambiar jugador", 13)
	change_button.custom_minimum_size = Vector2(150, 42)
	change_button.pressed.connect(_change_player)
	row.add_child(change_button)
	var refresh_button := UiKit.ghost_button("Actualizar", 13)
	refresh_button.custom_minimum_size = Vector2(104, 42)
	refresh_button.pressed.connect(_refresh)
	row.add_child(refresh_button)
	return row


func _change_player() -> void:
	var new_name := _name_input.text.strip_edges()
	if _db == null or new_name.is_empty() or new_name == String(_db.jugador_nombre):
		return
	_name_input.release_focus()
	_show_message("Cambiando de jugador...", UiKit.INK_SOFT)
	_db.cambiar_jugador(new_name)


func _refresh() -> void:
	if _db == null:
		return
	_show_message("Consultando el marcador...", UiKit.INK_SOFT)
	_db.consultar_leaderboard()


func _clear_table() -> void:
	for child in _table_holder.get_children():
		_table_holder.remove_child(child)
		child.queue_free()


func _show_message(text: String, color: Color) -> void:
	_clear_table()
	var message := UiKit.wrapped_label(text, 14, color, 640)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_holder.add_child(message)


func _on_leaderboard_updated(rows: Array, ok: bool) -> void:
	if not ok:
		_show_message("No se pudo conectar con el servidor local.\nInicia tools/servidor_sqlite.py (puerto 8080) y pulsa Actualizar.", UiKit.INK_BAD)
		return
	if rows.is_empty():
		_show_message("Todavía no hay jugadores en el marcador.\nJuega un rato y vuelve.", UiKit.INK_SOFT)
		return
	_clear_table()
	var active_name := String(_db.jugador_nombre) if _db != null else ""

	var grid := _new_grid()
	var titles: Array = []
	for spec in COLUMNS:
		titles.append(String((spec as Dictionary)["title"]))
	_add_row(grid, titles, UiKit.INK_ACCENT, 11, {})
	var shown_active := false
	for i in mini(rows.size(), TOP_ROWS):
		var entry: Dictionary = rows[i]
		var is_active := String(entry.get("jugador", "")) == active_name
		shown_active = shown_active or is_active
		_add_entry(grid, i, entry, is_active)
	_table_holder.add_child(grid)

	# Si el jugador activo quedó fuera del top, su fila va aparte para que vea su posición.
	if not shown_active:
		for i in range(TOP_ROWS, rows.size()):
			var entry: Dictionary = rows[i]
			if String(entry.get("jugador", "")) == active_name:
				_table_holder.add_child(UiKit.divider())
				var own := _new_grid()
				_add_entry(own, i, entry, true)
				_table_holder.add_child(own)
				break


func _new_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 9)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _add_entry(grid: GridContainer, index: int, entry: Dictionary, is_active: bool) -> void:
	var seconds := int(entry.get("tiempo_segundos", 0))
	var name_text := String(entry.get("jugador", "?"))
	if is_active:
		name_text += "  (tú)"
	var cells := [
		str(index + 1),
		name_text,
		str(int(entry.get("score", 0))),
		str(int(entry.get("monedas", 0))),
		str(int(entry.get("coleccionables", 0))),
		str(int(entry.get("misiones", 0))),
		UiKit.format_time(seconds),
	]
	var color := UiKit.INK_GOOD if is_active else UiKit.INK
	var overrides := {}
	if index < MEDAL_COLORS.size():
		overrides[0] = MEDAL_COLORS[index]
	_add_row(grid, cells, color, 14, overrides)


## Añade una fila de celdas a la rejilla. `overrides` cambia el color de columnas concretas.
func _add_row(grid: GridContainer, cells: Array, color: Color, font_size: int, overrides: Dictionary) -> void:
	for column in COLUMNS.size():
		var spec: Dictionary = COLUMNS[column]
		var cell_color := color
		if overrides.has(column):
			cell_color = overrides[column]
		var cell := UiKit.label(String(cells[column]), font_size, cell_color)
		cell.custom_minimum_size = Vector2(float(spec["width"]), 0)
		cell.horizontal_alignment = spec["align"]
		cell.clip_text = true
		if bool(spec.get("expand", false)):
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		closed.emit()
