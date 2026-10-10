class_name NpcProfile
extends Resource
## Datos de un aldeano. Se edita en el Inspector (data/npcs/*.tres) y se asigna
## al nodo del NPC en World.tscn, así que añadir o cambiar personajes no
## requiere tocar ningún script.

## Identificador interno (por ejemplo "mira"). La misión lo usa para saber quién la da.
@export var id: String = ""
## Nombre que se muestra sobre el personaje y en el diálogo.
@export var display_name: String = ""
## Oficio o título (aparece bajo el nombre en el diálogo).
@export var role: String = ""
## Color del sprite y de la etiqueta de nombre.
@export var color: Color = Color.WHITE
## Cuadro inicial de la animación idle (sirve para desincronizar a los NPCs).
@export var idle_frame: int = 0
## Primer saludo del personaje (la misión puede reemplazarlo).
@export_multiline var greeting: String = ""
## Personalidad que se envía a Gemini como instrucción de sistema.
@export_multiline var persona: String = ""

## Si es verdadero, el aldeano pasea por su zona (ver WanderActor). Desmárcalo para dejarlo quieto.
@export var wanders: bool = true
## Hasta dónde se aleja de su sitio inicial, en píxeles.
@export_range(0.0, 400.0, 5.0) var wander_radius: float = 70.0
## Velocidad al caminar, en píxeles por segundo (el jugador va a 145).
@export_range(5.0, 120.0, 1.0) var wander_speed: float = 42.0
