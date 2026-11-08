extends RefCounted
## Utilidades puras compartidas (formato, tiempo, ids, aritmética de recursos).


## Desfase de reloj solo para tests (simula el paso del tiempo sin esperar).
static var debug_offset_ms: int = 0


## Traducción (i18n): la clave es el texto en español; inglés por defecto.
static func t(text: String) -> String:
	return TranslationServer.translate(text)


## Separador de miles según el idioma activo: "1,500" en inglés, "1.500" en español.
static func thousands_sep() -> String:
	return "." if TranslationServer.get_locale().begins_with("es") else ","


## Separador decimal según el idioma activo: "1.5K" en inglés, "1,5K" en español.
static func decimal_sep() -> String:
	return "," if TranslationServer.get_locale().begins_with("es") else "."


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + debug_offset_ms


static func fmt_num(value: float) -> String:
	var v: float = absf(value)
	var sign: String = "-" if value < 0 else ""
	if v >= 1_000_000_000.0:
		return "%s%.1fB" % [sign, v / 1_000_000_000.0]
	if v >= 1_000_000.0:
		return "%s%.1fM" % [sign, v / 1_000_000.0]
	if v >= 10_000.0:
		return "%s%.0fK" % [sign, v / 1000.0]
	if v >= 1000.0:
		return "%s%.1fK" % [sign, v / 1000.0]
	return "%s%d" % [sign, int(v)]


static func fmt_int(value: int) -> String:
	var s: String = str(absi(value))
	var sep: String = thousands_sep()
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if value < 0 else "") + out


static func fmt_time(seconds: float) -> String:
	var total: int = maxi(0, ceili(seconds))
	var h: int = total / 3600
	var m: int = (total % 3600) / 60
	var s: int = total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]


static func fmt_duration_short(seconds: float) -> String:
	var total: int = maxi(0, ceili(seconds))
	if total >= 3600:
		return "%dh %02dm" % [total / 3600, (total % 3600) / 60]
	if total >= 60:
		return "%dm %02ds" % [total / 60, total % 60]
	return "%ds" % total


static func new_id(prefix: String = "") -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	return prefix + bytes.hex_encode()


static func dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


static func v2(arr: Variant) -> Vector2:
	if arr is Vector2:
		return arr
	if arr is Vector2i:
		return Vector2(arr)
	if arr is Array and arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


static func arr2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


## Posición derivada del tiempo (spec GAL3-001: se deriva, no se integra).
static func lerp_path(origin: Vector2, target: Vector2, depart_ts: int, arrive_ts: int, now: int) -> Vector2:
	var span: int = arrive_ts - depart_ts
	if span <= 0:
		return target
	var t: float = clampf(float(now - depart_ts) / float(span), 0.0, 1.0)
	return origin.lerp(target, t)


static func add_into(target: Dictionary, delta: Dictionary, factor: float = 1.0) -> void:
	for k: String in delta:
		target[k] = int(target.get(k, 0)) + int(round(float(delta[k]) * factor))


static func sum_values(d: Dictionary) -> int:
	var total: int = 0
	for k: String in d:
		total += int(d[k])
	return total


static func hash_seed(text: String) -> int:
	return int(text.hash()) & 0x7fffffff
