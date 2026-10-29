extends Node2D
class_name FieldFX

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")

func play(plot_id: int, action: String) -> void:
	for child in get_children(): child.queue_free()
	var texture: Texture2D
	var height := 52.0
	match action:
		"water": texture = Assets.crop_overlay("watered")
		"harvest":
			texture = Assets.crop_overlay("harvest")
			height = 66.0
		"seed", "till": texture = Assets.crop_overlay("stage_up")
		"fertilize": texture = Assets.crop_overlay("fertilized")
		_: texture = Assets.crop_overlay("stage_up")
	if texture == null: return
	var coord := Geometry.grid_coord(plot_id)
	var sprite := Sprite2D.new()
	sprite.name = "ActionFX_%s" % action
	sprite.texture = texture
	sprite.position = Geometry.crop_anchor(coord.x, coord.y)
	sprite.centered = false
	sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height())
	var scale_value := height / float(texture.get_height())
	sprite.scale = Vector2.ONE * scale_value
	add_child(sprite)
	var tween := create_tween()
	tween.tween_interval(0.10)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
	tween.finished.connect(sprite.queue_free)
