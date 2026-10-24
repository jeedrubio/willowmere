extends Node
## Efectos de sonido (autoload "Sfx"). Los WAV están en res://audio/sfx y se generan con
## tools/audio/generar_sfx.py. Reproduce con un grupo de reproductores para que varios
## sonidos puedan sonar a la vez, con variación de tono para que no cansen.
## El volumen y el silencio se ajustan en Ajustes > Audio (GameFeel.sfx_volume / sfx_muted).

const SFX_DIR := "res://audio/sfx/"
const NAMES := [
	"ui_hover", "ui_click", "ui_back", "ui_confirm", "menu_open", "pickup", "coin", "harvest",
	"error", "bump", "quest_start", "quest_complete", "door", "save", "load", "talk",
]
const POOL_SIZE := 10
## Un mismo sonido no se repite antes de estos milisegundos (evita el "ametrallado" al pasar el ratón).
const MIN_GAP_MS := 40

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _last_played := {}
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFeel.load_settings()
	for sound_name in NAMES:
		var path: String = SFX_DIR + sound_name + ".wav"
		if ResourceLoader.exists(path):
			_streams[sound_name] = load(path)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)


## Reproduce un efecto. `pitch_jitter` (0..1) varía el tono al azar; `gain` multiplica el volumen.
func play(sound_name: String, pitch_jitter: float = 0.0, gain: float = 1.0) -> void:
	if GameFeel.sfx_muted or GameFeel.sfx_volume <= 0.0 or not _streams.has(sound_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound_name, -1000)) < MIN_GAP_MS:
		return
	_last_played[sound_name] = now
	var player := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _streams[sound_name]
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = linear_to_db(clampf(GameFeel.sfx_volume * gain, 0.0001, 1.0))
	player.play()


func set_volume(value: float) -> void:
	GameFeel.sfx_volume = clampf(value, 0.0, 1.0)
	GameFeel.save_settings()


func set_muted(value: bool) -> void:
	GameFeel.sfx_muted = value
	GameFeel.save_settings()
