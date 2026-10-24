class_name CoyoteTarget
extends RefCounted
## Coyote time para interacciones: el último objetivo válido (aldeano, cultivo, puerta) sigue
## disponible durante `grace` segundos después de que el jugador sale de su alcance.
##
## En un plataformas es "saltar justo después de dejar la plataforma". Aquí es el equivalente en
## vista cenital: pasarte un paso del cultivo o de la puerta y pulsar E/F un instante tarde.
## Llama a update() cada fotograma con el objetivo actual (o null si no hay ninguno).

var grace := GameFeel.INTERACT_COYOTE_TIME
var _last: Variant = null
var _last_seen_ms := -1


func update(current: Variant, now_ms: int = -1) -> void:
	if current != null:
		_last = current
		_last_seen_ms = _now(now_ms)


## El objetivo actual si lo hay; si no, el último si salió del alcance hace menos de `grace`.
## `used_coyote` (opcional, diccionario) recibe {"used": true} cuando se salvó gracias al coyote time.
func resolve(current: Variant, now_ms: int = -1, info: Dictionary = {}) -> Variant:
	if current != null:
		return current
	if _last != null and (_now(now_ms) - _last_seen_ms) <= int(grace * 1000.0):
		info["used"] = true
		return _last
	return null


func clear() -> void:
	_last = null
	_last_seen_ms = -1


func _now(now_ms: int) -> int:
	return now_ms if now_ms >= 0 else Time.get_ticks_msec()
