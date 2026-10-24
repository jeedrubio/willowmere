#!/usr/bin/env python3
"""Genera sesiones y telemetría FICTICIAS para probar el panel de estadísticas.

    python tools/generar_datos_demo.py                 # crea willowmere_demo.db con 70 sesiones
    python tools/servidor_sqlite.py --db willowmere_demo.db

Nunca toca willowmere_data.db a menos que lo fuerces con --forzar (no lo hagas: mezclaría
datos inventados con los reales).
"""
import argparse
import math
import os
import random
import re
import sqlite3
import sys
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import servidor_sqlite as srv  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYERS = ["Benigno", "Lucía", "Marcos", "Aurora", "Fabián", "Renata", "Santiago", "Valentina", "Camila", "Diego", "Ximena", "Mateo"]
NPCS = ["Mira", "Elsie", "Orin", "Tomas", "Bram", "Juno"]
HOUSES = ["Casa del Prado", "Posada del Sol", "Panadería", "Herrería", "Cabaña", "Granja", "Carpintería", "Tienda General", "Molino", "Casa del Lago"]
CROPS = ["strawberry", "leek", "potato", "onion"]
AI_ERRORS = ["Error 429: se superó la cuota de la API.", "El aldeano no tuvo respuesta esta vez. Inténtalo de nuevo.",
             "La respuesta del aldeano fue ilegible. Inténtalo de nuevo.", "No se pudo iniciar la conexión. Revisa tu clave e inténtalo de nuevo."]
# Zonas del pueblo (en píxeles del mundo, ver tools/dashboard/mapa_pueblo.png x2): (x, y, radio, peso)
HOTSPOTS = [
    (578, 368, 90, 4), (1524, 366, 80, 4),      # plazas
    (266, 500, 120, 5), (1920, 560, 160, 4), (1282, 580, 70, 2),   # huertos
    (580, 700, 60, 2), (1000, 370, 400, 3), (1520, 850, 70, 2),    # caminos
    (320, 240, 40, 1), (860, 240, 40, 1), (1260, 240, 40, 1), (1800, 240, 40, 1), (2050, 240, 40, 1),
    (330, 800, 40, 1), (800, 800, 40, 1), (1260, 800, 40, 1), (1800, 800, 40, 1), (2050, 800, 40, 1),
]
CROP_AREAS = [(266, 500, 130, 60), (1920, 560, 170, 70), (1282, 580, 70, 45)]


def quest_titles():
    text = open(os.path.join(ROOT, "scripts", "systems", "quest_log.gd"), encoding="utf-8").read()
    pairs = re.findall(r'"id": "(\w+)".*?"title": "([^"]+)"', text, flags=re.S)
    return pairs or [("mira_garden", "El encargo del jardín de Mira")]


def pick_hotspot(rng):
    return rng.choices(HOTSPOTS, weights=[h[3] for h in HOTSPOTS])[0]


def make_session(rng, conn, start, player, quests, live=False):
    sid = "%d-%06x" % (int(start), rng.randrange(0xFFFFFF))
    version = rng.choices(["0.3.0", "0.4.0"], weights=[2, 3])[0]
    os_name = rng.choices(["Windows", "Linux", "macOS"], weights=[6, 2, 2])[0]
    has_key = rng.random() < 0.45
    rows = []
    t = start
    place = srv.OUTDOOR_PLACE
    fps_bad = rng.random() < 0.12

    def ev(cat, e, obj="", det="", val=0.0, x=None, y=None, at=None, where=None):
        rows.append((sid, player, at if at is not None else t, cat, e, obj, det, val, where or place, x, y))

    ev("sesion", "inicio")
    plays = rng.random() < 0.88
    active = 0.0
    last_seen = start + rng.uniform(5, 60)
    if plays:
        to_play = max(2.0, rng.lognormvariate(2.3, 0.7))
        t = start + to_play
        ev("menu", "jugar", rng.choice(["nueva", "nueva", "continuar", "cargar"]), "", to_play)
        ev("lugar", "entrada", srv.OUTDOOR_PLACE)
        target_active = min(3600, max(40, rng.lognormvariate(6.9, 0.75)))
        px, py, _, _ = pick_hotspot(rng)
        goal = pick_hotspot(rng)
        gx, gy = goal[0] + rng.uniform(-goal[2], goal[2]), goal[1] + rng.uniform(-goal[2] * 0.5, goal[2] * 0.5)
        dwell = 0
        indoors_left = 0
        place_since = 0.0
        # lo que hará esta sesión (cada paso con su probabilidad, en orden)
        plan = []
        if rng.random() < 0.80: plan.append("cosecha")
        if rng.random() < 0.85: plan.append("hablar")
        if "hablar" in plan and rng.random() < 0.72: plan.append("encargo")
        if "hablar" in plan and rng.random() < 0.55: plan.append("ia")
        if rng.random() < 0.60: plan.append("casa")
        if "encargo" in plan and rng.random() < 0.45: plan.append("completar")
        for extra in rng.sample(["pausa", "ajustes", "controles", "inventario", "marcador", "guardado"], rng.randint(0, 3)):
            plan.append(extra)
        schedule = sorted(rng.uniform(0.05, 0.95) * target_active for _ in plan)
        rng.shuffle(plan)
        schedule_iter = list(zip(schedule, plan))
        accepted = {}
        steps = int(target_active / 2)
        for step in range(steps):
            t = start + to_play + step * 2.0
            active += 2.0
            if indoors_left > 0:
                indoors_left -= 2
                ev("movimiento", "pos", "", "", 2.0, 3200 + rng.uniform(40, 360), 160 + rng.uniform(20, 260))
                if indoors_left <= 0:
                    ev("lugar", "salida", place, "", active - place_since)
                    place = srv.OUTDOOR_PLACE
                    place_since = active
                    ev("lugar", "entrada", place)
            else:
                if dwell > 0:
                    dwell -= 2
                else:
                    dx, dy = gx - px, gy - py
                    dist = math.hypot(dx, dy)
                    if dist < 40:
                        dwell = rng.randint(6, 50)
                        goal = pick_hotspot(rng)
                        gx, gy = goal[0] + rng.uniform(-goal[2], goal[2]), goal[1] + rng.uniform(-goal[2] * 0.5, goal[2] * 0.5)
                    else:
                        move = min(dist, 250)
                        px += dx / dist * move + rng.uniform(-8, 8)
                        py += dy / dist * move + rng.uniform(-8, 8)
                px = min(max(px, 20), srv.WORLD_W - 20)
                py = min(max(py, 20), srv.WORLD_H - 20)
                ev("movimiento", "pos", "", "", 2.0, round(px, 1), round(py, 1))
            if step % 3 == 0:
                base = rng.gauss(30 if fps_bad else 59, 6 if fps_bad else 2.5)
                if place != srv.OUTDOOR_PLACE:
                    base += 3
                ev("rendimiento", "fps", "", "", max(8, min(base, 144)))
            while schedule_iter and schedule_iter[0][0] <= step * 2.0:
                _, action = schedule_iter.pop(0)
                if action == "cosecha":
                    area = rng.choice(CROP_AREAS)
                    for _ in range(rng.randint(2, 14)):
                        crop = rng.choice(CROPS)
                        ev("juego", "cosecha", crop, "", 1.0, round(area[0] + rng.uniform(-area[2], area[2]), 1), round(area[1] + rng.uniform(-area[3], area[3]), 1))
                        ev("economia", "cosecha", crop, "", 5)
                        if rng.random() < 0.14:
                            ev("feel", "input_buffer", "interact", "", rng.uniform(50, 190))
                        elif rng.random() < 0.07:
                            ev("feel", "coyote", "interact")
                elif action == "hablar":
                    npc = rng.choice(NPCS)
                    ev("juego", "hablar", npc, "", 0, round(px, 1), round(py, 1))
                    ev("ia", "charla_inicio", npc)
                    ev("ia", "charla_fin", npc, "", rng.uniform(8, 160), at=t + 30)
                elif action == "encargo":
                    qid, title = rng.choice(quests)
                    accepted[qid] = active
                    ev("juego", "encargo_aceptado", qid, title)
                    ev("economia", "mision_aceptada", title, "", 10)
                elif action == "ia":
                    npc = rng.choice(NPCS)
                    for _ in range(rng.randint(1, 6)):
                        if not has_key:
                            ev("ia", "sin_clave", npc)
                            break
                        ev("ia", "mensaje_enviado", npc)
                        if rng.random() < 0.07:
                            ev("ia", "error", npc, rng.choice(AI_ERRORS), rng.uniform(800, 9000))
                        else:
                            ev("ia", "respuesta", npc, "", min(rng.lognormvariate(7.8, 0.45), 14000))
                elif action == "casa" and place == srv.OUTDOOR_PLACE:
                    house = rng.choice(HOUSES)
                    ev("juego", "entrar_casa", house)
                    ev("lugar", "salida", place, "", active - place_since)
                    place, place_since, indoors_left = house, active, rng.randint(20, 90)
                    ev("lugar", "entrada", place)
                elif action == "completar" and accepted:
                    qid = rng.choice(list(accepted))
                    title = dict(quests).get(qid, qid)
                    ev("juego", "encargo_completado", qid, title, active - accepted.pop(qid))
                    ev("economia", "encargo", title, "", 50)
                    ev("economia", "recompensa", "Monedas obtenidas", "", rng.choice([25, 40, 60]))
                elif action in srv.MENU_LABELS:
                    ev("menu", action)
                    if action == "guardado" and rng.random() < 0.8:
                        ev("partida", "guardar", "ranura %d" % rng.randint(1, 3))
                elif action in ("pausa", "ajustes", "controles", "inventario", "marcador", "guardado"):
                    ev("menu", action)
            last_seen = t
        if indoors_left > 0 or place != srv.OUTDOOR_PLACE:
            ev("lugar", "salida", place, "", active - place_since, at=t)
        else:
            ev("lugar", "salida", place, "", active - place_since, at=t)
    ended = not live
    if ended:
        ev("sesion", "fin", "", "", last_seen - start, at=last_seen)
    else:
        last_seen = time.time()
    conn.execute("INSERT INTO sesiones (id, jugador, inicio, ultimo_visto, fin, version, os, api_key, tiempo_activo) VALUES (?,?,?,?,?,?,?,?,?)",
                 (sid, player, start, last_seen, 1 if ended else 0, version, os_name, 1 if has_key else 0, active))
    conn.executemany("INSERT INTO telemetria (sesion_id, jugador, ts, cat, ev, objetivo, detalle, valor, lugar, x, y) VALUES (?,?,?,?,?,?,?,?,?,?,?)", rows)
    return len(rows)


def seed_players(rng, conn):
    now = datetime.now()
    types = [("Coleccionable", "Obtuvo Fresa", 1), ("Misión Completada", "Completó: El encargo del jardín de Mira", 50),
             ("Monedas", "Monedas obtenidas", 25), ("Inicio de sesión", "Entró a Willowmere", 0), ("Cosecha", "Cosechó Puerro", 5)]
    for name in PLAYERS:
        items, quests_done, coins, seconds = rng.randint(4, 45), rng.randint(0, 8), rng.randint(60, 900), rng.randint(300, 5400)
        score = items * 50 + coins * 10 + quests_done * 150 + seconds * 2
        last = now.timestamp() - rng.choice([20, 600, 4000, 30000, 200000, 900000])
        conn.execute("INSERT OR REPLACE INTO jugadores VALUES (?,?,?,?,?,?,?)", (name, score, coins, items, quests_done, seconds,
                     datetime.fromtimestamp(last).strftime("%Y-%m-%d %H:%M:%S")))
    for i in range(60):
        kind = rng.choice(types)
        when = datetime.fromtimestamp(now.timestamp() - i * rng.uniform(300, 9000))
        conn.execute("INSERT INTO historial_eventos (jugador, tipo_evento, detalle, valor, fecha_hora) VALUES (?,?,?,?,?)",
                     (rng.choice(PLAYERS), kind[0], kind[1], kind[2], when.strftime("%Y-%m-%d %H:%M:%S")))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", default="willowmere_demo.db")
    parser.add_argument("--sesiones", type=int, default=70)
    parser.add_argument("--semilla", type=int, default=7)
    parser.add_argument("--forzar", action="store_true", help="permite escribir en willowmere_data.db (no recomendado)")
    args = parser.parse_args()
    if os.path.basename(args.db) == "willowmere_data.db" and not args.forzar:
        sys.exit("Rechazado: eso mezclaría datos inventados con tus datos reales. Usa otra base (--db willowmere_demo.db).")
    srv.DB_PATH = args.db
    srv.init_db()
    rng = random.Random(args.semilla)
    quests = quest_titles()
    conn = sqlite3.connect(args.db)
    now = time.time()
    total = 0
    for i in range(args.sesiones):
        days_ago = min(29.5, rng.expovariate(1 / 9.0))
        day_start = now - days_ago * 86400
        hour = rng.choices(range(24), weights=[1, 1, 0, 0, 0, 1, 2, 3, 3, 3, 4, 4, 5, 6, 6, 6, 7, 8, 10, 11, 10, 8, 4, 2])[0]
        d = datetime.fromtimestamp(day_start).replace(hour=hour, minute=rng.randint(0, 59), second=rng.randint(0, 59))
        start = min(d.timestamp(), now - 3600)
        total += make_session(rng, conn, start, rng.choice(PLAYERS), quests)
    for _ in range(2):  # dos sesiones "en curso" ahora mismo
        total += make_session(rng, conn, now - rng.uniform(120, 600), rng.choice(PLAYERS), quests, live=True)
    seed_players(rng, conn)
    conn.commit()
    conn.close()
    print("Listo: %d sesiones y %d eventos en %s" % (args.sesiones + 2, total, os.path.abspath(args.db)))


if __name__ == "__main__":
    main()
