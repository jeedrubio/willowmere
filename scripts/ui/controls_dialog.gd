class_name ControlsDialog
extends Control
## Ventana con la lista de controles. Se abre desde el título y desde el menú de pausa.

signal closed


func _ready() -> void:
	UiKit.full_rect(self)
	z_index = 60
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
	dialog.custom_minimum_size = Vector2(480, 0)
	dialog.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.COLOR_CARD, 15, Color("#55717D"), 1))
	center.add_child(dialog)
	var margin := UiKit.margin(26, 26, 22, 22)
	dialog.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var title_copy := VBoxContainer.new()
	title_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_copy.add_theme_constant_override("separation", 1)
	title_row.add_child(title_copy)
	title_copy.add_child(UiKit.label("Controles", 20, UiKit.COLOR_TEXT))
	title_copy.add_child(UiKit.label("CÓMO JUGAR", 9, UiKit.COLOR_ACCENT))
	var close_button := UiKit.ghost_button("Cerrar")
	close_button.custom_minimum_size = Vector2(64, 30)
	close_button.pressed.connect(closed.emit)
	title_row.add_child(close_button)

	content.add_child(UiKit.divider())

	for entry in Controls.help_rows():
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override("separation", 6)
		var action_label := UiKit.label(String(entry["action"]), 12, UiKit.COLOR_MUTED)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(action_label)
		for key_text in entry["keys"]:
			row.add_child(UiKit.keycap(String(key_text)))
		content.add_child(row)

	content.add_child(UiKit.divider())
	content.add_child(UiKit.label("Las teclas se pueden cambiar en Proyecto > Configuración del proyecto > Mapa de entradas.", 10, UiKit.COLOR_FAINT))


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		closed.emit()
