class_name MusicPlayer
extends Node
## Música de fondo. Es un nodo normal (Main.tscn > MusicPlayer): selecciónalo y
## configúralo en el Inspector, no hace falta tocar código.
##
## Modos (play_mode):
##   LOOP_TRACK              repite sin parar la pista `track`. Si `track` está vacío usa
##                           la primera canción de la carpeta.
##   RANDOM_FROM_FOLDER      al terminar cada canción elige otra al azar de `music_folder`
##                           (nunca repite la que acaba de sonar, salvo que haya una sola).
##   SEQUENTIAL_FROM_FOLDER  las toca en orden alfabético y vuelve a empezar.
##
## Formatos: .ogg, .mp3 y .wav. Basta con soltar los archivos en la carpeta
## (por defecto res://music) y dejar que Godot los importe.
## El volumen y el silencio se guardan en user://settings.cfg.

signal track_started(track_name: String)

enum PlayMode { LOOP_TRACK, RANDOM_FROM_FOLDER, SEQUENTIAL_FROM_FOLDER }

const AUDIO_EXTENSIONS := ["ogg", "mp3", "wav"]
const SETTINGS_PATH := "user://settings.cfg"
const SILENT_DB := -80.0

@export var autoplay := true
@export var play_mode: PlayMode = PlayMode.RANDOM_FROM_FOLDER
## Pista para el modo LOOP_TRACK (arrastra aquí un .ogg/.mp3/.wav).
@export var track: AudioStream
## Carpeta con las canciones para los modos RANDOM_FROM_FOLDER y SEQUENTIAL_FROM_FOLDER.
@export_dir var music_folder := "res://music"
@export_range(0.0, 1.0, 0.01) var volume := 0.6
@export var muted := false
## Segundos de fundido al iniciar la primera canción (0 = sin fundido).
@export var fade_in_seconds := 2.0
@export var audio_bus: StringName = &"Master"

var _player: AudioStreamPlayer
var _paths: Array[String] = []
var _last_path := ""
var _playlist_index := -1
var _current_name := ""
var _fade_tween: Tween = null
var _first_start := true
var _warned_empty := false


func _ready() -> void:
	_load_settings()
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = audio_bus
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	_apply_volume()
	if autoplay:
		play()


## Empieza (o reinicia) la reproducción según play_mode.
func play() -> void:
	if play_mode == PlayMode.LOOP_TRACK and track != null:
		_start_stream(track, track.resource_path.get_file().get_basename())
		return
	_paths = _scan_folder()
	_playlist_index = -1
	next_track()


func stop() -> void:
	if _player != null:
		_player.stop()
	_current_name = ""


## Salta a la siguiente canción (al azar o en orden, según el modo).
func next_track() -> void:
	if play_mode == PlayMode.LOOP_TRACK and track != null:
		_start_stream(track, track.resource_path.get_file().get_basename())
		return
	if _paths.is_empty():
		_paths = _scan_folder()
	if _paths.is_empty():
		if not _warned_empty:
			push_warning("MusicPlayer: no hay música en '%s'. Añade archivos .ogg, .mp3 o .wav." % music_folder)
			_warned_empty = true
		return
	var path := ""
	if play_mode == PlayMode.RANDOM_FROM_FOLDER:
		path = _pick_random()
	elif play_mode == PlayMode.SEQUENTIAL_FROM_FOLDER:
		_playlist_index = (_playlist_index + 1) % _paths.size()
		path = _paths[_playlist_index]
	else:
		path = _paths[0]
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		push_warning("MusicPlayer: no se pudo cargar '%s'." % path)
		_paths.erase(path)
		if not _paths.is_empty():
			next_track()
		return
	_last_path = path
	_start_stream(stream, path.get_file().get_basename())


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_muted(value: bool) -> void:
	muted = value
	_apply_volume()


func is_playing() -> bool:
	return _player != null and _player.playing


func current_track_name() -> String:
	return _current_name


## Cuántas pistas hay disponibles (para mostrar u ocultar el botón "Next track").
func track_count() -> int:
	if play_mode == PlayMode.LOOP_TRACK and track != null:
		return 1
	return _scan_folder().size()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)   # conserva otras secciones si ya existía
	config.set_value("audio", "music_volume", volume)
	config.set_value("audio", "music_muted", muted)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	volume = clampf(float(config.get_value("audio", "music_volume", volume)), 0.0, 1.0)
	muted = bool(config.get_value("audio", "music_muted", muted))


func _start_stream(stream: AudioStream, track_name: String) -> void:
	var source := stream
	# Ogg y MP3 traen una propiedad `loop`: se ajusta en una copia para que repetir
	# (o no) dependa solo de play_mode y no de cómo se importó el archivo.
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		source = stream.duplicate() as AudioStream
		source.set("loop", play_mode == PlayMode.LOOP_TRACK)
	_player.stream = source
	_player.play()
	_current_name = track_name
	_apply_volume()
	if _first_start and fade_in_seconds > 0.0 and not muted:
		_player.volume_db = SILENT_DB
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", _target_db(), fade_in_seconds)
	_first_start = false
	track_started.emit(track_name)


func _on_track_finished() -> void:
	if play_mode == PlayMode.LOOP_TRACK:
		_player.play()   # .wav no trae loop: se reinicia la misma pista
	else:
		next_track()


func _pick_random() -> String:
	var path := _paths[randi() % _paths.size()]
	while _paths.size() > 1 and path == _last_path:
		path = _paths[randi() % _paths.size()]
	return path


func _target_db() -> float:
	if muted or volume <= 0.001:
		return SILENT_DB
	return linear_to_db(volume)


func _apply_volume() -> void:
	if _player == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_player.volume_db = _target_db()


func _scan_folder() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(music_folder)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# En un juego exportado los archivos aparecen como "nombre.ogg.import" o ".remap".
			var clean := file_name.trim_suffix(".import").trim_suffix(".remap")
			var path := music_folder.path_join(clean)
			if clean.get_extension().to_lower() in AUDIO_EXTENSIONS and not found.has(path):
				found.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
