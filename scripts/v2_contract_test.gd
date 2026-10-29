extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var state: Dictionary = app.get("_state")
	assert(state["field_plots"].size() == 12, "V2 requires 12 plots")
	assert(state["inventory"].has("seed_tomato") and state["inventory"].has("seed_pumpkin"), "MVP seed set is incomplete")
	assert(not state["inventory"].has("seed_wheat") and not state["inventory"].has("seed_strawberry"), "Retired crops remain active")
	app.call("_handle_action", "go_field")
	await process_frame
	var ui_root: Control = app.get("_ui_root")
	for i in range(1, 13):
		var plot_node := ui_root.find_child("Plot_%02d" % i, true, false)
		assert(plot_node != null, "Missing plot %02d" % i)
		for layer_name in ["BaseSoil", "StateOverlay", "CropSprite", "ReadyOverlay", "SelectionOverlay", "ClickArea"]:
			assert(plot_node.get_node_or_null(layer_name) != null, "Plot %02d missing %s" % [i, layer_name])
	app.call("_handle_action", "field_till")
	app.call("_handle_action", "field_seed")
	var before_fertilize: int = app.get("_state")["field_plots"][0]["growth_stage"]
	app.call("_handle_action", "field_fertilize")
	assert(app.get("_state")["field_plots"][0]["growth_stage"] == before_fertilize, "Fertilizer must remain an overlay until day growth")
	app.call("_handle_action", "field_water")
	app.call("_handle_action", "advance_day")
	state = app.get("_state")
	assert(state["field_plots"][0]["growth_stage"] == 2, "Watered fertilized crop should receive the V2 growth bonus")
	assert(not state["field_plots"][1]["is_hoed"], "Plot updates must remain independent")
	assert(state["field_plots"][0]["position"] == Vector2(405, 230), "Plot origin does not match V2")
	assert(state["field_plots"][11]["position"] == Vector2(795, 460), "Plot grid does not match V2")
	print("V2_CONTRACT_TEST_PASS")
	quit()
