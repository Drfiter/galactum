extends "res://ui/panels/window.gd"
## Misiones de historia + evento rotativo "Órdenes del Día" (Equipo 5).


func _init() -> void:
	desired_size = Vector2(980, 600)
	live_refresh = 1.0


func window_title() -> String:
	return U.t("Misiones y eventos")


func window_icon() -> String:
	return "ui_missions"


func on_player_updated() -> void:
	rebuild()


func build() -> void:
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(_story_card())
	row.add_child(_daily_card())


func _story_card() -> Control:
	var s: Dictionary = GameClient.me.get("story", {})
	var card := UI.panel("CardHi")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10)
	card.add_child(v)
	v.add_child(UI.label(U.t("HISTORIA DEL COMANDANTE"), 14, UI.CYAN, "bold"))
	if s.is_empty():
		v.add_child(UI.label(U.t("¡Completaste todas las misiones de la demo!"), 18, UI.GREEN, "bold"))
		return card
	v.add_child(UI.label(U.t("Misión %d de %d") % [int(s.get("index", 0)) + 1, int(s.get("total", 1))], 14, UI.TEXT_DIM))
	v.add_child(UI.wrap(UI.label(str(s.get("title", "")), 24, UI.TEXT, "bold")))
	v.add_child(UI.wrap(UI.label(str(s.get("desc", "")), 16, UI.TEXT_DIM)))
	var prog: int = int(s.get("progress", 0))
	var target: int = int(s.get("target", 1))
	var done: bool = prog >= target
	v.add_child(UI.progress(minf(prog, target), target, UI.GOLD if done else UI.CYAN, 16))
	v.add_child(UI.label("%s / %s" % [U.fmt_num(mini(prog, target)), U.fmt_num(target)], 15, UI.TEXT, "semibold"))
	v.add_child(UI.label(U.t("Recompensa"), 14, UI.GOLD, "bold"))
	v.add_child(UI.reward_row(s.get("reward", {}), 16))
	v.add_child(UI.spacer())
	var b := UI.button(U.t("¡Reclamar recompensa!") if done else U.t("Ir a la misión"), "GoldButton" if done else "PrimaryButton", "ui_gift" if done else "ui_target", Vector2(0, 58))
	b.pressed.connect(func() -> void:
		close_window()
		if done:
			game.claim_story()
		else:
			game.goto_mission(s))
	v.add_child(b)
	return card


func _daily_card() -> Control:
	var d: Dictionary = GameClient.me.get("daily", {})
	var card := UI.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10)
	card.add_child(v)
	var h := UI.hbox(8)
	h.add_child(UI.icon("ui_trophy", 26, UI.PURPLE))
	h.add_child(UI.label(str(d.get("name", U.t("Órdenes del Día"))).to_upper(), 16, UI.PURPLE, "bold"))
	h.add_child(UI.spacer())
	var rem: float = float(int(d.get("ends_at", 0)) - GameClient.server_now()) / 1000.0
	h.add_child(UI.label(U.t("Termina en ") + U.fmt_time(rem), 14, UI.TEXT_DIM))
	v.add_child(h)
	v.add_child(UI.wrap(UI.label(U.t("Evento rotativo de 3 horas: suma puntos minando, cazando, entrenando, mejorando, investigando y venciendo en combate."), 14, UI.TEXT_DIM)))
	var pts: int = int(d.get("points", 0))
	var tiers: Array = d.get("tiers", [])
	var claimed: Array = d.get("claimed", [])
	v.add_child(UI.label(U.t("%s puntos") % U.fmt_int(pts), 26, UI.TEXT, "title"))
	for i: int in range(tiers.size()):
		var t: Dictionary = tiers[i]
		var row := UI.panel("Card")
		var rh := UI.hbox(10)
		row.add_child(rh)
		rh.add_child(UI.label(U.t("Nivel %d") % (i + 1), 15, UI.PURPLE, "bold"))
		var cv := UI.vbox(4)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.progress(minf(pts, float(t["points"])), float(t["points"]), UI.PURPLE, 8))
		cv.add_child(UI.reward_row(t.get("reward", {}), 14))
		rh.add_child(cv)
		var is_claimed: bool = claimed.has(i) or claimed.has(float(i))
		if is_claimed:
			rh.add_child(UI.icon("ui_check", 30, UI.GREEN))
		else:
			var b := UI.button(U.t("%d pts") % int(t["points"]) if pts < int(t["points"]) else U.t("Reclamar"), "GoldButton" if pts >= int(t["points"]) else "GhostButton", "", Vector2(120, 44))
			b.disabled = pts < int(t["points"])
			var idx: int = i
			b.pressed.connect(func() -> void:
				send("claim_daily", {"tier": idx}, func(p: Dictionary) -> void: game.show_reward(p.get("reward", {}), U.t("Órdenes del Día · Nivel %d") % (idx + 1))))
			rh.add_child(b)
		v.add_child(row)
	return card
