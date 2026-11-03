extends "res://ui/panels/window.gd"
## Ventana de recompensa obtenida.


func _init() -> void:
	desired_size = Vector2(620, 380)


func window_title() -> String:
	return U.t("¡Recompensa!")


func window_icon() -> String:
	return "ui_gift"


func build() -> void:
	var t := UI.wrap(UI.label(str(args.get("title", "")), 20, UI.GOLD, "bold"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	var c := UI.panel("CardGold")
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	c.add_child(center)
	var row := UI.reward_row(args.get("reward", {}), 22)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.x = 520
	center.add_child(row)
	body.add_child(c)
	var ok := UI.button(U.t("¡Genial!"), "GoldButton", "ui_check", Vector2(220, 56))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_window)
	body.add_child(ok)
