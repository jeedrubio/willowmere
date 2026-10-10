class_name UiKit
extends RefCounted
## Colores y utilidades de estilo compartidas por toda la interfaz.

const COLOR_BORDER := Color("#35506B")
const COLOR_TEXT := Color("#F6F0DB")
const COLOR_MUTED := Color("#A5B3B1")
const COLOR_FAINT := Color("#71838B")
const COLOR_ACCENT := Color("#F2B35F")
const COLOR_MINT := Color("#77D3B0")
const COLOR_RED := Color("#F58D78")
const COLOR_CARD := Color("#142336")


static func full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


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


static func apply_button_style(button: Button, normal: Color, hover: Color, pressed: Color) -> void:
	button.add_theme_stylebox_override("normal", panel_style(normal, 8))
	button.add_theme_stylebox_override("hover", panel_style(hover, 8))
	button.add_theme_stylebox_override("pressed", panel_style(pressed, 8))
	button.add_theme_stylebox_override("focus", panel_style(hover, 8, COLOR_MINT, 1))


static func primary_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	apply_button_style(button, Color("#337C75"), Color("#4D9E91"), Color("#28655F"))
	button.add_theme_color_override("font_color", Color.WHITE)
	return button


static func ghost_button(text: String, font_size: int = 10) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	apply_ghost_style(button)
	return button


## Estilo "fantasma" (borde fino, fondo transparente) para un botón ya creado.
static func apply_ghost_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel_style(Color.TRANSPARENT, 8, COLOR_BORDER, 1))
	button.add_theme_stylebox_override("hover", panel_style(Color("#22384A"), 8, Color("#568080"), 1))
	button.add_theme_stylebox_override("pressed", panel_style(Color("#2A4C55"), 8, COLOR_MINT, 1))
	button.add_theme_stylebox_override("focus", panel_style(Color("#22384A"), 8, COLOR_MINT, 1))


## Botón grande para los menús (título y pausa). `primary` lo resalta.
static func menu_button(text: String, primary: bool = false) -> Button:
	var button: Button = primary_button(text, 14) if primary else ghost_button(text, 13)
	button.custom_minimum_size = Vector2(300, 46)
	return button


static func divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = COLOR_BORDER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Etiqueta con aspecto de tecla (para la lista de controles).
static func keycap(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", panel_style(Color("#0E1B2B"), 6, COLOR_BORDER, 1))
	var padding := margin(9, 9, 4, 4)
	chip.add_child(padding)
	padding.add_child(label(text, 11, COLOR_MINT))
	return chip


## Estilo oscuro con relleno verde para un HSlider.
static func style_slider(slider: HSlider) -> void:
	var track := panel_style(Color("#0A1523"), 4, COLOR_BORDER, 1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := panel_style(Color("#4D9E91"), 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _circle_texture(18, COLOR_TEXT)
	var knob_hover := _circle_texture(18, COLOR_MINT)
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob_hover)
	slider.add_theme_icon_override("grabber_disabled", knob)
	slider.custom_minimum_size = Vector2(0, 26)


static func _circle_texture(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := (size - 1) / 2.0
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(Vector2(middle, middle))
			var alpha := clampf(middle + 0.5 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)


## Campo de texto con el estilo oscuro del juego.
static func line_edit(placeholder: String, font_size: int) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.add_theme_font_size_override("font_size", font_size)
	input.add_theme_color_override("font_color", COLOR_TEXT)
	input.add_theme_color_override("font_placeholder_color", COLOR_FAINT)
	input.add_theme_stylebox_override("normal", panel_style(Color("#0A1523"), 9, COLOR_BORDER, 1))
	input.add_theme_stylebox_override("focus", panel_style(Color("#0A1523"), 9, COLOR_MINT, 1))
	return input
