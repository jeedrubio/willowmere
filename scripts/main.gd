extends Node2D
## Willowmere: escena principal (scenes/Main.tscn). Solo coordina; cada tarea vive en su módulo:
##   scripts/actors/   village_npc, npc_profile, actor_frames, wander_actor, animal_life
##                     (aldeanos, animaciones y paseo de aldeanos y animales)
##   scripts/systems/  controls, inventory, item_db, quest_log, conversation,
##                     gemini_client, music_player (reglas y datos del juego)
##   scripts/world/    crop_manager, house_manager, interior_room, interior_db,
##                     terrain_builder (cultivos, casas, interiores, terreno)
##   scripts/ui/       game_hud, dialogue_panel, settings_dialog, title_screen,
##                     pause_menu, controls_dialog, inventory_panel, ui_kit (interfaz)

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
var dialogue_open := false

var dialogue: DialoguePanel
var inventory_panel: InventoryPanel
var title_screen: TitleScreen = null
var settings_dialog: SettingsDialog = null
var pause_menu: PauseMenu = null
var controls_dialog: ControlsDialog = null

@onready var gemini: GeminiClient = $GeminiClient
@onready var music: MusicPlayer = $MusicPlayer
@onready var hud: GameHud = $HUDLayer/HUD


func _ready() -> void:
	Controls.ensure_actions()
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
	camera = player.get_node_or_null("TownCamera") as Camera2D
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
	return not game_started or dialogue_open or transitioning or _settings_open() \
			or _controls_open() or _pause_open() or _inventory_open()


func _inventory_open() -> bool:
	return is_instance_valid(inventory_panel) and inventory_panel.visible


func _settings_open() -> bool:
	return is_instance_valid(settings_dialog)


func _controls_open() -> bool:
	return is_instance_valid(controls_dialog)


func _pause_open() -> bool:
	return is_instance_valid(pause_menu)


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
	if not _is_input_blocked():
		_update_interaction_prompt()
	if is_instance_valid(player):
		player.z_index = int(player.position.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Controls.CANCEL):
		if _controls_open():
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
		if not _settings_open() and not _controls_open() and event.is_action_pressed(Controls.CONFIRM):
			_start_game()
		return
	if _pause_open() or _controls_open() or _settings_open() or transitioning:
		return
	if event.is_action_pressed(Controls.INVENTORY) and not dialogue_open:
		_toggle_inventory()
		return
	if _is_input_blocked():
		return
	if event.is_action_pressed(Controls.ENTER):
		_use_door()
		return
	if inside_house or not event.is_action_pressed(Controls.INTERACT):
		return
	var nearby_npc := _nearest_npc()
	if nearby_npc != null:
		_open_dialogue(nearby_npc)
		return
	var nearby_crop := _nearest_crop()
	if nearby_crop != null:
		_harvest_crop(nearby_crop)


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
	if inventory.add(item_id, 1) > 0:
		hud.show_toast("Mochila llena", UiKit.COLOR_RED)
		return
	crop_manager.harvest(plot)
	hud.show_toast("+1 %s" % ItemDb.display_name(item_id))
	_update_interaction_prompt()


func _toggle_inventory() -> void:
	if _inventory_open():
		inventory_panel.close()
	else:
		hud.hide_prompt()
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

## F en la puerta: entra a la casa; F junto a la puerta del interior: sale.
func _use_door() -> void:
	if inside_house:
		if interior.near_exit(player.position):
			_leave_house()
		return
	var door := houses.nearest_door(player.position)
	if not door.is_empty():
		_enter_house(door)


func _enter_house(door: Dictionary) -> void:
	if transitioning:
		return
	transitioning = true
	hud.hide_prompt()
	await hud.fade_to(1.0, FADE_TIME)
	current_house = door
	exit_position = door["exit_position"]
	interior.build(String(door["interior"]))
	inside_house = true
	player.position = interior.spawn_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_bounds = interior.player_bounds()
	player_facing = "up"
	player_sprite.flip_h = false
	_set_camera_indoors()
	hud.set_location(String(door["name"]))
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
	hud.set_location(DEFAULT_PLACE)
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_update_interaction_prompt()


# -----------------------------------------------------------------------------
# Título, pausa, ajustes y misión
# -----------------------------------------------------------------------------

func _build_title_screen() -> void:
	title_screen = TitleScreen.new()
	hud.add_child(title_screen)
	title_screen.start_requested.connect(_start_game)
	title_screen.controls_requested.connect(_show_controls)
	title_screen.settings_requested.connect(_show_settings)
	title_screen.quit_requested.connect(_quit_game)


func _start_game() -> void:
	game_started = true
	if is_instance_valid(title_screen):
		title_screen.queue_free()
	title_screen = null
	_update_interaction_prompt()


func _quit_game() -> void:
	get_tree().quit()


func _open_pause() -> void:
	if _pause_open():
		return
	hud.hide_prompt()
	pause_menu = PauseMenu.new()
	hud.add_child(pause_menu)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.controls_requested.connect(_show_controls)
	pause_menu.settings_requested.connect(_show_settings)
	pause_menu.quit_requested.connect(_quit_game)
	get_tree().paused = true


func _close_pause() -> void:
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	pause_menu = null
	get_tree().paused = false
	_update_interaction_prompt()


func _show_controls() -> void:
	if _controls_open():
		return
	controls_dialog = ControlsDialog.new()
	hud.add_child(controls_dialog)
	controls_dialog.closed.connect(_close_controls)


func _close_controls() -> void:
	if is_instance_valid(controls_dialog):
		controls_dialog.queue_free()
	controls_dialog = null


func _on_track_started(track_name: String) -> void:
	hud.show_toast("♪  %s" % track_name, UiKit.COLOR_MUTED)


func _update_quest_tracker() -> void:
	hud.set_quests(quest_log.tracker_entries(), quest_log.idle_text())


func _update_coins() -> void:
	hud.set_coins(inventory.coins)


func _on_quest_started(title: String) -> void:
	hud.show_toast("Nuevo encargo: %s" % title, UiKit.COLOR_ACCENT)


func _on_quest_completed(title: String, coins: int, rewards: Array) -> void:
	hud.show_toast("Encargo completado: %s" % title, UiKit.COLOR_ACCENT)
	var parts: PackedStringArray = []
	if coins > 0:
		parts.append("+%d monedas" % coins)
	for reward in rewards:
		parts.append("+1 %s" % String(reward))
	if not parts.is_empty():
		hud.show_toast(", ".join(parts))


func _update_api_status() -> void:
	hud.set_api_connected(gemini.has_key())
	if is_instance_valid(dialogue):
		dialogue.set_api_ready(gemini.has_key())


func _show_settings() -> void:
	if _settings_open():
		return
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
# Diálogo con aldeanos
# -----------------------------------------------------------------------------

func _open_dialogue(npc: VillageNpc) -> void:
	if dialogue_open:
		return
	active_npc = npc
	npc.begin_conversation(player.position)
	dialogue_open = true
	hud.hide_prompt()
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
		active_npc.end_conversation()
	active_npc = null
	_update_interaction_prompt()


func _on_message_submitted(text: String) -> void:
	if not dialogue_open or active_npc == null or gemini.request_in_flight:
		return
	if not gemini.has_key():
		dialogue.add_line("Gemini", "Este aldeano espera una clave de API de Gemini. Abre Ajustes para conectar la conversación.", false, true)
		return
	conversation.add_user(text)
	dialogue.set_busy(true)
	dialogue.show_typing()
	gemini.send_chat(active_npc.profile.persona, conversation.turns)


func _on_reply_received(reply: String) -> void:
	dialogue.hide_typing()
	dialogue.set_busy(false)
	if not dialogue_open or active_npc == null:
		return
	conversation.add_model(reply)
	dialogue.add_line(active_npc.profile.display_name, reply, false, false)


func _on_request_failed(message: String) -> void:
	dialogue.hide_typing()
	dialogue.set_busy(false)
	conversation.discard_pending_user_turn()
	if dialogue_open:
		dialogue.add_line("Gemini", message, false, true)
