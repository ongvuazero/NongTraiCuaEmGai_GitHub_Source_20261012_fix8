extends RefCounted
class_name FieldProjectionV71

const MANIFEST_PATH := "res://v7/data/field_projection_manifest_v7_1.json"
const MODE_PERSPECTIVE := "AUTHORED_PERSPECTIVE_QUAD"
const MODE_DIMETRIC := "DIMETRIC_2_1"
const EPSILON := 0.001

static var _manifest_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		assert(file != null, "Missing V7.1 projection manifest")
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "Invalid V7.1 projection manifest")
		_manifest_cache = (parsed as Dictionary).duplicate(true)
	return _manifest_cache


static func columns() -> int:
	return int(manifest()["logical_grid"]["columns"])


static func rows() -> int:
	return int(manifest()["logical_grid"]["rows"])


static func projection_value(key: String, fallback: float = 0.0) -> float:
	return float(manifest()["projection"].get(key, fallback))


static func quad_point(key: String) -> Vector2:
	var raw: Array = manifest()["projection"]["quad"][key]
	return Vector2(float(raw[0]), float(raw[1]))


static func screen_point_from_uv(u: float, v: float) -> Vector2:
	var top := quad_point("tl").lerp(quad_point("tr"), u)
	var bottom := quad_point("bl").lerp(quad_point("br"), u)
	return top.lerp(bottom, v)


static func cell_polygon(column: int, row: int, grid_columns: int = -1, grid_rows: int = -1) -> PackedVector2Array:
	var count_x := columns() if grid_columns <= 0 else grid_columns
	var count_y := rows() if grid_rows <= 0 else grid_rows
	var u0 := float(column) / float(count_x)
	var u1 := float(column + 1) / float(count_x)
	var v0 := float(row) / float(count_y)
	var v1 := float(row + 1) / float(count_y)
	return PackedVector2Array([
		screen_point_from_uv(u0, v0),
		screen_point_from_uv(u1, v0),
		screen_point_from_uv(u1, v1),
		screen_point_from_uv(u0, v1),
	])


static func plot_polygon(column: int, row: int, grid_columns: int = -1, grid_rows: int = -1, inset_ratio: float = -1.0) -> PackedVector2Array:
	var cell := cell_polygon(column, row, grid_columns, grid_rows)
	var center := polygon_center(cell)
	var inset := projection_value("plot_inset_ratio", 0.12) if inset_ratio < 0.0 else inset_ratio
	var result := PackedVector2Array()
	for point in cell:
		result.append(point.lerp(center, inset))
	return result


static func selection_polygon(column: int, row: int, grid_columns: int = -1, grid_rows: int = -1) -> PackedVector2Array:
	return plot_polygon(column, row, grid_columns, grid_rows, maxf(0.04, projection_value("plot_inset_ratio", 0.12) - 0.035))


static func crop_anchor(column: int, row: int, grid_columns: int = -1, grid_rows: int = -1) -> Vector2:
	var count_x := columns() if grid_columns <= 0 else grid_columns
	var count_y := rows() if grid_rows <= 0 else grid_rows
	var u := (float(column) + 0.5) / float(count_x)
	var local_v := projection_value("crop_anchor_v", 0.55)
	var v := (float(row) + local_v) / float(count_y)
	return screen_point_from_uv(u, v)


static func foot_anchor(column: int, row: int, grid_columns: int = -1, grid_rows: int = -1) -> Vector2:
	return crop_anchor(column, row, grid_columns, grid_rows)


static func perspective_scale(v: float) -> float:
	return lerpf(projection_value("far_scale", 0.78), projection_value("near_scale", 1.0), clampf(v, 0.0, 1.0))


static func perspective_scale_for_row(row: int, grid_rows: int = -1) -> float:
	var count_y := rows() if grid_rows <= 0 else grid_rows
	return perspective_scale((float(row) + projection_value("crop_anchor_v", 0.55)) / float(count_y))


static func plot_id(column: int, row: int, grid_columns: int = -1) -> int:
	var count_x := columns() if grid_columns <= 0 else grid_columns
	return row * count_x + column + 1


static func grid_coord(plot_id_value: int) -> Vector2i:
	var zero_based := plot_id_value - 1
	return Vector2i(zero_based % columns(), zero_based / columns())


static func hit_test_plot(screen_point: Vector2) -> int:
	# Iterating in plot-id order is the deterministic shared-edge tie breaker.
	for row in range(rows()):
		for column in range(columns()):
			if Geometry2D.is_point_in_polygon(screen_point, cell_polygon(column, row)):
				return plot_id(column, row)
	return -1


static func polygon_center(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point in polygon:
		result += point
	return result / float(polygon.size())


static func normalized_depth_for_row(row: int, grid_rows: int = -1) -> float:
	var count_y := rows() if grid_rows <= 0 else grid_rows
	return (float(row) + projection_value("crop_anchor_v", 0.55)) / float(count_y)


static func depth_key(ground_contact: Vector2) -> float:
	return ground_contact.y


static func dimetric_screen_point(gx: float, gy: float, origin: Vector2, elevation_px: float = 0.0) -> Vector2:
	var spec: Dictionary = manifest()["future_dimetric_2_1"]
	var tile_width := float(spec["tile_width"])
	var tile_height := float(spec["tile_height"])
	return Vector2(
		origin.x + (gx - gy) * tile_width * 0.5,
		origin.y + (gx + gy) * tile_height * 0.5 - elevation_px
	)
