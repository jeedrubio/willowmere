class_name VillageNpc
extends StaticBody2D
## Aldeano con el que se puede hablar. Los datos viven en el recurso `profile`.

@export var profile: NpcProfile

## Se crea con start_wandering(); null si el aldeano no pasea.
var wander: WanderActor = null


## Activa el sprite animado y oculta la vista previa que solo se usa en el editor.
func setup_visuals(frames: SpriteFrames) -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		sprite.sprite_frames = frames
		sprite.play("idle_down")
		if profile != null:
			sprite.frame = profile.idle_frame
			sprite.modulate = profile.color
		sprite.visible = true
	var preview := get_node_or_null("EditorPreview") as Sprite2D
	if preview != null:
		preview.visible = false
	var name_label := get_node_or_null("NameLabel") as Label
	if name_label != null and profile != null:
		name_label.text = profile.display_name.to_upper()
		name_label.add_theme_color_override("font_color", profile.color)


## Pone al aldeano a pasear por su zona (los parámetros salen del perfil).
## `bounds` es el rectángulo de World por el que puede moverse.
func start_wandering(player: Node2D, bounds: Rect2) -> void:
	if wander != null or profile == null or not profile.wanders:
		return
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	# Usa la misma caja de colisión que el aldeano, para que no atraviese nada.
	var size := Vector2(17, 13)
	var foot := Vector2.ZERO
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		foot = shape_node.position
		var rect := shape_node.shape as RectangleShape2D
		if rect != null:
			size = rect.size
	wander = WanderActor.for_npc(self, sprite, player, bounds, profile.wander_radius,
			profile.wander_speed, size + Vector2(2, 2), foot)


## Durante un diálogo el aldeano se detiene y mira hacia `look_at`.
func begin_conversation(look_at: Vector2) -> void:
	if wander != null:
		wander.freeze(look_at)


func end_conversation() -> void:
	if wander != null:
		wander.unfreeze()
