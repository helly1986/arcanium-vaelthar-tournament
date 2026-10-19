extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ESECUTORE DI TECNICHE DI GUERRA — il player esegue ciò che ha imparato
## ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ Niente `class_name`: si importa con `preload`. Vedi `fazioni.gd`.
##
## Prende una `TecnicaGuerra` appresa (flag in PlayerFlags) e la esegue A
## STRATO: la clip si mescola sopra la guardia, filtrata sul braccio armato, e
## le gambe e lo scudo non se ne accorgono. È il gemello, lato player, dello
## strato del Fante (`arcanium_humanoid_enemy.gd`, `NODO_STRATO`) — e come lì,
## il meccanismo non è cablato sulla Testuggine: legge la clip, il filtro, la
## finestra e il costo da una risorsa. La seconda tecnica è un `.tres`.
##
## ─── Non alza `busy` — e questo è tutto il punto ───────────────────────────
## `AnimationTreeSoulsBase.set_guarding()` abbassa lo scudo appena `busy` è
## vero: è il tell su cui gli avversari temporizzano, e va bene per un fendente.
## Ma una tecnica che esiste per colpire SENZA aprire la guardia non può
## passare da lì. Quindi qui `busy` non si tocca: il gesto vive in un OneShot
## suo, in cima all'albero, e a tenere fuori un secondo colpo ci pensano
## `_in_corso` e l'input del player, che con lo scudo alzato consuma il click
## anche quando la tecnica rifiuta. Lato nemico la stessa cosa la fa
## `_strato_attivo` scavalcando `_busy` in `_aggiorna_guardia`.
##
## ─── Non riapre `parry_active` ──────────────────────────────────────────────
## La finestra di parata si apre SOLO in `start_guard()`, all'alzata dello
## scudo. Un colpo che la rinfrescasse darebbe parate infinite a chi tiene il
## destro premuto e picchietta il sinistro. Questo file non nomina la parata,
## e deve restare così.
##
## ─── Lo slot si INNESTA a runtime, come sul Fante ───────────────────────────
## La Lucida Tecnica ha il suo OneShot autorato nel .tscn del player. Qui no,
## e per una ragione: il FILTRO. Un OneShot a strato è definito dalle ossa che
## lascia passare, e quelle si ricavano dallo scheletro vero (`filtro_osso` e
## tutta la sua discendenza), non si scrivono a mano in una lista di trenta
## voci che al primo osso rinominato smette di combaciare in silenzio. Il
## Fante fa già così; qui si fa uguale.
##
## ─── La clip arriva dal GLB del Fante ───────────────────────────────────────
## `sword_guard_thrust_01.glb` è stata autorata per il Fante, ma i nomi delle
## ossa sono quelli della convenzione unica del progetto: si riscrive solo il
## prefisso del percorso (`NephiliteRig/Skeleton3D` → `%GeneralSkeleton`),
## come fa `_carica_famiglia` del nemico. Le tracce su ossa che il player non
## ha (pollici, punti d'attacco) si SCARTANO invece di lasciarle a cercare un
## nodo che non c'è. Sono solo rotazioni: l'avambraccio del player è più corto
## di quello del Fante e la posa lo segue — la PORTATA no, e va misurata.

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")

## Il catalogo delle tecniche lo scandisce la risorsa stessa (`catalogo()`).
const TecnicaGuerra := preload("res://arcanium/resources/tecnica_guerra.gd")
## Libreria del player in cui finiscono le clip delle tecniche, una per `id`.
const LIBRERIA := "TecnicheLib"
## I due nodi che compongono lo slot, in cima al BlendTree del player.
const NODO_ONESHOT := "TecnicaGuerra"
const NODO_ANIM := "TecnicaGuerraAnim"
## Prefisso dei percorsi delle tracce del player: è quello di MeleeLib e dei
## filtri già autorati nell'albero (`%GeneralSkeleton:Chest`, ...). DEVE
## coincidere fra clip e filtro, o il filtro non riconosce le tracce.
const PREFISSO_SCHELETRO := "%GeneralSkeleton"
## La clip dal GLB al player: estratta in `clip_da_glb.gd` il 2026-09-13,
## quando l'arco del protagonista ha avuto bisogno della stessa cosa.
const ClipDaGlb := preload("res://arcanium/systems/clip_da_glb.gd")

@export var player : Node3D
@export var anim_tree : AnimationTree
## L'EquipmentSystem dell'arma: apre la lama nella finestra del gesto.
@export var weapon_system : Node
@export var vitals : Node           ## PlayerVitals, per il costo in stamina

signal iniziata(tecnica : Resource)
signal finita(tecnica : Resource)
signal rifiutata(motivo : String)

## Tutte le tecniche su disco, apprese o no: l'apprendimento si chiede al
## momento del lancio, perché può cambiare a partita in corso (il tomo).
var _tecniche : Array[Resource] = []
var _cooldown_fino : Dictionary = {}

var _in_corso : Resource = null
var _finestra_aperta : bool = false
var _t : float = 0.0
var _durata : float = 0.0
## Il OneShot diventa `active` solo al primo tick dell'albero: senza questo
## flag "non è attivo" al frame zero verrebbe letto come "è già finito".
var _visto_attivo : bool = false
var _skeleton : Skeleton3D = null


func _ready() -> void:
	if player == null:
		player = get_parent() as Node3D
	_carica_tecniche()
	_carica_clip()
	_innesta_slot()
	if player != null and player.has_signal("hurt_started"):
		player.hurt_started.connect(_on_hurt)
	if player != null and player.has_signal("death_started"):
		player.death_started.connect(_on_hurt)
	set_physics_process(true)


# ═══════════════════════════════════════════════════════════════════════════
# Cosa si sa fare
# ═══════════════════════════════════════════════════════════════════════════

## Solo i GESTI: una tecnica senza clip (l'Arcieria, che apre l'armadio agli
## archi e basta) si sa ma non si lancia, e qui non deve comparire — o
## l'accordo di guardia proverebbe a eseguire una clip che non c'è.
func _carica_tecniche() -> void:
	_tecniche.clear()
	for t in TecnicaGuerra.catalogo():
		if t.has_method("gesto") and t.gesto():
			_tecniche.append(t)


## Le tecniche che il giocatore HA imparato, adesso.
func apprese() -> Array[Resource]:
	var out : Array[Resource] = []
	var albero := get_tree()
	for t in _tecniche:
		if t.appresa(albero):
			out.append(t)
	return out


## La tecnica che l'accordo "guardia + colpo" deve lanciare: la prima appresa.
## Con una sola tecnica è ovvio; quando ce ne saranno due servirà una
## selezione (rotellina, come le magie) — e sarà qui che si legge.
func tecnica_di_guardia() -> Resource:
	var a := apprese()
	return a[0] if not a.is_empty() else null


func pronta(t : Resource) -> bool:
	return t != null and float(_cooldown_fino.get(t, 0.0)) <= _adesso()


func in_corso() -> Resource:
	return _in_corso


# ═══════════════════════════════════════════════════════════════════════════
# Le clip
# ═══════════════════════════════════════════════════════════════════════════

func _anim_player() -> AnimationPlayer:
	return ClipDaGlb.anim_player(anim_tree)


func _trova_scheletro() -> Skeleton3D:
	if _skeleton == null:
		_skeleton = ClipDaGlb.scheletro(anim_tree)
	return _skeleton


## Ogni tecnica porta la sua clip nella libreria del player, sotto il suo `id`.
## La clip si prende dal GLB dichiarato in `clip_glb` — se assente, si assume
## che `clip` sia già una "Libreria/Clip" del player e non si carica nulla.
func _carica_clip() -> void:
	var ap := _anim_player()
	var sk := _trova_scheletro()
	if ap == null or sk == null:
		push_warning("TecnicaGuerraCaster: AnimationPlayer o scheletro assenti — nessuna clip caricata.")
		return
	var lib := ClipDaGlb.libreria(ap, LIBRERIA)
	for t in _tecniche:
		var glb : String = str(t.get("clip_glb"))
		if glb == "" or not ResourceLoader.exists(glb):
			continue
		var anim := ClipDaGlb.carica(glb, sk)
		if anim == null:
			push_warning("TecnicaGuerraCaster: '%s' senza clip utilizzabile in %s" % [t.id, glb])
			continue
		ClipDaGlb.registra(lib, str(t.id), anim)


# ═══════════════════════════════════════════════════════════════════════════
# Lo slot nell'albero
# ═══════════════════════════════════════════════════════════════════════════

## Un OneShot filtrato in CIMA al BlendTree: prende come base ciò che oggi
## alimenta `output` e diventa lui l'ultimo anello. Così il braccio della
## tecnica vince su tutto — guardia compresa, che è ciò che serve — e il resto
## del corpo passa intatto.
func _innesta_slot() -> void:
	if anim_tree == null:
		return
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	if radice == null:
		push_warning("TecnicaGuerraCaster: l'albero del player non è un BlendTree.")
		return
	if radice.has_node(NODO_ONESHOT):
		return
	var sorgente := _chi_alimenta(radice, "output")
	if sorgente == "":
		push_warning("TecnicaGuerraCaster: non trovo chi alimenta `output` — slot non innestato.")
		return

	var uno := AnimationNodeOneShot.new()
	uno.filter_enabled = true
	## Attacco secco, rientro morbido: il carico del colpo va letto, il ritorno
	## in guardia no (è la stessa regola del corpo del Fante).
	uno.fadein_time = 0.06
	uno.fadeout_time = 0.18
	var clip := AnimationNodeAnimation.new()
	radice.add_node(NODO_ONESHOT, uno, Vector2(2900, -280))
	radice.add_node(NODO_ANIM, clip, Vector2(2900, -80))
	radice.disconnect_node("output", 0)
	radice.connect_node(NODO_ONESHOT, 0, sorgente)
	radice.connect_node(NODO_ONESHOT, 1, NODO_ANIM)
	radice.connect_node("output", 0, NODO_ONESHOT)


## Il BlendTree non espone le connessioni con un metodo pubblico, ma le
## serializza in `node_connections` come terne [a, porta, da]: si legge quella.
func _chi_alimenta(radice : AnimationNodeBlendTree, nodo : String) -> String:
	var conn = radice.get("node_connections")
	if conn is Array:
		var i := 0
		while i + 2 < conn.size():
			if str(conn[i]) == nodo and int(conn[i + 1]) == 0:
				return str(conn[i + 2])
			i += 3
	return ""


## Riscrive il filtro dello slot per QUESTA tecnica: l'osso dichiarato e tutta
## la sua discendenza. Le ossa di uno Skeleton3D sono in ordine topologico, una
## passata basta (è `_ossa_da` del Fante).
func _filtra(t : Resource) -> void:
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	var sk := _trova_scheletro()
	if radice == null or sk == null or not radice.has_node(NODO_ONESHOT):
		return
	var uno : AnimationNodeOneShot = radice.get_node(NODO_ONESHOT)
	uno.filters = []
	uno.filter_enabled = true
	var dal : String = str(t.get("filtro_osso"))
	var idx := sk.find_bone(dal)
	if idx < 0:
		push_warning("TecnicaGuerraCaster: osso '%s' assente sul player, filtro vuoto." % dal)
		return
	var dentro := {idx: true}
	for i in sk.get_bone_count():
		if dentro.has(sk.get_bone_parent(i)):
			dentro[i] = true
	for i in dentro.keys():
		uno.set_filter_path(NodePath("%s:%s" % [PREFISSO_SCHELETRO, sk.get_bone_name(i)]), true)


# ═══════════════════════════════════════════════════════════════════════════
# Il lancio
# ═══════════════════════════════════════════════════════════════════════════

## Tenta il lancio della tecnica di guardia. Ritorna true se il gesto è partito.
## L'ordine dei controlli è quello della Lucida: prima quelli gratis, poi la
## spesa — invertirlo scalerebbe stamina per un colpo che non parte.
func lancia(t : Resource = null) -> bool:
	if t == null:
		t = tecnica_di_guardia()
	if t == null:
		rifiutata.emit("nessuna_tecnica")
		return false
	if _in_corso != null:
		rifiutata.emit("gia_in_corso")
		return false
	if player != null and ("guarding" in player) and not player.guarding:
		rifiutata.emit("senza_guardia")
		return false
	if not pronta(t):
		rifiutata.emit("cooldown")
		return false
	## ⚠️ La clip si verifica PRIMA di spendere: il primo giro di questo file
	## la controllava dentro `_suona`, dopo la stamina, e un GLB non caricato
	## costava 18 punti per un gesto che non partiva. Lo ha detto il cancello.
	if not _clip_risolta(t):
		rifiutata.emit("clip_non_risolta")
		return false
	var costo : float = float(t.get("costo_stamina"))
	if costo > 0.0:
		if vitals == null or not vitals.has_method("spend_stamina"):
			rifiutata.emit("nessun_vitals")
			return false
		if not vitals.spend_stamina(costo):
			rifiutata.emit("stamina_insufficiente")
			return false

	_suona(t)

	_in_corso = t
	_finestra_aperta = false
	_t = 0.0
	_visto_attivo = false
	_durata = _durata_clip(t)
	var cd : float = float(t.get("cooldown"))
	if cd > 0.0:
		_cooldown_fino[t] = _adesso() + cd
	if player != null and ("tecnica_in_corso" in player):
		player.tecnica_in_corso = t
	iniziata.emit(t)
	return true


## Tutto cio' che serve a suonare la tecnica esiste? Gratis, e va chiesto
## prima di spendere.
func _clip_risolta(t : Resource) -> bool:
	if anim_tree == null or anim_tree.tree_root == null:
		return false
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	if radice == null or not radice.has_node(NODO_ANIM):
		return false
	var ap := _anim_player()
	return ap != null and ap.has_animation("%s/%s" % [LIBRERIA, str(t.id)])


func _suona(t : Resource) -> void:
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	_filtra(t)
	var nodo := radice.get_node(NODO_ANIM) as AnimationNodeAnimation
	nodo.animation = StringName("%s/%s" % [LIBRERIA, str(t.id)])
	anim_tree.set("parameters/%s/request" % NODO_ONESHOT,
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _durata_clip(t : Resource) -> float:
	var ap := _anim_player()
	var nome := "%s/%s" % [LIBRERIA, str(t.id)]
	if ap == null or not ap.has_animation(nome):
		return 0.0
	var v : float = float(t.get("speed_scale"))
	return ap.get_animation(nome).length / maxf(v, 0.01)


## L'avanzamento nel gesto si MISURA col tempo e si tiene agganciato allo stato
## del OneShot (interrotto = finestra chiusa), esattamente come la Lucida: vedi
## lì perché `time_to_end` non esiste e un timer puro terrebbe la lama viva.
func _physics_process(delta : float) -> void:
	if _in_corso == null:
		return
	var attivo : bool = bool(anim_tree.get("parameters/%s/active" % NODO_ONESHOT)) if anim_tree != null else false
	if attivo:
		_visto_attivo = true
	elif _visto_attivo:
		_chiudi()
		return
	_t += delta
	if _durata <= 0.0 or _t >= _durata:
		_chiudi()
		return
	var avanzamento : float = _t / _durata
	var dentro : bool = avanzamento >= float(_in_corso.get("finestra_da")) \
		and avanzamento <= float(_in_corso.get("finestra_a"))
	if dentro and not _finestra_aperta:
		_apri_finestra()
	elif not dentro and _finestra_aperta:
		_chiudi_finestra()


func _apri_finestra() -> void:
	_finestra_aperta = true
	if weapon_system != null and weapon_system.has_method("apri_finestra_tecnica"):
		weapon_system.apri_finestra_tecnica(float(_in_corso.get("portata")))


func _chiudi_finestra() -> void:
	_finestra_aperta = false
	if weapon_system != null and weapon_system.has_method("chiudi_finestra_tecnica"):
		weapon_system.chiudi_finestra_tecnica()


func _chiudi() -> void:
	if _finestra_aperta:
		_chiudi_finestra()
	var t := _in_corso
	_in_corso = null
	if player != null and ("tecnica_in_corso" in player):
		player.tecnica_in_corso = null
	if t != null:
		finita.emit(t)


## Colpito o morto a metà gesto: il braccio si arrende, la lama si spegne.
func _on_hurt() -> void:
	if _in_corso == null:
		return
	if anim_tree != null:
		anim_tree.set("parameters/%s/request" % NODO_ONESHOT,
			AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_chiudi()


func _adesso() -> float:
	return OrologioGioco.adesso()
