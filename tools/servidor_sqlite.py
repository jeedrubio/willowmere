#!/usr/bin/env python3
"""Servidor local de Willowmere: base de datos SQLite + panel web de estadísticas.

Uso (desde la carpeta del proyecto):
    python tools/servidor_sqlite.py                 # usa willowmere_data.db y el puerto 8080
    python tools/servidor_sqlite.py --db otra.db --port 9000

El panel está en http://localhost:8080  (pestañas "Jugadores" y "Analítica").

Qué guarda (la base se crea y se actualiza sola; tus datos anteriores se conservan):
    jugadores         marcador acumulado de cada jugador            (POST /api/sync)
    historial_eventos bitácora de acciones del marcador             (POST /api/sync)
    sesiones          una fila por cada vez que se abre el juego    (POST /api/telemetry)
    telemetria        eventos de uso: posición, FPS, menús, IA...   (POST /api/telemetry)

Solo usa la biblioteca estándar de Python (sin instalar nada).
"""
import argparse
import csv
import io
import json
import math
import os
import sqlite3
import statistics
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DASH_DIR = os.path.join(BASE_DIR, "dashboard")

DB_PATH = "willowmere_data.db"
PORT = 8080

# Mundo exterior del juego (en píxeles) y tamaño de celda del mapa de calor.
WORLD_W, WORLD_H = 2272, 1216
CELL = 32
OUTDOOR_PLACE = "Plaza Central"
# Una sesión sin señales durante este tiempo se considera terminada.
SESSION_TIMEOUT = 45
MAX_EVENTS_PER_POST = 5000
MAX_BODY = 5 * 1024 * 1024

PERIODS = {"24h": 24 * 3600, "7d": 7 * 24 * 3600, "30d": 30 * 24 * 3600, "all": None}

# Muestras automáticas: no cuentan como "acciones" del jugador.
SAMPLE_EVENTS = {("movimiento", "pos"), ("rendimiento", "fps")}
# Eventos que ocurren solos (no son una decisión del jugador): no sirven como "última acción".
NOT_ACTIONS = SAMPLE_EVENTS | {("sesion", "fin"), ("lugar", "salida"), ("lugar", "entrada"),
                               ("ia", "charla_fin"), ("ia", "respuesta"),
                               ("sesion", "telemetria_activada"), ("sesion", "telemetria_desactivada")}

EVENT_LABELS = {
    ("sesion", "inicio"): "Abrió el juego",
    ("sesion", "fin"): "Cerró el juego",
    ("menu", "jugar"): "Pulsó «Jugar»",
    ("juego", "cosecha"): "Cosechó",
    ("juego", "hablar"): "Habló con un aldeano",
    ("juego", "encargo_aceptado"): "Aceptó un encargo",
    ("juego", "encargo_completado"): "Completó un encargo",
    ("juego", "entrar_casa"): "Entró a una casa",
    ("ia", "mensaje_enviado"): "Escribió a la IA",
    ("ia", "sin_clave"): "Intentó charlar sin clave",
    ("ia", "respuesta"): "Respuesta de la IA",
    ("ia", "error"): "Error de la IA",
    ("ia", "charla_inicio"): "Empezó una charla",
    ("ia", "charla_fin"): "Terminó una charla",
    ("menu", "pausa"): "Abrió la pausa",
    ("menu", "ajustes"): "Abrió Ajustes",
    ("menu", "controles"): "Abrió Controles",
    ("menu", "inventario"): "Abrió la mochila",
    ("menu", "marcador"): "Abrió el marcador",
    ("menu", "guardado"): "Abrió Guardar partida",
    ("menu", "carga"): "Abrió Cargar partida",
    ("partida", "guardar"): "Guardó la partida",
    ("partida", "cargar"): "Cargó una partida",
    ("lugar", "entrada"): "Entró a un lugar",
    ("lugar", "salida"): "Salió de un lugar",
    ("movimiento", "pos"): "Muestra de posición",
    ("rendimiento", "fps"): "Muestra de FPS",
    ("feel", "input_buffer"): "Acción salvada por el input buffer",
    ("feel", "coyote"): "Interacción salvada por coyote time",
    ("sesion", "telemetria_activada"): "Activó la telemetría",
    ("sesion", "telemetria_desactivada"): "Desactivó la telemetría",
}
COIN_LABELS = {
    "coleccionable": "Coleccionables",
    "encargo": "Encargos completados",
    "recompensa": "Recompensas de encargos",
    "cosecha": "Cosechas",
    "mision_aceptada": "Encargos aceptados",
}
CROP_NAMES = {"strawberry": "Fresa", "leek": "Puerro", "potato": "Papa", "onion": "Cebolla"}
MENU_LABELS = {
    "pausa": "Menú de pausa", "ajustes": "Ajustes", "controles": "Controles", "inventario": "Mochila",
    "marcador": "Marcador", "guardado": "Guardar partida", "carga": "Cargar partida",
}
FUNNEL = [
    ("Abrió el juego", lambda c, e: (c, e) == ("sesion", "inicio")),
    ("Pulsó «Jugar»", lambda c, e: (c, e) == ("menu", "jugar")),
    ("Cosechó", lambda c, e: (c, e) == ("juego", "cosecha")),
    ("Habló con un aldeano", lambda c, e: (c, e) == ("juego", "hablar")),
    ("Aceptó un encargo", lambda c, e: (c, e) == ("juego", "encargo_aceptado")),
    ("Escribió a la IA", lambda c, e: c == "ia" and e in ("mensaje_enviado", "sin_clave")),
    ("Entró a una casa", lambda c, e: (c, e) == ("juego", "entrar_casa")),
    ("Completó un encargo", lambda c, e: (c, e) == ("juego", "encargo_completado")),
]


# ----------------------------------------------------------------------------
# Base de datos
# ----------------------------------------------------------------------------

def connect():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    cur = conn.cursor()
    # Marcador y bitácora (ya existían: no se tocan sus datos)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS jugadores (
            jugador TEXT PRIMARY KEY,
            score INTEGER DEFAULT 0,
            monedas INTEGER DEFAULT 0,
            coleccionables INTEGER DEFAULT 0,
            misiones INTEGER DEFAULT 0,
            tiempo_segundos INTEGER DEFAULT 0,
            ultima_actualizacion TEXT
        )""")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS historial_eventos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jugador TEXT,
            tipo_evento TEXT,
            detalle TEXT,
            valor INTEGER DEFAULT 0,
            fecha_hora TEXT
        )""")
    # Telemetría de uso
    cur.execute("""
        CREATE TABLE IF NOT EXISTS sesiones (
            id TEXT PRIMARY KEY,
            jugador TEXT,
            inicio REAL,
            ultimo_visto REAL,
            fin INTEGER DEFAULT 0,
            version TEXT,
            os TEXT,
            api_key INTEGER DEFAULT 0,
            tiempo_activo REAL DEFAULT 0
        )""")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS telemetria (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sesion_id TEXT,
            jugador TEXT,
            ts REAL,
            cat TEXT,
            ev TEXT,
            objetivo TEXT,
            detalle TEXT,
            valor REAL,
            lugar TEXT,
            x REAL,
            y REAL
        )""")
    for statement in (
        "CREATE INDEX IF NOT EXISTS idx_tel_ts ON telemetria(ts)",
        "CREATE INDEX IF NOT EXISTS idx_tel_sesion ON telemetria(sesion_id)",
        "CREATE INDEX IF NOT EXISTS idx_tel_evento ON telemetria(cat, ev)",
        "CREATE INDEX IF NOT EXISTS idx_ses_inicio ON sesiones(inicio)",
        "CREATE INDEX IF NOT EXISTS idx_hist_fecha ON historial_eventos(fecha_hora)",
        "CREATE INDEX IF NOT EXISTS idx_hist_jugador ON historial_eventos(jugador)",
    ):
        cur.execute(statement)
    conn.commit()
    conn.close()


# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------

def since_ts(period):
    seconds = PERIODS.get(period, None)
    return 0.0 if seconds is None else time.time() - seconds


def fmt_ts(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    k = (len(ordered) - 1) * p / 100.0
    lo = int(math.floor(k))
    hi = min(lo + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def mean(values):
    return sum(values) / len(values) if values else None


def label_of(cat, ev):
    if cat == "economia":
        return "Monedas: " + COIN_LABELS.get(ev, ev)
    return EVENT_LABELS.get((cat, ev), "%s / %s" % (cat, ev))


def to_float(value, default=0.0):
    try:
        number = float(value)
        return number if math.isfinite(number) else default
    except (TypeError, ValueError):
        return default


def clip(text, limit):
    return str(text if text is not None else "")[:limit]


# ----------------------------------------------------------------------------
# Jugadores (marcador) -> pestaña "Jugadores"
# ----------------------------------------------------------------------------

def players_data(period, player):
    since_text = fmt_ts(since_ts(period)) if PERIODS.get(period) else "0000-00-00 00:00:00"
    conn = connect()
    where, params = ["ultima_actualizacion >= ?"], [since_text]
    if player:
        where.append("jugador = ?")
        params.append(player)
    rows = [dict(r) for r in conn.execute(
        "SELECT * FROM jugadores WHERE %s ORDER BY score DESC LIMIT 50" % " AND ".join(where), params)]
    now = time.time()
    for row in rows:
        try:
            last = datetime.strptime(row["ultima_actualizacion"], "%Y-%m-%d %H:%M:%S").timestamp()
            row["hace_seg"] = max(0, int(now - last))
        except (TypeError, ValueError):
            row["hace_seg"] = None

    ev_where, ev_params = ["fecha_hora >= ?"], [since_text]
    if player:
        ev_where.append("jugador = ?")
        ev_params.append(player)
    events = [dict(r) for r in conn.execute(
        "SELECT * FROM historial_eventos WHERE %s ORDER BY id DESC LIMIT 40" % " AND ".join(ev_where), ev_params)]
    names = sorted({r[0] for r in conn.execute("SELECT jugador FROM jugadores")} |
                   {r[0] for r in conn.execute("SELECT DISTINCT jugador FROM sesiones")})
    conn.close()

    best = max(rows, key=lambda r: r["score"]) if rows else None
    summary = {
        "jugadores": len(rows),
        "mejor_score": best["score"] if best else 0,
        "mejor_jugador": best["jugador"] if best else None,
        "tiempo_total": sum(r["tiempo_segundos"] for r in rows),
        "items": sum(r["coleccionables"] for r in rows),
        "misiones": sum(r["misiones"] for r in rows),
        "monedas": sum(r["monedas"] for r in rows),
    }
    return {"leaderboard": rows, "eventos": events, "resumen": summary,
            "nombres": [n for n in names if n], "ahora": now}


# ----------------------------------------------------------------------------
# Analítica de desarrollo -> pestaña "Analítica"
# ----------------------------------------------------------------------------

def analytics(period, player):
    now = time.time()
    since = since_ts(period)
    conn = connect()

    s_where, s_params = ["inicio >= ?"], [since]
    if player:
        s_where.append("jugador = ?")
        s_params.append(player)
    sessions = [dict(r) for r in conn.execute(
        "SELECT * FROM sesiones WHERE %s ORDER BY inicio DESC" % " AND ".join(s_where), s_params)]

    e_where, e_params = ["ts >= ?"], [since]
    if player:
        e_where.append("jugador = ?")
        e_params.append(player)
    events = [dict(r) for r in conn.execute(
        "SELECT * FROM telemetria WHERE %s ORDER BY ts, id" % " AND ".join(e_where), e_params)]
    conn.close()

    ids = set()
    for s in sessions:
        ids.add(s["id"])
        s["duracion"] = max(0.0, (s["ultimo_visto"] or s["inicio"]) - s["inicio"])
        s["en_curso"] = (not s["fin"]) and (now - (s["ultimo_visto"] or 0)) < SESSION_TIMEOUT
    live = sum(1 for s in sessions if s["en_curso"])
    n_sessions = len(sessions)

    by_session = defaultdict(list)
    for e in events:
        if e["sesion_id"] in ids:
            by_session[e["sesion_id"]].append(e)
    scoped = [e for sid in by_session for e in by_session[sid]]
    real_events = [e for e in scoped if (e["cat"], e["ev"]) not in SAMPLE_EVENTS]

    # --- Indicadores clave
    durations = [s["duracion"] for s in sessions if s["duracion"] > 0]
    actives = [s["tiempo_activo"] for s in sessions if s["tiempo_activo"] is not None]
    played = [e for e in scoped if (e["cat"], e["ev"]) == ("menu", "jugar")]
    played_sessions = {e["sesion_id"] for e in played}
    time_to_play = [e["valor"] for e in played if e["valor"] is not None and e["valor"] >= 0]
    fps_values = [e["valor"] for e in scoped if (e["cat"], e["ev"]) == ("rendimiento", "fps") and e["valor"] and e["valor"] > 0]
    latencies = [e["valor"] for e in scoped if (e["cat"], e["ev"]) == ("ia", "respuesta") and e["valor"] is not None]
    ai_errors = [e for e in scoped if (e["cat"], e["ev"]) == ("ia", "error")]
    no_key_attempts = sum(1 for e in scoped if (e["cat"], e["ev"]) == ("ia", "sin_clave"))
    with_key = sum(1 for s in sessions if s["api_key"])
    per_player = Counter(s["jugador"] for s in sessions)
    days_by_player = defaultdict(set)
    for s in sessions:
        days_by_player[s["jugador"]].add(datetime.fromtimestamp(s["inicio"]).date())
    returning = sum(1 for p, days in days_by_player.items() if len(days) >= 2)

    kpis = {
        "sesiones": n_sessions,
        "en_curso": live,
        "jugadores_unicos": len(per_player),
        "duracion_media": mean(durations),
        "duracion_mediana": statistics.median(durations) if durations else None,
        "activo_medio": mean(actives),
        "pct_jugar": (100.0 * len(played_sessions) / n_sessions) if n_sessions else None,
        "tiempo_hasta_jugar": mean(time_to_play),
        "eventos_por_sesion": (len(real_events) / n_sessions) if n_sessions else None,
        "eventos_total": len(real_events),
        "fps_medio": mean(fps_values),
        "fps_p5": percentile(fps_values, 5),
        "ia_latencia_media": mean(latencies),
        "ia_latencia_p95": percentile(latencies, 95),
        "ia_pct_errores": (100.0 * len(ai_errors) / (len(ai_errors) + len(latencies))) if (ai_errors or latencies) else None,
        "pct_con_clave": (100.0 * with_key / n_sessions) if n_sessions else None,
        "intentos_sin_clave": no_key_attempts,
        "jugadores_recurrentes": returning,
    }

    # --- Embudo de progreso
    funnel = []
    previous = None
    for name, test in FUNNEL:
        reached = sum(1 for sid in ids if any(test(e["cat"], e["ev"]) for e in by_session.get(sid, ())))
        if name == "Abrió el juego":
            reached = n_sessions  # toda sesión abrió el juego
        lost = max(0, previous - reached) if previous is not None else 0
        funnel.append({"paso": name, "sesiones": reached,
                       "pct": (100.0 * reached / n_sessions) if n_sessions else 0.0,
                       "perdidas": lost,
                       "pct_perdido": (100.0 * lost / previous) if previous else 0.0})
        previous = reached

    # --- Sesiones por día y hora del día
    days = []
    if period == "all":
        first = min((datetime.fromtimestamp(s["inicio"]).date() for s in sessions), default=datetime.now().date())
        span = min(60, (datetime.now().date() - first).days + 1)
    else:
        span = {"24h": 2, "7d": 7, "30d": 30}.get(period, 7)
    today = datetime.now().date()
    per_day = {(today - timedelta(days=i)): [0, 0.0] for i in range(span - 1, -1, -1)}
    hours = [0] * 24
    for s in sessions:
        d = datetime.fromtimestamp(s["inicio"])
        hours[d.hour] += 1
        if d.date() in per_day:
            per_day[d.date()][0] += 1
            per_day[d.date()][1] += (s["tiempo_activo"] or 0) / 60.0
    for d, (count, minutes) in per_day.items():
        days.append({"dia": d.isoformat(), "sesiones": count, "minutos": round(minutes, 1)})

    # --- Dónde abandonan (última acción de cada sesión ya terminada)
    last_action = Counter()
    finished = 0
    for s in sessions:
        if s["en_curso"]:
            continue
        finished += 1
        actions = [e for e in by_session.get(s["id"], ()) if (e["cat"], e["ev"]) not in NOT_ACTIONS and e["cat"] != "economia"]
        if actions:
            last = actions[-1]
            if (last["cat"], last["ev"]) == ("sesion", "inicio"):
                last_action["Se fue desde el título (no pulsó «Jugar»)"] += 1
            else:
                last_action[label_of(last["cat"], last["ev"])] += 1
        else:
            last_action["Se fue desde el título (no pulsó «Jugar»)"] += 1
    abandon = [{"accion": a, "sesiones": n, "pct": 100.0 * n / finished if finished else 0.0}
               for a, n in last_action.most_common(10)]

    # --- Mapa de calor del pueblo
    move_cells, harvest_cells = Counter(), Counter()
    for e in scoped:
        x, y = e["x"], e["y"]
        if x is None or y is None or not (0 <= x < WORLD_W and 0 <= y < WORLD_H):
            continue
        cell = (int(x // CELL), int(y // CELL))
        if (e["cat"], e["ev"]) == ("movimiento", "pos") and e["lugar"] == OUTDOOR_PLACE:
            move_cells[cell] += e["valor"] or 0
        elif (e["cat"], e["ev"]) == ("juego", "cosecha"):
            harvest_cells[cell] += 1
    heatmap = {
        "celda": CELL, "ancho": WORLD_W, "alto": WORLD_H,
        "movimiento": [[gx, gy, round(v, 1)] for (gx, gy), v in move_cells.items()],
        "cosechas": [[gx, gy, n] for (gx, gy), n in harvest_cells.items()],
    }

    # --- Encargos
    quests = {}
    for e in scoped:
        if e["cat"] != "juego" or e["ev"] not in ("encargo_aceptado", "encargo_completado"):
            continue
        q = quests.setdefault(e["objetivo"], {"id": e["objetivo"], "titulo": e["detalle"] or e["objetivo"],
                                              "aceptados": 0, "completados": 0, "tiempos": []})
        if e["detalle"]:
            q["titulo"] = e["detalle"]
        if e["ev"] == "encargo_aceptado":
            q["aceptados"] += 1
        else:
            q["completados"] += 1
            if e["valor"] is not None and e["valor"] >= 0:
                q["tiempos"].append(e["valor"])
    quest_rows = []
    for q in quests.values():
        quest_rows.append({"id": q["id"], "titulo": q["titulo"], "aceptados": q["aceptados"],
                           "completados": q["completados"],
                           "tasa": (100.0 * q["completados"] / q["aceptados"]) if q["aceptados"] else None,
                           "tiempo_medio": mean(q["tiempos"])})
    quest_rows.sort(key=lambda r: -r["aceptados"])

    # --- Aldeanos e IA
    npcs = {}
    error_texts = Counter()
    for e in scoped:
        if e["cat"] != "ia":
            continue
        n = npcs.setdefault(e["objetivo"] or "(sin nombre)", {"charlas": 0, "mensajes": 0, "duraciones": [], "latencias": [], "errores": 0})
        if e["ev"] == "charla_inicio":
            n["charlas"] += 1
        elif e["ev"] == "mensaje_enviado":
            n["mensajes"] += 1
        elif e["ev"] == "charla_fin" and e["valor"] is not None:
            n["duraciones"].append(e["valor"])
        elif e["ev"] == "respuesta" and e["valor"] is not None:
            n["latencias"].append(e["valor"])
        elif e["ev"] == "error":
            n["errores"] += 1
            error_texts[e["detalle"] or "(sin detalle)"] += 1
    npc_rows = [{"aldeano": name, "charlas": v["charlas"], "mensajes": v["mensajes"],
                 "duracion_media": mean(v["duraciones"]), "latencia_media": mean(v["latencias"]),
                 "errores": v["errores"]} for name, v in npcs.items()]
    npc_rows.sort(key=lambda r: -r["charlas"])
    top_errors = [{"detalle": t, "n": n} for t, n in error_texts.most_common(8)]

    # --- Cosechas, lugares, menús, monedas
    crops = Counter(e["objetivo"] for e in scoped if (e["cat"], e["ev"]) == ("juego", "cosecha"))
    crop_rows = [{"cultivo": CROP_NAMES.get(k, k), "n": n} for k, n in crops.most_common()]

    place_time, place_visits = Counter(), Counter()
    for e in scoped:
        if e["cat"] == "lugar" and e["ev"] == "salida":
            place_time[e["objetivo"]] += e["valor"] or 0
        elif e["cat"] == "lugar" and e["ev"] == "entrada":
            place_visits[e["objetivo"]] += 1
    place_rows = [{"lugar": p, "segundos": round(place_time.get(p, 0), 1), "visitas": place_visits.get(p, 0)}
                  for p in set(place_time) | set(place_visits)]
    place_rows.sort(key=lambda r: -r["segundos"])

    menu_count, menu_sessions = Counter(), defaultdict(set)
    for e in scoped:
        if e["cat"] == "menu" and e["ev"] in MENU_LABELS:
            menu_count[e["ev"]] += 1
            menu_sessions[e["ev"]].add(e["sesion_id"])
    menu_rows = [{"menu": MENU_LABELS[k], "n": n, "sesiones": len(menu_sessions[k])} for k, n in menu_count.most_common()]
    saved = sum(1 for e in scoped if (e["cat"], e["ev"]) == ("partida", "guardar"))
    loaded = sum(1 for e in scoped if (e["cat"], e["ev"]) == ("partida", "cargar"))

    coins = Counter()
    for e in scoped:
        if e["cat"] == "economia":
            coins[e["ev"]] += e["valor"] or 0
    coin_rows = [{"origen": COIN_LABELS.get(k, k), "monedas": round(v)} for k, v in coins.most_common()]

    # --- Game feel: cuántas interacciones salvaron el input buffer y el coyote time
    interactions = sum(1 for e in scoped if (e["cat"], e["ev"]) in (("juego", "cosecha"), ("juego", "hablar"), ("juego", "entrar_casa")))
    buffer_events = [e for e in scoped if (e["cat"], e["ev"]) == ("feel", "input_buffer")]
    coyote_n = sum(1 for e in scoped if (e["cat"], e["ev"]) == ("feel", "coyote"))
    feel = {
        "interacciones": interactions,
        "buffer": len(buffer_events),
        "coyote": coyote_n,
        "pct_salvadas": (100.0 * (len(buffer_events) + coyote_n) / interactions) if interactions else None,
        "buffer_espera_media_ms": mean([e["valor"] for e in buffer_events if e["valor"] is not None]),
    }

    # --- Extras para desarrollo: sistema/versión y FPS por lugar
    builds = defaultdict(lambda: {"sesiones": 0, "duraciones": []})
    for s in sessions:
        key = (s["version"] or "?", s["os"] or "?")
        builds[key]["sesiones"] += 1
        builds[key]["duraciones"].append(s["duracion"])
    build_rows = [{"version": v, "os": o, "sesiones": d["sesiones"], "duracion_media": mean(d["duraciones"])}
                  for (v, o), d in builds.items()]
    build_rows.sort(key=lambda r: -r["sesiones"])
    fps_by_place = defaultdict(list)
    for e in scoped:
        if (e["cat"], e["ev"]) == ("rendimiento", "fps") and e["valor"] and e["valor"] > 0:
            fps_by_place[e["lugar"] or "?"].append(e["valor"])
    fps_rows = [{"lugar": p, "fps_medio": mean(v), "fps_p5": percentile(v, 5), "muestras": len(v)} for p, v in fps_by_place.items()]
    fps_rows.sort(key=lambda r: (r["fps_medio"] or 0))

    # --- Listas recientes y resumen por tipo
    recent_sessions = [{
        "inicio": fmt_ts(s["inicio"]), "jugador": s["jugador"], "version": s["version"], "os": s["os"],
        "duracion": s["duracion"], "activo": s["tiempo_activo"], "api_key": bool(s["api_key"]),
        "estado": "en curso" if s["en_curso"] else "terminada",
    } for s in sessions[:15]]
    recent_events = [{
        "hora": fmt_ts(e["ts"]), "jugador": e["jugador"], "categoria": e["cat"], "evento": label_of(e["cat"], e["ev"]),
        "lugar": e["lugar"], "valor": e["valor"], "detalle": e["objetivo"] or e["detalle"] or "",
    } for e in reversed([e for e in scoped if (e["cat"], e["ev"]) not in SAMPLE_EVENTS][-40:])]
    by_type = Counter((e["cat"], e["ev"]) for e in scoped)
    summary = [{"categoria": c, "evento": label_of(c, ev), "n": n} for (c, ev), n in by_type.most_common(40)]

    return {
        "generado": now, "periodo": period, "jugador": player or "",
        "kpis": kpis, "embudo": funnel, "dias": days, "horas": hours, "abandono": abandon,
        "abandono_total": finished, "mapa": heatmap, "encargos": quest_rows,
        "aldeanos": npc_rows, "errores_ia": top_errors, "cosechas": crop_rows, "lugares": place_rows,
        "menus": menu_rows, "partidas": {"guardadas": saved, "cargadas": loaded},
        "monedas": coin_rows, "builds": build_rows, "fps_lugares": fps_rows, "feel": feel,
        "sesiones_recientes": recent_sessions, "eventos_recientes": recent_events, "resumen_eventos": summary,
    }


def export_csv(period, player):
    since = since_ts(period)
    where, params = ["ts >= ?"], [since]
    if player:
        where.append("jugador = ?")
        params.append(player)
    conn = connect()
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["fecha_hora", "sesion_id", "jugador", "categoria", "evento", "objetivo", "detalle", "valor", "lugar", "x", "y"])
    for r in conn.execute("SELECT * FROM telemetria WHERE %s ORDER BY ts, id" % " AND ".join(where), params):
        writer.writerow([fmt_ts(r["ts"]), r["sesion_id"], r["jugador"], r["cat"], r["ev"], r["objetivo"],
                         r["detalle"], r["valor"], r["lugar"], r["x"], r["y"]])
    conn.close()
    return out.getvalue().encode("utf-8-sig")  # BOM para que Excel respete los acentos


# ----------------------------------------------------------------------------
# Escritura: marcador y telemetría
# ----------------------------------------------------------------------------

def save_sync(body):
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    jugador = clip(body.get("jugador", "Granjero_1"), 40) or "Granjero_1"
    monedas = int(to_float(body.get("monedas")))
    coleccionables = int(to_float(body.get("coleccionables")))
    misiones = int(to_float(body.get("misiones")))
    tiempo = int(to_float(body.get("tiempo_segundos")))
    score = (coleccionables * 50) + (monedas * 10) + (misiones * 150) + (tiempo * 2)
    conn = connect()
    conn.execute("""
        INSERT INTO jugadores (jugador, score, monedas, coleccionables, misiones, tiempo_segundos, ultima_actualizacion)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(jugador) DO UPDATE SET
            score = excluded.score, monedas = excluded.monedas, coleccionables = excluded.coleccionables,
            misiones = excluded.misiones, tiempo_segundos = excluded.tiempo_segundos,
            ultima_actualizacion = excluded.ultima_actualizacion
    """, (jugador, score, monedas, coleccionables, misiones, tiempo, ahora))
    evento = clip(body.get("evento_tipo", ""), 60)
    if evento:
        conn.execute("""INSERT INTO historial_eventos (jugador, tipo_evento, detalle, valor, fecha_hora)
                        VALUES (?, ?, ?, ?, ?)""",
                     (jugador, evento, clip(body.get("evento_detalle", ""), 200), int(to_float(body.get("evento_valor"))), ahora))
    conn.commit()
    conn.close()
    return {"ok": True, "score": score}


def save_telemetry(body):
    session = body.get("session")
    events = body.get("events", [])
    if not isinstance(session, dict) or not isinstance(events, list):
        raise ValueError("formato inválido")
    sid = clip(session.get("id"), 64)
    if not sid:
        raise ValueError("falta el id de sesión")
    now = time.time()
    jugador = clip(session.get("jugador", "Anónimo"), 40) or "Anónimo"
    conn = connect()
    conn.execute("""
        INSERT INTO sesiones (id, jugador, inicio, ultimo_visto, fin, version, os, api_key, tiempo_activo)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            jugador = excluded.jugador, ultimo_visto = excluded.ultimo_visto,
            fin = MAX(fin, excluded.fin), version = excluded.version, os = excluded.os,
            api_key = MAX(api_key, excluded.api_key), tiempo_activo = MAX(tiempo_activo, excluded.tiempo_activo)
    """, (sid, jugador, to_float(session.get("inicio"), now), now, 1 if session.get("fin") else 0,
          clip(session.get("version"), 20), clip(session.get("os"), 20),
          1 if session.get("api_key") else 0, to_float(session.get("activo"))))
    rows = []
    for e in events[:MAX_EVENTS_PER_POST]:
        if not isinstance(e, dict):
            continue
        x, y = e.get("x"), e.get("y")
        rows.append((sid, jugador, to_float(e.get("t"), now), clip(e.get("c"), 30), clip(e.get("e"), 40),
                     clip(e.get("o"), 80), clip(e.get("d"), 160), to_float(e.get("v")), clip(e.get("p"), 60),
                     to_float(x) if x is not None else None, to_float(y) if y is not None else None))
    conn.executemany("""INSERT INTO telemetria (sesion_id, jugador, ts, cat, ev, objetivo, detalle, valor, lugar, x, y)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", rows)
    conn.commit()
    conn.close()
    return {"ok": True, "guardados": len(rows)}


# ----------------------------------------------------------------------------
# HTTP
# ----------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "WillowmereDB/2.0"

    def _send(self, status, content_type, payload, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))  # sin esto Godot puede recibir el cuerpo vacío
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def _json(self, data, status=200):
        self._send(status, "application/json; charset=utf-8", json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def _file(self, name, content_type):
        path = os.path.join(DASH_DIR, name)
        if not os.path.isfile(path):
            self._json({"error": "No se encontró tools/dashboard/" + name}, 404)
            return
        with open(path, "rb") as f:
            self._send(200, content_type, f.read())

    def do_OPTIONS(self):
        self._send(204, "text/plain", b"", {"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                                            "Access-Control-Allow-Headers": "Content-Type"})

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        period = query.get("periodo", ["all"])[0]
        if period not in PERIODS:
            period = "all"
        player = query.get("jugador", [""])[0].strip()
        if player.lower() in ("todos", "all", "*"):
            player = ""
        try:
            if url.path in ("/", "/index.html"):
                self._file("index.html", "text/html; charset=utf-8")
            elif url.path == "/mapa.png":
                self._file("mapa_pueblo.png", "image/png")
            elif url.path == "/api/leaderboard":
                # Lo usa el menú "Marcador" del juego: sin filtros, como siempre.
                data = players_data("all", "")
                self._json({"leaderboard": data["leaderboard"][:20], "eventos": data["eventos"]})
            elif url.path == "/api/dashboard":
                self._json(players_data(period, player))
            elif url.path == "/api/analytics":
                self._json(analytics(period, player))
            elif url.path == "/api/export.csv":
                name = "willowmere_telemetria_%s%s.csv" % (period, "_" + player if player else "")
                self._send(200, "text/csv; charset=utf-8", export_csv(period, player),
                           {"Content-Disposition": 'attachment; filename="%s"' % name})
            elif url.path == "/api/health":
                self._json({"ok": True, "hora": time.time()})
            else:
                self._json({"error": "Ruta no encontrada"}, 404)
        except Exception as error:  # el panel debe seguir vivo aunque una consulta falle
            self._json({"error": str(error)}, 500)

    def do_POST(self):
        url = urlparse(self.path)
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > MAX_BODY:
                self._json({"error": "Cuerpo demasiado grande"}, 413)
                return
            raw = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
            body = json.loads(raw)
            if not isinstance(body, dict):
                raise ValueError("se esperaba un objeto JSON")
            if url.path == "/api/sync":
                self._json(save_sync(body))
            elif url.path == "/api/telemetry":
                self._json(save_telemetry(body))
            else:
                self._json({"error": "Endpoint inválido"}, 400)
        except (ValueError, json.JSONDecodeError) as error:
            self._json({"error": "Petición inválida: %s" % error}, 400)
        except Exception as error:
            self._json({"error": str(error)}, 500)

    def log_message(self, format, *args):
        return  # sin ruido en la consola


def main():
    global DB_PATH, PORT
    parser = argparse.ArgumentParser(description="Servidor local de Willowmere (SQLite + panel web)")
    parser.add_argument("--db", default=DB_PATH, help="archivo de la base de datos (por defecto %(default)s)")
    parser.add_argument("--port", type=int, default=PORT, help="puerto (por defecto %(default)s)")
    args = parser.parse_args()
    DB_PATH, PORT = args.db, args.port
    init_db()
    print("======================================================")
    print("Base de datos SQLite activa: %s" % os.path.abspath(DB_PATH))
    print("Panel web disponible en:     http://localhost:%d" % PORT)
    print("======================================================")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
