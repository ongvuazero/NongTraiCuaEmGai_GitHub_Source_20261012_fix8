extends Node

# Additive rendered QA. All tested controls receive motion/down/up through
# Viewport.push_input. Route calls and fresh farms are setup only.
const MAIN = preload("res://scenes/main.tscn")
const DRAGON = preload("res://scenes/screens/10_dragon.tscn")
const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/ITCH_UI_RECOVERY_20261005/NAVIGATION"
const HOME_ROUTES := ["field_select", "shop", "storage", "animal", "dragon", "quest", "settings"]
const HOME_COPY := ["Ruộng", "Cửa hàng", "Kho", "Vật nuôi", "Đảo Rồng", "Nhiệm vụ", "Cài đặt"]
const DRAGON_COPY := ["Lò ấp trứng", "Nhà trẻ", "Sân chơi", "Shop Rồng", "Kho Rồng", "Sách Rồng"]
const DRAGON_ICONS := ["egg", "nursery", "play", "shop", "storage", "book"]
const PROTECTED_NODES := ["Background", "HUD_DaySeasonChip", "HUD_CoinChip", "HUD_EnergyChip", "HUD_DragonEnergyChip", "HatcheryPortalVisual", "FarmerVisual", "CatVisual", "DragonPortalIdentity", "DragonInfoPanel", "ComingSoonPanel", "ComingSoonTitle", "ComingSoonMessage", "DragonSectionPrimary", "DragonSectionSecondary", "DragonSelectionCycle", "DragonActionFeedback", "DragonIslandAccess"]

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var completed: Array[String] = []
var host: Control
var screen: Node
var shared_signature: Dictionary = {}
var shared_states: Dictionary = {}
var run_root := ""
var mouse_inside := false
var route_events: Array[String] = []
var logo_source_info: Dictionary = {}


func _ready() -> void:
	var isolated := OS.get_environment("MSF_TEST_SAVE_DIR")
	var absolute := ProjectSettings.globalize_path(isolated).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated.is_empty() or not absolute.contains("itch_ui_recovery_20261005") or absolute == player or player.begins_with(absolute + "/"):
		push_error("Navigation V5 QA requires a fresh itch_ui_recovery_20261005 MSF_TEST_SAVE_DIR separate from player saves and their ancestors.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated.path_join(("my_sisters_farm_slot_%d.save" % slot) + String(suffix))):
				push_error("Navigation V5 QA refuses existing saves/backups; it deletes nothing.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Navigation V5 QA requires rendered normal gameplay.")
		get_tree().quit(2)
		return
	mouse_inside = get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position())
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error("NAVIGATION_COHESION_V5: " + detail)


func _settle(frames := 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _route(route: String) -> void:
	ScreenRouter.go(route)
	await _settle()
	screen = host.get_child(host.get_child_count() - 1)
	_check(ScreenRouter.current_screen == route, "Setup route " + route)


func _record_route(route: String) -> void:
	route_events.append(route)


func _button(name: String) -> TextureButton:
	return screen.find_child(name, true, false) as TextureButton


func _move(point: Vector2) -> void:
	if not mouse_inside:
		get_viewport().notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)


func _press(name: String) -> void:
	var button := _button(name)
	_check(button != null, "Actual control exists " + name)
	if button == null: return
	_check(button.is_visible_in_tree() and not button.disabled, "Actual control enabled " + name)
	if not button.is_visible_in_tree() or button.disabled: return
	var fired: Array[bool] = [false]
	var witness := func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	var point := button.get_global_rect().get_center()
	_move(point)
	for down in [true, false]:
		var input := InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		input.pressed = bool(down)
		input.position = point
		input.global_position = point
		get_viewport().push_input(input, true)
	await _settle()
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Viewport pointer activated actual GUI " + name)


func _capture(name: String) -> void:
	_move(Vector2(1270, 700))
	await _settle(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and image.get_size() == Vector2i(1280, 720), "Native rendered capture " + name)
	if image == null: return
	if ScreenRouter.current_screen == "dragon": _rendered_logo(image, name)
	var path := run_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(path), "Capture refuses overwrite " + name)
	if FileAccess.file_exists(path): return
	_check(image.save_png(ProjectSettings.globalize_path(path)) == OK, "Capture saved " + name)
	captures.append(path)


func _rendered_logo(rendered: Image, detail: String) -> void:
	var logo := screen.find_child("Logo", true, false) as TextureRect
	_check(logo != null and logo.is_visible_in_tree() and logo.texture != null, detail + " shared Logo node is visible")
	if logo == null or logo.texture == null: return
	logo_source_info = logo.get_meta("logo_source_diagnostics", {})
	_check(int(logo_source_info.get("logo_colored_rgb_pixels", 0)) > 10000, detail + " original zero-alpha UI logo still contains recoverable source RGB")
	_check(logo.get_global_rect() == Rect2(FarmNav.LOGO), detail + " Logo occupies the actual Home art rectangle")
	var source := logo.texture.get_image()
	_check(source != null and source.get_size() == FarmNav.LOGO.size and source.get_used_rect().has_area(), detail + " Logo contains actual source pixels")
	if source == null: return
	var total := 0
	var matched := 0
	for y in range(3, source.get_height(), 7):
		for x in range(3, source.get_width(), 7):
			var expected := source.get_pixel(x, y)
			if expected.a < 0.98: continue
			total += 1
			var actual := rendered.get_pixel(int(logo.global_position.x) + x, int(logo.global_position.y) + y)
			if absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) < 0.12: matched += 1
	_check(total > 100 and float(matched) / float(maxi(total, 1)) > 0.90, detail + " rendered Logo pixels visibly match approved source; not merely a populated node")


func _gameplay() -> Dictionary:
	var snapshot: Dictionary = GameState.data.duplicate(true)
	for key in ["saved_at_unix", "last_screen", "status_text"]: snapshot.erase(key)
	return snapshot


func _pose(control: Control) -> Dictionary:
	var record := {"position": control.position, "size": control.size, "rotation": control.rotation, "scale": control.scale, "anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]}
	if control is TextureRect:
		record["art"] = control.texture.resource_path if control.texture != null else ""
	return record


func _protected_scene() -> void:
	var before_scene := load("res://BACKUPS/ITCH_UI_RECOVERY_20261005/scenes/screens/10_dragon.tscn") as PackedScene
	_check(before_scene != null, "Pre-edit scene backup exists")
	if before_scene == null: return
	var before := before_scene.instantiate()
	var after := DRAGON.instantiate()
	for node_name in PROTECTED_NODES:
		var old_node := before.find_child(String(node_name), true, false) as Control
		var new_node := after.find_child(String(node_name), true, false) as Control
		_check(old_node != null and new_node != null, "Protected authored node exists " + String(node_name))
		if old_node != null and new_node != null:
			_check(_pose(old_node) == _pose(new_node), "Main content/HUD art and authored geometry preserved " + String(node_name))
	before.free()
	after.free()


func _component(button: TextureButton, expected: String, detail: String) -> void:
	_check(button != null, detail + " component exists")
	if button == null: return
	var signature := FarmNav.component_signature(button)
	if shared_signature.is_empty():
		shared_signature = signature
		for state in ["texture_normal", "texture_hover", "texture_pressed", "texture_disabled", "texture_focused"]:
			shared_states[state] = button.get(String(state))
	_check(signature == shared_signature, detail + " uses identical source art, geometry, font, color, states and dimensions")
	for state in ["texture_normal", "texture_hover", "texture_pressed", "texture_disabled", "texture_focused"]:
		_check(button.get(String(state)) == shared_states[state], detail + " shares actual texture instance " + String(state))
	var caption := button.get_node_or_null("Caption") as Label
	_check(caption != null and caption.text == tr(expected), detail + " localized caption")
	if caption != null:
		var text_width := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		var factor := minf(button.size.y / 62.0, 1.0)
		var safe_width := button.size.x - 75.0 * factor - 14.0 * factor
		if caption.autowrap_mode == TextServer.AUTOWRAP_OFF:
			_check(text_width + 2.0 <= safe_width, detail + " Font.get_string_size fits actual safe caption footprint after icon and wood edge")
		else:
			var paragraph := TextParagraph.new()
			paragraph.width = safe_width - 2.0
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.add_string(caption.text, caption.get_theme_font("font"), caption.get_theme_font_size("font_size"))
			_check(paragraph.get_line_count() <= 2, detail + " long caption shapes into at most two readable lines")
			for line in range(paragraph.get_line_count()):
				_check(paragraph.get_line_width(line) + 2.0 <= safe_width, detail + " actual shaped line fits safe caption footprint " + str(line))
		_check(caption.position.x >= 75.0 * factor and caption.position.x + caption.size.x <= button.size.x - 14.0 * factor + 0.1, detail + " actual caption rectangle stays outside icon area and inside wood edge")
		_check(caption.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, detail + " manually localized caption cannot be retranslated after fitting")
		_check(caption.get_theme_font_size("font_size") >= 16 and caption.get_theme_font_size("font_size") <= 18, detail + " measured fitting keeps a readable 16-18px game font")
	var icon := button.get_node_or_null("NavigationIcon") as TextureRect
	_check(icon != null and icon.texture != null, detail + " semantic art icon exists")
	if icon != null and icon.texture != null:
		var image := icon.texture.get_image()
		_check(image != null and image.get_used_rect().has_area(), detail + " icon is nonempty")
	_check(button.texture_normal != button.texture_hover and button.texture_normal != button.texture_pressed, detail + " visible hover/pressed feedback uses game art")


func _locale_case(locale: String, slot: int) -> void:
	_check(GameState.new_state(slot), locale + " fresh isolated farm persisted")
	UILocale.set_locale(locale)
	await _route("hub")
	var direct: Array[BaseButton] = []
	for child in screen.get_children():
		if child is BaseButton: direct.append(child as BaseButton)
	for index in range(HOME_ROUTES.size()):
		var button := _button("LeftNav_%s" % HOME_ROUTES[index])
		_component(button, String(HOME_COPY[index]), locale + " Home menu " + str(index))
		_check(direct.size() > index and direct[index] == button, locale + " direct Home control order preserved " + str(index))
	await _capture(locale + "_HOME_SHARED_MENU")
	for index in range(HOME_ROUTES.size()):
		await _route("hub")
		var before := _gameplay()
		await _press("LeftNav_%s" % HOME_ROUTES[index])
		_check(ScreenRouter.current_screen == String(HOME_ROUTES[index]), locale + " Home callback reaches " + String(HOME_ROUTES[index]))
		_check(_gameplay() == before, locale + " navigation does not change gameplay " + String(HOME_ROUTES[index]))
		if String(HOME_ROUTES[index]) == "settings":
			_check(GameState.settings_return == "hub", locale + " Settings return remains Home")
	await _route("dragon")
	var identity := screen.get_instance_id()
	var event_count := route_events.size()
	var panel := screen.find_child("ComingSoonPanel", true, false) as Control
	_check(panel != null and not panel.visible, locale + " Dragon begins with context closed")
	for index in range(DRAGON_COPY.size()):
		var button := _button("DragonNav_%d" % index)
		_component(button, String(DRAGON_COPY[index]), locale + " Dragon menu " + str(index))
		if button != null:
			_check(button.get_meta("farm_navigation_icon", "") == String(DRAGON_ICONS[index]), locale + " Dragon semantic icon " + str(index))
	await _capture(locale + "_DRAGON_SHARED_MENU_CLOSED")
	for index in range(DRAGON_COPY.size()):
		var before := _gameplay()
		await _press("DragonNav_%d" % index)
		_check(panel != null and panel.visible and int(screen.get("active_section")) == index, locale + " real Dragon section callback " + str(index))
		var title := screen.find_child("ComingSoonTitle", true, false) as Label
		_check(title != null and title.text == tr(String(DRAGON_COPY[index])).to_upper(), locale + " opened section has localized title " + str(index))
		_check(screen.get_instance_id() == identity and route_events.size() == event_count, locale + " Dragon sections refresh in place " + str(index))
		_check(_gameplay() == before, locale + " section navigation changes no gameplay " + str(index))
		var button := _button("DragonNav_%d" % index)
		_check(button != null and button.get_meta("selected", false) and button.texture_normal == button.texture_pressed, locale + " selected state keeps shared art " + str(index))
		if index == 0: await _capture(locale + "_DRAGON_INCUBATOR_OPEN")
		await _press("DragonNav_%d" % index)
		_check(panel != null and not panel.visible, locale + " repeated Dragon menu input closes context " + str(index))
	var other_locale := "en" if locale == "vi" else "vi"
	UILocale.set_locale(other_locale)
	await _settle()
	_check(screen.get_instance_id() == identity, locale + " active Dragon locale change preserves authored screen")
	for index in range(DRAGON_COPY.size()):
		_component(_button("DragonNav_%d" % index), String(DRAGON_COPY[index]), locale + " active switch to " + other_locale + " menu " + str(index))
	UILocale.set_locale(locale)
	await _settle()
	for index in range(DRAGON_COPY.size()):
		_component(_button("DragonNav_%d" % index), String(DRAGON_COPY[index]), locale + " active switch back menu " + str(index))
	var moved := _button("DragonNav_0")
	var old_position := moved.position
	moved.position += Vector2(15, 0)
	GameState.changed.emit()
	await _settle()
	_check(moved.position == old_position + Vector2(15, 0), locale + " authored/manual menu position survives ordinary refresh")
	_check(screen.get_instance_id() == identity, locale + " ordinary refresh preserves screen instance")
	moved.position = old_position
	await _press("DragonBackToHub")
	_check(ScreenRouter.current_screen == "hub", locale + " actual Dragon Back reaches Home")
	completed.append(locale)


func _run() -> void:
	run_root = REPORT_ROOT.path_join("RUN_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()])
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_root)) != OK:
		push_error("Cannot create fresh Navigation V5 evidence directory.")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	_protected_scene()
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost") as Control
	await _settle()
	ScreenRouter.screen_changed.connect(_record_route)
	await _locale_case("vi", 1)
	await _locale_case("en", 2)
	_check(completed == ["vi", "en"], "Both locale cases explicitly completed")
	_check(captures.size() == 6, "Six required rendered captures saved")
	var status := "ITCH_NAVIGATION_COHESION_V5_PASS" if failures.is_empty() else "ITCH_NAVIGATION_COHESION_V5_FAIL"
	var report := FileAccess.open(run_root.path_join("RESULTS.json"), FileAccess.WRITE)
	if report == null:
		push_error("Cannot save Navigation V5 result evidence.")
		get_tree().quit(1)
		return
	report.store_string(JSON.stringify({"result": status, "checks": checks, "failures": failures, "captures": captures, "completed_locales": completed, "shared_component": shared_signature, "logo_source_diagnostics": logo_source_info, "gui_input": "Viewport.push_input motion/down/up only; signal witnesses are read-only", "scope": "Home seven navigation routes/order/callbacks; Dragon six section callbacks/open-close/selected states/Back/in-place manual positioning; identical actual art resources/style/typography; EN/VI captions and rendered captures; preserved serialized main content and HUD", "save_root": OS.get_environment("MSF_TEST_SAVE_DIR"), "limits": "Presentation and real-menu-input evidence; no claim of earned Dragon progression or complete GDD validation."}, "\t"))
	report.close()
	print(status)
	print("NAVIGATION_V5_RESULTS: " + ProjectSettings.globalize_path(run_root.path_join("RESULTS.json")))
	get_tree().quit(0 if failures.is_empty() else 1)
