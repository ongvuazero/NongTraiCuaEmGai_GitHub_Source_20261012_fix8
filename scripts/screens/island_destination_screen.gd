extends BaseScreen

const Nav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const BodyArt = preload("res://scripts/ui/companion_body_art.gd")
const Target = preload("res://scripts/ui/destination_world_target.gd")
const ActionEffect = preload("res://scripts/ui/destination_action_effect.gd")
const CarePresentation = preload("res://scripts/ui/dragon_world_presenter.gd")
const CaptionBadge = preload("res://scripts/ui/world_caption_badge.gd")
const TimberHeader = preload("res://scripts/ui/destination_timber_header.gd")
const LAYOUT_PATH := "res://data/presentation/island_destination_layout_v2.json"
var island_id := "botanical"
var context: Control
var title: Label
var detail: Label
var preview: TextureRect
var action_root: Control
var result: Label
var selector: OptionButton
var current_group := ""
var current_id := ""
var _bodies: Dictionary = {}
var _body_states: Dictionary = {}
var _landmarks: Dictionary = {}
var _records: Dictionary = {}
var _layout: Dictionary = {}
var _island_layout: Dictionary = {}
var _selector_ids: Array[String] = []
var _body_clock := 0.0
var _last_effect: Control
var _care_icons: Dictionary = {}
var _result_badge: Control

func _t(vi: String, en: String) -> String:
	return UILocale.pair(vi, en)

func build() -> void:
	set_meta("UI_IN_PLACE_REFRESH", true)
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	_island_layout = _layout.islands.get(island_id, {})
	set_meta("presentation_manifest", LAYOUT_PATH)
	var art := "res://assets/approved_world_v2/destinations/" + island_id + ".png"
	if island_id == "snake": art = "res://assets/living_world_v1/snake_painterly_pilot.png"
	if not ResourceLoader.exists(art): art = "res://assets/approved_world_v1/destinations/" + island_id + ".png"
	var background := UI.texture_rect(art, Rect2(0, 0, 1280, 720), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	background.name = "DestinationBackground"
	background.z_index = -100
	add_child(background)
	var hud := Control.new()
	hud.name = "DestinationHUD"
	hud.z_index = 1000
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	UI.add_hud(hud)
	Nav.style_logo(hud.get_child(0) as TextureRect)
	var routes := [["Ruộng", "Field", "field_select", "field"], ["Cửa hàng", "Shop", "shop", "shop"], ["Kho", "Storage", "storage", "storage"], ["Vật nuôi", "Animals", "animal", "animal"], ["Đảo Rồng", "Dragons", "dragon", "dragon"], ["Nhiệm vụ", "Orders", "quest", "quest"], ["Cài đặt", "Settings", "settings", "settings"]]
	for i in range(routes.size()):
		var route: Array = routes[i]
		_button("DestinationNav_" + route[2], _t(route[0], route[1]), Rect2(20, 129 + i * 62, 217, 58), route[3], hud).pressed.connect(ScreenRouter.go.bind(route[2]))
	_button("DestinationBackMap", _t("Bản đồ đảo", "Island map"), Rect2(20, 635, 218, 58), "islands", hud).pressed.connect(ScreenRouter.go.bind("islands"))
	var next_day := UI.art_button(_t("Ngày mới", "Next day"),Rect2(1060,648,202,57),"night_next_day")
	next_day.name = "DestinationNextDay"
	hud.add_child(next_day)
	next_day.pressed.connect(_next_day)
	var island: Dictionary = GameState.world_config().islands.get(island_id, {})
	var sign := _button("DestinationArrival", tr(String(island.get("name", island_id))), Rect2(458, 109, 350, 57), "islands", hud)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrival_caption := sign.get_node("Caption") as Label
	arrival_caption.add_theme_font_override("font", TimberHeader.FONT)
	arrival_caption.add_theme_font_size_override("font_size", 20)
	var hint := CaptionBadge.new()
	hint.name = "DestinationArrivalHint"
	hint.setup(_t("Chạm vào vườn, công trình hoặc bạn đồng hành", "Touch a garden, building or companion"), 610, "", 14)
	hint.position = Vector2(285, 173)
	hud.add_child(hint)
	var farmer_record: Dictionary = _island_layout.get("farmer", _layout.farmer)
	var farmer_size := _vector(farmer_record.size)
	var farmer := UI.texture_rect(ROOT + "/ANIMATION/FARMER/idle/frame_01.png", Rect2(_vector(farmer_record.feet) - farmer_size * _vector(farmer_record.pivot), farmer_size))
	farmer.name = "DestinationFarmer"
	farmer.z_index = int(farmer_record.feet[1])
	add_child(farmer)
	_build_landmarks()
	_build_context()
	_refresh()

func _vector(values: Array) -> Vector2:
	return Vector2(values[0],values[1])

func _button(id: String, caption: String, rect: Rect2, icon: String, parent: Control, font_size := 16) -> TextureButton:
	var button := UI.title_button(caption, rect)
	button.name = id
	parent.add_child(button)
	if caption != "×": Nav.style_button(button, icon, caption, font_size)
	return button

func _ids_for(group: String) -> Array[String]:
	var ids: Array[String] = []
	for id in GameState.world_config().get(group, {}):
		var spec: Dictionary = GameState.world_config()[group][id]
		var location := String(spec.get("island", ""))
		if group == "recipes" and location.is_empty(): location = String(GameState.world_config().buildings.get(spec.get("building", ""), {}).get("island", ""))
		if location == island_id: ids.append(String(id))
	return ids

func _build_landmarks() -> void:
	for record in _island_layout.get("landmarks", []):
		var id := String(record.id)
		var group := String(record.group)
		var key := group + "/" + id
		var spec: Dictionary = GameState.world_config().get(group, {}).get(id, {})
		var item_id := String(record.get("texture", id))
		var caption := tr(String(spec.get("name", id)))
		if group == "recipes": caption = _t("Bàn bào chế", "Brewing table")
		if group == "gather":
			item_id = String(GameState.world_config().islands[island_id].gather_item)
			caption = tr(String(GameState.world_config().items[item_id].name))
		var object := Target.new()
		object.name = "DestinationGather" if group == "gather" else "DestinationLandmark_" + group + "_" + id
		object.setup(record, Assets.get_item_texture(item_id), Assets.get_item_texture(String(spec.get("item", id))), caption)
		object.set_meta("config_id", id)
		object.set_meta("config_group", group)
		object.set_meta("feet", _vector(record.feet))
		object.set_meta("hit_shape", record.hit_shape)
		object.pressed.connect(_open_entry.bind(group,id))
		add_child(object)
		_landmarks[key] = object
		_records[key] = record
	for record in _island_layout.get("actors", []):
		var id := String(record.id)
		if id not in _ids_for("creatures"):
			push_error("Destination manifest species is outside island membership: " + id)
			continue
		var texture := BodyArt.texture(id)
		if texture == null: continue
		var body := TextureButton.new()
		body.name = "DestinationBody_" + id
		body.texture_normal = texture
		body.texture_hover = texture
		body.ignore_texture_size = true
		body.stretch_mode = TextureButton.STRETCH_SCALE
		body.size = _vector(record.size)
		body.position = _vector(record.feet) - body.size * _vector(record.pivot)
		body.pivot_offset = body.size * _vector(record.pivot)
		body.z_index = int(record.feet[1])
		body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(texture.get_image(),0.18)
		body.texture_click_mask = bitmap
		body.set_meta("config_id", id)
		body.set_meta("feet", _vector(record.feet))
		body.set_meta("terrain", record.terrain)
		body.set_meta("source_animation", "static art; procedural breathing/pose feedback")
		body.pressed.connect(_open_entry.bind("creatures",id))
		body.tooltip_text = tr(String(GameState.world_config().creatures[id].name))
		add_child(body)
		_bodies[id] = body
		_records["creatures/" + id] = record
		var badge := CaptionBadge.new()
		badge.name = "DestinationCreatureState_" + id
		var badge_width := clampf(body.size.x, 146, 196)
		var caption_override: Array = record.get("caption_rect",[])
		if caption_override.size() == 4: badge_width = float(caption_override[2])
		badge.setup(tr(String(GameState.world_config().creatures[id].name)), badge_width)
		badge.position = Vector2(clampf(body.position.x + (body.size.x - badge_width) * 0.5, 252, 934 - badge_width) - body.position.x, body.size.y + 6)
		if caption_override.size() == 4:
			badge.position = Vector2(caption_override[0],caption_override[1])-body.position
			badge.set_meta("caption_override",caption_override)
		body.add_child(badge)
		var dirt := UI.texture_rect(Assets.animal_overlay("dirty_mud_dust"), Rect2(body.size * Vector2(0.25,0.54), body.size * Vector2(0.5,0.37)))
		dirt.name = "DirtyOverlay"
		body.add_child(dirt)
		var product := UI.texture_rect(Assets.get_item_texture(String(GameState.world_config().creatures[id].product)), Rect2(body.size.x - 31, 6, 29, 29))
		product.name = "ProductReady"
		body.add_child(product)
		_body_states[id] = badge
		var vacancy := _button("DestinationVacancy_" + id, tr(String(GameState.world_config().creatures[id].name)), Rect2(_vector(record.feet) - Vector2(83,47),Vector2(166,43)), "creatures",self)
		vacancy.z_index = int(record.feet[1])
		vacancy.pressed.connect(_open_entry.bind("creatures",id))

func _build_context() -> void:
	var rect: Array = _layout.context
	context = UI.panel(Rect2(rect[0],rect[1],rect[2],rect[3]))
	context.name = "DestinationContext"
	context.visible = false
	context.z_index = 1000
	var paper := StyleBoxTexture.new()
	paper.texture = TimberHeader.panel_texture()
	paper.set_texture_margin(SIDE_LEFT,28)
	paper.set_texture_margin(SIDE_RIGHT,28)
	paper.set_texture_margin(SIDE_TOP,125)
	paper.set_texture_margin(SIDE_BOTTOM,40)
	context.add_theme_stylebox_override("panel",paper)
	add_child(context)
	title = UI.label("",TimberHeader.SAFE_RECT,20,Color("fff2da"),HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "DestinationContextTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.add_child(title)
	_button("CloseDestinationContext", "×",Rect2(276,7,36,36),"book",context).pressed.connect(close_top_presentation)
	selector = OptionButton.new()
	selector.name = "DestinationRecipeSelector"
	selector.position = Vector2(34,128)
	selector.size = Vector2(254,31)
	selector.add_theme_font_size_override("font_size",14)
	_style_recipe_selector(selector)
	selector.item_selected.connect(_select_recipe)
	context.add_child(selector)
	preview = UI.texture_rect(null,Rect2(105,127,110,84))
	preview.name = "DestinationContextPreview"
	context.add_child(preview)
	detail = UI.label("",Rect2(34,211,254,81),14)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.add_child(detail)
	action_root = Control.new()
	action_root.name = "DestinationContextActions"
	action_root.position = Vector2(34,308)
	action_root.size = Vector2(254,100)
	action_root.set_meta("mobile_touch_rows",true)
	context.add_child(action_root)
	_result_badge = CaptionBadge.new()
	_result_badge.name = "DestinationResultPlaque"
	_result_badge.setup("", 968, "", 14, Rect2(281,77,968,84))
	_result_badge.position = Vector2(281, 77)
	_result_badge.z_index = 1000
	_result_badge.visible = false
	add_child(_result_badge)
	result = _result_badge.caption
	result.name = "DestinationActionResult"

func _style_recipe_selector(button: OptionButton) -> void:
	# Keep the native keyboard/list semantics, but use the game's cream/wood
	# shell and paper palette instead of the default grey software control.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var shell := StyleBoxTexture.new()
		shell.texture = Nav._shell("hover" if state in ["hover", "pressed", "focus"] else "disabled" if state == "disabled" else "normal")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: shell.set_texture_margin(side, 9.0)
		shell.content_margin_left = 13.0
		shell.content_margin_right = 29.0
		button.add_theme_stylebox_override(state, shell)
	button.add_theme_color_override("font_color", Color("4b2e19"))
	button.add_theme_color_override("font_hover_color", Color("4b2e19"))
	button.add_theme_color_override("font_pressed_color", Color("4b2e19"))
	button.add_theme_color_override("font_hover_pressed_color", Color("4b2e19"))
	button.add_theme_color_override("font_disabled_color", Color("7b684d"))
	button.add_theme_color_override("font_focus_color", Color("4b2e19"))
	button.add_theme_color_override("arrow_modulate", Color("79532e"))
	var popup := button.get_popup()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff0d2")
	paper.border_color = Color("8b5d31")
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(10)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: paper.set_content_margin(side, 9.0)
	popup.add_theme_stylebox_override("panel", paper)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color("6d963f")
	selected.border_color = Color("dfb462")
	selected.set_border_width_all(2)
	selected.set_corner_radius_all(7)
	popup.add_theme_stylebox_override("hover", selected)
	popup.add_theme_color_override("font_color", Color("4b2e19"))
	popup.add_theme_color_override("font_hover_color", Color("fff4da"))
	popup.add_theme_constant_override("v_separation", 9)
	button.set_meta("game_recipe_skin", "cream_wood_paper_v1")

func close_top_presentation() -> bool:
	if context == null or not context.visible: return false
	context.hide()
	for object in _landmarks.values():
		object.selected = false
		object.queue_redraw()
	return true

func _open_entry(group: String,id: String) -> void:
	current_group = group
	current_id = id
	context.show()
	for key in _landmarks:
		_landmarks[key].selected = key == group + "/" + id or (group == "recipes" and key.begins_with("recipes/"))
		_landmarks[key].queue_redraw()
	_selector_ids.clear()
	if group == "recipes": _selector_ids = _ids_for("recipes")
	selector.clear()
	for recipe_id in _selector_ids: selector.add_item(tr(String(GameState.world_config().recipes[recipe_id].name)))
	_refresh()

func _select_recipe(index: int) -> void:
	if index < 0 or index >= _selector_ids.size(): return
	current_id = _selector_ids[index]
	_refresh()

func _refresh() -> void:
	if not is_node_ready() or context == null: return
	bind_top_hud()
	_result_badge.set_copy(result.text)
	_result_badge.visible = not result.text.is_empty()
	var world: Dictionary = GameState.world_state()
	for key in _landmarks:
		var object = _landmarks[key]
		var record: Dictionary = _records[key]
		var id := String(record.id)
		match String(record.group):
			"buildings":
				var level := int(world.buildings.get(id,0))
				var maximum := int(GameState.world_config().buildings.get(id,{}).get("max_level",1))
				object.set_world_state("built" if level > 0 else "unbuilt",(_t("Hoàn tất · Cấp %d", "Completed · Level %d") if level >= maximum else _t("Cấp %d", "Level %d")) % level,level)
			"gardens":
				var garden: Dictionary = world.gardens.get(id,{})
				var state := "empty" if garden.is_empty() else "ready" if garden.get("ready",false) else "wet" if garden.get("watered_today",false) else "growing"
				var caption := _t("Đất trống", "Empty soil") if state == "empty" else _t("Thu hoạch", "Ready to harvest") if state == "ready" else _t("Đã tưới · %d ngày", "Watered · %d days") % int(garden.get("growth",0)) if state == "wet" else _t("Đang lớn · cần tưới", "Growing · water needed")
				object.set_world_state(state,caption)
			"recipes":
				var ready := false
				var queued := false
				for task in world.craft_queue:
					if String(task.recipe) in _ids_for("recipes"):
						queued = true
						ready = ready or bool(task.ready)
				object.set_world_state("ready" if ready else "growing" if queued else "idle",_t("Có món để nhận", "Craft ready") if ready else _t("Đang chế tạo", "Crafting") if queued else _t("Chọn công thức", "Choose recipe"))
			"gather":
				var available := bool(GameState.world_action_info("gather",island_id).get("ok",false))
				object.set_world_state("ready" if available else "depleted",_t("Có thể thu thập", "Ready to gather") if available else _t("Trở lại ngày mai", "Return tomorrow"))
	for id in _bodies:
		var body: TextureButton = _bodies[id]
		var owned: bool = world.creatures.has(id)
		body.visible = owned
		(get_node("DestinationVacancy_" + id) as Control).visible = not owned
		if not owned: continue
		var creature: Dictionary = world.creatures[id]
		var disease := String(creature.get("disease",""))
		var dirty := int(creature.cleanliness) < 40
		var products := int(creature.products_ready)
		var state := "sick" if not disease.is_empty() else "dirty" if dirty else "products" if products > 0 else "owned"
		body.set_meta("world_state",state)
		var caption := tr(String(GameState.world_config().creatures[id].name))
		var status := _t("Cần thuốc: ", "Remedy: ") + tr(String(GameState.world_config().items.get("medicine_" + disease,{}).get("name",disease))) if state == "sick" else _t("Cần dọn sạch", "Needs cleaning") if state == "dirty" else _t("Sản phẩm ×%d", "Products ×%d") % products if products > 0 else _t("Khỏe mạnh", "Healthy")
		_body_states[id].set_copy(caption, status)
		(body.get_node("DirtyOverlay") as Control).visible = dirty
		(body.get_node("ProductReady") as Control).visible = products > 0
		body.self_modulate = Color("e6cbed") if state == "sick" else Color.WHITE
	if not context.visible or current_id.is_empty(): return
	for child in action_root.get_children():
		action_root.remove_child(child)
		child.queue_free()
	selector.visible = current_group == "recipes"
	var mobile_recipe := selector.visible and preload("res://scripts/ui/mobile_runtime.gd").is_mobile()
	preview.position.y = 174 if mobile_recipe else 163 if selector.visible else 127
	preview.size.y = 48 if selector.visible else 84
	detail.position.y = 227 if mobile_recipe else 219
	detail.size.y = 74 if current_group == "creatures" and not String(world.creatures.get(current_id,{}).get("disease","")).is_empty() else 81
	if selector.visible and current_id in _selector_ids: selector.select(_selector_ids.find(current_id))
	var spec: Dictionary = GameState.world_config().get(current_group,{}).get(current_id,{})
	title.text = tr(String(spec.get("name",current_id)))
	match current_group:
		"gather":
			var item := String(GameState.world_config().islands[island_id].gather_item)
			title.text = _t("Thu thập tại đảo", "Island resource")
			preview.texture = Assets.get_item_texture(item)
			detail.text = tr(String(GameState.world_config().items[item].name)) + " ×" + str(GameState.world_config().islands[island_id].gather_amount) + "\n" + _t("Mỗi ngày thu thập một lần.", "Gather once per day.")
			_add_action("gather",island_id,_t("Thu thập", "Gather"))
		"buildings":
			preview.texture = Assets.get_item_texture(current_id)
			var level := int(world.buildings.get(current_id,0))
			var maximum := int(spec.get("max_level",1))
			if level >= maximum:
				detail.text = (_t("Cấp %d / %d\nCông trình đã hoàn tất.\nKhông cần nâng cấp thêm.", "Level %d / %d\nConstruction complete.\nNo further upgrades.")) % [level,maximum]
				_add_action("build",current_id,_t("Đã hoàn tất", "Completed"))
			else:
				detail.text = _t("Cấp %d / %d\nNâng cấp: %d xu", "Level %d / %d\nUpgrade: %d coins") % [level,maximum,int(spec.cost)*(level+1)] + "\n" + _materials(spec.get("items",{}))
				_add_action("build",current_id,_t("Xây / Nâng cấp", "Build / Upgrade"))
		"gardens":
			var garden: Dictionary = world.gardens.get(current_id,{})
			preview.texture = Assets.get_item_texture(String(spec.item))
			detail.text = _t("Lớn: %d / %d ngày\nTưới: %s\nHạt trong kho: %d", "Growth: %d / %d days\nWatered: %s\nSeeds in storage: %d") % [int(garden.get("growth",0)),int(spec.days),_t("Rồi", "Yes") if garden.get("watered_today",false) else _t("Chưa", "No"),int(GameState.data.inventory.get(spec.seed,0))]
			_add_action("plant_garden",current_id,_t("Gieo", "Plant"))
			_add_action("water_garden",current_id,_t("Tưới", "Water"))
			_add_action("harvest_garden",current_id,_t("Thu hoạch", "Harvest"))
		"recipes":
			preview.texture = Assets.get_item_texture(String(spec.output))
			detail.text = _materials(spec.ingredients) + "\n" + (_t("%d xu · %d ngày", "%d coins · %d days") % [int(spec.coins),int(spec.days)])
			_add_action("craft",current_id,_t("Chế tạo", "Craft"))
			_add_action("claim_craft",current_id,_t("Nhận", "Claim"))
		"creatures":
			preview.texture = BodyArt.texture(current_id)
			var creature: Dictionary = world.creatures.get(current_id,{})
			if creature.is_empty():
				if String(spec.kind) == "dragon":
					detail.text = _t("Chưa sở hữu. Ấp đúng trứng nguyên tố tại Đảo Rồng để đón bạn này.", "Not owned. Hatch its elemental egg on Dragon Island.")
				else:
					detail.text = _t("Chưa sở hữu · %d xu", "Not owned · %d coins") % int(spec.cost)
					_add_action("adopt",current_id,_t("Nhận nuôi", "Adopt"))
			else:
				var food := String(spec.food)
				detail.text = (_t("No %d · Sạch %d · Vui %d\nSản phẩm: %d", "Full %d · Clean %d · Happy %d\nProducts: %d") % [int(creature.fullness),int(creature.cleanliness),int(creature.happiness),int(creature.products_ready)]) + "\n" + tr(String(GameState.world_config().items[food].name)) + " ×" + str(GameState.data.inventory.get(food,0))
				if not String(creature.disease).is_empty():
					var remedy := "medicine_" + String(creature.disease)
					detail.text = (_t("No %d · Sạch %d · Vui %d\nCần: %s\nTrong kho: %d", "Full %d · Clean %d · Happy %d\nRemedy: %s\nOwned: %d") % [int(creature.fullness),int(creature.cleanliness),int(creature.happiness),tr(String(GameState.world_config().items.get(remedy,{}).get("name",remedy))),int(GameState.data.inventory.get(remedy,0))])
					_add_action("heal",current_id,_t("Dùng thuốc", "Use remedy"))
				# Illness does not disable care in existing WorldSystems rules.
				# Keep valid actions accessible; eligibility remains authoritative.
				for entry in [["feed","Cho ăn","Feed"],["pet","Vuốt ve","Pet"],["clean","Dọn","Clean"],["collect","Thu","Collect"]]: _add_action(entry[0],current_id,_t(entry[1],entry[2]))
	TimberHeader.fit(title, title.text)
	preload("res://scripts/ui/mobile_runtime.gd").request_control_layout(context)

func _materials(items: Dictionary) -> String:
	var parts: Array[String] = []
	for id in items: parts.append(tr(String(GameState.world_config().items.get(id,{}).get("name",id))) + " ×" + str(items[id]))
	return ", ".join(parts)

func _care_icon(id: String) -> Texture2D:
	# Reuse the measured, approved semantic atlas from Dragon care.
	# Overlay sheets belong to world feedback, not tiny button icons.
	if _care_icons.has(id): return _care_icons[id] as Texture2D
	var source := load(CarePresentation.ICON_ATLAS) as Texture2D
	var region: Rect2 = CarePresentation.ICON_REGIONS[id]
	var factor := source.get_size() / Vector2(1316,1195)
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = Rect2(region.position * factor,region.size * factor)
	texture.filter_clip = true
	_care_icons[id] = texture
	return texture

func _add_action(action: String,id: String,caption: String) -> void:
	var index := action_root.get_child_count()
	var bounds := Rect2((index%2)*130,(index/2)*40,124,37)
	if current_group in ["buildings","gather"] or action == "adopt":
		bounds = Rect2(0,0,254,37)
	elif current_group == "recipes":
		bounds = Rect2(0,index*40,254,37)
	elif action == "harvest_garden":
		bounds = Rect2(0,40,254,37)
	var sick_care := current_group == "creatures" and not String(GameState.world_state().creatures.get(id,{}).get("disease","")).is_empty()
	if sick_care:
		# Wide remedy row + two compact care rows, all inside the paper interior.
		action_root.position.y = 295
		if action == "heal":
			bounds = Rect2(0,0,254,34)
		else:
			index -= 1
			bounds = Rect2((index%2)*130,38+(index/2)*35,124,32)
	else:
		action_root.position.y = 320 if current_group == "recipes" and preload("res://scripts/ui/mobile_runtime.gd").is_mobile() else 308
	var button := _button("DestinationAction_" + action + "_" + id,caption,bounds,"storage" if action in ["collect","gather"] else "field",action_root,14)
	var icon := button.get_node_or_null("NavigationIcon") as TextureRect
	if icon != null:
		var creature: Dictionary = GameState.world_config().creatures.get(id,{})
		match action:
			"plant_garden": icon.texture = Assets.get_item_texture(String(GameState.world_config().gardens[id].seed))
			"water_garden": icon.texture = _care_icon("water")
			"harvest_garden": icon.texture = Assets.get_item_texture(String(GameState.world_config().gardens[id].item))
			"build": icon.texture = Assets.get_item_texture(id)
			"craft", "claim_craft": icon.texture = Assets.get_item_texture(String(GameState.world_config().recipes[id].output))
			"gather": icon.texture = Assets.get_item_texture(String(GameState.world_config().islands[id].gather_item))
			"feed": icon.texture = Assets.get_item_texture(String(creature.get("food","")))
			"pet": icon.texture = _care_icon("pet")
			"clean": icon.texture = _care_icon("clean")
			"collect": icon.texture = Assets.get_item_texture(String(creature.get("product","")))
			"heal": icon.texture = Assets.get_item_texture("medicine_" + String(GameState.world_state().creatures.get(id,{}).get("disease","")))
	var info := GameState.world_action_info(action,id)
	button.disabled = not bool(info.get("ok",false))
	button.tooltip_text = UILocale.translate_message(String(info.get("reason","")))
	button.pressed.connect(_perform.bind(action,id))

func _action_point(action: String,id: String) -> Vector2:
	if action in ["feed","heal"] and _bodies.has(id):
		var body := _bodies[id] as Control
		if body.has_meta("motion_mouth"): return body.get_global_transform()*Vector2(body.get_meta("motion_mouth"))
	var group := "creatures" if action in ["adopt","feed","pet","clean","collect","heal"] else "gardens" if action.ends_with("garden") else "buildings" if action == "build" else "gather" if action == "gather" else "recipes"
	var key := group + "/" + id
	if _records.has(key):
		var point := _vector(_records[key].action_point)
		if group == "creatures" and _bodies.has(id):
			point += (_bodies[id] as Control).get_meta("live_motion_offset",Vector2.ZERO)
		return point
	if group == "recipes":
		for candidate in _records:
			if candidate.begins_with("recipes/"): return _vector(_records[candidate].action_point)
	return Vector2(600,450)

func _perform(action: String,id: String) -> void:
	var point := _action_point(action,id)
	var info := GameState.world_action_info(action,id)
	var feedback_item := ""
	if action in ["feed","collect","heal"]:
		var creature: Dictionary = GameState.world_config().creatures.get(id,{})
		feedback_item = String(creature.get("food","")) if action == "feed" else String(creature.get("product","")) if action == "collect" else "medicine_"+String(GameState.world_state().creatures.get(id,{}).get("disease",""))
	elif action.ends_with("garden"):
		var garden: Dictionary = GameState.world_config().gardens.get(id,{})
		feedback_item = String(garden.get("seed","")) if action == "plant_garden" else String(garden.get("item",""))
	elif action == "gather": feedback_item = String(GameState.world_config().islands[id].gather_item)
	elif action in ["craft","claim_craft"]: feedback_item = String(GameState.world_config().recipes[id].output)
	elif action == "build": feedback_item = id
	var stock_before := GameState.dragon_energy() if feedback_item == "dragon_energy" else int(GameState.data.inventory.get(feedback_item,0))
	var succeeded := false
	if bool(info.get("ok",false)):
		succeeded = GameState.world_action(action,id)
		result.text = UILocale.translate_message(GameState.status)
	else:
		result.text = UILocale.translate_message(String(info.get("reason","")))
	result.set_meta("action_succeeded",succeeded)
	result.set_meta("action",action)
	result.set_meta("target_id",id)
	_refresh()
	if _last_effect != null and is_instance_valid(_last_effect): _last_effect.queue_free()
	var effect := ActionEffect.new()
	effect.name = "DestinationEffect_" + action
	add_child(effect)
	var stock_after := GameState.dragon_energy() if feedback_item == "dragon_energy" else int(GameState.data.inventory.get(feedback_item,0))
	var delta_stock := stock_after-stock_before
	var receipt := ("+%d" % delta_stock if delta_stock > 0 else str(delta_stock)) if succeeded and delta_stock != 0 else "✓" if succeeded else ""
	effect.start(point,action,succeeded,Assets.get_item_texture(feedback_item),receipt)
	_last_effect = effect
	if succeeded and _bodies.has(id):
		var body: TextureButton = _bodies[id]
		body.set_meta("care_action",action)
		body.set_meta("care_action_at_msec",Time.get_ticks_msec())
		if action in ["feed","heal"]:
			var flow := effect.get_node_or_null("SemanticWorldFlow") as Node2D
			if flow != null: flow.follow_mouth(body)
	elif _bodies.has(id):
		(_bodies[id] as Control).set_meta("care_action","")
		(_bodies[id] as Control).set_meta("care_action_at_msec",-10000)

func _next_day() -> void:
	var succeeded := GameState.advance_day()
	result.text = UILocale.translate_message(GameState.status)
	result.set_meta("action_succeeded",succeeded)
	_refresh()

# Complete source-frame playback is owned by LiveCreatureMotion. Whole-body
# scaling is removed so foot roots, click geometry and caption plates stay put.
