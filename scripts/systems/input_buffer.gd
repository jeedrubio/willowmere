class_name InputBuffer
extends RefCounted
## Input buffering: recuerda una acción pulsada un instante antes de poder ejecutarla.
##
## Ejemplo: el jugador pulsa E mientras aún camina hacia un cultivo, o durante el fundido de una
## puerta. En vez de perder la pulsación, se guarda `window` segundos y se ejecuta en cuanto sea
## posible. Si caduca sin ejecutarse, se descarta (así no se dispara "tarde" una acción olvidada).

var window := GameFeel.INPUT_BUFFER_TIME
var _pressed := {}   # acción -> instante (ms) en que se pulsó


func press(action: StringName, now_ms: int = -1) -> void:
	_pressed[action] = _now(now_ms)


## ¿Hay una pulsación reciente de esta acción? (no la gasta)
func has(action: StringName, now_ms: int = -1) -> bool:
	return _pressed.has(action) and (_now(now_ms) - int(_pressed[action])) <= int(window * 1000.0)


## Devuelve true y gasta la pulsación si todavía es reciente. Si caducó, la borra y devuelve false.
func consume(action: StringName, now_ms: int = -1) -> bool:
	var fresh := has(action, now_ms)
	_pressed.erase(action)
	return fresh


## Milisegundos desde que se pulsó la acción (o -1 si no hay pulsación guardada).
func age_ms(action: StringName, now_ms: int = -1) -> int:
	if not _pressed.has(action):
		return -1
	return _now(now_ms) - int(_pressed[action])


func clear(action: StringName = &"") -> void:
	if action == &"":
		_pressed.clear()
	else:
		_pressed.erase(action)


## Quita las pulsaciones caducadas (llamar de vez en cuando para no acumular basura).
func expire(now_ms: int = -1) -> void:
	for action in _pressed.keys():
		if not has(action, now_ms):
			_pressed.erase(action)


func _now(now_ms: int) -> int:
	return now_ms if now_ms >= 0 else Time.get_ticks_msec()
