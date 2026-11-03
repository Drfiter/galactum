extends "res://ui/panels/window.gd"
## Diálogo de confirmación genérico.


func _init() -> void:
	desired_size = Vector2(600, 300)


func window_title() -> String:
	return U.t("Confirmar")


func window_icon() -> String:
	return "ui_info"


func build() -> void:
	var l := UI.wrap(UI.label(str(args.get("text", "")), 18, UI.TEXT))
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(l)
	var h := UI.hbox(12, BoxContainer.ALIGNMENT_END)
	var no := UI.button(U.t("Cancelar"), "GhostButton", "", Vector2(150, 52))
	no.pressed.connect(close_window)
	var yes := UI.button(str(args.get("yes", U.t("Confirmar"))), str(args.get("variation", "PrimaryButton")), "ui_check", Vector2(180, 52))
	yes.pressed.connect(func() -> void:
		var cb: Callable = args.get("on_yes", Callable())
		close_window()
		if cb.is_valid():
			cb.call())
	h.add_child(no)
	h.add_child(yes)
	body.add_child(h)
