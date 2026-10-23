class_name ControlsDialog
extends Control
## Ventana con la lista de controles. Se abre desde el título y desde el menú de pausa.

signal closed


func _ready() -> void:
	var parts := UiKit.build_modal(self, 560, 60)
	var content: VBoxContainer = parts["content"]
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	content.add_child(UiKit.modal_header("Controles", "CÓMO JUGAR", closed.emit))

	var card := UiKit.section_card(content, 18, 4)
	var rows := Controls.help_rows()
	for i in rows.size():
		var entry: Dictionary = rows[i]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 38)
		row.add_theme_constant_override("separation", 6)
		var action_label := UiKit.label(String(entry["action"]), 14, UiKit.INK_SOFT)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(action_label)
		for key_text in entry["keys"]:
			var cap := UiKit.keycap(String(key_text))
			cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(cap)
		card.add_child(row)
		if i < rows.size() - 1:
			card.add_child(UiKit.divider())

	content.add_child(UiKit.wrapped_label("Las teclas se pueden cambiar en Proyecto > Configuración del proyecto > Mapa de entradas.", 11, UiKit.INK_FAINT, 500))
	UiKit.fade_in(self)


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		closed.emit()
