class_name Conversation
extends RefCounted
## Historial de una charla con un NPC, en el formato que usa Gemini
## ("user" / "model").

var turns: Array[Dictionary] = []


func start(greeting: String) -> void:
	turns.clear()
	add_model(greeting)


func add_user(text: String) -> void:
	turns.append({"role": "user", "text": text})


func add_model(text: String) -> void:
	turns.append({"role": "model", "text": text})


## Si la petición falla, se descarta el mensaje del jugador que quedó sin respuesta.
func discard_pending_user_turn() -> void:
	if turns.is_empty():
		return
	var last: Dictionary = turns.back()
	if str(last.get("role", "")) == "user":
		turns.pop_back()
