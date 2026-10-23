extends SceneTree

## Cancello del BATTLEGROUND (costruttore_dungeon.gd + schiera_battleground.gd +
## ArcaniumEnemy.alleato):
##   1. nel nodo battleground il dungeon si ferma sullo schieramento, con le 3
##      truppe base e almeno 3 punti (la sala d'ingresso prima);
##   2. «Deploy» mette in campo 3 truppe dove sono state messe, e il gioco riparte;
##   3. le truppe sono alleate: nel gruppo e sul layer del giocatore, fuori dal
##      conto dei nemici, i loro colpi sul layer dei nemici, e cercano i nemici;
##   4. un nemico vicino a una truppa prende di mira la truppa;
##   5. una truppa che colpisce un nemico gli toglie vita;
##   6. l'ondata e' piu' grossa di uno scontro della stessa tappa.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_battleground.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 6

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(21)
	var id_bg := _nodo(torneo, "battleground")
	var id_sc := ""
	var reg_bg : int = int(torneo.nodo(id_bg)["regione"])
	for id in torneo.regione(reg_bg)["nodi"]:
		if torneo.nodo(id)["tipo"] == "scontro" and int(torneo.nodo(id)["piano"]) > 0:
			id_sc = id

	## 6. (prima: lo scontro della stessa tappa, per il confronto)
	torneo.nodo_corrente = id_sc
	var scena_s : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena_s.get_node("Dungeon").obiettivo = 0
	root.add_child(scena_s)
	for k in 3:
		await process_frame
	var nemici_scontro : int = scena_s.get_node("Dungeon")._nemici_tot
	root.remove_child(scena_s)
	scena_s.free()

	## 1.
	torneo.nodo_corrente = id_bg
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var du : Node = scena.get_node("Dungeon")
	du.obiettivo = 0
	root.add_child(scena)
	for k in 3:
		await process_frame
	var sch : Control = du._schiera
	_ok(sch != null and paused and sch.truppe.size() == 3 and sch.punti.size() >= 3 and sch.punti[0]["nome"] == "Entrance hall",
			"schieramento aperto a gioco fermo: %d truppe, punti %s" % [sch.truppe.size() if sch else 0,
			str(sch.punti.map(func(p): return p["nome"])) if sch else "-"])

	## 2.
	var punti : Array = sch.punti
	sch.scelte = [0, 1, 1]
	sch.conferma()
	for k in 3:
		await process_frame
	var vicini := 0
	for k in du.alleati.size():
		var p : Vector3 = punti[[0, 1, 1][k]]["pos"]
		if Vector2(du.alleati[k].global_position.x - p.x, du.alleati[k].global_position.z - p.z).length() < 2.5:
			vicini += 1
	_ok(du.alleati.size() == 3 and vicini == 3 and not paused, "3 truppe in campo ai loro punti (%d), gioco ripartito" % vicini)

	## 3.
	var a : Node = du.alleati[0]
	var nemici : Array = get_nodes_in_group("nemico_dungeon")
	var in_conto := nemici.has(a)
	var maschere_ok := true
	if a.has_method("_all_hitboxes"):
		for h in a._all_hitboxes():
			if (h as Area3D).collision_mask != a.LAYER_NEMICI:
				maschere_ok = false
	_ok(a.alleato and a.is_in_group("player") and not a.is_in_group("targets") and a.collision_layer == 2
			and not in_conto and maschere_ok and a.gruppo_ostile() == "targets",
			"le truppe sono alleate: gruppo player %s, targets %s, layer %d, nel conto %s, maschere %s, ostile %s" % [a.is_in_group("player"),
			a.is_in_group("targets"), a.collision_layer, in_conto, maschere_ok, a.gruppo_ostile()])

	## 4.
	var e : Node3D = nemici[0]
	var pl : Node3D = scena.get_node("Player")
	pl.global_position = e.global_position + Vector3(30, 0, 30)
	(a as Node3D).global_position = e.global_position + Vector3(1.5, 0, 0)
	_ok(e._nearest_player_target() == a, "il nemico vicino a una truppa la prende di mira (%s)" % str(e._nearest_player_target()))

	## 5.
	var hs = e.health_system
	var prima : float = hs._health_f
	var mossa = a.move_set.moves[0] if a.move_set != null and not a.move_set.moves.is_empty() else null
	if mossa != null:
		e.hit(a, mossa)
	await process_frame
	_ok(mossa != null and hs._health_f < prima and e.target == a,
			"una truppa colpisce: vita %.0f -> %.0f, il nemico ora punta la truppa" % [prima, hs._health_f])
	_ok(du._nemici_tot > nemici_scontro, "l'ondata e' piu' grossa: %d nemici contro %d di uno scontro" % [du._nemici_tot, nemici_scontro])
	root.remove_child(scena)
	scena.free()

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


func _nodo(torneo : Node, tipo : String) -> String:
	for reg in torneo.mappa["regioni"]:
		for id in reg["nodi"]:
			if reg["nodi"][id]["tipo"] == tipo:
				return id
	return ""
