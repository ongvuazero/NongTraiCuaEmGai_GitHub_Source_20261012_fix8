extends Node
class_name FieldState

var game_state: Node

func bind(authority: Node) -> void:
	game_state = authority

func plots() -> Array:
	return game_state.field_plots().duplicate(true)

func selected_plot_id() -> int:
	return int(game_state.data.get("selected_plot", 1))

func selected_plot() -> Dictionary:
	return game_state.get_plot(selected_plot_id()).duplicate(true)

func action_allowed(action: String) -> bool:
	return bool(game_state.field_action_allowed(action))


func action_allowed_on_plot(plot_id: int, action: String) -> bool:
	return bool(game_state.field_action_allowed(action, game_state.get_plot(plot_id)))


func tool_available(action: String) -> bool:
	if not game_state.has_energy(action):
		return false
	if action == "harvest":
		for plot in game_state.field_plots():
			if game_state.field_action_allowed("harvest", plot): return true
		return false
	if action == "seed":
		var inventory: Dictionary = game_state.data.get("inventory", {})
		for crop in ["carrot", "tomato", "pumpkin"]:
			if game_state.is_crop_unlocked(crop) and int(inventory.get("seed_" + crop, 0)) > 0:
				return true
		return false
	return action in ["till", "water", "fertilize", "harvest"]

func dispatch(action: String) -> bool:
	return bool(game_state.apply_field_action(action))


func dispatch_on_plot(plot_id: int, action: String) -> bool:
	return bool(game_state.apply_field_action_on_plot(plot_id, action, false))
