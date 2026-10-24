class_name Juice
extends RefCounted
## Efectos visuales sueltos para dar respuesta a las acciones: textos flotantes, ráfagas de
## partículas, rebotes de escala y temblores. Todo se apaga si el jugador desactiva los
## efectos en Ajustes > Juego (GameFeel.effects_enabled).


## Texto que sube y se desvanece (p. ej. "+1 Fresa") en coordenadas del mundo.
static func floating_text(parent: Node, pos: Vector2, text: String, color: Color = Color.WHITE, rise: float = 30.0) -> void:
	if not GameFeel.effects_enabled or not is_instance_valid(parent):
		return
	var label := Label.new()
	label.text = text
	label.z_index = 4000
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#2B2540"))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.reset_size()
	label.position = pos - label.size / 2.0
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.4, 0.4)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - rise, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


## Ráfaga de cuadraditos (estilo pixel) que saltan y caen.
static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 10, speed: float = 90.0, gravity: float = 260.0) -> void:
	if not GameFeel.effects_enabled or not is_instance_valid(parent):
		return
	var particles := CPUParticles2D.new()
	particles.z_index = 3900
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.position = pos
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.55
	particles.explosiveness = 1.0
	particles.direction = Vector2(0, -1)
	particles.spread = 75.0
	particles.gravity = Vector2(0, gravity)
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 2.4
	particles.scale_amount_max = 4.6
	particles.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	parent.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	# Por si "finished" no llega (p. ej. si el nodo se pausa), se limpia igualmente.
	# Se conecta directamente a queue_free: si el nodo ya no existe, Godot desconecta solo.
	particles.get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


## Anillo de destellos para momentos grandes (completar un encargo).
static func sparkle(parent: Node, pos: Vector2, color: Color = Color("#FFE27A")) -> void:
	burst(parent, pos, color, 18, 140.0, 120.0)
	burst(parent, pos, Color("#FFFFFF"), 8, 80.0, 60.0)


## Rebote de "squash & stretch" (sube y baja de escala). Funciona con Sprite2D, AnimatedSprite2D, etc.
static func pop(item: Node2D, strength: float = 0.18, time: float = 0.2) -> void:
	if not GameFeel.effects_enabled or not is_instance_valid(item):
		return
	if not item.has_meta("_pop_base"):
		item.set_meta("_pop_base", item.scale)
	var base: Vector2 = item.get_meta("_pop_base")
	if item.has_meta("_pop_tween"):
		var old: Tween = item.get_meta("_pop_tween")
		if old != null and old.is_valid():
			old.kill()
	item.scale = base
	var tween := item.create_tween()
	item.set_meta("_pop_tween", tween)
	tween.tween_property(item, "scale", base * Vector2(1.0 + strength, 1.0 - strength), time * 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_property(item, "scale", base, time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Temblor lateral corto (acción rechazada, p. ej. cosechar algo que no está maduro).
static func jiggle(item: Node2D, amplitude: float = 2.5, time: float = 0.22) -> void:
	if not GameFeel.effects_enabled or not is_instance_valid(item):
		return
	if not item.has_meta("_jiggle_x"):
		item.set_meta("_jiggle_x", item.position.x)
	var x: float = item.get_meta("_jiggle_x")
	if item.has_meta("_jiggle_tween"):
		var old: Tween = item.get_meta("_jiggle_tween")
		if old != null and old.is_valid():
			old.kill()
	item.position.x = x
	var tween := item.create_tween()
	item.set_meta("_jiggle_tween", tween)
	for i in 4:
		var sign := -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(item, "position:x", x + sign * amplitude * (1.0 - i / 4.0), time / 5.0)
	tween.tween_property(item, "position:x", x, time / 5.0)
