extends Node

# Isolated authority tests only. No GUI, OS write denial, production schema,
# deleted files, or rich x999 balances are used to simulate save failures.
const FarmData = preload("res://scripts/farm_data.gd")
const Rules = preload("res://scripts/world_systems.gd")
const SLOT := 1

class FailingSaveService:
	extends RefCounted
	var calls := 0
	var read_service: RefCounted

	func save_current_slot(_slot_id: int, _state: Dictionary, _location: String = "hub") -> Dictionary:
		calls += 1
		return {"ok": false, "message": "Deterministic QA save failure."}

	func get_slot_metadata(slot_id: int) -> Dictionary:
		return read_service.call("get_slot_metadata", slot_id)

var failures: Array[String] = []
var checks := 0
var changed_emissions := 0
var real_save_service: RefCounted
var failing_save_service := FailingSaveService.new()
var checkpoint_state: Dictionary = {}


func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated_root.is_empty() or not qa_root.contains("gdd_closure_v3") or qa_root == player_root or player_root.begins_with(qa_root + "/"):
		push_error("Core transaction QA requires a fresh MSF_TEST_SAVE_DIR containing gdd_closure_v3, separate from and not above player saves.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		if FileAccess.file_exists(isolated_root.path_join("my_sisters_farm_slot_%d.save" % slot)):
			push_error("Core transaction QA refuses an occupied save root. Supply a fresh directory; existing saves are preserved.")
			get_tree().quit(2)
			return
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CORE_TRANSACTION_SAFETY: " + message)


func _on_changed() -> void:
	changed_emissions += 1


func _without_status(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("status_text")
	return result


func _fresh_fixture() -> Dictionary:
	# A normal loaded fixture includes the existing long_khi wallet alias.
	# All original inventory keys, including known zero stacks, are retained.
	var state := GameState.normalize_state(FarmData.create_initial_state())
	state["selected_slot"] = SLOT
	Rules.sync_chicken(state)
	return state


func _field_fixture(action: String) -> Dictionary:
	var state := _fresh_fixture()
	var plot: Dictionary = state["field_plots"][0]
	if action != "till":
		plot["is_hoed"] = true
	if action in ["water", "fertilize", "harvest"]:
		plot["crop"] = "carrot"
		plot["growth_stage"] = 4 if action == "harvest" else 1
		plot["planted_day"] = 1
		plot["ready_to_harvest"] = action == "harvest"
	state["field_plots"][0] = plot
	return state


func _day_fixture() -> Dictionary:
	var state := _field_fixture("water")
	state["energy"] = 45
	state["field_plots"][0]["watered_today"] = true
	state["field_plots"][0]["fertilizer_pending"] = true
	state["field_plots"][0]["last_watered_day"] = 1
	return state


func _animal_fixture() -> Dictionary:
	var state := _fresh_fixture()
	state["animal"] = {"fullness": 50, "cleanliness": 50, "happiness": 50, "eggs_ready": 2}
	Rules.sync_chicken(state)
	return state


func _full_fixture(unknown_stacks := 20) -> Dictionary:
	var state := _animal_fixture()
	for item_id in state["inventory"]:
		state["inventory"][item_id] = 0
	for index in range(unknown_stacks):
		state["inventory"]["qa_capacity_unknown_%02d" % index] = 1
	state["world"]["buildings"].erase("warehouse")
	return state


func _checkpoint(case_name: String, state: Dictionary) -> bool:
	GameState.save_service = real_save_service
	GameState.data = state.duplicate(true)
	GameState.selected_slot = SLOT
	_check(not bool(GameState.get("_order_submit_in_progress")), case_name + ": starts with order lock released")
	var saved := GameState.save("core_transaction_checkpoint")
	_check(saved, case_name + ": real isolated checkpoint saved")
	if not saved: return false
	var loaded: Dictionary = real_save_service.call("load_slot", SLOT)
	_check(bool(loaded.get("ok", false)), case_name + ": checkpoint readable by real SaveService")
	if not bool(loaded.get("ok", false)): return false
	checkpoint_state = (loaded.get("state", {}) as Dictionary).duplicate(true)
	_check(_without_status(checkpoint_state).has("inventory"), case_name + ": checkpoint uses original inventory schema")
	return true


func _assert_stored_checkpoint_unchanged(case_name: String) -> void:
	var loaded: Dictionary = real_save_service.call("load_slot", SLOT)
	_check(bool(loaded.get("ok", false)), case_name + ": rejected action leaves real checkpoint readable")
	if bool(loaded.get("ok", false)):
		_check((loaded.get("state", {}) as Dictionary) == checkpoint_state, case_name + ": stored checkpoint unchanged, including save metadata")


func _assert_checkpoint_unchanged(case_name: String) -> void:
	_assert_stored_checkpoint_unchanged(case_name)
	GameState.save_service = real_save_service
	var expected := GameState.normalize_state(checkpoint_state)
	var restored := GameState.load_slot(SLOT)
	_check(restored, case_name + ": GameState reloads the real checkpoint")
	if restored:
		_check(_without_status(GameState.data) == _without_status(expected), case_name + ": reload restores all original gameplay fields")


func _save_rejection(case_name: String, state: Dictionary, action: Callable, returns_bool := true) -> void:
	if not _checkpoint(case_name, state): return
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	var saves_before := failing_save_service.calls
	GameState.save_service = failing_save_service
	var result: Variant = action.call()
	if returns_bool:
		_check(result == false, case_name + ": reports save rejection")
	_check(failing_save_service.calls == saves_before + 1, case_name + ": valid action attempts exactly one fake save")
	_check(_without_status(GameState.data) == _without_status(before), case_name + ": all gameplay mutations roll back")
	_check(changed_emissions == emissions_before, case_name + ": rejection emits no changed signal")
	_check(not GameState.status.is_empty(), case_name + ": failure feedback remains available")
	_assert_checkpoint_unchanged(case_name)


func _capacity_rejection(case_name: String, state: Dictionary, action: Callable) -> void:
	if not _checkpoint(case_name, state): return
	_check(Rules.inventory_stacks(GameState.data) == 20, case_name + ": exactly twenty occupied fixture item types")
	_check(Rules.inventory_capacity(GameState.data) == 20, case_name + ": original capacity is twenty without Warehouse")
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	var result: Variant = action.call()
	_check(result == false, case_name + ": rejects a new occupied stack at capacity")
	_check(_without_status(GameState.data) == _without_status(before), case_name + ": capacity rejection rolls back all gameplay fields")
	_check(changed_emissions == emissions_before, case_name + ": capacity rejection emits no changed signal")
	_assert_checkpoint_unchanged(case_name)


func _assert_current_saved(case_name: String) -> void:
	var expected := _without_status(GameState.data)
	var loaded: Dictionary = real_save_service.call("load_slot", SLOT)
	_check(bool(loaded.get("ok", false)), case_name + ": successful action stored through real SaveService")
	if bool(loaded.get("ok", false)):
		var normalized := GameState.normalize_state(loaded.get("state", {}) as Dictionary)
		# SaveService adds metadata to its payload, not to the live dictionary.
		for key in ["last_screen", "saved_at_unix"]:
			normalized.erase(key)
			expected.erase(key)
		_check(_without_status(normalized) == expected, case_name + ": stored gameplay matches successful transaction")


func _order_save_failure_and_retry() -> void:
	var state := _fresh_fixture()
	state["inventory"]["crop_carrot"] = 1
	_save_rejection("order_submit_save_failure", state, GameState.submit_active_order)
	_check(not bool(GameState.get("_order_submit_in_progress")), "order rejection clears the re-entry lock")
	GameState.save_service = real_save_service
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	var order: Dictionary = GameState.get_active_order()
	_check(GameState.submit_active_order(), "same order retries successfully using real SaveService after failure")
	_check(changed_emissions == emissions_before + 1, "successful order retry emits changed exactly once")
	_check(int(GameState.data["inventory"]["crop_carrot"]) == int(before["inventory"]["crop_carrot"]) - int(order["need_amount"]), "order retry consumes the required crop exactly once")
	_check(int(GameState.data["inventory"]["seed_tomato"]) == int(before["inventory"]["seed_tomato"]) + int(order["reward_amount"]), "order retry grants the seed reward exactly once")
	_check(int(GameState.data["coins"]) == int(before["coins"]) + int(order["reward_coins"]), "order retry grants coins exactly once")
	_check(int(GameState.data["orders_done"]) == int(before["orders_done"]) + 1, "order retry advances original progress exactly once")
	_assert_current_saved("successful_order_retry")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not bool(GameState.get("_order_submit_in_progress")), "successful retry releases deferred order lock")


func _existing_stack_overcapacity() -> void:
	var state := _full_fixture(21)
	state["inventory"]["animal_feed"] = 2
	if not _checkpoint("existing_stack_overcapacity", state): return
	_check(GameState.load_slot(SLOT), "loaded old overcapacity fixture restores through original normalization")
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	var stacks_before := Rules.inventory_stacks(before)
	_check(stacks_before > Rules.inventory_capacity(before), "loaded fixture really begins above original item-type capacity")
	_check(GameState.buy("animal_feed"), "buying an already occupied stack remains allowed in loaded overcapacity save")
	_check(int(GameState.data["inventory"]["animal_feed"]) == int(before["inventory"]["animal_feed"]) + 2, "allowed existing-stack purchase grants only its authored amount")
	_check(int(GameState.data["coins"]) == int(before["coins"]) - 22, "allowed existing-stack purchase deducts its authored price")
	_check(Rules.inventory_stacks(GameState.data) == stacks_before, "existing-stack purchase adds no occupied item type")
	_check(changed_emissions == emissions_before + 1, "allowed existing-stack purchase emits changed once")
	_assert_current_saved("existing_stack_overcapacity")


func _order_frees_reward_slot() -> void:
	var state := _full_fixture(19)
	state["inventory"]["crop_carrot"] = 1
	if not _checkpoint("order_frees_reward_slot", state): return
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	_check(Rules.inventory_stacks(before) == Rules.inventory_capacity(before), "order fixture starts at the original twenty item-type capacity")
	_check(int(before["inventory"]["seed_tomato"]) == 0, "order reward is a new occupied item type")
	_check(GameState.submit_active_order(), "order consumption frees one item type before its reward is checked")
	_check(int(GameState.data["inventory"]["crop_carrot"]) == 0 and int(GameState.data["inventory"]["seed_tomato"]) == 3, "order replaces exactly the consumed crop type with its seed reward")
	_check(int(GameState.data["coins"]) == int(before["coins"]) + 70 and int(GameState.data["orders_done"]) == 1, "full-capacity order grants original reward/progress")
	_check(Rules.inventory_stacks(GameState.data) == 20, "order reward stays within shared original capacity")
	_check(changed_emissions == emissions_before + 1, "allowed full-capacity order emits changed once")
	_assert_current_saved("order_frees_reward_slot")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not bool(GameState.get("_order_submit_in_progress")), "full-capacity order releases its deferred lock")


func _full_energy_tonic_rejection() -> void:
	var state := _fresh_fixture()
	state["energy"] = 100
	state["inventory"]["medicine"] = 2
	if not _checkpoint("full_energy_tonic", state): return
	var before := GameState.data.duplicate(true)
	var emissions_before := changed_emissions
	var saves_before := failing_save_service.calls
	GameState.save_service = failing_save_service
	_check(not GameState.use_item("medicine"), "full-energy tonic is rejected")
	_check(failing_save_service.calls == saves_before, "full-energy tonic never attempts a save transaction")
	_check(_without_status(GameState.data) == _without_status(before), "full-energy rejection consumes no tonic and changes no gameplay field")
	_check(changed_emissions == emissions_before, "full-energy tonic rejection emits no changed signal")
	_assert_checkpoint_unchanged("full_energy_tonic")


func _settings_fixture() -> Dictionary:
	var state := _fresh_fixture()
	state["day"] = 9
	state["coins"] = 731
	state["inventory"]["crop_carrot"] = 2
	state["master_volume"] = 70.0
	state["music_volume"] = 60.0
	state["sfx_volume"] = 50.0
	state["fullscreen"] = false
	return state


func _audio_snapshot() -> Dictionary:
	var result: Dictionary = {"window_mode": DisplayServer.window_get_mode()}
	for bus_name in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_check(index >= 0, "test audio bus exists: " + String(bus_name))
		if index >= 0: result[bus_name] = AudioServer.get_bus_volume_db(index)
	return result


func _assert_audio_unchanged(before: Dictionary, case_name: String) -> void:
	var after := _audio_snapshot()
	for bus_name in ["Master", "Music", "SFX"]:
		_check(is_equal_approx(float(after.get(bus_name, 1000.0)), float(before.get(bus_name, -1000.0))), case_name + ": preserves actual " + String(bus_name) + " bus volume")
	_check(after["window_mode"] == before["window_mode"], case_name + ": preserves actual window mode")


func _confirm_save_failure(target_slot: int, confirmation: String, case_name: String) -> void:
	GameState.selected_slot = target_slot
	GameState.save_mode = "new"
	GameState.confirm_action = confirmation
	var before := GameState.data.duplicate(true)
	var draft_before := GameState.settings_draft.duplicate(true)
	var audio_before := _audio_snapshot()
	var emissions_before := changed_emissions
	var saves_before := failing_save_service.calls
	GameState.save_service = failing_save_service
	_check(not GameState.confirm_slot(), case_name + ": confirmation propagates persistence failure")
	_check(failing_save_service.calls == saves_before + 1, case_name + ": confirmation attempts exactly one fake save")
	_check(_without_status(GameState.data) == _without_status(before), case_name + ": retains the active farm")
	_check(GameState.selected_slot == target_slot, case_name + ": retains the chosen UI slot")
	_check(GameState.settings_draft == draft_before, case_name + ": restores the old settings draft")
	_check(GameState.confirm_action == confirmation, case_name + ": retains confirmation intent for retry")
	_check(changed_emissions == emissions_before, case_name + ": failure emits no changed signal")
	_assert_audio_unchanged(audio_before, case_name)
	_assert_checkpoint_unchanged(case_name)


func _new_game_failure_and_confirm_retry() -> void:
	if not _checkpoint("new_game_save_failure", _settings_fixture()): return
	GameState.settings_draft = {"master": 70.0, "music": 60.0, "sfx": 50.0, "fullscreen": false}
	GameState.apply_audio_settings()
	var before := GameState.data.duplicate(true)
	var old_slot := GameState.selected_slot
	var draft_before := GameState.settings_draft.duplicate(true)
	var audio_before := _audio_snapshot()
	var emissions_before := changed_emissions
	var saves_before := failing_save_service.calls
	GameState.save_service = failing_save_service
	_check(not GameState.new_state(2, true), "new game reports persistence failure")
	_check(failing_save_service.calls == saves_before + 1, "new game attempts exactly one fake save")
	_check(_without_status(GameState.data) == _without_status(before), "failed new game retains all active-farm gameplay data")
	_check(GameState.selected_slot == old_slot, "failed new game restores selected_slot property")
	_check(GameState.settings_draft == draft_before, "failed new game restores settings draft")
	_check(changed_emissions == emissions_before, "failed new game emits no changed signal")
	_assert_audio_unchanged(audio_before, "new_game_save_failure")
	_check(not bool((real_save_service.call("get_slot_metadata", 2) as Dictionary).get("occupied", false)), "failed new game never creates target slot two")
	_assert_checkpoint_unchanged("new_game_save_failure")
	_confirm_save_failure(2, "", "confirm_new_slot_save_failure")
	_check(not bool((real_save_service.call("get_slot_metadata", 2) as Dictionary).get("occupied", false)), "failed empty-slot confirmation leaves target slot empty")
	_confirm_save_failure(SLOT, "overwrite", "confirm_overwrite_save_failure")
	GameState.save_service = real_save_service
	GameState.selected_slot = 2
	GameState.save_mode = "new"
	GameState.confirm_action = ""
	emissions_before = changed_emissions
	_check(GameState.confirm_slot(), "new game confirmation retries successfully through real SaveService")
	_check(changed_emissions == emissions_before + 1, "successful new game emits changed exactly once")
	_check(GameState.selected_slot == 2 and int(GameState.data["selected_slot"]) == 2, "successful confirmation owns its selected new slot")
	_check(GameState.confirm_action.is_empty(), "successful confirmation clears its pending intent")
	_check(int(GameState.data["day"]) == 1 and int(GameState.data["coins"]) == 400 and int(GameState.data["energy"]) == 100, "successful new game initializes original authored balances")
	_check(GameState.data["inventory"] == FarmData.create_initial_state()["inventory"], "successful new game initializes the original inventory only")
	_check(GameState.settings_draft == {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}, "successful new game initializes original settings defaults")
	var loaded: Dictionary = real_save_service.call("load_slot", 2)
	_check(bool(loaded.get("ok", false)), "successful new-game retry creates a valid target checkpoint")
	if bool(loaded.get("ok", false)):
		var expected := GameState.normalize_state(loaded.get("state", {}) as Dictionary)
		_check(GameState.load_slot(2), "successful new-game target reloads through GameState")
		_check(_without_status(GameState.data) == _without_status(expected), "new-game retry reloads its exact original-schema gameplay state")
	_assert_stored_checkpoint_unchanged("new_game_keeps_other_slot")


func _settings_save_failure_and_retry() -> void:
	if not _checkpoint("settings_save_failure", _settings_fixture()): return
	GameState.settings_draft = {"master": 70.0, "music": 60.0, "sfx": 50.0, "fullscreen": false}
	GameState.apply_audio_settings()
	var before := GameState.data.duplicate(true)
	var audio_before := _audio_snapshot()
	var desired := {"master": 38.0, "music": 47.0, "sfx": 59.0, "fullscreen": false}
	GameState.settings_draft = desired.duplicate(true)
	var emissions_before := changed_emissions
	var saves_before := failing_save_service.calls
	GameState.save_service = failing_save_service
	GameState.apply_settings()
	_check(failing_save_service.calls == saves_before + 1, "edited settings attempt exactly one fake save")
	_check(_without_status(GameState.data) == _without_status(before), "failed settings preserve all original data")
	_check(GameState.settings_draft == desired, "failed settings retain desired draft for retry")
	_check(changed_emissions == emissions_before, "failed settings emit no changed signal")
	_assert_audio_unchanged(audio_before, "settings_save_failure")
	_assert_stored_checkpoint_unchanged("settings_save_failure")
	# Retry immediately with the same retained draft; no reload or reassignment
	# is used to manufacture edited settings before the successful attempt.
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	GameState.apply_settings()
	_check(changed_emissions == emissions_before + 1, "settings retry emits changed exactly once")
	_check(GameState.settings_draft == desired, "settings retry uses the same retained user draft")
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var bus_name := String(pair[0])
		var key := String(pair[1])
		_check(float(GameState.data[key + "_volume"]) == float(desired[key]), "settings retry saves desired " + key + " volume")
		var index := AudioServer.get_bus_index(bus_name)
		_check(index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(index), linear_to_db(float(desired[key]) / 100.0)), "settings retry applies desired " + bus_name + " bus volume")
	_check(bool(GameState.data["fullscreen"]) == bool(desired["fullscreen"]), "settings retry saves desired window preference")
	_assert_current_saved("settings_real_retry")
	var loaded: Dictionary = real_save_service.call("load_slot", SLOT)
	if bool(loaded.get("ok", false)):
		var expected := GameState.normalize_state(loaded.get("state", {}) as Dictionary)
		_check(GameState.load_slot(SLOT), "saved settings retry reloads through GameState")
		_check(_without_status(GameState.data) == _without_status(expected), "settings reload preserves all saved gameplay fields")
		_check(GameState.settings_draft == desired, "settings reload restores the saved user preferences")


func _run() -> void:
	real_save_service = GameState.save_service
	failing_save_service.read_service = real_save_service
	GameState.changed.connect(_on_changed)
	for action in ["till", "seed", "water", "fertilize", "harvest"]:
		var state := _field_fixture(String(action))
		_check(GameState.field_action_allowed(String(action), state["field_plots"][0]), "fixture makes field action valid before save failure: " + String(action))
		_save_rejection("field_" + String(action), state, GameState.apply_field_action_on_plot.bind(1, String(action)))
	var other_plot_state := _field_fixture("till")
	other_plot_state["selected_plot"] = 2
	_save_rejection("field_target_selection", other_plot_state, GameState.apply_field_action_on_plot.bind(1, "till"))
	_save_rejection("advance_day", _day_fixture(), GameState.advance_day, false)
	_save_rejection("buy", _fresh_fixture(), GameState.buy.bind("seed_carrot"))
	var sell_state := _fresh_fixture()
	sell_state["inventory"]["crop_carrot"] = 2
	_save_rejection("sell", sell_state, GameState.sell.bind("crop_carrot"))
	var medicine_state := _fresh_fixture()
	medicine_state["energy"] = 50
	medicine_state["inventory"]["medicine"] = 2
	_save_rejection("use_medicine", medicine_state, GameState.use_item.bind("medicine"))
	for action in ["feed_animals", "clean_animals", "pet_animals", "collect"]:
		_save_rejection("chicken_" + String(action), _animal_fixture(), GameState.animal_action.bind(String(action)))
	await _order_save_failure_and_retry()
	_capacity_rejection("capacity_core_buy", _full_fixture(), GameState.buy.bind("seed_carrot"))
	_capacity_rejection("capacity_chicken_collect", _full_fixture(), GameState.animal_action.bind("collect"))
	var harvest_state := _full_fixture()
	harvest_state["field_plots"][0] = _field_fixture("harvest")["field_plots"][0].duplicate(true)
	_capacity_rejection("capacity_field_harvest", harvest_state, GameState.apply_field_action_on_plot.bind(1, "harvest"))
	_existing_stack_overcapacity()
	await _order_frees_reward_slot()
	_full_energy_tonic_rejection()
	_new_game_failure_and_confirm_retry()
	_settings_save_failure_and_retry()
	GameState.save_service = real_save_service
	if GameState.changed.is_connected(_on_changed): GameState.changed.disconnect(_on_changed)
	print("Core transaction assertions: %d" % checks)
	if failures.is_empty():
		print("CORE_TRANSACTION_SAFETY_TEST_PASS")
		get_tree().quit(0)
	else:
		print("CORE_TRANSACTION_SAFETY_TEST_FAIL")
		for failure in failures: print(failure)
		get_tree().quit(1)

