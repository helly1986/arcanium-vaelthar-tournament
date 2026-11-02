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
	var kit : Resource = load(scheda.dotazione["arma_primaria"])
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
	if not scheda.dotazione.has("scudo") and String(kit.get("object_type")) == "HEAVY":
		valori["seconda_mano_attiva"] = true
		valori["seconda_mano"] = sk.get_bone_global_pose(sk.find_bone("RightHand")).affine_inverse() \
				* sk.get_bone_global_pose(sk.find_bone("LeftHand"))
	var righe := []
	for k in CAMPI:
		if valori.has(k):
			righe.append("%s = %s" % [k, var_to_str(valori[k])])
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
