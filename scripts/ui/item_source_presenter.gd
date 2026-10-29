extends RefCounted

# Presentation and navigation only. Sources come from world configuration,
# except the verified core-field harvest route for Ancient Dragon Fruit.
const FarmData = preload("res://scripts/farm_data.gd")


static func source(item_id: String) -> Dictionary:
	var config := GameState.world_config()
	var item: Dictionary = config.get("items", {}).get(item_id, {})
	if item_id == "ancient_fruit":
		return {"route": "field_select", "hint": UILocale.pair("%s: thu hoạch cây trồng; tối đa 12 lần thu hoạch không có quả.", "%s: harvest crops; guaranteed after 12 harvests without a fruit.") % item_name(item_id), "caption": UILocale.pair("Đến Ruộng", "Open Fields")}
	for island_id in config.get("islands", {}):
		var island: Dictionary = config["islands"][island_id]
		if String(island.get("gather_item", "")) == item_id:
			return {"route": "islands", "group": "islands", "id": String(island_id), "hint": UILocale.pair("%s: thu thập hằng ngày tại %s.", "%s: gather daily on %s.") % [item_name(item_id), island_name(String(island_id))], "caption": UILocale.pair("Đến %s", "Open %s") % island_name(String(island_id))}
	for garden_id in config.get("gardens", {}):
		var garden: Dictionary = config["gardens"][garden_id]
		if String(garden.get("item", "")) == item_id:
			return {"route": "craft", "group": "gardens", "id": String(garden_id), "hint": UILocale.pair("%s: mua %s tại %s rồi trồng ở Vườn dược liệu.", "%s: buy %s on %s, then grow it in the Herb Garden.") % [item_name(item_id), item_name(String(garden.get("seed", ""))), island_name(String(garden.get("island", "botanical")))], "caption": UILocale.pair("Mở Vườn dược liệu", "Open Herb Garden")}
	if int(item.get("price", 0)) > 0:
		var island_id := String(item.get("island", "main"))
		var group := String(item.get("group", ""))
		var category := "medicine" if group == "Medicine" else "seeds" if group == "Herb Seed" else "food" if group in ["Food", "Treat"] else "rare"
		var hint := UILocale.pair("%s: mua ở Cửa hàng chính, %d xu.", "%s: buy in Main Shop for %d coins.") % [item_name(item_id), int(item["price"])]
		if not bool(GameState.world_state().get("unlocked_islands", {}).get(island_id, false)):
			hint += " " + UILocale.pair("Mở %s trước.", "Unlock %s first.") % island_name(island_id)
		return {"route": "shop", "category": category, "id": item_id, "hint": hint, "caption": UILocale.pair("Mở Cửa hàng chính", "Open Main Shop")}
	if item_id.begins_with("crop_") and FarmData.CROP_DEFINITIONS.has(item_id.trim_prefix("crop_")):
		return {"route": "field_select", "hint": UILocale.pair("%s: trồng và thu hoạch tại Ruộng.", "%s: grow and harvest in the Fields.") % item_name(item_id), "caption": UILocale.pair("Đến Ruộng", "Open Fields")}
	return {}


static func item_name(item_id: String) -> String:
	return UILocale.translate_message(String(GameState.world_config().get("items", {}).get(item_id, {}).get("name", FarmData.get_inventory_name(item_id))))


static func island_name(island_id: String) -> String:
	return UILocale.translate_message(String(GameState.world_config().get("islands", {}).get(island_id, {}).get("name", island_id)))


static func open(item_id: String) -> void:
	var entry := source(item_id)
	if entry.is_empty(): return
	ScreenRouter.go(String(entry["route"]))
	var screen := ScreenRouter.host.get_child(ScreenRouter.host.get_child_count() - 1)
	if entry.has("group"):
		screen.call_deferred("select_entry", String(entry["group"]), String(entry["id"]))
	elif entry.has("category"):
		screen.call_deferred("_set_category", String(entry["category"]))
		screen.call_deferred("_select_product", String(entry["id"]))
