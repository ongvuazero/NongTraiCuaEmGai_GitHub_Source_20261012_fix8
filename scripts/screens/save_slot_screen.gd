extends BaseScreen

const V6 = preload("res://v6/runtime/v6_spec_registry.gd")

const RUNTIME_ICON_ASSETS := {
	"slot_flower": "res://v6/art/plates/save/icons/save_slot_icon_flower.png",
	"slot_coin": "res://v6/art/plates/save/icons/save_slot_icon_coin.png",
	"slot_location": "res://v6/art/plates/save/icons/save_slot_icon_location.png",
	"detail_flower": "res://v6/art/plates/save/icons/save_detail_icon_flower.png",
	"detail_coin": "res://v6/art/plates/save/icons/save_detail_icon_coin.png",
	"detail_location": "res://v6/art/plates/save/icons/save_detail_icon_location.png",
	"detail_playtime": "res://v6/art/plates/save/icons/save_detail_icon_playtime.png",
	"detail_lastplayed": "res://v6/art/plates/save/icons/save_detail_icon_lastplayed.png",
	"button_back": "res://v6/art/plates/save/icons/save_button_icon_back.png",
	"button_delete": "res://v6/art/plates/save/icons/save_button_icon_delete.png",
	"button_confirm": "res://v6/art/plates/save/icons/save_button_icon_confirm.png",
	"selected_badge": "res://v6/art/plates/save/save_selected_badge_exact_v6_8_1.png"
}

const RUNTIME_SLOT_ICON_BASE_RECTS := {
	"flower": Rect2(306, 194, 36, 39),
	"coin": Rect2(429, 194, 37, 39),
	"location": Rect2(555, 194, 27, 39),
}

const RUNTIME_DETAIL_ICON_RECTS := {
	"flower": Rect2(752, 468, 45, 46),
	"coin": Rect2(878, 468, 40, 46),
	"location": Rect2(998, 468, 33, 46),
	"playtime": Rect2(752, 523, 44, 47),
	"lastplayed": Rect2(895, 523, 48, 47),
}

const RUNTIME_BUTTON_ICON_RECTS := {
	"BACK": Rect2(66, 620, 46, 54),
	"DELETE": Rect2(816, 617, 45, 56),
	"CONFIRM": Rect2(1025, 616, 49, 58),
}

var geometry: Dictionary
var layout: Dictionary
var parity_data: Dictionary
var parity_mode := false
var reference_fidelity_mode := false
var _refresh_pending := false
var _confirmation_action := ""
var _confirmation_slot := 0
var _confirmation_meta: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Status-only failures must be visible here without rebuilding every game screen.
	if not GameState.status_changed.is_connected(_on_save_status_changed):
		GameState.status_changed.connect(_on_save_status_changed)


func _exit_tree() -> void:
	if GameState.status_changed.is_connected(_on_save_status_changed):
		GameState.status_changed.disconnect(_on_save_status_changed)
	super._exit_tree()


func _on_save_status_changed(_message: String) -> void:
	if GameState.status_context == "save": _refresh()


func _refresh() -> void:
	if _refresh_pending or not is_inside_tree() or is_queued_for_deletion():
		return
	_refresh_pending = true
	call_deferred("_rebuild_save")


func _rebuild_save() -> void:
	_refresh_pending = false
	if not is_inside_tree() or is_queued_for_deletion():
		return
	# Remove the old input targets only after their pressed callback has returned.
	for child in get_children():
		if child.name not in _serialized_root_children:
			remove_child(child)
			child.queue_free()
	build()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not _confirmation_action.is_empty():
		_cancel_confirmation()
		get_viewport().set_input_as_handled()


func build() -> void:
	set_meta("v6_visual_status", "V6_8_3_CANONICAL_SAVE_RUNTIME")
	geometry = V6.geometry("save")
	layout = V6.load_json("res://v6/data/screen_specs/save_dynamic_layout_v6_6.json")
	parity_mode = V6.is_parity_mode()
	reference_fidelity_mode = parity_mode and OS.get_environment("MSF_REFERENCE_FIDELITY") == "1"
	parity_data = V6.parity_fixture().get("save", {}) if parity_mode else {}

	var plate_spec := V6.reference_plate_spec("save")
	if reference_fidelity_mode:
		add_child(UI.texture_rect(String(plate_spec["base_plate"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
		_add_reference_only_hit_targets()
		return

	if parity_mode:
		# Keep the proven V6.8.1 parity path intact.
		add_child(UI.texture_rect("res://v6/art/plates/save/save_unified_static_runtime_base_v6_8_1.png", Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
		add_child(UI.texture_rect(String(plate_spec["static_icon_overlay"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
	else:
		# Shipping/runtime path: state-aware icons replace the unconditional sheet.
		add_child(UI.texture_rect(String(plate_spec["base_plate"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
		add_child(UI.texture_rect(String(plate_spec["ui_overlay_runtime"]), Rect2(0, 0, 1280, 720), TextureRect.STRETCH_SCALE))
		add_child(UI.texture_rect("res://v6/art/plates/save/save_detail_quote_complete_v6_7.png", Rect2(1109, 392, 122, 179), TextureRect.STRETCH_SCALE))
	_add_header_typography()
	for slot_id in range(1, 4):
		_add_slot(slot_id)
	_add_detail()
	var buttons: Dictionary = parity_data.get("buttons", {})
	_add_action_button(String(buttons.get("back", "Quay lại")), "BACK", _back)
	_add_action_button(String(buttons.get("delete", "Xóa")), "DELETE", _delete)
	_add_action_button(String(buttons.get("confirm", "Xác nhận")), "CONFIRM", _confirm)
	_add_preview_footer()
	if not parity_mode:
		_add_save_status()
		if not _confirmation_action.is_empty():
			_add_confirmation_dialog()


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


func _font_size(id: String, fallback: int) -> int:
	var minimum := 14 if id in ["slot_day_season", "slot_money", "slot_location", "slot_flavor", "detail_day_season", "detail_money", "detail_location", "detail_play_time", "detail_last_played"] else 16
	return maxi(minimum, int(layout.get("font_sizes", {}).get(id, fallback)))


func _runtime_location_label(location: String) -> String:
	var names := {"hub": "Trang trại", "field": "Ruộng", "field_select": "Ruộng", "shop": "Cửa hàng", "storage": "Kho", "animal": "Vật nuôi", "dragon": "Đảo Rồng", "quest": "Nhiệm vụ", "settings": "Cài đặt", "islands": "Bản đồ đảo", "craft": "Xưởng", "creatures": "Bạn đồng hành", "events": "Lịch mùa"}
	return tr(String(names.get(location, location)))


func _runtime_season_label(season: String) -> String:
	var normalized := season.to_lower().replace("mùa ", "")
	var season_keys := {"xuân": "spring", "hạ": "summer", "hè": "summer", "thu": "autumn", "đông": "winter"}
	return tr(String(season_keys.get(normalized, normalized)))


func _add_header_typography() -> void:
	if parity_mode:
		return
	var title_text := String(parity_data.get("header_title", "CHỌN Ô LƯU"))
	var subtitle_text := String(parity_data.get("header_subtitle", "Tiếp tục câu chuyện nông trại"))
	var title := UI.label(tr(title_text), V6.visible_rect(geometry, "HEADER_TITLE", "content_rects"), _font_size("header_title", 30), Color("4b2d1a"), HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "SaveMainHeader"
	if not parity_mode:
		var clear_header := V6.visible_rect(geometry, "HEADER_TITLE", "content_rects")
		var font := title.get_theme_font("font")
		var points := _font_size("header_title", 30)
		while points > 18 and (font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > clear_header.size.x - 16 or font.get_height(points) > clear_header.size.y):
			points -= 1
		title.add_theme_font_size_override("font_size", points)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.tooltip_text = title.text
		title.size = clear_header.size
	_apply_parity_type(title, 1, Color("fff1d5"))
	add_child(title)
	add_child(UI.label(tr(subtitle_text), V6.visible_rect(geometry, "HEADER_SUBTITLE", "content_rects"), _font_size("header_subtitle", 16), Color("72513a"), HORIZONTAL_ALIGNMENT_CENTER))


func _slot_rect(slot_id: int) -> Rect2:
	match slot_id:
		1: return V6.visible_rect(geometry, "SLOT_1_SELECTED")
		2: return V6.visible_rect(geometry, "SLOT_2")
		_: return V6.visible_rect(geometry, "SLOT_3")


func _slot_data(slot_id: int) -> Dictionary:
	if parity_mode:
		for candidate in parity_data.get("slots", []):
			if int(candidate.get("slot", 0)) == slot_id:
				var result: Dictionary = candidate.duplicate(true)
				result["valid"] = true
				return result
		return {"occupied": false, "valid": true}
	var meta := GameState.slot_metadata(slot_id)
	var state: Dictionary = {}
	if bool(meta.get("occupied", false)) and bool(meta.get("valid", false)):
		var loaded: Dictionary = GameState.save_service.load_slot(slot_id)
		if bool(loaded.get("ok", false)):
			state = loaded.get("state", {})
	elif bool(meta.get("recoverable", false)):
		# Read the same validated candidate used by metadata without recovering it,
		# replacing live farm data, or guessing its season from another slot.
		var candidate: Dictionary = GameState.save_service.call("_recovery_candidate", GameState.save_service.call("_slot_path", slot_id))
		state = candidate.get("state", {})
	var season_state := state if not state.is_empty() else {"day": int(meta.get("day", 1))}
	return {
		"occupied": bool(meta.get("occupied", false)),
		"valid": bool(meta.get("valid", false)),
		"recoverable": bool(meta.get("recoverable", false)),
		"recovery_source": String(meta.get("recovery_source", "")),
		"primary_missing": bool(meta.get("primary_missing", false)),
		"message": String(meta.get("message", "")),
		"farm_name": String(state.get("farm_name", meta.get("farm_name", "Nông trại của tôi"))),
		"day": int(meta.get("day", 1)),
		"season": WorldSystems.season(season_state),
		"money": int(meta.get("coins", 0)),
		"location": String(meta.get("location", "Nông trại")),
		"flavor": String(state.get("flavor", meta.get("flavor", "Một khởi đầu mới trên nông trại."))),
		"last_played": int(meta.get("last_played", 0)),
		"play_time": String(state.get("play_time", meta.get("play_time", "--"))),
		"thumbnail_path": String(state.get("thumbnail_path", meta.get("thumbnail_path", ""))),
	}


func _slot_field_rect(slot_id: int, field: String) -> Rect2:
	var base := V6.rect_from(layout["slot_1"][field])
	if slot_id == 1:
		return base
	var delta_y := _slot_rect(slot_id).position.y - _slot_rect(1).position.y
	return Rect2(base.position + Vector2(0, delta_y), base.size)


func _runtime_slot_thumbnail_path(slot_id: int, meta: Dictionary) -> String:
	var saved_path := String(meta.get("thumbnail_path", ""))
	if not saved_path.is_empty() and ResourceLoader.exists(saved_path):
		return saved_path
	var fallback := "res://v6/art/plates/save/save_thumb_slot%d_v6_5.png" % slot_id
	if ResourceLoader.exists(fallback):
		return fallback
	return "res://v6/art/plates/save/save_thumb_slot1_v6_5.png"


func _runtime_detail_thumbnail_path(selected_slot: int, meta: Dictionary) -> String:
	var saved_path := String(meta.get("thumbnail_path", ""))
	if not saved_path.is_empty() and ResourceLoader.exists(saved_path):
		return saved_path
	if ResourceLoader.exists("res://v6/art/plates/save/save_thumb_detail_v6_5.png"):
		return "res://v6/art/plates/save/save_thumb_detail_v6_5.png"
	return _runtime_slot_thumbnail_path(selected_slot, meta)


func _add_runtime_slot_icons(slot_id: int) -> void:
	var delta_y := _slot_rect(slot_id).position.y - _slot_rect(1).position.y
	var flower_rect := RUNTIME_SLOT_ICON_BASE_RECTS["flower"]
	var coin_rect := RUNTIME_SLOT_ICON_BASE_RECTS["coin"]
	var location_rect := RUNTIME_SLOT_ICON_BASE_RECTS["location"]
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["slot_flower"], Rect2(flower_rect.position + Vector2(0, delta_y), flower_rect.size), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["slot_coin"], Rect2(coin_rect.position + Vector2(0, delta_y), coin_rect.size), TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["slot_location"], Rect2(location_rect.position + Vector2(0, delta_y), location_rect.size), TextureRect.STRETCH_SCALE))


func _add_slot(slot_id: int) -> void:
	var selected_slot := int(parity_data.get("selected_slot", 1)) if parity_mode else GameState.selected_slot
	var selected := slot_id == selected_slot
	var meta := _slot_data(slot_id)
	var shell_rect := _slot_rect(slot_id)
	var occupied := bool(meta.get("occupied", false)) and bool(meta.get("valid", false))
	var recoverable := bool(meta.get("recoverable", false))
	if occupied or recoverable:
		var thumbnail_path := "res://v6/art/plates/save/save_thumb_slot%d_v6_5.png" % slot_id if parity_mode else _runtime_slot_thumbnail_path(slot_id, meta)
		var snapshot_preview := UI.texture_rect(thumbnail_path, _slot_field_rect(slot_id, "thumbnail"), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		if recoverable and not occupied:
			snapshot_preview.modulate = Color(0.9, 0.85, 0.75, 0.65)
		add_child(snapshot_preview)
	elif not parity_mode:
		var empty_preview := UI.texture_rect("res://v6/art/plates/save/save_thumb_slot1_v6_5.png", _slot_field_rect(slot_id, "thumbnail"), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		empty_preview.name = "EmptySlotPreview%d" % slot_id
		empty_preview.modulate = Color(0.82, 0.75, 0.62, 0.38)
		add_child(empty_preview)
	if selected and not parity_mode:
		var selected_outline := UI.panel(shell_rect, Color("00000000"), Color("ffd33d"), 20)
		selected_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(selected_outline)
	var click := Button.new()
	click.name = "SlotSelect%d" % slot_id
	click.flat = true
	click.position = shell_rect.position
	click.size = shell_rect.size
	click.pressed.connect(_choose_slot.bind(slot_id))
	add_child(click)

	var number := UI.label("%d" % slot_id, _slot_field_rect(slot_id, "number"), _font_size("slot_number", 22), Color("4d3020"), HORIZONTAL_ALIGNMENT_CENTER)
	_apply_parity_type(number, 1, Color("fff1dc"))
	add_child(number)
	var farm_name := String(meta.get("farm_name", "")) if occupied else tr("Recoverable save" if recoverable else ("Corrupt save data" if bool(meta.get("occupied", false)) else "Ô TRỐNG"))
	if occupied and farm_name.strip_edges().is_empty(): farm_name = tr("No farm name")
	var farm := UI.raw_label(farm_name, _slot_field_rect(slot_id, "name"), _font_size("slot_name", 21), Color("3f2a1c"), HORIZONTAL_ALIGNMENT_LEFT)
	farm.name = "SlotFarmName%d" % slot_id
	farm.add_theme_font_override("font", LocaleFonts.for_text(farm_name, LocaleFonts.semibold()))
	farm.clip_text = true
	farm.tooltip_text = farm_name
	_apply_parity_type(farm, 0, Color.TRANSPARENT)
	add_child(farm)
	if occupied or recoverable:
		if not parity_mode:
			_add_runtime_slot_icons(slot_id)
		var day_text := tr("Day %d\n%s") % [int(meta.get("day", 1)), tr(String(meta.get("season", "Spring")))] if parity_mode else tr("Ngày %d\n%s") % [int(meta.get("day", 1)), _runtime_season_label(String(meta.get("season", "spring")))]
		add_child(UI.label(day_text, _slot_field_rect(slot_id, "day_season"), _font_size("slot_day_season", 13), Color("65452f"), HORIZONTAL_ALIGNMENT_LEFT))
		add_child(UI.label(_format_int(int(meta.get("money", 0))), _slot_field_rect(slot_id, "money"), _font_size("slot_money", 14), Color("65452f"), HORIZONTAL_ALIGNMENT_LEFT))
		add_child(UI.label(String(meta.get("location", "Farm")) if parity_mode else _runtime_location_label(String(meta.get("location", "hub"))), _slot_field_rect(slot_id, "location"), _font_size("slot_location", 13), Color("65452f"), HORIZONTAL_ALIGNMENT_LEFT))
		var flavor_text := tr("Backup found. Recover before loading.") if recoverable and not occupied else String(meta.get("flavor", ""))
		var flavor := UI.label(flavor_text, _slot_field_rect(slot_id, "flavor"), _font_size("slot_flavor", 13), Color("85654c"), HORIZONTAL_ALIGNMENT_LEFT)
		flavor.clip_text = true
		flavor.tooltip_text = flavor_text
		add_child(flavor)
	else:
		var flavor_text := tr("No valid recovery copy. This slot is not empty.") if bool(meta.get("occupied", false)) else tr("Bắt đầu một nông trại mới")
		var flavor := UI.label(flavor_text, _slot_field_rect(slot_id, "flavor"), _font_size("slot_flavor", 13), Color("85654c"), HORIZONTAL_ALIGNMENT_LEFT)
		flavor.clip_text = true
		flavor.tooltip_text = flavor_text
		add_child(flavor)
	if selected:
		if parity_mode:
			add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["selected_badge"], Rect2(597, 244, 87, 32), TextureRect.STRETCH_SCALE))
		else:
			var selected_text := tr(String(meta.get("selected_label", "ĐANG CHỌN")))
			var badge := UI.label(selected_text, _slot_field_rect(slot_id, "selected"), 12, Color("694416"), HORIZONTAL_ALIGNMENT_CENTER)
			badge.name = "SelectedSlotBadge%d" % slot_id
			var badge_style := StyleBoxFlat.new()
			badge_style.bg_color = Color("f4cf69")
			badge_style.border_color = Color("b27d2f")
			badge_style.set_border_width_all(2)
			badge_style.set_corner_radius_all(7)
			badge.add_theme_stylebox_override("normal", badge_style)
			add_child(badge)


func _add_runtime_detail_icons() -> void:
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["detail_flower"], RUNTIME_DETAIL_ICON_RECTS["flower"], TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["detail_coin"], RUNTIME_DETAIL_ICON_RECTS["coin"], TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["detail_location"], RUNTIME_DETAIL_ICON_RECTS["location"], TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["detail_playtime"], RUNTIME_DETAIL_ICON_RECTS["playtime"], TextureRect.STRETCH_SCALE))
	add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["detail_lastplayed"], RUNTIME_DETAIL_ICON_RECTS["lastplayed"], TextureRect.STRETCH_SCALE))


func _add_detail() -> void:
	var selected_slot := int(parity_data.get("selected_slot", 1)) if parity_mode else GameState.selected_slot
	var meta: Dictionary = parity_data.get("detail", {}) if parity_mode else _slot_data(selected_slot)
	if not parity_mode:
		var title_text := tr("CHI TIẾT Ô LƯU %d") % selected_slot
		# Outer art includes flowers. Center only in the clear wooden interior;
		# measured translated glyphs, not Latin/source width, own the font fit.
		var clear_title_rect := Rect2(842, 94, 282, 45)
		var detail_title := UI.label(title_text, clear_title_rect, _font_size("detail_title", 25), Color("fff5de"), HORIZONTAL_ALIGNMENT_CENTER)
		detail_title.name = "SaveDetailHeader"
		var title_font := detail_title.get_theme_font("font")
		var title_size := _font_size("detail_title", 25)
		while title_size > 16 and title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > clear_title_rect.size.x - 16:
			title_size -= 1
		detail_title.add_theme_font_size_override("font_size", title_size)
		detail_title.clip_text = true
		detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail_title.tooltip_text = title_text
		detail_title.set_meta("save_header_clear_rect", clear_title_rect)
		add_child(detail_title)
	if bool(meta.get("occupied", true)) and bool(meta.get("valid", true)):
		var detail_thumbnail_path := "res://v6/art/plates/save/save_thumb_detail_v6_5.png" if parity_mode else _runtime_detail_thumbnail_path(selected_slot, meta)
		add_child(UI.texture_rect(detail_thumbnail_path, V6.rect_from(layout["detail"]["thumbnail"]), TextureRect.STRETCH_KEEP_ASPECT_COVERED))
		if not parity_mode:
			_add_runtime_detail_icons()
		var farm_name := String(meta.get("farm_name", ""))
		if farm_name.strip_edges().is_empty(): farm_name = tr("No farm name")
		var farm := UI.raw_label(farm_name, V6.rect_from(layout["detail"]["farm_name"]), _font_size("detail_farm_name", 23), Color("432b1c"), HORIZONTAL_ALIGNMENT_LEFT)
		farm.name = "DetailFarmName"
		farm.clip_text = true
		farm.tooltip_text = farm_name
		_apply_parity_type(farm, 0, Color.TRANSPARENT)
		add_child(farm)
		add_child(UI.label(String(meta.get("flavor", "")), V6.rect_from(layout["detail"]["flavor"]), _font_size("detail_flavor", 13), Color("85654c"), HORIZONTAL_ALIGNMENT_LEFT))
		var detail_day_text := tr("Day %d\n%s") % [int(meta.get("day", 1)), tr(String(meta.get("season", "Spring")))] if parity_mode else tr("Ngày %d\n%s") % [int(meta.get("day", 1)), _runtime_season_label(String(meta.get("season", "spring")))]
		add_child(UI.label(detail_day_text, V6.rect_from(layout["detail"]["day_season"]), _font_size("detail_day_season", 13), Color("533724"), HORIZONTAL_ALIGNMENT_LEFT))
		add_child(UI.label(_format_int(int(meta.get("money", 0))), V6.rect_from(layout["detail"]["money"]), _font_size("detail_money", 14), Color("533724"), HORIZONTAL_ALIGNMENT_LEFT))
		add_child(UI.label(String(meta.get("location", "Farm")) if parity_mode else _runtime_location_label(String(meta.get("location", "hub"))), V6.rect_from(layout["detail"]["location"]), _font_size("detail_location", 13), Color("533724"), HORIZONTAL_ALIGNMENT_LEFT))
		var play_time_value := String(meta.get("play_time", "--"))
		var last_played_value := str(meta.get("last_played", "--"))
		if not parity_mode:
			var date := Time.get_datetime_dict_from_unix_time(int(meta.get("last_played", 0)))
			last_played_value = "%02d/%02d/%04d\n%02d:%02d" % [int(date.day), int(date.month), int(date.year), int(date.hour), int(date.minute)]
		if parity_mode:
			add_child(UI.label(tr("Play Time\n%s") % play_time_value, V6.rect_from(layout["detail"]["play_time"]), _font_size("detail_play_time", 16), Color("74513a"), HORIZONTAL_ALIGNMENT_LEFT))
			add_child(UI.label(tr("Last Played\n%s") % last_played_value, V6.rect_from(layout["detail"]["last_played"]), _font_size("detail_last_played", 16), Color("74513a"), HORIZONTAL_ALIGNMENT_LEFT))
		else:
			add_child(UI.label(tr("Thời gian\n%s") % play_time_value, V6.rect_from(layout["detail"]["play_time"]), _font_size("detail_play_time", 14), Color("74513a"), HORIZONTAL_ALIGNMENT_LEFT))
			var last_played := UI.label(last_played_value, V6.rect_from(layout["detail"]["last_played"]), _font_size("detail_last_played", 14), Color("74513a"), HORIZONTAL_ALIGNMENT_LEFT)
			last_played.tooltip_text = tr("Chơi lần cuối\n%s") % last_played_value
			add_child(last_played)
	elif not parity_mode and bool(meta.get("occupied", false)):
		_add_invalid_detail(meta, selected_slot)
	else:
		if not parity_mode:
			var empty_detail := UI.texture_rect("res://v6/art/plates/save/save_thumb_detail_v6_5.png", V6.rect_from(layout["detail"]["thumbnail"]), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
			empty_detail.name = "EmptyDetailPreview"
			empty_detail.modulate = Color(0.86, 0.80, 0.70, 0.48)
			add_child(empty_detail)
			var empty_message := UI.label(tr("Ô lưu đang trống\nSẵn sàng bắt đầu Ngày 1"), Rect2(757, 404, 342, 73), 20, Color("5c3b24"), HORIZONTAL_ALIGNMENT_CENTER)
			empty_message.name = "EmptySlotDescription"
			add_child(empty_message)
		else:
			add_child(UI.label("Ô lưu đang trống\nSẵn sàng bắt đầu Ngày 1", V6.visible_rect(geometry, "DETAIL_MESSAGE", "content_rects"), 20, Color("5c3b24"), HORIZONTAL_ALIGNMENT_CENTER))


func _add_invalid_detail(meta: Dictionary, slot_id: int) -> void:
	var recoverable := bool(meta.get("recoverable", false))
	var preview := UI.texture_rect(_runtime_detail_thumbnail_path(slot_id, meta), V6.rect_from(layout["detail"]["thumbnail"]), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	preview.name = "RecoveryDetailPreview" if recoverable else "CorruptDetailPreview"
	preview.modulate = Color(0.85, 0.78, 0.66, 0.52)
	add_child(preview)
	var title := UI.label(tr("Recoverable save" if recoverable else "Corrupt save data"), Rect2(758, 400, 348, 38), 20, Color("8e4326"), HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "RecoverySlotDescription" if recoverable else "CorruptSlotDescription"
	add_child(title)
	var description := tr("Backup found. Recover before loading.") if recoverable else tr("No valid recovery copy. This slot is not empty.")
	if recoverable:
		description += "\n" + (tr("Ngày %d\n%s") % [int(meta.get("day", 1)), _runtime_season_label(String(meta.get("season", "spring")))]).replace("\n", " · ")
	var details := UI.label(description, Rect2(758, 441, 348, 67), 15, Color("5c3b24"), HORIZONTAL_ALIGNMENT_CENTER)
	details.name = "RecoverySlotDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(details)
	if recoverable:
		var recover := UI.art_button(tr("Recover save"), Rect2(790, 516, 286, 51))
		recover.name = "RecoverButton"
		recover.pressed.connect(_recover.bind(slot_id))
		add_child(recover)


func _add_save_status() -> void:
	var save_message := GameState.save_status_message()
	if save_message.is_empty():
		return
	var panel := UI.panel(Rect2(251, 612, 518, 67), Color("fff1dced"), Color("a67642"), 10)
	panel.name = "SaveStatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var message := UI.label(save_message, Rect2(13, 5, 492, 57), 14, Color("8e3425"), HORIZONTAL_ALIGNMENT_CENTER)
	message.name = "SaveStatusMessage"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(message)


func _add_confirmation_dialog() -> void:
	# Pending state is not consent. Only ConfirmActionButton invokes the second step.
	var overlay := Control.new()
	overlay.name = "ConfirmDialog"
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(1280, 720)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.name = "InputBlocker"
	shade.color = Color(0.12, 0.09, 0.06, 0.65)
	shade.size = overlay.size
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var panel := UI.panel(Rect2(260, 171, 760, 390), Color("fff1da"), Color("81522b"), 20)
	panel.name = "ConfirmationPanel"
	overlay.add_child(panel)
	var title_key := "Confirm delete" if _confirmation_action == "delete" else "Confirm overwrite"
	var title := UI.label(tr(title_key), Rect2(24, 20, 712, 48), 29, Color("6c351e"), HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ConfirmationTitle"
	title.add_theme_font_override("font", preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf"))
	panel.add_child(title)
	var farm_name := String(_confirmation_meta.get("farm_name", ""))
	if farm_name.strip_edges().is_empty():
		farm_name = tr("No farm name")
	var snapshot := UILocale.text("Slot %d · %s\nDay %d · %s", [_confirmation_slot, farm_name, int(_confirmation_meta.get("day", 1)), _runtime_season_label(String(_confirmation_meta.get("season", "spring")))])
	if not bool(_confirmation_meta.get("valid", false)) and not bool(_confirmation_meta.get("recoverable", false)):
		snapshot = tr("CHI TIẾT Ô LƯU %d") % _confirmation_slot
	if not bool(_confirmation_meta.get("valid", false)):
		snapshot += "\n" + tr("Corrupt or missing primary save")
	var details := UI.raw_label(snapshot, Rect2(28, 78, 704, 106), 20, Color("503320"), HORIZONTAL_ALIGNMENT_CENTER)
	details.name = "ConfirmationDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(details)
	var warning_key := "Remove this slot from the list?\nA deleted copy is kept on this device." if _confirmation_action == "delete" else "Replace this farm with a new Day 1 farm?\nA backup is kept on this device."
	var warning := tr(warning_key)
	var warning_label := UI.label(warning, Rect2(28, 189, 704, 92), 18, Color("973e29"), HORIZONTAL_ALIGNMENT_CENTER)
	warning_label.name = "ConfirmationWarning"
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(warning_label)
	var cancel := UI.art_button(tr("Cancel"), Rect2(70, 308, 282, 57))
	cancel.name = "CancelConfirmationButton"
	cancel.pressed.connect(_cancel_confirmation)
	panel.add_child(cancel)
	var confirm := UI.art_button(tr("Delete save" if _confirmation_action == "delete" else "Overwrite"), Rect2(409, 308, 282, 57))
	confirm.name = "ConfirmActionButton"
	confirm.pressed.connect(_execute_confirmation)
	panel.add_child(confirm)
	var back := UI.art_button(tr("Quay lại"), Rect2(33, 612, 201, 57))
	back.name = "ConfirmationBackButton"
	back.pressed.connect(_cancel_confirmation)
	overlay.add_child(back)
	for target in ["Action_BACK", "Action_DELETE", "Action_CONFIRM", "SlotSelect1", "SlotSelect2", "SlotSelect3", "RecoverButton"]:
		var button := find_child(target, true, false) as BaseButton
		if button != null:
			button.disabled = true
	cancel.grab_focus()


func _add_action_button(text: String, rect_id: String, callback: Callable) -> void:
	var hit_rect := V6.visible_rect(geometry, rect_id)
	if rect_id == "BACK":
		hit_rect = Rect2(33, 612, 201, 57)
	var button := Button.new()
	button.name = "Action_%s" % rect_id
	button.flat = true
	button.position = hit_rect.position
	button.size = hit_rect.size
	button.pressed.connect(callback)
	add_child(button)
	if parity_mode:
		return
	# Keep button art independent from localized runtime captions.
	match rect_id:
		"BACK":
			add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["button_back"], RUNTIME_BUTTON_ICON_RECTS["BACK"], TextureRect.STRETCH_SCALE))
		"DELETE":
			add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["button_delete"], RUNTIME_BUTTON_ICON_RECTS["DELETE"], TextureRect.STRETCH_SCALE))
		"CONFIRM":
			add_child(UI.texture_rect(RUNTIME_ICON_ASSETS["button_confirm"], RUNTIME_BUTTON_ICON_RECTS["CONFIRM"], TextureRect.STRETCH_SCALE))
	var label_rect := V6.rect_from(layout["button_label_rects"][rect_id])
	var font_size := _font_size(rect_id.to_lower(), 20)
	var color := Color("3e291b") if rect_id == "BACK" else Color("fff7e2")
	var caption := UI.label(text, label_rect, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	var outline_color := Color("fff4dc") if rect_id == "BACK" else Color("5b2b1e")
	_apply_parity_type(caption, 1, outline_color)
	add_child(caption)


func _add_reference_only_hit_targets() -> void:
	for slot_id in range(1, 4):
		var click := Button.new()
		click.flat = true
		click.position = _slot_rect(slot_id).position
		click.size = _slot_rect(slot_id).size
		click.pressed.connect(_choose_slot.bind(slot_id))
		add_child(click)
	var callbacks := {
		"BACK": ScreenRouter.go.bind("title"),
		"DELETE": _delete,
		"CONFIRM": _confirm,
	}
	for id in ["BACK", "DELETE", "CONFIRM"]:
		var rect := V6.visible_rect(geometry, id)
		if id == "BACK":
			rect = Rect2(33, 612, 201, 57)
		var button := Button.new()
		button.flat = true
		button.position = rect.position
		button.size = rect.size
		button.pressed.connect(callbacks[id])
		add_child(button)


func _apply_parity_type(label: Label, outline_size: int, outline_color: Color) -> void:
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color("0000002e"))


func _format_int(value: int) -> String:
	var source := str(value)
	var result := ""
	while source.length() > 3:
		result = "," + source.right(3) + result
		source = source.left(source.length() - 3)
	return source + result


func _choose_slot(slot_id: int) -> void:
	if parity_mode or not _confirmation_action.is_empty():
		return
	GameState.cancel_confirmation()
	GameState.choose_slot(slot_id)
	_refresh()


func _confirm() -> void:
	if parity_mode or not _confirmation_action.is_empty():
		return
	# A stale pending core action from an earlier screen is never user consent.
	GameState.cancel_confirmation()
	if GameState.confirm_slot():
		ScreenRouter.go("hub")
	elif GameState.confirm_action == "overwrite":
		_open_confirmation("overwrite")


func _delete() -> void:
	if parity_mode or not _confirmation_action.is_empty():
		return
	GameState.cancel_confirmation()
	GameState.delete_selected_slot()
	if GameState.confirm_action == "delete":
		_open_confirmation("delete")


func _open_confirmation(action: String) -> void:
	_confirmation_action = action
	_confirmation_slot = GameState.selected_slot
	_confirmation_meta = _slot_data(_confirmation_slot).duplicate(true)
	# Show immediately on the first click; the deferred rebuild coalesces status/changed.
	if get_node_or_null("ConfirmDialog") == null:
		_add_confirmation_dialog()
	_refresh()


func _cancel_confirmation() -> void:
	_confirmation_action = ""
	_confirmation_slot = 0
	_confirmation_meta = {}
	GameState.cancel_confirmation()
	var dialog := get_node_or_null("ConfirmDialog") as Control
	if dialog != null:
		dialog.hide()
	_refresh()


func _execute_confirmation() -> void:
	if _confirmation_action.is_empty():
		return
	if GameState.selected_slot != _confirmation_slot or GameState.confirm_action != _confirmation_action:
		_cancel_confirmation()
		GameState.set_status("Save confirmation expired. Please choose the slot again.", false, "save")
		return
	var action := _confirmation_action
	_confirmation_action = ""
	_confirmation_slot = 0
	_confirmation_meta = {}
	var dialog := get_node_or_null("ConfirmDialog") as Control
	if dialog != null:
		dialog.hide()
	if action == "overwrite":
		if GameState.confirm_slot():
			ScreenRouter.go("hub")
	else:
		GameState.delete_selected_slot()
	# Failure is displayed outside the modal, never requiring a hidden second click.
	GameState.cancel_confirmation()
	_refresh()


func _recover(slot_id: int) -> void:
	if parity_mode or not _confirmation_action.is_empty():
		return
	GameState.cancel_confirmation()
	if GameState.recover_slot(slot_id):
		ScreenRouter.go("hub")
	else:
		_refresh()


func _back() -> void:
	if not _confirmation_action.is_empty():
		_cancel_confirmation()
		return
	if not parity_mode:
		GameState.cancel_confirmation()
	ScreenRouter.go("title")
