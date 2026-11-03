extends Node
## Carga y compila todos los scripts del proyecto (con autoloads activos).
func _ready() -> void:
	var files: Array = []
	_walk("res://", files)
	var bad: int = 0
	for f: String in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			print("BAD: ", f)
			bad += 1
	print("checked ", files.size(), " scripts, bad=", bad)
	get_tree().quit(1 if bad > 0 else 0)


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub: String in d.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir.path_join(sub), out)
