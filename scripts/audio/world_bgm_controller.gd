extends Node

# Presentation only. GameState owns the existing Music/Master bus settings.
# This Main sibling survives ScreenHost replacements and gameplay-menu freezes.
const FARM_PATH := "res://assets/audio/bgm/farm_day_loop.ogg"
const FANTASY_PATH := "res://assets/audio/bgm/dragon_isles_loop.ogg"
const FARM_ROUTES := ["title","save","hub","field","field_select","animal"]
const FANTASY_ROUTES := ["dragon","destination"]
const SILENCE_DB := -80.0

@export_range(0.1,4.0,0.05) var crossfade_seconds := 1.35
@export_range(-30.0,0.0,0.5) var base_volume_db := -8.0

var players: Dictionary = {}
var _streams: Dictionary = {}
var _gains := {"farm":0.0,"fantasy":0.0}
var _fade_from := {"farm":0.0,"fantasy":0.0}
var _fade_elapsed := 0.0
var _fading := false
var _requested_family := ""
var _current_family := ""
var _last_route := ""
var _router: Node
var _missing_assets: Array[String] = []
var _route_events := 0
var _track_starts := 0
var _family_switches := 0
var _missing_warning_count := 0
var _music_bus_available := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("presentation_only",true)
	set_meta("settings_volume_owner","GameState Music/Master buses")
	_music_bus_available = AudioServer.get_bus_index("Music") >= 0
	for family in ["farm","fantasy"]:
		var player := AudioStreamPlayer.new()
		player.name = "FarmBGM" if family == "farm" else "FantasyBGM"
		player.bus = "Music"
		player.volume_db = SILENCE_DB
		add_child(player)
		players[family] = player
	_load_track("farm",FARM_PATH)
	_load_track("fantasy",FANTASY_PATH)
	if not _missing_assets.is_empty() or not _music_bus_available:
		_missing_warning_count = 1
		push_warning("BGM remains silent or retains its available track; missing assets: %s; Music bus available: %s" % [str(_missing_assets),str(_music_bus_available)])
	set_process(false)
	_router = get_node_or_null("/root/ScreenRouter")
	if _router != null and _router.has_signal("screen_changed"):
		_router.connect("screen_changed",_on_route_changed)
		_on_route_changed(String(_router.get("current_screen")))

func _load_track(family: String,path: String) -> void:
	# No audio preloads: fresh installs remain valid before generated assets arrive.
	if not ResourceLoader.exists(path):
		_missing_assets.append(path)
		return
	var source := load(path) as AudioStream
	if not source is AudioStreamOggVorbis:
		_missing_assets.append(path)
		return
	# Runtime-only copy: enable a native seamless loop without changing imports.
	var stream := source.duplicate() as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = 0.0
	_streams[family] = stream
	(players[family] as AudioStreamPlayer).stream = stream

func _exit_tree() -> void:
	if is_instance_valid(_router) and _router.is_connected("screen_changed",_on_route_changed):
		_router.disconnect("screen_changed",_on_route_changed)

func _on_route_changed(route: String) -> void:
	_last_route = route
	_route_events += 1
	var family := _requested_family if not _requested_family.is_empty() else "farm"
	if route in FARM_ROUTES: family = "farm"
	elif route in FANTASY_ROUTES: family = "fantasy"
	_request_family(family)

func _request_family(family: String) -> void:
	_requested_family = family
	# Never stop the available track just because another asset is not installed.
	if not _music_bus_available or not _streams.has(family): return
	if family == _current_family: return
	var player := players[family] as AudioStreamPlayer
	if not player.playing:
		player.volume_db = SILENCE_DB
		player.play()
		_track_starts += 1
	_fade_from = _gains.duplicate()
	_fade_elapsed = 0.0
	_fading = true
	if not _current_family.is_empty(): _family_switches += 1
	_current_family = family
	set_process(true)

func _process(delta: float) -> void:
	if not _fading: return
	_fade_elapsed += maxf(0.0,delta)
	var progress := clampf(_fade_elapsed/maxf(crossfade_seconds,0.01),0.0,1.0)
	for family in players:
		var target := 1.0 if String(family) == _current_family else 0.0
		_gains[family] = lerpf(float(_fade_from[family]),target,progress)
		var gain := clampf(float(_gains[family]),0.0,1.0)
		var player := players[family] as AudioStreamPlayer
		# Only local fade/trim; never multiply user settings or touch bus volume.
		player.volume_db = SILENCE_DB if gain <= 0.0 else base_volume_db+linear_to_db(gain)
	if progress < 1.0: return
	_fading = false
	for family in players:
		if float(_gains[family]) <= 0.0: (players[family] as AudioStreamPlayer).stop()
	set_process(false)

func qa_summary() -> Dictionary:
	var streams: Array[Dictionary] = []
	for family in ["farm","fantasy"]:
		var player := players.get(family) as AudioStreamPlayer
		if player == null: continue
		var stream := _streams.get(family) as AudioStreamOggVorbis
		streams.append({"family":family,"playing":player.playing,"position":player.get_playback_position(),"gain":float(_gains[family]),"volume_db":player.volume_db,"bus":String(player.bus),"loop":stream != null and stream.loop,"length":stream.get_length() if stream != null else 0.0})
	return {"players":players.size(),"streams_available":_streams.size(),"missing_assets":_missing_assets.duplicate(),"missing_warning_count":_missing_warning_count,"music_bus_available":_music_bus_available,"requested_family":_requested_family,"current_family":_current_family,"last_route":_last_route,"fading":_fading,"route_events":_route_events,"track_starts":_track_starts,"family_switches":_family_switches,"base_volume_db":base_volume_db,"crossfade_seconds":crossfade_seconds,"streams":streams,"save_writes":0}

