extends BaseScreen

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const GameplayButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const FeedbackFlow = preload("res://scripts/ui/action_feedback_flow.gd")
const FeedbackAudio = preload("res://v7/production/field_audio_feedback.gd")
const FoodResolver = preload("res://scripts/creature_food_resolver.gd")
const AlphaHit = preload("res://scripts/ui/animal_alpha_hit.gd")
const ItemSource = preload("res://scripts/ui/item_source_presenter.gd")
const ACTION_LABELS := {"feed_animals": "Cho ăn", "clean_animals": "Dọn dẹp", "pet_animals": "Vuốt ve", "collect": "Thu trứng"}
const SPECIES := {"cloud_chicken": "Gà Mây", "cow": "Bò Đồng Cỏ", "duck": "Vịt Mây", "pig": "Heo Củ"}
const SPECIES_TABS := {"cloud_chicken": "AnimalSpecies_chicken", "cow": "AnimalSpecies_cow", "duck": "AnimalSpecies_duck", "pig": "AnimalSpecies_pig"}
const CARE_ACTIONS := {"feed_animals": "feed", "clean_animals": "clean", "pet_animals": "pet", "collect": "collect"}
const COLLECT_LABELS := {"cloud_chicken": "Thu trứng", "cow": "Thu sữa", "duck": "Thu trứng vịt", "pig": "Thu nấm củ"}
const PRODUCT_LABELS := {"cloud_chicken": "Trứng gà", "cow": "Sữa", "duck": "Trứng vịt", "pig": "Nấm củ"}
const YARD_LABELS := {"cloud_chicken": "Chuồng Gà Mây", "cow": "Khu Bò Đồng Cỏ", "duck": "Ao Vịt Mây", "pig": "Khu Heo Củ"}
const FOOD_LABELS := {"cloud_chicken": "Máng ăn", "cow": "Cỏ khô", "duck": "Hạt ao hồ", "pig": "Củ nghiền"}
const VISUAL_NODES := {"cow": "CowVisual", "duck": "DuckVisual", "pig": "PigVisual"}
const WORLD_CARE_TARGETS := {"ChickenVisual01": "cloud_chicken", "ChickenVisual02": "cloud_chicken", "CowVisual": "cow", "DuckVisual": "duck", "PigVisual": "pig"}
const MAIN_VISUALS := {"cloud_chicken": "ChickenVisual01", "cow": "CowVisual", "duck": "DuckVisual", "pig": "PigVisual"}
const CARE_METERS := {"CareFullness": "fullness", "CareCleanliness": "cleanliness", "CareHappiness": "happiness"}
const STATUS_ART := ROOT + "/ANIMAL/STATUS_OVERLAYS/"
# The approved source sprites have different transparent foot padding.
# These normalized feedback roots do not move or scale any animal body.
@export var species_feedback_root_y: Dictionary = {"cloud_chicken": 0.94, "cow": 0.965, "duck": 0.94, "pig": 0.91}
const UTILITY_COPY := {
	"cloud_chicken": "1 hạt bạc hà khi Đảo Dược Liệu đã mở.",
	"cow": "1 hạt bạc hà khi Đảo Dược Liệu đã mở.",
	"duck": "Tưới 1 luống đã trồng vào ngày mới.",
	"pig": "Tìm 1 đá xây dựng vào ngày mới.",
}

# Exposed art maps are presentation only; no sprite owns individual save state.
@export var species_background_paths: Dictionary = {
	"cloud_chicken": "res://assets/canonical_v2/03_ART_RUNTIME_READY/ENVIRONMENT/SCREEN_PLATES/animal_coop_yard.png",
	"cow": "res://assets/gdd_closure_v3/environment/cow_yard.png",
	"duck": "res://assets/gdd_closure_v3/environment/duck_pond.png",
	"pig": "res://assets/gdd_closure_v3/environment/pig_yard.png",
}
@export var species_portrait_paths: Dictionary = {
	"cloud_chicken": "res://assets/canonical_v2/03_ART_RUNTIME_READY/ANIMAL/BASE/chicken_idle.png",
	"cow": "res://assets/canonical_v2/03_ART_RUNTIME_READY/CHARACTERS/ANIMALS/cow_idle.png",
	"duck": "res://assets/gdd_closure_v3/animals/duck_idle.png",
	"pig": "res://assets/gdd_closure_v3/animals/pig_idle.png",
}
var selected_species := "cloud_chicken"
var feedback := "Chăm Gà Mây để nhận trứng.\nCho ăn, vuốt ve, dọn dẹp."
var _last_action_failed := false
var _has_care_result := false
var _selected_visual_name := "ChickenVisual01"
var _feedback_tween: Tween
var _world_art_cache: Dictionary = {}
var _action_flow: Node2D
var _action_audio: Node
const MOUTH_CONTACTS := {"cloud_chicken": Vector2(0.76, 0.35), "cow": Vector2(0.80, 0.42), "duck": Vector2(0.81, 0.25), "pig": Vector2(0.87, 0.35)}


func build() -> void:
	if get_node_or_null("AnimalProductionStatus") == null:
		var banner := UI.panel(Rect2(370, 163, 510, 66), Color("fff1d8e8"))
		banner.name = "AnimalProductionStatus"
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var copy := UI.label("", Rect2(16, 5, 478, 56), 16, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
		copy.name = "ProductionReason"
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		banner.add_child(copy)
		add_child(banner)
	set_meta("ANIMAL_CORE_LOCK", "FUNCTIONAL_TEST_REQUIRED")
	set_meta("GDD_SPECIES_PRESENTATION", "CHICKEN_COW_DUCK_PIG_SEPARATE")
	set_meta("GDD_INDIVIDUAL_GROWTH", "NOT_IMPLEMENTED_IN_WORLD_RULES")
	set_meta("UI_IN_PLACE_REFRESH", true)
	set_meta("MOCKUP_UI_APPLICATION", "REAL_SPECIES_CARE_PANEL_AND_IMMEDIATE_PRODUCT_FEEDBACK")
	bind_button("AnimalBackToHub", ScreenRouter.back_home)
	bind_button("AnimalAdvanceDay", _advance_day)
	for action_id in ACTION_LABELS:
		bind_button("AnimalAction_%s" % action_id, _animal_action.bind(action_id))
	bind_button("AnimalCollectionAccess", _open_collection)
	for species in SPECIES_TABS:
		bind_button(String(SPECIES_TABS[species]), _select_species.bind(String(species)))
	bind_button("AnimalAdoptSelected", _adopt_selected)
	bind_button("AnimalUtilitySelected", _toggle_utility)
	bind_button("AnimalHealSelected", _heal_selected)
	var care := find_child("AnimalCareContext", true, false) as Control
	var remedy_shop := UI.title_button("", Rect2(197, 295, 149, 56))
	remedy_shop.name = "AnimalRemedyShop"
	remedy_shop.get_child(0).name = "Caption"
	remedy_shop.pressed.connect(_open_remedy_shop)
	care.add_child(remedy_shop)
	bind_button("AnimalCareClose", _close_care)
	bind_button("AnimalWorldProduct", _collect_world_product)
	for dirt_name in ["AnimalMess01", "AnimalMess02", "AnimalMess03"]:
		bind_button(dirt_name, _clean_world_mess)
	for node_name in WORLD_CARE_TARGETS:
		var target := find_child(String(node_name), true, false) as Control
		if target == null: continue
		if target is TextureRect and target.get_script() == null: target.set_script(AlphaHit)
		target.mouse_filter = Control.MOUSE_FILTER_STOP
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var callback := _on_animal_gui_input.bind(String(WORLD_CARE_TARGETS[node_name]), String(node_name))
		if not target.gui_input.is_connected(callback): target.gui_input.connect(callback)
	_apply_care_button_skin()
	_action_audio = FeedbackAudio.new()
	_action_audio.name = "AnimalActionAudio"
	add_child(_action_audio)
	_refresh()
	_close_care()


func _refresh() -> void:
	bind_top_hud()
	var feedback_label := get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	if feedback_label != null:
		var disease := String(_species_state().get("disease", ""))
		var text := UILocale.translate_message(feedback)
		var full_text := text
		if not _last_action_failed and not _owned():
			var eligibility := _action_info("adopt")
			full_text = UILocale.translate_message(String(eligibility.get("reason", "")))
			text = tr("Đủ điều kiện nhận nuôi.") if bool(eligibility.get("ok", false)) else full_text
		elif not _last_action_failed and not disease.is_empty():
			text = tr("Đang bệnh: %s\nDùng %s.") % [tr(disease), _item_name("medicine_" + disease)]
			full_text = _remedy_guidance(disease)
		feedback_label.text = text
		feedback_label.tooltip_text = UILocale.translate_message(full_text)
		feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		feedback_label.max_lines_visible = 3
	_refresh_animal_visuals()
	_refresh_species_details()
	for action_id in ACTION_LABELS:
		var reason := _action_reason(String(action_id))
		var caption := String(COLLECT_LABELS[selected_species]) if action_id == "collect" else String(ACTION_LABELS[action_id])
		CardState.apply_action(find_child("AnimalAction_%s" % action_id, true, false) as BaseButton, reason.is_empty(), reason if not reason.is_empty() else tr(caption))
	var adopt := find_child("AnimalAdoptSelected", true, false) as BaseButton
	adopt.visible = not _owned()
	var adopt_info := _action_info("adopt")
	CardState.apply_action(adopt, bool(adopt_info.get("ok", false)), UILocale.translate_message(String(adopt_info.get("reason", ""))))
	var utility := find_child("AnimalUtilitySelected", true, false) as BaseButton
	utility.visible = _owned()
	var utility_info := _action_info("unassign_utility" if _utility_assigned() else "assign_utility")
	CardState.apply_action(utility, bool(utility_info.get("ok", false)), UILocale.translate_message(String(utility_info.get("reason", ""))))
	(utility.get_node("Caption") as Label).text = tr("Dừng hỗ trợ" if _utility_assigned() else "Giao hỗ trợ")
	var heal := find_child("AnimalHealSelected", true, false) as BaseButton
	heal.visible = _owned() and not String(_species_state().get("disease", "")).is_empty()
	var heal_info := _action_info("heal")
	CardState.apply_action(heal, bool(heal_info.get("ok", false)), UILocale.translate_message(String(heal_info.get("reason", ""))))
	for species in SPECIES_TABS:
		var species_button := find_child(String(SPECIES_TABS[species]), true, false) as TextureButton
		var selected: bool = selected_species == species
		CardState.apply_tab(species_button, selected, true, tr(String(SPECIES[species])))
		var tab_caption := species_button.get_node_or_null("Caption") as Label
		if tab_caption != null: tab_caption.add_theme_color_override("font_color", Color("fff4d2") if selected else Color("3d2917"))
		GameplayButtonSkin.set_selected(species_button, selected)
	_refresh_care_context()
	_refresh_selection_feedback()
	_refresh_world_feedback()
	for action_id in ACTION_LABELS:
		GameplayButtonSkin.refresh(find_child("AnimalAction_%s" % action_id, true, false) as TextureButton)
	for button_name in ["AnimalAdoptSelected", "AnimalUtilitySelected", "AnimalHealSelected"]:
		GameplayButtonSkin.refresh(find_child(button_name, true, false) as TextureButton)


func _refresh_animal_visuals() -> void:
	var animal: Dictionary = _species_state()
	var values := {"Hunger": int(animal.get("fullness", 0)), "Cleanliness": int(animal.get("cleanliness", 0)), "Happiness": int(animal.get("happiness", 0))}
	for prefix in values:
		var value := clampi(int(values[prefix]), 0, 100)
		var label := find_child(prefix + "Value", true, false) as Label
		var bar := find_child(prefix + "Bar", true, false) as Control
		if label != null: label.text = str(value) if _owned() else "—"
		if bar != null:
			var fill := bar.find_child("ProgressFill", true, false) as Control
			if fill != null: fill.size.x = maxf(0, bar.size.x - 8.0) * value / 100.0
	(find_child("EggStatusLabel", true, false) as Label).text = tr("Sẵn sàng: %d · %s") % [_products_ready(), tr(PRODUCT_LABELS[selected_species])]
	var energy_label := get_node_or_null("MainContent/AnimalResourceStrip/EnergyValueLabel") as Label
	var feed_label := get_node_or_null("MainContent/AnimalResourceStrip/FeedInventoryLabel") as Label
	if energy_label != null: energy_label.text = tr("Năng lượng  %d") % int(GameState.data.get("energy", 0))
	if feed_label != null:
		feed_label.text = tr("Thức ăn  %d") % _inventory_count(_food_id())
		feed_label.tooltip_text = tr("%s · dành cho %s") % [_item_name(_food_id()), tr(SPECIES[selected_species])]
	(find_child("AnimalNameLabel", true, false) as Label).text = tr(SPECIES[selected_species])
	(find_child("AnimalDescriptionLabel", true, false) as Label).text = tr("Đã nuôi" if _owned() else "Xem trước")
	var portrait := find_child("Art_chicken_idle", true, false) as TextureRect
	portrait.texture = _species_portrait(selected_species)
	portrait.modulate.a = 1.0 if _owned() else 0.45
	for species in VISUAL_NODES:
		var visual := find_child(String(VISUAL_NODES[species]), true, false) as TextureRect
		if visual == null:
			continue
		visual.visible = selected_species == species
		visual.texture = _species_portrait(String(species))
		visual.modulate.a = 1.0 if _owned() else 0.45
	var sheep := find_child("SheepVisual", true, false) as CanvasItem
	if sheep != null:
		sheep.visible = false
	# These old flat-color debug rails duplicate the fences painted in each yard.
	# They are presentation only and never contain care/click or save state.
	for fence_name in ["FenceRailTopDark", "FenceRailTopHighlight", "FenceRailBottomDark", "FenceRailBottomHighlight", "FencePost01", "FencePost02", "FencePost03", "FencePost04"]:
		var fence := find_child(fence_name, true, false) as CanvasItem
		if fence != null:
			fence.visible = false
	for visual_name in ["ChickenVisual01", "ChickenVisual02"]:
		var chicken := find_child(visual_name, true, false) as CanvasItem
		if chicken != null:
			chicken.visible = selected_species == "cloud_chicken"
	# Existing small-chicken nodes are decoration, not baby entities.
	# WorldData age_days has no maturation threshold or breeding action.
	for visual_name in ["ChickVisual01", "ChickVisual02", "ChickVisual03"]:
		var chick := find_child(visual_name, true, false) as CanvasItem
		if chick != null:
			chick.visible = false
	var station_food := find_child("Art_animal_feed", true, false) as TextureRect
	if station_food != null:
		station_food.texture = Assets.get_item_texture(_food_id())
		station_food.visible = selected_species == "cloud_chicken"
	var station_label := find_child("FeedStationVisualLabel", true, false) as Label
	# The authored station/body rectangles belong to the user's scene, not refresh.
	if station_label != null:
		station_label.text = tr(FOOD_LABELS[selected_species])
		station_label.tooltip_text = _item_name(_food_id())
	var yard_sign := find_child("AnimalYardSignLabel", true, false) as Label
	if yard_sign != null: yard_sign.text = tr(YARD_LABELS[selected_species])
	(find_child("AnimalAction_collect", true, false).get_node("Caption") as Label).text = tr(COLLECT_LABELS[selected_species])
	var background := get_node("Background") as TextureRect
	var background_path := String(species_background_paths.get(selected_species, ""))
	background.texture = load(background_path) as Texture2D if not background_path.is_empty() and ResourceLoader.exists(background_path) else Assets.background("animal")
	set_meta("SPECIES_BACKGROUND_BOUND", not background_path.is_empty() and ResourceLoader.exists(background_path))
	for node_name in WORLD_CARE_TARGETS:
		var target := find_child(String(node_name), true, false) as Control
		if target != null: target.tooltip_text = tr("Chạm vật nuôi để chăm sóc.")


func _refresh_species_details() -> void:
	(find_child("AnimalFoodLabel", true, false) as Label).text = tr("Thức ăn: %s ×%d") % [_item_name(_food_id()), _inventory_count(_food_id())]
	(find_child("AnimalOutputLabel", true, false) as Label).text = tr("%s · Sẵn sàng %d · Kho %d") % [_item_name(_product_id()), _products_ready(), _inventory_count(_product_id())]
	var utility_label := find_child("AnimalUtilityLabel", true, false) as Label
	utility_label.text = tr("Đã giao hỗ trợ" if _utility_assigned() else "Chưa giao hỗ trợ") + "\n" + tr(UTILITY_COPY[selected_species])
	utility_label.tooltip_text = tr("Hỗ trợ áp dụng ngày mới khi cả ba chỉ số từ 40 và không bệnh. Một loài cho mỗi loại hỗ trợ. Hạt/đá cần chỗ trong Kho.")
	var condition := find_child("AnimalAdoptionLabel", true, false) as Label
	if _owned():
		condition.text = tr("Sản phẩm ngày mới: chỉ số ≥40, không bệnh.")
		condition.tooltip_text = tr("Mỗi ngày chăm tốt tạo 1 sản phẩm. Tối đa chờ thu: %d.") % (6 if selected_species == "cloud_chicken" else 3)
	else:
		var definition := _definition()
		condition.text = tr("Nhận nuôi: %d xu · %d đơn · Chuồng") % [int(definition.get("cost", 0)), int(definition.get("orders", 0))]
		condition.tooltip_text = UILocale.translate_message(String(_action_info("adopt").get("reason", "")))


func _action_reason(action: String) -> String:
	if not _owned(): return tr("Chưa nhận nuôi loài này.")
	if selected_species != "cloud_chicken":
		var info := _action_info(String(CARE_ACTIONS[action]))
		return "" if bool(info.get("ok", false)) else UILocale.translate_message(String(info.get("reason", "")))
	var info := GameState.animal_action_info(action)
	return "" if bool(info.get("ok", false)) else UILocale.translate_message(String(info.get("reason", "")))


func _animal_action(action: String) -> void:
	_stop_action_feedback()
	_has_care_result = true
	var reason := _action_reason(action)
	if not reason.is_empty():
		feedback = reason
		_last_action_failed = true
		_refresh()
		return
	var ready_before := _products_ready()
	var stock_before := _inventory_count(_product_id())
	var kind := String(CARE_ACTIONS[action])
	var meter_key := "fullness" if kind == "feed" else "cleanliness" if kind == "clean" else "happiness"
	var meter_before := int(_species_state().get(meter_key, 0))
	var food_used := _food_id()
	var succeeded: bool = GameState.animal_action(action) if selected_species == "cloud_chicken" else GameState.world_action(String(CARE_ACTIONS[action]), selected_species)
	_last_action_failed = not succeeded
	if succeeded:
		match action:
			"feed_animals": feedback = tr("Đã cho ăn.\n%s còn ×%d.") % [_item_name(food_used), _inventory_count(food_used)]
			"clean_animals": feedback = tr("Đã dọn dẹp.")
			"pet_animals": feedback = tr("Đã vuốt ve.")
			"collect": feedback = tr("Đã thu %s ×%d.\nKho: %d.") % [_item_name(_product_id()), ready_before, _inventory_count(_product_id())]
	else: feedback = GameState.status
	_refresh()
	if succeeded:
		var actual_amount := maxi(0, _inventory_count(_product_id()) - stock_before) if kind == "collect" else maxi(0, int(_species_state().get(meter_key, 0)) - meter_before)
		_show_action_feedback(action, actual_amount if kind == "collect" else ready_before, actual_amount, food_used if kind == "feed" else "")


func _definition() -> Dictionary:
	return GameState.world_config().get("creatures", {}).get(selected_species, {})


func _owned() -> bool:
	return GameState.world_state().get("creatures", {}).has(selected_species)


func _species_state() -> Dictionary:
	var world_creature: Dictionary = GameState.world_state().get("creatures", {}).get(selected_species, {})
	if selected_species != "cloud_chicken": return world_creature
	# Legacy chicken owns care/products; disease remains world-owned.
	var chicken: Dictionary = GameState.data.get("animal", {}).duplicate(true)
	chicken["disease"] = String(world_creature.get("disease", ""))
	return chicken


func _action_info(action: String) -> Dictionary:
	return GameState.world_action_info(action, selected_species)


func _food_id() -> String:
	return FoodResolver.resolve(GameState.data, selected_species)


func _product_id() -> String:
	return String(_definition().get("product", "egg"))


func _products_ready() -> int:
	return int(_species_state().get("eggs_ready" if selected_species == "cloud_chicken" else "products_ready", 0)) if _owned() else 0


func _inventory_count(item_id: String) -> int:
	return int(GameState.data.get("inventory", {}).get(item_id, 0))


func _item_name(item_id: String) -> String:
	return tr("Thức ăn vật nuôi") if item_id == "animal_feed" else tr(String(GameState.world_config().get("items", {}).get(item_id, {}).get("name", item_id)))


func _species_portrait(species: String) -> Texture2D:
	var path := String(species_portrait_paths.get(species, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


func _care_action_icon(action: String) -> Texture2D:
	match action:
		"feed_animals": return Assets.get_item_texture(_food_id())
		"collect": return Assets.get_item_texture(_product_id())
		"clean_animals": return load(STATUS_ART + "clean_fresh_sparkle.png") as Texture2D
	return load(STATUS_ART + "happy_cared_heart.png") as Texture2D


func _apply_care_button_skin() -> void:
	for action in ACTION_LABELS:
		var button := find_child("AnimalAction_" + String(action), true, false) as TextureButton
		GameplayButtonSkin.apply(button, {"icon_node": "ActionIcon", "icon_texture": _care_action_icon(String(action)), "font_size": 16 if action == "collect" else 18})
	for button_name in ["AnimalAdoptSelected", "AnimalUtilitySelected", "AnimalHealSelected", "AnimalBackToHub", "AnimalAdvanceDay"]:
		GameplayButtonSkin.apply(find_child(button_name, true, false) as TextureButton, {"font_size": 18})
	for species in SPECIES_TABS:
		GameplayButtonSkin.apply(find_child(String(SPECIES_TABS[species]), true, false) as TextureButton, {"font_size": 20})


func _world_texture(key: String, preferred: String, fallback: String) -> Texture2D:
	# Only immutable art is cached; readiness and cleanliness always read state.
	if _world_art_cache.has(key): return _world_art_cache[key] as Texture2D
	var generated := ResourceLoader.exists(preferred)
	var texture := load(preferred) as Texture2D if generated else load(fallback) as Texture2D
	# Source alpha>32 bounds were measured from the original PNGs, not guessed.
	# Scale bounds to imported dimensions; never scan millions of pixels on an
	# action/frame. Original PNGs remain unmodified and cache is source-only.
	if generated and texture != null:
		var native_size := Vector2(1254, 1254) if key == "mess" else Vector2(1619, 971)
		var opaque_bounds := Rect2(51, 462, 1153, 366) if key == "mess" else Rect2(67, 168, 1479, 675)
		var imported_scale := texture.get_size() / native_size
		var trimmed := AtlasTexture.new()
		trimmed.atlas = texture
		trimmed.region = Rect2(opaque_bounds.position * imported_scale, opaque_bounds.size * imported_scale)
		texture = trimmed
	_world_art_cache[key] = texture
	return texture


func _refresh_world_feedback() -> void:
	var production := get_node_or_null("AnimalProductionStatus/ProductionReason") as Label
	if production != null:
		production.text = production_reason()
	var cleanliness := clampi(int(_species_state().get("cleanliness", 0)), 0, 100)
	var mess_count := 0 if not _owned() or cleanliness == 100 else 1 if cleanliness >= 75 else 2 if cleanliness >= 45 else 3
	var clean_reason := _action_reason("clean_animals")
	for index in range(1, 4):
		var mess := find_child("AnimalMess%02d" % index, true, false) as TextureButton
		if mess == null: continue
		mess.visible = index <= mess_count
		mess.disabled = not clean_reason.is_empty()
		mess.tooltip_text = UILocale.pair("Chuồng còn bẩn — chạm để dọn.", "The yard needs cleaning — click the mess.") if clean_reason.is_empty() else clean_reason
		mess.texture_normal = _world_texture("mess", "res://assets/player_feedback_v2/animal/ground_mess.png", STATUS_ART + "dirty_mud_dust.png")
		mess.texture_hover = mess.texture_normal
		mess.texture_pressed = mess.texture_normal
		mess.texture_disabled = mess.texture_normal
		mess.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		mess.set_meta("cleanliness", cleanliness)
	var clean_label := find_child("AnimalYardCleanStatus", true, false) as Label
	if clean_label != null:
		clean_label.visible = _owned() and mess_count == 0
		clean_label.text = UILocale.pair("Chuồng sạch", "Clean yard")
	var pickup := find_child("AnimalWorldProduct", true, false) as TextureButton
	if pickup == null: return
	var ready := _products_ready()
	pickup.visible = _owned() and ready > 0
	pickup.disabled = not _action_reason("collect").is_empty()
	pickup.tooltip_text = UILocale.pair("Chạm để nhặt %d %s.", "Click to collect %d %s.") % [ready, tr(PRODUCT_LABELS[selected_species])]
	pickup.set_meta("products_ready", ready)
	pickup.set_meta("species", selected_species)
	var nest := pickup.get_node("NestArt") as TextureRect
	nest.texture = _world_texture("nest", "res://assets/player_feedback_v2/animal/empty_nest.png", STATUS_ART + "egg_ready.png")
	var product := pickup.get_node("ProductIcon") as TextureRect
	product.texture = Assets.get_item_texture(_product_id())
	var count := pickup.get_node("ProductQuantity") as Label
	count.text = "×%d" % ready
	var instruction := pickup.get_node("PickupCaption") as Label
	instruction.text = UILocale.pair("Nhặt", "Collect")
	set_meta("WORLD_MESS_COUNT", mess_count)
	set_meta("WORLD_PRODUCTS_READY", ready)


func production_reason() -> String:
	if not _owned(): return UILocale.pair("Chưa nhận nuôi con vật này.", "This animal has not been adopted.")
	if _products_ready() > 0:
		return UILocale.pair("Có %d %s — chạm ổ sản phẩm để nhặt.", "%d %s ready — click the product nest to collect.") % [_products_ready(), tr(PRODUCT_LABELS[selected_species])]
	var state := _species_state()
	var disease := String(state.get("disease", ""))
	if not disease.is_empty():
		return UILocale.pair("Chưa có sản phẩm: đang %s.\nCần %s; cho ăn không chữa bệnh.", "No product: %s.\nUse %s; feeding does not cure illness.") % [tr(disease), _item_name("medicine_" + disease)]
	var lacking: Array[String] = []
	for entry in [["fullness", "No bụng", "Fullness"], ["cleanliness", "Sạch sẽ", "Cleanliness"], ["happiness", "Vui vẻ", "Happiness"]]:
		if int(state.get(entry[0], 0)) < 40: lacking.append(UILocale.pair(String(entry[1]), String(entry[2])))
	if not lacking.is_empty():
		return UILocale.pair("Chưa có sản phẩm: %s dưới 40.\nChăm sóc đủ, rồi chọn NGÀY MỚI.", "No product: %s below 40.\nCare for it, then choose NEXT DAY.") % ", ".join(lacking)
	return UILocale.pair("Đủ điều kiện — chọn NGÀY MỚI để có sản phẩm.\nSản phẩm không sinh theo thời gian chờ.", "Ready for production — choose NEXT DAY.\nProducts do not appear by waiting in real time.")


func _collect_world_product() -> void:
	# Same single transaction as the care button. No extra save/reward path.
	var context := find_child("AnimalCareContext", true, false) as Control
	if context != null: context.visible = true
	_animal_action("collect")


func _clean_world_mess() -> void:
	var context := find_child("AnimalCareContext", true, false) as Control
	if context != null: context.visible = true
	_animal_action("clean_animals")


func _utility_assigned() -> bool:
	return String(GameState.world_state().get("utility", {}).get(String(_definition().get("utility", "")), "")) == selected_species


func _select_species(species: String) -> void:
	if not SPECIES.has(species): return
	selected_species = species
	_selected_visual_name = String(MAIN_VISUALS[species])
	_stop_action_feedback()
	_last_action_failed = false
	_has_care_result = false
	feedback = "Chăm Gà Mây để nhận trứng.\nCho ăn, vuốt ve, dọn dẹp." if species == "cloud_chicken" else tr("Chăm %s mỗi ngày.\nThức ăn và sản phẩm riêng.") % tr(SPECIES[species])
	_refresh()
	var context := find_child("AnimalCareContext", true, false) as Control
	if context != null: context.visible = false
	_refresh_selection_feedback()


func _on_animal_gui_input(event: InputEvent, species: String, visual_name: String) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	if selected_species != species: _select_species(species)
	_selected_visual_name = visual_name
	var context := find_child("AnimalCareContext", true, false) as Control
	if context != null: context.visible = true
	_refresh_care_context()
	_refresh_selection_feedback()
	get_viewport().set_input_as_handled()


func _close_care() -> void:
	var context := find_child("AnimalCareContext", true, false) as Control
	if context != null: context.visible = false
	_refresh_selection_feedback()


func close_top_presentation() -> bool:
	var context := find_child("AnimalCareContext", true, false) as Control
	if context == null or not context.is_visible_in_tree(): return false
	_close_care()
	return true


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	var context := find_child("AnimalCareContext", true, false) as Control
	if context == null or not context.is_visible_in_tree() or context.get_global_rect().has_point(event.position): return
	for control_name in ["AnimalCareActions", "AnimalWorldProduct", "AnimalMess01", "AnimalMess02", "AnimalMess03"]:
		var control := find_child(control_name, true, false) as Control
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(event.position): return
	for node_name in WORLD_CARE_TARGETS:
		var target := find_child(String(node_name), true, false) as Control
		if target != null and target.is_visible_in_tree():
			var local_point: Vector2 = target.get_global_transform_with_canvas().affine_inverse() * event.position
			if target.has_method("_has_point") and target.call("_has_point", local_point): return
	_close_care()


func _refresh_care_context() -> void:
	var context := find_child("AnimalCareContext", true, false) as Control
	if context == null: return
	(context.get_node("CareSpeciesName") as Label).text = tr(SPECIES[selected_species])
	var state := _species_state()
	for meter_name in CARE_METERS:
		var meter := context.get_node_or_null(String(meter_name)) as ProgressBar
		var meter_value := context.get_node_or_null(String(meter_name) + "Value") as Label
		var value := clampi(int(state.get(CARE_METERS[meter_name], 0)), 0, 100)
		if meter != null:
			meter.value = value if _owned() else 0
			meter.modulate.a = 1.0 if _owned() else 0.45
		if meter_value != null: meter_value.text = str(value) if _owned() else "—"
	var summary := context.get_node("CareStateSummary") as Label
	summary.text = tr("No %d · Sạch %d · Vui %d") % [int(state.get("fullness", 0)), int(state.get("cleanliness", 0)), int(state.get("happiness", 0))] if _owned() else tr("Chưa nhận nuôi")
	var stock := context.get_node("CareFoodAndProduct") as Label
	stock.text = tr("Thức ăn: %s ×%d") % [_item_name(_food_id()), _inventory_count(_food_id())]
	stock.tooltip_text = "%s ×%d · %s ×%d" % [_item_name(_food_id()), _inventory_count(_food_id()), _item_name(_product_id()), _products_ready()]
	var product := context.get_node_or_null("CareProductQuantity") as Label
	if product != null: product.text = tr("Sẵn sàng: %d · %s") % [_products_ready(), tr(PRODUCT_LABELS[selected_species])]
	var product_icon := context.get_node_or_null("CareProductIcon") as TextureRect
	if product_icon != null: product_icon.texture = Assets.get_item_texture(_product_id())
	var fullness_icon := context.get_node_or_null("CareFullnessIcon") as TextureRect
	if fullness_icon != null: fullness_icon.texture = Assets.get_item_texture(_food_id())
	var result := context.get_node("CareActionResult") as Label
	result.text = UILocale.translate_message(feedback)
	if not _last_action_failed and not _owned():
		result.text = UILocale.translate_message(String(_action_info("adopt").get("reason", "")))
	elif not _has_care_result and not String(state.get("disease", "")).is_empty():
		result.text = _remedy_guidance(String(state["disease"]))
	result.tooltip_text = result.text
	if not _last_action_failed and not String(state.get("disease", "")).is_empty():
		result.tooltip_text = _remedy_guidance(String(state["disease"]))
	result.position = Vector2(40, 355)
	result.size = Vector2(304, 69)
	result.max_lines_visible = 4
	result.add_theme_font_size_override("font_size", 14)
	result.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	result.modulate = Color(0.65, 0.22, 0.15) if _last_action_failed else Color.WHITE
	var utility := find_child("AnimalUtilitySelected", true, false) as Control
	# Secondary care stays contextual. A sick creature shows its cure, not a row
	# of unrelated collection/management actions.
	if utility != null: utility.visible = _owned() and String(state.get("disease", "")).is_empty()
	var heal := find_child("AnimalHealSelected", true, false) as Control
	if heal != null: heal.visible = _owned() and not String(state.get("disease", "")).is_empty()
	var shop := find_child("AnimalRemedyShop", true, false) as TextureButton
	var sick := _owned() and not String(state.get("disease", "")).is_empty()
	if shop != null:
		shop.visible = sick
		GameplayButtonSkin.apply(shop, {"caption": UILocale.pair("Mua thuốc", "Buy Remedy"), "font_size": 14, "layout_content": true})
		shop.tooltip_text = _remedy_guidance(String(state.get("disease", ""))) if sick else ""
	if heal != null:
		heal.size = Vector2(149 if sick else 306, 56)
		GameplayButtonSkin.apply(heal as TextureButton, {"caption": UILocale.pair("Trị bệnh", "Heal"), "font_size": 14, "layout_content": true})
	# Captions remain real labels and localize separately from each texture.
	for action in ACTION_LABELS:
		var button := find_child("AnimalAction_" + String(action), true, false) as BaseButton
		if button == null: continue
		var caption := button.get_node_or_null("Caption") as Label
		if caption != null:
			caption.text = tr(String(COLLECT_LABELS[selected_species]) if action == "collect" else String(ACTION_LABELS[action]))
			if action == "collect" and selected_species == "duck": caption.text = UILocale.pair("Thu trứng vịt", "Collect eggs")
			caption.add_theme_font_size_override("font_size", 16 if action == "collect" else 18)
		var action_icon := button.get_node_or_null("ActionIcon") as TextureRect
		if action_icon != null:
			action_icon.texture = _care_action_icon(String(action))
	var prompt := find_child("AnimalInteractionHint", true, false) as Control
	if prompt != null: prompt.visible = not context.visible
	var actions := find_child("AnimalCareActions", true, false) as Control
	if actions != null: actions.visible = context.visible


func _refresh_selection_feedback() -> void:
	var marker := find_child("AnimalSelectionMarker", true, false) as Control
	var context := find_child("AnimalCareContext", true, false) as Control
	var target := find_child(_selected_visual_name, true, false) as Control
	if marker == null or context == null or target == null: return
	var prompt := find_child("AnimalInteractionHint", true, false) as Control
	if prompt != null: prompt.visible = not context.visible
	var actions := find_child("AnimalCareActions", true, false) as Control
	if actions != null: actions.visible = context.visible
	marker.visible = context.visible and target.is_visible_in_tree() and _owned()
	if not marker.visible: return
	# Feedback anchors follow scene-authored body rectangles; bodies are never reset.
	var rect := target.get_global_rect()
	var root_y := rect.position.y + rect.size.y * float(species_feedback_root_y.get(selected_species, 1.0))
	marker.global_position = Vector2(rect.get_center().x - marker.size.x * 0.5, root_y - marker.size.y * 0.68)


func _stop_action_feedback() -> void:
	for body_name in WORLD_CARE_TARGETS:
		var body := find_child(String(body_name),true,false) as Control
		if body != null:
			body.set_meta("care_action","")
			body.set_meta("care_action_at_msec",-10000)
	if _feedback_tween != null and _feedback_tween.is_valid(): _feedback_tween.kill()
	if is_instance_valid(_action_flow):
		_action_flow.hide()
		_action_flow.queue_free()
	_action_flow = null
	for name in ["AnimalActionToast", "AnimalActionEffect"]:
		var node := find_child(name, true, false) as CanvasItem
		if node != null: node.visible = false

func _process(_delta: float) -> void:
	if _feedback_tween == null or not _feedback_tween.is_valid(): return
	var modal := find_child("SaveMenuDialog",true,false) as Control
	if modal != null and modal.is_visible_in_tree():
		_feedback_tween.pause()
	elif not _feedback_tween.is_running():
		_feedback_tween.play()


func _body_contacts(target: Control) -> Dictionary:
	var draw_size := target.size
	var inset := Vector2.ZERO
	if target is TextureRect and (target as TextureRect).texture != null:
		var texture_size := (target as TextureRect).texture.get_size()
		var ratio := minf(target.size.x / maxf(texture_size.x, 1), target.size.y / maxf(texture_size.y, 1))
		draw_size = texture_size * ratio
		inset = (target.size - draw_size) * 0.5
	var normalized: Vector2 = MOUTH_CONTACTS.get(selected_species, Vector2(0.75, 0.35))
	if target is TextureRect and (target as TextureRect).flip_h: normalized.x = 1.0 - normalized.x
	var transform := target.get_global_transform()
	return {
		"mouth": transform * target.get_meta("motion_mouth",inset + draw_size * normalized),
		"head": transform * (inset + draw_size * Vector2(normalized.x - 0.08, maxf(0.12, normalized.y - 0.18))),
		"feet": transform * Vector2(target.size.x * 0.5, target.size.y * float(species_feedback_root_y.get(selected_species, 0.94)))
	}


func _show_action_feedback(action: String, product_amount: int = 0, actual_delta: int = 0, source_item := "") -> void:
	_stop_action_feedback()
	var target := find_child(_selected_visual_name, true, false) as Control
	var toast := find_child("AnimalActionToast", true, false) as Control
	var effect := find_child("AnimalActionEffect", true, false) as TextureRect
	if target == null or toast == null or effect == null: return
	var icon := toast.get_node("ProductIcon") as TextureRect
	var caption := toast.get_node("ResultLabel") as Label
	var kind := String(CARE_ACTIONS.get(action, action))
	if action == "collect":
		icon.texture = Assets.get_item_texture(_product_id())
		caption.text = "+%d %s" % [product_amount, tr(PRODUCT_LABELS[selected_species])]
	elif kind == "heal":
		icon.texture = Assets.get_item_texture(source_item)
		caption.text = UILocale.pair("Đã chữa bệnh", "Remedy used")
	else:
		icon.texture = Assets.get_item_texture(source_item if not source_item.is_empty() else _food_id()) if action == "feed_animals" else load(STATUS_ART + ("clean_fresh_sparkle.png" if action == "clean_animals" else "happy_cared_heart.png")) as Texture2D
		caption.text = tr("Đã dọn dẹp." if action == "clean_animals" else "Đã vuốt ve." if action == "pet_animals" else "Cho ăn")
		if actual_delta > 0:
			caption.text = "%s +%d" % [UILocale.pair("No bụng", "Fullness") if kind == "feed" else UILocale.pair("Sạch sẽ", "Cleanliness") if kind == "clean" else UILocale.pair("Vui vẻ", "Happiness"), actual_delta]
	var rect := target.get_global_rect()
	var start := Vector2(clampf(rect.get_center().x - toast.size.x * 0.5, 20.0, 844.0 - toast.size.x), maxf(rect.position.y - toast.size.y + 16.0, 172.0))
	toast.global_position = start
	toast.modulate = Color.WHITE
	toast.visible = true
	var contacts := _body_contacts(target)
	var contact: Vector2 = contacts["mouth"] if kind in ["feed", "heal"] else contacts["head"] if kind == "pet" else contacts["feet"]
	effect.texture = load(STATUS_ART + ("clean_fresh_sparkle.png" if kind in ["clean", "collect", "heal"] else "interaction_success_heart_burst.png")) as Texture2D
	effect.global_position = contact - effect.size * 0.5
	effect.modulate = Color.WHITE
	effect.visible = kind != "feed"
	toast.set_meta("feedback_action", action)
	toast.set_meta("feedback_product_amount", product_amount if action == "collect" else 0)
	toast.set_meta("feedback_amount", product_amount if kind == "collect" else actual_delta)
	target.set_meta("species_id", selected_species)
	target.set_meta("care_action", kind)
	target.set_meta("care_action_at_msec", Time.get_ticks_msec())
	target.set_meta("care_feedback_amount", product_amount if kind == "collect" else actual_delta)
	_action_flow = FeedbackFlow.new()
	_action_flow.name = "AnimalSemanticActionFlow"
	_action_flow.z_index = 9
	add_child(_action_flow)
	_action_flow.global_position = contact
	_action_flow.set_meta("target_species", selected_species)
	_action_flow.set_meta("target_visual", String(target.name))
	_action_flow.set_meta("actual_amount", product_amount if kind == "collect" else actual_delta)
	var flow_art := icon.texture if kind in ["feed", "pet", "collect", "heal"] else null
	_action_flow.configure(kind, 0.85, Vector2.ZERO, flow_art, (toast.get_global_rect().get_center() - contact) if kind == "collect" else Vector2.ZERO)
	if kind in ["feed","heal"]: _action_flow.follow_mouth(target)
	_action_flow.set_meta("contact_global", contact)
	_action_audio.play_action("seed" if kind == "feed" else "water" if kind == "clean" else "harvest" if kind == "collect" else "fertilize" if kind == "heal" else "crop_ready")
	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(toast, "global_position", start + Vector2(0, -22), 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(effect, "modulate:a", 0.0, 0.65).set_delay(0.15)
	_feedback_tween.tween_property(toast, "modulate:a", 0.0, 0.35).set_delay(0.95)
	_feedback_tween.chain().tween_callback(_stop_action_feedback)


func _adopt_selected() -> void:
	_has_care_result = true
	var succeeded := GameState.world_action("adopt", selected_species)
	_last_action_failed = not succeeded
	feedback = tr("Đã nhận nuôi %s.") % tr(SPECIES[selected_species]) if succeeded else GameState.status
	_refresh()


func _toggle_utility() -> void:
	_has_care_result = true
	var action := "unassign_utility" if _utility_assigned() else "assign_utility"
	var succeeded := GameState.world_action(action, selected_species)
	_last_action_failed = not succeeded
	feedback = tr("Đã dừng hỗ trợ.") if succeeded and action == "unassign_utility" else tr("Đã giao hỗ trợ.\nHiệu quả từ ngày mới.") if succeeded else GameState.status
	_refresh()


func _heal_selected() -> void:
	_stop_action_feedback()
	_has_care_result = true
	var disease := String(_species_state().get("disease", ""))
	var cure := "medicine_" + disease
	var stock_before := _inventory_count(cure)
	var succeeded := GameState.world_action("heal", selected_species)
	_last_action_failed = not succeeded
	feedback = tr("Đã dùng đúng thuốc cho %s.") % tr(SPECIES[selected_species]) if succeeded else GameState.status
	_refresh()
	if succeeded: _show_action_feedback("heal", 0, maxi(0, stock_before - _inventory_count(cure)), cure)


func _remedy_guidance(disease: String) -> String:
	var remedy_id := "medicine_" + disease
	var item: Dictionary = GameState.world_config().get("items", {}).get(remedy_id, {})
	if item.is_empty(): return ""
	var guidance := UILocale.pair("Dùng Trị bệnh với %s.\nCửa hàng chính: %d xu.", "Use Heal with %s.\nMain Shop: %d coins.") % [_item_name(remedy_id), int(item.get("price", 0))]
	var island := String(item.get("island", "main"))
	if not bool(GameState.world_state().get("unlocked_islands", {}).get(island, false)):
		guidance += "\n" + UILocale.pair("Mở %s trước.", "Unlock %s first.") % ItemSource.island_name(island)
	return guidance


func _open_remedy_shop() -> void:
	ItemSource.open("medicine_" + String(_species_state().get("disease", "")))


func _open_collection() -> void:
	ScreenRouter.go("creatures")
	var screen := ScreenRouter.host.get_child(ScreenRouter.host.get_child_count() - 1)
	screen.call_deferred("select_entry", "creatures", selected_species)


func _advance_day() -> void:
	_has_care_result = true
	var succeeded := GameState.advance_day()
	_last_action_failed = not succeeded
	feedback = tr("Ngày mới: xem thức ăn, sản phẩm và hỗ trợ.") if succeeded else GameState.status
	_refresh()
	if not succeeded:
		var context := find_child("AnimalCareContext", true, false) as Control
		if context != null: context.visible = true
		_refresh_selection_feedback()
