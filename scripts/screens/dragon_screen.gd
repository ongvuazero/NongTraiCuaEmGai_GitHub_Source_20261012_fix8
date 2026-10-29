extends BaseScreen

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const GameSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const WorldPresenter = preload("res://scripts/ui/dragon_world_presenter.gd")
const ShopSurface = preload("res://scripts/ui/dragon_shop_surface.gd")
const SECTION_NAMES := ["Lò ấp trứng", "Nhà trẻ", "Sân chơi", "Shop Rồng", "Kho Rồng", "Sách Rồng"]
const SECTION_ICONS := ["egg", "nursery", "play", "shop", "storage", "book"]
# A body click and a section tab can share care art, but only a tab click toggles
# that same tab closed. This is the sole transient presentation surface state.
enum Surface { CLOSED, SECTION, SECTION_CARE, BODY_CARE, SHOP }
var active_section := 0
var selection_index := 0
var feedback := ""
var _primary_spec: Dictionary = {}
var _secondary_spec: Dictionary = {}
var _surface := Surface.CLOSED
var live_world
var dragon_shop


func build() -> void:
	set_meta("TRUE_WYSIWYG_V2", "VISUAL_REVIEW_REQUIRED")
	set_meta("UI_IN_PLACE_REFRESH", true)
	bind_button("DragonBackToHub", ScreenRouter.back_home)
	bind_standard_left_navigation()
	var panel := find_child("ComingSoonPanel", true, false) as Control
	_surface = Surface.SECTION if panel != null and panel.visible else Surface.CLOSED
	for index in range(SECTION_NAMES.size()): bind_button("DragonNav_%d" % index, _select_section.bind(index))
	_build_section_controls()
	_present_navigation()
	_build_live_world()
	_build_dragon_shop()
	_refresh()


func _build_live_world() -> void:
	(find_child("Background", true, false) as TextureRect).texture = load("res://assets/approved_world_v1/ui/dragon_environment_matte_v3.png") as Texture2D
	for name in ["HatcheryPortalVisual", "DragonPortalIdentity"]:
		var legacy := find_child(name, true, false) as CanvasItem
		if legacy != null: legacy.hide()
	var panel := find_child("ComingSoonPanel", true, false) as Control
	# Keep authored section controls, but move their visual block clear of bodies.
	if panel != null:
		panel.position = Vector2(934, 160)
		panel.set_meta("mobile_touch_rows", true)
		# Replace the summary's backdrop; retain native text/buttons and input.
		# Content bounds are calibrated below. The source has no baked UI/text.
		var source := load("res://assets/approved_world_v1/ui/dragon_section_frame_matte_v1.png") as Texture2D
		var frame := AtlasTexture.new()
		frame.atlas = source
		var factor := source.get_size() / Vector2(1421, 1107)
		frame.region = Rect2(Vector2(28, 19) * factor, Vector2(1379, 1080) * factor)
		frame.filter_clip = true
		var style := StyleBoxTexture.new()
		style.texture = frame
		panel.add_theme_stylebox_override("panel", style)
		# The new timber/leaf rim has a smaller usable interior. One measured
		# manifest keeps title and native actions clear of that art in every tab.
		for entry in [["ComingSoonTitle", "section_title"], ["ComingSoonMessage", "section_message"], ["DragonSectionPrimary", "section_primary"], ["DragonSectionSecondary", "section_secondary"], ["DragonSelectionCycle", "section_cycle"]]:
			var control := panel.find_child(entry[0], true, false) as Control
			if control == null: continue
			var rect := WorldPresenter.layout_rect(entry[1])
			control.position = rect.position - panel.position
			control.size = rect.size
		(find_child("ComingSoonTitle", true, false) as Label).add_theme_font_size_override("font_size", 20)
		(find_child("ComingSoonMessage", true, false) as Label).add_theme_font_size_override("font_size", 15)
	var map_access := find_child("DragonIslandAccess", true, false) as TextureButton
	if map_access != null:
		map_access.position = Vector2(265, 659)
		map_access.size = Vector2(235, 47)
		# Keep the original key: two legacy VI aliases share different EN casing.
		# The navigation presenter owns translation and in-place locale refresh.
		FarmNav.style_button(map_access, "islands", "Island map", 17)
	var home := find_child("DragonBackToHub", true, false) as Control
	if home != null:
		home.position = Vector2(20, 640)
		home.size = Vector2(230, 63)
	for name in ["DragonInfoPanel", "DragonVisual01", "DragonVisual02", "DragonVisual03", "DragonVisual04", "DragonVisual05", "Dragon02Shadow", "Dragon03Shadow", "Dragon04Shadow", "Dragon05Shadow"]:
		var old := find_child(name, true, false) as CanvasItem
		if old != null: old.hide()
	var farmer := find_child("FarmerVisual", true, false) as Control
	if farmer != null:
		var rect := WorldPresenter.layout_rect("farmer")
		farmer.position = rect.position
		farmer.size = rect.size
		var source := load(ROOT + "/ANIMATION/FARMER/idle/frame_01.png") as Texture2D
		var trimmed := AtlasTexture.new()
		trimmed.atlas = source
		var factor := source.get_size() / Vector2(384, 540)
		trimmed.region = Rect2(Vector2(100, 14) * factor, Vector2(240, 515) * factor)
		(farmer as TextureRect).texture = trimmed
	var cat := find_child("CatVisual", true, false) as Control
	if cat != null:
		cat.position = Vector2(760, 545)
		cat.size = Vector2(53, 65)
		# The original PNG is a sheet slice containing neighboring cat fragments.
		# Measured central alpha silhouette: [124,69,264,415] on 439x514.
		var source := load(ROOT + "/CHARACTERS/CAT/calico_cat_sitting.png") as Texture2D
		var isolated := AtlasTexture.new()
		isolated.atlas = source
		var factor := source.get_size() / Vector2(439, 514)
		isolated.region = Rect2(Vector2(119, 64) * factor, Vector2(274, 425) * factor)
		isolated.filter_clip = true
		(cat as TextureRect).texture = isolated
		cat.set_meta("source_sprite_region", [119, 64, 274, 425])
	live_world = WorldPresenter.new()
	live_world.name = "LiveDragonWorld"
	add_child(live_world)
	live_world.incubator_selected.connect(_open_world_nest)
	live_world.care_opened.connect(_on_care_opened)
	live_world.care_closed.connect(_on_care_closed)
	var next := UI.art_button(tr("Ngày mới"), Rect2(28, 575, 202, 54), "night_next_day")
	next.name = "DragonWorldNextDay"
	next.pressed.connect(func() -> void: GameState.advance_day(); _refresh())
	add_child(next)


func _open_world_nest(egg_id: String) -> void:
	active_section = 0
	_set_surface(Surface.SECTION)
	var ids := _section_ids(_world_config(), _world_state().get("creatures", {}))
	selection_index = maxi(0, ids.find(egg_id))
	feedback = ""
	_refresh()


func _build_dragon_shop() -> void:
	dragon_shop = ShopSurface.new()
	dragon_shop.name = "DragonShopSurface"
	add_child(dragon_shop)
	dragon_shop.closed.connect(close_top_presentation)
	dragon_shop.hatchery_requested.connect(_select_section.bind(0))
	dragon_shop.hide()


func close_top_presentation() -> bool:
	if _surface == Surface.CLOSED: return false
	feedback = ""
	_set_surface(Surface.CLOSED)
	_refresh_dragon_section()
	return true


func _set_surface(surface: int) -> void:
	_surface = surface
	_apply_surface()


func _apply_surface() -> void:
	var panel := find_child("ComingSoonPanel", true, false) as Control
	if panel != null: panel.visible = _surface == Surface.SECTION
	if dragon_shop != null: dragon_shop.visible = _surface == Surface.SHOP
	if live_world != null and _surface in [Surface.CLOSED, Surface.SECTION, Surface.SHOP]:
		live_world.close_care(false)
	for index in range(SECTION_NAMES.size()):
		var button := find_child("DragonNav_%d" % index, true, false) as TextureButton
		if button != null:
			var selected := _surface in [Surface.SECTION, Surface.SECTION_CARE, Surface.SHOP] and index == active_section
			FarmNav.set_selected(button, selected)
			var caption := tr(SECTION_NAMES[index])
			FarmNav.set_caption(button, "✓ " + caption if selected and index in [1, 2] else caption)
	if panel != null and panel.visible: preload("res://scripts/ui/mobile_runtime.gd").request_control_layout(panel)


func _on_care_opened() -> void:
	if _surface == Surface.SECTION_CARE and active_section in [1, 2]:
		var ids := _section_ids(_world_config(), _world_state().get("creatures", {}))
		selection_index = maxi(0, ids.find(live_world.selected_id))
		_set_surface(Surface.SECTION_CARE)
	else:
		live_world.set_care_mode("body")
		_set_surface(Surface.BODY_CARE)
	_refresh_dragon_section()


func _on_care_closed() -> void:
	_set_surface(Surface.CLOSED)
	_refresh_dragon_section()


func _build_section_controls() -> void:
	# Scene-owned geometry and action art survive refresh; shared navigation
	# presentation is applied once without changing parent screen layout.
	bind_button("DragonSectionPrimary", _perform_primary)
	bind_button("DragonSectionSecondary", _perform_secondary)
	bind_button("DragonSelectionCycle", _cycle_selection)
	bind_button("DragonIslandAccess", ScreenRouter.go.bind("islands"))


func _present_navigation() -> void:
	FarmNav.style_logo(find_child("Logo", true, false) as TextureRect)
	for index in range(SECTION_NAMES.size()):
		var button := find_child("DragonNav_%d" % index, true, false) as TextureButton
		FarmNav.style_button(button, String(SECTION_ICONS[index]), tr(SECTION_NAMES[index]))
	FarmNav.style_button(find_child("DragonBackToHub", true, false) as TextureButton, "home", tr("Trang trại"), 18)


func _refresh() -> void:
	bind_top_hud()
	for index in range(SECTION_NAMES.size()):
		FarmNav.set_caption(find_child("DragonNav_%d" % index, true, false) as TextureButton, String(SECTION_NAMES[index]))
	FarmNav.set_caption(find_child("DragonBackToHub", true, false) as TextureButton, "Trang trại")
	_refresh_dragon_section()


func _select_section(index: int) -> void:
	var next_section := clampi(index, 0, SECTION_NAMES.size() - 1)
	var toggling_closed := next_section == active_section and _surface in [Surface.SECTION, Surface.SECTION_CARE, Surface.SHOP]
	active_section = next_section
	selection_index = 0
	feedback = ""
	if live_world != null and active_section in [1, 2]:
		var care_ids := _section_ids(_world_config(), _world_state().get("creatures", {}))
		selection_index = maxi(0, care_ids.find(live_world.selected_id))
		live_world.set_care_mode("nursery" if active_section == 1 else "playground")
	if live_world != null: live_world.close_care(false)
	if toggling_closed:
		_set_surface(Surface.CLOSED)
	else:
		var world := _world_state()
		var ids := _section_ids(_world_config(), world.get("creatures", {}))
		var has_care := bool(world.get("unlocked_islands", {}).get("dragon", false)) and active_section in [1, 2] and not ids.is_empty()
		_set_surface(Surface.SHOP if active_section == 3 else Surface.SECTION_CARE if has_care else Surface.SECTION)
	_refresh_dragon_section()
	# Opening is an explicit navigation transition, never a side effect of refresh.
	if _surface == Surface.SECTION_CARE and live_world != null:
		var care_ids := _section_ids(_world_config(), _world_state().get("creatures", {}))
		if not care_ids.is_empty(): live_world.select_species(String(care_ids[selection_index]))


func _refresh_dragon_section() -> void:
	var world := _world_state()
	var config := _world_config()
	var unlocked := bool(world.get("unlocked_islands", {}).get("dragon", false))
	var creatures: Dictionary = world.get("creatures", {})
	var title := find_child("ComingSoonTitle", true, false) as Label
	var message := find_child("ComingSoonMessage", true, false) as Label
	if title != null:
		title.text = tr(SECTION_NAMES[active_section]).to_upper()
		title.add_theme_font_override("font", LocaleFonts.for_text(title.text, LocaleFonts.semibold()))
		var size := 20
		while size > 18 and title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 272:
			size -= 1
		title.add_theme_font_size_override("font_size", size)
		title.tooltip_text = title.text
	var selection := _section_ids(config, creatures)
	if not selection.is_empty(): selection_index = posmod(selection_index, selection.size())
	var selected_id := String(selection[selection_index]) if not selection.is_empty() else ""
	var summary := ""
	_primary_spec = {}
	_secondary_spec = {}
	if not unlocked:
		summary = tr("900 xu + 1 Long Quả Cổ\nCần hoàn thành 3 đơn hàng.\nTiến độ: %d / 3 đơn") % int(GameState.data.get("orders_done", 0))
		if active_section in [1, 2]:
			var purpose := _care_purpose()
			summary = purpose + "\n" + UILocale.pair("900 xu + 1 Long Quả Cổ\nĐơn hàng: %d / 3", "900 coins + 1 Ancient Fruit\nOrders: %d / 3") % int(GameState.data.get("orders_done", 0))
		_primary_spec = _spec("Mở Đảo", "unlock_island", "dragon")
		_secondary_spec = _route_spec("Xem các đảo", "islands")
	else:
		match active_section:
			0:
				var egg: Dictionary = config.get("eggs", {}).get(selected_id, {})
				var incubator: Dictionary = world.get("incubators", {}).get(selected_id, {})
				var egg_count := int(GameState.data.get("inventory", {}).get(selected_id, 0))
				if not incubator.is_empty():
					summary = tr("%s\nẤp: %d / %d ngày\n%s") % [tr(String(egg.get("name", selected_id))), int(incubator.get("progress", 0)), int(incubator.get("required", 1)), tr("Sẵn sàng đón rồng!") if bool(incubator.get("ready", false)) else tr("Qua ngày để trứng phát triển.")]
					_primary_spec = _spec("Đón rồng", "claim_hatch", selected_id)
				else:
					summary = tr("%s · %d xu\nTrứng trong Kho: %d\nThời gian ấp: %d ngày") % [tr(String(egg.get("name", selected_id))), int(egg.get("cost", 0)), egg_count, int(egg.get("days", 0))]
					_primary_spec = _spec("Ấp trứng" if egg_count > 0 else "Mua trứng", "incubate" if egg_count > 0 else "buy_egg", selected_id)
				_secondary_spec = _spec("Ngày mới", "advance_day", "")
			1, 2:
				if selected_id.is_empty():
					summary = _care_purpose() + "\n" + UILocale.pair("Chưa có Rồng. Mua và ấp trứng\ntại Lò ấp để bắt đầu.", "No dragon yet. Buy and incubate\nan egg at the Egg Incubator.")
					_primary_spec = {"caption": "Lò ấp", "section": 0}
					_secondary_spec = _route_spec("Bộ sưu tập", "creatures")
				else:
					var definition: Dictionary = config.get("creatures", {}).get(selected_id, {})
					var creature: Dictionary = creatures.get(selected_id, {})
					summary = tr("%s\nNo %d · Sạch %d · Vui %d\n%s") % [tr(String(definition.get("name", selected_id))), int(creature.get("fullness", 0)), int(creature.get("cleanliness", 0)), int(creature.get("happiness", 0)), tr("Sức khỏe tốt") if String(creature.get("disease", "")).is_empty() else tr("Cần thuốc: %s") % tr(String(creature.get("disease", "")))]
					_primary_spec = _spec("Cho ăn" if active_section == 1 else "Vuốt ve", "feed" if active_section == 1 else "pet", selected_id)
					_secondary_spec = _spec("Dọn dẹp" if active_section == 1 else "Thu Long Khí", "clean" if active_section == 1 else "collect", selected_id)
			3:
				# The native Shop content owns food/remedy cards and transactions.
				# This summary surface is never opened for the Shop section.
				pass
			4:
				summary = tr("Long Khí: %d · Long Mạch: %d\nMỗi ngày: 5 Long Khí → 20 năng lượng.\nVật phẩm nằm trong Kho chung.") % [GameState.dragon_energy(), int(world.get("long_vein", 0))]
				_primary_spec = _route_spec("Mở Kho", "storage")
				_secondary_spec = _spec("Nhận phước", "dragon_blessing", "dragon_energy")
			5:
				var definition: Dictionary = config.get("creatures", {}).get(selected_id, {})
				var description := tr(String(definition.get("description", "")))
				summary = tr("%s · %s\nHỗ trợ: %s\n%s") % [tr(String(definition.get("name", selected_id))), tr("Đã sở hữu") if creatures.has(selected_id) else tr("Chưa sở hữu"), _utility_name(String(definition.get("utility", ""))), description]
				_primary_spec = _spec("Gán utility", "assign_utility", selected_id)
				_secondary_spec = _route_spec("Sưu tập", "creatures")
	if message != null:
		message.text = summary
		message.add_theme_font_override("font", LocaleFonts.for_text(summary, LocaleFonts.regular()))
		message.tooltip_text = summary
		_layout_section_copy(message)
		message.visible = feedback.is_empty()
	_update_action("DragonSectionPrimary", _primary_spec)
	_update_action("DragonSectionSecondary", _secondary_spec)
	var cycle := find_child("DragonSelectionCycle", true, false) as BaseButton
	if cycle != null:
		cycle.visible = unlocked and active_section != 3 and selection.size() > 1
		var caption := cycle.get_node_or_null("Caption") as Label
		if caption != null: caption.text = tr("Lựa chọn tiếp theo  (%d / %d)") % [selection_index + 1, selection.size()]
		GameSkin.apply(cycle as TextureButton, {"font_size": 14, "layout_content": true})
	var status_label := find_child("DragonActionFeedback", true, false) as Label
	if status_label != null:
		status_label.text = UILocale.translate_message(feedback)
		status_label.tooltip_text = status_label.text
		status_label.visible = not feedback.is_empty()
	_refresh_owned_dragon_info(config, creatures, selected_id)
	_refresh_owned_art(creatures, unlocked)
	if live_world != null:
		live_world.refresh(selected_id if _surface == Surface.SECTION_CARE else "")
	if dragon_shop != null: dragon_shop.refresh_surface()
	if _surface == Surface.SECTION_CARE and (not unlocked or selected_id.is_empty()):
		_surface = Surface.SECTION
	_apply_surface()


func _layout_section_copy(message: Label) -> void:
	# Every section contains functional information, including Storage exchange
	# costs. Preserve all lines at a readable size and grow the paper/actions.
	var panel := find_child("ComingSoonPanel", true, false) as Control
	if panel == null: return
	var title := find_child("ComingSoonTitle", true, false) as Label
	var title_rect := WorldPresenter.layout_rect("section_title")
	# The ornament covers the leftmost wood edge. Put the text on the clear
	# timber, using cream ink instead of dark-on-dark panel copy.
	title_rect.position.x += 24
	title_rect.size.x -= 24
	if title != null:
		title.add_theme_font_size_override("font_size",18)
		title.add_theme_color_override("font_color",Color("fff1da"))
		title.add_theme_color_override("font_outline_color",Color("4a2b19"))
		title.add_theme_constant_override("outline_size",2)
		title.tooltip_text = title.text
	var title_extra := maxf(0.0, title.get_minimum_size().y - title_rect.size.y) if title != null else 0.0
	if title != null:
		title.position = title_rect.position - panel.position
		title.size = title_rect.size + Vector2(0, title_extra)
	var rect := WorldPresenter.layout_rect("section_message")
	message.position = rect.position - panel.position + Vector2(0, title_extra)
	message.size = rect.size
	message.max_lines_visible = -1
	message.clip_contents = true
	# Label's actual shaping includes wrap mode and theme line spacing; generic
	# Font multiline measurement can undercount a line in this native control.
	var measured := Vector2(rect.size.x, message.get_minimum_size().y)
	var copy_extra := maxf(0.0, measured.y + 6.0 - rect.size.y)
	var extra := title_extra + copy_extra
	message.size.y = rect.size.y + copy_extra
	# Full-width stacked actions preserve natural translated verbs. Half-width
	# buttons were silently cutting Open Storage / Assign Utility in ten locales.
	panel.size.y = 263.0 + extra + 42.0
	for entry in [["DragonSectionPrimary", "section_primary"], ["DragonSectionSecondary", "section_secondary"], ["DragonSelectionCycle", "section_cycle"]]:
		var control := panel.find_child(entry[0], true, false) as Control
		if control != null:
			var bounds := WorldPresenter.layout_rect(entry[1])
			if entry[0] == "DragonSectionPrimary": bounds.size.x = 294
			elif entry[0] == "DragonSectionSecondary": bounds = Rect2(WorldPresenter.layout_rect("section_primary").position + Vector2(0, 42), Vector2(294, 38))
			else: bounds.position.y += 42
			control.position = bounds.position - panel.position + Vector2(0.0, extra)
			control.size = bounds.size
	var status_label := find_child("DragonActionFeedback", true, false) as Label
	if status_label != null:
		status_label.position = message.position
		status_label.size = message.size
	panel.set_meta("book_copy_measured", measured)
	panel.set_meta("book_copy_complete", measured.y <= message.size.y)
	panel.set_meta("section_copy_complete", measured.y <= message.size.y)
	panel.set_meta("section_copy_measured", measured)


func _section_ids(config: Dictionary, creatures: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if active_section == 0:
		for egg_id in config.get("eggs", {}): ids.append(String(egg_id))
	elif active_section == 3:
		for creature_id in config.get("creatures", {}):
			var definition: Dictionary = config["creatures"][creature_id]
			if String(definition.get("kind", "")) == "dragon":
				var food_id := String(definition.get("food", ""))
				if not food_id.is_empty() and food_id not in ids: ids.append(food_id)
	elif active_section in [1, 2, 5]:
		for creature_id in config.get("creatures", {}):
			var definition: Dictionary = config["creatures"][creature_id]
			if String(definition.get("kind", "")) == "dragon" and (active_section == 5 or creatures.has(creature_id)):
				ids.append(String(creature_id))
	return ids


func _refresh_owned_dragon_info(config: Dictionary, creatures: Dictionary, selected_id: String) -> void:
	var panel := find_child("DragonInfoPanel", true, false) as Control
	if panel != null: panel.hide()


func _refresh_owned_art(creatures: Dictionary, unlocked: bool) -> void:
	# Legacy unmapped atlas stays hidden. LiveDragonWorld owns the eight explicit
	# species-to-source bindings and native body input, without gameplay state.
	for index in range(1, 5):
		var visual := find_child("DragonVisual%02d" % index, true, false) as CanvasItem
		if visual != null: visual.visible = false
	var water_visual := find_child("DragonVisual05", true, false) as CanvasItem
	if water_visual != null: water_visual.visible = false
	for shadow_name in ["Dragon02Shadow", "Dragon03Shadow", "Dragon04Shadow"]:
		var shadow := find_child(shadow_name, true, false) as CanvasItem
		if shadow != null: shadow.visible = false
	var water_shadow := find_child("Dragon05Shadow", true, false) as CanvasItem
	if water_shadow != null: water_shadow.visible = false


func _spec(caption: String, action: String, target_id: String) -> Dictionary:
	return {"caption": caption, "action": action, "id": target_id}


func _route_spec(caption: String, route: String) -> Dictionary:
	return {"caption": caption, "route": route}


func _update_action(node_name: String, specification: Dictionary) -> void:
	var button := find_child(node_name, true, false) as BaseButton
	if button == null: return
	var caption := button.get_node_or_null("Caption") as Label
	if caption != null: caption.text = tr(String(specification.get("caption", "")))
	var info := _action_info(specification)
	CardState.apply_action(button, bool(info.get("ok", false)), UILocale.translate_message(String(info.get("reason", ""))))
	GameSkin.apply(button as TextureButton, {"font_size": 16, "layout_content": true})


func _action_info(specification: Dictionary) -> Dictionary:
	if specification.is_empty(): return {"ok": false, "reason": "Chưa có hành động phù hợp."}
	if specification.has("route") or specification.has("section") or String(specification.get("action", "")) == "advance_day":
		return {"ok": true, "reason": String(specification.get("caption", ""))}
	if GameState.has_method("world_action_info"):
		return GameState.call("world_action_info", String(specification.get("action", "")), String(specification.get("id", "")))
	return {"ok": false, "reason": "Dữ liệu thế giới chưa sẵn sàng."}


func _perform_primary() -> void:
	_perform_spec(_primary_spec)


func _perform_secondary() -> void:
	_perform_spec(_secondary_spec)


func _perform_spec(specification: Dictionary) -> void:
	var info := _action_info(specification)
	if not bool(info.get("ok", false)):
		feedback = String(info.get("reason", ""))
	elif specification.has("route"):
		ScreenRouter.go(String(specification["route"]))
		return
	elif specification.has("section"):
		_select_section(int(specification["section"]))
		return
	elif String(specification.get("action", "")) == "advance_day":
		feedback = tr("Đã sang ngày mới. Kiểm tra tiến độ trứng và chăm sóc rồng.") if GameState.advance_day() else UILocale.translate_message(GameState.status)
	else:
		GameState.call("world_action", String(specification.get("action", "")), String(specification.get("id", "")))
		feedback = GameState.status
	_refresh()


func _cycle_selection() -> void:
	selection_index += 1
	feedback = ""
	_refresh_dragon_section()


func _world_state() -> Dictionary:
	return GameState.call("world_state") if GameState.has_method("world_state") else {}


func _care_purpose() -> String:
	if active_section == 1:
		return UILocale.pair("Cho ăn · Dọn dẹp · Chữa bệnh", "Feed · Clean · Remedy")
	return UILocale.pair("Vuốt ve · Vui vẻ · Thu Long Khí", "Pet · Happiness · Collect Energy")


func _world_config() -> Dictionary:
	return GameState.call("world_config") if GameState.has_method("world_config") else {}


func _utility_name(utility: String) -> String:
	return tr(String({"water": "Tưới nước", "storage": "Bảo quản", "preservation": "Bảo quản", "hatch": "Ấp nhanh", "gather": "Thu vật liệu", "garden": "Hạt thảo dược", "materials": "Vật liệu", "seeds": "Hạt giống", "health": "Sức khỏe", "none": "Không có"}.get(utility, utility)))
