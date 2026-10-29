extends Node

const FarmData = preload("res://scripts/farm_data.gd")
const SaveServiceClass = preload("res://scripts/save_service.gd")
const WorldData = preload("res://scripts/world_data.gd")
const WorldSystems = preload("res://scripts/world_systems.gd")
const StateValidator = preload("res://scripts/save_state_validator.gd")
const Fields = preload("res://scripts/field_zones.gd")

signal changed
signal status_changed(text: String)

var data: Dictionary = {}
var save_service
var selected_slot := 1
var save_mode := "new"
var confirm_action := ""
var settings_return := "title"
var settings_draft := {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}
var status := ""
var status_context := "gameplay" # Transient presentation channel, never serialized.
var _save_notice_source := "" # Keep a real save failure when unrelated gameplay emits status.
var _order_submit_in_progress := false
var _farm_session_active := false # Transient only; not a new save-schema field.
var _title_preferences := {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}
var _settings_baseline: Dictionary = {}


func _ready() -> void:
	var save_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	if save_root.is_empty() and QARichFixture.requested():
		save_root = "user://qa_rich"
	save_service = SaveServiceClass.new(save_root if not save_root.is_empty() else "user://")
	save_service.migrate_legacy_save_if_needed()
	new_state(1, false)
	# Boot defaults exist for presentation, not as permission to overwrite Slot1.
	_farm_session_active = false
	_load_title_preferences()
	settings_draft = _title_preferences.duplicate(true)
	_settings_baseline = settings_draft.duplicate(true)
	_ensure_audio_buses()
	apply_audio_settings()
	apply_display_settings()


func new_state(slot_id: int, persist := true) -> bool:
	var previous := data.duplicate(true)
	var previous_slot := selected_slot
	var previous_settings := settings_draft.duplicate(true)
	var previous_active := _farm_session_active
	var previous_baseline := _settings_baseline.duplicate(true)
	data = FarmData.create_initial_state()
	data["selected_slot"] = slot_id
	WorldSystems.sync_chicken(data)
	selected_slot = slot_id
	settings_draft = _settings_from_data()
	_farm_session_active = true
	_settings_baseline = settings_draft.duplicate(true)
	if persist and not _save_core_action(previous, "hub"):
		selected_slot = previous_slot
		settings_draft = previous_settings
		_farm_session_active = previous_active
		_settings_baseline = previous_baseline
		return false
	changed.emit()
	return true


func save(location := "hub") -> bool:
	if data.is_empty() or not _farm_session_active:
		set_status("Start or load a farm before saving.", false, "save")
		return false
	var ok := bool(save_service.save_current_slot(int(data.get("selected_slot", selected_slot)), data, location).get("ok", false))
	if ok:
		_save_notice_source = ""
	else:
		set_status("Save failed. Your progress is not confirmed saved.\nPlease retry.", false, "save")
	return ok


func load_slot(slot_id: int) -> bool:
	var result: Dictionary = save_service.load_slot(slot_id)
	if not result.get("ok", false):
		set_status("Cannot load this save. Recover a backup or choose another slot.", false, "save")
		return false
	return _accept_loaded_state(result["state"], slot_id)


func _accept_loaded_state(raw: Dictionary, slot_id: int) -> bool:
	var validation := StateValidator.validate_state(raw)
	if not validation["ok"]:
		set_status("Cannot load this save. Recover a backup or choose another slot.", false, "save")
		return false
	var candidate := normalize_state(raw)
	validation = StateValidator.validate_state(candidate)
	if not validation["ok"]:
		set_status("Cannot load this save. Recover a backup or choose another slot.", false, "save")
		return false
	data = candidate
	data["selected_slot"] = slot_id
	selected_slot = slot_id
	_farm_session_active = true
	settings_draft = _settings_from_data()
	_settings_baseline = settings_draft.duplicate(true)
	apply_audio_settings()
	apply_display_settings()
	_save_notice_source = ""
	changed.emit()
	return true


func recover_slot(slot_id: int) -> bool:
	var result: Dictionary = save_service.recover_slot(slot_id)
	if not result.get("ok", false):
		set_status("Could not recover this save. Original files were kept.", false, "save")
		return false
	if not _accept_loaded_state(result["state"], slot_id): return false
	set_status("Recovered save slot %d. Original recovery copies were kept." % slot_id, false, "save")
	return true


func cancel_confirmation() -> void:
	confirm_action = ""


func has_active_farm() -> bool:
	return _farm_session_active


func normalize_state(loaded: Dictionary) -> Dictionary:
	var base := FarmData.create_initial_state()
	for key in loaded:
		base[key] = loaded[key]
	base["save_version"] = maxi(4, int(base.get("save_version", 4)))
	base["world"] = WorldData.normalize_state(base.get("world", {}) if base.get("world", {}) is Dictionary else {})
	# Migrate the old HUD resource once, then keep one authoritative balance.
	var loaded_world: Dictionary = loaded.get("world", {}) if loaded.get("world", {}) is Dictionary else {}
	if not loaded_world.has("dragon_energy"):
		base["world"]["dragon_energy"] = maxi(0, int(loaded.get("long_khi", 0)))
	base["long_khi"] = int(base["world"]["dragon_energy"])
	base["inventory"] = WorldData.merge_defaults(FarmData.create_initial_state()["inventory"], base.get("inventory", {}) if base.get("inventory", {}) is Dictionary else {})
	base["animal"] = WorldData.merge_defaults(FarmData.create_initial_state()["animal"], base.get("animal", {}) if base.get("animal", {}) is Dictionary else {})
	if not base.get("field_plots", []) is Array:
		base["field_plots"] = FarmData.create_initial_state()["field_plots"]
	while base["field_plots"].size() < 12:
		base["field_plots"].append(FarmData.create_initial_state()["field_plots"][base["field_plots"].size()])
	for i in range(mini(12, base["field_plots"].size())):
		if not base["field_plots"][i] is Dictionary:
			base["field_plots"][i] = FarmData.create_initial_state()["field_plots"][i]
		var plot: Dictionary = base["field_plots"][i]
		if plot.has("fertilized") and not plot.has("fertilizer_pending"):
			plot["fertilizer_pending"] = bool(plot["fertilized"])
		plot.erase("fertilized")
		plot = WorldData.merge_defaults(FarmData.create_initial_state()["field_plots"][i], plot)
		for k in ["is_hoed", "watered_today", "fertilizer_pending", "ready_to_harvest"]:
			if not plot.has(k): plot[k] = false
		if not plot.has("planted_day"): plot["planted_day"] = -1
		if not plot.has("last_watered_day"): plot["last_watered_day"] = -1
		base["field_plots"][i] = plot
	Fields.normalize(base, FarmData.create_initial_state()["field_plots"])
	var selected_crop := String(base.get("selected_seed", "carrot"))
	var required_orders := {"carrot": 0, "tomato": 1, "pumpkin": 2}
	if not required_orders.has(selected_crop) or int(base.get("orders_done", 0)) < int(required_orders[selected_crop]):
		base["selected_seed"] = "carrot"
	WorldSystems.sync_chicken(base)
	return base


func world_state() -> Dictionary:
	return data.get("world", {}).duplicate(true)


func world_config() -> Dictionary:
	return WorldData.config().duplicate(true)


func current_season() -> String:
	return WorldSystems.season(data)


func dragon_energy() -> int:
	return int(data.get("world", {}).get("dragon_energy", data.get("long_khi", 0)))


func world_inventory_capacity() -> int:
	return WorldSystems.inventory_capacity(data)


func world_action_info(action: String, id: String = "") -> Dictionary:
	if data.is_empty(): return {"ok": false, "reason": "Start or load a farm first."}
	return WorldSystems.act(data.duplicate(true), action, id)


func world_action(action: String, id: String = "", notify := true) -> bool:
	if data.is_empty(): return false
	var candidate := data.duplicate(true)
	var outcome := WorldSystems.act(candidate, action, id)
	if not bool(outcome.get("ok", false)):
		set_status(String(outcome.get("reason", "Action unavailable.")))
		return false
	var previous := data
	data = candidate
	data["long_khi"] = dragon_energy() # Compatibility alias, never a second wallet.
	data["status_text"] = String(outcome["reason"])
	if not save("world"):
		data = previous
		set_status("Could not save this action; your previous farm state was kept.", true, "save")
		return false
	set_status(String(outcome["reason"]))
	if notify: changed.emit()
	return true


func slot_metadata(slot_id: int) -> Dictionary:
	return save_service.get_slot_metadata(slot_id)


func latest_slot() -> int:
	return save_service.get_latest_valid_slot()


func choose_slot(slot_id: int) -> void:
	selected_slot = slot_id
	confirm_action = ""
	changed.emit()


func confirm_slot() -> bool:
	var meta := slot_metadata(selected_slot)
	if save_mode == "continue":
		return load_slot(selected_slot)
	if meta.get("occupied", false) and confirm_action != "overwrite":
		confirm_action = "overwrite"
		set_status("Nhan Confirm lan nua de ghi de Slot %d." % selected_slot, true, "save")
		return false
	if not new_state(selected_slot, true): return false
	confirm_action = ""
	return true


func delete_selected_slot() -> bool:
	if confirm_action != "delete":
		confirm_action = "delete"
		set_status("Nhan Delete lan nua de xoa Slot %d." % selected_slot, true, "save")
		return false
	var outcome: Dictionary = save_service.delete_slot(selected_slot)
	var ok := bool(outcome.get("ok", false))
	confirm_action = ""
	set_status("Deleted slot %d. A deleted copy is kept on this device." % selected_slot if ok else "Could not delete this slot. Original files were kept.", false, "save")
	changed.emit()
	return ok


func select_plot(plot_id: int) -> void:
	data["selected_plot"] = plot_id
	changed.emit()


func select_plot_silent(plot_id: int) -> void:
	data["selected_plot"] = plot_id


func is_crop_unlocked(crop_id: String) -> bool:
	match crop_id:
		"carrot": return true
		"tomato": return int(data.get("orders_done", 0)) >= 1
		"pumpkin": return int(data.get("orders_done", 0)) >= 2
	return false


func select_seed(crop_id: String, notify := true) -> bool:
	if not FarmData.CROP_DEFINITIONS.has(crop_id) or not is_crop_unlocked(crop_id):
		set_status("Cây trồng này chưa được mở khóa.")
		return false
	data["selected_seed"] = crop_id
	if notify:
		changed.emit()
	return true


func get_plot(plot_id := -1) -> Dictionary:
	var target := plot_id if plot_id > 0 else int(data.get("selected_plot", 1))
	for plot in field_plots():
		if int(plot["id"]) == target:
			return plot
	return {}


func field_plots(zone := "") -> Array:
	return Fields.plots(data, zone)


func active_field_zone() -> String:
	return Fields.active_id(data)


func is_field_zone_open(zone: String) -> bool:
	return Fields.is_open(data, zone)


func select_field_zone(zone: String, notify := true) -> bool:
	if not Fields.IDS.has(zone): return false
	if not is_field_zone_open(zone):
		set_status(tr("This field opens on day %d.") % Fields.open_day(zone), false)
		return false
	if zone == active_field_zone(): return true
	var previous := data.duplicate(true)
	data["active_field_zone"] = zone
	data["selected_plot"] = 1
	if not _save_core_action(previous, "field_select"): return false
	if notify: changed.emit()
	return true


func field_action_allowed(action: String, plot := {}) -> bool:
	if not is_field_zone_open(active_field_zone()): return false
	var p: Dictionary = get_plot() if plot.is_empty() else plot
	if p.is_empty() or bool(p.get("locked", false)) or not has_energy(action): return false
	match action:
		"till": return not bool(p["is_hoed"])
		"seed":
			var crop := String(data.get("selected_seed", "carrot"))
			return is_crop_unlocked(crop) and bool(p["is_hoed"]) and String(p["crop"]).is_empty() and int(data["inventory"].get("seed_" + crop, 0)) > 0
		"water": return bool(p["is_hoed"]) and not String(p["crop"]).is_empty() and not bool(p["watered_today"]) and not bool(p["ready_to_harvest"])
		"fertilize": return bool(p["is_hoed"]) and not String(p["crop"]).is_empty() and not bool(p["fertilizer_pending"]) and not bool(p["ready_to_harvest"])
		"harvest": return bool(field_harvest_info(p).ok)
	return false


func field_harvest_info(plot := {}) -> Dictionary:
	# Same read-only reward/capacity preflight for toolbar, bed and transaction.
	# Existing over-capacity saves may add to an existing stack, not a new one.
	var p: Dictionary = get_plot() if plot.is_empty() else plot
	var reason := ""
	if not is_field_zone_open(active_field_zone()): reason = "This plot is locked."
	elif p.is_empty() or bool(p.get("locked", false)): reason = "This plot is locked."
	elif not bool(p.get("ready_to_harvest", false)) or not FarmData.CROP_DEFINITIONS.has(String(p.get("crop", ""))): reason = "Nothing is ready to harvest."
	elif not has_energy("harvest"): reason = "Need %d energy; you have %d.\nNext Day restores 100." % [int(FarmData.ACTION_ENERGY_COSTS.harvest), int(data.get("energy", 0))]
	var item := "crop_" + String(p.get("crop", ""))
	var amount := 1
	var rewards := WorldSystems.field_harvest_rewards(data, String(p.get("crop", "")))
	var stacks := WorldSystems.inventory_stacks(data)
	var capacity := WorldSystems.inventory_capacity(data)
	var stacks_after := stacks
	for reward_item in rewards:
		if int(data.get("inventory", {}).get(reward_item, 0)) <= 0: stacks_after += 1
	if reason.is_empty() and stacks_after > maxi(capacity, stacks):
		reason = "Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % capacity
	return {"ok": reason.is_empty(), "reason": UILocale.translate_message(reason), "reward_item": item, "reward_amount": amount, "rewards": rewards, "stacks": stacks, "stacks_after": stacks_after, "capacity": capacity}


func apply_field_action(action: String) -> bool:
	return apply_field_action_on_plot(int(data.get("selected_plot", 1)), action)


func apply_field_action_on_plot(plot_id: int, action: String, notify := true) -> bool:
	var index := plot_id - 1
	var beds := field_plots()
	if index < 0 or index >= beds.size(): return false
	var previous := data.duplicate(true)
	data["selected_plot"] = plot_id
	var plot: Dictionary = beds[index]
	if not field_action_allowed(action, plot):
		set_status(String(field_harvest_info(plot).reason) if action == "harvest" else "Khong the thuc hien: trang thai hoac nang luong khong du.")
		return false
	var harvest_reward := field_harvest_info(plot) if action == "harvest" else {}
	use_energy(action)
	match action:
		"till": plot["is_hoed"] = true
		"seed":
			var crop := String(data["selected_seed"])
			plot["crop"] = crop
			plot["growth_stage"] = 0
			plot["planted_day"] = int(data.get("day", 1))
			data["inventory"]["seed_" + crop] -= 1
		"water":
			plot["watered_today"] = true
			plot["last_watered_day"] = int(data.get("day", 1))
		"fertilize": plot["fertilizer_pending"] = true
		"harvest":
			var item := String(harvest_reward.reward_item)
			data["inventory"][item] = int(data["inventory"].get(item, 0)) + int(harvest_reward.reward_amount)
			# Approved repeat loop: harvest returns soil to its original untilled state.
			plot["is_hoed"] = false
			plot["crop"] = ""
			plot["growth_stage"] = 0
			plot["watered_today"] = false
			plot["fertilizer_pending"] = false
			plot["ready_to_harvest"] = false
			plot["planted_day"] = -1
	beds[index] = plot
	WorldSystems.record_field_action(data, action)
	if not _save_core_action(previous, "field"): return false
	if notify:
		changed.emit()
	return true


func advance_day(notify := true) -> bool:
	# Reject malformed input before changing day, energy or any crop. Validation
	# is feedback-only and never guesses an unknown crop into a different one.
	var validation := StateValidator.validate_state(data)
	if not validation["ok"]:
		set_status("Cannot advance the day: farm data is invalid. Load a valid save or recover a backup.", false)
		return false
	var previous := data.duplicate(true)
	data["day"] = int(data.get("day", 1)) + 1
	data["energy"] = 100
	for zone in Fields.IDS:
		var beds := field_plots(zone)
		for i in range(beds.size()):
			var plot: Dictionary = beds[i]
			if not String(plot["crop"]).is_empty() and bool(plot["watered_today"]):
				var bonus := 1 if bool(plot["fertilizer_pending"]) else 0
				plot["growth_stage"] = int(plot["growth_stage"]) + 1 + bonus
				plot["fertilizer_pending"] = false
				var max_stage := int(FarmData.CROP_DEFINITIONS[plot["crop"]]["max_stage"])
				plot["growth_stage"] = mini(int(plot["growth_stage"]), max_stage)
				plot["ready_to_harvest"] = int(plot["growth_stage"]) >= max_stage
			plot["watered_today"] = false
			beds[i] = plot
	WorldSystems.advance_world_day(data)
	if not _save_core_action(previous, "field"): return false
	if notify:
		changed.emit()
	return true


func buy(item_id: String) -> bool:
	if item_id.begins_with("seed_"):
		var crop_id := item_id.trim_prefix("seed_")
		if FarmData.CROP_DEFINITIONS.has(crop_id) and not is_crop_unlocked(crop_id):
			set_status("Hạt giống này chưa được mở khóa.")
			return false
	for item in FarmData.SHOP_ITEMS:
		if item["id"] == item_id and int(data["coins"]) >= int(item["price"]):
			var previous := data.duplicate(true)
			data["coins"] -= int(item["price"])
			data["inventory"][item_id] = int(data["inventory"].get(item_id, 0)) + int(item["amount"])
			if not _save_core_action(previous, "shop"): return false
			set_status("Da mua %s." % item["label"])
			changed.emit()
			return true
	set_status("Khong du tien.")
	return false


func sell(item_id: String) -> bool:
	if int(data["inventory"].get(item_id, 0)) <= 0 or not item_id.begins_with("crop_"):
		set_status("Khong co nong san de ban.")
		return false
	var crop := item_id.trim_prefix("crop_")
	if not FarmData.CROP_DEFINITIONS.has(crop): return false
	var previous := data.duplicate(true)
	data["inventory"][item_id] -= 1
	data["coins"] += int(FarmData.CROP_DEFINITIONS[crop]["sell_value"])
	if not _save_core_action(previous, "storage"): return false
	set_status("Da ban %s." % FarmData.CROP_DEFINITIONS[crop]["label"])
	changed.emit()
	return true


func use_item(item_id: String) -> bool:
	if item_id != "medicine" or int(data["inventory"].get(item_id, 0)) <= 0: return false
	if int(data.get("energy", 0)) >= 100:
		set_status("Farm energy is already full.")
		return false
	var previous := data.duplicate(true)
	data["inventory"][item_id] -= 1
	data["energy"] = mini(100, int(data["energy"]) + 25)
	if not _save_core_action(previous, "storage"): return false
	changed.emit()
	return true


func animal_action_info(action: String) -> Dictionary:
	# This legacy chicken preview is also the transaction's preflight. Keeping
	# it read-only prevents UI eligibility, resource use and success VFX drifting.
	if action not in ["collect", "feed_animals", "clean_animals", "pet_animals"]:
		return {"ok": false, "reason": "Action unavailable."}
	var animal: Dictionary = data.get("animal", {})
	if action == "collect":
		if int(animal.get("eggs_ready", 0)) <= 0:
			return {"ok": false, "reason": UILocale.translate_message("No product ready. Feed, clean and pet this companion, then advance the day.")}
		var stacks := WorldSystems.inventory_stacks(data)
		var new_stack := int(data.get("inventory", {}).get("egg", 0)) <= 0
		if new_stack and stacks + 1 > maxi(WorldSystems.inventory_capacity(data), stacks):
			return {"ok": false, "reason": UILocale.translate_message("Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % WorldSystems.inventory_capacity(data))}
		return {"ok": true, "reason": ""}
	var meter := "fullness" if action == "feed_animals" else "cleanliness" if action == "clean_animals" else "happiness"
	if int(animal.get(meter, 0)) >= 100:
		var reason := "This companion is already full." if meter == "fullness" else "This companion is already clean." if meter == "cleanliness" else "This companion is already content."
		return {"ok": false, "reason": UILocale.translate_message(reason)}
	if not has_energy(action):
		return {"ok": false, "reason": UILocale.translate_message("Need %d energy for care." % int(FarmData.ACTION_ENERGY_COSTS.get(action, 0)))}
	var food := preload("res://scripts/creature_food_resolver.gd").resolve(data, "cloud_chicken")
	if action == "feed_animals" and int(data.get("inventory", {}).get(food, 0)) <= 0:
		var food_name := String(WorldData.config().get("items", {}).get(food, {}).get("name", food))
		return {"ok": false, "reason": UILocale.translate_message("Need the species food: %s." % food_name)}
	return {"ok": true, "reason": "", "food": food}


func animal_action(action: String) -> bool:
	var eligibility := animal_action_info(action)
	if not bool(eligibility.get("ok", false)):
		set_status(String(eligibility.get("reason", "Action unavailable.")))
		return false
	var previous := data.duplicate(true)
	var animal: Dictionary = data["animal"]
	if action == "collect":
		if int(animal["eggs_ready"]) <= 0:
			set_status("Chua co trung san sang.")
			return false
		data["inventory"]["egg"] += int(animal["eggs_ready"])
		animal["eggs_ready"] = 0
		set_status("Da thu trung vao Kho.")
	elif not has_energy(action):
		set_status("Khong du nang luong.")
		return false
	else:
		use_energy(action)
		match action:
			"feed_animals":
				var food := String(eligibility["food"])
				data["inventory"][food] -= 1
				animal["fullness"] = mini(100, int(animal["fullness"]) + 25)
				set_status("Da cho ga an.")
			"clean_animals":
				animal["cleanliness"] = mini(100, int(animal["cleanliness"]) + 25)
				set_status("Da don dep chuong.")
			"pet_animals":
				animal["happiness"] = mini(100, int(animal["happiness"]) + 20)
				set_status("Da vuot ve ga.")
	data["animal"] = animal
	WorldSystems.sync_chicken(data)
	if action == "feed_animals" and data.get("world", {}).get("creatures", {}).has("cloud_chicken"):
		data["world"]["creatures"]["cloud_chicken"]["last_fed_day"] = int(data.get("day", 1))
	if action == "collect":
		data["event_progress"]["collect"] = int(data["event_progress"].get("collect", 0)) + 1
		data["world"]["stats"]["animal_collect"] = int(data["world"]["stats"].get("animal_collect", 0)) + 1
	else:
		data["world"]["stats"]["care"] = int(data["world"]["stats"].get("care", 0)) + 1
	if not _save_core_action(previous, "animal"): return false
	changed.emit()
	return true


func get_active_order() -> Dictionary:
	if FarmData.ORDER_DEFINITIONS.is_empty():
		return {}
	var index := posmod(int(data.get("active_order_index", 0)), FarmData.ORDER_DEFINITIONS.size())
	return FarmData.ORDER_DEFINITIONS[index]


func can_submit_active_order() -> bool:
	return bool(submit_active_order_info().ok)


func submit_active_order_info() -> Dictionary:
	# Preview the exact exchange, including the stack freed by its last crop.
	# This is read-only and shares the authority's capacity rule for old saves.
	var order := get_active_order()
	if order.is_empty():
		return {"ok": false, "reason": UILocale.translate_message("Không có đơn hàng hợp lệ.")}
	var need_item := String(order["need_item"])
	var needed := int(order["need_amount"])
	var owned := int(data.get("inventory", {}).get(need_item, 0))
	if owned < needed:
		return {"ok": false, "reason": UILocale.translate_message("Chưa đủ vật phẩm: cần %d, hiện có %d." % [needed, owned])}
	var reward_item := String(order["reward_item"])
	var after: Dictionary = data.get("inventory", {}).duplicate()
	after[need_item] = owned - needed
	after[reward_item] = int(after.get(reward_item, 0)) + int(order["reward_amount"])
	var allowed_stacks := maxi(WorldSystems.inventory_capacity(data), WorldSystems.inventory_stacks(data))
	if WorldSystems.inventory_stacks({"inventory": after}) > allowed_stacks:
		return {"ok": false, "reason": UILocale.translate_message("Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % WorldSystems.inventory_capacity(data))}
	return {"ok": true, "reason": ""}


func submit_active_order() -> bool:
	if _order_submit_in_progress:
		return false
	var eligibility := submit_active_order_info()
	if not bool(eligibility.ok):
		set_status(String(eligibility.reason), false)
		return false
	var order := get_active_order()

	var previous := data.duplicate(true)
	_order_submit_in_progress = true
	var need_item := String(order["need_item"])
	var reward_item := String(order["reward_item"])
	data["inventory"][need_item] = int(data["inventory"].get(need_item, 0)) - int(order["need_amount"])
	data["inventory"][reward_item] = int(data["inventory"].get(reward_item, 0)) + int(order["reward_amount"])
	data["coins"] = int(data.get("coins", 0)) + int(order["reward_coins"])
	data["orders_done"] = int(data.get("orders_done", 0)) + 1
	data["active_order_index"] = (int(data.get("active_order_index", 0)) + 1) % FarmData.ORDER_DEFINITIONS.size()
	data["last_rewards"] = [
		{"label": "Xu", "value": "+%d" % int(order["reward_coins"])},
		{"label": FarmData.get_inventory_name(reward_item), "value": "+%d" % int(order["reward_amount"])},
	]
	if int(data["orders_done"]) >= 3:
		set_status("Đã hoàn thành mục tiêu nông trại đầu tiên!")
	else:
		set_status("Đã giao %s · nhận %d xu và %s x%d." % [String(order["title"]), int(order["reward_coins"]), FarmData.get_inventory_name(reward_item), int(order["reward_amount"])])
	if not _save_core_action(previous, "orders"):
		_order_submit_in_progress = false
		return false
	changed.emit()
	call_deferred("_unlock_order_submit")
	return true


func _unlock_order_submit() -> void:
	_order_submit_in_progress = false


# Keep the existing core loop atomic just like world_action. No new save schema
# or inventory is introduced. Loaded over-capacity saves may reduce/use their
# existing stacks, but an action cannot introduce another stack above capacity.
func _save_core_action(previous: Dictionary, location: String) -> bool:
	var allowed_stacks := maxi(WorldSystems.inventory_capacity(data), WorldSystems.inventory_stacks(previous))
	if WorldSystems.inventory_stacks(data) > allowed_stacks:
		data = previous
		set_status("Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % WorldSystems.inventory_capacity(data), false)
		return false
	if not save(location):
		data = previous
		set_status("Could not save this action; your previous farm state was kept.", false, "save")
		return false
	return true


func has_energy(action: String) -> bool:
	return int(data.get("energy", 0)) >= int(FarmData.ACTION_ENERGY_COSTS.get(action, 0))


func use_energy(action: String) -> void:
	data["energy"] -= int(FarmData.ACTION_ENERGY_COSTS.get(action, 0))


func update_setting(key: String, value) -> void:
	settings_draft[key] = value


func apply_settings() -> bool:
	if settings_use_global_preferences():
		if not _save_title_preferences(settings_draft):
			set_status("Could not save preferences. Farm save slots were not changed.", false)
			return false
		_title_preferences = settings_draft.duplicate(true)
		_settings_baseline = settings_draft.duplicate(true)
		apply_audio_settings()
		apply_display_settings()
		set_status("Preferences saved. Farm save slots were not changed.", false)
		changed.emit()
		return true
	var previous := data.duplicate(true)
	for key in settings_draft:
		data[key + "_volume" if key != "fullscreen" else key] = settings_draft[key]
	if not _save_core_action(previous, "settings"): return false
	_settings_baseline = settings_draft.duplicate(true)
	apply_audio_settings()
	apply_display_settings()
	changed.emit()
	return true


func settings_use_global_preferences() -> bool:
	return settings_return == "title" or not _farm_session_active


func begin_settings() -> void:
	settings_draft = _title_preferences.duplicate(true) if settings_use_global_preferences() else _settings_from_data()
	_settings_baseline = settings_draft.duplicate(true)


func settings_baseline() -> Dictionary:
	return _settings_baseline.duplicate(true)


func _settings_preferences_path() -> String:
	var isolated := OS.get_environment("MSF_TEST_SAVE_DIR")
	if not isolated.is_empty(): return isolated.path_join("settings_preferences.cfg")
	return "user://qa_rich/settings_preferences.cfg" if QARichFixture.requested() else "user://settings_preferences.cfg"


func _load_title_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_preferences_path()) != OK: return
	for key in ["master", "music", "sfx"]:
		var value = config.get_value("settings", key, _title_preferences[key])
		if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 100:
			_title_preferences[key] = float(value)
	var fullscreen = config.get_value("settings", "fullscreen", false)
	if fullscreen is bool: _title_preferences["fullscreen"] = fullscreen


func _save_title_preferences(preferences: Dictionary) -> bool:
	var config := ConfigFile.new()
	for key in ["master", "music", "sfx", "fullscreen"]:
		config.set_value("settings", key, preferences[key])
	var path := _settings_preferences_path()
	var temporary := path + ".tmp"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK: return false
	if config.save(temporary) != OK: return false
	var verification := ConfigFile.new()
	if verification.load(temporary) != OK: return false
	for key in ["master", "music", "sfx", "fullscreen"]:
		if verification.get_value("settings", key) != preferences[key]: return false
	# No farm slot path is used here. Keep the previous preference file as a
	# bounded backup, and return failure before applying the draft on any IO error.
	var target_abs := ProjectSettings.globalize_path(path)
	var temporary_abs := ProjectSettings.globalize_path(temporary)
	if DirAccess.dir_exists_absolute(target_abs): return false
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(target_abs, target_abs + ".bak") != OK: return false
		if DirAccess.remove_absolute(target_abs) != OK: return false
	if DirAccess.rename_absolute(temporary_abs, target_abs) != OK:
		if FileAccess.file_exists(path + ".bak"): DirAccess.copy_absolute(target_abs + ".bak", target_abs)
		return false
	return true


func reset_settings() -> void:
	settings_draft = {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}
	changed.emit()


func apply_audio_settings() -> void:
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(float(settings_draft[pair[1]]) / 100.0))


func apply_display_settings() -> void:
	preload("res://scripts/ui/mobile_runtime.gd").apply_display_settings(bool(settings_draft.get("fullscreen", false)))


func _settings_from_data() -> Dictionary:
	return {"master": float(data.get("master_volume", 80.0)), "music": float(data.get("music_volume", 70.0)), "sfx": float(data.get("sfx_volume", 85.0)), "fullscreen": bool(data.get("fullscreen", false))}


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func save_status_message() -> String:
	return UILocale.translate_message(_save_notice_source)


func set_status(text: String, persist_in_state := true, context := "gameplay") -> void:
	status = UILocale.translate_message(text)
	status_context = context
	if context == "save": _save_notice_source = text
	if persist_in_state: data["status_text"] = status
	status_changed.emit(status)
