extends Node

# Presentation only. Exact source paths select a replacement; scene nodes,
# input rectangles, overlays and farm state keep their authored ownership.
const MANIFEST_PATH := "res://data/presentation/background_art_replacements_v2.json"
const SCRIPT_PATH := "res://scripts/ui/background_art_router.gd"
const UI_MASK_SHADER = preload("res://scripts/ui/background_native_ui_mask.gdshader")
const WATCH_INTERVAL := 0.25
static var _paths: Dictionary = {}
static var _ui_masks: Dictionary = {}
static var _ui_guards: Dictionary = {}
static var _decorative_paths: Array = []
static var _catalog_loaded := false
static var _loaded_replacements: Dictionary = {}
var _targets: Array[CanvasItem] = []
var _sprite_draws: Dictionary = {}
var _species_originals: Dictionary = {}
var _watch_clock := 0.0
var _root_child_count := -1


static func _load_catalog() -> void:
	if _catalog_loaded: return
	_catalog_loaded = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary:
		_paths = parsed.get("replacements", {})
		_ui_masks = parsed.get("native_ui_masks", {})
		_ui_guards = parsed.get("native_ui_guards", {})
		_decorative_paths = parsed.get("decorative_textures_to_hide", [])
	else: push_error("Background replacement manifest is not a dictionary")


static func _replacement_texture(path: String) -> Texture2D:
	if _loaded_replacements.has(path): return _loaded_replacements[path] as Texture2D
	if not ResourceLoader.exists(path): return null
	var texture := load(path) as Texture2D
	if texture != null: _loaded_replacements[path] = texture
	return texture


static func resolved_path(original: String) -> String:
	_load_catalog()
	var target := String(_paths.get(original, ""))
	return target if not target.is_empty() and _replacement_texture(target) != null else original


static func texture_for(original: String) -> Texture2D:
	var path := resolved_path(original)
	if _loaded_replacements.has(path): return _loaded_replacements[path] as Texture2D
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func install(screen: Node) -> Node:
	if not is_instance_valid(screen) or screen.is_queued_for_deletion(): return null
	var existing := screen.get_node_or_null("BackgroundArtRouter")
	if existing != null:
		existing.call("refresh")
		return existing
	_load_catalog()
	var router = load(SCRIPT_PATH).new()
	router.name = "BackgroundArtRouter"
	screen.add_child(router)
	screen.child_entered_tree.connect(router._on_root_child_entered)
	# BaseScreen rebuilds dynamic siblings after state changes. Retain only this
	# watcher; it will discover the new plate without rebuilding any screen.
	for property in screen.get_property_list():
		if String(property.name) != "_serialized_root_children": continue
		var authored = screen.get("_serialized_root_children")
		if authored is Array and router.name not in authored: authored.append(router.name)
		break
	screen.set_meta("background_art_manifest", MANIFEST_PATH)
	router.refresh()
	return router


func _ready() -> void:
	set_meta("presentation_only", true)
	set_process(true)


func _texture(node: CanvasItem) -> Texture2D:
	if node is TextureRect: return (node as TextureRect).texture
	if node is Sprite2D: return (node as Sprite2D).texture
	return null


func _discover_branch(branch: Node) -> void:
	for child in branch.get_children():
		if child == self or child.is_queued_for_deletion(): continue
		if child is TextureRect or child is Sprite2D:
			var plate := child as CanvasItem
			var texture := _texture(plate)
			if texture != null and (texture.resource_path in _paths or texture.resource_path in _paths.values() or texture.resource_path in _ui_masks or texture.resource_path in _decorative_paths):
				_targets.append(plate)
		_discover_branch(child)


func _discover() -> void:
	_targets.clear()
	var screen := get_parent()
	if screen == null: return
	_discover_branch(screen)
	_root_child_count = screen.get_child_count()
	var live_ids: Array[int] = []
	for target in _targets: live_ids.append(target.get_instance_id())
	for id in _sprite_draws.keys():
		if id not in live_ids: _sprite_draws.erase(id)


func _route_species_paths() -> void:
	var screen := get_parent()
	if screen == null: return
	if _species_originals.is_empty():
		for property in screen.get_property_list():
			if String(property.name) != "species_background_paths": continue
			var paths = screen.get("species_background_paths")
			if paths is Dictionary: _species_originals = paths.duplicate(true)
			break
	if _species_originals.is_empty(): return
	var paths = screen.get("species_background_paths")
	if not paths is Dictionary: return
	for species in _species_originals:
		paths[species] = resolved_path(String(_species_originals[species]))


func _replace_plate(plate: CanvasItem) -> void:
	var source := _texture(plate)
	if source == null: return
	var original := source.resource_path
	if original not in _paths: return
	if _ui_guards.has(original):
		var masks: Dictionary = get_parent().get_meta("background_art_ui_masks", {})
		if not masks.has(String(_ui_guards[original])): return
	var path := resolved_path(original)
	if path == original: return
	var replacement := _replacement_texture(path)
	if replacement == null or replacement.get_size().x <= 0.0 or replacement.get_size().y <= 0.0: return
	if plate is Sprite2D:
		var sprite := plate as Sprite2D
		var source_scale := sprite.scale
		var id := sprite.get_instance_id()
		# A refresh can restore the original texture while leaving our scale.
		# Reuse its source scale so repeated routing never compounds the ratio.
		if _sprite_draws.has(id):
			var prior: Dictionary = _sprite_draws[id]
			if prior.source == original and sprite.scale.is_equal_approx(prior.mapped_scale):
				source_scale = prior.source_scale
		var mapped_scale := source_scale if sprite.region_enabled else source_scale * source.get_size() / replacement.get_size()
		sprite.texture = replacement
		sprite.scale = mapped_scale
		_sprite_draws[id] = {"source": original, "source_scale": source_scale, "mapped_scale": mapped_scale}
	else:
		# Keep the original Control rectangle, expand/stretch modes and anchors.
		var control := plate as TextureRect
		var authored_position := control.position
		var authored_size := control.size
		control.texture = replacement
		control.position = authored_position
		control.size = authored_size
	var extent := (plate as TextureRect).size if plate is TextureRect else (plate as Sprite2D).texture.get_size() * (plate as Sprite2D).scale.abs()
	# Dynamic BaseScreen builds append their new background after retained live
	# actors. Full scene plates need an explicit depth independent of that order.
	# Preview thumbnails that reuse an environment source keep their own depth.
	if absf(extent.x - 1280.0) <= 3.0 and absf(extent.y - 720.0) <= 3.0:
		if not plate.has_meta("background_art_original_z"): plate.set_meta("background_art_original_z", plate.z_index)
		plate.z_index = -100
	plate.set_meta("background_art_original_path", original)
	plate.set_meta("background_art_replacement_path", path)
	var screen := get_parent()
	var remapped: Dictionary = screen.get_meta("background_art_remapped", {})
	remapped[original] = path
	screen.set_meta("background_art_remapped", remapped)


func _native_mask_rects(spec: Dictionary, internal_restore := false) -> PackedVector4Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(String(spec.get("geometry_source", ""))))
	var rects := PackedVector4Array()
	if not parsed is Dictionary: return rects
	var authored: Dictionary = parsed.get(String(spec.get("geometry_group", "visible_rects")), {})
	for key in spec.get("visible_rects", {}):
		if not authored.has(key): return PackedVector4Array()
		var values: Array = authored[key]
		var rim: Array = spec.visible_rects[key]
		if internal_restore and key not in spec.get("full_rgb_restore_keys", []): rects.append(Vector4(values[0] + 4, values[1] + 4, values[2] - 8, values[3] - 8))
		else: rects.append(Vector4(values[0] - rim[0], values[1] - rim[1], values[2] + rim[0] + rim[2], values[3] + rim[1] + rim[3]))
	for values in spec.get("extra_art_rects", []):
		if internal_restore and not bool(spec.get("full_rgb_restore_extra_art", false)): rects.append(Vector4(values[0] + 4, values[1] + 4, values[2] - 8, values[3] - 8))
		else: rects.append(Vector4(values[0], values[1], values[2], values[3]))
	return rects if not rects.is_empty() and rects.size() <= 16 else PackedVector4Array()


func _clip_native_ui() -> void:
	var screen := get_parent()
	var masks: Dictionary = {}
	for plate in _targets:
		var source := _texture(plate)
		if source == null or source.resource_path not in _ui_masks: continue
		var spec: Dictionary = _ui_masks[source.resource_path]
		if _replacement_texture(String(spec.replacement_background)) == null: continue
		if plate.has_meta("background_art_native_ui_mask"):
			masks[source.resource_path] = plate.get_meta("background_art_native_ui_mask")
			continue
		# Never displace another visual material. Keep the composite background
		# until its functional skin can be preserved by this dedicated mask.
		if plate.material != null: continue
		var rects := _native_mask_rects(spec)
		if rects.is_empty(): continue
		var material := ShaderMaterial.new()
		material.shader = UI_MASK_SHADER
		material.set_shader_parameter("source_size", source.get_size())
		material.set_shader_parameter("reject_cold_backing_pixels",bool(spec.get("reject_cold_backing_pixels",false)))
		var cold_exempt := PackedVector4Array()
		var geometry = JSON.parse_string(FileAccess.get_file_as_string(String(spec.get("geometry_source", ""))))
		if geometry is Dictionary:
			var authored: Dictionary = geometry.get(String(spec.get("geometry_group", "visible_rects")), {})
			for key in spec.get("cold_filter_exempt_keys", []):
				if not authored.has(key) or cold_exempt.size() >= 4: continue
				var values: Array = authored[key]
				cold_exempt.append(Vector4(values[0], values[1], values[2], values[3]))
		material.set_shader_parameter("cold_filter_exempt_count", cold_exempt.size())
		cold_exempt.resize(4)
		material.set_shader_parameter("cold_filter_exempt_rects", cold_exempt)
		material.set_shader_parameter("keep_rect_count", rects.size())
		var shader_rects := rects.duplicate()
		shader_rects.resize(16)
		material.set_shader_parameter("keep_rects", shader_rects)
		var restore_rects := _native_mask_rects(spec, true)
		material.set_shader_parameter("restore_rect_count", restore_rects.size())
		restore_rects.resize(16)
		material.set_shader_parameter("restore_rects", restore_rects)
		var backing_path := String(spec.get("backing_texture", ""))
		if not backing_path.is_empty():
			var backing := load(backing_path) as Texture2D
			if backing == null: continue
			material.set_shader_parameter("backing_ui", backing)
		var backing_rects := PackedVector4Array()
		for values in spec.get("backing_art_rects", []): backing_rects.append(Vector4(values[0], values[1], values[2], values[3]))
		material.set_shader_parameter("backing_rect_count", backing_rects.size())
		backing_rects.resize(4)
		material.set_shader_parameter("backing_rects", backing_rects)
		plate.material = material
		plate.set_meta("background_art_native_ui_mask", rects)
		masks[source.resource_path] = rects
	screen.set_meta("background_art_ui_masks", masks)
	if masks.is_empty(): return
	for plate in _targets:
		var source := _texture(plate)
		if source != null and source.resource_path in _decorative_paths:
			plate.hide()
			plate.set_meta("background_art_hidden_decorative_text", source.resource_path)


func _on_root_child_entered(child: Node) -> void:
	if child == self or not (child is TextureRect or child is Sprite2D): return
	var texture := _texture(child as CanvasItem)
	if texture != null and (texture.resource_path in _paths or texture.resource_path in _ui_masks):
		# The same idle cycle completes the native build and routes its plate
		# before rendering; species swaps continue using the quarter-second watch.
		call_deferred("refresh")


func refresh() -> void:
	_route_species_paths()
	_discover()
	_clip_native_ui()
	for plate in _targets: _replace_plate(plate)


func _process(delta: float) -> void:
	_watch_clock += delta
	if _watch_clock < WATCH_INTERVAL: return
	_watch_clock = 0.0
	var screen := get_parent()
	if screen == null or screen.is_queued_for_deletion(): return
	_route_species_paths()
	var discover := screen.get_child_count() != _root_child_count
	for plate in _targets:
		if not is_instance_valid(plate) or plate.is_queued_for_deletion(): discover = true
	if discover: _discover()
	_clip_native_ui()
	for plate in _targets: _replace_plate(plate)
