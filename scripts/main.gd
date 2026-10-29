# LEGACY_NOT_ROUTED (V6.8.3): retained only for historical recovery.
# project.godot -> scenes/main.tscn -> scripts/main_v3.gd, and ScreenRouter owns
# every player-visible screen. Do not attach this legacy monolithic renderer to
# a runnable scene or route; its embedded Save UI is not canonical.
extends Control


const FarmData = preload("res://scripts/farm_data.gd")
const UIAssetRegistry = preload("res://scripts/ui_asset_registry.gd")
const SaveService = preload("res://scripts/save_service.gd")

const SCREEN_TITLE := "title"
const SCREEN_SAVE := "save"
const SCREEN_HUB := "hub"
const SCREEN_FIELD := "field"
const SCREEN_ANIMAL_INSIDE := "animal_inside"
const SCREEN_SHOP := "shop"
const SCREEN_STORAGE := "storage"
const SCREEN_SETTINGS := "settings"
const SCREEN_DRAGON := "dragon"

const SAVE_BOARD := UIAssetRegistry.ROOT + "/REPAIRS_AND_SHARED/SAVE/save_preview_detail_board.png"

const COLOR_CREAM := Color(0.99, 0.96, 0.88, 1.0)
const COLOR_SOFT := Color(0.94, 0.91, 0.82, 0.98)
const COLOR_TEXT := Color(0.17, 0.11, 0.05, 1.0)
const COLOR_GOLD := Color(0.95, 0.84, 0.47, 0.96)
const COLOR_BLUE := Color(0.22, 0.48, 0.88, 0.86)
const COLOR_BLUE_LIGHT := Color(0.74, 0.90, 0.98, 0.72)
const COLOR_BROWN := Color(0.28, 0.18, 0.08, 0.86)
const COLOR_BROWN_DARK := Color(0.20, 0.13, 0.07, 0.92)
const COLOR_DIM := Color(0.03, 0.03, 0.03, 0.48)
const COLOR_GREEN := Color(0.30, 0.76, 0.42, 0.95)
const COLOR_RED := Color(0.90, 0.35, 0.29, 0.96)

var _ui_root: Control
var _state: Dictionary = {}
var _current_screen: String = SCREEN_TITLE
var _current_overlay := ""
var _farmer_action := "idle"
var _save_service := SaveService.new()
var _save_mode := "load"
var _selected_save_slot := 1
var _slot_confirmation := ""
var _settings_return_screen := SCREEN_TITLE
var _settings_snapshot: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_title("Nong Trai Vui Ve")
	var isolated_save_dir := OS.get_environment("MSF_TEST_SAVE_DIR")
	if not isolated_save_dir.is_empty():
		_save_service = SaveService.new(isolated_save_dir)
	_state = FarmData.create_initial_state()
	_save_service.migrate_legacy_save_if_needed()
	_ensure_audio_buses()
	_apply_audio_settings()
	_current_screen = SCREEN_TITLE
	_render()


func _render() -> void:
	if is_instance_valid(_ui_root):
		remove_child(_ui_root)
		_ui_root.queue_free()

	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_root)

	match _current_screen:
		SCREEN_TITLE:
			_render_title()
		SCREEN_SAVE:
			_render_save_slots()
		SCREEN_HUB:
			_render_hub()
		SCREEN_FIELD:
			_render_field()
		SCREEN_ANIMAL_INSIDE:
			_render_animal_inside()
		SCREEN_SHOP:
			_render_full_screen_panel("shop")
		SCREEN_STORAGE:
			_render_full_screen_panel("storage")
		SCREEN_SETTINGS:
			_render_full_screen_panel("settings")
		SCREEN_DRAGON:
			_render_dragon()
		_:
			_current_screen = SCREEN_HUB
			_render_hub()

	if _current_overlay != "":
		_render_overlay()


func _render_title() -> void:
	_add_background_texture(UIAssetRegistry.background("title"))
	_add_environment_layers("title")
	var logo := _make_label("MY SISTER'S\nFARM", 54, Color(0.35, 0.14, 0.06), HORIZONTAL_ALIGNMENT_CENTER)
	logo.position = Vector2(70, 84)
	logo.size = Vector2(390, 150)
	_ui_root.add_child(logo)
	var menu := VBoxContainer.new()
	menu.position = Vector2(154, 278)
	menu.size = Vector2(250, 300)
	menu.add_theme_constant_override("separation", 12)
	_ui_root.add_child(menu)
	for entry in [
		{"label": "Tiep tuc", "action": "continue_game"},
		{"label": "Tro choi moi", "action": "open_new_game"},
		{"label": "Cai dat", "action": "open_settings"},
		{"label": "Thoat", "action": "quit_game"},
	]:
		var button := _make_button(entry["label"], entry["action"] == "continue_game", Vector2(250, 54))
		button.pressed.connect(_handle_action.bind(entry["action"]))
		menu.add_child(button)


func _render_save_slots() -> void:
	_add_background_texture(UIAssetRegistry.background("title"))
	var title_text := "Chon tep de tai" if _save_mode == "load" else "Chon tep cho tro choi moi"
	var title := _make_label(title_text, 34, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(390, 30)
	title.size = Vector2(500, 55)
	_ui_root.add_child(title)
	var board := TextureRect.new()
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.texture = load(SAVE_BOARD)
	board.position = Vector2(220, 78)
	board.size = Vector2(840, 560)
	board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(board)
	var list := VBoxContainer.new()
	list.position = Vector2(280, 156)
	list.size = Vector2(430, 350)
	list.add_theme_constant_override("separation", 14)
	_ui_root.add_child(list)
	for slot_id in range(1, SaveService.SLOT_COUNT + 1):
		var metadata := _save_service.get_slot_metadata(slot_id)
		var slot_label := "Slot %d - TRONG" % slot_id
		if metadata["occupied"] and metadata["valid"]:
			slot_label = "Slot %d | Ngay %d | %d xu" % [slot_id, int(metadata["day"]), int(metadata["coins"])]
		elif metadata["occupied"]:
			slot_label = "Slot %d - SAVE LOI" % slot_id
		var button := _make_button(slot_label, slot_id == _selected_save_slot, Vector2(430, 82))
		button.pressed.connect(_select_save_slot.bind(slot_id))
		list.add_child(button)

	var selected_meta := _save_service.get_slot_metadata(_selected_save_slot)
	var details := VBoxContainer.new()
	details.position = Vector2(740, 166)
	details.size = Vector2(270, 330)
	details.add_theme_constant_override("separation", 12)
	_ui_root.add_child(details)
	details.add_child(_make_label("Slot %d" % _selected_save_slot, 26, COLOR_TEXT))
	if selected_meta["occupied"] and selected_meta["valid"]:
		details.add_child(_make_label("Ngay: %d" % int(selected_meta["day"]), 18, COLOR_TEXT))
		details.add_child(_make_label("Tien: %d" % int(selected_meta["coins"]), 18, COLOR_TEXT))
		details.add_child(_make_label("Vi tri: %s" % String(selected_meta["location"]), 17, COLOR_TEXT))
		details.add_child(_make_label("Cap nhat: %s" % Time.get_datetime_string_from_unix_time(int(selected_meta["last_played"])), 14, COLOR_TEXT))
	else:
		details.add_child(_make_label("Tep trong" if not selected_meta["occupied"] else "Save bi loi - tep goc duoc giu", 17, COLOR_TEXT))
	if not _slot_confirmation.is_empty():
		details.add_child(_make_label("Xac nhan: %s. Bam lai nut xac nhan." % _slot_confirmation, 15, COLOR_RED))
	var confirm := _make_button("Xac nhan", true, Vector2(250, 48))
	confirm.pressed.connect(_confirm_save_slot)
	details.add_child(confirm)
	var delete := _make_button("Xoa slot", false, Vector2(250, 44))
	delete.disabled = not bool(selected_meta["occupied"])
	delete.pressed.connect(_request_delete_slot)
	details.add_child(delete)
	var back := _make_button("Quay lai", false, Vector2(150, 44))
	back.position = Vector2(250, 625)
	back.pressed.connect(_handle_action.bind("go_title"))
	_ui_root.add_child(back)


func _render_hub() -> void:
	_add_background_texture(UIAssetRegistry.background("hub"))
	_add_environment_layers("hub")
	_build_top_hud("My Sister's Farm", "Trang trai cua em gai")
	_build_left_navigation("hub")
	_render_farmer(Vector2(648, 468), 0.32)
	_build_status_card(Vector2(930, 575), Vector2(316, 108))
	_build_order_board()


func _render_field() -> void:
	_add_background_texture(UIAssetRegistry.background("field"))
	_build_top_hud("Ruong", "12 o dat doc lap - cay, gieo, tuoi, bon, thu hoach")
	_build_status_card(Vector2(28, 584), Vector2(262, 100))
	_build_field_action_bar()

	for plot in _state["field_plots"]:
		_add_plot_view(plot)

	var right_panel := Panel.new()
	right_panel.position = Vector2(915, 98)
	right_panel.size = Vector2(336, 474)
	right_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.23, 0.15, 0.08, 0.88), COLOR_GOLD, 28))
	_ui_root.add_child(right_panel)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 14)
	scroll.size = Vector2(308, 446)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(scroll)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(286, 0)
	info.add_theme_constant_override("separation", 10)
	scroll.add_child(info)
	var plot := _get_selected_plot()
	var seed_id: String = _state["selected_seed"]

	info.add_child(_make_label("Thong tin ruong", 25, COLOR_CREAM))
	info.add_child(_make_media_preview(UIAssetRegistry.seed_card(seed_id, true), Vector2(286, 118), Color(0.97, 0.92, 0.82, 0.12)))
	info.add_child(_make_label("Hat dang chon: %s" % FarmData.get_crop_label(seed_id), 16, Color(0.99, 0.90, 0.62, 1.0)))
	info.add_child(_make_label("Hat con lai: %d" % int(_state["inventory"].get(FarmData.CROP_DEFINITIONS[seed_id]["seed_item"], 0)), 15, COLOR_SOFT))
	info.add_child(_make_spacer(2))

	if plot.is_empty():
		info.add_child(_make_label("Chon 1 o dat de xem chi tiet.", 15, COLOR_SOFT))
	else:
		info.add_child(_make_label("O %02d" % int(plot["id"]), 20, COLOR_CREAM))
		info.add_child(_make_label("Trang thai: %s" % _plot_status_text(plot), 15, COLOR_SOFT))
		info.add_child(_make_label("Cay trong: %s" % _plot_crop_text(plot), 15, COLOR_SOFT))
		info.add_child(_make_label("Giai doan: %d" % int(plot["growth_stage"]), 15, COLOR_SOFT))
		info.add_child(_make_label("Da tuoi: %s" % ("Co" if plot["watered_today"] else "Chua"), 15, COLOR_SOFT))
		info.add_child(_make_label("Bon dang cho: %s" % ("Co" if plot["fertilizer_pending"] else "Chua"), 15, COLOR_SOFT))

	info.add_child(_make_spacer(6))
	info.add_child(_make_label("Ton kho nhanh", 18, Color(0.99, 0.90, 0.62, 1.0)))
	for item_id in ["seed_carrot", "seed_tomato", "seed_pumpkin", "crop_carrot", "crop_tomato", "crop_pumpkin"]:
		info.add_child(_make_label("- %s: %d" % [FarmData.get_inventory_name(item_id), int(_state["inventory"].get(item_id, 0))], 14, COLOR_SOFT))

	info.add_child(_make_spacer(6))
	var active_order := _get_active_order()
	info.add_child(_make_label("Don hien tai", 18, Color(0.99, 0.90, 0.62, 1.0)))
	info.add_child(_make_label("%s x%d" % [FarmData.get_inventory_name(active_order["need_item"]), int(active_order["need_amount"])], 14, COLOR_SOFT))
	info.add_child(_make_label("Thuong: %d tien" % int(active_order["reward_coins"]), 14, COLOR_SOFT))

	info.add_child(_make_spacer(6))
	var small_row := HBoxContainer.new()
	small_row.add_theme_constant_override("separation", 8)
	info.add_child(small_row)
	for entry in [
		{"label": "Kho", "action": "open_inventory"},
		{"label": "Shop", "action": "open_shop"},
		{"label": "Thuong", "action": "open_reward"},
	]:
		var button := _make_button(entry["label"], false, Vector2(90, 40))
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_handle_action.bind(entry["action"]))
		small_row.add_child(button)

	info.add_child(_make_spacer(4))
	info.add_child(_make_label(_state["status_text"], 14, Color(0.99, 0.91, 0.64, 1.0)))
	_render_farmer(Vector2(265, 500), 0.30)


func _render_animal_entry() -> void:
	_add_background_texture(UIAssetRegistry.background("animal"))
	_add_environment_layers("animal")
	_build_top_hud("Khu chuong", "Tu hub vao man ngoai cua khu nuoi, sau do moi vao ben trong.")
	_build_status_card(Vector2(980, 580), Vector2(250, 92))
	_build_action_bar([
		{"label": "Vao chuong", "action": "go_animal_inside"},
		{"label": "Kho", "action": "open_inventory"},
		{"label": "Pet", "action": "open_pet"},
		{"label": "Hub", "action": "go_hub"},
	])

	var hotspot := _make_hotspot(Rect2(270, 66, 295, 210), "Chuong", "go_animal_inside")
	_ui_root.add_child(hotspot)

	var tag := _make_chip("Click vao chuong de vao man trong", Color(0.06, 0.06, 0.07, 0.90))
	tag.position = Vector2(250, 42)
	_ui_root.add_child(tag)

	var panel := _create_panel(Rect2(880, 110, 350, 186), COLOR_BROWN, COLOR_GOLD, 26)
	_ui_root.add_child(panel)
	var box := _panel_body(panel, 8)
	box.add_child(_make_label("Flow dung", 24, COLOR_CREAM))
	box.add_child(_make_label("Khong mo panel to de len hub. Chuong la 1 scene rieng, tu do moi vao man thao tac vat nuoi.", 15, COLOR_SOFT))
	box.add_child(_make_media_preview(UIAssetRegistry.get_animal_texture("chicken"), Vector2(302, 92), Color(0.97, 0.92, 0.82, 0.12)))
	box.add_child(_make_label(_state["status_text"], 14, Color(0.99, 0.91, 0.64, 1.0)))


func _render_animal_inside() -> void:
	_add_background_texture(UIAssetRegistry.background("animal"))
	_add_environment_layers("animal")
	_build_top_hud("Khu vat nuoi", "Cho an, cham soc, thu gom va don dep")
	_build_left_navigation("animal")
	_build_action_bar([
		{"label": "Cho an", "action": "feed_animals"},
		{"label": "Don", "action": "clean_animals"},
		{"label": "Vuot", "action": "pet_animals"},
		{"label": "Thu", "action": "collect_eggs"},
		{"label": "Kho", "action": "open_inventory"},
		{"label": "Hub", "action": "go_hub"},
	])

	var animal: Dictionary = _state["animal"]
	var panel := _create_panel(Rect2(882, 108, 352, 388), COLOR_BROWN_DARK, COLOR_GOLD, 28)
	_ui_root.add_child(panel)
	var box := _panel_body(panel, 12)
	box.add_child(_make_label("Trang thai vat nuoi", 25, COLOR_CREAM))
	box.add_child(_make_media_preview(UIAssetRegistry.animal_overlay("happy_cared_heart"), Vector2(304, 110), Color(0.97, 0.92, 0.82, 0.12)))
	box.add_child(_make_stat_bar("Do no", int(animal["fullness"]), Color(0.96, 0.72, 0.28, 0.95)))
	box.add_child(_make_stat_bar("Sach se", int(animal["cleanliness"]), Color(0.40, 0.82, 0.98, 0.95)))
	box.add_child(_make_stat_bar("Tam trang", int(animal["happiness"]), Color(0.95, 0.38, 0.48, 0.95)))
	box.add_child(_make_label("Trung san sang: %d" % int(animal["eggs_ready"]), 16, COLOR_SOFT))
	box.add_child(_make_label(_state["status_text"], 14, Color(0.99, 0.91, 0.64, 1.0)))
	_render_animal_world_status(animal)
	_render_farmer(Vector2(350, 500), 0.30)


func _render_full_screen_panel(kind: String) -> void:
	_add_background_texture(UIAssetRegistry.background(kind))
	_add_environment_layers(kind)
	var titles := {"shop": "Shop", "storage": "Kho", "settings": "Cai dat"}
	_build_top_hud(titles[kind], "Quan ly trang trai")
	_build_left_navigation(kind)
	var panel := _create_panel(Rect2(245, 100, 980, 570), Color(0.98, 0.93, 0.82, 0.92), Color(0.45, 0.25, 0.10, 0.92), 24)
	_ui_root.add_child(panel)
	var content := _panel_body(panel, 10)
	content.add_child(_make_label(titles[kind], 30, COLOR_TEXT))
	match kind:
		"shop":
			_build_shop_overlay(content)
		"storage":
			_build_inventory_overlay(content)
		"settings":
			_build_runtime_settings(content)


func _render_dragon() -> void:
	_add_background_texture(UIAssetRegistry.background("dragon_near"))
	_add_environment_layers("dragon")
	_build_top_hud("Dao Rong", "Khu rong hien tai - khong mo rong breeding/combat")
	_build_left_navigation("dragon")
	var dragon := TextureRect.new()
	dragon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dragon.texture = load(UIAssetRegistry.ROOT + "/REPAIRS_AND_SHARED/DRAGON/blue_sleeping_dragon.png")
	dragon.position = Vector2(570, 270)
	dragon.size = Vector2(390, 330)
	dragon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui_root.add_child(dragon)
	var card := _create_panel(Rect2(940, 445, 295, 185), Color(0.98, 0.93, 0.82, 0.92), Color(0.45, 0.25, 0.10), 22)
	_ui_root.add_child(card)
	var body := _panel_body(card, 7)
	body.add_child(_make_label("Rong xanh dang ngu", 22, COLOR_TEXT))
	body.add_child(_make_label("Khu vuon uom va dao noi dang hoat dong trong pham vi MVP hien tai.", 15, Color(0.30, 0.20, 0.10)))
	body.add_child(_make_label("Banh rong: %d" % int(_state["inventory"].get("dragon_treat", 0)), 16, COLOR_TEXT))


func _build_left_navigation(active: String) -> void:
	var nav := VBoxContainer.new()
	nav.position = Vector2(16, 115)
	nav.size = Vector2(205, 480)
	nav.add_theme_constant_override("separation", 7)
	_ui_root.add_child(nav)
	for entry in [
		{"id": "field", "label": "Ruong", "action": "go_field"},
		{"id": "shop", "label": "Shop", "action": "open_shop"},
		{"id": "storage", "label": "Kho", "action": "open_inventory"},
		{"id": "animal", "label": "Vat nuoi", "action": "go_animal_inside"},
		{"id": "dragon", "label": "Dao Rong", "action": "open_island"},
		{"id": "quest", "label": "Nhiem vu", "action": "open_event"},
		{"id": "settings", "label": "Cai dat", "action": "open_settings"},
	]:
		var button := _make_button(entry["label"], entry["id"] == active, Vector2(205, 52))
		button.icon = UIAssetRegistry.home_nav(entry["id"])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 42)
		button.pressed.connect(_handle_action.bind(entry["action"]))
		nav.add_child(button)
	var hub := _make_button("Ve trang trai", false, Vector2(205, 44))
	if active == "hub":
		hub.text = "Tep luu"
		hub.pressed.connect(_handle_action.bind("open_save"))
	elif active == "settings":
		hub.text = "Quay lai"
		hub.pressed.connect(_handle_action.bind("settings_back"))
	else:
		hub.pressed.connect(_handle_action.bind("go_hub"))
	nav.add_child(hub)


func _build_runtime_settings(content: VBoxContainer) -> void:
	for setting in [
		{"key": "master_volume", "label": "Am luong tong"},
		{"key": "music_volume", "label": "Nhac nen"},
		{"key": "sfx_volume", "label": "Hieu ung"},
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		content.add_child(row)
		var label := _make_label(setting["label"], 18, COLOR_TEXT)
		label.custom_minimum_size = Vector2(210, 40)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.value = float(_state.get(setting["key"], 80))
		slider.custom_minimum_size = Vector2(480, 40)
		slider.value_changed.connect(_set_volume_setting.bind(setting["key"]))
		row.add_child(slider)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Toan man hinh"
	fullscreen.button_pressed = bool(_state.get("fullscreen", false))
	fullscreen.add_theme_font_size_override("font_size", 18)
	fullscreen.toggled.connect(_set_fullscreen)
	content.add_child(fullscreen)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var apply_button := _make_button("Ap dung", true, Vector2(170, 44))
	apply_button.pressed.connect(_apply_settings)
	actions.add_child(apply_button)
	var reset_button := _make_button("Dat lai", false, Vector2(170, 44))
	reset_button.pressed.connect(_reset_settings)
	actions.add_child(reset_button)
	var back_button := _make_button("Quay lai", false, Vector2(170, 44))
	back_button.pressed.connect(_handle_action.bind("settings_back"))
	actions.add_child(back_button)
	content.add_child(_make_label("Do phan giai thiet ke: 1280 x 720", 18, COLOR_TEXT))
	content.add_child(_make_label("V2 runtime • text va so lieu do engine hien thi", 15, Color(0.36, 0.25, 0.14)))


func _set_volume_setting(value: float, key: String) -> void:
	_state[key] = value
	_apply_audio_bus(key, value)


func _set_fullscreen(enabled: bool) -> void:
	_state["fullscreen"] = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _apply_audio_bus(key: String, value: float) -> void:
	var bus_name: String = {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX"}.get(key, "")
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	AudioServer.set_bus_mute(bus_index, value <= 0.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value / 100.0, 0.001)))


func _apply_audio_settings() -> void:
	_ensure_audio_buses()
	_apply_audio_bus("master_volume", float(_state.get("master_volume", 80.0)))
	_apply_audio_bus("music_volume", float(_state.get("music_volume", 70.0)))
	_apply_audio_bus("sfx_volume", float(_state.get("sfx_volume", 85.0)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_state.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_settings() -> void:
	_apply_audio_settings()
	_settings_snapshot = {
		"master_volume": _state.get("master_volume", 80.0),
		"music_volume": _state.get("music_volume", 70.0),
		"sfx_volume": _state.get("sfx_volume", 85.0),
		"fullscreen": _state.get("fullscreen", false),
	}
	_set_status("Da ap dung cai dat.")
	_save_game()
	_render()


func _reset_settings() -> void:
	_state["master_volume"] = 80.0
	_state["music_volume"] = 70.0
	_state["sfx_volume"] = 85.0
	_state["fullscreen"] = false
	_apply_audio_settings()
	_apply_settings()


func _cancel_settings_changes() -> void:
	if not _settings_snapshot.is_empty():
		for key in _settings_snapshot:
			_state[key] = _settings_snapshot[key]
		_apply_audio_settings()


func _render_farmer(pos: Vector2, visual_scale: float) -> void:
	var farmer := AnimatedSprite2D.new()
	farmer.name = "CanonicalFarmer"
	farmer.sprite_frames = UIAssetRegistry.farmer_frames(_farmer_action)
	farmer.animation = _farmer_action
	farmer.position = pos
	farmer.scale = Vector2.ONE * visual_scale
	farmer.centered = true
	_ui_root.add_child(farmer)
	if _farmer_action not in ["idle", "walk"]:
		farmer.animation_finished.connect(_reset_farmer_to_idle.bind(farmer))
	farmer.play()


func _reset_farmer_to_idle(farmer: AnimatedSprite2D) -> void:
	_farmer_action = "idle"
	if not is_instance_valid(farmer):
		return
	farmer.sprite_frames = UIAssetRegistry.farmer_frames("idle")
	farmer.animation = "idle"
	farmer.play()


func _render_animal_world_status(animal: Dictionary) -> void:
	var chicken := TextureRect.new()
	chicken.name = "AnimalSprite"
	chicken.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chicken.texture = UIAssetRegistry.animal_base()
	chicken.position = Vector2(480, 305)
	chicken.size = Vector2(200, 235)
	chicken.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui_root.add_child(chicken)
	var status_kind := "egg_ready" if int(animal["eggs_ready"]) > 0 else ("hungry" if int(animal["fullness"]) < 40 else "happy_cared_heart")
	var status := TextureRect.new()
	status.name = "AnimalStatusOverlay"
	status.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status.texture = UIAssetRegistry.animal_overlay(status_kind)
	status.position = Vector2(515, 190)
	status.size = Vector2(128, 128)
	status.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui_root.add_child(status)
	var bars := VBoxContainer.new()
	bars.position = Vector2(690, 330)
	bars.size = Vector2(180, 145)
	_ui_root.add_child(bars)
	for entry in [
		{"value": animal["fullness"], "texture": "fullness"},
		{"value": animal["cleanliness"], "texture": "cleanliness"},
		{"value": animal["happiness"], "texture": "bond_happiness"},
		{"value": mini(100, int(animal["eggs_ready"]) * 34), "texture": "product_readiness"},
	]:
		var bar := TextureProgressBar.new()
		bar.name = "Animal_%s" % entry["texture"]
		bar.nine_patch_stretch = true
		bar.custom_minimum_size = Vector2(180, 34)
		bar.min_value = 0
		bar.max_value = 100
		bar.value = int(entry["value"])
		bar.texture_progress = UIAssetRegistry.animal_bar(entry["texture"])
		bar.tint_under = Color(0.2, 0.15, 0.1, 0.35)
		bars.add_child(bar)


func _render_overlay() -> void:
	var dim := ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(dim)

	var modal := _create_panel(Rect2(150, 74, 980, 572), Color(0.19, 0.12, 0.07, 0.96), COLOR_GOLD, 30)
	_ui_root.add_child(modal)
	var content := _panel_body(modal, 12)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	content.add_child(top_row)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(heading)

	var close_button := _make_button("Dong", false, Vector2(120, 42))
	close_button.pressed.connect(_close_overlay)
	top_row.add_child(close_button)

	match _current_overlay:
		"inventory":
			heading.add_child(_make_label("Kho vat pham", 28, COLOR_CREAM))
			heading.add_child(_make_label("Danh sach vat pham va hat giong hien dang co trong save.", 16, COLOR_SOFT))
			_build_inventory_overlay(content)
		"shop":
			heading.add_child(_make_label("Shop", 28, COLOR_CREAM))
			heading.add_child(_make_label("Mua them hat giong va do cham soc de tiep tuc nong trai.", 16, COLOR_SOFT))
			_build_shop_overlay(content)
		"pet":
			heading.add_child(_make_label("Pet va dong hanh", 28, COLOR_CREAM))
			heading.add_child(_make_label("Cac pet dang dong hanh trong vertical slice nong trai.", 16, COLOR_SOFT))
			_build_pet_overlay(content)
		"island":
			heading.add_child(_make_label("Ban do dao", 28, COLOR_CREAM))
			heading.add_child(_make_label("Teaser map mo rong cho nhung khu sau.", 16, COLOR_SOFT))
			_build_island_overlay(content)
		"event":
			heading.add_child(_make_label("Su kien", 28, COLOR_CREAM))
			heading.add_child(_make_label("Nhiem vu nho de khuyen khich nguoi choi thu loop farm.", 16, COLOR_SOFT))
			_build_event_overlay(content)
		"reward":
			heading.add_child(_make_label("Reward", 28, COLOR_CREAM))
			heading.add_child(_make_label("Qua vua nhan duoc tu thu hoach, trung ga hoac event.", 16, COLOR_SOFT))
			_build_reward_overlay(content)
		"house":
			heading.add_child(_make_label("Nha va save", 28, COLOR_CREAM))
			heading.add_child(_make_label("Thong tin save hien tai va nut di nhanh.", 16, COLOR_SOFT))
			_build_house_overlay(content)
		"craft":
			heading.add_child(_make_label("Craft", 28, COLOR_CREAM))
			heading.add_child(_make_label("Cong thuc nho phuc vu pet va vong lap nong trai.", 16, COLOR_SOFT))
			_build_craft_overlay(content)
		"settings":
			heading.add_child(_make_label("Cai dat", 28, COLOR_CREAM))
			heading.add_child(_make_label("Thong tin runtime hien tai cua project.", 16, COLOR_SOFT))
			_build_settings_overlay(content)
		_:
			heading.add_child(_make_label("Overlay", 28, COLOR_CREAM))
			heading.add_child(_make_label("Khong co noi dung.", 16, COLOR_SOFT))


func _build_inventory_overlay(content: VBoxContainer) -> void:
	var primary := COLOR_TEXT if _current_screen == SCREEN_STORAGE else COLOR_CREAM
	var secondary := Color(0.38, 0.25, 0.12) if _current_screen == SCREEN_STORAGE else COLOR_SOFT
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	for entry in FarmData.INVENTORY_CATALOG:
		var amount := int(_state["inventory"].get(entry["id"], 0))
		if amount <= 0:
			continue
		var card := _create_panel(Rect2(0, 0, 214, 118), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		grid.add_child(card)
		var box := _panel_body(card, 6)
		box.add_child(_make_media_preview(UIAssetRegistry.get_item_texture(entry["id"]), Vector2(182, 62), Color(0.97, 0.92, 0.82, 0.08)))
		box.add_child(_make_label(entry["label"], 18, primary))
		box.add_child(_make_label(entry["group"], 14, Color(0.99, 0.90, 0.62, 1.0)))
		box.add_child(_make_label("So luong: %d" % amount, 16, secondary))


func _build_shop_overlay(content: VBoxContainer) -> void:
	var primary := COLOR_TEXT if _current_screen == SCREEN_SHOP else COLOR_CREAM
	var secondary := Color(0.38, 0.25, 0.12) if _current_screen == SCREEN_SHOP else COLOR_SOFT
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for item in FarmData.SHOP_ITEMS:
		var row := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(row)
		var row_box := _panel_body(row, 8)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		row_box.add_child(top)

		top.add_child(_make_media_preview(UIAssetRegistry.get_item_texture(item["id"]), Vector2(132, 86), Color(0.97, 0.92, 0.82, 0.08)))

		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(text_box)
		text_box.add_child(_make_label(item["label"], 20, primary))
		text_box.add_child(_make_label("%s | +%d mon" % [item["group"], int(item["amount"])], 14, secondary))

		var buy_button := _make_button("Mua %d" % int(item["price"]), true, Vector2(140, 40))
		buy_button.pressed.connect(_buy_shop_item.bind(item["id"]))
		top.add_child(buy_button)

	content.add_child(_make_label("Tien hien tai: %d" % int(_state["coins"]), 16, Color(0.99, 0.90, 0.62, 1.0)))


func _build_pet_overlay(content: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for pet in FarmData.PETS:
		var card := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(card)
		var box := _panel_body(card, 6)
		box.add_child(_make_media_preview(UIAssetRegistry.get_pet_texture(pet["name"]), Vector2(914, 120), Color(0.97, 0.92, 0.82, 0.08)))
		box.add_child(_make_label(pet["name"], 20, COLOR_CREAM))
		box.add_child(_make_label("Level %d | %s" % [int(pet["level"]), pet["mood"]], 15, Color(0.99, 0.90, 0.62, 1.0)))
		box.add_child(_make_label(pet["role"], 15, COLOR_SOFT))


func _build_island_overlay(content: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for island in FarmData.ISLANDS:
		var row := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(row)
		var box := _panel_body(row, 6)
		box.add_child(_make_label(island["name"], 20, COLOR_CREAM))
		box.add_child(_make_label(island["state"], 15, Color(0.99, 0.90, 0.62, 1.0)))
		box.add_child(_make_label(island["desc"], 15, COLOR_SOFT))


func _build_event_overlay(content: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for task in FarmData.EVENT_TASKS:
		var progress := int(_state["event_progress"].get(task["id"], 0))
		var done := progress >= int(task["target"])
		var row := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(row)
		var box := _panel_body(row, 6)
		box.add_child(_make_label(task["label"], 20, COLOR_CREAM))
		box.add_child(_make_label("Tien do: %d / %d" % [progress, int(task["target"])], 15, COLOR_SOFT))
		box.add_child(_make_chip("Hoan thanh" if done else "Dang lam", COLOR_GREEN if done else COLOR_BLUE))

	var claim_button := _make_button("Nhan thuong event", true, Vector2(240, 44))
	claim_button.disabled = not _event_completed()
	claim_button.pressed.connect(_claim_event_reward)
	content.add_child(claim_button)


func _build_reward_overlay(content: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for reward in _state["last_rewards"]:
		var row := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(row)
		var box := _panel_body(row, 6)
		box.add_child(_make_media_preview(UIAssetRegistry.get_item_texture(_reward_to_item_id(reward["label"])), Vector2(320, 82), Color(0.97, 0.92, 0.82, 0.08)))
		box.add_child(_make_label(reward["label"], 20, COLOR_CREAM))
		box.add_child(_make_label(reward["value"], 18, Color(0.99, 0.90, 0.62, 1.0)))

	var button := _make_button("Nhan va dong", true, Vector2(200, 44))
	button.pressed.connect(_claim_reward_popup)
	content.add_child(button)


func _build_house_overlay(content: VBoxContainer) -> void:
	var slot_id := int(_state.get("selected_slot", 1))
	content.add_child(_make_label("Save: Slot %d" % slot_id, 22, COLOR_CREAM))
	content.add_child(_make_label("Ngay %d | Tien %d | Nang luong %d" % [int(_state["day"]), int(_state["coins"]), int(_state["energy"])], 16, COLOR_SOFT))
	content.add_child(_make_label("Flow hien tai: Hub -> Ruong / Chuong -> Overlay rieng", 15, COLOR_SOFT))
	content.add_child(_make_label("Don da giao: %d" % int(_state["orders_done"]), 15, COLOR_SOFT))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	for entry in [
		{"label": "Kho", "action": "open_inventory"},
		{"label": "Shop", "action": "open_shop"},
		{"label": "Ban do", "action": "open_island"},
	]:
		var button := _make_button(entry["label"], false, Vector2(120, 40))
		button.pressed.connect(_handle_action.bind(entry["action"]))
		row.add_child(button)


func _build_craft_overlay(content: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	content.add_child(list)

	for recipe in FarmData.CRAFT_RECIPES:
		var row := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 18)
		list.add_child(row)
		var box := _panel_body(row, 6)
		box.add_child(_make_media_preview(UIAssetRegistry.get_item_texture("dragon_treat"), Vector2(420, 92), Color(0.97, 0.92, 0.82, 0.08)))
		box.add_child(_make_label(recipe["name"], 20, COLOR_CREAM))
		box.add_child(_make_label("Can: %s" % recipe["need"], 15, Color(0.99, 0.90, 0.62, 1.0)))
		box.add_child(_make_label("Nhan: %s" % recipe["reward"], 15, COLOR_SOFT))
		box.add_child(_make_label(recipe["note"], 14, COLOR_SOFT))

	var button := _make_button("Craft Banh Rong", true, Vector2(220, 44))
	button.pressed.connect(_craft_dragon_treat)
	content.add_child(button)


func _build_settings_overlay(content: VBoxContainer) -> void:
	for item in FarmData.SETTINGS_ITEMS:
		content.add_child(_make_label("%s: %s" % [item["label"], item["value"]], 18, COLOR_SOFT))


func _build_top_hud(title: String, subtitle: String) -> void:
	var panel := Panel.new()
	panel.position = Vector2(16, 14)
	panel.size = Vector2(1248, 70)
	panel.add_theme_stylebox_override("panel", _stylebox(Color(0.17, 0.26, 0.46, 0.78), COLOR_BLUE_LIGHT, 26))
	_ui_root.add_child(panel)
	var title_label := _make_label(title, 23, COLOR_CREAM)
	title_label.position = Vector2(18, 8)
	title_label.size = Vector2(560, 30)
	panel.add_child(title_label)
	var subtitle_label := _make_label(subtitle, 13, Color(0.92, 0.97, 1.0, 0.95))
	subtitle_label.position = Vector2(18, 39)
	subtitle_label.size = Vector2(690, 24)
	panel.add_child(subtitle_label)
	var values := [
		{"label": "Ngay", "value": str(_state["day"])},
		{"label": "Tien", "value": str(_state["coins"])},
		{"label": "Nang luong", "value": str(_state["energy"])},
	]
	for i in range(values.size()):
		var chip := Panel.new()
		chip.position = Vector2(810 + i * 135, 8)
		chip.size = Vector2(126, 54)
		chip.add_theme_stylebox_override("panel", _stylebox(Color(0.98, 0.93, 0.82, 0.16), Color(1, 1, 1, 0.12), 16))
		panel.add_child(chip)
		var text := _make_label("%s\n%s" % [values[i]["label"], values[i]["value"]], 13, COLOR_CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		text.position = Vector2(4, 5)
		text.size = Vector2(118, 45)
		chip.add_child(text)


func _build_world_badges() -> void:
	var labels := [
		{"text": "Nha", "pos": Vector2(250, 96)},
		{"text": "Chuong", "pos": Vector2(444, 78)},
		{"text": "Ruong", "pos": Vector2(818, 134)},
		{"text": "Kho", "pos": Vector2(1030, 450)},
	]
	for entry in labels:
		var chip := _make_chip(entry["text"], Color(0.05, 0.06, 0.08, 0.88))
		chip.position = entry["pos"]
		_ui_root.add_child(chip)


func _build_order_board() -> void:
	var active_order := _get_active_order()
	var panel := _create_panel(Rect2(845, 214, 392, 242), Color(0.19, 0.12, 0.07, 0.90), COLOR_GOLD, 28)
	_ui_root.add_child(panel)
	var box := _panel_body(panel, 8)
	box.add_child(_make_label("Bang don hom nay", 23, COLOR_CREAM))
	box.add_child(_make_label(active_order["title"], 18, Color(0.99, 0.90, 0.62, 1.0)))
	box.add_child(_make_media_preview(UIAssetRegistry.get_order_texture(active_order["need_item"]), Vector2(344, 98), Color(0.97, 0.92, 0.82, 0.08)))
	box.add_child(_make_label(active_order["desc"], 14, COLOR_SOFT))
	box.add_child(_make_label("Can: %d %s" % [int(active_order["need_amount"]), FarmData.get_inventory_name(active_order["need_item"])], 14, COLOR_SOFT))
	box.add_child(_make_label("Thuong: %d tien + %d %s" % [int(active_order["reward_coins"]), int(active_order["reward_amount"]), FarmData.get_inventory_name(active_order["reward_item"])], 14, COLOR_SOFT))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var deliver_button := _make_button("Giao hang", true, Vector2(160, 40))
	deliver_button.disabled = not _can_fulfill_active_order()
	deliver_button.pressed.connect(_deliver_active_order)
	row.add_child(deliver_button)

	var goto_field := _make_button("Ra ruong", false, Vector2(140, 40))
	goto_field.pressed.connect(_handle_action.bind("go_field"))
	row.add_child(goto_field)


func _build_hub_hotspots() -> void:
	for hotspot in FarmData.HUB_HOTSPOTS:
		var button := _make_hotspot(hotspot["rect"], hotspot["label"], hotspot["action"])
		_ui_root.add_child(button)


func _build_status_card(pos: Vector2, size: Vector2) -> void:
	var panel := _create_panel(Rect2(pos.x, pos.y, size.x, size.y), COLOR_BLUE, COLOR_BLUE_LIGHT, 28)
	_ui_root.add_child(panel)
	var box := _panel_body(panel, 4)
	box.add_child(_make_label("Ngay %d" % int(_state["day"]), 18, COLOR_CREAM))
	box.add_child(_make_label("Tien %d" % int(_state["coins"]), 18, COLOR_CREAM))
	box.add_child(_make_label("Nang luong %d" % int(_state["energy"]), 16, Color(0.96, 0.99, 1.0, 0.96)))
	box.add_child(_make_label(_state["status_text"], 13, Color(0.96, 0.99, 1.0, 0.96)))


func _build_action_bar(entries: Array) -> void:
	var panel := _create_panel(Rect2(306, 596, 948, 100), Color(0.18, 0.46, 0.85, 0.84), COLOR_BLUE_LIGHT, 36)
	_ui_root.add_child(panel)
	var body := _panel_body(panel, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)

	for entry in entries:
		var button := _make_button(entry["label"], false, Vector2(104, 52))
		button.pressed.connect(_handle_action.bind(entry["action"]))
		row.add_child(button)


func _build_field_action_bar() -> void:
	var seed_row := HBoxContainer.new()
	seed_row.position = Vector2(394, 94)
	seed_row.size = Vector2(420, 92)
	seed_row.add_theme_constant_override("separation", 12)
	_ui_root.add_child(seed_row)
	for crop_id in ["carrot", "tomato", "pumpkin"]:
		var seed := TextureButton.new()
		seed.custom_minimum_size = Vector2(92, 92)
		seed.ignore_texture_size = true
		seed.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		seed.texture_normal = UIAssetRegistry.seed_card(crop_id, crop_id == _state["selected_seed"])
		seed.texture_hover = UIAssetRegistry.seed_card(crop_id, true)
		seed.tooltip_text = "%s (%d)" % [FarmData.get_crop_label(crop_id), int(_state["inventory"].get(FarmData.CROP_DEFINITIONS[crop_id]["seed_item"], 0))]
		seed.pressed.connect(_select_seed.bind(crop_id))
		seed_row.add_child(seed)

	var panel := _create_panel(Rect2(300, 590, 955, 110), Color(0.98, 0.93, 0.82, 0.88), Color(0.45, 0.25, 0.10, 0.90), 24)
	_ui_root.add_child(panel)
	var body := _panel_body(panel, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	body.add_child(row)
	for entry in [
		{"id": "hoe", "label": "Cay", "action": "field_till", "kind": "till"},
		{"id": "plant", "label": "Gieo", "action": "field_seed", "kind": "seed"},
		{"id": "water", "label": "Tuoi", "action": "field_water", "kind": "water"},
		{"id": "fertilize", "label": "Bon", "action": "field_fertilize", "kind": "fertilize"},
		{"id": "harvest", "label": "Thu", "action": "field_harvest", "kind": "harvest"},
	]:
		var allowed := _field_action_allowed(entry["kind"])
		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(132, 70)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.texture_normal = UIAssetRegistry.action_button(entry["id"], "default")
		button.texture_hover = UIAssetRegistry.action_button(entry["id"], "hover")
		button.texture_pressed = UIAssetRegistry.action_button(entry["id"], "pressed")
		button.texture_disabled = UIAssetRegistry.action_button(entry["id"], "disabled")
		button.disabled = not allowed
		button.tooltip_text = entry["label"]
		button.pressed.connect(_handle_action.bind(entry["action"]))
		if not allowed:
			var badge := TextureRect.new()
			badge.texture = UIAssetRegistry.feedback_badge("no_energy" if not _has_energy_for(entry["kind"]) else "unavailable")
			badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			badge.position = Vector2(96, 2)
			badge.size = Vector2(32, 32)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(badge)
		var caption := _make_label(entry["label"], 14, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		caption.position = Vector2(6, 48)
		caption.size = Vector2(120, 20)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		row.add_child(button)
	for entry in [{"label": "Ngay moi", "action": "advance_day"}, {"label": "Ve nha", "action": "go_hub"}]:
		var button := _make_button(entry["label"], false, Vector2(110, 70))
		button.pressed.connect(_handle_action.bind(entry["action"]))
		row.add_child(button)


func _select_seed(crop_id: String) -> void:
	_state["selected_seed"] = crop_id
	_set_status("Da chon hat %s." % FarmData.get_crop_label(crop_id))
	_render()


func _field_action_allowed(kind: String) -> bool:
	var plot := _get_selected_plot()
	if plot.is_empty():
		return false
	match kind:
		"till": return not bool(plot["is_hoed"]) and _has_energy_for("till")
		"seed": return bool(plot["is_hoed"]) and String(plot["crop"]).is_empty() and _has_energy_for("seed")
		"water": return bool(plot["is_hoed"]) and not bool(plot["watered_today"]) and _has_energy_for("water")
		"fertilize": return bool(plot["is_hoed"]) and not bool(plot["fertilizer_pending"]) and _has_energy_for("fertilize")
		"harvest": return bool(plot["ready_to_harvest"]) and _has_energy_for("harvest")
	return false


func _plot_has_available_action(plot: Dictionary) -> bool:
	if not bool(plot["is_hoed"]):
		return _has_energy_for("till")
	if bool(plot["ready_to_harvest"]):
		return _has_energy_for("harvest")
	if String(plot["crop"]).is_empty():
		var crop_id: String = _state["selected_seed"]
		var seed_item: String = FarmData.CROP_DEFINITIONS[crop_id]["seed_item"]
		return (_has_energy_for("seed") and int(_state["inventory"].get(seed_item, 0)) > 0) or _has_energy_for("water") or _has_energy_for("fertilize")
	return (not bool(plot["watered_today"]) and _has_energy_for("water")) or (not bool(plot["fertilizer_pending"]) and _has_energy_for("fertilize"))


func _add_plot_view(plot: Dictionary) -> void:
	var top_left: Vector2 = plot["position"]
	var holder := Control.new()
	holder.name = "Plot_%02d" % int(plot["id"])
	holder.position = top_left
	holder.size = Vector2(115, 80)
	_ui_root.add_child(holder)

	var base_kind := "unhoed"
	if bool(plot["is_hoed"]):
		base_kind = "watered" if bool(plot["watered_today"]) else "dry"
	_add_plot_layer(holder, "BaseSoil", UIAssetRegistry.plot_texture(base_kind), Rect2(0, 0, 115, 80))

	var state_texture: Texture2D
	if bool(plot["fertilizer_pending"]):
		state_texture = UIAssetRegistry.plot_texture("fertilized_watered" if bool(plot["watered_today"]) else "fertilized_dry")
	elif bool(plot["watered_today"]) and not String(plot["crop"]).is_empty():
		state_texture = UIAssetRegistry.crop_overlay("watered")
	_add_plot_layer(holder, "StateOverlay", state_texture, Rect2(0, 0, 115, 80))

	if not String(plot["crop"]).is_empty():
		var crop := TextureRect.new()
		crop.name = "CropSprite"
		crop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crop.texture = UIAssetRegistry.world_crop(String(plot["crop"]), int(plot["growth_stage"]))
		crop.position = Vector2(8, -44)
		crop.size = Vector2(99, 112)
		crop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(crop)
	else:
		_add_plot_layer(holder, "CropSprite", null, Rect2(0, 0, 115, 80))

	_add_plot_layer(holder, "ReadyOverlay", UIAssetRegistry.crop_overlay("ready") if bool(plot["ready_to_harvest"]) else null, Rect2(0, -18, 115, 98))
	var feedback_texture: Texture2D
	if int(plot["id"]) == int(_state["selected_plot"]):
		feedback_texture = UIAssetRegistry.plot_texture("valid" if _plot_has_available_action(plot) else "invalid")
	_add_plot_layer(holder, "ActionFeedbackOverlay", feedback_texture, Rect2(0, 0, 115, 80))
	var selection := _add_plot_layer(holder, "SelectionOverlay", UIAssetRegistry.plot_texture("selected") if int(plot["id"]) == int(_state["selected_plot"]) else null, Rect2(0, 0, 115, 80))

	var button := Button.new()
	button.name = "ClickArea"
	button.position = Vector2.ZERO
	button.size = Vector2(115, 80)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_select_plot.bind(int(plot["id"])))
	button.mouse_entered.connect(_set_plot_hover.bind(selection, true, int(plot["id"])))
	button.mouse_exited.connect(_set_plot_hover.bind(selection, false, int(plot["id"])))
	holder.add_child(button)


func _add_plot_layer(parent: Control, layer_name: String, texture: Texture2D, rect: Rect2) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = layer_name
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.texture = texture
	layer.position = rect.position
	layer.size = rect.size
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer


func _set_plot_hover(layer: TextureRect, hovered: bool, plot_id: int) -> void:
	if not is_instance_valid(layer):
		return
	if hovered:
		layer.texture = UIAssetRegistry.plot_texture("hover")
	else:
		layer.texture = UIAssetRegistry.plot_texture("selected") if plot_id == int(_state["selected_plot"]) else null


func _make_hotspot(rect: Rect2, label: String, action: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _stylebox(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.08), 16))
	button.add_theme_stylebox_override("hover", _stylebox(Color(0.95, 0.84, 0.47, 0.12), COLOR_GOLD, 16))
	button.add_theme_stylebox_override("pressed", _stylebox(Color(0.95, 0.84, 0.47, 0.20), COLOR_GOLD, 16))
	button.pressed.connect(_handle_action.bind(action))
	button.mouse_entered.connect(_set_status.bind("Dang nham vao %s." % label))
	return button


func _add_background(path: String) -> void:
	_add_background_texture(load(path) as Texture2D)


func _add_environment_layers(screen: String) -> void:
	for texture in UIAssetRegistry.environment_layers(screen):
		_add_background_texture(texture)


func _add_background_texture(texture: Texture2D) -> void:
	var bg := TextureRect.new()
	bg.texture = texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(bg)


func _create_panel(rect: Rect2, bg_color: Color, border_color: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.add_theme_stylebox_override("panel", _stylebox(bg_color, border_color, radius))
	return panel


func _panel_body(panel: PanelContainer, spacing: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", spacing)
	margin.add_child(box)
	return box


func _stylebox(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_label(text: String, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(label: String, accent: bool, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	if accent:
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_stylebox_override("normal", _stylebox(Color(0.98, 0.86, 0.45, 0.98), Color(1, 0.98, 0.88, 1.0), 18))
		button.add_theme_stylebox_override("hover", _stylebox(Color(1.0, 0.90, 0.55, 1.0), Color(1, 0.98, 0.88, 1.0), 18))
		button.add_theme_stylebox_override("pressed", _stylebox(Color(0.92, 0.78, 0.30, 1.0), Color(1, 0.98, 0.88, 1.0), 18))
		button.add_theme_stylebox_override("disabled", _stylebox(Color(0.45, 0.42, 0.35, 0.75), Color(0.60, 0.56, 0.50, 0.75), 18))
	else:
		button.add_theme_color_override("font_color", COLOR_CREAM)
		button.add_theme_stylebox_override("normal", _stylebox(Color(0.17, 0.39, 0.76, 0.88), COLOR_BLUE_LIGHT, 18))
		button.add_theme_stylebox_override("hover", _stylebox(Color(0.23, 0.49, 0.90, 0.95), Color(0.92, 0.98, 1.0, 0.95), 18))
		button.add_theme_stylebox_override("pressed", _stylebox(Color(0.14, 0.28, 0.62, 0.98), Color(0.92, 0.98, 1.0, 0.95), 18))
		button.add_theme_stylebox_override("disabled", _stylebox(Color(0.16, 0.20, 0.26, 0.75), Color(0.35, 0.40, 0.48, 0.75), 18))
	return button


func _make_chip(text: String, color: Color) -> PanelContainer:
	var chip := _create_panel(Rect2(0, 0, 0, 0), color, Color(1, 1, 1, 0.12), 16)
	var body := _panel_body(chip, 0)
	body.add_child(_make_label(text, 14, Color(1, 1, 1, 0.98), HORIZONTAL_ALIGNMENT_CENTER))
	return chip


func _make_small_stat(label: String, value: String) -> PanelContainer:
	var stat := _create_panel(Rect2(0, 0, 0, 0), Color(0.98, 0.93, 0.82, 0.10), Color(0.98, 0.93, 0.82, 0.14), 16)
	var box := _panel_body(stat, 0)
	box.add_child(_make_label(label, 12, Color(0.99, 0.90, 0.62, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_make_label(value, 16, COLOR_CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	return stat


func _make_media_preview(texture: Texture2D, size: Vector2, bg_color: Color) -> PanelContainer:
	var panel := _create_panel(Rect2(0, 0, size.x, size.y), bg_color, Color(1, 1, 1, 0.10), 18)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	if texture == null:
		var fallback := _make_label("Dang cap nhat art", 14, COLOR_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		margin.add_child(fallback)
		return panel

	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = texture
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = size - Vector2(16, 16)
	margin.add_child(image)
	return panel


func _make_stat_bar(label: String, value: int, fill_color: Color) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.add_child(_make_label("%s: %d" % [label, value], 16, COLOR_SOFT))

	var base := PanelContainer.new()
	base.custom_minimum_size = Vector2(0, 18)
	base.add_theme_stylebox_override("panel", _stylebox(Color(0.08, 0.08, 0.08, 0.35), Color(1, 1, 1, 0.06), 8))
	wrap.add_child(base)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(clampf(float(value) / 100.0, 0.0, 1.0) * 296.0, 14)
	base.add_child(fill)
	return wrap


func _make_spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _handle_action(action: String) -> void:
	match action:
		"go_title":
			_current_overlay = ""
			_current_screen = SCREEN_TITLE
		"open_save":
			_current_overlay = ""
			_save_mode = "load"
			_slot_confirmation = ""
			_current_screen = SCREEN_SAVE
		"open_new_game":
			_current_overlay = ""
			_save_mode = "new"
			_slot_confirmation = ""
			_current_screen = SCREEN_SAVE
		"continue_game":
			_current_overlay = ""
			var latest_slot := _save_service.get_latest_valid_slot()
			if latest_slot == 0:
				_save_mode = "load"
				_current_screen = SCREEN_SAVE
				_set_status("Chua co save hop le de tiep tuc.")
			else:
				_load_slot(latest_slot)
		"quit_game":
			get_tree().quit()
		"go_hub":
			_current_overlay = ""
			_current_screen = SCREEN_HUB
			_set_status("Da quay ve hub nong trai.")
		"go_field":
			_current_overlay = ""
			_current_screen = SCREEN_FIELD
			_set_status("Da vao man ruong.")
		"go_animal_entry":
			_current_overlay = ""
			_current_screen = SCREEN_ANIMAL_INSIDE
			_set_status("Da vao khu chuong.")
		"go_animal_inside":
			_current_overlay = ""
			_current_screen = SCREEN_ANIMAL_INSIDE
			_set_status("Da vao ben trong chuong.")
		"open_inventory":
			_current_overlay = ""
			_current_screen = SCREEN_STORAGE
			_set_status("Mo kho vat pham.")
		"open_shop":
			_current_overlay = ""
			_current_screen = SCREEN_SHOP
			_set_status("Mo shop.")
		"open_pet":
			_current_overlay = "pet"
			_set_status("Mo danh sach pet.")
		"open_island":
			_current_overlay = ""
			_current_screen = SCREEN_DRAGON
			_set_status("Mo ban do dao.")
		"open_event":
			_current_overlay = "event"
			_set_status("Mo event.")
		"open_reward":
			_current_overlay = "reward"
			_set_status("Mo reward.")
		"open_house":
			_current_overlay = "house"
			_set_status("Mo thong tin nha va save.")
		"open_craft":
			_current_overlay = "craft"
			_set_status("Mo khu craft.")
		"open_settings":
			_current_overlay = ""
			if _current_screen != SCREEN_SETTINGS:
				_settings_return_screen = _current_screen
			_settings_snapshot = {
				"master_volume": _state.get("master_volume", 80.0),
				"music_volume": _state.get("music_volume", 70.0),
				"sfx_volume": _state.get("sfx_volume", 85.0),
				"fullscreen": _state.get("fullscreen", false),
			}
			_current_screen = SCREEN_SETTINGS
			_set_status("Mo cai dat.")
		"settings_back":
			_cancel_settings_changes()
			_current_screen = _settings_return_screen
			_set_status("Da quay lai.")
		"cycle_seed":
			_cycle_seed()
		"field_till":
			_apply_field_action("till")
		"field_seed":
			_apply_field_action("seed")
		"field_water":
			_apply_field_action("water")
		"field_fertilize":
			_apply_field_action("fertilize")
		"field_harvest":
			_apply_field_action("harvest")
		"advance_day":
			_advance_day()
		"feed_animals":
			_feed_animals()
		"clean_animals":
			_clean_animals()
		"pet_animals":
			_pet_animals()
		"collect_eggs":
			_collect_eggs()
	if _current_screen not in [SCREEN_TITLE, SCREEN_SAVE]:
		_save_game()
	_render()


func _select_save_slot(slot_id: int) -> void:
	_selected_save_slot = slot_id
	_slot_confirmation = ""
	_render()


func _confirm_save_slot() -> void:
	var metadata := _save_service.get_slot_metadata(_selected_save_slot)
	if _save_mode == "load":
		if not metadata["occupied"] or not metadata["valid"]:
			_set_status("Slot nay khong co save hop le.")
			_render()
			return
		_load_slot(_selected_save_slot)
		_render()
		return
	if metadata["occupied"] and _slot_confirmation != "ghi de slot %d" % _selected_save_slot:
		_slot_confirmation = "ghi de slot %d" % _selected_save_slot
		_set_status("Can xac nhan ghi de save cu.")
		_render()
		return
	_state = FarmData.create_initial_state()
	_state["selected_slot"] = _selected_save_slot
	_current_screen = SCREEN_HUB
	_current_overlay = ""
	_slot_confirmation = ""
	_set_status("Da tao tro choi moi o slot %d." % _selected_save_slot)
	_save_game()
	_render()


func _request_delete_slot() -> void:
	if _slot_confirmation != "xoa slot %d" % _selected_save_slot:
		_slot_confirmation = "xoa slot %d" % _selected_save_slot
		_set_status("Can xac nhan xoa slot.")
		_render()
		return
	var result := _save_service.delete_slot(_selected_save_slot)
	_slot_confirmation = ""
	_set_status(result["message"])
	_render()


func _save_game() -> bool:
	var slot_id := int(_state.get("selected_slot", _selected_save_slot))
	var result := _save_service.save_current_slot(slot_id, _state, _current_screen)
	if result["ok"]:
		_state = result["state"]
	else:
		_set_status(result["message"])
	return bool(result["ok"])


func _load_slot(slot_id: int) -> bool:
	var result := _save_service.load_slot(slot_id)
	if not result["ok"]:
		_set_status(result["message"])
		return false
	_state = _normalize_loaded_state(result["state"])
	_selected_save_slot = slot_id
	_state["selected_slot"] = slot_id
	_current_screen = SCREEN_HUB
	_current_overlay = ""
	_set_status("Da tai slot %d." % slot_id)
	_apply_audio_settings()
	return true


func _normalize_loaded_state(loaded: Dictionary) -> Dictionary:
	var normalized := loaded.duplicate(true)
	for i in range(normalized.get("field_plots", []).size()):
		var plot: Dictionary = normalized["field_plots"][i]
		if not plot.has("fertilizer_pending"):
			plot["fertilizer_pending"] = bool(plot.get("fertilized", false))
		plot.erase("fertilized")
		normalized["field_plots"][i] = plot
	return normalized


func _select_plot(plot_id: int) -> void:
	_state["selected_plot"] = plot_id
	_set_status("Da chon o dat %02d." % plot_id)
	_render()


func _close_overlay() -> void:
	_current_overlay = ""
	_render()


func _cycle_seed() -> void:
	var order := ["carrot", "tomato", "pumpkin"]
	var current_index := order.find(_state["selected_seed"])
	current_index = (current_index + 1) % order.size()
	_state["selected_seed"] = order[current_index]
	_set_status("Da doi hat sang %s." % FarmData.get_crop_label(_state["selected_seed"]))


func _apply_field_action(kind: String) -> void:
	var index := _get_plot_index(int(_state["selected_plot"]))
	if index == -1:
		_set_status("Chua co o dat duoc chon.")
		return

	var plot: Dictionary = _state["field_plots"][index]
	if not _has_energy_for(kind):
		_set_status("Khong du nang luong cho thao tac nay.")
		return
	var mutated := false
	match kind:
		"till":
			if not bool(plot["is_hoed"]):
				plot["is_hoed"] = true
				plot["crop"] = ""
				plot["growth_stage"] = 0
				plot["watered_today"] = false
				plot["fertilizer_pending"] = false
				plot["ready_to_harvest"] = false
				_use_energy(4)
				_add_progress("till")
				_farmer_action = "hoe"
				mutated = true
				_set_status("Da cay o %02d." % int(plot["id"]))
			else:
				_set_status("O dat nay da duoc cay.")
		"seed":
			if not bool(plot["is_hoed"]) or not String(plot["crop"]).is_empty():
				_set_status("Can cay dat truoc khi gieo.")
			else:
				var crop_id: String = _state["selected_seed"]
				var crop_data: Dictionary = FarmData.CROP_DEFINITIONS[crop_id]
				var seed_item: String = crop_data["seed_item"]
				if int(_state["inventory"].get(seed_item, 0)) <= 0:
					_set_status("Khong con %s." % FarmData.get_inventory_name(seed_item))
				else:
					_state["inventory"][seed_item] = int(_state["inventory"][seed_item]) - 1
					plot["crop"] = crop_id
					plot["growth_stage"] = 0
					plot["watered_today"] = false
					plot["fertilizer_pending"] = false
					plot["ready_to_harvest"] = false
					_use_energy(3)
					_add_progress("seed")
					_farmer_action = "plant"
					mutated = true
					_set_status("Da gieo %s vao o %02d." % [crop_data["label"], int(plot["id"])])
		"water":
			if bool(plot["is_hoed"]) and not bool(plot["watered_today"]):
				plot["watered_today"] = true
				_use_energy(2)
				_farmer_action = "water"
				mutated = true
				_set_status("Da tuoi o %02d." % int(plot["id"]))
			else:
				_set_status("O nay khong can tuoi them hom nay.")
		"fertilize":
			if bool(plot["is_hoed"]) and not bool(plot["fertilizer_pending"]):
				plot["fertilizer_pending"] = true
				_use_energy(2)
				_farmer_action = "fertilize"
				mutated = true
				_set_status("Da bon o %02d." % int(plot["id"]))
			else:
				_set_status("O nay chua cay hoac da duoc bon.")
		"harvest":
			if not bool(plot["ready_to_harvest"]):
				_set_status("Cay chua chin.")
			else:
				var harvest_crop: Dictionary = FarmData.CROP_DEFINITIONS[plot["crop"]]
				var harvest_item: String = harvest_crop["crop_item"]
				_state["inventory"][harvest_item] = int(_state["inventory"].get(harvest_item, 0)) + 1
				_state["coins"] = int(_state["coins"]) + int(harvest_crop["sell_value"])
				_state["last_rewards"] = [
					{"label": harvest_crop["label"], "value": "+1"},
					{"label": "Tien", "value": "+%d" % int(harvest_crop["sell_value"])},
				]
				plot["crop"] = ""
				plot["growth_stage"] = 0
				plot["watered_today"] = false
				plot["fertilizer_pending"] = false
				plot["ready_to_harvest"] = false
				_use_energy(3)
				_add_progress("harvest")
				_farmer_action = "harvest"
				mutated = true
				_current_overlay = "reward"
				_set_status("Da thu hoach o %02d." % int(plot["id"]))

	_state["field_plots"][index] = plot
	if mutated:
		_save_game()


func _advance_day() -> void:
	_state["day"] = int(_state["day"]) + 1
	_state["energy"] = mini(100, int(_state["energy"]) + 18)

	for i in range(_state["field_plots"].size()):
		var plot: Dictionary = _state["field_plots"][i]
		if not String(plot["crop"]).is_empty() and bool(plot["watered_today"]) and not bool(plot["ready_to_harvest"]):
			var crop: Dictionary = FarmData.CROP_DEFINITIONS[plot["crop"]]
			var growth := 1 + (1 if bool(plot["fertilizer_pending"]) else 0)
			plot["growth_stage"] = mini(int(crop["max_stage"]), int(plot["growth_stage"]) + growth)
			plot["fertilizer_pending"] = false
			plot["ready_to_harvest"] = int(plot["growth_stage"]) >= int(crop["max_stage"])
		plot["watered_today"] = false
		_state["field_plots"][i] = plot

	var animal: Dictionary = _state["animal"]
	animal["fullness"] = clampi(int(animal["fullness"]) - 8, 0, 100)
	animal["cleanliness"] = clampi(int(animal["cleanliness"]) - 6, 0, 100)
	animal["happiness"] = clampi(int(animal["happiness"]) - 2, 0, 100)
	if int(animal["fullness"]) >= 40 and int(animal["cleanliness"]) >= 35:
		animal["eggs_ready"] = mini(3, int(animal["eggs_ready"]) + 1)
	_state["animal"] = animal
	_set_status("Da sang ngay moi.")
	_save_game()


func _feed_animals() -> void:
	if not _require_energy("feed_animals"):
		return
	if int(_state["inventory"].get("animal_feed", 0)) <= 0:
		_set_status("Khong con thuc an vat nuoi.")
		return
	_state["inventory"]["animal_feed"] = int(_state["inventory"]["animal_feed"]) - 1
	var animal: Dictionary = _state["animal"]
	animal["fullness"] = clampi(int(animal["fullness"]) + 20, 0, 100)
	animal["happiness"] = clampi(int(animal["happiness"]) + 6, 0, 100)
	_state["animal"] = animal
	_use_energy(2)
	_farmer_action = "feed"
	_set_status("Da cho vat nuoi an.")
	_save_game()


func _clean_animals() -> void:
	if not _require_energy("clean_animals"):
		return
	var animal: Dictionary = _state["animal"]
	animal["cleanliness"] = clampi(int(animal["cleanliness"]) + 18, 0, 100)
	animal["happiness"] = clampi(int(animal["happiness"]) + 4, 0, 100)
	_state["animal"] = animal
	_use_energy(2)
	_farmer_action = "clean"
	_set_status("Da don dep khu chuong.")
	_save_game()


func _pet_animals() -> void:
	if not _require_energy("pet_animals"):
		return
	var animal: Dictionary = _state["animal"]
	animal["happiness"] = clampi(int(animal["happiness"]) + 12, 0, 100)
	_state["animal"] = animal
	_use_energy(1)
	_farmer_action = "pet_care"
	_set_status("Vat nuoi dang vui hon.")
	_save_game()


func _collect_eggs() -> void:
	var animal: Dictionary = _state["animal"]
	if int(animal["eggs_ready"]) <= 0:
		_set_status("Chua co trung de thu.")
		return
	animal["eggs_ready"] = int(animal["eggs_ready"]) - 1
	_state["animal"] = animal
	_state["inventory"]["egg"] = int(_state["inventory"].get("egg", 0)) + 1
	_state["coins"] = int(_state["coins"]) + 20
	_add_progress("collect")
	_state["last_rewards"] = [
		{"label": "Trung ga", "value": "+1"},
		{"label": "Tien", "value": "+20"},
	]
	_current_overlay = "reward"
	_set_status("Da thu 1 trung ga.")
	_save_game()


func _deliver_active_order() -> void:
	var active_order := _get_active_order()
	if not _can_fulfill_active_order():
		_set_status("Chua du vat pham de giao don.")
		_render()
		return

	var need_item: String = active_order["need_item"]
	var reward_item: String = active_order["reward_item"]
	_state["inventory"][need_item] = int(_state["inventory"].get(need_item, 0)) - int(active_order["need_amount"])
	_state["inventory"][reward_item] = int(_state["inventory"].get(reward_item, 0)) + int(active_order["reward_amount"])
	_state["coins"] = int(_state["coins"]) + int(active_order["reward_coins"])
	_state["orders_done"] = int(_state["orders_done"]) + 1
	_state["active_order_index"] = (int(_state["active_order_index"]) + 1) % FarmData.ORDER_DEFINITIONS.size()
	_state["last_rewards"] = [
		{"label": "Tien", "value": "+%d" % int(active_order["reward_coins"])},
		{"label": FarmData.get_inventory_name(reward_item), "value": "+%d" % int(active_order["reward_amount"])},
	]
	_current_overlay = "reward"
	_set_status("Da giao don %s." % active_order["title"])
	_save_game()
	_render()


func _buy_shop_item(item_id: String) -> void:
	for item in FarmData.SHOP_ITEMS:
		if item["id"] != item_id:
			continue
		if int(_state["coins"]) < int(item["price"]):
			_set_status("Khong du tien.")
			_render()
			return
		_state["coins"] = int(_state["coins"]) - int(item["price"])
		_state["inventory"][item_id] = int(_state["inventory"].get(item_id, 0)) + int(item["amount"])
		_set_status("Da mua %s." % item["label"])
		_save_game()
		_render()
		return


func _claim_event_reward() -> void:
	if not _event_completed():
		_set_status("Event chua xong.")
		_render()
		return
	_state["coins"] = int(_state["coins"]) + 120
	_state["inventory"]["animal_feed"] = int(_state["inventory"].get("animal_feed", 0)) + 1
	_state["inventory"]["seed_carrot"] = int(_state["inventory"].get("seed_carrot", 0)) + 2
	_state["last_rewards"] = [
		{"label": "Tien", "value": "+120"},
		{"label": "Thuc an vat nuoi", "value": "+1"},
		{"label": "Hat Ca rot", "value": "+2"},
	]
	_current_overlay = "reward"
	_set_status("Da nhan thuong event.")
	_save_game()
	_render()


func _claim_reward_popup() -> void:
	_current_overlay = ""
	_set_status("Da nhan reward.")
	_render()


func _craft_dragon_treat() -> void:
	if int(_state["inventory"].get("crop_carrot", 0)) < 2 or int(_state["inventory"].get("egg", 0)) < 1:
		_set_status("Can 2 Ca rot tuoi va 1 Trung ga.")
		_render()
		return
	_state["inventory"]["crop_carrot"] = int(_state["inventory"]["crop_carrot"]) - 2
	_state["inventory"]["egg"] = int(_state["inventory"]["egg"]) - 1
	_state["inventory"]["dragon_treat"] = int(_state["inventory"].get("dragon_treat", 0)) + 1
	_set_status("Da craft Banh Rong.")
	_save_game()
	_render()


func _unlock_more_fields() -> void:
	if int(_state["event_progress"].get("harvest", 0)) >= 1:
		var idx_11 := _get_plot_index(11)
		if idx_11 != -1 and bool(_state["field_plots"][idx_11]["locked"]):
			var plot_11: Dictionary = _state["field_plots"][idx_11]
			plot_11["locked"] = false
			plot_11["state"] = "empty"
			_state["field_plots"][idx_11] = plot_11
	if int(_state["event_progress"].get("harvest", 0)) >= 2:
		var idx_12 := _get_plot_index(12)
		if idx_12 != -1 and bool(_state["field_plots"][idx_12]["locked"]):
			var plot_12: Dictionary = _state["field_plots"][idx_12]
			plot_12["locked"] = false
			plot_12["state"] = "empty"
			_state["field_plots"][idx_12] = plot_12


func _has_energy_for(action: String) -> bool:
	return int(_state.get("energy", 0)) >= int(FarmData.ACTION_ENERGY_COSTS.get(action, 0))


func _require_energy(action: String) -> bool:
	if _has_energy_for(action):
		return true
	_set_status("Khong du nang luong cho thao tac nay.")
	return false


func _use_energy(amount: int) -> void:
	_state["energy"] = int(_state["energy"]) - amount


func _add_progress(key: String) -> void:
	_state["event_progress"][key] = int(_state["event_progress"].get(key, 0)) + 1


func _event_completed() -> bool:
	for task in FarmData.EVENT_TASKS:
		if int(_state["event_progress"].get(task["id"], 0)) < int(task["target"]):
			return false
	return true


func _set_status(text: String) -> void:
	_state["status_text"] = text


func _get_plot_index(plot_id: int) -> int:
	for i in range(_state["field_plots"].size()):
		if int(_state["field_plots"][i]["id"]) == plot_id:
			return i
	return -1


func _get_selected_plot() -> Dictionary:
	var index := _get_plot_index(int(_state["selected_plot"]))
	if index == -1:
		return {}
	return _state["field_plots"][index]


func _get_active_order() -> Dictionary:
	return FarmData.ORDER_DEFINITIONS[int(_state["active_order_index"]) % FarmData.ORDER_DEFINITIONS.size()]


func _can_fulfill_active_order() -> bool:
	var active_order := _get_active_order()
	return int(_state["inventory"].get(active_order["need_item"], 0)) >= int(active_order["need_amount"])


func _reward_to_item_id(label: String) -> String:
	match label:
		"Trung ga":
			return "egg"
		"Tien":
			return ""
		"Ca rot":
			return "crop_carrot"
		"Ca chua":
			return "crop_tomato"
		"Bi ngo":
			return "crop_pumpkin"
		_:
			for entry in FarmData.INVENTORY_CATALOG:
				if entry["label"] == label:
					return entry["id"]
	return ""


func _plot_status_text(plot: Dictionary) -> String:
	if not bool(plot["is_hoed"]):
		return "Chua cay"
	if bool(plot["ready_to_harvest"]):
		return "San sang thu hoach"
	if String(plot["crop"]).is_empty():
		return "Dat kho" if not bool(plot["watered_today"]) else "Dat am"
	return "Dang lon - dat am" if bool(plot["watered_today"]) else "Dang lon - dat kho"


func _plot_crop_text(plot: Dictionary) -> String:
	if String(plot.get("crop", "")) == "":
		return "Chua co"
	return FarmData.get_crop_label(String(plot["crop"]))


func _plot_badge_text(plot: Dictionary) -> String:
	if not bool(plot["is_hoed"]):
		return "Chua cay"
	if String(plot["crop"]).is_empty():
		return "Da cay"
	if bool(plot["ready_to_harvest"]):
		return "Thu ngay"
	return _plot_crop_text(plot)


func _plot_fill_color(plot: Dictionary) -> Color:
	if not bool(plot["is_hoed"]):
		return Color(0.48, 0.35, 0.22, 0.94)
	if bool(plot["ready_to_harvest"]):
		return Color(0.95, 0.78, 0.28, 0.98)
	return Color(0.24, 0.59, 0.33, 0.96) if not String(plot["crop"]).is_empty() else Color(0.58, 0.42, 0.26, 0.95)
