# Game feel / juice en Willowmere

Willowmere es un RPG de granja en **vista cenital** (no hay saltos ni plataformas), así que las técnicas
clásicas se adaptaron a lo que el jugador hace aquí: **interactuar** (E), **usar puertas** (F) y **cosechar**.
Todos los valores se ajustan en un solo archivo: `scripts/systems/game_feel.gd`.

## 1. Input buffering — `scripts/systems/input_buffer.gd`
Una pulsación de **E** o **F** que no se puede ejecutar todavía se guarda `INPUT_BUFFER_TIME` (0,20 s) y se
ejecuta en cuanto es posible. Si caduca, se descarta (así no se dispara "tarde" algo que el jugador ya olvidó).

Casos reales en el juego:
- Pulsar E un paso **antes de llegar** a un cultivo o aldeano.
- Pulsar F/E **durante el fundido** de una puerta.
- Pulsar E justo **antes de que un cultivo termine de madurar**.

No se guarda mientras hay un diálogo, la mochila o un menú abierto (evita que una E "fantasma" se dispare al cerrarlos).
Dónde: `Main._unhandled_input()` guarda la pulsación y `Main._process_buffered_input()` la ejecuta.

## 2. Coyote time — `scripts/systems/coyote_target.gd`
En un plataformas es "saltar justo después de dejar la plataforma". Aquí es el equivalente cenital:
el último objetivo válido (aldeano, cultivo, puerta) **sigue disponible `INTERACT_COYOTE_TIME` (0,15 s)** después
de salir de su alcance, siempre que no se haya alejado más de `COYOTE_MAX_RANGE_FACTOR` (1,6x) su alcance.
Sirve cuando el jugador se pasa un paso del cultivo o de la puerta y pulsa un instante tarde.
Dónde: `Main._try_interact()` y `Main._try_door()`.

## 3. Screenshake — `scripts/systems/camera_shake.gd`
Modelo de **trauma** (0..1): cada golpe suma trauma, la vibración es proporcional a trauma² y se amortigua sola
(`SHAKE_DECAY`). El desplazamiento se redondea a píxeles enteros para respetar el pixel art.

| Momento | Trauma |
|---|---|
| Cosechar | 0,22 |
| Cosechar con mochila llena / cultivo aún verde | 0,14 / 0,07 |
| Aceptar un encargo | 0,25 |
| Completar un encargo | 0,60 |
| Cruzar una puerta | 0,12 |
| Ganar monedas | 0,10 |

Accesibilidad: **Ajustes > Juego** permite dejarla en *Desactivada*, *Suave* (x0,5) o *Normal*.

## 4. Feedback
- **Sonido** (`scripts/systems/sfx.gd`, autoload `Sfx`): 16 efectos chiptune sintetizados con
  `tools/audio/generar_sfx.py` (cosecha, recoger, moneda, error, encargo nuevo/completado, puerta, guardar/cargar,
  menús...). Volumen y silencio propios en **Ajustes > Audio**, con variación de tono para que no cansen.
- **Partículas y textos flotantes** (`scripts/systems/juice.gd`): ráfaga del color del cultivo y "+1 Fresa" al
  cosechar, chispas y "¡Encargo completado!" al terminar un encargo, "Mochila llena" / "Aún crece" al fallar.
  Polvo bajo los pies al caminar. Se pueden apagar en **Ajustes > Juego**.
- **Rebotes** (squash & stretch) del jugador y del cultivo, y temblor lateral del cultivo cuando la acción se rechaza.
- **Interfaz** (`scripts/ui/game_hud.gd`, `scripts/ui/ui_kit.gd`): el contador de monedas cuenta hasta el valor
  nuevo y rebota; destello de pantalla al completar un encargo; los avisos y toasts entran con rebote; los botones
  suenan y se agrandan al pasar el ratón y se "aplastan" al pulsar.

## Medir si funciona
La telemetría registra `feel/input_buffer` (con cuántos ms esperó) y `feel/coyote`. El panel web
(Analítica > *Game feel*) muestra qué porcentaje de las interacciones se salvaron gracias a ellos.

## Pruebas
Los módulos son clases pequeñas sin dependencias de escena (`InputBuffer`, `CoyoteTarget`, `CameraShake`), por lo que
se prueban fácilmente: reciben el tiempo como argumento opcional (`now_ms`).
