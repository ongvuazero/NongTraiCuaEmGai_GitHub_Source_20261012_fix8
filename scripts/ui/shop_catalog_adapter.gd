extends RefCounted

# Catalog projection only: prices, requirements and purchases remain GameState.
const FarmData = preload("res://scripts/farm_data.gd")
var scope := "main"


func _init(context := "main") -> void:
	scope = context


func dragon_ids(category: String) -> Array[String]:
	var result: Array[String] = []
	var config := GameState.world_config()
	var foods: Array[String] = []
	var diseases: Array[String] = []
	for definition in config.get("creatures", {}).values():
		if String(definition.get("kind", "")) != "dragon": continue
		var food := String(definition.get("food", ""))
		if not food.is_empty() and food not in foods: foods.append(food)
		var disease := String(definition.get("care_disease", ""))
		if not disease.is_empty() and disease not in diseases: diseases.append(disease)
	for id in config.get("items", {}):
		var definition: Dictionary = config["items"][id]
		if (category == "food" and String(id) in foods) or (category == "medicine" and String(definition.get("cures", "")) in diseases):
			result.append(String(id))
	return result


func items(category: String) -> Array:
	var result: Array = []
	if scope == "dragon":
		for id in dragon_ids(category): result.append(item(id))
		return result
	for definition in FarmData.SHOP_ITEMS:
		var id := String(definition["id"])
		if (category == "seeds" and id.begins_with("seed_")) or (category == "food" and id == "animal_feed") or (category == "medicine" and id == "medicine"):
			result.append(item(id))
	var config := GameState.world_config()
	if category == "expansion":
		for id in config.get("buildings", {}): result.append(item(String(id)))
	elif category == "rare":
		for id in config.get("eggs", {}): result.append(item(String(id)))
	for id in config.get("items", {}):
		var group := String(config["items"][id].get("group", ""))
		if (category == "seeds" and group == "Herb Seed") or (category == "food" and group in ["Food", "Treat"]) or (category == "medicine" and group == "Medicine") or (category == "rare" and group == "Rare"):
			result.append(item(String(id)))
	return result


func item(id: String) -> Dictionary:
	if scope == "dragon" and id not in dragon_ids("food") and id not in dragon_ids("medicine"): return {}
	for definition in FarmData.SHOP_ITEMS:
		if String(definition.get("id", "")) == id:
			var core: Dictionary = definition.duplicate(true)
			core["kind"] = "core"
			return core
	var config := GameState.world_config()
	for group in ["buildings", "eggs", "items"]:
		if not config.get(group, {}).has(id): continue
		var product: Dictionary = config[group][id].duplicate(true)
		product["id"] = id
		product["kind"] = "building" if group == "buildings" else "egg" if group == "eggs" else "world_item"
		if group == "buildings":
			product["price"] = int(product.get("cost", 0)) * (int(GameState.world_state().get("buildings", {}).get(id, 0)) + 1)
		elif group == "eggs": product["price"] = int(product.get("cost", 0))
		product["amount"] = int(product.get("amount", 1))
		return product
	return {}
