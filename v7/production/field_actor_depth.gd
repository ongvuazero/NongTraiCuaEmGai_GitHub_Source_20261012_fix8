extends Node2D
class_name FieldActorDepth

signal action_contact(job: Dictionary)
signal walk_step()

const Assets = preload("res://scripts/ui_asset_registry.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const PRODUCTION_ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY/ANIMATION/FARMER"
const ANIMATION_LAYOUT := "res://assets/player_feedback_v2/farmer/animation_layout.json"
const FRAME_SEQUENCE := [1, 2, 3, 5, 6, 8, 9, 10]
const ANIMATION_FPS := {
	"idle": 6.0,
	"walk": 12.0,
	"hoe": 12.0,
	"plant": 12.0,
	"water": 14.0,
	"fertilize": 12.0,
	"harvest": 14.0,
}

const ACTION_ANIMATIONS := {
	"till": "hoe",
	"seed": "plant",
	"water": "water",
	"fertilize": "fertilize",
	"harvest": "harvest",
}

var sprite: AnimatedSprite2D
var target_height := 116.0
var last_action := ""
var movement_tween: Tween
var movement_generation := 0
var _source_layout: Dictionary = {}
var _frame_cache: Dictionary = {}
var _source_animation := "idle"
var _presentation_queue: Array[Dictionary] = []
var _active_job: Dictionary = {}
var _contact_sent := false
var _walking := false
var _walk_distance := 0.0
var _walk_previous := Vector2.ZERO
var _walk_step_index := 0
var _field_corridor_y := 0.0
var _field_surface: CanvasItem
var _crop_surface: CanvasItem
var _navigation_signature: Array = []
var _navigation_ready := false
var _navigation_obstacles: Array[PackedVector2Array] = []
var _navigation_nodes: Array[Vector2] = []
var _navigation_edges: Array[Array] = []
var _physical_obstacles: Array[PackedVector2Array] = []
var _direction_obstacles: Dictionary = {}
var _direction_obstacle_bounds: Dictionary = {}
var _circle_obstacle_bounds: Array[Rect2] = []
var _navigation_radius := FIELD_BOOT_CLEARANCE
var _presentation_elapsed := 0.0
var _facing_right := true
var walk_rig: Node2D
var _travel_path: Array[Vector2] = []
var _travel_direction := Vector2.ZERO
var _settle_continuation := ""
const WALK_SPEED := 192.0
const WALK_STRIDE := 96.0
const FIELD_BOOT_CLEARANCE := 8.0
const GLIDE_BOOT_CLEARANCE := 16.0
const CONTACT_FRAMES := {"till": 3, "seed": 3, "water": 3, "fertilize": 3, "harvest": 3}


func configure(foot_position: Vector2, target_height_value := 116.0) -> void:
	position = foot_position
	target_height = target_height_value
	sprite = AnimatedSprite2D.new()
	sprite.name = "CanonicalFarmerAnimatedSprite"
	sprite.centered = false
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	add_child(sprite)
	_configure_walk_rig()
	_play_idle()
	set_meta("foot_anchor", foot_position)
	set_meta("animated_runtime", true)


func play_action(gameplay_action: String) -> bool:
	if not ACTION_ANIMATIONS.has(gameplay_action):
		return false
	last_action = gameplay_action
	_play_animation(String(ACTION_ANIMATIONS[gameplay_action]), false)
	return true


func move_then_play(foot_position: Vector2, gameplay_action: String, duration := 0.22) -> void:
	# Kept for existing QA callers. Travel now follows real distance, not a
	# fixed 0.22-second slide. Gameplay is never called from this actor.
	enqueue_action(foot_position, gameplay_action, {"legacy_duration_hint": duration})


func enqueue_action(foot_position: Vector2, gameplay_action: String, payload := {}, waypoints: Array[Vector2] = []) -> void:
	if not ACTION_ANIMATIONS.has(gameplay_action): return
	var job: Dictionary = payload.duplicate(true)
	job["target"] = foot_position
	job["action"] = gameplay_action
	job["waypoints"] = waypoints.duplicate()
	# Authority and per-plot feedback are already committed. The farmer follows
	# the newest field intent immediately, without finishing obsolete journeys.
	# Replanning starts at the actual feet position; it never teleports or replays
	# a transaction. Standalone/legacy callers still retain their FIFO contract.
	if bool(job.get("latest_target", job.get("coalesce_pending", false))):
		var preserve_walk_phase := _walking
		_sync_rig_travel(0.0)
		movement_generation += 1
		if movement_tween != null and movement_tween.is_valid(): movement_tween.kill()
		_active_job = {}
		_presentation_queue.clear()
		_presentation_queue.append(job)
		set_meta("presentation_queue_size", 0)
		set_meta("retarget_count", int(get_meta("retarget_count", 0)) + 1)
		_start_next_job(preserve_walk_phase)
		return
	_presentation_queue.append(job)
	set_meta("presentation_queue_size", _presentation_queue.size())
	if _active_job.is_empty(): _start_next_job()


func set_field_corridor(y: float) -> void:
	# Compatibility only. A requested future corridor is not movement state.
	_field_corridor_y = position.y
	set_meta("legacy_requested_corridor", y)


func set_field_navigation(surface: CanvasItem, crop_surface: CanvasItem = null) -> void:
	# Surface is the REAL rendered bed-world, not the encompassing input Control.
	_field_surface = surface
	_crop_surface = crop_surface if crop_surface != null else surface
	_navigation_ready = false


func field_point(point: Vector2, plot_id := 0) -> Vector2:
	if not is_instance_valid(_field_surface): return point
	var source := _rendered_bed_surface(plot_id) if plot_id > 0 else _field_surface
	return _actor_parent_transform().affine_inverse() * (source.get_global_transform() * point)


func _actor_parent_transform() -> Transform2D:
	var parent := get_parent() as CanvasItem
	return parent.get_global_transform() if parent != null else Transform2D.IDENTITY


func _rendered_bed_surface(plot_id: int) -> CanvasItem:
	var bed := _field_surface.get_node_or_null("Bed_%02d" % plot_id) as CanvasItem
	return bed if bed != null else _field_surface


func field_route(from: Vector2, target: Vector2) -> Array[Vector2]:
	_prepare_field_navigation()
	if from.distance_to(target) <= 0.5: return [target]
	if _endpoint_segment_allowed(from, target) and _endpoint_segment_allowed(target, from) and _segment_clear(from, target): return [target]
	var nodes: Array[Vector2] = _navigation_nodes.duplicate()
	var edges: Array[Array] = _navigation_edges.duplicate(true)
	# Work gutters are intentionally narrower than an all-heading turn circle.
	# Enter/leave them vertically; turn only after the COMPLETE boot envelope
	# has reached open grass. Ports come from actual rendered obstacles.
	for endpoint in [from, target]:
		if _circle_point_clear(endpoint): continue
		var port: Variant = _vertical_gutter_port(endpoint)
		if port == null: continue
		var port_index := nodes.size()
		nodes.append(port)
		edges.append([])
		for index in range(port_index):
			if _endpoint_segment_allowed(nodes[index], nodes[port_index]) and _segment_clear(nodes[port_index], nodes[index]):
				var distance := _route_distance(nodes[port_index] - nodes[index])
				edges[port_index].append([index, distance])
				edges[index].append([port_index, distance])
	var source_index := nodes.size()
	var target_index := source_index + 1
	nodes.append(from)
	nodes.append(target)
	edges.append([])
	edges.append([])
	for endpoint in [source_index, target_index]:
		for index in range(source_index):
			if _endpoint_segment_allowed(nodes[endpoint], nodes[index]) and _endpoint_segment_allowed(nodes[index], nodes[endpoint]) and _segment_clear(nodes[endpoint], nodes[index]):
				var distance := _route_distance(nodes[endpoint] - nodes[index])
				edges[endpoint].append([index, distance])
				edges[index].append([endpoint, distance])
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for index in range(nodes.size()):
		distances.append(INF)
		previous.append(-1)
		visited.append(false)
	distances[source_index] = 0.0
	for iteration in range(nodes.size()):
		var best := -1
		for index in range(nodes.size()):
			if not visited[index] and (best == -1 or distances[index] < distances[best]): best = index
		if best == -1 or is_inf(distances[best]): break
		if best == target_index: break
		visited[best] = true
		for edge in edges[best]:
			var next := int(edge[0])
			var candidate := distances[best] + float(edge[1])
			if candidate < distances[next]:
				distances[next] = candidate
				previous[next] = best
	var result: Array[Vector2] = []
	if previous[target_index] == -1: return result
	var cursor := target_index
	while cursor != source_index:
		result.push_front(nodes[cursor])
		cursor = previous[cursor]
	return result


func _prepare_field_navigation() -> void:
	var parent_inverse := _actor_parent_transform().affine_inverse()
	var signature: Array = []
	var bed_transforms: Array[Transform2D] = []
	for plot_id in range(1, 13):
		var transform := parent_inverse * _rendered_bed_surface(plot_id).get_global_transform() if is_instance_valid(_field_surface) else Transform2D.IDENTITY
		bed_transforms.append(transform)
		signature.append(transform)
	var crop_transform := parent_inverse * _crop_surface.get_global_transform() if is_instance_valid(_crop_surface) else Transform2D.IDENTITY
	signature.append(crop_transform)
	if _navigation_ready and signature == _navigation_signature: return
	_navigation_signature = signature
	_navigation_ready = true
	_navigation_obstacles.clear()
	_physical_obstacles.clear()
	_direction_obstacles.clear()
	_direction_obstacle_bounds.clear()
	_circle_obstacle_bounds.clear()
	_navigation_radius = GLIDE_BOOT_CLEARANCE if _fast_glide() else FIELD_BOOT_CLEARANCE
	if walk_rig != null and walk_rig.has_method("navigation_footprint"):
		_navigation_radius = maxf(_navigation_radius, float(walk_rig.call("navigation_radius")) + 1.0)
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1,1), Vector2(1,-1), Vector2(-1,1), Vector2(-1,-1)]:
			var footprint: PackedVector2Array = walk_rig.call("navigation_footprint", direction)
			for point in footprint: _navigation_radius = maxf(_navigation_radius, point.length() + 1.0)
	_navigation_nodes.clear()
	_navigation_edges.clear()
	for plot_id in range(1, 13):
		var bed := PixelMap.visual_plot_rect(plot_id)
		var crop_anchor := PixelMap.visual_crop_anchor(plot_id)
		# The renderer caps a mature crop at 72% of bed width / 88% height,
		# anchored at its visible-pixel bottom center. Reserve this full envelope
		# even for an empty plot, so walking soles never cut across crop artwork.
		var crop_rect := Rect2(crop_anchor - Vector2(bed.size.x * 0.36, bed.size.y * 0.88), Vector2(bed.size.x * 0.72, bed.size.y * 0.88))
		# Stage-in presentation may start5px below its settled planting root.
		crop_rect.size.y += 5.0
		var crop_polygon := PackedVector2Array([crop_rect.position, Vector2(crop_rect.end.x, crop_rect.position.y), crop_rect.end, Vector2(crop_rect.position.x, crop_rect.end.y)])
		_add_navigation_obstacle(PixelMap.visual_interaction_polygon(plot_id), bed_transforms[plot_id - 1])
		_add_navigation_obstacle(crop_polygon, crop_transform)
	for index in range(_navigation_nodes.size()): _navigation_edges.append([])
	for left in range(_navigation_nodes.size()):
		for right in range(left + 1, _navigation_nodes.size()):
			if _circle_segment_clear(_navigation_nodes[left], _navigation_nodes[right]):
				var distance := _route_distance(_navigation_nodes[left] - _navigation_nodes[right])
				_navigation_edges[left].append([right, distance])
				_navigation_edges[right].append([left, distance])
	if walk_rig != null:
		# Rows intentionally shift their beds. Follow those real gutter centers
		# with shallow bends instead of forcing one vertical x through all rows.
		var first_gutter_node := _navigation_nodes.size()
		for plot_id in range(1, 13):
			var anchor := field_point(authored_work_anchor(plot_id), plot_id)
			_navigation_nodes.append(anchor)
			_navigation_edges.append([])
			var port: Variant = _vertical_gutter_port(anchor)
			if port != null:
				_navigation_nodes.append(port)
				_navigation_edges.append([])
		for right in range(first_gutter_node, _navigation_nodes.size()):
			for left in range(right):
				var from: Vector2 = _navigation_nodes[left]
				var target: Vector2 = _navigation_nodes[right]
				if _endpoint_segment_allowed(from, target) and _endpoint_segment_allowed(target, from) and _segment_clear(from, target):
					var distance := _route_distance(target - from)
					_navigation_edges[left].append([right, distance])
					_navigation_edges[right].append([left, distance])


func _add_navigation_obstacle(polygon: PackedVector2Array, transform: Transform2D) -> void:
	# These are the actual current soil polygons, not inset old rectangles.
	# Inflate by a boot radius so the soles, not only a single point, stay on
	# grass. Routing vertices receive 1px extra tolerance outside obstacles.
	# Inflate AFTER conversion into actor-parent space: an independent rendered
	# bed scale must not shrink the actor's boot-clearance radius.
	var actor_polygon := PackedVector2Array()
	for point in polygon: actor_polygon.append(transform * point)
	_physical_obstacles.append(actor_polygon)
	for expanded in Geometry2D.offset_polygon(actor_polygon, _navigation_radius, Geometry2D.JOIN_MITER):
		_navigation_obstacles.append(expanded)
		_circle_obstacle_bounds.append(_polygon_bounds(expanded))
	for expanded in Geometry2D.offset_polygon(actor_polygon, _navigation_radius + 1.0, Geometry2D.JOIN_MITER):
		for point in expanded: _navigation_nodes.append(point)


func _segment_clear(from: Vector2, target: Vector2) -> bool:
	var obstacles := _navigation_obstacles
	var bounds := _circle_obstacle_bounds
	if walk_rig != null and walk_rig.has_method("navigation_footprint"):
		var direction := target - from
		# Exact direction key, not rounded bins that can underbound a diagonal.
		var key := Vector2.ZERO if direction.length_squared() < 0.00001 else direction.normalized()
		if not _direction_obstacles.has(key):
			# Mid-segment clicks produce new exact headings indefinitely. Bound
			# their convex-cache memory without weakening the geometric envelope.
			if _direction_obstacles.size() >= 512:
				_direction_obstacles.clear()
				_direction_obstacle_bounds.clear()
			var footprint: PackedVector2Array = walk_rig.call("navigation_footprint", direction)
			var expanded: Array[PackedVector2Array] = []
			for physical in _physical_obstacles:
				var sums := PackedVector2Array()
				for point in physical:
					for foot in footprint: sums.append(point - foot)
				var hull := Geometry2D.convex_hull(sums)
				for padded in Geometry2D.offset_polygon(hull, 0.75, Geometry2D.JOIN_MITER): expanded.append(padded)
			_direction_obstacles[key] = expanded
			var expanded_bounds: Array[Rect2] = []
			for polygon in expanded: expanded_bounds.append(_polygon_bounds(polygon))
			_direction_obstacle_bounds[key] = expanded_bounds
		obstacles = _direction_obstacles[key]
		bounds = _direction_obstacle_bounds[key]
	return _polygons_segment_clear(from, target, obstacles, bounds)


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: result = result.expand(point)
	return result


func _polygons_segment_clear(from: Vector2, target: Vector2, obstacles: Array[PackedVector2Array], bounds: Array[Rect2]) -> bool:
	# Cheap conservative rejection only; every possible overlap still gets
	# the exact point/edge test. Vertical and zero-length segments keep area.
	var segment_bounds := Rect2(from, Vector2.ZERO).expand(target).grow(0.01)
	for obstacle in range(obstacles.size()):
		if not segment_bounds.intersects(bounds[obstacle]): continue
		var polygon := obstacles[obstacle]
		if Geometry2D.is_point_in_polygon(from, polygon) or Geometry2D.is_point_in_polygon(target, polygon): return false
		for index in range(polygon.size()):
			if Geometry2D.segment_intersects_segment(from, target, polygon[index], polygon[(index + 1) % polygon.size()]) != null: return false
	return true


func _circle_point_clear(point: Vector2) -> bool:
	for index in range(_navigation_obstacles.size()):
		if _circle_obstacle_bounds[index].has_point(point) and Geometry2D.is_point_in_polygon(point, _navigation_obstacles[index]): return false
	return true


func _circle_segment_clear(from: Vector2, target: Vector2) -> bool:
	return _polygons_segment_clear(from, target, _navigation_obstacles, _circle_obstacle_bounds)


func _endpoint_segment_allowed(endpoint: Vector2, other: Vector2) -> bool:
	var delta := other - endpoint
	return _circle_point_clear(endpoint) or absf(delta.x) <= absf(delta.y) / 0.6 * tan(deg_to_rad(15.0)) + 0.001


static func authored_work_anchor(plot_id: int) -> Vector2:
	var bed := PixelMap.visual_plot_rect(plot_id)
	var x := bed.position.x - 8.0
	if (plot_id - 1) % 4 > 0:
		var previous := PixelMap.visual_plot_rect(plot_id - 1)
		x = (previous.position.x + previous.size.x * 0.90 + bed.position.x + bed.size.x * 0.10) * 0.5
	return Vector2(x, PixelMap.visual_crop_anchor(plot_id).y - 12.0)


func _vertical_gutter_port(endpoint: Vector2) -> Variant:
	var top := endpoint.y
	for polygon in _physical_obstacles:
		for point in polygon: top = minf(top, point.y - _navigation_radius - 3.0)
	var probe := endpoint
	while probe.y >= top:
		probe.y -= 2.0
		if not _segment_clear(endpoint, probe): return null
		if _circle_point_clear(probe): return probe
	return null


func _route_distance(direction: Vector2) -> float:
	return float(walk_rig.call("physical_distance", direction)) if walk_rig != null else direction.length()


func _start_next_job(preserve_walk_phase := false) -> void:
	if _presentation_queue.is_empty():
		_active_job = {}
		_play_idle()
		return
	_active_job = _presentation_queue.pop_front()
	set_meta("presentation_queue_size", _presentation_queue.size())
	_contact_sent = false
	_presentation_elapsed = 0.0
	var path: Array = _active_job["waypoints"].duplicate()
	var target: Vector2 = _active_job["target"]
	if _active_job.has("field_corridor_y") or bool(_active_job.get("field_navigation", false)):
		path = field_route(position, target)
		if path.is_empty():
			# Never replace a missing safe route with a straight line through soil.
			set_meta("last_presentation_outcome", "no_safe_route_idle")
			cancel_presentations()
			return
	if path.is_empty() or not (path.back() as Vector2).is_equal_approx(target): path.append(target)
	var distance := 0.0
	var travel_seconds := 0.0
	var previous := position
	var previous_direction := Vector2.ZERO
	for point in path:
		distance += previous.distance_to(point)
		var direction := (point as Vector2) - previous
		travel_seconds += _travel_duration(direction)
		if walk_rig != null and direction.length_squared() > 0.0001:
			var physical := Vector2(direction.x, direction.y / 0.6).normalized()
			if previous_direction != Vector2.ZERO and previous_direction.dot(physical) < cos(deg_to_rad(15.0)):
				travel_seconds += float(walk_rig.call("settle_duration"))
			elif previous_direction == Vector2.ZERO and _walking and bool(walk_rig.call("needs_turn", direction)):
				travel_seconds += float(walk_rig.call("settle_duration"))
			previous_direction = physical
		previous = point
	if walk_rig != null and distance > 0.5: travel_seconds += float(walk_rig.call("settle_duration"))
	set_meta("movement_path", path.duplicate())
	set_meta("movement_path_distance", distance)
	# The newest intent reaches its real safe work anchor. A physical travel
	# time is not an obsolete backlog; there is never a queue of old field jobs.
	var action_name := String(ACTION_ANIMATIONS[_active_job["action"]])
	var action_frames := _production_frames(action_name)
	set_meta("expected_presentation_seconds", travel_seconds + action_frames.get_frame_count(action_name) / action_frames.get_animation_speed(action_name))
	_travel_path.clear()
	for point in path:
		if (point as Vector2).distance_to(position) > 0.5: _travel_path.append(point)
	if walk_rig != null:
		sprite.stop()
		sprite.visible = false
		if _settle_continuation != "":
			# Inputs during a stationary foot-gather only replace the intent.
			# Do not restart a half-finished gather or a discarded old route.
			_settle_continuation = "travel" if distance > 0.5 else "action"
			return
		if distance <= 0.5:
			_arrive_for_action()
			return
		set_meta("walk_speed", walk_rig.call("physical_speed"))
		set_meta("walk_stride", walk_rig.call("stride_pixels"))
		set_meta("walk_cycles_per_second", walk_rig.call("cadence_cycles_per_second"))
		_start_travel_segment(preserve_walk_phase)
		return
	if distance <= 0.5:
		_arrive_for_action()
		return
	_walking = true
	_walk_previous = position
	if not preserve_walk_phase:
		_walk_distance = 0.0
		_walk_step_index = 0
	if _fast_glide():
		# Intentional user-selected fast glide, not a pretend walking cycle.
		# A single idle bitmap/fixed pivot moves without footstep sound, body
		# warp, a delayed old journey, or a synthetic step cadence.
		_play_idle()
		sprite.pause()
		sprite.frame = 0
	elif _layout().get("animations", {}).has("walk"):
		_play_animation("walk", true)
		sprite.pause()
		# A retarget preserves traveled-distance phase in this same frame; do
		# not flash pose0 between every rapid input and cause a foot jitter.
		var count := sprite.sprite_frames.get_frame_count(&"walk")
		sprite.frame = int(floor(_walk_distance / _walk_stride() * count)) % maxi(count, 1)
	else:
		# Missing authored walk must not turn idle art into a sliding walk.
		if bool(_active_job.get("latest_target", _active_job.get("coalesce_pending", false))):
			set_meta("last_presentation_outcome", "missing_walk_idle")
			cancel_presentations()
			return
		# Unchanged legacy standalone contract, never used by the field screen.
		_play_idle()
	set_meta("movement_phase", "glide" if _fast_glide() else "walk")
	set_meta("walk_speed", _walk_speed())
	set_meta("walk_stride", _walk_stride())
	set_meta("walk_cycles_per_second", 0.0 if _fast_glide() else _walk_speed() / _walk_stride())
	set_meta("travel_policy", "intentional_fast_glide" if _fast_glide() else "walk")
	movement_generation += 1
	var generation := movement_generation
	movement_tween = create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)
	previous = position
	for point in path:
		var segment := previous.distance_to(point)
		if segment > 0.5:
			var direction := (point as Vector2) - previous
			movement_tween.tween_callback(_face_travel.bind(direction))
			movement_tween.tween_property(self, "position", point, segment / _walk_speed())
		previous = point
	movement_tween.finished.connect(func() -> void:
		if generation == movement_generation: _arrive_for_action()
	)


func _configure_walk_rig() -> void:
	var definition: Dictionary = _layout().get("animations", {}).get("walk", {})
	if String(definition.get("type", "")) != "skeletal_2d": return
	var script := load(String(definition.get("script", "res://scripts/ui/native_farmer_walk_rig.gd"))) as Script
	if script == null: return
	var candidate := Node2D.new()
	candidate.set_script(script)
	candidate.name = "NativeFarmerWalkRig"
	add_child(candidate)
	if not bool(candidate.call("configure", target_height * 0.88)):
		candidate.queue_free()
		return
	walk_rig = candidate
	walk_rig.connect("footstep", func(_leg: int) -> void: walk_step.emit())
	_navigation_ready = false
	set_meta("walk_source", "skeletal_2d")


func _travel_duration(direction: Vector2) -> float:
	if walk_rig != null: return float(walk_rig.call("travel_duration", direction))
	return direction.length() / _walk_speed()


func _sync_rig_travel(delta: float) -> void:
	if walk_rig == null or not _walking: return
	var direction := position - _walk_previous
	_walk_distance += float(walk_rig.call("physical_distance", direction))
	walk_rig.call("advance_walk", position, _travel_direction, delta)
	_walk_previous = position
	_field_corridor_y = position.y
	set_meta("movement_distance", _walk_distance)


func _begin_rig_settle(continuation: String, next_direction := Vector2.ZERO) -> void:
	_walking = false
	_settle_continuation = continuation
	walk_rig.call("end_walk", false, next_direction)
	set_meta("movement_phase", "settle")
	sprite.stop()
	sprite.visible = false


func _start_travel_segment(preserve_phase := true) -> void:
	while not _travel_path.is_empty() and _travel_path.front().distance_to(position) <= 0.5:
		_travel_path.pop_front()
	if _travel_path.is_empty():
		_arrive_for_action()
		return
	var target: Vector2 = _travel_path.front()
	var direction := target - position
	if _walking and bool(walk_rig.call("needs_turn", direction)):
		_sync_rig_travel(0.0)
		_begin_rig_settle("travel", direction)
		return
	_travel_direction = direction
	_walk_previous = position
	walk_rig.call("begin_walk", position, direction, preserve_phase and _walking)
	_walking = true
	set_meta("movement_phase", "walk")
	movement_generation += 1
	var generation := movement_generation
	movement_tween = create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)
	movement_tween.tween_property(self, "position", target, _travel_duration(direction))
	movement_tween.finished.connect(func() -> void:
		if generation != movement_generation: return
		_sync_rig_travel(0.0)
		_travel_path.pop_front()
		_start_travel_segment(true)
	)


func _face_travel(direction: Vector2) -> void:
	if _walking and not _fast_glide() and direction.length_squared() > 0.0001:
		var name := _walk_animation_for_direction(direction)
		if name != String(sprite.animation):
			_play_animation(name, true)
			sprite.pause()
			var count := sprite.sprite_frames.get_frame_count(name)
			sprite.frame = int(floor(_walk_distance / _walk_stride() * count)) % maxi(count, 1)
	if absf(direction.x) > 0.01:
		_facing_right = direction.x > 0.0
		_apply_source_facing()


func _walk_animation_for_direction(direction: Vector2) -> String:
	var cardinal := "down" if direction.y >= 0.0 else "up"
	if absf(direction.x) >= absf(direction.y): cardinal = "right" if direction.x >= 0.0 else "left"
	var candidate := "walk_" + cardinal
	var definitions: Dictionary = _layout().get("animations", {})
	var resolved := candidate if definitions.has(candidate) else "walk"
	set_meta("walk_direction", cardinal)
	set_meta("walk_directional_source_present", definitions.has(candidate))
	return resolved


func _walk_stride() -> float:
	if walk_rig != null: return float(walk_rig.call("stride_pixels"))
	var definition: Dictionary = _layout().get("animations", {}).get("walk", {})
	if definition.has("stride_source_pixels"):
		# Calibrated full-cycle planted-boot displacement, not guessed cadence.
		return maxf(1.0, float(definition["stride_source_pixels"]) * target_height * 0.88 / maxf(1.0, float(definition.get("reference_body_height", target_height))))
	return maxf(1.0, float(definition.get("stride_pixels", WALK_STRIDE)))


func _walk_speed() -> float:
	if _fast_glide(): return maxf(1.0, float(_layout().get("animations", {}).get("walk", {}).get("speed_pixels_per_second", 520.0)))
	if walk_rig != null: return float(walk_rig.call("physical_speed"))
	var definition: Dictionary = _layout().get("animations", {}).get("walk", {})
	var cadence := clampf(float(definition.get("cadence_cycles_per_second", 2.0)), 1.4, 2.5)
	return clampf(float(definition.get("speed_pixels_per_second", _walk_stride() * cadence)), _walk_stride() * 1.4, _walk_stride() * 2.5)


func _fast_glide() -> bool:
	return String(_layout().get("animations", {}).get("walk", {}).get("type", "")) == "fast_glide"


func _apply_source_facing() -> void:
	var source_facing := String(_layout().get("animations", {}).get(_source_animation, {}).get("source_facing", "right"))
	if source_facing in ["up", "down", "front", "back"]:
		sprite.scale.x = absf(sprite.scale.x)
		return
	var source_left := source_facing == "left"
	var facing := 1.0 if _facing_right != source_left else -1.0
	sprite.scale.x = absf(sprite.scale.x) * facing


func _arrive_for_action() -> void:
	if walk_rig != null and _walking:
		_sync_rig_travel(0.0)
		_begin_rig_settle("action")
		return
	_walking = false
	if _active_job.is_empty():
		_play_idle()
		return
	if walk_rig != null: walk_rig.visible = false
	sprite.visible = true
	set_meta("foot_anchor", position)
	set_meta("movement_phase", "action")
	if _active_job.has("soil_contact"):
		var contact: Vector2 = _active_job.get("actor_soil_contact", _active_job["soil_contact"])
		_face_travel(contact - position)
	set_meta("last_presentation_outcome", "at_target")
	play_action(String(_active_job["action"]))


func cancel_presentations() -> void:
	_sync_rig_travel(0.0)
	var was_walking := _walking
	movement_generation += 1
	if movement_tween != null and movement_tween.is_valid(): movement_tween.kill()
	_presentation_queue.clear()
	_active_job = {}
	_travel_path.clear()
	_walking = false
	_contact_sent = false
	_field_corridor_y = position.y
	set_meta("foot_anchor", position)
	set_meta("presentation_queue_size", 0)
	set_meta("movement_phase", "idle")
	if walk_rig != null and (was_walking or _settle_continuation != ""):
		if _settle_continuation == "": _begin_rig_settle("idle")
		else: _settle_continuation = "idle"
	else: _play_idle()


func _process(delta: float) -> void:
	if not _active_job.is_empty() and bool(_active_job.get("latest_target", _active_job.get("coalesce_pending", false))):
		_presentation_elapsed += delta
		set_meta("presentation_elapsed_seconds", _presentation_elapsed)
	if walk_rig != null:
		if _settle_continuation != "":
			walk_rig.call("advance_settle", delta)
			if bool(walk_rig.call("settle_complete")):
				var continuation := _settle_continuation
				_settle_continuation = ""
				if continuation == "travel" and not _active_job.is_empty(): _start_travel_segment(false)
				elif continuation == "action" and not _active_job.is_empty(): _arrive_for_action()
				else: _play_idle()
		elif _walking: _sync_rig_travel(delta)
		return
	if not _walking or sprite == null: return
	var traveled := position.distance_to(_walk_previous)
	var direction := position - _walk_previous
	_walk_distance += traveled
	_walk_previous = position
	_field_corridor_y = position.y
	_face_travel(direction)
	if _fast_glide():
		set_meta("movement_distance", _walk_distance)
		return
	if String(sprite.animation).begins_with("walk"):
		var count := sprite.sprite_frames.get_frame_count(sprite.animation)
		sprite.frame = int(floor(_walk_distance / _walk_stride() * count)) % maxi(count, 1)
	var step_index := int(floor(_walk_distance / (_walk_stride() * 0.5)))
	if step_index > _walk_step_index:
		_walk_step_index = step_index
		walk_step.emit()
	set_meta("movement_distance", _walk_distance)


func _on_frame_changed() -> void:
	_sync_authored_frame_pivot()
	if _active_job.is_empty() or String(get_meta("movement_phase", "")) != "action" or _walking or _contact_sent: return
	var action := String(_active_job["action"])
	if sprite.animation == StringName(ACTION_ANIMATIONS.get(action, "")) and sprite.frame >= int(CONTACT_FRAMES.get(action, 3)):
		_contact_sent = true
		set_meta("last_contact_plot", int(_active_job.get("plot_id", 0)))
		action_contact.emit(_active_job.duplicate(true))


func is_action_playing() -> bool:
	return sprite != null and sprite.is_playing() and sprite.animation != &"idle"


func current_animation_name() -> String:
	return String(sprite.animation) if sprite != null else ""


func _play_idle() -> void:
	if walk_rig != null: walk_rig.visible = false
	sprite.visible = true
	_play_animation("idle", true)


func _play_animation(animation_name: String, looping: bool) -> void:
	_source_animation = animation_name
	var frames := _production_frames(animation_name)
	frames.set_animation_loop(animation_name, looping)
	sprite.sprite_frames = frames
	sprite.animation = animation_name
	var first_frame := frames.get_frame_texture(animation_name, 0)
	if first_frame != null:
		var definition: Dictionary = _layout().get("animations", {}).get(animation_name, {})
		var body_height := float(definition.get("reference_body_height", first_frame.get_height()))
		if first_frame is AtlasTexture and definition.has("canvas"):
			var source_canvas: Array = definition["canvas"]
			body_height *= (first_frame as AtlasTexture).atlas.get_height() / float(source_canvas[1])
		# Original idle body occupies ~88% of its canvas. Preserve that visible
		# body height with one authored scale per action, never resize each pose.
		var scale_value := target_height * 0.88 / body_height
		sprite.scale = Vector2.ONE * scale_value
		_apply_source_facing()
	sprite.speed_scale = 1.0
	sprite.play(animation_name)
	_sync_authored_frame_pivot()


func _production_frames(animation_name: String) -> SpriteFrames:
	if _frame_cache.has(animation_name):
		return _frame_cache[animation_name] as SpriteFrames
	var definition: Dictionary = _layout().get("animations", {}).get(animation_name, {})
	if definition.has("path") and definition.has("grid"):
		var texture := load(String(definition["path"])) as Texture2D
		var grid: Array = definition["grid"]
		var cell := texture.get_size() / Vector2(float(grid[0]), float(grid[1]))
		var authored := SpriteFrames.new()
		authored.remove_animation("default")
		authored.add_animation(animation_name)
		authored.set_animation_speed(animation_name, float(ANIMATION_FPS.get(animation_name, 12.0)))
		for index in range(int(grid[0]) * int(grid[1])):
			var frame := AtlasTexture.new()
			frame.atlas = texture
			frame.region = Rect2(Vector2(index % int(grid[0]), index / int(grid[0])) * cell, cell)
			authored.add_frame(animation_name, frame)
		_frame_cache[animation_name] = authored
		return authored
	var source: Array = {
		"idle": ["idle", "frame"],
		"hoe": ["hoe", "frame"],
		"plant": ["plant", "frame"],
		"water": ["water", "frame"],
		"fertilize": ["fertilize", "frame"],
		"harvest": ["harvest", "frame"],
	}.get(animation_name, ["idle", "frame"])
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, float(ANIMATION_FPS.get(animation_name, 12.0)))
	frames.set_animation_loop(animation_name, animation_name == "idle")
	for index in FRAME_SEQUENCE:
		var path := "%s/%s/%s_%02d.png" % [PRODUCTION_ROOT, source[0], source[1], index]
		frames.add_frame(animation_name, load(path) as Texture2D)
	return frames


func _layout() -> Dictionary:
	if _source_layout.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ANIMATION_LAYOUT))
		if parsed is Dictionary: _source_layout = parsed
	return _source_layout


func _sync_authored_frame_pivot() -> void:
	if sprite == null: return
	var definition: Dictionary = _layout().get("animations", {}).get(_source_animation, {})
	var pivots: Array = definition.get("frame_pivots", [])
	if pivots.is_empty() and not definition.has("fixed_pivot"): return
	var point: Array = definition["fixed_pivot"] if definition.has("fixed_pivot") else pivots[clampi(sprite.frame, 0, pivots.size() - 1)]
	var canvas: Array = definition["canvas"]
	var texture := load(String(definition["path"])) as Texture2D
	var imported_scale := texture.get_size() / Vector2(float(canvas[0]), float(canvas[1]))
	var pivot := Vector2(float(point[0]), float(point[1])) * imported_scale
	sprite.offset = -pivot
	sprite.set_meta("source_feet_pivot", pivot)
	sprite.set_meta("source_animation_sheet", String(definition["path"]))
	sprite.set_meta("authored_pivot_alignment", true)


func _on_animation_finished() -> void:
	if sprite.animation != &"idle":
		_active_job = {}
		set_meta("movement_phase", "idle")
		_start_next_job()
