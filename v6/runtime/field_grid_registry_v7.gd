extends RefCounted

const MANIFEST_PATH := "res://v6/data/field/field_grid_manifest_v7.json"

static var _manifest_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		assert(file != null, "Missing V7 field grid manifest")
		var parsed = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "Invalid V7 field grid manifest")
		_manifest_cache = parsed
	return _manifest_cache


static func plots() -> Array:
	return manifest().get("plots", [])


static func plot_record(plot_id: int) -> Dictionary:
	for record in plots():
		if int(record.get("plot_id", 0)) == plot_id:
			return record
	return {}


static func rect_from(values: Array) -> Rect2:
	assert(values.size() == 4, "V7 field rect requires four values")
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


static func shape_rect(record: Dictionary, key: String) -> Rect2:
	var shape: Dictionary = record.get(key, {})
	assert(String(shape.get("type", "")) == "rect", "V7 current field contract expects rect shapes")
	return rect_from(shape.get("points_or_rect", []))


static func validate_against_state(field_plots: Array) -> void:
	var records := plots()
	assert(records.size() == field_plots.size(), "Field manifest/state plot counts differ")
	var seen: Dictionary = {}
	for record in records:
		var plot_id := int(record.get("plot_id", 0))
		assert(plot_id > 0 and not seen.has(plot_id), "Field manifest plot ids must be unique")
		seen[plot_id] = true
		assert(shape_rect(record, "visible_shape").has_area(), "Plot visible rect must have area")
		assert(shape_rect(record, "interaction_shape").has_area(), "Plot interaction rect must have area")
	for plot in field_plots:
		assert(seen.has(int(plot.get("id", 0))), "GameState plot missing from field manifest")
