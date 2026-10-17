class_name InteriorDb
extends RefCounted
## Datos de los interiores de las casas: piezas del atlas Interior.png, paletas
## de colores y la distribución de muebles de cada casa.
##
## Para añadir o cambiar una habitación edita LAYOUTS. Cada elemento es
##   [pieza, x, y]            mueble: (x, y) = centro de la base, en píxeles de la habitación
##   [pieza, x, y, y_base]    objeto apoyado encima de otro mueble cuya base está en y_base
## La habitación mide ROOM_SIZE (se dibuja a escala SCALE, igual que casas y personajes).

const ATLAS: Texture2D = preload("res://asset_pack/Objects/Interior.png")

const SCALE := 1.4
const ROOM_SIZE := Vector2(320, 208)
const WALL_HEIGHT := 56.0     # pared del fondo
const FRONT_Y := 192.0        # donde empieza la pared de enfrente (con la puerta)
const SIDE := 12.0            # grosor de las paredes laterales
const EXIT_POINT := Vector2(160, 188)
const SPAWN_POINT := Vector2(160, 166)
const DOOR_RECT := Rect2(144, 19, 16, 23)

## kind: "solid" (colisiona), "wall" (colgado de la pared) o "floor" (alfombra).
## rect: región en Interior.png. foot: huella de colisión (ancho, alto) sobre la base.
const PROPS := {
	"tulips": {"rect": Rect2(4, 1, 8, 15), "foot": Vector2(8, 5)},
	"frame_flowers": {"rect": Rect2(18, 1, 12, 15), "kind": "wall"},
	"plant": {"rect": Rect2(34, 0, 11, 16), "foot": Vector2(9, 6)},
	"clock": {"rect": Rect2(1, 18, 13, 13), "kind": "wall"},
	"frame_egg": {"rect": Rect2(18, 18, 13, 13), "kind": "wall"},
	"window": {"rect": Rect2(1, 48, 14, 16), "kind": "wall"},
	"bed_v": {"rect": Rect2(87, 8, 18, 34), "foot": Vector2(18, 26)},
	"bed_h": {"rect": Rect2(80, 52, 32, 24), "foot": Vector2(32, 16)},
	"fireplace": {"rect": Rect2(115, 8, 26, 40), "foot": Vector2(24, 12)},
	"rug": {"rect": Rect2(0, 82, 48, 30), "kind": "floor"},
	"table": {"rect": Rect2(68, 120, 24, 23), "foot": Vector2(22, 12)},
	"cabinet_a": {"rect": Rect2(96, 120, 16, 18), "foot": Vector2(16, 10)},
	"cabinet_b": {"rect": Rect2(112, 120, 16, 18), "foot": Vector2(16, 10)},
	"cabinet_c": {"rect": Rect2(128, 120, 16, 18), "foot": Vector2(16, 10)},
	"cabinet_d": {"rect": Rect2(144, 120, 16, 18), "foot": Vector2(16, 10)},
	"chair_front": {"rect": Rect2(2, 125, 11, 18), "foot": Vector2(9, 6)},
	"chair_front2": {"rect": Rect2(18, 127, 11, 16), "foot": Vector2(9, 6)},
	"chair_right": {"rect": Rect2(35, 125, 10, 18), "foot": Vector2(8, 6)},
	"chair_left": {"rect": Rect2(51, 125, 10, 18), "foot": Vector2(8, 6)},
}

const THEMES := {
	"meadow": {"floor": Color("#B58B5B"), "floor_line": Color("#9C744A"), "wall": Color("#EAD8B8"), "wainscot": Color("#C9A778"), "trim": Color("#6B4429")},
	"inn": {"floor": Color("#A8774A"), "floor_line": Color("#8E6239"), "wall": Color("#E9CFA8"), "wainscot": Color("#B98B58"), "trim": Color("#5E3A22")},
	"bakery": {"floor": Color("#C79B6B"), "floor_line": Color("#AD8353"), "wall": Color("#F2DCD0"), "wainscot": Color("#D9A99A"), "trim": Color("#7A4A3A")},
	"smithy": {"floor": Color("#6E6A66"), "floor_line": Color("#5B5753"), "wall": Color("#9A948C"), "wainscot": Color("#76706A"), "trim": Color("#3F3A36")},
	"cottage": {"floor": Color("#BF9A6A"), "floor_line": Color("#A5825A"), "wall": Color("#DDE6C8"), "wainscot": Color("#A9BE8C"), "trim": Color("#5F4A2E")},
	"farmhouse": {"floor": Color("#A9794B"), "floor_line": Color("#8F633A"), "wall": Color("#EBDCB6"), "wainscot": Color("#BE9A62"), "trim": Color("#5B3B24")},
	"carpenter": {"floor": Color("#9A6E45"), "floor_line": Color("#80593A"), "wall": Color("#D9C29A"), "wainscot": Color("#A98456"), "trim": Color("#4F3220")},
	"store": {"floor": Color("#B89A72"), "floor_line": Color("#9F825C"), "wall": Color("#E5D3B0"), "wainscot": Color("#B5894E"), "trim": Color("#6A4526")},
	"mill": {"floor": Color("#A68A66"), "floor_line": Color("#8C7355"), "wall": Color("#E3D6BD"), "wainscot": Color("#B7A27A"), "trim": Color("#5A4630")},
	"lake": {"floor": Color("#B89368"), "floor_line": Color("#9E7B53"), "wall": Color("#CFE3E6"), "wainscot": Color("#98BFC6"), "trim": Color("#4F5F63")},
}

const LAYOUTS := {
	"meadow": {"theme": "meadow", "items": [
		["window", 60, 40], ["window", 260, 40], ["frame_flowers", 110, 38], ["clock", 210, 36],
		["fireplace", 160, 76],
		["bed_v", 36, 90], ["cabinet_a", 62, 80], ["tulips", 62, 66, 80],
		["rug", 205, 148], ["table", 205, 136], ["chair_front", 205, 122],
		["chair_right", 183, 138], ["chair_left", 227, 138],
		["plant", 292, 86],
	]},
	"inn": {"theme": "inn", "items": [
		["window", 54, 42], ["window", 102, 42], ["frame_flowers", 190, 38], ["clock", 228, 36],
		["fireplace", 276, 76],
		["bed_v", 30, 90], ["cabinet_a", 54, 82], ["tulips", 54, 68, 82],
		["bed_v", 78, 90], ["cabinet_b", 102, 82], ["bed_v", 126, 90],
		["rug", 240, 156], ["table", 240, 140], ["chair_front", 240, 126],
		["chair_right", 218, 142], ["chair_left", 262, 142],
		["table", 70, 150], ["chair_front", 70, 136], ["chair_right", 48, 152], ["chair_left", 92, 152],
		["plant", 296, 104],
	]},
	"bakery": {"theme": "bakery", "items": [
		["window", 60, 40], ["window", 260, 40], ["frame_egg", 200, 38], ["clock", 160, 36],
		["fireplace", 110, 76], ["cabinet_c", 150, 80], ["cabinet_d", 166, 80],
		["cabinet_a", 96, 126], ["cabinet_b", 112, 126], ["cabinet_c", 128, 126], ["cabinet_d", 144, 126],
		["tulips", 112, 114, 126],
		["rug", 250, 156], ["table", 250, 140], ["chair_front", 250, 126],
		["chair_right", 228, 142], ["chair_left", 272, 142],
		["table", 50, 134], ["chair_front", 50, 120], ["chair_right", 28, 136],
		["plant", 296, 96], ["plant", 28, 90],
	]},
	"smithy": {"theme": "smithy", "items": [
		["window", 50, 40], ["window", 270, 40], ["clock", 220, 36], ["frame_flowers", 110, 38],
		["fireplace", 160, 76],
		["cabinet_c", 40, 98], ["cabinet_d", 56, 98], ["cabinet_c", 72, 98],
		["cabinet_a", 40, 152], ["cabinet_b", 56, 152],
		["bed_h", 262, 98],
		["table", 236, 152], ["chair_front", 236, 138], ["chair_right", 214, 154], ["chair_left", 258, 154],
	]},
	"cottage": {"theme": "cottage", "items": [
		["window", 70, 40], ["window", 250, 40], ["frame_egg", 118, 36], ["frame_flowers", 200, 38],
		["fireplace", 160, 76],
		["bed_v", 36, 90], ["cabinet_b", 60, 82], ["tulips", 60, 68, 82],
		["rug", 160, 148], ["table", 160, 136], ["chair_front", 160, 122],
		["chair_right", 138, 138], ["chair_left", 182, 138],
		["plant", 292, 90], ["plant", 292, 150],
	]},
	"farmhouse": {"theme": "farmhouse", "items": [
		["window", 60, 40], ["window", 130, 40], ["clock", 196, 36], ["frame_egg", 226, 36],
		["fireplace", 170, 76],
		["cabinet_a", 254, 82], ["cabinet_b", 270, 82], ["cabinet_c", 286, 82], ["tulips", 270, 68, 82],
		["bed_h", 50, 94], ["bed_h", 50, 128], ["plant", 100, 92],
		["rug", 230, 158], ["table", 230, 142], ["chair_front", 230, 128],
		["chair_right", 208, 144], ["chair_left", 252, 144],
	]},
	"farmhome": {"theme": "farmhouse", "items": [
		["window", 58, 40], ["window", 258, 40], ["clock", 198, 36], ["frame_flowers", 112, 38],
		["fireplace", 160, 76],
		["bed_v", 36, 112], ["cabinet_a", 86, 102], ["tulips", 86, 88, 102],
		["rug", 208, 158], ["table", 208, 144], ["chair_front", 208, 130],
		["chair_right", 186, 146], ["chair_left", 230, 146],
		["cabinet_c", 270, 92], ["plant", 292, 146],
	]},
	"carpenter": {"theme": "carpenter", "items": [
		["window", 60, 40], ["window", 260, 40], ["clock", 110, 36], ["frame_flowers", 160, 38],
		["fireplace", 200, 76],
		["cabinet_c", 40, 98], ["cabinet_d", 56, 98], ["cabinet_c", 72, 98], ["cabinet_d", 88, 98],
		["cabinet_a", 40, 152], ["cabinet_b", 56, 152], ["cabinet_a", 72, 152], ["cabinet_b", 88, 152],
		["table", 230, 142], ["chair_front", 230, 128], ["chair_right", 208, 144],
		["bed_v", 290, 92], ["plant", 292, 152],
	]},
	"store": {"theme": "store", "items": [
		["window", 70, 40], ["window", 250, 40], ["frame_flowers", 120, 38], ["frame_egg", 200, 38], ["clock", 160, 36],
		["cabinet_a", 32, 82], ["cabinet_b", 48, 82], ["cabinet_c", 64, 82], ["cabinet_d", 80, 82],
		["cabinet_d", 240, 82], ["cabinet_c", 256, 82], ["cabinet_b", 272, 82], ["cabinet_a", 288, 82],
		["cabinet_c", 74, 128], ["cabinet_d", 90, 128], ["cabinet_c", 106, 128],
		["cabinet_d", 214, 128], ["cabinet_c", 230, 128], ["cabinet_d", 246, 128],
		["cabinet_b", 270, 168], ["cabinet_a", 286, 168], ["tulips", 278, 154, 168],
		["plant", 24, 100], ["plant", 24, 150],
	]},
	"mill": {"theme": "mill", "items": [
		["window", 60, 40], ["window", 260, 40], ["frame_egg", 110, 38], ["clock", 210, 36],
		["fireplace", 160, 76],
		["bed_v", 36, 90], ["cabinet_c", 60, 82], ["tulips", 60, 68, 82],
		["cabinet_a", 254, 96], ["cabinet_b", 270, 96], ["cabinet_c", 286, 96],
		["cabinet_d", 254, 130], ["cabinet_a", 270, 130], ["cabinet_b", 286, 130],
		["rug", 110, 162], ["table", 110, 148], ["chair_front", 110, 134],
		["chair_right", 88, 150], ["chair_left", 132, 150],
		["plant", 28, 140],
	]},
	"lake": {"theme": "lake", "items": [
		["window", 100, 40], ["window", 160, 40], ["window", 220, 40],
		["clock", 70, 36], ["frame_egg", 275, 36],
		["fireplace", 36, 76],
		["bed_h", 262, 98], ["cabinet_a", 290, 90], ["tulips", 290, 76, 90],
		["rug", 100, 162], ["table", 100, 148], ["chair_front", 100, 134],
		["chair_right", 78, 150], ["chair_left", 122, 150],
		["plant", 296, 150], ["plant", 70, 100],
	]},
}
