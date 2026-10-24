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
var _info_label: Label
var _primary_button: Button


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

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	layout.add_child(column)

	var logo_texture := load(LOGO_PATH) as Texture2D
	if logo_texture != null:
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.custom_minimum_size = Vector2(500, 115)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(logo)
	else:
		column.add_child(_outlined("Willowmere", 56, Color("#F4C98A")))
	column.add_child(_outlined("Una pequeña aventura de primavera", 16, Color("#FFE9B8")))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_info_label = _outlined("", 14, Color("#BFEBC9"))
	column.add_child(_info_label)
	_buttons_box = VBoxContainer.new()
	_buttons_box.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	_buttons_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons_box.add_theme_constant_override("separation", 8)
	column.add_child(_buttons_box)
	column.add_child(_outlined(Controls.title_hint(), 12, Color("#D9C9B0")))


func _build_version_label() -> void:
	var version := _outlined("v%s" % String(ProjectSettings.get_setting("application/config/version", "")), 13, Color(1, 1, 1, 0.7))
	version.anchor_left = 1.0
	version.anchor_right = 1.0
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -160
	version.offset_right = -16
	version.offset_top = -30
	version.offset_bottom = -8
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


## Vuelve a dibujar los botones (por ejemplo tras borrar o crear partidas en el menú de guardado).
func refresh() -> void:
	_build_buttons()


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

	_primary_button.grab_focus.call_deferred()


## Texto claro con contorno oscuro para leerse sobre el fondo.
func _outlined(text: String, font_size: int, color: Color) -> Label:
	var result := UiKit.label(text, font_size, color)
	result.add_theme_color_override("font_outline_color", Color("#1A1426"))
	result.add_theme_constant_override("outline_size", 6)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
