class_name GameFeel
extends RefCounted
## Parámetros de "game feel" del juego, todos en un solo sitio para ajustarlos fácil,
## y las preferencias del jugador (sacudida, efectos, volumen de efectos).
## Las preferencias se guardan en user://gamefeel.cfg.
##
## Qué hace cada cosa (ver docs/GAME_FEEL.md):
##   Input buffering  -> InputBuffer: una pulsación de E/F que llega "demasiado pronto" espera un instante.
##   Coyote time      -> CoyoteTarget: se puede interactuar un instante DESPUÉS de salir del alcance.
##   Screenshake      -> CameraShake: vibración de cámara en cosechas, encargos, puertas, errores...
##   Feedback         -> Juice (partículas, textos flotantes, rebotes) + Sfx (sonidos) + HUD.

## Cuánto tiempo (segundos) se recuerda una pulsación que no se pudo ejecutar todavía.
const INPUT_BUFFER_TIME := 0.20
## Cuánto tiempo (segundos) sigue valiendo un objetivo (aldeano, cultivo, puerta) tras salir de su alcance.
const INTERACT_COYOTE_TIME := 0.15
## Durante el coyote time el objetivo solo vale si no se ha alejado más de este múltiplo de su alcance.
const COYOTE_MAX_RANGE_FACTOR := 1.6

## La sacudida usa un modelo de "trauma" (0..1) que se amortigua solo.
const SHAKE_DECAY := 1.9
const SHAKE_MAX_OFFSET := Vector2(9.0, 6.0)
## Trauma que añade cada acción (antes de multiplicar por el ajuste del jugador).
const TRAUMA_HARVEST := 0.22
const TRAUMA_HARVEST_FAIL := 0.14
const TRAUMA_QUEST_START := 0.25
const TRAUMA_QUEST_DONE := 0.60
const TRAUMA_DOOR := 0.12
const TRAUMA_COINS := 0.10
const TRAUMA_TALK := 0.05

const SETTINGS_PATH := "user://gamefeel.cfg"
const SHAKE_LEVELS := {"off": 0.0, "low": 0.5, "normal": 1.0}

static var shake_level := "normal"
static var effects_enabled := true
static var mobile_controls_enabled := false
static var sfx_volume := 0.8
static var sfx_muted := false
static var _loaded := false


static func shake_scale() -> float:
	return float(SHAKE_LEVELS.get(shake_level, 1.0))


static func load_settings() -> void:
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var level := String(config.get_value("feel", "shake", "normal"))
	shake_level = level if SHAKE_LEVELS.has(level) else "normal"
	effects_enabled = bool(config.get_value("feel", "effects", true))
	mobile_controls_enabled = bool(config.get_value("controls", "mobile", false))
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
	sfx_muted = bool(config.get_value("audio", "sfx_muted", false))


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("feel", "shake", shake_level)
	config.set_value("feel", "effects", effects_enabled)
	config.set_value("controls", "mobile", mobile_controls_enabled)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.save(SETTINGS_PATH)
