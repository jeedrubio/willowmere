class_name Energy
extends RefCounted
## Energía del jugador para usar herramientas.

signal changed(current: int, maximum: int)

const MAX_ENERGY := 100

var current := MAX_ENERGY


func spend(amount: int) -> bool:
	if amount < 0 or current < amount:
		return false
	current -= amount
	changed.emit(current, MAX_ENERGY)
	return true


func restore(amount: int) -> void:
	var previous := current
	current = mini(MAX_ENERGY, current + maxi(0, amount))
	if current != previous:
		changed.emit(current, MAX_ENERGY)


func restore_full() -> void:
	set_value(MAX_ENERGY)


func set_value(value: int) -> void:
	var next := clampi(value, 0, MAX_ENERGY)
	if next == current:
		return
	current = next
	changed.emit(current, MAX_ENERGY)
