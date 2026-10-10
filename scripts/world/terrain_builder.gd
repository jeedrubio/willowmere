@tool
class_name TerrainBuilder
extends Node2D
## Pinta el terreno inicial en las capas TileMapLayer bajo este nodo:
## Ground, Water, Garden, Border (diseño de terrain/ground_map.gd) y Decor.
##
## Cómo funciona:
## - Al abrir World.tscn en el editor, cada capa que esté VACÍA se pinta con el
##   diseño inicial y la escena se guarda sola. Desde ese momento los tiles
##   viven dentro de World.tscn y se editan con el panel TileMap como cualquier
##   otro mapa.
## - Si una capa ya tiene tiles, este script no la toca.
## - Al ejecutar el juego solo rellena capas vacías (red de seguridad).
## - Casilla "Repaint": borra todas las capas y vuelve al diseño inicial.
## - El diseño inicial lo genera tools/generate_terrain.py.
## - La colisión del agua no está aquí: vive en el TileSet (Physics Layer 0).

const GroundMap := preload("res://terrain/ground_map.gd")
const GROUND_SOURCE := 0
const DECOR_SOURCE := 1
## Capas que se pintan desde ground_map.gd (el nombre del nodo coincide con la
## constante en mayúsculas dentro de ground_map.gd).
const MAP_LAYERS := ["Ground", "Water", "Garden", "Border"]

## Pinta solo las capas vacías al abrir World.tscn y guarda la escena.
## Desactívalo si quieres dejar una capa vacía a propósito.
@export var auto_paint_when_empty := true

## Marca esta casilla para borrar y repintar el terreno con el diseño original.
@export var repaint := false:
	set(value):
		repaint = false
		if value and is_inside_tree() and (not Engine.is_editor_hint() or _is_edited_scene()):
			paint(true)
			_save_scene_if_editing()


func _ready() -> void:
	if Engine.is_editor_hint():
		# El editor todavía no sabe cuál es la escena abierta; se comprueba al final del fotograma.
		_paint_in_editor.call_deferred()
	else:
		paint(false)


func _paint_in_editor() -> void:
	if not auto_paint_when_empty or not is_inside_tree() or not _is_edited_scene():
		return
	if paint(false):
		_save_scene_if_editing()
		print("Willowmere: terreno pintado en las capas de World.tscn.")


## En el editor solo se pinta cuando se está editando World.tscn directamente.
## Si World está instanciada dentro de Main.tscn, pintar ahí haría que Main
## guardara una copia de los tiles que taparía los cambios hechos en World.
func _is_edited_scene() -> bool:
	var tree := get_tree()
	return tree != null and tree.edited_scene_root != null and tree.edited_scene_root == owner


## Pinta las capas vacías (o todas si `force`). Devuelve true si pintó algo.
func paint(force: bool) -> bool:
	var painted := false
	for layer_name in MAP_LAYERS:
		var layer := get_node_or_null(layer_name) as TileMapLayer
		if layer != null and (force or layer.get_used_cells().is_empty()):
			_paint_map_layer(layer, _rows_for(layer_name))
			painted = true
	var decor := get_node_or_null("Decor") as TileMapLayer
	if decor != null and (force or decor.get_used_cells().is_empty()):
		_paint_decor(decor)
		painted = true
	return painted


func _rows_for(layer_name: String) -> Array:
	match layer_name:
		"Ground":
			return GroundMap.GROUND
		"Water":
			return GroundMap.WATER
		"Garden":
			return GroundMap.GARDEN
		"Border":
			return GroundMap.BORDER
	return []


func _save_scene_if_editing() -> void:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return
	var editor_interface: Object = Engine.get_singleton("EditorInterface")
	editor_interface.call("save_scene")


func _paint_map_layer(layer: TileMapLayer, rows: Array) -> void:
	layer.clear()
	var alphabet: String = GroundMap.ALPHABET
	var base := alphabet.length()
	var columns: int = GroundMap.ATLAS_COLUMNS
	var code_length: int = GroundMap.CODE_LENGTH
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(floori(float(row.length()) / float(code_length))):
			var index := 0
			var valid := true
			for k in range(code_length):
				var digit := alphabet.find(row[x * code_length + k])
				if digit < 0:
					valid = false
					break
				index = index * base + digit
			if not valid:
				continue
			var atlas_coords := Vector2i(index % columns, floori(float(index) / float(columns)))
			layer.set_cell(Vector2i(x, y), GROUND_SOURCE, atlas_coords)


## Estampa la hoja completa del pasto decorativo en cada origen (como hacían
## los antiguos sprites GrassTexture1-4).
func _paint_decor(layer: TileMapLayer) -> void:
	layer.clear()
	if layer.tile_set == null:
		return
	var source := layer.tile_set.get_source(DECOR_SOURCE) as TileSetAtlasSource
	if source == null:
		return
	var grid := source.get_atlas_grid_size()
	var origins: Array = GroundMap.DECOR_ORIGINS
	for origin in origins:
		for ty in range(grid.y):
			for tx in range(grid.x):
				var coords := Vector2i(tx, ty)
				if source.has_tile(coords):
					layer.set_cell(origin + coords, DECOR_SOURCE, coords)
