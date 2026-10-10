class_name AnimalLife
extends RefCounted
## Da vida a los animales de la granja. Cada Sprite2D de World.tscn cuya textura
## esté en "asset_pack/Farm Animals/" se convierte en un animal que pasea, descansa
## y (las aves) huye si te acercas mucho. No hay que tocar la escena: para añadir un
## animal basta con colocar otro sprite con su hoja (hframes/vframes) en World.
##
## Las hojas tienen 4 columnas. Vacas: fila 0 de lado, fila 1 de frente, fila 2 de
## espaldas. Gallinas y pollitos: fila 0 caminando, fila 1 picoteando.

const SPECIES := {
	"cow": {
		"walk": {"side": [0, 1, 2, 3], "down": [4, 5, 6, 7], "up": [8, 9, 10, 11]},
		"idle": {"side": [0, 0, 0, 1, 0, 0], "down": [4], "up": [8]},
		"directional": true,
		"walk_fps": 5.0,
		"idle_fps": 1.2,
		"size": Vector2(24, 10),
		"foot": 12.0,
		"speed": 22.0,
		"radius": 100.0,
		"pause_min": 3.0,
		"pause_max": 9.0,
	},
	"chicken": {
		"walk": {"side": [0, 1, 2, 3]},
		"idle": {"side": [4, 5, 6, 7]},
		"directional": false,
		"walk_fps": 8.0,
		"idle_fps": 3.0,
		"size": Vector2(12, 8),
		"foot": 11.0,
		"speed": 30.0,
		"radius": 70.0,
		"pause_min": 1.0,
		"pause_max": 4.0,
		"flee": 44.0,
	},
	"chick": {
		"walk": {"side": [0, 1, 2, 3]},
		"idle": {"side": [4, 5, 6, 7]},
		"directional": false,
		"walk_fps": 9.0,
		"idle_fps": 3.0,
		"size": Vector2(9, 6),
		"foot": 9.0,
		"speed": 34.0,
		"radius": 34.0,
		"pause_min": 0.8,
		"pause_max": 2.5,
		"flee": 34.0,
	},
}

## Ajustes por nombre de nodo. "follow": pasea alrededor de otro nodo (el pollito sigue a su madre).
const OVERRIDES := {
	"BabyChicken": {"follow": "RedChickenEast"},
}


## Pone a pasear a todos los animales de `world`. Devuelve los WanderActor creados.
static func start(world: Node2D, player: Node2D, bounds: Rect2) -> Array[WanderActor]:
	var actors: Array[WanderActor] = []
	for child in world.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var species := _species_for(sprite.texture.resource_path)
		if species.is_empty():
			continue
		var config: Dictionary = (SPECIES[species] as Dictionary).duplicate(true)
		var overrides: Dictionary = OVERRIDES.get(String(sprite.name), {})
		config.merge(overrides, true)
		var follow: Node2D = null
		if config.has("follow"):
			follow = world.find_child(String(config["follow"]), true, false) as Node2D
		actors.append(WanderActor.for_animal(sprite, player, bounds, config, follow))
	return actors


static func _species_for(texture_path: String) -> String:
	var path := texture_path.to_lower()
	if not path.contains("farm animals"):
		return ""
	if path.contains("baby chicken"):
		return "chick"
	if path.contains("chicken"):
		return "chicken"
	if path.contains("cow"):
		return "cow"
	return ""
