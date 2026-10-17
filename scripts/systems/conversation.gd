class_name Conversation
extends RefCounted

var turns: Array[Dictionary] = []


func start(greeting: String) -> void:
	turns.clear()
	add_model(greeting)


func add_user(text: String) -> void:
	turns.append({"role": "user", "text": text})
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var db := tree.root.get_node_or_null("DBManager")
		if db:
			db.registrar_accion("Diálogo IA", "Jugador dijo: " + text.left(40), 5)


func add_model(text: String) -> void:
	turns.append({"role": "model", "text": text})


func discard_pending_user_turn() -> void:
	if turns.is_empty():
		return
	var last: Dictionary = turns.back()
	if str(last.get("role", "")) == "user":
		turns.pop_back()
