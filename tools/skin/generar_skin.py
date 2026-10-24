#!/usr/bin/env python3
"""Genera las texturas de la interfaz (botones y paneles pixel-art) a partir de la imagen de botones.

    python tools/skin/generar_skin.py --fuente botones.png --salida asset_pack/UI/skin

La imagen fuente debe tener (como la original) el botón "Start" normal arriba a la izquierda y el
mismo botón pulsado arriba a la derecha. El script:
  1. reduce cada botón a su resolución de píxel nativa (80 x 35),
  2. lo cuantiza a pocos colores y borra el texto,
  3. uniformiza el centro (para que se pueda estirar a cualquier tamaño sin deformar los remaches),
  4. genera variantes de color (hover, verde, rojo, deshabilitado, panel, hundido) y las amplía x2.
Los márgenes de corte (9-slice) se escriben en skin.json y los lee UiKit.
"""
import argparse
import colorsys
import json
import os
from collections import Counter

import numpy as np
from PIL import Image

SCALE = 2
# Cajas de los botones "Start" en la imagen fuente (x0, y0, x1, y1) y su tamaño nativo.
BOX_NORMAL = (240, 231, 890, 515)
BOX_PRESSED = (1109, 250, 1759, 515)
NATIVE_NORMAL = (80, 35)
NATIVE_PRESSED = (80, 33)
# Márgenes del 9-slice en píxeles nativos: (izquierda, arriba, derecha, abajo)
MARGINS_NORMAL = (13, 9, 13, 11)
MARGINS_PRESSED = (13, 9, 13, 8)
TEXT_BOX = (22, 5, 60, 25)  # zona donde estaba el texto "Start" (x0, y0, x1, y1), se borra


def to_native(img, box, size):
    x0, y0, x1, y1 = box
    w, h = size
    sx, sy = (x1 - x0 + 1) / w, (y1 - y0 + 1) / h
    src = img.load()
    out = Image.new("RGB", size)
    px = out.load()
    for j in range(h):
        for i in range(w):
            cx, cy = x0 + (i + 0.5) * sx, y0 + (j + 0.5) * sy
            block = np.array([src[int(cx + dx), int(cy + dy)] for dx in (-2, 0, 2) for dy in (-2, 0, 2)])
            px[i, j] = tuple(int(v) for v in np.median(block, axis=0))
    return out


def quantize(img, colors=14):
    q = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    rgb = np.array(q.convert("RGB"))
    alpha = np.where(rgb.min(axis=2) > 232, 0, 255).astype(np.uint8)  # el blanco del fondo = transparente
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


def mode_of(pixels):
    """Color (RGBA) más frecuente de una lista de píxeles."""
    return Counter(map(tuple, pixels)).most_common(1)[0][0]


def body_color(img):
    a = np.array(img)
    return mode_of(a[10:24, 14:66].reshape(-1, 4))


def erase_text(img, margins):
    a = np.array(img)
    x0, y0, x1, y1 = TEXT_BOX
    a[y0:y1, x0:x1] = body_color(img)
    return Image.fromarray(a, "RGBA")


def uniform_middle(img, margins):
    """Centro estirable: cada fila del centro usa su color más frecuente (sin muescas ni dibujos sueltos)."""
    a = np.array(img)
    h, w = a.shape[:2]
    ml, mt, mr, mb = margins
    out = a.copy()
    # franja central horizontal: una columna "típica" repetida
    for y in range(h):
        out[y, ml:w - mr] = mode_of(a[y, ml:w - mr])
    # laterales: una fila "típica" repetida hacia abajo
    for x in list(range(ml)) + list(range(w - mr, w)):
        out[mt:h - mb, x] = mode_of(a[mt:h - mb, x])
    # el centro entero, con el color del cuerpo
    out[mt:h - mb, ml:w - mr] = mode_of(a[mt:h - mb, ml:w - mr].reshape(-1, 4))
    return Image.fromarray(out, "RGBA")


def recolor(img, hue=None, sat_mul=1.0, val_mul=1.0, sat_add=0.0):
    """Cambia el matiz de los colores claros (el contorno oscuro y la transparencia no se tocan)."""
    a = np.array(img)
    out = a.copy()
    for color in {tuple(c) for c in a.reshape(-1, 4)}:
        if color[3] == 0:
            continue
        r, g, b = [v / 255 for v in color[:3]]
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if v < 0.4:  # contorno oscuro
            continue
        if hue is not None:
            h = hue
        s = min(1.0, max(0.0, s * sat_mul + sat_add))
        v = min(1.0, v * val_mul)
        nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
        mask = np.all(a == np.array(color), axis=2)
        out[mask] = (int(nr * 255), int(ng * 255), int(nb * 255), color[3])
    return Image.fromarray(out, "RGBA")


def fill_notches(img):
    """Rellena los huecos transparentes de una sola muesca en los bordes (botón sin 'mordiscos')."""
    a = np.array(img)
    h, w = a.shape[:2]
    for y in range(h):
        for x in range(1, w - 1):
            if a[y, x, 3] == 0 and a[y, x - 1, 3] > 0 and a[y, x + 1, 3] > 0:
                a[y, x] = a[y, x - 1]
    return Image.fromarray(a, "RGBA")


def fix_border(img):
    """Contorno exterior completo en color oscuro y las 4 esquinas transparentes (borde limpio)."""
    a = np.array(img)
    h, w = a.shape[:2]
    dark = [tuple(c) for c in a.reshape(-1, 4) if c[3] > 0 and max(c[:3]) < 100]
    outline = Counter(dark).most_common(1)[0][0]
    a[0, :] = outline
    a[h - 1, :] = outline
    a[:, 0] = outline
    a[:, w - 1] = outline
    for y, x in ((0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)):
        a[y, x] = (0, 0, 0, 0)
    return Image.fromarray(a, "RGBA")


def up(img):
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fuente", required=True)
    parser.add_argument("--salida", default="asset_pack/UI/skin")
    args = parser.parse_args()
    os.makedirs(args.salida, exist_ok=True)
    src = Image.open(args.fuente).convert("RGB")

    normal = fix_border(fill_notches(uniform_middle(erase_text(quantize(to_native(src, BOX_NORMAL, NATIVE_NORMAL)), MARGINS_NORMAL), MARGINS_NORMAL)))
    pressed = fix_border(fill_notches(uniform_middle(erase_text(quantize(to_native(src, BOX_PRESSED, NATIVE_PRESSED)), MARGINS_PRESSED), MARGINS_PRESSED)))

    # matices (0..1): tan ~0.08, salmón ~0.04, verde ~0.30, rojo ~0.0
    variants = {
        "btn_normal": normal,
        "btn_hover": recolor(normal, hue=0.045, sat_mul=1.05, val_mul=0.98),
        "btn_pressed": pressed,
        "btn_disabled": recolor(normal, sat_mul=0.25, val_mul=0.92),
        "btn_primary": recolor(normal, hue=0.27, sat_mul=0.95, val_mul=0.93),
        "btn_primary_hover": recolor(normal, hue=0.24, sat_mul=1.0, val_mul=1.0),
        "btn_primary_pressed": recolor(pressed, hue=0.27, sat_mul=1.0, val_mul=0.88),
        "btn_danger": recolor(normal, hue=0.01, sat_mul=1.1, val_mul=0.97),
        "btn_danger_hover": recolor(normal, hue=0.0, sat_mul=1.25, val_mul=1.0),
        "btn_danger_pressed": recolor(pressed, hue=0.0, sat_mul=1.2, val_mul=0.9),
        "panel": recolor(normal, hue=0.095, sat_mul=0.62, val_mul=1.04),
        "inset": recolor(pressed, hue=0.085, sat_mul=0.95, val_mul=0.97),
    }
    for name, image in variants.items():
        up(image).save(os.path.join(args.salida, name + ".png"))

    ml, mt, mr, mb = MARGINS_NORMAL
    pl, pt, pr, pb = MARGINS_PRESSED
    meta = {
        "escala": SCALE,
        "normal": {"izq": ml * SCALE, "arr": mt * SCALE, "der": mr * SCALE, "abj": mb * SCALE, "alto": NATIVE_NORMAL[1] * SCALE},
        "pressed": {"izq": pl * SCALE, "arr": pt * SCALE, "der": pr * SCALE, "abj": pb * SCALE, "alto": NATIVE_PRESSED[1] * SCALE},
    }
    with open(os.path.join(args.salida, "skin.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("Texturas escritas en", args.salida, meta)


if __name__ == "__main__":
    main()
