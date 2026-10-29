extends RefCounted
class_name FieldProjectionV72

const MANIFEST_PATH := "res://v7/data/field_visual_manifest_v7_2.json"
const MODE := "AUTHORED_PERSPECTIVE_QUAD_WITH_DEPTH_CURVE"

static var _manifest_cache: Dictionary = {}
static var _plot_offsets: Dictionary = {}


static func set_plot_offsets(offsets: Dictionary) -> void:
	_plot_offsets = offsets.duplicate()


static func _plot_offset(column: int, row: int) -> Vector2:
	return Vector2(_plot_offsets.get(plot_id(column, row), Vector2.ZERO))


static func _offset_polygon(polygon: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		result.append(point + offset)
	return result


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		assert(file != null, "Missing V7.2 visual manifest")
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "Invalid V7.2 visual manifest")
		_manifest_cache = (parsed as Dictionary).duplicate(true)
	return _manifest_cache


static func projection() -> Dictionary:
	return manifest()["projection"]


static func columns() -> int:
	return int(manifest()["logical_grid"]["columns"])


static func rows() -> int:
	return int(manifest()["logical_grid"]["rows"])


static func value(key: String, fallback: float = 0.0) -> float:
	return float(projection().get(key, fallback))


static func quad_point(key: String) -> Vector2:
	var raw: Array = projection()["quad"][key]
	return Vector2(float(raw[0]), float(raw[1]))


static func projected_v(logical_v: float) -> float:
	return pow(clampf(logical_v, 0.0, 1.0), value("depth_exponent", 1.28))


static func screen_point_from_uv(u: float, logical_v: float) -> Vector2:
	var top := quad_point("tl").lerp(quad_point("tr"), u)
	var bottom := quad_point("bl").lerp(quad_point("br"), u)
	return top.lerp(bottom, projected_v(logical_v))


static func cell_polygon(column: int, row: int) -> PackedVector2Array:
	return _offset_polygon(uv_polygon(
		float(column) / columns(),
		float(column + 1) / columns(),
		float(row) / rows(),
		float(row + 1) / rows()
	), _plot_offset(column, row))


static func bed_uv_bounds(column: int, row: int) -> Rect2:
	var margin_u := value("bed_margin_u", 0.075)
	var margin_v := value("bed_margin_v", 0.13)
	var u0 := (float(column) + margin_u) / columns()
	var u1 := (float(column + 1) - margin_u) / columns()
	var v0 := (float(row) + margin_v) / rows()
	var v1 := (float(row + 1) - margin_v) / rows()
	return Rect2(u0, v0, u1 - u0, v1 - v0)


static func bed_polygon(column: int, row: int) -> PackedVector2Array:
	var bounds := bed_uv_bounds(column, row)
	return _offset_polygon(uv_polygon(bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y), _plot_offset(column, row))


static func bed_band_polygon(column: int, row: int, local_v: float, local_half_width: float = 0.025) -> PackedVector2Array:
	var bounds := bed_uv_bounds(column, row)
	var v0 := bounds.position.y + bounds.size.y * clampf(local_v - local_half_width, 0.0, 1.0)
	var v1 := bounds.position.y + bounds.size.y * clampf(local_v + local_half_width, 0.0, 1.0)
	return _offset_polygon(uv_polygon(bounds.position.x, bounds.end.x, v0, v1), _plot_offset(column, row))


static func bed_point(column: int, row: int, local_u: float, local_v: float) -> Vector2:
	var bounds := bed_uv_bounds(column, row)
	return screen_point_from_uv(
		bounds.position.x + bounds.size.x * local_u,
		bounds.position.y + bounds.size.y * local_v
	) + _plot_offset(column, row)


static func crop_anchor(column: int, row: int) -> Vector2:
	return bed_point(column, row, value("crop_anchor_local_u", 0.5), value("crop_anchor_local_v", 0.68))


static func foot_anchor(column: int, row: int) -> Vector2:
	return crop_anchor(column, row)


static func mature_target_height(column: int, row: int) -> float:
	var bounds := bed_uv_bounds(column, row)
	var local_v := value("crop_anchor_local_v", 0.68)
	var logical_depth := bounds.position.y + bounds.size.y * local_v
	var depth := projected_v(logical_depth)
	var far_height := value("mature_target_height_far", 62.0)
	var middle_height := value("mature_target_height_mid", (far_height + value("mature_target_height_near", 84.0)) * 0.5)
	var near_height := value("mature_target_height_near", 84.0)
	if depth <= 0.5:
		return lerpf(far_height, middle_height, depth * 2.0)
	return lerpf(middle_height, near_height, (depth - 0.5) * 2.0)


static func stage_multiplier(stage: int) -> float:
	var multipliers: Array = projection()["stage_multipliers"]
	return float(multipliers[clampi(stage, 0, multipliers.size() - 1)])


static func crop_target_height(column: int, row: int, stage: int) -> float:
	return mature_target_height(column, row) * stage_multiplier(stage)


static func row_screen_height(row: int) -> float:
	var top_point := screen_point_from_uv(0.5, float(row) / rows())
	var bottom_point := screen_point_from_uv(0.5, float(row + 1) / rows())
	return bottom_point.y - top_point.y


static func plot_id(column: int, row: int) -> int:
	return row * columns() + column + 1


static func grid_coord(plot_id_value: int) -> Vector2i:
	var zero_based := plot_id_value - 1
	return Vector2i(zero_based % columns(), zero_based / columns())


static func cell_center(column: int, row: int) -> Vector2:
	return polygon_center(cell_polygon(column, row))


static func hit_test_plot(screen_point: Vector2) -> int:
	for row in range(rows()):
		for column in range(columns()):
			if Geometry2D.is_point_in_polygon(screen_point, cell_polygon(column, row)):
				return plot_id(column, row)
	return -1


static func polygon_center(polygon: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	return center / polygon.size()


static func uv_polygon(u0: float, u1: float, v0: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([
		screen_point_from_uv(u0, v0),
		screen_point_from_uv(u1, v0),
		screen_point_from_uv(u1, v1),
		screen_point_from_uv(u0, v1),
	])


static func depth_key(ground_contact: Vector2) -> float:
	return ground_contact.y
