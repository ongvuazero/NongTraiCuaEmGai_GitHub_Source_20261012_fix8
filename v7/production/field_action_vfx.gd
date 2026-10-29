extends Node2D
class_name FieldActionVFX

const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const SemanticFlow = preload("res://scripts/ui/action_feedback_flow.gd")
const VFX_TEXTURES := {
	"till": "res://assets/player_feedback_v2/vfx/till_sheet.png",
	"seed": "res://assets/player_feedback_v2/vfx/plant_sheet.png",
	"water": "res://assets/player_feedback_v2/vfx/water_sheet.png",
	"fertilize": "res://assets/player_feedback_v2/vfx/fertilize_sheet.png",
	"harvest": "res://assets/player_feedback_v2/vfx/harvest_sheet.png",
}
const TARGET_HEIGHT := {
	"till": 54.0,
	"seed": 38.0,
	"water": 66.0,
	"fertilize": 48.0,
	"harvest": 78.0,
}

const ACTION_TIMING := {
	"till": {"frames": 8, "duration": 0.68},
	"seed": {"frames": 8, "duration": 0.64},
	"water": {"frames": 8, "duration": 0.72},
	"fertilize": {"frames": 8, "duration": 0.68},
	"harvest": {"frames": 8, "duration": 0.68},
}

var plot_id := 1
var action := "till"
var frame_count := 8
var duration := 0.46
var elapsed := 0.0
var frame_index := 0
var visual: Sprite2D
var source_sheet: Texture2D
var frame_textures: Array[AtlasTexture] = []
var frame_canvas := Vector2.ZERO
var semantic_flow: Node2D


func configure(target_plot_id: int, action_id: String, soil_contact := Vector2.INF) -> void:
	plot_id = target_plot_id
	action = action_id
	# The committed soil updates immediately. A newer action on the same bed
	# must not remain hidden under the previous water/seed effect after fast taps.
	for sibling in get_parent().get_children():
		if sibling != self and sibling is FieldActionVFX and sibling.plot_id == plot_id:
			sibling.hide()
			sibling.queue_free()
	set_meta("replaces_previous_plot_effect",true)
	var timing: Dictionary = ACTION_TIMING.get(action, ACTION_TIMING["till"])
	frame_count = int(timing["frames"])
	duration = float(timing["duration"])
	position = soil_contact if soil_contact.is_finite() else PixelMap.visual_crop_anchor(plot_id)
	set_meta("target_anchor", position)
	set_meta("frame_count", frame_count)
	set_meta("duration", duration)
	visual = Sprite2D.new()
	visual.name = "PainterlyAnimatedVFX"
	source_sheet = load(String(VFX_TEXTURES.get(action, VFX_TEXTURES["seed"]))) as Texture2D
	if source_sheet == null:
		set_meta("source_missing", true)
		queue_free()
		return
	_build_frame_atlases()
	_set_frame(0)
	visual.centered = false
	# A fixed full-cell canvas/pivot across the complete sequence. Never trim or
	# rescale each frame's growing/decaying silhouette independently.
	visual.offset = Vector2(-frame_canvas.x * 0.5, -frame_canvas.y)
	var target_height := float(TARGET_HEIGHT.get(action, 48.0))
	var base_scale := target_height / frame_canvas.y
	visual.scale = Vector2.ONE * base_scale
	visual.modulate.a = 1.0
	add_child(visual)
	semantic_flow = SemanticFlow.new()
	semantic_flow.name = "SemanticActionFlow"
	add_child(semantic_flow)
	semantic_flow.configure(action, duration, Vector2.ZERO)
	set_meta("semantic_feedback", true)
	set_meta("soil_contact", position)
	set_process(true)
	_update_visual(0.0)


func _process(delta: float) -> void:
	elapsed += delta
	if action == "harvest" and is_instance_valid(semantic_flow):
		var receipt := get_parent().get_node_or_null("HarvestReward_%02d/RewardCropIcon" % plot_id) as Sprite2D
		if receipt != null and receipt.texture != null:
			semantic_flow.attach_receipt(to_local(receipt.global_position), receipt.texture)
	var next_frame := mini(frame_count - 1, int(floor(elapsed / duration * float(frame_count))))
	if next_frame != frame_index:
		frame_index = next_frame
		_set_frame(frame_index)
	_update_visual(clampf(elapsed / duration, 0.0, 1.0))
	if elapsed >= duration:
		queue_free()


func _update_visual(t: float) -> void:
	if visual == null or visual.texture == null:
		return
	var target_height := float(TARGET_HEIGHT.get(action, 48.0))
	var base_scale := target_height / frame_canvas.y
	visual.scale = Vector2.ONE * base_scale
	# Source frames already grow/peak/decay. Only a gentle final tail fade,
	# without an extra scale tween that makes the effect look like a UI pop.
	visual.modulate.a = 1.0 - smoothstep(0.88, 1.0, t)
	visual.position = Vector2.ZERO


func _set_frame(index: int) -> void:
	if frame_textures.is_empty():
		return
	visual.texture = frame_textures[clampi(index, 0, frame_textures.size() - 1)]


func _build_frame_atlases() -> void:
	frame_textures.clear()
	# Actual imported dimensions, including the supplied 1774x887 canvas:
	# each 4x2 cell is 443.5px square. No guessed 512px extraction geometry.
	frame_canvas = source_sheet.get_size() / Vector2(4.0, 2.0)
	for index in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = source_sheet
		atlas.region = Rect2(Vector2(index % 4, index / 4) * frame_canvas, frame_canvas)
		atlas.filter_clip = true
		frame_textures.append(atlas)
	set_meta("frame_canvas", frame_canvas)
	set_meta("source_dimensions", source_sheet.get_size())
	set_meta("root_rule", "fixed bottom-center full cell; constant scale; native fractional AtlasTexture")
