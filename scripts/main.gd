extends Node2D
## Willowmere: escena principal (scenes/Main.tscn). Solo coordina; cada tarea vive en su módulo:
##   scripts/actors/   village_npc, npc_profile, actor_frames, wander_actor, animal_life
##                     (aldeanos, animaciones y paseo de aldeanos y animales)
##   scripts/systems/  controls, energy, inventory, item_db, quest_log, conversation,
##                     gemini_client, music_player (reglas y datos del juego)
##   scripts/world/    crop_manager, house_manager, interior_room, interior_db,
##                     terrain_builder (cultivos, casas, interiores, terreno)
##   scripts/ui/       game_hud, hotbar, dialogue_panel, trade_panel, settings_dialog,
##                     title_screen, pause_menu, controls_dialog, inventory_panel, ui_kit

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
const TOOL_ENERGY_COST := 5
const NPC_GROUP := &"village_npc"
const FARM_WORLD_SIZE := Vector2(2272, 1216)
const FARM_SCENE := preload("res://scenes/Farm.tscn")
const INACTIVE_WORLD_OFFSET := Vector2(5000, 0)
const TOWN_RETURN_X := 62.0

## Los interiores viven dentro de World, muy a la derecha del mapa (fuera de WORLD_SIZE).
const INTERIOR_ORIGIN := Vector2(3200, 0)
const INDOOR_ZOOM := Vector2(1.6, 1.6)
const FADE_TIME := 0.25
const DEFAULT_PLACE := "Plaza Central"

var world: Node2D
var town_world: Node2D
var farm_world: Node2D = null
var town_world_position := Vector2.ZERO
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
var energy := Energy.new()
var quest_log := QuestLog.new()
var conversation := Conversation.new()

var houses := HouseManager.new()
var farm_houses := HouseManager.new()
var interior: InteriorRoom
var town_interior: InteriorRoom
var farm_interior: InteriorRoom
var inside_house := false
var current_house: Dictionary = {}
var exit_position := Vector2.ZERO
var transitioning := false
var town_return_position := Vector2(TOWN_RETURN_X, 398.0)

var game_started := false
var dialogue_open := false
var day_cycle: DayCycle
var daylight: CanvasModulate

var dialogue: DialoguePanel
var inventory_panel: InventoryPanel
var hotbar: Hotbar
var trade_panel: TradePanel
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
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	day_cycle.process_mode = Node.PROCESS_MODE_PAUSABLE
	day_cycle.time_changed.connect(_on_clock_changed)
	day_cycle.day_changed.connect(_on_day_changed)
	day_cycle.day_ended.connect(_on_day_ended)
	add_child(day_cycle)
	daylight = CanvasModulate.new()
	daylight.name = "Daylight"
	add_child(daylight)

	world = get_node("World") as Node2D
	town_world = world
	town_world_position = town_world.position
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player = world.get_node("Player") as CharacterBody2D
	_connect_world_exit(town_world, "TownFarmExit", true)
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
	inventory.coins = Inventory.STARTING_COINS

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
	_on_clock_changed(day_cycle.day, day_cycle.minutes)
	hud.settings_requested.connect(_show_settings)
	dialogue = DialoguePanel.new()
	dialogue.z_index = 20
	hud.add_child(dialogue)
	dialogue.message_submitted.connect(_on_message_submitted)
	dialogue.close_requested.connect(_close_dialogue)
	dialogue.shop_requested.connect(_open_market)
	hotbar = Hotbar.new()
	hud.add_child(hotbar)
	hotbar.setup(inventory, energy)
	hotbar.slot_selected.connect(inventory.select_hotbar)
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
func _apply_world_bounds(world_size: Vector2 = WORLD_SIZE) -> void:
	player_bounds = Rect2(Vector2(18, 18), world_size - Vector2(36, 36))
	_set_camera_outdoors(world_size)
	var half := WALL_THICKNESS / 2.0
	var walls := {
		"BoundaryLeft": Vector2(-half, world_size.y / 2.0),
		"BoundaryRight": Vector2(world_size.x + half, world_size.y / 2.0),
		"BoundaryTop": Vector2(world_size.x / 2.0, -half),
		"BoundaryBottom": Vector2(world_size.x / 2.0, world_size.y + half),
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
				rect.size = Vector2(WALL_THICKNESS, world_size.y + WALL_THICKNESS * 2.0)
			else:
				rect.size = Vector2(world_size.x + WALL_THICKNESS * 2.0, WALL_THICKNESS)


## Zona exterior por la que pueden pasear aldeanos y animales (la misma del jugador).
func _outdoor_bounds(world_size: Vector2 = WORLD_SIZE) -> Rect2:
	return Rect2(Vector2(18, 18), world_size - Vector2(36, 36))


func _set_camera_outdoors(world_size: Vector2 = WORLD_SIZE) -> void:
	if camera == null:
		return
	camera.zoom = outdoor_zoom
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world_size.x)
	camera.limit_bottom = int(world_size.y)


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


func _on_clock_changed(day: int, minutes: int) -> void:
	if is_instance_valid(hud) and hud.is_node_ready():
		hud.set_clock(day, minutes)
	_apply_daylight()


func _on_day_changed(day: int) -> void:
	crop_manager.advance_day(day)
	if is_instance_valid(hud) and hud.is_node_ready():
		hud.show_toast("Día %d · ¡Amanece!" % day, UiKit.COLOR_ACCENT)


func _on_day_ended(_day: int) -> void:
	if transitioning:
		_pass_out_when_ready()
	else:
		_pass_out()


func _pass_out_when_ready() -> void:
	while transitioning:
		await get_tree().process_frame
	if day_cycle.minutes >= DayCycle.END_MINUTES:
		_pass_out()


func _apply_daylight() -> void:
	if not is_instance_valid(daylight) or day_cycle == null:
		return
	daylight.color = Color.WHITE if inside_house else day_cycle.daylight_color()


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
	houses.setup(town_world)
	town_interior = InteriorRoom.new()
	town_interior.name = "Interior"
	town_interior.position = INTERIOR_ORIGIN
	town_world.add_child(town_interior)
	interior = town_interior


func _current_house_manager() -> HouseManager:
	return farm_houses if world == farm_world else houses


# -----------------------------------------------------------------------------
# Movimiento e interacción
# -----------------------------------------------------------------------------

func _is_input_blocked() -> bool:
	return not game_started or dialogue_open or transitioning or _settings_open() \
			or _controls_open() or _pause_open() or _inventory_open() or _shop_open()


func _inventory_open() -> bool:
	return is_instance_valid(inventory_panel) and inventory_panel.visible


func _settings_open() -> bool:
	return is_instance_valid(settings_dialog)


func _controls_open() -> bool:
	return is_instance_valid(controls_dialog)


func _pause_open() -> bool:
	return is_instance_valid(pause_menu)


func _shop_open() -> bool:
	return is_instance_valid(trade_panel)


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
		elif _shop_open():
			_close_shop()
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
	if not dialogue_open and not _shop_open() and not _inventory_open():
		for index in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed(Controls.HOTBAR_ACTIONS[index]):
				inventory.select_hotbar(index)
				return
	if event.is_action_pressed(Controls.INVENTORY) and not dialogue_open:
		_toggle_inventory()
		return
	if _is_input_blocked():
		return
	if event.is_action_pressed(Controls.ENTER):
		_use_door()
		return
	if inside_house:
		if event.is_action_pressed(Controls.INTERACT) and _can_sleep():
			_sleep_in_bed()
		return
	if not event.is_action_pressed(Controls.INTERACT):
		return
	var nearby_npc := _nearest_npc()
	if nearby_npc != null:
		_open_dialogue(nearby_npc)
		return
	_use_selected_item()


func _nearest_npc() -> VillageNpc:
	var closest: VillageNpc = null
	var closest_distance := NPC_INTERACT_DISTANCE
	if not is_instance_valid(player):
		return closest
	for npc in npcs:
		if not is_instance_valid(npc):
			continue
		if not world.is_ancestor_of(npc):
			continue
		var distance := player.position.distance_to(npc.position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = npc
	return closest


func _facing_vector() -> Vector2:
	match player_facing:
		"up":
			return Vector2.UP
		"side":
			return Vector2.LEFT if player_sprite.flip_h else Vector2.RIGHT
		_:
			return Vector2.DOWN


func _target_farm_plot() -> CropManager.CropPlot:
	if not is_instance_valid(player):
		return null
	var target := player.position + _facing_vector() * 30.0
	return crop_manager.target_plot(target, player.position)


func _selected_plot_action(plot: CropManager.CropPlot, item_id: String) -> String:
	if plot == null or item_id.is_empty():
		return ""
	if item_id == "pickaxe":
		return "PREPARAR TIERRA" if not plot.tilled else "TIERRA PREPARADA"
	if ItemDb.is_seed(item_id):
		if not inventory.has_item(item_id):
			return "SIN SEMILLAS"
		if not plot.tilled:
			return "CAMBIA AL PICO PARA PREPARAR"
		return "PLANTAR %s" % ItemDb.display_name(ItemDb.crop_for_seed(item_id)).to_upper() if not plot.is_planted() else "PARCELA OCUPADA"
	if item_id == "watering_can":
		if plot.is_planted() and not plot.is_mature() and not plot.watered_today:
			return "REGAR %s" % ItemDb.display_name(plot.crop_id).to_upper()
		if plot.watered_today:
			return "YA REGADO HOY"
		return "NO HAY NADA QUE REGAR"
	if item_id == "hoe":
		if plot.is_mature():
			return "COSECHAR %s" % ItemDb.display_name(plot.crop_id).to_upper()
		return "AÚN NO ESTÁ LISTO"
	return ""


func _use_selected_item() -> void:
	var item_id := inventory.selected_item()
	var plot := _target_farm_plot()
	if plot == null:
		if world == farm_world and (ItemDb.is_seed(item_id) or item_id in ["pickaxe", "watering_can", "hoe"]):
			hud.show_toast("Acércate a una parcela cercada", UiKit.COLOR_FAINT)
		return

	var success := false
	if item_id == "pickaxe":
		if plot.tilled:
			hud.show_toast("Esta tierra ya está preparada", UiKit.COLOR_FAINT)
			return
		success = true
	elif item_id == "watering_can":
		if not plot.is_planted():
			hud.show_toast("Primero planta una semilla", UiKit.COLOR_FAINT)
			return
		if plot.is_mature():
			hud.show_toast("Ese cultivo ya está maduro", UiKit.COLOR_FAINT)
			return
		if plot.watered_today:
			hud.show_toast("Ya regaste este cultivo hoy", UiKit.COLOR_FAINT)
			return
		success = true
	elif item_id == "hoe":
		if not plot.is_mature():
			hud.show_toast("El cultivo aún no está listo para cosechar", UiKit.COLOR_FAINT)
			return
		var crop_id := plot.crop_id
		if inventory.clone().add(crop_id, 1) > 0:
			hud.show_toast("Mochila llena", UiKit.COLOR_RED)
			return
		if not _spend_tool_energy():
			return
		inventory.add(crop_id, 1)
		crop_manager.harvest(plot)
		hud.show_toast("+1 %s" % ItemDb.display_name(crop_id))
		_update_interaction_prompt()
		return
	elif ItemDb.is_seed(item_id):
		if not plot.tilled:
			hud.show_toast("Prepara primero la tierra con el pico", UiKit.COLOR_FAINT)
			return
		if plot.is_planted():
			hud.show_toast("Esta parcela ya tiene una semilla", UiKit.COLOR_FAINT)
			return
		if not inventory.has_item(item_id):
			hud.show_toast("No te quedan semillas de ese tipo", UiKit.COLOR_RED)
			return
		success = true
	else:
		hud.show_toast("Elige una herramienta o unas semillas en la barra", UiKit.COLOR_FAINT)
		return

	if not success or not _spend_tool_energy():
		return
	match item_id:
		"pickaxe":
			crop_manager.till(plot)
			hud.show_toast("Tierra preparada")
		"watering_can":
			crop_manager.water(plot)
			hud.show_toast("Cultivo regado · crecerá al amanecer")
		_:
			if inventory.remove_matching(item_id, 1):
				crop_manager.plant(plot, item_id)
				hud.show_toast("Semilla plantada")
	_update_interaction_prompt()


func _spend_tool_energy() -> bool:
	if energy.spend(TOOL_ENERGY_COST):
		return true
	hud.show_toast("No tienes energía. Ve a dormir para recuperarla.", UiKit.COLOR_RED)
	return false


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
		if _can_sleep():
			hud.show_prompt("%s   DORMIR" % Controls.key_label(Controls.INTERACT).to_upper())
		elif interior.near_exit(player.position):
			hud.show_prompt("%s   SALIR · %s" % [enter_key, String(current_house.get("name", "Casa")).to_upper()])
		else:
			hud.hide_prompt()
		return
	var nearby_npc := _nearest_npc()
	if nearby_npc != null:
		hud.show_prompt("%s   HABLAR CON %s" % [Controls.key_label(Controls.INTERACT).to_upper(), nearby_npc.profile.display_name.to_upper()])
		return
	var door := _current_house_manager().nearest_door(player.position)
	if not door.is_empty():
		hud.show_prompt("%s   ENTRAR · %s" % [enter_key, String(door["name"]).to_upper()])
		return
	var plot := _target_farm_plot()
	var action := _selected_plot_action(plot, inventory.selected_item())
	if not action.is_empty() and not action.begins_with("TIERRA PREPARADA") \
			and not action.begins_with("PARCELA OCUPADA") \
			and not action.begins_with("CAMBIA AL PICO") \
			and not action.begins_with("YA REGADO") \
			and not action.begins_with("NO HAY") \
			and not action.begins_with("SIN SEMILLAS") \
			and not action.begins_with("AÚN NO"):
		hud.show_prompt("%s   %s" % [Controls.key_label(Controls.INTERACT).to_upper(), action])
		return
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
	if world != town_world and world != farm_world:
		return
	var door := _current_house_manager().nearest_door(player.position)
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
	interior = farm_interior if world == farm_world else town_interior
	interior.build(String(door["interior"]))
	inside_house = true
	player.position = interior.spawn_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_bounds = interior.player_bounds()
	player_facing = "up"
	player_sprite.flip_h = false
	_set_camera_indoors()
	_apply_daylight()
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
	var world_size := FARM_WORLD_SIZE if world == farm_world else WORLD_SIZE
	player_bounds = _outdoor_bounds(world_size)
	player_facing = "down"
	player_sprite.flip_h = false
	_set_camera_outdoors(world_size)
	_apply_daylight()
	hud.set_location("Tu granja" if world == farm_world else DEFAULT_PLACE)
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_update_interaction_prompt()


func _can_sleep() -> bool:
	return inside_house and world == farm_world \
			and String(current_house.get("interior", "")) == "farmhome" \
			and interior != null and interior.near_bed(player.position)


func _sleep_in_bed() -> void:
	if transitioning or not _can_sleep():
		return
	transitioning = true
	player.velocity = Vector2.ZERO
	hud.hide_prompt()
	await hud.fade_to(1.0, FADE_TIME)
	day_cycle.sleep_until_morning()
	energy.restore_full()
	player.position = interior.wake_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_facing = "down"
	player_sprite.flip_h = false
	player_sprite.play("idle_down")
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	_update_interaction_prompt()


func _pass_out() -> void:
	if transitioning or not game_started:
		return
	if dialogue_open:
		_close_dialogue()
	if _shop_open():
		_close_shop()
	if _inventory_open():
		inventory_panel.close()
	if _settings_open():
		_close_settings()
	if _controls_open():
		_close_controls()
	transitioning = true
	player.velocity = Vector2.ZERO
	hud.hide_prompt()
	await hud.fade_to(1.0, FADE_TIME)
	_ensure_farm_world()
	if inside_house and interior != null:
		interior.clear()
	inside_house = false
	if world != farm_world:
		var previous_world := world
		if player.get_parent() == previous_world:
			previous_world.remove_child(player)
		previous_world.visible = false
		previous_world.process_mode = Node.PROCESS_MODE_DISABLED
		previous_world.position = INACTIVE_WORLD_OFFSET
		farm_world.position = Vector2.ZERO
		farm_world.visible = true
		farm_world.process_mode = Node.PROCESS_MODE_PAUSABLE
		farm_world.add_child(player)
		world = farm_world
	else:
		farm_world.visible = true
		farm_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	interior = farm_interior
	farm_interior.clear()
	farm_interior.build("farmhome")
	inside_house = true
	current_house = {"name": "Casa de la Granja", "interior": "farmhome"}
	if not farm_houses.doors.is_empty():
		exit_position = farm_houses.doors[0]["exit_position"]
	player.position = farm_interior.wake_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_bounds = farm_interior.player_bounds()
	player_facing = "down"
	player_sprite.flip_h = false
	player_sprite.play("idle_down")
	crop_manager.activate_world(farm_world)
	day_cycle.sleep_until_morning()
	energy.set_value(Energy.MAX_ENERGY / 2)
	_set_camera_indoors()
	_apply_daylight()
	hud.set_location(String(current_house["name"]))
	await get_tree().process_frame
	if camera != null:
		camera.reset_smoothing()
	await hud.fade_to(0.0, FADE_TIME)
	transitioning = false
	hud.show_toast("Te dormiste a las 2:00 · Energía: 50%", UiKit.COLOR_ACCENT)
	_update_interaction_prompt()


# -----------------------------------------------------------------------------
# Viaje entre el pueblo y la granja
# -----------------------------------------------------------------------------

func _connect_world_exit(scene: Node2D, area_name: String, leads_to_farm: bool) -> void:
	var exit_area := scene.get_node_or_null(area_name) as Area2D
	if exit_area == null:
		push_warning("No se encontró la salida '%s' en %s." % [area_name, scene.name])
		return
	exit_area.body_entered.connect(_on_world_exit_body_entered.bind(leads_to_farm))


func _on_world_exit_body_entered(body: Node2D, leads_to_farm: bool) -> void:
	if body != player or not game_started or transitioning or inside_house:
		return
	if leads_to_farm:
		_enter_farm()
	else:
		_leave_farm()


func _enter_farm() -> void:
	if transitioning or world != town_world:
		return
	transitioning = true
	player.velocity = Vector2.ZERO
	hud.hide_prompt()
	town_return_position = Vector2(TOWN_RETURN_X, clampf(player.position.y, 340.0, 450.0))
	await hud.fade_to(1.0, FADE_TIME)
	_ensure_farm_world()
	_switch_outdoor_world(farm_world, Vector2(FARM_WORLD_SIZE.x - 72.0, 398.0), FARM_WORLD_SIZE, "Tu granja")
	await _finish_world_transition()


func _ensure_farm_world() -> void:
	if farm_world != null:
		return
	farm_world = FARM_SCENE.instantiate() as Node2D
	farm_world.name = "FarmWorld"
	farm_world.position = Vector2.ZERO
	farm_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(farm_world)
	_connect_world_exit(farm_world, "FarmTownExit", false)
	AnimalLife.start(farm_world, player, _outdoor_bounds(FARM_WORLD_SIZE))
	farm_houses.setup(farm_world, HouseManager.FARM_HOUSES)
	farm_interior = InteriorRoom.new()
	farm_interior.name = "FarmInterior"
	farm_interior.position = INTERIOR_ORIGIN
	farm_world.add_child(farm_interior)


func _leave_farm() -> void:
	if transitioning or world != farm_world:
		return
	transitioning = true
	player.velocity = Vector2.ZERO
	hud.hide_prompt()
	await hud.fade_to(1.0, FADE_TIME)
	_switch_outdoor_world(town_world, town_return_position, WORLD_SIZE, DEFAULT_PLACE)
	await _finish_world_transition()


func _switch_outdoor_world(destination_world: Node2D, spawn: Vector2, world_size: Vector2, place: String) -> void:
	var previous_world := world
	previous_world.remove_child(player)
	previous_world.visible = false
	previous_world.process_mode = Node.PROCESS_MODE_DISABLED
	previous_world.position = INACTIVE_WORLD_OFFSET

	if destination_world == town_world:
		destination_world.position = town_world_position
	else:
		destination_world.position = Vector2.ZERO
	destination_world.visible = true
	destination_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	destination_world.add_child(player)
	world = destination_world

	player.position = spawn
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player_facing = "side"
	player_sprite.flip_h = destination_world == farm_world
	player_sprite.play("idle_side")
	_apply_world_bounds(world_size)
	crop_manager.activate_world(world)
	hud.set_location(place)


func _finish_world_transition() -> void:
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
	day_cycle.start()
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


func _open_market() -> void:
	if not dialogue_open or active_npc == null or world != town_world:
		return
	var seller_name := active_npc.profile.display_name
	_close_dialogue()
	trade_panel = TradePanel.new()
	hud.add_child(trade_panel)
	trade_panel.setup(inventory, seller_name)
	trade_panel.buy_seed_requested.connect(_buy_seed_pack)
	trade_panel.sell_crop_requested.connect(_sell_crop)
	trade_panel.close_requested.connect(_close_shop)
	hud.hide_prompt()


func _close_shop() -> void:
	if is_instance_valid(trade_panel):
		trade_panel.queue_free()
	trade_panel = null
	_update_interaction_prompt()


func _buy_seed_pack(seed_id: String) -> void:
	if not ItemDb.is_seed(seed_id):
		return
	if inventory.coins < ItemDb.SEED_PACK_PRICE:
		hud.show_toast("No tienes suficientes monedas", UiKit.COLOR_RED)
		return
	if inventory.clone().add(seed_id, ItemDb.SEED_PACK_AMOUNT) > 0:
		hud.show_toast("Mochila llena", UiKit.COLOR_RED)
		return
	if not inventory.spend_coins(ItemDb.SEED_PACK_PRICE):
		return
	inventory.add(seed_id, ItemDb.SEED_PACK_AMOUNT)
	hud.show_toast("Compraste %d × %s" % [ItemDb.SEED_PACK_AMOUNT, ItemDb.display_name(seed_id)])


func _sell_crop(crop_id: String) -> void:
	if not ItemDb.is_crop(crop_id) or not inventory.remove_matching(crop_id, 1):
		return
	var price := ItemDb.sell_price(crop_id)
	inventory.add_coins(price)
	hud.show_toast("Vendiste %s · +%d monedas" % [ItemDb.display_name(crop_id), price], UiKit.COLOR_ACCENT)


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
