extends RefCounted
class_name UILocale

const Registry = preload("res://scripts/localization/locale_registry.gd")
const Fonts = preload("res://scripts/localization/locale_fonts.gd")
const Events = preload("res://scripts/localization/locale_events.gd")
const CATALOG_PATH := "res://localization/catalog.json"
# These positional values are user-authored identities, not UI translation keys.
# Resolve via the canonical English pair so every locale/source alias is covered.
const RAW_TEMPLATE_ARGUMENT_POSITIONS := {
	"Slot %d · %s\nDay %d · %s": [1],
}
static var _initialized := false
static var _catalog: Dictionary = {}
static var _messages: Dictionary = {}
static var _pairs: Dictionary = {}
static var _locale_texts: Dictionary = {}
static var _locale_provenance: Dictionary = {}
static var _templates: Array = []
static var _translations: Array[Translation] = []
static var _events := Events.new()
static var _missing: Dictionary = {}
static var _literal_parameter_expression: RegEx

static func events():
	return _events

static func initialize() -> void:
	if _initialized: return
	_initialized = true
	Fonts.initialize()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("Missing compiled localization catalog: " + CATALOG_PATH)
		return
	_catalog = parsed.get("aliases", {}).duplicate(true)
	# Numbers and bare format parameters are caller-owned data, never lookup keys.
	# Apply this to source aliases too so an invalid catalog cannot register them.
	for source in _catalog.keys():
		if _is_literal_parameter(String(source)): _catalog.erase(source)
	_messages = parsed.get("messages", {})
	for id in _messages:
		_pairs[String(_messages[id].vi) + "\u001f" + String(_messages[id].en)] = id
	for language in Registry.SUPPORTED:
		var path := "res://localization/locales/%s.json" % language
		var document = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		_locale_texts[language] = document.get("messages", {}) if document is Dictionary else {}
		_locale_provenance[language] = document.get("provenance", {}) if document is Dictionary else {}
	# Already rendered text can be translated again; original source keys win.
	for language in Registry.SUPPORTED:
		for id in _locale_texts[language]:
			var value := String(_locale_texts[language][id])
			if not value.is_empty() and not _is_literal_parameter(value) and not _catalog.has(value): _catalog[value] = id
	for language in Registry.SUPPORTED:
		var translation := Translation.new()
		translation.set_locale(language)
		for source in _catalog:
			translation.add_message(source, _resolved_text(String(_catalog[source]), language))
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	for source in _catalog:
		if "%" in source: _register_template(String(source))
	var preferences := _read_preferences()
	var language := Registry.normalize(String(preferences.get_value("interface", "language", "vi")))
	var override_language := Registry.normalize(OS.get_environment("MSF_QA_LOCALE"))
	if not override_language.is_empty(): language = override_language
	TranslationServer.set_locale(language if not language.is_empty() else "vi")
	Fonts.set_locale(TranslationServer.get_locale())

static func _resolved_text(id: String, language: String) -> String:
	var texts: Dictionary = _locale_texts.get(language, {})
	if texts.has(id) and not String(texts[id]).is_empty(): return String(texts[id])
	# Explicit per-message fallback, not translated coverage/native approval.
	_missing[language + ":" + id] = true
	return String(_messages.get(id, {}).get("en", ""))

static func current_locale() -> String:
	initialize()
	var language := Registry.normalize(TranslationServer.get_locale())
	return language if not language.is_empty() else "vi"

static func supported_locales() -> PackedStringArray:
	return Registry.supported_locales()

static func set_locale(language: String) -> void:
	var normalized := Registry.normalize(language)
	if normalized.is_empty(): return
	initialize()
	# Explicit Settings changes also confirm the installation-level choice.
	# Persist before applying so a failed write never promises a remembered choice.
	if not _write_language_preferences(normalized, true):
		push_warning("Language preference could not be saved.")
		return
	_apply_locale(normalized)

static func language_choice_confirmed() -> bool:
	var preferences := _read_preferences()
	var language := Registry.normalize(String(preferences.get_value("interface", "language", "")))
	return not language.is_empty() and preferences.get_value("interface", "language_confirmed", false) == true

static func confirm_language_choice(language: String) -> bool:
	var normalized := Registry.normalize(language)
	if normalized.is_empty(): return false
	initialize()
	if not _write_language_preferences(normalized, true): return false
	_apply_locale(normalized)
	return true

static func _apply_locale(normalized: String) -> void:
	if current_locale() == normalized: return
	TranslationServer.set_locale(normalized)
	Fonts.set_locale(normalized)
	_events.locale_changed.emit(normalized)

static func _read_preferences() -> ConfigFile:
	var preferences := ConfigFile.new()
	if preferences.load(_preferences_path()) != OK:
		preferences = ConfigFile.new()
		preferences.load(_preferences_path() + ".bak")
	return preferences

static func _write_language_preferences(language: String, confirmed: bool) -> bool:
	var path := _preferences_path()
	var absolute := ProjectSettings.globalize_path(path)
	# A directory or failed write must leave the chooser open, not erase data.
	if DirAccess.dir_exists_absolute(absolute): return false
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: return false
	var preferences := _read_preferences()
	preferences.set_value("interface", "language", language)
	preferences.set_value("interface", "language_confirmed", confirmed)
	var temporary := absolute + ".tmp"
	if preferences.save(temporary) != OK: return false
	var verify := ConfigFile.new()
	if verify.load(temporary) != OK or verify.get_value("interface", "language", "") != language or verify.get_value("interface", "language_confirmed", false) != confirmed:
		DirAccess.remove_absolute(temporary)
		return false
	var old := ConfigFile.new()
	var old_is_valid := old.load(absolute) == OK
	# Preserve a good backup when a damaged primary was recovered from it.
	if old_is_valid and DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
		DirAccess.remove_absolute(temporary)
		return false
	if FileAccess.file_exists(absolute) and DirAccess.remove_absolute(absolute) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		if old_is_valid: DirAccess.copy_absolute(absolute + ".bak", absolute)
		DirAccess.remove_absolute(temporary)
		return false
	return true

static func coverage(language: String = "") -> Dictionary:
	initialize()
	var locale := Registry.normalize(language if not language.is_empty() else current_locale())
	var count := 0
	var unchanged := 0
	var texts: Dictionary = _locale_texts.get(locale, {})
	for id in _messages:
		if texts.has(id) and not String(texts[id]).is_empty() and String(_locale_provenance.get(locale, {}).get(id, "")) != "explicit_unresolved_english_fallback_not_translated":
			count += 1
			if String(texts[id]) == String(_messages[id].en): unchanged += 1
	return {"translated": count, "total": _messages.size(), "fallback": _messages.size() - count, "unchanged_english": unchanged, "native_approved": locale in ["en", "vi"]}

static func text(source: String, values = []) -> String:
	# Localize the template before inserting caller-owned parameters. In particular,
	# farm names must remain literal even when they equal a catalog word such as Carrot.
	var translated := translate_message(source)
	if values is Dictionary:
		var parameter := RegEx.new()
		parameter.compile("\\{([A-Za-z][A-Za-z0-9_]*)\\}")
		var matches := parameter.search_all(translated)
		for index in range(matches.size() - 1, -1, -1):
			var found: RegExMatch = matches[index]
			var key := found.get_string(1)
			if values.has(key): translated = translated.left(found.get_start()) + str(values[key]) + translated.substr(found.get_end())
			else: push_warning("Missing named translation parameter: " + key)
		return translated
	return translated % values if values is Array and not values.is_empty() else translated

static func pair(vi: String, en: String) -> String:
	initialize()
	var source := vi if current_locale() == "vi" else en
	if _is_literal_parameter(source): return source
	var key := vi + "\u001f" + en
	if _pairs.has(key): return _resolved_text(String(_pairs[key]), current_locale())
	if _catalog.has(vi): return translate_message(vi)
	if _catalog.has(en): return translate_message(en)
	return translate_message(vi if current_locale() == "vi" else en)

static func _preferences_path() -> String:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	if not isolated_root.is_empty(): return isolated_root.path_join("ui_preferences.cfg")
	if QARichFixture.requested(): return "user://qa_rich/ui_preferences.cfg"
	return "user://ui_preferences.cfg"

static func _register_template(source: String) -> void:
	var token := RegEx.new()
	token.compile("%(?:[0-9.]+)?[dsf]")
	var matches := token.search_all(source)
	if matches.is_empty(): return
	var pattern := "^"
	var cursor := 0
	for found in matches:
		pattern += _escape_regex(source.substr(cursor, found.get_start() - cursor))
		pattern += "(-?[0-9]+(?:[.][0-9]+)?)" if found.get_string().ends_with("d") or found.get_string().ends_with("f") else "(.+?)"
		cursor = found.get_end()
	pattern += _escape_regex(source.substr(cursor)) + "$"
	var expression := RegEx.new()
	if expression.compile(pattern) == OK: _templates.append({"source": source, "regex": expression})

static func _escape_regex(value: String) -> String:
	var escaped := ""
	for character in value: escaped += "\\" + character if character in "\\.^$|?*+()[]{}" else character
	return escaped

static func _is_literal_parameter(value: String) -> bool:
	var literal := value.strip_edges()
	if literal.is_valid_int() or literal.is_valid_float(): return true
	if _literal_parameter_expression == null:
		_literal_parameter_expression = RegEx.new()
		# Also retain numeric ratios/counts and bare parameters. Templates combining
		# a word parameter with numbers remain translatable (for example %s %d/%d).
		_literal_parameter_expression.compile("^(?:(?=[0-9\\s.,:/%×+\\-]*[0-9])[0-9\\s.,:/%×+\\-]+|%(?:[0-9.]+)?s|\\{[A-Za-z][A-Za-z0-9_]*\\}|%%|(?:(?:%(?:[0-9.]+)?[df])[\\s.,:/×+\\-]*)+)$")
	return _literal_parameter_expression.search(literal) != null

static func translate_message(message: String) -> String:
	if message.is_empty() or _is_literal_parameter(message): return message
	initialize()
	if _catalog.has(message): return String(TranslationServer.translate(message))
	for template in _templates:
		var found: RegExMatch = template.regex.search(message)
		if found == null: continue
		var source_id := String(_catalog.get(template.source, ""))
		var canonical_source := String(_messages.get(source_id, {}).get("en", template.source))
		var raw_positions: Array = RAW_TEMPLATE_ARGUMENT_POSITIONS.get(canonical_source, [])
		var translated := String(TranslationServer.translate(template.source))
		var token := RegEx.new()
		token.compile("%(?:[0-9.]+)?[dsf]")
		var translated_tokens := token.search_all(translated)
		for index in range(translated_tokens.size() - 1, -1, -1):
			if index + 1 >= found.get_strings().size(): continue
			var value := found.get_string(index + 1)
			if index not in raw_positions and not _is_literal_parameter(value) and _catalog.has(value): value = String(TranslationServer.translate(value))
			var part: RegExMatch = translated_tokens[index]
			translated = translated.left(part.get_start()) + value + translated.substr(part.get_end())
		return translated
	return message
