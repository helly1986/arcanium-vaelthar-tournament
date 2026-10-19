extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: l'arciere Sylvorn — tira da lontano, non tira attraverso i muri,
## si ritira con giudizio
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_arciere.gd
##
## Otto promesse:
##   1. la scena e' un arciere: moveset con un tiro (proiettile), soglia
##      d'inseguimento a distanza, origine del tiro risolta, niente scudo, e
##      il corpo e' il Soldato Scelto (riggato il 2026-09-13), non il Fante
##   2. con il bersaglio in linea la mossa e' usabile; con un muro in mezzo NO
##   3. al rilascio nasce UNA freccia, che vola verso il bersaglio e lo colpisce
##      con la mossa (danno del tiro, non un contatto di lama)
##   4. col bersaglio addosso si RITIRA: corre via, guarda dove corre, e smette
##      quando ha ripreso la distanza — poi riposa, e per un po' non si ritira
##   5. un colpo subito chiude la ritirata
##   6. l'ARCO: impugnato con la DESTRA su Prop_Attachment_R (la sinistra tira
##      la corda), l'impugnatura all'origine e nella mano, la corda come nodo;
##      la freccia parte dall'incocco; la corda NON si tende all'inizio del
##      tiro (la mano sta nella faretra) ma all'INCOCCO misurato della mossa
##      (`tendi_da`, dal playhead), scatta a riposo al rilascio, e un tiro
##      interrotto la lascia andare; la FRECCIA IN MANO compare all'estrazione
##      (`estrai_da`), sta sulla corda dall'incocco e sparisce al rilascio
##   7. il DROP: l'arco cade come oggetto, e l'oggetto ha la sua versione da
##      armadio con illustrazione e modello — il ponte dell'inventario lo trova
##   8. il boss, da cui il tiro e' stato sollevato, spara ancora
##
## Le mosse a distanza stanno nell'umanoide dal 2026-09-12: l'arciere e' il
## secondo che spara, e il codice e' uno. L'arco e' del 2026-09-13.

const ARCIERE := "res://arcanium/characters/sylvorn_soldato_scelto.tscn"
const BOSS := "res://arcanium/characters/senza_nome.tscn"

var guasti := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Un corpo che sa essere colpito, sul layer del player (2).
class Manichino extends CharacterBody3D:
	var colpi : Array = []
	var spinte : Array = []
	func spingi(verso : Vector3, forza : float) -> void:
		spinte.append([verso, forza])
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		var f := CollisionShape3D.new()
		var c := CapsuleShape3D.new()
		c.radius = 0.4
		c.height = 1.8
		f.shape = c
		f.position = Vector3(0, 0.9, 0)
		add_child(f)
	func hit(_chi, mossa) -> void:
		colpi.append(mossa)


func _muro(pos : Vector3) -> StaticBody3D:
	var m := StaticBody3D.new()
	m.collision_layer = 1
	var f := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4.0, 4.0, 0.4)
	f.shape = b
	f.position = Vector3(0, 2.0, 0)
	m.add_child(f)
	m.position = pos
	return m


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var a : Node3D = (load(ARCIERE) as PackedScene).instantiate()
	root.add_child(a)
	await process_frame
	await process_frame
	a.set_physics_process(false)

	print("=== 1. e' un arciere ===")
	## Il tiro RAPIDO: la prima mossa a proiettile (la seconda e' il caricato).
	var tiro = null
	for m in a.move_set.moves:
		if m.projectile_scene != null:
			tiro = m
			break
	_sia(tiro != null, "il moveset ha una mossa a proiettile (%s)" % (tiro.id if tiro else "-"))
	_sia(a.move_set.melee_threshold >= 6.0, "l'inseguimento si ferma a distanza (soglia %.1f m)" % a.move_set.melee_threshold)
	_sia(tiro != null and tiro.min_range >= 2.0, "e il tiro ha una distanza minima (%.1f m)" % (tiro.min_range if tiro else 0.0))
	_sia(a.get_node_or_null(a.cast_origin) != null, "l'origine del tiro e' risolta (%s)" % str(a.cast_origin))
	_sia(a.scudo == null, "niente scudo")
	## Il corpo e' il SOLDATO SCELTO, non il Fante: e' lui che porta l'arco.
	var corpi := []
	for m in a.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		corpi.append(m.name)
	_sia(corpi.any(func(n): return n.begins_with("SoldatoScelto")), "il corpo e' il Soldato Scelto (%s)" % str(corpi))
	if tiro == null:
		_fine(a)
		return

	print()
	print("=== 2. linea di tiro ===")
	## Nel gruppo del PLAYER: `Fazioni.colpibile` non ferisce chi sta nello
	## stesso schieramento del tiratore, e "targets" e' quello dei nemici.
	var b := Manichino.new()
	b.add_to_group("player")
	root.add_child(b)
	b.global_position = a.global_position + a.global_transform.basis.z * 8.0
	a.target = b
	await physics_frame
	_sia(a._has_line_of_sight(), "bersaglio a 8 m in vista: linea libera")
	_sia(a._move_is_usable(tiro), "e la mossa e' usabile")
	var muro := _muro(a.global_position + a.global_transform.basis.z * 4.0)
	root.add_child(muro)
	await physics_frame
	await physics_frame
	_sia(not a._has_line_of_sight(), "con un muro in mezzo: linea interrotta")
	_sia(not a._move_is_usable(tiro), "e la mossa NON e' usabile")
	muro.queue_free()
	await physics_frame
	await physics_frame
	_sia(a._has_line_of_sight(), "tolto il muro, torna libera")

	print()
	print("=== 3. la freccia ===")
	## Si contano le FRECCE, non i figli: al rilascio nasce anche la sua scia
	## (SciaFreccia, scia_freccia.gd), arrivata dopo questo cancello.
	var frecce_prima := root.get_children().filter(func(c): return c.name.begins_with("Freccia")).size()
	a._deliver_hit(tiro)
	await physics_frame
	var freccia : Node3D = null
	var frecce := 0
	for c in root.get_children():
		if c.name.begins_with("Freccia"):
			freccia = c
			frecce += 1
	_sia(frecce == frecce_prima + 1 and freccia != null, "al rilascio nasce una freccia sola")
	if freccia != null:
		var d0 : float = freccia.global_position.distance_to(b.global_position)
		var dir : Vector3 = freccia.get("direction")
		_sia(dir.dot((b.global_position - freccia.global_position).normalized()) > 0.9, "puntata verso il bersaglio")
		for _i in 90:
			await physics_frame
			if not is_instance_valid(freccia) or not b.colpi.is_empty():
				break
		_sia(b.colpi.size() == 1, "il bersaglio e' stato colpito una volta (%d)" % b.colpi.size())
		_sia(not b.colpi.is_empty() and b.colpi[0] == tiro, "con la mossa del tiro (danno %d, %s)" % [tiro.power, tiro.damage_type])
		_sia(b.spinte.size() == 1 and is_equal_approx(b.spinte[0][1], tiro.spinta) and tiro.spinta > 0.0,
			"e la SPINTA del tiro (%.1f m/s), nel verso del volo" % tiro.spinta)
		var caricato = null
		for m in a.move_set.moves:
			if m.id == "R2":
				caricato = m
		_sia(caricato != null and caricato.spinta > tiro.spinta * 2.0 and caricato.power > tiro.power,
			"c'e' il Tiro Caricato: spinge %.1f contro %.1f, e fa piu' male" % [caricato.spinta if caricato else 0.0, tiro.spinta])
		## Un nemico spinto si sposta davvero: un Fante a riposo, senza bersaglio.
		var fante : Node3D = (load("res://arcanium/characters/sylvorn_fante.tscn") as PackedScene).instantiate()
		root.add_child(fante)
		fante.global_position = Vector3(20, 0.05, 20)
		await physics_frame
		await physics_frame
		var da := fante.global_position
		fante.spingi(Vector3(0, 0, 1), 6.0)
		for _i in 90:
			await physics_frame
		## In piano: qui non c'e' pavimento e il Fante cade, ma la spinta e' orizzontale.
		var d := fante.global_position - da
		var spostato := Vector2(d.x, d.z).length()
		_sia(spostato > 1.0 and spostato < 3.0, "un Fante spinto a 6 m/s si sposta di %.2f m e si ferma" % spostato)
		fante.set("_trincerato", true)
		fante.spingi(Vector3(0, 0, 1), 6.0)
		_sia(is_equal_approx(fante.spinta_in_corso().length(), 3.0), "in guardia ne prende la meta' (%.1f)" % fante.spinta_in_corso().length())
		fante.queue_free()
		_sia(not is_instance_valid(freccia) or not freccia.visible, "e la freccia e' sparita (partita da %.1f m)" % d0)

	print()
	print("=== 4. la ritirata ===")
	## Con la fisica spenta il residuo di `_root_motion_delta` non si rinnova:
	## si azzera per provare il ripiego a velocita' fissa (il ramo a root
	## motion e' lo stesso di `_chase`). E si spengono i tiri: a 10 m la mossa
	## sarebbe usabile e `_busy` bloccherebbe la ritirata successiva.
	a.set("_root_motion_delta", Vector3.ZERO)
	a.set("_next_attack", a._now() + 1000.0)
	b.global_position = a.global_position + a.global_transform.basis.z * 2.5
	a.velocity = Vector3.ZERO
	a._ai_step(1.0 / 60.0)
	_sia(bool(a.get("_in_ritirata")), "col bersaglio a 2,5 m parte la ritirata")
	var via : Vector3 = a.velocity
	via.y = 0.0
	var verso_b : Vector3 = (b.global_position - a.global_position)
	verso_b.y = 0.0
	_sia(via.length() > 0.1 and via.normalized().dot(verso_b.normalized()) < -0.5,
		"e corre VIA dal bersaglio (velocita' %.1f m/s)" % via.length())
	_sia(a.get("_current_anim") == a.run_anim, "con la clip di corsa")
	for _i in 30:
		a._face(1.0 / 60.0)
	var guarda : Vector3 = a.global_transform.basis.z
	_sia(guarda.dot(verso_b.normalized()) < -0.5, "e dopo mezzo secondo guarda dove corre, non il bersaglio")
	## Distanza ripresa: la ritirata finisce e comincia il riposo.
	b.global_position = a.global_position + a.global_transform.basis.z * -10.0
	a._ai_step(1.0 / 60.0)
	_sia(not bool(a.get("_in_ritirata")), "a 10 m la ritirata e' finita")
	b.global_position = a.global_position + a.global_transform.basis.z * 2.5
	a._ai_step(1.0 / 60.0)
	_sia(not bool(a.get("_in_ritirata")), "e subito dopo, col bersaglio di nuovo addosso, NON si ritira (riposo)")
	a.set("_ritirata_riposo_fino", 0.0)
	a._ai_step(1.0 / 60.0)
	_sia(bool(a.get("_in_ritirata")), "passato il riposo, si ritira di nuovo")

	print()
	print("=== 5. un colpo chiude la ritirata ===")
	a.hit(b, tiro)
	_sia(not bool(a.get("_in_ritirata")), "dopo un colpo la ritirata e' chiusa")

	print()
	print("=== 6. l'arco e la corda ===")
	var arco : Node3D = a.get_node_or_null(a.arco)
	_sia(arco != null, "l'arco e' montato (%s)" % str(a.arco))
	if arco != null:
		var mount := arco.get_parent() as BoneAttachment3D
		var sk : Skeleton3D = a.get_node("Model/NephiliteRig/Skeleton3D")
		_sia(mount != null and mount.bone_name == "Prop_Attachment_R" and mount.bone_idx == sk.find_bone("Prop_Attachment_R"),
			"nella DESTRA, su un BoneAttachment di Prop_Attachment_R (idx %d)" % (mount.bone_idx if mount else -1))
		var mano := a.get_node_or_null(a.mano_che_tira) as BoneAttachment3D
		_sia(mano != null and mano.bone_name == "Prop_Attachment_L" and mano.bone_idx == sk.find_bone("Prop_Attachment_L"),
			"e la mano che tira e' la SINISTRA (Prop_Attachment_L, idx %d)" % (mano.bone_idx if mano else -1))
		_sia(arco.position.length() < 0.06, "l'impugnatura sta nella mano (%.3f m dal mount)" % arco.position.length())
		## La faretra: sulla schiena, visibile. Un arciere senza faretra tira
		## frecce dal nulla.
		var faretra_mount := a.get_node_or_null("Model/NephiliteRig/Skeleton3D/MountFaretra") as BoneAttachment3D
		var faretra : Node3D = faretra_mount.get_node_or_null("Faretra") if faretra_mount else null
		_sia(faretra_mount != null and faretra_mount.bone_name == "Back_Attachment" and faretra_mount.bone_idx == sk.find_bone("Back_Attachment"),
			"la faretra pende dalla schiena (Back_Attachment, idx %d)" % (faretra_mount.bone_idx if faretra_mount else -1))
		_sia(faretra != null and faretra.visible and not faretra.find_children("*", "MeshInstance3D", true, false).is_empty(),
			"ed e' un modello visibile")
		## E la freccia che tira e' di Spirito, come l'arco.
		_sia(tiro.projectile_scene != null and tiro.projectile_scene.resource_path.get_file() == "freccia_spirito.tscn",
			"e tira frecce di Spirito (%s)" % (tiro.projectile_scene.resource_path.get_file() if tiro.projectile_scene else "-"))
		var mesh : MeshInstance3D = null
		for m in arco.find_children("*", "MeshInstance3D", true, false):
			if m.get_parent().name != "Corda":
				mesh = m
		var aabb : AABB = mesh.get_aabb() if mesh else AABB()
		_sia(mesh != null and absf(aabb.size.y - 1.0) < 0.03 and aabb.position.y < -0.40 and aabb.end.y > 0.52,
			"la mesh e' alta un metro con l'impugnatura all'origine (y %.2f..%.2f)" % [aabb.position.y, aabb.end.y])
		var corda : Node3D = arco.get_node_or_null("Corda")
		_sia(corda != null and corda.has_method("tendi"), "porta la corda come nodo")
		var origine : Node = a.get_node_or_null(a.cast_origin)
		_sia(corda != null and origine != null and corda.is_ancestor_of(origine), "e la freccia parte dall'incocco della corda")
		if corda != null:
			await process_frame
			var riposo : Vector3 = corda.get_node("Incocco").position
			var alto : Vector3 = corda.get_node("PuntaAlta").position
			var basso : Vector3 = corda.get_node("PuntaBassa").position
			_sia(alto.y > riposo.y and riposo.y > basso.y and alto.distance_to(basso) > 0.8,
				"le punte stanno sopra e sotto l'incocco, a %.2f m l'una dall'altra" % alto.distance_to(basso))
			_sia(not corda.tesa() and corda.incocco_attuale().distance_to(riposo) < 0.001, "a riposo l'incocco sta al suo posto")
			## La mossa dichiara l'incocco, misurato (misura_arco.tscn): prima
			## di quell'istante la corda non segue nessuno. Il playhead si manda
			## avanti a mano, come la fisica farebbe col tempo.
			_sia(tiro.tendi_da > 0.5, "il tiro ha un incocco misurato (tendi_da %.2f s)" % tiro.tendi_da)
			## Il mixer che suona la clip: l'albero se il nemico ce l'ha (il
			## Soldato Scelto oggi no), altrimenti l'AnimationPlayer.
			var mixer : AnimationMixer = a.get("_albero") as AnimationMixer
			if mixer == null:
				mixer = a.anim_player
			a._begin_move(tiro)
			a._advance_attack_timeline()
			_sia(not corda.tesa(), "all'inizio del tiro la corda e' a riposo: la mano sta nella faretra")
			mixer.advance(tiro.tendi_da * 0.5)
			a._advance_attack_timeline()
			_sia(not corda.tesa(), "a meta' strada (%.2f s) ancora a riposo" % (tiro.tendi_da * 0.5))
			## La FRECCIA IN MANO (freccia_in_mano.gd): nascosta finche' la mano
			## non l'ha estratta, in mano fino all'incocco, poi sulla corda.
			var in_mano : Node = a.get("_freccia")
			_sia(in_mano != null and tiro.estrai_da > 0.0 and tiro.estrai_da < tiro.tendi_da,
				"la mossa ha un'estrazione misurata prima dell'incocco (%.2f s)" % tiro.estrai_da)
			_sia(in_mano != null and in_mano.fase() == 0, "e a meta' strada la freccia non si vede ancora")
			mixer.advance(tiro.estrai_da + 0.02 - tiro.tendi_da * 0.5)
			a._advance_attack_timeline()
			_sia(in_mano != null and in_mano.fase() == 1 and in_mano.visible, "passata l'estrazione (%.2f s) la freccia e' in mano" % tiro.estrai_da)
			mixer.advance(tiro.tendi_da + 0.02 - tiro.estrai_da - 0.02)
			a._advance_attack_timeline()
			await process_frame
			_sia(corda.tesa(), "passato l'incocco (%.2f s) la corda e' tesa" % tiro.tendi_da)
			_sia(in_mano != null and in_mano.fase() == 2, "e la freccia sta sulla corda")
			## All'incocco la mano e' SULLA corda (e' la definizione: l'incocco
			## si muove di un centimetro); e' alla massima apertura, un attimo
			## prima del rilascio misurato, che l'incocco deve stare alla mano.
			var rilascio : float = a._contact_times(tiro)[0]
			mixer.advance(rilascio - 0.05 - (tiro.tendi_da + 0.02))
			a._advance_attack_timeline()
			await process_frame
			var tirato : Vector3 = corda.incocco_attuale()
			_sia(corda.tesa(), "un attimo prima del rilascio (%.2f s) e' ancora tesa" % (rilascio - 0.05))
			_sia(tirato.distance_to(riposo) > 0.1, "e l'incocco ha seguito la mano fino all'apertura (%.2f m dal riposo)" % tirato.distance_to(riposo))
			_sia(absf(tirato.z - riposo.z) < 0.0005 and (tirato.x - riposo.x) * signf(riposo.x) >= -0.0005,
				"restando nel piano dell'arco, dalla parte della corda")
			a._deliver_hit(tiro)
			_sia(not corda.tesa(), "al rilascio la corda e' libera")
			_sia(in_mano != null and in_mano.fase() == 0 and not in_mano.visible, "e la freccia in mano e' sparita: vola il proiettile")
			for _i in 60:
				await process_frame
			_sia(corda.incocco_attuale().distance_to(riposo) < 0.002, "e in un secondo l'incocco e' tornato a riposo (%.4f m)" % corda.incocco_attuale().distance_to(riposo))
			## Un secondo tiro (dall'idle, o `_play` non farebbe ripartire la
			## stessa clip), portato oltre l'incocco e poi interrotto.
			a._play(a.idle_anim, true)
			a._begin_move(tiro)
			mixer.advance(tiro.tendi_da + 0.02)
			a._advance_attack_timeline()
			_sia(corda.tesa(), "(secondo tiro, tesa all'incocco)")
			a._clear_move_state()
			_sia(not corda.tesa(), "un tiro interrotto lascia andare la corda")
			for c in root.get_children():
				if c.name.begins_with("Freccia"):
					c.queue_free()

	print()
	print("=== 7. il drop e l'armadio ===")
	var drop : Node = a.get_node_or_null("Drop_arco")
	_sia(drop != null and drop.item_id == "arco_di_spirito_sylvorn" and drop.drop_chance > 0.0,
		"l'arciere ha il drop dell'arco (%s, %.0f%%)" % [drop.item_id if drop else "-", (drop.drop_chance * 100.0) if drop else 0.0])
	var voce_path := "res://arcanium/resources/items/arco_di_spirito_sylvorn.tres"
	var arma_path := "res://arcanium/resources/weapons/arco_di_spirito_sylvorn.tres"
	var voce = load(voce_path) if ResourceLoader.exists(voce_path) else null
	var arma = load(arma_path) if ResourceLoader.exists(arma_path) else null
	_sia(voce != null and voce.category == "arma" and voce.lore != "" and voce.source != "", "l'oggetto esiste, e' un'arma e ha lore e fonte")
	_sia(arma != null and arma.image != null and arma.held_model != null, "la versione da armadio ha illustrazione e modello")
	_sia(voce != null and arma != null and voce.item_name == arma.name and arma.damage_type == "PERFORAZIONE",
		"con lo stesso nome (%s) e danno da perforazione" % (arma.name if arma else "-"))
	if arma != null and arma.held_model != null:
		var tenuto : Node = arma.held_model.instantiate()
		_sia(tenuto.get_node_or_null("Corda") != null, "e il modello da impugnare porta la corda")
		tenuto.free()

	print()
	print("=== 8. il boss spara ancora ===")
	var boss : Node3D = (load(BOSS) as PackedScene).instantiate()
	root.add_child(boss)
	await process_frame
	await process_frame
	boss.set_physics_process(false)
	var spell = null
	for m in boss.move_set.moves:
		if m.projectile_scene != null:
			spell = m
			break
	var bb := Manichino.new()
	bb.add_to_group("player")
	root.add_child(bb)
	bb.global_position = boss.global_position + boss.global_transform.basis.z * 8.0
	boss.target = bb
	await physics_frame
	_sia(spell != null and boss._move_is_usable(spell), "la spell del boss e' usabile in linea di tiro")
	var n0 := root.get_child_count()
	if spell != null:
		boss._deliver_hit(spell)
	await physics_frame
	_sia(root.get_child_count() == n0 + 1, "e al rilascio nasce il suo proiettile")

	bb.queue_free()
	boss.queue_free()
	b.queue_free()
	_fine(a)


func _fine(a : Node) -> void:
	a.queue_free()
	await process_frame
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
