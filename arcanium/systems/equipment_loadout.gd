extends Node

## ═══════════════════════════════════════════════════════════════════════════
## EQUIPAGGIAMENTO INDOSSATO (autoload: EquipmentLoadout)
## ═══════════════════════════════════════════════════════════════════════════
##
## Cosa il protagonista possiede e cosa indossa, e quali EFFETTI ne derivano.
##
## Prima non esisteva niente del genere: l'equipaggiamento era una costante
## `preload` dentro il menu, cioè cinque risorse fisse che nessuno poteva
## cambiare e che non influivano su nulla. Un pezzo d'armatura era un'etichetta.
##
## Qui vivono le due cose che rendono l'equipaggiamento una MECCANICA:
##   • le RESISTENZE che modificano il danno subito dal player;
##   • i BONUS ALLE EVOCAZIONI, per famiglia di creatura.
##
## Il menu legge e scrive qui; player e minion leggono gli effetti. Nessuno dei
## due sa dell'altro.
##
## ─── I LUCCHETTI: possedere non è saper usare ───────────────────────────────
## Un arco si trova prima di saperlo tirare (cade dal Soldato Scelto, sta in
## vetrina da Solan) ed entra nel posseduto come ogni pezzo. Ma si IMPUGNA solo
## sapendo l'Arcieria, che è una tecnica di guerra imparata dal suo tomo: la
## tecnica dichiara i tipi d'arma che apre (`TecnicaGuerra.abilita_tipi`,
## "BOW"), e `sbloccato()` lo chiede al suo flag. Il cancello sta QUI e non nel
## menu perché da qui passano tutte le strade — la modale, il ciclo, la
## ricarica di una partita salvata prima del lucchetto — e un cancello messo
## su una sola di esse è una porta chiusa con la finestra aperta.

## I quattro slot dei TALISMANI sono intercambiabili: un talismano dichiara la
## famiglia (`equip_slot = "talismano"`), non il numero, altrimenti entrerebbe
## solo nel primo. Il costo di portarne uno non e' rinunciare a un'arma — e'
## rinunciare a un ALTRO talismano, che e' la scelta interessante.
##
## ⚠️ I BRACCIALI hanno uno slot loro e non dividono "armatura_alta" con la
## corazza: sono due pezzi che si portano INSIEME, e nello stesso slot uno
## escluderebbe l'altro. Stessa ragione per cui i gambali non stanno con la
## corazza. Quando arriveranno i guanti vorranno il loro, non questo.
const EQUIP_SLOTS := ["arma_primaria", "arma_secondaria", "armatura_alta",
	"armatura_bassa", "bracciali", "scudo",
	"talismano_1", "talismano_2", "talismano_3", "talismano_4"]

## Slot numerati che condividono una famiglia: "talismano_2" → "talismano".
## Gli altri slot restituiscono se stessi.
const FAMIGLIE_NUMERATE := ["talismano"]

## Il CATALOGO di tutto ciò che esiste nel gioco, non ciò che si possiede: la
## scansione di queste cartelle dice quali pezzi sono stati creati, e il set
## `_posseduti` dice quali sono tuoi. Prima le due cose coincidevano — bastava
## che un .tres esistesse su disco perché il protagonista lo avesse indosso — e
## con un mercante quella scorciatoia diventava insostenibile: Solan avrebbe
## venduto oggetti già posseduti.
const EQUIP_DIRS := ["res://arcanium/resources/weapons/",
	"res://arcanium/resources/equipment/"]

const STARTER := {
	"arma_primaria": "res://arcanium/resources/weapons/lama_prima_veglia.tres",
	"arma_secondaria": "res://arcanium/resources/equipment/sigillo_prima_veglia.tres",
	"armatura_alta": "res://arcanium/resources/equipment/corazza_prima_veglia.tres",
	"armatura_bassa": "res://arcanium/resources/equipment/gambali_prima_veglia.tres",
	"bracciali": "res://arcanium/resources/equipment/bracciali_prima_veglia.tres",
	"scudo": "res://arcanium/resources/equipment/scudo_prima_veglia.tres",
}

const TecnicaGuerra := preload("res://arcanium/resources/tecnica_guerra.gd")

signal changed
## Emesso quando un pezzo entra o esce dal posseduto (acquisto, vendita, drop).
signal owned_changed

var equipped : Dictionary = {}

## Percorsi dei .tres posseduti, come insieme (percorso → true). È lo stato che
## il mercante modifica e che il salvataggio deve conservare.
var _posseduti : Dictionary = {}
## Catalogo per slot: cambia solo se qualcuno aggiunge file al progetto, quindi
## si legge dal disco una volta sola.
var _catalogo_cache : Dictionary = {}
## Tipo d'arma → tecnica di guerra che lo apre ("BOW" → Arcieria). Si
## costruisce dal catalogo delle tecniche alla prima domanda, una volta sola.
var _lucchetti : Dictionary = {}
var _lucchetti_letti : bool = false


func _ready() -> void:
	_dotazione_iniziale()


## Il kit con cui si comincia. Sta in una funzione sola perche' serve in DUE
## momenti — all'avvio del gioco e a ogni partita nuova — e due copie della
## stessa lista divergono al primo pezzo aggiunto.
##
## Il kit e' quello del CAMPIONE della run (`dotazione` della sua scheda in
## arcanium/resources/campioni/): ogni casata parte con le sue armi, e lo scudo
## e' solo di Dawnkeep. STARTER resta il kit di riserva, per quando la casata
## non ha una scheda.
func _dotazione_iniziale() -> void:
	var kit := kit_della_run()
	for slot in kit:
		if ResourceLoader.exists(kit[slot]):
			equipped[slot] = load(kit[slot])
			_posseduti[kit[slot]] = true


const CAMPIONI := "res://arcanium/resources/campioni/"

## Slot -> percorso della scheda, per la casata della run.
func kit_della_run() -> Dictionary:
	var salva := get_node_or_null("/root/SaveManager")
	var casa : String = String(salva.get_house()) if salva != null and salva.has_method("get_house") else ""
	var scheda := CAMPIONI + casa + ".tres"
	if casa != "" and ResourceLoader.exists(scheda):
		var c : Resource = load(scheda)
		if c != null and "dotazione" in c and not (c.dotazione as Dictionary).is_empty():
			return c.dotazione
	return STARTER


## Azzera tutto e rimette la dotazione iniziale (nuova partita).
##
## ⚠️ Serve perche' gli AUTOLOAD SOPRAVVIVONO al cambio scena: `begin_new_run`
## cancellava il file di salvataggio ma lasciava in memoria cio' che si aveva
## addosso. Risultato visto in gioco: partita nuova iniziata col Manto del
## Branco Guasto indosso e con la Spada del Senza Nome — che e' la ricompensa
## di un boss che si stava ancora affrontando. Cancellare il salvataggio non
## azzera la memoria.
func clear_all() -> void:
	equipped.clear()
	_posseduti.clear()
	_dotazione_iniziale()
	owned_changed.emit()
	changed.emit()


# ═══════════════════════════════════════════════════════════════════════════
# Possesso ed equipaggiamento
# ═══════════════════════════════════════════════════════════════════════════

func equipped_in(slot : String) -> Resource:
	return equipped.get(slot)


## TUTTI i pezzi compatibili con lo slot che esistono nel gioco, posseduti o no.
## È la vetrina del mercante, non l'armadio del protagonista.
func catalog_for_slot(slot : String) -> Array:
	if _catalogo_cache.has(slot):
		return _catalogo_cache[slot]
	var fuori : Array = []
	for dir_path in EQUIP_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			# In build i .tres diventano .remap: senza questo la lista sarebbe
			# vuota nel gioco esportato e piena solo in editor.
			var nome := f.trim_suffix(".remap")
			if not nome.ends_with(".tres"):
				continue
			var res = load(dir_path + nome)
			if res != null and "equip_slot" in res and accetta(slot, res):
				fuori.append(res)
	_catalogo_cache[slot] = fuori
	return fuori


## Famiglia di uno slot: "talismano_3" → "talismano", tutto il resto invariato.
func famiglia(slot : String) -> String:
	for f in FAMIGLIE_NUMERATE:
		if slot.begins_with(f + "_"):
			return f
	return slot


func accetta(slot : String, res : Resource) -> bool:
	if res == null or not ("equip_slot" in res):
		return false
	var dichiarato : String = str(res.equip_slot)
	return dichiarato == slot or dichiarato == famiglia(slot)


## I pezzi dello slot che il protagonista POSSIEDE davvero. Il menu equipaggia
## solo da qui: il catalogo serve a Solan, non all'armadio.
func owned_for_slot(slot : String) -> Array:
	var fuori : Array = []
	for res in catalog_for_slot(slot):
		if owns(res):
			fuori.append(res)
	return fuori


func owns(res : Resource) -> bool:
	return res != null and _posseduti.has(res.resource_path)


## La tecnica di guerra che serve per IMPUGNARE questo pezzo, o null se il suo
## tipo non ne chiede nessuna. Si legge dal tipo (`object_type`), non dal
## pezzo: un arco nuovo nasce chiuso senza che nessuno lo dichiari.
func tecnica_richiesta(res : Resource) -> Resource:
	if res == null or not ("object_type" in res):
		return null
	if not _lucchetti_letti:
		_lucchetti_letti = true
		for t in TecnicaGuerra.catalogo():
			if not ("abilita_tipi" in t):
				continue
			for tipo in t.abilita_tipi:
				_lucchetti[str(tipo)] = t
	return _lucchetti.get(str(res.object_type))


## Vero se il pezzo si può mettere addosso ADESSO: o non chiede nessuna
## tecnica, o quella tecnica è appresa. Il possesso è un'altra cosa (`owns`).
func sbloccato(res : Resource) -> bool:
	var t := tecnica_richiesta(res)
	return t == null or (t.has_method("appresa") and t.appresa(get_tree()))


## Entra in possesso di un pezzo (acquisto, drop, ricompensa di quest).
## Ritorna false se lo si aveva già: chi chiama non deve controllare prima.
func acquire(res : Resource) -> bool:
	if res == null or res.resource_path == "" or owns(res):
		return false
	_posseduti[res.resource_path] = true
	owned_changed.emit()
	changed.emit()
	return true


## Si separa da un pezzo (vendita). Ciò che si INDOSSA non si vende: restare a
## mani nude per un click sbagliato è un danno che il giocatore non ha scelto,
## e il menu non avrebbe più niente da mostrare nello slot.
func release(res : Resource) -> bool:
	if res == null or not owns(res):
		return false
	for slot in equipped:
		if equipped[slot] == res:
			return false
	_posseduti.erase(res.resource_path)
	owned_changed.emit()
	changed.emit()
	return true


func is_equipped(res : Resource) -> bool:
	if res == null:
		return false
	for slot in equipped:
		if equipped[slot] == res:
			return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
# Serializzazione per SaveManager
# ═══════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var indossati : Dictionary = {}
	for slot in equipped:
		if equipped[slot] != null:
			indossati[slot] = equipped[slot].resource_path
	return {"posseduti": _posseduti.keys(), "indossati": indossati}


func from_dict(d : Dictionary) -> void:
	if d == null or d.is_empty():
		return
	_posseduti = {}
	for p in d.get("posseduti", []):
		## Un pezzo tolto dal progetto dopo il salvataggio non deve piantare il
		## caricamento: si perde quel pezzo, non la partita.
		if ResourceLoader.exists(str(p)):
			_posseduti[str(p)] = true
	var indossati : Dictionary = d.get("indossati", {})
	for slot in indossati:
		var p := str(indossati[slot])
		if ResourceLoader.exists(p):
			equipped[slot] = load(p)
			_posseduti[p] = true
	## Un pezzo chiuso da un lucchetto non torna addosso da un salvataggio: o la
	## partita è di prima che il lucchetto esistesse, o il salvataggio è stato
	## toccato. Resta posseduto; nello slot torna il pezzo di partenza. I flag
	## sono già stati ripristinati (SaveManager li rimette prima di noi).
	for slot in equipped.keys():
		if equipped[slot] != null and not sbloccato(equipped[slot]):
			var t := tecnica_richiesta(equipped[slot])
			push_warning("EquipmentLoadout: '%s' era addosso senza sapere '%s' — tolto." % [
				str(equipped[slot].get("name")), str(t.get("name")) if t != null else "?"])
			var kit := kit_della_run()
			if kit.has(slot) and ResourceLoader.exists(kit[slot]):
				equipped[slot] = load(kit[slot])
				_posseduti[kit[slot]] = true
			else:
				equipped.erase(slot)
	owned_changed.emit()
	changed.emit()


## Ritorna vero se il pezzo è finito addosso. Falso se è chiuso da un
## lucchetto (`sbloccato`): chi chiama non deve controllare prima, ma non deve
## nemmeno fidarsi — la modale rilegge e resta aperta.
func equip(slot : String, res : Resource) -> bool:
	if res == null:
		return false
	if equipped.get(slot) == res:
		return true
	if not sbloccato(res):
		return false
	## Un oggetto e' UNO: se sta gia' in un altro slot lo si sposta, non lo si
	## duplica. Senza questo, con quattro slot intercambiabili si potrebbe
	## indossare lo stesso Anello quattro volte e sommarne il bonus.
	for altro in equipped.keys():
		if altro != slot and equipped[altro] == res:
			equipped.erase(altro)
	equipped[slot] = res
	changed.emit()
	return true


## Toglie ciò che sta in uno slot senza metterci altro. Sui talismani serve:
## avere quattro slot e nessun modo di lasciarne uno vuoto sarebbe una gabbia.
func unequip(slot : String) -> void:
	if not equipped.has(slot):
		return
	equipped.erase(slot)
	changed.emit()


## Passa al pezzo compatibile successivo. Usato dal menu. I pezzi chiusi da un
## lucchetto si saltano: il ciclo non deve inciampare su un arco che non si sa
## ancora tirare.
func cycle(slot : String, dir : int) -> void:
	var lista := owned_for_slot(slot)
	if lista.size() <= 1:
		return
	var i := lista.find(equipped_in(slot))
	if i < 0:
		i = 0
	for _passo in lista.size() - 1:
		i = (i + dir + lista.size()) % lista.size()
		if equip(slot, lista[i]):
			return


# ═══════════════════════════════════════════════════════════════════════════
# Effetti
# ═══════════════════════════════════════════════════════════════════════════

## Moltiplicatore di danno SUBITO per un tipo, dato tutto ciò che si indossa.
## I pezzi si moltiplicano fra loro: due da 0.9 fanno 0.81, non 0.8 — le
## protezioni si accumulano con rendimenti decrescenti invece di annullare il
## danno impilandone abbastanza.
func resistance_for(damage_type : String) -> float:
	var m := 1.0
	for slot in equipped:
		var res = equipped[slot]
		if res != null and "resistances" in res:
			m *= float(res.resistances.get(damage_type, 1.0))
	return m * resistenza_della_run(damage_type)


## I tipi di danno che «Allenati» (fisici) e «Studia» (magici) proteggono.
const DANNI_FISICI : PackedStringArray = ["FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "FRATTURA"]
const DANNI_MAGICI : PackedStringArray = ["CRIO", "EROSIONE", "SACRO", "VELENO", "FUOCO", "FULMINE"]
## Quanto resta del danno per ogni allenamento o studio (5% in meno a volta,
## che si moltiplica come le protezioni dei pezzi).
const RESISTENZA_PER_RIPOSO := 0.95


## La protezione guadagnata ai riposi della run (Torneo.allenamenti/studi).
func resistenza_della_run(damage_type : String) -> float:
	var torneo := get_node_or_null("/root/Torneo")
	if torneo == null or not ("allenamenti" in torneo):
		return 1.0
	if damage_type in DANNI_FISICI:
		return pow(RESISTENZA_PER_RIPOSO, int(torneo.allenamenti))
	if damage_type in DANNI_MAGICI:
		return pow(RESISTENZA_PER_RIPOSO, int(torneo.studi))
	return 1.0


## Moltiplicatore dell'Arcanium guadagnato per uccisione, dato ciò che si
## indossa. Lo legge `crystal_bounty.gd` al momento di accreditare.
func arcanium_multiplier() -> float:
	var bonus := 0.0
	for slot in equipped:
		var res = equipped[slot]
		if res != null and "arcanium_bonus" in res:
			bonus += float(res.arcanium_bonus)
	return 1.0 + bonus


## Moltiplicatore di danno per le evocazioni di una FAMIGLIA ("bestia", ...).
## I bonus si SOMMANO prima di applicarsi: due pezzi da +15% fanno +30%, che su
## un bonus offensivo è la lettura che il giocatore si aspetta.
func summon_multiplier(family : String) -> float:
	if family == "":
		return 1.0
	var bonus := 0.0
	for slot in equipped:
		var res = equipped[slot]
		if res != null and "summon_damage_bonus" in res:
			bonus += float(res.summon_damage_bonus.get(family, 0.0))
	return 1.0 + bonus


## Scrive le resistenze correnti dentro un ArcaniumHealthSystem. Da richiamare
## quando l'equipaggiamento cambia.
##
## Si parte SEMPRE dalle resistenze base del personaggio e si applicano sopra
## quelle dell'armatura: accumulare sul valore già scritto farebbe compounding a
## ogni cambio d'equipaggiamento, e dopo tre swap si diventerebbe invulnerabili.
func apply_to(health_system : Node) -> void:
	if health_system == null or not ("resistances" in health_system):
		return
	if not health_system.has_meta("resistenze_base"):
		health_system.set_meta("resistenze_base", health_system.resistances.duplicate())
	var base : Dictionary = health_system.get_meta("resistenze_base")
	var fuori : Dictionary = base.duplicate()
	for tipo in fuori:
		fuori[tipo] = float(fuori[tipo]) * resistance_for(tipo)
	health_system.resistances = fuori
