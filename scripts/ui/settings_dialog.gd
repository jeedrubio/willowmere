class_name SettingsDialog
extends Control
## Ajustes con cuatro pestañas: Audio (música y efectos), Juego (sacudida de cámara y
## efectos visuales), Gemini (clave de Google AI Studio, que se queda en memoria) y Datos.

signal saved(key: String)
signal closed

const TAB_AUDIO := "audio"
const TAB_GAME := "juego"
const TAB_GEMINI := "gemini"
const TAB_DATA := "datos"

var _current_key := ""
var _model_name := ""
var _music: MusicPlayer = null

var _key_input: LineEdit
var _tab_buttons := {}
var _pages := {}
var _volume_slider: HSlider
var _mute_check: CheckButton
var _track_label: Label


## Llamar antes de añadirlo al árbol.
func setup(current_key: String, model_name: String, music: MusicPlayer = null) -> void:
	_current_key = current_key
	_model_name = model_name
	_music = music


func _ready() -> void:
	var parts := UiKit.build_modal(self, 600, 50)
	var content: VBoxContainer = parts["content"]
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	content.add_child(UiKit.modal_header("Ajustes", "AUDIO  /  JUEGO  /  GEMINI  /  DATOS", closed.emit))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	var tab_titles := {TAB_AUDIO: "Audio", TAB_GAME: "Juego", TAB_GEMINI: "Gemini", TAB_DATA: "Datos"}
	for tab_id in [TAB_AUDIO, TAB_GAME, TAB_GEMINI, TAB_DATA]:
		var button := UiKit.ghost_button(String(tab_titles[tab_id]), 14)
		button.custom_minimum_size = Vector2(112, 44)
		button.pressed.connect(_show_tab.bind(tab_id))
		tabs.add_child(button)
		_tab_buttons[tab_id] = button
	content.add_child(UiKit.divider())

	# Las dos pestañas comparten esta altura mínima: así la ventana no "salta" al cambiar de una a otra.
	var pages_holder := VBoxContainer.new()
	pages_holder.custom_minimum_size = Vector2(540, 330)
	content.add_child(pages_holder)
	var audio_page := _build_audio_page()
	var game_page := _build_game_page()
	pages_holder.add_child(game_page)
	_pages[TAB_GAME] = game_page
	var gemini_page := _build_gemini_page()
	pages_holder.add_child(audio_page)
	pages_holder.add_child(gemini_page)
	var data_page := _build_data_page()
	pages_holder.add_child(data_page)
	_pages[TAB_AUDIO] = audio_page
	_pages[TAB_GEMINI] = gemini_page
	_pages[TAB_DATA] = data_page

	_show_tab(TAB_AUDIO)
	UiKit.fade_in(self)


func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.save_settings()


func _slider_row(card: VBoxContainer, title: String, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var caption := UiKit.label(title, 15, UiKit.INK)
	caption.custom_minimum_size = Vector2(190, 0)
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundf(value * 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_slider(slider)
	row.add_child(slider)
	var readout := UiKit.label("%d%%" % int(slider.value), 15, UiKit.INK_ACCENT)
	readout.custom_minimum_size = Vector2(52, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%d%%" % int(v)
		on_change.call(v / 100.0))
	return slider


func _check(card: VBoxContainer, text: String, pressed: bool, on_toggle: Callable) -> CheckButton:
	var check := UiKit.check_button(text, 15)
	check.set_pressed_no_signal(pressed)
	check.toggled.connect(on_toggle)
	card.add_child(check)
	return check


func _build_audio_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	var card := UiKit.section_card(page, 18, 12)

	if _music == null:
		card.add_child(UiKit.wrapped_label("No se encontró ningún nodo MusicPlayer en la escena.", 14, UiKit.INK_SOFT, 480))
	else:
		_volume_slider = _slider_row(card, "Volumen de la música", _music.volume, func(v: float) -> void: _music.set_volume(v))
		_mute_check = _check(card, "Silenciar música", _music.muted, func(on: bool) -> void: _music.set_muted(on))
		var track_row := HBoxContainer.new()
		track_row.add_theme_constant_override("separation", 12)
		card.add_child(track_row)
		_track_label = UiKit.label("", 13, UiKit.INK_SOFT)
		_track_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_track_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_track_label.clip_text = true
		_track_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		track_row.add_child(_track_label)
		var next_button := UiKit.ghost_button("Siguiente pista", 14)
		next_button.custom_minimum_size = Vector2(170, 42)
		next_button.pressed.connect(_music.next_track)
		next_button.visible = _music.track_count() > 1
		track_row.add_child(next_button)
		_music.track_started.connect(_on_track_started)
		_refresh_track_label()

	card.add_child(UiKit.divider())
	_slider_row(card, "Volumen de efectos", GameFeel.sfx_volume, func(v: float) -> void:
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.set_volume(v)
			sfx.play("coin"))
	_check(card, "Silenciar efectos", GameFeel.sfx_muted, func(on: bool) -> void:
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.set_muted(on))
	return page


func _build_game_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	var card := UiKit.section_card(page, 18, 14)

	card.add_child(UiKit.label("Sacudida de cámara", 15, UiKit.INK))
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 8)
	card.add_child(levels)
	var level_buttons := {}
	var refresh_levels := func() -> void:
		for level in level_buttons:
			UiKit.set_variant(level_buttons[level], "primary" if level == GameFeel.shake_level else "default")
	for entry in [["off", "Desactivada"], ["low", "Suave"], ["normal", "Normal"]]:
		var button := UiKit.ghost_button(String(entry[1]), 14)
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var level_id := String(entry[0])
		button.pressed.connect(func() -> void:
			GameFeel.shake_level = level_id
			GameFeel.save_settings()
			refresh_levels.call()
			var camera_shake := get_tree().root.find_child("CameraShake", true, false)
			if camera_shake != null:
				camera_shake.add_trauma(0.35))
		levels.add_child(button)
		level_buttons[level_id] = button
	refresh_levels.call()
	card.add_child(UiKit.wrapped_label("La cámara vibra al cosechar, completar encargos o cruzar puertas. Desactívala si te marea.", 13, UiKit.INK_SOFT, 500))

	card.add_child(UiKit.divider())
	_check(card, "Partículas y textos flotantes", GameFeel.effects_enabled, func(on: bool) -> void:
		GameFeel.effects_enabled = on
		GameFeel.save_settings())
	card.add_child(UiKit.wrapped_label("Las chispas y los \"+1\" que aparecen al recoger cosas.", 13, UiKit.INK_SOFT, 500))
	return page


func _build_gemini_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	var card := UiKit.section_card(page, 18, 12)

	card.add_child(UiKit.wrapped_label("Añade una clave de Google AI Studio para que los aldeanos respondan en personaje. Solo se guarda en memoria durante esta sesión (y nunca en tus partidas guardadas). También puedes definir la variable de entorno GEMINI_API_KEY.", 13, UiKit.INK_SOFT, 520))

	_key_input = UiKit.line_edit("Pega tu clave de API de Gemini", 14)
	_key_input.custom_minimum_size = Vector2(0, 44)
	_key_input.secret = true
	_key_input.text = _current_key
	_key_input.text_submitted.connect(_on_key_submitted)
	card.add_child(_key_input)
	card.add_child(UiKit.label("Consigue una clave en aistudio.google.com  ·  Modelo: " + _model_name, 11, UiKit.INK_FAINT))

	var actions := HBoxContainer.new()
	card.add_child(actions)
	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(action_spacer)
	var save := UiKit.primary_button("Guardar y conectar", 14)
	save.custom_minimum_size = Vector2(190, 42)
	save.pressed.connect(_on_save_pressed)
	actions.add_child(save)
	return page


func _build_data_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	var card := UiKit.section_card(page, 18, 12)
	var tele := get_tree().root.get_node_or_null("Telemetry")
	if tele == null:
		card.add_child(UiKit.wrapped_label("La telemetría no está disponible en esta escena.", 13, UiKit.INK_SOFT, 480))
		return page

	var check := UiKit.check_button("Enviar estadísticas anónimas de uso", 14)
	check.set_pressed_no_signal(tele.enabled)
	check.toggled.connect(func(on: bool) -> void: tele.set_enabled(on))
	card.add_child(check)
	card.add_child(UiKit.divider())
	card.add_child(UiKit.wrapped_label("Sirven para mejorar el juego: duración de las partidas, por dónde se mueve la gente, qué menús se usan, FPS y cómo responde la IA. Se envían solo al servidor local (tools/servidor_sqlite.py).", 13, UiKit.INK_SOFT, 520))
	card.add_child(UiKit.wrapped_label("Nunca se envía lo que escribes a los aldeanos, tu clave de Gemini ni datos personales.", 13, UiKit.INK_GOOD, 520))
	return page


func _show_tab(tab_id: String) -> void:
	for id in _pages:
		_pages[id].visible = (id == tab_id)
		var button: Button = _tab_buttons[id]
		UiKit.set_variant(button, "primary" if id == tab_id else "default")
	if tab_id == TAB_GEMINI and is_instance_valid(_key_input):
		_key_input.grab_focus()


func _on_track_started(_track_name: String) -> void:
	_refresh_track_label()


func _refresh_track_label() -> void:
	if not is_instance_valid(_track_label):
		return
	var current := _music.current_track_name()
	if current.is_empty():
		_track_label.text = "No hay música sonando"
	else:
		_track_label.text = "♪  Reproduciendo: %s" % current


func _on_key_submitted(_text: String) -> void:
	_on_save_pressed()


func _on_save_pressed() -> void:
	saved.emit(_key_input.text.strip_edges())
	closed.emit()


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		closed.emit()
