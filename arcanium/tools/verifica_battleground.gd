extends SceneTree

## Cancello del BATTLEGROUND (arcanium/levels/battleground/: il campo aperto,
## le due armate, l'arcimago rivale; ArcaniumEnemy.alleato):
##   1. la battaglia si apre ferma sullo schieramento: 3 truppe, 4 punti nella
##      meta' sud, il nome del campione rivale;
##   2. «Deploy» mette in campo le 3 truppe ai loro punti, e il gioco riparte;
##   3. le truppe sono alleate: gruppo e layer del giocatore, fuori dal conto,
##      colpi sul layer dei nemici, cercano i nemici;
##   4. l'arcimago rivale e' un campione di un'altra casata: le ossa e la mesh
##      del suo GLB sul corpo del Comandante, l'arma della sua casata in mano,
##      vita da Comandante x3 per la forza del nodo;
##   5. l'armata del rivale: 7 + 2 per tappa, tutta a nord; giocatore e
##      truppe a sud;
##   6. un nemico vicino a una truppa la prende di mira, e una truppa che lo
##      colpisce gli toglie vita;
##   7. sterminare l'armata non basta; abbattere l'arcimago la sbanda (cade
##      tutta) e la battaglia e' vinta.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_battleground.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 7

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
	root.get_node("SaveManager")._house = "dawnkeep"
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(21)
	for reg in torneo.mappa["regioni"]:
		for id in reg["nodi"]:
			if reg["nodi"][id]["tipo"] == "battleground" and torneo.nodo_corrente == "":
				torneo.nodo_corrente = id
	var tappa : int = int(torneo.nodo_in_corso()["regione"]) + 1
	var scena : Node = load("res://arcanium/levels/battleground/battleground.tscn").instantiate()
	var du : Node = scena.get_node("Campo")
	root.add_child(scena)
	for k in 5:
		await process_frame

	## 1.
	var sch : Control = du._schiera
	var a_sud : bool = sch != null and sch.punti.all(func(p): return p["pos"].z > 0.0)
	_ok(sch != null and paused and sch.truppe.size() == 3 and sch.punti.size() == 4 and a_sud and sch.rivale != "",
			"schieramento a gioco fermo: %d truppe, punti %s, rivale %s" % [sch.truppe.size() if sch else 0,
			str(sch.punti.map(func(p): return p["nome"])) if sch else "-", sch.rivale if sch else "-"])

	## 2.
	var punti : Array = sch.punti
	sch.scelte = [0, 1, 2]
	sch.conferma()
	for k in 3:
		await process_frame
	var ai_punti := 0
	for k in du.alleati.size():
		var p : Vector3 = punti[k]["pos"]
		if Vector2(du.alleati[k].global_position.x - p.x, du.alleati[k].global_position.z - p.z).length() < 2.5:
			ai_punti += 1
	_ok(du.alleati.size() == 3 and ai_punti == 3 and not paused, "3 truppe in campo ai loro punti (%d), gioco ripartito" % ai_punti)

	## 3.
	var a : Node = du.alleati[0]
	var nemici : Array = get_nodes_in_group("nemico_dungeon")
	var maschere_ok := true
	for h in a._all_hitboxes():
		if (h as Area3D).collision_mask != a.LAYER_NEMICI:
			maschere_ok = false
	_ok(a.alleato and a.is_in_group("player") and not a.is_in_group("targets") and a.collision_layer == 2
			and not nemici.has(a) and maschere_ok and a.gruppo_ostile() == "targets",
			"le truppe sono alleate: gruppo player, layer 2, fuori dal conto, colpi sui nemici")

	## 4.
	var r : Node = du.rivale
	var c : Resource = du.campione_rivale
	var sk : Skeleton3D = r.get_node("Model/NephiliteRig/Skeleton3D")
	var glb : Node = (load(c.corpo) as PackedScene).instantiate()
	var ossa_glb : int = (glb.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).get_bone_count()
	glb.free()
	var mesh_visibili := sk.get_children().filter(func(m): return m is MeshInstance3D and m.visible and m.mesh != null).size()
	var comandante : Node = load(du.CORPO_RIVALE).instantiate()
	var vita_base : int = comandante.health_system.total_health
	comandante.free()
	var arma := r.get_node_or_null("Model/NephiliteRig/Skeleton3D/MountArma/ArmaRivale")
	_ok(c.casata != "dawnkeep" and r.get_node("CorpoCampione").campione == c and sk.get_bone_count() == ossa_glb
			and mesh_visibili >= 1 and arma != null
			and r.health_system.total_health == int(round(vita_base * du.RIVALE_VITA * du._forza)),
			"arcimago rivale: %s (%s), %d ossa, arma %s, vita %d" % [c.nome, c.casata, sk.get_bone_count(),
			arma != null, r.health_system.total_health])

	## 5.
	var tutti_a_nord : bool = nemici.all(func(e): return e.global_position.z < 0.0)
	var pl : Node3D = scena.get_node("Player")
	_ok(nemici.size() == 7 + 2 * (tappa - 1) and tutti_a_nord and r.global_position.z < 0.0 and pl.global_position.z > 0.0,
			"armata del rivale: %d nemici a nord (tappa %d), rivale a nord, giocatore a sud" % [nemici.size(), tappa])

	## 6.
	var e : Node3D = nemici[0]
	pl.global_position = e.global_position + Vector3(30, 0, 30)
	for t in du.alleati:
		(t as Node3D).global_position = e.global_position + Vector3(20, 0, 20)
	(a as Node3D).global_position = e.global_position + Vector3(1.5, 0, 0)
	r.global_position = e.global_position + Vector3(-25, 0, -25)
	var hs = e.health_system
	var prima : float = hs._health_f
	var mossa = a.move_set.moves[0]
	e.hit(a, mossa)
	await process_frame
	_ok(e._nearest_player_target() == a and hs._health_f < prima,
			"il nemico vicino punta la truppa, la truppa gli toglie vita (%.0f -> %.0f)" % [prima, hs._health_f])

	## 7.
	for n in nemici:
		if is_instance_valid(n) and n.health_system._health_f > 0.0:
			n.health_system._health_f = 0.0
			n.health_system.died.emit()
	for k in 10:
		await process_frame
	var finito_senza_rivale : bool = du._finito
	## L'armata torna in vita per la prova della sbandata: due nemici nuovi.
	var nuovi : Array = []
	for k in 2:
		var n2 : Node3D = load(du.ARMATA[0]).instantiate()
		n2.position = Vector3(k * 3.0, 0.1, -10.0)
		n2.add_to_group("nemico_dungeon")
		du.add_child(n2)
		nuovi.append(n2)
	await process_frame
	r.health_system._health_f = 0.0
	r.health_system.died.emit()
	for k in 10:
		await process_frame
	var sbandati : bool = nuovi.all(func(n): return not is_instance_valid(n) or n.health_system._health_f <= 0.0)
	_ok(not finito_senza_rivale and du._finito and sbandati,
			"armata sterminata: finita=%s; caduto l'arcimago: finita=%s, armata sbandata=%s" % [finito_senza_rivale, du._finito, sbandati])

	paused = false
	root.remove_child(scena)
	scena.free()
	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
