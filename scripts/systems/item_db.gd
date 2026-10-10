class_name ItemDb
extends RefCounted
## Catálogo de objetos del juego. Para añadir uno nuevo basta con una entrada
## en ITEMS: los cultivos usan `row` (fila de "Spring Crops.png") como icono y
## los demás objetos muestran sus iniciales (`abbr`) con el color indicado.

const CROPS_TEXTURE := preload("res://asset_pack/Objects/Spring Crops.png")
## Nombre especial que usan las misiones para pedir "cualquier cultivo".
const ANY_CROP := "@crop"

## Fila de la hoja de cultivos -> id del objeto que se cosecha.
const CROP_ROWS := ["strawberry", "leek", "potato", "onion"]
## Último cuadro (madurez) de cada fila de la hoja de cultivos.
const MATURE_STAGES := [5, 5, 6, 5]
## Multiplicador del tiempo de crecimiento de cada cultivo.
const GROWTH_SCALE := [1.0, 1.1, 1.3, 0.9]

const ITEMS := {
	"strawberry": {"name": "Fresa", "desc": "Dulce y calentita por el sol.", "row": 0, "crop": true},
	"leek": {"name": "Puerro", "desc": "Suave y perfecto para las sopas.", "row": 1, "crop": true},
	"potato": {"name": "Papa", "desc": "Contundente, confiable y buena en todo.", "row": 2, "crop": true},
	"onion": {"name": "Cebolla", "desc": "Te hace llorar, pero mejora la cena.", "row": 3, "crop": true},
	"garden_star": {"name": "Estrella del Jardín", "desc": "Una flor de primavera prensada, regalo de Mira.", "abbr": "EJ", "color": Color("#F2B35F")},
	"berry_jam": {"name": "Frasco de Mermelada", "desc": "La famosa conserva de Mira.", "abbr": "FM", "color": Color("#F58D78")},
	"sweet_loaf": {"name": "Pan Dulce", "desc": "Todavía calientito del horno de Elsie.", "abbr": "PD", "color": Color("#E8C48A")},
	"lucky_horseshoe": {"name": "Herradura de la Suerte", "desc": "Orin jura que trae buena suerte.", "abbr": "HS", "color": Color("#A5B3B1")},
	"river_pearl": {"name": "Perla del Río", "desc": "Tomas la encontró en el Lago Willow.", "abbr": "PR", "color": Color("#9AD7E8")},
	"inn_token": {"name": "Ficha del Posadero", "desc": "Vale por una noche gratis en la Posada del Sol.", "abbr": "FP", "color": Color("#D49A6A")},
	"explorer_map": {"name": "Mapa del Explorador", "desc": "El boceto de Juno de todo el valle.", "abbr": "ME", "color": Color("#C7B98A")},
	"spring_crown": {"name": "Corona de Primavera", "desc": "Tejida con las primeras flores de la temporada.", "abbr": "CP", "color": Color("#77D3B0")},
}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func display_name(id: String) -> String:
	if id == ANY_CROP:
		return "Cultivos de primavera"
	var data: Dictionary = ITEMS.get(id, {})
	return String(data.get("name", id.capitalize()))


static func description(id: String) -> String:
	var data: Dictionary = ITEMS.get(id, {})
	return String(data.get("desc", ""))


static func is_crop(id: String) -> bool:
	var data: Dictionary = ITEMS.get(id, {})
	return bool(data.get("crop", false))


## ¿El objeto `item_id` cuenta como `wanted`? (`wanted` puede ser un id o ANY_CROP.)
static func matches(item_id: String, wanted: String) -> bool:
	if wanted == ANY_CROP:
		return is_crop(item_id)
	return item_id == wanted


## Icono de un cultivo (recorte de la hoja) o null si el objeto usa iniciales.
static func icon(id: String) -> Texture2D:
	var data: Dictionary = ITEMS.get(id, {})
	if not data.has("row"):
		return null
	var texture := AtlasTexture.new()
	texture.atlas = CROPS_TEXTURE
	# Columna 8 = cultivo cosechado; la mitad inferior de la celda de 16x32.
	texture.region = Rect2(128, int(data["row"]) * 32 + 16, 16, 16)
	return texture


static func abbreviation(id: String) -> String:
	var data: Dictionary = ITEMS.get(id, {})
	return String(data.get("abbr", id.left(2).to_upper()))


static func color(id: String) -> Color:
	var data: Dictionary = ITEMS.get(id, {})
	return data.get("color", Color.WHITE)
