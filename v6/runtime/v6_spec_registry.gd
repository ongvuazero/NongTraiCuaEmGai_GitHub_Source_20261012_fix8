extends RefCounted
class_name V6SpecRegistry

const SCREEN_SPEC_PATHS := {
	"title": "res://v6/data/screen_specs/title_screen_spec_v6_1.json",
	"save": "res://v6/data/screen_specs/save_screen_spec_v6_1.json",
	"home_hub": "res://v6/data/screen_specs/home_hub_screen_spec_v6_1.json",
}

const ANCHOR_PATHS := {
	"title": "res://v6/data/anchors/title_anchors_v6_1.json",
	"save": "res://v6/data/anchors/save_anchors_v6_1.json",
	"home_hub": "res://v6/data/anchors/home_hub_anchors_v6_1.json",
}

const GEOMETRY_PATHS := {
	"title": "res://v6/data/screen_specs/title_screen_spec_v6_3.json",
	"save": "res://v6/data/screen_specs/save_screen_spec_v6_3.json",
	"home_hub": "res://v6/data/screen_specs/home_hub_screen_spec_v6_3.json",
}

const PARITY_SPEC_PATHS := {
	"title": "res://v6/data/screen_specs/title_screen_spec_v6_4.json",
	"save": "res://v6/data/screen_specs/save_dynamic_layout_v6_4.json",
	"home_hub": "res://v6/data/screen_specs/home_hub_screen_spec_v6_4.json",
}

const REFERENCE_PLATE_SPEC_PATHS := {
	"title": "res://v6/data/screen_specs/title_screen_spec_v6_5.json",
	"save": "res://v6/data/screen_specs/save_screen_spec_v6_6.json",
	"home_hub": "res://v6/data/screen_specs/home_hub_screen_spec_v6_5.json",
}

const PARITY_FIXTURE_PATH := "res://v6/qa/parity_fixture_v6_4.json"

const BBOX_MANIFEST_PATH := "res://v6/data/manifests/phase1_visible_bbox_manifest_v6_3.json"


static func load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "Missing V6 data file: %s" % path)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "Invalid V6 JSON object: %s" % path)
	return parsed


static func screen(screen_id: String) -> Dictionary:
	assert(SCREEN_SPEC_PATHS.has(screen_id), "Unknown V6 screen spec: %s" % screen_id)
	return load_json(SCREEN_SPEC_PATHS[screen_id])


static func anchors(screen_id: String) -> Dictionary:
	assert(ANCHOR_PATHS.has(screen_id), "Unknown V6 anchor registry: %s" % screen_id)
	return load_json(ANCHOR_PATHS[screen_id])


static func geometry(screen_id: String) -> Dictionary:
	assert(GEOMETRY_PATHS.has(screen_id), "Unknown V6.3 geometry spec: %s" % screen_id)
	return load_json(GEOMETRY_PATHS[screen_id])


static func parity_spec(screen_id: String) -> Dictionary:
	assert(PARITY_SPEC_PATHS.has(screen_id), "Unknown V6.4 parity spec: %s" % screen_id)
	return load_json(PARITY_SPEC_PATHS[screen_id])


static func reference_plate_spec(screen_id: String) -> Dictionary:
	assert(REFERENCE_PLATE_SPEC_PATHS.has(screen_id), "Unknown V6.5 reference-plate spec: %s" % screen_id)
	return load_json(REFERENCE_PLATE_SPEC_PATHS[screen_id])


static func parity_fixture() -> Dictionary:
	return load_json(PARITY_FIXTURE_PATH)


static func is_parity_mode() -> bool:
	return OS.get_environment("MSF_PARITY_MODE") == "1"


static func dictionary_rect(spec: Dictionary, group: String, rect_id: String) -> Rect2:
	var rects: Dictionary = spec.get(group, {})
	assert(rects.has(rect_id), "Missing V6.4 rect: %s/%s" % [group, rect_id])
	return rect_from(rects[rect_id])


static func visible_rect(spec: Dictionary, rect_id: String, group: String = "visible_rects") -> Rect2:
	var rects: Dictionary = spec.get(group, {})
	assert(rects.has(rect_id), "Missing V6.3 visible rect: %s" % rect_id)
	return rect_from(rects[rect_id])


static func foot_anchor(spec: Dictionary, anchor_id: String) -> Vector2:
	var anchors_v6_3: Dictionary = spec.get("foot_anchors", {})
	assert(anchors_v6_3.has(anchor_id), "Missing V6.3 foot anchor: %s" % anchor_id)
	return point_from(anchors_v6_3[anchor_id])


static func bbox_entry(role: String) -> Dictionary:
	var manifest := load_json(BBOX_MANIFEST_PATH)
	for candidate in manifest.get("assets", []):
		if String(candidate.get("role", "")) == role:
			return candidate
	assert(false, "Missing V6.3 bbox role: %s" % role)
	return {}


static func compensated_rect(role: String) -> Rect2:
	var record := bbox_entry(role)
	assert(record.has("compensated_node_rect"), "Missing compensated node rect: %s" % role)
	return rect_from(record["compensated_node_rect"])


static func uniform_actor_rect(role: String, foot: Vector2) -> Rect2:
	var record := bbox_entry(role)
	var canvas: Array = record["canvas_size"]
	var alpha_bbox: Array = record["alpha_bbox"]
	var scale := float(record["uniform_scale"])
	var visible_width := float(alpha_bbox[2]) * scale
	var target_height := float(record["target_visible_height"])
	var visible_top_left := Vector2(foot.x - visible_width * 0.5, foot.y - target_height)
	var node_position := visible_top_left - Vector2(float(alpha_bbox[0]), float(alpha_bbox[1])) * scale
	return Rect2(node_position, Vector2(float(canvas[0]), float(canvas[1])) * scale)


static func rect_from(value: Array) -> Rect2:
	assert(value.size() == 4, "V6 rect must contain x, y, width, height")
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func point_from(value: Array) -> Vector2:
	assert(value.size() == 2, "V6 point must contain x and y")
	return Vector2(float(value[0]), float(value[1]))


static func entry(entries: Array, entry_id: String) -> Dictionary:
	for candidate in entries:
		if String(candidate.get("id", "")) == entry_id:
			return candidate
	assert(false, "Missing V6 registry entry: %s" % entry_id)
	return {}


static func ui_rect(spec: Dictionary, rect_id: String) -> Rect2:
	return rect_from(entry(spec.get("ui_rects", []), rect_id)["px"])


static func control_rect(spec: Dictionary, control_id: String) -> Rect2:
	return rect_from(entry(spec.get("controls", []), control_id)["rect_px"])


static func overlay_rect(spec: Dictionary, overlay_id: String) -> Rect2:
	return rect_from(entry(spec.get("overlays", []), overlay_id)["rect_px"])


static func anchor_point(registry: Dictionary, anchor_id: String) -> Vector2:
	return point_from(entry(registry.get("anchors", []), anchor_id)["px"])


static func named_rect(registry: Dictionary, rect_id: String) -> Rect2:
	return rect_from(entry(registry.get("rects", []), rect_id)["px"])


static func rect_at_feet(feet: Vector2, size: Vector2) -> Rect2:
	return Rect2(feet - Vector2(size.x * 0.5, size.y), size)


static func rect_centered(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)
