extends RefCounted
class_name QARichFixture

# Explicit debug fixture: never loaded by production release or normal start.
static func requested() -> bool:
	return OS.has_feature("debug") and (OS.get_cmdline_user_args().has("--qa-rich-state") or OS.get_environment("MSF_QA_RICH_INVENTORY") == "1")


static func apply() -> void:
	# Resume only the isolated developer profile. Never refill money on reload.
	# Fresh-session QA explicitly disables resume so every run is reproducible.
	var resume := OS.get_environment("MSF_QA_RICH_RESUME") == "1"
	if resume and bool(GameState.save_service.get_slot_metadata(3).get("occupied", false)):
		if GameState.load_slot(3):
			return
	GameState.new_state(3, false)
	var config := GameState.world_config()
	for item in GameState.data.inventory:
		GameState.data.inventory[item] = 999
	for item in config.get("items", {}):
		if item == "dragon_energy":
			continue # Currency is authoritative in the world wallet, not a stack.
		GameState.data.inventory[item] = 999
	for egg in config.get("eggs", {}):
		GameState.data.inventory[egg] = 999
	GameState.data.inventory.erase("dragon_energy")
	GameState.data.coins = 9999999
	GameState.data.energy = 100
	GameState.data.orders_done = 8
	GameState.data.active_order_index = 0
	# Keep headroom so the very first Collect Dragon Energy is also testable.
	GameState.data.world.dragon_energy = 50
	GameState.data.long_khi = 50
	for island in config.get("islands", {}):
		GameState.data.world.unlocked_islands[island] = true
	for building in config.get("buildings", {}):
		GameState.data.world.buildings[building] = 1
	GameState.data.world.buildings.barn = 2
	for species in config.get("creatures", {}):
		if OS.get_environment("MSF_QA_RICH_EGGS_MODE") == "1" and String(config.creatures[species].get("kind", "")) == "dragon":
			continue
		GameState.data.world.creatures[species] = preload("res://scripts/world_data.gd").creature_state()
		GameState.data.world.creatures[species].products_ready = 2
	GameState.data.animal.eggs_ready = 2
	preload("res://scripts/world_systems.gd").sync_chicken(GameState.data)
	GameState.save("hub")
	GameState.get_window().title = preload("res://scripts/localization/locale_registry.gd").game_title(UILocale.current_locale()) + " — FULL CONTENT TEST (isolated save)"
	GameState.changed.emit()

