extends RefCounted
## Multi-idioma (feedback de revisión: inglés por defecto + selector en ajustes).
## Las claves son los textos originales en español; `data/i18n_en.json` trae la
## traducción al inglés. Los Label/Button de Godot se traducen solos; los textos
## con formato pasan por `U.t()` antes de formatear.

const SETTINGS_PATH: String = "user://settings.cfg"
const LOCALES: Array = [["en", "English"], ["es", "Español"]]

static var _ready: bool = false


static func setup(read_json: Callable) -> void:
	if _ready:
		return
	_ready = true
	var d: Dictionary = read_json.call("i18n_en")
	var t := Translation.new()
	t.locale = "en"
	for k: String in d:
		if not k.begins_with("_"):
			t.add_message(k, str(d[k]))
	TranslationServer.add_translation(t)
	# Sin esto Godot cae al inglés cuando el idioma elegido no tiene traducción
	# (las claves ya están en español).
	ProjectSettings.set_setting("internationalization/locale/fallback", "es")
	TranslationServer.set_locale(saved_locale())


static func saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return str(cfg.get_value("general", "locale", "en"))
	return "en"


static func current() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("general", "locale", locale)
	cfg.save(SETTINGS_PATH)
