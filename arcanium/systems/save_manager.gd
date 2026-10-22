extends Node

## Gestione del salvataggio unico di Arcanium (autoload "SaveManager"). Un solo
## slot, su ConfigFile in user://arcanium_save.cfg. Sostituisce ed estende il
## vecchio ProgressionTracker (assorbe l'esito del Prologo).
##
## Ciclo di vita:
##  - "Nuova Partita" → creazione personaggio → begin_new_run(house, gender):
##    imposta la run in memoria e AZZERA il salvataggio su disco (l'avviso di
##    sovrascrittura è nel menu, prima di arrivare qui).
##  - Durante il gioco: set_outcome() alla vittoria/sconfitta contro il Senza Nome.
##  - Primo salvataggio vero: record_checkpoint(resume_scene) alla transizione
##    verso il Crocevia (PrologueDirector) → has_save() diventa true.
##  - "Continua" (menu) compare solo se has_save(); ricarica get_resume_scene().

const SAVE_PATH := "user://arcanium_save.cfg"
const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")

# Stato della run corrente (in memoria).
var _house : String = HouseCatalog.DEFAULT_HOUSE
var _gender : String = "male"
var _outcome : String = ""   # "" | "defeated" | "victorious"
var _resume_scene : String = ""

# Guard anti-autosave: true mentre _restore_state() sta ripopolando
# PlayerFlags/QuestManager/PlayerStats dal cfg, per evitare che i loro
# segnali 'changed' triggerino una persist_state() a metà ripristino.
var _restoring : bool = false

func _ready() -> void:
	# Carica la run persistita in memoria (così "Continua" riprende con la casata giusta).
	var cfg := _load_cfg()
	if cfg:
		_house = str(cfg.get_value("save", "house", _house))
		_gender = str(cfg.get_value("save", "gender", _gender))
		_outcome = str(cfg.get_value("save", "outcome", _outcome))
		_resume_scene = str(cfg.get_value("save", "resume_scene", _resume_scene))
	_applica_voce()

	# Differito: PlayerFlags/QuestManager/PlayerStats sono autoload registrati
	# DOPO SaveManager in project.godot, quindi non esistono ancora qui dentro.
	call_deferred("_restore_state")

## True se esiste un salvataggio valido su disco (→ mostra "Continua").
func has_save() -> bool:
	var cfg := _load_cfg()
	return cfg != null and str(cfg.get_value("save", "resume_scene", "")) != ""

func get_resume_scene() -> String:
	var cfg := _load_cfg()
	if cfg:
		return str(cfg.get_value("save", "resume_scene", ""))
	return ""

## Avvia una nuova run dalla creazione personaggio. Azzera il salvataggio su disco
## (sovrascrittura confermata a monte nel menu).
## Sesso del personaggio -> voce del protagonista.
##
## ⚠️ Va spinta da QUI e non letta da `Suoni`: `Suoni` e' una classe statica
## senza accesso all'albero, e soprattutto il sesso appartiene alla RUN (come la
## casata), non alle preferenze — chi comincia una partita nuova col sesso
## opposto deve sentire l'altra voce, e chi carica una partita vecchia deve
## risentire la sua.
func _applica_voce() -> void:
	Suoni.voce = Suoni.Voce.FEMMINILE if _gender == "female" else Suoni.Voce.MASCHILE


func begin_new_run(house : String, gender : String) -> void:
	_house = house
	_gender = gender
	_applica_voce()
	_outcome = ""
	_resume_scene = ""
	# clear_all() non emette 'changed': azzerare qui non fa scattare l'autosave
	# (che comunque sarebbe no-op finché _resume_scene è vuoto).
	PlayerFlags.clear_all()
	PlayerStats.clear_all()
	## ⚠️⚠️ Anche l'ARMADIO e lo ZAINO, che prima restavano com'erano. Cancellare
	## il file di salvataggio non azzera la memoria: gli autoload attraversano il
	## cambio scena, e una partita nuova ripartiva con quello che si aveva
	## addosso nella precedente — visto in gioco, si cominciava col Manto del
	## Branco Guasto e con la Spada del Senza Nome, cioe' la ricompensa di un
	## boss che si stava ancora affrontando.
	##
	## ⚠️ L'ordine conta: prima l'armadio, poi lo zaino. La dotazione iniziale
	## dello zaino passa dal ponte `_concedi_equipaggiabile`, che scrive
	## nell'armadio; azzerando l'armadio dopo si butterebbe via quello che il
	## ponte ha appena concesso.
	var armadio := get_node_or_null("/root/EquipmentLoadout")
	if armadio and armadio.has_method("clear_all"):
		armadio.call("clear_all")
	var zaino := get_node_or_null("/root/ArcaniumInventory")
	if zaino and zaino.has_method("clear_all"):
		zaino.call("clear_all")
	## Le tecniche che il campione sa gia' (Ilwen: l'Arcieria). Dopo
	## PlayerFlags.clear_all, che le aveva appena tolte.
	_tecniche_del_campione()
	## ⚠️ E i CONI. Restavano tutti accesi: il viaggio rapido li elencava e da
	## una partita nuova si arrivava a Kalvorn senza fare la Traccia Perduta.
	var coni := get_node_or_null("/root/CheckpointManager")
	if coni and coni.has_method("clear_all"):
		coni.call("clear_all")
	## Livello e portafoglio ripartono da zero: sono progressi della RUN, non
	## preferenze del giocatore.
	var prog := get_node_or_null("/root/MarcheProgression")
	if prog and prog.has_method("reset"):
		prog.call("reset")
	var banca := get_node_or_null("/root/CrystalBank")
	if banca and banca.has_method("reset"):
		banca.reset()
	var abs := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(abs)

func _tecniche_del_campione() -> void:
	var scheda := "res://arcanium/resources/campioni/%s.tres" % _house
	if not ResourceLoader.exists(scheda):
		return
	var c : Resource = load(scheda)
	if c == null or not ("tecniche_iniziali" in c):
		return
	for percorso in c.tecniche_iniziali:
		var t : Resource = load(percorso) if ResourceLoader.exists(percorso) else null
		if t != null and "unlock_flag" in t and String(t.unlock_flag) != "":
			PlayerFlags.set_flag(t.unlock_flag)

## Esito del Prologo (in memoria durante il gioco; persistito al checkpoint).
func set_outcome(outcome : String) -> void:
	_outcome = outcome

func get_outcome() -> String:
	return _outcome

func get_house() -> String:
	return _house

func get_gender() -> String:
	return _gender

## Marche di partenza della casata corrente (derivate dal catalogo).
func get_marche() -> Dictionary:
	return HouseCatalog.get_house(_house).get("marche", {})

## Scrive il salvataggio vero (primo checkpoint = risveglio nel Crocevia).
## Singolo punto di scrittura: imposta lo stato e delega a persist_state().
func record_checkpoint(resume_scene : String) -> void:
	_resume_scene = resume_scene
	persist_state()

## Riscrive l'INTERO save su disco: sezione [save] (house/gender/outcome/
## resume_scene) più flags/quests/stats (PlayerFlags/QuestManager/PlayerStats,
## salvati come Dictionary diretti — ConfigFile serializza Variant, Dictionary
## incluso, senza bisogno di passare da JSON.stringify).
##
## Guard: nessuna scrittura finché non è avvenuto almeno un checkpoint
## (_resume_scene vuoto) — evita save prematuri durante il Prologo, PRIMA
## che il giocatore risvegli al Crocevia.
func persist_state() -> void:
	if _resume_scene == "":
		return

	var cfg := ConfigFile.new()
	cfg.set_value("save", "house", _house)
	cfg.set_value("save", "gender", _gender)
	cfg.set_value("save", "outcome", _outcome)
	cfg.set_value("save", "resume_scene", _resume_scene)

	cfg.set_value("flags", "data", PlayerFlags.to_dict())
	cfg.set_value("stats", "data", PlayerStats.to_dict())
	## Coni accesi: senza, il viaggio rapido dimentica al riavvio i checkpoint
	## già conquistati e tocca riaccenderli a piedi.
	var cm := get_node_or_null("/root/CheckpointManager")
	if cm and cm.has_method("to_dict"):
		cfg.set_value("checkpoints", "data", cm.call("to_dict"))

	## Livello e punti sulle Marche, comprati ai Coni.
	var prog := get_node_or_null("/root/MarcheProgression")
	if prog and prog.has_method("to_dict"):
		cfg.set_value("progressione", "data", prog.call("to_dict"))

	## Cosa possiedi e cosa indossi: senza, quello che compri da Solan
	## sparirebbe alla prima ricarica.
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout and loadout.has_method("to_dict"):
		cfg.set_value("equipaggiamento", "data", loadout.call("to_dict"))

	## ⚠️ E lo ZAINO, che prima non si salvava affatto. Non si notava perche'
	## l'autoload e' vivo per tutta la sessione: le pozioni raccolte c'erano
	## ancora dopo un cambio scena, e sembrava salvato. Chiudendo il gioco
	## tornavano quelle di partenza.
	var zaino := get_node_or_null("/root/ArcaniumInventory")
	if zaino and zaino.has_method("to_dict"):
		cfg.set_value("zaino", "data", zaino.call("to_dict"))

	## L'Arcanium Cristallizzato è la valuta con cui si sale di livello e si
	## compra da Solan: se non lo salviamo, riaprendo il gioco il giocatore
	## ritrova il livello pagato ma il portafoglio a zero.
	var banca := get_node_or_null("/root/CrystalBank")
	if banca:
		cfg.set_value("save", "crystals", int(banca.crystals))

	cfg.save(SAVE_PATH)

## Ripristina flag/quest/stat dal cfg su disco negli autoload dedicati
## (chiamato deferred da _ready, quando gli autoload esistono già) e
## collega l'autosave: ogni 'changed' di PlayerFlags/QuestManager/PlayerStats
## richiama persist_state() (autosave immediato souls-like), a meno che il
## ripristino stesso sia in corso (_restoring).
func _restore_state() -> void:
	_restoring = true

	var cfg := _load_cfg()
	if cfg:
		PlayerFlags.from_dict(cfg.get_value("flags", "data", {}))
		PlayerStats.from_dict(cfg.get_value("stats", "data", {}))
		var cm := get_node_or_null("/root/CheckpointManager")
		if cm and cm.has_method("from_dict"):
			cm.call("from_dict", cfg.get_value("checkpoints", "data", {}))
		var prog := get_node_or_null("/root/MarcheProgression")
		if prog and prog.has_method("from_dict"):
			prog.call("from_dict", cfg.get_value("progressione", "data", {}))
		var loadout := get_node_or_null("/root/EquipmentLoadout")
		if loadout and loadout.has_method("from_dict"):
			loadout.call("from_dict", cfg.get_value("equipaggiamento", "data", {}))
		## ⚠️ Lo zaino DOPO l'armadio: `from_dict` dello zaino non passa dal ponte
		## proprio per non rimettere in armadio cio' che si era venduto, quindi
		## e' l'armadio a dover avere l'ultima parola sul possesso.
		var zaino := get_node_or_null("/root/ArcaniumInventory")
		if zaino and zaino.has_method("from_dict"):
			zaino.call("from_dict", cfg.get_value("zaino", "data", {}))
		## ⚠️ Non dentro un torneo: questo ripristino e' differito, e arrivava
		## DOPO che il primo dungeon aveva aperto la run con la banca a zero.
		var banca := get_node_or_null("/root/CrystalBank")
		var torneo := get_node_or_null("/root/Torneo")
		if banca and not (torneo != null and torneo.in_corso):
			banca.crystals = int(cfg.get_value("save", "crystals", 0))
			banca.changed.emit(banca.crystals)
	else:
		PlayerFlags.from_dict({})
		PlayerStats.from_dict({})
		var prog := get_node_or_null("/root/MarcheProgression")
		if prog and prog.has_method("reset"):
			prog.call("reset")

	_restoring = false

	# is_connected guard: _restore_state() può essere richiamata più di una
	# volta (es. da test, o da un futuro reload esplicito) — senza il guard
	# Godot rifiuta la connect() doppia con un errore.
	if not PlayerFlags.changed.is_connected(_on_state_changed):
		PlayerFlags.changed.connect(_on_state_changed)
	if not PlayerStats.changed.is_connected(_on_state_changed):
		PlayerStats.changed.connect(_on_state_changed)

func _on_state_changed() -> void:
	if _restoring:
		return
	persist_state()

func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg
	return null
