extends Node2D
class_name FieldBedVisual

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")

const RECONSTRUCTION_ROOT := "res://assets/field_approved_v1/runtime/plots"
const STATE_TEXTURES := {
	"untilled": RECONSTRUCTION_ROOT + "/plot_untilled.png",
	"tilled_dry": RECONSTRUCTION_ROOT + "/plot_tilled.png",
	"tilled_wet": RECONSTRUCTION_ROOT + "/plot_wet.png",
	"fertilized": RECONSTRUCTION_ROOT + "/plot_fertilized.png",
}
const FERTILIZER_MARK_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// Reuse only the pale nutrient grains in the approved fertilized art.
	// Its opaque brown soil must never cover a watered bed underneath.
	float side = mix(0.20, 0.12, clamp((UV.y - 0.20) / 0.60, 0.0, 1.0));
	float soil = step(side, UV.x) * step(UV.x, 1.0 - side) * step(0.22, UV.y) * step(UV.y, 0.83);
	float grain = smoothstep(0.48, 0.64, source.g) * (1.0 - smoothstep(0.24, 0.36, source.r - source.g));
	COLOR = vec4(source.rgb, source.a * grain * soil);
}
"""

const DRY_INNER := Color("8b5c38")
const DRY_LIP := Color("a66f43")
const DRY_SHADOW := Color(0.16, 0.09, 0.05, 0.31)
const DRY_FURROW := Color(0.31, 0.19, 0.12, 0.42)
const WET_INNER := Color("5a3c2d")
const WET_LIP := Color("78533c")
const WET_FURROW := Color("2d211b")
const UNTILLED_INNER := Color(0.64, 0.43, 0.25, 0.39)
const UNTILLED_LIP := Color(0.76, 0.55, 0.32, 0.50)
const UNTILLED_FURROW := Color(0.38, 0.25, 0.15, 0.20)

var plot_id := 1
var state := "tilled_dry"
var selected := false
var fertilized := false
var visual_polygon := PackedVector2Array()
var inner_polygon := PackedVector2Array()
var reconstruction_texture: Texture2D
var fertilizer_marks: Sprite2D
static var _nutrient_shader: Shader


func configure(id_value: int, state_value: String, selected_value := false, fertilized_value := false) -> void:
	plot_id = id_value
	state = state_value
	selected = selected_value
	fertilized = fertilized_value
	visual_polygon = PixelMap.visual_plot_polygon(plot_id)
	inner_polygon = _inset_polygon(visual_polygon, 0.055)
	reconstruction_texture = load(String(STATE_TEXTURES.get(state, STATE_TEXTURES["untilled"])))
	_configure_fertilizer_marks()
	set_meta("selection_is_outline_only", true)
	set_meta("soil_state", state)
	set_meta("fertilizer_visible", fertilized and state != "untilled")
	queue_redraw()


func _draw() -> void:
	if reconstruction_texture != null:
		var target_rect := PixelMap.visual_plot_rect(plot_id)
		draw_texture_rect(reconstruction_texture, target_rect, false)
		if selected:
			_draw_selection(PixelMap.visual_interaction_polygon(plot_id))
		return
	if visual_polygon.is_empty():
		if selected:
			_draw_selection(Geometry.cell_polygon(Geometry.grid_coord(plot_id).x, Geometry.grid_coord(plot_id).y))
		return
	if state == "untilled":
		_draw_untilled()
		if selected:
			_draw_selection(visual_polygon)
		return
	var wet := state == "tilled_wet"
	var lip := WET_LIP if wet else DRY_LIP
	var inner := WET_INNER if wet else DRY_INNER
	var furrow := WET_FURROW if wet else DRY_FURROW
	var shadow := PackedVector2Array()
	for point in visual_polygon:
		shadow.append(point + Vector2(0, 4.0))
	draw_colored_polygon(shadow, DRY_SHADOW)
	draw_colored_polygon(visual_polygon, lip)
	draw_colored_polygon(inner_polygon, inner)
	_draw_edge_variation(lip)
	_draw_furrows(furrow, wet)
	if fertilized:
		_draw_fertilizer()
	if wet:
		_draw_moisture_highlights()
	if selected:
		_draw_selection(visual_polygon)


func _configure_fertilizer_marks() -> void:
	if fertilizer_marks != null:
		fertilizer_marks.free()
		fertilizer_marks = null
	if not fertilized or state == "untilled":
		return
	var source := load(String(STATE_TEXTURES["fertilized"])) as Texture2D
	if source == null:
		return
	fertilizer_marks = Sprite2D.new()
	fertilizer_marks.name = "PersistentNutrientGrains"
	fertilizer_marks.texture = source
	fertilizer_marks.centered = false
	var target_rect := PixelMap.visual_plot_rect(plot_id)
	fertilizer_marks.position = target_rect.position
	fertilizer_marks.scale = target_rect.size / source.get_size()
	if _nutrient_shader == null:
		_nutrient_shader = Shader.new()
		_nutrient_shader.code = FERTILIZER_MARK_SHADER
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _nutrient_shader
	fertilizer_marks.material = shader_material
	add_child(fertilizer_marks)


func _draw_untilled() -> void:
	var shadow := PackedVector2Array()
	for point in visual_polygon:
		shadow.append(point + Vector2(0, 3.2))
	draw_colored_polygon(shadow, Color(0.18, 0.10, 0.05, 0.18))
	draw_colored_polygon(visual_polygon, UNTILLED_LIP)
	draw_colored_polygon(inner_polygon, UNTILLED_INNER)
	var coord := Geometry.grid_coord(plot_id)
	for band in range(3):
		var points := PackedVector2Array()
		var local_v := 0.27 + float(band) * 0.23
		for step in range(9):
			var point := Geometry.bed_point(coord.x, coord.y, 0.10 + float(step) * 0.10, local_v)
			point.y += sin(float(step + plot_id + band) * 1.45) * 0.7
			points.append(point)
		draw_polyline(points, UNTILLED_FURROW, 1.0, true)
	_draw_soil_clods()
	_draw_edge_variation(Color(UNTILLED_LIP, 0.38))


func _organic_polygon(base: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var center := _centroid(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7300 + seed_value * 977
	for edge_index in range(base.size()):
		var a := base[edge_index]
		var b := base[(edge_index + 1) % base.size()]
		var edge := b - a
		var normal := Vector2(-edge.y, edge.x).normalized()
		if normal.dot(center - (a + b) * 0.5) < 0.0:
			normal = -normal
		for segment in range(9):
			var t := 0.045 + float(segment) * 0.114
			var point := a.lerp(b, t)
			var rounding := 6.5 if segment in [0, 8] else (2.0 if segment in [1, 7] else 0.0)
			point = point.lerp(center, rounding / maxf(1.0, point.distance_to(center)))
			var noise := rng.randf_range(-4.1, 4.1)
			if segment in [0, 8]:
				noise *= 0.45
			result.append(point + normal * noise)
	return result


func _inset_polygon(source: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center := _centroid(source)
	var result := PackedVector2Array()
	for point in source:
		result.append(point.lerp(center, amount))
	return result


func _draw_furrows(color: Color, wet: bool) -> void:
	var coord := Geometry.grid_coord(plot_id)
	for band in range(4):
		var local_v := 0.22 + float(band) * 0.18
		var points := PackedVector2Array()
		for step in range(9):
			var local_u := 0.10 + float(step) * 0.10
			var point := Geometry.bed_point(coord.x, coord.y, local_u, local_v)
			point.y += sin(float(step + band + plot_id) * 1.7) * 0.9
			points.append(point)
		draw_polyline(points, color, 1.6 if wet else 1.15, true)
		if wet:
			draw_polyline(points, Color(0.78, 0.73, 0.64, 0.09), 0.8, true)


func _draw_soil_clods() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14500 + plot_id * 211
	var coord := Geometry.grid_coord(plot_id)
	for index in range(14):
		var point := Geometry.bed_point(coord.x, coord.y, rng.randf_range(0.10, 0.90), rng.randf_range(0.16, 0.84))
		var radius := rng.randf_range(0.7, 1.8)
		draw_circle(point, radius, Color(0.30, 0.18, 0.10, rng.randf_range(0.16, 0.30)))


func _draw_edge_variation(lip: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11000 + plot_id * 131
	for index in range(28):
		var edge_index := rng.randi_range(0, visual_polygon.size() - 1)
		var a := visual_polygon[edge_index]
		var b := visual_polygon[(edge_index + 1) % visual_polygon.size()]
		var point := a.lerp(b, rng.randf_range(0.15, 0.85))
		var radius := rng.randf_range(1.2, 3.5)
		var tone := lip.lightened(rng.randf_range(-0.08, 0.12))
		draw_circle(point + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.0, 2.0)), radius, tone)
	for index in range(4):
		var edge_index := rng.randi_range(0, visual_polygon.size() - 1)
		var point := visual_polygon[edge_index]
		draw_circle(point, rng.randf_range(1.0, 2.1), Color("b7a07a"))
		draw_circle(point + Vector2(-0.4, -0.5), rng.randf_range(0.35, 0.75), Color(0.85, 0.79, 0.65, 0.75))
	if plot_id % 3 == 1:
		var weed_origin := visual_polygon[(plot_id * 5) % visual_polygon.size()] + Vector2(0, 2)
		for offset in [-3.0, 0.0, 3.0]:
			draw_line(weed_origin + Vector2(offset, 1), weed_origin + Vector2(offset * 0.65, -4.0 - absf(offset) * 0.4), Color("557c31"), 1.2, true)


func _draw_fertilizer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19000 + plot_id * 313
	var coord := Geometry.grid_coord(plot_id)
	for index in range(16):
		var point := Geometry.bed_point(coord.x, coord.y, rng.randf_range(0.12, 0.88), rng.randf_range(0.18, 0.82))
		draw_circle(point, rng.randf_range(0.8, 1.5), Color("d5b45b"))


func _draw_moisture_highlights() -> void:
	var coord := Geometry.grid_coord(plot_id)
	for index in range(3):
		var v := 0.30 + index * 0.18
		var a := Geometry.bed_point(coord.x, coord.y, 0.18, v)
		var b := Geometry.bed_point(coord.x, coord.y, 0.72, v)
		draw_line(a, b, Color(0.82, 0.76, 0.68, 0.10), 1.0, true)


func _draw_selection(polygon: PackedVector2Array) -> void:
	if polygon.is_empty():
		return
	# An outline only: the center pixels remain the truthful current soil state.
	var closed := PackedVector2Array(polygon)
	closed.append(polygon[0])
	draw_polyline(closed, Color(0.72, 0.42, 0.14, 0.28), 6.4, true)
	draw_polyline(closed, Color("ffe7a3"), 2.4, true)


func _centroid(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point in polygon:
		result += point
	return result / float(polygon.size())
