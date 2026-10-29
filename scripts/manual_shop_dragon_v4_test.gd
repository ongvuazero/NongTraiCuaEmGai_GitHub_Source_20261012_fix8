extends Node

# Additive rendered QA. Routes and labelled fixtures are setup; gameplay/menu
# callbacks are activated by viewport pointer input, never called directly.
const MAIN = preload("res://scenes/main.tscn")
const DRAGON = preload("res://scenes/screens/10_dragon.tscn")
const FarmData = preload("res://scripts/farm_data.gd")
const WorldData = preload("res://scripts/world_data.gd")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/MANUAL_BASELINE_REPAIR_V4/SHOP_DRAGON"
const SHOP_TABS := [["Tab_Seeds", "seeds"], ["Tab_Food", "food"], ["Tab_Medicine", "medicine"], ["Tab_Expansion", "expansion"], ["Tab_Rare", "rare"]]
const SECTION_NAMES := ["Lò ấp trứng", "Nhà trẻ", "Sân chơi", "Shop Rồng", "Kho Rồng", "Sách Rồng"]
# Exactly twenty scene-authored positions, deliberately excluding the meter
# fill whose width is gameplay-driven. No baseline comes from post-ready UI.
const DRAGON_GEOMETRY := ["ComingSoonPanel", "ComingSoonTitle", "ComingSoonMessage", "DragonSectionPrimary", "DragonSectionSecondary", "DragonSelectionCycle", "DragonActionFeedback", "DragonIslandAccess", "LeftNavigation", "DragonNav_0", "DragonNav_1", "DragonNav_2", "DragonNav_3", "DragonNav_4", "DragonNav_5", "DragonBackToHub", "HatcheryPortalVisual", "FarmerVisual", "CatVisual", "DragonPortalIdentity"]
const ART_STATES := ["texture_normal", "texture_pressed", "texture_hover", "texture_disabled"]

var failures: Array[String] = []
var checks: int = 0
var captures: Array[String] = []
var completed: Array[String] = []
var notes: Array[String] = []
var route_events: Array[String] = []
var authored_geometry: Dictionary = {}
var authored_menu: Dictionary = {}
var run_root: String = ""
var capture_root: String = ""
var host: Control
var screen: Node
var screen_identity: int = 0
var mouse_inside: bool = false


func _ready() -> void:
	var isolated: String = OS.get_environment("MSF_TEST_SAVE_DIR")
	var absolute: String = ProjectSettings.globalize_path(isolated).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated.is_empty() or not absolute.contains("manual_baseline_repair_v4") or absolute == player or player.begins_with(absolute + "/"):
		push_error("Shop/Dragon V4 QA requires a fresh named manual_baseline_repair_v4 MSF_TEST_SAVE_DIR, separate from player saves and their ancestors.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated.path_join(("my_sisters_farm_slot_%d.save" % slot) + String(suffix))):
				push_error("Shop/Dragon V4 refuses existing saves, temporary files and backups. Nothing is removed.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Shop/Dragon V4 requires rendered normal gameplay, not headless/rich/parity mode.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error("MANUAL_SHOP_DRAGON_V4: " + detail)


func _settle(frames: int = 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _current_screen() -> Node:
	return host.get_child(host.get_child_count() - 1)


func _record_route(route: String) -> void:
	route_events.append(route)


func _route(route: String) -> void:
	# Test setup only. Back, category, page, purchase and section input is real GUI.
	ScreenRouter.go(route)
	await _settle()
	screen = _current_screen()
	screen_identity = screen.get_instance_id()
	_check(ScreenRouter.current_screen == route, "Setup route: " + route)
	_check(screen.scene_file_path == ScreenRouter.SCREENS[route].resource_path, "Canonical serialized scene: " + route)


func _node(name: String) -> Node:
	return screen.find_child(name, true, false)


func _button(name: String) -> BaseButton:
	return _node(name) as BaseButton


func _click(point: Vector2) -> void:
	if not mouse_inside:
		get_viewport().notify_mouse_entered()
		mouse_inside = true
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = bool(down)
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await _settle()


func _press(name: String) -> bool:
	var button: BaseButton = _button(name)
	_check(button != null, "Actual control exists: " + name)
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, "Control is visible and enabled: " + name)
	if not button.is_visible_in_tree() or button.disabled: return false
	var fired: Array[bool] = [false]
	var witness: Callable = func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Viewport pointer activates actual button: " + name)
	return fired[0]


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	_check(rendered != null and rendered.get_size() == Vector2i(1280, 720), "Native 1280x720 capture: " + name)
	if rendered == null: return
	var target: String = capture_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(target), "Capture refuses prior evidence overwrite: " + name)
	if FileAccess.file_exists(target): return
	var saved: bool = rendered.save_png(ProjectSettings.globalize_path(target)) == OK
	_check(saved, "Rendered capture saved: " + name)
	if saved: captures.append(target)


func _gameplay(state: Dictionary) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	# SaveService owns these metadata keys; status_text is error/presentation copy.
	for key in ["saved_at_unix", "last_screen", "status_text"]: copy.erase(key)
	# Original fresh farms may omit the legacy HUD alias. Reload normalizes it
	# from the existing world wallet. Compare its value, never discard the alias
	# or overwrite an existing value that could expose a real wallet mismatch.
	if not copy.has("long_khi"):
		copy["long_khi"] = int(copy.get("world", {}).get("dragon_energy", 0))
	return copy


func _in_place(route: String, event_count: int, label: String) -> void:
	_check(is_instance_valid(screen) and screen.get_instance_id() == screen_identity, label + ": same screen instance")
	_check(ScreenRouter.current_screen == route and _current_screen() == screen, label + ": stays on canonical " + route)
	_check(route_events.size() == event_count, label + ": no hidden routing to Craft/Companions/other scenes")


func _pose(control: Control) -> Dictionary:
	return {"position": control.position, "size": control.size, "rotation": control.rotation, "scale": control.scale, "anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]}


func _sample_dragon_scene() -> void:
	var authored: Node = DRAGON.instantiate()
	var context: Control = authored.find_child("ComingSoonPanel", true, false) as Control
	_check(context != null and not context.visible, "Serialized Dragon context is initially hidden before ready")
	for name in DRAGON_GEOMETRY:
		var control: Control = authored.find_child(String(name), true, false) as Control
		_check(control != null, "Authored geometry node exists: " + String(name))
		if control != null: authored_geometry[String(name)] = _pose(control)
	for index in range(SECTION_NAMES.size()):
		var button: TextureButton = authored.find_child("DragonNav_%d" % index, true, false) as TextureButton
		_check(button != null, "Authored leaf-menu button: %d" % index)
		if button == null: continue
		var record: Dictionary = {"modulate": button.modulate, "self_modulate": button.self_modulate, "children": button.get_child_count()}
		for property in ART_STATES:
			var texture: Texture2D = button.get(String(property)) as Texture2D
			_check(texture != null, "Serialized leaf art exists: %d %s" % [index, property])
			record[String(property)] = texture.resource_path if texture != null else ""
		authored_menu[index] = record
	authored.free()
	_check(authored_geometry.size() == 20 and authored_menu.size() == 6, "Twenty authored geometry nodes and six menu-art baselines sampled")


func _dragon_geometry(label: String, manual_delta: Vector2 = Vector2.ZERO) -> void:
	_check(is_instance_valid(screen) and screen.get_instance_id() == screen_identity, label + ": Dragon instance preserved")
	if not is_instance_valid(screen): return
	for name in DRAGON_GEOMETRY:
		var control: Control = _node(String(name)) as Control
		_check(control != null and authored_geometry.has(String(name)), label + ": authored node retained " + String(name))
		if control == null or not authored_geometry.has(String(name)): continue
		var record: Dictionary = authored_geometry[String(name)]
		var position: Vector2 = record["position"]
		var size: Vector2 = record["size"]
		var scale_value: Vector2 = record["scale"]
		_check(control.position.is_equal_approx(position + manual_delta), label + ": serialized/manual position " + String(name))
		_check(control.size.is_equal_approx(size), label + ": serialized size " + String(name))
		_check(is_equal_approx(control.rotation, float(record["rotation"])) and control.scale.is_equal_approx(scale_value), label + ": serialized transform " + String(name))
		_check([control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom] == record["anchors"], label + ": serialized anchors " + String(name))


func _dragon_menu_art(label: String) -> void:
	var context: Control = _node("ComingSoonPanel") as Control
	var opened: bool = context != null and context.visible
	var active: int = int(screen.get("active_section"))
	for index in range(SECTION_NAMES.size()):
		var button: TextureButton = _button("DragonNav_%d" % index) as TextureButton
		_check(button != null and authored_menu.has(index), label + ": leaf menu exists %d" % index)
		if button == null or not authored_menu.has(index): continue
		var record: Dictionary = authored_menu[index]
		var selected: bool = opened and index == active
		for property in ART_STATES:
			var actual: Texture2D = button.get(String(property)) as Texture2D
			var expected: String = String(record["texture_pressed"] if property == "texture_normal" and selected else record[String(property)])
			_check(actual != null and actual.resource_path == expected, label + ": exact authored art %d %s" % [index, property])
		_check(button.modulate == record["modulate"] and button.self_modulate == record["self_modulate"], label + ": no generated menu tint %d" % index)
		_check(button.get_child_count() == int(record["children"]), label + ": no generated check/badge child %d" % index)
		var caption: Label = button.get_node_or_null("Caption") as Label
		_check(caption != null and not caption.text.is_empty(), label + ": authored menu caption %d" % index)
		if caption != null:
			for mark in ["✓", "✔", "☑"]: _check(not caption.text.contains(String(mark)), label + ": no generated check prefix %d" % index)


func _manual_position_probe(locale: String) -> void:
	# Presentation-only, reversible stand-in for moving authored nodes in editor.
	# A normal changed signal refreshes the actual screen; no callback is invoked.
	var before: Dictionary = _gameplay(GameState.data)
	var event_count: int = route_events.size()
	for name in DRAGON_GEOMETRY:
		var control: Control = _node(String(name)) as Control
		if control != null and authored_geometry.has(String(name)):
			var position: Vector2 = authored_geometry[String(name)]["position"]
			control.position = position + Vector2(20, 0)
	GameState.changed.emit()
	await _settle()
	_dragon_geometry(locale + " manual +20px refresh", Vector2(20, 0))
	_in_place("dragon", event_count, locale + " manual +20px refresh")
	_check(_gameplay(GameState.data) == before, locale + ": manual layout probe cannot change gameplay")
	for name in DRAGON_GEOMETRY:
		var control: Control = _node(String(name)) as Control
		if control != null and authored_geometry.has(String(name)): control.position = authored_geometry[String(name)]["position"]
	GameState.changed.emit()
	await _settle()
	_dragon_geometry(locale + " manual layout restored")


func _shop_case(locale: String, slot: int) -> void:
	_check(GameState.new_state(slot), locale + ": original fresh farm persisted only in isolated QA slot")
	UILocale.set_locale(locale)
	await _route("shop")
	var event_count: int = route_events.size()
	var before_tabs: Dictionary = _gameplay(GameState.data)
	for definition in SHOP_TABS:
		await _press(String(definition[0]))
		_check(String(screen.get("active_category")) == String(definition[1]), locale + ": actual category binding " + String(definition[1]))
		_check(int(screen.get("page_index")) == 0, locale + ": category starts at page zero")
		_in_place("shop", event_count, locale + " Shop tab " + String(definition[1]))
		_check(_gameplay(GameState.data) == before_tabs, locale + ": tab click changes no gameplay")
		var offers: Array = screen.call("_category_shop_items")
		_check(not offers.is_empty(), locale + ": current category offers exist")
		if not offers.is_empty(): _check(String(screen.get("selected_product")) == String(offers[0]["id"]), locale + ": selection follows visible category ID")
		if definition[1] in ["seeds", "expansion", "rare"]: await _capture(locale + "_SHOP_" + String(definition[1]).to_upper() + "_NORMAL_LOCKS")
	await _press("Tab_Seeds")
	var runtime_script: Script = screen.get_script() as Script
	var page_size: int = int(runtime_script.get_script_constant_map().get("PAGE_SIZE", 0))
	var seeds: Array = screen.call("_category_shop_items")
	_check(page_size > 0 and seeds.size() > page_size, locale + ": real seed catalog requires another page")
	await _press("ShopNextPage")
	_check(int(screen.get("page_index")) == 1, locale + ": actual Next page advances exactly once")
	if page_size > 0 and seeds.size() > page_size: _check(String(screen.get("selected_product")) == String(seeds[page_size]["id"]), locale + ": next-page selection uses actual catalog ID")
	_in_place("shop", event_count, locale + " next page")
	await _press("ShopPreviousPage")
	_check(int(screen.get("page_index")) == 0, locale + ": actual Previous returns to first page")
	_check(_gameplay(GameState.data) == before_tabs, locale + ": category/paging never changes gameplay")
	await _press("SelectProduct_seed_carrot")
	_check(String(screen.get("selected_product")) == "seed_carrot", locale + ": pointer selects actual carrot offer")
	var definition: Dictionary = {}
	for item in FarmData.SHOP_ITEMS:
		if String(item.get("id", "")) == "seed_carrot": definition = item
	_check(not definition.is_empty(), locale + ": authored carrot price/bundle exists")
	var coins: int = int(GameState.data.get("coins", 0))
	var amount: int = int(GameState.data.get("inventory", {}).get("seed_carrot", 0))
	await _press("BuySelectedProduct")
	_check(int(GameState.data.get("coins", 0)) == coins - int(definition.get("price", 0)), locale + ": real Buy charges exact authored coins")
	_check(int(GameState.data.get("inventory", {}).get("seed_carrot", 0)) == amount + int(definition.get("amount", 0)), locale + ": real Buy grants exact authored seed bundle")
	_in_place("shop", event_count, locale + " purchase")
	var purchased: Dictionary = _gameplay(GameState.data)
	var saved: Dictionary = GameState.save_service.load_slot(slot)
	_check(bool(saved.get("ok", false)) and saved.get("state") is Dictionary, locale + ": Buy autosave reloads without any final manual save")
	if saved.get("state") is Dictionary: _check(_gameplay(saved["state"]) == purchased, locale + ": saved gameplay equals purchased RAM, excluding metadata/status only")
	_check(GameState.load_slot(slot), locale + ": real GameState reload succeeds")
	await _settle()
	_check(_gameplay(GameState.data) == purchased, locale + ": real reload retains purchase")
	_in_place("shop", event_count, locale + " purchase reload")
	await _press("ShopBackToHub")
	screen = _current_screen()
	_check(ScreenRouter.current_screen == "hub" and screen.scene_file_path == ScreenRouter.SCREENS["hub"].resource_path, locale + ": real Shop Back reaches canonical Home")
	_check(_gameplay(GameState.data) == purchased, locale + ": Shop Back changes no gameplay")
	completed.append(locale + "_shop")


func _dragon_context(index: int, event_count: int, locale: String, fixture: String) -> void:
	var before: Dictionary = _gameplay(GameState.data)
	await _press("DragonNav_%d" % index)
	var panel: Control = _node("ComingSoonPanel") as Control
	var title: Label = _node("ComingSoonTitle") as Label
	var message: Label = _node("ComingSoonMessage") as Label
	_check(panel != null and panel.is_visible_in_tree(), locale + ": real menu click opens context " + str(index))
	_check(int(screen.get("active_section")) == index, locale + ": context belongs to clicked section " + str(index))
	_check(title != null and title.text == tr(SECTION_NAMES[index]).to_upper(), locale + ": section-specific localized title " + str(index))
	_check(message != null and message.is_visible_in_tree() and not message.text.is_empty(), locale + ": live section message " + str(index))
	_check(_button("DragonSectionPrimary") != null and _button("DragonSectionSecondary") != null, locale + ": serialized context action controls remain available")
	_in_place("dragon", event_count, locale + " " + fixture + " menu " + str(index))
	_check(_gameplay(GameState.data) == before, locale + ": menu opens no gameplay mutation " + str(index))
	_dragon_geometry(locale + " " + fixture + " menu " + str(index))
	_dragon_menu_art(locale + " " + fixture + " menu " + str(index))


func _dragon_case(locale: String) -> void:
	await _route("dragon")
	var event_count: int = route_events.size()
	var panel: Control = _node("ComingSoonPanel") as Control
	_check(panel != null and not panel.visible, locale + ": initial canonical Dragon context stays closed")
	_check(not bool(GameState.data.get("world", {}).get("unlocked_islands", {}).get("dragon", false)), locale + ": original Dragon island really locked")
	_dragon_geometry(locale + " Dragon initial")
	_dragon_menu_art(locale + " Dragon initial")
	var initial: Dictionary = _gameplay(GameState.data)
	GameState.changed.emit()
	await _settle()
	_check(panel != null and not panel.visible, locale + ": ordinary refresh cannot open initial context")
	_check(_gameplay(GameState.data) == initial, locale + ": closed refresh changes no gameplay")
	await _capture(locale + "_DRAGON_CLOSED_ORIGINAL_LOCKS")
	await _manual_position_probe(locale)
	for index in range(SECTION_NAMES.size()):
		await _dragon_context(index, event_count, locale, "LOCKED")
		if index == 0: await _capture(locale + "_DRAGON_LOCKED_CONTEXT_OPEN")
	await _press("DragonNav_5")
	_check(panel != null and not panel.visible, locale + ": clicking current section again closes its context")
	# Explicit presentation/action-eligibility fixture, not earned Dragon progress.
	GameState.data["world"]["unlocked_islands"]["dragon"] = true
	GameState.data["world"]["buildings"]["dragon_altar"] = 1
	GameState.data["world"]["creatures"]["water_dragon"] = WorldData.creature_state()
	GameState.data["inventory"]["aquatic_feed"] = 2
	notes.append(locale + ": UNLOCKED DRAGON FIXTURE ONLY: dragon island=true, altar=1, water_dragon owned by setup, aquatic_feed=2; not earned progression, incubation, growth or breeding proof.")
	GameState.changed.emit()
	await _settle()
	_check(panel != null and not panel.visible, locale + ": unlocked fixture refresh still cannot auto-open context")
	for index in range(SECTION_NAMES.size()):
		await _dragon_context(index, event_count, locale, "UNLOCKED_FIXTURE")
		if index == 1: await _capture(locale + "_DRAGON_NURSERY_UNLOCKED_OWNED_WATER_DRAGON_FIXTURE_NOT_EARNED")
	var before_back: Dictionary = _gameplay(GameState.data)
	await _press("DragonBackToHub")
	screen = _current_screen()
	_check(ScreenRouter.current_screen == "hub" and screen.scene_file_path == ScreenRouter.SCREENS["hub"].resource_path, locale + ": actual Dragon Back reaches canonical Home")
	_check(_gameplay(GameState.data) == before_back, locale + ": Dragon Back changes no gameplay")
	completed.append(locale + "_dragon")


func _run() -> void:
	run_root = REPORT_ROOT.path_join("RUN_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()])
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		push_error("Shop/Dragon V4 refuses an existing evidence run directory.")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root)) != OK:
		push_error("Could not create a new Shop/Dragon V4 evidence directory.")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	_sample_dragon_scene()
	var main: Node = MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost") as Control
	await _settle()
	ScreenRouter.screen_changed.connect(_record_route)
	await _shop_case("vi", 1)
	await _dragon_case("vi")
	await _shop_case("en", 2)
	await _dragon_case("en")
	_check(completed == ["vi_shop", "vi_dragon", "en_shop", "en_dragon"], "All four locale/screen cases reached explicit completion markers")
	_check(captures.size() == 12, "All twelve scoped rendered captures saved")
	var status: String = "MANUAL_SHOP_DRAGON_V4_TEST_PASS" if failures.is_empty() else "MANUAL_SHOP_DRAGON_V4_TEST_FAIL"
	var payload: Dictionary = {"result": status, "checks": checks, "failures": failures, "captures": captures, "completed_cases": completed, "save_root": OS.get_environment("MSF_TEST_SAVE_DIR"), "authored_dragon_geometry_nodes": authored_geometry.size(), "notes": notes, "gui_input": "Viewport.push_input motion/down/up only; pressed witnesses are read-only, never signal/callback invocation", "snapshot_comparison": "Ignore only saved_at_unix, last_screen and status_text. Default an absent long_khi HUD alias from existing world.dragon_energy; compare the resulting alias value and retain any already-present value to expose wallet mismatches.", "scope": "Canonical Shop five tabs/paging/carrot Buy/autosave reload/Back; canonical Dragon initial closed/locked open/all six menus/exact authored menu art/twenty node poses/reversible +20px refresh/labelled unlocked Nursery/Back", "limits": "Rendered assertion/capture evidence only. No earned Dragon progress, pacing, animation/lifecycle/whole-GDD or commercial visual approval."}
	var result_path: String = run_root.path_join("MANUAL_SHOP_DRAGON_V4_RESULTS.json")
	var report: FileAccess = FileAccess.open(result_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write new Shop/Dragon V4 result JSON.")
		get_tree().quit(1)
		return
	report.store_string(JSON.stringify(payload, "\t"))
	report.close()
	print(status)
	print("MANUAL_SHOP_DRAGON_V4_RESULTS: " + ProjectSettings.globalize_path(result_path))
	get_tree().quit(0 if failures.is_empty() else 1)
