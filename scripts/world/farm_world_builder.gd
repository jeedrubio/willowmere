@tool
extends Node2D
## Builds a simple grassy floor from the existing ground atlas for the farm map.

const GROUND_SOURCE := 0
const MAP_COLUMNS := 142
const MAP_ROWS := 76


func _ready() -> void:
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground == null or not ground.get_used_cells().is_empty():
		return
	for y in range(MAP_ROWS):
		for x in range(MAP_COLUMNS):
			ground.set_cell(Vector2i(x, y), GROUND_SOURCE, Vector2i.ZERO)
