@tool
extends SceneTree
## CANCELLO: ogni nemico dichiara le famiglie di clip che il suo moveset USA?
##
## godot --headless --script res://arcanium/tools/verifica_famiglie_anim.gd
##
## ⚠️ Perche' esiste. Sulla Traccia Perduta i quattro Consumati erano rimasti
## con `famiglie_anim = ["sword"]` dopo una prova delle meccaniche Sylvorn. Ma
## `consumato_moveset.tres` usa SOLO clip `spear/`: senza quella libreria il
## nemico insegue e non attacca MAI. E non lo dice nessuno -- `_carica_famiglia`
## salta in silenzio le clip che non trova, per scelta («una famiglia a meta' e'
## meglio di un nemico senza clip»), quindi non c'e' nemmeno un warning.
##
## Si controllano le SCENE dei nemici e i LIVELLI, perche' un livello puo'
## sovrascrivere `famiglie_anim` sull'istanza -- ed e' esattamente quello che
## era successo.

## Le famiglie e le loro clip, lette dallo script del nemico invece che
## ricopiate: una lista ricopiata invecchia e mente.
const FAMIGLIE := preload("res://arcanium/systems/enemies/arcanium_humanoid_enemy.gd").FAMIGLIE

const SCENE_DIRS := ["res://arcanium/characters/", "res://arcanium/levels/"]

func _init() -> void:
	var problemi : PackedStringArray = []
	var mancanti : PackedStringArray = []
	var visti := 0
	for d in SCENE_DIRS:
		for f in _tscn(d):
			var pk := load(f) as PackedScene
			if pk == null:
				continue
			var radice : Node = pk.instantiate()
			for n in _tutti(radice):
				if not (n is CharacterBody3D) or not ("famiglie_anim" in n) or not ("move_set" in n):
					continue
				var ms = n.get("move_set")
				if ms == null:
					continue
				visti += 1
				var dichiarate := {}
				for fam in n.get("famiglie_anim"):
					dichiarate[str(fam)] = true
				var servono := {}
				# (a) le clip del MOVESET
				for m in ms.moves:
					_famiglia(str(m.anim), servono)
				# ⚠️ (b) e TUTTE le altre clip che il nodo nomina, che sono di piu'
				# e contano quanto le prime: `sword` non tiene solo gli attacchi,
				# ci stanno dentro locomozione, morte, colpo subito, poise-break
				# e le COPPIE VICTIM DEI FINISHER del protagonista
				# (`*_victim_anim` / `*_getup_anim`). Un nemico che lascia cadere
				# `sword` perche' «attacca di lancia» perde tutto quello -- e il
				# giocatore lo vede quando lo finisce e non succede niente.
				for prop in n.get_property_list():
					if prop["type"] == TYPE_STRING and str(prop["name"]).ends_with("_anim"):
						_famiglia(str(n.get(prop["name"])), servono)
				for s in servono:
					if not dichiarate.has(s):
						problemi.append("%s :: %s -- serve la famiglia '%s' (%s) ma famiglie_anim dichiara %s"
							% [f.get_file(), n.name, s, servono[s], str(n.get("famiglie_anim"))])
				# ⚠️ E la clip deve ESISTERE, non basta che la famiglia sia
				# dichiarata. Le due scene del Fante non dichiaravano affatto
				# idle/walk/run/death/hurt: restavano ai default dello script,
				# "idle" e "walk" NUDI, che in nessuna libreria esistono. Il
				# nemico sarebbe nato senza locomozione e senza morte, in
				# silenzio -- `_play()` salta una clip che non trova.
				for prop2 in n.get_property_list():
					if prop2["type"] != TYPE_STRING or not str(prop2["name"]).ends_with("_anim"):
						continue
					var clip : String = str(n.get(prop2["name"]))
					if clip == "":
						continue
					var fam : String = clip.get_slice("/", 0) if clip.contains("/") else ""
					var nome : String = clip.get_slice("/", 1) if clip.contains("/") else clip
					if fam == "" or not FAMIGLIE.has(fam) or not (nome in FAMIGLIE[fam]):
						mancanti.append("%s :: %s -- %s = \"%s\""
							% [f.get_file(), n.name, prop2["name"], clip])
			radice.queue_free()
	_verifica_bone_map()

	print("=== %d nemici con moveset controllati ===" % visti)
	if problemi.is_empty():
		print("TUTTO A POSTO: ogni nemico dichiara le famiglie che gli servono.")
	else:
		for p in problemi:
			print("  ROTTO  " + p)
		print("%d nemici non caricherebbero le proprie clip." % problemi.size())
	# ⚠️ Seconda lista, e NON e' fatale di proposito: clip nominate da una
	# proprieta' ma che non esistono ancora nel pack. Oggi sono tutte le
	# `sword_guard_*`, cioe' la guardia con lo scudo: il nemico assorbe il danno
	# ma non alza mai lo scudo. E' un buco vero, non un falso positivo -- ma
	# farne fallire il cancello lo terrebbe rosso finche' quelle clip non
	# esistono, e un cancello sempre rosso non lo guarda piu' nessuno.
	if not mancanti.is_empty():
		print("
=== clip nominate e MAI AUTORATE (%d) ===" % mancanti.size())
		var viste := {}
		for m in mancanti:
			var c : String = m.get_slice("= ", 1)
			viste[c] = int(viste.get(c, 0)) + 1
		for c in viste:
			print("  %-44s citata da %d nemici" % [c, viste[c]])
	quit(0 if problemi.is_empty() else 1)

## Registra la famiglia di una clip, tenendo un esempio per il messaggio.
func _famiglia(clip : String, dentro : Dictionary) -> void:
	if clip.contains("/"):
		dentro[clip.get_slice("/", 0)] = clip


func _tscn(d : String) -> PackedStringArray:
	var fuori : PackedStringArray = []
	var dir := DirAccess.open(d)
	if dir == null:
		return fuori
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			fuori.append(d + f)
	return fuori

func _tutti(n : Node) -> Array[Node]:
	var fuori : Array[Node] = [n]
	for c in n.get_children():
		fuori.append_array(_tutti(c))
	return fuori

## ⚠️⚠️ OGNI CLIP DEVE AVERE LA BONE MAP NEL PROPRIO `.import`, O META' DELLE SUE
## TRACCE CADE NEL VUOTO — E NON LO DICE NESSUNO.
##
## Lo scheletro in gioco usa la convenzione Nephilite-Godot (`Spine`, `Chest`,
## `LeftUpperArm`, `LeftFoot`). I GLB del pack e quelli autorati in Cascadeur
## usano invece la convenzione del pack (`Spine_01`, `Shoulder_L`, `Ankle_L`).
## A riconciliarle e' la `retarget/bone_map` dichiarata nel `.import` di ogni
## singola clip, che rinomina le ossa durante l'importazione.
##
## Un `.glb` nuovo entra con `_subresources={}` — nessuna mappa. Le sue tracce
## restano coi nomi del pack, e in gioco NON TROVANO L'OSSO: si perdono in
## silenzio, senza un errore, senza un avviso.
##
## Misurato il 2026-08-25 sulla botta di scudo appena autorata: **8 tracce
## agganciate su 34, diciannove ossa perse** — tutta la spina, tutte e due le
## braccia, tutte e due le gambe. Restavano bacino, collo e testa, e il
## personaggio si vedeva COLCATO A TERRA. Diagnosi sbagliate prima di trovarla:
## rotazione del `Root`, nodo dell'armatura, ossi d'aggancio, riposo del corpo —
## tutte falsificate leggendo il GLB, che infatti era sano. Il difetto non stava
## nell'asset: stava in una riga del `.import`.
##
## Questo controllo costa la lettura di un file di testo e chiude l'intera
## classe. Non e' fatale: dice quali clip sono nude, e si copia il blocco da una
## che funziona.
func _verifica_bone_map() -> void:
	var nude : PackedStringArray = []
	var con_mappa := 0
	for famiglia in FAMIGLIE:
		for clip in FAMIGLIE[famiglia]:
			var glb : String = "res://assets/characters/enemies/anims/%s/%s.glb" % [famiglia, clip]
			if not ResourceLoader.exists(glb):
				continue          # gia' segnalata dall'altra lista
			var imp := FileAccess.open(glb + ".import", FileAccess.READ)
			if imp == null:
				nude.append("%s (nessun .import: mai importata dall'editor)" % clip)
				continue
			var testo := imp.get_as_text()
			imp.close()
			if testo.contains("retarget/bone_map"):
				con_mappa += 1
			else:
				nude.append(clip)
	if nude.is_empty():
		print("ok    tutte e %d le clip importate hanno la bone map" % con_mappa)
		return
	print("")
	print("=== ⚠️ CLIP SENZA BONE MAP NEL .import (%d) ===" % nude.size())
	print("    Le loro tracce useranno i nomi del pack e in gioco NON troveranno")
	print("    l'osso: spina, braccia e gambe si perdono in silenzio.")
	for c in nude:
		print("  NUDA  " + c)
	print("    Cura: copiare il blocco `_subresources` da una clip che funziona")
	print("    (es. sword_idle_01.glb.import) e reimportare dall'editor.")
