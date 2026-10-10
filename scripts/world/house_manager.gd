class_name HouseManager
extends RefCounted
## Puertas de las casas del pueblo. Lee los Sprite2D de World.tscn (no hay que
## tocar la escena), dibuja una puerta en las casas de pared lisa y guarda dónde
## debe pararse el jugador para entrar con la acción "enter" (F).
##
## Para dar interior a una casa nueva: añade una entrada a HOUSES y un diseño con
## el mismo "interior" en InteriorDb.LAYOUTS.

const DOOR_REACH := 40.0
## La puerta pintada de las casas con region_rect.x = 144 queda a la derecha del centro.
const PAINTED_DOOR_OFFSET := 12.5   # en píxeles del sprite (antes de la escala)
## Distancia desde el centro del sprite hasta la base de la puerta.
const DOOR_BASE_Y := 62.0
const EXIT_GAP := 14.0

const HOUSES := [
	{"node": "MeadowHouse", "name": "Casa del Prado", "interior": "meadow"},
	{"node": "SunlitInn", "name": "Posada del Sol", "interior": "inn"},
	{"node": "Bakery", "name": "Panadería", "interior": "bakery"},
	{"node": "Smithy", "name": "Herrería", "interior": "smithy"},
	{"node": "Cottage", "name": "Cabaña", "interior": "cottage"},
	{"node": "Farmhouse", "name": "Granja", "interior": "farmhouse"},
	{"node": "Carpenter", "name": "Carpintería", "interior": "carpenter"},
	{"node": "GeneralStore", "name": "Tienda General", "interior": "store"},
	{"node": "MillHouse", "name": "Molino", "interior": "mill"},
	{"node": "LakeHouse", "name": "Casa del Lago", "interior": "lake"},
]

## Cada puerta: {name, interior, point (donde se interactúa), exit_position (dónde reaparece el jugador)}
var doors: Array[Dictionary] = []


func setup(world: Node2D) -> void:
	doors.clear()
	for house in HOUSES:
		var sprite := world.find_child(String(house["node"]), true, false) as Sprite2D
		if sprite == null:
			push_warning("Casa '%s' no encontrada en World; se ignora." % house["node"])
			continue
		var door_x := sprite.position.x
		if sprite.region_rect.position.x < 1.0:
			_add_door_overlay(sprite)
		else:
			door_x += PAINTED_DOOR_OFFSET * sprite.scale.x
		var point := Vector2(door_x, sprite.position.y + DOOR_BASE_Y)
		doors.append({
			"name": String(house["name"]),
			"interior": String(house["interior"]),
			"point": point,
			"exit_position": point + Vector2(0, EXIT_GAP),
		})


## Puerta más cercana al jugador dentro de DOOR_REACH, o {} si no hay.
func nearest_door(player_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := DOOR_REACH
	for door in doors:
		var distance := player_position.distance_to(door["point"])
		if distance <= best_distance:
			best_distance = distance
			best = door
	return best


## Las casas de pared lisa (region x = 0) no traen puerta: se pega la del atlas House.png.
func _add_door_overlay(house: Sprite2D) -> void:
	var door := _house_piece(house, Rect2(128, 3, 16, 23), Vector2(-8, 9))
	house.add_child(door)
	var step := _house_piece(house, Rect2(112, 41, 16, 9), Vector2(-8, 33))
	house.add_child(step)


func _house_piece(house: Sprite2D, region: Rect2, local_position: Vector2) -> Sprite2D:
	var piece := Sprite2D.new()
	piece.texture = house.texture
	piece.texture_filter = house.texture_filter
	piece.region_enabled = true
	piece.region_rect = region
	piece.centered = false
	piece.position = local_position
	piece.z_index = 1
	return piece
