extends SceneTree

## Il BANCO DELLE IMPUGNATURE di un campione, generato dalla sua scheda:
## arcanium/tools/banco_impugnatura_<nome>.tscn, dove l'autore sistema a mano
## la presa (vedi CampioneResource.presa_arma / presa_scudo).
##
## Dentro: il GLB del campione nella posa in cui sta in gioco da fermo con
## l'arma del suo kit (a riposo la presa veniva di lato, Edran 2026-10-23),
## gli agganci RightHand e LeftHand con i perni del player, `Sword` con dentro
## il modello dell'arma del kit (held_model) e `Shield` se il kit ha lo scudo.
## Sword e Shield partono dalla presa gia' nella scheda.
##
## La posa: con un'arma a una mano la POSA del GLB (fotogramma 0); con
## un'arma a due mani la GUARDIA A DUE MANI di guardia_due_mani.gd (asta
## verticale sul fianco destro, destra sopra e sinistra sotto), perche' la
## sinistra deve trovare l'asta (Zarine, Aurin).
##
## I nodi aggiunti dentro il GLB vogliono `[editable path=...]`, o il primo
## salvataggio dall'editor li butta via: qui si mette da se'. Si genera una
## volta per campione: rigenerarlo cancella cio' che l'autore ha sistemato e
## non e' ancora nella scheda.
##
## Uso: godot --headless --path . --script res://arcanium/tools/banco_impugnatura.gd -- <casata> [uscita.tscn] [corpo.glb]
## Con `corpo` il banco monta quel GLB al posto di quello della scheda: il
## corpo nuovo sullo scheletro ARP, prima di passarlo alla scheda (2026-11-01).
## Le prese della scheda, misurate sulla mano del corpo vecchio, partono
## convertite sulla mano del corpo nuovo (presa_su_scheletro.gd, 2026-11-02).
##
## Con `arma=<risorsa.tres>` il banco e' per un'arma che non e' quella del kit
## (l'equipaggiamento e' intercambiabile: l'arco in mano a Edran, 2026-11-02).
## La presa parte da quella della scheda per quel TIPO d'arma
## (CampioneResource.prese) o, se non c'e', da quella del campione che ha quel
## tipo nel kit (l'arco di Ilwen), portata sulla mano di questo corpo. Il banco
## si ricorda l'arma (metadata `arma`): dal_banco_alla_scheda.gd scrive la
## presa nel tipo giusto.
##
## Con `fonte=<casata>` la presa di partenza e' quella che quel campione ha
## per quel tipo d'arma (la scheda dopo il suo banco): lo spadone sistemato a
## mano su Ilwen portato sugli altri, 2026-11-02.
##
## Con `sinistra=<risorsa.tres>` in mano sinistra c'e' quello scudo o quel
## sigillo, con l'arma a una mano in destra (2026-11-07): il banco si ricorda il
## pezzo (metadata `sinistra`). La faccia viene dalla presa di chi ha lo scudo nel
## kit (Edran), portata sulla mano di questo corpo; il disco, scudo o sigillo, si
## mette col centro della maniglia o il suo sul palmo (PresaSuScheletro.sul_palmo).
## Con `sinistra_da=<banco.tscn>` la presa e le dita della sinistra vengono da quel
## banco, portate sulla mano di questo corpo: il sigillo di Edran sugli altri.

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const SPADA := "res://characters/equipment/sword_arcane.tscn"
const SCUDO := "res://player/equipment_system/equipment/shield.tscn"
const SIGILLO := "res://player/equipment_system/equipment/sigillo_gadget.tscn"
const PERNO_DESTRA := "WeaponSystem/RightHand/HandPivot"
const PERNO_SINISTRA := "GadgetSystem/LeftHand/HandPivot"
const PRESA_MANO := "res://arcanium/systems/presa_mano.gd"
## Il centro della maniglia dello scudo, nello spazio del suo modello (monta_scudo.py).
const MANIGLIA := Vector3(0, 0, 0.043)
const PosaMenu := preload("res://arcanium/systems/posa_menu.gd")
const Guardia := preload("res://arcanium/tools/guardia_due_mani.gd")
const PresaSuScheletro := preload("res://arcanium/tools/presa_su_scheletro.gd")


func _init() -> void:
	var tutti := OS.get_cmdline_user_args()
	var args := Array(tutti).filter(func(a): return not String(a).contains("="))
	var arma_scelta := ""
	var casata_fonte := ""
	var sinistra_scelta := ""
	var banco_sinistra := ""
	for a in tutti:
		if String(a).begins_with("sinistra_da="):
			banco_sinistra = String(a).trim_prefix("sinistra_da=")
		elif String(a).begins_with("sinistra="):
			sinistra_scelta = String(a).trim_prefix("sinistra=")
		if String(a).begins_with("arma="):
			arma_scelta = String(a).trim_prefix("arma=")
		if String(a).begins_with("fonte="):
			casata_fonte = String(a).trim_prefix("fonte=")
	if args.is_empty():
		push_error("uso: ... -- <casata> [uscita.tscn]")
		quit(1)
		return
	var scheda : Resource = load("res://arcanium/resources/campioni/%s.tres" % args[0])
	var nome := String(scheda.nome).split(" ")[0]
	var uscita : String = args[1] if args.size() > 1 else "res://arcanium/tools/banco_impugnatura_%s.tscn" % nome.to_lower()
	var corpo_glb : String = args[2] if args.size() > 2 else String(scheda.corpo)
	var kit : Resource = load(scheda.dotazione["arma_primaria"]) if scheda.dotazione.has("arma_primaria") else null
	if arma_scelta != "":
		kit = load(arma_scelta)
	var tipo := String(kit.object_type) if kit != null and String(kit.object_type) != "" else "SLASH"
	var pesante := tipo == "HEAVY"

	## I perni delle mani, dalla
	## scena del player (non entra nell'albero).
	var pl : Node = (load(PLAYER) as PackedScene).instantiate()
	var perno_d : Transform3D = (pl.get_node(PERNO_DESTRA) as Node3D).transform
	var perno_s : Transform3D = (pl.get_node(PERNO_SINISTRA) as Node3D).transform
	## La presa di partenza: quella della scheda per questo tipo d'arma, o
	## quella di chi ha questo tipo nel kit.
	var p : Dictionary = scheda.presa_per(tipo)
	var corpo_fonte := String(scheda.corpo)
	var fonte := nome
	if casata_fonte != "":
		var altro : Resource = load("res://arcanium/resources/campioni/%s.tres" % casata_fonte)
		p = altro.presa_per(tipo)
		corpo_fonte = String(altro.corpo)
		fonte = String(altro.nome).split(" ")[0]
	elif tipo != scheda.tipo_del_kit() and not scheda.prese.has(tipo):
		for f in DirAccess.get_files_at("res://arcanium/resources/campioni"):
			var altro : Resource = load("res://arcanium/resources/campioni/" + f) if f.ends_with(".tres") else null
			if altro != null and altro.has_method("tipo_del_kit") and altro.tipo_del_kit() == tipo:
				p = altro.presa_per(tipo)
				corpo_fonte = String(altro.corpo)
				fonte = String(altro.nome).split(" ")[0]
				break
	var presa_arma : Transform3D = p["presa_arma"]
	var presa_scudo : Transform3D = scheda.presa_scudo
	var corpo_scudo := String(scheda.corpo)
	var sinistra : Resource = load(sinistra_scelta) if sinistra_scelta != "" else null
	if sinistra != null and not scheda.dotazione.has("scudo"):
		for f in DirAccess.get_files_at("res://arcanium/resources/campioni"):
			var altro : Resource = load("res://arcanium/resources/campioni/" + f) if f.ends_with(".tres") else null
			if altro != null and "dotazione" in altro and altro.dotazione.has("scudo"):
				presa_scudo = altro.presa_scudo
				corpo_scudo = String(altro.corpo)
				break
	if corpo_glb != corpo_fonte:
		var da := PresaSuScheletro.scheletro(corpo_fonte)
		var a := PresaSuScheletro.scheletro(corpo_glb)
		presa_arma = PresaSuScheletro.converti(presa_arma, perno_d, da, a, "Right")
		PresaSuScheletro.libera(da)
		PresaSuScheletro.libera(a)
	if corpo_glb != corpo_scudo:
		var da := PresaSuScheletro.scheletro(corpo_scudo)
		var a := PresaSuScheletro.scheletro(corpo_glb)
		presa_scudo = PresaSuScheletro.converti(presa_scudo, perno_s, da, a, "Left")
		PresaSuScheletro.libera(da)
		PresaSuScheletro.libera(a)

	## La posa, letta da un'istanza nell'albero.
	var corpo : Node3D = (load(corpo_glb) as PackedScene).instantiate()
	PosaMenu.assicura(corpo)
	root.add_child(corpo)
	var sk : Skeleton3D = corpo.find_children("*", "Skeleton3D", true, false)[0]
	var posa := ""
	if pesante:
		## La guardia a due mani costruita con l'IK (guardia_due_mani.gd):
		## quella della HeavyIdle portata col retarget teneva l'asta in
		## diagonale e la sinistra lontana (l'utente, 2026-11-01).
		Guardia.applica(sk)
		posa = "guardia a due mani"
	else:
		for n in corpo.find_children("*", "AnimationPlayer", true, false):
			var ap := n as AnimationPlayer
			if ap.has_animation("Posa"):
				ap.play("Posa")
				ap.seek(0.0, true)
				posa = "Posa"
	pl.free()
	var p_sk := String(corpo.get_path_to(sk))

	## Il testo della scena, come lo salva l'editor (una scena salvata con
	## PackedScene.pack si portava dentro tutte le mesh del GLB: 3,5 MB).
	var risorse := [corpo_glb, SPADA]
	var modello : PackedScene = kit.held_model if kit != null and "held_model" in kit else null
	if modello != null:
		risorse.append(modello.resource_path)
	var con_scudo : bool = scheda.dotazione.has("scudo") and not tipo in ["BOW", "HEAVY"] and sinistra == null
	if con_scudo:
		risorse.append(SCUDO)
	var e_scudo : bool = sinistra != null and "block_resistances" in sinistra
	var modello_scudo : PackedScene = sinistra.held_model if e_scudo else null
	if sinistra != null:
		risorse.append(SCUDO if e_scudo else SIGILLO)
		if modello_scudo != null:
			risorse.append(modello_scudo.resource_path)
	var t := "[gd_scene format=3]\n\n"
	for k in risorse.size():
		t += '[ext_resource type="PackedScene" path="%s" id="%d"]\n' % [risorse[k], k + 1]
	t += '[ext_resource type="Script" path="%s" id="presa_mano"]\n' % PRESA_MANO
	t += '\n[node name="BancoImpugnatura%s" type="Node3D"]\n' % nome
	if arma_scelta != "":
		t += 'metadata/arma = "%s"\n' % arma_scelta
	if sinistra != null:
		t += 'metadata/sinistra = "%s"\n' % sinistra_scelta
	t += '\n'
	t += '[node name="%s" parent="." instance=ExtResource("1")]\n\n' % nome
	t += '[node name="%s" parent="%s/%s"]\n' % [sk.name, nome, p_sk.get_base_dir()]
	for b in sk.get_bone_count():
		if not sk.get_bone_pose_position(b).is_equal_approx(sk.get_bone_rest(b).origin):
			t += "bones/%d/position = %s\n" % [b, var_to_str(sk.get_bone_pose_position(b))]
		t += "bones/%d/rotation = %s\n" % [b, var_to_str(sk.get_bone_pose_rotation(b))]
	t += "\n"
	var p_osso := "%s/%s" % [nome, p_sk]
	t += _mano(p_osso, "RightHand", perno_d, "Sword", 2, presa_arma)
	var p_spada := "%s/RightHand/HandPivot/Sword" % p_osso
	var editabili := [nome]
	if modello != null:
		## Il modello dell'arma del kit, come lo monta held_weapon.gd: quelli
		## della spada del player si spengono.
		var spada : Node = (load(SPADA) as PackedScene).instantiate()
		for figlio in spada.get_children():
			if figlio is VisualInstance3D:
				t += '[node name="%s" parent="%s"]\nvisible = false\n\n' % [figlio.name, p_spada]
		spada.free()
		t += '[node name="ModelloEquipaggiato" parent="%s" instance=ExtResource("3")]\ntransform = %s\n\n' % [
				p_spada, var_to_str(kit.held_transform)]
		editabili.append(p_spada)
	if con_scudo:
		t += _mano(p_osso, "LeftHand", perno_s, "Shield", risorse.find(SCUDO) + 1, presa_scudo)
	if sinistra != null:
		var pezzo := "Shield" if e_scudo else "Sigillo_Gadget"
		## Il punto del pezzo che va sul palmo: il centro della maniglia, che sul
		## modello dello scudo sta sul retro del disco, o il centro del sigillo.
		var punto := Vector3(0, 0.0285, 0)
		if modello_scudo != null:
			punto = sinistra.held_transform * MANIGLIA
		presa_scudo = PresaSuScheletro.sul_palmo(presa_scudo, perno_s, sk, "Left", punto)
		p["chiusura_mano_sinistra"] = 0.6 if e_scudo else 0.5
		p["pollice_mano_sinistra"] = 0.0
		if banco_sinistra != "":
			var b : Node = (load(banco_sinistra) as PackedScene).instantiate()
			var da := PresaSuScheletro.scheletro(b.get_child(0).scene_file_path)
			var a := PresaSuScheletro.scheletro(corpo_glb)
			presa_scudo = PresaSuScheletro.converti((b.find_child(pezzo, true, false) as Node3D).transform,
					perno_s, da, a, "Left")
			var dita : Node = b.find_child("PresaManoSinistra", true, false)
			p["chiusura_mano_sinistra"] = float(dita.get("chiusura"))
			p["pollice_mano_sinistra"] = float(dita.get("pollice"))
			PresaSuScheletro.libera(da)
			PresaSuScheletro.libera(a)
			b.free()
		t += _mano(p_osso, "LeftHand", perno_s, pezzo, risorse.find(SCUDO if e_scudo else SIGILLO) + 1, presa_scudo)
		if modello_scudo != null:
			## Il modello dell'armadio al posto di quello della scena, come fa
			## held_weapon.gd.
			var p_scudo := "%s/LeftHand/HandPivot/Shield" % p_osso
			t += '[node name="ShieldMesh" parent="%s"]\nvisible = false\n\n' % p_scudo
			t += '[node name="ModelloEquipaggiato" parent="%s" instance=ExtResource("%d")]\ntransform = %s\n\n' % [
					p_scudo, risorse.find(modello_scudo.resource_path) + 1, var_to_str(sinistra.held_transform)]
			editabili.append(p_scudo)
	## Le dita chiuse come in gioco (presa_mano.gd e' @tool): la presa si
	## sistema sulla mano vera, non su quella aperta. I due nodi ci sono
	## sempre, anche a chiusura 0 (la mano aperta): l'autore la alza dal banco
	## (l'arco di Ilwen, 2026-11-02). In gioco 0 vuol dire nessuna presa.
	for lato in [["Destra", "Right", p["chiusura_mano_destra"], p["pollice_mano_destra"]],
			["Sinistra", "Left", p["chiusura_mano_sinistra"], p["pollice_mano_sinistra"]]]:
		t += '[node name="PresaMano%s" type="SkeletonModifier3D" parent="%s"]\nscript = ExtResource("presa_mano")\nlato = "%s"\nchiusura = %s\npollice = %s\n\n' % [
				lato[0], p_osso, lato[1], var_to_str(lato[2]), var_to_str(lato[3])]
	for e in editabili:
		t += '[editable path="%s"]\n' % e
	var f := FileAccess.open(uscita, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	print("BANCO: %s, posa %s, in mano %s (%s, presa di %s)%s -> %s" % [nome, posa if posa != "" else "MANCANTE",
			kit.name if kit != null else "la spada del player", tipo, fonte, ", scudo" if con_scudo else "", uscita])
	quit()


## Aggancio all'osso, perno del player e l'oggetto con la presa della scheda.
func _mano(p_osso : String, osso : String, perno : Transform3D, nome : String, risorsa : int,
		presa : Transform3D) -> String:
	var t := '[node name="%s" type="BoneAttachment3D" parent="%s"]\nbone_name = "%s"\n\n' % [osso, p_osso, osso]
	t += '[node name="HandPivot" type="Marker3D" parent="%s/%s"]\ntransform = %s\n\n' % [p_osso, osso, var_to_str(perno)]
	t += '[node name="%s" parent="%s/%s/HandPivot" instance=ExtResource("%d")]\ntransform = %s\n\n' % [
			nome, p_osso, osso, risorsa, var_to_str(presa)]
	return t
