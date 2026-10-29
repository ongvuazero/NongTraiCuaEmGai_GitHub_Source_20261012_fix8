extends RefCounted
class_name FieldZones

# Home retains the original field_plots array permanently. Extra fields never
# swap or duplicate that legacy array, so old saves and utility watering remain
# attached to the same original beds.
const IDS := ["home", "lakeside", "forest", "highland"]
const EXTRA_IDS := ["lakeside", "forest", "highland"]
const OPEN_DAYS := {"home": 1, "lakeside": 20, "forest": 40, "highland": 60}
const LABELS := {"home": "Main Field", "lakeside": "Lakeside Field", "forest": "Forest Field", "highland": "Highland Field"}
const BACKGROUNDS := {
	"home": "res://assets/field_approved_v1/runtime/field_background_clear_v2_20261008.png",
	"lakeside": "res://assets/field_zones_v1/lakeside_background.png",
	"forest": "res://assets/field_zones_v1/forest_background.png",
	"highland": "res://assets/field_zones_v1/highland_background.png",
}


static func initial_extra_fields(template: Array) -> Dictionary:
	var fields := {}
	for id in EXTRA_IDS: fields[id] = template.duplicate(true)
	return fields


static func active_id(state: Dictionary) -> String:
	var id := String(state.get("active_field_zone", "home"))
	return id if IDS.has(id) else "home"


static func open_day(id: String) -> int:
	return int(OPEN_DAYS.get(id, -1))


static func is_open(state: Dictionary, id: String) -> bool:
	return IDS.has(id) and int(state.get("day", 1)) >= open_day(id)


static func plots(state: Dictionary, id := "") -> Array:
	var target := active_id(state) if id.is_empty() else id
	if target == "home": return state.get("field_plots", [])
	return state.get("field_zone_plots", {}).get(target, [])


static func normalize(state: Dictionary, defaults: Array) -> void:
	var fields: Dictionary = state.get("field_zone_plots", {}) if state.get("field_zone_plots", {}) is Dictionary else {}
	for id in EXTRA_IDS:
		var beds: Array = fields.get(id, []).duplicate(true) if fields.get(id, []) is Array else []
		while beds.size() < 12: beds.append(defaults[beds.size()].duplicate(true))
		for index in range(mini(12, beds.size())):
			var bed: Dictionary = beds[index] if beds[index] is Dictionary else {}
			if bed.has("fertilized") and not bed.has("fertilizer_pending"): bed["fertilizer_pending"] = bool(bed["fertilized"])
			bed.erase("fertilized")
			for key in defaults[index]:
				if not bed.has(key): bed[key] = defaults[index][key]
			beds[index] = bed
		fields[id] = beds
	state["field_zone_plots"] = fields
	state["active_field_zone"] = active_id(state)


static func background_path(id: String) -> String:
	var path := String(BACKGROUNDS.get(id, BACKGROUNDS["home"]))
	return path if ResourceLoader.exists(path) else String(BACKGROUNDS["home"])
