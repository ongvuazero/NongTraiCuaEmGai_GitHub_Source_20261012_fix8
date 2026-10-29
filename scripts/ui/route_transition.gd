extends CanvasLayer

# Presentation-only outgoing-frame dissolve. Navigation remains with ScreenRouter.
# A single short input guard prevents double-clicking into the incoming screen.
const DURATION := 0.24
var _snapshot: TextureRect
var _fade: Tween
var _captured := false
var _active := false
var _captures := 0
var _reveals := 0
var _max_capture_usec := 0
var _incoming: Node
var _incoming_mode := Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_snapshot = TextureRect.new()
	_snapshot.name = "OutgoingScreenDissolve"
	_snapshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_snapshot.stretch_mode = TextureRect.STRETCH_SCALE
	_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snapshot.focus_mode = Control.FOCUS_NONE
	_snapshot.hide()
	add_child(_snapshot)
	set_meta("presentation_only",true)
	set_meta("save_writes",0)

func capture() -> void:
	if _snapshot == null or DisplayServer.get_name() == "headless": return
	var viewport := get_viewport()
	if viewport == null or viewport.get_texture() == null: return
	var started := Time.get_ticks_usec()
	var frame := viewport.get_texture().get_image()
	if frame == null or frame.is_empty(): return
	if is_instance_valid(_fade): _fade.kill()
	_release_guard()
	_snapshot.texture = ImageTexture.create_from_image(frame)
	_snapshot.position = Vector2.ZERO
	_snapshot.size = viewport.get_visible_rect().size
	_snapshot.modulate.a = 1.0
	_snapshot.mouse_filter = Control.MOUSE_FILTER_STOP
	_snapshot.show()
	_captured = true
	_active = true
	_captures += 1
	_max_capture_usec = maxi(_max_capture_usec,Time.get_ticks_usec()-started)

func reveal(incoming: Node) -> void:
	if not _captured or _snapshot == null: return
	_incoming = incoming
	_incoming_mode = incoming.process_mode
	# A native Back/menu can arrive through its ALWAYS adapter during reveal.
	# Expose the underlying mode, not this temporary guard, to that modal.
	incoming.set_meta("route_transition_restore_mode", _incoming_mode)
	# GUI guards alone do not block Field's raw touch/_input handlers.
	incoming.process_mode = Node.PROCESS_MODE_DISABLED
	_captured = false
	_reveals += 1
	if is_instance_valid(_fade): _fade.kill()
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade.tween_property(_snapshot,"modulate:a",0.0,DURATION)
	_fade.tween_callback(_finish)

func _finish() -> void:
	_release_guard()
	_active = false
	_snapshot.hide()
	_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snapshot.texture = null

func _release_guard() -> void:
	if not is_instance_valid(_incoming):
		_incoming = null
		return
	var modal := _incoming.find_child("SaveMenuDialog",true,false) as Control
	var menu_open := modal != null and modal.is_visible_in_tree()
	if _incoming.process_mode == Node.PROCESS_MODE_DISABLED and not menu_open:
		_incoming.process_mode = _incoming_mode
	_incoming.remove_meta("route_transition_restore_mode")
	_incoming = null

func qa_summary() -> Dictionary:
	return {"active":_active,"captures":_captures,"reveals":_reveals,"duration":DURATION,"overlays":1,"input_guard":_snapshot != null and _snapshot.visible and _snapshot.mouse_filter == Control.MOUSE_FILTER_STOP,"max_capture_usec":_max_capture_usec,"save_writes":0}
