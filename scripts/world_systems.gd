extends RefCounted
class_name WorldSystems

# GameState owns transactions/autosave. This module only changes the supplied
# dictionary and never emits signals, opens screens, or touches save files.
const WorldData = preload("res://scripts/world_data.gd")
const FoodResolver = preload("res://scripts/creature_food_resolver.gd")
const StarterFarm = preload("res://scripts/farm_data.gd")
const Fields = preload("res://scripts/field_zones.gd")
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]


static func season(data: Dictionary) -> String:
	var length := maxi(1, int(data.get("world", {}).get("season_length", 28)))
	return SEASON_IDS[posmod(floori(float(int(data.get("day", 1)) - 1) / float(length)), 4)]


static func inventory_capacity(data: Dictionary) -> int:
	return 20 + 10 * int(data.get("world", {}).get("buildings", {}).get("warehouse", 0))


static func inventory_stacks(data: Dictionary) -> int:
	var stacks := 0
	for amount in data.get("inventory", {}).values():
		if int(amount) > 0:
			stacks += 1
	return stacks


static func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": UILocale.translate_message(reason)}


static func _owns_island(data: Dictionary, island: String) -> bool:
	return bool(data["world"]["unlocked_islands"].get(island, false))


static func _owns_building(data: Dictionary, building: String) -> bool:
	return building.is_empty() or int(data["world"]["buildings"].get(building, 0)) > 0


static func _requirements(data: Dictionary, definition: Dictionary) -> Dictionary:
	if int(data.get("orders_done", 0)) < int(definition.get("orders", 0)):
		return _result(false, "Complete %d crop orders first." % int(definition["orders"]))
	var island := String(definition.get("island", "main"))
	if not _owns_island(data, island):
		return _result(false, "Unlock %s first." % String(WorldData.config()["islands"].get(island, {}).get("name", island)))
	var building := String(definition.get("building", ""))
	if not _owns_building(data, building):
		return _result(false, "Build %s first." % String(WorldData.config()["buildings"].get(building, {}).get("name", building)))
	return _result(true, "")


static func _can_pay(data: Dictionary, coins: int, items: Dictionary) -> Dictionary:
	if int(data.get("coins", 0)) < coins:
		return _result(false, "Need %d coins; you have %d." % [coins, int(data.get("coins", 0))])
	for item in items:
		if int(data["inventory"].get(item, 0)) < int(items[item]):
			return _result(false, "Need %s x%d; you have %d." % [_item_name(item), int(items[item]), int(data["inventory"].get(item, 0))])
	return _result(true, "")


static func _pay(data: Dictionary, coins: int, items: Dictionary) -> void:
	data["coins"] = int(data.get("coins", 0)) - coins
	for item in items:
		data["inventory"][item] = int(data["inventory"].get(item, 0)) - int(items[item])


static func _add(data: Dictionary, item: String, amount: int) -> void:
	if item == "dragon_energy":
		data["world"]["dragon_energy"] = mini(99, int(data["world"].get("dragon_energy", 0)) + amount)
	else:
		data["inventory"][item] = int(data["inventory"].get(item, 0)) + amount


static func _item_name(item: String) -> String:
	return String(WorldData.config()["items"].get(item, {}).get("name", item.replace("_", " ").capitalize()))


static func _stat(data: Dictionary, stat: String, amount := 1) -> void:
	data["world"]["stats"][stat] = int(data["world"]["stats"].get(stat, 0)) + amount


static func sync_chicken(data: Dictionary) -> void:
	if not data.get("world", {}).get("creatures", {}).has("cloud_chicken"):
		return
	var chicken: Dictionary = data["world"]["creatures"]["cloud_chicken"]
	for meter in ["fullness", "cleanliness", "happiness"]:
		chicken[meter] = int(data["animal"].get(meter, chicken.get(meter, 60)))
	chicken["products_ready"] = int(data["animal"].get("eggs_ready", 0))
	data["world"]["creatures"]["cloud_chicken"] = chicken


static func _write_chicken(data: Dictionary) -> void:
	var chicken: Dictionary = data["world"]["creatures"]["cloud_chicken"]
	for meter in ["fullness", "cleanliness", "happiness"]:
		data["animal"][meter] = int(chicken[meter])
	data["animal"]["eggs_ready"] = int(chicken["products_ready"])


static func act(data: Dictionary, action: String, id: String) -> Dictionary:
	var before_stacks := inventory_stacks(data)
	var outcome: Dictionary = _perform(data, action, id)
	if not bool(outcome["ok"]):
		return outcome
	if inventory_stacks(data) > maxi(inventory_capacity(data), before_stacks):
		return _result(false, "Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % inventory_capacity(data))
	data["world"]["last_action"] = action + ":" + id
	data["world"]["last_result"] = outcome["reason"]
	return outcome


static func _perform(data: Dictionary, action: String, id: String) -> Dictionary:
	match action:
		"unlock_island": return _unlock_island(data, id)
		"build": return _build(data, id)
		"buy_item": return _buy_item(data, id)
		"sell_item": return _sell_item(data, id)
		"craft": return _craft(data, id)
		"claim_craft": return _claim_craft(data, id)
		"plant_garden", "water_garden", "harvest_garden": return _garden_action(data, action, id)
		"adopt": return _adopt(data, id)
		"feed", "clean", "pet", "treat", "heal", "collect", "assign_utility", "unassign_utility": return _creature_action(data, action, id)
		"buy_egg", "incubate", "claim_hatch": return _egg_action(data, action, id)
		"gather": return _gather(data, id)
		"request_seed_relief": return _request_seed_relief(data)
		"discard_item": return _discard_item(data, id)
		"claim_event": return _claim_event(data, id)
		"dragon_blessing":
			if not _owns_island(data, "dragon"): return _result(false, "Unlock Dragon Island first.")
			var altar: Dictionary = WorldData.config()["buildings"]["dragon_altar"]
			var price := int(altar.get("blessing_cost", 5))
			if int(data["world"].get("blessing_day", 0)) == int(data["day"]): return _result(false, "The altar blessing was used today. Return next day.")
			if int(data["energy"]) >= 100: return _result(false, "Farm energy is already full.")
			if int(data["world"]["dragon_energy"]) < price: return _result(false, "Need %d Dragon Energy for an altar blessing." % price)
			data["world"]["dragon_energy"] = int(data["world"]["dragon_energy"]) - price
			data["energy"] = mini(100, int(data["energy"]) + int(altar.get("blessing_energy", 20)))
			data["world"]["blessing_day"] = int(data["day"])
			return _result(true, "Altar blessing recovered farm energy. Available again next day.")
		"convert_fruit":
			if not _owns_island(data, "dragon"):
				return _result(false, "Unlock Dragon Island before converting surplus fruit.")
			if int(data["inventory"].get("ancient_fruit", 0)) <= 0:
				return _result(false, "Need one Ancient Dragon Fruit.")
			if int(data["world"]["dragon_energy"]) > 94:
				return _result(false, "Dragon Energy is near its 99-point cap; use it first.")
			_pay(data, 0, {"ancient_fruit": 1})
			_add(data, "dragon_energy", 5)
			return _result(true, "Converted surplus fruit into 5 Dragon Energy.")
	return _result(false, "Unknown world action: " + action)


# Read-only policy used by the transaction and its Home presentation. Existing
# integer gather_days stores the cooldown, keeping v2/v3/v4 saves compatible.
# Relief has no coins, sellable grant, automatic illness cure or energy cost.
static func seed_relief_info(data: Dictionary) -> Dictionary:
	var day := int(data.get("day", 1))
	var last_day := int(data.get("world", {}).get("gather_days", {}).get("seed_relief", -1))
	if last_day >= day:
		return _result(false, UILocale.pair("Đã nhận hạt cứu trợ hôm nay.", "Seed relief was already claimed today."))
	var seed_price := 12
	for offer in StarterFarm.SHOP_ITEMS:
		if String(offer.get("id", "")) == "seed_carrot": seed_price = int(offer.price)
	if int(data.get("coins", 0)) >= seed_price:
		return _result(false, UILocale.pair("Bạn còn đủ xu để mua hạt cà rốt ở Cửa hàng.", "You can still buy carrot seeds in the Shop."))
	var inventory: Dictionary = data.get("inventory", {})
	for crop in StarterFarm.CROP_DEFINITIONS:
		var definition: Dictionary = StarterFarm.CROP_DEFINITIONS[crop]
		# Even a locked crop's harvested produce can be sold. Its seed, however,
		# is not a productive route until the corresponding order gate opens.
		if int(inventory.get(definition.crop_item, 0)) > 0:
			return _result(false, UILocale.pair("Bạn còn nông sản để giao đơn hoặc bán lấy xu mua hạt.", "Deliver or sell your remaining crops to buy seeds."))
		var required_orders := int({"carrot": 0, "tomato": 1, "pumpkin": 2}.get(crop, 0))
		if int(data.get("orders_done", 0)) >= required_orders and int(inventory.get(definition.seed_item, 0)) > 0:
			return _result(false, UILocale.pair("Bạn còn hạt giống để trồng; hãy dùng chúng trước.", "You still have usable crop seeds; plant them first."))
	for zone in Fields.IDS:
		for bed in Fields.plots(data, String(zone)):
			if not String(bed.get("crop", "")).is_empty():
				return _result(false, UILocale.pair("Bạn còn cây trên ruộng; tiếp tục chăm và thu hoạch.", "You still have a planted crop; care for it and harvest."))
	# Don't issue relief when already-owned sellable stock/ready products can
	# finance the cheapest seed pack. Partial income below that price isn't an
	# escape on its own, so it must not permanently suppress recovery.
	var liquid_coins := int(data.get("coins", 0))
	var config := WorldData.config()
	for item in inventory:
		liquid_coins += int(inventory[item]) * int(config.items.get(item, {}).get("sell", 0))
	for species in data.get("world", {}).get("creatures", {}):
		var creature: Dictionary = data.world.creatures[species]
		var ready := int(data.get("animal", {}).get("eggs_ready", 0)) if species == "cloud_chicken" else int(creature.get("products_ready", 0))
		var product := String(config.creatures.get(species, {}).get("product", ""))
		liquid_coins += ready * int(config.items.get(product, {}).get("sell", 0))
	if liquid_coins >= seed_price:
		return _result(false, UILocale.pair("Bạn còn sản phẩm đủ bán lấy xu mua hạt. Thu sản phẩm rồi bán trong Kho.", "You have enough products to buy seeds. Collect and sell them in Storage."))
	return _result(true, UILocale.pair("Hết vốn và hết hạt/cây: nhận 1 hạt cà rốt để trồng lại.", "No seed money or crops left: receive 1 carrot seed to restart."))


static func _request_seed_relief(data: Dictionary) -> Dictionary:
	var eligibility := seed_relief_info(data)
	if not bool(eligibility.ok): return eligibility
	_add(data, "seed_carrot", 1)
	data["world"]["gather_days"]["seed_relief"] = int(data["day"])
	return _result(true, UILocale.pair("Đã nhận 1 hạt cà rốt cứu trợ. Vào Ruộng để gieo, tưới và thu hoạch lấy vốn.", "Received 1 relief carrot seed. Plant, water and harvest it to rebuild your funds."))


static func _discard_item(data: Dictionary, id: String) -> Dictionary:
	if id == "dragon_energy" or id.is_empty():
		return _result(false, UILocale.pair("Không thể bỏ tài nguyên này.", "This resource cannot be discarded."))
	var amount := int(data.get("inventory", {}).get(id, 0))
	if amount <= 0:
		return _result(false, UILocale.pair("Bạn không có vật phẩm này.", "You do not own this item."))
	# Presentation must confirm the exact chosen stack and count before calling
	# this action. No automatic eviction or conversion of the player's supplies.
	data["inventory"][id] = 0
	return _result(true, UILocale.pair("Đã bỏ loại vật phẩm đã chọn để giải phóng kho.", "Discarded the selected item stack to free storage space."))


static func _unlock_island(data: Dictionary, id: String) -> Dictionary:
	var islands: Dictionary = WorldData.config()["islands"]
	if not islands.has(id): return _result(false, "Unknown island.")
	if _owns_island(data, id): return _result(false, "This island is already unlocked.")
	var definition: Dictionary = islands[id]
	if int(data.get("orders_done", 0)) < int(definition["orders"]):
		return _result(false, "Complete %d crop orders first." % int(definition["orders"]))
	var previous := String(definition["requires"])
	if not _owns_island(data, previous): return _result(false, "Unlock %s first." % previous.capitalize())
	var payment := _can_pay(data, int(definition["cost"]), definition["items"])
	if not payment["ok"]: return payment
	_pay(data, int(definition["cost"]), definition["items"])
	data["world"]["unlocked_islands"][id] = true
	if id == "dragon":
		data["world"]["buildings"]["dragon_altar"] = 1
		data["last_rewards"] = [{"label": "Island unlocked", "value": "Dragon Island"}]
	return _result(true, "Unlocked %s." % String(definition["name"]))


static func _build(data: Dictionary, id: String) -> Dictionary:
	var buildings: Dictionary = WorldData.config()["buildings"]
	if not buildings.has(id): return _result(false, "Unknown building.")
	if id == "dragon_altar": return _unlock_island(data, "dragon")
	var definition: Dictionary = buildings[id]
	var level := int(data["world"]["buildings"].get(id, 0))
	if level >= int(definition["max_level"]): return _result(false, "This building is already at its maximum level.")
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	var coins := int(definition["cost"]) * (level + 1)
	var payment := _can_pay(data, coins, definition["items"])
	if not payment["ok"]: return payment
	_pay(data, coins, definition["items"])
	data["world"]["buildings"][id] = level + 1
	return _result(true, "%s is now level %d." % [String(definition["name"]), level + 1])


static func _buy_item(data: Dictionary, id: String) -> Dictionary:
	var items: Dictionary = WorldData.config()["items"]
	if not items.has(id) or int(items[id].get("price", 0)) <= 0:
		return _result(false, "This item cannot be purchased.")
	var definition: Dictionary = items[id]
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	var payment := _can_pay(data, int(definition["price"]), {})
	if not payment["ok"]: return payment
	_pay(data, int(definition["price"]), {})
	_add(data, id, int(definition["amount"]))
	return _result(true, "Bought %s x%d." % [String(definition["name"]), int(definition["amount"])])


static func _sell_item(data: Dictionary, id: String) -> Dictionary:
	var items: Dictionary = WorldData.config()["items"]
	var value := int(items.get(id, {}).get("sell", 0))
	if id == "egg": value = 10
	if value <= 0: return _result(false, "Rare materials and food cannot be sold here.")
	if int(data["inventory"].get(id, 0)) <= 0: return _result(false, "You do not own this item.")
	_pay(data, 0, {id: 1})
	data["coins"] = int(data["coins"]) + value
	return _result(true, "Sold one %s for %d coins." % [_item_name(id), value])


static func _craft(data: Dictionary, id: String) -> Dictionary:
	var recipes: Dictionary = WorldData.config()["recipes"]
	if not recipes.has(id): return _result(false, "Unknown recipe.")
	var definition: Dictionary = recipes[id]
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	var payment := _can_pay(data, int(definition["coins"]), definition["ingredients"])
	if not payment["ok"]: return payment
	if int(definition["days"]) > 0:
		for task in data["world"]["craft_queue"]:
			if task.get("recipe", "") == id:
				return _result(false, "This recipe is already queued; claim it before crafting again.")
	_pay(data, int(definition["coins"]), definition["ingredients"])
	if int(definition["days"]) == 0:
		_add(data, String(definition["output"]), int(definition["amount"]))
		_stat(data, "craft")
		return _result(true, "Crafted %s x%d." % [String(definition["name"]), int(definition["amount"])])
	data["world"]["craft_queue"].append({"recipe": id, "progress": 0, "required": int(definition["days"]), "ready": false})
	return _result(true, "%s queued for %d days." % [String(definition["name"]), int(definition["days"])])


static func _claim_craft(data: Dictionary, id: String) -> Dictionary:
	var queue: Array = data["world"]["craft_queue"]
	for index in range(queue.size()):
		if queue[index].get("recipe", "") == id and bool(queue[index].get("ready", false)):
			var definition: Dictionary = WorldData.config()["recipes"].get(id, {})
			if definition.is_empty(): return _result(false, "Queued recipe data is missing.")
			_add(data, String(definition["output"]), int(definition["amount"]))
			queue.remove_at(index)
			_stat(data, "craft")
			return _result(true, "Collected %s x%d." % [String(definition["name"]), int(definition["amount"])])
	return _result(false, "No finished craft to collect.")


static func _garden_action(data: Dictionary, action: String, id: String) -> Dictionary:
	var gardens: Dictionary = WorldData.config()["gardens"]
	if not gardens.has(id): return _result(false, "Unknown medicinal crop.")
	var definition: Dictionary = gardens[id]
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	var planted: Dictionary = data["world"]["gardens"].get(id, {})
	if action == "plant_garden":
		if not planted.is_empty(): return _result(false, "This garden is occupied; harvest it first.")
		if int(data["inventory"].get(String(definition["seed"]), 0)) <= 0:
			return _result(false, "Buy %s first." % _item_name(String(definition["seed"])))
		if int(data["energy"]) < 3: return _result(false, "Need 3 energy to plant.")
		_pay(data, 0, {String(definition["seed"]): 1})
		data["energy"] = int(data["energy"]) - 3
		data["world"]["gardens"][id] = {"growth": 0, "watered_today": false, "ready": false, "planted_day": int(data["day"])}
		return _result(true, "Planted %s in its separate medicinal garden." % String(definition["name"]))
	if planted.is_empty(): return _result(false, "Plant this medicinal garden first.")
	if action == "water_garden":
		if bool(planted.get("ready", false)): return _result(false, "This garden is ready to harvest.")
		if bool(planted.get("watered_today", false)): return _result(false, "This garden was watered today.")
		if int(data["energy"]) < 2: return _result(false, "Need 2 energy to water.")
		data["energy"] = int(data["energy"]) - 2
		planted["watered_today"] = true
		return _result(true, "Watered %s. Advance the day to grow it." % String(definition["name"]))
	if not bool(planted.get("ready", false)): return _result(false, "This garden is still growing.")
	if int(data["energy"]) < 3: return _result(false, "Need 3 energy to harvest.")
	var amount := 1 + int(data["world"]["buildings"].get("garden", 0))
	_add(data, String(definition["item"]), amount)
	data["energy"] = int(data["energy"]) - 3
	data["world"]["gardens"].erase(id)
	_stat(data, "garden_harvest")
	return _result(true, "Harvested %s x%d." % [String(definition["name"]), amount])


static func _adopt(data: Dictionary, id: String) -> Dictionary:
	var creatures: Dictionary = WorldData.config()["creatures"]
	if not creatures.has(id): return _result(false, "Unknown creature.")
	if data["world"]["creatures"].has(id): return _result(false, "You already have this companion.")
	var definition: Dictionary = creatures[id]
	if String(definition["kind"]) == "dragon": return _result(false, "Dragons must hatch from their own elemental eggs.")
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	var kind := String(definition["kind"])
	var count := 0
	for species in data["world"]["creatures"]:
		if String(creatures.get(species, {}).get("kind", "")) == kind: count += 1
	var capacity := 2 + int(data["world"]["buildings"].get("barn", 1))
	if kind == "fish": capacity = 3 * int(data["world"]["buildings"].get("pond", 0))
	if kind == "monster": capacity = 3
	if count >= capacity: return _result(false, "Companion capacity reached; upgrade the matching building.")
	var payment := _can_pay(data, int(definition["cost"]), {})
	if not payment["ok"]: return payment
	_pay(data, int(definition["cost"]), {})
	data["world"]["creatures"][id] = WorldData.creature_state()
	return _result(true, "Welcomed %s. Food: %s." % [String(definition["name"]), _item_name(String(definition["food"]))])


static func _care_ok(state: Dictionary) -> bool:
	return int(state.get("fullness", 0)) >= 40 and int(state.get("cleanliness", 0)) >= 40 and int(state.get("happiness", 0)) >= 40 and String(state.get("disease", "")).is_empty()


static func _creature_action(data: Dictionary, action: String, id: String) -> Dictionary:
	var creatures: Dictionary = WorldData.config()["creatures"]
	if not creatures.has(id) or not data["world"]["creatures"].has(id): return _result(false, "You do not own this creature.")
	if id == "cloud_chicken": sync_chicken(data)
	var state: Dictionary = data["world"]["creatures"][id]
	var definition: Dictionary = creatures[id]
	var name := String(definition["name"])
	if action == "collect":
		var amount := int(state.get("products_ready", 0))
		if amount <= 0: return _result(false, "No product ready. Feed, clean and pet this companion, then advance the day.")
		if String(definition["product"]) == "dragon_energy" and int(data["world"]["dragon_energy"]) + amount > 99:
			return _result(false, "Use Dragon Energy before collecting more.")
		_add(data, String(definition["product"]), amount)
		state["products_ready"] = 0
		_stat(data, "animal_collect", amount)
		if id == "cloud_chicken": _write_chicken(data)
		return _result(true, "Collected %s x%d from %s." % [_item_name(String(definition["product"])), amount, name])
	if action == "assign_utility":
		if not _care_ok(state): return _result(false, "Companion needs healthy care meters of at least 40 before assignment.")
		var utility := String(definition["utility"])
		if String(data["world"]["utility"].get(utility, "")) == id: return _result(false, "This companion is already assigned.")
		data["world"]["utility"][utility] = id
		return _result(true, "%s assigned to %s utility. Benefits apply next day while care is adequate." % [name, utility])
	if action == "unassign_utility":
		var utility := String(definition["utility"])
		if String(data["world"]["utility"].get(utility, "")) != id: return _result(false, "This companion is not assigned.")
		data["world"]["utility"].erase(utility)
		return _result(true, "Unassigned %s." % name)
	var energy_cost := 1 if action in ["pet", "treat"] else 2
	if int(data["energy"]) < energy_cost: return _result(false, "Need %d energy for care." % energy_cost)
	match action:
		"treat":
			if String(definition["kind"]) != "dragon": return _result(false, "Dragon Cake is a dragon-only mood supplement, not species food.")
			if int(state["happiness"]) >= 100: return _result(false, "This dragon is already content.")
			if int(data["inventory"].get("dragon_treat", 0)) <= 0: return _result(false, "Craft a Warm Dragon Cake first.")
			_pay(data, 0, {"dragon_treat": 1})
			state["happiness"] = mini(100, int(state["happiness"]) + 25)
		"feed":
			if int(state["fullness"]) >= 100: return _result(false, "This companion is already full.")
			var food := FoodResolver.resolve(data, id)
			if int(data["inventory"].get(food, 0)) <= 0: return _result(false, "Need the species food: %s." % _item_name(String(definition["food"])))
			_pay(data, 0, {food: 1})
			state["fullness"] = mini(100, int(state["fullness"]) + 30)
			state["last_fed_day"] = int(data["day"])
		"clean":
			if int(state["cleanliness"]) >= 100: return _result(false, "This companion is already clean.")
			state["cleanliness"] = mini(100, int(state["cleanliness"]) + 30)
		"pet":
			if int(state["happiness"]) >= 100: return _result(false, "This companion is already content.")
			state["happiness"] = mini(100, int(state["happiness"]) + 25)
		"heal":
			var disease := String(state.get("disease", ""))
			if disease.is_empty(): return _result(false, "This companion is healthy.")
			var medicine := "medicine_" + disease
			if not WorldData.config()["items"].has(medicine): return _result(false, "No configured cure for this disease.")
			if int(data["inventory"].get(medicine, 0)) <= 0: return _result(false, "Need %s for %s." % [_item_name(medicine), disease])
			_pay(data, 0, {medicine: 1})
			state["disease"] = ""
			state["neglect_days"] = 0
			state["happiness"] = mini(100, int(state["happiness"]) + 10)
	data["energy"] = int(data["energy"]) - energy_cost
	_stat(data, "care")
	if id == "cloud_chicken": _write_chicken(data)
	return _result(true, "%s: %s complete." % [name, action.capitalize()])


static func _egg_action(data: Dictionary, action: String, id: String) -> Dictionary:
	var eggs: Dictionary = WorldData.config()["eggs"]
	if not eggs.has(id): return _result(false, "Unknown egg.")
	var definition: Dictionary = eggs[id]
	var species := String(definition["species"])
	var requirements := _requirements(data, definition)
	if not requirements["ok"]: return requirements
	if data["world"]["creatures"].has(species): return _result(false, "This dragon is already in your collection.")
	if action == "buy_egg":
		if data["world"]["incubators"].has(id) or int(data["inventory"].get(id, 0)) > 0:
			return _result(false, "You already own or incubate this egg.")
		var payment := _can_pay(data, int(definition["cost"]), {})
		if not payment["ok"]: return payment
		var dragon_cost := int(definition.get("energy_cost", 0))
		if int(data["world"]["dragon_energy"]) < dragon_cost: return _result(false, "Need %d Dragon Energy." % dragon_cost)
		_pay(data, int(definition["cost"]), {})
		data["world"]["dragon_energy"] = int(data["world"]["dragon_energy"]) - dragon_cost
		_add(data, id, 1)
		return _result(true, "Bought %s." % String(definition["name"]))
	if action == "incubate":
		if data["world"]["incubators"].has(id): return _result(false, "This egg is already incubating.")
		if int(data["inventory"].get(id, 0)) <= 0: return _result(false, "Buy or craft this egg first.")
		if data["world"]["incubators"].size() >= 3: return _result(false, "All three incubators are occupied; hatch a ready egg first.")
		_pay(data, 0, {id: 1})
		data["world"]["incubators"][id] = {"progress": 0, "required": int(definition["days"]), "ready": false, "started_day": int(data["day"])}
		return _result(true, "%s is incubating for %d days." % [String(definition["name"]), int(definition["days"])])
	var incubator: Dictionary = data["world"]["incubators"].get(id, {})
	if not bool(incubator.get("ready", false)): return _result(false, "This egg is not ready to hatch.")
	data["world"]["creatures"][species] = WorldData.creature_state()
	data["world"]["incubators"].erase(id)
	_stat(data, "hatch")
	data["last_rewards"] = [{"label": "Dragon hatched", "value": String(WorldData.config()["creatures"][species]["name"])}]
	return _result(true, "Hatched %s! Care for it with %s." % [String(WorldData.config()["creatures"][species]["name"]), _item_name(String(WorldData.config()["creatures"][species]["food"]))])


static func _gather(data: Dictionary, id: String) -> Dictionary:
	var islands: Dictionary = WorldData.config()["islands"]
	if not islands.has(id) or not _owns_island(data, id): return _result(false, "Unlock this island first.")
	if int(data["world"]["gather_days"].get(id, 0)) == int(data["day"]): return _result(false, "Already gathered here today; return tomorrow.")
	if int(data["energy"]) < 4: return _result(false, "Need 4 energy to gather.")
	var definition: Dictionary = islands[id]
	var amount := int(definition["gather_amount"])
	if int(data["world"]["buildings"].get("warehouse", 0)) > 0: amount += 1
	var utilities := active_utilities(data)
	if utilities.has("storage"): amount += 1
	_add(data, String(definition["gather_item"]), mini(3, amount))
	data["energy"] = int(data["energy"]) - 4
	data["world"]["gather_days"][id] = int(data["day"])
	_stat(data, "gather")
	return _result(true, "Gathered %s x%d from %s." % [_item_name(String(definition["gather_item"])), mini(3, amount), String(definition["name"])])


static func _claim_event(data: Dictionary, id: String) -> Dictionary:
	var events: Dictionary = WorldData.config()["events"]
	if not events.has(id): return _result(false, "Unknown event.")
	if data["world"]["claimed_events"].has(id): return _result(false, "This reward has already been claimed.")
	var definition: Dictionary = events[id]
	var stat := String(definition["stat"])
	var progress := int(data.get(stat, data["world"]["stats"].get(stat, 0)))
	if progress < int(definition["target"]): return _result(false, "Progress: %d / %d." % [progress, int(definition["target"])])
	if definition.has("season") and season(data) != String(definition["season"]): return _result(false, "This event is available during %s." % String(definition["season"]).capitalize())
	var ingredients: Dictionary = definition.get("ingredients", {})
	var payment := _can_pay(data, 0, ingredients)
	if not payment["ok"]: return payment
	_pay(data, 0, ingredients)
	data["coins"] = int(data["coins"]) + int(definition["coins"])
	for item in definition["items"]: _add(data, item, int(definition["items"][item]))
	data["world"]["claimed_events"].append(id)
	data["last_rewards"] = [{"label": String(definition["name"]), "value": "+%d coins" % int(definition["coins"])}]
	return _result(true, "Claimed %s: %d coins and supplies." % [String(definition["name"]), int(definition["coins"])])


static func _field_harvest_fruit_due(data: Dictionary) -> bool:
	# Predict the next committed harvest, before stats/Long Vein are incremented.
	# The same predicate owns preview and reward delivery, including the rare roll.
	var world: Dictionary = data.get("world", {})
	var harvests := int(world.get("stats", {}).get("harvest", 0)) + 1
	var rare_roll := posmod(harvests * 17 + int(data.get("day", 1)) * 7 + int(data.get("selected_slot", 1)) * 13, 20) == 0
	return rare_roll or int(world.get("long_vein", 0)) + 1 >= 12


static func field_harvest_rewards(data: Dictionary, crop: String) -> Dictionary:
	var rewards := {"crop_" + crop: 1}
	if _field_harvest_fruit_due(data): rewards["ancient_fruit"] = 1
	return rewards


static func record_field_action(data: Dictionary, action: String, crop := "") -> void:
	var fruit_due := action == "harvest" and _field_harvest_fruit_due(data)
	var stat := "plant" if action == "seed" else action
	_stat(data, stat)
	if data.get("event_progress", {}).has(action):
		data["event_progress"][action] = int(data["event_progress"].get(action, 0)) + 1
	if action != "harvest": return
	data["world"]["long_vein"] = int(data["world"]["long_vein"]) + 1
	if fruit_due:
		_add(data, "ancient_fruit", 1)
		data["world"]["long_vein"] = 0
		data["world"]["last_result"] = "Ancient Dragon Fruit discovered! Keep it for the Dragon Altar."


static func active_utilities(data: Dictionary) -> Dictionary:
	var active: Dictionary = {}
	for utility in data["world"]["utility"]:
		var species := String(data["world"]["utility"][utility])
		var state: Dictionary = data["world"]["creatures"].get(species, {})
		if _care_ok(state): active[utility] = species
	return active


static func advance_world_day(data: Dictionary) -> void:
	sync_chicken(data)
	var world: Dictionary = data["world"]
	var config: Dictionary = WorldData.config()
	var seasonal: Dictionary = config["seasons"][season(data)]
	var utilities := active_utilities(data)
	var preservation := 2 if int(world["buildings"].get("icehouse", 0)) > 0 or utilities.has("storage") else 0
	for species in world["creatures"]:
		var definition: Dictionary = config["creatures"].get(species, {})
		if definition.is_empty(): continue
		var state: Dictionary = world["creatures"][species]
		if _care_ok(state):
			var stored_products := int(state["products_ready"])
			state["products_ready"] = maxi(stored_products, mini(6 if species == "cloud_chicken" else 3, stored_products + 1))
			state["neglect_days"] = 0
		else:
			state["neglect_days"] = int(state.get("neglect_days", 0)) + 1
		state["age_days"] = int(state.get("age_days", 0)) + 1
		state["fullness"] = maxi(0, int(state["fullness"]) - int(seasonal["fullness_decay"]) + preservation)
		state["cleanliness"] = maxi(0, int(state["cleanliness"]) - int(seasonal["cleanliness_decay"]) + preservation)
		state["happiness"] = maxi(0, int(state["happiness"]) - (3 if int(state["fullness"]) < 40 or int(state["cleanliness"]) < 40 else 1))
		if int(state["neglect_days"]) >= 3 and not utilities.has("health") and String(state["disease"]).is_empty():
			state["disease"] = String(definition["care_disease"])
	_write_chicken(data)
	for garden_id in world["gardens"]:
		var garden: Dictionary = world["gardens"][garden_id]
		var definition: Dictionary = config["gardens"].get(garden_id, {})
		if definition.is_empty(): continue
		if bool(garden.get("watered_today", false)) and not bool(garden.get("ready", false)):
			var growth := 1
			if String(definition["season"]) == season(data) and posmod(int(data["day"]), int(seasonal["garden_growth_interval"])) == 0: growth += 1
			garden["growth"] = mini(int(definition["days"]), int(garden.get("growth", 0)) + growth)
			garden["ready"] = int(garden["growth"]) >= int(definition["days"])
		garden["watered_today"] = false
	var speed := 1
	if int(world["buildings"].get("forge", 0)) > 0 or utilities.has("hatch"): speed = 2
	for egg_id in world["incubators"]:
		var incubator: Dictionary = world["incubators"][egg_id]
		incubator["progress"] = mini(int(incubator["required"]), int(incubator["progress"]) + speed)
		incubator["ready"] = int(incubator["progress"]) >= int(incubator["required"])
	for task in world["craft_queue"]:
		task["progress"] = mini(int(task["required"]), int(task["progress"]) + speed)
		task["ready"] = int(task["progress"]) >= int(task["required"])
	# Utilities never produce coins or harvest farm crops. Water uses the current
	# approved plot dictionaries after their daily reset and applies at most two.
	if utilities.has("water"):
		var count := 0
		var limit := 2 if String(utilities["water"]) == "water_dragon" else 1
		for plot in data["field_plots"]:
			if count >= limit: break
			if not bool(plot.get("locked", false)) and not String(plot.get("crop", "")).is_empty() and not bool(plot.get("ready_to_harvest", false)):
				plot["watered_today"] = true
				plot["last_watered_day"] = int(data["day"])
				count += 1
	if utilities.has("garden") and _owns_island(data, "botanical"):
		if int(data["inventory"].get("seed_mint", 0)) > 0 or inventory_stacks(data) < inventory_capacity(data): _add(data, "seed_mint", 1)
	if utilities.has("gather"):
		var species := String(utilities["gather"])
		var item := "dragon_crystal" if species == "gold_dragon" else "stone"
		if int(data["inventory"].get(item, 0)) > 0 or inventory_stacks(data) < inventory_capacity(data): _add(data, item, 1)
