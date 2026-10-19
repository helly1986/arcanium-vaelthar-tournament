extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: l'ARCO nelle mani del PLAYER — il tipo d'arma BOW
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_arco_player.gd
##
## Sette promesse, e ognuna se salta e' un difetto diverso:
##
##   1. la clip del tiro e' nella libreria del player, sulle SUE ossa
##   2. l'albero ha i due rami BOW (locomozione e attacco) e SLASH non prende
##      piu' anche gli archi                              -> altrimenti arco = spada
##   3. equipaggiare l'arco lo mette in mano (la DESTRA, come ogni arma: e' la
##      sinistra che tira), nasconde lo scudo, annuncia BOW all'albero, e la
##      guardia non parte                                  -> altrimenti si para
##      con uno scudo invisibile
##   4. il tiro: la corda si tende, la lama NON si accende, al rilascio nasce
##      UNA freccia con la risorsa dell'arco, e il bersaglio davanti la prende
##      con il danno da perforazione dell'arco
##   5. un colpo subito prima del rilascio annulla il tiro: nessuna freccia
##   6. il tiro CARICATO (colpo forte): un'altra clip nel ramo, freccia con
##      potenza, posa e SPINTA moltiplicate; e la spinta sposta davvero chi la
##      prende — il player stesso, spinto, si muove e si ferma
##   7. rimessa la spada, lo scudo torna e il tipo a SLASH
##   8. il salvataggio dell'utente non e' toccato
##
## ⚠️ In headless lo scheletro non si muove: si prova la logica, non la posa.

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const ARCO := "res://arcanium/resources/weapons/arco_di_spirito_sylvorn.tres"
const SALVATAGGIO := "user://arcanium_save.cfg"
const COPIA := "user://arcanium_save.cfg.collaudo_arco"

var guasti := 0
var _fatto := false
var _scoccate : Array = []
var _annullati := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Un nemico finto: corpo sul layer del mondo (1), nel gruppo "targets", che
## registra cio' che gli arriva.
class Manichino extends StaticBody3D:
	var colpi : Array = []
	var spinte : Array = []
	func spingi(verso : Vector3, forza : float) -> void:
		spinte.append([verso, forza])
	func _init() -> void:
		collision_layer = 1
		collision_mask = 0
		var f := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(3.0, 4.0, 0.8)
		f.shape = b
		f.position = Vector3(0, 1.0, 0)
		add_child(f)
		add_to_group("targets")
	func hit(_chi, info) -> void:
		colpi.append(info)


func _process(_dt : float) -> bool:
	if not _fatto:
		_fatto = true
		_prova()
	return false


func _prova() -> void:
	var loadout := root.get_node_or_null("EquipmentLoadout")
	var salva := root.get_node_or_null("SaveManager")
	_sia(loadout != null, "l'autoload EquipmentLoadout c'e'")
	if loadout == null:
		quit(1)
		return
	var c_era := _copia(SALVATAGGIO, COPIA)
	var arco : Resource = load(ARCO)
	var spada : Resource = loadout.equipped_in("arma_primaria")

	## Un pavimento: senza, il player cade nel vuoto per tutto il collaudo, la
	## freccia parte da dove e' caduto e il bersaglio resta su in alto.
	var suolo := StaticBody3D.new()
	suolo.collision_layer = 1
	var forma := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	forma.shape = box
	suolo.add_child(forma)
	suolo.position = Vector3(0, -0.5, 0)
	root.add_child(suolo)

	var p : Node3D = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(p)
	await process_frame
	await process_frame
	await process_frame
	## Il player nasce STATIC e passa a FREE solo dopo la prima clip misurata
	## (`_ready` nel player): un attacco chiesto prima resta in coda per sempre.
	for _i in 600:
		if p.current_state == p.state.FREE:
			break
		await physics_frame
	_sia(p.current_state == p.state.FREE, "il player e' libero di agire")

	var arcieria : Node = p.get_node_or_null("ArcieriaPlayer")
	_sia(arcieria != null and arcieria.innestato(), "il player ha l'ArcieriaPlayer, innestata")
	if arcieria == null:
		_fine(p, loadout, spada, salva, c_era)
		return
	## La freccia si consuma da sola all'impatto: si annota SUBITO chi l'ha
	## tirata e con cosa, perche' dopo il nodo non c'e' piu'.
	arcieria.scoccata.connect(func(f): _scoccate.append({"source": f.get("source"), "move": f.get("move")}))
	arcieria.annullato.connect(func(): _annullati += 1)

	print()
	print("=== 1. la clip del tiro e' del player ===")
	var ap : AnimationPlayer = p.find_child("AnimationPlayer", true, false)
	_sia(ap != null and ap.has_animation("ArcoLib/Tiro"), "esiste 'ArcoLib/Tiro'")
	if ap != null and ap.has_animation("ArcoLib/Tiro"):
		var a := ap.get_animation("ArcoLib/Tiro")
		var estranee := 0
		for i in a.get_track_count():
			if not str(a.track_get_path(i)).begins_with("%GeneralSkeleton:"):
				estranee += 1
		_sia(estranee == 0 and a.get_track_count() > 10, "tutte le %d tracce stanno su %%GeneralSkeleton" % a.get_track_count())

	print()
	print("=== 2. i rami BOW nell'albero ===")
	var albero : AnimationTree = p.get_node("AnimStateTree")
	var radice := albero.tree_root as AnimationNodeBlendTree
	var ms := radice.get_node("MovementStates") as AnimationNodeStateMachine
	var at := radice.get_node("ATTACK_tree") as AnimationNodeStateMachine
	_sia(ms.has_node("BOW_tree"), "MovementStates ha BOW_tree")
	_sia(ms.has_node("BOW_tree") and (ms.get_node("BOW_tree") as AnimationNodeStateMachine).has_node("MoveStrafe"),
		"con il suo MoveStrafe")
	var va := false
	var torna := false
	for i in ms.get_transition_count():
		var da := str(ms.get_transition_from(i))
		var a_ := str(ms.get_transition_to(i))
		if da == "SLASH_tree" and a_ == "BOW_tree":
			va = ms.get_transition(i).advance_expression.contains("BOW")
		if da == "BOW_tree" and a_ == "SLASH_tree":
			torna = ms.get_transition(i).advance_expression.contains("BOW")
	_sia(va and torna, "e le transizioni SLASH<->BOW su weapon_type")
	_sia(at.has_node("BOW") and (at.get_node("BOW") as AnimationNodeStateMachine).has_node("Tiro"), "ATTACK_tree ha BOW/Tiro")
	var slash_esclude := false
	var bow_entra := false
	for i in at.get_transition_count():
		if str(at.get_transition_from(i)) == "Start":
			var e := at.get_transition(i).advance_expression
			if str(at.get_transition_to(i)) == "SLASH":
				slash_esclude = e.contains("BOW") and e.contains("HEAVY")
			if str(at.get_transition_to(i)) == "BOW":
				bow_entra = e.contains("BOW")
	_sia(slash_esclude, "Start->SLASH esclude anche BOW")
	_sia(bow_entra, "e Start->BOW entra con weapon_type == BOW")

	print()
	print("=== 3. l'arco in mano ===")
	loadout.acquire(arco)
	## L'arco e' chiuso da un lucchetto (la tecnica dell'Arcieria, vedi
	## verifica_arcieria_tomo): qui si collauda il TIRO, non il lucchetto, e
	## la tecnica si segna come appresa. Il salvataggio e' gia' al riparo.
	var lucchetto : Resource = loadout.tecnica_richiesta(arco)
	_sia(lucchetto != null and not loadout.sbloccato(arco), "senza l'Arcieria l'arco e' chiuso")
	if lucchetto != null:
		root.get_node("PlayerFlags").set_flag(str(lucchetto.get("unlock_flag")))
	_sia(loadout.equip("arma_primaria", arco), "con l'Arcieria si mette")
	await process_frame
	await process_frame
	_sia(str(p.weapon_type) == "BOW", "il player annuncia BOW (%s)" % str(p.weapon_type))
	_sia(str(albero.weapon_type) == "BOW", "e l'albero lo ha preso (%s)" % str(albero.weapon_type))
	var destra : Node3D = p.get_node("WeaponSystem/RightHand/HandPivot")
	var modello : Node3D = destra.get_child(0).get_node_or_null("ModelloEquipaggiato")
	_sia(modello != null and modello.get_node_or_null("Corda") != null, "il modello dell'arco pende dalla DESTRA, con la corda")
	var gadget = p.get_node("GadgetSystem").current_equipment
	_sia(gadget != null and not gadget.visible, "lo scudo e' nascosto")
	p.start_guard()
	_sia(not p.guarding, "e la guardia non parte")

	print()
	print("=== 4. il tiro ===")
	var bersaglio := Manichino.new()
	root.add_child(bersaglio)
	bersaglio.global_position = p.global_position + p.global_transform.basis.z * 6.0
	var arma_destra = p.get_node("WeaponSystem").current_equipment
	var corda : Node = modello.get_node("Corda") if modello else null
	var tesa_durante := false
	var tesa_subito := false
	var tesa_a := -1.0
	var lama_accesa := false
	p.queue_attack(false)
	for _i in 300:
		await physics_frame
		if corda != null and corda.tesa():
			tesa_durante = true
			if tesa_a < 0.0:
				tesa_a = float(arcieria.get("_t"))
			if _i < 3:
				tesa_subito = true
		if arma_destra != null and arma_destra.monitoring:
			lama_accesa = true
		if not _scoccate.is_empty() and not arcieria.in_tiro():
			break
	_sia(tesa_durante, "durante il carico la corda era tesa")
	## Non dall'inizio: la sinistra sta nella faretra. Si tende all'incocco
	## del set, misurato sulla clip (misura_arco.tscn).
	var set_arco : Resource = arcieria.get("set_arco")
	var atteso : float = float(set_arco.get("incocco")) * float(arcieria.get("_durata"))
	_sia(not tesa_subito, "ma non dall'inizio del tiro (la mano sta nella faretra)")
	_sia(atteso > 0.5 and tesa_a >= 0.0 and absf(tesa_a - atteso) < 0.1,
		"si e' tesa all'incocco del set (%.2f s, atteso %.2f)" % [tesa_a, atteso])
	_sia(not lama_accesa, "e la lama non si e' mai accesa")
	_sia(_scoccate.size() == 1, "al rilascio e' nata UNA freccia (%d)" % _scoccate.size())
	if _scoccate.size() == 1:
		var f : Dictionary = _scoccate[0]
		_sia(f.source == p, "con il player come sorgente")
		_sia(f.move != null and str(f.move.name) == str(arco.name), "e la risorsa dell'arco come colpo")
		_sia(corda != null and not corda.tesa(), "e la corda e' stata rilasciata")
	for _i in 120:
		await physics_frame
		if not bersaglio.colpi.is_empty():
			break
	_sia(bersaglio.colpi.size() == 1, "il bersaglio a 6 m e' stato colpito una volta (%d)" % bersaglio.colpi.size())
	if not bersaglio.colpi.is_empty():
		var info = bersaglio.colpi[0]
		_sia(str(info.damage_type) == "PERFORAZIONE" and int(info.power) == int(arco.power) and int(info.power) > 0,
			"con danno da perforazione dell'arco (%d)" % int(info.power))

	print()
	print("=== 5. un colpo subito annulla il tiro ===")
	for _i in 90:
		await physics_frame
		if not p.busy:
			break
	_scoccate.clear()
	p.queue_attack(false)
	for _i in 30:
		await physics_frame
		if arcieria.in_tiro():
			break
	_sia(arcieria.in_tiro(), "il secondo tiro e' partito")
	p.hurt_started.emit()
	await physics_frame
	_sia(not arcieria.in_tiro() and _annullati >= 1, "e il colpo subito lo ha annullato")
	for _i in 200:
		await physics_frame
	_sia(_scoccate.is_empty(), "nessuna freccia da un tiro interrotto")

	print()
	print("=== 6. il tiro caricato e la spinta ===")
	for _i in 120:
		await physics_frame
		if not p.busy and not arcieria.in_tiro():
			break
	_scoccate.clear()
	bersaglio.colpi.clear()
	bersaglio.spinte.clear()
	var sm_bow := at.get_node("BOW") as AnimationNodeStateMachine
	_sia(sm_bow.has_node("TiroCaricato"), "il ramo BOW ha lo stato TiroCaricato")
	p.queue_attack(true)
	for _i in 30:
		await physics_frame
		if arcieria.in_tiro():
			break
	_sia(arcieria.in_tiro_caricato(), "un colpo forte e' un tiro caricato")
	for _i in 300:
		await physics_frame
		if not _scoccate.is_empty() and not bersaglio.spinte.is_empty():
			break
	_sia(_scoccate.size() == 1, "al rilascio e' nata la freccia (%d)" % _scoccate.size())
	if _scoccate.size() == 1:
		var m = _scoccate[0].move
		_sia(m != null and int(m.power) == int(round(arco.power * arco.heavy_power_mult)) and int(m.power) > int(arco.power),
			"con potenza moltiplicata (%d contro %d)" % [int(m.power) if m else 0, int(arco.power)])
		_sia(m != null and is_equal_approx(float(m.spinta), arco.spinta * arco.heavy_spinta_mult) and float(m.spinta) > 0.0,
			"e spinta moltiplicata (%.1f m/s)" % (float(m.spinta) if m else 0.0))
	_sia(bersaglio.spinte.size() == 1 and bersaglio.spinte[0][0].z > 0.9 and is_equal_approx(bersaglio.spinte[0][1], arco.spinta * arco.heavy_spinta_mult),
		"il bersaglio ha ricevuto la spinta nel verso del volo (%s)" % str(bersaglio.spinte))
	## E chi la riceve si muove davvero: il player, spinto all'indietro.
	for _i in 120:
		await physics_frame
		if not p.busy and not arcieria.in_tiro():
			break
	var da : Vector3 = p.global_position
	p.spingi(-p.global_transform.basis.z, 6.0)
	for _i in 90:
		await physics_frame
	var spostato : float = (p.global_position - da).length()
	_sia(spostato > 1.0 and spostato < 3.0, "spinto a 6 m/s il player arretra di %.2f m e si ferma" % spostato)
	_sia(p.spinta_in_corso() == Vector3.ZERO, "e la spinta si e' esaurita")
	p.guarding = true
	p.spingi(-p.global_transform.basis.z, 6.0)
	_sia(is_equal_approx(p.spinta_in_corso().length(), 3.0), "in guardia se ne prende la meta' (%.1f)" % p.spinta_in_corso().length())
	p.guarding = false
	p.set("_spinta", Vector3.ZERO)

	print()
	print("=== 7. rimessa la spada ===")
	if spada != null:
		loadout.equip("arma_primaria", spada)
		await process_frame
		await process_frame
		_sia(str(p.weapon_type) != "BOW", "il tipo non e' piu' BOW (%s)" % str(p.weapon_type))
		## La spada di prima puo' avere un modello suo (la Spada del Senza Nome
		## ce l'ha): cio' che conta e' che in mano non ci sia piu' l'ARCO.
		var in_mano : Node = destra.get_child(0).get_node_or_null("ModelloEquipaggiato")
		_sia(in_mano == null or in_mano.get_node_or_null("Corda") == null, "la destra e' tornata alla spada (%s)" % str(spada.name))
		_sia(gadget != null and gadget.visible, "e lo scudo si vede di nuovo")
	else:
		_sia(false, "nessuna arma iniziale da rimettere")

	bersaglio.queue_free()
	suolo.queue_free()
	_fine(p, loadout, spada, salva, c_era)


func _fine(p : Node, loadout : Node, spada : Resource, salva : Node, c_era : bool) -> void:
	print()
	print("=== 8. il salvataggio ===")
	if loadout != null and spada != null:
		loadout.equip("arma_primaria", spada)
	var arco : Resource = load(ARCO)
	if loadout != null and loadout.owns(arco):
		loadout.release(arco)
	p.queue_free()
	await process_frame
	if c_era:
		if salva != null:
			salva.set("_resume_scene", "")
		_sia(_copia(COPIA, SALVATAGGIO), "il salvataggio dell'utente e' stato rimesso a posto")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPIA))
	elif FileAccess.file_exists(SALVATAGGIO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SALVATAGGIO))
		print("  ok    il salvataggio scritto dal collaudo e' stato tolto")
	print()
	print("%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)


func _copia(da : String, a : String) -> bool:
	if not FileAccess.file_exists(da):
		return false
	var sorgente := FileAccess.open(da, FileAccess.READ)
	var dest := FileAccess.open(a, FileAccess.WRITE)
	if sorgente == null or dest == null:
		return false
	dest.store_buffer(sorgente.get_buffer(sorgente.get_length()))
	return true
