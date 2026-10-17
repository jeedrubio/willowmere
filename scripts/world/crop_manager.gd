class_name CropManager
extends Node
## Parcela interactiva de la granja. Las cosechas avanzan una etapa al amanecer
## solo si se regaron ese día; los cultivos no crecen con tiempo real.

const CROP_TEXTURE: Texture2D = preload("res://asset_pack/Objects/Spring Crops.png")
const FIELD_ORIGIN := Vector2(1872, 496)
const CELL_SIZE := 32.0
const FIELD_COLUMNS := 6
const FIELD_ROWS := 4
const INTERACTION_DISTANCE := 50.0


class CropPlot:
	extends RefCounted
	var cell := Vector2i.ZERO
	var center := Vector2.ZERO
	var tilled := false
	var crop_id := ""
	var stage := 0
	var watered_today := false
	var soil: Polygon2D
	var furrow: Line2D
	var crop_sprite: Sprite2D

	func is_planted() -> bool:
		return not crop_id.is_empty()

	func is_mature() -> bool:
		if not is_planted():
			return false
		var row := ItemDb.CROP_ROWS.find(crop_id)
		return row >= 0 and stage >= int(ItemDb.MATURE_STAGES[row])


var plots: Dictionary = {}
var active_world: Node2D
var _plot_layer: Node2D


func setup(world: Node) -> void:
	active_world = world as Node2D


## Registra el campo la primera vez que se visita y lo conserva al cambiar de zona.
func activate_world(world: Node2D) -> void:
	active_world = world
	if world != null and world.name == "FarmWorld":
		_ensure_field(world)


func _ensure_field(world: Node2D) -> void:
	_plot_layer = world.get_node_or_null("FarmPlots") as Node2D
	if _plot_layer == null:
		_plot_layer = Node2D.new()
		_plot_layer.name = "FarmPlots"
		_plot_layer.z_index = 1
		world.add_child(_plot_layer)
	if not plots.is_empty():
		return
	for y in FIELD_ROWS:
		for x in FIELD_COLUMNS:
			var plot := CropPlot.new()
			plot.cell = Vector2i(x, y)
			plot.center = FIELD_ORIGIN + Vector2((float(x) + 0.5) * CELL_SIZE, (float(y) + 0.5) * CELL_SIZE)
			plots[plot.cell] = plot


## Busca la casilla a la que apunta el jugador, usando coordenadas locales del mundo.
func target_plot(target_position: Vector2, player_position: Vector2) -> CropPlot:
	if active_world == null or active_world.name != "FarmWorld" or plots.is_empty():
		return null
	var cell_x := floori((target_position.x - FIELD_ORIGIN.x) / CELL_SIZE)
	var cell_y := floori((target_position.y - FIELD_ORIGIN.y) / CELL_SIZE)
	if cell_x < 0 or cell_x >= FIELD_COLUMNS or cell_y < 0 or cell_y >= FIELD_ROWS:
		return null
	var plot := plots.get(Vector2i(cell_x, cell_y)) as CropPlot
	if plot == null or player_position.distance_to(plot.center) > INTERACTION_DISTANCE:
		return null
	return plot


func till(plot: CropPlot) -> bool:
	if plot == null or plot.tilled:
		return false
	plot.tilled = true
	_create_soil_visuals(plot)
	_record_action("Labranza", "Preparó tierra en la parcela %s" % _plot_label(plot))
	return true


func plant(plot: CropPlot, seed_id: String) -> bool:
	if plot == null or not plot.tilled or plot.is_planted() or not ItemDb.is_seed(seed_id):
		return false
	var crop_id := ItemDb.crop_for_seed(seed_id)
	if crop_id.is_empty():
		return false
	plot.crop_id = crop_id
	plot.stage = 0
	plot.watered_today = false
	plot.crop_sprite = Sprite2D.new()
	plot.crop_sprite.name = "Crop_%s" % crop_id
	plot.crop_sprite.texture = CROP_TEXTURE
	plot.crop_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plot.crop_sprite.region_enabled = true
	plot.crop_sprite.scale = Vector2(1.25, 1.25)
	plot.crop_sprite.position = plot.center + Vector2(0, 12)
	plot.crop_sprite.z_index = int(plot.center.y) + 10
	_plot_layer.add_child(plot.crop_sprite)
	_update_crop_visual(plot)
	_update_soil_visual(plot)
	_record_action("Siembra", "Plantó %s en la parcela %s" % [ItemDb.display_name(crop_id), _plot_label(plot)])
	return true


func water(plot: CropPlot) -> bool:
	if plot == null or not plot.is_planted() or plot.is_mature() or plot.watered_today:
		return false
	plot.watered_today = true
	_update_soil_visual(plot)
	_record_action("Riego", "Regó %s en la parcela %s" % [ItemDb.display_name(plot.crop_id), _plot_label(plot)])
	return true


## Devuelve el id del cultivo cosechado, o una cadena vacía si no está maduro.
func harvest(plot: CropPlot) -> String:
	if plot == null or not plot.is_mature():
		return ""
	var crop_id := plot.crop_id
	plot.crop_id = ""
	plot.stage = 0
	plot.watered_today = false
	if is_instance_valid(plot.crop_sprite):
		plot.crop_sprite.queue_free()
	plot.crop_sprite = null
	_update_soil_visual(plot)
	_record_action("Cosecha", "Cosechó %s en la parcela %s" % [ItemDb.display_name(crop_id), _plot_label(plot)])
	return crop_id


## Resuelve la noche que acaba de terminar y borra el estado de riego diario.
func advance_day(_new_day: int) -> void:
	for value in plots.values():
		var plot := value as CropPlot
		if not plot.is_planted():
			continue
		if plot.watered_today and not plot.is_mature():
			plot.stage += 1
			_update_crop_visual(plot)
		plot.watered_today = false
		_update_soil_visual(plot)


func _create_soil_visuals(plot: CropPlot) -> void:
	plot.soil = Polygon2D.new()
	plot.soil.name = "TilledSoil"
	plot.soil.polygon = PackedVector2Array([
		Vector2(-13, -11), Vector2(13, -11), Vector2(13, 11), Vector2(-13, 11),
	])
	plot.soil.position = plot.center
	plot.soil.z_index = int(plot.center.y)
	_plot_layer.add_child(plot.soil)
	plot.furrow = Line2D.new()
	plot.furrow.name = "SoilFurrows"
	plot.furrow.points = PackedVector2Array([Vector2(-9, -4), Vector2(9, -4)])
	plot.furrow.width = 1.5
	plot.furrow.default_color = Color("#5E402F")
	plot.furrow.position = plot.center
	plot.furrow.z_index = int(plot.center.y) + 1
	_plot_layer.add_child(plot.furrow)
	_update_soil_visual(plot)


func _update_soil_visual(plot: CropPlot) -> void:
	if not is_instance_valid(plot.soil):
		return
	plot.soil.color = Color("#61727A") if plot.watered_today else Color("#8A6040")
	if is_instance_valid(plot.furrow):
		plot.furrow.default_color = Color("#465961") if plot.watered_today else Color("#5E402F")


func _update_crop_visual(plot: CropPlot) -> void:
	if not is_instance_valid(plot.crop_sprite):
		return
	var row := ItemDb.CROP_ROWS.find(plot.crop_id)
	if row < 0:
		return
	plot.crop_sprite.region_rect = Rect2(plot.stage * 16, row * 32, 16, 32)
	plot.crop_sprite.z_index = int(plot.center.y) + 10


func _plot_label(plot: CropPlot) -> String:
	return "%d,%d" % [plot.cell.x + 1, plot.cell.y + 1]


func _record_action(action: String, details: String) -> void:
	var db := get_tree().root.get_node_or_null("DBManager")
	if db != null:
		db.registrar_evento(action, details)
