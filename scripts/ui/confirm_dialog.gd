class_name ConfirmDialog
extends Control
## Aviso modal con un mensaje y varios botones (confirmar un borrado, salir sin guardar...).
## No se cierra solo: quien lo crea escucha `chosen` / `cancelled` y lo libera.
##
## Cada opción: {"id": String, "text": String, "style": "primary" | "ghost" | "danger"}.
## El foco inicial cae en la primera opción "ghost" (la salida segura) o, si no hay, en la primera.

signal chosen(id: String)
signal cancelled

var _title := ""
var _message := ""
var _options: Array = []


## Llamar antes de añadirlo al árbol.
func setup(title: String, message: String, options: Array) -> void:
	_title = title
	_message = message
	_options = options


func _ready() -> void:
	# Por encima de cualquier otra ventana, también cuando cuelga de una que ya tiene z_index.
	z_as_relative = false
	var parts := UiKit.build_modal(self, 460, 70, 0.62, Vector2(28, 24))
	var content: VBoxContainer = parts["content"]
	content.add_theme_constant_override("separation", 12)
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	content.add_child(UiKit.label(_title, 22, UiKit.INK))
	content.add_child(UiKit.wrapped_label(_message, 14, UiKit.INK_SOFT, 400))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	content.add_child(gap)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)

	var focus_target: Button = null
	for entry in _options:
		var option: Dictionary = entry
		var id := String(option.get("id", ""))
		var text := String(option.get("text", id))
		var style := String(option.get("style", "ghost"))
		var button: Button
		match style:
			"primary":
				button = UiKit.primary_button(text, 14)
			"danger":
				button = UiKit.danger_button(text, 14)
			_:
				button = UiKit.ghost_button(text, 14)
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(chosen.emit.bind(id))
		buttons.add_child(button)
		if focus_target == null or (style == "ghost" and focus_target.get_meta("style", "") != "ghost"):
			focus_target = button
		button.set_meta("style", style)
	if focus_target != null:
		focus_target.grab_focus.call_deferred()
	UiKit.fade_in(self, 0.12)


## Equivale a pulsar Esc o a hacer clic fuera.
func dismiss() -> void:
	cancelled.emit()


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cancelled.emit()
