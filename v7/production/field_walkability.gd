extends RefCounted
class_name FieldWalkability

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")

static func is_walkable(point: Vector2) -> bool:
	var quad := PackedVector2Array([Geometry.quad_point("tl"), Geometry.quad_point("tr"), Geometry.quad_point("br"), Geometry.quad_point("bl")])
	if not Geometry2D.is_point_in_polygon(point, quad):
		return false
	for row in range(Geometry.rows()):
		for column in range(Geometry.columns()):
			if Geometry2D.is_point_in_polygon(point, Geometry.bed_polygon(column, row)):
				return false
	return true

static func standing_lane(plot_id: int) -> Vector2:
	var coord := Geometry.grid_coord(plot_id)
	var bed := Geometry.bed_polygon(coord.x, coord.y)
	var top := (bed[0] + bed[1]) * 0.5 + Vector2(0, -15)
	var right := (bed[1] + bed[2]) * 0.5 + Vector2(17, 3)
	var bottom := (bed[2] + bed[3]) * 0.5 + Vector2(0, 18)
	var left := (bed[3] + bed[0]) * 0.5 + Vector2(-17, 3)
	var candidates := [bottom, left, right, top]
	if coord.y == Geometry.rows() - 1:
		candidates = [top, left, right, bottom]
	for point in candidates:
		if is_walkable(point):
			return point
	return Geometry.cell_center(coord.x, coord.y)

static func interaction_distance(plot_id: int, actor_foot: Vector2) -> float:
	return actor_foot.distance_to(standing_lane(plot_id))
