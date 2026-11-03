extends "res://ui/panels/window.gd"
## Bono de inicio de sesión: cada ciclo de 24 h una caja de ~US$1 en objetos,
## armada por una función aleatoria sobre un pool de "regalos de centavos".


func _init() -> void:
	desired_size = Vector2(1060, 560)


func window_title() -> String:
	return U.t("Bono diario de inicio de sesión")


func window_icon() -> String:
	return "ui_calendar"


func on_player_updated() -> void:
	rebuild()


func build() -> void:
	live_refresh = 1.0
	var st: Dictionary = GameClient.me.get("shop", {}).get("login", {})
	var days: int = int(st.get("days", 7))
	var day: int = int(st.get("day", 0))
	var available: bool = bool(st.get("available", false))
	var budgets: Array = st.get("budgets_usd", [])
	body.add_child(UI.wrap(UI.label(U.t("Inicia sesión cada día para recibir una caja de suministros. Cada caja vale cerca de US$1 en objetos al azar; el día 7 trae un premio mayor y un Salto Warp garantizado."), 15, UI.TEXT_DIM)))
	var row := UI.hbox(10, BoxContainer.ALIGNMENT_CENTER)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for i: int in range(days):
		var is_today: bool = i == day
		var done: bool = i < day
		var style: String = "CardGold" if (is_today and available) else ("CardHi" if is_today else "Card")
		var card := UI.panel(style)
		card.custom_minimum_size = Vector2(130, 210)
		var v := UI.vbox(6, BoxContainer.ALIGNMENT_CENTER)
		card.add_child(v)
		var t := UI.title("%s %d" % [U.t("Día"), i + 1], 20, UI.GOLD if is_today else UI.TEXT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		var ic := UI.icon("ui_check" if done else ("ui_chest" if i == days - 1 else "ui_gift"), 58, UI.GREEN if done else (UI.GOLD if is_today else UI.TEXT_DIM))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var usd: float = float(budgets[i]) if i < budgets.size() else 1.0
		var vl := UI.label(U.t("≈ US$ %.2f") % usd, 14, UI.GREEN, "bold")
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(vl)
		var sl := UI.label(U.t("Reclamado") if done else (U.t("¡Hoy!") if is_today else ""), 13, UI.TEXT_DIM, "semibold")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
		row.add_child(card)
	var last: Dictionary = st.get("last_reward", {})
	if not available and not last.is_empty():
		var lr := UI.hbox(10)
		lr.add_child(UI.label(U.t("Última caja:"), 15, UI.TEXT_DIM, "semibold"))
		var rr := UI.reward_row(last, 15)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(rr)
		body.add_child(lr)
	var bottom := UI.hbox(12, BoxContainer.ALIGNMENT_CENTER)
	body.add_child(bottom)
	if available:
		var b := UI.button(U.t("¡Reclamar Día %d!") % (day + 1), "GoldButton", "ui_gift", Vector2(300, 60))
		b.pressed.connect(func() -> void: send("claim_login", {}, func(p: Dictionary) -> void:
			game.show_reward(p.get("reward", {}), U.t("Bono del Día %d · valor US$ %.2f") % [int(p.get("day", 1)), float(p.get("value_usd", 1.0))])))
		bottom.add_child(b)
	else:
		var wait: float = float(int(st.get("next_at", 0)) - GameClient.server_now()) / 1000.0
		var l := UI.label(U.t("Próxima caja en %s") % U.fmt_time(maxf(0.0, wait)), 18, UI.CYAN, "bold")
		l.name = "Wait"
		bottom.add_child(l)
		var dbg := UI.button(U.t("Demo: simular siguiente día"), "GhostButton", "ui_timer", Vector2(0, 48))
		dbg.pressed.connect(func() -> void: send("debug_next_day", {}))
		bottom.add_child(dbg)


func tick() -> void:
	var l: Label = body.find_child("Wait", true, false)
	if l != null:
		var st: Dictionary = GameClient.me.get("shop", {}).get("login", {})
		var wait: float = float(int(st.get("next_at", 0)) - GameClient.server_now()) / 1000.0
		l.text = U.t("Próxima caja en %s") % U.fmt_time(maxf(0.0, wait))
