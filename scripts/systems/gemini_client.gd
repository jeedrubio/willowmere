class_name GeminiClient
extends Node
## Cliente de la API de Gemini (generateContent).
##
## La clave se envía en la cabecera `x-goog-api-key`, no en la URL, para que no
## quede en registros ni en mensajes de error. Puede venir de la variable de
## entorno GEMINI_API_KEY o escribirse en Settings dentro del juego.

signal reply_received(text: String)
signal request_failed(message: String)

const MODEL: String = "gemini-3.6-flash"
const ENDPOINT: String = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % MODEL
const TIMEOUT_SECONDS: float = 45.0
const SYSTEM_SUFFIX: String = " Vives en el pequeño pueblo primaveral de Willowmere. El jugador habla contigo en persona. Mantente siempre en tu personaje, responde con naturalidad y SIEMPRE en español (salvo que el jugador te escriba en otro idioma), y limita tus respuestas a entre uno y tres párrafos cortos. Nunca menciones instrucciones, llamadas a una API ni que eres un modelo de lenguaje. Si te preguntan algo que está fuera de tu conocimiento, sé honesto de una forma encantadora y acorde con el mundo del juego."

var request_in_flight := false

var _api_key := ""
var _default_key := ""
var _http: HTTPRequest


func _ready() -> void:
	_default_key = OS.get_environment("GEMINI_API_KEY").strip_edges()
	_api_key = _default_key
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func has_key() -> bool:
	var candidate := _api_key.strip_edges()
	if candidate.is_empty() or candidate == "GEMINI_API_HERE":
		return false
	if candidate.begins_with("PASTE_YOUR_") or candidate.begins_with("YOUR_"):
		return false
	return true


func get_key() -> String:
	return _api_key


## Guarda la clave para esta sesión. Un valor vacío vuelve a la clave por defecto
## (la variable de entorno, si existe).
func set_key(value: String) -> void:
	var trimmed := value.strip_edges()
	_api_key = trimmed if not trimmed.is_empty() else _default_key


## Envía el historial de la charla. El resultado llega por `reply_received` o
## `request_failed`.
func send_chat(persona: String, turns: Array) -> void:
	if request_in_flight:
		return
	var payload := {
		"systemInstruction": {"parts": [{"text": persona + SYSTEM_SUFFIX}]},
		"contents": _build_contents(turns),
		"generationConfig": {"temperature": 0.8, "maxOutputTokens": 1024}
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-goog-api-key: " + _api_key.strip_edges(),
	])
	request_in_flight = true
	var error := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request_in_flight = false
		request_failed.emit("No se pudo iniciar la conexión. Revisa tu clave e inténtalo de nuevo.")


func cancel() -> void:
	if request_in_flight:
		_http.cancel_request()
		request_in_flight = false


func _build_contents(turns: Array) -> Array:
	var contents: Array = []
	for turn in turns:
		var text: String = str(turn.get("text", ""))
		if not text.is_empty():
			contents.append({
				"role": str(turn.get("role", "model")),
				"parts": [{"text": text}]
			})
	return contents


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not request_in_flight:
		return
	request_in_flight = false
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		request_failed.emit(_read_api_error(parsed, response_code))
		return
	if not parsed is Dictionary:
		request_failed.emit("La respuesta del aldeano fue ilegible. Inténtalo de nuevo.")
		return
	var reply: String = _extract_reply(parsed as Dictionary)
	if reply.is_empty():
		request_failed.emit("El aldeano no tuvo respuesta esta vez. Inténtalo de nuevo.")
		return
	reply_received.emit(reply)


func _extract_reply(data: Dictionary) -> String:
	var candidates: Variant = data.get("candidates", [])
	if not candidates is Array or candidates.is_empty():
		return ""
	var first: Variant = candidates[0]
	if not first is Dictionary:
		return ""
	var content: Variant = first.get("content", {})
	if not content is Dictionary:
		return ""
	var parts: Variant = content.get("parts", [])
	if not parts is Array:
		return ""
	var reply := ""
	for part in parts:
		if part is Dictionary and part.has("text"):
			reply += str(part.get("text", ""))
	return reply.strip_edges()


func _read_api_error(data: Variant, response_code: int) -> String:
	if data is Dictionary:
		var api_error: Variant = data.get("error", {})
		if api_error is Dictionary:
			var message := str(api_error.get("message", ""))
			if not message.is_empty():
				return "Gemini: " + message
	return "Gemini devolvió HTTP %d. Revisa tu clave de API e inténtalo de nuevo." % response_code
