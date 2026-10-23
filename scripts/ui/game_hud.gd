class_name GameHud
extends Control
## HUD permanente: ubicación y controles, misión, estado de Gemini y el cartel
## de interacción.

signal settings_requested

var _quest_card: PanelContainer
var _quest_box: VBoxContainer
var _coins_label: Label
var _stats_label: Label
var _toasts: VBoxContainer
var _api_status: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _location_label: Label
var _fade: ColorRect
## Tarjetas del HUD de juego (se ocultan en la portada).
var _gameplay_nodes: Array[Control] = []
var _gameplay_shown := true
var _coins_shown := 0.0
var _coins_target := 0
var _coins_tween: Tween = null
var _flash: ColorRect = null


func setup(model_name: String) -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_location_card()
	_build_quest_card()
	_build_status_card(model_name)
	_build_coins_card()
	_build_stats_card()
	_build_toasts()
	_build_prompt()
	_build_fade()
	for child in get_children():
		if child != _fade and child is Control:
			_gameplay_nodes.append(child)


## Muestra las misiones activas (máx. 3) o `idle_text` si no hay ninguna.
## Cada entrada: {"title": String, "detail": String, "ready": bool}.
func set_quests(entries: Array, idle_text: String) -> void:
	for child in _quest_box.get_children():
		_quest_box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_quest_box.add_child(UiKit.label("ENCARGOS", 10, UiKit.INK_ACCENT))
		_quest_box.add_child(_wrapped_label(idle_text, 11, UiKit.INK))
	else:
		var shown := 0
		for entry in entries:
			if shown >= 3:
				break
			shown += 1
			var ready: bool = entry["ready"]
			_quest_box.add_child(UiKit.label(String(entry["title"]), 10, UiKit.INK_GOOD if ready else UiKit.INK_ACCENT))
			_quest_box.add_child(_wrapped_label(String(entry["detail"]), 11, UiKit.INK))
		if entries.size() > shown:
			_quest_box.add_child(UiKit.label("+ %d más" % (entries.size() - shown), 9, UiKit.INK_SOFT))
	_quest_card.reset_size.call_deferred()


## Muestra u oculta todas las tarjetas del HUD de juego (la portada las esconde).
func set_gameplay_visible(value: bool) -> void:
	_gameplay_shown = value
	for node in _gameplay_nodes:
		if is_instance_valid(node):
			node.visible = value


## Las monedas "cuentan" hasta el nuevo valor en vez de saltar de golpe.
func set_coins(amount: int) -> void:
	_coins_target = amount
	if _coins_tween != null and _coins_tween.is_valid():
		_coins_tween.kill()
	if absi(amount - int(_coins_shown)) <= 1:
		_coins_shown = float(amount)
		_coins_label.text = "MONEDAS  %d" % amount
		return
	_coins_tween = create_tween()
	_coins_tween.tween_method(_set_coins_text, _coins_shown, float(amount), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_coins_text(value: float) -> void:
	_coins_shown = value
	_coins_label.text = "MONEDAS  %d" % int(round(value))


## Rebote y destello del contador de monedas al ganar monedas.
func punch_coins() -> void:
	_coins_label.pivot_offset = Vector2(0, _coins_label.size.y / 2.0)
	var tween := _coins_label.create_tween()
	_coins_label.scale = Vector2(1.0, 1.0)
	_coins_label.modulate = Color(1.6, 0.8, 0.4)
	tween.set_parallel(true)
	tween.tween_property(_coins_label, "scale", Vector2(1.28, 1.28), 0.08).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_property(_coins_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var glow := _coins_label.create_tween()
	glow.tween_property(_coins_label, "modulate", Color.WHITE, 0.45)


## Destello de pantalla completa muy breve (momentos importantes).
func flash(color: Color = Color.WHITE, strength: float = 0.3) -> void:
	if not GameFeel.effects_enabled:
		return
	if _flash == null:
		_flash = ColorRect.new()
		UiKit.full_rect(_flash)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.z_index = 90
		add_child(_flash)
	_flash.color = Color(color.r, color.g, color.b, strength)
	var tween := _flash.create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Puntos del marcador y tiempo de juego (los calcula DBManager).
func set_stats(score: int, play_seconds: int) -> void:
	_stats_label.text = "PUNTOS  %d    ·    %s" % [score, UiKit.format_time(play_seconds)]


## Aviso breve en la esquina inferior izquierda que se desvanece solo.
func show_toast(text: String, color: Color = UiKit.COLOR_MINT) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	var margin := UiKit.margin(12, 12, 6, 6)
	panel.add_child(margin)
	margin.add_child(UiKit.label(text, 11, UiKit.on_paper(color)))
	_toasts.add_child(panel)
	# Entrada con un pequeño rebote
	panel.pivot_offset = Vector2(0, 16)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.82, 0.82)
	var enter := panel.create_tween().set_parallel(true)
	enter.tween_property(panel, "modulate:a", 1.0, 0.12)
	enter.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tween := panel.create_tween()
	tween.tween_interval(2.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func set_api_connected(connected: bool) -> void:
	if connected:
		_api_status.text = "GEMINI  /  CONECTADO"
		_api_status.add_theme_color_override("font_color", UiKit.INK_GOOD)
	else:
		_api_status.text = "GEMINI  /  MODO DEMO"
		_api_status.add_theme_color_override("font_color", UiKit.INK_ACCENT)


func show_prompt(text: String) -> void:
	if not _gameplay_shown:
		return
	var appearing := not _prompt_panel.visible
	_prompt_panel.visible = true
	_prompt_label.text = text
	if appearing:
		_prompt_panel.pivot_offset = _prompt_panel.size / 2.0
		_prompt_panel.scale = Vector2(0.88, 0.88)
		_prompt_panel.create_tween().tween_property(_prompt_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_prompt() -> void:
	_prompt_panel.visible = false


## Nombre del lugar que se muestra bajo "WILLOWMERE" (por ejemplo "BAKERY").
func set_location(place: String) -> void:
	_location_label.text = "SPRINGFALL  /  %s" % place.to_upper()


## Funde la pantalla a negro (alpha 1) o la devuelve (alpha 0). Usar con await.
func fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, duration)
	await tween.finished


func _build_location_card() -> void:
	var card := PanelContainer.new()
	card.position = Vector2(20, 18)
	card.size = Vector2(390, 80)
	card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(card)
	var margin := UiKit.margin(16, 16, 11, 11)
	card.add_child(margin)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 2)
	margin.add_child(copy)
	copy.add_child(UiKit.label("WILLOWMERE", 20, UiKit.INK))
	_location_label = UiKit.label("SPRINGFALL  /  PLAZA CENTRAL", 10, UiKit.INK_ACCENT)
	copy.add_child(_location_label)
	copy.add_child(UiKit.label(Controls.hud_hint(), 9, UiKit.INK_SOFT))


func _wrapped_label(text: String, font_size: int, color: Color) -> Label:
	var label := UiKit.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	return label


func _build_quest_card() -> void:
	_quest_card = PanelContainer.new()
	_quest_card.position = Vector2(20, 112)
	_quest_card.custom_minimum_size = Vector2(310, 0)
	_quest_card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(_quest_card)
	var margin := UiKit.margin(14, 14, 10, 10)
	_quest_card.add_child(margin)
	_quest_box = VBoxContainer.new()
	_quest_box.add_theme_constant_override("separation", 3)
	margin.add_child(_quest_box)


func _build_coins_card() -> void:
	var card := PanelContainer.new()
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -318
	card.offset_right = -20
	card.offset_top = 108
	card.offset_bottom = 148
	card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(card)
	var margin := UiKit.margin(14, 14, 8, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	_coins_label = UiKit.label("MONEDAS  0", 11, UiKit.INK_ACCENT)
	_coins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_coins_label)
	row.add_child(UiKit.label("%s  MOCHILA" % Controls.key_label(Controls.INVENTORY).to_upper(), 9, UiKit.INK_SOFT))


func _build_stats_card() -> void:
	var card := PanelContainer.new()
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -318
	card.offset_right = -20
	card.offset_top = 158
	card.offset_bottom = 198
	card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(card)
	var margin := UiKit.margin(14, 14, 8, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	_stats_label = UiKit.label("PUNTOS  0    ·    0:00", 11, UiKit.INK)
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_label)
	row.add_child(UiKit.label("%s  MARCADOR" % Controls.key_label(Controls.LEADERBOARD).to_upper(), 9, UiKit.INK_SOFT))


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = 20
	_toasts.offset_right = 340
	_toasts.offset_top = -220
	_toasts.offset_bottom = -20
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


func _build_status_card(model_name: String) -> void:
	var card := PanelContainer.new()
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -318
	card.offset_top = 18
	card.offset_right = -20
	card.offset_bottom = 98
	card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(card)
	var margin := UiKit.margin(14, 12, 11, 11)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	_api_status = UiKit.label("GEMINI  /  MODO DEMO", 11, UiKit.INK_ACCENT)
	copy.add_child(_api_status)
	copy.add_child(UiKit.label(model_name + "  ·  CHAT EN LÍNEA", 9, UiKit.INK_SOFT))
	var settings_button := UiKit.ghost_button("Ajustes")
	settings_button.custom_minimum_size = Vector2(96, 42)
	settings_button.pressed.connect(settings_requested.emit)
	row.add_child(settings_button)


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_bottom = 1.0
	_prompt_panel.offset_left = -174
	_prompt_panel.offset_top = -92
	_prompt_panel.offset_right = 174
	_prompt_panel.offset_bottom = -48
	_prompt_panel.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_panel)
	_prompt_label = UiKit.label("E   HABLAR", 12, UiKit.INK_GOOD)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.visible = false


func _build_fade() -> void:
	_fade = ColorRect.new()
	UiKit.full_rect(_fade)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.z_index = 100
	add_child(_fade)
