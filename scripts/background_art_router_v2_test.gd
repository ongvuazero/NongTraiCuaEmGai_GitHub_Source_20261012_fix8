extends SceneTree

const Router = preload("res://scripts/ui/background_art_router.gd")
const FIELD := "res://assets/field_approved_v1/runtime/field_background_clear_v2_20261008.png"
const COW := "res://assets/gdd_closure_v3/environment/cow_yard.png"
const HOME := "res://v6/art/reference_runtime/home_hub_reference_runtime_base_v6_5.png"
const OVERLAY := "res://v6/art/plates/home_hub/home_hub_ui_overlay_v6_5.png"
const TITLE_BASE := "res://v6/art/reference_runtime/title_reference_runtime_base_v6_5.png"
const TITLE_UI := "res://v6/art/plates/title/title_ui_overlay_v6_5.png"
const SAVE_BASE := "res://v6/art/reference_runtime/save_reference_runtime_base_v6_5.png"
const SAVE_UI := "res://v6/art/plates/save/save_ui_overlay_runtime_v6_6.png"
const SAVE_QUOTE := "res://v6/art/plates/save/save_detail_quote_complete_v6_7.png"
var failures: Array[String] = []
var checks := 0

class AnimalFixture extends Control:
	var species_background_paths: Dictionary = {}
	var _serialized_root_children: Array[StringName] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error("BACKGROUND_ART_ROUTER_V2: " + detail)

func _run() -> void:
	Router._load_catalog()
	var production_paths: Dictionary = Router._paths.duplicate(true)
	var production_masks: Dictionary = Router._ui_masks.duplicate(true)
	_check(production_paths.size() >= 20, "Production manifest covers main and shared world backgrounds")
	_check(not production_paths.has(OVERLAY), "Home functional overlay is not routed")
	_check(not production_paths.has("res://v6/art/plates/title/title_ui_overlay_v6_5.png"), "Title functional overlay is not routed")
	# Existing sources make dimension and refresh checks deterministic before
	# generated replacement assets arrive. No images or player saves are written.
	Router._paths = {FIELD: COW, HOME: FIELD, COW: "res://missing_background_router_test.png"}
	Router._ui_masks[OVERLAY].replacement_background = COW
	var screen := AnimalFixture.new()
	screen.species_background_paths = {"cloud_chicken": FIELD, "cow": COW}
	root.add_child(screen)
	var field := Sprite2D.new()
	field.name = "Background"
	field.texture = load(FIELD) as Texture2D
	field.centered = false
	field.position = Vector2(14, 21)
	field.scale = Vector2(0.76555026, 0.76514345)
	screen.add_child(field)
	var original_scale := field.scale
	var original_extent := field.texture.get_size() * field.scale
	var original_position := field.position
	var home := TextureRect.new()
	home.texture = load(HOME) as Texture2D
	home.position = Vector2(25, 30)
	home.size = Vector2(1280, 720)
	home.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	home.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	screen.add_child(home)
	var original_rect := home.get_rect()
	var overlay := TextureRect.new()
	overlay.texture = load(OVERLAY) as Texture2D
	screen.add_child(overlay)
	var overlay_texture := overlay.texture
	var router := Router.install(screen)
	_check(router != null and Router.install(screen) == router, "Installation is idempotent")
	_check(router.name in screen._serialized_root_children, "Watcher survives BaseScreen presentation rebuilds")
	_check(field.texture.resource_path == COW, "Exact Field source is replaced")
	_check((field.texture.get_size() * field.scale).is_equal_approx(original_extent), "Different image dimensions preserve Sprite2D draw extent")
	_check(field.position == original_position and not field.centered, "Sprite origin and authored position stay unchanged")
	_check(home.get_rect() == original_rect and home.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "Control rectangle and stretch mode stay unchanged")
	_check(overlay.texture == overlay_texture, "Unmapped UI overlay is untouched")
	_check(field.z_index == -100 and overlay.z_index == 0, "Scene scenery stays behind live occupants while native overlay depth stays unchanged")
	_check(screen.species_background_paths.cloud_chicken == COW, "Animal exported path uses available replacement")
	_check(screen.species_background_paths.cow == COW, "Missing replacement keeps original animal source")
	_check(Router.resolved_path(COW) == COW, "Missing target path falls back without loading it")
	# Simulate a texture-only runtime refresh; ratio must not compound.
	field.texture = load(FIELD) as Texture2D
	router.call("refresh")
	_check((field.texture.get_size() * field.scale).is_equal_approx(original_extent), "Repeated texture refresh does not compound Sprite scale")
	_check(field.scale.is_equal_approx(original_scale * (load(FIELD) as Texture2D).get_size() / (load(COW) as Texture2D).get_size()), "Field scales by the measured source dimensions")
	# Simulate animal selection changing the existing Background node.
	home.texture = load(FIELD) as Texture2D
	router.call("_process", 0.3)
	_check(home.texture.resource_path == COW, "Watcher catches a later background texture swap")
	# Simulate a dynamic BaseScreen rebuilding the same number of siblings.
	home.queue_free()
	await process_frame
	var rebuilt := TextureRect.new()
	rebuilt.texture = load(HOME) as Texture2D
	screen.add_child(rebuilt)
	router.call("_process", 0.3)
	_check(rebuilt.texture.resource_path == FIELD, "Watcher discovers a rebuilt dynamic background")
	screen.queue_free()
	await process_frame
	await _check_save_skin()
	await _check_standard_native_ui("HOME", HOME, OVERLAY, "res://v6/data/screen_specs/home_hub_screen_spec_v6_3.json", "visible_ui_rects", Vector2i(135, 50))
	await _check_standard_native_ui("TITLE", TITLE_BASE, TITLE_UI, "res://v6/data/screen_specs/title_screen_spec_v6_3.json", "visible_rects", Vector2i(630, 140))
	Router._paths = production_paths
	Router._ui_masks = production_masks
	print("BACKGROUND_ART_ROUTER_V2: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _point_kept(point: Vector2, rects: PackedVector4Array) -> bool:
	for value in rects:
		if Rect2(value.x, value.y, value.z, value.w).has_point(point): return true
	return false


func _check_save_skin() -> void:
	var masks: Dictionary = Router._ui_masks.duplicate(true)
	Router._paths = {SAVE_BASE: FIELD}
	Router._ui_masks[SAVE_UI].replacement_background = COW
	var screen := Control.new()
	root.add_child(screen)
	var contrast := ColorRect.new()
	contrast.color = Color("385ec8")
	contrast.size = Vector2(1280, 720)
	screen.add_child(contrast)
	var base := TextureRect.new()
	base.texture = load(SAVE_BASE) as Texture2D
	base.size = Vector2(1280, 720)
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.add_child(base)
	var native := TextureRect.new()
	native.texture = load(SAVE_UI) as Texture2D
	native.size = Vector2(1280, 720)
	native.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	native.stretch_mode = TextureRect.STRETCH_SCALE
	screen.add_child(native)
	var original_skin := native.texture
	var quote := TextureRect.new()
	quote.texture = load(SAVE_QUOTE) as Texture2D
	quote.position = Vector2(1109, 392)
	quote.size = Vector2(122, 179)
	screen.add_child(quote)
	var label := Label.new()
	label.text = "Native label"
	label.position = Vector2(805, 469)
	label.size = Vector2(75, 44)
	screen.add_child(label)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(994, 617)
	button.size = Vector2(246, 59)
	screen.add_child(button)
	var label_rect := label.get_rect()
	var button_rect := button.get_rect()
	var router := Router.install(screen)
	_check(base.texture.resource_path == FIELD, "Save base routes after native UI preservation is installed")
	_check(native.texture == original_skin and native.material is ShaderMaterial, "Save UI keeps every original skin pixel and uses alpha clipping only")
	_check(label.get_rect() == label_rect and button.get_rect() == button_rect, "Save dynamic text and input geometry stay unchanged")
	_check(not quote.visible and quote.get_rect() == Rect2(1109, 392, 122, 179), "Decorative English quote hides without changing its authored rectangle")
	var rects: PackedVector4Array = native.get_meta("background_art_native_ui_mask", PackedVector4Array())
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://v6/data/screen_specs/save_screen_spec_v6_3.json"))
	var all_frames := true
	for values in geometry.visible_rects.values():
		var rect := Rect2(values[0], values[1], values[2], values[3])
		for point in [rect.position, rect.end - Vector2.ONE, rect.get_center()]:
			all_frames = all_frames and _point_kept(point, rects)
	_check(all_frames, "Mask retains all authored Save frame bounds including action skins")
	_check(_point_kept(Vector2(900, 105), rects), "Mask retains the detail title wood and leaf rim")
	_check(not _point_kept(Vector2(1085, 82), rects), "Mask removes the unrelated top decorative quote placard")
	_check(not _point_kept(Vector2(710, 110), rects) and not _point_kept(Vector2(640, 695), rects), "Mask reveals new scenery in gaps and removes the original footer credits")
	# A conflicting visual material blocks the base swap rather than losing UI.
	var blocked := Control.new()
	root.add_child(blocked)
	var blocked_base := TextureRect.new()
	blocked_base.texture = load(SAVE_BASE) as Texture2D
	blocked.add_child(blocked_base)
	var blocked_ui := TextureRect.new()
	blocked_ui.texture = load(SAVE_UI) as Texture2D
	blocked_ui.material = CanvasItemMaterial.new()
	blocked.add_child(blocked_ui)
	Router.install(blocked)
	_check(blocked_base.texture.resource_path == SAVE_BASE, "Save keeps original composite when a native UI material cannot be preserved")
	blocked.queue_free()
	if "--render-mask" in OS.get_cmdline_user_args():
		base.hide()
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var output := root.get_texture().get_image()
		var source := native.texture.get_image()
		var pixel_match := true
		for point in [Vector2i(400, 250), Vector2i(1160, 200), Vector2i(500, 75), Vector2i(900, 650), Vector2i(1055, 110), Vector2i(1055, 95)]:
			var actual := output.get_pixelv(point)
			var expected := source.get_pixelv(point)
			pixel_match = pixel_match and absf(actual.r - expected.r) < 0.025 and absf(actual.g - expected.g) < 0.025 and absf(actual.b - expected.b) < 0.025
		_check(pixel_match, "Rendered mask preserves original native skin colors")
		var logo_actual := output.get_pixel(100, 50)
		var logo_expected := (load(SAVE_BASE) as Texture2D).get_image().get_pixel(100, 50)
		_check(absf(logo_actual.r - logo_expected.r) < 0.025 and absf(logo_actual.b - logo_expected.b) < 0.025, "Rendered mask preserves original branded logo artwork from its native backing source")
		var revealed := output.get_pixel(640, 695)
		_check(absf(revealed.r - contrast.color.r) < 0.025 and absf(revealed.b - contrast.color.b) < 0.025, "Rendered footer gap reveals the clean underlying background")
		var report := "res://reports/BACKGROUND_ROUTING_20261009"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report))
		output.save_png(report + "/SAVE_NATIVE_UI_MASK.png")
		print("BACKGROUND_ART_ROUTER_V2 capture: ", report + "/SAVE_NATIVE_UI_MASK.png")
	screen.queue_free()
	await process_frame
	Router._ui_masks = masks


func _check_standard_native_ui(id: String, original: String, skin_path: String, geometry_path: String, group: String, logo_point: Vector2i) -> void:
	Router._paths = {original: FIELD}
	Router._ui_masks[skin_path].replacement_background = COW
	var screen := Control.new()
	root.add_child(screen)
	var contrast := ColorRect.new()
	contrast.color = Color("385ec8")
	contrast.size = Vector2(1280, 720)
	screen.add_child(contrast)
	var base := TextureRect.new()
	base.texture = load(original) as Texture2D
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.size = Vector2(1280, 720)
	screen.add_child(base)
	var native := TextureRect.new()
	native.texture = load(skin_path) as Texture2D
	native.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	native.size = Vector2(1280, 720)
	native.stretch_mode = TextureRect.STRETCH_SCALE
	screen.add_child(native)
	var original_texture := native.texture
	Router.install(screen)
	_check(base.texture.resource_path == FIELD, id + " base changes only after native UI alpha restoration is installed")
	_check(native.texture == original_texture and native.get_rect() == Rect2(0, 0, 1280, 720), id + " original UI texture and full viewport geometry stay unchanged")
	var rects: PackedVector4Array = native.get_meta("background_art_native_ui_mask", PackedVector4Array())
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(geometry_path))
	var frames_kept := true
	for values in geometry[group].values():
		var rect := Rect2(values[0], values[1], values[2], values[3])
		for point in [rect.position, rect.end - Vector2.ONE, rect.get_center()]: frames_kept = frames_kept and _point_kept(point, rects)
	_check(frames_kept, id + " mask covers every authored native frame without moving controls")
	if "--render-mask" in OS.get_cmdline_user_args():
		base.hide()
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var output := root.get_texture().get_image()
		var actual := output.get_pixelv(logo_point)
		var expected := (load(original) as Texture2D).get_image().get_pixelv(logo_point)
		_check(absf(actual.r - expected.r) < 0.025 and absf(actual.b - expected.b) < 0.025, id + " logo RGB survives its internal source alpha hole")
		var clear := output.get_pixel(0, 0)
		_check(absf(clear.r - contrast.color.r) < 0.025 and absf(clear.b - contrast.color.b) < 0.025, id + " zero-RGB source transparency stays clear")
		output.save_png("res://reports/BACKGROUND_ROUTING_20261009/" + id + "_NATIVE_UI_MASK.png")
	screen.queue_free()
	await process_frame
