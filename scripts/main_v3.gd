extends Control

const FarmData = preload("res://scripts/farm_data.gd")
const AmbientLife = preload("res://scripts/ui/world_ambient_life.gd")
const CreatureMotion = preload("res://scripts/ui/live_creature_motion.gd")
const BackgroundArtRouter = preload("res://scripts/ui/background_art_router.gd")
const HomeLivingPresenter = preload("res://scripts/ui/home_living_presenter.gd")
const WorldBGM = preload("res://scripts/audio/world_bgm_controller.gd")
const RouteTransition = preload("res://scripts/ui/route_transition.gd")
const FieldTypography = preload("res://scripts/ui/field_toolbar_typography.gd")
const Branding = preload("res://scripts/ui/localized_branding.gd")
const BrandNames = preload("res://scripts/localization/locale_registry.gd")
const FirstLaunchLanguage = preload("res://scripts/ui/first_launch_language.gd")
const MobileRuntime = preload("res://scripts/ui/mobile_runtime.gd")

@onready var _ui_root: Control = $ScreenHost

var _state: Dictionary:
	get: return GameState.data
	set(value): GameState.data = value
var _current_screen: String:
	get: return ScreenRouter.current_screen
	set(value): ScreenRouter.current_screen = value
var _farmer_action := "idle"
var _route_transition: CanvasLayer
var _screen_entered_once := false


func _ready() -> void:
	UILocale.initialize()
	_refresh_brand_window()
	UILocale.events().locale_changed.connect(_refresh_brand_window)
	var bgm := WorldBGM.new()
	bgm.name = "WorldBGMController"
	add_child(bgm) # Main sibling: route rebuilds and screen-only freezes do not restart music.
	_route_transition = RouteTransition.new()
	_route_transition.name = "RouteTransition"
	add_child(_route_transition)
	_ui_root.child_entered_tree.connect(_on_screen_entered)
	ScreenRouter.initialize(_ui_root)
	if QARichFixture.requested():
		QARichFixture.apply()
		ScreenRouter.go("hub")
	_show_initial_language_choice()
	MobileRuntime.install(self)

func _show_initial_language_choice() -> void:
	if UILocale.language_choice_confirmed(): return
	# Explicit automation opt-in, debug + isolated saves only. Never suppress the
	# first-launch prompt for a normal player or mark a skipped choice confirmed.
	if OS.is_debug_build() and not OS.get_environment("MSF_TEST_SAVE_DIR").is_empty() and OS.get_environment("MSF_QA_SKIP_LANGUAGE_CHOOSER") == "1": return
	var chooser := FirstLaunchLanguage.new()
	chooser.name = "FirstLaunchLanguage"
	chooser.setup(_ui_root)
	chooser.modal_completed.connect(_on_initial_language_chosen)
	add_child(chooser)

func _on_initial_language_chosen() -> void:
	# Rebuild only the title so baked/live labels reflect the confirmed language.
	# No farm slot is created, loaded or overwritten by onboarding.
	if ScreenRouter.current_screen == "title": ScreenRouter.go("title")

func _on_screen_entered(screen: Node) -> void:
	# Route/transactions remain owned by ScreenRouter and GameState. Install
	# presentation only after the scene's authored controls have been built.
	# The router queue_frees outgoing screens. Capture BEFORE its end-of-frame
	# exit signals, not from those signals after an incoming reveal has run.
	if _screen_entered_once and is_instance_valid(_route_transition):
		_route_transition.call("capture")
	_screen_entered_once = true
	call_deferred("_install_living_presentation",screen,ScreenRouter.current_screen)
	call_deferred("_finish_screen_transition",screen)

func _refresh_brand_window(_locale: String = "") -> void:
	var suffix := " — FULL CONTENT TEST (isolated save)" if QARichFixture.requested() else " — TEST " + String(ProjectSettings.get_setting("application/config/version", ""))
	get_window().title = BrandNames.game_title(UILocale.current_locale()) + suffix

func _finish_screen_transition(screen: Node) -> void:
	if is_instance_valid(_route_transition) and is_instance_valid(screen) and not screen.is_queued_for_deletion():
		_route_transition.call("reveal",screen)

func _keep_runtime_child(screen: Node,child_name: StringName) -> void:
	var authored = screen.get("_serialized_root_children")
	if authored is Array and child_name not in authored: authored.append(child_name)

func _install_living_presentation(screen: Node,route: String) -> void:
	if not is_instance_valid(screen) or screen.is_queued_for_deletion(): return
	if OS.get_environment("MSF_DISABLE_LIVING_PRESENTATION") == "1": return
	BackgroundArtRouter.install(screen)
	_keep_runtime_child(screen,"BackgroundArtRouter")
	Branding.install(screen,route)
	_keep_runtime_child(screen,"LocalizedBranding")
	if route == "field": FieldTypography.apply(screen)
	if route == "hub" and BackgroundArtRouter.resolved_path("res://v6/art/reference_runtime/home_hub_reference_runtime_base_v6_5.png") == "res://assets/living_world_all_v2/home_hub.png":
		HomeLivingPresenter.install(screen)
		_keep_runtime_child(screen,"HomeLivingPresenter")
	if route == "title" and BackgroundArtRouter.resolved_path("res://v6/art/reference_runtime/title_reference_runtime_base_v6_5.png") == "res://assets/living_world_all_v2/home_hub.png":
		HomeLivingPresenter.install_title(screen)
		_keep_runtime_child(screen,"TitleLivingPresenter")
	var ambient_id := String(screen.get("island_id")) if route == "destination" else route
	if route == "field" and GameState.active_field_zone() != "home": ambient_id = "field_" + GameState.active_field_zone()
	if route == "animal": ambient_id = "animal_"+String(screen.get("selected_species"))
	if route in ["hub","field","dragon","destination","animal","title","save","field_select","shop","storage","settings","quest","islands","craft","creatures","events"] and screen.get_node_or_null("WorldAmbientLife") == null:
		var ambient := AmbientLife.new()
		ambient.setup(ambient_id)
		if route in ["field","destination"]: ambient.z_index = -50
		screen.add_child(ambient)
		if route not in ["field","destination"]:
			for child in screen.get_children():
				if child != ambient and String(child.name).to_lower().contains("background"):
					screen.move_child(ambient,mini(child.get_index()+1,screen.get_child_count()-1))
					break
		_keep_runtime_child(screen,ambient.name)
	if route in ["hub","dragon","animal","destination","title"] and screen.get_node_or_null("LiveCreatureMotion") == null:
		var motion := CreatureMotion.new()
		screen.add_child(motion)
		_keep_runtime_child(screen,motion.name)


func _handle_action(action: String) -> void:
	match action:
		"open_new_game": GameState.save_mode = "new"; ScreenRouter.go(ScreenRouter.SAVE_ROUTE_ID)
		"open_save": GameState.save_mode = "continue"; ScreenRouter.go(ScreenRouter.SAVE_ROUTE_ID)
		"continue_game":
			GameState.save_mode = "continue"
			var slot := GameState.latest_slot()
			if slot > 0: GameState.selected_slot = slot
			ScreenRouter.go(ScreenRouter.SAVE_ROUTE_ID)
		"go_hub": ScreenRouter.go("hub")
		"go_field": ScreenRouter.go(ScreenRouter.FIELD_SELECT_ROUTE_ID)
		"open_shop": ScreenRouter.go("shop")
		"open_inventory": ScreenRouter.go("storage")
		"open_settings": GameState.settings_return = ScreenRouter.current_screen; ScreenRouter.go("settings")
		"go_animal_inside": ScreenRouter.go("animal")
		"open_island": ScreenRouter.go("dragon")
		"field_till": _apply_field_action("till")
		"field_seed": _apply_field_action("seed")
		"field_water": _apply_field_action("water")
		"field_fertilize": _apply_field_action("fertilize")
		"field_harvest": _apply_field_action("harvest")
		"advance_day": _advance_day()


func _select_save_slot(slot_id: int) -> void: GameState.choose_slot(slot_id)
func _confirm_save_slot() -> void: GameState.confirm_slot()
func _save_game() -> bool: return GameState.save(ScreenRouter.current_screen)
func _load_slot(slot_id: int) -> bool: return GameState.load_slot(slot_id)
func _normalize_loaded_state(state: Dictionary) -> Dictionary: return GameState.normalize_state(state)
func _select_plot(plot_id: int) -> void: GameState.select_plot(plot_id)
func _apply_field_action(action: String) -> void: _farmer_action = "idle" if not GameState.apply_field_action(action) else action
func _advance_day() -> void: GameState.advance_day()
func _buy_shop_item(item_id: String) -> void: GameState.buy(item_id)
func _feed_animals() -> void: _farmer_action = "feed" if GameState.animal_action("feed_animals") else "idle"
func _clean_animals() -> void: _farmer_action = "clean" if GameState.animal_action("clean_animals") else "idle"
func _pet_animals() -> void: _farmer_action = "pet_care" if GameState.animal_action("pet_animals") else "idle"
func _collect_eggs() -> void: GameState.animal_action("collect")


func _deliver_active_order() -> void:
	var order: Dictionary = FarmData.ORDER_DEFINITIONS[int(GameState.data.get("active_order_index", 0)) % FarmData.ORDER_DEFINITIONS.size()]
	if int(GameState.data["inventory"].get(order["need_item"], 0)) < int(order["need_amount"]): return
	GameState.data["inventory"][order["need_item"]] -= int(order["need_amount"])
	GameState.data["coins"] += int(order["reward_coins"])
	GameState.data["orders_done"] += 1
	GameState.data["active_order_index"] = (int(GameState.data["active_order_index"]) + 1) % FarmData.ORDER_DEFINITIONS.size()
	GameState.save("hub")
	GameState.changed.emit()
