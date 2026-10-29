extends Node

const MAIN = preload("res://scenes/main.tscn")
const Rich = preload("res://scripts/qa_rich_fixture.gd")
const CAPTURES := "res://REPORTS/MASTER_PLAN_V1/CAPTURES"
const ROUTES := ["title", "save", "hub", "field_select", "field", "shop", "storage", "settings", "animal", "dragon", "quest", "islands", "craft", "creatures", "events"]
var failures: Array[String] = []
var observations: Array = []
var host: Control
var checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("MASTER_UI_QA: " + message)


func _settle(frames := 8) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _screen() -> Node:
	return host.get_child(host.get_child_count() - 1)


func _route(route: String) -> Node:
	ScreenRouter.go(route)
	await _settle()
	_check(ScreenRouter.current_screen == route, "Route " + route)
	_check(_screen().scene_file_path == ScreenRouter.SCREENS[route].resource_path, "Canonical scene " + route)
	return _screen()


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	_check(screenshot.get_size() == Vector2i(1280, 720), "1280x720 screenshot " + path)
	_check(screenshot.save_png(ProjectSettings.globalize_path(path)) == OK, "Screenshot saved " + path)


func _observe(screen: Node, locale: String, state: String) -> void:
	for node in screen.find_children("*", "", true, false):
		if node is Label and node.is_visible_in_tree():
			var label := node as Label
			var font := label.get_theme_font("font")
			var rectangle := label.get_global_rect()
			observations.append({
				"route": ScreenRouter.current_screen, "locale": locale, "fixture": state,
				"node": str(screen.get_path_to(label)), "text": label.text,
				"rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y],
				"font": font.resource_path, "font_size": label.get_theme_font_size("font_size"),
				"minimum": [label.get_minimum_size().x, label.get_minimum_size().y],
				"autowrap": label.autowrap_mode
			})


func _run() -> void:
	if OS.get_environment("MSF_TEST_SAVE_DIR").is_empty():
		push_error("QA_ISOLATION_REQUIRED: Set MSF_TEST_SAVE_DIR to a dedicated test directory. Player saves and language preferences must not be overwritten.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	get_window().size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	var font := load("res://assets/fonts/BeVietnamPro-Regular.ttf") as Font
	for glyph in "ăâđêôơưÁẮẲẴẶẤẦẨẪẬếềễệớờởỡợứừửữự":
		_check(font.has_char(glyph.unicode_at(0)), "Vietnamese glyph " + glyph)
	GameState.new_state(1, false)
	_check(int(GameState.data.inventory.seed_carrot) == 6, "Production starts at 6 Carrot seeds")
	_check(int(GameState.data.coins) == 400, "Production starts at 400 coins")
	for fixture in ["FRESH", "RICH"]:
		if fixture == "RICH":
			Rich.apply()
			_check(int(GameState.data.inventory.seed_carrot) == 999, "Rich 999 seed")
			_check(int(GameState.data.inventory.crop_carrot) == 999, "Rich 999 crop")
			_check(int(GameState.data.coins) == 999999, "Rich coin count")
		for locale in ["vi", "en"]:
			UILocale.set_locale(locale)
			await _settle()
			_check(UILocale.current_locale() == locale, "Locale " + locale)
			_check(UILocale.translate_message("Need 900 coins; you have 400.") == ("Cần 900 xu; hiện có 400." if locale == "vi" else "Need 900 coins; you have 400."), "Dynamic translated requirement")
			_check(UILocale.translate_message("Spring") == ("Xuân" if locale == "vi" else "Spring"), "Season alias")
			for index in range(ROUTES.size()):
				var screen := await _route(ROUTES[index])
				_observe(screen, locale, fixture)
				await _capture(CAPTURES.path_join("%s_%s_%02d_%s.png" % [fixture, locale, index + 1, ROUTES[index]]))
	# Prove live retranslation without a route change.
	var settings := await _route("settings")
	var language_button := settings.find_child("SettingsLanguageToggle", true, false) as BaseButton
	_check(language_button != null, "Real Settings language control")
	if language_button != null:
		_check(not language_button.get_signal_connection_list("pressed").is_empty(), "Language handler")
		language_button.pressed.emit()
		await _settle()
		_check(UILocale.current_locale() == "vi", "Settings switched en to vi")
		language_button.pressed.emit()
		await _settle()
		_check(UILocale.current_locale() == "en", "Settings switched vi to en")
	UILocale.set_locale("vi")
	GameState.new_state(1, false)
	_check(int(GameState.data.inventory.seed_carrot) == 6, "Rich fixture did not mutate New Game definition")
	var stream := FileAccess.open("res://REPORTS/MASTER_PLAN_V1/LABEL_OBSERVATIONS.json", FileAccess.WRITE)
	stream.store_string(JSON.stringify(observations, "\t"))
	stream.close()
	var report := FileAccess.open("res://REPORTS/MASTER_PLAN_V1/UI_TEST_RESULTS.txt", FileAccess.WRITE)
	report.store_line("MASTER_UI_QA_PASS" if failures.is_empty() else "MASTER_UI_QA_FAIL")
	report.store_line("Assertions: %d" % checks)
	for failure in failures:
		report.store_line(failure)
	report.close()
	print("MASTER_UI_QA_PASS" if failures.is_empty() else "MASTER_UI_QA_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

