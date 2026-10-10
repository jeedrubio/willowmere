class_name DialoguePanel
extends PanelContainer
## Ventana de conversación con un aldeano: cabecera, historial con scroll,
## campo de texto y botón de enviar. No sabe nada de Gemini ni de la misión;
## avisa con señales y Main decide qué hacer.

signal message_submitted(text: String)
signal close_requested

var _name_label: Label
var _role_label: Label
var _status_label: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _message_input: LineEdit
var _send_button: Button
var _typing_row: Control = null
var _api_ready := false
var _busy := false


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -475
	offset_top = -292
	offset_right = 475
	offset_bottom = -18
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiKit.panel_style(Color("#101C2B"), 15, Color("#496477"), 1))

	var margin := UiKit.margin(17, 17, 14, 14)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)

	content.add_child(_build_header())

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = UiKit.COLOR_BORDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 102)
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	_scroll.add_child(_list)

	var input_row := HBoxContainer.new()
	input_row.custom_minimum_size = Vector2(0, 40)
	input_row.add_theme_constant_override("separation", 8)
	content.add_child(input_row)
	_message_input = UiKit.line_edit("Dile algo a este aldeano...", 12)
	_message_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_input.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_message_input)
	_send_button = UiKit.primary_button("Enviar  ↗", 11)
	_send_button.custom_minimum_size = Vector2(93, 38)
	_send_button.pressed.connect(_submit)
	input_row.add_child(_send_button)

	visible = false


## Abre la ventana con el saludo inicial del personaje.
func open_with(npc_name: String, npc_role: String, greeting: String, api_ready: bool) -> void:
	for child in _list.get_children():
		child.free()
	_typing_row = null
	_name_label.text = npc_name.to_upper()
	_role_label.text = npc_role.to_upper()
	_busy = false
	_api_ready = api_ready
	_refresh_status()
	_refresh_input_state()
	visible = true
	add_line(npc_name, greeting, false, false)
	_message_input.clear()
	_message_input.grab_focus()
	_scroll_to_bottom()


func close() -> void:
	hide_typing()
	_busy = false
	_refresh_input_state()
	visible = false


func set_api_ready(api_ready: bool) -> void:
	_api_ready = api_ready
	_refresh_status()


func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh_status()
	_refresh_input_state()


func add_line(speaker: String, text: String, from_player: bool, is_error: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	if from_player:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(320 if from_player else 390, 0)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if from_player else Control.SIZE_SHRINK_BEGIN
	var fill_color := Color("#23424A") if from_player else Color("#1A2B3A")
	var border_color := Color("#467D78") if from_player else Color("#365368")
	if is_error:
		fill_color = Color("#382731")
		border_color = Color("#875060")
	bubble.add_theme_stylebox_override("panel", UiKit.panel_style(fill_color, 9, border_color, 1))
	var margin := UiKit.margin(11, 11, 7, 7)
	bubble.add_child(margin)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	margin.add_child(copy)
	var speaker_color := UiKit.COLOR_MINT
	if is_error:
		speaker_color = UiKit.COLOR_RED
	elif from_player:
		speaker_color = UiKit.COLOR_ACCENT
	copy.add_child(UiKit.label(speaker.to_upper(), 9, speaker_color))
	var body := UiKit.label(text, 12, Color("#FFD8D3") if is_error else UiKit.COLOR_TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	row.add_child(bubble)
	if not from_player:
		var end_space := Control.new()
		end_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(end_space)
	_list.add_child(row)
	_scroll_to_bottom()


func show_typing() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_typing_row = row
	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(170, 31)
	bubble.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#1A2B3A"), 9, UiKit.COLOR_BORDER, 1))
	var margin := UiKit.margin(10, 10, 5, 5)
	bubble.add_child(margin)
	margin.add_child(UiKit.label("Pensando con Gemini...", 10, UiKit.COLOR_MUTED))
	row.add_child(bubble)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_list.add_child(row)
	_scroll_to_bottom()


func hide_typing() -> void:
	if is_instance_valid(_typing_row):
		_typing_row.free()
	_typing_row = null


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 42)
	header.add_theme_constant_override("separation", 10)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(39, 39)
	avatar.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#3E5A5B"), 11, UiKit.COLOR_MINT, 1))
	var symbol := UiKit.label("✦", 20, UiKit.COLOR_MINT)
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(symbol)
	header.add_child(avatar)

	var name_copy := VBoxContainer.new()
	name_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_copy.add_theme_constant_override("separation", 1)
	header.add_child(name_copy)
	_name_label = UiKit.label("ALDEANO", 15, UiKit.COLOR_TEXT)
	name_copy.add_child(_name_label)
	_role_label = UiKit.label("", 10, UiKit.COLOR_ACCENT)
	name_copy.add_child(_role_label)

	_status_label = UiKit.label("ENLACE GEMINI", 10, UiKit.COLOR_MINT)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status_label)

	var close_button := UiKit.ghost_button("Esc  ×")
	close_button.custom_minimum_size = Vector2(67, 31)
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)
	return header


func _on_text_submitted(_text: String) -> void:
	_submit()


func _submit() -> void:
	if _busy:
		return
	var text := _message_input.text.strip_edges()
	if text.is_empty():
		return
	_message_input.clear()
	add_line("Tú", text, true, false)
	message_submitted.emit(text)


func _refresh_status() -> void:
	if _busy:
		_status_label.text = "ENLACE GEMINI  ·  PENSANDO..."
	elif _api_ready:
		_status_label.text = "ENLACE GEMINI  ·  LISTO"
	else:
		_status_label.text = "MODO DEMO  ·  FALTA LA CLAVE"
	_status_label.add_theme_color_override("font_color", UiKit.COLOR_MINT if _api_ready else UiKit.COLOR_ACCENT)


func _refresh_input_state() -> void:
	_send_button.disabled = _busy
	_send_button.text = "Pensando..." if _busy else "Enviar  ↗"
	_message_input.editable = not _busy


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
