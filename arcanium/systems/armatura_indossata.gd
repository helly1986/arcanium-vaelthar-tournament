@tool
extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ARMATURA INDOSSATA
## ═══════════════════════════════════════════════════════════════════════════
##
## Fa combaciare ciò che il menu dice di indossare con ciò che il protagonista
## indossa davvero. È il gemello di `held_weapon.gd`: quello riguarda ciò che si
## stringe in mano, questo ciò che si porta addosso. La differenza non è di
## dettaglio — un'arma è RIGIDA e sta appesa a un osso solo, un pezzo d'armatura
## si DEFORMA e va legato a tutto lo scheletro.
##
## ⚠️ Per questo un pezzo d'armatura NON si appende a un BoneAttachment3D. Un
## bracciale appeso all'avambraccio segue l'avambraccio e basta: sul gomito si
## stacca. Ciò che serve è un `MeshInstance3D` con la sua `Skin`, messo come
## FIGLIO dello Skeleton3D del personaggio — è il modo in cui Godot lega una
## mesh a uno scheletro, ed è esattamente com'è fatta la vecchia `ArmorChest`.
##
## ## Come fa a legarsi a uno scheletro che non è il suo
##
## I pezzi arrivano dentro un `.glb` che porta con sé una COPIA dello scheletro
## (`vesti_protagonista.py` pesa le piastre sulle 61 ossa di `GeneralSkeleton`).
## Qui la copia si butta via e si tengono solo le mesh: riparentate sotto il
## `GeneralSkeleton` vero, la loro `Skin` si risolve PER NOME D'OSSO, perché
## l'import tiene `skins/use_named_skins=true`. Nessun rimappaggio a mano.
##
## ⚠️ Il corollario da non dimenticare: le ossa devono chiamarsi uguale. Un
## personaggio con una convenzione diversa non indossa questa armatura, e il
## sintomo è una piastra che resta ferma nell'origine mentre il corpo cammina.
##
## ## ⚠️⚠️ E devono avere lo STESSO REST — cioè lo stesso import
##
## Non basta che le ossa si chiamino uguale: devono anche stare nello stesso
## posto **a riposo**. Il corpo si importa con `retarget/bone_map` e
## `rest_fixer/fix_silhouette`, che RISCRIVONO il rest dello scheletro; se il
## `.glb` delle piastre non ha le stesse impostazioni, il suo rest resta quello
## di Blender, la sua `Skin` è calcolata su quello, e legandola allo scheletro
## corretto le piastre finiscono altrove.
##
## Misurato fra i due scheletri, prima di allinearli: bacino e torace
## coincidevano, ma **LeftHand era fuori di 56 cm**, LeftLowerArm di 30, e le
## ossa degli arti ruotate fra gli 84 e i 172 gradi. In gioco si vedeva così:
## corazza a posto, ginocchiere a metà coscia e stinchi calati sotto il piede,
## con la gamba nuda in mezzo. Sembra un problema di vestizione ed è un problema
## di IMPORT.
##
## La regola: **un `.glb` che deve condividere uno scheletro condivide anche le
## impostazioni di retarget.** Vedi `prima_veglia_set.glb.import`, che porta lo
## stesso blocco `_subresources` di `protagonista_v4.glb.import`.
##
## ## Perché non si è preso il sistema di vestizione del forum
##
## La strada segnalata (il "3D RPG clothing and inventory system" di Godot)
## porta con sé un inventario suo. Qui l'inventario ESISTE già ed è più avanti:
## `EquipmentLoadout` ha gli slot, il possesso, il salvataggio e gli effetti sul
## danno. Mancava solo il pezzo visivo, che è questo file. L'unica idea che vale
## la pena rubargli è che sia l'OGGETTO a dichiarare quali regioni di pelle
## copre — vedi `worn_pieces` sulla risorsa, e la nota sulla maschera in fondo.

## Lo scheletro da vestire. Sotto di lui finiscono le piastre.
@export var skeleton : Skeleton3D

## Gli slot di `EquipmentLoadout` che vestono il corpo. L'ordine non conta.
@export var slots : PackedStringArray = ["armatura_alta", "armatura_bassa", "bracciali"]

## Cosa indossare quando `EquipmentLoadout` non c'è: nell'editor e sui banchi di
## taratura non ci sono autoload, e senza questo il banco mostrerebbe un corpo
## nudo proprio dove serve guardare l'armatura.
@export var pezzi_fissi : Array[Resource] = [] : set = _set_pezzi_fissi


## Marchio sui nodi che appendiamo noi. Serve a ritirarli al cambio successivo
## senza sfiorare le mesh che stanno nella scena da sempre (il corpo, e le
## vecchie ArmorChest/ArmorLegs): quelle si nascondono, non si cancellano.
const META_MIO := "armatura_indossata"

var _loadout : Node


func _ready() -> void:
	if Engine.is_editor_hint():
		_applica()
		return
	_loadout = get_node_or_null("/root/EquipmentLoadout")
	if _loadout != null and _loadout.has_signal("changed"):
		_loadout.changed.connect(_applica)
	## `EquipmentLoadout._ready()` riempie il loadout iniziale, e fra autoload e
	## scena l'ordine non è garantito: si aspetta un frame invece di scommetterci.
	## Stessa ragione, stessa riga, di `held_weapon.gd`.
	await get_tree().process_frame
	_applica()


func _set_pezzi_fissi(v : Array[Resource]) -> void:
	pezzi_fissi = v
	if is_inside_tree():
		_applica()


## Le risorse che decidono cosa si indossa: il loadout se c'è, altrimenti i
## pezzi fissi del banco.
func _indossati() -> Array:
	## ⚠️ I pezzi fissi VINCONO sul loadout quando ci sono, non fanno da ripiego.
	## Prima cedevano il passo appena `EquipmentLoadout` esisteva — e gli autoload
	## esistono anche quando si preme play su un banco. Risultato: il banco della
	## vestizione mostrava quello che aveva addosso il SALVATAGGIO, non i pezzi che
	## si stavano tarando. Un banco che mostra un'altra cosa non serve a niente.
	if not pezzi_fissi.is_empty():
		return Array(pezzi_fissi)
	if _loadout == null:
		return []
	var fuori : Array = []
	for slot in slots:
		var res = _loadout.equipped_in(slot)
		if res != null:
			fuori.append(res)
	return fuori


func _applica() -> void:
	if skeleton == null:
		push_warning("ArmaturaIndossata: nessuno scheletro da vestire.")
		return
	_spoglia()
	for res in _indossati():
		_indossa(res)


## Toglie solo ciò che abbiamo appeso noi.
func _spoglia() -> void:
	for c in skeleton.get_children():
		if c.has_meta(META_MIO):
			c.free()   ## subito, non queue_free: sotto ricontiamo i figli


## Appende le piastre di UN pezzo equipaggiato.
func _indossa(res : Resource) -> void:
	if res == null or not ("worn_model" in res):
		return
	var modello : PackedScene = res.worn_model
	if modello == null:
		return
	var voluti : PackedStringArray = res.worn_pieces if "worn_pieces" in res else PackedStringArray()
	var radice : Node = modello.instantiate()
	var presi := 0
	## `find_children` con una lista di nomi vuota prende tutto: un set che non
	## dichiara i pezzi si indossa INTERO, che è il caso normale di un pezzo
	## solo per file. La lista serve quando un `.glb` porta l'intero set e due
	## slot diversi se ne prendono metà per uno.
	for mi in radice.find_children("*", "MeshInstance3D", true, false):
		var m : MeshInstance3D = mi
		if voluti.size() > 0 and not voluti.has(m.name):
			continue
		## L'owner va tolto PRIMA di staccarla: la mesh appartiene alla scena del
		## `.glb`, e riparentarla senza toglierlo fa avvisare Godot a ogni piastra
		## ("will make owner inconsistent").
		m.owner = null
		m.get_parent().remove_child(m)
		m.transform = Transform3D.IDENTITY
		m.set_meta(META_MIO, true)
		skeleton.add_child(m)
		## ⚠️ Le piastre NON prendono `owner`, nemmeno sui banchi, ed e' deliberato.
		## Senza owner l'editor non le mostra nell'albero e non si possono
		## selezionare col gizmo — sembra una limitazione da togliere. Provato, e
		## la cura e' peggiore: intestandole Godot ne CUOCE mesh e skin dentro il
		## `.tscn`. Il banco della vestizione passava da 7 KB a 3,7 MB, e da quel
		## momento leggeva la copia cotta invece del `.glb` — rigenerare da Blender
		## non l'avrebbe piu' aggiornato, e un banco che mostra una versione vecchia
		## e' peggio che non averlo.
		##
		## La misura dell'armatura si tara dove vive: la tabella `VESTIZIONE` in
		## `arcanium/tools/vesti_protagonista.py`.
		presi += 1
	radice.free()
	if presi == 0:
		push_warning("ArmaturaIndossata: '%s' non ha dato nessuna piastra (worn_pieces=%s)."
			% [str(res.name if "name" in res else res.resource_path), str(voluti)])


## ⚠️ LA PELLE SOTTO NON SI SPEGNE ANCORA.
##
## `corpo_mascherato.gdshader` sa cancellare regioni di pelle (`regioni_nascoste`)
## ma lavora per regioni INTERE — braccia, gambe. I bracciali partono dal gomito
## e i gambali da metà coscia: spegnere "braccia" e "gambe" aprirebbe un buco
## dove la piastra non arriva. O i pezzi coprono tutta la regione, o la pelle
## resta e le piastre si tengono larghe (`gonfia` in `vesti_protagonista.py`).
