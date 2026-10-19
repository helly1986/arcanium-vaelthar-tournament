extends SceneTree

## ⛔ CANCELLO: quanto l'IMPORT ha riscritto lo scheletro?
##
## `retarget/rest_fixer/fix_silhouette` allinea le ossa alla posa di riferimento
## umanoide di Godot. Su alcune ossa e' quello che si vuole; su altre riscrive
## una posa che nell'asset era GIUSTA, e il difetto sembra di modellazione:
## i piedi del protagonista uscivano all'insu' perche' il fixer rendeva
## ORIZZONTALE un osso del piede che nel .glb puntava in avanti e in giu'.
##
## Qui si confronta osso per osso il rest importato con quello del .glb, e si
## ordina per scarto. Chi e' in cima e' quello che l'import ha piegato di piu'.
##
##     blender --background --factory-startup --python arcanium/tools/rest_da_blender.py -- \
##         <file.glb> <scarto>/rest.json
##     godot --headless --script res://arcanium/tools/verifica_rest_import.gd -- <file.glb> <scarto>/rest.json
##
## ⚠️ Senza argomenti guarda il corpo del protagonista e cerca il json accanto.

var _fatto := false


func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true

	var arg : PackedStringArray = OS.get_cmdline_user_args()
	var glb : String = arg[0] if arg.size() > 0 else "res://assets/characters/base_body/protagonista_v4.glb"
	var json_path : String = arg[1] if arg.size() > 1 else "res://arcanium/tools/_rest_blender.json"

	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		print("non trovo il json del rest di Blender: %s" % json_path)
		print("generalo con `rest_da_blender.py` (vedi l'intestazione di questo file)")
		quit(1)
		return true
	var atteso : Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var scena := Node.new()
	root.add_child(scena)
	current_scene = scena
	var nodo = load(glb).instantiate()
	scena.add_child(nodo)
	var scheletri : Array = nodo.find_children("*", "Skeleton3D", true, false)
	if scheletri.is_empty():
		print("nessuno scheletro in %s" % glb)
		quit(1)
		return true
	var sk : Skeleton3D = scheletri[0]

	## per ogni osso: di quanto si e' spostata la TESTA, e di quanto e' ruotata
	## la direzione testa->coda (che e' quella che si vede sulla pelle)
	var righe : Array = []
	var mancanti : Array = []
	for nome in atteso.keys():
		var i := sk.find_bone(nome)
		if i < 0:
			mancanti.append(nome)
			continue
		var t : Transform3D = sk.get_bone_global_rest(i)
		var t_att := Vector3(atteso[nome]["testa"][0], atteso[nome]["testa"][1], atteso[nome]["testa"][2])
		var c_att := Vector3(atteso[nome]["coda"][0], atteso[nome]["coda"][1], atteso[nome]["coda"][2])
		var d_testa : float = (t.origin - t_att).length()
		## la direzione dell'osso importato: dal figlio, se c'e', altrimenti l'asse Y
		## ⚠️ La direzione di un osso si legge dal FIGLIO, non dall'asse locale:
		## su un rig importato l'asse Y non e' garantito lungo l'osso. Per le
		## ossa FOGLIA (punte delle dita, Toes) un figlio non c'e' e il numero e'
		## solo una stima — si segnala invece di spacciarlo per misura.
		var dir_got : Vector3 = t.basis.y.normalized()
		var stimata := true
		## ⚠️ "figlio unico" non basta: `UpperArm` ha DUE figli, l'osso vero e il
		## suo `_twist_`. Scartando i twist il figlio buono si trova quasi
		## sempre, e mezza tabella smette di dirsi "stimata" quando non lo e'.
		var figli : PackedInt32Array = sk.get_bone_children(i)
		var candidati : Array = []
		for fig in figli:
			if not sk.get_bone_name(fig).contains("_twist_"):
				candidati.append(fig)
		if candidati.is_empty():
			candidati.assign(Array(figli))
		if candidati.size() >= 1:
			## il piu' lontano: su un osso con piu' figli e' quello che ne da'
			## la direzione (le dita partono tutte dalla mano, il polso no)
			var migliore : int = candidati[0]
			var d_max : float = 0.0
			for c in candidati:
				var dd : float = (sk.get_bone_global_rest(c).origin - t.origin).length()
				if dd > d_max:
					d_max = dd
					migliore = c
			if d_max > 1e-5:
				dir_got = (sk.get_bone_global_rest(migliore).origin - t.origin).normalized()
				stimata = false
		var dir_att : Vector3 = (c_att - t_att)
		var gradi : float = 0.0
		if dir_att.length() > 1e-5:
			gradi = rad_to_deg(dir_got.angle_to(dir_att.normalized()))
		righe.append({"osso": nome, "dm": d_testa, "gradi": gradi, "stimata": stimata})

	righe.sort_custom(func(a, b): return a["gradi"] > b["gradi"])
	print("=== %d ossa confrontate (%s) ===" % [righe.size(), glb.get_file()])
	print("%-26s %10s %10s" % ["osso", "spostata", "ruotata"])
	var storte := 0
	for r in righe:
		if r["gradi"] < 5.0 and r["dm"] < 0.005:
			continue
		storte += 1
		print("  %-24s %8.4f m %8.1f gradi%s"
			% [r["osso"], r["dm"], r["gradi"],
			   "   (foglia: direzione stimata)" if r["stimata"] else ""])
	if storte == 0:
		print("  nessuna: il rest importato e' quello del .glb")
	else:
		print()
		print("%d ossa riscritte dall'import (soglia: 5 gradi o 5 mm)." % storte)
		print("Se una di queste era GIUSTA nel .glb, mettila in")
		print("`retarget/rest_fixer/fix_silhouette/filter`: e' una lista di ESCLUSIONE.")
	## ⚠️ Le catene che si guardano sempre, anche se stanno sotto soglia: se una
	## sembra storta a occhio serve il NUMERO, non l'assenza dalla lista sopra.
	print()
	print("=== catene chiave, sotto o sopra soglia ===")
	var per_nome : Dictionary = {}
	for r in righe:
		per_nome[r["osso"]] = r
	for catena in [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes"],
			["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"],
			["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]]:
		var pezzi : Array = []
		for nome in catena:
			if per_nome.has(nome):
				pezzi.append("%s %.1f gradi" % [nome.replace("Left", ""), per_nome[nome]["gradi"]])
		print("  " + " | ".join(pezzi))

	if not mancanti.is_empty():
		print("ossa del .glb che l'import non ha: %s" % str(mancanti))
	quit(0)
	return true
