class_name UiKit
extends RefCounted
## Estilo compartido de toda la interfaz.
##
## Dos "mundos" de color:
##   - COLOR_*  : paleta oscura del HUD y del chat (tarjetas flotantes sobre el juego).
##   - INK_*    : tinta oscura para escribir sobre los menús de pergamino (botones y paneles).
## Los botones, paneles y campos usan las texturas pixel-art de asset_pack/UI/skin
## (se generan con tools/skin/generar_skin.py). Cambiar el aspecto = cambiar esas imágenes.

# --- Paleta oscura (HUD, chat)
const COLOR_BORDER := Color("#35506B")
const COLOR_TEXT := Color("#F6F0DB")
const COLOR_MUTED := Color("#A5B3B1")
const COLOR_FAINT := Color("#71838B")
const COLOR_ACCENT := Color("#F2B35F")
const COLOR_MINT := Color("#77D3B0")
const COLOR_RED := Color("#F58D78")
const COLOR_CARD := Color("#142336")
const COLOR_DEEP := Color("#0E1B2B")
const COLOR_INPUT := Color("#0A1523")
const COLOR_CARD_BORDER := Color("#55717D")

# --- Tinta sobre pergamino (menús)
const INK := Color("#2B2540")
const INK_SOFT := Color("#5A4A52")
const INK_FAINT := Color("#8A7568")
const INK_ACCENT := Color("#B04A24")
const INK_GOOD := Color("#2E6B3C")
const INK_BAD := Color("#A3321F")
const PAPER_LIGHT := Color("#FFF1D0")
const PAPER_EDGE := Color("#D9A877")

const SKIN_DIR := "res://asset_pack/UI/skin/"
## Márgenes de corte (9-slice) de las texturas; deben coincidir con skin.json.
const SKIN_NORMAL_MARGINS := Vector4(26, 18, 26, 22)
const SKIN_PRESSED_MARGINS := Vector4(26, 18, 26, 16)
const DEFAULT_MOBILE_UI_SCALE := 1.6

static var _texture_cache := {}
static var mobile_ui_enabled := false
static var mobile_ui_scale_factor := 1.0


# -----------------------------------------------------------------------------
# Utilidades básicas
# -----------------------------------------------------------------------------

static func full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


static func set_mobile_ui_enabled(enabled: bool, scale_factor: float = DEFAULT_MOBILE_UI_SCALE) -> void:
	mobile_ui_enabled = enabled
	mobile_ui_scale_factor = clampf(scale_factor, 1.0, 3.0) if enabled else 1.0


## Scales a UI panel around the appropriate edge/center, preserving its layout anchor.
static func apply_mobile_scale(control: Control, enabled: bool, pivot_mode: String = "auto", scale_override: float = -1.0) -> void:
	if not control.has_meta("_mobile_original_scale"):
		control.set_meta("_mobile_original_scale", control.scale)
		control.set_meta("_mobile_original_pivot", control.pivot_offset)
		control.set_meta("_mobile_pivot_mode", pivot_mode)
		control.resized.connect(_refresh_mobile_transform_on_resize.bind(weakref(control)))
	else:
		control.set_meta("_mobile_pivot_mode", pivot_mode)
	control.set_meta("_mobile_scale_override", scale_override)
	_refresh_mobile_transform(weakref(control), enabled)
	_queue_mobile_transform(control)


static func _refresh_mobile_transform(control_ref: WeakRef, enabled: bool) -> void:
	var control := control_ref.get_ref() as Control
	if control == null or not control.has_meta("_mobile_original_scale"):
		return
	if enabled:
		var pivot_mode := String(control.get_meta("_mobile_pivot_mode", "auto"))
		control.scale = (control.get_meta("_mobile_original_scale") as Vector2) * _fitted_mobile_scale(control, pivot_mode)
		control.pivot_offset = _mobile_pivot(control, pivot_mode)
	else:
		control.scale = control.get_meta("_mobile_original_scale")
		control.pivot_offset = control.get_meta("_mobile_original_pivot")


static func _refresh_mobile_transform_on_resize(control_ref: WeakRef) -> void:
	_refresh_mobile_transform(control_ref, mobile_ui_enabled)
	var control := control_ref.get_ref() as Control
	if control != null:
		_queue_mobile_transform(control)


static func _queue_mobile_transform(control: Control) -> void:
	control.call_deferred("set", "scale", control.scale)
	control.call_deferred("set", "pivot_offset", control.pivot_offset)


static func _fitted_mobile_scale(control: Control, pivot_mode: String) -> float:
	var factor := float(control.get_meta("_mobile_scale_override", -1.0))
	if factor < 0.0:
		factor = mobile_ui_scale_factor
	var centered_pivot := _mobile_pivot(control, pivot_mode)
	var viewport_size := control.get_viewport_rect().size
	if not is_zero_approx(control.size.x) and is_equal_approx(centered_pivot.x, control.size.x * 0.5):
		factor = minf(factor, viewport_size.x / control.size.x)
	if not is_zero_approx(control.size.y) and is_equal_approx(centered_pivot.y, control.size.y * 0.5):
		factor = minf(factor, viewport_size.y / control.size.y)
	return maxf(1.0, factor)


static func _mobile_pivot(control: Control, pivot_mode: String) -> Vector2:
	if pivot_mode == "center":
		return control.size * 0.5
	var pivot := control.size * 0.5
	if is_equal_approx(control.anchor_left, control.anchor_right):
		if is_equal_approx(control.anchor_left, 0.0):
			pivot.x = 0.0
		elif is_equal_approx(control.anchor_right, 1.0):
			pivot.x = control.size.x
	if is_equal_approx(control.anchor_top, control.anchor_bottom):
		if is_equal_approx(control.anchor_top, 0.0):
			pivot.y = 0.0
		elif is_equal_approx(control.anchor_bottom, 1.0):
			pivot.y = control.size.y
	return pivot


static func _sync_modal_wrapper_size(wrapper_ref: WeakRef, card_ref: WeakRef) -> void:
	var wrapper := wrapper_ref.get_ref() as Control
	var card := card_ref.get_ref() as Control
	if wrapper != null and card != null:
		wrapper.custom_minimum_size = card.get_combined_minimum_size()


static func margin(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var container := MarginContainer.new()
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)
	return container


static func panel_style(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	return style


static func label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


## Texto que salta de línea (descripciones, avisos). `min_width` evita que el contenedor lo aplaste.
static func wrapped_label(text: String, font_size: int, color: Color, min_width: float = 0.0) -> Label:
	var result := label(text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(min_width, 0)
	return result


# -----------------------------------------------------------------------------
# Skin pixel-art: texturas y cajas
# -----------------------------------------------------------------------------

static func _skin(texture_name: String) -> Texture2D:
	if not _texture_cache.has(texture_name):
		_texture_cache[texture_name] = load(SKIN_DIR + texture_name + ".png")
	return _texture_cache[texture_name]


## Caja de 9 cortes con una textura del skin. `content` = márgenes interiores (izq, arriba, der, abajo).
## Los márgenes interiores por defecto (arriba 10 + abajo 14) obligan a que el botón mida al menos
## ~40 px con texto pequeño: es lo que necesitan los bordes del 9-slice (18 + 22) para no aplastarse.
static func texture_box(texture_name: String, pressed_margins: bool = false, content: Vector4 = Vector4(14, 10, 14, 14)) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _skin(texture_name)
	var m := SKIN_PRESSED_MARGINS if pressed_margins else SKIN_NORMAL_MARGINS
	box.texture_margin_left = m.x
	box.texture_margin_top = m.y
	box.texture_margin_right = m.z
	box.texture_margin_bottom = m.w
	box.content_margin_left = content.x
	box.content_margin_top = content.y
	box.content_margin_right = content.z
	box.content_margin_bottom = content.w
	return box


## Marco de las ventanas (pergamino claro con remaches y "labio" inferior).
## Los argumentos se ignoran: existen para no romper llamadas antiguas.
static func card_style(_radius: int = 16, _border: Color = Color.TRANSPARENT, _border_width: int = 1) -> StyleBoxTexture:
	return texture_box("panel", false, Vector4(6, 4, 6, 12))


## Tarjeta pequeña del HUD con la misma textura de pergamino que los menús, pero con cortes
## (9-slice) más cortos para que quepa en tarjetas de ~40 px de alto sin deformarse.
static func hud_card_style() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _skin("panel")
	box.texture_margin_left = 12
	box.texture_margin_top = 10
	box.texture_margin_right = 12
	box.texture_margin_bottom = 12
	box.content_margin_left = 0
	box.content_margin_top = 0
	box.content_margin_right = 0
	box.content_margin_bottom = 4
	return box


## Traduce un color de la paleta oscura a su equivalente de tinta, legible sobre pergamino.
static func on_paper(color: Color) -> Color:
	if color.is_equal_approx(COLOR_MINT):
		return INK_GOOD
	if color.is_equal_approx(COLOR_RED):
		return INK_BAD
	if color.is_equal_approx(COLOR_ACCENT):
		return INK_ACCENT
	if color.is_equal_approx(COLOR_MUTED) or color.is_equal_approx(COLOR_FAINT):
		return INK_SOFT
	if color.is_equal_approx(COLOR_TEXT):
		return INK
	return color.darkened(0.55)


## Recuadro hundido (más oscuro) para agrupar contenido dentro de una ventana.
static func inset_style() -> StyleBoxTexture:
	return texture_box("inset", true, Vector4(6, 6, 6, 8))


# -----------------------------------------------------------------------------
# Botones
# -----------------------------------------------------------------------------

## Aplica el skin a un botón. `variant`: "default" (arena), "primary" (verde) o "danger" (rojo).
static func skin_button(button: Button, variant: String = "default") -> void:
	var normal_name := "btn_normal"
	var hover_name := "btn_hover"
	var pressed_name := "btn_pressed"
	match variant:
		"primary":
			normal_name = "btn_primary"
			hover_name = "btn_primary_hover"
			pressed_name = "btn_primary_pressed"
		"danger":
			normal_name = "btn_danger"
			hover_name = "btn_danger_hover"
			pressed_name = "btn_danger_pressed"
	button.add_theme_stylebox_override("normal", texture_box(normal_name))
	button.add_theme_stylebox_override("hover", texture_box(hover_name))
	button.add_theme_stylebox_override("hover_pressed", texture_box(pressed_name, true, Vector4(14, 9, 14, 9)))
	button.add_theme_stylebox_override("pressed", texture_box(pressed_name, true, Vector4(14, 9, 14, 9)))
	button.add_theme_stylebox_override("disabled", texture_box("btn_disabled"))
	# El foco (teclado) se dibuja como un contorno por fuera del botón.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = INK
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(2)
	button.add_theme_stylebox_override("focus", focus)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	button.add_theme_color_override("font_disabled_color", INK_FAINT)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.set_meta("variant", variant)
	_wire_button(button)


## Interruptor (CheckButton) con el mismo aspecto pixel-art que el resto: pastilla arena
## cuando está apagado y verde cuando está encendido, con pomo crema y borde de tinta.
static func check_button(text: String, font_size: int = 14) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	skin_check(check, font_size)
	return check


static func skin_check(check: CheckButton, font_size: int = 14) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 6
	empty.content_margin_bottom = 6
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		check.add_theme_stylebox_override(style_name, empty)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = INK
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(2)
	check.add_theme_stylebox_override("focus", focus)
	var off_icon := _switch_texture(false, false)
	var on_icon := _switch_texture(true, false)
	check.add_theme_icon_override("unchecked", off_icon)
	check.add_theme_icon_override("checked", on_icon)
	check.add_theme_icon_override("unchecked_disabled", _switch_texture(false, true))
	check.add_theme_icon_override("checked_disabled", _switch_texture(true, true))
	# Godot 4.4+ usa estos nombres para los interruptores que van a la derecha del texto.
	check.add_theme_icon_override("unchecked_mirrored", off_icon)
	check.add_theme_icon_override("checked_mirrored", on_icon)
	check.add_theme_icon_override("unchecked_disabled_mirrored", _switch_texture(false, true))
	check.add_theme_icon_override("checked_disabled_mirrored", _switch_texture(true, true))
	check.add_theme_constant_override("h_separation", 12)
	check.add_theme_font_size_override("font_size", font_size)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(color_name, INK)
	check.add_theme_color_override("font_disabled_color", INK_FAINT)
	check.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not check.has_meta("_wired"):
		check.set_meta("_wired", true)
		check.mouse_entered.connect(func() -> void:
			if not check.disabled:
				play_sfx("ui_hover"))
		check.toggled.connect(func(_on: bool) -> void: play_sfx("ui_click"))


## Dibuja la pastilla del interruptor en baja resolución (22 x 12) y la amplía x2 sin suavizar.
static func _switch_texture(on: bool, disabled: bool) -> ImageTexture:
	var key := "switch_%s_%s" % [on, disabled]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var w := 22
	var h := 12
	var ink := INK_FAINT if disabled else INK
	var body := Color("#86C76A") if on else Color("#E3C896")
	if disabled:
		body = Color("#CDBFA6")
	var knob := PAPER_LIGHT
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Pastilla con esquinas recortadas (estilo pixel): borde de tinta y relleno.
	for y in h:
		for x in w:
			var corner_x := mini(x, w - 1 - x)
			var corner_y := mini(y, h - 1 - y)
			if corner_x + corner_y < 2:
				continue
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 or (corner_x + corner_y == 2 and corner_x < 2 and corner_y < 2)
			image.set_pixel(x, y, ink if edge else body)
	# Pomo cuadrado de 6 x 6 con borde, a la izquierda (apagado) o a la derecha (encendido).
	var knob_x := w - 9 if on else 3
	for y in range(3, 9):
		for x in range(knob_x, knob_x + 6):
			var knob_edge := x == knob_x or x == knob_x + 5 or y == 3 or y == 8
			var knob_corner := (x == knob_x or x == knob_x + 5) and (y == 3 or y == 8)
			if knob_corner:
				continue
			image.set_pixel(x, y, ink if knob_edge else knob)
	image.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	return texture


## Cambia el color de un botón ya creado (p. ej. la pestaña activa pasa a verde).
static func set_variant(button: Button, variant: String) -> void:
	skin_button(button, variant)


## Compatibilidad con llamadas antiguas: ahora el aspecto sale del skin.
static func apply_button_style(button: Button, _normal: Color = Color.WHITE, _hover: Color = Color.WHITE, _pressed: Color = Color.WHITE) -> void:
	skin_button(button, "primary")


static func apply_ghost_style(button: Button) -> void:
	skin_button(button, "default")


static func primary_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	skin_button(button, "primary")
	return button


## Botón rojizo para acciones que no se pueden deshacer (borrar, salir sin guardar).
static func danger_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	skin_button(button, "danger")
	return button


static func ghost_button(text: String, font_size: int = 12) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	skin_button(button, "default")
	return button


## Botón grande de los menús (título y pausa). `primary` lo pone verde y `danger` rojo.
## No fija el ancho: lo reparte el contenedor (columna completa o rejilla de 2).
static func menu_button(text: String, primary: bool = false, danger: bool = false) -> Button:
	var button: Button
	if danger:
		button = danger_button(text, 16)
	elif primary:
		button = primary_button(text, 17)
	else:
		button = ghost_button(text, 16)
	button.custom_minimum_size = Vector2(0, 50)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


## Sonidos y rebote de los botones: tic al pasar el ratón (o con el teclado), clic al pulsar
## y un pequeño "aplastón" mientras se mantiene pulsado. Se conecta una sola vez por botón.
static func _wire_button(button: Button) -> void:
	if button.has_meta("_wired"):
		return
	button.set_meta("_wired", true)
	button.resized.connect(func() -> void: button.pivot_offset = button.size / 2.0)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			play_sfx("ui_hover")
			_scale_to(button, 1.035, 0.08))
	button.mouse_exited.connect(func() -> void: _scale_to(button, 1.0, 0.1))
	button.focus_entered.connect(func() -> void:
		if not button.is_hovered() and not button.disabled:
			play_sfx("ui_hover"))
	button.button_down.connect(func() -> void: _scale_to(button, 0.965, 0.05))
	button.button_up.connect(func() -> void: _scale_to(button, 1.035 if button.is_hovered() else 1.0, 0.09))
	button.pressed.connect(func() -> void: play_sfx("ui_click"))


static func _scale_to(control: Control, target: float, time: float) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	if control.has_meta("_scale_tween"):
		var old: Tween = control.get_meta("_scale_tween")
		if old != null and old.is_valid():
			old.kill()
	var tween := control.create_tween()
	control.set_meta("_scale_tween", tween)
	tween.tween_property(control, "scale", Vector2(target, target), time).set_trans(Tween.TRANS_SINE)


static func play_sfx(sound_name: String, pitch_jitter: float = 0.0, gain: float = 1.0) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var sfx := (loop as SceneTree).root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.play(sound_name, pitch_jitter, gain)


# -----------------------------------------------------------------------------
# Otros elementos
# -----------------------------------------------------------------------------

static func divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.color = Color(0.17, 0.145, 0.25, 0.28)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Etiqueta con aspecto de tecla (para la lista de controles).
static func keycap(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(34, 0)
	var style := panel_style(PAPER_LIGHT, 3, INK, 2)
	style.border_width_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var padding := margin(8, 8, 3, 3)
	chip.add_child(padding)
	var key := label(text, 13, INK)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	padding.add_child(key)
	return chip


## Recuadro hundido para agrupar contenido dentro de una ventana.
## Se añade a `into` y devuelve la columna interior donde poner los elementos.
static func section_card(into: Control, padding: int = 16, separation: int = 12) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", inset_style())
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	into.add_child(panel)
	var inner_margin := margin(padding, padding, padding - 6, padding - 6)
	panel.add_child(inner_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	inner_margin.add_child(column)
	return column


## Deslizador: carril marrón, relleno verde y pomo crema con aro oscuro.
static func style_slider(slider: HSlider) -> void:
	var track := panel_style(Color("#6B4636"), 3, INK, 2)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := panel_style(Color("#86C76A"), 3, INK, 2)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _circle_texture(20, PAPER_LIGHT, INK)
	var knob_hover := _circle_texture(20, Color("#FFFFFF"), INK)
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob_hover)
	slider.add_theme_icon_override("grabber_disabled", knob)
	slider.custom_minimum_size = Vector2(0, 28)


static func _circle_texture(size: int, fill: Color, ring: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := (size - 1) / 2.0
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(Vector2(middle, middle))
			var alpha := clampf(middle + 0.5 - distance, 0.0, 1.0)
			var color := ring if distance > middle - 2.2 else fill
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)


## Campo de texto claro con borde oscuro (escribe con tinta).
static func line_edit(placeholder: String, font_size: int) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.add_theme_font_size_override("font_size", font_size)
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("font_placeholder_color", INK_FAINT)
	input.add_theme_color_override("caret_color", INK)
	input.add_theme_color_override("selection_color", Color("#E8A565"))
	var normal := panel_style(PAPER_LIGHT, 3, INK, 2)
	var focus := panel_style(Color("#FFFAE8"), 3, INK_ACCENT, 3)
	for style in [normal, focus]:
		style.content_margin_left = 12
		style.content_margin_right = 12
	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)
	return input


# -----------------------------------------------------------------------------
# Ventanas (modales)
# -----------------------------------------------------------------------------

## Prepara `host` como ventana modal: fondo oscuro que bloquea el ratón, tarjeta centrada
## y una columna donde añadir el contenido. Devuelve {"shade", "card", "content"}.
## `width` es el ancho mínimo de la tarjeta; `z` el orden de dibujo respecto al HUD.
static func build_modal(host: Control, width: float, z: int, shade_alpha: float = 0.78, pad: Vector2 = Vector2(28, 22)) -> Dictionary:
	full_rect(host)
	host.z_index = z
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var shade := ColorRect.new()
	full_rect(shade)
	shade.color = Color(0.02, 0.04, 0.08, shade_alpha)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(shade)

	var center := CenterContainer.new()
	full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(wrapper)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.add_theme_stylebox_override("panel", card_style())
	full_rect(card)
	wrapper.add_child(card)
	card.minimum_size_changed.connect(_sync_modal_wrapper_size.bind(weakref(wrapper), weakref(card)))
	_sync_modal_wrapper_size(weakref(wrapper), weakref(card))
	host.set_meta("_mobile_scale_target", card)
	apply_mobile_scale(card, mobile_ui_enabled, "center")
	var padding := margin(int(pad.x), int(pad.x), int(pad.y), int(pad.y))
	card.add_child(padding)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	padding.add_child(content)
	return {"shade": shade, "card": card, "content": content}


## Cabecera de ventana: título grande, subtítulo en mayúsculas y botón "Cerrar" a la derecha.
## Sin `on_close` no se dibuja el botón.
static func modal_header(title: String, subtitle: String, on_close: Callable = Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	copy.add_child(label(title, 26, INK))
	if not subtitle.is_empty():
		copy.add_child(label(subtitle, 12, INK_ACCENT))
	if on_close.is_valid():
		var close_button := ghost_button("Cerrar", 14)
		close_button.custom_minimum_size = Vector2(96, 42)
		close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close_button.pressed.connect(on_close)
		row.add_child(close_button)
	return row


static func fade_in(control: Control, duration: float = 0.15) -> void:
	control.modulate.a = 0.0
	control.create_tween().tween_property(control, "modulate:a", 1.0, duration)


## 3725 -> "1:02:05"; 754 -> "12:34".
static func format_time(total_seconds: int) -> String:
	var seconds := maxi(total_seconds, 0)
	var hours := floori(seconds / 3600.0)
	var minutes := floori((seconds % 3600) / 60.0)
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds % 60]
	return "%d:%02d" % [minutes, seconds % 60]
