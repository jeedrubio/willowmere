import sqlite3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse
from datetime import datetime

DB_PATH = "willowmere_data.db"
PORT = 8080

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Tabla principal de jugadores y Leaderboard
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS jugadores (
            jugador TEXT PRIMARY KEY,
            score INTEGER DEFAULT 0,
            monedas INTEGER DEFAULT 0,
            coleccionables INTEGER DEFAULT 0,
            misiones INTEGER DEFAULT 0,
            tiempo_segundos INTEGER DEFAULT 0,
            ultima_actualizacion TEXT
        )
    """)
    # Tabla detallada de todo lo que hace el jugador
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS historial_eventos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jugador TEXT,
            tipo_evento TEXT,
            detalle TEXT,
            valor INTEGER DEFAULT 0,
            fecha_hora TEXT
        )
    """)
    conn.commit()
    conn.close()

HTML_DASHBOARD = """<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Willowmere - Panel Web Local & Leaderboard (SQLite)</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #1a241e; color: #e8f0ea; margin: 0; padding: 24px; }
        h1, h2 { color: #8fd694; margin-bottom: 10px; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #2e4436; padding-bottom: 12px; margin-bottom: 20px; }
        .badge { background: #2e4436; color: #a3e4a8; padding: 6px 12px; border-radius: 6px; font-size: 14px; }
        .grid { display: grid; grid-template-columns: 1.2fr 1fr; gap: 24px; }
        .card { background: #233128; border: 1px solid #354c3e; border-radius: 10px; padding: 18px; box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 14px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #354c3e; }
        th { background: #2c3e33; color: #8fd694; }
        tr:hover { background: #2b3d31; }
        .rank-1 { color: #ffd700; font-weight: bold; }
        .rank-2 { color: #c0c0c0; font-weight: bold; }
        .rank-3 { color: #cd7f32; font-weight: bold; }
        button { background: #4caf50; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-weight: bold; }
        button:hover { background: #43a047; }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h1>🌾 Willowmere — Sistema Web de Base de Datos</h1>
            <small>Conectado en tiempo real a SQLite (willowmere_data.db)</small>
        </div>
        <div>
            <span class="badge" id="status">Sincronizado</span>
            <button onclick="cargarDatos()">🔄 Actualizar ahora</button>
        </div>
    </div>

    <div class="grid">
        <div class="card">
            <h2>🏆 Leaderboard & Estadísticas de Jugadores</h2>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Jugador</th>
                        <th>Score</th>
                        <th>🪙 Monedas</th>
                        <th>🎒 Coleccionables</th>
                        <th>📜 Misiones</th>
                        <th>⏱️ Tiempo</th>
                        <th>Última actividad</th>
                    </tr>
                </thead>
                <tbody id="tabla-leaderboard"></tbody>
            </table>
        </div>

        <div class="card">
            <h2>📋 Bitácora de Acciones del Jugador (Tiempo Real)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Hora</th>
                        <th>Jugador</th>
                        <th>Acción</th>
                        <th>Detalle</th>
                    </tr>
                </thead>
                <tbody id="tabla-eventos"></tbody>
            </table>
        </div>
    </div>

    <script>
        function formatearTiempo(seg) {
            const m = Math.floor(seg / 60);
            const s = seg % 60;
            return `${m}m ${s}s`;
        }

        async function cargarDatos() {
            const res = await fetch('/api/dashboard');
            const data = await res.json();

            const lb = document.getElementById('tabla-leaderboard');
            lb.innerHTML = data.leaderboard.map((row, idx) => `
                <tr class="rank-${idx + 1}">
                    <td>${idx + 1}</td>
                    <td>${row.jugador}</td>
                    <td><strong>${row.score}</strong></td>
                    <td>${row.monedas}</td>
                    <td>${row.coleccionables}</td>
                    <td>${row.misiones}</td>
                    <td>${formatearTiempo(row.tiempo_segundos)}</td>
                    <td>${row.ultima_actualizacion}</td>
                </tr>
            `).join('') || '<tr><td colspan="8">Sin registros aún. Juega en Godot para generar datos.</td></tr>';

            const ev = document.getElementById('tabla-eventos');
            ev.innerHTML = data.eventos.map(e => `
                <tr>
                    <td>${e.fecha_hora}</td>
                    <td><strong>${e.jugador}</strong></td>
                    <td>${e.tipo_evento}</td>
                    <td>${e.detalle} (${e.valor >= 0 ? '+' + e.valor : e.valor})</td>
                </tr>
            `).join('') || '<tr><td colspan="4">Sin eventos registrados.</td></tr>';
        }

        setInterval(cargarDatos, 2500);
        cargarDatos();
    </script>
</body>
</html>
"""

class DBRequestHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/" or path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_DASHBOARD.encode("utf-8"))
        elif path == "/api/dashboard" or path == "/api/leaderboard":
            conn = sqlite3.connect(DB_PATH)
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()
            cur.execute("SELECT * FROM jugadores ORDER BY score DESC LIMIT 20")
            leaderboard = [dict(r) for r in cur.fetchall()]
            cur.execute("SELECT * FROM historial_eventos ORDER BY id DESC LIMIT 30")
            eventos = [dict(r) for r in cur.fetchall()]
            conn.close()
            self._send_json({"leaderboard": leaderboard, "eventos": eventos})
        else:
            self._send_json({"error": "Ruta no encontrada"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length).decode("utf-8")) if length > 0 else {}
        ahora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()

        if path == "/api/sync":
            jugador = body.get("jugador", "Granjero_1")
            monedas = int(body.get("monedas", 0))
            coleccionables = int(body.get("coleccionables", 0))
            misiones = int(body.get("misiones", 0))
            tiempo = int(body.get("tiempo_segundos", 0))
            score = (coleccionables * 50) + (monedas * 10) + (misiones * 150) + (tiempo * 2)

            cur.execute("""
                INSERT INTO jugadores (jugador, score, monedas, coleccionables, misiones, tiempo_segundos, ultima_actualizacion)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(jugador) DO UPDATE SET
                    score = excluded.score,
                    monedas = excluded.monedas,
                    coleccionables = excluded.coleccionables,
                    misiones = excluded.misiones,
                    tiempo_segundos = excluded.tiempo_segundos,
                    ultima_actualizacion = excluded.ultima_actualizacion
            """, (jugador, score, monedas, coleccionables, misiones, tiempo, ahora))

            evento = body.get("evento_tipo", "")
            if evento:
                cur.execute("""
                    INSERT INTO historial_eventos (jugador, tipo_evento, detalle, valor, fecha_hora)
                    VALUES (?, ?, ?, ?, ?)
                """, (jugador, evento, body.get("evento_detalle", ""), int(body.get("evento_valor", 0)), ahora))

            conn.commit()
            conn.close()
            self._send_json({"ok": True, "score": score})
        else:
            conn.close()
            self._send_json({"error": "Endpoint inválido"}, 400)

    def log_message(self, format, *args):
        return # Silencia logs innecesarios en consola

if __name__ == "__main__":
    init_db()
    print(f"======================================================")
    print(f"Base de datos SQLite activa: {DB_PATH}")
    print(f"Sistema Web Local disponible en: http://localhost:{PORT}")
    print(f"======================================================")
    HTTPServer(("127.0.0.1", PORT), DBRequestHandler).serve_forever()