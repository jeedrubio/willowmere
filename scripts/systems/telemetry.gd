extends Node
## Telemetría de uso (anónima) para analizar el juego desde el panel de desarrollo
## (tools/servidor_sqlite.py > pestaña Analítica). Es un autoload.
##
## Qué registra: la sesión (inicio, fin, versión, sistema operativo, tiempo activo),
## dónde está el jugador cada pocos segundos, los FPS, el tiempo por lugar, el uso de
## menús, cosechas, encargos y las charlas con la IA (latencias y errores).
## Qué NO registra: el texto de los mensajes, la clave de la API ni datos personales.
##
## Los eventos se acumulan y se envían por lotes cada pocos segundos. Si el servidor
## no está encendido no pasa nada: se reintenta más tarde. El jugador puede apagarla
## en Ajustes > Datos (se guarda en user://privacy.cfg).

signal flushed

const SERVER_URL := "http://127.0.0.1:8080"
const FLUSH_INTERVAL := 8.0
const RETRY_INTERVAL := 30.0
const POSITION_INTERVAL := 2.0
const FPS_INTERVAL := 5.0
const MAX_BUFFER := 3000
const PRIVACY_PATH := "user://privacy.cfg"

## Se puede apagar desde Ajustes. Con false no se registra ni se envía nada.
var enabled := true
var session_id := ""
## Segundos de juego "de verdad": sin contar el título ni la pausa.
var active_seconds := 0.0
var has_api_key := false
var place := "Plaza Central"

var _player: Node2D = null
var _playing := false
var _ended := false
var _sending := false
var _buffer: Array = []
var _session_started := 0.0
var _flush_in := FLUSH_INTERVAL
var _position_in := POSITION_INTERVAL
var _fps_in := FPS_INTERVAL
var _place_seconds := 0.0
var _place_open := false
var _http: HTTPRequest = null
var _last_batch: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_privacy()
	session_id = "%d-%06x" % [int(Time.get_unix_time_from_system()), randi() % 0xFFFFFF]
	_session_started = Time.get_unix_time_from_system()
	track("sesion", "inicio")


func _process(delta: float) -> void:
	if _ended:
		return
	_flush_in -= delta
	if _flush_in <= 0.0:
		_flush_in = FLUSH_INTERVAL
		flush()
	if not _playing or get_tree().paused:
		return
	active_seconds += delta
	_place_seconds += delta
	_position_in -= delta
	if _position_in <= 0.0:
		_position_in = POSITION_INTERVAL
		track("movimiento", "pos", "", "", POSITION_INTERVAL, true)
	_fps_in -= delta
	if _fps_in <= 0.0:
		_fps_in = FPS_INTERVAL
		track("rendimiento", "fps", "", "", Engine.get_frames_per_second())


## Main avisa de qué nodo es el jugador para poder leer su posición.
func set_player(player: Node2D) -> void:
	_player = player


## El jugador pulsó "Jugar" (nueva partida, continuar o cargar desde el título).
func begin_play(mode: String) -> void:
	if _playing:
		return
	track("menu", "jugar", mode, "", Time.get_unix_time_from_system() - _session_started)
	_playing = true
	_place_open = true
	_place_seconds = 0.0
	track("lugar", "entrada", place)


## Cambio de lugar (plaza exterior o el interior de una casa).
func set_place(new_place: String) -> void:
	if new_place == place and _place_open:
		return
	if _place_open:
		track("lugar", "salida", place, "", _place_seconds)
	place = new_place
	_place_seconds = 0.0
	if _playing:
		_place_open = true
		track("lugar", "entrada", place)


## Apunta un evento. `pos` (Vector2) fija unas coordenadas; con `with_pos` se usa la
## posición actual del jugador. `valor` es un número libre (segundos, latencia en ms...).
func track(category: String, event: String, target: String = "", detail: String = "", value: float = 0.0, with_pos: bool = false, pos: Variant = null) -> void:
	if not enabled or _ended:
		return
	var entry := {
		"t": snappedf(Time.get_unix_time_from_system(), 0.001),
		"c": category,
		"e": event,
		"o": target,
		"d": _scrub(detail).left(160),
		"v": snappedf(value, 0.01),
		"p": place,
	}
	if pos is Vector2:
		entry["x"] = snappedf((pos as Vector2).x, 0.1)
		entry["y"] = snappedf((pos as Vector2).y, 0.1)
	elif with_pos and is_instance_valid(_player):
		entry["x"] = snappedf(_player.position.x, 0.1)
		entry["y"] = snappedf(_player.position.y, 0.1)
	_buffer.append(entry)
	if _buffer.size() > MAX_BUFFER:
		_buffer = _buffer.slice(_buffer.size() - MAX_BUFFER)


## Quita de un texto cualquier cosa con forma de clave de API de Google antes de enviarlo.
func _scrub(text: String) -> String:
	var key_pattern := RegEx.new()
	key_pattern.compile("AIza[0-9A-Za-z_-]{10,}")
	return key_pattern.sub(text, "[clave]", true)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	if value:
		enabled = true
		track("sesion", "telemetria_activada")
	else:
		track("sesion", "telemetria_desactivada")
		flush()
		enabled = false
		_buffer.clear()
	var config := ConfigFile.new()
	config.set_value("privacy", "telemetry", value)
	config.save(PRIVACY_PATH)


func _load_privacy() -> void:
	var config := ConfigFile.new()
	if config.load(PRIVACY_PATH) == OK:
		enabled = bool(config.get_value("privacy", "telemetry", true))


## Cierra la sesión y envía lo que quede. Úsalo con await antes de salir del juego.
func shutdown() -> void:
	if _ended:
		return
	if _place_open:
		track("lugar", "salida", place, "", _place_seconds)
		_place_open = false
	track("sesion", "fin", "", "", Time.get_unix_time_from_system() - _session_started)
	# Si justo había un envío en curso, se espera a que termine para poder mandar el lote final.
	var waited := 0.0
	while _sending and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	flush(true)
	_ended = true
	waited = 0.0
	while _sending and waited < 1.5:
		await get_tree().process_frame
		waited += get_process_delta_time()


## Envía los eventos acumulados (y la información de la sesión) al servidor.
func flush(final: bool = false) -> void:
	if not enabled or _sending:
		return
	var batch := _buffer.duplicate()
	_buffer.clear()
	var db := get_tree().root.get_node_or_null("DBManager")
	var payload := {
		"session": {
			"id": session_id,
			"jugador": String(db.jugador_nombre) if db != null else "Anónimo",
			"inicio": _session_started,
			"version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")),
			"os": OS.get_name(),
			"api_key": has_api_key,
			"activo": snappedf(active_seconds, 0.1),
			"fin": final,
		},
		"events": batch,
	}
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 5.0
		add_child(_http)
		_http.request_completed.connect(_on_flush_done)
	_sending = true
	_last_batch = batch
	var error := _http.request(SERVER_URL + "/api/telemetry", ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_restore_batch()
		_sending = false
		_flush_in = RETRY_INTERVAL
		flushed.emit()



func _on_flush_done(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_sending = false
	if response_code != 200:
		_restore_batch()
		_flush_in = RETRY_INTERVAL
	_last_batch = []
	flushed.emit()


## Si el envío falló, los eventos vuelven al principio de la cola para el siguiente intento.
func _restore_batch() -> void:
	if _last_batch.is_empty() or _ended:
		return
	_buffer = _last_batch + _buffer
	if _buffer.size() > MAX_BUFFER:
		_buffer = _buffer.slice(_buffer.size() - MAX_BUFFER)
