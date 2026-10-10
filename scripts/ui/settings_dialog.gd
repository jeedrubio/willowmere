class_name SettingsDialog
extends Control
## Ajustes con dos pestañas: Audio (volumen de la música, silencio, siguiente
## canción) y Gemini (clave de Google AI Studio, que se queda en memoria).

signal saved(key: String)
signal closed

const TAB_AUDIO := "audio"
const TAB_GEMINI := "gemini"

var _current_key := ""
var _model_name := ""
var _music: MusicPlayer = null

var _key_input: LineEdit
var _tab_buttons := {}
var _pages := {}
var _volume_slider: HSlider
var _volume_value: Label
var _mute_check: CheckButton
var _track_label: Label


## Llamar antes de añadirlo al árbol.
func setup(current_key: String, model_name: String, music: MusicPlayer = null) -> void:
	_current_key = current_key
	_model_name = model_name
	_music = music


func _ready() -> void:
	UiKit.full_rect(self)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP

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

	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(540, 0)
	dialog.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.COLOR_CARD, 15, Color("#55717D"), 1))
	center.add_child(dialog)
	var margin := UiKit.margin(24, 24, 20, 20)
	dialog.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size = Vector2(0, 33)
	content.add_child(title_row)
	var title_copy := VBoxContainer.new()
	title_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_copy.add_theme_constant_override("separation", 1)
	title_row.add_child(title_copy)
	title_copy.add_child(UiKit.label("Ajustes", 20, UiKit.COLOR_TEXT))
	title_copy.add_child(UiKit.label("AUDIO  /  GEMINI", 9, UiKit.COLOR_ACCENT))
	var close_button := UiKit.ghost_button("Cerrar")
	close_button.custom_minimum_size = Vector2(64, 30)
	close_button.pressed.connect(closed.emit)
	title_row.add_child(close_button)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	for tab_id in [TAB_AUDIO, TAB_GEMINI]:
		var button := UiKit.ghost_button("Audio" if tab_id == TAB_AUDIO else "Gemini", 12)
		button.custom_minimum_size = Vector2(110, 34)
		button.pressed.connect(_show_tab.bind(tab_id))
		tabs.add_child(button)
		_tab_buttons[tab_id] = button
	content.add_child(UiKit.divider())

	var audio_page := _build_audio_page()
	var gemini_page := _build_gemini_page()
	content.add_child(audio_page)
	content.add_child(gemini_page)
	_pages[TAB_AUDIO] = audio_page
	_pages[TAB_GEMINI] = gemini_page

	_show_tab(TAB_AUDIO)


func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.save_settings()


func _build_audio_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)

	if _music == null:
		var missing := UiKit.label("No se encontró ningún nodo MusicPlayer en la escena.", 12, UiKit.COLOR_MUTED)
		page.add_child(missing)
		return page

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	page.add_child(volume_row)
	var volume_title := UiKit.label("Volumen de la música", 12, UiKit.COLOR_TEXT)
	volume_title.custom_minimum_size = Vector2(110, 0)
	volume_row.add_child(volume_title)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 1
	_volume_slider.value = roundf(_music.volume * 100.0)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_slider(_volume_slider)
	_volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume_slider)
	_volume_value = UiKit.label("%d%%" % int(_volume_slider.value), 12, UiKit.COLOR_ACCENT)
	_volume_value.custom_minimum_size = Vector2(42, 0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_value)

	_mute_check = CheckButton.new()
	_mute_check.text = "Silenciar música"
	_mute_check.button_pressed = _music.muted
	_mute_check.add_theme_font_size_override("font_size", 12)
	_mute_check.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_mute_check.add_theme_color_override("font_hover_color", UiKit.COLOR_TEXT)
	_mute_check.add_theme_color_override("font_pressed_color", UiKit.COLOR_TEXT)
	_mute_check.toggled.connect(_on_mute_toggled)
	page.add_child(_mute_check)

	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 10)
	page.add_child(track_row)
	_track_label = UiKit.label("", 11, UiKit.COLOR_MUTED)
	_track_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_track_label.clip_text = true
	track_row.add_child(_track_label)
	var next_button := UiKit.ghost_button("Siguiente pista  ⏭", 11)
	next_button.custom_minimum_size = Vector2(120, 32)
	next_button.pressed.connect(_music.next_track)
	next_button.visible = _music.track_count() > 1
	track_row.add_child(next_button)
	_music.track_started.connect(_on_track_started)
	_refresh_track_label()

	var hint := UiKit.label("Coloca archivos .ogg, .mp3 o .wav en la carpeta de música (%s) para añadir canciones." % _music.music_folder, 10, UiKit.COLOR_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(480, 0)
	page.add_child(hint)
	return page


func _build_gemini_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 11)

	var intro := UiKit.label("Añade una clave de Google AI Studio para que los aldeanos respondan en personaje. Solo se guarda en memoria durante esta sesión. También puedes definir la variable de entorno GEMINI_API_KEY.", 12, UiKit.COLOR_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(480, 52)
	page.add_child(intro)

	_key_input = UiKit.line_edit("Pega tu clave de API de Gemini", 12)
	_key_input.custom_minimum_size = Vector2(0, 43)
	_key_input.secret = true
	_key_input.text = _current_key
	_key_input.text_submitted.connect(_on_key_submitted)
	page.add_child(_key_input)
	page.add_child(UiKit.label("Consigue una clave en aistudio.google.com  ·  Modelo: " + _model_name, 10, UiKit.COLOR_FAINT))

	var actions := HBoxContainer.new()
	page.add_child(actions)
	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(action_spacer)
	var save := UiKit.primary_button("Guardar y conectar", 11)
	save.custom_minimum_size = Vector2(132, 36)
	save.pressed.connect(_on_save_pressed)
	actions.add_child(save)
	return page


func _show_tab(tab_id: String) -> void:
	for id in _pages:
		_pages[id].visible = (id == tab_id)
		var button: Button = _tab_buttons[id]
		if id == tab_id:
			UiKit.apply_button_style(button, Color("#337C75"), Color("#4D9E91"), Color("#28655F"))
			button.add_theme_color_override("font_color", Color.WHITE)
			button.add_theme_color_override("font_hover_color", Color.WHITE)
		else:
			UiKit.apply_ghost_style(button)
			button.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
			button.add_theme_color_override("font_hover_color", UiKit.COLOR_TEXT)
	if tab_id == TAB_GEMINI and is_instance_valid(_key_input):
		_key_input.grab_focus()


func _on_volume_changed(value: float) -> void:
	_volume_value.text = "%d%%" % int(value)
	_music.set_volume(value / 100.0)


func _on_mute_toggled(pressed: bool) -> void:
	_music.set_muted(pressed)


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
