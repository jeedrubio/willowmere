class_name MobileControls
extends Control
## Optional touch controls that feed the game's existing Input Map actions.

signal action_pressed(action: StringName)

const MODE_HIDDEN := 0
const MODE_GAMEPLAY := 1
const JOYSTICK_SIZE := 160.0
const BUTTON_SIZE := Vector2(84.0, 62.0)
const CONTEXTUAL_ACTIONS := [Controls.INTERACT, Controls.ENTER]


class TouchJoystick extends Control:
	signal direction_changed(value: Vector2)

	const NO_POINTER := -2
	const MOUSE_POINTER := -1
	var _active_pointer := NO_POINTER
	var _direction := Vector2.ZERO


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed and _active_pointer == NO_POINTER:
				_active_pointer = touch.index
				_update_direction(touch.position)
				accept_event()
			elif not touch.pressed and _active_pointer == touch.index:
				_reset_pointer()
				accept_event()
		elif event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			if _active_pointer == drag.index:
				_update_direction(drag.position)
				accept_event()
		elif event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index != MOUSE_BUTTON_LEFT:
				return
			if mouse_button.pressed and _active_pointer == NO_POINTER:
				_active_pointer = MOUSE_POINTER
				_update_direction(mouse_button.position)
				accept_event()
			elif not mouse_button.pressed and _active_pointer == MOUSE_POINTER:
				_reset_pointer()
				accept_event()
		elif event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
			_update_direction((event as InputEventMouseMotion).position)
			accept_event()


	func reset() -> void:
		_active_pointer = NO_POINTER
		_set_direction(Vector2.ZERO)


	func _reset_pointer() -> void:
		_active_pointer = NO_POINTER
		_set_direction(Vector2.ZERO)


	func _update_direction(pointer_position: Vector2) -> void:
		var radius := minf(size.x, size.y) * 0.36
		if radius <= 0.0:
			return
		var offset := pointer_position - size * 0.5
		_set_direction(offset.limit_length(radius) / radius)


	func _set_direction(value: Vector2) -> void:
		if _direction.distance_squared_to(value) < 0.0001:
			return
		_direction = value
		direction_changed.emit(_direction)
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.46
		draw_circle(center, radius, Color(0.035, 0.075, 0.11, 0.56))
		draw_arc(center, radius, 0.0, TAU, 48, Color(0.86, 0.79, 0.61, 0.72), 3.0, true)
		draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(radius * 0.55, 0), Color(1, 1, 1, 0.14), 2.0)
		draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.55), Color(1, 1, 1, 0.14), 2.0)
		var thumb_center := center + _direction * radius * 0.58
		var thumb_radius := minf(size.x, size.y) * 0.18
		draw_circle(thumb_center, thumb_radius, Color(0.90, 0.78, 0.56, 0.94))
		draw_arc(thumb_center, thumb_radius, 0.0, TAU, 32, Color(0.15, 0.22, 0.25, 0.86), 2.0, true)


var _mode := MODE_HIDDEN
var _joystick: TouchJoystick
var _buttons: Dictionary = {}
var _pause_button: Button
var _pause_button_top := -1.0
var _available_action: StringName = &""
var _available_label := ""
var _mobile_ui_scale_factor := 1.0


func _ready() -> void:
	UiKit.full_rect(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_controls()
	resized.connect(_layout_controls)
	call_deferred("_layout_controls")


func _exit_tree() -> void:
	_release_all_inputs()


## Context controls whether the overlay is shown on the title screen or in active play.
func set_context(enabled: bool, game_started: bool, blocked: bool, available_action: StringName = &"", action_label: String = "") -> void:
	var next_mode := MODE_HIDDEN
	if enabled and game_started and not blocked:
		next_mode = MODE_GAMEPLAY
	var next_action := available_action if next_mode == MODE_GAMEPLAY else &""
	var next_label := action_label if next_action != &"" else ""
	if next_mode == _mode and next_action == _available_action and next_label == _available_label:
		return
	if next_mode != _mode:
		_release_all_inputs()
	_mode = next_mode
	_available_action = next_action
	_available_label = next_label
	visible = _mode != MODE_HIDDEN
	_joystick.visible = _mode == MODE_GAMEPLAY
	for action in _buttons:
		var button: Button = _buttons[action]
		var contextual: bool = action in CONTEXTUAL_ACTIONS
		button.visible = _mode == MODE_GAMEPLAY and (not contextual or action == _available_action)
		if contextual:
			button.text = _available_label if action == _available_action and not _available_label.is_empty() \
					else ("HABLAR" if action == Controls.INTERACT else "PUERTA")
	_layout_controls()


func set_mobile_ui_scale(enabled: bool) -> void:
	_mobile_ui_scale_factor = UiKit.mobile_ui_scale_factor if enabled else 1.0
	for button in _buttons.values():
		(button as Button).add_theme_font_size_override("font_size", roundi(12.0 * _mobile_ui_scale_factor))
	_layout_controls()


func _build_controls() -> void:
	_joystick = TouchJoystick.new()
	_joystick.name = "Joystick"
	_joystick.direction_changed.connect(_on_joystick_changed)
	add_child(_joystick)

	var definitions := [
		[Controls.INTERACT, "HABLAR", 0, 0],
		[Controls.ENTER, "PUERTA", 0, 1],
		[Controls.INVENTORY, "BOLSA", 1, 0],
	]
	for definition in definitions:
		var action: StringName = definition[0]
		var button := _make_action_button(String(definition[1]))
		button.name = "Action_" + String(action)
		button.pressed.connect(_on_action_pressed.bind(action))
		button.set_meta("row", int(definition[2]))
		button.set_meta("column", int(definition[3]))
		add_child(button)
		_buttons[action] = button

	_pause_button = _make_action_button("PAUSA")
	_pause_button.name = "Action_" + String(Controls.CANCEL)
	_pause_button.pressed.connect(_on_action_pressed.bind(Controls.CANCEL))
	add_child(_pause_button)
	_buttons[Controls.CANCEL] = _pause_button


func _make_action_button(label: String) -> Button:
	var button := UiKit.ghost_button(label, 12)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _layout_controls() -> void:
	if not is_instance_valid(_joystick):
		return
	var scale_factor := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.72, 1.15) * _mobile_ui_scale_factor
	var margin := 24.0 * scale_factor
	var joystick_size := Vector2.ONE * JOYSTICK_SIZE * scale_factor
	_joystick.position = Vector2(margin, size.y - margin - joystick_size.y)
	_joystick.size = joystick_size

	var button_size := BUTTON_SIZE * scale_factor
	var gap := 8.0 * scale_factor
	var group_width := button_size.x * 2.0 + gap
	var group_height := button_size.y * 2.0 + gap
	for action in _buttons:
		var button: Button = _buttons[action]
		button.size = button_size
		if action == Controls.CANCEL:
			var pause_top := margin if _pause_button_top < 0.0 else _pause_button_top
			button.position = Vector2(size.x - margin - button_size.x, pause_top)
			continue
		var row := int(button.get_meta("row"))
		var column := int(button.get_meta("column"))
		var column_offset := float(column) * (button_size.x + gap)
		if action == Controls.INVENTORY:
			column_offset = (group_width - button_size.x) * 0.5
		button.position = Vector2(
			size.x - margin - group_width + column_offset,
			size.y - margin - group_height + row * (button_size.y + gap)
		)


func set_pause_button_top(top: float) -> void:
	_pause_button_top = top
	_layout_controls()


func _on_joystick_changed(direction: Vector2) -> void:
	_set_move_action(Controls.MOVE_LEFT, direction.x < -0.25)
	_set_move_action(Controls.MOVE_RIGHT, direction.x > 0.25)
	_set_move_action(Controls.MOVE_UP, direction.y < -0.25)
	_set_move_action(Controls.MOVE_DOWN, direction.y > 0.25)


func _set_move_action(action: StringName, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _on_action_pressed(action: StringName) -> void:
	if _mode == MODE_HIDDEN:
		return
	action_pressed.emit(action)


func _release_all_inputs() -> void:
	if is_instance_valid(_joystick):
		_joystick.reset()
	for action in [Controls.MOVE_LEFT, Controls.MOVE_RIGHT, Controls.MOVE_UP, Controls.MOVE_DOWN]:
		if InputMap.has_action(action):
			Input.action_release(action)
