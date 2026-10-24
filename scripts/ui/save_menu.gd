class_name SaveMenu
extends Control
## Menú de partidas guardadas: tres ranuras con un resumen de cada una.
## Sirve para guardar (desde el menú de pausa) y para cargar (desde pausa y título).
## No toca el juego: avisa con señales y Main guarda o carga de verdad.

signal save_requested(slot: int)
signal load_requested(slot: int)
signal closed

enum Mode { SAVE, LOAD }

var _mode: Mode = Mode.SAVE
var _confirm_load := false

var _slots_box: VBoxContainer
var _status: Label
var _confirm: ConfirmDialog = null
var _focus_slot := 1


## Llamar antes de añadirlo al árbol. `confirm_load` pide confirmación antes de cargar
## (cuando ya hay una partida en marcha que se perdería).
func setup(mode: Mode, confirm_load: bool = false) -> void:
	_mode = mode
	_confirm_load = confirm_load


func _ready() -> void:
	var parts := UiKit.build_modal(self, 740, 55)
	var content: VBoxContainer = parts["content"]
	(parts["shade"] as ColorRect).gui_input.connect(_on_shade_input)

	var saving := _mode == Mode.SAVE
	content.add_child(UiKit.modal_header(
			"Guardar partida" if saving else "Cargar partida",
			"ELIGE UNA RANURA PARA GUARDAR" if saving else "ELIGE LA PARTIDA QUE QUIERES RETOMAR",
			closed.emit))
	content.add_child(UiKit.divider())

	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 10)
	content.add_child(_slots_box)

	content.add_child(UiKit.divider())
	_status = UiKit.wrapped_label("", 12, UiKit.INK_FAINT, 660)
	content.add_child(_status)
	_reset_status()

	refresh()
	UiKit.fade_in(self)


## Vuelve a leer las ranuras del disco y las redibuja.
func refresh() -> void:
	for child in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.queue_free()
	var focus_button: Button = null
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		var result := _build_slot(slot)
		_slots_box.add_child(result["row"])
		if slot == _focus_slot or focus_button == null:
			var main_button: Button = result["main_button"]
			if not main_button.disabled:
				focus_button = main_button
	if focus_button != null:
		focus_button.grab_focus.call_deferred()


func show_status(text: String, color: Color = UiKit.INK_GOOD) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## Esc: cierra primero el aviso de confirmación si lo hay; si no, el menú.
func cancel() -> void:
	if is_instance_valid(_confirm):
		_close_confirm()
	else:
		closed.emit()


func _reset_status() -> void:
	if _mode == Mode.SAVE:
		show_status("Se guarda tu posición, la mochila, los encargos, los cultivos y el marcador.", UiKit.INK_FAINT)
	else:
		show_status("Al cargar vuelves al punto exacto donde guardaste.", UiKit.INK_FAINT)


func _build_slot(slot: int) -> Dictionary:
	var info := SaveGame.peek(slot)
	var state := String(info["state"])

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 98)
	row.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#F5D9A8") if state != "empty" else Color("#EBCB97"), 3, UiKit.INK if state != "empty" else UiKit.INK_FAINT, 2))
	var padding := UiKit.margin(16, 16, 14, 14)
	row.add_child(padding)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	padding.add_child(line)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(54, 54)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", UiKit.panel_style(Color("#E9BE8A"), 3, UiKit.INK, 2))
	var number := UiKit.label(str(slot), 24, UiKit.INK_ACCENT if state == "ok" else UiKit.INK_FAINT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(number)
	line.add_child(badge)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 3)
	line.add_child(copy)
	match state:
		"ok":
			var summary: Dictionary = info["summary"]
			var place := String(summary["place"])
			copy.add_child(UiKit.label(place if not place.is_empty() else "Willowmere", 17, UiKit.INK))
			copy.add_child(UiKit.label("%s  ·  Jugado %s  ·  %d monedas  ·  %d/%d encargos" % [
					String(summary["player"]), UiKit.format_time(int(summary["play_seconds"])),
					int(summary["coins"]), int(summary["quests_done"]), int(summary["quests_total"])],
					13, UiKit.INK_SOFT))
			copy.add_child(UiKit.label(String(summary["saved_text"]), 12, UiKit.INK_FAINT))
		"corrupt":
			copy.add_child(UiKit.label("Archivo dañado", 17, UiKit.INK_BAD))
			copy.add_child(UiKit.label("No se pudo leer esta partida (dañada o de otra versión del juego).", 13, UiKit.INK_SOFT))
		_:
			copy.add_child(UiKit.label("Ranura vacía", 17, UiKit.INK_SOFT))
			copy.add_child(UiKit.label("Todavía no hay ninguna partida guardada aquí.", 13, UiKit.INK_FAINT))

	var actions := HBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 8)
	line.add_child(actions)

	var main_button: Button
	if _mode == Mode.SAVE:
		main_button = UiKit.primary_button("Guardar aquí" if state == "empty" else "Sobrescribir", 14)
	else:
		main_button = UiKit.primary_button("Cargar", 14)
		main_button.disabled = state != "ok"
	main_button.custom_minimum_size = Vector2(130, 44)
	main_button.pressed.connect(_on_main_pressed.bind(slot, state))
	actions.add_child(main_button)

	var delete_button := UiKit.ghost_button("Borrar", 13)
	delete_button.custom_minimum_size = Vector2(78, 44)
	delete_button.disabled = state == "empty"
	delete_button.pressed.connect(_on_delete_pressed.bind(slot))
	actions.add_child(delete_button)

	return {"row": row, "main_button": main_button}


func _on_main_pressed(slot: int, state: String) -> void:
	_focus_slot = slot
	if _mode == Mode.SAVE:
		if state == "empty":
			save_requested.emit(slot)
		else:
			_ask("¿Sobrescribir la ranura %d?" % slot,
					"La partida guardada ahí se reemplazará por tu progreso actual.",
					"Sobrescribir", "danger", save_requested.emit.bind(slot))
	else:
		if _confirm_load:
			_ask("¿Cargar la ranura %d?" % slot,
					"Se reemplazará tu partida actual. Lo que no hayas guardado se perderá.",
					"Cargar", "primary", load_requested.emit.bind(slot))
		else:
			load_requested.emit(slot)


func _on_delete_pressed(slot: int) -> void:
	_focus_slot = slot
	_ask("¿Borrar la ranura %d?" % slot, "Esta partida se eliminará para siempre.",
			"Borrar", "danger", _delete_slot.bind(slot))


func _delete_slot(slot: int) -> void:
	SaveGame.delete(slot)
	refresh()
	show_status("Ranura %d borrada." % slot, UiKit.INK_SOFT)


func _ask(title: String, message: String, confirm_text: String, confirm_style: String, on_confirm: Callable) -> void:
	if is_instance_valid(_confirm):
		return
	_confirm = ConfirmDialog.new()
	_confirm.setup(title, message, [
		{"id": "cancel", "text": "Cancelar", "style": "ghost"},
		{"id": "ok", "text": confirm_text, "style": confirm_style},
	])
	add_child(_confirm)
	_confirm.chosen.connect(func(id: String) -> void:
		_close_confirm()
		if id == "ok":
			on_confirm.call())
	_confirm.cancelled.connect(_close_confirm)


func _close_confirm() -> void:
	if is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null
	refresh()


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cancel()
