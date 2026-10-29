extends RefCounted
class_name SaveService

const StateValidator = preload("res://scripts/save_state_validator.gd")
const SLOT_COUNT := 3
const SLOT_FILE_PATTERN := "my_sisters_farm_slot_%d.save"
const LEGACY_SAVE_PATH := "user://my_sisters_farm_v2.save"
const SAVE_MAGIC := "MSF3\n"
const MAX_SAVE_BYTES := 64 * 1024 * 1024

var _base_dir := "user://"
var _sequence := 0


func _init(base_dir: String = "user://") -> void:
	_base_dir = base_dir
	if not _base_dir.ends_with("/"): _base_dir += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_dir))


func validate_state(state: Dictionary) -> Dictionary:
	return StateValidator.validate_state(state)


func save_current_slot(slot_id: int, state: Dictionary, location: String = "hub") -> Dictionary:
	if not _valid_slot(slot_id): return _result(false, "Slot khong hop le.")
	var validation := StateValidator.validate_state(state)
	if not validation["ok"]: return validation
	var payload := state.duplicate(true)
	payload["selected_slot"] = slot_id
	payload["last_screen"] = location
	payload["saved_at_unix"] = int(Time.get_unix_time_from_system())
	var bytes := (SAVE_MAGIC + Marshalls.raw_to_base64(var_to_bytes(payload))).to_utf8_buffer()
	var target := _slot_path(slot_id)
	var staged := target + ".writing." + _suffix()
	if _write_bytes(staged, bytes) != OK or not _verified_bytes(staged, bytes):
		return _result(false, "Khong the ghi/kiem tra save tam; tep cu duoc giu nguyen.")
	var published := _publish_temporary(staged, target + ".tmp")
	if not published["ok"]: return published
	var committed := _commit_temporary(target, bytes, true)
	if not committed["ok"]: return committed
	return {"ok": true, "message": "Da luu slot %d." % slot_id, "state": payload}


func load_slot(slot_id: int) -> Dictionary:
	if not _valid_slot(slot_id): return _result(false, "Slot khong hop le.")
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return _result(false, "Slot %d can phuc hoi tu backup." % slot_id if get_slot_metadata(slot_id)["recoverable"] else "Slot %d dang trong." % slot_id)
	var result := _read_valid_state(path)
	if not result["ok"]:
		result["message"] = "Save slot %d bi loi; tep goc va backup van duoc giu. %s" % [slot_id, result["message"]]
	return result


# Recovery is explicit. Inspecting or pressing Continue never rewrites the
# primary, nor silently substitutes an older farm into memory.
func recover_slot(slot_id: int) -> Dictionary:
	if not _valid_slot(slot_id): return _result(false, "Slot khong hop le.")
	var target := _slot_path(slot_id)
	if FileAccess.file_exists(target) and _read_valid_state(target)["ok"]:
		return _result(false, "Slot hop le; khong can phuc hoi.")
	var candidate := _recovery_candidate(target)
	if candidate.is_empty(): return _result(false, "Khong co backup hop le de phuc hoi slot %d." % slot_id)
	var source: String = candidate["path"]
	var source_bytes := FileAccess.get_file_as_bytes(source)
	# A .tmp recovery remains untouched even when the final replace fails.
	var staged := target + ".recovery." + _suffix()
	if _copy_path(source, staged) != OK or not _verified_bytes(staged, source_bytes):
		return _result(false, "Khong the sao luu tep phuc hoi; ban tot van duoc giu.")
	var preserved := ""
	if FileAccess.file_exists(target):
		var archived := _preserve_file(target, "corrupt")
		if not archived["ok"]: return archived
		preserved = archived["path"]
		if _remove_path(target) != OK: return _result(false, "Khong the thay tep loi; tep goc va backup duoc giu.")
	if _rename_path(staged, target) != OK or not _verified_bytes(target, source_bytes):
		if not preserved.is_empty(): _restore_copy(preserved, target)
		return _result(false, "Phuc hoi that bai; tep goc va ban backup tot van duoc giu.")
	var result := _read_valid_state(target)
	if not result["ok"]: return result
	result["message"] = "Da phuc hoi slot %d tu .%s." % [slot_id, candidate["kind"]]
	result["recovery_source"] = candidate["kind"]
	result["preserved_path"] = preserved
	return result


func delete_slot(slot_id: int) -> Dictionary:
	if not _valid_slot(slot_id): return _result(false, "Slot khong hop le.")
	var path := _slot_path(slot_id)
	# Explicit deletion retires canonical recovery candidates too; archives
	# remain available manually but .deleted.bak never resurrects a slot.
	var archives: Dictionary = {}
	for suffix in ["", ".bak", ".tmp"]:
		var source: String = path + suffix
		if not FileAccess.file_exists(source): continue
		var archive: String = path + ".deleted.bak" if suffix.is_empty() and not FileAccess.file_exists(path + ".deleted.bak") else source + ".deleted." + _suffix() + ".bak"
		var bytes := FileAccess.get_file_as_bytes(source)
		if _copy_path(source, archive) != OK or FileAccess.get_file_as_bytes(archive) != bytes:
			return _result(false, "Khong the sao luu slot truoc khi xoa; tep hien tai van duoc giu.")
		archives[source] = archive
	# Retire backups first, so a failed primary removal is still a normal load.
	var retired: Array[String] = []
	for suffix in [".bak", ".tmp", ""]:
		if FileAccess.file_exists(path + suffix) and _remove_path(path + suffix) != OK:
			for source in retired: _restore_copy(archives[source], source)
			return _result(false, "Khong the xoa slot %d; ban luu truoc xoa van duoc giu." % slot_id)
		if archives.has(path + suffix): retired.append(path + suffix)
	return _result(true, "Da xoa slot %d; ban .deleted.bak duoc giu de phuc hoi thu cong." % slot_id)


func get_slot_metadata(slot_id: int) -> Dictionary:
	var metadata := {"slot_id": slot_id, "occupied": false, "valid": true, "recoverable": false, "recovery_source": "", "primary_missing": true, "day": 0, "coins": 0, "location": "", "last_played": 0, "farm_name": "", "message": ""}
	if not _valid_slot(slot_id):
		metadata["valid"] = false
		return metadata
	var path := _slot_path(slot_id)
	metadata["primary_missing"] = not FileAccess.file_exists(path)
	var loaded := _read_valid_state(path) if not metadata["primary_missing"] else _result(false, "Slot dang trong.")
	if loaded["ok"]:
		_metadata_from_state(metadata, loaded["state"], path)
		metadata["occupied"] = true
		return metadata
	var candidate := _recovery_candidate(path)
	metadata["occupied"] = not metadata["primary_missing"] or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")
	metadata["valid"] = not metadata["occupied"] # Empty is valid, recovery is not a normal load.
	metadata["message"] = loaded["message"]
	if not candidate.is_empty():
		metadata["recoverable"] = true
		metadata["recovery_source"] = candidate["kind"]
		_metadata_from_state(metadata, candidate["state"], candidate["path"])
	return metadata


func get_latest_valid_slot() -> int:
	var latest_slot := 0
	var latest_time := -1
	for slot_id in range(1, SLOT_COUNT + 1):
		var metadata := get_slot_metadata(slot_id)
		if metadata["occupied"] and (metadata["valid"] or metadata["recoverable"]) and int(metadata["last_played"]) > latest_time:
			latest_time = int(metadata["last_played"])
			latest_slot = slot_id
	return latest_slot


func migrate_legacy_save_if_needed() -> Dictionary:
	if _base_dir != "user://": return _result(true, "Test/isolated save root; bo qua legacy migration.")
	# Even broken/recoverable slots are user data, not migration destinations.
	for slot_id in range(1, SLOT_COUNT + 1):
		if get_slot_metadata(slot_id)["occupied"]: return _result(true, "Khong can migrate.")
	if not FileAccess.file_exists(LEGACY_SAVE_PATH): return _result(true, "Khong can migrate.")
	var legacy := _read_valid_state(LEGACY_SAVE_PATH)
	if not legacy["ok"]: return _result(false, "Save cu bi loi; da giu nguyen de khoi phuc.")
	return save_current_slot(1, legacy["state"], String(legacy["state"].get("last_screen", "hub")))


func _read_valid_state(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _result(false, "Khong mo duoc save.")
	var length := file.get_length()
	if length < 4 or length > MAX_SAVE_BYTES:
		file.close()
		return _result(false, "Save co kich thuoc khong hop le.")
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length: return _result(false, "Khong doc duoc day du tep save.")
	var variant_bytes := bytes
	var text_prefix := bytes.slice(0, mini(bytes.size(), SAVE_MAGIC.length())).get_string_from_utf8()
	if text_prefix == SAVE_MAGIC:
		variant_bytes = Marshalls.base64_to_raw(bytes.slice(SAVE_MAGIC.length()).get_string_from_utf8())
	if variant_bytes.size() < 4 or int(variant_bytes.decode_u32(0) & 0xFF) != TYPE_DICTIONARY:
		return _result(false, "Save co header khong hop le.")
	var loaded = bytes_to_var(variant_bytes)
	if not loaded is Dictionary: return _result(false, "Save khong phai Dictionary.")
	var validation := StateValidator.validate_state(loaded)
	if not validation["ok"]: return validation
	return {"ok": true, "message": "OK", "state": loaded}


func _recovery_candidate(target: String) -> Dictionary:
	var candidate: Dictionary = {}
	var latest := -1
	# .deleted.bak and archived corruption are intentionally never candidates.
	for suffix in [".bak", ".tmp"]:
		var path: String = target + suffix
		if not FileAccess.file_exists(path): continue
		var loaded := _read_valid_state(path)
		if not loaded["ok"]: continue
		var time := int(loaded["state"].get("saved_at_unix", FileAccess.get_modified_time(path)))
		if time >= latest:
			latest = time
			candidate = {"path": path, "kind": suffix.substr(1), "state": loaded["state"]}
	return candidate


func _metadata_from_state(metadata: Dictionary, state: Dictionary, path: String) -> void:
	metadata["day"] = int(state.get("day", 1))
	metadata["coins"] = int(state.get("coins", 0))
	metadata["location"] = String(state.get("last_screen", "hub"))
	metadata["last_played"] = int(state.get("saved_at_unix", FileAccess.get_modified_time(path)))
	metadata["farm_name"] = String(state.get("farm_name", ""))


func _publish_temporary(staged: String, temporary: String) -> Dictionary:
	var preserved := ""
	if FileAccess.file_exists(temporary):
		var archived := _preserve_file(temporary, "interrupted")
		if not archived["ok"]: return archived
		preserved = archived["path"]
		if _remove_path(temporary) != OK: return _result(false, "Khong the thay save tam; tep cu duoc giu.")
	if _rename_path(staged, temporary) != OK:
		if not preserved.is_empty(): _restore_copy(preserved, temporary)
		return _result(false, "Khong the cong bo save tam; cac ban goc van duoc giu.")
	return _result(true, "OK")


func _commit_temporary(target: String, expected: PackedByteArray, update_backup: bool) -> Dictionary:
	var temporary := target + ".tmp"
	var preserved := ""
	if FileAccess.file_exists(target):
		var primary_valid := bool(_read_valid_state(target)["ok"])
		# Never poison a known-good .bak with a corrupt primary.
		if update_backup and primary_valid:
			var backup_result := _replace_backup_from(target, target + ".bak")
			if not backup_result["ok"]: return backup_result
			preserved = target + ".bak"
		else:
			var archived := _preserve_file(target, "corrupt")
			if not archived["ok"]: return archived
			preserved = archived["path"]
		if _remove_path(target) != OK: return _result(false, "Khong the thay the save cu; backup va save tam duoc giu.")
	if _rename_path(temporary, target) != OK or not _verified_bytes(target, expected):
		if not preserved.is_empty(): _restore_copy(preserved, target)
		return _result(false, "Ghi save that bai; tep cu va save tam/backup van duoc giu de phuc hoi.")
	return _result(true, "OK")


func _replace_backup_from(source: String, backup: String) -> Dictionary:
	var staged := backup + ".writing." + _suffix()
	var expected := FileAccess.get_file_as_bytes(source)
	if _copy_path(source, staged) != OK or not _verified_bytes(staged, expected):
		return _result(false, "Khong the kiem tra backup; primary va backup cu van duoc giu.")
	var preserved := ""
	if FileAccess.file_exists(backup):
		# A bounded second-generation fallback, not an unbounded archive per
		# crop click. The current primary and .bak remain intact until verified.
		preserved = backup + ".previous"
		var old_bytes := FileAccess.get_file_as_bytes(backup)
		if _copy_path(backup, preserved) != OK or FileAccess.get_file_as_bytes(preserved) != old_bytes:
			return _result(false, "Khong the giu backup truoc; primary va backup hien tai van duoc giu.")
		if _remove_path(backup) != OK: return _result(false, "Khong the thay backup; primary van duoc giu.")
	if _rename_path(staged, backup) != OK or not _verified_bytes(backup, expected):
		if not preserved.is_empty(): _restore_copy(preserved, backup)
		return _result(false, "Khong the cong bo backup; primary va ban sao tot van duoc giu.")
	return _result(true, "OK")


func _preserve_file(path: String, label: String) -> Dictionary:
	var archived := path + "." + label + "." + _suffix() + ".bak"
	var bytes := FileAccess.get_file_as_bytes(path)
	if _copy_path(path, archived) != OK or FileAccess.get_file_as_bytes(archived) != bytes:
		return _result(false, "Khong the bao toan tep goc; khong ghi de/xoa tep nay.")
	return {"ok": true, "message": "OK", "path": archived}


func _restore_copy(source: String, target: String) -> bool:
	var expected := FileAccess.get_file_as_bytes(source)
	return _copy_path(source, target) == OK and FileAccess.get_file_as_bytes(target) == expected


func _verified_bytes(path: String, expected: PackedByteArray) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == expected and _read_valid_state(path)["ok"]


# Overridable I/O seams let isolated QA inject failure without global runtime flags.
func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


func _copy_path(source: String, target: String) -> Error:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))


func _remove_path(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rename_path(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))


func _suffix() -> String:
	_sequence += 1
	return "%d_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), _sequence]


func _slot_path(slot_id: int) -> String:
	return _base_dir + (SLOT_FILE_PATTERN % slot_id)


func _valid_slot(slot_id: int) -> bool:
	return slot_id >= 1 and slot_id <= SLOT_COUNT


func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
