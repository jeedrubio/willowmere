class_name InteriorRoom
extends Node2D
## Habitación de una casa. Se reconstruye cada vez que entras (build) y se vacía
## al salir (clear). Vive lejos del pueblo, dentro de World, y Main teletransporta
## ahí al jugador; las posiciones que devuelve son coordenadas de World.

const EXIT_REACH := 42.0
const BED_REACH := 44.0

var _theme: Dictionary = {}
var _has_bed := false
var _bed_interaction_point := Vector2.ZERO


func _ready() -> void:
	scale = Vector2.ONE * InteriorDb.SCALE
	z_index = -100   # el suelo y las paredes (_draw) quedan debajo de todo
	visible = false


func build(house_id: String) -> void:
	clear()
	var layout: Dictionary = InteriorDb.LAYOUTS.get(house_id, InteriorDb.LAYOUTS["meadow"])
	_theme = InteriorDb.THEMES[String(layout["theme"])]
	_add_void()
	_add_room_collision()
	_add_exit_door()
	for item in layout["items"]:
		var entry: Array = item
		if entry.size() >= 4:
			_add_prop(String(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]))
		else:
			_add_prop(String(entry[0]), float(entry[1]), float(entry[2]))
	visible = true
	queue_redraw()


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_theme = {}
	_has_bed = false
	_bed_interaction_point = Vector2.ZERO
	visible = false
	queue_redraw()


## Dónde aparece el jugador al entrar (coordenadas de World).
func spawn_position() -> Vector2:
	return position + InteriorDb.SPAWN_POINT * InteriorDb.SCALE


## Zona de la puerta de salida (coordenadas de World).
func exit_point() -> Vector2:
	return position + InteriorDb.EXIT_POINT * InteriorDb.SCALE


func near_exit(player_position: Vector2) -> bool:
	return visible and player_position.distance_to(exit_point()) <= EXIT_REACH


func near_bed(player_position: Vector2) -> bool:
	return visible and _has_bed and player_position.distance_to(_bed_interaction_point) <= BED_REACH


## Dónde se despierta el jugador al completar una noche, en coordenadas de World.
func wake_position() -> Vector2:
	return _bed_interaction_point if _has_bed else spawn_position()


## Rectángulo por el que puede moverse el centro del jugador (coordenadas de World).
func player_bounds() -> Rect2:
	var s := InteriorDb.SCALE
	return Rect2(position + Vector2(20, 66) * s, Vector2(280, 118) * s)


## Centro de la habitación en coordenadas globales (para fijar la cámara).
func camera_center() -> Vector2:
	return global_position + InteriorDb.ROOM_SIZE * InteriorDb.SCALE / 2.0


func _z_for(local_y: float) -> int:
	return int(position.y + local_y * InteriorDb.SCALE)


func _add_void() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05)
	backdrop.position = Vector2(-900, -900)
	backdrop.size = Vector2(2200, 2000)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.z_as_relative = false
	backdrop.z_index = -110
	add_child(backdrop)


func _add_room_collision() -> void:
	var w := InteriorDb.ROOM_SIZE.x
	var h := InteriorDb.ROOM_SIZE.y
	_add_block(Rect2(0, 0, w, InteriorDb.WALL_HEIGHT + 2.0))
	_add_block(Rect2(0, 0, InteriorDb.SIDE, h))
	_add_block(Rect2(w - InteriorDb.SIDE, 0, InteriorDb.SIDE, h))
	_add_block(Rect2(0, InteriorDb.FRONT_Y, w, h - InteriorDb.FRONT_Y))


func _add_exit_door() -> void:
	var door := Sprite2D.new()
	door.texture = InteriorDb.ATLAS
	door.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	door.region_enabled = true
	door.region_rect = InteriorDb.DOOR_RECT
	door.centered = false
	door.position = Vector2(InteriorDb.ROOM_SIZE.x / 2.0 - 8.0, InteriorDb.FRONT_Y + 14.0 - 23.0)
	door.z_as_relative = false
	door.z_index = _z_for(InteriorDb.FRONT_Y) - 20
	add_child(door)


## (x, y) = centro de la base de la pieza. Si host_y >= 0 la pieza está apoyada
## sobre otro mueble cuya base está en host_y: se dibuja encima y no colisiona.
func _add_prop(prop_name: String, x: float, y: float, host_y: float = -1.0) -> void:
	if not InteriorDb.PROPS.has(prop_name):
		push_warning("Interior: pieza desconocida '%s'." % prop_name)
		return
	var def: Dictionary = InteriorDb.PROPS[prop_name]
	var rect: Rect2 = def["rect"]
	var kind := String(def.get("kind", "solid"))
	if not _has_bed and (prop_name == "bed_v" or prop_name == "bed_h"):
		_has_bed = true
		_bed_interaction_point = position + Vector2(x + 30.0, y - 8.0) * InteriorDb.SCALE

	var sprite := Sprite2D.new()
	sprite.texture = InteriorDb.ATLAS
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = rect
	sprite.centered = false
	sprite.position = Vector2(roundf(x - rect.size.x / 2.0), y - rect.size.y)
	sprite.z_as_relative = false
	if kind == "wall":
		sprite.z_index = -90
	elif kind == "floor":
		sprite.z_index = -80
	elif host_y >= 0.0:
		sprite.z_index = _z_for(host_y) + 1
	else:
		sprite.z_index = _z_for(y)
	add_child(sprite)

	if kind == "solid" and host_y < 0.0:
		var foot: Vector2 = def["foot"]
		_add_block(Rect2(x - foot.x / 2.0, y - foot.y, foot.x, foot.y))


func _add_block(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size / 2.0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _draw() -> void:
	if _theme.is_empty():
		return
	var w := InteriorDb.ROOM_SIZE.x
	var h := InteriorDb.ROOM_SIZE.y
	var wall_h := InteriorDb.WALL_HEIGHT
	var front_y := InteriorDb.FRONT_Y
	var side := InteriorDb.SIDE
	var floor_color: Color = _theme["floor"]
	var line_color: Color = _theme["floor_line"]
	var wall_color: Color = _theme["wall"]
	var wain_color: Color = _theme["wainscot"]
	var trim_color: Color = _theme["trim"]

	# Suelo de tablones
	draw_rect(Rect2(0, wall_h, w, front_y - wall_h), floor_color)
	var y := wall_h
	var row := 0
	while y < front_y:
		draw_line(Vector2(0, y), Vector2(w, y), line_color, 1.0)
		var x := 24.0 if row % 2 == 1 else 0.0
		while x < w:
			draw_line(Vector2(x, y), Vector2(x, minf(y + 8.0, front_y)), line_color, 1.0)
			x += 48.0
		y += 8.0
		row += 1
	draw_rect(Rect2(0, wall_h, w, 6), Color(0, 0, 0, 0.14))
	draw_rect(Rect2(side, wall_h, 5, front_y - wall_h), Color(0, 0, 0, 0.08))
	draw_rect(Rect2(w - side - 5, wall_h, 5, front_y - wall_h), Color(0, 0, 0, 0.08))

	# Pared del fondo con friso
	draw_rect(Rect2(0, 0, w, wall_h), wall_color)
	var stripe := 8.0
	while stripe < w:
		draw_line(Vector2(stripe, 4), Vector2(stripe, 35), wall_color.darkened(0.05), 1.0)
		stripe += 16.0
	draw_rect(Rect2(0, 36, w, wall_h - 36.0), wain_color)
	draw_rect(Rect2(0, 35, w, 2), trim_color)
	draw_rect(Rect2(0, wall_h - 3.0, w, 3), trim_color)
	draw_rect(Rect2(0, 0, w, 4), trim_color)

	# Paredes laterales y de enfrente
	draw_rect(Rect2(0, 0, side, h), trim_color)
	draw_rect(Rect2(w - side, 0, side, h), trim_color)
	draw_rect(Rect2(0, front_y, w, h - front_y), trim_color)
	draw_rect(Rect2(side, front_y - 2.0, w - side * 2.0, 2), trim_color.darkened(0.25))

	# Felpudo junto a la puerta
	var mat := Rect2(w / 2.0 - 13.0, front_y - 14.0, 26, 10)
	draw_rect(mat, Color("#8E3F3A"))
	draw_rect(mat, Color("#5E2724"), false, 1.0)
