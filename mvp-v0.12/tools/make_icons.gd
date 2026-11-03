extends SceneTree
## Rasteriza el ícono SVG a los PNG que pide Android (lanzador y adaptativo).
func _init() -> void:
	var svg: String = FileAccess.get_file_as_string("res://icon.svg")
	var fg: String = FileAccess.get_file_as_string("res://assets/android/icon_fg.svg")
	for spec: Array in [["res://assets/android/icon_192.png", 192, 0.75], ["res://assets/android/icon_512.png", 512, 2.0]]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(spec[2]))
		img.save_png(spec[0])
	var fimg := Image.new()
	fimg.load_svg_from_string(fg, 1.6875)
	fimg.save_png("res://assets/android/icon_foreground_432.png")
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(Color("060a1a"))
	bg.save_png("res://assets/android/icon_background_432.png")
	print("icons ok")
	quit()
