class_name CropManager
extends Node

const SECONDS_PER_STAGE := 9.0
const REGROW_DELAY_MIN := 6.0
const REGROW_DELAY_MAX := 14.0
const START_MATURE_CHANCE := 0.4
const CROP_TEXTURE_FILE := "Spring Crops.png"


class CropPlot:
	extends RefCounted
	var sprite: Sprite2D
	var row := 0
	var stage := 0
	var empty := false
	var timer := 0.0
	var stage_length := 1.0
	var base_scale := Vector2.ONE

	func mature_stage() -> int:
		return int(ItemDb.MATURE_STAGES[row])

	func is_mature() -> bool:
		return not empty and stage >= mature_stage()

	func item_id() -> String:
		return String(ItemDb.CROP_ROWS[row])

	func progress() -> float:
		if empty:
			return 0.0
		if is_mature():
			return 1.0
		var into_stage := 1.0 - clampf(timer / stage_length, 0.0, 1.0)
		return clampf((float(stage) + into_stage) / float(mature_stage()), 0.0, 1.0)


var plots: Array[CropPlot] = []
var _rng := RandomNumberGenerator.new()


func setup(world: Node) -> void:
	_rng.randomize()
	for child in world.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if not sprite.texture.resource_path.ends_with(CROP_TEXTURE_FILE):
			continue
		var row := int(sprite.region_rect.position.y / 32.0)
		if row < 0 or row >= ItemDb.CROP_ROWS.size():
			continue
		var plot := CropPlot.new()
		plot.sprite = sprite
		plot.row = row
		plot.base_scale = sprite.scale
		if _rng.randf() < START_MATURE_CHANCE:
			plot.stage = plot.mature_stage()
		else:
			plot.stage = _rng.randi_range(0, plot.mature_stage() - 1)
		_start_stage_timer(plot)
		_apply_visual(plot, false)
		plots.append(plot)


func _process(delta: float) -> void:
	for plot in plots:
		if plot.empty:
			plot.timer -= delta
			if plot.timer <= 0.0:
				plot.empty = false
				plot.stage = 0
				_start_stage_timer(plot)
				_apply_visual(plot, true)
		elif not plot.is_mature():
			plot.timer -= delta
			if plot.timer <= 0.0:
				plot.stage += 1
				_start_stage_timer(plot)
				_apply_visual(plot, true)


func _start_stage_timer(plot: CropPlot) -> void:
	plot.stage_length = SECONDS_PER_STAGE * float(ItemDb.GROWTH_SCALE[plot.row]) * _rng.randf_range(0.8, 1.25)
	plot.timer = plot.stage_length


func _apply_visual(plot: CropPlot, pop: bool) -> void:
	var sprite := plot.sprite
	sprite.visible = not plot.empty
	sprite.region_rect = Rect2(plot.stage * 16, plot.row * 32, 16, 32)
	if pop and not plot.empty:
		sprite.scale = plot.base_scale * 1.18
		var tween := sprite.create_tween()
		tween.tween_property(sprite, "scale", plot.base_scale, 0.25)


func nearest_plot(pos: Vector2, max_distance: float, mature_only: bool) -> CropPlot:
	var closest: CropPlot = null
	var closest_distance := max_distance
	for plot in plots:
		if plot.empty or (mature_only and not plot.is_mature()):
			continue
		var distance := pos.distance_to(plot.sprite.position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = plot
	return closest


func harvest(plot: CropPlot) -> bool:
	if plot == null or not plot.is_mature():
		return false
	var nombre_cultivo := ItemDb.display_name(plot.item_id())
	plot.empty = true
	plot.timer = _rng.randf_range(REGROW_DELAY_MIN, REGROW_DELAY_MAX)
	_apply_visual(plot, false)
	var db := get_tree().root.get_node_or_null("DBManager")
	if db:
		db.registrar_accion("Cosecha", "Cosechó " + nombre_cultivo + " en el campo", 5)
	return true


## Identificador estable de un cultivo: su posición en el mundo (en décimas de píxel).
func _plot_key(plot: CropPlot) -> String:
	return "%d:%d" % [roundi(plot.sprite.position.x * 10.0), roundi(plot.sprite.position.y * 10.0)]


## Estado de todos los cultivos para guardar la partida.
func to_array() -> Array:
	var saved: Array = []
	for plot in plots:
		saved.append({
			"id": _plot_key(plot),
			"stage": plot.stage,
			"empty": plot.empty,
			"timer": plot.timer,
			"stage_length": plot.stage_length,
		})
	return saved


func load_array(saved: Array) -> void:
	var by_id := {}
	for entry in saved:
		if typeof(entry) == TYPE_DICTIONARY:
			var item: Dictionary = entry
			by_id[String(item.get("id", ""))] = item
	for plot in plots:
		var item: Dictionary = by_id.get(_plot_key(plot), {})
		if item.is_empty():
			continue
		plot.empty = bool(item.get("empty", false))
		plot.stage = clampi(int(item.get("stage", 0)), 0, plot.mature_stage())
		plot.stage_length = maxf(0.5, float(item.get("stage_length", plot.stage_length)))
		plot.timer = clampf(float(item.get("timer", plot.stage_length)), 0.0, 120.0)
		_apply_visual(plot, false)
