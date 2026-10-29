extends Node

# Rendered additive QA. Production GUI callbacks are never called directly.
const MAIN = preload("res://scenes/main.tscn")
const SHOP = preload("res://scenes/screens/06_shop.tscn")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/MANUAL_BASELINE_REPAIR_V4/SHOP"
const BACK_ART := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/TITLE_SAVE_HOME/title_button_frame_default.png"

var failures: Array[String] = []
var checks: int = 0
var captures: Array[String] = []
var completed: Array[String] = []
var baseline: Array[Dictionary] = []
var run_root: String = ""
var capture_root: String = ""
var host: Control
var screen: Node
var mouse_inside: bool = false
var identity: int = 0


func _ready() -> void:
	var isolated: String = OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root: String = ProjectSettings.globalize_path(isolated).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated.is_empty() or not qa_root.contains("manual_baseline_repair_v4") or qa_root == player or player.begins_with(qa_root + "/"):
		push_error("Manual Shop QA requires a fresh named manual_baseline_repair_v4 MSF_TEST_SAVE_DIR outside player saves and their ancestors.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			var filename: String = ("my_sisters_farm_slot_%d.save" % slot) + String(suffix)
			if FileAccess.file_exists(isolated.path_join(filename)):
				push_error("Manual Shop QA refuses occupied saves/tmp/backups; no files are removed.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Manual Shop QA requires rendered normal gameplay, not headless/rich/parity.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("MANUAL_SHOP_V4: " + message)


func _settle(frames: int = 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _sample_authored(parent: Node, indices: Array[int]) -> void:
	for index in range(parent.get_child_count()):
		var node: Node = parent.get_child(index)
		var trail: Array[int] = indices.duplicate()
		trail.append(index)
		if node is Control:
			var control: Control = node as Control
			baseline.append({"indices": trail, "name": String(node.name), "position": control.position, "size": control.size, "rotation": control.rotation, "scale": control.scale, "anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]})
		_sample_authored(node, trail)


func _geometry(label: String) -> void:
	_check(is_instance_valid(screen) and screen.get_instance_id() == identity, label + ": same canonical Shop instance")
	if not is_instance_valid(screen): return
	for record in baseline:
		var node: Node = screen
		for index in record["indices"]:
			if node == null or int(index) >= node.get_child_count():
				node = null
				break
			node = node.get_child(int(index))
		var control: Control = node as Control
		var name: String = String(record["name"])
		_check(control != null, label + ": authored control preserved " + name)
		if control == null: continue
		# Runtime selectors bind actual item IDs; the balance label also renames.
		if not name.begins_with("SelectProduct_") and name != "ShopCoinBalance":
			_check(String(control.name) == name, label + ": authored order/name " + name)
		_check(control.position.is_equal_approx(record["position"]), label + ": manual position " + name)
		_check(control.size.is_equal_approx(record["size"]), label + ": manual size " + name)
		_check(is_equal_approx(control.rotation, float(record["rotation"])) and control.scale.is_equal_approx(record["scale"]), label + ": manual transform " + name)
		_check([control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom] == record["anchors"], label + ": authored anchors " + name)
	_check(screen.find_children("LeftNav_*", "BaseButton", true, false).is_empty(), label + ": no old web sidebar controls")
	var back: TextureButton = screen.find_child("ShopBackToHub", true, false) as TextureButton
	var detail: Control = screen.find_child("ProductDetailPanel", true, false) as Control
	var feedback: Control = screen.find_child("ShopFeedbackPanel", true, false) as Control
	_check(back != null and detail != null and feedback != null, label + ": Back/detail/feedback exist")
	if back != null and detail != null and feedback != null:
		var rect: Rect2 = back.get_global_rect()
		_check(back.is_visible_in_tree() and not back.disabled, label + ": Back visible and enabled")
		_check(rect.position.is_equal_approx(Vector2(1016, 600)) and rect.size.is_equal_approx(Vector2(168, 52)), label + ": Back uses requested free-board margin")
		_check(not rect.intersects(detail.get_global_rect()) and not rect.intersects(feedback.get_global_rect()), label + ": Back does not cover information")
		_check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(rect), label + ": Back inside viewport")
		_check(back.texture_normal != null and back.texture_normal.resource_path == BACK_ART, label + ": existing approved Back art")
		for index in range(1, 6):
			var card: Control = screen.find_child("ProductSlot%02d" % index, true, false) as Control
			if card != null and card.is_visible_in_tree(): _check(not rect.intersects(card.get_global_rect()), label + ": Back does not cover card")


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
	var button: BaseButton = screen.find_child(name, true, false) as BaseButton
	_check(button != null, "Actual GUI control: " + name)
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, "Enabled visible control: " + name)
	if not button.is_visible_in_tree() or button.disabled: return false
	var fired: Array[bool] = [false]
	var witness: Callable = func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Viewport input activates GUI: " + name)
	return fired[0]


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	_check(rendered != null and rendered.get_size() == Vector2i(1280, 720), "Native viewport capture: " + name)
	if rendered == null: return
	var target: String = capture_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(target), "Capture never overwrites: " + name)
	if FileAccess.file_exists(target): return
	var saved: bool = rendered.save_png(ProjectSettings.globalize_path(target)) == OK
	_check(saved, "Capture saved: " + name)
	if saved: captures.append(target)


func _without_metadata(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for key in ["status_text", "saved_at_unix", "last_screen"]: result.erase(key)
	return result


func _case(locale: String, slot: int) -> void:
	# Original-schema fresh farm is setup only, not rich/earned progression.
	_check(GameState.new_state(slot), locale + ": fresh original farm saved in isolated slot")
	UILocale.set_locale(locale)
	ScreenRouter.go("shop")
	await _settle()
	screen = host.get_child(host.get_child_count() - 1)
	identity = screen.get_instance_id()
	_check(screen.scene_file_path == SHOP.resource_path, locale + ": canonical authored Shop scene")
	_geometry(locale + " fresh")
	await _capture(locale + "_01_BEFORE_TAB")
	await _press("Tab_Food")
	_check(String(screen.get("active_category")) == "food", locale + ": real food tab binding")
	_geometry(locale + " after tab")
	await _capture(locale + "_02_AFTER_TAB")
	await _press("Tab_Seeds")
	await _capture(locale + "_03_BEFORE_PAGE")
	await _press("ShopNextPage")
	_check(int(screen.get("page_index")) == 1, locale + ": real next-page binding once")
	_geometry(locale + " after page")
	await _capture(locale + "_04_AFTER_PAGE")
	await _press("ShopPreviousPage")
	await _press("SelectProduct_seed_tomato")
	var buy: BaseButton = screen.find_child("BuySelectedProduct", true, false) as BaseButton
	_check(buy != null and buy.disabled, locale + ": fresh tomato purchase locked")
	var before_lock: Dictionary = GameState.data.duplicate(true)
	var save_path: String = OS.get_environment("MSF_TEST_SAVE_DIR").path_join("my_sisters_farm_slot_%d.save" % slot)
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	if buy != null: await _click(buy.get_global_rect().get_center())
	_check(GameState.data == before_lock and FileAccess.get_file_as_bytes(save_path) == bytes_before, locale + ": disabled locked click preserves data and save bytes")
	_geometry(locale + " locked selection")
	await _press("Tab_Medicine")
	_check(String(screen.get("selected_product")) == "medicine", locale + ": tonic actual ID")
	_geometry(locale + " medicine tab")
	await _press("Tab_Seeds")
	await _press("SelectProduct_seed_carrot")
	var coins_before: int = int(GameState.data.get("coins", 0))
	var seeds_before: int = int(GameState.data.get("inventory", {}).get("seed_carrot", 0))
	var selected_slot_before: int = GameState.selected_slot
	await _capture(locale + "_05_BEFORE_BUY")
	await _press("BuySelectedProduct")
	_check(int(GameState.data.get("coins", 0)) == coins_before - 12, locale + ": one real carrot bundle charges locked price 12")
	_check(int(GameState.data.get("inventory", {}).get("seed_carrot", 0)) == seeds_before + 3, locale + ": one real carrot bundle adds three seeds")
	_check(GameState.selected_slot == selected_slot_before, locale + ": purchase preserves slot")
	_geometry(locale + " after buy")
	await _capture(locale + "_06_AFTER_BUY")
	var expected: Dictionary = _without_metadata(GameState.data)
	var stored: Dictionary = GameState.save_service.load_slot(slot)
	_check(bool(stored.get("ok", false)) and stored.get("state") is Dictionary, locale + ": action autosave exists without final manual save")
	if stored.get("state") is Dictionary: _check(_without_metadata(stored["state"]) == expected, locale + ": persisted gameplay equals RAM")
	_check(GameState.load_slot(slot), locale + ": actual isolated reload")
	await _settle()
	_check(_without_metadata(GameState.data) == expected, locale + ": actual reload preserves purchase")
	_geometry(locale + " after reload")
	await _press("ShopBackToHub")
	_check(ScreenRouter.current_screen == "hub", locale + ": actual Back GUI returns Home")
	_check(_without_metadata(GameState.data) == expected, locale + ": Back does not mutate gameplay")
	await _capture(locale + "_07_AFTER_BACK")
	completed.append(locale)


func _run() -> void:
	run_root = REPORT_ROOT.path_join("RUN_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()])
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		push_error("Manual Shop QA refuses existing evidence directory.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	get_window().size = Vector2i(1280, 720)
	var authored: Node = SHOP.instantiate()
	_sample_authored(authored, [])
	authored.free()
	_check(not baseline.is_empty(), "Authored descendant Control baseline sampled before ready; root viewport sizing excluded")
	var main: Node = MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost") as Control
	await _settle()
	await _case("vi", 1)
	await _case("en", 2)
	_check(completed == ["vi", "en"], "Both locale cases reached explicit completion markers")
	_check(captures.size() == 14, "All fourteen native before/after viewport captures saved")
	var result_path: String = run_root.path_join("MANUAL_SHOP_BINDING_V4_RESULTS.txt")
	var report: FileAccess = FileAccess.open(result_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write new Manual Shop QA report.")
		get_tree().quit(1)
		return
	var result: String = "MANUAL_SHOP_BINDING_V4_TEST_PASS" if failures.is_empty() else "MANUAL_SHOP_BINDING_V4_TEST_FAIL"
	report.store_line(result)
	report.store_line("Assertions: %d; Captures: %d; Authored Controls: %d" % [checks, captures.size(), baseline.size()])
	report.store_line("Completed locales: " + str(completed))
	report.store_line("Save root: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	report.store_line("GUI: Viewport.push_input only; pressed connections are read-only witnesses. Canonical routes/fresh original farms are setup only.")
	report.store_line("Scope: authored manual Shop geometry persists through EN/VI tab/page/selection/locked click/purchase/reload; actual approved-art Back routes Home. No rich data or economy/schema changes.")
	report.store_line("VISUAL REVIEW REQUIRED. No source continuity, lifecycle, architecture, commercial visual or whole-game/GDD approval follows from assertion PASS.")
	for failure in failures: report.store_line("FAIL: " + failure)
	for path in captures: report.store_line("CAPTURE: " + path)
	report.close()
	print(result)
	print("MANUAL_SHOP_BINDING_V4_RESULTS: " + ProjectSettings.globalize_path(result_path))
	get_tree().quit(0 if failures.is_empty() else 1)
