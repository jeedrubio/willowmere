extends Node

const SERVER_URL := "http://127.0.0.1:8080"

var jugador_nombre: String = "Benigno"
var monedas: int = 0
var coleccionables: int = 0
var misiones: int = 0
var tiempo_segundos: int = 0

var _http_lb: HTTPRequest
var _timer_segundo: Timer

var _canvas: CanvasLayer
var _panel_lb: PanelContainer
var _texto_lb: RichTextLabel
var _input_nombre: LineEdit
var _lbl_hud_mini: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_http_lb = HTTPRequest.new()
	_http_lb.request_completed.connect(_on_leaderboard_recibido)
	add_child(_http_lb)
	
	_timer_segundo = Timer.new()
	_timer_segundo.wait_time = 1.0
	_timer_segundo.autostart = true
	_timer_segundo.timeout.connect(_on_segundo_transcurrido)
	add_child(_timer_segundo)
	
	_construir_ui()
	sincronizar_con_bd("Inicio de sesión", "Entró a Willowmere", 0)


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			toggle_leaderboard()
		elif event.keycode == KEY_K:
			registrar_coleccionable("Cosecha de Primavera", 1)


func _on_segundo_transcurrido() -> void:
	tiempo_segundos += 1
	_actualizar_hud_mini()
	if tiempo_segundos % 5 == 0:
		sincronizar_con_bd()


func registrar_coleccionable(nombre_item: String, cantidad: int = 1) -> void:
	coleccionables += cantidad
	monedas += cantidad * 15
	_actualizar_hud_mini()
	sincronizar_con_bd("Coleccionable", "Obtuvo " + nombre_item, cantidad)


func agregar_monedas(cantidad: int, motivo: String = "Recompensa") -> void:
	monedas += cantidad
	_actualizar_hud_mini()
	sincronizar_con_bd("Monedas", motivo, cantidad)


func registrar_mision(titulo_mision: String) -> void:
	misiones += 1
	monedas += 50
	_actualizar_hud_mini()
	sincronizar_con_bd("Misión Completada", "Completó: " + titulo_mision, 50)


func registrar_accion(tipo: String, detalle: String, valor: int = 10) -> void:
	monedas += valor
	_actualizar_hud_mini()
	sincronizar_con_bd(tipo, detalle, valor)


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


func toggle_leaderboard() -> void:
	_panel_lb.visible = not _panel_lb.visible
	if _panel_lb.visible:
		consultar_leaderboard()


func consultar_leaderboard() -> void:
	_texto_lb.text = "Cargando Leaderboard desde SQLite..."
	if _http_lb.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http_lb.request(SERVER_URL + "/api/leaderboard")


func _on_leaderboard_recibido(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_texto_lb.text = "[color=salmon]No se pudo conectar con servidor_sqlite.py en el puerto 8080.[/color]"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data or not data.has("leaderboard"):
		return
	
	var texto := "[b][color=#8fd694]#   JUGADOR          SCORE    MONEDAS   ITEMS   TIEMPO[/color][/b]\n"
	texto += "------------------------------------------------------------\n"
	var pos := 1
	for row in data["leaderboard"]:
		var t_seg := int(row["tiempo_segundos"])
		var tiempo_fmt := "%dm %ds" % [t_seg / 60, t_seg % 60]
		texto += "%d.  %-15s  %-7d  🪙 %-6d 🎒 %-5d ⏱️ %s\n" % [
			pos, row["jugador"], int(row["score"]), int(row["monedas"]), int(row["coleccionables"]), tiempo_fmt
		]
		pos += 1
	_texto_lb.text = texto


func _actualizar_hud_mini() -> void:
	if _lbl_hud_mini:
		var score := (coleccionables * 50) + (monedas * 10) + (misiones * 150) + (tiempo_segundos * 2)
		_lbl_hud_mini.text = "👤 %s | ⭐ Score: %d | 🪙 %d | 🎒 Items: %d | ⏱️ %ds | [L] Leaderboard" % [
			jugador_nombre, score, monedas, coleccionables, tiempo_segundos
		]


func _construir_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 95
	add_child(_canvas)
	
	var barra := PanelContainer.new()
	barra.position = Vector2(12, 12)
	_canvas.add_child(barra)
	
	_lbl_hud_mini = Label.new()
	_lbl_hud_mini.add_theme_font_size_override("font_size", 14)
	barra.add_child(_lbl_hud_mini)
	_actualizar_hud_mini()
	
	_panel_lb = PanelContainer.new()
	_panel_lb.visible = false
	_panel_lb.custom_minimum_size = Vector2(580, 360)
	_panel_lb.set_anchors_preset(Control.PRESET_CENTER)
	_canvas.add_child(_panel_lb)
	
	var vbox := VBoxContainer.new()
	_panel_lb.add_child(vbox)
	
	var titulo := Label.new()
	titulo.text = "🏆 LEADERBOARD WILLOWMERE (SQLite)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 18)
	vbox.add_child(titulo)
	
	var hbox_user := HBoxContainer.new()
	vbox.add_child(hbox_user)
	
	var lbl_u := Label.new()
	lbl_u.text = "Jugador activo:"
	hbox_user.add_child(lbl_u)
	
	_input_nombre = LineEdit.new()
	_input_nombre.text = jugador_nombre
	_input_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_user.add_child(_input_nombre)
	
	var btn_cambiar := Button.new()
	btn_cambiar.text = "Cambiar / Crear Jugador"
	btn_cambiar.pressed.connect(func():
		if not _input_nombre.text.strip_edges().is_empty():
			jugador_nombre = _input_nombre.text.strip_edges()
			tiempo_segundos = 0
			coleccionables = 0
			monedas = 0
			misiones = 0
			_input_nombre.release_focus()
			sincronizar_con_bd("Nuevo Jugador", "Cambio de perfil", 0)
			await get_tree().create_timer(0.2).timeout
			consultar_leaderboard()
	)
	hbox_user.add_child(btn_cambiar)
	
	_texto_lb = RichTextLabel.new()
	_texto_lb.bbcode_enabled = true
	_texto_lb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_texto_lb)
	
	var btn_cerrar := Button.new()
	btn_cerrar.text = "Cerrar [L]"
	btn_cerrar.pressed.connect(toggle_leaderboard)
	vbox.add_child(btn_cerrar)
