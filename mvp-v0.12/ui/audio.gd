extends Node
## Efectos de sonido y música del cliente.
##
## No es un Autoload: el primer `Sfx.play()` crea un único nodo "GalactumAudio"
## bajo la raíz del árbol, que sobrevive al cambio entre el título y la partida
## (la música no se corta) y solo existe en el cliente, nunca en el servidor
## dedicado. Los sonidos se generan con tools/gen_audio.py.

const SETTINGS_PATH: String = "user://settings.cfg"
const NODE_NAME: String = "GalactumAudio"
const VOICES: int = 6
## Un mismo efecto no se repite antes de este intervalo (evita saturar con,
## por ejemplo, diez explosiones en el mismo cuadro).
const MIN_GAP_MS: int = 60

const SOUNDS: Dictionary = {
	"click": preload("res://assets/audio/click.wav"),
	"collect": preload("res://assets/audio/collect.wav"),
	"upgrade": preload("res://assets/audio/upgrade.wav"),
	"launch": preload("res://assets/audio/launch.wav"),
	"laser": preload("res://assets/audio/laser.wav"),
	"explosion": preload("res://assets/audio/explosion.wav"),
	"alert": preload("res://assets/audio/alert.wav"),
	"reward": preload("res://assets/audio/reward.wav"),
	"error": preload("res://assets/audio/error.wav"),
}
const MUSIC: AudioStream = preload("res://assets/audio/music_ambient.wav")

var sfx_enabled: bool = true
var music_enabled: bool = true
var played: Dictionary = {}   # nombre -> veces reproducido (diagnóstico y pruebas)
var _voices: Array = []
var _next: int = 0
var _last_ms: Dictionary = {}
var _music: AudioStreamPlayer


## Nodo de audio compartido; se crea la primera vez que se usa.
static func get_instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless" and OS.has_feature("dedicated_server"):
		return null
	var node: Node = tree.root.get_node_or_null(NODE_NAME)
	if node == null:
		node = (load("res://ui/audio.gd") as GDScript).new()
		node.name = NODE_NAME
		tree.root.add_child(node)
	return node


## Reproduce un efecto por nombre ("click", "collect", "launch"...).
static func play(sound: String, volume_db: float = 0.0) -> void:
	var a: Node = get_instance()
	if a != null:
		a._play(sound, volume_db)


## Inicia la música de fondo en bucle (si está activada en Ajustes).
static func start_music() -> void:
	var a: Node = get_instance()
	if a != null:
		a._start_music()


func _init() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sfx_enabled = bool(cfg.get_value("audio", "sfx", true))
		music_enabled = bool(cfg.get_value("audio", "music", true))
	for i: int in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)
	var wav := MUSIC as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))


func _play(sound: String, volume_db: float) -> void:
	if not sfx_enabled or not SOUNDS.has(sound):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -100000)) < MIN_GAP_MS:
		return
	_last_ms[sound] = now
	var p: AudioStreamPlayer = _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = SOUNDS[sound]
	p.volume_db = volume_db
	p.play()
	played[sound] = int(played.get(sound, 0)) + 1


func _start_music() -> void:
	if music_enabled and not _music.playing:
		_music.stream = MUSIC
		_music.play()


func is_music_playing() -> bool:
	return _music.playing


func set_sfx_enabled(on: bool) -> void:
	sfx_enabled = on
	_save()


func set_music_enabled(on: bool) -> void:
	music_enabled = on
	if on:
		_start_music()
	else:
		_music.stop()
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "sfx", sfx_enabled)
	cfg.set_value("audio", "music", music_enabled)
	cfg.save(SETTINGS_PATH)
