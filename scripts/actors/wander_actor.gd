class_name WanderActor
extends Node
## Hace que un personaje o animal pasee por su zona: elige un punto cercano a su
## "casa", camina hasta él, descansa un rato y repite.
##
## - Se añade como HIJO del nodo que se mueve (aldeano o Sprite2D de un animal),
##   así que no hay que cambiar nada en World.tscn.
## - Respeta la colisión del mundo (casas, árboles, vallas, agua, jugador) con una
##   consulta de física: si el siguiente paso choca, el actor se detiene.
## - Los actores no se montan unos sobre otros (ver `separation`).
## - Si el jugador se acerca, los aldeanos se detienen y lo miran; los animales
##   asustadizos (gallinas) se apartan.
## - Se detiene solo cuando el mundo está en pausa (hereda el modo de proceso de World).
##
## Cómo se ve el actor (animaciones, giro del sprite) lo decide un "visual":
## NpcVisual para AnimatedSprite2D de personajes, AnimalVisual para hojas de animales.

const STATE_IDLE := 0
const STATE_WALK := 1

## Los aldeanos se paran y miran al jugador cuando está más cerca que esto.
const PLAYER_STOP_DISTANCE := 80.0
const ARRIVE_DISTANCE := 1.5
const PATH_SAMPLE_STEP := 8.0
const PICK_ATTEMPTS := 8
const COLLISION_MASK := 1
## Aceleración y frenado, en "velocidades de paseo por segundo" (4 = tarda ~0,25 s en arrancar).
const ACCELERATION := 4.0
const DECELERATION := 6.0
## Al acercarse al destino frena durante este tiempo (en segundos de paseo) hasta un mínimo.
const SLOW_RADIUS_TIME := 0.5
const MIN_ARRIVE_SCALE := 0.3
## Por debajo de esta velocidad (px/s) se considera que está parado.
const MIN_VISIBLE_SPEED := 2.0

## Todos los actores vivos (para que no se pisen entre sí).
static var _actors: Array[WanderActor] = []

var body: Node2D
var player: Node2D = null
## Si no es null, el actor pasea alrededor de este nodo en vez de su punto inicial.
var anchor: Node2D = null
## Rectángulo (en coordenadas de World) dentro del que puede moverse.
var bounds := Rect2()
var home := Vector2.ZERO
var radius := 70.0
var speed := 30.0
var pause_min := 2.5
var pause_max := 7.0
## Posición del "pie" respecto al nodo, y tamaño de la caja con que choca.
var foot_offset := Vector2.ZERO
var body_size := Vector2(17, 13)
## Distancia mínima que guarda con otros actores.
var separation := 18.0
var yields_to_player := false
## Si es mayor que 0, el actor huye cuando el jugador se acerca a menos de esta distancia.
var flee_distance := 0.0
var flee_speed_scale := 2.2

var _visual: ActorVisual
var _state := STATE_IDLE
var _target := Vector2.ZERO
var _timer := 0.0
var _walk_speed := 30.0
## Velocidad actual (px/s): cambia poco a poco para que arranque y frene con suavidad.
var _velocity := Vector2.ZERO
var _frozen := false
var _fleeing := false
var _shape := RectangleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
var _rng := RandomNumberGenerator.new()


# -----------------------------------------------------------------------------
# Fábricas
# -----------------------------------------------------------------------------

## Aldeano: usa el AnimatedSprite2D con las animaciones de ActorFrames.
static func for_npc(npc: Node2D, sprite: AnimatedSprite2D, player_node: Node2D, area: Rect2,
		wander_radius: float, wander_speed: float, size: Vector2, foot: Vector2) -> WanderActor:
	var actor := WanderActor.new()
	actor.name = "WanderActor"
	actor.body = npc
	actor.player = player_node
	actor.bounds = area
	actor.radius = wander_radius
	actor.speed = wander_speed
	actor.body_size = size
	actor.foot_offset = foot
	actor.separation = maxf(size.x, 16.0)
	actor.yields_to_player = true
	actor._visual = NpcVisual.new(sprite)
	npc.add_child(actor)
	return actor


## Animal: `config` describe sus cuadros de animación y su ritmo (ver AnimalLife.SPECIES).
static func for_animal(sprite: Sprite2D, player_node: Node2D, area: Rect2, config: Dictionary,
		follow: Node2D) -> WanderActor:
	var actor := WanderActor.new()
	actor.name = "WanderActor"
	actor.body = sprite
	actor.player = player_node
	actor.bounds = area
	actor.radius = float(config.get("radius", 60.0))
	actor.speed = float(config.get("speed", 20.0))
	actor.pause_min = float(config.get("pause_min", 2.0))
	actor.pause_max = float(config.get("pause_max", 6.0))
	var size: Vector2 = config.get("size", Vector2(12, 8))
	actor.body_size = size * sprite.scale
	actor.foot_offset = Vector2(0.0, float(config.get("foot", 10.0)) * sprite.scale.y)
	actor.separation = size.x * sprite.scale.x
	actor.flee_distance = float(config.get("flee", 0.0))
	actor.anchor = follow
	actor._visual = AnimalVisual.new(sprite, config)
	sprite.add_child(actor)
	return actor


# -----------------------------------------------------------------------------
# Ciclo de vida
# -----------------------------------------------------------------------------

func _ready() -> void:
	if body == null:
		body = get_parent() as Node2D
	home = body.position
	_rng.randomize()
	_shape.size = body_size
	_query.shape = _shape
	_query.collision_mask = COLLISION_MASK
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	var collider := body as CollisionObject2D
	if collider != null:
		_query.exclude = [collider.get_rid()]
	_walk_speed = speed
	# Cada actor empieza en un momento distinto para que no se muevan todos a la vez.
	_timer = _rng.randf_range(0.3, maxf(pause_max, 0.5))
	_actors.append(self)


func _exit_tree() -> void:
	_actors.erase(self)


## Detiene al actor y lo gira hacia `look_at` (se usa durante un diálogo).
func freeze(look_at: Vector2) -> void:
	_frozen = true
	_state = STATE_IDLE
	_fleeing = false
	_visual.face(look_at - body.position)


## Reanuda el paseo tras un breve descanso.
func unfreeze() -> void:
	_frozen = false
	_enter_idle(_rng.randf_range(1.0, 2.5))


func _physics_process(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if _frozen:
		_apply_motion(Vector2.ZERO, delta)
		return

	var player_distance := INF
	if is_instance_valid(player):
		player_distance = player.position.distance_to(body.position)

	if flee_distance > 0.0 and not _fleeing and player_distance < flee_distance:
		_start_flee()
	if yields_to_player and player_distance < PLAYER_STOP_DISTANCE:
		_state = STATE_IDLE
		_timer = maxf(_timer, 1.0)
		_visual.face(player.position - body.position)

	var desired := Vector2.ZERO
	if _state == STATE_WALK:
		desired = _walk_velocity()
	else:
		_timer -= delta
		if _timer <= 0.0:
			_pick_target()
	_apply_motion(desired, delta)


## Velocidad que quiere llevar hacia el destino: constante y, al llegar, frena poco a poco.
func _walk_velocity() -> Vector2:
	var to_target := _target - body.position
	var distance := to_target.length()
	if distance <= ARRIVE_DISTANCE:
		_enter_idle()
		return Vector2.ZERO
	var slow_radius := maxf(_walk_speed * SLOW_RADIUS_TIME, 6.0)
	var desired_speed := _walk_speed * clampf(distance / slow_radius, MIN_ARRIVE_SCALE, 1.0)
	return to_target / distance * desired_speed


## Mueve al actor acelerando y frenando de forma gradual (nada de arrancar o parar en seco)
## y le dice al visual qué animación y a qué ritmo reproducir.
func _apply_motion(desired: Vector2, delta: float) -> void:
	var rate := maxf(_walk_speed, 10.0) * (ACCELERATION if desired != Vector2.ZERO else DECELERATION)
	_velocity = _velocity.move_toward(desired, rate * delta)
	var moving := _velocity.length() > MIN_VISIBLE_SPEED
	if moving:
		var next_position := body.position + _velocity * delta
		if _state == STATE_WALK:
			# No pasarse del destino en un solo paso.
			var remaining := _target - body.position
			if _velocity.length() * delta >= remaining.length():
				next_position = _target
		if _is_free(next_position):
			body.position = next_position
			body.z_index = int(next_position.y)
		else:
			# Algo bloquea el camino: se detiene, descansa un momento y elige otro destino.
			_velocity = Vector2.ZERO
			moving = false
			_enter_idle(_rng.randf_range(0.4, 1.2))
	if moving:
		_visual.animate(_velocity, delta, _velocity.length() / maxf(speed, 1.0))
	else:
		_visual.animate(Vector2.ZERO, delta, 0.0)


func _enter_idle(wait := -1.0) -> void:
	_state = STATE_IDLE
	_fleeing = false
	_timer = wait if wait >= 0.0 else _rng.randf_range(pause_min, pause_max)


# -----------------------------------------------------------------------------
# Elección de destino
# -----------------------------------------------------------------------------

func _center() -> Vector2:
	if anchor != null and is_instance_valid(anchor):
		return anchor.position
	return home


func _pick_target() -> void:
	var center := _center()
	for attempt in range(PICK_ATTEMPTS):
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(radius * 0.25, radius)
		# Un poco aplastado en vertical: la vista es de arriba y se ve más natural.
		var candidate := center + Vector2(cos(angle), sin(angle) * 0.75) * distance
		if _is_free(candidate) and _path_clear(body.position, candidate):
			_set_target(candidate, speed * _rng.randf_range(0.85, 1.15))
			return
	_enter_idle()


func _start_flee() -> void:
	var away := body.position - player.position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	away = away.normalized()
	var center := _center()
	var max_leash := radius * 1.3
	for angle in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var candidate: Vector2 = body.position + away.rotated(angle) * radius * 0.8
		if candidate.distance_to(center) > max_leash:
			candidate = center + (candidate - center).normalized() * max_leash
		if _is_free(candidate) and _path_clear(body.position, candidate):
			_set_target(candidate, speed * flee_speed_scale)
			_fleeing = true
			return


func _set_target(point: Vector2, walk_speed: float) -> void:
	_target = point
	_walk_speed = walk_speed
	_state = STATE_WALK


# -----------------------------------------------------------------------------
# Colisión
# -----------------------------------------------------------------------------

func _path_clear(from: Vector2, to: Vector2) -> bool:
	var length := from.distance_to(to)
	var steps := int(ceil(length / PATH_SAMPLE_STEP))
	for i in range(1, steps + 1):
		if not _is_free(from.lerp(to, float(i) / float(steps))):
			return false
	return true


## ¿Puede el actor estar en `pos`? (dentro de los límites, sin chocar con el mundo
## ni con otros actores).
func _is_free(pos: Vector2) -> bool:
	if not bounds.has_point(pos):
		return false
	if not _clear_of_actors(pos):
		return false
	var parent := body.get_parent() as Node2D
	if parent == null:
		return true
	_query.transform = Transform2D(0.0, parent.to_global(pos + foot_offset))
	var space := body.get_world_2d().direct_space_state
	return space.intersect_shape(_query, 1).is_empty()


## Permite acercarse a otro actor solo si ya estaba encima (para poder salir).
func _clear_of_actors(pos: Vector2) -> bool:
	for other in _actors:
		if other == self or not is_instance_valid(other.body):
			continue
		var other_position := other.body.position
		var gap := (separation + other.separation) * 0.5
		var new_distance := pos.distance_to(other_position)
		if new_distance < gap and new_distance < body.position.distance_to(other_position):
			return false
	return true


# -----------------------------------------------------------------------------
# Visuales
# -----------------------------------------------------------------------------

class ActorVisual:
	extends RefCounted

	## `direction` es cero cuando el actor está quieto. `speed_ratio` es su velocidad actual
	## respecto a la de paseo (1 = paseo normal): sirve para que los pies no resbalen.
	func animate(_direction: Vector2, _delta: float, _speed_ratio: float) -> void:
		pass

	## Gira al actor hacia `direction` sin moverlo.
	func face(_direction: Vector2) -> void:
		pass


## Personajes: usa idle_/walk_ + down/up/side de ActorFrames (el lado mira a la derecha).
class NpcVisual:
	extends ActorVisual

	## Velocidad de la animación de caminar con el paseo normal (1.0 = como el jugador).
	const WALK_ANIMATION_SCALE := 0.6

	var sprite: AnimatedSprite2D
	var facing := "down"

	func _init(target: AnimatedSprite2D) -> void:
		sprite = target

	func animate(direction: Vector2, _delta: float, speed_ratio: float) -> void:
		if sprite == null or sprite.sprite_frames == null:
			return
		var moving := direction.length_squared() > 0.01
		if moving:
			_set_facing(direction)
			# Los pasos van al ritmo de la velocidad real (el jugador va mucho más rápido).
			sprite.speed_scale = clampf(speed_ratio * WALK_ANIMATION_SCALE, 0.3, 1.4)
		else:
			sprite.speed_scale = 1.0
		_play(("walk_" if moving else "idle_") + facing)

	## Solo cambia hacia dónde mira; la animación la elige animate() en el mismo fotograma.
	func face(direction: Vector2) -> void:
		if sprite == null or sprite.sprite_frames == null:
			return
		if direction.length_squared() > 0.01:
			_set_facing(direction)

	func _set_facing(direction: Vector2) -> void:
		if absf(direction.x) > absf(direction.y):
			facing = "side"
			sprite.flip_h = direction.x < 0.0
		elif direction.y < 0.0:
			facing = "up"
			sprite.flip_h = false
		else:
			facing = "down"
			sprite.flip_h = false

	func _play(animation_name: String) -> void:
		if sprite.animation != animation_name:
			sprite.play(animation_name)


## Animales: recorren cuadros de una hoja (Sprite2D con hframes/vframes).
## Los dibujos miran a la IZQUIERDA, así que se voltean al ir a la derecha.
class AnimalVisual:
	extends ActorVisual

	var sprite: Sprite2D
	var walk_frames: Dictionary = {}
	var idle_frames: Dictionary = {}
	var walk_fps := 7.0
	var idle_fps := 2.0
	## Con "directional" hay cuadros distintos para ir de lado, hacia abajo y hacia arriba.
	var directional := false
	var facing := "side"
	var _clock := 0.0

	func _init(target: Sprite2D, config: Dictionary) -> void:
		sprite = target
		walk_frames = config.get("walk", {})
		idle_frames = config.get("idle", {})
		walk_fps = float(config.get("walk_fps", 7.0))
		idle_fps = float(config.get("idle_fps", 2.0))
		directional = bool(config.get("directional", false))
		_clock = randf() * 4.0
		if directional and sprite.hframes > 0:
			# Conserva hacia dónde miraba el animal en la escena (fila 0 lado, 1 frente, 2 espalda).
			var row := clampi(floori(float(sprite.frame) / float(sprite.hframes)), 0, 2)
			facing = ["side", "down", "up"][row]

	func animate(direction: Vector2, delta: float, speed_ratio: float) -> void:
		var moving := direction.length_squared() > 0.01
		if moving:
			_apply_direction(direction)
		var table := walk_frames if moving else idle_frames
		var frames: Array = table.get(facing, [])
		if frames.is_empty():
			return
		if moving:
			_clock += delta * walk_fps * clampf(speed_ratio, 0.3, 2.5)
		else:
			_clock += delta * idle_fps
		sprite.frame = int(frames[int(_clock) % frames.size()])

	func face(direction: Vector2) -> void:
		if direction.length_squared() > 0.01:
			_apply_direction(direction)

	func _apply_direction(direction: Vector2) -> void:
		if directional and absf(direction.y) > absf(direction.x):
			facing = "up" if direction.y < 0.0 else "down"
			sprite.flip_h = false
		else:
			facing = "side"
			if absf(direction.x) > 0.01:
				sprite.flip_h = direction.x > 0.0
