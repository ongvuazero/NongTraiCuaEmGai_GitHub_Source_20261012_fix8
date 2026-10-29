extends Node

# Native mobile behavior only. No economy, farm schema, or offline-day reward.
# The same adapter can be forced in isolated desktop QA with MSF_MOBILE_QA=1.
const DESIGN_SIZE := Vector2(1280, 720)
const MIN_TOUCH_LOGICAL := 48.0
var _main: Control
var _suspended := false
var _tree_was_paused := false
var _paused_audio: Dictionary = {}
var _last_background_save_ok := true
var _back_events := 0
var _pause_events := 0
var _resume_events := 0
var _touch_targets_expanded := 0
var _safe_controls_adjusted := 0
var _layout_wait := 0.0
var _pending_control_scopes: Array[Node] = []
var _control_layout_queued := false

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] or OS.get_environment("MSF_MOBILE_QA") == "1"

static func apply_display_settings(desktop_fullscreen: bool) -> void:
	# A saved desktop window preference must never turn off Android immersive mode.
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if is_mobile() or desktop_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

static func install(main: Control) -> Node:
	if not is_mobile(): return null
	var existing := main.get_node_or_null("MobileRuntime")
	if existing != null: return existing
	var runtime := new()
	runtime.name = "MobileRuntime"
	runtime._main = main
	main.add_child(runtime)
	return runtime

static func request_control_layout(scope: Node) -> void:
	if not is_mobile() or not is_instance_valid(scope): return
	var ancestor := scope
	while ancestor != null:
		var runtime := ancestor.get_node_or_null("MobileRuntime")
		if runtime != null:
			runtime.call("_queue_control_layout", scope)
			return
		ancestor = ancestor.get_parent()

func _queue_control_layout(scope: Node) -> void:
	if not _pending_control_scopes.has(scope): _pending_control_scopes.append(scope)
	if _control_layout_queued: return
	_control_layout_queued = true
	call_deferred("_layout_pending_controls")

func _layout_pending_controls() -> void:
	_control_layout_queued = false
	var scopes := _pending_control_scopes.duplicate()
	_pending_control_scopes.clear()
	var safe := _control_safe_area()
	for scope in scopes:
		if not is_instance_valid(scope) or scope.is_queued_for_deletion() or not scope.is_inside_tree(): continue
		if scope is CanvasItem and not scope.is_visible_in_tree(): continue
		_expand_small_buttons(scope, safe)
		_clamp_corner_controls(scope, safe)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	apply_display_settings(false)
	ScreenRouter.screen_changed.connect(_route_changed)
	get_viewport().size_changed.connect(_schedule_layout)
	call_deferred("_layout_mobile_controls")
	set_meta("no_offline_day_advance", true)

func _exit_tree() -> void:
	if ScreenRouter.screen_changed.is_connected(_route_changed): ScreenRouter.screen_changed.disconnect(_route_changed)
	if get_viewport().size_changed.is_connected(_schedule_layout): get_viewport().size_changed.disconnect(_schedule_layout)
	if _suspended: resume_runtime()

func _notification(what: int) -> void:
	if not is_mobile() or not is_instance_valid(_main): return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST: handle_back()
		NOTIFICATION_APPLICATION_PAUSED: suspend_runtime()
		NOTIFICATION_APPLICATION_RESUMED: resume_runtime()

func handle_back() -> void:
	_back_events += 1
	var language := _main.get_node_or_null("FirstLaunchLanguage")
	if language != null and language.has_method("is_open") and bool(language.call("is_open")): return
	var screen := active_screen()
	if screen == null: return
	var credits := screen.get_node_or_null("CreditsDialog")
	if credits != null and credits.has_method("is_open") and bool(credits.call("is_open")):
		credits.call("close")
		return
	var menu := screen.get_node_or_null("GameplaySaveMenu")
	var dialog := menu.get_node_or_null("SaveMenuDialog") as Control if menu != null else null
	if dialog != null and dialog.visible:
		menu.call("close_menu")
		return
	if screen.has_method("close_top_presentation") and bool(screen.call("close_top_presentation")): return
	var route := ScreenRouter.current_screen
	if route == "settings":
		# Settings apply only through its Apply button; native Back discards draft.
		ScreenRouter.go(GameState.settings_return)
	elif route == "save" and screen.has_method("_back"):
		screen.call("_back") # First Back cancels pending overwrite/delete.
	elif route == "title":
		get_tree().quit()
	elif menu != null:
		menu.call("open_menu")
	else:
		ScreenRouter.go("hub")

func active_screen() -> Control:
	var host := _main.get_node_or_null("ScreenHost")
	if host == null: return null
	for index in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(index)
		if child is Control and not child.is_queued_for_deletion(): return child as Control
	return null

func suspend_runtime() -> void:
	if _suspended: return
	_suspended = true
	_pause_events += 1
	_cancel_active_pointer_gestures()
	# Save only committed farm data. A queued presentation command is not executed.
	_last_background_save_ok = true
	if GameState.has_active_farm():
		var location := ScreenRouter.current_screen
		if location == "destination": location = "islands"
		_last_background_save_ok = GameState.save(location)
	_tree_was_paused = get_tree().paused
	get_tree().paused = true
	_pause_audio_tree(_main)

func _cancel_active_pointer_gestures() -> void:
	# A touch held while Android backgrounds the app must not become a new
	# toolbar transaction when the next foreground release arrives.
	if ScreenRouter.current_screen != "field": return
	var screen := active_screen()
	if screen == null: return
	var touches: Dictionary = screen.get("_toolbar_touch_buttons")
	for button in touches.values():
		if is_instance_valid(button) and screen.has_method("_toolbar_visual_event"):
			screen.call("_toolbar_visual_event", button, "pressed", false)
	touches.clear()
	screen.set("_pressed_plot_id", 0)

func _pause_audio_tree(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		_paused_audio[node] = bool(node.get("stream_paused"))
		node.set("stream_paused", true)
	for child in node.get_children(): _pause_audio_tree(child)

func resume_runtime() -> void:
	if not _suspended: return
	_suspended = false
	_resume_events += 1
	for player in _paused_audio:
		if is_instance_valid(player): player.set("stream_paused", _paused_audio[player])
	_paused_audio.clear()
	get_tree().paused = _tree_was_paused
	apply_display_settings(false)
	if not _last_background_save_ok:
		GameState.set_status("Save failed. Your progress is not confirmed saved.\nPlease retry.", false, "save")
	call_deferred("_layout_mobile_controls")

func _route_changed(_route: String) -> void:
	_schedule_layout()

func _schedule_layout() -> void:
	_layout_wait = 0.08

func _process(delta: float) -> void:
	if _suspended or _layout_wait <= 0.0: return
	_layout_wait -= minf(delta, 0.05)
	if _layout_wait <= 0.0: _layout_mobile_controls()

func safe_area_logical() -> Rect2:
	if DisplayServer.get_name() == "headless": return Rect2(Vector2.ZERO, DESIGN_SIZE)
	var safe := Rect2(DisplayServer.get_display_safe_area())
	# Window screen transform already includes stretch and centered letterboxing.
	var inverse := get_viewport().get_screen_transform().affine_inverse()
	var logical := Rect2(inverse * safe.position, inverse.basis_xform(safe.size))
	return logical.intersection(Rect2(Vector2.ZERO, DESIGN_SIZE))

func _layout_mobile_controls() -> void:
	var screen := active_screen()
	if screen == null: return
	var safe := _control_safe_area()
	_expand_small_buttons(screen, safe)
	if screen.has_method("_fit_audio_row_labels"): screen.call("_fit_audio_row_labels")
	_clamp_corner_controls(screen, safe)
	set_meta("safe_area_logical", safe)

func _control_safe_area() -> Rect2:
	var safe := safe_area_logical()
	if safe.size.x < 100 or safe.size.y < 100: safe = Rect2(Vector2.ZERO, DESIGN_SIZE)
	return safe

func _clamp_corner_controls(scope: Node, safe: Rect2) -> void:
	# Do not move/scale fixed world geometry: plot and creature alpha hitboxes
	# share authored coordinates. Only independent corner affordances are inset.
	for id in ["OpenGameplayMenu", "CloseDestinationContext", "CloseDragonCare", "DragonShopClose"]:
		var control := scope.find_child(id, true, false) as Control
		if control == null or not control.is_visible_in_tree(): continue
		var box := control.get_global_rect()
		var clamped := Vector2(clampf(box.position.x, safe.position.x, safe.end.x - box.size.x), clampf(box.position.y, safe.position.y, safe.end.y - box.size.y))
		if box.position.distance_to(clamped) > 0.1:
			control.global_position += clamped - box.position
			_safe_controls_adjusted += 1

func _expand_small_buttons(node: Node, safe: Rect2) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var button := child as BaseButton
			if button.is_visible_in_tree() and button.size.x > 0 and button.size.y > 0:
				# Bounded extension, centered in its own row. No transparent overlay
				# callback exists, so native GUI still dispatches exactly once.
				var scale := button.get_global_transform().get_scale().abs()
				var target := Vector2(maxf(button.size.x, MIN_TOUCH_LOGICAL / maxf(scale.x, 0.001)), maxf(button.size.y, MIN_TOUCH_LOGICAL / maxf(scale.y, 0.001)))
				if not target.is_equal_approx(button.size) and not button.get_parent() is Container:
					var original := button.size
					if not button.has_meta("mobile_original_rect"): button.set_meta("mobile_original_rect", Rect2(button.position, original))
					button.position -= (target - original) * 0.5
					button.size = target
					button.set_meta("mobile_touch_expanded", true)
					_touch_targets_expanded += 1
					# Styled buttons already reflow their icon/text on resized. Keep
					# that padding; only bare labels (such as ×) fill the new target.
					if not button.has_meta("farm_navigation_style") and not button.has_meta("gameplay_button_skin_options"):
						for content in button.get_children():
							if content is Label: content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_expand_small_buttons(child, safe)
	if node.has_meta("mobile_touch_rows"): _space_touch_rows(node)

func _space_touch_rows(node: Node) -> void:
	# Destination action grids own their free vertical space. Expanding their
	# 32/37px cards must also separate rows so a tap cannot choose another action.
	var rows: Array[Dictionary] = []
	for child in node.get_children():
		if not child is BaseButton or not child.is_visible_in_tree(): continue
		var origin: Rect2 = child.get_meta("mobile_original_rect", Rect2(child.position, child.size))
		var row_index := -1
		for index in range(rows.size()):
			if is_equal_approx(float(rows[index].origin), origin.position.y): row_index = index; break
		if row_index < 0:
			rows.append({"origin":origin.position.y, "buttons":[child]})
		else: rows[row_index].buttons.append(child)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.origin) < float(b.origin))
	var previous_bottom := -INF
	for row in rows:
		var top := INF
		var bottom := -INF
		for button in row.buttons:
			top = minf(top, button.position.y)
			bottom = maxf(bottom, button.position.y + button.size.y)
		var shift := maxf(0.0, previous_bottom + 4.0 - top)
		for button in row.buttons: button.position.y += shift
		previous_bottom = bottom + shift

func qa_summary() -> Dictionary:
	return {"mobile": is_mobile(), "suspended": _suspended, "back_events": _back_events, "pause_events": _pause_events, "resume_events": _resume_events, "background_save_ok": _last_background_save_ok, "expanded_touch_targets": _touch_targets_expanded, "safe_controls_adjusted": _safe_controls_adjusted, "safe_area": get_meta("safe_area_logical", Rect2()), "offline_day_advance": false, "production_device_tested": false}
