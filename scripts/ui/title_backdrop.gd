class_name TitleBackdrop
extends Node
## Fondo vivo de la portada: una cámara recorre el propio pueblo (pastizal con vacas y gallinas,
## huertos y granja) mientras los animales pasean. No hay nada que dibujar aparte: es el mundo
## real con zoom, así que siempre combina con el juego. Main lo crea al abrir el juego y lo
## cierra con finish() al pulsar "Jugar".

const ZOOM := Vector2(3.0, 3.0)
## Puntos del mundo (px) por los que pasa la cámara, en orden y en bucle.
const SHOTS := [
	Vector2(830, 1040),   # pastizal: vacas y gallinas
	Vector2(300, 525),    # huerto de la izquierda, con vaca y gallina
	Vector2(940, 570),    # camino: gallinas, pollito y vaca
	Vector2(1282, 585),   # huerto central
	Vector2(1920, 560),   # granja del este
]
const PAN_SPEED := 90.0
const PAN_MIN_TIME := 4.5
const DRIFT_TIME := 7.0

var _camera: Camera2D = null
var _player: Node2D = null
var _tween: Tween = null
var _labels: Node2D = null


func setup(world: Node2D, player: Node2D) -> void:
	_player = player
	if is_instance_valid(player):
		player.visible = false
	# Los rótulos del mundo ("PASTIZAL"...) chocarían con el logo.
	_labels = world.get_node_or_null("Labels") as Node2D
	if _labels != null:
		_labels.visible = false
	_camera = Camera2D.new()
	_camera.zoom = ZOOM
	_camera.position = SHOTS[0]
	_camera.position_smoothing_enabled = false
	world.add_child(_camera)
	_camera.make_current()
	_run()


func _run() -> void:
	_tween = create_tween().set_loops()
	var index := 0
	for i in SHOTS.size():
		var from: Vector2 = SHOTS[i]
		var to: Vector2 = SHOTS[(i + 1) % SHOTS.size()]
		# Pequeña deriva mientras se "mira" cada lugar, y después viaje al siguiente.
		_tween.tween_property(_camera, "position", from + Vector2(34, -10), DRIFT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var travel := maxf(PAN_MIN_TIME, from.distance_to(to) / PAN_SPEED)
		_tween.tween_property(_camera, "position", to, travel).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		index += 1


## Quita la cámara de la portada y devuelve el control a la cámara del jugador.
func finish(player_camera: Camera2D) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_camera):
		_camera.queue_free()
	if is_instance_valid(_player):
		_player.visible = true
	if is_instance_valid(_labels):
		_labels.visible = true
	if is_instance_valid(player_camera):
		player_camera.make_current()
		player_camera.reset_smoothing()
	queue_free()
