extends Control

# Painted flow belongs to the scenic panel, never to the surrounding menu.
# All geometry is measured in source coordinates and remapped through the
# actual TextureRect draw extent. This node is below island art and controls.
const Ambient = preload("res://scripts/ui/world_ambient_life.gd")
const FLOW = preload("res://scripts/ui/world_ambient_flow.gdshader")
const COPY_NAMES := ["LandmarkNamePlaque","EntryState"]
static var _panel_clocks: Dictionary = {}
var panel_id := ""
var local_clock := 0.0
var _source: TextureRect
var _materials: Array[ShaderMaterial] = []
var _record: Dictionary = {}
var _screen: Node
var _paused := false
var _draw_extent := Rect2()

func setup(id: String,source: TextureRect) -> void:
	panel_id = id
	_source = source
	name = "PanelSceneryLife"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_meta("presentation_only",true)
	set_meta("source_measured_motion",true)
	local_clock = float(_panel_clocks.get(id,0.0))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(Ambient.MANIFEST_PATH))
	if manifest is Dictionary: _record = manifest.get("panel_scenes",{}).get(id,{})
	_source.resized.connect(_rebuild)
	_rebuild()
	set_process(true)

func _exit_tree() -> void:
	if not panel_id.is_empty(): _panel_clocks[panel_id] = local_clock

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_materials.clear()
	if not is_instance_valid(_source) or _source.texture==null or _record.is_empty(): return
	# Source-specific masks are not silently reused against unrelated artwork.
	if _source.texture.resource_path!=String(_record.get("source","")): return
	position = _source.position
	size = _source.size
	var texture_size := _source.texture.get_size()
	var draw_scale := maxf(size.x/texture_size.x,size.y/texture_size.y)
	_draw_extent = Rect2((size-texture_size*draw_scale)*0.5,texture_size*draw_scale)
	var reference := Vector2(_record.canvas[0],_record.canvas[1])
	for layer in _record.get("layers",[]):
		var points := PackedVector2Array()
		for point in layer.polygon: points.append(_draw_extent.position+Vector2(point[0],point[1])/reference*_draw_extent.size)
		var bounds := Rect2(points[0],Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		var polygon := Polygon2D.new()
		polygon.name = String(layer.id)
		polygon.polygon = points
		var material := ShaderMaterial.new()
		material.shader = FLOW
		material.set_shader_parameter("effect_kind",Ambient.KIND_IDS.get(layer.kind,0))
		material.set_shader_parameter("strength",float(layer.strength))
		material.set_shader_parameter("flow_direction",Vector2(layer.flow[0],layer.flow[1]))
		material.set_shader_parameter("region_origin",bounds.position)
		material.set_shader_parameter("region_size",bounds.size)
		material.set_shader_parameter("world_plate",_source.texture)
		material.set_shader_parameter("plate_origin",_draw_extent.position)
		material.set_shader_parameter("plate_size",_draw_extent.size)
		material.set_shader_parameter("phase",float(String(layer.id).hash()%31)*0.27)
		material.set_shader_parameter("local_clock",local_clock)
		material.set_shader_parameter("mask_point_count",mini(points.size(),20))
		points.resize(20)
		material.set_shader_parameter("mask_points",points)
		polygon.material = material
		add_child(polygon)
		_materials.append(material)
	_refresh_copy_masks()

func _find_screen() -> Node:
	var node := get_parent()
	while node!=null:
		if node.get_node_or_null("WorldAmbientLife")!=null: return node
		node=node.get_parent()
	return null

func _refresh_copy_masks() -> void:
	if not is_inside_tree() or get_parent()==null: return
	var blocks := PackedVector4Array()
	var inverse := get_global_transform().affine_inverse()
	for copy_name in COPY_NAMES:
		for node in get_parent().find_children(copy_name,"Control",true,false):
			var control := node as Control
			if not control.is_visible_in_tree() or blocks.size()>=Ambient.UI_BLOCK_BUDGET: continue
			var global_rect := control.get_global_rect().grow(2.0)
			var rect := Rect2(inverse*global_rect.position,inverse.basis_xform(global_rect.size))
			blocks.append(Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
	var count := blocks.size()
	blocks.resize(Ambient.UI_BLOCK_BUDGET)
	for material in _materials:
		material.set_shader_parameter("ui_blocks",blocks)
		material.set_shader_parameter("ui_block_count",count)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not is_instance_valid(_screen): _screen = _find_screen()
	var ambient := _screen.get_node_or_null("WorldAmbientLife") if _screen!=null else null
	if ambient!=null:
		var state: Dictionary = ambient.qa_summary()
		_paused = bool(state.paused)
		if _paused: return
		local_clock = float(state.clock)
	else:
		local_clock += minf(delta,0.05)
	_panel_clocks[panel_id] = local_clock
	_refresh_copy_masks()
	for material in _materials: material.set_shader_parameter("local_clock",local_clock)

func qa_summary() -> Dictionary:
	return {"panel":panel_id,"clock":local_clock,"paused":_paused or not can_process(),"layers":_materials.size(),"mouse_filter":mouse_filter,"clipped":clip_contents,"source":_source.texture.resource_path if is_instance_valid(_source) and _source.texture!=null else "","draw_extent":str(_draw_extent)}
