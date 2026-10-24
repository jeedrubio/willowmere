extends Node2D
## Willowmere: escena principal (scenes/Main.tscn). Solo coordina; cada tarea vive en su módulo:
##   scripts/actors/   village_npc, npc_profile, actor_frames, wander_actor, animal_life
##                     (aldeanos, animaciones y paseo de aldeanos y animales)
##   scripts/systems/  controls, inventory, item_db, quest_log, conversation,
##                     gemini_client, music_player, save_game, db_manager (reglas y datos del juego)
##   scripts/world/    crop_manager, house_manager, interior_room, interior_db,
##                     terrain_builder (cultivos, casas, interiores, terreno)
##   scripts/ui/       game_hud, dialogue_panel, settings_dialog, title_screen,
##                     pause_menu, controls_dialog, inventory_panel, save_menu,
##                     leaderboard_menu, confirm_dialog, ui_kit (interfaz)

## Tamaño del mundo en píxeles (142 x 76 celdas de 16 px). Es el ÚNICO lugar donde hay
## que cambiarlo: de aquí salen el límite del jugador, las cuatro paredes y la cámara.
## Si lo cambias, pinta las capas de tiles hasta cubrir el nuevo tamaño
## (ver README, sección Terrain).
const WORLD_SIZE := Vector2(2272, 1216)
const WALL_THICKNESS := 20.0
const PLAYER_SPEED := 145.0
## Aceleración y frenado del jugador (px/s²): arranca y para con suavidad, sin saltos.
const PLAYER_ACCELERATION := 1300.0
const PLAYER_FRICTION := 1700.0
## Polvo de los pasos: posición respecto al jugador (a la altura de los pies) y velocidad mínima.
const DUST_OFFSET := Vector2(0, 0)
const DUST_MIN_SPEED := 12.0
const NPC_INTERACT_DISTANCE := 68.0
const CROP_INTERACT_DISTANCE := 52.0
const NPC_GROUP := &"village_npc"

## Los interiores viven dentro de World, muy a la derecha del mapa (fuera de WORLD_SIZE).
const INTERIOR_ORIGIN := Vector2(3200, 0)
const INDOOR_ZOOM := Vector2(1.6, 1.6)
const FADE_TIME := 0.25
const DEFAULT_PLACE := "Plaza Central"

var world: Node2D
var player: CharacterBody2D
var player_sprite: AnimatedSprite2D
var camera: Camera2D
var outdoor_zoom := Vector2.ONE
var actor_frames: SpriteFrames
var player_facing := "down"
## Rectángulo por el que se puede mover el centro del jugador (cambia dentro de las casas).
var player_bounds := Rect2()
## Dónde empieza el jugador al abrir el juego (por si una partida guardada no se puede restaurar).
var start_position := Vector2.ZERO

var npcs: Array[VillageNpc] = []
var crop_manager: CropManager
var active_npc: VillageNpc = null

var inventory := Inventory.new()
var quest_log := QuestLog.new()
var conversation := Conversation.new()

var houses := HouseManager.new()
var interior: InteriorRoom
var inside_house := false
var current_house: Dictionary = {}
var exit_position := Vector2.ZERO
var transitioning := false

var game_started := false
## Cómo se llegó a jugar desde el título: "nueva", "continuar" o "cargar" (para la telemetría).
var start_mode := "nueva"
var _dialogue_started_ms := 0
## Game feel (ver GameFeel y docs/GAME_FEEL.md)
var input_buffer := InputBuffer.new()
var coyote_interact := CoyoteTarget.new()
var coyote_door := CoyoteTarget.new()
var camera_shake: CameraShake = null
var _last_coins := 0
var _dust: CPUParticles2D = null

const CROP_COLORS := {
	"strawberry": Color("#E8445E"), "leek": Color("#8FDB6B"),
	"potato": Color("#D9B27A"), "onion": Color("#D9A3E3"),
}
var _ai_sent_ms := 0
var dialogue_open := false

var dialogue: DialoguePanel
var inventory_panel: InventoryPanel
var title_screen: TitleScreen = null
var settings_dialog: SettingsDialog = null
var pause_menu: PauseMenu = null
var controls_dialog: ControlsDialog = null
var save_menu: SaveMenu = null
var title_backdrop: TitleBackdrop = null
var leaderboard_menu: LeaderboardMenu = null
var confirm_dialog: ConfirmDialog = null

@onready var gemini: GeminiClient = $GeminiClient
@onready var music: MusicPlayer = $MusicPlayer
@onready var hud: GameHud = $HUDLayer/HUD


func _ready() -> void:
	Controls.ensure_actions()
	# Al cerrar la ventana se pasa por _quit_game() para poder enviar la telemetría pendiente.
	get_tree().auto_accept_quit = false
	if get_tree().root.get_node_or_null("DBManager") == null:
		var db_node: Node = load("res://scripts/systems/db_manager.gd").new()
		db_node.name = "DBManager"
		get_tree().root.add_child.call_deferred(db_node)
	
	
	# Main sigue activo con el juego en pausa (para el menú); el mundo y los
	# cultivos sí se detienen, y la música sigue sonando.
	process_mode = Node.PROCESS_MODE_ALWAYS

	world = get_node("World") as Node2D
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player = world.get_node("Player") as CharacterBody2D
	start_position = player.position
	var tele := _tele()
	if tele != null:
		tele.set_player(player)
	camera = player.get_node_or_null("TownCamera") as Camera2D
	GameFeel.load_settings()
	camera_shake = CameraShake.new()
	camera_shake.name = "CameraShake"
	camera_shake.camera = camera
	add_child(camera_shake)
	_build_dust()
	if camera != null:
		outdoor_zoom = camera.zoom
	_apply_world_bounds()
	actor_frames = ActorFrames.build()
	player_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	player_sprite.sprite_frames = actor_frames
	player_sprite.play("idle_down")
	player_sprite.visible = true
	var player_preview := player.get_node("EditorPreview") as Sprite2D
	player_preview.visible = false

	crop_manager = CropManager.new()
	crop_manager.name = "CropManager"
	add_child(crop_manager)
	crop_manager.process_mode = Node.PROCESS_MODE_PAUSABLE
	crop_manager.setup(world)
	quest_log.attach_inventory(inventory)
	_load_scene_npcs()
	AnimalLife.start(world, player, _outdoor_bounds())
	_build_houses()

	hud.setup(GeminiClient.MODEL)
	hud.settings_requested.connect(_show_settings)
	var db := _db()
	if db != null:
		db.stats_changed.connect(_update_stats)
	dialogue = DialoguePanel.new()
	hud.add_child(dialogue)
	dialogue.message_submitted.connect(_on_message_submitted)
	dialogue.close_requested.connect(_close_dialogue)
	inventory_panel = InventoryPanel.new()
	hud.add_child(inventory_panel)
	inventory_panel.setup(inventory)

	gemini.reply_received.connect(_on_reply_received)
	gemini.request_failed.connect(_on_request_failed)
	quest_log.changed.connect(_update_quest_tracker)
	quest_log.quest_started.connect(_on_quest_started)
	quest_log.quest_completed.connect(_on_quest_completed)
	inventory.changed.connect(_update_coins)
	music.track_started.connect(_on_track_started)

	_update_api_status()
	_update_coins()
	_update_stats()
	_update_quest_tracker()
	_build_title_screen()
	_update_interaction_prompt()


## Ajusta paredes invisibles y límites de cámara al tamaño de WORLD_SIZE.
func _apply_world_bounds() -> void:
	player_bounds = Rect2(Vector2(18, 18), WORLD_SIZE - Vector2(36, 36))
	_set_camera_outdoors()
	var half := WALL_THICKNESS / 2.0
	var walls := {
		"BoundaryLeft": Vector2(-half, WORLD_SIZE.y / 2.0),
		"BoundaryRight": Vector2(WORLD_SIZE.x + half, WORLD_SIZE.y / 2.0),
		"BoundaryTop": Vector2(WORLD_SIZE.x / 2.0, -half),
		"BoundaryBottom": Vector2(WORLD_SIZE.x / 2.0, WORLD_SIZE.y + half),
	}
	for wall_name in walls:
		var wall := world.find_child(wall_name, true, false) as Node2D
		if wall == null:
			continue
		wall.position = walls[wall_name]
		var shape_node := wall.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var rect: RectangleShape2D = null
		if shape_node != null:
			rect = shape_node.shape as RectangleShape2D
		if rect != null:
			if wall_name == "BoundaryLeft" or wall_name == "BoundaryRight":
				rect.size = Vector2(WALL_THICKNESS, WORLD_SIZE.y + WALL_THICKNESS * 2.0)
			else:
				rect.size = Vector2(WORLD_SIZE.x + WALL_THICKNESS * 2.0, WALL_THICKNESS)


## Zona exterior por la que pueden pasear aldeanos y animales (la misma del jugador).
func _outdoor_bounds() -> Rect2:
	return Rect2(Vector2(18, 18), WORLD_SIZE - Vector2(36, 36))


func _set_camera_outdoors() -> void:
	if camera == null:
		return
	camera.zoom = outdoor_zoom
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_bottom = int(WORLD_SIZE.y)


## Dentro de una casa la cámara se queda quieta, centrada en la habitación.
func _set_camera_indoors() -> void:
	if camera == null:
		return
	camera.zoom = INDOOR_ZOOM
	var view := get_viewport_rect().size / INDOOR_ZOOM
	var center := interior.camera_center()
	camera.limit_left = int(floor(center.x - view.x / 2.0))
	camera.limit_right = int(ceil(center.x + view.x / 2.0))
	camera.limit_top = int(floor(center.y - view.y / 2.0))
	camera.limit_bottom = int(ceil(center.y + view.y / 2.0))


func _load_scene_npcs() -> void:
	for npc_node in get_tree().get_nodes_in_group(NPC_GROUP):
		var npc := npc_node as VillageNpc
		if npc == null or npc.profile == null:
			push_warning("%s no tiene un NpcProfile asignado; se ignora." % npc_node.name)
			continue
		npc.setup_visuals(actor_frames)
		npc.start_wandering(player, _outdoor_bounds())
		npcs.append(npc)


func _build_houses() -> void:
	houses.setup(world)
	interior = InteriorRoom.new()
	interior.name = "Interior"
	interior.position = INTERIOR_ORIGIN
	world.add_child(interior)


# -----------------------------------------------------------------------------
# Movimiento e interacción
# -----------------------------------------------------------------------------

func _is_input_blocked() -> bool:
	return not game_started or dialogue_open or transitioning or _modal_open() \
			or _pause_open() or _inventory_open()


## ¿Hay alguna ventana encima (ajustes, controles, guardado, marcador o aviso)?
func _modal_open() -> bool:
	return _settings_open() or _controls_open() or _save_open() or _leaderboard_open() \
			or _confirm_open()


func _inventory_open() -> bool:
	return is_instance_valid(inventory_panel) and inventory_panel.visible


func _settings_open() -> bool:
	return is_instance_valid(settings_dialog)


func _controls_open() -> bool:
	return is_instance_valid(controls_dialog)


func _pause_open() -> bool:
	return is_instance_valid(pause_menu)


func _save_open() -> bool:
	return is_instance_valid(save_menu)


func _leaderboard_open() -> bool:
	return is_instance_valid(leaderboard_menu)


func _confirm_open() -> bool:
	return is_instance_valid(confirm_dialog)


func _db() -> Node:
	return get_tree().root.get_node_or_null("DBManager")


func _tele() -> Node:
	return get_tree().root.get_node_or_null("Telemetry")


## Apunta un evento de telemetría (si el autoload existe).
func _track(category: String, event: String, target: String = "", detail: String = "", value: float = 0.0, with_pos: bool = false, pos: Variant = null) -> void:
	var tele := _tele()
	if tele != null:
		tele.track(category, event, target, detail, value, with_pos, pos)


## Muestra el nombre del lugar en el HUD y lo anota para medir el tiempo por lugar.
func _set_place(place_name: String) -> void:
	hud.set_location(place_name)
	var tele := _tele()
	if tele != null:
		tele.set_place(place_name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if _is_input_blocked():
		player.velocity = Vector2.ZERO
		_update_player_animation(Vector2.ZERO)
		return

	var move_input := Controls.movement_vector()
	var rate := PLAYER_ACCELERATION if move_input != Vector2.ZERO else PLAYER_FRICTION
	player.velocity = player.velocity.move_toward(move_input * PLAYER_SPEED, rate * delta)
	player.move_and_slide()
	player.position = player.position.clamp(player_bounds.position, player_bounds.end)
	player.z_index = int(player.position.y)
	_update_player_animation(move_input)


func _update_player_animation(move_input: Vector2) -> void:
	if is_instance_valid(_dust):
		# Se emite según la velocidad real (no según la tecla): así no sale polvo al empujar
		# contra una pared y sigue un instante al frenar, en sintonía con la animación.
		var moving := player.velocity.length_squared() > DUST_MIN_SPEED * DUST_MIN_SPEED
		_dust.emitting = moving and GameFeel.effects_enabled and game_started
	if move_input.length_squared() > 0.01:
		if abs(move_input.x) > abs(move_input.y):
			player_facing = "side"
			player_sprite.flip_h = move_input.x < 0
		elif move_input.y < 0:
			player_facing = "up"
			player_sprite.flip_h = false
		else:
			player_facing = "down"
			player_sprite.flip_h = false
		var walking_animation := "walk_" + player_facing
		if player_sprite.animation != walking_animation:
			player_sprite.play(walking_animation)
	else:
		var idle_animation := "idle_" + player_facing
		if player_sprite.animation != idle_animation:
			player_sprite.play(idle_animation)


func _process(_delta: float) -> void:
	_sync_backdrop_menus()
	input_buffer.expire()
	if game_started and is_instance_valid(player) and not _modal_open() and not _pause_open():
		# El coyote time se "alimenta" cada fotograma con lo que hay al alcance (ver CoyoteTarget).
		coyote_interact.update(_find_interact_target())
		coyote_door.update(_find_door_target())
		_process_buffered_input()
	if not _is_input_blocked():
		_update_interaction_prompt()
	if is_instance_valid(player):
		player.z_index = int(player.position.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Controls.CANCEL):
		if _confirm_open():
			_close_confirm()
		elif _save_open():
			save_menu.cancel()
		elif _leaderboard_open():
			_close_leaderboard()
		elif _controls_open():
			_close_controls()
		elif _settings_open():
			_close_settings()
		elif dialogue_open:
			_close_dialogue()
		elif _inventory_open():
			inventory_panel.close()
		elif _pause_open():
			_close_pause()
		elif game_started and not transitioning:
			_open_pause()
		return
	if not game_started:
		if not _modal_open() and event.is_action_pressed(Controls.CONFIRM):
			_continue_game()
		return
	if _leaderboard_open() and event.is_action_pressed(Controls.LEADERBOARD):
		_close_leaderboard()
		return
	if _pause_open() or _modal_open():
		input_buffer.clear()
		return
	if event.is_action_pressed(Controls.INVENTORY) and not dialogue_open and not transitioning:
		_toggle_inventory()
		return
	# Input buffering: E y F se guardan un instante aunque aún no se puedan ejecutar
	# (durante un fundido, un paso antes de llegar, antes de que madure el cultivo...).
	if not dialogue_open and not _inventory_open():
		if event.is_action_pressed(Controls.ENTER):
			input_buffer.press(&"door")
			_process_buffered_input()
			return
		if event.is_action_pressed(Controls.INTERACT):
			input_buffer.press(&"interact")
			_process_buffered_input()
			if input_buffer.has(&"interact"):
				_feedback_not_ready()
			return
	if _is_input_blocked():
		return
	if event.is_action_pressed(Controls.LEADERBOARD):
		_open_leaderboard()


## Mientras un submenú (guardado, ajustes...) está abierto, el menú de pausa o el título
## de detrás se oculta para que sus bordes no se asomen; al cerrarlo vuelve con el foco.
func _sync_backdrop_menus() -> void:
	var show_backdrop := not _modal_open()
	if _pause_open() and pause_menu.visible != show_backdrop:
		pause_menu.visible = show_backdrop
		if show_backdrop:
			pause_menu.focus_first()
	if is_instance_valid(title_screen) and title_screen.is_menu_visible() != show_backdrop:
		title_screen.set_menu_visible(show_backdrop)
		if show_backdrop:
			title_screen.focus_first()


func _nearest_npc() -> VillageNpc:
	var closest: VillageNpc = null
	var closest_distance := NPC_INTERACT_DISTANCE
	if not is_instance_valid(player):
		return closest
	for npc in npcs:
		if not is_instance_valid(npc):
			continue
		var distance := player.position.distance_to(npc.position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = npc
	return closest


## Cultivo maduro más cercano (el único que se puede cosechar).
func _nearest_crop() -> CropManager.CropPlot:
	if not is_instance_valid(player):
		return null
	return crop_manager.nearest_plot(player.position, CROP_INTERACT_DISTANCE, true)


func _harvest_crop(plot: CropManager.CropPlot) -> void:
	var item_id := plot.item_id()
	var crop_position := plot.sprite.position
	if inventory.add(item_id, 1) > 0:
		hud.show_toast("Mochila llena", UiKit.COLOR_RED)
		_sfx("error")
		_shake(GameFeel.TRAUMA_HARVEST_FAIL)
		Juice.jiggle(plot.sprite)
		Juice.floating_text(world, crop_position + Vector2(0, -14), "Mochila llena", Color("#FF9A86"))
		return
	crop_manager.harvest(plot)
	_track("juego", "cosecha", item_id, "", 1.0, false, crop_position)
	hud.show_toast("+1 %s" % ItemDb.display_name(item_id))
	# Feedback de acierto: sonido, partículas, texto flotante, rebotes y un golpecito de cámara.
	_sfx("harvest", 0.06)
	get_tree().create_timer(0.07).timeout.connect(func() -> void: _sfx("pickup", 0.04))
	var crop_color: Color = CROP_COLORS.get(item_id, Color("#FFE27A"))
	Juice.burst(world, crop_position + Vector2(0, -4), crop_color, 12)
	Juice.floating_text(world, crop_position + Vector2(0, -16), "+1 %s" % ItemDb.display_name(item_id), crop_color.lightened(0.35))
	Juice.pop(plot.sprite, 0.22)
	Juice.pop(player_sprite, 0.1)
	_shake(GameFeel.TRAUMA_HARVEST)
	_update_interaction_prompt()


func _toggle_inventory() -> void:
	if _inventory_open():
		inventory_panel.close()
	else:
		hud.hide_prompt()
		_track("menu", "inventario")
		inventory_panel.open()


func _update_interaction_prompt() -> void:
	if not is_instance_valid(player):
		return
	var enter_key := Controls.key_label(Controls.ENTER).to_upper()
	if inside_house:
		if interior.near_exit(player.position):
			hud.show_prompt("%s   SALIR · %s" % [enter_key, String(current_house.get("name", "Casa")).to_upper()])
		else:
			hud.hide_prompt()
		return
	var nearby_npc := _nearest_npc()
	if nearby_npc != null:
		hud.show_prompt("%s   HABLAR CON %s" % [Controls.key_label(Controls.INTERACT).to_upper(), nearby_npc.profile.display_name.to_upper()])
		return
	var door := houses.nearest_door(player.position)
	if not door.is_empty():
		hud.show_prompt("%s   ENTRAR · %s" % [enter_key, String(door["name"]).to_upper()])
		return
	var ready_crop := _nearest_crop()
	if ready_crop != null:
		hud.show_prompt("%s   COSECHAR · %s" % [Controls.key_label(Controls.INTERACT).to_upper(), ItemDb.display_name(ready_crop.item_id()).to_upper()])
		return
	var growing_crop: CropManager.CropPlot = null
	growing_crop = crop_manager.nearest_plot(player.position, CROP_INTERACT_DISTANCE, false)
	if growing_crop != null:
		hud.show_prompt("%s   CRECIENDO  %d%%" % [ItemDb.display_name(growing_crop.item_id()).to_upper(), int(growing_crop.progress() * 100.0)])
	else:
		hud.hide_prompt()


# -----------------------------------------------------------------------------
# Casas: entrar y salir
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Interacción: objetivos, input buffering y coyote time
# -----------------------------------------------------------------------------

## Qué puede usar E ahora mismo: aldeano o, si no hay, cultivo maduro. null si nada.
func _find_interact_target() -> Variant:
	if inside_house or not is_instance_valid(player):
		return null
	var npc := _nearest_npc()
	if npc != null:
		return {"kind": "npc", "node": npc}
	var crop := _nearest_crop()
	if crop != null:
		return {"kind": "crop", "plot": crop}
	return null


## Qué puede usar F ahora mismo: la puerta de una casa o la salida del interior.
func _find_door_target() -> Variant:
	if not is_instance_valid(player):
		return null
	if inside_house:
		return {"kind": "exit"} if interior.near_exit(player.position) else null
	var door := houses.nearest_door(player.position)
	return {"kind": "door", "door": door} if not door.is_empty() else null


## ¿Sigue valiendo un objetivo recordado por el coyote time? (no se ha alejado demasiado ni ha cambiado)
func _target_still_valid(target: Dictionary) -> bool:
	var factor := GameFeel.COYOTE_MAX_RANGE_FACTOR
	match String(target["kind"]):
		"npc":
			var npc: VillageNpc = target["node"]
			return is_instance_valid(npc) and player.position.distance_to(npc.position) <= NPC_INTERACT_DISTANCE * factor
		"crop":
			var plot: CropManager.CropPlot = target["plot"]
			return plot.is_mature() and player.position.distance_to(plot.sprite.position) <= CROP_INTERACT_DISTANCE * factor
		"door":
			return not inside_house
		"exit":
			return inside_house
	return false


## E: habla con el aldeano o cosecha el cultivo. `info["used"]` = true si se salvó con coyote time.
func _try_interact(info: Dictionary) -> bool:
	var current: Variant = _find_interact_target()
	var target: Variant = coyote_interact.resolve(current, -1, info)
	if target == null:
		return false
	if current == null and not _target_still_valid(target):
		coyote_interact.clear()
		info.erase("used")
		return false
	coyote_interact.clear()
	match String(target["kind"]):
		"npc":
			_open_dialogue(target["node"])
		"crop":
			_harvest_crop(target["plot"])
	return true


## F: entra a la casa o sale de ella.
func _try_door(info: Dictionary) -> bool:
	var current: Variant = _find_door_target()
	var target: Variant = coyote_door.resolve(current, -1, info)
	if target == null:
		return false
	if current == null and not _target_still_valid(target):
		coyote_door.clear()
		info.erase("used")
		return false
	coyote_door.clear()
	match String(target["kind"]):
		"door":
			_enter_house(target["door"])
		"exit":
			_leave_house()
	return true


## Ejecuta las acciones guardadas en el buffer en cuanto es posible. Si no se puede todavía
## (fundido, diálogo...), se queda esperando hasta que caduque (GameFeel.INPUT_BUFFER_TIME).
func _process_buffered_input() -> void:
	if not game_started or transitioning or dialogue_open or _inventory_open():
		return
	for action in [&"door", &"interact"]:
		if not input_buffer.has(action):
			continue
		var age := input_buffer.age_ms(action)
		var info := {}
		var done := _try_door(info) if action == &"door" else _try_interact(info)
		if not done:
			continue
		input_buffer.clear(action)
		if age >= 45:
			_track("feel", "input_buffer", String(action), "", float(age))
		if info.get("used", false):
			_track("feel", "coyote", String(action))


## E pulsada sin nada que hacer, pero con un cultivo todavía creciendo al lado: "toc" y temblor.
func _feedback_not_ready() -> void:
	if inside_house or not is_instance_valid(player):
		return
	var growing := crop_manager.nearest_plot(player.position, CROP_INTERACT_DISTANCE, false)
	if growing == null or growing.is_mature():
		return
	_sfx("bump")
	_shake(GameFeel.TRAUMA_HARVEST_FAIL * 0.5)
	Juice.jiggle(growing.sprite)
	Juice.floating_text(world, growing.sprite.position + Vector2(0, -14), "Aún crece", Color("#E9D8A6"))


## Sacude la cámara (trauma 0..1, ver GameFeel.TRAUMA_*).
func _shake(amount: float) -> void:
	if is_instance_valid(camera_shake):
		camera_shake.add_trauma(amount)


func _sfx(sound_name: String, pitch_jitter: float = 0.0, gain: float = 1.0) -> void:
	UiKit.play_sfx(sound_name, pitch_jitter, gain)


## Polvo que levantan los pies al caminar.
func _build_dust() -> void:
	_dust = CPUParticles2D.new()
	# Los pies del sprite quedan en y ≈ -1 respecto al origen del jugador (sprite en y=-15,
	# escala 1.4, pies en el píxel 26 de 32). Antes estaba en 11, unos 12 px por debajo.
	_dust.position = DUST_OFFSET
	# Sigue la posición interpolada del jugador, igual que el sprite, para no ir a saltos.
	_dust.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_dust.z_index = -1
	_dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dust.amount = 8
	_dust.lifetime = 0.38
	_dust.local_coords = false
	_dust.emitting = false
	_dust.direction = Vector2(0, -1)
	_dust.spread = 55.0
	_dust.gravity = Vector2.ZERO
	_dust.initial_velocity_min = 6.0
	_dust.initial_velocity_max = 16.0
	_dust.scale_amount_min = 1.8
	_dust.scale_amount_max = 3.0
	_dust.color = Color(0.93, 0.86, 0.7, 0.55)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	_dust.color_ramp = fade
	player.add_child(_dust)


func _enter_house(door: Dictionary) -> void:
	if transitioning:
		return
	transitioning = true
	hud.hide_prompt()
	_sfx("door")
	_shake(GameFeel.TRAUMA_DOOR)
	await hud.fade_to(1.0, FADE_TIME)
	current_house = door
	exit_position = door["exit_position"]
	_track("juego", "entrar_casa", String(door["name"]))
	interior.build(String(door["interior"]))
	inside_house = true
	player.position = interior.spawn_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_bounds = interior.player_bounds()
	player_facing = "up"
	player_sprite.flip_h = false
	_set_camera_indoors()
	_set_place(String(door["name"]))
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_update_interaction_prompt()


func _leave_house() -> void:
	if transitioning:
		return
	transitioning = true
	hud.hide_prompt()
	_sfx("door")
	_shake(GameFeel.TRAUMA_DOOR)
	await hud.fade_to(1.0, FADE_TIME)
	interior.clear()
	inside_house = false
	player.position = exit_position
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_bounds = Rect2(Vector2(18, 18), WORLD_SIZE - Vector2(36, 36))
	player_facing = "down"
	player_sprite.flip_h = false
	_set_camera_outdoors()
	_set_place(DEFAULT_PLACE)
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_update_interaction_prompt()


# -----------------------------------------------------------------------------
# Título, pausa, menús y misión
# -----------------------------------------------------------------------------

func _build_title_screen() -> void:
	title_backdrop = TitleBackdrop.new()
	add_child(title_backdrop)
	title_backdrop.setup(world, player)
	hud.set_gameplay_visible(false)
	title_screen = TitleScreen.new()
	hud.add_child(title_screen)
	title_screen.start_requested.connect(_start_game)
	title_screen.continue_requested.connect(_continue_game)
	title_screen.load_requested.connect(_show_save_menu.bind(SaveMenu.Mode.LOAD))
	title_screen.controls_requested.connect(_show_controls)
	title_screen.settings_requested.connect(_show_settings)
	title_screen.quit_requested.connect(_quit_game)


func _start_game() -> void:
	game_started = true
	if is_instance_valid(title_backdrop):
		title_backdrop.finish(camera)
	title_backdrop = null
	hud.set_gameplay_visible(true)
	var tele := _tele()
	if tele != null:
		tele.begin_play(start_mode)
	var db := _db()
	if db != null:
		db.session_active = true
	if is_instance_valid(title_screen):
		title_screen.queue_free()
	title_screen = null
	_update_interaction_prompt()


## "Continuar" del título: retoma la partida guardada más reciente (o empieza una nueva si no hay).
func _continue_game() -> void:
	var slot := SaveGame.latest_slot()
	if slot > 0:
		start_mode = "continuar"
		_load_game(slot)
	else:
		_start_game()


func _quit_game() -> void:
	var tele := _tele()
	if tele != null:
		await tele.shutdown()
	get_tree().quit()


## Salir desde el menú de pausa: avisa antes, por si hay progreso sin guardar.
func _request_quit() -> void:
	if _modal_open() or transitioning:
		return
	confirm_dialog = ConfirmDialog.new()
	confirm_dialog.setup("¿Salir del juego?", "Lo que no hayas guardado se perderá.", [
		{"id": "cancel", "text": "Seguir jugando", "style": "ghost"},
		{"id": "save", "text": "Guardar partida", "style": "primary"},
		{"id": "quit", "text": "Salir sin guardar", "style": "danger"},
	])
	hud.add_child(confirm_dialog)
	confirm_dialog.chosen.connect(_on_quit_choice)
	confirm_dialog.cancelled.connect(_close_confirm)


func _on_quit_choice(id: String) -> void:
	_close_confirm()
	match id:
		"save":
			_show_save_menu(SaveMenu.Mode.SAVE)
		"quit":
			_quit_game()


func _close_confirm() -> void:
	if is_instance_valid(confirm_dialog):
		confirm_dialog.queue_free()
	confirm_dialog = null


func _open_pause() -> void:
	if _pause_open():
		return
	hud.hide_prompt()
	_sfx("menu_open")
	_track("menu", "pausa")
	pause_menu = PauseMenu.new()
	hud.add_child(pause_menu)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.save_requested.connect(_show_save_menu.bind(SaveMenu.Mode.SAVE))
	pause_menu.load_requested.connect(_show_save_menu.bind(SaveMenu.Mode.LOAD))
	pause_menu.leaderboard_requested.connect(_open_leaderboard)
	pause_menu.controls_requested.connect(_show_controls)
	pause_menu.settings_requested.connect(_show_settings)
	pause_menu.quit_requested.connect(_request_quit)
	get_tree().paused = true


func _close_pause() -> void:
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	pause_menu = null
	get_tree().paused = false
	_sfx("ui_back")
	_update_interaction_prompt()


func _show_controls() -> void:
	if _modal_open() or transitioning:
		return
	_track("menu", "controles")
	controls_dialog = ControlsDialog.new()
	hud.add_child(controls_dialog)
	controls_dialog.closed.connect(_close_controls)


func _close_controls() -> void:
	if is_instance_valid(controls_dialog):
		controls_dialog.queue_free()
	controls_dialog = null


func _open_leaderboard() -> void:
	if _modal_open() or transitioning:
		return
	hud.hide_prompt()
	_track("menu", "marcador")
	leaderboard_menu = LeaderboardMenu.new()
	hud.add_child(leaderboard_menu)
	leaderboard_menu.closed.connect(_close_leaderboard)


func _close_leaderboard() -> void:
	if is_instance_valid(leaderboard_menu):
		leaderboard_menu.queue_free()
	leaderboard_menu = null


func _on_track_started(track_name: String) -> void:
	hud.show_toast("♪  %s" % track_name, UiKit.COLOR_MUTED)


func _update_quest_tracker() -> void:
	hud.set_quests(quest_log.tracker_entries(), quest_log.idle_text())


func _update_coins() -> void:
	var coins := inventory.coins
	hud.set_coins(coins)
	if game_started and not transitioning and coins > _last_coins:
		_sfx("coin")
		hud.punch_coins()
		_shake(GameFeel.TRAUMA_COINS)
	_last_coins = coins


func _update_stats() -> void:
	var db := _db()
	if db != null and is_instance_valid(hud):
		hud.set_stats(db.score(), db.tiempo_segundos)


func _on_quest_started(title: String) -> void:
	hud.show_toast("Nuevo encargo: %s" % title, UiKit.COLOR_ACCENT)
	_sfx("quest_start")
	_shake(GameFeel.TRAUMA_QUEST_START)
	if is_instance_valid(player):
		Juice.floating_text(world, player.position + Vector2(0, -34), "¡Nuevo encargo!", Color("#FFD27A"))


func _on_quest_completed(title: String, coins: int, rewards: Array) -> void:
	hud.show_toast("Encargo completado: %s" % title, UiKit.COLOR_ACCENT)
	_sfx("quest_complete")
	_shake(GameFeel.TRAUMA_QUEST_DONE)
	hud.flash(Color("#FFE9A8"), 0.26)
	if is_instance_valid(player):
		Juice.sparkle(world, player.position + Vector2(0, -10))
		Juice.pop(player_sprite, 0.22)
		Juice.floating_text(world, player.position + Vector2(0, -36), "¡Encargo completado!", Color("#FFE27A"))
		if coins > 0:
			Juice.floating_text(world, player.position + Vector2(0, -18), "+%d monedas" % coins, Color("#FFD04D"))
	var parts: PackedStringArray = []
	if coins > 0:
		parts.append("+%d monedas" % coins)
	for reward in rewards:
		parts.append("+1 %s" % String(reward))
	if not parts.is_empty():
		hud.show_toast(", ".join(parts))


func _update_api_status() -> void:
	var tele := _tele()
	if tele != null:
		tele.has_api_key = gemini.has_key()
	hud.set_api_connected(gemini.has_key())
	if is_instance_valid(dialogue):
		dialogue.set_api_ready(gemini.has_key())


func _show_settings() -> void:
	if _modal_open() or transitioning:
		return
	_track("menu", "ajustes")
	settings_dialog = SettingsDialog.new()
	settings_dialog.setup(gemini.get_key() if gemini.has_key() else "", GeminiClient.MODEL, music)
	hud.add_child(settings_dialog)
	settings_dialog.saved.connect(_on_settings_saved)
	settings_dialog.closed.connect(_close_settings)


func _on_settings_saved(key: String) -> void:
	gemini.set_key(key)
	_update_api_status()


func _close_settings() -> void:
	if is_instance_valid(settings_dialog):
		settings_dialog.queue_free()
	settings_dialog = null


# -----------------------------------------------------------------------------
# Guardar y cargar partida
# -----------------------------------------------------------------------------

func _show_save_menu(mode: SaveMenu.Mode) -> void:
	if _modal_open() or transitioning:
		return
	_track("menu", "guardado" if mode == SaveMenu.Mode.SAVE else "carga")
	save_menu = SaveMenu.new()
	# Si ya hay una partida en marcha, cargar otra pide confirmación (se perdería lo no guardado).
	save_menu.setup(mode, game_started)
	hud.add_child(save_menu)
	save_menu.save_requested.connect(_save_game)
	save_menu.load_requested.connect(_load_game)
	save_menu.closed.connect(_close_save_menu)


func _close_save_menu() -> void:
	if is_instance_valid(save_menu):
		save_menu.queue_free()
	save_menu = null
	if is_instance_valid(title_screen):
		title_screen.refresh()


## Todo lo que se guarda de la partida. Los aldeanos y animales no se guardan: siguen paseando.
func _collect_save_data() -> Dictionary:
	var db := _db()
	return {
		"saved_at": int(Time.get_unix_time_from_system()),
		"saved_text": SaveGame.timestamp_text(),
		"place": String(current_house.get("name", DEFAULT_PLACE)) if inside_house else DEFAULT_PLACE,
		"player": {
			"position": [player.position.x, player.position.y],
			"facing": player_facing,
			"flip_h": player_sprite.flip_h,
		},
		"location": {
			"inside": inside_house,
			"house": String(current_house.get("name", "")) if inside_house else "",
		},
		"inventory": inventory.to_dict(),
		"quests": quest_log.to_dict(),
		"crops": crop_manager.to_array(),
		"stats": db.export_state() if db != null else {},
	}


func _save_game(slot: int) -> void:
	if transitioning or not _save_open():
		return
	var error := SaveGame.write(slot, _collect_save_data())
	if error != OK:
		save_menu.show_status("No se pudo guardar la partida (error %d)." % error, UiKit.INK_BAD)
		return
	_track("partida", "guardar", "ranura %d" % slot)
	var db := _db()
	if db != null:
		db.sincronizar_con_bd("Partida guardada", "Ranura %d" % slot, 0)
	_sfx("save")
	save_menu.refresh()
	save_menu.show_status("Partida guardada en la ranura %d." % slot, UiKit.INK_GOOD)


func _load_game(slot: int) -> void:
	if transitioning:
		return
	var data := SaveGame.read(slot)
	if data.is_empty():
		if _save_open():
			save_menu.show_status("No se pudo leer la ranura %d." % slot, UiKit.INK_BAD)
		return
	if not game_started and start_mode == "nueva":
		start_mode = "cargar"
	transitioning = true
	hud.hide_prompt()
	await hud.fade_to(1.0, FADE_TIME)
	_close_save_menu()
	if _pause_open():
		_close_pause()
	if not game_started:
		_start_game()
	_apply_save_data(data)
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_sfx("load")
	_track("partida", "cargar", "ranura %d" % slot)
	hud.show_toast("Partida cargada  ·  Ranura %d" % slot)
	_update_interaction_prompt()


func _apply_save_data(data: Dictionary) -> void:
	if inside_house:
		interior.clear()
		inside_house = false
	inventory.load_dict(_saved_section(data, "inventory"))
	quest_log.load_dict(_saved_section(data, "quests"))
	var saved_crops: Variant = data.get("crops", [])
	if typeof(saved_crops) == TYPE_ARRAY:
		crop_manager.load_array(saved_crops)
	var db := _db()
	if db != null:
		db.import_state(_saved_section(data, "stats"))

	var saved_player := _saved_section(data, "player")
	var saved_location := _saved_section(data, "location")
	var position := start_position
	var saved_position: Variant = saved_player.get("position", [])
	if typeof(saved_position) == TYPE_ARRAY and (saved_position as Array).size() == 2:
		position = Vector2(float(saved_position[0]), float(saved_position[1]))
	var facing := String(saved_player.get("facing", "down"))
	player_facing = facing if facing in ["up", "down", "side"] else "down"
	player_sprite.flip_h = bool(saved_player.get("flip_h", false))

	var door := {}
	var saved_inside := bool(saved_location.get("inside", false))
	if saved_inside:
		door = _door_named(String(saved_location.get("house", "")))
	if not door.is_empty():
		current_house = door
		exit_position = door["exit_position"]
		interior.build(String(door["interior"]))
		inside_house = true
		player_bounds = interior.player_bounds()
		_set_camera_indoors()
		_set_place(String(door["name"]))
	else:
		# Si la casa ya no existe, la posición guardada (de dentro) no sirve: volver al inicio.
		if saved_inside:
			position = start_position
			player_facing = "down"
			player_sprite.flip_h = false
		current_house = {}
		player_bounds = _outdoor_bounds()
		_set_camera_outdoors()
		_set_place(DEFAULT_PLACE)

	player.position = position.clamp(player_bounds.position, player_bounds.end)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_sprite.play("idle_" + player_facing)
	_update_stats()


func _saved_section(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _door_named(house_name: String) -> Dictionary:
	for door in houses.doors:
		if String(door["name"]) == house_name:
			return door
	return {}


# -----------------------------------------------------------------------------
# Diálogo con aldeanos
# -----------------------------------------------------------------------------

func _open_dialogue(npc: VillageNpc) -> void:
	if dialogue_open:
		return
	active_npc = npc
	npc.begin_conversation(player.position)
	dialogue_open = true
	hud.hide_prompt()
	_dialogue_started_ms = Time.get_ticks_msec()
	_sfx("talk", 0.05)
	Juice.pop(player_sprite, 0.1)
	_track("juego", "hablar", npc.profile.display_name, "", 0.0, true)
	_track("ia", "charla_inicio", npc.profile.display_name)
	var greeting := npc.profile.greeting
	var quest_text := quest_log.talk_to(npc.profile)
	if not quest_text.is_empty():
		greeting = quest_text
	conversation.start(greeting)
	dialogue.open_with(npc.profile.display_name, npc.profile.role, greeting, gemini.has_key())


func _close_dialogue() -> void:
	if not dialogue_open:
		return
	gemini.cancel()
	dialogue.close()
	dialogue_open = false
	if is_instance_valid(active_npc):
		_track("ia", "charla_fin", active_npc.profile.display_name, "", (Time.get_ticks_msec() - _dialogue_started_ms) / 1000.0)
	if is_instance_valid(active_npc):
		active_npc.end_conversation()
	active_npc = null
	_update_interaction_prompt()


func _on_message_submitted(text: String) -> void:
	if not dialogue_open or active_npc == null or gemini.request_in_flight:
		return
	if not gemini.has_key():
		_track("ia", "sin_clave", active_npc.profile.display_name)
		dialogue.add_line("Gemini", "Este aldeano espera una clave de API de Gemini. Abre Ajustes para conectar la conversación.", false, true)
		return
	conversation.add_user(text)
	_ai_sent_ms = Time.get_ticks_msec()
	_track("ia", "mensaje_enviado", active_npc.profile.display_name)
	dialogue.set_busy(true)
	dialogue.show_typing()
	gemini.send_chat(active_npc.profile.persona, conversation.turns)


func _on_reply_received(reply: String) -> void:
	dialogue.hide_typing()
	dialogue.set_busy(false)
	if not dialogue_open or active_npc == null:
		return
	conversation.add_model(reply)
	_track("ia", "respuesta", active_npc.profile.display_name, "", float(Time.get_ticks_msec() - _ai_sent_ms))
	dialogue.add_line(active_npc.profile.display_name, reply, false, false)


func _on_request_failed(message: String) -> void:
	dialogue.hide_typing()
	dialogue.set_busy(false)
	conversation.discard_pending_user_turn()
	_track("ia", "error", active_npc.profile.display_name if is_instance_valid(active_npc) else "", message, float(Time.get_ticks_msec() - _ai_sent_ms))
	if dialogue_open:
		dialogue.add_line("Gemini", message, false, true)
