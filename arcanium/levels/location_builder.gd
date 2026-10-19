@tool
extends Node3D
class_name LocationBuilder

## Base comune di TUTTI i costruttori di location (arena, crocevia, e le
## prossime). Mette in un posto solo le due cose che servono sempre:
## generare la location da codice, e permettere di rifinirla a mano nell'editor
## senza che la rigenerazione butti via il lavoro.
##
## Una sottoclasse deve solo:
##   - `extends "res://arcanium/levels/location_builder.gd"`
##   - implementare `_build_content()`, popolando `_built` con `_spawn*`/`_add`
## Tutto il resto (pulsanti, persistenza, adozione della scena salvata) arriva
## da qui.
##
## ─── FLUSSO "GENERA, RIFINISCI A MANO, E NON PERDERE NULLA" ─────────────────
##   1. apri la scena: se non c'è un "Built", viene generato. Ogni oggetto
##      riceve un id stabile = il suo nome, `<categoria>_<NN>` (`column_03`,
##      `Solan_00`). Progressivo PER CATEGORIA, non globale: cambiare il numero
##      di detriti non sfasa gli id delle colonne.
##   2. sposta/ruota/scala/cancella col gizmo e SALVA la scena (Ctrl+S): la
##      geometria è fatta di nodi normali, scritti nel .tscn.
##   3. spunta **`save_layout`**: le tue posizioni finiscono in un .tres
##      (vedi arena_overrides.gd) — solo ciò che hai davvero spostato o
##      cancellato, confrontato con quanto genera il codice.
##   4. da lì in poi **`rebuild` NON è distruttivo**: rigenera e riapplica le
##      tue rifiniture. Serve a cambiare l'algoritmo senza rifare il lavoro.
##   5. **`reset_layout`** torna alle posizioni originali del codice.
##   6. gli oggetti che AGGIUNGI a mano vanno sotto **"HandPlaced"**, che il
##      builder non tocca mai: lì puoi mettere qualunque nodo con tutte le sue
##      proprietà, non solo una transform.
##      Se per abitudine li lasci cadere sotto "Built", NON vanno persi: al primo
##      `save_layout` o `rebuild` vengono spostati d'ufficio sotto "HandPlaced"
##      (con un warning nell'Output che dice quali). Il motivo per cui non
##      possono restare lì è che "Built" viene DISTRUTTO e rigenerato a ogni
##      build, e il salvataggio del layout registra solo le transform dei nodi
##      generati dal codice — di un oggetto tuo non saprebbe nemmeno che asset è.
## ⚠️ L'id È il nome: rinominare a mano un oggetto generato ne spezza il
## collegamento con la rifinitura salvata.

const OverridesRes := preload("res://arcanium/levels/arena_overrides.gd")

## Rigenera da codice e riapplica le rifiniture salvate.
## ⚠️ Perde solo le modifiche fatte a mano e NON ancora salvate: premi
## `save_layout` prima di `rebuild`.
@export var rebuild : bool = false : set = _set_rebuild

## Costruisce al _ready SOLO se la scena non contiene già un "Built" salvato:
## una volta generata e salvata, la verità è la scena, non il codice.
@export var build_on_ready : bool = true

## Dove salvare le rifiniture. Se vuoto viene dedotto dal nome della scena
## (`crocevia_arco_ambra.tscn` → `crocevia_arco_ambra_layout.tres`), così ogni
## nuova location funziona senza configurare niente.
@export_file("*.tres") var overrides_path : String = ""

## Spunta per SALVARE su disco le posizioni attuali degli oggetti generati.
@export var save_layout : bool = false : set = _set_save_layout

## Spunta per BUTTARE VIA le rifiniture salvate e tornare al layout generato.
@export var reset_layout : bool = false : set = _set_reset_layout

var _built : Node3D
## Progressivo PER CATEGORIA per gli id (`column_00`, `column_01`, `rock_00`).
var _bid_count : Dictionary = {}

func _ready() -> void:
	## Se la scena salvata contiene GIÀ un "Built" lo si ADOTTA invece di
	## ricostruire: è ciò che rende possibili le rifiniture a mano.
	## (Attenzione a non testare qui una variabile di runtime come `_built`:
	## alla riapertura è sempre null e la location verrebbe rigenerata ogni
	## volta, buttando via ogni ritocco. Era il bug originale.)
	var existing := get_node_or_null("Built")
	if existing is Node3D:
		_built = existing
		_on_adopted()
		return
	if build_on_ready:
		build()

## Chiamato quando si ADOTTA un "Built" già salvato invece di generarlo. La
## sottoclasse ricostruisce qui gli indici di runtime che normalmente riempie
## durante la generazione (es. la lista delle luci del ciclo notte): adottando,
## quel codice non gira, e senza questo aggancio resterebbero vuoti.
func _on_adopted() -> void:
	pass

func _set_rebuild(v : bool) -> void:
	if v:
		build()

func build() -> void:
	var old := get_node_or_null("Built")
	if old:
		_salvage_hand_added(old)
		old.free()
	_bid_count.clear()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)
	_built.owner = _owner_target()

	_build_content()

	## L'ordine conta: prima si fotografa ciò che il CODICE ha prodotto, poi si
	## riapplicano le rifiniture — altrimenti il pristine registrerebbe le
	## posizioni già corrette a mano e il confronto perderebbe senso.
	_persist_pristine()
	_apply_layout()
	_ensure_hand_placed()
	## Ultimo passo: qui il layout a mano è già applicato, quindi è l'unico punto
	## in cui si conosce l'ingombro REALE della location. Serve a chi deve
	## dimensionarsi su ciò che c'è davvero (il pavimento del Crocevia si estende
	## fin dove sono finiti muri e torri dopo gli spostamenti manuali).
	_after_layout()
	print("BUILD OK — Built children: %d" % _built.get_child_count())


## Innesto post-layout. Vuoto di default.
func _after_layout() -> void:
	pass

## DA IMPLEMENTARE nella sottoclasse: genera il contenuto sotto `_built`.
func _build_content() -> void:
	push_warning("LocationBuilder: _build_content() non implementato.")

## ─── Nodi generati ───────────────────────────────────────────────────────────
## A CHI intestare i nodi generati perché l'editor li consideri parte della
## scena (e quindi li mostri nell'albero, li lasci selezionare e li salvi).
## ⚠️ Il builder è il nodo RADICE della sua scena, e in Godot la radice ha
## `owner == null`: il vecchio `if Engine.is_editor_hint() and owner:` era
## quindi SEMPRE falso e nessun oggetto veniva mai intestato — era il motivo per
## cui la scena risultava vuota nell'editor. Quando `owner` è null il
## proprietario corretto è il nodo stesso.
func _owner_target() -> Node:
	return owner if owner != null else self
## `register`: false per i nodi che NON sono arredo (cielo/luci ritrovati per
## nome alla build successiva, che non vanno rinominati).
func _add(node : Node, register : bool = true) -> void:
	_built.add_child(node)
	if register:
		_register(node, node.name)
	node.owner = _owner_target()

## Marchio dei nodi GENERATI. Serve a distinguerli da quelli aggiunti a mano
## sotto `Built`, che il rebuild non deve distruggere (vedi _salvage_hand_added).
## I metadati vengono serializzati nel .tscn, quindi il marchio sopravvive al
## salvataggio e alla riapertura della scena.
const META_GENERATO := "arcanium_generato"

## Assegna al nodo il suo id stabile = il nome, `<categoria>_<NN>`. L'id è la
## chiave con cui le rifiniture a mano vengono salvate e ritrovate.
func _register(node : Node, base : String) -> void:
	var n : int = _bid_count.get(base, 0)
	_bid_count[base] = n + 1
	node.name = "%s_%02d" % [base, n]
	node.set_meta(META_GENERATO, true)

## Rende i nodi generati parte della scena SALVATA: senza `owner` l'editor non
## li scrive nel .tscn e sparirebbero alla riapertura.
## NON scende dentro le sotto-scene istanziate (i .glb): i loro figli
## appartengono alla scena d'origine, e marcarli qui riempirebbe il .tscn di
## override inutili. Possedere la radice dell'istanza basta.
func _set_owner_rec(node : Node, o : Node) -> void:
	node.owner = o
	if not node.scene_file_path.is_empty():
		return
	for c in node.get_children():
		_set_owner_rec(c, o)

## ─── COLLISIONE AUTOMATICA ───────────────────────────────────────────────────
## Genera la collisione dalla MESH REALE dell'oggetto, invece di approssimarla a
## mano con scatole e cilindri (che vanno tarati uno per uno, e quando la stima
## sbaglia si resta attraversabili o si sbatte contro l'aria).
##
## ⚠️ Non serve nessun plugin di "auto collider": è una funzione NATIVA di Godot
## — la stessa del menu "Mesh → Crea corpo statico di collisione" dell'editor,
## qui richiamata da codice. Una dipendenza esterna in meno da mantenere.
##
## `concave` = collisione esatta sulla forma (giusta per lo scenario statico:
## sotto un banco ci si passa davvero). `false` = guscio convesso, più
## grossolano ma più economico, adatto a oggetti piccoli e tondeggianti.
func _auto_collide(inst : Node3D, concave : bool = true) -> int:
	if inst == null:
		return 0
	var creati := 0
	## ⚠️ `find_children` NON include il nodo di partenza. Se la radice del .glb è
	## essa stessa una MeshInstance3D non nasceva nessun collider (il Cono), e se
	## lo era solo una parte dell'oggetto la collisione veniva parziale (le
	## bancarelle: si passava attraverso alcuni pezzi e non altri).
	var mesh_nodes : Array = inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		mesh_nodes.append(inst)
	for node in mesh_nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if concave:
			mi.create_trimesh_collision()
		else:
			mi.create_convex_collision()
		creati += 1
	## I corpi appena creati stanno DENTRO la sotto-scena del .glb, dove
	## `_set_owner_rec` non scende: vanno intestati a parte, altrimenti l'editor
	## non li salva e alla riapertura la location tornerebbe attraversabile.
	for body in inst.find_children("*", "StaticBody3D", true, false):
		body.owner = _owner_target()
		for c in body.get_children():
			c.owner = _owner_target()
	return creati

## Contenitore per gli oggetti aggiunti A MANO: `rebuild` cancella solo "Built",
## qui dentro non tocca nulla.
func _ensure_hand_placed() -> Node3D:
	var hp := get_node_or_null("HandPlaced") as Node3D
	if hp != null:
		return hp
	hp = Node3D.new()
	hp.name = "HandPlaced"
	add_child(hp)
	hp.owner = _owner_target()
	return hp


## Mette in salvo ciò che il builder NON ha creato prima di distruggere `Built`.
##
## `build()` libera l'intero sottoalbero `Built` e lo rigenera. Chiunque avesse
## trascinato o duplicato un prop lì dentro se lo vedeva sparire al primo
## rebuild — e il rebuild parte da solo al play, quindi il prop spariva
## esattamente quando si andava a controllare se funzionava. Bloccare un'uscita
## con un carretto è una tecnica standard, e il builder non deve combatterla.
##
## Cosa è "generato": ha il marchio META_GENERATO, oppure il suo nome sta nel
## `pristine` del layout. Il secondo criterio copre i nodi salvati PRIMA che il
## marchio esistesse — senza, il primo rebuild dopo questo cambio avrebbe
## scambiato l'intera location per roba fatta a mano.
##
## LIMITE NOTO, deliberato: si guardano solo i figli DIRETTI di "Built". Un prop
## lasciato cadere DENTRO un altro nodo (dentro un muro, dentro un NPC) non viene
## recuperato. Ci ho provato e l'ho tolto: in una scena gia' salvata non c'e' modo
## affidabile di distinguere un asset trascinato a mano dal GLB che il builder
## mette dentro un NPC, e il tentativo portava via i modelli di Koval, Solan,
## Mira, Arath e Yovyan. Meglio un recupero che copre il caso normale che uno
## che ogni tanto smonta gli NPC.
func _salvage_hand_added(old : Node) -> void:
	var noti : Dictionary = {}
	var res := _load_layout()
	if res and "pristine" in res:
		noti = res.pristine

	var da_salvare : Array = []
	for c in old.get_children():
		if c.has_meta(META_GENERATO) or noti.has(c.name):
			continue
		da_salvare.append(c)
	if da_salvare.is_empty():
		return

	var nomi : Array = []
	for c in da_salvare:
		nomi.append(str(c.name))
	_riparenta(da_salvare)
	push_warning("LocationBuilder: %d nodi aggiunti a mano spostati da 'Built' a 'HandPlaced' (Built viene rigenerato a ogni build): %s"
		% [da_salvare.size(), ", ".join(nomi)])


## Sposta i nodi sotto "HandPlaced" conservando la posizione nel mondo. Si toglie
## dal genitore REALE e non da "Built": i nodi annidati hanno un altro genitore,
## e `Built.remove_child()` su di loro non farebbe nulla lasciandoli a morire.
func _riparenta(nodi : Array) -> void:
	var hp := _ensure_hand_placed()
	for c in nodi:
		var t : Transform3D = (c as Node3D).global_transform if c is Node3D else Transform3D.IDENTITY
		var padre : Node = c.get_parent()
		if padre:
			padre.remove_child(c)
		hp.add_child(c)
		if c is Node3D:
			(c as Node3D).global_transform = t
		c.owner = _owner_target()

## ─── Layout persistito ───────────────────────────────────────────────────────
## Percorso effettivo del file: quello impostato, o dedotto dalla scena.
func _layout_path() -> String:
	if not overrides_path.is_empty():
		return overrides_path
	var base := scene_file_path
	if base.is_empty() and owner:
		base = owner.scene_file_path
	if base.is_empty():
		return ""
	return base.get_basename() + "_layout.tres"

func _load_layout() -> Resource:
	var path := _layout_path()
	if not path.is_empty() and ResourceLoader.exists(path):
		var res := load(path)
		if res is OverridesRes:
			return res
		push_warning("LocationBuilder: %s non è un ArenaOverrides, lo ignoro." % path)
	return OverridesRes.new()

## Scrive su disco. Solo in editor: un gioco esportato non deve (e spesso non
## può) scrivere dentro res://.
func _save_layout_res(res : Resource) -> bool:
	if not Engine.is_editor_hint():
		return false
	var path := _layout_path()
	if path.is_empty():
		push_warning("LocationBuilder: nessun percorso per il layout (scena non salvata?).")
		return false
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("LocationBuilder: salvataggio layout fallito (%s) su %s" % [err, path])
		return false
	return true

## Fotografa le posizioni APPENA generate dal codice e le persiste: riaprendo
## una scena salvata il builder non ha più quel dato in memoria, e senza
## riferimento non saprebbe più distinguere cosa è stato spostato a mano.
func _persist_pristine() -> void:
	if _built == null:
		return
	var res := _load_layout()
	var snap := {}
	for c in _built.get_children():
		if c is Node3D:
			snap[c.name] = (c as Node3D).transform
	res.pristine = snap
	_save_layout_res(res)

## Riapplica sopra la geometria appena generata le rifiniture salvate. È questo
## che rende `rebuild` non distruttivo.
func _apply_layout() -> void:
	if _built == null:
		return
	var res := _load_layout()
	var moved := 0
	for id in res.overrides:
		var n := _built.get_node_or_null(NodePath(str(id)))
		if n is Node3D:
			(n as Node3D).transform = res.overrides[id]
			moved += 1
	var removed := 0
	for id in res.deleted:
		var n := _built.get_node_or_null(NodePath(str(id)))
		if n:
			n.free()
			removed += 1
	if moved > 0 or removed > 0:
		print("LocationBuilder: layout riapplicato — %d spostati, %d rimossi." % [moved, removed])

func _set_save_layout(v : bool) -> void:
	if not v:
		return
	var built := get_node_or_null("Built")
	if built == null:
		push_warning("LocationBuilder: nessun 'Built' da salvare.")
		return
	var res := _load_layout()
	if res.pristine.is_empty():
		push_warning("LocationBuilder: manca il riferimento pristine — premi 'rebuild' una volta, poi risalva.")
		return

	## PRIMA di salvare: chi è stato aggiunto a mano sotto "Built" viene messo al
	## sicuro sotto "HandPlaced". Il salvataggio del layout, per come è fatto,
	## IGNORA i nodi che il builder non ha generato (vedi sotto: "non è affar
	## suo"), quindi la loro posizione non finirebbe da nessuna parte e il primo
	## rebuild li cancellerebbe. Farlo qui e non solo in `build()` è ciò che
	## salva il flusso naturale "sistemo la scena → save_layout → rebuild".
	_salvage_hand_added(built)

	var edits := {}
	var present := {}
	for c in built.get_children():
		if not (c is Node3D):
			continue
		present[c.name] = true
		if not res.pristine.has(c.name):
			continue  ## non generato dal builder: non è affar suo
		var orig : Transform3D = res.pristine[c.name]
		var now : Transform3D = (c as Node3D).transform
		if not now.is_equal_approx(orig):
			edits[c.name] = now
	var gone := PackedStringArray()
	for id in res.pristine:
		if not present.has(id):
			gone.append(str(id))
	res.overrides = edits
	res.deleted = gone
	if _save_layout_res(res):
		print("LocationBuilder: layout salvato in %s — %d spostati, %d cancellati." % [
			_layout_path(), edits.size(), gone.size()])

func _set_reset_layout(v : bool) -> void:
	if not v:
		return
	var res := _load_layout()
	res.clear_edits()
	if _save_layout_res(res):
		print("LocationBuilder: rifiniture azzerate, torno al layout generato.")
		build()
