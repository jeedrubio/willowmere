class_name CameraShake
extends Node
## Vibración de cámara con el modelo de "trauma": cada golpe suma trauma (0..1) y la
## sacudida es proporcional a trauma² (así los golpes pequeños casi no se notan y los
## grandes sí). El desplazamiento se redondea a píxeles enteros para no romper el pixel art.
## El jugador puede reducirla o apagarla en Ajustes > Juego (GameFeel.shake_level).

var camera: Camera2D = null
var trauma := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Suma trauma. `amount` es lo "fuerte" que es el golpe (0.1 suave, 0.6 fuerte).
func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount * GameFeel.shake_scale())


func current_offset() -> Vector2:
	return camera.offset if is_instance_valid(camera) else Vector2.ZERO


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return
	if trauma <= 0.0:
		if camera.offset != Vector2.ZERO:
			camera.offset = Vector2.ZERO
		return
	trauma = maxf(0.0, trauma - GameFeel.SHAKE_DECAY * delta)
	var power := trauma * trauma
	camera.offset = Vector2(
			randf_range(-1.0, 1.0) * GameFeel.SHAKE_MAX_OFFSET.x * power,
			randf_range(-1.0, 1.0) * GameFeel.SHAKE_MAX_OFFSET.y * power).round()
