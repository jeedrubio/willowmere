class_name Inventory
extends RefCounted

signal changed

const SLOT_COUNT := 24
const MAX_STACK := 99

var slots: Array[Dictionary] = []
var coins := 0
var is_clone := false


func _init() -> void:
	for i in SLOT_COUNT:
		slots.append({})


func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("DBManager") if tree else null


func add(id: String, amount: int = 1) -> int:
	var left := amount
	for slot in slots:
		if left <= 0:
			break
		if not slot.is_empty() and slot["id"] == id and int(slot["count"]) < MAX_STACK:
			var moved := mini(MAX_STACK - int(slot["count"]), left)
			slot["count"] = int(slot["count"]) + moved
			left -= moved
	for i in slots.size():
		if left <= 0:
			break
		if slots[i].is_empty():
			var stack := mini(MAX_STACK, left)
			slots[i] = {"id": id, "count": stack}
			left -= stack
	var guardados := amount - left
	if guardados > 0:
		changed.emit()
		if not is_clone:
			var db := _db()
			if db:
				db.registrar_coleccionable(ItemDb.display_name(id), guardados)
	return left


func add_coins(amount: int) -> void:
	coins += amount
	changed.emit()
	if not is_clone and amount > 0:
		var db := _db()
		if db:
			db.agregar_monedas(amount, "Monedas obtenidas")


func count(id: String) -> int:
	return count_matching(id)


func count_matching(wanted: String) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and ItemDb.matches(String(slot["id"]), wanted):
			total += int(slot["count"])
	return total


func has_item(id: String, amount: int = 1) -> bool:
	return count_matching(id) >= amount


func remove_matching(wanted: String, amount: int) -> bool:
	if count_matching(wanted) < amount:
		return false
	var left := amount
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var slot := slots[i]
		if slot.is_empty() or not ItemDb.matches(String(slot["id"]), wanted):
			continue
		var taken := mini(int(slot["count"]), left)
		slot["count"] = int(slot["count"]) - taken
		left -= taken
		if int(slot["count"]) <= 0:
			slots[i] = {}
	changed.emit()
	return true


func clone() -> Inventory:
	var copy := Inventory.new()
	copy.is_clone = true
	copy.coins = coins
	for i in slots.size():
		copy.slots[i] = slots[i].duplicate()
	return copy
