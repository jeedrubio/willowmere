class_name Controls
extends RefCounted
## Nombres de las acciones del Input Map y utilidades para leerlas.
##
## Las acciones están definidas en project.godot, así que se pueden ver y
## remapear en Proyecto > Configuración del proyecto > Mapa de entrada.
## ensure_actions() solo añade las que falten (red de seguridad).

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const INTERACT := &"interact"
const INVENTORY := &"inventory"
const ENTER := &"enter"   # entrar / salir de una casa estando en la puerta
const HOTBAR_ACTIONS := [
	&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4",
	&"hotbar_5", &"hotbar_6", &"hotbar_7", &"hotbar_8",
]
# Acciones integradas de Godot (Enter / Espacio y Esc por defecto).
const CONFIRM := &"ui_accept"
const CANCEL := &"ui_cancel"

const _DEFAULT_KEYS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"interact": [KEY_E],
	&"inventory": [KEY_I],
	&"enter": [KEY_F],
	&"hotbar_1": [KEY_1],
	&"hotbar_2": [KEY_2],
	&"hotbar_3": [KEY_3],
	&"hotbar_4": [KEY_4],
	&"hotbar_5": [KEY_5],
	&"hotbar_6": [KEY_6],
	&"hotbar_7": [KEY_7],
	&"hotbar_8": [KEY_8],
}


static func ensure_actions() -> void:
	for action in _DEFAULT_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in _DEFAULT_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


static func movement_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)


## Texto de la primera tecla asignada a una acción (por ejemplo "E").
static func key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		var label: String = ""
		if key_event.physical_keycode != KEY_NONE:
			label = key_event.as_text_physical_keycode()
		else:
			label = key_event.as_text_keycode()
		if not label.is_empty():
			return label
	return "?"


static func hud_hint() -> String:
	return "WASD MOVER  ·  %s USAR  ·  1–8 ELEGIR  ·  %s PUERTAS  ·  %s MOCHILA  ·  ESC MENÚ" % [
		key_label(INTERACT).to_upper(),
		key_label(ENTER).to_upper(),
		key_label(INVENTORY).to_upper(),
	]


static func title_hint() -> String:
	return "%s  COMENZAR     ·     ESC  MENÚ DURANTE EL JUEGO" % key_label(CONFIRM).to_upper()


## Filas de la ventana de controles: {"action": texto, "keys": [teclas]}.
static func help_rows() -> Array:
	return [
		{"action": "Moverse", "keys": ["W", "A", "S", "D", "FLECHAS"]},
		{"action": "Hablar, usar una herramienta o trabajar la parcela", "keys": [key_label(INTERACT).to_upper()]},
		{"action": "Elegir una herramienta o semillas", "keys": ["1–8"]},
		{"action": "Entrar o salir de una casa (en la puerta)", "keys": [key_label(ENTER).to_upper()]},
		{"action": "Abrir la mochila", "keys": [key_label(INVENTORY).to_upper()]},
		{"action": "Menú de pausa / cerrar ventanas", "keys": ["ESC"]},
		{"action": "Comenzar desde la pantalla de título", "keys": ["ENTER", "ESPACIO"]},
	]
