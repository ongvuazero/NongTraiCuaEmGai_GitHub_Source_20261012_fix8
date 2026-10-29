extends Node

# QA-only rendered pointer test. Uses isolated saves, not player data.
const MAIN = preload("res://scenes/main.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const VFX = preload("res://v7/production/field_action_vfx.gd")
const CAPTURES := "res://REPORTS/GDD_CLOSURE_V3/07_FIELD_REGRESSION"
var failures: Array[String] = []
var checks := 0
var host: Control
var screen: Node
var mouse_inside := false

func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated_root.is_empty() or not qa_root.contains("gdd_closure_v3") or qa_root == player_root or player_root.begins_with(qa_root + "/"):
		push_error("QA_ISOLATION_REQUIRED: Use a fresh gdd_closure_v3 test root separate from and not above player saves.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated_root.path_join(("my_sisters_farm_slot_%d.save" % slot) + suffix)):
				push_error("QA_ISOLATION_REQUIRED: Refusing occupied saves, temporary files or backups; supply a fresh gdd_closure_v3 test directory.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless":
		push_error("FIELD_REGRESSION_RENDER_REQUIRED: Rendered GUI and captures are required; headless is not visual proof.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FIELD_UI_QA: " + message)

func _settle(frames := 8) -> void:
	for _frame in range(frames): await get_tree().process_frame

func _capture(name: String) -> void:
	await _settle(2)
	# Capture the persistent selected state, not the 100ms press flash.
	await get_tree().create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(CAPTURES.path_join(name + ".png"))) == OK, "Capture " + name)

func _click(point: Vector2) -> void:
	var viewport := get_viewport()
	if not mouse_inside:
		viewport.notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	await _settle()

func _press(path: String) -> void:
	var button := screen.get_node(path) as BaseButton
	_check(button.is_visible_in_tree() and not button.disabled, "Usable button " + path)
	var fired := [false]
	button.pressed.connect(func() -> void: fired[0] = true, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	_check(fired[0], "Pointer activates " + path)

func _plot(plot_id: int) -> void:
	var polygon: PackedVector2Array = PixelMap.visual_interaction_polygon(plot_id)
	var point := Vector2.ZERO
	for vertex in polygon: point += vertex
	point /= polygon.size()
	var area := screen.get_node("EDIT_ME/FieldArea") as Control
	await _click(area.get_global_transform() * point)
	_check(screen.qa_last_clicked_plot_id() == plot_id, "Actual plot pointer " + str(plot_id))
	_check(screen.qa_world_rebuilds_per_action() == 0, "Zero full rebuilds after plot action")

func _tool(action: String) -> void:
	var path := "EDIT_ME/BottomActionHUD/Action_harvest" if action == "harvest" else "EDIT_ME/BottomActionHUD/ToolGroup/Action_" + action
	await _press(path)
	await get_tree().create_timer(0.18).timeout
	var button := screen.get_node(path) as BaseButton
	_check(bool(button.get_meta("field_selected", false)), "Tool is visibly selected " + action)
	_check((button.get_node("ToolStateFrame") as CanvasItem).visible, "Persistent selected frame " + action)
	_check((button.get_node("ToolStateFrame") as Panel).get_theme_stylebox("panel") == screen.tool_selected_style, "Selected style restored after press pulse " + action)
	_check(not bool(button.get_meta("field_pressed", false)), "Pressed metadata released " + action)

func _run() -> void:
	if OS.get_environment("MSF_TEST_SAVE_DIR").is_empty():
		push_error("QA_ISOLATION_REQUIRED: Set MSF_TEST_SAVE_DIR to a dedicated test directory. Player saves must not be overwritten.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	get_window().size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	for locale in ["vi", "en"]:
		UILocale.set_locale(locale)
		GameState.new_state(1, false)
		ScreenRouter.go("field")
		await _settle()
		screen = host.get_child(host.get_child_count() - 1)
		_check(screen.scene_file_path == "res://scenes/screens/05_field_gameplay.tscn", "Canonical field")
		await _capture(locale + "_01_EMPTY")
		await _tool("till")
		await _capture(locale + "_02_TILL_SELECTED")
		await _plot(1)
		_check(GameState.get_plot(1).is_hoed, "Till commits immediately")
		await _capture(locale + "_03_TILLED")
		var popup := "EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup"
		await _press("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed")
		_check((screen.get_node(popup) as CanvasItem).visible, "Attached seed picker opens")
		_check((screen.get_node(popup + "/Seed_tomato") as BaseButton).disabled, "Tomato locked")
		_check((screen.get_node(popup + "/Seed_pumpkin") as BaseButton).disabled, "Pumpkin locked")
		await _capture(locale + "_04_SEED_LOCKS")
		await _press(popup + "/Seed_carrot")
		await _plot(1)
		_check(GameState.get_plot(1).crop == "carrot", "Carrot planted")
		_check(int(GameState.data.inventory.seed_carrot) == 5, "Seed consumed once")
		await _capture(locale + "_05_PLANTED")
		await _tool("water")
		await _capture(locale + "_06_WATER_SELECTED")
		await _plot(1)
		_check(GameState.get_plot(1).watered_today, "Water commits immediately")
		await _capture(locale + "_07_WATERED")
		await _press("EDIT_ME/BottomActionHUD/Action_advance_day")
		_check(int(GameState.data.day) == 2, "Next Day")
		await _capture(locale + "_08_GROWING")
		for _day in range(5):
			if bool(GameState.get_plot(1).ready_to_harvest): break
			await _tool("water")
			await _plot(1)
			await _press("EDIT_ME/BottomActionHUD/Action_advance_day")
		_check(GameState.get_plot(1).ready_to_harvest, "Ready through real actions")
		await _capture(locale + "_09_READY")
		await _tool("harvest")
		await _plot(1)
		_check(int(GameState.data.inventory.crop_carrot) == 1, "Harvest grants one item")
		await _capture(locale + "_10_HARVESTED")
		# Fixture capture is deliberately labelled; not an earned-gameplay claim.
		QARichFixture.apply()
		ScreenRouter.go("hub")
		await _settle()
		ScreenRouter.go("field")
		await _settle()
		screen = host.get_child(host.get_child_count() - 1)
		await _press("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed")
		await _capture(locale + "_11_FIXTURE_999_PICKER")
		await _press(popup + "/Seed_pumpkin")
		# Test disabled feedback in a separate fixture, not normal-game mutation.
		GameState.data.energy = 0
		GameState.changed.emit()
		await _settle()
		_check((screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton).disabled, "Energy disabled state")
		await _capture(locale + "_12_FIXTURE_NO_ENERGY")
		GameState.data.energy = 100
		for id in range(1, 13):
			var plot := GameState.get_plot(id)
			plot.is_hoed = true
			plot.crop = ["carrot", "tomato", "pumpkin"][(id - 1) % 3]
			plot.growth_stage = 3 if plot.crop == "carrot" else 4
			plot.ready_to_harvest = true
		GameState.changed.emit()
		await _settle()
		await _capture(locale + "_13_FIXTURE_FULL_FIELD")
	# Validate each source resolves, has alpha, and cycles the intended atlas cell.
	GameState.new_state(1, false)
	GameState.get_plot(1).is_hoed = true
	ScreenRouter.go("hub")
	await _settle()
	ScreenRouter.go("field")
	await _settle()
	screen = host.get_child(host.get_child_count() - 1)
	for action in ["till", "seed", "water", "fertilize", "harvest"]:
		var fx := VFX.new()
		screen.renderer.fx_world.add_child(fx)
		fx.configure(1, action)
		fx.set_process(false)
		fx._set_frame(3)
		fx._update_visual(0.4)
		_check(fx.visual.texture is AtlasTexture, "Native atlas " + action)
		_check(fx.position == PixelMap.visual_crop_anchor(1), "Exact bed anchor " + action)
		_check(fx.source_sheet.get_image().detect_alpha() != Image.ALPHA_NONE, "Transparent source " + action)
		await _capture("FIXTURE_VFX_" + action.to_upper() + "_FRAME3")
		fx.queue_free()
	var report := FileAccess.open(CAPTURES.path_join("FIELD_REGRESSION_RESULTS.txt"), FileAccess.WRITE)
	report.store_line("GDD_CLOSURE_V3_FIELD_REGRESSION_PASS" if failures.is_empty() else "GDD_CLOSURE_V3_FIELD_REGRESSION_FAIL")
	report.store_line("Assertions: %d" % checks)
	for failure in failures: report.store_line(failure)
	report.close()
	print("GDD_CLOSURE_V3_FIELD_REGRESSION_PASS" if failures.is_empty() else "GDD_CLOSURE_V3_FIELD_REGRESSION_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

