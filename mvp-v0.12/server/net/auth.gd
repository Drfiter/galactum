extends RefCounted
## Cuentas del servidor dedicado (feedback del 26/10: "no hay backend real:
## login, registro, JWT"). Alcance del MVP, sin NestJS/PostgreSQL:
##
## - Registro e inicio de sesión con usuario y contraseña. La contraseña nunca
##   se guarda: se almacena PBKDF2-HMAC-SHA256 con sal aleatoria por cuenta.
## - Token de acceso JWT HS256 de vida corta (`sub` = player_id) que exige el
##   `hello` del SSS dedicado.
## - Token de renovación aleatorio de un solo uso (rotación): se guarda solo su
##   hash SHA-256 y caduca a los 30 días; `logout` lo revoca.
## - El secreto de firma sale de la variable de entorno GALACTUM_JWT_SECRET. Si
##   no existe se genera uno aleatorio por proceso (los tokens de acceso dejan
##   de valer al reiniciar; los de renovación siguen sirviendo). Nunca se
##   versiona un secreto en el repositorio.
## - Intentos fallidos limitados por cuenta (bloqueo temporal).

const U = preload("res://shared/util.gd")

const PBKDF2_ITERATIONS: int = 4000
const ACCESS_TTL_SEC: int = 15 * 60
const REFRESH_TTL_SEC: int = 30 * 24 * 3600
const MAX_FAILED: int = 5
const LOCK_SEC: int = 300
const ISSUER: String = "galactum-sss"

var srv: Node
var _secret: PackedByteArray
var _crypto := Crypto.new()


func _init(server: Node) -> void:
	srv = server
	var env: String = OS.get_environment("GALACTUM_JWT_SECRET")
	if env.length() >= 32:
		_secret = env.to_utf8_buffer()
	else:
		_secret = _crypto.generate_random_bytes(32)


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func accounts() -> Dictionary:
	if not srv.state.has("accounts"):
		srv.state["accounts"] = {}
	return srv.state["accounts"]


# ---------------------------------------------------------------- primitivas

static func b64url(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")


static func b64url_decode(text: String) -> PackedByteArray:
	var s: String = text.replace("-", "+").replace("_", "/")
	while s.length() % 4 != 0:
		s += "="
	return Marshalls.base64_to_raw(s)


func hmac(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	return _crypto.hmac_digest(HashingContext.HASH_SHA256, key, msg)


static func sha256_hex(text: String) -> String:
	return text.sha256_text()


## PBKDF2-HMAC-SHA256 con un solo bloque (32 bytes de salida).
func pbkdf2(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var key: PackedByteArray = password.to_utf8_buffer()
	var block: PackedByteArray = salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u: PackedByteArray = hmac(key, block)
	var out: PackedByteArray = u.duplicate()
	for _i: int in range(iterations - 1):
		u = hmac(key, u)
		for j: int in range(out.size()):
			out[j] = out[j] ^ u[j]
	return out


## Comparación en tiempo constante.
static func same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff: int = 0
	for i: int in range(a.size()):
		diff |= a[i] ^ b[i]
	return diff == 0


func jwt_sign(payload: Dictionary) -> String:
	var head: String = b64url(JSON.stringify({"alg": "HS256", "typ": "JWT"}).to_utf8_buffer())
	var body: String = b64url(JSON.stringify(payload).to_utf8_buffer())
	var sig: String = b64url(hmac(_secret, (head + "." + body).to_utf8_buffer()))
	return head + "." + body + "." + sig


## Devuelve el payload si la firma y la vigencia son válidas; si no, {}.
func jwt_verify(token: String) -> Dictionary:
	var parts: PackedStringArray = token.split(".")
	if parts.size() != 3:
		return {}
	var header: Variant = JSON.parse_string(b64url_decode(parts[0]).get_string_from_utf8())
	if not (header is Dictionary) or str(header.get("alg", "")) != "HS256":
		return {}
	var expected: PackedByteArray = hmac(_secret, (parts[0] + "." + parts[1]).to_utf8_buffer())
	if not same(expected, b64url_decode(parts[2])):
		return {}
	var payload: Variant = JSON.parse_string(b64url_decode(parts[1]).get_string_from_utf8())
	if not (payload is Dictionary):
		return {}
	var now_s: int = int(U.now_ms() / 1000)
	if int(payload.get("exp", 0)) <= now_s or str(payload.get("iss", "")) != ISSUER:
		return {}
	return payload


# ---------------------------------------------------------------- cuentas

static func valid_username(u: String) -> bool:
	if u.length() < 3 or u.length() > 18:
		return false
	var re := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	return re.search(u) != null


func register(username: String, password: String, avatar: String) -> Dictionary:
	username = username.strip_edges()
	if not valid_username(username):
		return _err("BAD_USERNAME", U.t("El usuario debe tener de 3 a 18 letras, números o guion bajo"))
	if password.length() < 8:
		return _err("WEAK_PASSWORD", U.t("La contraseña debe tener al menos 8 caracteres"))
	var key: String = username.to_lower()
	if accounts().has(key) or not srv.find_human_by_name(username).is_empty():
		return _err("TAKEN", U.t("Ese nombre de usuario ya existe"))
	var salt: PackedByteArray = _crypto.generate_random_bytes(16)
	var p: Dictionary = srv.create_human(username, avatar if not avatar.is_empty() else "p01")
	accounts()[key] = {
		"username": username, "player_id": p["id"], "salt": Marshalls.raw_to_base64(salt), "iter": PBKDF2_ITERATIONS,
		"hash": Marshalls.raw_to_base64(pbkdf2(password, salt, PBKDF2_ITERATIONS)), "created": U.now_ms(),
		"refresh": {}, "failed": 0, "locked_until": 0,
	}
	return _issue(accounts()[key])


func login(username: String, password: String) -> Dictionary:
	var a: Dictionary = accounts().get(username.strip_edges().to_lower(), {})
	var now: int = U.now_ms()
	if a.is_empty():
		# Mismo mensaje que con contraseña errónea: no revela qué usuarios existen.
		return _err("BAD_CREDENTIALS", U.t("Usuario o contraseña incorrectos"))
	if int(a.get("locked_until", 0)) > now:
		return _err("LOCKED", U.t("Demasiados intentos fallidos. Prueba en %s") % U.fmt_time(float(int(a["locked_until"]) - now) / 1000.0))
	var got: PackedByteArray = pbkdf2(password, Marshalls.base64_to_raw(str(a["salt"])), int(a.get("iter", PBKDF2_ITERATIONS)))
	if not same(got, Marshalls.base64_to_raw(str(a["hash"]))):
		a["failed"] = int(a.get("failed", 0)) + 1
		if int(a["failed"]) >= MAX_FAILED:
			a["failed"] = 0
			a["locked_until"] = now + LOCK_SEC * 1000
		return _err("BAD_CREDENTIALS", U.t("Usuario o contraseña incorrectos"))
	a["failed"] = 0
	return _issue(a)


func refresh(token: String) -> Dictionary:
	var h: String = sha256_hex(token)
	var now: int = U.now_ms()
	for key: String in accounts():
		var a: Dictionary = accounts()[key]
		var rt: Dictionary = a.get("refresh", {})
		if rt.has(h):
			var exp: int = int(rt[h])
			rt.erase(h)  # rotación: cada token de renovación sirve una sola vez
			if exp <= now:
				return _err("EXPIRED", U.t("La sesión expiró: inicia sesión de nuevo"))
			return _issue(a)
	return _err("BAD_TOKEN", U.t("Sesión no válida: inicia sesión de nuevo"))


func logout(token: String) -> Dictionary:
	var h: String = sha256_hex(token)
	for key: String in accounts():
		(accounts()[key].get("refresh", {}) as Dictionary).erase(h)
	return {"ok": true}


func _issue(a: Dictionary) -> Dictionary:
	var now_s: int = int(U.now_ms() / 1000)
	var access: String = jwt_sign({"sub": a["player_id"], "name": a["username"], "iss": ISSUER, "iat": now_s, "exp": now_s + ACCESS_TTL_SEC})
	var rtoken: String = b64url(_crypto.generate_random_bytes(32))
	var rt: Dictionary = a.get("refresh", {})
	# Limpia los vencidos y limita las sesiones abiertas por cuenta.
	var now: int = U.now_ms()
	for h: String in rt.keys():
		if int(rt[h]) <= now:
			rt.erase(h)
	while rt.size() >= 5:
		rt.erase(rt.keys()[0])
	rt[sha256_hex(rtoken)] = now + REFRESH_TTL_SEC * 1000
	a["refresh"] = rt
	return {"ok": true, "access_token": access, "refresh_token": rtoken, "expires_in": ACCESS_TTL_SEC, "username": a["username"], "player_id": a["player_id"]}


## player_id del token de acceso, o "" si no es válido.
func player_from_token(token: String) -> String:
	var payload: Dictionary = jwt_verify(token)
	if payload.is_empty():
		return ""
	var pid: String = str(payload.get("sub", ""))
	return pid if not srv.player(pid).is_empty() else ""
