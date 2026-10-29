extends BaseScreen

const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const LocaleType = preload("res://scripts/localization/locale_fonts.gd")


func build() -> void:
	set_meta("v6_visual_status", "V6_5_REFERENCE_PLATE")
	var spec := V6.parity_spec("title")
	var plate_spec := V6.reference_plate_spec("title")
	var fixture: Dictionary = V6.parity_fixture().get("title", {}) if V6.is_parity_mode() else {}
	add_child(UI.texture_rect(String(plate_spec["base_plate"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(String(plate_spec["ui_overlay"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
	var entries := {
		"CONTINUE": [String(fixture.get("continue", "Tiếp tục")), "continue"],
		"NEW_GAME": [String(fixture.get("new_game", "Trò chơi mới")), "new"],
		"SETTINGS": [String(fixture.get("settings", "Cài đặt")), "settings"],
		"QUIT": [String(fixture.get("quit", "Thoát")), "quit"],
	}
	for control_id in ["CONTINUE", "NEW_GAME", "SETTINGS", "QUIT"]:
		var entry: Array = entries[control_id]
		var mapped_rects := {
			"CONTINUE": Rect2(486, 287, 298, 73),
			"NEW_GAME": Rect2(486, 367, 298, 73),
			"SETTINGS": Rect2(486, 451, 298, 73),
			"QUIT": Rect2(486, 536, 298, 73),
		}
		var mapped_label_rects := {
			"CONTINUE": Rect2(565, 287, 190, 73),
			"NEW_GAME": Rect2(590, 367, 170, 73),
			"SETTINGS": Rect2(580, 451, 180, 73),
			"QUIT": Rect2(580, 536, 180, 73),
		}
		var hit_rect: Rect2 = mapped_rects[control_id]
		var button := Button.new()
		button.flat = true
		button.position = hit_rect.position
		button.size = hit_rect.size
		button.pressed.connect(_action.bind(entry[1]))
		add_child(button)
		var caption := UI.label(tr(String(entry[0])), mapped_label_rects[control_id], 24, Color("3c2818"), HORIZONTAL_ALIGNMENT_CENTER)
		caption.name = "TitleCaption_"+control_id
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var font := LocaleType.for_text(caption.text,LocaleType.semibold())
		caption.add_theme_font_override("font",font)
		var point_size := 24
		while point_size>18 and font.get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x>mapped_label_rects[control_id].size.x-4:
			point_size-=1
		caption.add_theme_font_size_override("font_size",point_size)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if font.get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x>mapped_label_rects[control_id].size.x-4 else TextServer.AUTOWRAP_OFF
		caption.clip_text = true
		caption.tooltip_text = caption.text
		caption.add_theme_color_override("font_outline_color", Color("fff4dc"))
		caption.add_theme_constant_override("outline_size", 1)
		add_child(caption)
	_add_preview_footer()


func _add_preview_footer() -> void:
	# Cover only the baked technical identifier strip, not decorative art signs.
	var footer := Panel.new()
	footer.name = "PreviewBuildFooter"
	footer.position = Vector2(0, 688)
	footer.size = Vector2(280, 32)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("242825")
	footer.add_theme_stylebox_override("panel", surface)
	add_child(footer)
	var caption := UI.label(tr("Bản thử nghiệm"), Rect2(18, 0, 250, 32), 14, Color("e5e7df"))
	caption.name = "PreviewBuildCaption"
	footer.add_child(caption)

func _action(action: String) -> void:
	match action:
		"continue":
			GameState.save_mode = "continue"
			var latest := GameState.latest_slot()
			if latest > 0: GameState.selected_slot = latest
			ScreenRouter.go("save")
		"new":
			GameState.save_mode = "new"
			ScreenRouter.go("save")
		"settings":
			GameState.settings_return = "title"
			ScreenRouter.go("settings")
		"quit": get_tree().quit()
