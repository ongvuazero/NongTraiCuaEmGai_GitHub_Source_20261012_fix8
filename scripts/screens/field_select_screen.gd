extends BaseScreen

const Fields = preload("res://scripts/field_zones.gd")


func build() -> void:
	bind_top_hud()
	set_meta("TRUE_WYSIWYG_V2", "PASS")
	set_meta("v7_visual_status", "V7_PHASE2_FIELD_SELECT_TRUE_WYSIWYG_V2")
	for index in range(Fields.IDS.size()):
		_configure_field_card(index, String(Fields.IDS[index]))
	bind_button("BackToHub", ScreenRouter.go.bind("hub"))


func _configure_field_card(index: int, zone: String) -> void:
	var prefix := "FieldCard%02d" % (index + 1)
	var card := get_node("MainBoard/" + prefix) as Panel
	var available := GameState.is_field_zone_open(zone)
	var title := card.get_node(prefix + "Label") as Label
	title.position = Vector2(198, 14)
	title.size = Vector2(196, 34)
	title.text = tr(String(Fields.LABELS[zone]))
	_fit_label(title, 19, 13)
	var detail := card.get_node(prefix + "Label_02") as Label
	detail.text = tr("12 independent plots")
	if not available:
		detail.text += "\n" + tr("Opens on day %d") % Fields.open_day(zone)
		detail.text += "\n" + tr("Day %d / %d") % [int(GameState.data.get("day", 1)), Fields.open_day(zone)]
	else:
		detail.text += "\n" + tr("Available")
	_fit_label(detail, 16, 12)
	var preview := card.get_node("FieldPreview_%d" % index) as TextureRect
	var plate_path := Fields.background_path(zone)
	if ResourceLoader.exists(plate_path): preview.texture = load(plate_path)
	preview.modulate = Color.WHITE if available else Color(0.72, 0.72, 0.72, 1)
	var surface := card.get_node_or_null(prefix + "Surface") as Control
	if surface != null:
		surface.visible = not available
		var badge := surface.get_child(0) as Label
		badge.text = tr("Opens on day %d") % Fields.open_day(zone)
		_fit_label(badge, 16, 11)
	var art := card.get_node_or_null(prefix + "Action") as TextureButton
	if art == null:
		art = (get_node("MainBoard/FieldCard01/FieldCard01Action") as TextureButton).duplicate() as TextureButton
		art.name = prefix + "Action"
		card.add_child(art)
	art.disabled = not available
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := art.get_node("Caption") as Label
	caption.text = tr("Enter field") if available else tr("Opens on day %d") % Fields.open_day(zone)
	_fit_label(caption, 16, 11)
	var button_name := "EnterField" if zone == "home" else "EnterField_" + zone
	var button := card.get_node_or_null(button_name) as Button
	if button == null:
		button = Button.new()
		button.name = button_name
		button.size = card.size
		button.flat = true
		card.add_child(button)
	button.disabled = not available
	button.tooltip_text = tr(String(Fields.LABELS[zone])) + " — " + (tr("Enter field") if available else tr("This field opens on day %d.") % Fields.open_day(zone))
	var callback := _enter_field.bind(zone)
	if not button.pressed.is_connected(callback): button.pressed.connect(callback)
	# The transparent card target owns clicks; captions never block it.
	for child in card.get_children():
		if child is Label: child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.move_child(button, card.get_child_count() - 1)
	card.set_meta("field_zone", zone)
	card.set_meta("field_unlock_day", Fields.open_day(zone))


func _fit_label(label: Label, preferred: int, minimum: int) -> void:
	var point_size := preferred
	while point_size > minimum and label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > label.size.x - 6:
		point_size -= 1
	label.add_theme_font_size_override("font_size", point_size)
	label.tooltip_text = label.text


func _enter_field(zone: String) -> void:
	if GameState.select_field_zone(zone, false):
		ScreenRouter.go(ScreenRouter.FIELD_ROUTE_ID)
	else:
		var caption := get_node("Header/HeaderLabel_02") as Label
		caption.text = tr("Retry save")
		caption.tooltip_text = UILocale.translate_message(GameState.status)
		var index := Fields.IDS.find(zone)
		if index >= 0:
			var prefix := "FieldCard%02d" % (index + 1)
			var detail := get_node("MainBoard/" + prefix + "/" + prefix + "Label_02") as Label
			detail.text = UILocale.translate_message(GameState.status)
			_fit_label(detail, 14, 12)
