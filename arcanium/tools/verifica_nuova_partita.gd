extends SceneTree

## ⛔ CANCELLO: una partita nuova comincia davvero da zero?
##
## ⚠️⚠️ Il difetto che ha reso necessario questo cancello: **cancellare il
## salvataggio non azzera la memoria**. `EquipmentLoadout` e `ArcaniumInventory`
## sono autoload, e un autoload attraversa il cambio scena: `begin_new_run()`
## rimuoveva il file su disco e lasciava intatto cio' che si aveva addosso.
## Visto in gioco: partita nuova iniziata col Manto del Branco Guasto indosso e
## con la Spada del Senza Nome — la ricompensa di un boss che si stava ancora
## affrontando.
##
## Il collaudo sporca lo stato di proposito e poi controlla che la partita nuova
## lo pulisca. Non basta guardare il file: il file era gia' giusto.
##
##     godot --headless --script res://arcanium/tools/verifica_nuova_partita.gd
##
## ⚠️ `begin_new_run()` CANCELLA `user://arcanium_save.cfg`. Il cancello se ne
## fa una copia e la rimette a posto: un collaudo non distrugge la partita di
## chi lo lancia.

const SALVATAGGIO := "user://arcanium_save.cfg"
const COPIA := "user://arcanium_save.cfg.collaudo"
const MANTO := "res://arcanium/resources/equipment/manto_branco_guasto.tres"
const SPADA := "res://arcanium/resources/weapons/lama_prima_veglia.tres"

var guasti := 0
var _fatto := false


func _sia(condizione : bool, cosa : String) -> void:
	if condizione:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


func _copia(da : String, a : String) -> bool:
	if not FileAccess.file_exists(da):
		return false
	var sorgente := FileAccess.open(da, FileAccess.READ)
	var dest := FileAccess.open(a, FileAccess.WRITE)
	if sorgente == null or dest == null:
		return false
	dest.store_buffer(sorgente.get_buffer(sorgente.get_length()))
	return true


func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true

	var salva := root.get_node_or_null("SaveManager")
	var armadio := root.get_node_or_null("EquipmentLoadout")
	var zaino := root.get_node_or_null("ArcaniumInventory")
	var coni := root.get_node_or_null("CheckpointManager")
	_sia(salva != null and armadio != null and zaino != null,
		"gli autoload ci sono (SaveManager, EquipmentLoadout, ArcaniumInventory)")
	if salva == null or armadio == null or zaino == null:
		quit(1)
		return true

	var c_era := _copia(SALVATAGGIO, COPIA)
	print("  salvataggio dell'utente: %s" % ("messo al riparo" if c_era else "non ce n'era"))

	print()
	print("=== si sporca lo stato, come farebbe una partita giocata ===")
	if ResourceLoader.exists(MANTO):
		var manto = load(MANTO)
		armadio.acquire(manto)
		armadio.equip("armatura_alta", manto)
	if ResourceLoader.exists(SPADA):
		armadio.acquire(load(SPADA))
	var oggetto = load("res://arcanium/resources/items/bracciali_prima_veglia.tres")
	zaino.add(oggetto, 3, true)
	## e si accendono due Coni, come dopo qualche ora di gioco
	if coni != null:
		coni.register_cone("collaudo_branco", "res://arcanium/levels/arena_branco.tscn",
			Transform3D.IDENTITY, "Arena del branco")
		coni.register_cone("collaudo_prova", "res://arcanium/levels/arena_prova.tscn",
			Transform3D.IDENTITY, "Arena di prova")
		coni.set_checkpoint("res://arcanium/levels/arena_prova.tscn",
			Transform3D.IDENTITY, "collaudo_prova")
	var addosso_prima = armadio.equipped_in("armatura_alta")
	print("  addosso in 'armatura_alta': %s" % (addosso_prima.name if addosso_prima else "niente"))
	print("  oggetti nello zaino: %d" % zaino.slots.size())
	_sia(addosso_prima != null and addosso_prima.name.contains("Manto"),
		"lo stato e' sporco: c'e' il manto addosso")
	_sia(zaino.has_item("bracciali_prima_veglia"), "e c'e' roba in piu' nello zaino")
	if coni != null:
		print("  Coni accesi: %d" % coni.known_cones().size())
		_sia(coni.known_cones().size() >= 2, "e ci sono Coni accesi")

	print()
	print("=== NUOVA PARTITA ===")
	salva.begin_new_run("dawnkeep", "male")

	var addosso = armadio.equipped_in("armatura_alta")
	print("  addosso in 'armatura_alta': %s" % (addosso.name if addosso else "niente"))
	_sia(addosso != null and addosso.name.contains("Corazza"),
		"torna la corazza della dotazione iniziale, non il manto")
	_sia(not armadio.owns(load(MANTO)) if ResourceLoader.exists(MANTO) else true,
		"il manto non risulta piu' posseduto")

	## ogni slot deve avere esattamente cio' che dice STARTER
	for slot in armadio.STARTER:
		var atteso : String = armadio.STARTER[slot]
		var res = armadio.equipped_in(slot)
		_sia(res != null and res.resource_path == atteso,
			"slot '%s' -> %s" % [slot, atteso.get_file()])
	_sia(armadio._posseduti.size() == armadio.STARTER.size(),
		"si possiede SOLO la dotazione iniziale: %d pezzi, non %d"
		% [armadio.STARTER.size(), armadio._posseduti.size()])

	print("  oggetti nello zaino: %d" % zaino.slots.size())
	_sia(not zaino.has_item("bracciali_prima_veglia"),
		"lo zaino non ha piu' la roba della partita precedente")
	_sia(zaino.has_item("fiala_sangue_eco"),
		"ma ha la dotazione iniziale (la fiala)")
	_sia(zaino.slots.size() == 1, "e solo quella: %d voci" % zaino.slots.size())

	## ⚠️ I CONI: se restano accesi si arriva a Kalvorn senza fare la Traccia.
	if coni != null:
		print("  Coni accesi dopo la partita nuova: %d" % coni.known_cones().size())
		_sia(coni.known_cones().is_empty(),
			"nessun Cono acceso, non %d" % coni.known_cones().size())
		_sia(not coni.has_checkpoint,
			"e nessun punto di risveglio ereditato dalla partita precedente")
		_sia(coni.scene_path == "",
			"la scena di risveglio e' vuota, non '%s'" % coni.scene_path)

	print()
	print("=== e lo ZAINO sopravvive a un salva/ricarica? ===")
	## ⚠️ Il difetto era invisibile in sessione: l'autoload resta vivo, quindi le
	## pozioni raccolte c'erano ancora dopo un cambio scena e sembrava salvato.
	## Si vedeva solo CHIUDENDO il gioco. Qui si simula: si scrive il
	## salvataggio, si svuota la memoria, si ricarica da disco.
	zaino.add(oggetto, 2, true)
	var pozione = load("res://arcanium/resources/items/fiala_sangue_eco.tres")
	zaino.add(pozione, 4, true)
	var voci_prima : int = zaino.slots.size()
	var fiale_prima := 0
	for sl in zaino.slots:
		if sl.def != null and sl.def.id == "fiala_sangue_eco":
			fiale_prima = sl.count
	print("  prima di salvare: %d voci, %d fiale" % [voci_prima, fiale_prima])

	salva.record_checkpoint("res://arcanium/levels/arena_prova.tscn")
	zaino.clear_all()
	print("  memoria svuotata: %d voci" % zaino.slots.size())
	salva._restore_state()
	print("  dopo la ricarica: %d voci" % zaino.slots.size())
	_sia(zaino.slots.size() == voci_prima,
		"lo zaino torna con le sue %d voci, non %d" % [voci_prima, zaino.slots.size()])
	_sia(zaino.has_item("bracciali_prima_veglia"),
		"e ci sono ancora i bracciali raccolti")
	var fiale_dopo := 0
	for sl in zaino.slots:
		if sl.def != null and sl.def.id == "fiala_sangue_eco":
			fiale_dopo = sl.count
	_sia(fiale_dopo == fiale_prima,
		"e le fiale sono ancora %d, non %d (il CONTEGGIO va salvato, non solo l'oggetto)"
		% [fiale_prima, fiale_dopo])

	## ⚠️⚠️ Si rimette il salvataggio dov'era, e NON basta ricopiare il file.
	##
	## La prima versione ricopiava e basta, e il file finiva comunque diverso:
	## `record_checkpoint()` qui sopra ha riempito `_resume_scene`, e da quel
	## momento QUALUNQUE `changed` di PlayerFlags/QuestManager/PlayerStats fa
	## scattare l'autosave — che riscrive il salvataggio DOPO il ripristino, con
	## lo stato del collaudo dentro. Me ne sono accorto confrontando i byte
	## fuori dal cancello: il cancello si dichiarava a posto e non lo era.
	##
	## Quindi prima si SPEGNE l'autosave svuotando `_resume_scene` — con quello
	## vuoto `persist_state()` esce subito — e solo dopo si ricopia.
	if c_era:
		salva._resume_scene = ""
		var tornato := _copia(COPIA, SALVATAGGIO)
		_sia(tornato, "il salvataggio dell'utente e' stato rimesso a posto")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPIA))

	print()
	if guasti == 0:
		print("TUTTO A POSTO: una partita nuova comincia da zero.")
	else:
		print("%d CONTROLLI FALLITI" % guasti)
	quit(1 if guasti > 0 else 0)
	return true
