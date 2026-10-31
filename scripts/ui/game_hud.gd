class_name GameHud
extends Control
## HUD permanente: ubicación, misiones, indicadores de juego y cartel de interacción.

signal leaderboard_requested
signal inventory_requested

## UI size multiplier whenever mobile controls are enabled; editable on the HUD node in the Inspector.
@export_range(1.0, 3.0, 0.05) var mobile_ui_scale := 1.6

const TOP_PANEL_LEFT_WIDTH := 390.0
const TOP_PANEL_COINS_WIDTH := 144.0
const TOP_PANEL_STATS_WIDTH := 188.0
const TOP_PANEL_METRICS_GAP := 8.0
const TOP_PANEL_RIGHT_WIDTH := TOP_PANEL_COINS_WIDTH + TOP_PANEL_METRICS_GAP + TOP_PANEL_STATS_WIDTH
const TOP_PANEL_METRICS_HEIGHT := 36.0
const TOP_PANEL_SIDE_MARGIN := 20.0
const TOP_PANEL_COLUMN_GAP := 24.0
const TOP_PANEL_TOP_MARGIN := 18.0
const TOP_PANEL_VERTICAL_GAP := 10.0
const TOP_PANEL_QUEST_GAP := 14.0

var _location_card: PanelContainer
var _quest_card: PanelContainer
var _quest_box: VBoxContainer
var _coins_card: PanelContainer
var _stats_card: PanelContainer
var _coins_label: Label
var _stats_label: Label
var _toasts: VBoxContainer
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _location_label: Label
var _fade: ColorRect
var _prompt_text := ""
var _prompt_action: StringName = &""
var _prompt_button_label := ""
var _mobile_controls_enabled := false
var _mobile_ui_scale_applied := false
var _applied_mobile_ui_scale := 1.0
## Tarjetas del HUD de juego (se ocultan en la portada).
var _gameplay_nodes: Array[Control] = []
var _gameplay_shown := true
var _coins_shown := 0.0
var _coins_target := 0
var _coins_tween: Tween = null
var _flash: ColorRect = null


func setup() -> void:
	_mobile_controls_enabled = GameFeel.mobile_controls_enabled
	UiKit.set_mobile_ui_enabled(_mobile_controls_enabled, mobile_ui_scale)
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_location_card()
	_build_quest_card()
	_build_coins_card()
	_build_stats_card()
	_set_metric_panels_interactive(_mobile_controls_enabled)
	_build_toasts()
	_build_prompt()
	_build_fade()
	for child in get_children():
		if child != _fade and child is Control:
			_gameplay_nodes.append(child)
	resized.connect(_layout_mobile_top_panels)
	_layout_mobile_top_panels()


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
	_refresh_prompt_visibility()


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


func show_prompt(text: String, action: StringName = &"", mobile_label: String = "") -> void:
	_prompt_text = text
	_prompt_action = action
	_prompt_button_label = mobile_label
	_prompt_label.text = text
	var appearing := _should_show_prompt() and not _prompt_panel.visible
	_refresh_prompt_visibility()
	if appearing:
		var base_scale := UiKit.mobile_ui_scale_factor
		_prompt_panel.pivot_offset = Vector2(
			_prompt_panel.size.x / 2.0,
			_prompt_panel.size.y if UiKit.mobile_ui_enabled else _prompt_panel.size.y / 2.0
		)
		_prompt_panel.scale = Vector2.ONE * base_scale * 0.88
		_prompt_panel.create_tween().tween_property(_prompt_panel, "scale", Vector2.ONE * base_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_prompt() -> void:
	_prompt_text = ""
	_prompt_action = &""
	_prompt_button_label = ""
	_refresh_prompt_visibility()


func set_mobile_controls_enabled(enabled: bool) -> void:
	var needs_scale := not _mobile_ui_scale_applied \
			or _mobile_controls_enabled != enabled \
			or not is_equal_approx(_applied_mobile_ui_scale, mobile_ui_scale)
	_mobile_controls_enabled = enabled
	UiKit.set_mobile_ui_enabled(enabled, mobile_ui_scale)
	if not needs_scale:
		return
	for node in _gameplay_nodes:
		if node is Control:
			UiKit.apply_mobile_scale(node, enabled)
	for child in get_children():
		if child == _fade or child == _flash:
			continue
		if child is MobileControls:
			(child as MobileControls).set_mobile_ui_scale(enabled)
		elif child is TitleScreen:
			(child as TitleScreen).set_mobile_ui_scale(enabled)
		elif child is DialoguePanel:
			UiKit.apply_mobile_scale(child as Control, enabled)
	_apply_registered_modal_scales(self, enabled)
	_layout_mobile_top_panels()
	_set_metric_panels_interactive(enabled)
	_mobile_ui_scale_applied = true
	_applied_mobile_ui_scale = mobile_ui_scale
	_refresh_prompt_visibility()


func prompt_action() -> StringName:
	return _prompt_action


func prompt_button_label() -> String:
	return _prompt_button_label


func _should_show_prompt() -> bool:
	return _gameplay_shown and not _prompt_text.is_empty() \
			and not (_mobile_controls_enabled and _prompt_action != &"")


func _refresh_prompt_visibility() -> void:
	if is_instance_valid(_prompt_panel):
		_prompt_panel.visible = _should_show_prompt()


func _apply_registered_modal_scales(node: Node, enabled: bool) -> void:
	if node.has_meta("_mobile_scale_target"):
		var target := node.get_meta("_mobile_scale_target") as Control
		if is_instance_valid(target):
			UiKit.apply_mobile_scale(target, enabled, "center")
	for child in node.get_children():
		_apply_registered_modal_scales(child, enabled)


func _layout_mobile_top_panels() -> void:
	if not is_instance_valid(_location_card) or not is_instance_valid(_quest_card) \
			or not is_instance_valid(_coins_card) or not is_instance_valid(_stats_card):
		return
	var viewport_width := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var requested_scale := UiKit.mobile_ui_scale_factor if _mobile_controls_enabled else 1.0
	var available_panel_width := viewport_width - TOP_PANEL_SIDE_MARGIN * 2.0 - TOP_PANEL_COLUMN_GAP
	var combined_panel_width := TOP_PANEL_LEFT_WIDTH + TOP_PANEL_RIGHT_WIDTH
	var can_keep_columns_separate := available_panel_width >= combined_panel_width
	var panel_scale := requested_scale
	if can_keep_columns_separate:
		panel_scale = minf(panel_scale, available_panel_width / combined_panel_width)
	else:
		panel_scale = 1.0
	panel_scale = maxf(panel_scale, 1.0)

	for panel in [_location_card, _quest_card, _coins_card, _stats_card]:
		UiKit.apply_mobile_scale(panel, _mobile_controls_enabled, "auto", panel_scale)
	_stats_card.offset_right = -TOP_PANEL_SIDE_MARGIN
	_stats_card.offset_left = -(TOP_PANEL_SIDE_MARGIN + TOP_PANEL_STATS_WIDTH)
	var coins_right_offset := TOP_PANEL_SIDE_MARGIN \
			+ (TOP_PANEL_STATS_WIDTH + TOP_PANEL_METRICS_GAP) * panel_scale
	_coins_card.offset_right = -coins_right_offset
	_coins_card.offset_left = -(coins_right_offset + TOP_PANEL_COINS_WIDTH)

	var left_column_bottom := TOP_PANEL_TOP_MARGIN + 80.0 * panel_scale
	_quest_card.position.y = left_column_bottom + TOP_PANEL_QUEST_GAP * panel_scale
	var metrics_top := TOP_PANEL_TOP_MARGIN
	if not can_keep_columns_separate:
		metrics_top = _quest_card.position.y + _quest_card.get_combined_minimum_size().y * panel_scale \
				+ TOP_PANEL_VERTICAL_GAP * panel_scale
	_coins_card.offset_top = metrics_top
	_coins_card.offset_bottom = metrics_top + TOP_PANEL_METRICS_HEIGHT
	_stats_card.offset_top = metrics_top
	_stats_card.offset_bottom = metrics_top + TOP_PANEL_METRICS_HEIGHT
	var controls := get_node_or_null("MobileControls") as MobileControls
	if controls != null:
		controls.set_pause_button_top(metrics_top + (TOP_PANEL_METRICS_HEIGHT + TOP_PANEL_VERTICAL_GAP) * panel_scale)


## Nombre del lugar que se muestra bajo "WILLOWMERE" (por ejemplo "BAKERY").
func set_location(place: String) -> void:
	_location_label.text = "SPRINGFALL  /  %s" % place.to_upper()


## Funde la pantalla a negro (alpha 1) o la devuelve (alpha 0). Usar con await.
func fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, duration)
	await tween.finished


func _build_location_card() -> void:
	_location_card = PanelContainer.new()
	_location_card.position = Vector2(TOP_PANEL_SIDE_MARGIN, TOP_PANEL_TOP_MARGIN)
	_location_card.size = Vector2(TOP_PANEL_LEFT_WIDTH, 80)
	_location_card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(_location_card)
	var margin := UiKit.margin(16, 16, 11, 11)
	_location_card.add_child(margin)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 2)
	margin.add_child(copy)
	copy.add_child(UiKit.label("WILLOWMERE", 20, UiKit.INK))
	_location_label = UiKit.label("SPRINGFALL  /  PLAZA CENTRAL", 10, UiKit.INK_ACCENT)
	copy.add_child(_location_label)


func _wrapped_label(text: String, font_size: int, color: Color) -> Label:
	var label := UiKit.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	return label


func _build_quest_card() -> void:
	_quest_card = PanelContainer.new()
	_quest_card.position = Vector2(TOP_PANEL_SIDE_MARGIN, TOP_PANEL_TOP_MARGIN + 80.0 + 14.0)
	_quest_card.custom_minimum_size = Vector2(310, 0)
	_quest_card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	add_child(_quest_card)
	var margin := UiKit.margin(14, 14, 10, 10)
	_quest_card.add_child(margin)
	_quest_box = VBoxContainer.new()
	_quest_box.add_theme_constant_override("separation", 3)
	margin.add_child(_quest_box)


func _build_coins_card() -> void:
	_coins_card = PanelContainer.new()
	_coins_card.anchor_left = 1.0
	_coins_card.anchor_right = 1.0
	_coins_card.offset_left = -(TOP_PANEL_RIGHT_WIDTH + TOP_PANEL_SIDE_MARGIN)
	_coins_card.offset_right = -TOP_PANEL_SIDE_MARGIN
	_coins_card.offset_top = TOP_PANEL_TOP_MARGIN
	_coins_card.offset_bottom = TOP_PANEL_TOP_MARGIN + TOP_PANEL_METRICS_HEIGHT
	_coins_card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	_coins_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_coins_card.gui_input.connect(_on_coins_panel_gui_input)
	add_child(_coins_card)
	var margin := UiKit.margin(10, 10, 5, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_card.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	_coins_label = UiKit.label("MONEDAS  0", 11, UiKit.INK_ACCENT)
	_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_coins_label)


func _build_stats_card() -> void:
	_stats_card = PanelContainer.new()
	_stats_card.anchor_left = 1.0
	_stats_card.anchor_right = 1.0
	_stats_card.offset_left = -(TOP_PANEL_RIGHT_WIDTH + TOP_PANEL_SIDE_MARGIN)
	_stats_card.offset_right = -TOP_PANEL_SIDE_MARGIN
	_stats_card.offset_top = TOP_PANEL_TOP_MARGIN
	_stats_card.offset_bottom = TOP_PANEL_TOP_MARGIN + TOP_PANEL_METRICS_HEIGHT
	_stats_card.add_theme_stylebox_override("panel", UiKit.hud_card_style())
	_stats_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_stats_card.gui_input.connect(_on_stats_panel_gui_input)
	add_child(_stats_card)
	var margin := UiKit.margin(10, 10, 5, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_card.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	_stats_label = UiKit.label("PUNTOS  0    ·    0:00", 11, UiKit.INK)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_label)


func _set_metric_panels_interactive(enabled: bool) -> void:
	for panel in [_coins_card, _stats_card]:
		if not is_instance_valid(panel):
			continue
		panel.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW


func _on_coins_panel_gui_input(event: InputEvent) -> void:
	if _is_mobile_panel_tap(event):
		inventory_requested.emit()
		_coins_card.accept_event()


func _on_stats_panel_gui_input(event: InputEvent) -> void:
	if _is_mobile_panel_tap(event):
		leaderboard_requested.emit()
		_stats_card.accept_event()


func _is_mobile_panel_tap(event: InputEvent) -> bool:
	if not _mobile_controls_enabled:
		return false
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		return mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed
	return false


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
