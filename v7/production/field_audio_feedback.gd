extends Node
class_name FieldAudioFeedback

const ROOT := "res://assets/audio/field_sprint1"
const CLIPS := {
	"till": "field_till.wav",
	"seed": "field_plant.wav",
	"water": "field_water.wav",
	"fertilize": "field_fertilize.wav",
	"harvest": "field_harvest.wav",
	"crop_ready": "field_crop_ready.wav",
	"step": "farmer_step_grass.wav",
}

var players: Array[AudioStreamPlayer] = []
var cursor := 0


func _ready() -> void:
	for index in range(4):
		var player := AudioStreamPlayer.new()
		player.name = "FieldSFX_%02d" % (index + 1)
		player.bus = "SFX"
		add_child(player)
		players.append(player)


func play_action(action: String) -> void:
	_play(action)


func play_crop_ready() -> void:
	_play("crop_ready")


func play_step() -> void:
	_play("step", -8.0)


func _play(id: String, volume_db := -2.0) -> void:
	if players.is_empty() or not CLIPS.has(id):
		return
	var player := players[cursor]
	cursor = (cursor + 1) % players.size()
	player.stream = load("%s/%s" % [ROOT, CLIPS[id]]) as AudioStream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03)
	player.play()
