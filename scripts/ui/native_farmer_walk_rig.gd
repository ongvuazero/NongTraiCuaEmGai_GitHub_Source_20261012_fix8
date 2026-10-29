extends Node2D
class_name NativeFarmerWalkRig

# Original bitmap pixels are untouched. These textured articulated polygons
# are assembled from measured alpha islands, never a warped whole-body sprite.
signal footstep(leg: int)
const LAYOUT := "res://assets/player_feedback_v3/farmer/rig_layout.json"
const REFERENCE_HEIGHT := 125.0
const GROUND_Y := 0.6
const HEIGHT_Y := 0.9
const STRIDE := 64.0
const CADENCE := 2.35
const HIP_HEIGHT := 40.0
const LEG_LENGTH := 19.5
var _unit := 1.0
var _definition: Dictionary = {}
var _parts: Dictionary = {}
var _textures: Dictionary = {}
var _position_plane := Vector2.ZERO
var _last_position := Vector2.ZERO
var _direction := Vector2.RIGHT # physical ground x/z, not screen x/y
var _distance := 0.0
var _plants := [Vector2.ZERO, Vector2.ZERO]
var _boot_facing := [1.0, 1.0]
var _boot_origins := [Vector2.ZERO, Vector2.ZERO]
var _walking := false
var _settling := false
var _settle_elapsed := 0.0
var _settle_from := [Vector2.ZERO, Vector2.ZERO]
var _settle_lift := [0.0, 0.0]
var _settle_order := [1,0]
var _settle_next_facing := 1.0
var _settle_phase := 0.0
var _swing_from := [Vector2.ZERO,Vector2.ZERO]
var _intro := 1.0
var _facing := 1.0
var _back := false
var _lift := [0.0, 0.0]
var _supports := [false, false]
var _knees := [Vector3.ZERO, Vector3.ZERO]
var _ankles := [Vector3.ZERO, Vector3.ZERO]
var _goal_feet := [Vector2.ZERO, Vector2.ZERO]
var _ik_clamps := 0
var _footprints: Dictionary = {}
var _navigation_radius := -1.0
var _body_height_delta := 0.0
var _settle_body_height := 0.0

func configure(visible_height: float) -> bool:
	_unit = visible_height / REFERENCE_HEIGHT
	var value = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not value is Dictionary: return false
	_definition = value
	for key in _definition.get("parts", {}):
		_create_part(String(key), _definition.parts[key])
	# All cutout pieces remain in the actor's y-sort canvas layer. Their
	# internal authored paint order must not jump in front of nearby crops.
	var ordered := get_children()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get_meta("paint_layer",0)) < int(b.get_meta("paint_layer",0)))
	for part in ordered: move_child(part,get_child_count()-1)
	visible = false
	return _parts.has("head") and _parts.has("body") and _parts.has("boot_0") and _parts.has("boot_1")

func stride_pixels() -> float: return STRIDE * _unit
func physical_speed() -> float: return stride_pixels() * CADENCE
func cadence_cycles_per_second() -> float: return CADENCE
func physical_distance(projected_delta: Vector2) -> float:
	return Vector2(projected_delta.x, projected_delta.y / GROUND_Y).length()
func travel_duration(projected_delta: Vector2) -> float:
	return physical_distance(projected_delta) / physical_speed()
func current_direction_plane() -> Vector2: return _project_ground(_direction)
func needs_turn(direction_in_plane: Vector2) -> bool:
	if not _walking or direction_in_plane.length_squared()<0.00001: return false
	var next := Vector2(direction_in_plane.x,direction_in_plane.y/GROUND_Y).normalized()
	return _direction.dot(next)<cos(deg_to_rad(15.0))
func settle_duration() -> float: return 0.20

func navigation_radius() -> float:
	if _navigation_radius>=0.0: return _navigation_radius
	var radius := 0.0
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(1,-1),Vector2(-1,1),Vector2(-1,-1)]:
		for point in navigation_footprint(direction): radius=maxf(radius,point.length())
	_navigation_radius=radius
	return _navigation_radius

func navigation_footprint(direction_in_plane: Vector2) -> PackedVector2Array:
	# Envelope of actual cutout boot vertices at every stance/swing/gather
	# position. Include both mirroring signs: a turn changes the boot only
	# while it is airborne. Startup's old standing contact also belongs here.
	var physical := Vector2(direction_in_plane.x,direction_in_plane.y/GROUND_Y).normalized()
	if physical.length_squared()<0.001: physical=Vector2.RIGHT
	if _footprints.has(physical): return _footprints[physical]
	var across := Vector2(-physical.y,physical.x)
	var points := PackedVector2Array()
	for leg in range(2):
		var boot := _parts["boot_%d"%leg] as Polygon2D
		var sole := float(_definition.parts["boot_%d"%leg].sole_height)*_unit
		var side := across*(-4.0 if leg==0 else 4.0)*_unit
		var standing := _standing_foot(leg)
		var origins: Array[Vector2]=[]
		# A world-space cubic smoothstep has real swing extrema at
		# t=(1±sqrt(2/3))/2: ±.27208stride, beyond the±.25 stance limit.
		for lead in [-stride_pixels()*0.275,stride_pixels()*0.275]:
			origins.append(_project_ground(side+physical*lead))
		# First stance / swing can trail from a true standing boot, not a
		# fabricated pre-stretched start pose. Gather stays in their hull.
		origins.append(standing)
		origins.append(standing-_project_ground(physical*stride_pixels()*0.25))
		for origin in origins:
			for lift in [0.0,7.0*_unit]:
				for facing in [-1.0,1.0]:
					for vertex in boot.polygon:
						points.append(origin+Vector2(vertex.x*facing,vertex.y-(sole+lift)*HEIGHT_Y))
	var hull:=Geometry2D.convex_hull(points)
	# Latest intents may introduce continuously varying headings. Bound the
	# cache for long sessions; recomputing a hull does not mutate gait state.
	if _footprints.size()>=512: _footprints.clear()
	_footprints[physical]=hull
	return hull

func begin_walk(feet_in_parent_plane: Vector2, direction_in_plane: Vector2, preserve_phase := false) -> void:
	_position_plane = feet_in_parent_plane
	_last_position = feet_in_parent_plane
	_set_direction(direction_in_plane)
	if not preserve_phase or not _walking:
		# Start from standing, in mid-support, instead of teleporting a boot
		# instantly16px forward on the first frame of a new journey.
		# Support the forward standing foot first. Choosing the trailing foot
		# forced a23px initial reach before its first lift (an unnatural stretch).
		var best_leg:=0
		var best_reach:=INF
		for leg in range(2):
			var predicted:=_standing_foot(leg)-_project_ground(_direction*stride_pixels()*0.25)-_side_offset(leg)
			var reach:=physical_distance(predicted)
			if reach<best_reach: best_reach=reach; best_leg=leg
		_distance = stride_pixels() * (0.25 if best_leg==0 else 0.75)
		_plants[0] = _position_plane + _standing_foot(0)
		_plants[1] = _position_plane + _standing_foot(1)
		_swing_from = [_plants[0],_plants[1]]
		_boot_facing = [_facing, _facing]
		_intro = 0.0
	_walking = true
	_settling = false
	visible = true
	_pose()

func advance_walk(feet_in_parent_plane: Vector2, direction_in_plane: Vector2, delta: float) -> void:
	if not _walking: return
	var previous := _distance
	var movement := feet_in_parent_plane - _last_position
	var traveled := physical_distance(movement)
	if traveled > 0.00001: _set_direction(movement)
	elif direction_in_plane.length_squared() > 0.001: _set_direction(direction_in_plane)
	_distance += traveled
	var half_stride := stride_pixels() * 0.5
	var boundary := int(floor(previous / half_stride)) + 1
	while float(boundary) * half_stride <= _distance and traveled > 0.00001:
		var proportion := (float(boundary) * half_stride - previous) / traveled
		var contact_root := _last_position.lerp(feet_in_parent_plane, clampf(proportion, 0.0, 1.0))
		var leg := boundary % 2
		_plants[leg] = contact_root + _side_offset(leg) + _project_ground(_direction * stride_pixels() * 0.25)
		_swing_from[1-leg] = _plants[1-leg]
		_boot_facing[leg] = _facing
		footstep.emit(leg)
		boundary += 1
	_position_plane = feet_in_parent_plane
	_last_position = feet_in_parent_plane
	if traveled > 0.00001: _intro = minf(1.0, _intro + traveled / (stride_pixels()*0.25))
	_pose()

func end_walk(immediate := false, next_direction_in_plane := Vector2.ZERO) -> void:
	_walking = false
	if immediate:
		_settling = false
		visible = false
		return
	_settling = true
	_settle_elapsed = 0.0
	_settle_order = [1,0] if bool(_supports[0]) else [0,1]
	_settle_next_facing = _facing
	if absf(next_direction_in_plane.x)>0.01: _settle_next_facing = 1.0 if next_direction_in_plane.x>0.0 else -1.0
	_settle_phase = fposmod(_distance/stride_pixels(),1.0)
	_settle_body_height = _body_height_delta
	for leg in range(2):
		_settle_from[leg] = _goal_feet[leg]
		_settle_lift[leg] = _lift[leg]

func settle_complete() -> bool: return not _settling

func advance_settle(delta: float) -> void:
	if not _settling: return
	_settle_elapsed += delta
	var t := clampf(_settle_elapsed / settle_duration(), 0.0, 1.0)
	_body_height_delta=lerpf(_settle_body_height,0.0,t*t*(3.0-2.0*t))
	for order in range(2):
		var leg := int(_settle_order[order])
		var step_t := clampf(t*2.0-float(order),0.0,1.0)
		var easing := step_t*step_t*(3.0-2.0*step_t)
		var local: Vector2 = (_settle_from[leg] as Vector2).lerp(_standing_foot(leg),easing)
		var lift: float = lerpf(float(_settle_lift[leg]),0.0,easing)+sin(PI*step_t)*4.0*_unit
		_goal_feet[leg] = local
		_lift[leg] = lift
		_supports[leg] = step_t>=1.0 or (step_t<=0.0 and float(_settle_lift[leg])<0.001)
		if step_t>0.15: _boot_facing[leg] = _settle_next_facing
		_place_leg(leg, local, lift, _boot_facing[leg])
	_place_upper_body(lerpf(_settle_phase,0.0,t*t*(3.0-2.0*t)),1.0-t*t*(3.0-2.0*t))
	if t >= 1.0: _settling = false

func _set_direction(screen_direction: Vector2) -> void:
	if screen_direction.length_squared() <= 0.000001: return
	_direction = Vector2(screen_direction.x, screen_direction.y/GROUND_Y).normalized()
	if absf(screen_direction.x) > 0.02: _facing = 1.0 if screen_direction.x > 0.0 else -1.0
	_back = screen_direction.y < -absf(screen_direction.x) * 0.55

func _standing_foot(leg: int) -> Vector2:
	return Vector2((-7.0 if leg == 0 else 4.0) * _unit, 0.0)

func _side_offset(leg: int) -> Vector2:
	var across := Vector2(-_direction.y, _direction.x)
	return _project_ground(across * (-4.0 if leg == 0 else 4.0) * _unit)

func _pose() -> void:
	var phase := fposmod(_distance / stride_pixels(), 1.0)
	# Real bounded pelvis rise at each support pass. Joints share this height;
	# the head/torso are never resized and the grounded boots stay world-locked.
	_body_height_delta=-cos(TAU*phase*2.0)*0.6*_unit*_intro
	for leg in range(2):
		var leg_phase := fposmod(phase + (0.0 if leg == 0 else 0.5), 1.0)
		var planted := leg_phase < 0.5
		var local := Vector2.ZERO
		var lift := 0.0
		if planted:
			local = (_plants[leg] as Vector2) - _position_plane
		else:
			var t := (leg_phase - 0.5) * 2.0
			var smooth := t*t*(3.0 - 2.0*t)
			var landing := _position_plane+_side_offset(leg)+_project_ground(_direction*(0.75-0.5*t)*stride_pixels())
			local = (_swing_from[leg] as Vector2).lerp(landing,smooth)-_position_plane
			lift = sin(PI*t) * 7.0 * _unit
			_boot_facing[leg] = _facing
			if _intro < 1.0:
				local = _standing_foot(leg).lerp(local, _intro)
				lift *= _intro
		_goal_feet[leg] = local
		_supports[leg] = planted
		_lift[leg] = lift
		_place_leg(leg, local, lift, _boot_facing[leg])
	_place_upper_body(phase)

func _project_ground(point: Vector2) -> Vector2: return Vector2(point.x, point.y*GROUND_Y)
func _project(point: Vector3) -> Vector2: return Vector2(point.x, point.z*GROUND_Y - point.y*HEIGHT_Y)

func _place_leg(leg: int, ground: Vector2, lift: float, boot_facing: float) -> void:
	var boot := _parts["boot_%d" % leg] as Polygon2D
	var spec: Dictionary = _definition.parts["boot_%d" % leg]
	var sole_height := float(spec.sole_height) * _unit
	var across := Vector2(-_direction.y,_direction.x)*(-4.0 if leg==0 else 4.0)*_unit
	var hip := Vector3(across.x, HIP_HEIGHT*_unit+_body_height_delta, across.y)
	var ankle := Vector3(ground.x, sole_height+lift, ground.y/GROUND_Y)
	var vector := ankle - hip
	var distance := vector.length()
	var length := LEG_LENGTH*_unit
	# Real 3D bone lengths remain constant; perspective may only foreshorten
	# each limb. Never stretch the head/torso or use a moving sole as body pivot.
	if distance > length*2.0-0.0001:
		_ik_clamps += 1
		# This is a diagnosed invalid route/turn, not permission to silently
		# elongate the shin. Keep the locked foot and expose the failed reach.
		set_meta("unreachable_support", true)
	var forward := Vector3(_direction.x,0.0,_direction.y)
	var axis := vector.normalized()
	var bend := forward - axis*forward.dot(axis)
	if bend.length_squared() < 0.0001: bend = Vector3.FORWARD
	var knee := hip + vector*0.5 + bend.normalized()*sqrt(maxf(0.0,length*length-distance*distance*0.25))
	_knees[leg] = knee
	_ankles[leg] = ankle
	_place_bone("thigh_%d"%leg, _project(hip), _project(knee))
	_place_bone("shin_%d"%leg, _project(knee), _project(ankle))
	boot.position = _project(ankle)
	boot.rotation = 0.0
	boot.scale = Vector2(boot_facing, 1.0)
	_boot_origins[leg] = _position_plane + boot.position

func _place_upper_body(phase: float, amplitude := 1.0) -> void:
	for key in ["body","head","body_back","head_back"]:
		if not _parts.has(key): continue
		var part := _parts[key] as Polygon2D
		part.visible = _back if key.ends_with("_back") else not _back
		var raw: Array = _definition.parts[key].position
		part.position = Vector2(float(raw[0]),float(raw[1]))*_unit+Vector2(0,-_body_height_delta*HEIGHT_Y)
		part.scale = Vector2(_facing,1.0)
		var lean:=sin(TAU*phase)*0.006*_intro*amplitude
		part.rotation = -lean*0.5 if key.begins_with("head") else lean
	if _back and not _parts.has("body_back"):
		(_parts.body as Polygon2D).visible = true
		(_parts.head as Polygon2D).visible = true
	for leg in range(2):
		var shoulder := Vector2((-14.0 if leg == 0 else 14.0)*_facing,-69.0)*_unit+Vector2(0,-_body_height_delta*HEIGHT_Y)
		var opposite := -cos(TAU*phase)*(1.0 if leg==0 else -1.0)*_intro*amplitude
		var elbow := shoulder + Vector2(_direction.x*opposite*4.0,13.5)*_unit
		var hand := shoulder + Vector2(_direction.x*opposite*8.0,28.0)*_unit
		_place_bone("upper_%d"%leg,shoulder,elbow)
		_place_bone("fore_%d"%leg,elbow,hand)

func _place_bone(key: String, from: Vector2, to: Vector2) -> void:
	var part := _parts[key] as Polygon2D
	var rest := float(_definition.parts[key].length)*_unit
	part.position = from
	part.rotation = (to-from).angle() - PI*0.5
	part.scale = Vector2(_facing if key.begins_with("fore") or key.begins_with("upper") else 1.0,(to-from).length()/rest)

func _create_part(key: String, spec: Dictionary) -> void:
	var path := String(spec.texture)
	if not _textures.has(path): _textures[path] = load(path) as Texture2D
	var texture := _textures[path] as Texture2D
	var canvas: Array = spec.canvas
	var imported := texture.get_size()/Vector2(float(canvas[0]),float(canvas[1]))
	var raw_pivot: Array = spec.pivot
	var pivot := Vector2(float(raw_pivot[0]),float(raw_pivot[1]))
	var direction := Vector2.DOWN
	var source_length := 1.0
	var width_scale := 1.0
	if spec.has("axis_end"):
		var endpoint: Array = spec.axis_end
		var delta := Vector2(float(endpoint[0]),float(endpoint[1]))-pivot
		direction = delta.normalized()
		source_length = delta.length()
		var minimum := INF
		var maximum := -INF
		var transverse := Vector2(direction.y,-direction.x)
		for value in spec.contour:
			var point := Vector2(float(value[0]),float(value[1]))-pivot
			minimum = minf(minimum,point.dot(transverse)); maximum = maxf(maximum,point.dot(transverse))
		width_scale = float(spec.width)/maxf(1.0,maximum-minimum)
	var shape := PackedVector2Array()
	var uv := PackedVector2Array()
	for value in spec.contour:
		var point := Vector2(float(value[0]),float(value[1]))
		var relative := point-pivot
		if spec.has("axis_end"):
			var transverse := Vector2(direction.y,-direction.x)
			relative = Vector2(relative.dot(transverse)*width_scale,relative.dot(direction)*float(spec.length)/source_length)
		else: relative *= float(spec.uniform_scale)
		shape.append(relative*_unit)
		uv.append(point*imported)
	var part := Polygon2D.new()
	part.name = "Rig_"+key
	part.polygon = shape
	part.uv = uv
	part.texture = texture
	part.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	part.antialiased = true
	part.z_index = 0
	part.set_meta("paint_layer",int(spec.layer))
	add_child(part)
	_parts[key] = part

func debug_sample() -> Dictionary:
	var plane := get_parent().get_parent() as CanvasItem
	var parent_to_global := plane.get_global_transform()
	var feet: Array[Dictionary] = []
	for leg in range(2):
		var boot := _parts["boot_%d"%leg] as Polygon2D
		var vertices := PackedVector2Array()
		for point in boot.polygon: vertices.append(boot.get_global_transform()*point)
		feet.append({"leg":leg,"support":_supports[leg],"lift":_lift[leg],
			"contact_parent":_plants[leg],"contact_global":parent_to_global*(_plants[leg] as Vector2),
			"ankle_parent":_boot_origins[leg],"boot_global_vertices":vertices,
			"boot_transform":boot.get_global_transform(),"knee":_knees[leg],"ankle_3d":_ankles[leg]})
	return {"phase":fposmod(_distance/stride_pixels(),1.0),"walking":_walking,"settling":_settling,
		"root_parent":_position_plane,"root_global":parent_to_global*_position_plane,"parent_transform":parent_to_global,
		"feet":feet,"head_scale":(_parts.head as Polygon2D).scale,"body_scale":(_parts.body as Polygon2D).scale,
		"ik_clamps":_ik_clamps,"stride":stride_pixels(),"cadence":CADENCE,"back_view":_back,
		"body_height_delta":_body_height_delta}
