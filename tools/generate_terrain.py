#!/usr/bin/env python3
"""Genera el suelo de Willowmere: atlas, TileSet y mapa de celdas por capas.

Salida (relativa a la raíz del proyecto):
  terrain/ground_tiles.png        atlas de tiles de 16x16
  terrain/willowmere_tileset.tres TileSet (fuente 0 = este atlas, fuente 1 = pasto decorativo)
                                  con una Physics Layer: el agua colisiona.
  terrain/ground_map.gd           mapa de 142x76 celdas, una cadena por fila y capa

Capas (nodos TileMapLayer bajo Backdrop en World.tscn):
  Ground   pasto, caminos, callejones y plazas
  Water    estanques y lago (con colisión en el TileSet)
  Garden   tierra de cultivo y surcos
  Border   borde oscuro del mapa
  Decor    parches de pasto decorativo (hoja "Tileset Grass Spring", fuente 1)

Cómo se dibuja:
  - El suelo se define en "cuartos" de 8 px (hierba / borde / camino / plaza),
    así los caminos conservan un borde exacto de 8 px sobre la cuadrícula de 16 px.
  - El agua se define en bloques de 4 px (orilla de arena, borde oscuro, agua),
    así los estanques salen redondeados.
  - Los tiles únicos se deduplican. Cada celda se guarda con 2 caracteres.

Para cambiar el tamaño del mapa edita WORLD_W y WORLD_H (en píxeles, múltiplos de
16) y recuerda que Main.gd tiene su propia constante WORLD_SIZE con el mismo valor.

Uso:  python3 tools/generate_terrain.py        (requiere Pillow)
"""
import math
import os
from PIL import Image

TILE = 16
QUARTER = 8
BLOCK = 4
WORLD_W = 2272
WORLD_H = 1216
COLUMNS = WORLD_W // TILE
ROWS = WORLD_H // TILE
ATLAS_COLUMNS = 8
ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
EMPTY = ".."

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# ---------------------------------------------------------------------------
# Plano del pueblo (en píxeles). World.tscn se arma a partir de estos datos.
# ---------------------------------------------------------------------------

# Caminos: (x0, y0, x1, y1, rango). 1 = borde de camino, 2 = camino, 3 = borde de plaza, 4 = plaza.
ROAD_RECTS = [
    # Calle principal este-oeste (centro y = 380) y avenida norte-sur (centro x = 576)
    (0, 328, WORLD_W, 432, 1), (0, 336, WORLD_W, 424, 2),
    (528, 0, 624, WORLD_H, 1), (536, 0, 616, WORLD_H, 2),
    # Plaza central
    (456, 296, 696, 464, 3), (464, 304, 688, 456, 4),
    # Segunda avenida norte-sur (centro x = 1520) y plaza del mercado
    (1488, 0, 1552, WORLD_H, 1), (1496, 0, 1544, WORLD_H, 2),
    (1440, 316, 1600, 444, 3), (1448, 324, 1592, 436, 4),
    # Calle sur este-oeste (centro y = 900) y plazuela del cruce
    (0, 868, WORLD_W, 932, 1), (0, 876, WORLD_W, 924, 2),
    (496, 852, 656, 948, 3), (504, 860, 648, 940, 4),
]


def lane_v(xc, y0, y1):
    """Callejón vertical de 32 px (borde 8 + camino 16 + borde 8)."""
    return [(xc - 16, y0, xc + 16, y1, 1), (xc - 8, y0, xc + 8, y1, 2)]


# Casas: (nombre, x, y, variante, letrero). y es el centro del sprite (80x112 escalado a 1.4).
#   variante "A" = casa de la pradera (region 0,0), "B" = posada con chimenea (region 144,0).
# Las dos primeras ya existían en el mapa original.
HOUSES = [
    ("MeadowHouse", 265, 174, "A", "MEADOW HOUSE"),
    ("SunlitInn", 865, 174, "B", "SUNLIT INN"),
    ("Bakery", 1260, 174, "A", "BAKERY"),
    ("Smithy", 1800, 174, "B", "SMITHY"),
    ("Cottage", 2050, 174, "A", "COTTAGE"),
    ("Farmhouse", 330, 770, "B", "FARMHOUSE"),
    ("Carpenter", 800, 770, "A", "CARPENTER"),
    ("GeneralStore", 1260, 770, "B", "GENERAL STORE"),
    ("MillHouse", 1800, 770, "A", "MILL HOUSE"),
    ("LakeHouse", 2050, 770, "B", "LAKE HOUSE"),
]

# Callejones que unen las puertas con las calles: (x centro, y0, y1)
LANES = []
for _name, _x, _y, _v, _label in HOUSES:
    _xc = int(round(_x / 8.0)) * 8
    if _y < 400:
        LANES += lane_v(_xc, _y + 74, 336)       # casa al norte de la calle principal
    else:
        LANES += lane_v(_xc, _y + 68, 876)       # casa al norte de la calle sur
# Camino al campo este (con portón en la valla)
LANES += lane_v(1920, 424, 504)
ROAD_RECTS += LANES

# Cuerpos de agua: (centro x, centro y, radio x, radio y, irregularidad)
WATERS = [
    (934, 483, 50, 50, 0.0),     # estanque original
    (330, 1040, 56, 56, 0.05),   # estanque suroeste
    (1950, 1060, 150, 95, 0.05), # lago sureste
]

# Campos de cultivo (celdas): (col0, fila0, col1, fila1, filas con surco)
FIELDS = [
    (8, 28, 24, 35, (31, 33)),                 # huerto original de Mira
    (109, 31, 130, 38, (33, 35, 37)),          # campo este
    (75, 34, 84, 39, (36, 38)),                # huerta pequeña
]

# Parches de pasto decorativo (celdas de origen; la hoja mide 12x4 celdas)
DECOR_ORIGINS_ORIGINAL = [(2, 4), (54, 4), (3, 37), (53, 37)]
DECOR_ORIGINS_NEW = [(60, 3), (100, 6), (120, 3), (136, 24), (100, 47), (121, 60),
                     (74, 60), (45, 60), (8, 58), (20, 68), (110, 68), (136, 40),
                     (100, 24), (66, 40), (130, 50), (90, 68)]
DECOR_SHEET_CELLS = [(x, y) for y in range(4) for x in range(12) if (x, y) != (10, 1)]

GRASS = (114, 184, 92)
EDGE = (166, 120, 88)
PATH = (198, 154, 107)
PLAZA = (209, 166, 118)
RANK_COLOR = {0: GRASS, 1: EDGE, 2: PATH, 3: EDGE, 4: PLAZA}

# Agua (bloques de 4 px): 0 vacío, 1 arena, 2 borde oscuro, 3 agua
SAND = (214, 196, 148)
RIM = (57, 124, 134)
WATER = (76, 158, 175)
WATER_LIGHT = (124, 195, 192)
WATER_COLOR = {1: SAND, 2: RIM, 3: WATER}

SOIL = (121, 84, 62)
SOIL_DARK = (94, 64, 47)
SOIL_SPECK = (104, 72, 53)
FURROW = (154, 106, 74)
FURROW_SHADE = (100, 68, 50)
BORDER = (62, 113, 75)


def hash2(a: int, b: int) -> int:
    return ((a * 73856093) ^ (b * 19349663)) & 0xFFFF


# ---------------------------------------------------------------------------
# Suelo
# ---------------------------------------------------------------------------

def rank_at(px: int, py: int) -> int:
    rank = 0
    for x0, y0, x1, y1, r in ROAD_RECTS:
        if x0 <= px < x1 and y0 <= py < y1 and r > rank:
            rank = r
    return rank


def cell_quarters(cx: int, cy: int):
    out = []
    for qy in range(2):
        for qx in range(2):
            out.append(rank_at(cx * TILE + qx * QUARTER + QUARTER // 2,
                               cy * TILE + qy * QUARTER + QUARTER // 2))
    return tuple(out)


def draw_ground(quarters, variant: int) -> Image.Image:
    img = Image.new("RGBA", (TILE, TILE))
    px = img.load()
    for i, rank in enumerate(quarters):
        ox, oy = (i % 2) * QUARTER, (i // 2) * QUARTER
        for y in range(QUARTER):
            for x in range(QUARTER):
                px[ox + x, oy + y] = RANK_COLOR[rank] + (255,)
    if len(set(quarters)) == 1 and variant:
        rank = quarters[0]
        if rank == 0:
            dark, light = (98, 164, 78), (132, 202, 106)
            spots = {1: [(3, 4, dark), (10, 11, dark), (12, 3, light)],
                     2: [(5, 12, dark), (11, 6, light), (2, 9, light)]}[variant]
        elif rank == 2:
            spots = [(4, 5, (180, 138, 95)), (11, 9, (180, 138, 95)),
                     (8, 3, (221, 187, 139)), (3, 12, (221, 187, 139))]
        elif rank == 4:
            spots = [(5, 4, (190, 148, 104)), (12, 10, (190, 148, 104)),
                     (9, 12, (224, 184, 134)), (3, 9, (224, 184, 134))]
        else:
            spots = []
        for x, y, color in spots:
            px[x, y] = color + (255,)
    return img


def ground_variant(cx: int, cy: int, rank: int) -> int:
    h = hash2(cx, cy)
    if rank == 0:
        n = h % 20
        return 0 if n < 14 else (1 if n < 17 else 2)
    if rank in (2, 4):
        return 0 if h % 20 < 16 else 1
    return 0


# ---------------------------------------------------------------------------
# Agua
# ---------------------------------------------------------------------------

def water_material(px: float, py: float) -> int:
    best = 0
    for cx, cy, rx, ry, wobble in WATERS:
        dx, dy = (px - cx) / rx, (py - cy) / ry
        r = math.sqrt(dx * dx + dy * dy)
        if wobble:
            ang = math.atan2(dy, dx)
            r /= 1.0 + wobble * math.sin(3 * ang + cx) + wobble * 0.6 * math.sin(5 * ang + cy)
        dist = (r - 1.0) * math.sqrt(rx * ry)  # distancia aproximada a la orilla (px)
        if dist < -4:
            m = 3
        elif dist < 0:
            m = 2
        elif dist < 5:
            m = 1
        else:
            m = 0
        if m > best:
            best = m
    return best


def water_cell_blocks(cx: int, cy: int):
    out = []
    for by in range(4):
        for bx in range(4):
            out.append(water_material(cx * TILE + bx * BLOCK + BLOCK / 2.0,
                                      cy * TILE + by * BLOCK + BLOCK / 2.0))
    return tuple(out)


def draw_water(blocks, variant: int) -> Image.Image:
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    px = img.load()
    for i, m in enumerate(blocks):
        if m == 0:
            continue
        ox, oy = (i % 4) * BLOCK, (i // 4) * BLOCK
        for y in range(BLOCK):
            for x in range(BLOCK):
                px[ox + x, oy + y] = WATER_COLOR[m] + (255,)
    if variant and all(m == 3 for m in blocks):
        dashes = {1: [(2, 4), (3, 4), (4, 4), (10, 11), (11, 11)],
                  2: [(9, 3), (10, 3), (11, 3), (3, 12), (4, 12), (5, 12)],
                  3: [(6, 8), (7, 8), (8, 8), (9, 8), (12, 13), (13, 13)]}[variant]
        for x, y in dashes:
            px[x, y] = WATER_LIGHT + (255,)
    return img


def water_collision(blocks):
    """Cuartos de 8 px con al menos 2 bloques de agua: (qx, qy) con origen en la esquina del tile."""
    quarters = []
    for qy in range(2):
        for qx in range(2):
            wet = 0
            for by in range(2):
                for bx in range(2):
                    if blocks[(qy * 2 + by) * 4 + (qx * 2 + bx)] in (2, 3):
                        wet += 1
            if wet >= 2:
                quarters.append((qx, qy))
    return quarters


# ---------------------------------------------------------------------------
# Huerto y borde
# ---------------------------------------------------------------------------

def field_cells():
    cells = {}
    for c0, r0, c1, r1, furrows in FIELDS:
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                cells[(c, r)] = r in furrows
    return cells


def draw_soil(mask, furrow: bool, variant: int) -> Image.Image:
    n, s, e, w = mask
    img = Image.new("RGBA", (TILE, TILE), SOIL + (255,))
    px = img.load()
    if furrow:
        for x in range(TILE):
            px[x, 6] = FURROW + (255,)
            px[x, 7] = FURROW + (255,)
            px[x, 8] = FURROW_SHADE + (255,)
    elif variant:
        for x, y in {1: [(3, 3), (11, 5), (6, 12)], 2: [(13, 10), (4, 9), (9, 2)]}[variant]:
            px[x, y] = SOIL_SPECK + (255,)
    for i in range(TILE):
        if not n:
            px[i, 0] = SOIL_DARK + (255,)
        if not s:
            px[i, TILE - 1] = SOIL_DARK + (255,)
        if not w:
            px[0, i] = SOIL_DARK + (255,)
        if not e:
            px[TILE - 1, i] = SOIL_DARK + (255,)
    return img


def draw_border(sides) -> Image.Image:
    n, s, e, w = sides
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            if (n and y < QUARTER) or (s and y >= TILE - QUARTER) or \
               (w and x < QUARTER) or (e and x >= TILE - QUARTER):
                px[x, y] = BORDER + (255,)
    return img


# ---------------------------------------------------------------------------
# Salida
# ---------------------------------------------------------------------------

def code_for(index: int) -> str:
    return ALPHABET[index // len(ALPHABET)] + ALPHABET[index % len(ALPHABET)]


def decor_origin_is_valid(origin, fields, water_cells) -> bool:
    ox, oy = origin
    if ox < 0 or oy < 0 or ox + 12 > COLUMNS or oy + 4 > ROWS:
        return False
    for ty in range(4):
        for tx in range(12):
            cx, cy = ox + tx, oy + ty
            if any(rank > 0 for rank in cell_quarters(cx, cy)):
                return False
            if (cx, cy) in fields or (cx, cy) in water_cells:
                return False
    return True


def build():
    """Calcula todo y devuelve (order, layers, decor_origins)."""
    tiles = {}   # clave -> índice
    order = []   # (clave, función que dibuja, colisión)

    def index_of(key, image_fn, collision=None):
        if key not in tiles:
            tiles[key] = len(order)
            order.append((key, image_fn, collision))
        return tiles[key]

    layers = {"Ground": [], "Water": [], "Garden": [], "Border": []}
    fields = field_cells()
    water_cells = set()

    for cy in range(ROWS):
        ground_row, water_row, garden_row, border_row = [], [], [], []
        for cx in range(COLUMNS):
            q = cell_quarters(cx, cy)
            variant = ground_variant(cx, cy, q[0]) if len(set(q)) == 1 else 0
            i = index_of(("g", q, variant), lambda q=q, v=variant: draw_ground(q, v))
            ground_row.append(code_for(i))

            blocks = water_cell_blocks(cx, cy)
            if any(blocks):
                if all(m == 3 for m in blocks):
                    h = hash2(cx, cy) % 12
                    wv = 0 if h < 9 else h - 8
                else:
                    wv = 0
                coll = water_collision(blocks)
                i = index_of(("w", blocks, wv), lambda b=blocks, v=wv: draw_water(b, v), coll)
                water_row.append(code_for(i))
                if coll:
                    water_cells.add((cx, cy))
            else:
                water_row.append(EMPTY)

            if (cx, cy) in fields:
                mask = tuple((cx + dx, cy + dy) in fields for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)))
                furrow = fields[(cx, cy)]
                sv = 0 if furrow or hash2(cx, cy) % 10 < 6 else 1 + hash2(cy, cx) % 2
                i = index_of(("s", mask, furrow, sv), lambda m=mask, f=furrow, v=sv: draw_soil(m, f, v))
                garden_row.append(code_for(i))
            else:
                garden_row.append(EMPTY)

            sides = (cy == 0, cy == ROWS - 1, cx == COLUMNS - 1, cx == 0)
            if any(sides):
                i = index_of(("b", sides), lambda s=sides: draw_border(s))
                border_row.append(code_for(i))
            else:
                border_row.append(EMPTY)
        layers["Ground"].append("".join(ground_row))
        layers["Water"].append("".join(water_row))
        layers["Garden"].append("".join(garden_row))
        layers["Border"].append("".join(border_row))

    assert len(order) <= len(ALPHABET) ** 2, "Demasiados tiles únicos"

    decor_origins = [o for o in DECOR_ORIGINS_ORIGINAL + DECOR_ORIGINS_NEW
                     if o in DECOR_ORIGINS_ORIGINAL or decor_origin_is_valid(o, fields, water_cells)]
    return order, layers, decor_origins


def main() -> None:
    order, layers, decor_origins = build()

    rows_needed = (len(order) + ATLAS_COLUMNS - 1) // ATLAS_COLUMNS
    atlas = Image.new("RGBA", (ATLAS_COLUMNS * TILE, rows_needed * TILE), (0, 0, 0, 0))
    for index, (_key, image_fn, _coll) in enumerate(order):
        atlas.paste(image_fn(), ((index % ATLAS_COLUMNS) * TILE, (index // ATLAS_COLUMNS) * TILE))

    terrain_dir = os.path.join(ROOT, "terrain")
    os.makedirs(terrain_dir, exist_ok=True)
    atlas.save(os.path.join(terrain_dir, "ground_tiles.png"))

    # --- TileSet -----------------------------------------------------------
    tres = [
        '[gd_resource type="TileSet" format=3 uid="uid://bf8j2qya0gp4e"]',
        "",
        '[ext_resource type="Texture2D" uid="uid://bm48soxurb53j" path="res://terrain/ground_tiles.png" id="1_ground"]',
        '[ext_resource type="Texture2D" uid="uid://bqrhq4m0doi6k" path="res://asset_pack/Tileset/Tileset Grass Spring.png" id="2_grass"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_ground"]',
        'texture = ExtResource("1_ground")',
    ]
    for index, (_key, _fn, coll) in enumerate(order):
        ax, ay = index % ATLAS_COLUMNS, index // ATLAS_COLUMNS
        tres.append("%d:%d/0 = 0" % (ax, ay))
        if coll:
            for p, (qx, qy) in enumerate(coll):
                x0, y0 = qx * QUARTER - 8, qy * QUARTER - 8
                pts = "%d, %d, %d, %d, %d, %d, %d, %d" % (
                    x0, y0, x0 + QUARTER, y0, x0 + QUARTER, y0 + QUARTER, x0, y0 + QUARTER)
                tres.append("%d:%d/0/physics_layer_0/polygon_%d/points = PackedVector2Array(%s)" % (ax, ay, p, pts))
    tres += ["", '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_grass"]',
             'texture = ExtResource("2_grass")']
    for x, y in DECOR_SHEET_CELLS:
        tres.append("%d:%d/0 = 0" % (x, y))
    tres += ["", "[resource]",
             "physics_layer_0/collision_layer = 1",
             "physics_layer_0/collision_mask = 0",
             'sources/0 = SubResource("TileSetAtlasSource_ground")',
             'sources/1 = SubResource("TileSetAtlasSource_grass")', ""]
    with open(os.path.join(terrain_dir, "willowmere_tileset.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tres))

    # --- ground_map.gd -----------------------------------------------------
    lines = [
        "# Archivo generado por tools/generate_terrain.py. No lo edites a mano.",
        "# Es el diseño inicial del terreno: TerrainBuilder pinta cada capa con",
        "# este diseño solo cuando está vacía. Una vez que pintes y guardes la",
        "# escena, los tiles de la escena mandan y este archivo deja de usarse.",
        "extends RefCounted",
        "",
        "const COLUMNS := %d" % COLUMNS,
        "const ROWS_COUNT := %d" % ROWS,
        "const ATLAS_COLUMNS := %d" % ATLAS_COLUMNS,
        "const ATLAS_TILE_COUNT := %d" % len(order),
        'const ALPHABET := "%s"' % ALPHABET,
        '## Cada celda ocupa 2 caracteres; ".." es una celda vacía.',
        "const CODE_LENGTH := 2",
        "const DECOR_ORIGINS := [%s]" % ", ".join("Vector2i(%d, %d)" % o for o in decor_origins),
        "",
    ]
    for name in ("Ground", "Water", "Garden", "Border"):
        lines.append("const %s := [" % name.upper())
        for row in layers[name]:
            lines.append('\t"%s",' % row)
        lines.append("]")
        lines.append("")
    with open(os.path.join(terrain_dir, "ground_map.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    print("Tiles únicos:", len(order), "| atlas:", atlas.size, "| parches decor:", len(decor_origins))


if __name__ == "__main__":
    main()
