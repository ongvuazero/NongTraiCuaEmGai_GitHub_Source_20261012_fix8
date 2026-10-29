extends Control

# Local world props and activities only. The existing presenter/WorldSystems
# remains the sole owner of resource costs, care gains and atomic autosave.
const UI = preload("res://scripts/ui_factory.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")
var presenter: Control
var mode := ""
var species := ""
var body: Control
var motion: Node
var props: Dictionary = {}
var home_points: Dictionary = {}
var food_token: TextureRect
var caption: Label
var generation := 0
var busy := false
var committing := false
var contact_done := false
var action := ""
var active_mode := ""
var active_species := ""
var active_page := 0
var active_generation := 0
var contact_elapsed := 0.0
var prop_elapsed := 0.0
var last_success := false
var contact_point := Vector2.ZERO
var token_start := Vector2.ZERO
var started := 0
var contacts := 0
var committed := 0
var cancelled := 0
var rejected := 0
var last_event := ""
var _scan_wait := 0.0

func setup(owner_presenter: Control, bowl: Texture2D, brush: Texture2D, ball: Texture2D) -> void:
	presenter = owner_presenter
	name = "DragonWorldActivities"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	set_meta("presentation_only", true)
	for entry in [["feed", bowl], ["clean", brush], ["pet", ball]]:
		var prop := TextureButton.new()
		prop.name = "DragonWorld_" + String(entry[0]) + "Prop"
		prop.texture_normal = entry[1]
		prop.texture_hover = entry[1]
		prop.texture_pressed = entry[1]
		prop.texture_disabled = entry[1]
		prop.ignore_texture_size = true
		prop.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		prop.size = Vector2(44, 34) if entry[0] == "feed" else Vector2(32, 44) if entry[0] == "clean" else Vector2(36, 36)
		prop.pivot_offset = prop.size * 0.5
		prop.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		prop.focus_mode = Control.FOCUS_NONE
		prop.pressed.connect(begin.bind(String(entry[0])))
		add_child(prop)
		props[String(entry[0])] = prop
	caption = UI.label("", Rect2(340, 622, 280, 30), 17, Color("fff7df"), HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "DragonActivityMode"
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	caption.add_theme_color_override("font_outline_color", Color("4a2b19"))
	caption.add_theme_constant_override("outline_size", 3)
	caption.clip_text = true
	caption.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(caption)
	food_token = UI.texture_rect(null, Rect2(0, 0, 25, 25))
	food_token.name = "NurseryFoodTransfer"
	food_token.visible = false
	food_token.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(food_token)
	process_priority = 2 # Props follow the motion controller's current source pose.
	set_process(true)
	refresh()

func _mode_visible() -> bool:
	if not is_instance_valid(presenter) or not presenter.is_visible_in_tree(): return false
	if String(presenter.get("care_mode")) not in ["nursery", "playground"]: return false
	var screen := presenter.get_parent()
	var shop := screen.get_node_or_null("DragonShopSurface") as Control
	if shop != null and shop.is_visible_in_tree(): return false
	var care := presenter.get("care") as Control
	return care != null and care.is_visible_in_tree()

func _selected_body() -> Control:
	for candidate in presenter.get("bodies"):
		if candidate.visible and String(candidate.get_meta("species_id", "")) == String(presenter.get("selected_id")):
			return candidate
	return null

func _controller() -> Node:
	if not is_instance_valid(presenter): return null
	return presenter.get_parent().get_node_or_null("LiveCreatureMotion")

func _base() -> Vector2:
	if is_instance_valid(motion) and motion.has_method("activity_summary"):
		var summary: Dictionary = motion.call("activity_summary", body)
		if summary.has("base"): return summary.base
	return Vector2(body.get_meta("live_motion_base", body.position))

func refresh() -> void:
	if not is_instance_valid(presenter): return
	var next_mode := String(presenter.get("care_mode"))
	var next_species := String(presenter.get("selected_id"))
	var next_body := _selected_body()
	if busy and (not _mode_visible() or next_mode != active_mode or next_species != active_species or next_body != body or int(presenter.get("page")) != active_page):
		cancel("selection_or_surface_changed")
	mode = next_mode
	species = next_species
	if not busy: body = next_body
	motion = _controller()
	visible = _mode_visible() and is_instance_valid(body)
	if not visible:
		food_token.hide()
		return
	var base := _base()
	# The secondary actors stand above/beside Farmer. Their native care heading
	# already names this mode; never lay an extra world caption over that actor.
	caption.visible = String(body.name) == "DragonBody_0"
	# Stations are authored relative to this actor's safe local ground. They
	# never request a cross-farmer trip, expand the walk lane or move the body.
	var right := minf(base.x + body.size.x * 0.89 + 8.0, 898.0)
	var ground := base.y + body.size.y * 0.96 + 5.0
	home_points.feed = Vector2(right, ground)
	home_points.clean = Vector2(right - 53.0, ground - 2.0)
	home_points.pet = Vector2(right - 5.0, ground)
	for key in props:
		var prop := props[key] as TextureButton
		prop.visible = key in ["feed", "clean"] if mode == "nursery" else key == "pet"
		if not busy:
			prop.position = Vector2(home_points[key]) - prop.size * 0.5
			prop.rotation = -0.16 if key == "clean" else 0.0
		var info := GameState.world_action_info(String(key), species)
		prop.disabled = busy or not bool(info.get("ok", false))
		prop.self_modulate = Color(1, 1, 1, 0.62) if not bool(info.get("ok", false)) else Color.WHITE
		var source := "Feed" if key == "feed" else "Clean" if key == "clean" else "Pet"
		prop.tooltip_text = UILocale.text(source) + ("\n" + UILocale.translate_message(String(info.get("reason", ""))) if not bool(info.get("ok", false)) else "")
		caption.text = UILocale.text("Nursery" if mode == "nursery" else "Playground")
		caption.tooltip_text = UILocale.text("Feed · Clean · Remedy" if mode == "nursery" else "Pet · Happiness · Collect Energy")
		caption.position = Vector2(clampf(base.x + body.size.x * 0.5 - 140.0, 276.0, 632.0), minf(ground + 30.0, 622.0))
	queue_redraw()

func begin(kind: String) -> bool:
	refresh()
	if busy or not visible or not props.has(kind) or not (props[kind] as TextureButton).visible:
		rejected += 1
		return false
	var info := GameState.world_action_info(kind, species)
	if not bool(info.get("ok", false)) or not is_instance_valid(motion) or not motion.has_method("begin_activity"):
		rejected += 1
		return false
	var summary: Dictionary = motion.call("activity_summary", body)
	if not summary.has("lane"):
		rejected += 1
		return false
	var lane: Rect2 = summary.lane
	var initial: Vector2 = summary.offset
	var approach := Vector2(24.0, 4.0) if String(body.name) == "DragonBody_0" else Vector2(16.0, 4.0) if String(body.name) == "DragonBody_1" else Vector2(8.0, 3.0)
	approach = approach.clamp(lane.position, lane.end)
	var origin := Vector2.ZERO.clamp(lane.position, lane.end)
	if origin.distance_to(approach) < 2.0:
		rejected += 1
		return false
	generation += 1
	active_generation = generation
	active_mode = mode
	active_species = species
	active_page = int(presenter.get("page"))
	action = kind
	contact_done = false
	contact_elapsed = 0.0
	prop_elapsed = 0.0
	last_success = false
	var points: Array[Vector2] = [origin, approach, initial]
	var accepted := bool(motion.call("begin_activity", body, points, 1, _contact.bind(generation), _complete.bind(generation), 34.0))
	if not accepted:
		rejected += 1
		return false
	busy = true
	started += 1
	last_event = "approaching_" + kind
	contact_point = Vector2(home_points[kind]) + (approach - origin) * 0.45
	refresh()
	return true

func _modal_visible() -> bool:
	if not is_instance_valid(presenter): return true
	var menu := presenter.get_parent().find_child("SaveMenuDialog", true, false) as Control
	return menu != null and menu.is_visible_in_tree()

func _contact(token: int) -> void:
	if token != generation or not busy or contact_done: return
	if _modal_visible() or not _mode_visible() or not is_instance_valid(body) or String(presenter.get("selected_id")) != active_species or String(body.get_meta("species_id", "")) != active_species:
		cancel("contact_cancelled")
		return
	contact_done = true
	contacts += 1
	committing = true
	committed += 1
	# The presenter performs exactly one existing authoritative transaction.
	# No progress, cost, meter or inventory value is changed by this controller.
	last_success = bool(presenter.call("_act", action))
	committing = false
	last_event = ("completed_" if last_success else "failed_") + action
	if last_success and action == "feed":
		var definition: Dictionary = GameState.world_config().creatures.get(active_species, {})
		food_token.texture = Assets.get_item_texture(String(definition.get("food", "")))
		food_token.modulate = Color.WHITE
		token_start = home_points.feed
		food_token.visible = true

func _complete(token: int) -> void:
	if token != generation or not busy: return
	busy = false
	food_token.hide()
	refresh()

func cancel(reason := "cancelled") -> void:
	if busy:
		cancelled += 1
		if is_instance_valid(motion) and is_instance_valid(body): motion.call("cancel_activity", body)
	generation += 1 # Invalidate any contact/complete callback already deferred.
	busy = false
	contact_done = false
	committing = false
	last_event = reason
	if is_instance_valid(food_token): food_token.hide()
	if is_instance_valid(presenter): refresh()

func _exit_tree() -> void:
	if busy and is_instance_valid(motion) and is_instance_valid(body): motion.call("cancel_activity", body)
	generation += 1
	busy = false

func _process(delta: float) -> void:
	if not is_instance_valid(presenter): return
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_scan_wait = 0.15
		refresh()
	if not busy or _modal_visible(): return
	prop_elapsed += minf(delta, 0.05)
	if action == "pet":
		var ball := props.pet as TextureButton
		var home: Vector2 = home_points.pet
		var roll := smoothstep(0.0, 0.6, prop_elapsed)
		var point := home.lerp(contact_point, roll)
		if contact_done:
			contact_elapsed += minf(delta, 0.05)
			point += Vector2(sin(contact_elapsed * TAU) * 3.0, -sin(clampf(contact_elapsed / 0.65, 0.0, 1.0) * PI) * 12.0)
		ball.position = point - ball.size * 0.5
		ball.rotation = (point.x - home.x) / 18.0
	elif contact_done and last_success:
		contact_elapsed += minf(delta, 0.05)
		if action == "feed" and food_token.visible:
			var mouth: Vector2 = body.get_meta("motion_mouth", body.size * Vector2(0.76, 0.29))
			var end := body.position + mouth
			var progress := smoothstep(0.0, 0.6, contact_elapsed)
			food_token.position = token_start.lerp(end, progress) + Vector2(0, -sin(progress * PI) * 18) - food_token.size * 0.5
			food_token.modulate.a = 1.0 - smoothstep(0.5, 0.65, contact_elapsed)
		elif action == "clean":
			var brush := props.clean as TextureButton
			var home: Vector2 = home_points.clean
			var coat := body.position + body.size * Vector2(0.62, 0.70)
			var progress := smoothstep(0.0, 0.18, contact_elapsed) * (1.0 - smoothstep(0.62, 0.82, contact_elapsed))
			var point := home.lerp(coat, progress)
			point += Vector2(0, sin(contact_elapsed * TAU * 3.0) * 7.0 * progress)
			brush.position = point - brush.size * 0.5
			brush.rotation = -0.16 + sin(contact_elapsed * TAU * 3.0) * 0.18 * progress
	queue_redraw()

func _draw() -> void:
	if not visible: return
	for key in props:
		var prop := props[key] as TextureButton
		if not prop.visible: continue
		var center: Vector2 = home_points.get(key, Vector2.ZERO)
		draw_set_transform(center + Vector2(0, 12), 0.0, Vector2(1.0, 0.27))
		draw_circle(Vector2.ZERO, 16.0, Color(0.16, 0.23, 0.08, 0.15))
	draw_set_transform(Vector2.ZERO)

func qa_summary() -> Dictionary:
	var targets: Dictionary = {}
	for key in props:
		var prop := props[key] as TextureButton
		targets[key] = {"visible": prop.is_visible_in_tree(), "disabled": prop.disabled, "rect": [prop.global_position.x, prop.global_position.y, prop.size.x, prop.size.y], "has_art": prop.texture_normal != null}
	return {"mode": mode, "species": species, "visible": is_visible_in_tree(), "busy": busy, "action": action, "contact_done": contact_done, "started": started, "contacts": contacts, "authority_calls": committed, "cancelled": cancelled, "rejected": rejected, "last_event": last_event, "last_success": last_success, "props": targets}
