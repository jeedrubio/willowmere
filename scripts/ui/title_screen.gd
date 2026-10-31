class_name TitleScreen
extends Control
## Portada: logo y botones a la izquierda, y de fondo el pueblo "vivo" (ver TitleBackdrop)
## con pétalos cayendo. Si hay partidas guardadas, "Continuar" retoma la más reciente.
## Solo avisa con señales; Main hace el resto.

signal start_requested
signal continue_requested
signal load_requested
signal controls_requested
signal settings_requested
signal quit_requested

const LOGO_PATH := "res://asset_pack/UI/logo_willowmere.png"
const BUTTON_WIDTH := 330.0

var _menu: Control
var _buttons_box: VBoxContainer
var _menu_column: VBoxContainer
var _info_label: Label
var _primary_button: Button
var _version_label: Label
var _logo: TextureRect
var _mobile_labels: Array[Label] = []
var _mobile_ui_enabled := false
var _mobile_scale_factor := 1.0


func _ready() -> void:
	UiKit.full_rect(self)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_build_shading()
	_build_petals()
	_build_menu()
	_build_version_label()
	_build_buttons()
	set_mobile_ui_scale(UiKit.mobile_ui_enabled)
	resized.connect(_on_resized)
	UiKit.fade_in(self, 0.7)


## Velo cálido general + sombra a la izquierda para que el menú se lea sobre el fondo.
func _build_shading() -> void:
	var warm := ColorRect.new()
	UiKit.full_rect(warm)
	warm.color = Color(1.0, 0.62, 0.35, 0.10)
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warm)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.05, 0.04, 0.10, 0.88))
	gradient.set_color(1, Color(0.05, 0.04, 0.10, 0.0))
	var side := GradientTexture2D.new()
	side.gradient = gradient
	side.fill_from = Vector2(0.0, 0.5)
	side.fill_to = Vector2(0.62, 0.5)
	side.width = 256
	side.height = 4
	var shade := TextureRect.new()
	UiKit.full_rect(shade)
	shade.texture = side
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Viñeta inferior suave
	var bottom := Gradient.new()
	bottom.set_color(0, Color(0.05, 0.04, 0.10, 0.0))
	bottom.set_color(1, Color(0.05, 0.04, 0.10, 0.55))
	var bottom_texture := GradientTexture2D.new()
	bottom_texture.gradient = bottom
	bottom_texture.fill_from = Vector2(0.5, 0.7)
	bottom_texture.fill_to = Vector2(0.5, 1.0)
	bottom_texture.width = 4
	bottom_texture.height = 256
	var vignette := TextureRect.new()
	UiKit.full_rect(vignette)
	vignette.texture = bottom_texture
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


## Pétalos que caen despacio de derecha a izquierda.
func _build_petals() -> void:
	var petals := CPUParticles2D.new()
	petals.position = Vector2(1000, -16)
	petals.amount = 26
	petals.lifetime = 11.0
	petals.preprocess = 10.0
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(520, 4)
	petals.direction = Vector2(-0.5, 1.0)
	petals.spread = 18.0
	petals.initial_velocity_min = 22.0
	petals.initial_velocity_max = 48.0
	petals.gravity = Vector2(-6, 10)
	petals.scale_amount_min = 2.6
	petals.scale_amount_max = 4.4
	petals.color = Color("#FFB3CF")
	petals.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(petals)


func _build_menu() -> void:
	var layout := MarginContainer.new()
	UiKit.full_rect(layout)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("margin_left", 56)
	layout.add_theme_constant_override("margin_top", 30)
	layout.add_theme_constant_override("margin_bottom", 30)
	layout.add_theme_constant_override("margin_right", 24)
	add_child(layout)
	_menu = layout

	_menu_column = VBoxContainer.new()
	_menu_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_column.add_theme_constant_override("separation", 6)
	layout.add_child(_menu_column)

	var logo_texture := load(LOGO_PATH) as Texture2D
	if logo_texture != null:
		_logo = TextureRect.new()
		_logo.texture = logo_texture
		_logo.custom_minimum_size = Vector2(500, 115)
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_column.add_child(_logo)
	else:
		var fallback_logo := _outlined("Willowmere", 56, Color("#F4C98A"))
		_menu_column.add_child(fallback_logo)
	var subtitle := _outlined("Una pequeña aventura de primavera", 16, Color("#FFE9B8"))
	_menu_column.add_child(subtitle)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_column.add_child(spacer)

	_info_label = _outlined("", 14, Color("#BFEBC9"))
	_menu_column.add_child(_info_label)
	_buttons_box = VBoxContainer.new()
	_buttons_box.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	_buttons_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons_box.add_theme_constant_override("separation", 8)
	_menu_column.add_child(_buttons_box)
	var controls_hint := _outlined(Controls.title_hint(), 12, Color("#D9C9B0"))
	_menu_column.add_child(controls_hint)


func _build_version_label() -> void:
	_version_label = _outlined("v%s" % String(ProjectSettings.get_setting("application/config/version", "")), 13, Color(1, 1, 1, 0.7))
	_version_label.anchor_left = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -160
	_version_label.offset_right = -16
	_version_label.offset_top = -30
	_version_label.offset_bottom = -8
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_version_label)


func set_mobile_ui_scale(enabled: bool) -> void:
	_mobile_ui_enabled = enabled
	for label in _mobile_labels:
		var base_font_size: int = label.get_meta("_mobile_base_font_size")
		label.add_theme_font_size_override("font_size", base_font_size)
	if is_instance_valid(_logo):
		_logo.custom_minimum_size = Vector2(500, 115)
	_buttons_box.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	_apply_button_sizes(1.0)
	_mobile_scale_factor = 1.0
	if enabled:
		var available_height := maxf(get_viewport_rect().size.y - 60.0, 1.0)
		var base_height := _menu_column.get_combined_minimum_size().y
		if base_height > 0.0:
			_mobile_scale_factor = minf(UiKit.mobile_ui_scale_factor, available_height / base_height)
			_mobile_scale_factor = maxf(_mobile_scale_factor, 1.0)
	for label in _mobile_labels:
		var base_font_size: int = label.get_meta("_mobile_base_font_size")
		label.add_theme_font_size_override("font_size", roundi(base_font_size * _mobile_scale_factor))
	if is_instance_valid(_logo):
		_logo.custom_minimum_size = Vector2(500, 115) * _mobile_scale_factor
	_buttons_box.custom_minimum_size = Vector2(BUTTON_WIDTH * _mobile_scale_factor, 0)
	_apply_button_sizes(_mobile_scale_factor)


func _apply_button_sizes(factor: float) -> void:
	for child in _buttons_box.get_children():
		if not child is Button:
			continue
		var button := child as Button
		if not button.has_meta("_mobile_base_size"):
			button.set_meta("_mobile_base_size", button.custom_minimum_size)
			button.set_meta("_mobile_base_font_size", button.get_theme_font_size("font_size"))
		var base_size: Vector2 = button.get_meta("_mobile_base_size")
		var base_font_size: int = button.get_meta("_mobile_base_font_size")
		button.custom_minimum_size = base_size * factor
		button.add_theme_font_size_override("font_size", roundi(base_font_size * factor))


func _on_resized() -> void:
	if _mobile_ui_enabled:
		set_mobile_ui_scale(true)


## Vuelve a dibujar los botones (por ejemplo tras borrar o crear partidas en el menú de guardado).
func refresh() -> void:
	_build_buttons()
	if _mobile_ui_enabled:
		set_mobile_ui_scale(true)


## Muestra u oculta solo el menú (el fondo se queda, p. ej. mientras hay Ajustes abiertos).
func set_menu_visible(value: bool) -> void:
	_menu.visible = value


func is_menu_visible() -> bool:
	return _menu.visible


## Devuelve el foco al botón principal (al volver de un submenú).
func focus_first() -> void:
	if is_instance_valid(_primary_button):
		_primary_button.grab_focus()


func _build_buttons() -> void:
	for child in _buttons_box.get_children():
		_buttons_box.remove_child(child)
		child.queue_free()

	var latest := SaveGame.latest_slot()
	if latest > 0:
		var summary: Dictionary = SaveGame.peek(latest)["summary"]
		var place := String(summary["place"])
		_info_label.text = "Última partida  ·  %s  ·  %s jugados" % [
				place if not place.is_empty() else "Willowmere", UiKit.format_time(int(summary["play_seconds"]))]
		_primary_button = UiKit.menu_button("Continuar", true)
		_primary_button.pressed.connect(continue_requested.emit)
		_buttons_box.add_child(_primary_button)
		var new_button := UiKit.menu_button("Nueva partida")
		new_button.pressed.connect(start_requested.emit)
		_buttons_box.add_child(new_button)
	else:
		_info_label.text = ""
		_primary_button = UiKit.menu_button("Comenzar a explorar", true)
		_primary_button.pressed.connect(start_requested.emit)
		_buttons_box.add_child(_primary_button)

	var load_button := UiKit.menu_button("Cargar partida")
	load_button.disabled = latest == 0
	load_button.pressed.connect(load_requested.emit)
	_buttons_box.add_child(load_button)
	var controls_button := UiKit.menu_button("Controles")
	controls_button.pressed.connect(controls_requested.emit)
	_buttons_box.add_child(controls_button)
	var settings_button := UiKit.menu_button("Ajustes")
	settings_button.pressed.connect(settings_requested.emit)
	_buttons_box.add_child(settings_button)
	if OS.get_name() != "Web":
		var quit_button := UiKit.menu_button("Salir")
		quit_button.pressed.connect(quit_requested.emit)
		_buttons_box.add_child(quit_button)

	_apply_button_sizes(_mobile_scale_factor)
	_primary_button.grab_focus.call_deferred()


## Texto claro con contorno oscuro para leerse sobre el fondo.
func _outlined(text: String, font_size: int, color: Color) -> Label:
	var result := UiKit.label(text, font_size, color)
	result.set_meta("_mobile_base_font_size", font_size)
	result.add_theme_color_override("font_outline_color", Color("#1A1426"))
	result.add_theme_constant_override("outline_size", 6)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_labels.append(result)
	return result
