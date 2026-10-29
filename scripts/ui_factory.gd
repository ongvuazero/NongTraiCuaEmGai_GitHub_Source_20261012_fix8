extends RefCounted
class_name UIFactory

const Assets = preload("res://scripts/ui_asset_registry.gd")
const ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY"


static func texture_rect(source, rect: Rect2, stretch := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var node := TextureRect.new()
	node.position = rect.position
	node.size = rect.size
	node.texture = load(source) if source is String else source
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = stretch
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func nine_patch(source, rect: Rect2, margin := 56) -> NinePatchRect:
	var node := NinePatchRect.new()
	node.position = rect.position
	node.size = rect.size
	node.texture = load(source) if source is String else source
	node.patch_margin_left = margin
	node.patch_margin_top = margin
	node.patch_margin_right = margin
	node.patch_margin_bottom = margin
	node.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	node.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func background(screen: String) -> TextureRect:
	var path: String = Assets.ENVIRONMENT_LAYERS.get(screen, [Assets.BACKGROUNDS.get(screen, Assets.BACKGROUNDS["hub"])])[0]
	return texture_rect(path, Rect2(0, 0, 1280, 720), TextureRect.STRETCH_KEEP_ASPECT_COVERED)


static func label(text: String, rect: Rect2, size := 22, color := Color("4a2b19"), align := HORIZONTAL_ALIGNMENT_LEFT, raw := false) -> Label:
	var node := Label.new()
	node.position = rect.position
	node.size = rect.size
	if raw: node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.text = text if raw else UILocale.translate_message(text)
	node.add_theme_font_override("font", LocaleFonts.for_text(node.text, LocaleFonts.regular()))
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func raw_label(text: String, rect: Rect2, size := 22, color := Color("4a2b19"), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	# Player-authored values are not message keys; they must survive locale changes.
	return label(text, rect, size, color, align, true)


static func art_button(text: String, rect: Rect2, family: String = "primary_medium") -> TextureButton:
	var button := TextureButton.new()
	button.position = rect.position
	button.size = rect.size
	var base := ROOT + "/UI/SHARED_BUTTONS/%s/" % family
	button.texture_normal = load(base + "default.png")
	button.texture_hover = load(base + "hover.png") if ResourceLoader.exists(base + "hover.png") else button.texture_normal
	button.texture_pressed = load(base + "pressed.png") if ResourceLoader.exists(base + "pressed.png") else button.texture_normal
	button.texture_disabled = load(base + "disabled.png") if ResourceLoader.exists(base + "disabled.png") else button.texture_normal
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	var caption_color := Color("fff3c4") if family == "night_next_day" else Color("3f2a18")
	var caption_rect := Rect2(Vector2.ZERO, rect.size)
	var caption_size := 22
	if family == "night_next_day":
		caption_rect = Rect2(42, 0, rect.size.x - 48, rect.size.y)
		caption_size = 16
	var caption := label(text, caption_rect, caption_size, caption_color, HORIZONTAL_ALIGNMENT_CENTER)
	caption.add_theme_font_override("font", preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf"))
	button.add_child(caption)
	return button


static func title_button(text: String, rect: Rect2) -> TextureButton:
	var button := TextureButton.new()
	button.position = rect.position
	button.size = rect.size
	var base := ROOT + "/UI/TITLE_SAVE_HOME/title_button_frame_"
	button.texture_normal = load(base + "default.png")
	button.texture_hover = load(base + "hover.png")
	button.texture_pressed = load(base + "pressed.png")
	button.texture_disabled = load(base + "disabled.png")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	var caption := label(text, Rect2(Vector2.ZERO, rect.size), 24, Color("3c2818"), HORIZONTAL_ALIGNMENT_CENTER)
	caption.add_theme_font_override("font", preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf"))
	button.add_child(caption)
	return button


static func panel(rect: Rect2, color := Color("f7e7c8"), border := Color("74451f"), radius := 18) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(4)
	style.set_corner_radius_all(radius)
	node.add_theme_stylebox_override("panel", style)
	return node


static func add_hud(root: Control, title := "", emphasized := false) -> void:
	# V16 component-map lock: shared HUD geometry from the 1280x720 manifests.
	var logo_rect := Rect2(26, 12, 235, 103)
	var logo := texture_rect(ROOT + "/UI/TITLE_SAVE_HOME/canonical_logo.png", logo_rect)
	root.add_child(logo)
	var values := [TranslationServer.translate("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), TranslationServer.translate(GameState.current_season())], "%d" % int(GameState.data.get("coins", 0)), "%d" % int(GameState.data.get("energy", 0)), "%d" % GameState.dragon_energy()]
	var chips := ["day_season_chip", "money_chip", "energy_chip", "long_khi_chip"]
	for i in range(4):
		var locked_rects := [Rect2(530, 13, 164, 55), Rect2(700, 15, 164, 53), Rect2(871, 14, 171, 54), Rect2(1050, 15, 207, 54)]
		var chip_rect: Rect2 = locked_rects[i]
		root.add_child(texture_rect(ROOT + "/UI/HUD/%s.png" % chips[i], chip_rect, TextureRect.STRETCH_SCALE))
		var value_label := label(values[i], Rect2(chip_rect.position.x + 52, chip_rect.position.y + 2, chip_rect.size.x - 58, chip_rect.size.y - 4), 15 if i == 0 else 17, Color("3b281a"), HORIZONTAL_ALIGNMENT_CENTER)
		value_label.name = ["HUD_DaySeasonLabel", "HUD_CoinValue", "HUD_EnergyValue", "HUD_DragonEnergyValue"][i]
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i == 0: value_label.add_theme_constant_override("line_spacing", -4)
		root.add_child(value_label)
	# Screen headings have their own mapped plaques. Do not add an unmapped HUD title.


static func add_active_hud(root: Control) -> void:
	# V4-only HUD for open screens 04-10. Frozen screens continue to use add_hud().
	root.add_child(texture_rect(ROOT + "/UI/TITLE_SAVE_HOME/canonical_logo.png", Rect2(24, 10, 252, 111)))
	var values := [TranslationServer.translate("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), TranslationServer.translate(GameState.current_season())], "%d" % int(GameState.data.get("coins", 0)), "%d" % int(GameState.data.get("energy", 0)), "%d" % GameState.dragon_energy()]
	var chips := ["day_season_chip", "money_chip", "energy_chip", "long_khi_chip"]
	var rects := [Rect2(505, 9, 184, 62), Rect2(696, 9, 182, 62), Rect2(885, 9, 184, 62), Rect2(1076, 9, 198, 62)]
	for i in range(4):
		var chip_rect: Rect2 = rects[i]
		root.add_child(texture_rect(ROOT + "/UI/HUD/%s.png" % chips[i], chip_rect, TextureRect.STRETCH_SCALE))
		var value_label := label(values[i], Rect2(chip_rect.position.x + 54, chip_rect.position.y + 3, chip_rect.size.x - 61, chip_rect.size.y - 6), 17 if i == 0 else 19, Color("3b281a"), HORIZONTAL_ALIGNMENT_CENTER)
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(value_label)


static func add_hud_layout(root: Control, logo_rect: Rect2, chip_rects: Array[Rect2], value_rects: Array[Rect2]) -> void:
	assert(chip_rects.size() == 4, "V6 HUD requires four locked chip rects")
	assert(value_rects.size() == 4, "V6 HUD requires four locked value rects")
	root.add_child(texture_rect(ROOT + "/UI/TITLE_SAVE_HOME/canonical_logo.png", logo_rect))
	var values := [TranslationServer.translate("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), TranslationServer.translate(GameState.current_season())], "%d" % int(GameState.data.get("coins", 0)), "%d" % int(GameState.data.get("energy", 0)), "%d" % GameState.dragon_energy()]
	var chips := ["day_season_chip", "money_chip", "energy_chip", "long_khi_chip"]
	for i in range(4):
		var chip_rect: Rect2 = chip_rects[i]
		root.add_child(texture_rect(ROOT + "/UI/HUD/%s.png" % chips[i], chip_rect, TextureRect.STRETCH_SCALE))
		var value_label := label(values[i], value_rects[i], 14 if i == 0 else 16, Color("3b281a"), HORIZONTAL_ALIGNMENT_CENTER)
		root.add_child(value_label)


static func add_bottom_nav(root: Control, active := "") -> void:
	var nav := panel(Rect2(250, 645, 780, 65), Color("5a351fe8"), Color("b87a3a"), 16)
	root.add_child(nav)
	var items := [["Trang trai", "hub"], ["Ruong", "field_select"], ["Shop", "shop"], ["Kho", "storage"], ["Vat nuoi", "animal"], ["Dragon nav", "dragon"]]
	for i in range(items.size()):
		var b := title_button(items[i][0], Rect2(12 + i * 127, 10, 116, 45))
		(b.get_child(0) as Label).add_theme_font_size_override("font_size", 16)
		b.disabled = items[i][1] == active
		b.pressed.connect(ScreenRouter.go.bind(items[i][1]))
		nav.add_child(b)


static func add_left_nav(root: Control, active := "") -> void:
	var items := [
		["Ruộng", "field_select"],
		["Cửa hàng", "shop"],
		["Kho", "storage"],
		["Vật nuôi", "animal"],
		["Đảo Rồng", "dragon"],
		["Nhiệm vụ", "quest"],
		["Cài đặt", "settings"],
	]
	for i in range(items.size()):
		var button := title_button(items[i][0], Rect2(24, 129 + i * 66, 207, 60))
		button.name = "LeftNav_%s" % items[i][1]
		(button.get_child(0) as Label).add_theme_font_size_override("font_size", 18)
		button.disabled = items[i][1] == active
		button.pressed.connect(ScreenRouter.go.bind(items[i][1]))
		root.add_child(button)
	var rest := art_button("Nghỉ / Ngày mới", Rect2(21, 593, 225, 61), "night_next_day")
	rest.name = "LeftNav_RestNextDay"
	rest.pressed.connect(GameState.advance_day)
	root.add_child(rest)
