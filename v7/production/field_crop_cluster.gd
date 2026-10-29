extends Node2D
class_name FieldCropCluster

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const PlantAssets = preload("res://v7/runtime/runtime_crop_registry_v7_3.gd")
const PRODUCTION_ROOT := "res://assets/field_approved_v1/runtime"

var plot_id := 1
var crop_id := "carrot"
var growth_stage := 0
var harvest_ready := false
var shadow_radius := Vector2(12, 3)
var shadow_spots: Array[Dictionary] = []
var seed_mounds: Array[Vector2] = []


func configure(id_value: int, crop_value: String, stage_value: int, ready_value := false) -> void:
	plot_id = id_value
	crop_id = crop_value
	growth_stage = stage_value
	harvest_ready = ready_value
	var coord := Geometry.grid_coord(plot_id)
	position = PixelMap.visual_crop_anchor(plot_id)
	_rebuild(coord)


func animate_stage_in() -> void:
	var settled_position := position
	position += Vector2(0, 5)
	scale = Vector2.ONE * 0.92
	modulate = Color(1.08, 1.05, 0.94, 0.86)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.38)
	tween.tween_property(self, "position", settled_position, 0.38)
	tween.tween_property(self, "modulate", Color.WHITE, 0.32)


func _rebuild(coord: Vector2i) -> void:
	for child in get_children():
		child.queue_free()
	shadow_spots.clear()
	seed_mounds.clear()
	_build_production_crop(coord)
	queue_redraw()


func _build_production_crop(coord: Vector2i) -> void:
	var stage := 4 if harvest_ready else clampi(growth_stage, 1, 4)
	var crop_path := "%s/crops/%s/%s_stage_%02d.png" % [PRODUCTION_ROOT, crop_id.to_upper(), crop_id, stage]
	var crop_texture := load(crop_path) as Texture2D
	if crop_texture == null:
		return
	var bed_bounds := _bounds(PixelMap.visual_plot_polygon(plot_id))
	var stage_height_ratio: float = float([0.46, 0.62, 0.76, 0.88][stage - 1])
	var stage_width_ratio: float = float([0.38, 0.50, 0.62, 0.72][stage - 1])
	var target_height: float = bed_bounds.size.y * stage_height_ratio
	var crop_sprite := _sprite(crop_texture)
	crop_sprite.name = "ProductionCrop"
	crop_sprite.z_index = 2
	# Every production crop uses the same geometric contract: the bottom-center
	# of its visible (non-transparent) pixels sits on the plot planting anchor.
	crop_sprite.position = Vector2.ZERO
	_scale_to_height(crop_sprite, target_height)
	var max_width := bed_bounds.size.x * stage_width_ratio
	var rendered_width := _visible_bounds(crop_texture).size.x * crop_sprite.scale.x
	if rendered_width > max_width:
		crop_sprite.scale *= max_width / rendered_width
		rendered_width = max_width
	shadow_spots.append({"position": Vector2(0, -1), "radius": Vector2(maxf(8.0, rendered_width * 0.30), 3.4 * float([0.88, 1.0, 1.12][clampi(coord.y, 0, 2)]))})
	var row_name: String = String(["far", "mid", "near"][clampi(coord.y, 0, 2)])
	var lip_texture := load("%s/plots/front_soil_lip_%s.png" % [PRODUCTION_ROOT, row_name]) as Texture2D
	if lip_texture != null:
		var lip := Sprite2D.new()
		lip.name = "FrontSoilLip"
		lip.texture = lip_texture
		lip.centered = false
		lip.offset = Vector2(-lip_texture.get_width() * 0.5, -lip_texture.get_height() * 0.38)
		lip.scale = Vector2(bed_bounds.size.x * 0.86 / float(lip_texture.get_width()), (14.0 + float(coord.y) * 2.5) / float(lip_texture.get_height()))
		lip.z_index = 4
		add_child(lip)


func _build_seed_cluster(coord: Vector2i) -> void:
	shadow_radius = Vector2(7.0, 2.0)
	var texture: Texture2D = load(String(PlantAssets.COMMON["seed"]))
	var offsets := [Vector2(-22, -6), Vector2(10, -7), Vector2(-29, 5), Vector2(0, 7), Vector2(29, 5)]
	var scale_factor := _row_scale(coord.y)
	for index in range(offsets.size()):
		var sprite := _sprite(texture)
		sprite.position = offsets[index] * Vector2(scale_factor, scale_factor * 0.72)
		_scale_to_height(sprite, (9.0 + float(index % 2) * 1.3) * scale_factor)
		seed_mounds.append(sprite.position + Vector2(0, 2.5))
		shadow_spots.append({"position": sprite.position + Vector2(0, 2), "radius": Vector2(8, 2.4) * scale_factor})


func _build_sprout_cluster(coord: Vector2i) -> void:
	shadow_radius = Vector2(13.0, 2.4) * _row_scale(coord.y)
	var texture: Texture2D = load(String(PlantAssets.COMMON["sprout"]))
	var offsets := [Vector2(-20, -7), Vector2(14, -7), Vector2(-28, 5), Vector2(0, 7), Vector2(28, 5)]
	var scale_factor := _row_scale(coord.y)
	for index in range(offsets.size()):
		var sprite := _sprite(texture)
		sprite.position = offsets[index] * Vector2(scale_factor, scale_factor * 0.70)
		var perspective_scale := 0.82 if index < 2 else 1.0
		_scale_to_height(sprite, (22.0 + float(index % 3) * 1.8) * scale_factor * perspective_scale)
		sprite.z_index = 0 if index < 2 else 1
		shadow_spots.append({"position": sprite.position + Vector2(0, 1), "radius": Vector2(8.5, 2.3) * scale_factor * perspective_scale})


func _build_family_cluster(coord: Vector2i) -> void:
	var max_stage := 5 if crop_id == "pumpkin" else 4
	var source_stage := max_stage if harvest_ready or growth_stage >= max_stage else maxi(1, growth_stage - 1)
	var texture := PlantAssets.world_crop(crop_id, source_stage)
	var target_height := Geometry.crop_target_height(coord.x, coord.y, growth_stage) * 1.08
	if harvest_ready:
		target_height = Geometry.crop_target_height(coord.x, coord.y, max_stage) * 1.08
	var bed_bounds := _bounds(PixelMap.plot_polygon(plot_id))
	var spread := bed_bounds.size.x
	var anchors := [
		{"position": Vector2(-spread * 0.16, -8), "scale": 0.60, "depth": 0},
		{"position": Vector2(spread * 0.16, -8), "scale": 0.60, "depth": 0},
		{"position": Vector2(-spread * 0.27, 6), "scale": 0.72, "depth": 1},
		{"position": Vector2(0, 8), "scale": 0.82, "depth": 1},
		{"position": Vector2(spread * 0.27, 6), "scale": 0.72, "depth": 1},
	]
	if crop_id == "pumpkin" and not harvest_ready:
		anchors = [anchors[0], anchors[3], anchors[4]]
	var widest_sprite := 0.0
	for anchor in anchors:
		var sprite := _sprite(texture)
		sprite.position = Vector2(anchor["position"])
		_scale_to_height(sprite, maxf(24.0, target_height * float(anchor["scale"])))
		sprite.z_index = int(anchor["depth"])
		var visible_width := float(texture.get_width()) * sprite.scale.x
		var max_single_width := bed_bounds.size.x * 0.42
		if visible_width > max_single_width:
			sprite.scale *= max_single_width / visible_width
			visible_width = max_single_width
		widest_sprite = maxf(widest_sprite, visible_width)
		shadow_spots.append({"position": sprite.position + Vector2(0, 2), "radius": Vector2(visible_width * 0.34, clampf(target_height * 0.045, 2.5, 5.5))})
	shadow_radius = Vector2(minf(widest_sprite * 0.44, bed_bounds.size.x * 0.25), clampf(target_height * 0.055, 3.0, 6.0))


func _sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2.ZERO
	var visible_bounds := _visible_bounds(texture)
	sprite.offset = Vector2(
		-visible_bounds.position.x - visible_bounds.size.x * 0.5,
		-visible_bounds.position.y - visible_bounds.size.y
	)
	add_child(sprite)
	return sprite


func _scale_to_height(sprite: Sprite2D, target_height: float) -> void:
	var visible_height := maxf(1.0, _visible_bounds(sprite.texture).size.y)
	var scale_value := target_height / visible_height
	sprite.scale = Vector2.ONE * scale_value


func _visible_bounds(texture: Texture2D) -> Rect2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture.get_size())
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2(Vector2.ZERO, texture.get_size())
	return Rect2(used)


func _row_scale(row: int) -> float:
	return lerpf(0.86, 1.14, float(row) / maxf(1.0, float(Geometry.rows() - 1)))


func _draw() -> void:
	if shadow_spots.is_empty():
		_draw_ellipse(Vector2(0, -1), shadow_radius, Color(0.15, 0.12, 0.10, 0.20))
	else:
		for spot in shadow_spots:
			_draw_ellipse(Vector2(spot["position"]), Vector2(spot["radius"]), Color(0.15, 0.12, 0.10, 0.22))
	for mound in seed_mounds:
		_draw_ellipse(mound, Vector2(9.5, 3.4), Color(0.25, 0.13, 0.07, 0.78))
		_draw_ellipse(mound + Vector2(0, -0.8), Vector2(7.0, 2.1), Color(0.48, 0.29, 0.14, 0.66))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		result = result.expand(point)
	return result
