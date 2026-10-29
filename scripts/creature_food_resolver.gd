extends RefCounted

# One presentation/transaction choice for configured food and legacy chicken
# compatibility. This is read-only and introduces no inventory or save fields.
const WorldData = preload("res://scripts/world_data.gd")

static func resolve(data: Dictionary, species: String) -> String:
	var definition: Dictionary = WorldData.config().get("creatures", {}).get(species, {})
	var configured := String(definition.get("food", ""))
	var inventory: Dictionary = data.get("inventory", {})
	if species == "cloud_chicken" and int(inventory.get(configured, 0)) <= 0 and int(inventory.get("animal_feed", 0)) > 0:
		return "animal_feed"
	return configured
