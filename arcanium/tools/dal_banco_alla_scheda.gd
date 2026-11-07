extends SceneTree

## DAL BANCO ALLA SCHEDA: legge il banco delle impugnature salvato dall'autore
## e stampa le righe della scheda del campione che ne vengono:
##   - presa_arma = Sword · modello · held_transform⁻¹ (l'autore muove sia
##     `Sword` sia `ModelloEquipaggiato`);
##   - chiusura_/pollice_mano_destra/sinistra dai due PresaMano;
##   - presa_scudo dallo `Shield`, se il kit ha lo scudo;
##   - seconda_mano = destra⁻¹ · sinistra, dalle pose delle ossa salvate nel
##     banco (la guardia a due mani, ritoccata a mano), se il kit non ha scudo.
## Le scrive nella scheda se si passa `scrivi`. Il corpo del banco (lo
## scheletro ARP, 2026-11-02) va nella scheda anche lui, come `corpo`.
##
## Un banco per un'arma che non e' quella del kit (metadata `arma`, l'arco in
## mano a Edran) scrive la sua presa in `prese[<tipo>]`
## (CampioneResource.prese) e non tocca corpo, scudo e la presa del kit.
## Un banco con un pezzo in mano sinistra (metadata `sinistra`) scrive solo
## `prese_sinistra[<SCUDO o SIGILLO>]`: presa e dita della sinistra.
##
## Uso: godot --headless --path . --script res://arcanium/tools/dal_banco_alla_scheda.gd -- <casata> <banco.tscn> [scrivi]

const CAMPI := ["corpo", "presa_arma", "chiusura_mano_destra", "chiusura_mano_sinistra", "pollice_mano_destra",
		"pollice_mano_sinistra", "presa_scudo", "seconda_mano_attiva", "seconda_mano"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var percorso_scheda := "res://arcanium/resources/campioni/%s.tres" % args[0]
	var scheda : Resource = load(percorso_scheda)
	var banco : Node = (load(args[1]) as PackedScene).instantiate()
	root.add_child(banco)
	await process_frame
	var sk : Skeleton3D = banco.find_children("*", "Skeleton3D", true, false)[0]
	var valori := {}
	var sword : Node3D = banco.find_child("Sword", true, false)
	var modello : Node3D = sword.get_node_or_null("ModelloEquipaggiato")
	var kit : Resource = load(String(banco.get_meta("arma", scheda.dotazione["arma_primaria"])))
	var tipo := String(kit.get("object_type")) if String(kit.get("object_type")) != "" else "SLASH"
	var del_kit : bool = tipo == scheda.tipo_del_kit()
	var presa : Transform3D = sword.transform
	if modello != null and "held_transform" in kit:
		presa = sword.transform * modello.transform * (kit.held_transform as Transform3D).affine_inverse()
	valori["presa_arma"] = presa
	var corpo_banco : Node = banco.get_child(0)
	if corpo_banco.scene_file_path != "":
		valori["corpo"] = corpo_banco.scene_file_path
	for l in [["Destra", "destra"], ["Sinistra", "sinistra"]]:
		var p := sk.get_node_or_null("PresaMano" + l[0])
		valori["chiusura_mano_" + l[1]] = _centesimi(float(p.get("chiusura"))) if p != null else 0.0
		valori["pollice_mano_" + l[1]] = _centesimi(float(p.get("pollice"))) if p != null else 1.0
	var shield : Node3D = banco.find_child("Shield", true, false)
	if shield != null:
		valori["presa_scudo"] = shield.transform
	## Solo le armi a due mani (HEAVY): con una lama o un martello a una mano
	## senza scudo la sinistra resta libera (Rashan, Kessra, 2026-11-02).
	if (not scheda.dotazione.has("scudo") or not del_kit) and tipo == "HEAVY":
		valori["seconda_mano_attiva"] = true
		valori["seconda_mano"] = sk.get_bone_global_pose(sk.find_bone("RightHand")).affine_inverse() \
				* sk.get_bone_global_pose(sk.find_bone("LeftHand"))
	var righe := []
	var sinistra := String(banco.get_meta("sinistra", ""))
	if sinistra != "":
		var pezzo : Resource = load(sinistra)
		var e_scudo : bool = "block_resistances" in pezzo
		var nodo : Node3D = banco.find_child("Shield" if e_scudo else "Sigillo_Gadget", true, false)
		var su_nodo : Transform3D = nodo.transform
		var suo_modello : Node3D = nodo.get_node_or_null("ModelloEquipaggiato")
		if suo_modello != null:
			su_nodo = nodo.transform * suo_modello.transform * (pezzo.held_transform as Transform3D).affine_inverse()
		var dita : Node = sk.get_node_or_null("PresaManoSinistra")
		var prese : Dictionary = scheda.prese_sinistra.duplicate(true)
		prese["SCUDO" if e_scudo else "SIGILLO"] = {"presa": su_nodo, "chiusura": _centesimi(float(dita.get("chiusura"))),
				"pollice": _centesimi(float(dita.get("pollice")))}
		righe.append("prese_sinistra = %s" % var_to_str(prese).replace("\n", " "))
	elif del_kit:
		for k in CAMPI:
			if valori.has(k):
				righe.append("%s = %s" % [k, var_to_str(valori[k])])
	else:
		## La presa di un altro tipo d'arma, in `prese`, su una riga sola (la
		## scrittura qui sotto lavora per righe).
		var prese : Dictionary = scheda.prese.duplicate(true)
		var questa := {}
		for k in scheda.CAMPI_PRESA:
			questa[k] = valori.get(k, scheda.presa_per(tipo)[k])
		if tipo != "HEAVY":
			questa["seconda_mano_attiva"] = false
		prese[tipo] = questa
		righe.append("prese = %s" % var_to_str(prese).replace("\n", " "))
	for r in righe:
		print("SCHEDA ", r)
	if "scrivi" in args:
		var testo := FileAccess.get_file_as_string(percorso_scheda)
		var linee := Array(testo.split("\n"))
		for r in righe:
			var nome : String = r.split(" = ")[0]
			var i := linee.find_custom(func(x): return String(x).begins_with(nome + " = "))
			if i >= 0:
				linee[i] = r
			else:
				var j := linee.find_custom(func(x): return String(x).begins_with("dotazione = "))
				linee.insert(j + 1 if j >= 0 else linee.size(), r)
		var f := FileAccess.open(percorso_scheda, FileAccess.WRITE)
		f.store_string("\n".join(linee))
		f.close()
		print("scritta ", percorso_scheda)
	quit()


## Al centesimo, senza il rumore di snappedf (1.4000000000000001 nella scheda):
## il quoziente per 100 e' il double piu' vicino al valore scritto.
static func _centesimi(v : float) -> float:
	return roundf(v * 100.0) / 100.0
