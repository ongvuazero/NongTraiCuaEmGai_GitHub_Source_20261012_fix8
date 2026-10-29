extends Node2D
class_name FieldDebugOverlay

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const Walkability = preload("res://v7/production/field_walkability.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
var mode := ""
var hitboxes: Dictionary = {}
var gutter_points := PackedVector2Array()

func set_hitboxes(value: Dictionary) -> void:
	hitboxes = value.duplicate(true)
	queue_redraw()

func set_mode(value: String) -> void:
	mode = value
	queue_redraw()

func set_gutter_points(value: PackedVector2Array) -> void:
	gutter_points = value
	queue_redraw()

func _draw() -> void:
	if mode.is_empty(): return
	if mode == "hitboxes":
		for plot_id in hitboxes:
			var rect := Rect2(hitboxes[plot_id])
			draw_rect(rect, Color(0.15, 0.82, 1.0, 0.20), true)
			draw_rect(rect, Color(0.15, 0.92, 1.0, 0.92), false, 2.0)
			draw_string(ThemeDB.fallback_font, rect.get_center() + Vector2(-13, 5), "P%02d" % int(plot_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		return
	if mode == "hit_polygons":
		for plot_id in range(1, 13):
			var polygon := PixelMap.visual_interaction_polygon(plot_id)
			draw_colored_polygon(polygon, Color(0.10, 0.78, 1.0, 0.32))
			draw_polyline(_closed(polygon), Color(0.15, 0.92, 1.0, 0.96), 2.0, true)
			var center := _centroid(polygon)
			draw_string(ThemeDB.fallback_font, center + Vector2(-13, 5), "P%02d" % plot_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		for point in gutter_points:
			draw_circle(point, 5.0, Color(0.92, 0.16, 0.12, 0.92))
			draw_line(point + Vector2(-7, -7), point + Vector2(7, 7), Color.WHITE, 2.0, true)
			draw_line(point + Vector2(-7, 7), point + Vector2(7, -7), Color.WHITE, 2.0, true)
		return
	for row in range(Geometry.rows()):
		for column in range(Geometry.columns()):
			var plot_id := Geometry.plot_id(column, row)
			var cell := Geometry.cell_polygon(column, row)
			var bed := Geometry.bed_polygon(column, row)
			match mode:
				"cells":
					draw_polyline(_closed(cell), Color("74e4ff"), 2.0, true)
					draw_string(ThemeDB.fallback_font, Geometry.cell_center(column, row), "P%02d" % plot_id, HORIZONTAL_ALIGNMENT_CENTER, 40, 13, Color.WHITE)
				"beds":
					draw_colored_polygon(bed, Color(1.0, 0.22, 0.12, 0.24))
					draw_polyline(_closed(bed), Color("ff9a72"), 2.0, true)
				"walkability":
					draw_polyline(_closed(cell), Color(0.25, 0.95, 0.44, 0.78), 3.0, true)
					draw_colored_polygon(bed, Color(0.95, 0.16, 0.12, 0.42))
				"anchors":
					var anchor := Geometry.crop_anchor(column, row)
					draw_circle(anchor, 5.0, Color("fff26e"))
					var lane := Walkability.standing_lane(plot_id)
					draw_circle(lane, 5.0, Color("55ff88"))
					draw_line(anchor, lane, Color(1, 1, 1, 0.65), 1.0, true)

func _closed(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array(polygon)
	result.append(polygon[0])
	return result


func _centroid(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point in polygon:
		result += point
	return result / float(polygon.size())
