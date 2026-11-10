extends Node
## Catálogos data-driven de Galactum (Equipo 2/3/5: "todo es catálogo + instancia").
## Ningún número de balance vive en el código: se leen desde res://data/*.json.
## Lo usan por igual el servidor autoritativo (SGM/SSS) y el cliente (para mostrar costos).

var elements: Array = []          # 10 elementos de construcción
var currencies: Array = []        # créditos, materia oscura, energía, plasma
var element_ids: PackedStringArray = []
var mining_element_ids: PackedStringArray = []
var resource_info: Dictionary = {} # id -> {name, short, color, source}

var troops: Dictionary = {}
var troop_order: PackedStringArray = []
var rooms_data: Dictionary = {}
var rooms_by_id: Dictionary = {}
var room_order: PackedStringArray = []
var research: Dictionary = {}
var techs_by_id: Dictionary = {}
var xeno: Dictionary = {}
var species_by_id: Dictionary = {}
var asteroids: Dictionary = {}
var items: Dictionary = {}
var items_by_id: Dictionary = {}
var missions: Dictionary = {}
var world: Dictionary = {}
var portraits: Dictionary = {}
var shop: Dictionary = {}
var events: Dictionary = {}
var crew: Dictionary = {}
var commander: Dictionary = {}
var armory: Dictionary = {}
var alliance: Dictionary = {}
var liveops: Dictionary = {}
var expeditions: Dictionary = {}
var materials_by_id: Dictionary = {}
var equipment_by_id: Dictionary = {}


const U = preload("res://shared/util.gd")
const I18n = preload("res://shared/i18n.gd")
const LOCALIZED_KEYS: Array = ["name", "desc", "title", "label", "branch", "phase", "badge"]


func _init() -> void:
	I18n.setup(_read)
	reload()


## Traduce in situ los textos de un catálogo al idioma activo.
func _localize(o: Variant) -> Variant:
	if o is Dictionary:
		for k: Variant in (o as Dictionary).keys():
			var v: Variant = o[k]
			if v is String and LOCALIZED_KEYS.has(str(k)):
				o[k] = tr(v)
			elif v is Dictionary or v is Array:
				_localize(v)
	elif o is Array:
		for i: int in range((o as Array).size()):
			if o[i] is Dictionary or o[i] is Array:
				_localize(o[i])
	return o


func reload() -> void:
	var el: Dictionary = _read("catalog_elements")
	elements = el.get("elements", [])
	currencies = el.get("currencies", [])
	element_ids = PackedStringArray()
	mining_element_ids = PackedStringArray()
	resource_info.clear()
	for e: Dictionary in elements:
		element_ids.append(e["id"])
		if e.get("source", "") == "mining":
			mining_element_ids.append(e["id"])
		resource_info[e["id"]] = e
	for c: Dictionary in currencies:
		resource_info[c["id"]] = c

	troops = _read("catalog_troops")
	troop_order = PackedStringArray(troops.get("order", []))

	rooms_data = _read("catalog_rooms")
	rooms_by_id.clear()
	room_order = PackedStringArray()
	for r: Dictionary in rooms_data.get("rooms", []):
		rooms_by_id[r["id"]] = r
		room_order.append(r["id"])

	research = _read("catalog_research")
	techs_by_id.clear()
	for t: Dictionary in research.get("techs", []):
		techs_by_id[t["id"]] = t

	xeno = _read("catalog_xenoforms")
	species_by_id.clear()
	for s: Dictionary in xeno.get("species", []):
		species_by_id[s["id"]] = s

	asteroids = _read("catalog_asteroids")
	items = _read("catalog_items")
	items_by_id.clear()
	for it: Dictionary in items.get("items", []):
		items_by_id[it["id"]] = it
	missions = _read("catalog_missions")
	world = _read("config_world")
	portraits = _read("catalog_portraits").get("portraits", {})
	shop = _read("catalog_shop")
	events = _read("catalog_events")
	crew = _read("catalog_crew")
	commander = _read("catalog_commander")
	armory = _read("catalog_armory")
	alliance = _read("catalog_alliance")
	liveops = _read("catalog_liveops")
	expeditions = _read("catalog_expeditions")
	materials_by_id.clear()
	for m: Dictionary in armory.get("materials", []):
		materials_by_id[m["id"]] = m
	equipment_by_id.clear()
	for e: Dictionary in armory.get("equipment", []):
		equipment_by_id[e["id"]] = e


func _read(catalog_name: String) -> Dictionary:
	var raw: Dictionary = _read_raw(catalog_name)
	if catalog_name.begins_with("i18n_"):
		return raw
	return _localize(raw)


func _read_raw(catalog_name: String) -> Dictionary:
	var path: String = "res://data/%s.json" % catalog_name
	var text: String = ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	if text.is_empty() and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is JSON:
			var d: Variant = (res as JSON).data
			return d if d is Dictionary else {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("Catálogo inválido: %s" % path)
	return {}


# ---------------------------------------------------------------- recursos

func res_name(id: String) -> String:
	if items_by_id.has(id):
		return str(items_by_id[id]["name"])
	if materials_by_id.has(id):
		return str(materials_by_id[id]["name"])
	return str(resource_info.get(id, {}).get("name", id))


func res_color(id: String) -> Color:
	return Color(str(resource_info.get(id, {}).get("color", "#ffffff")))


func is_resource(id: String) -> bool:
	return resource_info.has(id)


# ---------------------------------------------------------------- tropas

## Clave de stack: "<tipo>_<nivel>", p. ej. "infantry_1".
func troop_key(type_id: String, tier: int) -> String:
	return "%s_%d" % [type_id, tier]


func split_troop_key(key: String) -> Array:
	var idx: int = key.rfind("_")
	return [key.substr(0, idx), int(key.substr(idx + 1))]


func troop_type(type_id: String) -> Dictionary:
	return troops.get("types", {}).get(type_id, {})


func troop_tier(key: String) -> Dictionary:
	var parts: Array = split_troop_key(key)
	var t: Dictionary = troop_type(parts[0])
	for tier: Dictionary in t.get("tiers", []):
		if int(tier["tier"]) == int(parts[1]):
			return tier
	return {}


func troop_stat(key: String, stat: String) -> float:
	return float(troop_tier(key).get("stats", {}).get(stat, 0.0))


func troop_name(key: String) -> String:
	var parts: Array = split_troop_key(key)
	return U.t("%s N%d") % [troop_type(parts[0]).get("name", parts[0]), parts[1]]


func all_troop_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for type_id: String in troop_order:
		for tier: Dictionary in troop_type(type_id).get("tiers", []):
			keys.append(troop_key(type_id, int(tier["tier"])))
	return keys


# ---------------------------------------------------------------- salas

func room(id: String) -> Dictionary:
	return rooms_by_id.get(id, {})


func room_max_level() -> int:
	return int(rooms_data.get("max_level", 10))


## Costo para subir la sala AL nivel `target_level`.
func room_cost(id: String, target_level: int) -> Dictionary:
	var r: Dictionary = room(id)
	var mult: float = _curve(float(r.get("growth", 1.5)), float(rooms_data.get("late_growth", 1.18)), target_level)
	var out: Dictionary = {}
	for k: String in r.get("cost", {}):
		out[k] = int(round(float(r["cost"][k]) * mult / 10.0) * 10)
	return out


func room_time(id: String, target_level: int) -> int:
	var r: Dictionary = room(id)
	return int(round(float(r.get("time", 20)) * _curve(float(r.get("time_growth", 1.6)), float(rooms_data.get("late_time_growth", 1.22)), target_level)))


## Crecimiento exponencial hasta late_level y más suave después (niveles 11-25).
func _curve(early: float, late: float, target_level: int) -> float:
	var cut: int = int(rooms_data.get("late_level", 10))
	var n_early: int = mini(target_level, cut) - 1
	var n_late: int = maxi(0, target_level - cut)
	return pow(early, n_early) * pow(late, n_late)


func room_effect(id: String, effect: String, level: int) -> float:
	var e: Dictionary = room(id).get("effects", {}).get(effect, {})
	if e.is_empty():
		return 0.0
	var v: float = float(e.get("base", 0)) + float(e.get("per_level", 0)) * (level - 1)
	if bool(e.get("floor", false)):
		v = floorf(v)
	if e.has("max"):
		v = minf(v, float(e["max"]))
	return v


## Producción por minuto de un recurso en una sala productora.
func room_production(id: String, level: int) -> Dictionary:
	var out: Dictionary = {}
	var prod: Dictionary = room(id).get("produces", {})
	for res_id: String in prod:
		out[res_id] = float(prod[res_id]["base"]) + float(prod[res_id]["per_level"]) * (level - 1)
	return out


# ---------------------------------------------------------------- investigación

func tech(id: String) -> Dictionary:
	return techs_by_id.get(id, {})


func tech_cost(id: String, target_level: int) -> Dictionary:
	var mult: float = pow(float(research.get("growth", 1.6)), target_level - 1)
	var base_mult: float = float(tech(id).get("cost_mult", 1.0))
	var out: Dictionary = {}
	for k: String in research.get("cost", {}):
		out[k] = int(round(float(research["cost"][k]) * mult * base_mult / 10.0) * 10)
	return out


func tech_time(id: String, target_level: int) -> int:
	var base_mult: float = float(tech(id).get("cost_mult", 1.0))
	return int(round(float(research.get("time", 20)) * base_mult * pow(float(research.get("time_growth", 1.7)), target_level - 1)))


# ---------------------------------------------------------------- PvE y mapa

func xeno_level(level: int) -> Dictionary:
	for l: Dictionary in xeno.get("levels", []):
		if int(l["level"]) == level:
			return l
	return {}


func asteroid_level(level: int) -> Dictionary:
	for l: Dictionary in asteroids.get("levels", []):
		if int(l["level"]) == level:
			return l
	return {}


func item(id: String) -> Dictionary:
	return items_by_id.get(id, {})


## Valor "opaco" en Materia Oscura de `qty` unidades de un recurso u objeto.
func value_mo(id: String, qty: float = 1.0) -> float:
	return float(shop.get("value_mo", {}).get(id, 0.0)) * qty


func value_usd(id: String, qty: float = 1.0) -> float:
	return value_mo(id, qty) / float(shop.get("usd_to_mo", 100))


## Valor en MO de una unidad de tropa (receta de entrenamiento valorizada).
func troop_value_mo(key: String) -> float:
	return bundle_value_mo(troop_tier(key).get("recipe", {}))


func troops_value_mo(stacks: Dictionary) -> float:
	var v: float = 0.0
	for k: String in stacks:
		v += troop_value_mo(k) * float(stacks[k])
	return v


func bundle_value_mo(bundle: Dictionary) -> float:
	var v: float = 0.0
	for k: String in bundle:
		v += value_mo(k, float(bundle[k]))
	return v


func cfg(key: String, default: Variant = null) -> Variant:
	return world.get(key, default)
