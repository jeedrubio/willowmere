# Herramientas de Willowmere

## Servidor de estadísticas (`servidor_sqlite.py`)
Desde la carpeta del proyecto:

    python tools/servidor_sqlite.py                      # base willowmere_data.db, puerto 8080
    python tools/servidor_sqlite.py --db otra.db --port 9000

Panel web: http://localhost:8080 — pestañas **Jugadores** (marcador y bitácora) y **Analítica**
(indicadores, embudo, mapa de calor, IA, menús, rendimiento...). No necesita instalar nada.

El juego envía por sí solo marcador (`/api/sync`) y telemetría de uso (`/api/telemetry`) si el
servidor está encendido; si no, sigue funcionando normal. El jugador puede apagar la telemetría en
Ajustes > Datos. Tu base existente se conserva: las tablas nuevas se crean al arrancar.

## Datos de prueba (`generar_datos_demo.py`)
Para ver el panel con información realista sin jugar:

    python tools/generar_datos_demo.py                   # crea willowmere_demo.db
    python tools/servidor_sqlite.py --db willowmere_demo.db

Se niega a escribir en `willowmere_data.db` para no mezclar datos inventados con los reales.

## Mapa del pueblo (`dashboard/mapa_pueblo.png`)
Fondo del mapa de calor (2272 x 1216 px del mundo, a media escala). Si cambias el mapa del juego,
vuelve a generarlo. La carpeta `dashboard/` tiene un `.gdignore` para que Godot no la importe.

## Estilo de la interfaz (`skin/generar_skin.py`)
Genera las texturas de botones y paneles de `asset_pack/UI/skin` a partir de una imagen de botones
(`python tools/skin/generar_skin.py --fuente botones.png --salida asset_pack/UI/skin`). Si cambias el
estilo, genera de nuevo las texturas y reabre el proyecto en Godot. Los márgenes de corte (9-slice) están en
`asset_pack/UI/skin/skin.json` y en `UiKit`.

## Efectos de sonido (`audio/generar_sfx.py`)
`python tools/audio/generar_sfx.py --salida audio/sfx` sintetiza los 16 efectos (cambia notas o duraciones en el
script y vuelve a ejecutarlo).

## Fuente
La interfaz usa *Pixelify Sans* (licencia OFL, en `asset_pack/Fonts`), sin ligaduras.
