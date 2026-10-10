class_name ActorFrames
extends RefCounted
## Construye las animaciones (idle y walk, 3 direcciones) del jugador y los NPCs
## cortando las hojas de sprites en cuadros de 32 px.

const FRAME_SIZE := 32
const IDLE_TEXTURE: Texture2D = preload("res://asset_pack/Character/Idle.png")
const WALK_TEXTURE: Texture2D = preload("res://asset_pack/Character/Walk.png")
const DIRECTIONS := ["down", "up", "side"]


static func build() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	_add_animations(frames, "idle", IDLE_TEXTURE, 4, 5.0)
	_add_animations(frames, "walk", WALK_TEXTURE, 6, 9.0)
	return frames


static func _add_animations(frames: SpriteFrames, prefix: String, texture: Texture2D, column_count: int, speed: float) -> void:
	for direction_index in range(DIRECTIONS.size()):
		var animation_name: String = prefix + "_" + DIRECTIONS[direction_index]
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, speed)
		frames.set_animation_loop(animation_name, true)
		for column in range(column_count):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(column * FRAME_SIZE, direction_index * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
			frames.add_frame(animation_name, atlas)
