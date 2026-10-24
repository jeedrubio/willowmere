class_name SaveGame
extends RefCounted
## Partidas guardadas: tres ranuras en user://saves/slot_N.json.
## Este módulo solo lee y escribe archivos y resume su contenido para los menús.
## Qué se guarda y cómo se restaura lo decide Main (_collect_save_data / _apply_save_data).
##
## En Windows la carpeta es %APPDATA%\Godot\app_userdata\<nombre del proyecto>\saves.
## La clave de Gemini NO se guarda nunca en las partidas.

const SLOT_COUNT := 3
const SAVE_DIR := "user://saves"
const VERSION := 1
const MONTHS := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Contenido de la ranura, o {} si está vacía, dañada o es de una versión más nueva del juego.
static func read(slot: int) -> Dictionary:
	return _read_file(slot_path(slot))


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	# JSON.new().parse() (a diferencia de parse_string) no escribe errores en la consola.
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = json.data
	if int(data.get("version", 0)) > VERSION:
		return {}
	return data


## Escribe primero a un archivo temporal y lo comprueba, para no dejar una partida
## a medias si el juego se cierra mientras guarda. Devuelve un Error de Godot (OK = bien).
static func write(slot: int, data: Dictionary) -> int:
	var make_dir_error := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if make_dir_error != OK:
		return make_dir_error
	data["version"] = VERSION
	var path := slot_path(slot)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if _read_file(temp_path).is_empty():
		DirAccess.remove_absolute(temp_path)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path)


static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(slot_path(slot))


## Estado de la ranura para los menús: {"state": "empty" | "corrupt" | "ok", "summary": {...}}.
static func peek(slot: int) -> Dictionary:
	if not exists(slot):
		return {"state": "empty"}
	var data := read(slot)
	if data.is_empty():
		return {"state": "corrupt"}
	return {"state": "ok", "summary": summarize(data)}


static func has_any() -> bool:
	return latest_slot() > 0


## Ranura con la partida más reciente, o 0 si no hay ninguna.
static func latest_slot() -> int:
	var best_slot := 0
	var best_time := -1
	for slot in range(1, SLOT_COUNT + 1):
		var data := read(slot)
		if data.is_empty():
			continue
		var saved_at := int(data.get("saved_at", 0))
		if saved_at > best_time:
			best_time = saved_at
			best_slot = slot
	return best_slot


static func summarize(data: Dictionary) -> Dictionary:
	var stats := _section(data, "stats")
	var inventory := _section(data, "inventory")
	var quests := _section(data, "quests")
	var done := 0
	for state in quests.values():
		if String(state) == "done":
			done += 1
	return {
		"place": String(data.get("place", "")),
		"player": String(stats.get("jugador", "")),
		"play_seconds": int(stats.get("tiempo_segundos", 0)),
		"coins": int(inventory.get("coins", 0)),
		"quests_done": done,
		"quests_total": QuestLog.QUESTS.size(),
		"saved_text": String(data.get("saved_text", "")),
		"saved_at": int(data.get("saved_at", 0)),
	}


static func _section(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


## Fecha y hora local para mostrar en la ranura, p. ej. "17 oct 2026  ·  04:32".
static func timestamp_text() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%d %s %d  ·  %02d:%02d" % [int(now["day"]), MONTHS[int(now["month"]) - 1], int(now["year"]), int(now["hour"]), int(now["minute"])]
