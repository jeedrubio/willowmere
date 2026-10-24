class_name PauseMenu
extends Control
## Menú de pausa (Esc). Solo avisa con señales; Main decide qué hacer y pausa el árbol.

signal resume_requested
signal save_requested
signal load_requested
signal leaderboard_requested
signal controls_requested
signal settings_requested
signal quit_requested

var _resume_button: Button


func _ready() -> void:
	var parts := UiKit.build_modal(self, 460, 40, 0.7, Vector2(36, 28))
	var content: VBoxContainer = parts["content"]
	content.add_theme_constant_override("separation", 10)

	content.add_child(_centered("MENÚ DEL JUEGO", 11, UiKit.INK_ACCENT))
	content.add_child(_centered("En pausa", 34, UiKit.INK))
	content.add_child(UiKit.divider())

	var resume_button := UiKit.menu_button("Continuar", true)
	resume_button.pressed.connect(resume_requested.emit)
	content.add_child(resume_button)

	var save_button := UiKit.menu_button("Guardar partida")
	save_button.pressed.connect(save_requested.emit)
	content.add_child(save_button)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for entry in [
		["Cargar partida", load_requested],
		["Marcador", leaderboard_requested],
		["Controles", controls_requested],
		["Ajustes", settings_requested],
	]:
		var button := UiKit.menu_button(String(entry[0]))
		button.pressed.connect((entry[1] as Signal).emit)
		grid.add_child(button)

	content.add_child(UiKit.divider())
	var quit_button := UiKit.menu_button("Salir del juego", false, true)
	quit_button.pressed.connect(quit_requested.emit)
	content.add_child(quit_button)

	content.add_child(_centered("ESC  CONTINUAR", 11, UiKit.INK_FAINT))
	_resume_button = resume_button
	resume_button.grab_focus.call_deferred()
	UiKit.fade_in(self)


## Devuelve el foco al botón principal (al volver de un submenú).
func focus_first() -> void:
	if is_instance_valid(_resume_button):
		_resume_button.grab_focus()


func _centered(text: String, font_size: int, color: Color) -> Label:
	var result := UiKit.label(text, font_size, color)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result
