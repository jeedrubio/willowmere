class_name CropManager
extends Node
## Cultivos vivos. Cada Sprite2D de World.tscn que use "Spring Crops.png" se
## convierte en una parcela: crece por etapas con el tiempo, se puede cosechar
## cuando madura, queda vacía un rato y vuelve a brotar desde semilla.
##
## El tipo de cultivo sale de la fila del recorte (region_rect) del sprite:
## 0 fresa, 1 puerro, 2 papa, 3 cebolla (ver ItemDb.CROP_ROWS). Para añadir
## parcelas basta con colocar otro sprite de cultivo en el campo.

## Segundos que tarda cada etapa de crecimiento (se multiplica por ItemDb.GROWTH_SCALE).
const SECONDS_PER_STAGE := 9.0
## Espera con la parcela vacía antes de que brote una semilla nueva.
const REGROW_DELAY_MIN := 6.0
const REGROW_DELAY_MAX := 14.0
## Probabilidad de que una parcela empiece ya madura al iniciar el juego.
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

	## Avance total de 0.0 a 1.0.
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
	# Los cultivos están en subcarpetas de World (Crops/...), así que se busca en todo el árbol.
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


## Parcela más cercana a `pos` dentro de `max_distance` (en coordenadas de World).
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


## Cosecha una parcela madura: queda vacía y rebrotará sola.
func harvest(plot: CropPlot) -> bool:
	if plot == null or not plot.is_mature():
		return false
	plot.empty = true
	plot.timer = _rng.randf_range(REGROW_DELAY_MIN, REGROW_DELAY_MAX)
	_apply_visual(plot, false)
	return true
