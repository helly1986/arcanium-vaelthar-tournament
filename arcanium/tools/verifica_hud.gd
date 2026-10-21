extends SceneTree

## Cancello dell'HUD NUOVO (design-ui-nuova, 2026-10-21), sul giocatore vero
## dentro un dungeon:
##   1. in alto a sinistra il medaglione e le tre barre vive (vita, Arcanium,
##      vigore); nessuna StatBar vecchia rimasta;
##   2. le zone del touch: vitali in alto a sinistra, cristalli in alto a
##      destra, barra azioni e status in basso al centro, e niente negli
##      angoli in basso (levetta a sinistra, tasti a destra);
##   3. un colpo abbassa la barra della vita e lascia la scia;
##   4. i cristalli in alto a destra seguono la banca;
##   5. il medaglione senza ritratto mostra il sigillo nel colore della casata;
##   6. l'accumulo di Congelamento compare in basso al centro, mezzo pieno;
##   7. allo scatto la scritta rossa FROSTBITE, e la riga resta come durata.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_hud.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 9
const BarraViva := preload("res://arcanium/ui/hud/barra_viva.gd")

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	## In headless la finestra e' 64x64: le zone si misurano a 1280x720.
	root.size = Vector2i(1280, 720)
	root.add_child(scena)
	for k in 10:
		await process_frame
	var hud : Control = null
	for n in get_nodes_in_group("arcanium_hud"):
		hud = n
	var w : Vector2 = hud.get_viewport_rect().size

	## 1.
	var barre : Array = hud.find_children("*", "", true, false).filter(func(n): return n.get_script() == BarraViva)
	var tipi : Array = barre.map(func(b): return int(b.tipo))
	var vecchie : Array = hud.find_children("*", "StatBar", true, false)
	_ok(hud._medaglione != null and tipi == [0, 1, 2] and vecchie.is_empty(),
			"in alto a sinistra medaglione e tre barre vive (tipi %s), nessuna StatBar (%d)" % [str(tipi), vecchie.size()])

	## 2. Le zone.
	var vitali : Rect2 = hud.get_node("Vitali").get_global_rect()
	var cristalli : Rect2 = hud.get_node("Cristalli").get_global_rect()
	var azioni : Rect2 = hud.get_spell_bar()._panel.get_global_rect()
	_ok(vitali.end.x < w.x * 0.45 and vitali.end.y < w.y * 0.25,
			"vitali in alto a sinistra (%s su %s)" % [str(vitali), str(w)])
	_ok(cristalli.position.x > w.x * 0.6 and cristalli.end.y < w.y * 0.2,
			"cristalli in alto a destra (%s)" % str(cristalli))
	var angolo_sx := Rect2(0, w.y * 0.62, w.x * 0.28, w.y * 0.38)
	var angolo_dx := Rect2(w.x * 0.72, w.y * 0.62, w.x * 0.28, w.y * 0.38)
	var invasori : Array = []
	for r in [vitali, cristalli, azioni]:
		if r.intersects(angolo_sx) or r.intersects(angolo_dx):
			invasori.append(str(r))
	_ok(absf(azioni.get_center().x - w.x * 0.5) < 2.0 and invasori.is_empty(),
			"barra azioni in basso al centro, angoli in basso liberi per il touch (%s)" % str(invasori))

	## 3. Un colpo.
	var pl : Node = scena.get_node("Player")
	var hs = pl.health_system
	hs._on_damage_signal({"power": 30.0, "damage_type": "FISICO"})
	await process_frame
	await process_frame
	var hp : Control = hud._hp_bar
	var atteso := float(hs.current_health) / float(hs.total_health)
	_ok(is_equal_approx(hp._ratio, atteso) and hp._chip.chip > hp._ratio + 0.05,
			"un colpo abbassa la vita (%.2f) e lascia la scia (%.2f)" % [hp._ratio, hp._chip.chip])

	## 4. I cristalli.
	var banca : Node = root.get_node("CrystalBank")
	banca.add(25)
	_ok(hud._cristalli.text == "◆ %d" % banca.crystals, "i cristalli seguono la banca (%s)" % hud._cristalli.text)

	## 5. Il medaglione.
	var med : Control = hud._medaglione
	_ok(med.ritratto == null and med.sigillo != null and med.sigillo.get_theme_color("font_color") == Color("#8fbfe0"),
			"senza ritratto, il sigillo nel colore di Dawnkeep")

	## 6. L'accumulo.
	var host = hud.status_host
	var stat : Node = hud.get_node("Status")
	var scatti : Array = []
	stat.scattato.connect(func(id, nome): scatti.append(nome))
	host.build_frozen(host.get_effect("frozen").threshold * 0.5 if host.get_effect("frozen") != null else 50.0)
	await process_frame
	await process_frame
	var riga : Control = stat.righe().get("frozen")
	var dove : Rect2 = riga.get_global_rect() if riga != null else Rect2()
	_ok(riga != null and riga._ratio > 0.2 and riga._ratio < 0.8 and absf(dove.get_center().x - w.x * 0.5) < 4.0
			and dove.end.y < azioni.position.y,
			"l'accumulo compare in basso al centro sopra la barra azioni (%.2f, %s)" % [riga._ratio if riga else -1.0, str(dove)])

	## 7. Lo scatto.
	host.apply_frozen()
	await process_frame
	await process_frame
	var scritte : Array = hud.find_children("ScrittaScatto*", "Label", true, false)
	var riga2 : Control = stat.righe().get("frozen")
	_ok(scatti == ["FROSTBITE"] and not scritte.is_empty() and scritte[0].text == "FROSTBITE"
			and scritte[0].get_theme_color("font_color") == stat.ROSSO_SCATTO
			and riga2 != null and riga2._ratio > 0.9,
			"allo scatto la scritta rossa %s, e la riga resta come durata (%.2f)" % [str(scatti), riga2._ratio if riga2 else -1.0])

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
