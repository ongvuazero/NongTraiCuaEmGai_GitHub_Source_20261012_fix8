extends RefCounted
class_name WorldData

const DATA_ROOT := "res://data/full_game/"
const TABLES := ["islands", "buildings", "items", "creatures", "gardens", "recipes", "eggs", "events", "seasons"]
static var _config: Dictionary = {}


static func config() -> Dictionary:
	if _config.is_empty():
		for table in TABLES:
			var path: String = DATA_ROOT + table + ".json"
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Dictionary:
				push_error("Full-game data is not a JSON dictionary: " + path)
				_config[table] = {}
			else:
				_config[table] = parsed
	return _config


static func creature_state() -> Dictionary:
	return {"fullness": 60, "cleanliness": 75, "happiness": 68, "disease": "", "age_days": 0, "products_ready": 0, "last_fed_day": 0, "neglect_days": 0}


static func initial_state() -> Dictionary:
	var islands: Dictionary = {}
	for island_id in config().get("islands", {}):
		islands[island_id] = island_id == "main"
	return {
		"version": 1,
		"unlocked_islands": islands,
		"buildings": {"barn": 1},
		"creatures": {"cloud_chicken": creature_state()},
		"gardens": {}, "incubators": {}, "craft_queue": [],
		"utility": {}, "gather_days": {}, "claimed_events": [],
		"dragon_energy": 0, "long_vein": 0,
		"stats": {"harvest": 0, "till": 0, "plant": 0, "water": 0, "care": 0, "craft": 0, "gather": 0, "hatch": 0, "garden_harvest": 0, "animal_collect": 0},
		"last_result": "", "last_action": "", "season_length": 28,
	}


static func merge_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key in loaded:
		if merged.get(key) is Dictionary and loaded[key] is Dictionary:
			merged[key] = merge_defaults(merged[key], loaded[key])
		else:
			merged[key] = loaded[key]
	return merged


static func normalize_state(loaded: Dictionary) -> Dictionary:
	var defaults := initial_state()
	var world := merge_defaults(defaults, loaded)
	var preserved: Dictionary = world.get("migration_preserved", {}) if world.get("migration_preserved", {}) is Dictionary else {}
	for key in ["unlocked_islands", "buildings", "creatures", "gardens", "incubators", "utility", "gather_days", "stats"]:
		if not world[key] is Dictionary:
			preserved[key] = world[key]
			world[key] = defaults[key].duplicate(true)
	for key in ["craft_queue", "claimed_events"]:
		if not world[key] is Array:
			preserved[key] = world[key]
			world[key] = []
	for species in world["creatures"]:
		if world["creatures"][species] is Dictionary:
			world["creatures"][species] = merge_defaults(creature_state(), world["creatures"][species])
		else:
			preserved["creature_" + String(species)] = world["creatures"][species]
			world["creatures"][species] = creature_state()
	for garden_id in world["gardens"]:
		var garden_defaults := {"growth": 0, "watered_today": false, "ready": false, "planted_day": -1}
		if world["gardens"][garden_id] is Dictionary:
			world["gardens"][garden_id] = merge_defaults(garden_defaults, world["gardens"][garden_id])
		else:
			preserved["garden_" + String(garden_id)] = world["gardens"][garden_id]
			world["gardens"][garden_id] = garden_defaults
	for egg_id in world["incubators"]:
		var incubation_defaults := {"progress": 0, "required": int(config()["eggs"].get(egg_id, {}).get("days", 3)), "ready": false, "started_day": 0}
		if world["incubators"][egg_id] is Dictionary:
			world["incubators"][egg_id] = merge_defaults(incubation_defaults, world["incubators"][egg_id])
		else:
			preserved["incubator_" + String(egg_id)] = world["incubators"][egg_id]
			world["incubators"][egg_id] = incubation_defaults
	var normalized_queue: Array = []
	for task in world["craft_queue"]:
		if task is Dictionary and task.has("recipe"):
			var queue_defaults := {"progress": 0, "required": int(config()["recipes"].get(task["recipe"], {}).get("days", 1)), "ready": false}
			normalized_queue.append(merge_defaults(queue_defaults, task))
		else:
			if not preserved.has("invalid_craft_queue"): preserved["invalid_craft_queue"] = []
			preserved["invalid_craft_queue"].append(task)
	world["craft_queue"] = normalized_queue
	if not preserved.is_empty(): world["migration_preserved"] = preserved
	world["unlocked_islands"]["main"] = true
	return world
