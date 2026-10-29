extends BaseScreen

const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const FutureIslands = preload("res://scripts/ui/future_islands_dialog.gd")

var order_panel: Panel
var v6_spec: Dictionary
var v6_anchors: Dictionary
var parity_spec: Dictionary


func build() -> void:
	set_meta("v6_visual_status", "V6_5_REFERENCE_PLATE_PRESENTATION_HUB")
	v6_spec = V6.screen("home_hub")
	v6_anchors = V6.anchors("home_hub")
	parity_spec = V6.parity_spec("home_hub")
	var plate_spec := V6.reference_plate_spec("home_hub")
	add_child(UI.texture_rect(String(plate_spec["base_plate"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(String(plate_spec["ui_overlay"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
	_add_dynamic_hud()
	_add_left_navigation()
	order_panel = UI.panel(V6.named_rect(v6_anchors, "ORDER_PANEL_RECT"), Color("f6e4bfee")); add_child(order_panel)
	order_panel.name = "FirstSessionOrderPanel"
	var order_title := UI.label(tr("BẮT ĐẦU"), V6.named_rect(v6_anchors, "ORDER_TITLE_RECT"), 18, Color("4b2d1a"), HORIZONTAL_ALIGNMENT_CENTER)
	order_title.name = "FirstSessionOrderTitle"
	order_panel.add_child(order_title)
	var order_body := UI.label(tr("Vào Ruộng để trồng\nCà rốt đầu tiên."), V6.named_rect(v6_anchors, "ORDER_BODY_RECT"), 16, Color("67462e"), HORIZONTAL_ALIGNMENT_CENTER)
	order_body.name = "FirstSessionOrderBody"
	order_panel.add_child(order_body)
	order_panel.visible = int(GameState.data.get("orders_done", 0)) == 0
	_add_seed_relief()
	_add_world_access()
	_add_future_islands_sign()


func _add_seed_relief() -> void:
	var need := WorldSystems.seed_relief_info(GameState.data)
	if not bool(need.get("ok", false)): return
	var eligibility := GameState.world_action_info("request_seed_relief")
	var has_space := bool(eligibility.get("ok", false))
	order_panel.visible = true
	order_panel.size.y = 178
	var title := order_panel.get_node("FirstSessionOrderTitle") as Label
	title.text = UILocale.pair("HẠT CỨU TRỢ", "SEED RELIEF")
	var body := order_panel.get_node("FirstSessionOrderBody") as Label
	body.text = UILocale.pair("Hết vốn và hết hạt/cây.\nNhận 1 hạt cà rốt\nđể trồng lại.", "No seed money or crops.\nReceive 1 carrot seed\nto restart your farm.")
	if not has_space:
		body.text = UILocale.pair("Kho đầy. Mở Kho,\nbỏ đồ không cần rồi\nquay lại nhận hạt.", "Storage is full. Open it,\ndiscard unused supplies,\nthen return for a seed.")
	_fit_home_copy(title, Rect2(12,8,196,32), 18, 14)
	_fit_home_copy(body, Rect2(15,43,190,70), 16, 13, true)
	var button := UI.art_button(UILocale.pair("Nhận hạt", "Receive seed") if has_space else UILocale.pair("Mở Kho", "Open Storage"), Rect2(12,118,196,48))
	button.name = "HomeSeedRelief" if has_space else "HomeSeedReliefStorage"
	button.tooltip_text = String(eligibility.get("reason", ""))
	order_panel.add_child(button)
	button.pressed.connect(_request_seed_relief if has_space else ScreenRouter.go.bind("storage"))


func _request_seed_relief() -> void:
	GameState.world_action("request_seed_relief")


func _add_future_islands_sign() -> void:
	# This matches the blank wooden arrow in the actual Home scenery plate.
	var sign := Button.new()
	sign.name = "HomeFutureIslandsSign"
	sign.position = Vector2(821,249)
	sign.size = Vector2(103,80)
	sign.flat = true
	sign.focus_mode = Control.FOCUS_ALL
	sign.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sign.tooltip_text = FutureIslands.title_text()
	sign.z_index = 2400
	for property in sign.get_property_list():
		if property.name == "accessibility_name": sign.set("accessibility_name", sign.tooltip_text)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(1.0,0.91,0.53,0.10)
	focus.border_color = Color("f4d770")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(8)
	sign.add_theme_stylebox_override("focus", focus)
	var hover := focus.duplicate() as StyleBoxFlat
	hover.set_border_width_all(1)
	sign.add_theme_stylebox_override("hover", hover)
	sign.pressed.connect(_open_future_islands)
	sign.set_meta("home_sign_logical_rect", Rect2(821,249,103,80))
	var caption := UI.label(tr("New ideas"), Rect2(23,15,70,24), 14, Color("fff1dc"), HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "FutureSignCaption"
	caption.add_theme_font_override("font", LocaleFonts.semibold())
	caption.add_theme_color_override("font_outline_color", Color("644328"))
	caption.add_theme_constant_override("outline_size", 1)
	_fit_home_copy(caption, Rect2(23,15,70,24), 14, 11)
	sign.add_child(caption)
	add_child(sign)
	# A live tree has the actual inherited script-font metrics, not detached
	# Control defaults. Refit the tiny plank caption after the initial build.
	call_deferred("_fit_future_sign_caption", caption)


func _fit_future_sign_caption(caption: Label) -> void:
	if is_instance_valid(caption) and not caption.is_queued_for_deletion():
		_fit_home_copy(caption, Rect2(23,15,70,24), 14, 11)


func _open_future_islands() -> void:
	FutureIslands.open_for(self)


func close_top_presentation() -> bool:
	var dialog := get_node_or_null("FutureIslandsDialog")
	if dialog != null and not dialog.is_queued_for_deletion() and dialog.is_open():
		dialog.close()
		return true
	return false


func _focus_future_sign_if_ready() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED or is_queued_for_deletion(): return
	var sign := get_node_or_null("HomeFutureIslandsSign") as Control
	if sign != null and not sign.is_queued_for_deletion(): sign.grab_focus()


func _add_world_access() -> void:
	# Nested access preserves the approved seven direct navigation hit targets.
	var access := Control.new()
	access.name = "WorldAccess"
	access.position = Vector2(284, 645)
	access.size = Vector2(700, 55)
	add_child(access)
	var entries := [["Bản đồ đảo", "islands"], ["Bào chế", "craft"], ["Sinh vật", "creatures"], ["Sự kiện", "events"]]
	for index in range(entries.size()):
		var button := UI.art_button(tr(String(entries[index][0])), Rect2(index * 172, 0, 165, 48))
		button.name = "HomeWorld_%s" % entries[index][1]
		(button.get_child(0) as Label).name = "Caption"
		var caption := button.get_child(0) as Label
		_fit_home_copy(caption, Rect2(10, 7, 145, 34), 18, 15)
		button.pressed.connect(ScreenRouter.go.bind(entries[index][1]))
		access.add_child(button)


func _add_world_landmarks() -> void:
	var geometry := V6.geometry("home_hub")
	add_child(UI.texture_rect(ROOT + "/PROPS/PORTAL/dragon_portal_complete.png", V6.uniform_actor_rect("HOME_PORTAL", V6.foot_anchor(geometry, "PORTAL_GROUND")), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(ROOT + "/CHARACTERS/ANIMALS/cow_idle.png", V6.uniform_actor_rect("HOME_COW", V6.foot_anchor(geometry, "COW")), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(ROOT + "/CHARACTERS/ANIMALS/sheep_idle.png", V6.uniform_actor_rect("HOME_SHEEP", V6.foot_anchor(geometry, "SHEEP")), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(ROOT + "/CHARACTERS/ANIMALS/chicken_idle.png", V6.uniform_actor_rect("HOME_CHICKEN", V6.foot_anchor(geometry, "CHICKEN")), TextureRect.STRETCH_SCALE))


func _add_left_navigation() -> void:
	var entries := [
		["NAV_FIELD", "Ruộng", "field_select"],
		["NAV_SHOP", "Cửa hàng", "shop"],
		["NAV_STORAGE", "Kho", "storage"],
		["NAV_ANIMALS", "Vật nuôi", "animal"],
		["NAV_DRAGON", "Đảo Rồng", "dragon"],
		["NAV_QUEST", "Nhiệm vụ", "quest"],
		["NAV_SETTINGS", "Cài đặt", "settings"],
	]
	var fixture_nav: Array = V6.parity_fixture().get("home_hub", {}).get("nav", []) if V6.is_parity_mode() else []
	var geometry := V6.geometry("home_hub")
	var icons := ["field", "shop", "storage", "animal", "dragon", "quest", "settings"]
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var hit_rect := V6.visible_rect(geometry, entry[0], "visible_ui_rects")
		var button := TextureButton.new()
		button.name = "LeftNav_%s" % String(entry[2])
		button.position = hit_rect.position
		button.size = hit_rect.size
		button.pressed.connect(_nav.bind(entry[2]))
		add_child(button)
		var caption_text := String(fixture_nav[index]) if fixture_nav.size() > index else String(entry[1])
		FarmNav.style_button(button, String(icons[index]), tr(caption_text))
		var caption := button.get_node("Caption") as Label
		caption.add_theme_constant_override("line_spacing", -2)
		_fit_home_copy(caption, Rect2(caption.position, caption.size), 18, 14, true)
	var rest_rect := V6.visible_rect(geometry, "REST_NEXTDAY", "visible_ui_rects")
	var next := Button.new()
	next.flat = true
	next.position = rest_rect.position
	next.size = rest_rect.size
	next.pressed.connect(GameState.advance_day)
	add_child(next)
	var fixture_home: Dictionary = V6.parity_fixture().get("home_hub", {}) if V6.is_parity_mode() else {}
	var rest_text := String(fixture_home.get("rest", "Nghỉ / Ngày mới"))
	var rest_caption := UI.label(tr(rest_text), V6.dictionary_rect(parity_spec, "dynamic_text_rects", "REST"), 16, Color("fff3c4"), HORIZONTAL_ALIGNMENT_CENTER)
	_apply_parity_type(rest_caption, Color("2b1b13"))
	add_child(rest_caption)


func _add_dynamic_hud() -> void:
	var fixture: Dictionary = V6.parity_fixture().get("home_hub", {}) if V6.is_parity_mode() else {}
	var date_text := tr("Day %d\n%s") % [int(fixture.get("day", 1)), tr(String(fixture.get("season", "Spring")))] if V6.is_parity_mode() else tr("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), tr(GameState.current_season())]
	var values := {
		"DATE": date_text,
		"MONEY": String(fixture.get("money", "0")) if V6.is_parity_mode() else "%d" % int(GameState.data.get("coins", 0)),
		"ENERGY": String(fixture.get("energy", "0 / 100")) if V6.is_parity_mode() else "%d/100" % int(GameState.data.get("energy", 0)),
		"LONG_KHI": "%s\n%s" % [tr(String(fixture.get("long_khi_label", "Long Khi"))), String(fixture.get("long_khi_value", "0"))] if V6.is_parity_mode() else tr("Long Khí\n%d") % GameState.dragon_energy(),
	}
	for id in ["DATE", "MONEY", "ENERGY", "LONG_KHI"]:
		var value := UI.label(values[id], V6.dictionary_rect(parity_spec, "dynamic_text_rects", id), 16 if id == "DATE" or id == "LONG_KHI" else 18, Color("3b281a"), HORIZONTAL_ALIGNMENT_CENTER)
		value.name = "HomeHUD_%s" % id
		if id == "ENERGY":
			# The right34px of this authored value rect contains the baked plus icon.
			# Reserve its space without moving or replacing any approved HUD art.
			value.clip_text = true
			value.size.x -= 34.0
		_apply_parity_type(value, Color("fff9e8"))
		add_child(value)
		if id in ["DATE", "LONG_KHI"]: value.add_theme_constant_override("line_spacing", -2)
		_fit_home_copy(value, Rect2(value.position + Vector2(2,4), value.size - Vector2(4,8)), 16 if id in ["DATE", "LONG_KHI"] else 18, 13 if id in ["DATE", "LONG_KHI"] else 15)


func _fit_home_copy(label: Label, safe: Rect2, base_size: int, minimum_size: int, allow_wrap := false) -> void:
	label.add_theme_font_override("font",LocaleFonts.for_text(label.text,label.get_theme_font("font")))
	# Keep authored button/chip Controls and complete information. The native
	# Label's line metrics include the active script/font fallback; Font's generic
	# multiline measurement underestimates them for Thai/CJK fallback chains.
	label.tooltip_text = label.text
	label.clip_text = true
	label.max_lines_visible = -1
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.position = safe.position
	label.custom_minimum_size = Vector2.ZERO
	label.size = safe.size
	var measured := Vector2.ZERO
	for font_size in range(base_size, minimum_size-1, -1):
		label.add_theme_font_size_override("font_size", font_size)
		measured.x = 0.0
		for line in label.text.split("\n"):
			measured.x = maxf(measured.x, label.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if allow_wrap and measured.x>safe.size.x else TextServer.AUTOWRAP_OFF
		if label.autowrap_mode!=TextServer.AUTOWRAP_OFF:
			measured.x = label.get_theme_font("font").get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,safe.size.x,font_size).x
		var lines := maxi(label.get_line_count(), 1)
		measured.y = lines*label.get_line_height()+maxi(lines-1,0)*label.get_theme_constant("line_spacing")
		if measured.x<=safe.size.x and measured.y<=safe.size.y: break
	label.size = safe.size
	label.set_meta("home_copy_safe_rect", safe)
	label.set_meta("home_copy_measured", measured)
	label.set_meta("home_copy_fits", measured.x<=safe.size.x and measured.y<=safe.size.y)


func _apply_parity_type(label: Label, outline_color: Color) -> void:
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color("0000002e"))


func _add_farmer() -> void:
	var geometry := V6.geometry("home_hub")
	add_child(UI.texture_rect(ROOT + "/ANIMATION/FARMER/idle/frame_01.png", V6.uniform_actor_rect("HOME_FARMER", V6.foot_anchor(geometry, "FARMER")), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(ROOT + "/CHARACTERS/CAT/calico_cat_sitting.png", V6.uniform_actor_rect("HOME_CAT", V6.foot_anchor(geometry, "CAT")), TextureRect.STRETCH_SCALE))


func _nav(target: String) -> void:
	if target == "settings": GameState.settings_return = "hub"
	ScreenRouter.go(target)


func _settings() -> void:
	GameState.settings_return = "hub"
	ScreenRouter.go("settings")
