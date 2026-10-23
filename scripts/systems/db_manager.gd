extends Node
## Estadísticas del jugador y sincronización con el servidor SQLite local
## (tools/servidor_sqlite.py). Es un autoload: no dibuja nada.
## La interfaz vive en scripts/ui: el marcador es LeaderboardMenu y la tarjeta de
## puntos/tiempo es parte de GameHud. Aquí solo se avisa con señales.

signal stats_changed
## `rows` son las filas del servidor (jugador, score, monedas, coleccionables, misiones,
## tiempo_segundos); `ok` es false si no se pudo contactar con el servidor.
signal leaderboard_updated(rows: Array, ok: bool)

const SERVER_URL := "http://127.0.0.1:8080"

var jugador_nombre: String = "Benigno"
var monedas: int = 0
var coleccionables: int = 0
var misiones: int = 0
var tiempo_segundos: int = 0
## Main la activa al empezar a jugar. Mientras sea false (pantalla de título) el tiempo no corre.
var session_active := false

var _http_lb: HTTPRequest
var _timer_segundo: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_http_lb = HTTPRequest.new()
	_http_lb.timeout = 5.0
	_http_lb.request_completed.connect(_on_leaderboard_recibido)
	add_child(_http_lb)

	_timer_segundo = Timer.new()
	_timer_segundo.wait_time = 1.0
	_timer_segundo.autostart = true
	_timer_segundo.timeout.connect(_on_segundo_transcurrido)
	add_child(_timer_segundo)

	sincronizar_con_bd("Inicio de sesión", "Entró a Willowmere", 0)


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			registrar_coleccionable("Cosecha de Primavera", 1)


## El tiempo de juego solo corre mientras se juega de verdad: no en la pantalla de
## título ni con el juego en pausa (así el tiempo de cada partida guardada es real).
func _on_segundo_transcurrido() -> void:
	if get_tree().paused or not session_active:
		return
	tiempo_segundos += 1
	stats_changed.emit()
	if tiempo_segundos % 5 == 0:
		sincronizar_con_bd()


func registrar_coleccionable(nombre_item: String, cantidad: int = 1) -> void:
	coleccionables += cantidad
	monedas += cantidad * 15
	_telemetry("economia", "coleccionable", nombre_item, cantidad * 15)
	stats_changed.emit()
	sincronizar_con_bd("Coleccionable", "Obtuvo " + nombre_item, cantidad)


func agregar_monedas(cantidad: int, motivo: String = "Recompensa") -> void:
	monedas += cantidad
	_telemetry("economia", "recompensa", motivo, cantidad)
	stats_changed.emit()
	sincronizar_con_bd("Monedas", motivo, cantidad)


func registrar_mision(titulo_mision: String) -> void:
	misiones += 1
	monedas += 50
	_telemetry("economia", "encargo", titulo_mision, 50)
	stats_changed.emit()
	sincronizar_con_bd("Misión Completada", "Completó: " + titulo_mision, 50)


func registrar_accion(tipo: String, detalle: String, valor: int = 10) -> void:
	monedas += valor
	_telemetry("economia", tipo.to_lower().replace(" ", "_"), detalle, valor)
	stats_changed.emit()
	sincronizar_con_bd(tipo, detalle, valor)


## Avisa a la telemetría de uso (si está disponible) de dónde vienen los puntos.
func _telemetry(category: String, event: String, target: String, value: float) -> void:
	var tele := get_tree().root.get_node_or_null("Telemetry")
	if tele != null:
		tele.track(category, event, target, "", value)


## Misma fórmula que usa el servidor para el marcador.
func score() -> int:
	return (coleccionables * 50) + (monedas * 10) + (misiones * 150) + (tiempo_segundos * 2)


## Estadísticas para guardar la partida (ver SaveGame).
func export_state() -> Dictionary:
	return {
		"jugador": jugador_nombre,
		"monedas": monedas,
		"coleccionables": coleccionables,
		"misiones": misiones,
		"tiempo_segundos": tiempo_segundos,
	}


func import_state(data: Dictionary) -> void:
	var nombre := String(data.get("jugador", jugador_nombre)).strip_edges()
	if not nombre.is_empty():
		jugador_nombre = nombre
	monedas = maxi(0, int(data.get("monedas", 0)))
	coleccionables = maxi(0, int(data.get("coleccionables", 0)))
	misiones = maxi(0, int(data.get("misiones", 0)))
	tiempo_segundos = maxi(0, int(data.get("tiempo_segundos", 0)))
	stats_changed.emit()
	sincronizar_con_bd("Partida cargada", "Se cargó una partida guardada", 0)


## Cambia (o crea) el jugador activo: su marcador empieza de cero.
func cambiar_jugador(nuevo_nombre: String) -> void:
	var nombre := nuevo_nombre.strip_edges()
	if nombre.is_empty():
		return
	jugador_nombre = nombre
	tiempo_segundos = 0
	coleccionables = 0
	monedas = 0
	misiones = 0
	stats_changed.emit()
	sincronizar_con_bd("Nuevo Jugador", "Cambio de perfil", 0)
	await get_tree().create_timer(0.3).timeout
	consultar_leaderboard()


func sincronizar_con_bd(evento_tipo: String = "", evento_detalle: String = "", evento_valor: int = 0) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())

	var payload := {
		"jugador": jugador_nombre,
		"monedas": monedas,
		"coleccionables": coleccionables,
		"misiones": misiones,
		"tiempo_segundos": tiempo_segundos,
		"evento_tipo": evento_tipo,
		"evento_detalle": evento_detalle,
		"evento_valor": evento_valor
	}
	var headers := ["Content-Type: application/json"]
	req.request(SERVER_URL + "/api/sync", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))


## Pide el marcador al servidor; el resultado llega por la señal leaderboard_updated.
func consultar_leaderboard() -> void:
	if _http_lb.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http_lb.request(SERVER_URL + "/api/leaderboard")


func _on_leaderboard_recibido(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		leaderboard_updated.emit([], false)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("leaderboard"):
		leaderboard_updated.emit([], false)
		return
	var rows: Array = (data as Dictionary)["leaderboard"]
	leaderboard_updated.emit(rows, true)
