extends SceneTree


var app: Control
var output_dir := ""


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://qa/screens")
	DirAccess.make_dir_recursive_absolute(output_dir)
	call_deferred("_run")


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _settle()
	await _capture("01_title.png")
	app.call("_handle_action", "open_new_game")
	await _settle()
	await _capture("02_save.png")
	app.call("_select_save_slot", 1)
	app.call("_confirm_save_slot")
	await _settle()
	await _capture("03_hub.png")
	app.call("_handle_action", "go_field")
	await _settle()
	app.call("_handle_action", "field_till")
	app.call("_handle_action", "field_seed")
	app.call("_handle_action", "field_water")
	app.call("_handle_action", "field_fertilize")
	app.call("_select_plot", 2)
	app.call("_handle_action", "field_till")
	app.call("_select_plot", 3)
	app.call("_handle_action", "field_till")
	app.call("_handle_action", "advance_day")
	app.call("_select_plot", 1)
	app.call("_handle_action", "field_water")
	await _settle()
	await _capture("04_field_layers.png")
	for entry in [
		["open_shop", "05_shop.png"],
		["open_inventory", "06_storage.png"],
		["open_settings", "07_settings.png"],
		["go_animal_inside", "08_animal.png"],
		["open_island", "09_dragon.png"],
	]:
		app.call("_handle_action", entry[0])
		await _settle()
		await _capture(entry[1])
	quit()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _capture(file_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save %s: %s" % [file_name, error_string(error)])
