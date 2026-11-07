extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ESECUTORE DI LUCIDE TECNICHE
## ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ Niente `class_name`: si importa con `preload`. Vedi `fazioni.gd`.
##
## Prende la `LucidaTecnica` dichiarata dall'arma in mano e la esegue: suona il
## gesto, tiene aperta la finestra in cui l'arma è viva, e ci fa nascere sopra
## l'effetto lungo la traccia della lama. Poi mette il cooldown.
##
## ─── Non sa nulla del Rovescio Risonante ────────────────────────────────────
## Volutamente. Questo file non nomina il muro di fuoco, l'Erosione né il Senza
## Nome: legge quattro dati da una risorsa e li esegue. La seconda Lucida
## Tecnica non passa da qui — passa da un `.tres`.
##
## ─── La finestra segue il PLAYHEAD, non un timer ────────────────────────────
## È la lezione già pagata dai nemici. `equipment_system.gd` apre la finestra
## d'arma con `anim_length * 0.3` e la chiude a `* 0.5`: due timer che partono
## insieme alla clip e poi vivono di vita propria. Se l'animazione viene
## interrotta, rallentata o fusa con un'altra, i timer non lo sanno e l'arma
## resta viva mentre a schermo il gesto è già finito.
##
## Qui la finestra è una DOMANDA sul playhead: "il gesto è fra il 15% e il 60%?"
## Una clip interrotta smette semplicemente di stare dentro la finestra, senza
## bisogno di invalidare nulla — lo stesso motivo per cui il controller nemico
## ha buttato via i suoi timer e le sue coroutine.

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const Fazioni := preload("res://arcanium/systems/fazioni.gd")
const InfusioneArma := preload("res://arcanium/systems/lucide/infusione_arma.gd")
## Sotto questi secondi rimasti un'infusione si puo' rinnovare; prima si rifiuta, per non
## buttare il costo.
const RINNOVO_INFUSIONE := 30.0

## Nodi dell'AnimationTree che compongono l'UNICO slot per le Lucide Tecniche.
## Il caster ci scrive dentro la clip della tecnica in corso: un nodo per
## tecnica avrebbe fatto crescere il grafo di un ramo a ogni arma nuova.
const NODO_ONESHOT := "LucidaTecnica"
const NODO_ANIM := "LucidaTecnicaAnim"

@export var player : Node3D
@export var anim_tree : AnimationTree
@export var blade_trail : Node
## EquipmentLoadout, per sapere l'arma in mano. Di norma si lascia VUOTO: è un
## autoload, e si risolve da solo in `_ready`.
##
## ⚠️ Non provare a puntarlo dalla scena con `NodePath("/root/EquipmentLoadout")`:
## un NodePath esportato viene risolto quando la scena viene istanziata, cioè
## PRIMA che entri nell'albero, e un percorso assoluto fuori dalla scena non
## esiste ancora — il campo resta `null` in silenzio. Ci sono già cascato: la
## Lucida Tecnica non partiva perché il caster non sapeva quale arma avessi.
@export var loadout : Node
@export var vitals : Node           ## PlayerVitals, per il costo in Arcanium Vivo

signal iniziata(tecnica : Resource)
signal finita(tecnica : Resource)
signal rifiutata(motivo : String)
## Per la HUD: quanto manca, e su quanto. Emesso a ogni cambiamento di stato.
signal cooldown_cambiato(rimasto : float, totale : float)

## Cooldown per TECNICA e non per arma: cambiare spada e tornare indietro non
## deve azzerare l'attesa. La chiave è la risorsa stessa, come fa SpellCaster
## con gli incantesimi.
var _cooldown_fino : Dictionary = {}

var _in_corso : Resource = null
var _finestra_aperta : bool = false
var _impatto_fatto : bool = false
var _corda_tesa : bool = false
var _carica : Node3D = null
## Quanto manca alla fine del canale, e l'effetto che vive con lui.
var _canale_resta : float = 0.0
var _effetto : Node = null
## L'infusione in corso: la tecnica, l'arma che la porta, quando finisce, e cosa si vede.
var _infusione : Resource = null
var _infusa : Resource = null
var _infusione_fino : float = 0.0
var _infusione_vfx : Node = null
## Tempo trascorso dentro il gesto e sua durata attesa. Vedi `_physics_process`
## per perché non basta chiedere l'avanzamento all'AnimationTree.
var _t : float = 0.0
var _durata : float = 0.0
## Il OneShot diventa `active` solo al primo tick dell'albero, non nell'istante
## in cui si manda la richiesta: senza questo flag, "non è attivo" al frame zero
## verrebbe scambiato per "è già finito" e la tecnica si chiuderebbe subito.
var _visto_attivo : bool = false


func _ready() -> void:
	if loadout == null:
		loadout = get_node_or_null("/root/EquipmentLoadout")
	if loadout == null:
		push_warning("LucidaTecnicaCaster: EquipmentLoadout non trovato — nessuna tecnica sarà lanciabile.")
	set_physics_process(true)
	if player != null and player.has_signal("hurt_started"):
		player.hurt_started.connect(_interrompi)
	if player != null and player.has_signal("death_started"):
		player.death_started.connect(_interrompi)


## La tecnica dell'arma attualmente in mano, o null.
func tecnica_corrente() -> Resource:
	if loadout == null:
		return null
	var arma = loadout.equipped_in("arma_primaria")
	if arma == null or not ("lucida_tecnica" in arma):
		return null
	var t = arma.lucida_tecnica
	if t == null or not t.has_method("valida") or not t.valida():
		return null
	return t


func rimanente(t : Resource) -> float:
	if t == null:
		return 0.0
	return maxf(0.0, float(_cooldown_fino.get(t, 0.0)) - _adesso())


func pronta(t : Resource) -> bool:
	return t != null and rimanente(t) <= 0.0


## Tenta il lancio. Ritorna true se il gesto è partito.
##
## L'ordine dei controlli non è casuale: prima quelli che NON costano nulla
## (esiste? è pronta? non ne sto già facendo una?), poi la spesa. Invertirlo
## significherebbe scalare Arcanium Vivo per un lancio che poi non parte.
func lancia() -> bool:
	var t := tecnica_corrente()
	if t == null:
		rifiutata.emit("nessuna_tecnica")
		return false
	if _in_corso != null:
		rifiutata.emit("gia_in_corso")
		return false
	if not pronta(t):
		rifiutata.emit("cooldown")
		return false
	if _infusione == t and _infusione_fino - _adesso() > RINNOVO_INFUSIONE:
		rifiutata.emit("gia_infusa")
		return false
	if t.costo > 0.0 or t.costo_stamina > 0.0:
		if vitals == null or not vitals.has_method("spend_arcanium"):
			rifiutata.emit("nessun_vitals")
			return false
		## Si controllano tutti e due prima di spendere: un rifiuto non costa niente.
		if vitals.stamina < t.costo_stamina:
			rifiutata.emit("stamina_insufficiente")
			return false
		if not vitals.spend_arcanium(t.costo):
			rifiutata.emit("arcanium_insufficiente")
			return false
		vitals.spend_stamina(t.costo_stamina)

	if not _suona(t):
		rifiutata.emit("clip_non_risolta")
		return false

	_in_corso = t
	_finestra_aperta = false
	_impatto_fatto = false
	_corda_tesa = false
	_t = 0.0
	if t.ferma and "tecnica_ferma" in player:
		player.tecnica_ferma = true
	if t.carica != null:
		var arma = player.get("weapon_system").current_equipment if player.get("weapon_system") != null else null
		if arma is Node3D:
			_carica = t.carica.instantiate() as Node3D
			(arma as Node3D).add_child(_carica)
	_visto_attivo = false
	_durata = _durata_clip()
	if t.cooldown > 0.0:
		_cooldown_fino[t] = _adesso() + t.cooldown
		cooldown_cambiato.emit(t.cooldown, t.cooldown)
	iniziata.emit(t)
	return true


## Scrive la clip nello slot generico e fa partire il OneShot.
func _suona(t : Resource) -> bool:
	if anim_tree == null or anim_tree.tree_root == null:
		return false
	var radice := anim_tree.tree_root as AnimationNodeBlendTree
	if radice == null or not radice.has_node(NODO_ANIM):
		return false
	var nodo := radice.get_node(NODO_ANIM) as AnimationNodeAnimation
	if nodo == null:
		return false
	nodo.animation = StringName(t.clip)
	anim_tree.set("parameters/%s/request" % NODO_ONESHOT,
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


## L'avanzamento nel gesto si MISURA qui, non si chiede all'AnimationTree.
##
## Il tentativo precedente leggeva `parameters/<OneShot>/time_to_end`: quel
## parametro NON esiste su AnimationNodeOneShot, quindi tornava `null`, che come
## float è 0.0, che come avanzamento è 1.0 — fuori finestra a ogni frame. Il
## risultato era una tecnica che partiva, metteva il cooldown, e non generava
## mai il muro. Verificato in gioco: `muri in scena: 0`.
##
## Restare agganciati allo stato dell'albero però conta, ed è il motivo per cui
## qui non c'è un semplice timer: se il gesto viene INTERROTTO (colpo incassato,
## morte, cambio arma), il OneShot smette di essere attivo e la finestra si
## chiude da sola. Un timer puro continuerebbe a contare a vuoto e terrebbe
## l'arma viva mentre a schermo il gesto non c'è più — che è esattamente il
## difetto di `equipment_system.gd`.
func _physics_process(delta : float) -> void:
	if _infusione != null and _adesso() >= _infusione_fino:
		_fine_infusione()
	if _canale_resta > 0.0:
		_canale_resta -= delta
		if _canale_resta <= 0.0 and _in_corso == null:
			_libera()
	if _in_corso == null:
		return

	var attivo : bool = bool(anim_tree.get("parameters/%s/active" % NODO_ONESHOT)) if anim_tree != null else false
	if attivo:
		_visto_attivo = true
	elif _visto_attivo:
		_chiudi()      # interrotto o finito prima del previsto
		return

	_t += delta
	if _durata <= 0.0 or _t >= _durata:
		_chiudi()
		return

	var avanzamento : float = _t / _durata
	if _in_corso.tende_corda_a > 0.0 and not _corda_tesa and not _impatto_fatto and avanzamento >= _in_corso.tende_corda_a:
		_corda_tesa = true
		_corda("tendi_corda")
	if _in_corso.impatto != null and not _impatto_fatto and avanzamento >= _in_corso.impatto_a:
		_impatto_fatto = true
		_lascia_la_carica()
		_fai_impatto(_in_corso)
	if _in_corso.infusione_metodo != "" and not _impatto_fatto and avanzamento >= _in_corso.impatto_a:
		_impatto_fatto = true
		_infondi(_in_corso)
	var dentro : bool = avanzamento >= _in_corso.finestra_da and avanzamento <= _in_corso.finestra_a
	if dentro and not _finestra_aperta:
		_apri()
	elif not dentro and _finestra_aperta:
		_chiudi_finestra()


## L'effetto dell'impatto: a terra sotto l'arma, girato come chi colpisce. Vive nel
## livello: resta anche se chi colpisce si sposta.
func _fai_impatto(t : Resource) -> void:
	var n := t.impatto.instantiate() as Node3D
	var mondo := player.get_parent()
	var sotto : Vector3 = player.global_position
	var arma = player.get("weapon_system").current_equipment if player.get("weapon_system") != null else null
	if arma is Node3D:
		sotto.x = (arma as Node3D).global_position.x
		sotto.z = (arma as Node3D).global_position.z
	if "lanciatore" in n:
		n.lanciatore = player
	if "costo" in n:
		n.costo = t.costo
	if "potenza" in n:
		var info := _info_danno()
		n.potenza = float(info.power) * t.danno_mult if info != null else 0.0
	## La posa prima di entrare nell'albero: il suo `_ready` guarda dov'e'.
	_effetto = n
	_canale_resta = t.canale
	var posa := Transform3D(Basis(Vector3.UP, player.global_rotation.y), sotto)
	n.transform = (mondo as Node3D).global_transform.affine_inverse() * posa if mondo is Node3D else posa
	mondo.add_child(n)


func _durata_clip() -> float:
	if _in_corso == null or anim_tree == null:
		return 0.0
	var ap := anim_tree.get_node_or_null(anim_tree.anim_player) as AnimationPlayer
	if ap == null or not ap.has_animation(_in_corso.clip):
		return 0.0
	return ap.get_animation(_in_corso.clip).length / maxf(_in_corso.speed_scale, 0.01)


func _apri() -> void:
	_finestra_aperta = true
	if blade_trail == null or _in_corso.effetto == null:
		return
	# Chi brucia lo deduce `Fazioni` dal player: qui si passa il CORPO, non
	# questo nodo, o la tecnica resterebbe senza schieramento.
	blade_trail.begin(_in_corso.effetto, _info_danno(), player,
		_in_corso.effetto_durata, _in_corso.effetto_danno_tick,
		_in_corso.effetto_intervallo_tick, _in_corso.effetto_maschera,
		_in_corso.fuoco_amico)


func _chiudi_finestra() -> void:
	_finestra_aperta = false
	if blade_trail != null:
		blade_trail.end()   # l'effetto resta in scena a vivere la sua durata


## Infonde l'arma in mano: e' lei a portarla, e se si cambia set resta su di lei.
func _infondi(t : Resource) -> void:
	_fine_infusione()
	_infusione = t
	_infusa = _info_danno()
	_infusione_fino = _adesso() + t.infusione_durata
	var arma = player.get("weapon_system").current_equipment if player.get("weapon_system") != null else null
	if not (arma is Node3D):
		return
	var v := InfusioneArma.new()
	v.name = "InfusioneArma"
	v.aspetto = t.infusione_aspetto
	v.colore = t.infusione_colore
	v.nucleo = t.infusione_nucleo
	v.arma = arma
	(arma as Node3D).add_child(v)
	_infusione_vfx = v
	if loadout != null and loadout.has_signal("changed") and not loadout.changed.is_connected(_riveste_infusione):
		loadout.changed.connect(_riveste_infusione)
	_riveste_infusione()


## Il cambio d'arma: la pellicola si rimette solo se in mano c'e' l'arma infusa.
func _riveste_infusione() -> void:
	if not is_instance_valid(_infusione_vfx):
		return
	if infusione_attiva():
		_infusione_vfx.visible = true
		_infusione_vfx.set_physics_process(true)
		_infusione_vfx.rivesti.call_deferred()
	else:
		_infusione_vfx.visible = false
		_infusione_vfx.set_physics_process(false)
		_infusione_vfx._togli_pellicola()


func _fine_infusione() -> void:
	_infusione = null
	_infusa = null
	_infusione_fino = 0.0
	if is_instance_valid(_infusione_vfx):
		_infusione_vfx.spegni()
	_infusione_vfx = null


## Vero se l'arma in mano adesso e' quella infusa.
func infusione_attiva() -> bool:
	return _infusione != null and _infusa != null and _info_danno() == _infusa


## Lo chiama l'arma dopo ogni colpo andato a segno.
func dopo_il_colpo(bersaglio : Node) -> void:
	if not infusione_attiva() or not is_instance_valid(bersaglio):
		return
	var salute = bersaglio.get("health_system")
	var host = salute.get("status_host") if salute != null else null
	if host != null and host.has_method(_infusione.infusione_metodo):
		host.call(_infusione.infusione_metodo, _infusione.infusione_accumulo)


## La corda dell'arco la tiene ArcieriaPlayer, come nel tiro.
func _corda(metodo : String) -> void:
	var arcieria : Node = player.get_node_or_null("ArcieriaPlayer")
	if arcieria != null and arcieria.has_method(metodo):
		arcieria.call(metodo)


func _lascia_la_carica() -> void:
	if _corda_tesa:
		_corda_tesa = false
		_corda("rilascia_corda")
	if _carica != null and is_instance_valid(_carica):
		_carica.queue_free()
	_carica = null


func _chiudi() -> void:
	if _finestra_aperta:
		_chiudi_finestra()
	_lascia_la_carica()
	var t := _in_corso
	_in_corso = null
	if _canale_resta <= 0.0:
		_libera()
	if t != null:
		finita.emit(t)


func _libera() -> void:
	_canale_resta = 0.0
	_effetto = null
	if "tecnica_ferma" in player:
		player.tecnica_ferma = false


## Un colpo subito interrompe una tecnica che tiene fermi: il gesto si tronca e l'effetto
## si spegne. Quelle che non tengono fermi le tronca gia' l'albero, e i loro effetti
## restano.
func _interrompi() -> void:
	if not ("tecnica_ferma" in player) or not player.tecnica_ferma:
		return
	if _in_corso != null and anim_tree != null:
		anim_tree.set("parameters/%s/request" % NODO_ONESHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	if _effetto != null and is_instance_valid(_effetto) and _effetto.has_method("spegni"):
		_effetto.spegni()
	_canale_resta = 0.0
	_chiudi()
	_libera()


## La risorsa passata all'effetto perché sappia tipo di danno e status. È
## l'arma equipaggiata: la Lucida Tecnica colpisce con la natura della lama che
## la insegna, non con una tabella danni sua.
func _info_danno() -> Resource:
	if loadout == null:
		return null
	return loadout.equipped_in("arma_primaria")


func _adesso() -> float:
	return OrologioGioco.adesso()
