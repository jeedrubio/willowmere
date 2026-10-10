class_name TitleScreen
extends Control
## Pantalla de título: descripción del juego y menú (empezar, controles, ajustes, salir).

signal start_requested
signal controls_requested
signal settings_requested
signal quit_requested


func _ready() -> void:
	UiKit.full_rect(self)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	UiKit.full_rect(shade)
	shade.color = Color(0.035, 0.075, 0.09, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(640, 0)
	card.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.COLOR_CARD, 22, Color("#789185"), 2))
	center.add_child(card)
	var margin := UiKit.margin(48, 48, 36, 30)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(_centered("UN PUEBLITO TRANQUILO  ·  SPRINGFALL", 11, UiKit.COLOR_ACCENT))
	content.add_child(_centered("Willowmere", 52, UiKit.COLOR_TEXT))
	content.add_child(_centered("Una pequeña aventura de primavera", 17, UiKit.COLOR_MINT))
	content.add_child(UiKit.divider())

	var description := _centered("Conoce a los aldeanos, cosecha cultivos de primavera, asómate a las casas del pueblo y ayuda a Mira a devolverle la vida a su jardín.", 14, UiKit.COLOR_MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(0, 44)
	content.add_child(description)
	content.add_child(_centered("TU PRIMER ENCARGO   ·   AYUDA A MIRA CON SU JARDÍN", 11, UiKit.COLOR_ACCENT))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	content.add_child(gap)

	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)
	var start_button := UiKit.menu_button("Comenzar a explorar", true)
	start_button.pressed.connect(start_requested.emit)
	buttons.add_child(start_button)
	var controls_button := UiKit.menu_button("Controles")
	controls_button.pressed.connect(controls_requested.emit)
	buttons.add_child(controls_button)
	var settings_button := UiKit.menu_button("Ajustes")
	settings_button.pressed.connect(settings_requested.emit)
	buttons.add_child(settings_button)
	if OS.get_name() != "Web":
		var quit_button := UiKit.menu_button("Salir")
		quit_button.pressed.connect(quit_requested.emit)
		buttons.add_child(quit_button)

	content.add_child(_centered(Controls.title_hint(), 10, UiKit.COLOR_FAINT))

	start_button.grab_focus.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.45)


func _centered(text: String, font_size: int, color: Color) -> Label:
	var result := UiKit.label(text, font_size, color)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result
