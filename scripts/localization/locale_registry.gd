extends RefCounted
class_name LocaleRegistry

# Locale preferences do not belong to farm slots. Translations beyond VI/EN
# are drafts until a native-language reviewer approves their catalog.
const SUPPORTED := ["vi", "en", "th", "ms", "id", "zh_CN", "ja", "ko", "ru", "es", "pt_BR", "de", "fr", "pl"]
const DEFINITIONS := {
	"vi": {"native": "Tiếng Việt", "title": "Nông Trại Của Em Gái", "lines": ["Nông Trại", "Của Em Gái"]},
	"en": {"native": "English", "title": "My Little Sister’s Farm", "lines": ["My Little Sister’s", "Farm"]},
	"th": {"native": "ไทย", "title": "ฟาร์มของน้องสาวฉัน", "lines": ["ฟาร์มของ", "น้องสาวฉัน"]},
	"ms": {"native": "Bahasa Melayu", "title": "Ladang Adik Perempuan Saya", "lines": ["Ladang Adik", "Perempuan Saya"]},
	"id": {"native": "Bahasa Indonesia", "title": "Ladang Adik Perempuanku", "lines": ["Ladang Adik", "Perempuanku"]},
	"zh_CN": {"native": "简体中文", "title": "妹妹的农场", "lines": ["妹妹的", "农场"]},
	"ja": {"native": "日本語", "title": "妹の農場", "lines": ["妹の", "農場"]},
	"ko": {"native": "한국어", "title": "여동생의 농장", "lines": ["여동생의", "농장"]},
	"ru": {"native": "Русский", "title": "Ферма моей младшей сестры", "lines": ["Ферма моей", "младшей сестры"]},
	"es": {"native": "Español", "title": "La granja de mi hermanita", "lines": ["La granja de mi", "hermanita"]},
	"pt_BR": {"native": "Português (Brasil)", "title": "A fazenda da minha irmãzinha", "lines": ["A fazenda da", "minha irmãzinha"]},
	"de": {"native": "Deutsch", "title": "Die Farm meiner kleinen Schwester", "lines": ["Die Farm meiner", "kleinen Schwester"]},
	"fr": {"native": "Français", "title": "La ferme de ma petite sœur", "lines": ["La ferme de ma", "petite sœur"]},
	"pl": {"native": "Polski", "title": "Farma mojej młodszej siostry", "lines": ["Farma mojej", "młodszej siostry"]},
}


static func supported_locales() -> PackedStringArray:
	return PackedStringArray(SUPPORTED)


static func normalize(language: String) -> String:
	var value := language.strip_edges().replace("-", "_")
	if value in SUPPORTED:
		return value
	var lower := value.to_lower()
	if lower == "pt" or lower.begins_with("pt_"):
		return "pt_BR"
	if lower == "zh" or lower.begins_with("zh_"):
		return "zh_CN"
	var base := lower.get_slice("_", 0)
	return base if base in SUPPORTED else ""


static func native_name(language: String) -> String:
	return String(DEFINITIONS.get(normalize(language), DEFINITIONS.vi).native)


static func game_title(language: String = "") -> String:
	var locale := normalize(language if not language.is_empty() else TranslationServer.get_locale())
	return String(DEFINITIONS.get(locale, DEFINITIONS.vi).title)


static func title_lines(language: String = "") -> PackedStringArray:
	var locale := normalize(language if not language.is_empty() else TranslationServer.get_locale())
	return PackedStringArray(DEFINITIONS.get(locale, DEFINITIONS.vi).lines)
