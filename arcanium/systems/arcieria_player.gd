extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ARCIERIA DEL PROTAGONISTA — il tipo d'arma BOW
## ═══════════════════════════════════════════════════════════════════════════
##
## L'AnimationTree del protagonista conosce due modi di menare, `SLASH` e
## `HEAVY`: ognuno un sotto-albero di locomozione (`MovementStates/<TIPO>_tree`)
## e un ramo di attacco (`ATTACK_tree/<TIPO>`), scelti dalla stringa
## `weapon_type` che `held_weapon.gd` annuncia leggendo `object_type` dal
## `.tres` dell'arma. Un tipo senza rami cade su SLASH: un arco menato come una
## spada.
##
## Qui si INNESTA il terzo modo, `BOW`, a runtime — come `tecnica_guerra_caster`
## innesta il suo OneShot — invece di toccare a mano le 2.500 righe del `.tscn`:
##
##   • `MovementStates/BOW_tree`: una copia del `SLASH_tree` in cui i punti del
##     blend (idle, passo, corsa) vengono sostituiti dalle clip d'arco se il
##     `SetArco` le ha; con le transizioni SLASH↔BOW su `weapon_type`, come
##     quelle SLASH↔HEAVY gia' nel file;
##   • `ATTACK_tree/BOW`: un solo stato, `Tiro`, con la clip del tiro; e la
##     transizione `Start → SLASH`, che nel file e' «tutto cio' che non e'
##     HEAVY», impara a escludere anche BOW.
##
## Il TIRO e' un attacco come gli altri per il player (`attack()`, stamina,
## buffer, `attack_started`, `attack_measured`): quello che cambia e' cosa
## succede durante la clip. Nessuna lama si accende (`equipment_system.gd`
## salta la finestra per i BOW); la corda dell'arco — impugnato con la DESTRA
## come ogni arma, e' la scelta del Soldato Scelto — segue la SINISTRA da
## `incocco` (la mano si posa sulla corda con la freccia: prima sta nella
## faretra) a `rilascio` della durata, quando nasce la FRECCIA — la stessa
## scena degli arcieri Sylvorn, con `move` = la risorsa dell'arco, cosi' il
## danno viaggia con i numeri scalati sulle Marche, e `source` = il player,
## cosi' `Fazioni` la fa ferire i nemici e non gli evocati. Le due frazioni
## si misurano sulla clip (`arcanium/tools/misura_arco.tscn`), come per
## l'arciere (`EnemyMove.tendi_da` e il contatto).
##
## La mira e' quella degli incantesimi: il bersaglio agganciato se c'e',
## altrimenti dritto davanti. Un colpo subito prima del rilascio annulla il
## tiro: la freccia non parte da un gesto interrotto.
##
## E la FRECCIA si vede prima di volare (`freccia_in_mano.gd`, come
## sull'arciere): da `estrazione` sta nella sinistra, da `incocco` sulla corda
## e arretra con lei, al rilascio sparisce e nasce il proiettile. Il modello e'
## quello della freccia che l'arco tira.
##
## ⚠️ Segnaposto: finche' il `SetArco` porta `sword_cast_01`, il gesto e' un
## lancio d'incantesimo. Le clip vere si autorano in Cascadeur e si mettono nel
## `.tres`; questo file non cambia.

const ClipDaGlb := preload("res://arcanium/systems/clip_da_glb.gd")
const FrecciaInMano := preload("res://arcanium/systems/armi/freccia_in_mano.gd")

const TIPO := "BOW"
const LIBRERIA := "ArcoLib"
const ALBERO_MOVIMENTO := "BOW_tree"
const ALBERO_BASE := "SLASH_tree"
const RAMO_ATTACCO := "BOW"
const STATO_TIRO := "Tiro"
const STATO_TIRO_CARICATO := "TiroCaricato"
const NOME_CLIP_TIRO := "Tiro"
const NOME_CLIP_TIRO_CARICATO := "TiroCaricato"
## Il modello dell'arco, appeso da `held_weapon.gd` sotto l'oggetto d'arma.
const NODO_MODELLO := "ModelloEquipaggiato"
## Punti del blend di locomozione del template (x = strafe, y = avanti):
## fermo, passo avanti, corsa avanti. Gli altri dieci restano della spada.
const PUNTI_BLEND := {"idle": Vector2(0, 0), "cammino": Vector2(0, 0.3), "corsa": Vector2(0, 1)}

@export var player : Node3D
@export var anim_tree : AnimationTree
@export var weapon_system : Node
## Il pivot della mano SINISTRA: e' la mano che tira la corda.
@export var mano_che_tira : Node3D
@export var set_arco : Resource

signal scoccata(freccia : Node3D)
signal annullato

var _in_tiro : bool = false
var _caricato : bool = false
var _t : float = 0.0
var _durata : float = 0.0
var _tesa : bool = false
var _rilasciata : bool = false
var _innestato : bool = false
var _freccia : Node3D = null


func _ready() -> void:
	if player == null or anim_tree == null:
		push_warning("ArcieriaPlayer: player o AnimationTree assenti — niente arco.")
		return
	## L'albero del player si monta nel suo _ready e i fratelli non hanno un
	## ordine garantito: un frame, come `held_weapon.gd`.
	await get_tree().process_frame
	_carica_clip()
	_innesta_movimento()
	_innesta_attacco()
	_innestato = true
	## Se l'arco era gia' in mano al caricamento (una partita salvata),
	## `held_weapon.gd` ha annunciato BOW PRIMA che i rami esistessero e
	## l'albero e' caduto su SLASH: si riannuncia adesso che ci sono.
	if str(player.get("weapon_type")) == TIPO and player.has_signal("weapon_change_ended"):
		player.weapon_change_ended.emit(TIPO)
	_freccia = FrecciaInMano.new()
	_freccia.name = "FrecciaInMano"
	add_child(_freccia)
	player.attack_started.connect(_on_attack_started)
	if anim_tree.has_signal("attack_measured"):
		anim_tree.attack_measured.connect(_on_attack_measured)
	if player.has_signal("hurt_started"):
		player.hurt_started.connect(_annulla)
	if player.has_signal("death_started"):
		player.death_started.connect(_annulla)


func innestato() -> bool:
	return _innestato


# ═══════════════════════════════════════════════════════════════════════════
# Le clip
# ═══════════════════════════════════════════════════════════════════════════

func _carica_clip() -> void:
	var ap := ClipDaGlb.anim_player(anim_tree)
	var sk := ClipDaGlb.scheletro(anim_tree)
	if ap == null or sk == null or set_arco == null:
		push_warning("ArcieriaPlayer: AnimationPlayer, scheletro o SetArco assenti — nessuna clip d'arco.")
		return
	var lib := ClipDaGlb.libreria(ap, LIBRERIA)
	var tiro := ClipDaGlb.carica(str(set_arco.clip_tiro), sk)
	if tiro == null:
		push_warning("ArcieriaPlayer: clip del tiro assente o vuota (%s)." % str(set_arco.clip_tiro))
	else:
		ClipDaGlb.registra(lib, NOME_CLIP_TIRO, tiro)
	## Il caricato: la sua clip, o la stessa del rapido finche' non c'e'.
	var glb_caricato := str(set_arco.get("clip_tiro_caricato"))
	var caricato := ClipDaGlb.carica(glb_caricato, sk) if glb_caricato != "" else null
	if caricato == null and tiro != null:
		caricato = ClipDaGlb.carica(str(set_arco.clip_tiro), sk)
	if caricato != null:
		ClipDaGlb.registra(lib, NOME_CLIP_TIRO_CARICATO, caricato)
	for nome in PUNTI_BLEND:
		var glb := str(set_arco.get("clip_" + nome))
		if glb == "":
			continue
		var anim := ClipDaGlb.carica(glb, sk, true)
		if anim != null:
			ClipDaGlb.registra(lib, nome, anim)


func _ha_clip(nome : String) -> bool:
	var ap := ClipDaGlb.anim_player(anim_tree)
	return ap != null and ap.has_animation(LIBRERIA + "/" + nome)


# ═══════════════════════════════════════════════════════════════════════════
# L'innesto nell'albero
# ═══════════════════════════════════════════════════════════════════════════

func _transizione(espressione : String = "", alla_fine : bool = false, xfade : float = 0.2) -> AnimationNodeStateMachineTransition:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = xfade
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	if alla_fine:
		tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	if espressione != "":
		tr.advance_expression = espressione
	return tr


## `BOW_tree`: il `SLASH_tree` copiato, con i punti del blend rimpiazzati dove
## il set ha una clip. Copiato e non condiviso: rimpiazzare un punto sul tree
## della spada cambierebbe anche la spada.
func _innesta_movimento() -> void:
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	var ms := radice.get_node("MovementStates") as AnimationNodeStateMachine
	if ms == null or ms.has_node(ALBERO_MOVIMENTO) or not ms.has_node(ALBERO_BASE):
		return
	var albero := (ms.get_node(ALBERO_BASE) as AnimationNodeStateMachine).duplicate(true) as AnimationNodeStateMachine
	var strafe := albero.get_node("MoveStrafe") as AnimationNodeBlendSpace2D
	if strafe != null:
		for nome in PUNTI_BLEND:
			if not _ha_clip(nome):
				continue
			for i in strafe.get_blend_point_count():
				if strafe.get_blend_point_position(i).is_equal_approx(PUNTI_BLEND[nome]):
					var n := AnimationNodeAnimation.new()
					n.animation = LIBRERIA + "/" + nome
					strafe.set_blend_point_node(i, n)
	ms.add_node(ALBERO_MOVIMENTO, albero, Vector2(468, 40))
	ms.add_transition(ALBERO_BASE, ALBERO_MOVIMENTO, _transizione('weapon_type == "%s"' % TIPO))
	ms.add_transition(ALBERO_MOVIMENTO, ALBERO_BASE, _transizione('weapon_type != "%s"' % TIPO))


## `ATTACK_tree/BOW`: due stati, il tiro rapido e il caricato, scelti da
## `player_node.secondary_action` come il ramo pesante della spada. Niente
## catena: un arco non concatena fendenti.
func _innesta_attacco() -> void:
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	var at := radice.get_node("ATTACK_tree") as AnimationNodeStateMachine
	if at == null or at.has_node(RAMO_ATTACCO) or not _ha_clip(NOME_CLIP_TIRO):
		return
	var ramo := AnimationNodeStateMachine.new()
	ramo.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
	var clip := AnimationNodeAnimation.new()
	clip.animation = LIBRERIA + "/" + NOME_CLIP_TIRO
	ramo.add_node(STATO_TIRO, clip, Vector2(400, 60))
	var caricato := AnimationNodeAnimation.new()
	caricato.animation = LIBRERIA + "/" + (NOME_CLIP_TIRO_CARICATO if _ha_clip(NOME_CLIP_TIRO_CARICATO) else NOME_CLIP_TIRO)
	ramo.add_node(STATO_TIRO_CARICATO, caricato, Vector2(400, 180))
	ramo.add_transition("Start", STATO_TIRO, _transizione("!player_node.secondary_action", false, 0.1))
	ramo.add_transition("Start", STATO_TIRO_CARICATO, _transizione("player_node.secondary_action", false, 0.1))
	ramo.add_transition(STATO_TIRO, "End", _transizione("", true, 0.2))
	ramo.add_transition(STATO_TIRO_CARICATO, "End", _transizione("", true, 0.2))
	at.add_node(RAMO_ATTACCO, ramo, Vector2(542, 300))
	at.add_transition("Start", RAMO_ATTACCO, _transizione('weapon_type == "%s"' % TIPO))
	at.add_transition(RAMO_ATTACCO, "End", _transizione("", true, 0.3))
	## La transizione verso SLASH nel file e' «weapon_type != HEAVY»: senza
	## questo ritocco un arco farebbe partire ANCHE un fendente, e vincerebbe
	## il primo dei due in ordine di lista.
	for i in at.get_transition_count():
		if str(at.get_transition_from(i)) == "Start" and str(at.get_transition_to(i)) == "SLASH":
			var tr := at.get_transition(i)
			if not tr.advance_expression.contains(TIPO):
				tr.advance_expression = '%s and weapon_type != "%s"' % [tr.advance_expression, TIPO]


# ═══════════════════════════════════════════════════════════════════════════
# Il tiro
# ═══════════════════════════════════════════════════════════════════════════

## L'arco: il modello che `held_weapon.gd` ha appeso sotto l'oggetto d'arma
## della destra.
func _arco_in_mano() -> Node3D:
	if weapon_system == null or not ("current_equipment" in weapon_system):
		return null
	var arma = weapon_system.current_equipment
	if arma == null:
		return null
	return arma.get_node_or_null(NODO_MODELLO) as Node3D


func _corda() -> Node:
	var arco := _arco_in_mano()
	if arco == null:
		return null
	var c := arco.get_node_or_null("Corda")
	return c if c != null and c.has_method("tendi") else null


func in_tiro() -> bool:
	return _in_tiro


func _on_attack_started() -> void:
	if str(player.weapon_type) != TIPO:
		return
	_in_tiro = true
	## `secondary_action` e' alta solo nel frame in cui `attack_strong` chiede
	## il colpo: si legge qui, o non si sa piu' quale tiro e' partito.
	_caricato = bool(player.get("secondary_action"))
	_tesa = false
	_rilasciata = false
	_t = 0.0
	## Stima prudente finche' `attack_measured` non porta la durata vera: la
	## stessa scelta di `_begin_attack` nel player.
	_durata = 1.0


func _on_attack_measured(length : float) -> void:
	if _in_tiro:
		_durata = length


func _physics_process(delta : float) -> void:
	if not _in_tiro:
		return
	_t += delta
	## Il OneShot `Attack` e' quello che suona il tiro: se si spegne prima del
	## rilascio (un colpo subito, una schivata), il tiro e' annullato. Nei primi
	## istanti puo' non essere ancora attivo: la richiesta viaggia un frame.
	if _t > 0.15 and not bool(anim_tree.get("parameters/Attack/active")):
		_annulla()
		return
	## Estrazione, incocco, rilascio: le tre frazioni del set per il tiro in corso.
	var estrazione : float = float(set_arco.get("estrazione_caricata")) if _caricato else float(set_arco.get("estrazione"))
	var incocco : float = float(set_arco.get("incocco_caricato")) if _caricato else float(set_arco.get("incocco"))
	var frazione : float = float(set_arco.get("rilascio_caricato")) if _caricato else float(set_arco.rilascio)
	if _freccia != null and estrazione > 0.0 and not _rilasciata and mano_che_tira != null 			and _freccia.fase() == FrecciaInMano.Fase.NASCOSTA and _t >= _durata * estrazione:
		_freccia.monta(FrecciaInMano.modello_di(_scena_freccia()))
		_freccia.estrai(mano_che_tira, set_arco.get("presa_freccia"))
	if not _tesa and not _rilasciata and _t >= _durata * incocco:
		_tesa = true
		var c := _corda()
		if c != null and mano_che_tira != null:
			c.tendi(mano_che_tira)
			if _freccia != null and _freccia.fase() != FrecciaInMano.Fase.NASCOSTA:
				_freccia.incocca(c)
	if not _rilasciata and _t >= _durata * frazione:
		_scocca()
	if _t >= _durata:
		_fine()


func _scocca() -> void:
	_rilasciata = true
	var c := _corda()
	if c != null:
		c.rilascia()
	if _freccia != null:
		_freccia.rilascia()
	var scena : PackedScene = _scena_freccia()
	if scena == null:
		return
	var origine := _bocca()
	var avanti : Vector3 = player.global_transform.basis.z.normalized()
	if player.has_method("aim_direction_from"):
		avanti = player.aim_direction_from(origine, avanti)
	var f := scena.instantiate() as Node3D
	if f == null:
		return
	f.set("direction", avanti.normalized())
	f.set("speed", float(set_arco.velocita_freccia))
	f.set("move", _colpo())
	f.set("source", player)
	player.get_parent().add_child(f)
	f.global_position = origine
	scoccata.emit(f)


## Da dove parte la freccia: l'incocco della corda dell'arco in mano, o davanti
## al petto se l'arco non ce l'ha.
func _bocca() -> Vector3:
	var arco := _arco_in_mano()
	if arco != null:
		var inc := arco.get_node_or_null("Corda/Incocco") as Node3D
		if inc != null:
			return inc.global_position
	var avanti : Vector3 = player.global_transform.basis.z
	avanti.y = 0.0
	return player.global_position + Vector3.UP * float(set_arco.altezza_bocca) + avanti.normalized() * 0.5


## Che freccia tirare: quella dichiarata dall'ARCO in mano, o quella del set.
func _scena_freccia() -> PackedScene:
	var res := _risorsa_arco()
	if res != null and ("freccia" in res) and res.freccia != null:
		return res.freccia
	return set_arco.freccia if set_arco != null else null


## Il COLPO che la freccia porta: la risorsa dell'arco, con `power` gia'
## scalato sulle Marche da `held_weapon.gd`. Il tiro CARICATO ne porta una
## copia con potenza, posa e spinta moltiplicate — la stessa regola del colpo
## forte della spada in `equipment_system.gd`, duplicando per non mutare la
## risorsa che il tiro rapido condivide.
func _colpo() -> Resource:
	var res := _risorsa_arco()
	if res == null or not _caricato or not (res is ArcaniumEquipmentResource):
		return res
	var forte : ArcaniumEquipmentResource = res.duplicate()
	forte.power = int(round(res.power * res.heavy_power_mult))
	forte.poise_damage = res.poise_damage * res.heavy_poise_mult
	forte.spinta = res.spinta * res.heavy_spinta_mult
	forte.scossa = Scossa.MEDIO
	return forte


func in_tiro_caricato() -> bool:
	return _in_tiro and _caricato


## La risorsa dell'arco.
func _risorsa_arco() -> Resource:
	if weapon_system != null and "current_equipment" in weapon_system and weapon_system.current_equipment != null:
		return weapon_system.current_equipment.equipment_info
	return null


func _fine() -> void:
	_in_tiro = false
	var c := _corda()
	if c != null:
		c.rilascia()
	if _freccia != null:
		_freccia.rilascia()


func _annulla() -> void:
	if not _in_tiro:
		return
	_fine()
	annullato.emit()
