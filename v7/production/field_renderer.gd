extends Node2D
class_name FieldRenderer

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const BedVisual = preload("res://v7/production/field_bed_visual.gd")
const CropCluster = preload("res://v7/production/field_crop_cluster.gd")
const ActionVFX = preload("res://v7/production/field_action_vfx.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")

var bed_world: Node2D
var crop_world: Node2D
var fx_world: Node2D
var plot_cache: Dictionary = {}
var selected_plot_id := 1


func _ready() -> void:
	bed_world = Node2D.new()
	bed_world.name = "FieldBedWorld"
	add_child(bed_world)
	crop_world = Node2D.new()
	crop_world.name = "FieldCropDepthWorld"
	crop_world.y_sort_enabled = true
	add_child(crop_world)
	fx_world = Node2D.new()
	fx_world.name = "FieldFXWorld"
	fx_world.z_index = 30
	add_child(fx_world)


func render(plots: Array, selected_plot: int, only_plot_ids := PackedInt32Array()) -> void:
	_clear(bed_world)
	_clear(crop_world)
	_clear(fx_world)
	plot_cache.clear()
	selected_plot_id = selected_plot
	for plot in plots:
		var plot_id := int(plot.get("id", 0))
		if not only_plot_ids.is_empty() and not only_plot_ids.has(plot_id):
			continue
		plot_cache[plot_id] = Dictionary(plot).duplicate(true)
		_render_plot(plot_id)


func update_plot(plot: Dictionary, new_selected_plot: int) -> void:
	var plot_id := int(plot.get("id", 0))
	var previous_selected := selected_plot_id
	selected_plot_id = new_selected_plot
	plot_cache[plot_id] = plot.duplicate(true)
	_render_plot(plot_id)
	if previous_selected != selected_plot_id and previous_selected != plot_id and plot_cache.has(previous_selected):
		_render_plot(previous_selected)
	if selected_plot_id != plot_id and plot_cache.has(selected_plot_id):
		_render_plot(selected_plot_id)


func update_all_plots(plots: Array, new_selected_plot: int) -> void:
	selected_plot_id = new_selected_plot
	for plot in plots:
		var plot_id := int(plot.get("id", 0))
		plot_cache[plot_id] = Dictionary(plot).duplicate(true)
		_render_plot(plot_id)


func update_selection(new_selected_plot: int) -> void:
	var previous_selected := selected_plot_id
	selected_plot_id = new_selected_plot
	if plot_cache.has(previous_selected):
		_render_plot(previous_selected)
	if selected_plot_id != previous_selected and plot_cache.has(selected_plot_id):
		_render_plot(selected_plot_id)


func _render_plot(plot_id: int) -> void:
	var old_bed := bed_world.get_node_or_null("Bed_%02d" % plot_id)
	if old_bed != null:
		old_bed.free()
	for child in crop_world.get_children():
		if String(child.name).begins_with("Crop_%02d_" % plot_id):
			child.free()
	var old_ready := fx_world.get_node_or_null("ReadyFX_%02d" % plot_id)
	if old_ready != null:
		old_ready.free()
	var old_need := fx_world.get_node_or_null("NeedFX_%02d" % plot_id)
	if old_need != null:
		old_need.free()
	var plot: Dictionary = plot_cache.get(plot_id, {})
	if plot.is_empty():
		return
	var hoed := bool(plot.get("is_hoed", false))
	var watered := bool(plot.get("watered_today", false))
	var crop_id := String(plot.get("crop", ""))
	var growth_stage := int(plot.get("growth_stage", 0))
	var ready := bool(plot.get("ready_to_harvest", false))
	var fertilized := bool(plot.get("fertilizer_pending", false))
	# Moisture and nutrients are independent persistent states. Nutrients are
	# overlaid as grains by BedVisual, never as an opaque replacement soil.
	var visual_state := "tilled_wet" if hoed and watered else ("tilled_dry" if hoed else "untilled")
	var bed := BedVisual.new()
	bed.name = "Bed_%02d" % plot_id
	bed_world.add_child(bed)
	bed.configure(plot_id, visual_state, plot_id == selected_plot_id, fertilized)
	_add_need_marker(plot_id, plot)
	if crop_id.is_empty():
		return
	var crop := CropCluster.new()
	crop.name = "Crop_%02d_%s" % [plot_id, crop_id]
	crop_world.add_child(crop)
	crop.configure(plot_id, crop_id, growth_stage, ready)
	if ready:
		_add_ready_fx(plot_id)


func play_action_fx(plot_id: int, action: String, soil_contact := Vector2.INF) -> void:
	var effect := ActionVFX.new()
	effect.name = "FX_%s_%02d" % [action, plot_id]
	fx_world.add_child(effect)
	effect.configure(plot_id, action, soil_contact)


func play_growth_transition(plot_ids: PackedInt32Array) -> void:
	for plot_id in plot_ids:
		var crop := crop_world.get_node_or_null("Crop_%02d_%s" % [plot_id, _crop_id_for_plot(plot_id)])
		if crop != null and crop.has_method("animate_stage_in"):
			crop.animate_stage_in()
		play_action_fx(plot_id, "seed")


func play_reward_feedback(plot_id: int, crop_id: String, crop_label: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var reward := Node2D.new()
	reward.name = "HarvestReward_%02d" % plot_id
	# The pickup belongs to the clicked crop, not an old screenshot UI slot.
	var bed_rect := PixelMap.visual_plot_rect(plot_id)
	reward.position = Vector2(bed_rect.get_center().x, bed_rect.position.y - 22.0)
	reward.z_index = 100
	fx_world.add_child(reward)
	var reward_texture: Texture2D = load("res://assets/field_approved_v1/runtime/ui/reward_popup.png")
	var plate := Sprite2D.new()
	plate.name = "RewardPlate"
	plate.texture = reward_texture
	plate.scale = Vector2(232.0 / float(reward_texture.get_width()), 76.0 / float(reward_texture.get_height()))
	reward.add_child(plate)
	var backing := Node2D.new()
	backing.name = "RewardBacking"
	reward.add_child(backing)
	var icon := Sprite2D.new()
	icon.name = "RewardCropIcon"
	icon.texture = Assets.get_item_texture("crop_" + crop_id)
	if icon.texture != null:
		icon.position = Vector2(-40, 0)
		icon.scale = Vector2.ONE * (48.0 / float(icon.texture.get_height()))
	reward.add_child(icon)
	var label := Label.new()
	label.name = "RewardQuantityLabel"
	label.position = Vector2(-6, -28)
	label.size = Vector2(106, 58)
	label.text = "+%d %s" % [quantity, crop_label]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("4a2c19"))
	reward.add_child(label)
	reward.scale = Vector2.ONE * 0.86
	reward.modulate.a = 1.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(reward, "scale", Vector2.ONE, 0.20)
	tween.tween_property(reward, "position:y", reward.position.y - 26.0, 1.32)
	tween.tween_property(reward, "modulate:a", 0.0, 0.28).set_delay(1.04)
	tween.finished.connect(reward.queue_free)


func _crop_id_for_plot(plot_id: int) -> String:
	var prefix := "Crop_%02d_" % plot_id
	for child in crop_world.get_children():
		if String(child.name).begins_with(prefix):
			return String(child.name).trim_prefix(prefix)
	return ""


func _add_ready_fx(plot_id: int) -> void:
	var texture := load("res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/FIELD/FEEDBACK_BADGES/ready.png") as Texture2D
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.name = "ReadyFX_%02d" % plot_id
	sprite.texture = texture
	# Opaque, persistent indicator ABOVE the plant, not a faint sparkle hidden
	# under leaves. It exists only while actual ready_to_harvest is true.
	var bed_rect := PixelMap.visual_plot_rect(plot_id)
	sprite.position = Vector2(bed_rect.get_center().x, bed_rect.position.y + 3.0)
	sprite.scale = Vector2.ONE * (42.0 / float(texture.get_height()))
	sprite.modulate.a = 1.0
	sprite.set_meta("harvest_ready_indicator", true)
	sprite.set_meta("plot_id", plot_id)
	fx_world.add_child(sprite)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func need_for_plot(plot: Dictionary) -> String:
	if bool(plot.get("locked", false)): return ""
	if bool(plot.get("ready_to_harvest", false)): return "harvest"
	if String(plot.get("crop", "")).is_empty():
		return "seed" if bool(plot.get("is_hoed", false)) else "till"
	return "" if bool(plot.get("watered_today", false)) else "water"


func _add_need_marker(plot_id: int, plot: Dictionary) -> void:
	var need := need_for_plot(plot)
	# Existing ready art is the harvest icon. Optional fertilizer is not a need.
	if need.is_empty() or need == "harvest": return
	var paths := {
		"till": "res://assets/field_approved_v1/runtime/ui/action_till.png",
		"seed": "res://assets/field_approved_v1/runtime/ui/action_plant_approved.png",
		"water": "res://assets/canonical_v2/03_ART_RUNTIME_READY/FIELD/CROP_OVERLAYS/watered_droplet_overlay.png",
	}
	var path := String(paths.get(need, ""))
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture == null:
		texture = Assets.action_button("hoe" if need == "till" else "plant" if need == "seed" else "water", "default")
	if texture == null: return
	var marker := Sprite2D.new()
	marker.name = "NeedFX_%02d" % plot_id
	marker.texture = texture
	var rect := PixelMap.visual_plot_rect(plot_id)
	marker.position = Vector2(rect.get_center().x, rect.position.y + 5)
	marker.scale = Vector2.ONE * (32.0 / maxf(texture.get_width(), texture.get_height()))
	marker.set_meta("plot_id", plot_id)
	marker.set_meta("need_action", need)
	fx_world.add_child(marker)
