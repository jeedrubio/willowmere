class_name QuestLog
extends RefCounted
## Misiones de los vecinos. Todas son de entrega: piden objetos que el jugador
## lleva en su Inventory y los consumen al entregarlos.
##
## Para añadir una misión agrega un diccionario a QUESTS:
##   id            identificador único
##   giver         NpcProfile.id de quien la da (data/npcs/*.tres)
##   giver_name    nombre que se muestra en el HUD
##   requires      ids de misiones que deben estar completadas antes
##   needs         {id de objeto o ItemDb.ANY_CROP: cantidad}
##   reward_coins  monedas
##   reward_items  {id de objeto: cantidad}
##   offer / progress / complete / after   textos de diálogo

signal changed
signal quest_started(title: String)
signal quest_completed(title: String, coins: int, rewards: Array)

const QUESTS := [
	{
		"id": "mira_garden", "giver": "mira", "giver_name": "Mira",
		"title": "El encargo del jardín de Mira", "requires": [],
		"needs": {"@crop": 5},
		"reward_coins": 30, "reward_items": {"garden_star": 1},
		"offer": "¿Podrías echarme una mano con el jardín de primavera? Recoge cinco cultivos de los huertos del pueblo y tráemelos. ¡Cualquier tipo sirve!",
		"progress": "¿Sigues recolectando? Los huertos están llenos de cultivos; solo espera a que maduren y recoge los que se vean listos.",
		"complete": "¡Recogiste todos los cultivos! El jardín estará floreciente antes del atardecer. Toma esta Estrella del Jardín como agradecimiento, y unas monedas por las molestias.",
		"after": "El jardín vuelve a florecer, gracias a ti.",
	},
	{
		"id": "mira_berries", "giver": "mira", "giver_name": "Mira",
		"title": "Día de la mermelada de fresa", "requires": ["mira_garden"],
		"needs": {"strawberry": 6},
		"reward_coins": 45, "reward_items": {"berry_jam": 1},
		"offer": "¡Estoy preparando mermelada para todo el pueblo! Necesito seis fresas maduras. Son las que tienen el fruto rojo brillante.",
		"progress": "La olla de la mermelada ya se está calentando, pero todavía me faltan fresas.",
		"complete": "¡Fresas perfectas! Aquí tienes un frasco de la primera tanda y unas monedas por la fruta fresca.",
		"after": "En el pueblo no dejan de hablar de mi mermelada. ¡Gracias otra vez!",
	},
	{
		"id": "elsie_pies", "giver": "elsie", "giver_name": "Elsie",
		"title": "Tartas saladas", "requires": [],
		"needs": {"potato": 4, "onion": 4},
		"reward_coins": 50, "reward_items": {"sweet_loaf": 1},
		"offer": "¡Estoy horneando tartas saladas para la posada y mi despensa está vacía! Tráeme cuatro papas y cuatro cebollas, y verás que vale la pena.",
		"progress": "El horno está caliente y esperando. Todavía me faltan papas y cebollas para el relleno.",
		"complete": "¡Maravilloso, las tartas estarán doradas para el mediodía! Llévate un pan dulce y unas monedas.",
		"after": "Las tartas se agotaron en una hora. ¡Vuelve cuando quieras por un pan calientito!",
	},
	{
		"id": "orin_lunch", "giver": "orin", "giver_name": "Orin",
		"title": "El almuerzo del herrero", "requires": [],
		"needs": {"potato": 6},
		"reward_coins": 40, "reward_items": {"lucky_horseshoe": 1},
		"offer": "Martillar da hambre. Seis buenas papas me alimentarían toda la semana. Tráelas y te pagaré en monedas y hierro.",
		"progress": "Mi estómago suena más fuerte que mi yunque. ¿Seis papas, recuerdas?",
		"complete": "¡Eso sí es un almuerzo! Toma, una herradura que forjé. Guárdala para la buena suerte.",
		"after": "La mejor comida de toda la temporada. Ahora la fragua funciona a base de papas.",
	},
	{
		"id": "tomas_soup", "giver": "tomas", "giver_name": "Tomas",
		"title": "Sopa de puerro junto al lago", "requires": [],
		"needs": {"leek": 5},
		"reward_coins": 45, "reward_items": {"river_pearl": 1},
		"offer": "Las carpas no están picando, así que haré sopa. Con cinco puerros bastaría. ¿Podrías traérmelos?",
		"progress": "Shh... sigo esperando esos puerros. La olla de la sopa está vacía.",
		"complete": "¡Qué puerros tan hermosos! Esta sopa calentará todo el lago. Toma esta perla que encontré, y unas monedas.",
		"after": "La sopa estuvo grandiosa. Aunque todavía ni una carpa.",
	},
	{
		"id": "bram_stew", "giver": "bram", "giver_name": "Bram",
		"title": "El estofado del posadero", "requires": [],
		"needs": {"leek": 3, "potato": 3, "onion": 3},
		"reward_coins": 70, "reward_items": {"inn_token": 1},
		"offer": "Todos los huéspedes de la Posada del Sol quieren mi estofado, y un buen estofado necesita tres puerros, tres papas y tres cebollas. ¿Me ayudas?",
		"progress": "A la olla del estofado todavía le faltan verduras. ¡Tres puerros, tres papas, tres cebollas!",
		"complete": "¡Ese es el estofado de la temporada! Toma una ficha para una noche de descanso gratis y una bolsa de monedas.",
		"after": "Los huéspedes siguen preguntando por ese estofado. Gracias a ti, la posada está llena esta noche.",
	},
	{
		"id": "juno_samples", "giver": "juno", "giver_name": "Juno",
		"title": "El mapa de los campos", "requires": ["mira_garden"],
		"needs": {"strawberry": 2, "leek": 2, "potato": 2, "onion": 2},
		"reward_coins": 80, "reward_items": {"explorer_map": 1},
		"offer": "Estoy trazando las tierras de cultivo del valle y necesito muestras de cada cultivo para rotular el mapa; dos de cada uno, por favor: fresas, puerros, papas y cebollas.",
		"progress": "El mapa tiene espacios en blanco donde irían las muestras. ¿Dos de cada cultivo, recuerdas?",
		"complete": "¡Justo lo que el mapa necesitaba! Aquí tienes una copia de la carta del valle y unas monedas por la caminata.",
		"after": "Los campos se ven hermosos en papel. Casi se pueden oler.",
	},
	{
		"id": "mira_feast", "giver": "mira", "giver_name": "Mira",
		"title": "El banquete de la cosecha de primavera", "requires": ["bram_stew", "juno_samples"],
		"needs": {"@crop": 12},
		"reward_coins": 150, "reward_items": {"spring_crown": 1},
		"offer": "Bram y Juno me contaron todo lo que has hecho por el pueblo. ¡Celebremos con un banquete de cosecha! Tráeme doce cultivos de cualquier tipo.",
		"progress": "La mesa del banquete está puesta, pero las canastas siguen medio vacías.",
		"complete": "¡Qué cosecha! Todo el pueblo hará banquete esta noche. ¡Te ganaste esta Corona de Primavera, héroe de Willowmere!",
		"after": "El banquete fue la noche más feliz que Willowmere ha visto en años.",
	},
]

## "active" o "done" por id de misión. Sin entrada = todavía no aceptada.
var states := {}
var inventory: Inventory


func attach_inventory(inv: Inventory) -> void:
	inventory = inv
	inventory.changed.connect(changed.emit)


func is_done(id: String) -> bool:
	return states.get(id, "") == "done"


func done_count() -> int:
	var total := 0
	for state in states.values():
		if state == "done":
			total += 1
	return total


func _requirements_met(quest: Dictionary) -> bool:
	for req in quest["requires"]:
		if not is_done(String(req)):
			return false
	return true


## Misión que `giver_id` tiene para ofrecer o recibir ahora (activa primero).
func _quest_for(giver_id: String) -> Dictionary:
	for entry in QUESTS:
		var quest: Dictionary = entry
		if quest["giver"] == giver_id and states.get(String(quest["id"]), "") == "active":
			return quest
	for entry in QUESTS:
		var quest: Dictionary = entry
		if quest["giver"] == giver_id and not states.has(String(quest["id"])) and _requirements_met(quest):
			return quest
	return {}


func _needs_met(quest: Dictionary) -> bool:
	var needs: Dictionary = quest["needs"]
	for key in needs:
		if inventory.count_matching(String(key)) < int(needs[key]):
			return false
	return true


## ¿Caben las recompensas una vez entregados los objetos?
func _rewards_fit(quest: Dictionary) -> bool:
	var test := inventory.clone()
	var needs: Dictionary = quest["needs"]
	for key in needs:
		test.remove_matching(String(key), int(needs[key]))
	var items: Dictionary = quest["reward_items"]
	for key in items:
		if test.add(String(key), int(items[key])) > 0:
			return false
	return true


func _have_text(quest: Dictionary) -> String:
	var parts: PackedStringArray = []
	var needs: Dictionary = quest["needs"]
	for key in needs:
		var need := int(needs[key])
		var have := mini(inventory.count_matching(String(key)), need)
		parts.append("%s %d/%d" % [ItemDb.display_name(String(key)), have, need])
	return ", ".join(parts)


## Diálogo de misión de este vecino. Devuelve "" si no tiene nada que decir
## (entonces se usa su saludo normal). Aquí se aceptan y se entregan misiones.
func talk_to(profile: NpcProfile) -> String:
	if profile == null or inventory == null:
		return ""
	var quest := _quest_for(profile.id)
	if quest.is_empty():
		return _last_done_line(profile.id)
	var id := String(quest["id"])
	if states.get(id, "") == "active":
		if _needs_met(quest):
			if not _rewards_fit(quest):
				return "¡Tu mochila está desbordada! Haz espacio y vuelve para que pueda agradecerte como se debe."
			_complete(quest)
			return String(quest["complete"])
		return "%s\n\n(Tienes: %s)" % [String(quest["progress"]), _have_text(quest)]
	states[id] = "active"
	quest_started.emit(String(quest["title"]))
	changed.emit()
	return String(quest["offer"])


func _last_done_line(giver_id: String) -> String:
	for i in range(QUESTS.size() - 1, -1, -1):
		var quest: Dictionary = QUESTS[i]
		if quest["giver"] == giver_id and is_done(String(quest["id"])):
			return String(quest["after"])
	return ""


func _complete(quest: Dictionary) -> void:
	var needs: Dictionary = quest["needs"]
	for key in needs:
		inventory.remove_matching(String(key), int(needs[key]))
	states[String(quest["id"])] = "done"
	var coins := int(quest["reward_coins"])
	var reward_names: Array = []
	var items: Dictionary = quest["reward_items"]
	for key in items:
		inventory.add(String(key), int(items[key]))
		reward_names.append(ItemDb.display_name(String(key)))
	if coins > 0:
		inventory.add_coins(coins)
	quest_completed.emit(String(quest["title"]), coins, reward_names)
	changed.emit()


## Datos para el HUD: una entrada por misión activa.
func tracker_entries() -> Array:
	var entries: Array = []
	for entry in QUESTS:
		var quest: Dictionary = entry
		if states.get(String(quest["id"]), "") != "active":
			continue
		var lines: PackedStringArray = []
		var needs: Dictionary = quest["needs"]
		for key in needs:
			var need := int(needs[key])
			var have := mini(inventory.count_matching(String(key)), need)
			lines.append("%s  %d / %d" % [ItemDb.display_name(String(key)), have, need])
		var ready := _needs_met(quest)
		if ready:
			lines.append("¡Listo! Llévaselo a %s." % String(quest["giver_name"]))
		else:
			lines.append("Entrégaselo a %s." % String(quest["giver_name"]))
		entries.append({
			"title": String(quest["title"]).to_upper(),
			"detail": "\n".join(lines),
			"ready": ready,
		})
	return entries


## Texto del HUD cuando no hay ninguna misión activa.
func idle_text() -> String:
	if done_count() >= QUESTS.size():
		return "¡Todos los encargos completados! Willowmere te lo agradece."
	return "Sin encargos activos.\nHabla con los aldeanos para encontrar nuevos."
