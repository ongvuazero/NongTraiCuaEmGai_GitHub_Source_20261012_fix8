@tool
extends Node2D

const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")

@export_category("Field Projection — Global Only")
@export var quad_top_left := Vector2(278, 268)
@export var quad_top_right := Vector2(894, 268)
@export var quad_bottom_right := Vector2(954, 558)
@export var quad_bottom_left := Vector2(214, 558)
@export_range(1.20, 1.36, 0.01) var depth_exponent := 1.28
@export_range(0.04, 0.14, 0.005) var bed_margin_u := 0.075
@export_range(0.08, 0.20, 0.005) var bed_margin_v := 0.13
@export_range(0.45, 0.82, 0.01) var crop_root_v := 0.68

@export_category("Crop Perspective Heights")
@export_range(40.0, 90.0, 1.0) var mature_height_far := 61.0
@export_range(45.0, 95.0, 1.0) var mature_height_middle := 72.5
@export_range(55.0, 110.0, 1.0) var mature_height_near := 84.0


func apply_tuning() -> void:
	var projection := Geometry.projection()
	projection["quad"] = {
		"tl": [quad_top_left.x, quad_top_left.y],
		"tr": [quad_top_right.x, quad_top_right.y],
		"br": [quad_bottom_right.x, quad_bottom_right.y],
		"bl": [quad_bottom_left.x, quad_bottom_left.y],
	}
	projection["depth_exponent"] = depth_exponent
	projection["bed_margin_u"] = bed_margin_u
	projection["bed_margin_v"] = bed_margin_v
	projection["crop_anchor_local_v"] = crop_root_v
	projection["mature_target_height_far"] = mature_height_far
	projection["mature_target_height_mid"] = mature_height_middle
	projection["mature_target_height_near"] = mature_height_near
