extends Control

# Presentation only. Insert after the scene background, before actor/UI siblings.
# Scene clocks resume on reentry, but advance only while their route is active.
# This transient presentation cache never reads or writes a player save.
const MANIFEST_PATH := "res://data/presentation/world_ambient_layout_v1.json"
const FLOW_SHADER = preload("res://scripts/ui/world_ambient_flow.gdshader")
const UI_BLOCK_BUDGET := 32
const KIND_IDS := {"surface":0,"waterfall":1,"lava":2,"mist":3,"rainbow":4,"lantern":5,"foliage":6,"flag":9}
const BLOCKING_CONTROL_NAMES := ["DestinationContext","DestinationArrival","DragonWorldCare","ComingSoonPanel","DragonShopSurface","FirstSessionOrderPanel","SaveMenuDialog","AnimalCareContext","AnimalProductionStatus","MainPanel","OrdersBoard","SettingsPanel","SaveConfirmationPanel"]
static var _scene_clocks: Dictionary = {}
var scene_id := ""
var local_clock := 0.0
var externally_paused := false
var _manifest: Dictionary = {}
var _scene: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _regions: Array[PackedVector2Array] = []
var _exclusions: Array[Rect2] = []
var _particles: Array[Dictionary] = []
var _modal: Control
var _modal_lookup_clock := 0.0
var _paused := true
var _last_step_usec := 0
var _max_step_usec := 0
var _motion_frames := 0
var _visible_particles := 0
var _blocking_controls: Array[Control] = []
var _dynamic_exclusions: Array[Rect2] = []
var _last_blocks := PackedVector4Array()
var _mask_scan_clock := 0.0
var _species_scan_clock := 0.0
var _species_switches := 0
var _plate: Texture2D
var _plate_rect := Rect2(0,0,1280,720)
var _object_scan_clock := 0.0
var _crop_materials: Dictionary = {}
var _construction_levels: Dictionary = {}
var _construction_bursts: Array[Dictionary] = []
var _construction_count := 0
var _dust_canvas: Node2D
var _panel_build_levels: Dictionary = {}
var _panel_levels_initialized := false

class DustCanvas extends Node2D:
	var presenter: Control
	func _draw() -> void:
		if is_instance_valid(presenter): presenter._draw_construction_on(self)

func setup(id: String) -> void:
	if id == scene_id and not _manifest.is_empty(): return
	_cache_clock()
	scene_id = id
	local_clock = float(_scene_clocks.get(id,0.0))
	name = "WorldAmbientLife"
	position = Vector2.ZERO
	size = Vector2(1280,720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 0
	set_meta("presentation_only",true)
	set_meta("manifest",MANIFEST_PATH)
	if _manifest.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if not parsed is Dictionary:
			push_error("Ambient manifest is not a dictionary")
			return
		_manifest = parsed
	_scene = _manifest.scenes.get(scene_id,{}).duplicate(true)
	if _scene.has("inherit"):
		var inherited: Dictionary = _manifest.scenes.get(String(_scene.inherit),{}).duplicate(true)
		for key in _scene: inherited[key] = _scene[key]
		_scene = inherited
		_scene["layers"] = Array(_scene.get("layers",[])) + Array(_scene.get("extra_layers",[]))
	if _scene.is_empty():
		push_warning("No ambient presentation for scene " + scene_id)
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_materials.clear()
	_regions.clear()
	_exclusions.clear()
	_particles.clear()
	_construction_bursts.clear()
	var source_path := String(_scene.get("source",""))
	_plate = load(source_path) as Texture2D if ResourceLoader.exists(source_path) else null
	_plate_rect=Rect2(0,0,1280,720)
	for rect in _scene.get("global_exclusions_override",_manifest.get("global_exclusions",[])) + _scene.get("exclusions",[]):
		_exclusions.append(Rect2(rect[0],rect[1],rect[2],rect[3]))
	for record in _scene.get("layers",[]): _add_flow(record)
	var random := RandomNumberGenerator.new()
	random.seed = String(scene_id).hash()
	for record in _scene.get("particles",[]): _add_particles(record,random)
	_update_particles()
	_dust_canvas = DustCanvas.new()
	_dust_canvas.name = "ConstructionDust"
	_dust_canvas.presenter = self
	# Building sprites use foot depth. Keep dust visible in front of them and
	# below the destination HUD; masks also remove any active context panel.
	_dust_canvas.z_index = 900
	add_child(_dust_canvas)
	_mask_scan_clock = 0.0
	_blocking_controls.clear()
	_last_blocks.clear()
	set_meta("particle_budget",_particles.size())
	set_process(true)
	queue_redraw()

func _cache_clock() -> void:
	if not scene_id.is_empty(): _scene_clocks[scene_id] = local_clock

func _exit_tree() -> void:
	_cache_clock()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(not _scene.is_empty())

func _polygon(points: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in points: polygon.append(Vector2(point[0],point[1]))
	return polygon

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: rect = rect.expand(point)
	return rect

func _safe_pieces(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [polygon]
	for rect in _exclusions:
		var cut := PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
		var remaining: Array[PackedVector2Array] = []
		for piece in pieces:
			for result_polygon in Geometry2D.clip_polygons(piece,cut):
			# A hole cannot be drawn as an independent fill. Shader exclusions
			# also cover interior cuts, so omitted hole contours stay transparent.
				if not Geometry2D.is_polygon_clockwise(result_polygon): remaining.append(result_polygon)
		pieces = remaining
	return pieces

func _add_flow(record: Dictionary) -> void:
	var polygon := _polygon(record.polygon)
	var bounds := _bounds(polygon)
	for piece in _safe_pieces(polygon):
		if piece.size() < 3: continue
		var node := Polygon2D.new()
		node.name = "Ambient_" + String(record.id) + "_" + str(_materials.size())
		node.polygon = piece
		var uv := PackedVector2Array()
		for point in piece: uv.append((point-bounds.position) / bounds.size)
		node.uv = uv
		var material := ShaderMaterial.new()
		material.shader = FLOW_SHADER
		material.set_shader_parameter("effect_kind",KIND_IDS.get(record.kind,0))
		material.set_shader_parameter("strength",float(record.get("strength",0.15)))
		material.set_shader_parameter("flow_direction",Vector2(record.flow[0],record.flow[1]))
		material.set_shader_parameter("region_size",bounds.size)
		material.set_shader_parameter("region_origin",bounds.position)
		material.set_shader_parameter("tint",Color(String(record.color)))
		material.set_shader_parameter("world_plate",_plate)
		material.set_shader_parameter("plate_origin",_plate_rect.position)
		material.set_shader_parameter("plate_size",_plate_rect.size)
		material.set_shader_parameter("phase",float(String(record.id).hash()%31)*0.27)
		material.set_shader_parameter("sway_pixels",float(record.get("sway_pixels",2.6)))
		material.set_shader_parameter("local_clock",local_clock)
		var points := PackedVector2Array(piece)
		material.set_shader_parameter("mask_point_count",mini(points.size(),20))
		points.resize(20)
		material.set_shader_parameter("mask_points",points)
		node.material = material
		node.set_meta("mask_polygon",piece)
		node.set_meta("effect_kind",record.kind)
		add_child(node)
		_materials.append(material)
		_regions.append(piece)

func _allowed(point: Vector2,polygon: PackedVector2Array,margin := 5.0) -> bool:
	if not Geometry2D.is_point_in_polygon(point,polygon): return false
	for rect in _exclusions:
		if rect.grow(margin).has_point(point): return false
	for rect in _dynamic_exclusions:
		if rect.grow(margin).has_point(point): return false
	for offset in [Vector2(margin,0),Vector2(-margin,0),Vector2(0,margin),Vector2(0,-margin)]:
		if not Geometry2D.is_point_in_polygon(point + offset,polygon): return false
	return true

func _add_particles(record: Dictionary,random: RandomNumberGenerator) -> void:
	if String(record.kind) == "smoke":
		var emitter: Array = record.emitter
		for index in range(mini(int(record.count),12)):
			_particles.append({"kind":"smoke","origin":Vector2(emitter[0],emitter[1]),"position":Vector2(emitter[0],emitter[1]),"phase":float(index)/float(record.count),"lifetime":float(record.get("lifetime",3.4)),"velocity":Vector2(record.velocity[0],record.velocity[1]),"size":float(record.get("radius",4.5)),"color":Color(String(record.color)),"alpha":0.0})
		return
	var polygon := _polygon(record.polygon)
	var bounds := _bounds(polygon)
	for _index in range(mini(int(record.count),24)):
		var point := bounds.get_center()
		var found := false
		for _attempt in range(64):
			point = bounds.position + Vector2(random.randf(),random.randf()) * bounds.size
			if _allowed(point,polygon):
				found = true
				break
		if not found: continue
		_particles.append({"kind":String(record.kind),"origin":point,"position":point,"polygon":polygon,"bounds":bounds,"velocity":Vector2(record.velocity[0],record.velocity[1]),"phase":random.randf()*TAU,"size":random.randf_range(1.2,2.6),"color":Color(String(record.color)),"alpha":0.0})

func set_paused(value: bool) -> void:
	externally_paused = value

func _save_modal_visible(delta: float) -> bool:
	if _modal != null and is_instance_valid(_modal): return _modal.is_visible_in_tree()
	_modal_lookup_clock -= delta
	if _modal_lookup_clock > 0.0: return false
	_modal_lookup_clock = 0.35
	var screen := get_parent()
	if screen != null: _modal = screen.find_child("SaveMenuDialog",true,false) as Control
	return _modal != null and _modal.is_visible_in_tree()

func _process(delta: float) -> void:
	var pause_now := externally_paused or not is_visible_in_tree() or _save_modal_visible(delta)
	_paused = pause_now
	if pause_now: return
	var started := Time.get_ticks_usec()
	_follow_animal_selection(delta)
	_refresh_visible_ui_masks(delta)
	_refresh_world_objects(delta)
	local_clock += minf(delta,0.05)
	_cache_clock()
	_motion_frames += 1
	for material in _materials: material.set_shader_parameter("local_clock",local_clock)
	for key in _crop_materials.keys():
		var crop: Dictionary = _crop_materials[key]
		if not is_instance_valid(crop.body):
			_crop_materials.erase(key)
			continue
		(crop.material as ShaderMaterial).set_shader_parameter("local_clock",local_clock)
	_update_particles()
	queue_redraw()
	if is_instance_valid(_dust_canvas): _dust_canvas.queue_redraw()
	for index in range(_construction_bursts.size()-1,-1,-1):
		if local_clock-float(_construction_bursts[index].born)>1.8: _construction_bursts.remove_at(index)
	_last_step_usec = Time.get_ticks_usec()-started
	_max_step_usec = maxi(_max_step_usec,_last_step_usec)

func _update_particles() -> void:
	_visible_particles = 0
	for particle in _particles:
		if String(particle.kind) == "smoke":
			var age := fposmod(local_clock+float(particle.phase)*float(particle.lifetime),float(particle.lifetime))
			var progress := age/float(particle.lifetime)
			particle.position = Vector2(particle.origin)+Vector2(particle.velocity)*age+Vector2(sin(age*1.15+float(particle.phase)*TAU)*3.8*progress,0)
			var smoke_extent := float(particle.size)*(0.42+progress*1.65)*1.9
			particle.alpha = sin(progress*PI)*0.32 if _point_clear(particle.position,smoke_extent) else 0.0
			particle.progress = progress
			if float(particle.alpha)>0.0: _visible_particles += 1
			continue
		var bounds: Rect2 = particle.bounds
		var origin: Vector2 = particle.origin
		var velocity: Vector2 = particle.velocity
		var travel := origin + velocity * local_clock
		travel.x = bounds.position.x + fposmod(travel.x-bounds.position.x,bounds.size.x)
		travel.y = bounds.position.y + fposmod(travel.y-bounds.position.y,bounds.size.y)
		travel += Vector2(sin(local_clock*0.7+particle.phase)*3.0,cos(local_clock*0.6+particle.phase)*2.0)
		particle.position = travel
		particle.alpha = 0.0
		if _allowed(travel,particle.polygon):
			var nearest_edge := minf(minf(travel.x-bounds.position.x,bounds.end.x-travel.x),minf(travel.y-bounds.position.y,bounds.end.y-travel.y))
			particle.alpha = clampf(nearest_edge/16.0,0.0,1.0) * 0.70
			_visible_particles += 1

func _point_clear(point: Vector2,margin := 0.0) -> bool:
	for rect in _exclusions + _dynamic_exclusions:
		if rect.grow(margin).has_point(point): return false
	return true

func _refresh_world_objects(delta: float) -> void:
	_object_scan_clock -= delta
	if _object_scan_clock>0.0: return
	_object_scan_clock = 0.30
	var screen := get_parent()
	if screen == null: return
	var candidates: Array[Node] = screen.find_children("*","TextureRect",true,false)
	var newest_plate: Texture2D
	var newest_rect := Rect2(0,0,1280,720)
	for candidate in candidates:
		var texture_rect := candidate as TextureRect
		if not texture_rect.is_visible_in_tree() or texture_rect.texture == null: continue
		if texture_rect.size.x<1100 or texture_rect.size.y<640: continue
		if String(texture_rect.name).to_lower().contains("overlay") or String(texture_rect.name).contains("GUIDE"): continue
		if texture_rect.has_meta("background_art_native_ui_mask"): continue
		newest_plate = texture_rect.texture
		var inverse := get_global_transform().affine_inverse()
		var global_rect := texture_rect.get_global_rect()
		newest_rect = Rect2(inverse*global_rect.position,inverse.basis_xform(global_rect.size))
		if texture_rect.stretch_mode in [TextureRect.STRETCH_KEEP_ASPECT,TextureRect.STRETCH_KEEP_ASPECT_CENTERED,TextureRect.STRETCH_KEEP_ASPECT_COVERED]:
			var ratios := newest_rect.size/newest_plate.get_size()
			var scale_factor := maxf(ratios.x,ratios.y) if texture_rect.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_COVERED else minf(ratios.x,ratios.y)
			var span := newest_plate.get_size()*scale_factor
			if texture_rect.stretch_mode!=TextureRect.STRETCH_KEEP_ASPECT: newest_rect.position+=(newest_rect.size-span)*0.5
			newest_rect.size=span
		break
	if newest_plate != null and (newest_plate != _plate or not newest_rect.is_equal_approx(_plate_rect)):
		_plate = newest_plate
		_plate_rect = newest_rect
		for material in _materials:
			material.set_shader_parameter("world_plate",_plate)
			material.set_shader_parameter("plate_origin",_plate_rect.position)
			material.set_shader_parameter("plate_size",_plate_rect.size)
	for sprite_node in screen.find_children("ProductionCrop","Sprite2D",true,false):
		var crop := sprite_node as Sprite2D
		if _crop_materials.has(crop.get_instance_id()): continue
		var material := ShaderMaterial.new()
		material.shader = FLOW_SHADER
		material.set_shader_parameter("effect_kind",7)
		material.set_shader_parameter("phase",float(String(crop.get_parent().name).hash()%31)*0.26)
		material.set_shader_parameter("sway_pixels",6.0)
		crop.material = material
		crop.set_meta("rooted_wind_motion",true)
		_crop_materials[crop.get_instance_id()] = {"body":crop,"material":material}
	for landmark in screen.find_children("DestinationLandmark_buildings_*","Control",true,false):
		var key := String(landmark.get_meta("config_id",landmark.name))
		var current_level := int(landmark.get("level"))
		if _construction_levels.has(key) and current_level>int(_construction_levels[key]):
			var body := landmark as Control
			var feet = body.get_meta("feet",body.position+body.size*Vector2(0.5,0.9))
			play_construction(Vector2(feet),body.size.x*0.46)
		_construction_levels[key] = current_level
	_observe_panel_builds(screen)

func _observe_panel_builds(screen: Node) -> void:
	if scene_id not in ["craft","shop"]: return
	# Read only the committed dictionary. Failed/rolled-back purchases have no
	# positive level delta, so they cannot borrow a success dust effect.
	var world: Dictionary = GameState.data.get("world",{})
	var levels: Dictionary = world.get("buildings",{})
	if not _panel_levels_initialized:
		_panel_build_levels = levels.duplicate()
		_panel_levels_initialized = true
		return
	var selected := ""
	var visual: Control
	if scene_id=="craft":
		selected = String(screen.get("selected_id"))
		visual = screen.get_node_or_null("MainPanel/EntryPreview") as Control
	else:
		var content := screen.get_node_or_null("SharedShopContent")
		if content!=null: selected=String(content.get("selected_product"))
		visual = screen.find_child("ProductArtwork",true,false) as Control
	for key in levels:
		if String(key)!=selected or int(levels[key])<=int(_panel_build_levels.get(key,0)) or visual==null: continue
		var global_rect := visual.get_global_rect()
		var inverse := get_global_transform().affine_inverse()
		var preview_rect := Rect2(inverse*global_rect.position,inverse.basis_xform(global_rect.size))
		play_construction(Vector2(preview_rect.get_center().x,preview_rect.end.y-22),preview_rect.size.x*0.32,preview_rect)
	_panel_build_levels = levels.duplicate()

func play_construction(scene_position: Vector2,spread := 80.0,preview_rect := Rect2()) -> void:
	# Called after an observed level increase. Pure presentation: no resource,
	# building, route, or save mutation happens here.
	if _construction_bursts.size()>=3: _construction_bursts.pop_front()
	_construction_bursts.append({"origin":scene_position,"spread":spread,"born":local_clock,"preview_rect":preview_rect})
	_construction_count += 1
	if is_instance_valid(_dust_canvas): _dust_canvas.queue_redraw()

func _draw_construction_on(canvas: Node2D) -> void:
	for burst in _construction_bursts:
		var age := local_clock-float(burst.born)
		var progress := age/1.8
		for index in range(16):
			var side := (float(index)/15.0-0.5)*2.0
			var point := Vector2(burst.origin)+Vector2(side*float(burst.spread)*(0.3+progress*0.8),-sin(float(index)*2.3)*6.0-age*(16.0+float(index%4)*6.0))
			var radius := (4.0+float(index%4)*1.4)*(0.5+progress*1.8)
			var preview_rect: Rect2 = burst.get("preview_rect",Rect2())
			if preview_rect.has_area():
				# A building illustration is allowed to animate inside its own
				# clipped preview; no dust may reach panel text or action controls.
				if not preview_rect.grow(-radius*1.85).has_point(point): continue
			elif not _point_clear(point,radius*1.85): continue
			var color := Color("dcc69e")
			color.a = sin(clampf(progress,0.0,1.0)*PI)*0.40
			for ring in range(3,0,-1):
				var soft := color
				soft.a *= 0.22/float(ring)
				canvas.draw_circle(point,radius*(1.0+float(ring)*0.28),soft)
			canvas.draw_circle(point,radius,color)

func _follow_animal_selection(delta: float) -> void:
	if not scene_id.begins_with("animal_"): return
	_species_scan_clock -= delta
	if _species_scan_clock > 0.0: return
	_species_scan_clock = 0.35
	var screen := get_parent()
	if screen == null: return
	var selected = screen.get("selected_species")
	if not selected is String: return
	var selected_key := "animal_" + String(selected)
	if selected_key == scene_id or not _manifest.scenes.has(selected_key): return
	setup(selected_key)
	_species_switches += 1

func _refresh_visible_ui_masks(delta: float) -> void:
	_mask_scan_clock -= delta
	if _mask_scan_clock <= 0.0:
		_mask_scan_clock = 0.35
		_blocking_controls.clear()
		var screen := get_parent()
		if screen != null:
			for control_name in BLOCKING_CONTROL_NAMES:
				var control := screen.find_child(control_name,true,false) as Control
				if control != null: _blocking_controls.append(control)
			# Caption paper is translucent. Mask its whole measured surface so
			# moving wisps cannot subtly flicker through letters or their backing.
			for control in screen.find_children("*","Control",true,false):
				if control.get_meta("readable_world_caption",false): _blocking_controls.append(control as Control)
	_dynamic_exclusions.clear()
	var blocks := PackedVector4Array()
	for rect in _exclusions:
		blocks.append(Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
	for control in _blocking_controls:
		if not is_instance_valid(control) or not control.is_visible_in_tree(): continue
		var global_rect := control.get_global_rect()
		var inverse := get_global_transform().affine_inverse()
		var rect := Rect2(inverse * global_rect.position,inverse.basis_xform(global_rect.size))
		_dynamic_exclusions.append(rect)
		blocks.append(Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
		if blocks.size() == UI_BLOCK_BUDGET: break
	var count := blocks.size()
	while blocks.size() < UI_BLOCK_BUDGET: blocks.append(Vector4.ZERO)
	if blocks == _last_blocks: return
	_last_blocks = blocks
	for material in _materials:
		material.set_shader_parameter("ui_block_count",count)
		material.set_shader_parameter("ui_blocks",blocks)

func _draw() -> void:
	for particle in _particles:
		var color: Color = particle.color
		color.a = float(particle.alpha)
		if color.a <= 0.0: continue
		var point: Vector2 = particle.position
		var radius := float(particle.size)
		match String(particle.kind):
			"smoke":
				var progress := float(particle.get("progress",0.0))
				radius *= 0.42+progress*1.65
				for ring in range(4,0,-1):
					var soft := color
					soft.a *= 0.13/float(ring)
					draw_circle(point,radius*(1.0+float(ring)*0.20),soft)
				# Unequal overlapping wisps avoid a row of identical hard circles.
				color.a *= 0.24
				draw_circle(point+Vector2(radius*0.23,-radius*0.12),radius*0.77,color)
				draw_circle(point-Vector2(radius*0.27,0),radius*0.63,color)
			"leaf":
				var direction := Vector2.from_angle(particle.phase + local_clock*0.3)
				var cross := direction.orthogonal()
				draw_colored_polygon(PackedVector2Array([point-direction*radius*1.7,point+cross*radius,point+direction*radius*1.7,point-cross*radius]),color)
			"breeze":
				color.a *= 0.35
				draw_line(point-Vector2(radius*2,0),point+Vector2(radius*2,0),color,1.0,true)
			"firefly", "ember":
				var halo := color
				halo.a *= 0.12
				draw_circle(point,radius*2.1,halo)
				color.a *= 0.75 + 0.15*sin(local_clock*0.8+particle.phase)
				draw_circle(point,radius*0.55,color)
			"snow":
				color.a *= 0.65
				draw_circle(point,radius*0.5,color)

func qa_summary() -> Dictionary:
	return {"scene":scene_id,"clock":local_clock,"paused":_paused or not can_process(),"motion_frames":_motion_frames,"layers":_materials.size(),"particles":_particles.size(),"visible_particles":_visible_particles,"rooted_crops":_crop_materials.size(),"construction_bursts":_construction_count,"max_process_usec":_max_step_usec,"last_process_usec":_last_step_usec,"mouse_filter":mouse_filter,"z_index":z_index,"species_switches":_species_switches,"cached_scene_count":_scene_clocks.size(),"foliage_edge_displacement":0.0,"flow_source":_plate.resource_path if _plate!=null else ""}

func qa_point_in_water_mask(point: Vector2) -> bool:
	for rect in _exclusions + _dynamic_exclusions:
		if rect.has_point(point): return false
	for region in _regions:
		if Geometry2D.is_point_in_polygon(point,region): return true
	return false

func qa_point_in_exclusion(point: Vector2) -> bool:
	for rect in _exclusions:
		if rect.grow(-2).has_point(point): return true
	return false
