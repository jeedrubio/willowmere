class_name PauseMenu
extends Control
## Menú de pausa (Esc). Solo avisa con señales; Main decide qué hacer y pausa el árbol.

signal resume_requested
signal controls_requested
signal settings_requested
signal quit_requested


func _ready() -> void:
	UiKit.full_rect(self)
	z_index = 40
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	UiKit.full_rect(shade)
	shade.color = Color(0.03, 0.06, 0.1, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.COLOR_CARD, 20, Color("#789185"), 2))
	center.add_child(card)
	var margin := UiKit.margin(44, 44, 32, 28)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(_centered("MENÚ DEL JUEGO", 10, UiKit.COLOR_ACCENT))
	content.add_child(_centered("En pausa", 32, UiKit.COLOR_TEXT))
	content.add_child(UiKit.divider())

	var resume_button := UiKit.menu_button("Continuar", true)
	resume_button.pressed.connect(resume_requested.emit)
	content.add_child(resume_button)
	var controls_button := UiKit.menu_button("Controles")
	controls_button.pressed.connect(controls_requested.emit)
	content.add_child(controls_button)
	var settings_button := UiKit.menu_button("Ajustes")
	settings_button.pressed.connect(settings_requested.emit)
	content.add_child(settings_button)
	var quit_button := UiKit.menu_button("Salir del juego")
	quit_button.pressed.connect(quit_requested.emit)
	content.add_child(quit_button)

	content.add_child(_centered("ESC  CONTINUAR", 9, UiKit.COLOR_FAINT))
	resume_button.grab_focus.call_deferred()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _centered(text: String, font_size: int, color: Color) -> Label:
	var result := UiKit.label(text, font_size, color)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result
