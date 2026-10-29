extends BaseScreen

# Authored game panels and artwork; GameState owns every transaction and save.
const Locale = preload("res://scripts/ui_locale.gd")
const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const BodyArt = preload("res://scripts/ui/companion_body_art.gd")
const PanelSceneryLife = preload("res://scripts/ui/panel_scenery_life.gd")
const ItemSource = preload("res://scripts/ui/item_source_presenter.gd")
const REGULAR_FONT = preload("res://assets/fonts/BeVietnamPro-Regular.ttf")
const BOLD_FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
@export var section := "islands"
var selected_group := ""
var selected_id := ""
var feedback := ""
var _hud: Control
var _blocked_reason := ""
var _has_available_action := false
var _island_art_cache: Dictionary = {}

const SECTIONS := {
	"islands": [["islands", "Island map"]],
	"craft": [["buildings", "Buildings"], ["gardens", "Herb garden"], ["recipes", "Recipes"], ["items", "Supplies"]],
	"creatures": [["creatures", "Companions"], ["eggs", "Eggs"]],
	"events": [["events", "Milestones & fairs"]],
}
const HEADINGS := {"islands": "Explore the islands", "craft": "Farm workshop", "creatures": "Our farm companions", "events": "Seasons & celebrations"}
const SUBHEADINGS := {
	"islands": "Choose an island on the map to discover its gifts.",
	"craft": "Build, grow herbs and make useful things for your farm.",
	"creatures": "A little care every day makes a happy companion.",
	"events": "Watch your progress and collect your farm rewards.",
}
const BACKGROUNDS := {"islands": "hub", "craft": "shop", "creatures": "animal", "events": "field_select"}
const BUTTON_ROOT := ROOT + "/UI/TITLE_SAVE_HOME/title_button_frame_"
const ACTION_ROOT := ROOT + "/UI/SHARED_BUTTONS/primary_medium/"
const LANDMARK_ICONS := {"main": "barn", "botanical": "garden", "dragon": "dragon_altar", "monster": "monster_pen", "ice": "icehouse", "lava": "forge", "snake": "serpent_den"}
const ISLAND_ART_ROOT := "res://assets/ui_mockup_application_v1/islands/"
const MAP_POSITIONS := {"main": Vector2(271, 273), "botanical": Vector2(18, 137), "dragon": Vector2(524, 137), "monster": Vector2(524, 0), "ice": Vector2(271, 0), "lava": Vector2(18, 0), "snake": Vector2(271, 137)}
# Source PNGs contain large transparent canvases. These measured opaque-art
# regions enlarge their actual artwork without changing a pixel of the files.
const ART_REGIONS := {
	"alchemy": Rect2(232, 235, 789, 830),
	"garden": Rect2(184, 131, 895, 991),
	"barn": Rect2(122, 217, 1037, 820),
	"special_shop": Rect2(211, 211, 833, 857),
	"dragon_altar": Rect2(194, 246, 870, 792),
	"icehouse": Rect2(75, 73, 1113, 1107),
	"forge": Rect2(71, 42, 1114, 1149),
	"serpent_den": Rect2(69, 121, 1117, 1015),
	"monster_pen": Rect2(38, 119, 1190, 1018),
	"warehouse": Rect2(55, 106, 1144, 1031),
	"pond": Rect2(210, 287, 837, 686),
}
const ANIMAL_ART := {
	"cloud_chicken": ROOT + "/ANIMAL/BASE/chicken_idle.png",
	"duck": "res://assets/gdd_closure_v3/animals/duck_idle.png",
	"pig": "res://assets/gdd_closure_v3/animals/pig_idle.png",
	"cow": ROOT + "/CHARACTERS/ANIMALS/cow_idle.png",
}
const DISPLAY_DESCRIPTIONS := {
	"islands:main": "Your cozy home, twelve crop beds and the Cloud Chicken barn.",
	"islands:botanical": "Grow medicinal herbs, brew remedies and prepare food for your companions.",
	"islands:dragon": "Raise elemental dragons, hatch their eggs and choose a daily helper.",
	"buildings:dragon_altar": "Hatch elemental eggs. Once a day, spend 5 Dragon Energy to restore up to 20 farm energy.",
	"buildings:warehouse": "Carry more gathered supplies. Your existing items always stay safe.",
	"items:dragon_treat": "A crafted cake gives an owned dragon +25 happiness. Keep feeding and treating it as usual.",
	"creatures:rainbow_dragon": "A rare companion that helps eggs hatch a little faster.",
	"creatures:gold_dragon": "A cared-for daily helper brings home one crystal each day.",
	"creatures:gold_fish": "A bright pond companion that brings small crafting materials.",
}


func build() -> void:
	Locale.initialize()
	_apply_authored_presentation()
	var background := UI.background(String(BACKGROUNDS.get(section, "hub")))
	background.name = "WorldBackground"
	add_child(background)
	move_child(background, 0)
	_hud = Control.new()
	_hud.name = "WorldHUD"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	UI.add_hud(_hud)
	FarmNav.style_logo(_hud.get_child(0) as TextureRect)
	_update_hud()
	_add_navigation()
	_add_touch_scroll_controls()
	for entry in SECTIONS.get(section, SECTIONS["islands"]):
		var tab := _paint_button(tr(String(entry[1])), Vector2(252, 48))
		tab.name = "Tabs_%s" % entry[0]
		tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tab.pressed.connect(_select_group.bind(String(entry[0])))
		get_node("MainPanel/Tabs").add_child(tab)
	_update_static_labels()
	_select_group(String(SECTIONS.get(section, SECTIONS["islands"])[0][0]))


func _add_touch_scroll_controls() -> void:
	# A thin desktop scrollbar is difficult to drag on a phone. Keep normal
	# swipe/drag scrolling, but also provide two large, fixed tap targets that
	# move exactly one list card at a time.
	var entries := get_node("MainPanel/Entries") as ScrollContainer
	entries.get_v_scroll_bar().value_changed.connect(_on_entries_scroll_changed)
	for definition in [["WorldEntriesUp", "▲", -1, 120], ["WorldEntriesDown", "▼", 1, 402]]:
		var button := _paint_button(String(definition[1]), Vector2(48, 48), false, true)
		button.name = String(definition[0])
		button.position = Vector2(entries.position.x + entries.size.x - 54, float(definition[3]))
		button.size = Vector2(48, 48)
		button.tooltip_text = UILocale.pair("Cuộn danh sách", "Scroll the list")
		button.set_meta("touch_scroll_direction", int(definition[2]))
		button.pressed.connect(_scroll_entries_one_card.bind(int(definition[2])))
		get_node("MainPanel").add_child(button)
	_update_touch_scroll_controls.call_deferred()


func _on_entries_scroll_changed(_value: float) -> void:
	_update_touch_scroll_controls()


func _scroll_entries_one_card(direction: int) -> void:
	var entries := get_node("MainPanel/Entries") as ScrollContainer
	var target := clampi(entries.scroll_vertical + direction * 104, 0, int(entries.get_v_scroll_bar().max_value))
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(entries, "scroll_vertical", target, 0.18)


func _apply_authored_presentation() -> void:
	# All major blocks are serialized in the scene. Only the wide island-map
	# variant differs; its hidden editor markers provide the exact rectangles.
	if section == "islands":
		var layout := get_node("MainPanel/ISLAND_LAYOUT")
		for marker in layout.get_children():
			var target := get_node("MainPanel/" + String(marker.name)) as Control
			target.position = (marker as Control).position
			target.size = (marker as Control).size
		get_node("MainPanel/Tabs").visible = false
		(get_node("MainPanel/EntryName") as Label).add_theme_font_size_override("font_size", 23)
		(get_node("MainPanel/EntryDescription") as Label).add_theme_font_size_override("font_size", 15)
		# Leave room for the restored daily gather and readable source links.
		(get_node("MainPanel/EntryPreview") as Control).size.y = 74
		(get_node("MainPanel/EntryStatus") as Control).position.y = 249
		(get_node("MainPanel/Details") as Control).position.y = 280
		(get_node("MainPanel/Details") as Control).size.y = 145
		(get_node("MainPanel/Actions") as Control).position.y = 434
	elif section == "creatures":
		var layout := get_node("MainPanel/COMPANION_LAYOUT")
		for marker in layout.get_children():
			var target := get_node("MainPanel/" + String(marker.name)) as Control
			target.position = (marker as Control).position
			target.size = (marker as Control).size
	var preview := get_node("MainPanel/EntryPreview") as Control
	var scenery := get_node("MainPanel/EntryPreview/PreviewScenery") as TextureRect
	scenery.size = preview.size
	var icon := get_node("MainPanel/EntryPreview/PreviewIcon") as TextureRect
	icon.position = Vector2(5, 6)
	icon.size = preview.size - Vector2(10, 12)


func _add_navigation() -> void:
	var home := UI.title_button(tr("Home"), Rect2(40, 653, 170, 54))
	home.name = "WorldBackHome"
	FarmNav.style_button(home, "home", tr("Home"), 17)
	home.pressed.connect(ScreenRouter.go.bind("hub"))
	add_child(home)
	var next := UI.art_button(tr("Next Day"), Rect2(1040, 653, 200, 54), "night_next_day")
	next.name = "WorldNextDay"
	next.pressed.connect(_on_world_next_day)
	add_child(next)
	for index in range(4):
		var entry: Array = [["Map", "islands"], ["Workshop", "craft"], ["Companions", "creatures"], ["Calendar", "events"]][index]
		var link := UI.title_button(tr(String(entry[0])), Rect2(232 + index * 192, 653, 180, 54))
		link.name = "WorldRoute_%s" % entry[1]
		FarmNav.style_button(link, String(entry[1]), tr(String(entry[0])), 15)
		FarmNav.set_selected(link, section == entry[1])
		link.pressed.connect(ScreenRouter.go.bind(String(entry[1])))
		add_child(link)


func _on_world_next_day() -> void:
	var succeeded := GameState.advance_day()
	feedback = tr("New day. Changes autosaved.") if succeeded else Locale.translate_message(GameState.status)
	_refresh()


func _refresh() -> void:
	if not is_node_ready() or _hud == null: return
	_update_static_labels()
	_update_hud()
	_rebuild_entries()
	_show_details()


func _update_static_labels() -> void:
	get_node("MainPanel/Heading").text = tr(String(HEADINGS.get(section, "Farm workshop")))
	get_node("MainPanel/Subtitle").text = tr(String(SUBHEADINGS.get(section, "")))
	get_node("MainPanel/DetailHeading").text = tr("Your selected companion") if section == "creatures" else tr("Selected island") if section == "islands" else tr("Your next farm goal") if section == "events" else tr("Make it for your farm")
	var home := find_child("WorldBackHome", true, false)
	if home != null: FarmNav.set_caption(home as TextureButton, "Home")
	var next := find_child("WorldNextDay", true, false)
	if next != null: (next.get_child(0) as Label).text = tr("Next Day")
	for entry in [["Map", "islands"], ["Workshop", "craft"], ["Companions", "creatures"], ["Calendar", "events"]]:
		var link := find_child("WorldRoute_%s" % entry[1], true, false)
		if link != null:
			FarmNav.set_caption(link as TextureButton, String(entry[0]))
			FarmNav.set_selected(link as TextureButton, section == entry[1])


func _update_hud() -> void:
	(_hud.get_node("HUD_DaySeasonLabel") as Label).text = tr("Day %d\n%s") % [int(GameState.data.get("day", 1)), tr(GameState.current_season().capitalize())]
	(_hud.get_node("HUD_CoinValue") as Label).text = str(int(GameState.data.get("coins", 0)))
	var energy := _hud.get_node("HUD_EnergyValue") as Label
	energy.text = str(int(GameState.data.get("energy", 0)))
	energy.tooltip_text = tr("Energy: %s / 100") % energy.text
	var dragon := _hud.get_node("HUD_DragonEnergyValue") as Label
	dragon.text = str(GameState.dragon_energy())
	dragon.tooltip_text = tr("Dragon Energy %d") % GameState.dragon_energy()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _paint_button(text: String, minimum: Vector2, active := false, green := false) -> TextureButton:
	var button := TextureButton.new()
	button.custom_minimum_size = minimum
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	_set_button_textures(button, ACTION_ROOT if green or active else BUTTON_ROOT)
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = text
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 24
	caption.offset_right = -24
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", BOLD_FONT)
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_color", Color("fff6d8") if green or active else Color("4a2b19"))
	caption.add_theme_color_override("font_outline_color", Color("432c1d"))
	caption.add_theme_constant_override("outline_size", 1 if green or active else 0)
	button.add_child(caption)
	return button


func _set_button_textures(button: TextureButton, texture_root: String) -> void:
	button.texture_normal = load(texture_root + "default.png")
	button.texture_hover = load(texture_root + "hover.png")
	button.texture_focused = button.texture_hover
	button.texture_pressed = load(texture_root + "pressed.png")
	button.texture_disabled = load(texture_root + "disabled.png")


func _select_group(group: String) -> void:
	var table: Dictionary = GameState.world_config().get(group, {})
	selected_group = group
	# Workshop opens on its actual workbench, rather than a barn upgrade.
	# Availability remains controlled by the live world action requirements.
	selected_id = "alchemy" if group == "buildings" and table.has("alchemy") else String(table.keys()[0]) if not table.is_empty() else ""
	feedback = ""
	get_node("MainPanel/Entries").scroll_vertical = 0
	_rebuild_entries()
	_show_details()
	_update_touch_scroll_controls()


func select_entry(group: String, id: String) -> void:
	if not GameState.world_config().get(group, {}).has(id): return
	if selected_group != group or selected_id != id: feedback = ""
	selected_group = group
	selected_id = id
	_rebuild_entries()
	_show_details()
	_update_touch_scroll_controls()


func _update_touch_scroll_controls() -> void:
	var entries := get_node("MainPanel/Entries") as ScrollContainer
	var up := get_node_or_null("MainPanel/WorldEntriesUp") as TextureButton
	var down := get_node_or_null("MainPanel/WorldEntriesDown") as TextureButton
	if up == null or down == null: return
	var needs_scroll := selected_group != "islands" and entries.get_v_scroll_bar().max_value > entries.size.y + 1.0
	up.visible = needs_scroll
	down.visible = needs_scroll
	up.disabled = entries.scroll_vertical <= 0
	down.disabled = entries.scroll_vertical >= int(entries.get_v_scroll_bar().max_value - entries.size.y - 1.0)


func _entry_texture(group: String, id: String, spec: Dictionary) -> Texture2D:
	match group:
		"islands": return _island_art(id)
		"buildings", "items", "eggs": return _registered_art(id)
		"gardens": return Assets.get_item_texture(String(spec.get("item", id)))
		"recipes": return Assets.get_item_texture(String(spec.get("output", id)))
		"events":
			var rewards: Dictionary = spec.get("items", {})
			return Assets.get_item_texture(String(rewards.keys()[0])) if not rewards.is_empty() else load(ROOT + "/ITEMS/quest.png")
		"creatures":
			var body := BodyArt.texture(id)
			if body != null: return body
			var body_path := "res://assets/approved_world_v1/dragons/" + id + ".png"
			if String(spec.get("kind", "")) == "dragon" and ResourceLoader.exists(body_path): return load(body_path) as Texture2D
			if ANIMAL_ART.has(id):
				if id == "cow":
					var portrait := AtlasTexture.new()
					portrait.atlas = load(String(ANIMAL_ART[id]))
					portrait.region = Rect2(4, 44, 450, 464)
					return portrait
				return load(String(ANIMAL_ART[id])) as Texture2D
			if id in ["water_dragon", "fire_dragon", "ice_dragon"]:
				var atlas := AtlasTexture.new()
				atlas.atlas = load(Assets.DRAGON_INHABITANTS_SHEET)
				var source_region: Rect2 = {"water_dragon": Rect2(694, 70, 286, 392), "fire_dragon": Rect2(1350, 90, 326, 370), "ice_dragon": Rect2(346, 110, 330, 352)}[id]
				atlas.region = source_region.intersection(Rect2(Vector2.ZERO, atlas.atlas.get_size()))
				return atlas
			# Rare dragons use their own authored elemental egg as a collection emblem.
			if String(spec.get("kind", "")) == "dragon": return Assets.get_item_texture(id.replace("_dragon", "_egg"))
			return Assets.get_item_texture(String(spec.get("product", "")))
	return null


func _island_art(id: String) -> Texture2D:
	if _island_art_cache.has(id):
		return _island_art_cache[id] as Texture2D
	if not LANDMARK_ICONS.has(id):
		return null
	var texture := load(ISLAND_ART_ROOT + id + ".png") as Texture2D
	if texture == null:
		return null
	var source := texture.get_image()
	if source == null:
		return texture
	if source.is_compressed() and source.decompress() != OK:
		return texture
	# Trim only transparent padding, measured on the actual imported texture.
	# The authored landmark rectangle, IDs and click targets stay unchanged.
	var used := source.get_used_rect()
	if not used.has_area():
		return texture
	var art := AtlasTexture.new()
	art.atlas = texture
	art.region = Rect2(used)
	_island_art_cache[id] = art
	return art


func _registered_art(id: String) -> Texture2D:
	var texture := Assets.get_item_texture(id)
	if texture == null or not ART_REGIONS.has(id): return texture
	var art := AtlasTexture.new()
	art.atlas = texture
	# The original artwork is 1254px, but these local imports cap textures
	# at 256px. Atlas regions must use imported texture coordinates.
	var original: Rect2 = ART_REGIONS[id]
	var imported_scale: Vector2 = texture.get_size() / Vector2(1254, 1254)
	art.region = Rect2(original.position * imported_scale, original.size * imported_scale)
	return art


func _rebuild_entries() -> void:
	var list := get_node("MainPanel/Entries/EntryList")
	_clear(list)
	var table: Dictionary = GameState.world_config().get(selected_group, {})
	if selected_group == "islands":
		var map := Control.new()
		map.name = "IslandMap"
		map.custom_minimum_size = Vector2(754, 402)
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.clip_contents = true
		list.add_child(map)
		var sea := UI.texture_rect(Assets.BACKGROUNDS["dragon_far"], Rect2(0, 0, 754, 402), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		sea.name = "IslandMapScenery"
		map.add_child(sea)
		var panel_life := PanelSceneryLife.new()
		map.add_child(panel_life)
		panel_life.setup("island_map",sea)
		for id in table:
			var spec: Dictionary = table[id]
			var button := _island_landmark(String(id), spec)
			button.position = MAP_POSITIONS.get(id, Vector2.ZERO)
			map.add_child(button)
	elif selected_group in ["creatures", "eggs", "items", "gardens"]:
		var grid := GridContainer.new()
		grid.name = "PortraitCollection" if selected_group == "creatures" else "IllustratedInventory"
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 9)
		grid.add_theme_constant_override("v_separation", 9)
		list.add_child(grid)
		for id in table: grid.add_child(_portrait_card(String(id), table[id]))
	else:
		for id in table: list.add_child(_entry_button(String(id), table[id]))
	for tab in get_node("MainPanel/Tabs").get_children():
		var selected: bool = String(tab.name) == "Tabs_%s" % selected_group
		var caption_key := ""
		for entry in SECTIONS.get(section, []):
			if String(tab.name) == "Tabs_%s" % entry[0]: caption_key = String(entry[1])
		(tab.get_node("Caption") as Label).text = tr(GameState.current_season().capitalize()) if section == "events" else tr(caption_key)
		var tab_icon_id: String = {"islands": "dragon_altar", "buildings": "alchemy", "gardens": "seed_mint", "recipes": "medicine_fatigue", "items": "stone", "creatures": "animal_feed", "eggs": "water_egg", "events": "seed_carrot"}.get(String(selected_group if selected else String(tab.name).trim_prefix("Tabs_")), "seed_carrot")
		ButtonSkin.apply(tab as TextureButton, {"selected": selected, "font_size": 17, "layout_content": true, "icon_texture": Assets.get_item_texture(tab_icon_id) if Assets.ITEM_ICONS.has(tab_icon_id) else null})
		if selected: get_node("MainPanel/EntryHeading").text = tr("Tap an island to explore") if selected_group == "islands" else tr(caption_key)
	_update_touch_scroll_controls.call_deferred()


func _island_landmark(id: String, spec: Dictionary) -> TextureButton:
	var selected := id == selected_id
	var button := TextureButton.new()
	button.name = "WorldSelect_islands_%s" % id
	button.custom_minimum_size = Vector2(212, 126)
	button.size = Vector2(212, 126)
	button.ignore_texture_size = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	var landmark := UI.texture_rect(_entry_texture("islands", id, spec), Rect2(31, 0, 150, 102))
	landmark.name = "EntryIcon"
	button.add_child(landmark)
	var plaque := UI.texture_rect((ACTION_ROOT if selected else BUTTON_ROOT) + "default.png", Rect2(0, 91, 212, 35), TextureRect.STRETCH_SCALE)
	plaque.name = "LandmarkNamePlaque"
	button.add_child(plaque)
	var caption := UI.label(tr(String(spec.get("name", id))), Rect2(12, 98, 188, 20), 13, Color("fff6d8") if selected else Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "Caption"
	caption.add_theme_font_override("font", BOLD_FONT)
	button.add_child(caption)
	var state := _state_badge(_entry_summary(id, spec), Rect2(146, 5, 62, 22), bool(GameState.world_state().get("unlocked_islands", {}).get(id, false)))
	state.name = "EntryState"
	button.add_child(state)
	button.tooltip_text = tr(String(spec.get("name", id))) + " · " + _entry_summary(id, spec)
	button.set_meta("entry_presentation", "LARGE_AUTHORED_LANDMARK")
	button.pressed.connect(select_entry.bind("islands", id))
	button.mouse_entered.connect(_landmark_hover.bind(landmark, true))
	button.mouse_exited.connect(_landmark_hover.bind(landmark, false))
	return button


func _landmark_hover(landmark: TextureRect, hovered: bool) -> void:
	landmark.modulate = Color(1.1, 1.08, 0.93) if hovered else Color.WHITE


func _state_badge(text: String, rect: Rect2, positive: bool) -> Label:
	var label := UI.label(text, rect, 10, Color("fff7e0"), HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_override("font", BOLD_FONT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("688747") if positive else Color("806749")
	style.set_corner_radius_all(8)
	style.content_margin_left = 5
	style.content_margin_right = 5
	label.add_theme_stylebox_override("normal", style)
	return label


func _portrait_card(id: String, spec: Dictionary) -> TextureButton:
	var selected := id == selected_id
	var button := _paint_button("", Vector2(180, 170), selected)
	button.name = "WorldSelect_%s_%s" % [selected_group, id]
	var icon := UI.texture_rect(_entry_texture(selected_group, id, spec), Rect2(13, 13, 154, 102))
	icon.name = "EntryIcon"
	button.add_child(icon)
	var caption := button.get_node("Caption") as Label
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	caption.position = Vector2(12, 117)
	caption.size = Vector2(156, 25)
	caption.text = tr(String(spec.get("name", id)))
	caption.add_theme_font_size_override("font_size", 13)
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var owned: bool = selected_group == "creatures" and GameState.world_state().get("creatures", {}).has(id)
	var state := _state_badge(_entry_summary(id, spec), Rect2(17, 143, 146, 21), owned)
	state.name = "EntryState"
	button.add_child(state)
	button.tooltip_text = caption.text + " · " + _entry_summary(id, spec)
	button.pressed.connect(select_entry.bind(selected_group, id))
	button.set_meta("entry_presentation", "PORTRAIT_COLLECTION_CARD")
	return button


func _entry_button(id: String, spec: Dictionary, map_pin := false) -> TextureButton:
	var selected := id == selected_id
	var button := _paint_button("", Vector2(106, 84) if map_pin else Vector2(0, 94), selected)
	button.name = "WorldSelect_%s_%s" % [selected_group, id]
	var icon := UI.texture_rect(_entry_texture(selected_group, id, spec), Rect2(40, 5, 26, 24) if map_pin else Rect2(11, 7, 80, 80))
	icon.name = "EntryIcon"
	button.add_child(icon)
	var caption := button.get_node("Caption") as Label
	caption.text = tr(String(spec.get("name", id)))
	caption.offset_left = 6 if map_pin else 99
	caption.offset_right = -6 if map_pin else -22
	caption.offset_top = 29 if map_pin else 20
	caption.offset_bottom = -37 if map_pin else -34
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if map_pin else HORIZONTAL_ALIGNMENT_LEFT
	caption.add_theme_font_size_override("font_size", 11 if map_pin else 16)
	var state := UI.label(_entry_summary(id, spec), Rect2(6, 47, 94, 14) if map_pin else Rect2(99, 54, 251, 21), 10 if map_pin else 13, Color("fff5d6") if selected else Color("765435"), HORIZONTAL_ALIGNMENT_CENTER if map_pin else HORIZONTAL_ALIGNMENT_LEFT)
	state.name = "EntryState"
	button.set_meta("entry_presentation", "MAP_PIN_CREAM_INSET" if map_pin else "ILLUSTRATED_GAME_CARD")
	button.set_meta("status_art_inset", Rect2(6, 44, 94, 20) if map_pin else Rect2(78, 37, 240, 24))
	button.add_child(state)
	button.tooltip_text = tr(String(spec.get("name", id))) + " · " + _entry_summary(id, spec)
	button.pressed.connect(select_entry.bind(selected_group, id))
	_fit_entry_copy(button, map_pin)
	button.resized.connect(_fit_entry_copy.bind(button, map_pin))
	return button


func _fit_entry_copy(button: TextureButton, map_pin: bool) -> void:
	# UIFactory sizes labels before their font override. Godot retains the
	# larger default-font minimum until explicitly resized, even after the
	# smaller glyphs paint correctly. Fit the final localized font first, then
	# reset both label boxes to measured heights inside the painted card.
	var definitions := [
		["Caption", 11 if map_pin else 17, 9 if map_pin else 14, Rect2(6, 29, 94, 18) if map_pin else Rect2(99, 19, 245, 29)],
		["EntryState", 10 if map_pin else 13, 9 if map_pin else 11, Rect2(6, 47, 94, 17) if map_pin else Rect2(99, 55, 245, 22)],
	]
	for definition in definitions:
		var label := button.get_node(String(definition[0])) as Label
		var font := label.get_theme_font("font")
		var font_size := int(definition[1])
		var minimum := int(definition[2])
		var slot: Rect2 = definition[3]
		while font_size > minimum and (font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > slot.size.x or ceilf(font.get_height(font_size)) > slot.size.y):
			font_size -= 1
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if label.get_theme_font_size("font_size") != font_size:
			label.add_theme_font_size_override("font_size", font_size)
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label.set_meta("measured_font_height", font.get_height(font_size))
		label.set_meta("painted_copy_slot", slot)
		var changed := _queue_entry_label_layout.bind(label)
		if not label.minimum_size_changed.is_connected(changed): label.minimum_size_changed.connect(changed)
		if not label.theme_changed.is_connected(changed): label.theme_changed.connect(changed)
		if not label.tree_entered.is_connected(changed): label.tree_entered.connect(changed)
		_queue_entry_label_layout(label)


func _queue_entry_label_layout(label: Label) -> void:
	if bool(label.get_meta("entry_layout_queued", false)): return
	label.set_meta("entry_layout_queued", true)
	_settled_entry_label_box.call_deferred(label)


func _settled_entry_label_box(label: Label) -> void:
	if not is_instance_valid(label) or label.is_queued_for_deletion(): return
	await get_tree().process_frame
	if not is_instance_valid(label) or label.is_queued_for_deletion(): return
	label.set_meta("entry_layout_queued", false)
	var slot: Rect2 = label.get_meta("painted_copy_slot", Rect2())
	var font_size := label.get_theme_font_size("font_size")
	var metric_height := ceilf(label.get_theme_font("font").get_height(font_size))
	# Only geometry changes here. Font/theme/minimum-size notifications queue
	# this setter after Godot reshapes the label, never another font mutation.
	label.reset_size()
	label.position = slot.position
	label.size = Vector2(slot.size.x, metric_height)
	label.set_meta("measured_font_height", metric_height)


func _entry_summary(id: String, _spec: Dictionary) -> String:
	var world := GameState.world_state()
	match selected_group:
		"islands": return tr("Open") if world.get("unlocked_islands", {}).get(id, false) else tr("Locked")
		"buildings": return tr("Level %d") % int(world.get("buildings", {}).get(id, 0))
		"items", "eggs": return tr("Owned: %d") % _count(id)
		"creatures": return tr("In collection") if world.get("creatures", {}).has(id) else tr("Not owned")
		"events":
			if id in world.get("claimed_events", []): return tr("Claimed")
			var stat := String(_spec.get("stat", ""))
			return "%d / %d" % [int(GameState.data.get(stat, world.get("stats", {}).get(stat, 0))), int(_spec.get("target", 1))]
		"gardens":
			var garden: Dictionary = world.get("gardens", {}).get(id, {})
			return tr("Ready to harvest") if garden.get("ready", false) else tr("Growing") if not garden.is_empty() else tr("Ready to plant")
		"recipes": return tr("View recipe")
	return ""


func _text(parent: Node, text: String) -> void:
	var label := Label.new()
	label.name = "DetailText%02d" % parent.get_child_count()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", REGULAR_FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("4a2b19"))
	label.add_theme_constant_override("line_spacing", 1)
	parent.add_child(label)


func _item_name(id: String) -> String:
	return tr(String(GameState.world_config().get("items", {}).get(id, {}).get("name", FarmData.get_inventory_name(id))))


func _table_name(group: String, id: String) -> String:
	return tr(String(GameState.world_config().get(group, {}).get(id, {}).get("name", id.replace("_", " ").capitalize())))


func _count(id: String) -> int:
	if id == "dragon_energy": return GameState.dragon_energy()
	return int(GameState.data.get("inventory", {}).get(id, 0))


func _costs(costs: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in costs: parts.append(tr("%s %d/%d") % [_item_name(String(id)), _count(String(id)), int(costs[id])])
	return ", ".join(parts) if not parts.is_empty() else tr("None")


func _requirement_line(done: bool, label: String, current: int, required: int) -> String:
	return "%s %s: %d/%d" % ["✓" if done else "✗", label, current, required]


func _island_unlock_guide(parent: Node, island_id: String, spec: Dictionary) -> void:
	var world := GameState.world_state()
	if bool(world.get("unlocked_islands", {}).get(island_id, false)):
		_text(parent, UILocale.pair("✓ Đảo đã mở. Bấm Đến đảo để khám phá.", "✓ Island unlocked. Tap Visit island to explore."))
		return
	_text(parent, UILocale.pair("Điều kiện mở khóa — hoàn thành tất cả các dòng:", "Unlock guide — complete every line:"))
	var required_orders := int(spec.get("orders", 0))
	var orders := int(GameState.data.get("orders_done", 0))
	_text(parent, _requirement_line(orders >= required_orders, UILocale.pair("Đơn nông sản", "Farm orders"), orders, required_orders))
	var required_coins := int(spec.get("cost", 0))
	var coins := int(GameState.data.get("coins", 0))
	_text(parent, _requirement_line(coins >= required_coins, UILocale.pair("Xu", "Coins"), coins, required_coins))
	var prerequisite := String(spec.get("requires", ""))
	if not prerequisite.is_empty():
		var prerequisite_open := bool(world.get("unlocked_islands", {}).get(prerequisite, false))
		_text(parent, "%s %s: %s" % ["✓" if prerequisite_open else "✗", UILocale.pair("Đảo tiền đề", "Required island"), _table_name("islands", prerequisite)])
	var materials: Dictionary = spec.get("items", {})
	for item_id in materials:
		var required := int(materials[item_id])
		var owned := _count(String(item_id))
		_text(parent, _requirement_line(owned >= required, _item_name(String(item_id)), owned, required))
	_item_sources(parent, materials)


func _rewards(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in items: parts.append(tr("%s ×%d") % [_item_name(String(id)), int(items[id])])
	return ", ".join(parts) if not parts.is_empty() else tr("None")


func _item_sources(parent: Node, costs: Dictionary) -> void:
	for item_id in costs:
		if _count(String(item_id)) >= int(costs[item_id]): continue
		var source := ItemSource.source(String(item_id))
		if source.is_empty(): continue
		var link := _paint_button(String(source["hint"]), Vector2(0, 72), false, true)
		link.name = "WorldSource_" + String(item_id)
		link.tooltip_text = String(source["hint"])
		var caption := link.get_node("Caption") as Label
		caption.offset_left = 12
		caption.offset_right = -12
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size", 14)
		ButtonSkin.apply(link, {"font_size": 14, "layout_content": true})
		link.pressed.connect(ItemSource.open.bind(String(item_id)))
		parent.add_child(link)


func _action(action: String, id: String, caption: String) -> void:
	var info: Dictionary = GameState.world_action_info(action, id)
	var button := _paint_button(caption, Vector2(0, 38 if section == "islands" else 45 if section == "creatures" else 50), false, true)
	button.name = "WorldAction_%s_%s" % [action, id.replace(":", "_")]
	button.disabled = not bool(info.get("ok", false))
	if not button.disabled: _has_available_action = true
	var label := button.get_node("Caption") as Label
	label.add_theme_font_size_override("font_size", 16)
	label.offset_left = 16
	label.offset_right = -16
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ButtonSkin.apply(button, {"font_size": 14 if section == "islands" else 15 if section == "creatures" else 17, "layout_content": true, "icon_texture": _action_icon(action, id)})
	button.tooltip_text = Locale.translate_message(String(info.get("reason", "")))
	if button.disabled and _blocked_reason.is_empty(): _blocked_reason = button.tooltip_text
	button.pressed.connect(_perform.bind(action, id))
	get_node("MainPanel/Actions").add_child(button)


func _action_icon(action: String, id: String) -> Texture2D:
	var spec: Dictionary = GameState.world_config().get(selected_group, {}).get(id, {})
	var icon_id := id
	match action:
		"gather": icon_id = String(spec.get("gather_item", "stone"))
		"plant_garden": icon_id = String(spec.get("seed", "seed_mint"))
		"harvest_garden": icon_id = String(spec.get("item", id))
		"craft", "claim_craft": icon_id = String(spec.get("output", "medicine"))
		"feed": icon_id = String(spec.get("food", "animal_feed"))
		"collect": icon_id = String(spec.get("product", "egg"))
		"heal": icon_id = "medicine"
		"claim_event": icon_id = "seed_carrot"
		"unlock_island": icon_id = String(LANDMARK_ICONS.get(id, "barn"))
		"water_garden": return Assets.texture(ROOT + "/ITEMS/watering_can.png")
		"pet", "treat": return Assets.texture(ROOT + "/ANIMAL/STATUS_OVERLAYS/happy_cared_heart.png")
		"clean": return Assets.texture(ROOT + "/ANIMAL/STATUS_OVERLAYS/clean_fresh_sparkle.png")
	return Assets.get_item_texture(icon_id) if Assets.ITEM_ICONS.has(icon_id) else null


func _perform(action: String, id: String) -> void:
	var succeeded := GameState.world_action(action, id)
	feedback = Locale.translate_message(GameState.status)
	if succeeded and feedback.is_empty(): feedback = tr("Action complete. Changes autosaved.")
	_update_hud()
	_rebuild_entries()
	_show_details()


func _care_meters(parent: Node, creature: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "CompanionCareMeters"
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	for entry in [["fullness", "Fullness"], ["cleanliness", "Cleanliness"], ["happiness", "Happiness"]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		row.add_child(column)
		_text(column, tr("%s: %d") % [tr(String(entry[1])), int(creature.get(entry[0], 0))])
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(0, 7)
		meter.show_percentage = false
		meter.value = int(creature.get(entry[0], 0))
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("799850")
		fill.set_corner_radius_all(3)
		meter.add_theme_stylebox_override("fill", fill)
		var track := StyleBoxFlat.new()
		track.bg_color = Color("bda580")
		track.set_corner_radius_all(3)
		meter.add_theme_stylebox_override("background", track)
		column.add_child(meter)


func _detail_scenery() -> Texture2D:
	if selected_group == "islands":
		return load(Assets.BACKGROUNDS["dragon_far"]) as Texture2D
	if selected_group == "creatures":
		if selected_id == "duck": return load("res://assets/gdd_closure_v3/environment/duck_pond.png") as Texture2D
		if selected_id == "pig": return load("res://assets/gdd_closure_v3/environment/pig_yard.png") as Texture2D
		if selected_id == "cow": return load("res://assets/gdd_closure_v3/environment/cow_yard.png") as Texture2D
		return load(Assets.ENVIRONMENT_LAYERS["animal"][0]) as Texture2D
	return load(Assets.ENVIRONMENT_LAYERS["shop"][0]) as Texture2D if section == "craft" else load(Assets.BACKGROUNDS["field_select"]) as Texture2D


func _reward_card(texture: Texture2D, text: String) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(110, 82)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := UI.texture_rect(texture, Rect2(28, 1, 56, 53))
	icon.name = "RewardArt"
	card.add_child(icon)
	var caption := UI.label(text, Rect2(1, 57, 108, 29), 12, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "RewardAmount"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(caption)
	return card


func _show_milestone_rewards(spec: Dictionary) -> void:
	var tray := get_node("MainPanel/MilestoneRewardTray") as HBoxContainer
	_clear(tray)
	if int(spec.get("coins", 0)) > 0:
		var coin := AtlasTexture.new()
		coin.atlas = load(ROOT + "/ITEMS/coin.png")
		coin.region = Rect2(27, 91, 205, 206)
		tray.add_child(_reward_card(coin, str(int(spec.get("coins", 0)))))
	var items: Dictionary = spec.get("items", {})
	for id in items:
		tray.add_child(_reward_card(Assets.get_item_texture(String(id)), _item_name(String(id)) + " ×" + str(int(items[id]))))


func _show_details() -> void:
	var parent := get_node("MainPanel/Details/DetailContent")
	_clear(parent)
	_clear(get_node("MainPanel/Actions"))
	_blocked_reason = ""
	_has_available_action = false
	get_node("MainPanel/Details").scroll_vertical = 0
	var spec: Dictionary = GameState.world_config().get(selected_group, {}).get(selected_id, {})
	var world := GameState.world_state()
	get_node("MainPanel/EntryName").text = tr(String(spec.get("name", selected_id)))
	var full_description := String(spec.get("description", spec.get("effect", "")))
	get_node("MainPanel/EntryDescription").text = tr(String(DISPLAY_DESCRIPTIONS.get(selected_group + ":" + selected_id, full_description)))
	get_node("MainPanel/EntryDescription").tooltip_text = tr(full_description)
	get_node("MainPanel/EntryStatus").text = _entry_summary(selected_id, spec)
	get_node("MainPanel/EntryPreview/PreviewIcon").texture = _entry_texture(selected_group, selected_id, spec)
	get_node("MainPanel/EntryPreview/PreviewScenery").texture = _detail_scenery()
	get_node("MainPanel/EntryPreview/PreviewScenery").visible = false
	var event_view := selected_group == "events"
	get_node("MainPanel/MilestoneProgress").visible = event_view
	get_node("MainPanel/MilestoneRewardTray").visible = event_view
	get_node("MainPanel/Details").visible = not event_view
	(get_node("MainPanel/EntryStatus") as Label).add_theme_font_size_override("font_size", 14 if event_view else 15 if section == "islands" else 16)
	(get_node("MainPanel/EntryStatus") as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if event_view else HORIZONTAL_ALIGNMENT_LEFT
	var actions := get_node("MainPanel/Actions") as GridContainer
	actions.columns = 3
	match selected_group:
		"islands":
			get_node("MainPanel/EntryStatus").text = tr("%s · Orders %d/%d") % [_entry_summary(selected_id, spec), int(GameState.data.get("orders_done", 0)), int(spec.get("orders", 0))]
			_island_unlock_guide(parent, selected_id, spec)
			_text(parent, tr("After opening: forage %s ×%d") % [_item_name(String(spec.get("gather_item", ""))), int(spec.get("gather_amount", 1))])
			actions.columns = 2
			_action("unlock_island", selected_id, tr("Unlock island"))
			var visit := _paint_button(UILocale.pair("Đến đảo", "Visit island"), Vector2(0, 38), false, true)
			visit.name = "WorldVisit_" + selected_id
			visit.disabled = not bool(world.get("unlocked_islands", {}).get(selected_id, false))
			visit.tooltip_text = tr("Unlock this island first.") if visit.disabled else tr("Visit the island")
			ButtonSkin.apply(visit, {"font_size": 14, "layout_content": true, "icon_texture": _entry_texture("islands", selected_id, spec)})
			visit.pressed.connect(ScreenRouter.visit_island.bind(selected_id))
			get_node("MainPanel/Actions").add_child(visit)
			if selected_id in ["main", "dragon"]:
				_action("gather", selected_id, UILocale.pair("Thu thập", "Gather"))
		"buildings":
			var level := int(world.get("buildings", {}).get(selected_id, 0))
			var maximum := int(spec.get("max_level", 1))
			get_node("MainPanel/EntryStatus").text = tr("Level %d / %d · Fully upgraded") % [level, maximum] if level >= maximum else tr("Level %d / %d") % [level, maximum]
			_text(parent, tr("Next upgrade: %d coins · Materials: %s") % [int(spec.get("cost", 0)) * (level + 1), _costs(spec.get("items", {}))] if level < maximum else tr("Your farm enjoys this building's benefits."))
			_text(parent, tr("Island: %s · Orders: %d") % [_table_name("islands", String(spec.get("island", "main"))), int(spec.get("orders", 0))])
			if level < maximum: _item_sources(parent, spec.get("items", {}))
			_action("build", selected_id, tr("Build / upgrade"))
		"gardens":
			var garden: Dictionary = world.get("gardens", {}).get(selected_id, {})
			get_node("MainPanel/EntryStatus").text = tr("Growth: %d/%d days · Watered: %s") % [int(garden.get("growth", 0)), int(spec.get("days", 3)), tr("Yes") if garden.get("watered_today", false) else tr("No")]
			_text(parent, tr("Seeds: %s ×%d · Favorite season: %s") % [_item_name(String(spec.get("seed", ""))), _count(String(spec.get("seed", ""))), tr(String(spec.get("season", "spring")).capitalize())])
			_text(parent, tr("Island: %s") % _table_name("islands", String(spec.get("island", "botanical"))))
			_action("plant_garden", selected_id, tr("Plant herb"))
			_action("water_garden", selected_id, tr("Water herb"))
			_action("harvest_garden", selected_id, tr("Harvest herb"))
		"recipes":
			get_node("MainPanel/EntryDescription").text = tr("Makes: %s ×%d\nWorkbench: %s") % [_item_name(String(spec.get("output", ""))), int(spec.get("amount", 1)), _table_name("buildings", String(spec.get("building", "alchemy")))]
			get_node("MainPanel/EntryStatus").text = tr("Time: %d day(s) · Recipe cost: %d coins") % [int(spec.get("days", 0)), int(spec.get("coins", 0))]
			_text(parent, tr("Ingredients: %s") % _costs(spec.get("ingredients", {})))
			_item_sources(parent, spec.get("ingredients", {}))
			for task in world.get("craft_queue", []):
				if task.get("recipe", "") == selected_id: _text(parent, tr("Crafting: %d/%d days · Finished: %s") % [int(task.get("progress", 0)), int(task.get("required", 1)), tr("Yes") if task.get("ready", false) else tr("No")])
			actions.columns = 2
			_action("craft", selected_id, tr("Craft recipe"))
			_action("claim_craft", selected_id, tr("Collect finished recipe"))
		"items":
			get_node("MainPanel/EntryStatus").text = tr("%s · Owned: %d") % [tr(String(spec.get("group", ""))), _count(selected_id)]
			_text(parent, tr("Buy %d for %d coins") % [int(spec.get("amount", 1)), int(spec.get("price", 0))] if int(spec.get("price", 0)) > 0 else tr("Obtain through farming, gathering or crafting."))
			if int(spec.get("sell", 0)) > 0: _text(parent, tr("Sell one: %d coins") % int(spec["sell"]))
			_action("buy_item", selected_id, tr("Buy supplies"))
			_action("sell_item", selected_id, tr("Sell one"))
			if selected_id == "ancient_fruit": _action("convert_fruit", selected_id, tr("Make Dragon Energy"))
			if selected_id == "dragon_energy": _action("dragon_blessing", selected_id, tr("Altar blessing"))
		"creatures":
			var creature: Dictionary = world.get("creatures", {}).get(selected_id, {})
			var utility := String(spec.get("utility", ""))
			if not creature.is_empty():
				var disease := String(creature.get("disease", ""))
				get_node("MainPanel/EntryStatus").text = tr("%s · Daily help: %s") % [tr("Healthy") if disease.is_empty() else tr(disease.capitalize()), tr(utility.capitalize())]
				_care_meters(parent, creature)
			else:
				_text(parent, tr("Adopt: %d coins · Orders: %d · Island: %s") % [int(spec.get("cost", 0)), int(spec.get("orders", 0)), _table_name("islands", String(spec.get("island", "main")))])
			_text(parent, tr("Food: %s · Gift: %s ×%d") % [_item_name(String(spec.get("food", ""))), _item_name(String(spec.get("product", ""))), int(creature.get("products_ready", 0))])
			var disease := String(creature.get("disease", ""))
			if not disease.is_empty():
				_text(parent, UILocale.pair("Dùng nút Trị bệnh với %s.", "Use Treat disease with %s.") % _item_name("medicine_" + disease))
				_item_sources(parent, {"medicine_" + disease: 1})
			actions.columns = 4 if not creature.is_empty() else 2
			for entry in [["adopt", "Adopt companion"], ["feed", "Feed"], ["clean", "Clean"], ["pet", "Pet"], ["collect", "Collect product"], ["heal", "Treat disease"], ["treat", "Give Dragon Cake"], ["assign_utility", "Assign help"], ["unassign_utility", "Rest companion"]]:
				if String(entry[0]) == "adopt" and not creature.is_empty(): continue
				if String(entry[0]) != "adopt" and creature.is_empty(): continue
				_action(String(entry[0]), selected_id, tr(String(entry[1])))
		"eggs":
			get_node("MainPanel/EntryDescription").text = tr("Hatches: %s · %d days") % [_table_name("creatures", String(spec.get("species", ""))), int(spec.get("days", 1))]
			get_node("MainPanel/EntryStatus").text = tr("Owned eggs: %d") % _count(selected_id)
			_text(parent, tr("Cost: %d coins + %d Dragon Energy") % [int(spec.get("cost", 0)), int(spec.get("energy_cost", 0))])
			var incubator: Dictionary = world.get("incubators", {}).get(selected_id, {})
			if not incubator.is_empty(): _text(parent, tr("Incubation: %d/%d days · Ready: %s") % [int(incubator.get("progress", 0)), int(incubator.get("required", 1)), tr("Yes") if incubator.get("ready", false) else tr("No")])
			_action("buy_egg", selected_id, tr("Buy egg"))
			_action("incubate", selected_id, tr("Start incubation"))
			_action("claim_hatch", selected_id, tr("Hatch ready egg"))
		"events":
			var stat := String(spec.get("stat", ""))
			var progress := int(GameState.data.get(stat, world.get("stats", {}).get(stat, 0)))
			get_node("MainPanel/EntryStatus").text = tr("Progress: %d / %d · Season: %s") % [progress, int(spec.get("target", 1)), tr(String(spec.get("season", "Any")).capitalize())]
			var meter := get_node("MainPanel/MilestoneProgress") as ProgressBar
			meter.max_value = maxi(1, int(spec.get("target", 1)))
			meter.value = mini(progress, int(meter.max_value))
			_show_milestone_rewards(spec)
			get_node("MainPanel/MilestoneRewardTray").tooltip_text = tr("Reward: %d coins + %s") % [int(spec.get("coins", 0)), _rewards(spec.get("items", {}))]
			if spec.has("ingredients"):
				get_node("MainPanel/EntryDescription").text += "\n" + tr("Delivery: %s") % _costs(spec.get("ingredients", {}))
			actions.columns = 2
			_action("claim_event", selected_id, tr("Collect reward"))
	var message := get_node("MainPanel/Feedback") as Label
	message.text = Locale.translate_message(feedback) if not feedback.is_empty() else _blocked_reason if not _has_available_action and not _blocked_reason.is_empty() else tr("Ready when you are. Your progress is saved automatically.")
	message.tooltip_text = message.text
	message.add_theme_color_override("font_color", Color("527337") if not feedback.is_empty() else Color("785136"))
