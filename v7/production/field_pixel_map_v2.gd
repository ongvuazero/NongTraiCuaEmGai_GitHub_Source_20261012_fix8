extends RefCounted
class_name FieldPixelMapV2

const MANIFEST_PATH := "res://assets/field_reconstruction_v2/10_ASSEMBLY/assembly_manifest_v2_pixel_mapped.json"
const VISUAL_FIELD_CENTER_X := 620.0
const VISUAL_ROW_SIZE := [Vector2(0.95, 0.95), Vector2.ONE, Vector2(1.06, 1.06)]
const VISUAL_ROW_SPACING := [0.96, 1.0, 1.03]
const VISUAL_ROW_Y_OFFSET := [-4.0, 0.0, 3.0]

# Canonical click footprint measured from the CURRENT approved runtime bed
# texture. Values are normalized inside visual_plot_rect and intentionally stay
# inside the grass/lip border, so the surrounding lawn remains a dead gutter.
const INTERACTION_FOOTPRINT := [
	Vector2(0.17, 0.19),
	Vector2(0.83, 0.19),
	Vector2(0.90, 0.73),
	Vector2(0.84, 0.82),
	Vector2(0.16, 0.82),
	Vector2(0.10, 0.73),
]

static var _manifest_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		assert(file != null, "Missing Field V2 pixel map")
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "Invalid Field V2 pixel map")
		_manifest_cache = (parsed as Dictionary).duplicate(true)
	return _manifest_cache


static func plot(plot_id: int) -> Dictionary:
	return Dictionary((manifest()["plots"] as Array)[clampi(plot_id - 1, 0, 11)])


static func plot_polygon(plot_id: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for raw_point in plot(plot_id)["poly_runtime_1280x720"]:
		result.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return result


static func plot_rect(plot_id: int) -> Rect2:
	var raw: Dictionary = plot(plot_id)["bbox_runtime_1280x720"]
	return Rect2(float(raw["x"]), float(raw["y"]), float(raw["w"]), float(raw["h"]))


static func visual_plot_rect(plot_id: int) -> Rect2:
	var source := plot_rect(plot_id)
	var row := clampi((plot_id - 1) / 4, 0, 2)
	var size_scale: Vector2 = VISUAL_ROW_SIZE[row]
	var target_size := source.size * size_scale
	var source_center_x := source.get_center().x
	var target_center_x := VISUAL_FIELD_CENTER_X + (source_center_x - VISUAL_FIELD_CENTER_X) * float(VISUAL_ROW_SPACING[row])
	var target_bottom := source.end.y + float(VISUAL_ROW_Y_OFFSET[row])
	return Rect2(Vector2(target_center_x - target_size.x * 0.5, target_bottom - target_size.y), target_size)


static func visual_plot_polygon(plot_id: int) -> PackedVector2Array:
	var source_rect := plot_rect(plot_id)
	var target_rect := visual_plot_rect(plot_id)
	var result := PackedVector2Array()
	for point in plot_polygon(plot_id):
		var normalized := Vector2(
			(point.x - source_rect.position.x) / source_rect.size.x,
			(point.y - source_rect.position.y) / source_rect.size.y
		)
		result.append(target_rect.position + normalized * target_rect.size)
	return result


static func visual_interaction_polygon(plot_id: int) -> PackedVector2Array:
	var target_rect := visual_plot_rect(plot_id)
	var result := PackedVector2Array()
	for normalized_point in INTERACTION_FOOTPRINT:
		result.append(target_rect.position + Vector2(normalized_point) * target_rect.size)
	return result


static func ground_anchor(plot_id: int) -> Vector2:
	var raw: Array = plot(plot_id)["ground_anchor_runtime_1280x720"]
	return Vector2(float(raw[0]), float(raw[1]))


static func visual_ground_anchor(plot_id: int) -> Vector2:
	var source_rect := plot_rect(plot_id)
	var target_rect := visual_plot_rect(plot_id)
	var source_anchor := ground_anchor(plot_id)
	var normalized := Vector2(
		(source_anchor.x - source_rect.position.x) / source_rect.size.x,
		(source_anchor.y - source_rect.position.y) / source_rect.size.y
	)
	return target_rect.position + normalized * target_rect.size



static func visual_crop_anchor(plot_id: int) -> Vector2:
	# Crop sprites use visible-pixel bottom-center pivots.
	# Anchor from the CURRENT visual bed, not the old reconstruction manifest point.
	var rect := visual_plot_rect(plot_id)
	var row := clampi((plot_id - 1) / 4, 0, 2)
	var y_ratio: float = float([0.80, 0.80, 0.79][row])
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * y_ratio)


static func farmer_feet(plot_id: int) -> Vector2:
	var anchor := visual_ground_anchor(plot_id)
	var col := (plot_id - 1) % 4
	if col > 0:
		var left_anchor := visual_ground_anchor(plot_id - 1)
		return Vector2((left_anchor.x + anchor.x) * 0.5 - 10.0, anchor.y + 15.0)
	var rect := visual_plot_rect(plot_id)
	return Vector2(rect.position.x - 38.0, anchor.y + 15.0)


static func ui_rect(element_id: String) -> Rect2:
	var raw: Dictionary = manifest()["ui_elements"][element_id]["runtime_rect"]
	return Rect2(float(raw["x"]), float(raw["y"]), float(raw["w"]), float(raw["h"]))
