extends Node

signal screen_changed(screen_id: String)

const SAVE_ROUTE_ID := "save"
const SAVE_CANONICAL_SCENE_PATH := "res://scenes/screens/save_slot_screen.tscn"
const SAVE_CANONICAL_SCRIPT_PATH := "res://scripts/screens/save_slot_screen.gd"
const SAVE_CANONICAL_DESTINATION := preload(SAVE_CANONICAL_SCENE_PATH)
const FIELD_SELECT_ROUTE_ID := "field_select"
const FIELD_ROUTE_ID := "field"
const FIELD_SELECT_CANONICAL_SCENE_PATH := "res://scenes/screens/04_field_select.tscn"
const FIELD_CANONICAL_SCENE_PATH := "res://scenes/screens/05_field_gameplay.tscn"
const FIELD_CANONICAL_SCRIPT_PATH := "res://scripts/screens/field_screen.gd"
const FIELD_SELECT_CANONICAL_DESTINATION := preload(FIELD_SELECT_CANONICAL_SCENE_PATH)
const FIELD_CANONICAL_DESTINATION := preload(FIELD_CANONICAL_SCENE_PATH)

const SCREENS := {
	"title": preload("res://scenes/screens/title_screen.tscn"),
	SAVE_ROUTE_ID: SAVE_CANONICAL_DESTINATION,
	"hub": preload("res://scenes/screens/home_hub_screen.tscn"),
	FIELD_SELECT_ROUTE_ID: FIELD_SELECT_CANONICAL_DESTINATION,
	FIELD_ROUTE_ID: FIELD_CANONICAL_DESTINATION,
	"shop": preload("res://scenes/screens/06_shop.tscn"),
	"storage": preload("res://scenes/screens/07_storage.tscn"),
	"settings": preload("res://scenes/screens/08_settings.tscn"),
	"animal": preload("res://scenes/screens/09_animal.tscn"),
	"quest": preload("res://scenes/screens/orders_screen.tscn"),
	"dragon": preload("res://scenes/screens/10_dragon.tscn"),
	"islands": preload("res://scenes/screens/world_system_screen.tscn"),
	"craft": preload("res://scenes/screens/world_system_screen.tscn"),
	"creatures": preload("res://scenes/screens/world_system_screen.tscn"),
	"events": preload("res://scenes/screens/world_system_screen.tscn"),
	"destination": preload("res://scenes/screens/island_destination_screen.tscn"),
}

var host: Control
var current_screen := "title"
var visited_island := "botanical" # Ephemeral view selection, never save state.


func initialize(screen_host: Control) -> void:
	host = screen_host
	go("title")


func go(screen_id: String) -> void:
	if host == null or not SCREENS.has(screen_id): return
	if screen_id not in ["title", "save", "settings"] and not GameState.has_active_farm(): return
	if screen_id == "settings" and current_screen != "settings":
		GameState.settings_return = current_screen
	if screen_id == "destination" and not bool(GameState.world_state().get("unlocked_islands", {}).get(visited_island, false)): return
	for child in host.get_children(): child.queue_free()
	current_screen = screen_id
	var screen = SCREENS[screen_id].instantiate()
	if screen_id in ["islands", "craft", "creatures", "events"]:
		screen.section = screen_id
	if screen_id == "destination": screen.island_id = visited_island
	host.add_child(screen)
	screen_changed.emit(screen_id)


func visit_island(island_id: String) -> bool:
	if not GameState.world_config().get("islands", {}).has(island_id): return false
	if not bool(GameState.world_state().get("unlocked_islands", {}).get(island_id, false)): return false
	visited_island = island_id
	go("hub" if island_id == "main" else "dragon" if island_id == "dragon" else "destination")
	return true


func is_canonical_save_root(screen: Node) -> bool:
	if screen == null:
		return false
	var screen_script: Script = screen.get_script() as Script
	return (
		screen.scene_file_path == SAVE_CANONICAL_SCENE_PATH
		and screen_script != null
		and String(screen_script.resource_path) == SAVE_CANONICAL_SCRIPT_PATH
		and String(screen.get_meta("v6_visual_status", "")) == "V6_8_3_CANONICAL_SAVE_RUNTIME"
	)


func is_canonical_field_root(screen: Node) -> bool:
	if screen == null:
		return false
	var screen_script: Script = screen.get_script() as Script
	return (
		screen.scene_file_path == FIELD_CANONICAL_SCENE_PATH
		and screen_script != null
		and String(screen_script.resource_path) == FIELD_CANONICAL_SCRIPT_PATH
		and String(screen.get_meta("v7_visual_status", "")) == "V7_PHASE2_FIELD_CORE_CANONICAL"
	)


func back_home() -> void:
	go("hub")
