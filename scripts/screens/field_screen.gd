extends BaseScreen

const GameSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const Fields = preload("res://scripts/field_zones.gd")

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const FieldStateClass = preload("res://v7/production/field_state.gd")
const RendererClass = preload("res://v7/production/field_renderer.gd")
const ActorClass = preload("res://v7/production/field_actor_depth.gd")
const DebugClass = preload("res://v7/production/field_debug_overlay.gd")
const PlantAssets = preload("res://v7/runtime/runtime_crop_registry_v7_3.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const FieldAudioClass = preload("res://v7/production/field_audio_feedback.gd")
const ToolbarResponseClass = preload("res://v7/production/field_toolbar_response.gd")
const FIELD_AREA_PATH := "EDIT_ME/FieldArea"
const WORLD_RENDERER_PATH := FIELD_AREA_PATH + "/WorldRenderer"
const SEED_ACTION_PATH := "EDIT_ME/BottomActionHUD/ToolGroup/Action_seed"
const SEED_POPUP_PATH := SEED_ACTION_PATH + "/SeedPickerAnchor/SeedPickerGroup"
const FARMER_VISUAL_HEIGHT := 130.0

@export var FIELD_HIT_POLYGON_DEBUG := false
@export var tool_selected_style: StyleBox
@export var tool_hover_style: StyleBox
@export var tool_pressed_style: StyleBox
@export var tool_disabled_style: StyleBox

var feedback := ""
var _feedback_is_error := false
var field_state: Node
var renderer: Node2D
var farmer: Node2D
var debug_overlay: Node2D
var field_audio: Node
var _pending_fx_action := ""
var _pending_fx_plot := 0
var _pending_actor_action := ""
var _pending_growth_plots := PackedInt32Array()
var _pending_reward_crop := ""
var _pending_reward_label := ""
var _pending_reward_quantity := 0
var _qa_static_visual_only := false
var _qa_debug_mode := ""
var _qa_actor_relation := ""
var _seed_popup_open := false
var _active_tool := ""
var _world_rebuild_total := 0
var _last_action_rebuilds := 0
var _last_action_latency_ms := 0.0
var _last_clicked_plot_id := 0
var _pressed_plot_id := 0
var _hover_plot_id := 0
var _toolbar_buttons: Array[TextureButton] = []
var _toolbar_touch_buttons := {}


func build() -> void:
	bind_top_hud()
	_bind_field_hud()
	_bind_field_zone_presentation()
	set_meta("TRUE_WYSIWYG_V2", "VISUAL_REVIEW_REQUIRED")
	set_meta("FIELD_GAMEPLAY_FUNCTIONAL_LOCK", "PASS")
	set_meta("FIELD_GAMEPLAY_DATA_LOCK", "PASS")
	set_meta("FIELD_GAMEPLAY_SAVE_LOCK", "PASS")
	set_meta("FIELD_GAMEPLAY_ROUTE_LOCK", "PASS")
	set_meta("FIELD_WORLD_RENDER_LOCK", "PASS")
	set_meta("FIELD_GAMEPLAY_WORLD_RENDER_RECOVERED", "PASS")
	set_meta("FIELD_GAMEPLAY_UI_EDITABLE", "PASS")
	set_meta("FIELD_GAMEPLAY_VISUAL_LOCK", "OPEN")
	get_node(WORLD_RENDERER_PATH).apply_tuning()
	Geometry.set_plot_offsets({})
	field_state = FieldStateClass.new()
	field_state.name = "RuntimeFieldState"
	add_child(field_state)
	field_state.bind(GameState)
	field_audio = FieldAudioClass.new()
	field_audio.name = "FieldAudioFeedback"
	add_child(field_audio)
	_rebuild_v73_world()
	if not _pending_actor_action.is_empty():
		farmer.play_action(_pending_actor_action)
		_pending_actor_action = ""
	if not _pending_fx_action.is_empty():
		renderer.play_action_fx(_pending_fx_plot, _pending_fx_action)
		_pending_fx_action = ""
		_pending_fx_plot = 0
	if not _pending_growth_plots.is_empty():
		renderer.play_growth_transition(_pending_growth_plots)
		_pending_growth_plots = PackedInt32Array()
	if not _pending_reward_crop.is_empty() and _pending_reward_quantity > 0:
		renderer.play_reward_feedback(field_state.selected_plot_id(), _pending_reward_crop, _pending_reward_label, _pending_reward_quantity)
		_pending_reward_crop = ""
		_pending_reward_label = ""
		_pending_reward_quantity = 0
	_populate_field_gameplay_ui()
	set_process_unhandled_input(false)


func _bind_field_zone_presentation() -> void:
	var zone := GameState.active_field_zone()
	var path := Fields.background_path(zone)
	var plate := get_node("EDIT_ME/Background") as Sprite2D
	var texture := load(path) as Texture2D
	if texture != null:
		plate.texture = texture
		plate.scale = Vector2(1280, 720) / texture.get_size()
		plate.position = Vector2.ZERO
		plate.centered = false
		plate.set_meta("field_zone", zone)
	var plaque := get_node_or_null("EDIT_ME/FieldZonePlaque") as TextureButton
	if plaque == null:
		plaque = UI.art_button("", Rect2(538, 83, 252, 43), "primary_medium")
		plaque.name = "FieldZonePlaque"
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plaque.focus_mode = Control.FOCUS_NONE
		get_node("EDIT_ME").add_child(plaque)
	plaque.position = Vector2(538, 83)
	plaque.size = Vector2(252, 43)
	plaque.z_index = 20
	var caption := plaque.get_child(0) as Label
	caption.text = tr(String(Fields.LABELS[zone]))
	var point_size := 17
	while point_size > 12 and caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > 226:
		point_size -= 1
	caption.add_theme_font_size_override("font_size", point_size)
	caption.tooltip_text = caption.text
	set_meta("active_field_zone", zone)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_instance_valid(field_state) and is_instance_valid(renderer):
		feedback = ""
		_feedback_is_error = false
		_bind_field_hud()
		_bind_field_zone_presentation()
		_populate_field_gameplay_ui()


func _rebuild_v73_world() -> void:
	_world_rebuild_total += 1
	var world_root := get_node(WORLD_RENDERER_PATH) as Node2D
	for child in world_root.get_children():
		child.free()
	renderer = RendererClass.new()
	renderer.name = "V73FieldRenderer"
	world_root.add_child(renderer)
	renderer.render(field_state.plots(), field_state.selected_plot_id())
	_configure_polygon_input()
	_add_runtime_actors()
	debug_overlay = DebugClass.new()
	debug_overlay.name = "FieldDebugOverlay"
	debug_overlay.z_index = 80
	world_root.add_child(debug_overlay)
	debug_overlay.set_mode("hit_polygons" if FIELD_HIT_POLYGON_DEBUG else _qa_debug_mode)


func _configure_polygon_input() -> void:
	for plot_id in range(1, 13):
		var plot := get_node("%s/Plot%02d" % [FIELD_AREA_PATH, plot_id]) as Control
		plot.visible = false
		plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var click := plot.get_node("TECHNICAL/ClickTarget") as BaseButton
		click.disabled = true
		click.mouse_filter = Control.MOUSE_FILTER_IGNORE
		click.focus_mode = Control.FOCUS_NONE
	var field_area := get_node(FIELD_AREA_PATH) as Control
	field_area.mouse_filter = Control.MOUSE_FILTER_STOP
	var callback := Callable(self, "_on_field_polygon_gui_input")
	if not field_area.gui_input.is_connected(callback):
		field_area.gui_input.connect(callback)


func _plot_at_point(local_point: Vector2) -> int:
	var area := get_node(FIELD_AREA_PATH) as Control
	var global_point := area.get_global_transform() * local_point
	for plot_id in range(1, 13):
		var bed := renderer.bed_world.get_node_or_null("Bed_%02d" % plot_id) as Node2D
		if bed != null and Geometry2D.is_point_in_polygon(bed.to_local(global_point), PixelMap.visual_interaction_polygon(plot_id)):
			return plot_id
	return 0


func _on_field_polygon_gui_input(event: InputEvent) -> void:
	if _qa_static_visual_only:
		return
	if event is InputEventMouseMotion:
		_apply_hover_plot(_plot_at_point((event as InputEventMouseMotion).position))
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var plot_id := _plot_at_point(mouse_event.position)
	if mouse_event.pressed:
		_pressed_plot_id = plot_id
		if plot_id > 0:
			_pulse_plot(plot_id)
			(get_node(FIELD_AREA_PATH) as Control).accept_event()
		return
	var pressed_plot := _pressed_plot_id
	_pressed_plot_id = 0
	if pressed_plot > 0 and plot_id == pressed_plot:
		_commit_plot_click(plot_id)
		(get_node(FIELD_AREA_PATH) as Control).accept_event()


func _apply_hover_plot(plot_id: int, force := false) -> void:
	if not force and plot_id == _hover_plot_id:
		return
	if renderer != null and renderer.bed_world != null and _hover_plot_id > 0:
		var previous := renderer.bed_world.get_node_or_null("Bed_%02d" % _hover_plot_id) as CanvasItem
		if previous != null:
			previous.modulate = Color.WHITE
	_hover_plot_id = plot_id
	if renderer != null and renderer.bed_world != null and _hover_plot_id > 0:
		var current := renderer.bed_world.get_node_or_null("Bed_%02d" % _hover_plot_id) as CanvasItem
		if current != null:
			current.modulate = Color(1.035, 1.03, 0.98, 1.0)


func _add_runtime_actors() -> void:
	var farmer_anchor := get_node(FIELD_AREA_PATH + "/FarmerVisual") as TextureRect
	var cat_anchor := get_node(FIELD_AREA_PATH + "/CatVisual") as TextureRect
	var farmer_foot := _stable_farmer_path_anchor(field_state.selected_plot_id())
	if not _qa_actor_relation.is_empty():
		var crop_root := PixelMap.ground_anchor(field_state.selected_plot_id())
		farmer_foot = crop_root + Vector2(-6, 48 if _qa_actor_relation == "front" else -48)
	farmer_anchor.visible = false
	cat_anchor.visible = false
	farmer = ActorClass.new()
	farmer.name = "RuntimeFarmerAtEditableAnchor"
	renderer.crop_world.add_child(farmer)
	farmer.set_field_navigation(renderer.bed_world, renderer.crop_world)
	farmer.configure(farmer.field_point(farmer_foot, field_state.selected_plot_id()), FARMER_VISUAL_HEIGHT)
	farmer.action_contact.connect(_on_farmer_action_contact)
	farmer.walk_step.connect(field_audio.play_step)
	# Join the crops' real ground-root y-sort; never force every limb above all
	# plants. The rig owns its internal assembly order, not global crop depth.
	farmer.z_index = 0
	farmer.set_meta("visual_beside_plot", true)


func _stable_farmer_path_anchor(plot_id: int) -> Vector2:
	# Feet stay in the bed's LEFT grass gutter. Tools reach the near soil edge;
	# inner beds no longer use a distant actor on the opposite field perimeter.
	# Do not park at the bottom lip: top crops in the next row project upward
	# into that strip. The side-of-root stance clears their visible canopy too.
	return ActorClass.authored_work_anchor(plot_id)


func _field_corridor_y(plot_id: int) -> float:
	var row := clampi((plot_id - 1) / 4, 0, 2)
	# Shared horizontal grass strip below each row, clear of the actual soil
	# polygons. The last strip stops above the bottom tool HUD at y=575.
	var bottom := 0.0
	for col in range(4): bottom = maxf(bottom, PixelMap.visual_plot_rect(row * 4 + col + 1).end.y)
	return minf(bottom + 2.0, 573.0)


func _populate_field_gameplay_ui() -> void:
	var panel := get_node("EDIT_ME/CropInfoPanel") as Panel
	var plot: Dictionary = field_state.selected_plot()
	var crop := String(plot.get("crop", ""))
	var crop_name := _crop_display_name(crop) if not crop.is_empty() else tr("EMPTY PLOT")
	(panel.get_node("CropTitle") as Label).text = crop_name
	var title := panel.get_node("CropTitle") as Label
	var title_size := 25
	while title_size > 18 and title.get_theme_font("font").get_string_size(crop_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 206:
		title_size -= 1
	title.add_theme_font_size_override("font_size", title_size)
	var preview := panel.get_node("CropPreview") as TextureRect
	preview.visible = not crop.is_empty()
	preview.texture = (Assets.get_item_texture("crop_" + crop) if bool(plot.get("ready_to_harvest", false)) else _production_crop_texture(crop, int(plot.get("growth_stage", 0)), false)) if not crop.is_empty() else null
	var lifecycle_label := panel.get_node("LifecycleLabel") as Label
	lifecycle_label.text = _panel_state(plot)
	var stage := int(plot.get("growth_stage", 0))
	var max_stage := int(FarmData.CROP_DEFINITIONS.get(crop, {}).get("max_stage", 0))
	var growth_copy := tr("Ready") if bool(plot.get("ready_to_harvest", false)) else tr("%d / %d Days") % [stage, max_stage]
	var detail := tr("GROWTH   %s\nWATER     %s\nYIELD     %s") % [
		tr("Not planted") if crop.is_empty() else growth_copy,
		tr("Watered") if plot.get("watered_today", false) else tr("Dry"),
		"—" if crop.is_empty() else tr("1 crop"),
	]
	detail += "\n" + tr("FERTILIZER %s") % (tr("Fertilized") if bool(plot.get("fertilizer_pending", false)) else tr("Not fertilized"))
	var guidance := _first_session_guidance(plot)
	var panel_tip := ""
	# The completed action owns this panel until the next explicit interaction.
	# Guidance must not hide a commit merely because the first order is unfinished.
	if not feedback.is_empty():
		panel_tip = feedback
		if not _feedback_is_error:
			var next_step := _compact_first_session_next_step(plot)
			if not next_step.is_empty(): panel_tip += "\n" + next_step
	elif not guidance.is_empty():
		panel_tip = guidance
	elif bool(plot.get("ready_to_harvest", false)):
		panel_tip = tr("Harvest when ready.")
	elif not crop.is_empty():
		panel_tip = tr("Water daily.")
	elif bool(plot.get("is_hoed", false)):
		panel_tip = tr("Choose a seed.")
	else:
		panel_tip = tr("Till before planting.")
	var detail_label := panel.get_node("DetailLabel") as Label
	detail_label.visible = false
	var stat_names := panel.get_node("StatNames") as Label
	var stat_values := panel.get_node("StatValues") as Label
	var tip_heading := panel.get_node("TipHeading") as Label
	var tip_text := panel.get_node("TipText") as Label
	# Fit after shaping: bundled Thai/CJK fallbacks increase font line metrics,
	# even for Latin text. The approved panel reflow below preserves every bed
	# and tool rectangle while keeping this complete caption available on hover.
	tip_heading.clip_text = true
	tip_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tip_heading.mouse_filter = Control.MOUSE_FILTER_PASS
	tip_text.mouse_filter = Control.MOUSE_FILTER_PASS
	tip_heading.text = tr("TIP")
	if not _active_tool.is_empty():
		tip_heading.text = tr("Selected: %s") % _tool_display_name(_active_tool)
		if feedback.is_empty():
			if not field_state.tool_available(_active_tool):
				panel_tip = _tool_unavailable_reason(_active_tool)
			elif not guidance.is_empty():
				panel_tip = guidance
			else:
				panel_tip = _tool_instruction(_active_tool)
	tip_heading.tooltip_text = tip_heading.text
	tip_text.text = panel_tip
	tip_text.tooltip_text = (feedback + "\n" if not feedback.is_empty() else "") + guidance if not guidance.is_empty() else panel_tip
	detail_label.text = detail + "\n\n" + tip_heading.text + "\n" + panel_tip
	# Layout belongs to the serialized scene, including manual edits. Refresh
	# changes content/visibility only; an empty plot uses the same authored layout.
	if crop.is_empty():
		preview.visible = false
		stat_names.visible = false
		stat_values.visible = false
	else:
		stat_names.visible = true
		stat_values.visible = true
		stat_names.text = tr("Growth\nWater\nYield")
		stat_values.text = "%d/%d\n%s\n1" % [stage, max_stage, tr("Watered") if plot.get("watered_today", false) else tr("Dry")]
	_fit_field_panel_copy(stat_names, stat_values, tip_heading, tip_text)
	_refresh_seed_access()
	_bind_field_ui()


func _fit_field_panel_copy(names: Label, values: Label, heading: Label, tip: Label) -> void:
	for label in [names, values, heading, tip]:
		# These strings are already translated by the screen, never twice.
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var point_size := 16
	while point_size >= 10:
		names.add_theme_font_size_override("font_size", point_size)
		values.add_theme_font_size_override("font_size", point_size)
		if names.get_minimum_size().x <= 102 and values.get_minimum_size().x <= 91 and maxf(names.get_theme_font("font").get_height(point_size), values.get_theme_font("font").get_height(point_size)) <= 30: break
		if point_size == 10: break
		point_size -= 1
	for label in [names, values]:
		label.add_theme_font_size_override("font_size", point_size)
		# Both columns share a 26px row pitch, independent of fallback ascent.
		label.add_theme_constant_override("line_spacing", int(floor(26.0 - label.get_theme_font("font").get_height(point_size))))
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.tooltip_text = label.text
	names.position = Vector2(24, 213)
	names.size = Vector2(102, 82)
	values.position = Vector2(124, 213)
	values.size = Vector2(91, 82)
	# The divider is painted at global y442. Put the heading below it, not on
	# top of the third stat; use the otherwise-empty lower panel for the tip.
	heading.position = Vector2(24, 312)
	heading.size = Vector2(190, 27)
	var heading_size := 15
	while heading_size >= 11:
		heading.add_theme_font_size_override("font_size", heading_size)
		if (_longest_line_width(heading, heading_size) <= 188 and heading.get_minimum_size().y <= 27) or heading_size == 11: break
		heading_size -= 1
	heading.add_theme_constant_override("line_spacing", -2)
	heading.size = Vector2(190, 27)
	heading.tooltip_text = heading.text
	tip.position = Vector2(24, 344)
	tip.size = Vector2(190, 80)
	tip.add_theme_constant_override("line_spacing", -2)
	var tip_size := 15
	tip.max_lines_visible = 4
	tip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	while tip_size >= 11:
		tip.add_theme_font_size_override("font_size", tip_size)
		# Font paragraph measurement uses per-glyph font metrics, while Label
		# includes the whole fallback chain. Fit the actual Label minimum.
		if tip.get_minimum_size().y <= 80 or tip_size == 11: break
		tip_size -= 1
	while tip.max_lines_visible > 2 and tip.get_minimum_size().y > 80:
		tip.max_lines_visible -= 1
	tip.size = Vector2(190, 80)


func _longest_line_width(label: Label, point_size: int) -> float:
	var width := 0.0
	for line in label.text.split("\n"):
		width = maxf(width, label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x)
	return width


func _refresh_seed_access() -> void:
	var block := get_node_or_null("EDIT_ME/SeedAccess") as Control
	if block == null: return
	var crop := String(GameState.data.get("selected_seed", "carrot"))
	(block.get_node("SeedAccessTitle") as Label).text = tr("Hạt giống")
	(block.get_node("SelectedSeedIcon") as TextureRect).texture = Assets.get_item_texture("seed_" + crop)
	(block.get_node("SelectedSeedStock") as Label).text = "%s ×%d" % [_crop_display_name(crop), int(GameState.data.get("inventory", {}).get("seed_" + crop, 0))]
	(block.get_node("UnlockSummary") as Label).text = tr("Cà chua: Đơn 1 · Bí ngô: Đơn 2") if int(GameState.data.get("orders_done", 0)) < 2 else tr("Cả 3 loại hạt đã mở")
	var open := block.get_node("OpenSeedPicker") as BaseButton
	open.disabled = not field_state.tool_available("seed")
	(open.get_node("Caption") as Label).text = tr("Chọn hạt")
	open.tooltip_text = tr("Choose a seed, then click a tilled plot.")
	GameSkin.apply(open as TextureButton, {"font_size": 16})
	if not open.pressed.is_connected(_toggle_seed_popup): open.pressed.connect(_toggle_seed_popup)


func _panel_state(plot: Dictionary) -> String:
	if bool(plot.get("ready_to_harvest", false)):
		return tr("READY")
	var crop := String(plot.get("crop", ""))
	if crop.is_empty():
		return tr("TILLED") if bool(plot.get("is_hoed", false)) else tr("UNTILLED")
	if bool(plot.get("fertilizer_pending", false)):
		return tr("Fertilized")
	return tr("PLANTED") if int(plot.get("growth_stage", 0)) <= 0 else tr("GROWING")


func _first_session_guidance(plot: Dictionary) -> String:
	if int(GameState.data.get("orders_done", 0)) != 0:
		return ""
	if int(GameState.data.get("inventory", {}).get("crop_carrot", 0)) >= 1:
		return tr("Carrot is in Storage. Open Orders to complete your first order.")
	if bool(plot.get("ready_to_harvest", false)):
		return tr("Carrot is ready. Press HARVEST.")
	if not bool(plot.get("is_hoed", false)):
		return tr("Choose a tool, then tap a plot.")
	var crop := String(plot.get("crop", ""))
	if crop.is_empty():
		return tr("Press PLANT, choose Carrot, then select a plot.")
	if crop == "carrot" and not bool(plot.get("watered_today", false)):
		return tr("Press WATER.")
	if crop == "carrot" and bool(plot.get("watered_today", false)):
		return tr("Press NEXT DAY. Water again tomorrow.")
	return ""


func _compact_first_session_next_step(plot: Dictionary) -> String:
	if int(GameState.data.get("orders_done", 0)) != 0: return ""
	if int(GameState.data.get("inventory", {}).get("crop_carrot", 0)) >= 1:
		return tr("Next: ORDERS.")
	if bool(plot.get("ready_to_harvest", false)): return tr("Next: HARVEST.")
	if not bool(plot.get("is_hoed", false)): return tr("Choose a tool, then tap a plot.")
	if String(plot.get("crop", "")).is_empty(): return tr("Next: PLANT.")
	if String(plot.get("crop", "")) == "carrot":
		return tr("Next: NEXT DAY.") if bool(plot.get("watered_today", false)) else tr("Next: WATER.")
	return ""


func _bind_field_hud() -> void:
	var day_label := get_node("EDIT_ME/TopHUD/HUD_DaySeasonLabel") as Label
	var coin_label := get_node("EDIT_ME/TopHUD/HUD_CoinValue") as Label
	var energy_label := get_node("EDIT_ME/TopHUD/HUD_EnergyValue") as Label
	day_label.text = tr("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), _season_display_name()]
	day_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var day_size := 12 if UILocale.current_locale() == "th" else 14
	var day_pitch := 18 if UILocale.current_locale() == "th" else 17
	while day_size > 11 and (_longest_line_width(day_label, day_size) > 124 or day_label.get_theme_font("font").get_height(day_size) + day_pitch > 44):
		day_size -= 1
	var day_spacing := int(floor(day_pitch - day_label.get_theme_font("font").get_height(day_size)))
	day_label.add_theme_font_size_override("font_size", day_size)
	day_label.add_theme_constant_override("line_spacing", day_spacing)
	# Reset the authored 44px box after font minimums changed on locale switch.
	day_label.position = Vector2(640, 16)
	day_label.size = Vector2(126, 44)
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.tooltip_text = day_label.text
	coin_label.text = str(int(GameState.data.get("coins", 0)))
	energy_label.text = "%d/100" % int(GameState.data.get("energy", 0))


func _season_display_name() -> String:
	match GameState.current_season():
		"spring": return tr("SPRING")
		"summer": return tr("SUMMER")
		"autumn": return tr("AUTUMN")
		"winter": return tr("WINTER")
	return ""


func _bind_field_ui() -> void:
	var action_nodes := {
		"till": "EDIT_ME/BottomActionHUD/ToolGroup/Action_till",
		"water": "EDIT_ME/BottomActionHUD/ToolGroup/Action_water",
		"fertilize": "EDIT_ME/BottomActionHUD/ToolGroup/Action_fertilize",
		"harvest": "EDIT_ME/BottomActionHUD/Action_harvest",
	}
	for action_id in action_nodes:
		var button := get_node(action_nodes[action_id]) as TextureButton
		button.disabled = not field_state.tool_available(String(action_id))
		button.tooltip_text = _tool_unavailable_reason(String(action_id)) if button.disabled else _tool_instruction(String(action_id))
		_bind_toolbar_feedback(button, _active_tool == String(action_id))
		var callback := _on_action_pressed.bind(String(action_id))
		if not _qa_static_visual_only and not button.pressed.is_connected(callback): button.pressed.connect(callback)
	var seed_action := get_node(SEED_ACTION_PATH) as TextureButton
	seed_action.disabled = not field_state.tool_available("seed")
	seed_action.tooltip_text = _tool_unavailable_reason("seed") if seed_action.disabled else tr("Choose a seed, then click a tilled plot.")
	_bind_toolbar_feedback(seed_action, _active_tool == "seed")
	if not _qa_static_visual_only and not seed_action.pressed.is_connected(_toggle_seed_popup): seed_action.pressed.connect(_toggle_seed_popup)
	var next := get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as TextureButton
	next.tooltip_text = tr("Rest until tomorrow. Energy returns to 100.")
	_bind_toolbar_feedback(next)
	if next.has_meta("field_day_result"):
		_toolbar_response(next).set_command_result(tr("Day %d") % int(next.get_meta("field_day_result")))
	if not _qa_static_visual_only and not next.pressed.is_connected(_on_advance_day_pressed): next.pressed.connect(_on_advance_day_pressed)
	var back := get_node("EDIT_ME/FieldBackButton") as TextureButton
	back.tooltip_text = tr("Return to field selection.")
	_bind_toolbar_feedback(back)
	if not _qa_static_visual_only and not back.pressed.is_connected(_on_back_pressed): back.pressed.connect(_on_back_pressed)
	for crop in ["carrot", "tomato", "pumpkin"]:
		var seed := get_node("%s/Seed_%s" % [SEED_POPUP_PATH, crop]) as TextureButton
		seed.texture_normal = Assets.get_item_texture("seed_" + crop)
		seed.disabled = not GameState.is_crop_unlocked(crop)
		seed.tooltip_text = _locked_crop_tooltip(crop) if seed.disabled else tr("Choose %s seeds.") % _crop_display_name(crop)
		_bind_toolbar_feedback(seed, String(GameState.data.get("selected_seed", "carrot")) == crop and not seed.disabled)
		var seed_caption := seed.get_node_or_null("Caption") as Label
		if seed_caption != null:
			var amount := int(GameState.data.get("inventory", {}).get("seed_" + crop, 0))
			seed_caption.text = tr("%s\nLOCKED") % _crop_display_name(crop).to_upper() if seed.disabled else tr("%s\nx%d") % [_crop_display_name(crop).to_upper(), amount]
			seed_caption.modulate = Color(0.66, 0.50, 0.34, 1.0) if seed.disabled else Color.WHITE
		var seed_callback := _select_seed_from_popup.bind(crop)
		if not _qa_static_visual_only and not seed.pressed.is_connected(seed_callback): seed.pressed.connect(seed_callback)
	var picker_title := get_node_or_null(SEED_POPUP_PATH + "/Title") as CanvasItem
	var picker_tail := get_node_or_null(SEED_POPUP_PATH + "/PointerTail") as CanvasItem
	if picker_title != null: picker_title.visible = true
	if picker_tail != null: picker_tail.visible = false
	for crop in ["carrot", "tomato", "pumpkin"]:
		var seed_button := get_node("%s/Seed_%s" % [SEED_POPUP_PATH, crop]) as TextureButton
		var caption := seed_button.get_node_or_null("Caption") as CanvasItem
		if caption != null: caption.visible = true
	_sync_seed_popup()


func _bind_toolbar_feedback(button: TextureButton, selected := false) -> void:
	button.set_meta("field_selected", selected)
	if button not in _toolbar_buttons:
		_toolbar_buttons.append(button)
	if button.get_node_or_null("ToolbarResponse") == null:
		var response := ToolbarResponseClass.new()
		response.name = "ToolbarResponse"
		button.add_child(response)
		response.configure(button)
	if button.get_node_or_null("ToolStateFrame") == null:
		var frame := Panel.new()
		frame.name = "ToolStateFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.offset_left = 3.0
		frame.offset_top = 3.0
		frame.offset_right = -3.0
		frame.offset_bottom = -3.0
	for binding in [
		[button.mouse_entered, _toolbar_visual_event.bind(button, "hover", true)],
		[button.mouse_exited, _toolbar_visual_event.bind(button, "hover", false)],
		[button.focus_entered, _toolbar_visual_event.bind(button, "focus", true)],
		[button.focus_exited, _toolbar_visual_event.bind(button, "focus", false)],
		[button.button_down, _toolbar_visual_event.bind(button, "pressed", true)],
		[button.button_up, _toolbar_visual_event.bind(button, "pressed", false)],
	]:
		var event_signal: Signal = binding[0]
		var callback: Callable = binding[1]
		if not event_signal.is_connected(callback): event_signal.connect(callback)
	_sync_toolbar_button_visual(button)


func _toolbar_visual_event(button: TextureButton, kind: String, enabled: bool) -> void:
	button.set_meta("field_" + kind, enabled)
	if kind == "pressed":
		if enabled:
			button.set_meta("field_press_until", Time.get_ticks_msec() + 100)
			_toolbar_response(button).play_acknowledgement(button.disabled)
		else:
			# SceneTree timers may expire just before a millisecond deadline.
			# Explicitly release this pulse so the selected style cannot stick
			# in its darker pressed state after a quick pointer click.
			var deadline := int(button.get_meta("field_press_until", 0))
			get_tree().create_timer(0.12).timeout.connect(_release_toolbar_press.bind(button, deadline))
	_sync_toolbar_button_visual(button)


func _release_toolbar_press(button: TextureButton, deadline: int) -> void:
	if not is_instance_valid(button): return
	if int(button.get_meta("field_press_until", 0)) == deadline:
		button.set_meta("field_press_until", 0)
	_sync_toolbar_button_visual(button)


func _sync_toolbar_button_visual(button: TextureButton) -> void:
	if not is_instance_valid(button): return
	var selected := bool(button.get_meta("field_selected", false))
	var hovered := bool(button.get_meta("field_hover", false)) or bool(button.get_meta("field_focus", false))
	var pressed := bool(button.get_meta("field_pressed", false)) or Time.get_ticks_msec() < int(button.get_meta("field_press_until", 0))
	var frame := button.get_node("ToolStateFrame") as Panel
	frame.visible = selected or hovered or pressed or button.disabled
	if button.disabled:
		button.self_modulate = Color(0.70, 0.70, 0.66, 0.48)
		frame.add_theme_stylebox_override("panel", tool_selected_style if selected else tool_disabled_style)
	elif pressed:
		button.self_modulate = Color(0.87, 0.79, 0.65, 1.0)
		frame.add_theme_stylebox_override("panel", tool_pressed_style)
	elif selected:
		button.self_modulate = Color(1.09, 1.06, 0.89, 1.0)
		frame.add_theme_stylebox_override("panel", tool_selected_style)
	elif hovered:
		button.self_modulate = Color(1.09, 1.08, 1.0, 1.0)
		frame.add_theme_stylebox_override("panel", tool_hover_style)
	else:
		button.self_modulate = Color.WHITE
	_toolbar_response(button).sync_state(selected, button.disabled, pressed, tr("Selected"), tr("Unavailable"))


func _toolbar_response(button: TextureButton) -> ToolbarResponseClass:
	return button.get_node("ToolbarResponse") as ToolbarResponseClass


func _toolbar_button_at_point(global_point: Vector2) -> TextureButton:
	# Reverse registration order gives the seed choices priority above their
	# toolbar parent. Every rectangle remains the one authored in the scene.
	for index in range(_toolbar_buttons.size() - 1, -1, -1):
		var button := _toolbar_buttons[index]
		if _toolbar_contains_point(button, global_point):
			return button
	return null


func _toolbar_contains_point(button: TextureButton, global_point: Vector2) -> bool:
	if not is_instance_valid(button) or not button.is_visible_in_tree():
		return false
	var local_point := button.get_global_transform_with_canvas().affine_inverse() * global_point
	return Rect2(Vector2.ZERO, button.size).has_point(local_point)


func _toolbar_unavailable_feedback(button: TextureButton) -> void:
	feedback = button.tooltip_text
	_feedback_is_error = true
	_toolbar_response(button).play_acknowledgement(true)
	_populate_field_gameplay_ui()


func _toolbar_touch_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var button := _toolbar_button_at_point(touch.position)
			if button == null:
				return false
			if button.disabled:
				_toolbar_unavailable_feedback(button)
			else:
				_toolbar_touch_buttons[touch.index] = button
				_toolbar_visual_event(button, "pressed", true)
			return true
		var pressed_button := _toolbar_touch_buttons.get(touch.index) as TextureButton
		if pressed_button == null:
			return false
		_toolbar_touch_buttons.erase(touch.index)
		_toolbar_visual_event(pressed_button, "pressed", false)
		if not touch.canceled and not pressed_button.disabled and _toolbar_contains_point(pressed_button, touch.position):
			# Touch owns the release; emulated mouse input is consumed in _input.
			# Existing pressed callbacks continue to own all gameplay decisions.
			pressed_button.pressed.emit()
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var dragged_button := _toolbar_touch_buttons.get(drag.index) as TextureButton
		if dragged_button != null:
			dragged_button.set_meta("field_pressed", _toolbar_contains_point(dragged_button, drag.position))
			_sync_toolbar_button_visual(dragged_button)
			return true
	return false


func _clear_toolbar_command_result() -> void:
	var next := get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as TextureButton
	if next.has_meta("field_day_result"):
		next.remove_meta("field_day_result")
	_toolbar_response(next).set_command_result("")


func _toolbar_action_failure(action: String) -> void:
	for button in _toolbar_buttons:
		if button.name == "Action_" + action:
			_toolbar_response(button).play_acknowledgement(true)
			return


func _tool_display_name(action: String) -> String:
	match action:
		"till": return tr("Till")
		"seed": return tr("Plant")
		"water": return tr("Water")
		"fertilize": return tr("Fertilize")
		"harvest": return tr("Harvest")
	return ""


func _tool_instruction(action: String) -> String:
	match action:
		"till": return tr("Click an untilled plot.")
		"seed": return tr("Plant %s in a tilled plot.") % _crop_display_name(String(GameState.data.get("selected_seed", "carrot")))
		"water": return tr("Click a planted plot to water.")
		"fertilize": return tr("Click a growing crop to fertilize.")
		"harvest": return tr("Click a ready crop to harvest.")
	return tr("Choose a tool, then tap a plot.")


func _tool_unavailable_reason(action: String) -> String:
	if not GameState.has_energy(action): return _energy_unavailable_reason(action)
	if action == "seed": return tr("No seeds available. Buy seeds in the Shop.")
	if action == "harvest":
		for plot in GameState.field_plots():
			if bool(plot.get("ready_to_harvest", false)): return String(GameState.field_harvest_info(plot).reason)
		return tr("Nothing is ready to harvest.")
	return tr("Action unavailable.")


func _energy_unavailable_reason(action: String) -> String:
	return tr("Need %d energy; you have %d.\nNext Day restores 100.") % [
		int(FarmData.ACTION_ENERGY_COSTS.get(action, 0)),
		int(GameState.data.get("energy", 0)),
	]


func _production_crop_texture(crop_id: String, growth_stage: int, ready: bool) -> Texture2D:
	var stage := 4 if ready else clampi(growth_stage, 1, 4)
	return load("res://assets/field_approved_v1/runtime/crops/%s/%s_stage_%02d.png" % [crop_id.to_upper(), crop_id, stage]) as Texture2D


func _toggle_seed_popup() -> void:
	var seed_action := get_node(SEED_ACTION_PATH) as TextureButton
	_seed_popup_open = not _seed_popup_open if not seed_action.disabled else false
	if not seed_action.disabled:
		_active_tool = "seed"
		_clear_toolbar_command_result()
		feedback = ""
		_feedback_is_error = false
	_populate_field_gameplay_ui()


func _sync_seed_popup() -> void:
	var seed_action := get_node(SEED_ACTION_PATH) as TextureButton
	var popup := get_node(SEED_POPUP_PATH) as Panel
	if seed_action.disabled:
		_seed_popup_open = false
	popup.visible = _seed_popup_open


func _close_seed_popup() -> void:
	_seed_popup_open = false
	var popup := get_node_or_null(SEED_POPUP_PATH) as Panel
	if popup != null:
		popup.visible = false


func close_top_presentation() -> bool:
	if not _seed_popup_open: return false
	_close_seed_popup()
	return true


func _select_seed_from_popup(crop: String) -> void:
	if GameState.select_seed(crop, false):
		_active_tool = "seed"
		_clear_toolbar_command_result()
		feedback = ""
		_feedback_is_error = false
		_close_seed_popup()
		_populate_field_gameplay_ui()
	else:
		feedback = _locked_crop_tooltip(crop)
		_feedback_is_error = true
		_populate_field_gameplay_ui()


func _locked_crop_tooltip(crop: String) -> String:
	match crop:
		"tomato": return tr("Complete The First Order to unlock Tomato.")
		"pumpkin": return tr("Complete A New Crop to unlock Pumpkin.")
	return ""


func _crop_display_name(crop: String) -> String:
	match crop:
		"carrot": return tr("Carrot")
		"tomato": return tr("Tomato")
		"pumpkin": return tr("Pumpkin")
	return tr(FarmData.get_crop_label(crop))


func _on_action_pressed(action: String) -> void:
	_active_tool = action
	_clear_toolbar_command_result()
	_close_seed_popup()
	feedback = ""
	_feedback_is_error = false
	_populate_field_gameplay_ui()


func _on_advance_day_pressed() -> void:
	_active_tool = ""
	_clear_toolbar_command_result()
	feedback = ""
	_feedback_is_error = false
	_close_seed_popup()
	var previous_stages := {}
	for plot in field_state.plots():
		previous_stages[int(plot.get("id", 0))] = int(plot.get("growth_stage", 0))
	if not GameState.advance_day(false):
		feedback = GameState.status
		_feedback_is_error = true
		_toolbar_action_failure("advance_day")
		_bind_field_hud()
		_populate_field_gameplay_ui()
		return
	farmer.cancel_presentations()
	_pending_growth_plots = PackedInt32Array()
	var became_ready := false
	for plot in GameState.field_plots():
		var plot_id := int(plot.get("id", 0))
		if not String(plot.get("crop", "")).is_empty() and int(plot.get("growth_stage", 0)) > int(previous_stages.get(plot_id, 0)):
			_pending_growth_plots.append(plot_id)
		if bool(plot.get("ready_to_harvest", false)) and int(previous_stages.get(plot_id, 0)) < int(plot.get("growth_stage", 0)):
			became_ready = true
	renderer.update_all_plots(GameState.field_plots(), field_state.selected_plot_id())
	renderer.play_growth_transition(_pending_growth_plots)
	if became_ready:
		field_audio.play_crop_ready()
	_pending_growth_plots = PackedInt32Array()
	feedback = tr("Day %d. Energy restored.") % int(GameState.data.get("day", 1))
	var next := get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as TextureButton
	next.set_meta("field_day_result", int(GameState.data.get("day", 1)))
	_toolbar_response(next).set_command_result(tr("Day %d") % int(GameState.data.get("day", 1)))
	_bind_field_hud()
	_populate_field_gameplay_ui()


func _on_back_pressed() -> void:
	_active_tool = ""
	_close_seed_popup()
	if is_instance_valid(farmer): farmer.cancel_presentations()
	ScreenRouter.go(ScreenRouter.FIELD_SELECT_ROUTE_ID)


func _commit_plot_click(plot_id: int) -> void:
	_last_clicked_plot_id = plot_id
	if _active_tool.is_empty():
		feedback = tr("Plot %02d selected.") % plot_id
		_feedback_is_error = false
		GameState.select_plot_silent(plot_id)
		renderer.update_selection(plot_id)
		_apply_hover_plot(_hover_plot_id, true)
		_populate_field_gameplay_ui()
		return
	_field_action_on_plot(plot_id, _active_tool)


func _pulse_plot(plot_id: int) -> void:
	if renderer == null or renderer.bed_world == null:
		return
	var bed := renderer.bed_world.get_node_or_null("Bed_%02d" % plot_id) as CanvasItem
	if bed == null:
		return
	bed.modulate = Color(1.08, 1.06, 0.94, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var rest_color := Color(1.035, 1.03, 0.98, 1.0) if plot_id == _hover_plot_id else Color.WHITE
	tween.tween_property(bed, "modulate", rest_color, 0.12)


func _input(event: InputEvent) -> void:
	if _qa_static_visual_only or _toolbar_buttons.is_empty():
		return
	if _toolbar_touch_input(event):
		get_viewport().set_input_as_handled()
		return
	var pointer_position := Vector2.ZERO
	var pointer_down := false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		# Godot dispatches the mouse synthesized from a touch BEFORE the touch.
		# Claim toolbar emulation from its authored rectangle even before a touch
		# is tracked. A tracked gesture also owns its outside release.
		if mouse_event.device == -1 and (not _toolbar_touch_buttons.is_empty() or _toolbar_button_at_point(mouse_event.position) != null):
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		pointer_position = mouse_event.position
		pointer_down = mouse_event.pressed
		var disabled_button := _toolbar_button_at_point(pointer_position)
		if disabled_button != null and disabled_button.disabled:
			if pointer_down:
				_toolbar_unavailable_feedback(disabled_button)
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventScreenTouch:
		pointer_position = (event as InputEventScreenTouch).position
		pointer_down = (event as InputEventScreenTouch).pressed
	else:
		return
	if _seed_popup_open and pointer_down:
		var popup := get_node(SEED_POPUP_PATH) as Control
		var seed_action := get_node(SEED_ACTION_PATH) as TextureButton
		if not popup.get_global_rect().has_point(pointer_position) and not _toolbar_contains_point(seed_action, pointer_position):
			_close_seed_popup()


func _lifecycle_label(plot: Dictionary) -> String:
	if bool(plot.get("ready_to_harvest", false)): return tr("Ready to Harvest")
	var crop := String(plot.get("crop", ""))
	if not crop.is_empty():
		var stage := int(plot.get("growth_stage", 0))
		return tr("Planted") if stage == 0 else tr("Growing · Day %d") % stage
	return tr("Tilled") if bool(plot.get("is_hoed", false)) else tr("Untilled")


func _field_action(action: String) -> void:
	_field_action_on_plot(int(field_state.selected_plot_id()), action)


func _field_action_on_plot(plot_id: int, action: String) -> void:
	if not field_state.action_allowed_on_plot(plot_id, action):
		GameState.select_plot_silent(plot_id)
		renderer.update_selection(plot_id)
		feedback = _action_failure_message(action)
		_feedback_is_error = true
		_toolbar_action_failure(action)
		_last_action_rebuilds = 0
		_last_action_latency_ms = 0.0
		set_meta("FIELD_WORLD_REBUILDS_PER_ACTION", 0)
		set_meta("FIELD_ACTION_LATENCY_MS", 0.0)
		_populate_field_gameplay_ui()
		return
	var rebuild_baseline := _world_rebuild_total
	var started_usec := Time.get_ticks_usec()
	var selected_before: Dictionary = GameState.get_plot(plot_id).duplicate(true)
	var crop_before := String(selected_before.get("crop", ""))
	var inventory_before := int(GameState.data.get("inventory", {}).get("crop_" + crop_before, 0)) if action == "harvest" and not crop_before.is_empty() else 0
	var success := bool(field_state.dispatch_on_plot(plot_id, action))
	feedback = _action_success_message(plot_id, action, crop_before, inventory_before) if success else GameState.status
	_feedback_is_error = not success
	if success:
		renderer.update_plot(GameState.get_plot(plot_id), plot_id)
		_apply_hover_plot(_hover_plot_id, true)
		var bed := PixelMap.visual_plot_rect(plot_id)
		var bed_visual := renderer.bed_world.get_node("Bed_%02d" % plot_id) as Node2D
		var contact_global := bed_visual.to_global(Vector2(bed.position.x + 27.0, bed.end.y - 20.0))
		var soil_contact: Vector2 = renderer.fx_world.to_local(contact_global)
		var presentation := {"plot_id": plot_id, "action": action, "day": int(GameState.data.day), "zone": GameState.active_field_zone(), "soil_contact": soil_contact, "actor_soil_contact": (farmer.get_parent() as Node2D).to_local(contact_global), "soil_contact_global": contact_global, "field_navigation": true, "latest_target": true, "feedback_immediate": true}
		if action == "harvest" and not crop_before.is_empty():
			var inventory_after := int(GameState.data.get("inventory", {}).get("crop_" + crop_before, 0))
			var reward_quantity := maxi(0, inventory_after - inventory_before)
			if reward_quantity > 0:
				presentation["reward_crop"] = crop_before
				presentation["reward_label"] = _crop_display_name(crop_before)
				presentation["reward_quantity"] = reward_quantity
		# Every committed plot gets its own feedback now, even if a rapid burst
		# replaces its not-yet-started farmer journey. Authority never waits for
		# a cosmetic queue and neither its contact nor catch-up grants rewards.
		_play_committed_field_feedback(presentation)
		farmer.enqueue_action(farmer.field_point(_stable_farmer_path_anchor(plot_id), plot_id), action, presentation)
		_bind_field_hud()
		_populate_field_gameplay_ui()
	else:
		# Failed persistence/capacity is real feedback, not a successful animation.
		_toolbar_action_failure(action)
		_bind_field_hud()
		_populate_field_gameplay_ui()
	_last_action_rebuilds = _world_rebuild_total - rebuild_baseline
	_last_action_latency_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
	set_meta("FIELD_WORLD_REBUILDS_PER_ACTION", _last_action_rebuilds)
	set_meta("FIELD_ACTION_LATENCY_MS", _last_action_latency_ms)


func _on_farmer_action_contact(job: Dictionary) -> void:
	# The authoritative dispatch/save already happened exactly once. This
	# delayed source-pose contact must NEVER dispatch or grant a second reward.
	if bool(job.get("feedback_immediate", false)): return
	_play_committed_field_feedback(job)


func _play_committed_field_feedback(job: Dictionary) -> void:
	if not is_instance_valid(renderer) or int(job.get("day", -1)) != int(GameState.data.day) or String(job.get("zone", "")) != GameState.active_field_zone(): return
	var plot_id := int(job.get("plot_id", 0))
	if plot_id < 1 or plot_id > 12: return
	var action := String(job.get("action", ""))
	renderer.play_action_fx(plot_id, action, job.get("soil_contact", Vector2.INF))
	field_audio.play_action(action)
	var quantity := int(job.get("reward_quantity", 0))
	if quantity > 0: renderer.play_reward_feedback(plot_id, String(job["reward_crop"]), String(job["reward_label"]), quantity)
	set_meta("FIELD_LAST_CONTACT_PLOT", plot_id)
	set_meta("FIELD_LAST_CONTACT_ACTION", action)


func _action_success_message(plot_id: int, action: String, crop_before: String, inventory_before: int) -> String:
	match action:
		"till": return tr("Tilled plot %d.") % plot_id
		"seed": return tr("Planted %s on plot %d.") % [_crop_display_name(String(GameState.get_plot(plot_id).get("crop", ""))), plot_id]
		"water": return tr("Watered plot %d.") % plot_id
		"fertilize": return tr("Fertilized plot %d.") % plot_id
		"harvest":
			var stored := int(GameState.data.get("inventory", {}).get("crop_" + crop_before, 0))
			var quantity := maxi(0, stored - inventory_before)
			return tr("Harvested +%d %s.\nStorage: %d.") % [quantity, _crop_display_name(crop_before), stored]
	return GameState.status


func _action_failure_message(action: String) -> String:
	if not GameState.has_energy(action):
		return _energy_unavailable_reason(action)
	var plot: Dictionary = field_state.selected_plot()
	if bool(plot.get("locked", false)): return tr("This plot is locked.")
	match action:
		"till": return tr("This plot is already tilled.")
		"seed":
			if not bool(plot.get("is_hoed", false)):
				return tr("Till this plot first.")
			if not String(plot.get("crop", "")).is_empty(): return tr("This plot already has a crop.")
			var selected_crop := String(GameState.data.get("selected_seed", "carrot"))
			if int(GameState.data.get("inventory", {}).get("seed_" + selected_crop, 0)) <= 0: return tr("No %s seeds. Buy more in the Shop.") % _crop_display_name(selected_crop)
			return tr("Choose an unlocked seed.")
		"water":
			if bool(plot.get("watered_today", false)):
				return tr("Already watered today.")
			if bool(plot.get("ready_to_harvest", false)): return tr("This crop is ready. Harvest it.")
			return tr("Plant a crop first.")
		"fertilize":
			if bool(plot.get("fertilizer_pending", false)):
				return tr("Already fertilized.")
			if bool(plot.get("ready_to_harvest", false)): return tr("This crop is ready. Harvest it.")
			return tr("Plant a crop first.")
		"harvest": return String(GameState.field_harvest_info(plot).reason)
	return tr("Action unavailable.")


func qa_farmer_animation() -> String:
	return farmer.current_animation_name() if farmer != null and farmer.has_method("current_animation_name") else ""


func qa_trigger_action(action: String) -> void:
	_field_action(action)


func qa_trigger_plot_click(plot_id: int) -> void:
	_pulse_plot(plot_id)
	_commit_plot_click(plot_id)


func qa_world_rebuilds_per_action() -> int:
	return _last_action_rebuilds


func qa_toolbar_response(button_path: String) -> Dictionary:
	var button := get_node(button_path) as TextureButton
	var snapshot: Dictionary = _toolbar_response(button).qa_snapshot()
	snapshot["active_tool"] = _active_tool
	snapshot["hovered"] = bool(button.get_meta("field_hover", false))
	snapshot["world_rebuild_total"] = _world_rebuild_total
	snapshot["button_transform"] = button.get_transform()
	snapshot["button_offsets"] = Vector4(button.offset_left, button.offset_top, button.offset_right, button.offset_bottom)
	return snapshot


func qa_action_latency_ms() -> float:
	return _last_action_latency_ms


func qa_last_clicked_plot_id() -> int:
	return _last_clicked_plot_id


func qa_reset_last_clicked_plot() -> void:
	_last_clicked_plot_id = 0


func qa_set_debug_mode(mode: String) -> void:
	_qa_debug_mode = mode
	if debug_overlay != null:
		debug_overlay.set_mode(mode)


func qa_set_actor_relation(plot_id: int, relation: String) -> void:
	_qa_actor_relation = relation
	GameState.select_plot(plot_id)


func qa_set_static_visual_only(enabled: bool) -> void:
	_qa_static_visual_only = enabled
	_refresh()
