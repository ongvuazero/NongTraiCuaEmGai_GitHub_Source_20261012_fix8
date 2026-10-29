extends RefCounted
class_name SaveStateValidator

const FarmDataClass = preload("res://scripts/farm_data.gd")
const WorldDataClass = preload("res://scripts/world_data.gd")
const Fields = preload("res://scripts/field_zones.gd")
const INT64_EXCLUSIVE_UPPER_FLOAT := 9223372036854775808.0


# Validation never repairs or mutates the supplied state. Missing legacy defaults
# remain the normalizer's job; present malformed data must not become a new farm.
static func validate_state(state: Dictionary) -> Dictionary:
	if not state.has("save_version") or not _integer(state["save_version"], 2, 4):
		return _bad("save_version", "expected an integer from 2 to 4")
	if not state.get("field_plots") is Array or not state.get("inventory") is Dictionary:
		return _bad("schema", "field_plots must be an Array and inventory a Dictionary")
	var version := int(state["save_version"])
	var plots: Array = state["field_plots"]
	if plots.size() > 12 or (version == 4 and plots.size() != 12):
		return _bad("field_plots", "expected 12 beds (legacy v2/v3 may omit trailing defaults)")
	for key in ["day", "coins", "energy", "selected_slot", "selected_plot", "active_order_index", "orders_done", "saved_at_unix", "long_khi"]:
		var minimum := 1 if key in ["day", "selected_slot"] else 0
		var maximum := 100 if key == "energy" else (3 if key == "selected_slot" else (12 if key == "selected_plot" else -1))
		if state.has(key) and not _integer(state[key], minimum, maximum):
			return _bad(key, "expected an integer in its supported range")
	for key in ["status_text", "last_screen", "farm_name"]:
		if state.has(key) and not state[key] is String:
			return _bad(key, "expected a String")
	if state.has("selected_seed") and (not state["selected_seed"] is String or not FarmDataClass.CROP_DEFINITIONS.has(state["selected_seed"])):
		return _bad("selected_seed", "unknown crop")
	var checked := _plots(plots, "field_plots")
	if not checked["ok"]: return checked
	# New fields are optional for v2/v3/v4 migration, but any data present is
	# checked before normalization; corrupt extra-field crops never vanish.
	if state.has("field_zone_plots"):
		if not state["field_zone_plots"] is Dictionary: return _bad("field_zone_plots", "expected a Dictionary")
		for zone in state["field_zone_plots"]:
			if not Fields.EXTRA_IDS.has(zone): return _bad("field_zone_plots", "unknown field zone")
			var beds = state["field_zone_plots"][zone]
			if not beds is Array or beds.size() != 12: return _bad("field_zone_plots." + zone, "expected 12 independent beds")
			checked = _plots(beds, "field_zone_plots." + zone)
			if not checked["ok"]: return checked
	if state.has("active_field_zone"):
		var zone = state["active_field_zone"]
		if not zone is String or not Fields.IDS.has(zone): return _bad("active_field_zone", "unknown field zone")
		if not Fields.is_open(state, zone): return _bad("active_field_zone", "field is not available on this farm day")
		if zone != "home" and not state.get("field_zone_plots", {}).has(zone): return _bad("active_field_zone", "selected field has no saved beds")
	checked = _integer_map(state["inventory"], "inventory")
	if not checked["ok"]: return checked
	for key in ["animal", "event_progress"]:
		if state.has(key):
			if not state[key] is Dictionary: return _bad(key, "expected a Dictionary")
			checked = _integer_map(state[key], key)
			if not checked["ok"]: return checked
	if state.has("last_rewards"):
		if not state["last_rewards"] is Array: return _bad("last_rewards", "expected an Array")
		for index in range(state["last_rewards"].size()):
			var reward = state["last_rewards"][index]
			var path := "last_rewards[%d]" % index
			if not reward is Dictionary: return _bad(path, "expected a Dictionary")
			for key in ["label", "value"]:
				if not reward.get(key) is String: return _bad(path + "." + key, "expected a String")
	if state.has("settings"):
		if not state["settings"] is Dictionary: return _bad("settings", "expected a Dictionary")
		for key in ["master", "music", "sfx"]:
			if state["settings"].has(key) and not _number(state["settings"][key], 0, 100):
				return _bad("settings." + key, "expected a finite number from 0 to 100")
		if state["settings"].has("fullscreen") and not state["settings"]["fullscreen"] is bool:
			return _bad("settings.fullscreen", "expected a bool")
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		if state.has(key) and not _number(state[key], 0, 100): return _bad(key, "expected a finite number from 0 to 100")
	if state.has("fullscreen") and not state["fullscreen"] is bool: return _bad("fullscreen", "expected a bool")
	if state.has("world"):
		if not state["world"] is Dictionary: return _bad("world", "expected a Dictionary")
		checked = _world(state["world"])
		if not checked["ok"]: return checked
	return {"ok": true, "message": "OK"}


static func _plots(plots: Array, prefix: String) -> Dictionary:
	for index in range(plots.size()):
		if not plots[index] is Dictionary: return _bad("%s[%d]" % [prefix, index], "expected a Dictionary")
		var plot: Dictionary = plots[index]
		var path := "%s[%d]" % [prefix, index]
		if plot.has("id") and (not _integer(plot["id"], 1, 12) or int(plot["id"]) != index + 1):
			return _bad(path + ".id", "duplicate, reordered or unsupported bed ID")
		if plot.has("position") and (not plot["position"] is Vector2 or not plot["position"].is_finite()):
			return _bad(path + ".position", "expected a finite Vector2")
		var crop = plot.get("crop", "")
		if not crop is String or (not String(crop).is_empty() and not FarmDataClass.CROP_DEFINITIONS.has(crop)):
			return _bad(path + ".crop", "unknown crop")
		for key in ["locked", "is_hoed", "watered_today", "fertilizer_pending", "ready_to_harvest", "fertilized"]:
			if plot.has(key) and not plot[key] is bool: return _bad(path + "." + key, "expected a bool")
		for key in ["growth_stage", "planted_day", "last_watered_day"]:
			if plot.has(key) and not _integer(plot[key], 0 if key == "growth_stage" else -1): return _bad(path + "." + key, "expected an integer")
		if not String(crop).is_empty() and int(plot.get("growth_stage", 0)) > int(FarmDataClass.CROP_DEFINITIONS[crop]["max_stage"]):
			return _bad(path + ".growth_stage", "exceeds this crop's final stage")
	return {"ok": true, "message": "OK"}


static func _world(world: Dictionary) -> Dictionary:
	var config := WorldDataClass.config()
	for key in ["version", "dragon_energy", "long_vein", "season_length", "blessing_day"]:
		if world.has(key) and not _integer(world[key], 1 if key == "season_length" else 0): return _bad("world." + key, "expected an integer")
	for key in ["last_result", "last_action"]:
		if world.has(key) and not world[key] is String: return _bad("world." + key, "expected a String")
	for key in ["unlocked_islands", "buildings", "creatures", "gardens", "incubators", "utility", "gather_days", "stats", "migration_preserved"]:
		if world.has(key) and not world[key] is Dictionary: return _bad("world." + key, "expected a Dictionary")
	for key in ["craft_queue", "claimed_events"]:
		if world.has(key) and not world[key] is Array: return _bad("world." + key, "expected an Array")
	for key in ["buildings", "gather_days", "stats"]:
		if world.has(key):
			var checked := _integer_map(world[key], "world." + key)
			if not checked["ok"]: return checked
	for id in world.get("unlocked_islands", {}):
		if not id is String or not world["unlocked_islands"][id] is bool: return _bad("world.unlocked_islands", "expected String IDs and bool values")
	for id in world.get("creatures", {}):
		if not config["creatures"].has(id): return _bad("world.creatures", "unknown creature")
		var creature = world["creatures"][id]
		if not creature is Dictionary: return _bad("world.creatures." + String(id), "expected a Dictionary")
		for key in ["fullness", "cleanliness", "happiness", "age_days", "products_ready", "last_fed_day", "neglect_days"]:
			if creature.has(key) and not _integer(creature[key], 0): return _bad("world.creatures." + String(id) + "." + key, "expected a nonnegative integer")
		if creature.has("disease") and not creature["disease"] is String: return _bad("world.creatures." + String(id) + ".disease", "expected a String")
	for group in ["gardens", "incubators"]:
		var table := "eggs" if group == "incubators" else "gardens"
		for id in world.get(group, {}):
			if not config[table].has(id): return _bad("world." + group, "unknown content ID")
			var entry = world[group][id]
			if not entry is Dictionary: return _bad("world." + group + "." + String(id), "expected a Dictionary")
			var checked := _progress(entry, "world." + group + "." + String(id))
			if not checked["ok"]: return checked
	for task in world.get("craft_queue", []):
		if not task is Dictionary or not task.get("recipe") is String or not config["recipes"].has(task["recipe"]): return _bad("world.craft_queue", "unknown or malformed recipe")
		var checked := _progress(task, "world.craft_queue")
		if not checked["ok"]: return checked
	for id in world.get("utility", {}):
		var species = world["utility"][id]
		if not id is String or not species is String or not config["creatures"].has(species): return _bad("world.utility", "unknown or malformed creature assignment")
	for id in world.get("claimed_events", []):
		if not id is String: return _bad("world.claimed_events", "expected String IDs")
	return {"ok": true, "message": "OK"}


static func _progress(entry: Dictionary, path: String) -> Dictionary:
	for key in ["growth", "progress", "required", "planted_day", "started_day"]:
		if entry.has(key) and not _integer(entry[key], -1 if key == "planted_day" else 0): return _bad(path + "." + key, "expected an integer")
	for key in ["ready", "watered_today"]:
		if entry.has(key) and not entry[key] is bool: return _bad(path + "." + key, "expected a bool")
	return {"ok": true, "message": "OK"}


static func _integer_map(values: Dictionary, path: String) -> Dictionary:
	for key in values:
		# Dictionary dot assignment can insert a StringName; String readers use
		# the same textual key, so preserve that valid representation as-is.
		if not (key is String or key is StringName) or not _integer(values[key], 0): return _bad(path + "." + str(key), "expected a textual key and nonnegative integer quantity")
	return {"ok": true, "message": "OK"}


static func _integer(value: Variant, minimum: int, maximum := -1) -> bool:
	# Preserve integral floats only when existing int() readers can convert them.
	# float(INT64_MAX) rounds up to 2^63, so the positive bound is exclusive.
	# Strings/bools are not guessed (int('broken') silently becomes zero).
	if not (value is int or value is float): return false
	if value is float and (not is_finite(value) or value != floor(value) or value < -INT64_EXCLUSIVE_UPPER_FLOAT or value >= INT64_EXCLUSIVE_UPPER_FLOAT): return false
	return value >= minimum and (maximum < 0 or value <= maximum)


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum


static func _bad(path: String, reason: String) -> Dictionary:
	return {"ok": false, "message": "Save invalid: %s (%s). Original data kept." % [path, reason]}
