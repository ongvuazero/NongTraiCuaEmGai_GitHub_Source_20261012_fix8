extends Control

# Native world presentation. No transaction, inventory or progression is owned here.
const UI = preload("res://scripts/ui_factory.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")
const Nav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const BodyArt = preload("res://scripts/ui/companion_body_art.gd")
const SemanticFlow = preload("res://scripts/ui/action_feedback_flow.gd")
const WorldActivities = preload("res://scripts/ui/dragon_world_activity.gd")
const LAYOUT := "res://data/presentation/dragon_visual_layout_v1.json"
const ART := "res://assets/approved_world_v1/dragons/"
const STATUS := "res://assets/canonical_v2/03_ART_RUNTIME_READY/ANIMAL/STATUS_OVERLAYS/"
const FRAME := "res://assets/approved_world_v1/ui/care_action_frame_v2.png"
const ICON_ATLAS := "res://assets/approved_world_v1/ui/care_semantic_icons_matte_v2.png"
const CARE_NAME_FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
const CARE_NAME_SIZE := 20
const CARE_NAME_MIN_SIZE := 18
# Visible alpha silhouettes (>80), with padding, measured from the source RGBA.
# These are native atlas regions, never painted screenshot slices.
const ICON_REGIONS := {
	"feed": Rect2(64, 88, 594, 509), "pet": Rect2(730, 82, 557, 515),
	"clean": Rect2(100, 618, 525, 541), "water": Rect2(774, 630, 424, 527)
}
static var _layout: Dictionary = {}
signal incubator_selected(egg_id: String)
signal care_opened
signal care_closed
var selected_id := ""
var care_mode := "body" # Transient presentation only, never farm save data.
var owned: Array[String] = []
var page := 0
var bodies: Array[TextureButton] = []
var nests: Array[Button] = []
var care: Control
var preview: TextureRect
var preview_frame: Control
var title: Label
var meters: Dictionary = {}
var values: Dictionary = {}
var food_label: Label
var production: Label
var actions: Dictionary = {}
var toast: Control
var toast_text: Label
var toast_icon: TextureRect
var effect: TextureRect
var effect_tween: Tween
var semantic_flow: Node2D
var page_label: Label
var empty_copy: Label
var texture_cache: Dictionary = {}
var selection_ring: Control
var mode_heading: Label
var meter_rows: Dictionary = {}
var mode_status: Control
var mode_status_icon: TextureRect
var mode_status_text: Label
var mode_note: Control
var mode_note_text: Label
var activity_world: Control

static func layout_rect(id: String) -> Rect2:
	if _layout.is_empty(): _layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var value: Array = _layout.get(id, [0, 0, 1, 1])
	return Rect2(value[0], value[1], value[2], value[3])

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	# The clean environment contains only an EMPTY hatchery structure. Live
	# eggs/progress/input remain separate nodes, never baked screenshot controls.
	var hatchery_anchor := Control.new()
	hatchery_anchor.name = "DragonIncubatorPavilion"
	hatchery_anchor.position = layout_rect("hatchery").position
	hatchery_anchor.size = layout_rect("hatchery").size
	hatchery_anchor.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hatchery_anchor)
	for index in range(3):
		var body := TextureButton.new()
		body.name = "DragonBody_%d" % index
		var body_rect := layout_rect(["main_body", "fire_body", "forest_body"][index])
		body.position = body_rect.position
		body.size = body_rect.size
		body.ignore_texture_size = true
		body.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		body.pressed.connect(_select_body.bind(index))
		add_child(body)
		bodies.append(body)
		var nest := Button.new()
		nest.name = "DragonIncubator_%d" % index
		var nest_rect := layout_rect("incubator_%d" % index)
		nest.position = nest_rect.position
		nest.size = nest_rect.size
		nest.flat = true
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			nest.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		# Straw belongs to the environment. This node is an invisible hit target;
		# only live eggs/progress are added, so the empty bowl is never doubled.
		nest.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var egg_icon := UI.texture_rect(null, Rect2(14, 8, 45, 57))
		egg_icon.name = "EggIcon"
		nest.add_child(egg_icon)
		var caption := UI.label("", Rect2(0, 64, 73, 30), 11, Color("fff7df"), HORIZONTAL_ALIGNMENT_CENTER)
		caption.name = "NestCaption"
		caption.add_theme_color_override("font_outline_color", Color("4a2b19"))
		caption.add_theme_constant_override("outline_size", 3)
		nest.add_child(caption)
		nest.pressed.connect(_select_nest.bind(index))
		add_child(nest)
		nests.append(nest)
	selection_ring = UI.texture_rect(load(STATUS + "selected_interaction_ring.png"), Rect2(0, 0, 104, 28))
	selection_ring.name = "DragonSelectionFeedback"
	selection_ring.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(selection_ring)
	page_label = UI.label("", Rect2(575, 665, 198, 32), 15, Color("fff7df"), HORIZONTAL_ALIGNMENT_CENTER)
	page_label.add_theme_color_override("font_outline_color", Color("4a2b19"))
	page_label.add_theme_constant_override("outline_size", 3)
	add_child(page_label)
	_button("DragonPreviousPage", "‹", Rect2(522, 660, 48, 42), "nursery", self).pressed.connect(_turn_page.bind(-1))
	_button("DragonNextPage", "›", Rect2(778, 660, 48, 42), "nursery", self).pressed.connect(_turn_page.bind(1))
	empty_copy = UI.label("", Rect2(515, 424, 410, 110), 21, Color("fff7df"), HORIZONTAL_ALIGNMENT_CENTER)
	empty_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_copy.add_theme_color_override("font_outline_color", Color("4a2b19"))
	empty_copy.add_theme_constant_override("outline_size", 3)
	add_child(empty_copy)
	_build_care()
	toast = UI.panel(Rect2(540, 313, 350, 62))
	toast.name = "DragonWorldResult"
	toast.mouse_filter = MOUSE_FILTER_IGNORE
	toast.visible = false
	toast.z_index = 20
	add_child(toast)
	toast_icon = UI.texture_rect(null, Rect2(12, 6, 47, 47))
	toast.add_child(toast_icon)
	toast_text = UI.label("", Rect2(69, 6, 268, 50), 17)
	toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_child(toast_text)
	effect = UI.texture_rect(null, Rect2(0, 0, 85, 85))
	effect.mouse_filter = MOUSE_FILTER_IGNORE
	effect.z_index = 19
	effect.visible = false
	add_child(effect)
	activity_world = WorldActivities.new()
	add_child(activity_world)
	activity_world.setup(self, _care_icon("feed"), _care_icon("clean"), Nav._icon("play"))
	refresh()

func _t(vi: String, en: String) -> String:
	return UILocale.pair(vi, en)

func body_texture(id: String) -> Texture2D:
	return BodyArt.texture(id)

func _care_icon(id: String) -> Texture2D:
	if texture_cache.has(id): return texture_cache[id] as Texture2D
	var source := load(ICON_ATLAS) as Texture2D
	var region: Rect2 = ICON_REGIONS[id]
	var factor := source.get_size() / Vector2(1316, 1195)
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(region.position * factor, region.size * factor)
	atlas.filter_clip = true
	texture_cache[id] = atlas
	return atlas

func _inset(rect: Rect2, tint := Color("fff2d5")) -> Control:
	var row := UI.panel(rect, tint, Color("d5a766"), 14)
	var style := row.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_border_width_all(1)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	care.add_child(row)
	return row

func _card_state(button: TextureButton, state: String) -> void:
	if button.disabled: state = "normal"
	button.self_modulate = Color("ffdf99") if state == "hover" else Color("dbc397") if state == "pressed" else Color.WHITE
	var icon := button.get_node("NavigationIcon") as TextureRect
	var caption := button.get_node("Caption") as Label
	icon.position.y = 13 if state == "pressed" else 11
	caption.position.y = 59 if state == "pressed" else 57

func _button(id: String, caption: String, rect: Rect2, icon: String, parent: Control) -> TextureButton:
	var button := UI.title_button(caption, rect)
	button.name = id
	parent.add_child(button)
	if caption not in ["‹", "›", "×"]: Nav.style_button(button, icon, caption, 16)
	return button

func _build_care() -> void:
	care = Control.new()
	care.name = "DragonWorldCare"
	care.position = layout_rect("care_panel").position
	care.size = layout_rect("care_panel").size
	care.mouse_filter = MOUSE_FILTER_STOP
	care.visible = false
	add_child(care)
	var paper := UI.texture_rect("res://assets/approved_world_v1/ui/dragon_care_panel.png", Rect2(Vector2.ZERO, care.size))
	care.add_child(paper)
	var title_rect := layout_rect("care_title")
	title_rect.position -= care.position
	title = UI.label("", title_rect, CARE_NAME_SIZE, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", CARE_NAME_FONT)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.max_lines_visible = 1
	title.name = "DragonCareName"
	care.add_child(title)
	_button("CloseDragonCare", "×", Rect2(283, 10, 36, 38), "book", care).pressed.connect(close_care)
	var frame_rect := layout_rect("preview_frame")
	frame_rect.position -= care.position
	# Preserve the authored cream/curved header instead of covering its lower
	# leaves with an opaque rectangular inset. Bounds remain a transparent anchor.
	preview_frame = Control.new()
	preview_frame.position = frame_rect.position
	preview_frame.size = frame_rect.size
	preview_frame.mouse_filter = MOUSE_FILTER_IGNORE
	care.add_child(preview_frame)
	preview_frame.name = "DragonCarePreviewFrame"
	var preview_rect := layout_rect("preview")
	preview_rect.position -= care.position
	preview = UI.texture_rect(null, preview_rect)
	preview.name = "DragonCarePreview"
	care.add_child(preview)
	mode_heading = UI.label("", Rect2(22, 218, 304, 26), 18, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	mode_heading.name = "DragonCareModeHeading"
	mode_heading.add_theme_font_override("font", CARE_NAME_FONT)
	mode_heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	care.add_child(mode_heading)
	var labels := [["fullness", "No bụng", "Fullness"], ["cleanliness", "Sạch sẽ", "Cleanliness"], ["happiness", "Vui vẻ", "Happiness"]]
	for i in range(3):
		var row: Array = labels[i]
		var row_panel := _inset(Rect2(22, 246 + i * 50, 304, 46))
		var row_caption := UI.label(_t(row[1], row[2]), Rect2(88, 246 + i * 50, 180, 24), 17)
		care.add_child(row_caption)
		var status_icon := UI.texture_rect(null, Rect2(31, 250 + i * 50, 40, 36))
		status_icon.name = ["FullnessIcon", "CleanlinessIcon", "HappinessIcon"][i]
		status_icon.texture = _care_icon("water") if i == 1 else Assets.animal_overlay("happy_cared_heart")
		care.add_child(status_icon)
		var bar := ProgressBar.new()
		var track := layout_rect(["fullness_track", "cleanliness_track", "happiness_track"][i])
		bar.position = track.position - care.position
		bar.show_percentage = false
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		var back := StyleBoxFlat.new()
		back.bg_color = Color("ddc493")
		back.border_color = Color("ad7d44")
		back.set_border_width_all(1)
		back.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("background", back)
		var fill := back.duplicate() as StyleBoxFlat
		fill.bg_color = [Color("79ac48"), Color("4daed0"), Color("dc827a")][i]
		bar.add_theme_stylebox_override("fill", fill)
		care.add_child(bar)
		# Assign after removing the default percentage/theme minimum. Control
		# grows to its old minimum on initial size assignment but never auto-shrinks.
		bar.size = track.size
		meters[row[0]] = bar
		var value := UI.label("", Rect2(280, 252 + i * 50, 45, 30), 18, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
		care.add_child(value)
		values[row[0]] = value
		var parts: Array[Control] = [row_panel, row_caption, status_icon, bar, value]
		var origins: Array[Vector2] = []
		for part in parts: origins.append(part.position)
		meter_rows[row[0]] = {"parts": parts, "origins": origins, "slot": i}
	mode_status = _inset(Rect2(22, 346, 304, 46))
	mode_status.name = "DragonModeStatus"
	mode_status_icon = UI.texture_rect(null, Rect2(10, 6, 35, 34))
	mode_status.add_child(mode_status_icon)
	mode_status_text = UI.label("", Rect2(55, 4, 238, 38), 16, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	mode_status_text.name = "DragonModeStatusText"
	mode_status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_status_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mode_status.add_child(mode_status_text)
	mode_note = _inset(Rect2(22, 346, 304, 46), Color("e4f2ef"))
	mode_note.name = "DragonModeNote"
	mode_note_text = UI.label("", Rect2(10, 4, 284, 38), 15, Color("336e39"), HORIZONTAL_ALIGNMENT_CENTER)
	mode_note_text.name = "DragonModeNoteText"
	mode_note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_note_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mode_note.add_child(mode_note_text)
	_inset(Rect2(22, 401, 304, 49))
	var food_icon := UI.texture_rect(null, Rect2(31, 409, 35, 35))
	food_icon.name = "DragonFoodIcon"
	care.add_child(food_icon)
	food_label = UI.label("", Rect2(73, 404, 243, 43), 15, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	food_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	care.add_child(food_label)
	_inset(Rect2(22, 455, 304, 42), Color("e4f2ef"))
	production = UI.label("", Rect2(31, 457, 286, 38), 14, Color("336e39"), HORIZONTAL_ALIGNMENT_CENTER)
	production.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	care.add_child(production)
	for entry in [["feed", "Cho ăn", "Feed", "storage"], ["pet", "Vuốt ve", "Pet", "play"], ["clean", "Dọn dẹp", "Clean", "settings"], ["collect", "Thu khí", "Collect", "dragon"]]:
		var i := actions.size()
		var action_rect := layout_rect(["feed_card", "pet_card", "clean_card", "collect_card"][i])
		action_rect.position -= care.position
		var button := TextureButton.new()
		button.name = "DragonCare_" + entry[0]
		button.position = action_rect.position
		button.size = action_rect.size
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.texture_normal = load(FRAME) as Texture2D
		button.texture_hover = button.texture_normal
		button.texture_pressed = button.texture_normal
		button.texture_disabled = button.texture_normal
		care.add_child(button)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var icon := UI.texture_rect(null, Rect2(14, 11, 45, 43))
		icon.name = "NavigationIcon"
		button.add_child(icon)
		var caption := UI.label(_t(entry[1], entry[2]), Rect2(8, 57, 57, 23), 12, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
		caption.add_theme_font_override("font", preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf"))
		caption.name = "Caption"
		button.add_child(caption)
		if entry[0] == "collect":
			var count := UI.label("", Rect2(7, 7, 25, 20), 12, Color("175ba4"), HORIZONTAL_ALIGNMENT_CENTER)
			count.name = "ReadyCount"
			count.add_theme_color_override("font_outline_color", Color("fff6da"))
			count.add_theme_constant_override("outline_size", 2)
			button.add_child(count)
		button.mouse_entered.connect(_card_state.bind(button, "hover"))
		button.mouse_exited.connect(_card_state.bind(button, "normal"))
		button.button_down.connect(_card_state.bind(button, "pressed"))
		button.button_up.connect(_card_state.bind(button, "hover"))
		button.pressed.connect(_act.bind(entry[0]))
		actions[entry[0]] = button
	# The remedy replaces the status row, never any valid care/collect action.
	var heal := _button("DragonCare_heal", _t("Dùng thuốc", "Use remedy"), Rect2(22, 455, 304, 42), "craft", care)
	heal.pressed.connect(_act.bind("heal"))
	actions["heal"] = heal

func refresh(preferred := "") -> void:
	if not is_node_ready(): return
	var world := GameState.world_state()
	var config := GameState.world_config()
	var opened := bool(world.get("unlocked_islands", {}).get("dragon", false))
	owned.clear()
	for id in config.get("creatures", {}):
		if String(config.creatures[id].get("kind", "")) == "dragon" and world.get("creatures", {}).has(id): owned.append(String(id))
	if not preferred.is_empty() and owned.has(preferred): selected_id = preferred
	if not owned.has(selected_id): selected_id = owned[0] if not owned.is_empty() else ""
	page = clampi(page, 0, maxi(0, int(ceil(owned.size() / 3.0)) - 1))
	for i in range(3):
		var index := page * 3 + i
		var body := bodies[i]
		body.visible = opened and index < owned.size()
		if not body.visible: continue
		var id := owned[index]
		body.texture_normal = body_texture(id)
		body.texture_hover = body.texture_normal
		body.texture_pressed = body.texture_normal
		if String(body.get_meta("species_id","")) != id:
			for transient_key in ["motion_mouth","source_frame","source_frame_anchor","source_frame_scale","care_action","care_action_at_msec"]:
				if body.has_meta(transient_key): body.remove_meta(transient_key)
		body.set_meta("species_id", id)
		body.set_meta("care_mode", care_mode)
		body.tooltip_text = tr(String(config.creatures[id].name)) + _t(" — chạm để chăm sóc", " — click to care")
		body.set_meta("production_animation", false)
		body.modulate = Color.WHITE
	var incubation: Dictionary = world.get("incubators", {})
	var eggs: Array = incubation.keys()
	for i in range(3):
		var nest := nests[i]
		nest.visible = opened
		var id := String(eggs[i]) if i < eggs.size() else ""
		nest.set_meta("egg_id", id)
		(nest.get_node("EggIcon") as TextureRect).texture = Assets.get_item_texture(id) if not id.is_empty() else null
		var text := _t("Ổ trống", "Empty nest")
		if not id.is_empty():
			var state: Dictionary = incubation[id]
			text = _t("Đón rồng!", "Hatch!") if state.get("ready", false) else "%d / %d %s" % [state.progress, state.required, _t("ngày", "days")]
		(nest.get_node("NestCaption") as Label).text = text
	# Mode summaries already explain empty state and its next action. Avoid a
	# second purpose block across the native Farmer/world art.
	empty_copy.visible = opened and owned.is_empty()
	empty_copy.text = _t("Chưa có Rồng.\nChạm ổ trứng để bắt đầu ấp.", "No dragons yet.\nClick a nest to begin incubating.")
	page_label.text = _t("Rồng của bạn · %d / %d", "Your dragons · %d / %d") % [page + 1, maxi(1, int(ceil(owned.size() / 3.0)))]
	page_label.visible = opened and not owned.is_empty()
	for key in ["DragonPreviousPage", "DragonNextPage"]:
		var button := get_node(key) as TextureButton
		button.visible = opened and owned.size() > 3
	if not opened or selected_id.is_empty():
		care.hide()
		toast.hide()
		effect.hide()
		if effect_tween != null and effect_tween.is_valid(): effect_tween.kill()
	_refresh_care(world, config)
	if activity_world != null: activity_world.refresh()
	if care.visible: preload("res://scripts/ui/mobile_runtime.gd").request_control_layout(care)

func _select_body(index: int) -> void:
	if activity_world != null: activity_world.cancel("body_selected")
	selected_id = String(bodies[index].get_meta("species_id", ""))
	care_opened.emit()
	care.show()
	refresh()

func close_care(notify := true) -> void:
	if activity_world != null: activity_world.cancel("surface_closed")
	if semantic_flow != null and is_instance_valid(semantic_flow): semantic_flow.queue_free()
	care.hide()
	if activity_world != null: activity_world.refresh()
	selection_ring.hide()
	toast.hide()
	effect.hide()
	if effect_tween != null and effect_tween.is_valid(): effect_tween.kill()
	if notify: care_closed.emit()

func close_top_presentation() -> bool:
	if not care.visible: return false
	close_care()
	return true

func select_species(id: String) -> void:
	if not owned.has(id): return
	if activity_world != null and id != selected_id: activity_world.cancel("species_selected")
	selected_id = id
	page = int(owned.find(id) / 3)
	care.show()
	refresh()


func set_care_mode(mode: String) -> void:
	if activity_world != null and mode != care_mode: activity_world.cancel("mode_changed")
	care_mode = mode if mode in ["body", "nursery", "playground"] else "body"
	set_meta("care_mode", care_mode)
	if activity_world != null: activity_world.refresh()


func _show_meter(key: String, slot: int, visible: bool) -> void:
	var row: Dictionary = meter_rows[key]
	var parts: Array = row["parts"]
	for index in range(parts.size()):
		var control := parts[index] as Control
		control.visible = visible
		control.position = row["origins"][index] + Vector2(0, (slot - int(row["slot"])) * 50)


func _present_care_mode(state: Dictionary, definition: Dictionary, config: Dictionary) -> void:
	var nursery := care_mode == "nursery"
	var playground := care_mode == "playground"
	mode_heading.text = _t("NHÀ TRẺ · CHĂM SÓC", "NURSERY · CARE") if nursery else _t("SÂN CHƠI · VUI CHƠI", "PLAYGROUND · PLAY") if playground else _t("CHĂM SÓC RỒNG", "DRAGON CARE")
	# Reserve a clean native heading inside the original preview footprint.
	var preview_rect := layout_rect("preview")
	preview.position = preview_rect.position - care.position
	preview.size = Vector2(preview_rect.size.x, 134)
	_show_meter("fullness", 0, not playground)
	_show_meter("cleanliness", 1, not playground)
	_show_meter("happiness", 0 if playground else 2, not nursery)
	mode_status.visible = nursery or playground
	mode_note.visible = playground
	var disease := String(state.get("disease", ""))
	var ready := int(state.get("products_ready", 0))
	mode_status.position = Vector2(22, 296 if playground else 346)
	if nursery:
		mode_status_icon.texture = Assets.get_item_texture("medicine_" + disease) if not disease.is_empty() else Assets.animal_overlay("happy_cared_heart")
		mode_status_text.text = _t("Sức khỏe tốt", "Healthy") if disease.is_empty() else tr(String(config.items.get("medicine_" + disease, {}).get("name", disease)))
		production.text = _t("Chăm sức khỏe trước khi vui chơi.", "Care for health before play.")
	elif playground:
		mode_status_icon.texture = Assets.get_item_texture("dragon_energy")
		mode_status_text.text = _t("Long Khí sẵn sàng: %d", "Dragon Energy ready: %d") % ready
		mode_note_text.text = _t("Cả 3 chỉ số ≥40 và khỏe mạnh;\nqua ngày để tạo Long Khí.", "All 3 meters ≥40 and healthy;\nNEXT DAY produces Dragon Energy.")
		(care.get_node("DragonFoodIcon") as TextureRect).texture = Assets.animal_overlay("happy_cared_heart")
		food_label.text = _t("Vuốt ve · 1 năng lượng\nVui vẻ tối đa 100", "Pet · 1 energy\nHappiness capped at 100")
		production.text = _t("Nhấn Thu khí để nhận %d Long Khí.", "Collect %d Dragon Energy now.") % ready if ready > 0 else _t("Chưa có khí. Chăm đủ rồi qua ngày.", "No energy ready. Care, then NEXT DAY.")
	production.visible = playground or disease.is_empty()
	for action in ["feed", "pet", "clean", "collect"]:
		var button: TextureButton = actions[action]
		button.visible = (action in ["feed", "clean"]) if nursery else (action in ["pet", "collect"]) if playground else true
		var rect := layout_rect(action + "_card")
		if nursery or playground:
			rect = layout_rect("pet_card" if action in ["feed", "pet"] else "clean_card")
		button.position = rect.position - care.position
		button.size = rect.size
	actions.heal.visible = not playground and not disease.is_empty()

func _select_nest(index: int) -> void:
	close_care(false)
	incubator_selected.emit(String(nests[index].get_meta("egg_id", "")))

func _turn_page(direction: int) -> void:
	var pages := maxi(1, int(ceil(owned.size() / 3.0)))
	page = posmod(page + direction, pages)
	close_care()
	refresh()

func _refresh_care(world: Dictionary, config: Dictionary) -> void:
	selection_ring.hide()
	if selected_id.is_empty(): return
	var state: Dictionary = world.creatures.get(selected_id, {})
	var definition: Dictionary = config.creatures.get(selected_id, {})
	_fit_care_name(tr(String(definition.get("name", selected_id))))
	preview.texture = body_texture(selected_id)
	for key in meters:
		meters[key].value = int(state.get(key, 0))
		values[key].text = str(int(state.get(key, 0)))
	var food := String(definition.get("food", ""))
	(care.get_node("FullnessIcon") as TextureRect).texture = _care_icon("feed")
	(care.get_node("DragonFoodIcon") as TextureRect).texture = Assets.get_item_texture(food)
	food_label.text = "%s ×%d" % [tr(String(config.items.get(food, {}).get("name", food))), int(GameState.data.inventory.get(food, 0))]
	var disease := String(state.get("disease", ""))
	var ready := int(state.get("products_ready", 0))
	production.text = (_t("Long Khí sẵn sàng: %d", "Dragon Energy ready: %d") % ready) if ready > 0 else _t("Chăm đủ ≥40, khỏe mạnh;\nchọn NGÀY MỚI để tạo Long Khí.", "Healthy meters ≥40;\nNEXT DAY produces Dragon Energy.")
	if not disease.is_empty(): production.text = tr(disease) + " · " + tr(String(config.items.get("medicine_" + disease, {}).get("name", "")))
	production.visible = disease.is_empty()
	Nav.set_caption(actions.heal, _t("Chữa ", "Treat ") + tr(disease) if not disease.is_empty() else _t("Dùng thuốc", "Use remedy"))
	var ready_count := actions.collect.get_node("ReadyCount") as Label
	ready_count.text = "×%d" % ready
	ready_count.visible = ready > 0
	for action in actions:
		var button: TextureButton = actions[action]
		var icon := button.get_node_or_null("NavigationIcon") as TextureRect
		if icon != null:
			match action:
				"feed": icon.texture = _care_icon("feed")
				"pet": icon.texture = _care_icon("pet")
				"clean": icon.texture = _care_icon("clean")
				"collect": icon.texture = Assets.get_item_texture("dragon_energy")
				"heal": icon.texture = Assets.get_item_texture("medicine_" + disease) if not disease.is_empty() else null
		var info := GameState.world_action_info(action, selected_id)
		button.disabled = not bool(info.get("ok", false))
		button.modulate = Color(0.65, 0.65, 0.65, 0.68) if button.disabled else Color.WHITE
		button.tooltip_text = UILocale.translate_message(String(info.get("reason", "")))
		if action == "heal" and not disease.is_empty(): button.tooltip_text = production.text + "\n" + button.tooltip_text
		if action == "collect" and ready > 0: button.tooltip_text = _t("Long Khí sẵn sàng: %d", "Dragon Energy ready: %d") % ready
		if action == "heal": button.visible = not disease.is_empty()
	_present_care_mode(state, definition, config)
	for body in bodies:
		if care.visible and body.visible and String(body.get_meta("species_id", "")) == selected_id:
			selection_ring.position = Vector2(body.position.x + body.size.x * 0.5 - 52, body.position.y + body.size.y - 17)
			selection_ring.show()

func _fit_care_name(caption: String) -> void:
	title.text = caption
	var safe := layout_rect("care_title")
	var font_size := CARE_NAME_SIZE
	while font_size > CARE_NAME_MIN_SIZE and CARE_NAME_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 4.0 > safe.size.x:
		font_size -= 1
	var measured := CARE_NAME_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	title.add_theme_font_size_override("font_size", font_size)
	title.custom_minimum_size = Vector2.ZERO
	title.size = safe.size
	title.tooltip_text = caption
	title.set_meta("measured_name_size", measured)
	title.set_meta("name_fits_header", measured.x + 4.0 <= safe.size.x and measured.y <= safe.size.y)

func _act(action: String) -> bool:
	if activity_world != null and not activity_world.committing: activity_world.cancel("direct_care_action")
	if semantic_flow != null and is_instance_valid(semantic_flow): semantic_flow.queue_free()
	var state: Dictionary = GameState.world_state().get("creatures", {}).get(selected_id, {})
	var amount := int(state.get("products_ready", 0))
	var before := GameState.dragon_energy()
	var ok := GameState.world_action(action, selected_id)
	refresh()
	if effect_tween != null and effect_tween.is_valid(): effect_tween.kill()
	toast.visible = true
	toast.modulate = Color.WHITE
	toast_text.text = UILocale.translate_message(GameState.status)
	toast.set_meta("action_succeeded", ok)
	toast.set_meta("action", action)
	toast.set_meta("target_species", selected_id)
	if ok and action == "collect": toast_text.text = "+%d %s · %d → %d" % [amount, _t("Long Khí", "Dragon Energy"), before, GameState.dragon_energy()]
	if ok and action == "pet":
		var happiness := int(GameState.world_state().get("creatures", {}).get(selected_id, {}).get("happiness", 0))
		toast_text.text = _t("Vui vẻ: %d → %d", "Happiness: %d → %d") % [int(state.get("happiness", 0)), happiness]
	if ok:
		for body in bodies:
			if body.visible and String(body.get_meta("species_id", "")) == selected_id:
				body.set_meta("care_mode", care_mode)
				body.set_meta("care_action", action)
				body.set_meta("care_action_at_msec", Time.get_ticks_msec())
	else:
		for body in bodies:
			if String(body.get_meta("species_id","")) == selected_id:
				body.set_meta("care_action","")
				body.set_meta("care_action_at_msec",-10000)
	var food := String(GameState.world_config().creatures[selected_id].food)
	toast_icon.texture = Assets.get_item_texture("dragon_energy" if action == "collect" else "medicine_" + String(state.get("disease", "")) if action == "heal" else food) if action in ["feed", "collect", "heal"] else load(STATUS + ("clean_fresh_sparkle.png" if action == "clean" else "happy_cared_heart.png")) as Texture2D
	effect.texture = load(STATUS + ("clean_fresh_sparkle.png" if action in ["clean", "collect", "heal"] else "interaction_success_heart_burst.png")) as Texture2D
	effect.visible = ok
	effect.modulate = Color.WHITE
	for body in bodies:
		if body.visible and String(body.get_meta("species_id", "")) == selected_id:
			effect.position = body.position + body.size * Vector2(0.65, 0.2) - Vector2(42, 42)
			if ok:
				semantic_flow = SemanticFlow.new()
				semantic_flow.name = "DragonSemanticFlow"
				add_child(semantic_flow)
				var mouth: Vector2 = body.get_meta("motion_mouth",body.size*Vector2(0.76,0.29))
				var anchor := mouth if action in ["feed","heal"] else mouth-Vector2(5,24) if action == "pet" else body.size*Vector2(0.5,0.94)
				semantic_flow.position = body.position+anchor
				semantic_flow.configure(action,0.95,Vector2.ZERO,toast_icon.texture,toast.position+toast.size*0.5-semantic_flow.position)
				if action in ["feed","heal"]: semantic_flow.follow_mouth(body)
	effect_tween = create_tween().set_parallel(true)
	effect_tween.tween_property(effect, "modulate:a", 0.0, 0.4).set_delay(0.5)
	effect_tween.tween_property(toast, "modulate:a", 0.0, 0.4).set_delay(1.5)
	effect_tween.finished.connect(func() -> void: effect.hide(); toast.hide())
	return ok
