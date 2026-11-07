extends SceneTree

## Cancello del CORPO DEL CAMPIONE in gioco (arcanium/systems/corpo_campione.gd),
## per ognuno dei sei campioni, dentro il dungeon vero:
##   1. il giocatore porta il corpo del campione della run: le ossa del suo
##      GLB nel GeneralSkeleton di sempre, la sua mesh visibile, quelle del
##      protagonista svuotate (niente Skin che cerca ossa che non ci sono);
##   2. mani e schiena hanno l'osso giusto: armi e scudo seguono il campione;
##   3. da fermo suona la sua idle d'autore (scheda.idle, al posto dell'idle
##      del tipo dell'arma del kit) o, senza, la sua Posa (braccia lungo i
##      fianchi), mai la guardia del moveset; e gli attacchi ci sono, portati
##      sul suo scheletro;
##   4. ArmaturaIndossata e' spenta: sul campione non si indossa nessun pezzo;
##   5. il kit e' quello della sua casata (dotazione della scheda): l'arma in
##      mano e' la sua, e lo scudo in mano sinistra c'e' solo se il kit ce l'ha;
##   6. arma e scudo stanno nella PRESA di quel corpo (presa_arma/presa_scudo
##      della scheda, sistemate a mano sul banco delle impugnature);
##   7. le dita si chiudono sull'impugnatura (presa_mano.gd) se la scheda lo
##      chiede: il modificatore sullo scheletro, con le pieghe trovate;
##   8. cambiando TIPO d'arma (l'arco in mano a Edran, la lama in mano a Ilwen)
##      arma, dita e seconda mano prendono la presa di quel tipo
##      (CampioneResource.prese, dai banchi), e tornando al kit tornano quelle
##      del kit;
##   9. lo scudo equipaggiato porta sul nodo Shield il suo modello e le sue
##      resistenze (held_weapon.gd), non sempre quelli della Prima Veglia;
##  10. il sigillo della casata ha il suo modello, e chi non ha lo scudo lo tiene
##      in mano da subito;
##  11. con un'arma a due mani il sigillo si sceglie posandola, e poi si torna;
##  12. il secondo set: il cambio mette in mano l'altra arma, con la sua presa.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_corpo_campione.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const CASATE := ["dawnkeep", "sylvorn", "vorrkai", "aethon", "verath", "amareth"]
const ATTESE := 6 * 12
const LAMA := "res://arcanium/resources/weapons/lama_ricurva.tres"
const SPADONE := "res://arcanium/resources/weapons/spadone_guarnigione_sylvorn.tres"
const SCUDO_GENERICO := "res://arcanium/resources/equipment/scudo_legno_ferro.tres"
const CorpoCampione := preload("res://arcanium/systems/corpo_campione.gd")

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	for casa in CASATE:
		salva._house = casa
		root.get_node("EquipmentLoadout").clear_all()
		var scheda : Resource = load("res://arcanium/resources/campioni/%s.tres" % casa)
		var glb : Node = (load(scheda.corpo) as PackedScene).instantiate()
		var sk_glb : Skeleton3D = glb.find_children("*", "Skeleton3D", true, false)[0]
		var ossa_glb := sk_glb.get_bone_count()
		glb.free()

		var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
		scena.get_node("Dungeon").seme = 0
		root.add_child(scena)
		for k in 10:
			await process_frame
		var pl : Node = scena.get_node("Player")
		var corpo : Node = pl.get_node("CorpoCampione")
		var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")

		## 1.
		var visibili : Array = []
		var con_skin_vecchia := 0
		for m in sk.get_children():
			if m is MeshInstance3D:
				var mi := m as MeshInstance3D
				if mi.visible and mi.mesh != null:
					visibili.append(String(mi.name))
				elif mi.skin != null:
					con_skin_vecchia += 1
		_ok(corpo.campione == scheda and sk.get_bone_count() == ossa_glb and visibili.size() >= 1
				and con_skin_vecchia == 0,
				"%s: corpo di %s, %d ossa (GLB %d), mesh %s, skin vecchie %d" % [casa,
				corpo.campione.nome if corpo.campione != null else "nessuno", sk.get_bone_count(), ossa_glb,
				str(visibili), con_skin_vecchia])

		## 2.
		var storti : Array = []
		for ba in pl.find_children("*", "BoneAttachment3D", true, false):
			var b := ba as BoneAttachment3D
			if b.bone_name != "" and b.use_external_skeleton and b.get_node_or_null(b.external_skeleton) == sk \
					and sk.find_bone(b.bone_name) < 0:
				storti.append(b.bone_name)
		_ok(storti.is_empty() and sk.find_bone("RightHand") >= 0 and sk.find_bone("LeftHand") >= 0,
				"%s: gli agganci trovano le loro ossa %s" % [casa, str(storti)])

		## 3.
		var ap : AnimationPlayer = pl.get_node("protagonist/AnimationPlayer")
		var idle := ap.get_animation("MeleeLib/LightIdle")
		var fendente := ap.get_animation("MeleeLib/root-Slash1")
		ap.play("MeleeLib/LightIdle")
		ap.seek(0.0, true)
		## Le mani sotto la meta' fra bacino e petto: la guardia del moveset le
		## tiene davanti al petto. Sotto il BACINO era troppo stretto per i corpi
		## ARP, che nella Posa (gomiti piegati di 14 gradi) le portano all'altezza
		## dell'anca: Kessra 1,4 cm sopra, Rashan 2 mm sotto (2026-11-02).
		var bacino := sk.get_bone_global_pose(sk.find_bone("Hips")).origin.y
		var petto := sk.get_bone_global_pose(sk.find_bone("Chest")).origin.y
		var soglia := (bacino + petto) * 0.5
		var mani_giu := sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin.y < soglia \
				and sk.get_bone_global_pose(sk.find_bone("RightHand")).origin.y < soglia
		## LightIdle parte dalla Posa (e' la Posa, o l'idle d'autore di chi ha
		## un'arma leggera, che dalla Posa parte). Con l'idle d'autore, la clip
		## del tipo dell'arma del kit (CorpoCampione.idle_sostituita) e' quella
		## (durata e tracce), in loop, e ogni sua traccia trova il suo osso.
		var da_fermo := mani_giu
		var come := "in Posa con le mani sotto la vita (%s)" % mani_giu
		if String(scheda.idle) != "":
			var d_autore := CorpoCampione.idle_d_autore(scheda.idle, sk)
			var nome_clip := CorpoCampione.idle_sostituita(scheda)
			var clip := ap.get_animation("MeleeLib/" + nome_clip) if nome_clip != "" else null
			var senza_osso := 0
			if clip != null:
				for t in clip.get_track_count():
					if sk.find_bone(String(clip.track_get_path(t).get_concatenated_subnames())) < 0:
						senza_osso += 1
			da_fermo = d_autore != null and clip != null and mani_giu and senza_osso == 0 \
					and is_equal_approx(clip.length, d_autore.length) \
					and clip.get_track_count() == d_autore.get_track_count() \
					and clip.loop_mode == Animation.LOOP_LINEAR
			come = "nell'idle d'autore %s al posto di %s (%.1f s, %d tracce, %d senza osso), LightIdle dalla Posa %s" % [
					String(scheda.idle).get_file(), nome_clip, clip.length if clip != null else 0.0,
					clip.get_track_count() if clip != null else 0, senza_osso, mani_giu]
		_ok(idle != null and da_fermo and fendente != null and fendente.get_track_count() > 0,
				"%s: da fermo %s, il fendente c'e' (%d tracce)" % [casa,
				come, fendente.get_track_count() if fendente != null else 0])

		## 4.
		var arm : Node = pl.get_node_or_null("ArmaturaIndossata")
		_ok(arm == null or (arm.get_script() == null and arm.process_mode == Node.PROCESS_MODE_DISABLED),
				"%s: ArmaturaIndossata spenta" % casa)

		## 5.
		var armadio : Node = root.get_node("EquipmentLoadout")
		var arma_kit : Resource = load(scheda.dotazione["arma_primaria"])
		var in_mano = pl.get_node("WeaponSystem").current_equipment
		var info = in_mano.equipment_info if in_mano != null else null
		var scudo : Node3D = corpo._gadget(pl, "block_resistances")
		var vuole_scudo : bool = scheda.dotazione.has("scudo")
		_ok(armadio.equipped_in("arma_primaria") == arma_kit and info == arma_kit and scudo.visible == vuole_scudo,
				"%s: kit di casata, in mano %s, scudo %s" % [casa,
				info.name if info != null and "name" in info else "-", "visibile" if scudo.visible else "nascosto"])

		## 6.
		var spada : Node3D = pl.get_node("WeaponSystem/RightHand/HandPivot/Sword")
		_ok(spada.transform.is_equal_approx(scheda.presa_arma)
				and scudo.transform.is_equal_approx(scheda.presa_sinistra("SCUDO", armadio.equipped_in("scudo"))["presa"]),
				"%s: la presa del corpo su arma e scudo (%s)" % [casa,
				"sistemata a mano" if scheda.presa_arma != Transform3D.IDENTITY else "quella del player"])

		## 7.
		var presa : Node = sk.get_node_or_null("PresaManoDestra")
		var vuole : bool = scheda.chiusura_mano_destra != 0.0
		_ok((presa == null) != vuole and (presa == null or (presa._pieghe.size() >= 6
				and is_equal_approx(presa.chiusura, scheda.chiusura_mano_destra)
				and is_equal_approx(presa.pollice, scheda.pollice_mano_destra))),
				"%s: dita sull'impugnatura %s" % [casa,
				"chiuse a %.2f, pollice %.2f, %d pieghe" % [presa.chiusura, presa.pollice, presa._pieghe.size()]
				if presa != null else "come nelle clip"])

		## 8. Come lo annuncia held_weapon.gd: weapon_type e il segnale.
		## Ogni tipo scritto dal banco (l'arco, lo spadone a due mani con la
		## seconda mano), o uno qualunque se la scheda non ne ha.
		var kit_tipo : String = scheda.tipo_del_kit()
		var altri : Array = scheda.prese.keys()
		if altri.is_empty():
			altri = ["BOW" if kit_tipo != "BOW" else "SLASH"]
		var cambiata := true
		for altro in altri:
			var attesa : Dictionary = scheda.presa_per(altro)
			pl.weapon_type = altro
			pl.weapon_change_ended.emit(altro)
			var dita : Node = sk.get_node_or_null("PresaManoDestra")
			cambiata = cambiata and spada.transform.is_equal_approx(attesa["presa_arma"]) \
					and (dita == null) == (attesa["chiusura_mano_destra"] == 0.0) \
					and (dita == null or is_equal_approx(dita.chiusura, attesa["chiusura_mano_destra"])) \
					and (sk.get_node_or_null("SecondaMano") != null) == bool(attesa["seconda_mano_attiva"])
		pl.weapon_type = kit_tipo
		pl.weapon_change_ended.emit(kit_tipo)
		var dita_kit : Node = sk.get_node_or_null("PresaManoDestra")
		var tornata : bool = spada.transform.is_equal_approx(scheda.presa_arma) \
				and (dita_kit == null or is_equal_approx(dita_kit.chiusura, scheda.chiusura_mano_destra)) \
				and (sk.get_node_or_null("SecondaMano") != null) == scheda.seconda_mano_attiva
		_ok(cambiata and tornata, "%s: con %s la presa di quel tipo (%s), poi di nuovo quella del kit" % [casa,
				", ".join(altri), "dal banco" if not scheda.prese.is_empty() else "quella del kit"])

		## 9. Lo scudo dell'armadio sul nodo Shield: modello e resistenze suoi,
		## e toglierlo rimette le cose come stavano.
		var generico : Resource = load(SCUDO_GENERICO)
		var kit_scudo : Resource = armadio.equipped_in("scudo")
		armadio.equip("scudo", generico)
		var modello : Node3D = scudo.get_node_or_null("ModelloEquipaggiato")
		var indossato : bool = scudo.equipment_info == generico and modello != null \
				and modello.transform.is_equal_approx(generico.held_transform) \
				and not (scudo.get_node("ShieldMesh") as Node3D).visible
		if kit_scudo != null:
			armadio.equip("scudo", kit_scudo)
		else:
			armadio.unequip("scudo")
		var riposto : bool = kit_scudo == null or (scudo.equipment_info == kit_scudo
				and scudo.get_node_or_null("ModelloEquipaggiato") == null
				and (scudo.get_node("ShieldMesh") as Node3D).visible)
		_ok(indossato and riposto, "%s: lo scudo generico in mano col suo modello, poi via" % casa)

		## 10. Il sigillo della casata: suo il modello (la Prima Veglia e' quello
		## della scena), e in mano da subito per chi non ha lo scudo.
		var sigillo : Node3D = corpo._gadget(pl, "is_spell_focus")
		var suo : Resource = load(scheda.dotazione["arma_secondaria"])
		var col_modello : bool = (sigillo.get_node_or_null("ModelloEquipaggiato") != null) == (suo.held_model != null)
		var mano_giusta : bool = kit_scudo != null or pl.get_node("GadgetSystem").current_equipment == sigillo
		var due_mani : bool = kit_tipo in ["BOW", "HEAVY"]
		var si_lancia : bool = pl.has_spell_focus() == (kit_scudo == null and not due_mani)
		_ok(sigillo.equipment_info == suo and col_modello and mano_giusta and si_lancia,
				"%s: %s, %s" % [casa, suo.name, "sul fianco, in mano lo scudo" if kit_scudo != null
				else ("non si lancia con l'arma a due mani" if due_mani else "in mano, si lancia")])

		## 11. Scegliere il sigillo con un'arma a due mani la posa: si lancia, la
		## destra e' vuota, non c'e' seconda mano; tornare all'arma rimette tutto.
		var due_mani_ok := true
		if due_mani:
			pl.gadget_change()
			var impugnatura : Node = pl.get_node("HeldWeapon")
			due_mani_ok = impugnatura.arma_riposta and pl.has_spell_focus() and not spada.visible and sigillo.visible \
					and pl.weapon_type == "SLASH" and sk.get_node_or_null("SecondaMano") == null \
					and sk.get_node_or_null("PresaManoDestra") == null
			pl.gadget_change()
			due_mani_ok = due_mani_ok and not impugnatura.arma_riposta and not pl.has_spell_focus() and spada.visible \
					and pl.weapon_type == kit_tipo and (sk.get_node_or_null("SecondaMano") != null) == scheda.seconda_mano_attiva
		_ok(due_mani_ok, "%s: %s" % [casa, "il sigillo posa l'arma, e si torna" if due_mani else "il sigillo sta con la sua arma"])

		## 12. Il secondo set: l'arma del kit non si sposta se lascia la mano vuota;
		## col cambio set l'altra arma e' in mano con la sua presa, e il sigillo si
		## usa o no a seconda di quante mani vuole; poi si torna.
		var altra : Resource = load(LAMA if due_mani else SPADONE)
		var rifiutata : bool = not armadio.equip("arma_riserva", arma_kit)
		armadio.equip("arma_riserva", altra)
		var cambiato : bool = armadio.cambia_set()
		var sistema_arma : Node = pl.get_node("WeaponSystem")
		var altro_tipo : String = String(altra.object_type)
		var con_altra : bool = cambiato and armadio.equipped_in("arma_primaria") == altra \
				and armadio.equipped_in("arma_riserva") == arma_kit and sistema_arma.current_equipment.equipment_info == altra \
				and pl.weapon_type == altro_tipo and spada.transform.is_equal_approx(scheda.presa_per(altro_tipo)["presa_arma"]) \
				and pl.has_spell_focus() == (due_mani and kit_scudo == null)
		armadio.cambia_set()
		armadio.unequip("arma_riserva")
		var di_nuovo : bool = armadio.equipped_in("arma_primaria") == arma_kit and pl.weapon_type == kit_tipo \
				and not armadio.cambia_set()
		_ok(rifiutata and con_altra and di_nuovo, "%s: secondo set %s (%s), poi di nuovo il kit" % [casa, altra.name, altro_tipo])

		root.remove_child(scena)
		scena.free()
		await process_frame

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
