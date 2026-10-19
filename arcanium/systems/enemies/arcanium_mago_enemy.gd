extends "res://arcanium/systems/enemies/arcanium_distanza_enemy.gd"

## ⚠️ Niente `class_name`: come gli altri nemici si aggancia per percorso.

## ═══════════════════════════════════════════════════════════════════════════
## MAGO GUERRIERO — la Voce Rimasta (Sylvorn, grado ④)
## ═══════════════════════════════════════════════════════════════════════════
##
## LORE/CREATURES.md ④: «tiene le distanze, radica il terreno sotto i piedi del
## giocatore e richiama Eco Radicate — evocazioni che a loro volta non
## rispondono più a nessuno. Combatte usando il bosco, non contro di te.» La
## canalizzazione in lui non si è spenta, si è SLEGATA: le magie sono più forti
## e più sporche del dovuto, e ogni tanto partono verso nessuno.
##
## Le distanze le tiene la base (`arcanium_distanza_enemy.gd`: la ritirata
## dell'arciere). Qui ci sono le tre mosse, riconosciute dall'`id` della
## EnemyMove, e nient'altro è speciale:
##
##   RADICI   — a `radici_segna` secondi di clip SEGNA dove sta il bersaglio, e
##              lì e ai due lati (di traverso alla linea mago→bersaglio) si
##              aprono tre cerchi: la radice dell'Eco Guasta (`EcoFx.radice`),
##              che esplode al contatto. Tre in fila di traverso: si esce avanti
##              o indietro, non di lato. Chi resta dentro è preso (la mossa
##              porta `stun_time`: la radice AFFERRA).
##              Con `sbandata` di probabilità la magia gli sfugge: i cerchi si
##              aprono su un punto a caso attorno a lui, verso nessuno. È il
##              «più sporche del dovuto» della lore, e un respiro per chi lo
##              sta inseguendo.
##   RICHIAMO — la clip di lancio rallentata (le braccia che restano alzate un
##              istante di troppo, finché non c'è la clip vera). All'inizio
##              segna dove usciranno le Eco con l'anello della radice; al
##              contatto le fa uscire. Mai più di `richiamo_max` vive alla
##              volta: la mossa non si sceglie nemmeno, se il tetto è pieno.
##   RESPINTA — chi gli arriva addosso: un cerchio attorno a lui (lo stesso
##              anello della radice, segnato all'inizio della mossa) che al
##              contatto colpisce e SPINGE via chi c'è dentro (`spinta` della
##              mossa). Non ha un'arma, quindi niente cono: `burst_radius` lo
##              sa fare solo il boss.
##   FRUSTA   — la Frusta di Spine: due rampicanti escono dalle mani
##              (`frusta_spine.gd`) e si caricano dietro di lui; a
##              `frusta_mira` secondi di clip MIRA il punto dove sta il
##              bersaglio (entro `frusta_portata`), e al contatto sferzano lì.
##              Colpisce chi sta sulla linea mago→punto, larga
##              `frusta_larghezza`: si schiva di lato, dopo la mira. Ferisce e
##              accumula LACERAZIONE (`laceration_buildup` della mossa).
##   (le altre) — il nemico umanoide com'è.
##
## Le Eco evocate sono la stessa `eco_radicata_guasta.tscn` di Kalvorn, con il
## loro corpo di spirito e le loro tre mosse: il Mago non le comanda, le
## sveglia. Nascono già rivolte al bersaglio, con lui come bersaglio.

const EcoFx := preload("res://arcanium/systems/spiriti/eco_fx.gd")

@export_group("Voce Rimasta")
## Il colore delle sue magie: lo stesso viola sporco delle Eco Guaste.
@export var colore : Color = Color(0.62, 0.32, 1.0)
## RADICI: quando si segna il punto (secondi di clip), raggio dei cerchi e
## quanto stanno di lato quelli ai fianchi.
@export var radici_segna : float = 0.85
@export var radici_raggio : float = 1.5
@export var radici_scarto : float = 2.6
## Probabilità che la magia parta verso nessuno, e quanto lontano da lui.
@export_range(0.0, 1.0) var sbandata : float = 0.15
@export var sbandata_distanza : Vector2 = Vector2(4.0, 8.0)
## RICHIAMO: la scena evocata, quante per lancio, il tetto delle vive, e dove
## escono (metri davanti a lui, e di lato).
@export var richiamo_scena : PackedScene
@export var richiamo_quante : int = 2
@export var richiamo_max : int = 3
@export var richiamo_davanti : float = 2.2
@export var richiamo_lato : float = 2.0

const RADICI := "RADICI"
const RICHIAMO := "RICHIAMO"
const RESPINTA := "RESPINTA"
const FRUSTA := "FRUSTA"
const FrustaSpine := preload("res://arcanium/systems/spiriti/frusta_spine.gd")

## FRUSTA: quando mira (secondi di clip), quanto arriva, quanto è larga la
## sferzata, e quanto prima del contatto le punte partono verso il punto.
@export var frusta_mira : float = 1.05
@export var frusta_portata : float = 10.0
@export var frusta_larghezza : float = 0.9
@export var frusta_anticipo : float = 0.2
## Le ossa delle mani, da cui escono i rampicanti.
@export var mano_sinistra : String = "LeftHand"
@export var mano_destra : String = "RightHand"

## RESPINTA: il raggio del cerchio attorno a lui.
@export var respinta_raggio : float = 3.0

var _punti : Array[Vector3] = []
var _segnata := false
var _evocate : Array[Node3D] = []
var _frusta : Node3D = null
var _frusta_punto := Vector3.ZERO
var _frusta_mirata := false
var _frusta_partita := false


## Il tetto delle evocazioni vive: con il tetto pieno il richiamo non si sceglie.
func _move_is_usable(move : EnemyMove) -> bool:
	if move.id == RICHIAMO:
		if richiamo_scena == null or _evocate_vive() >= richiamo_max:
			return false
	return super._move_is_usable(move)


func _evocate_vive() -> int:
	_evocate = _evocate.filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion() \
		and e.get("_state") != State.DEAD)
	return _evocate.size()


func _on_move_started(move : EnemyMove, clip_len : float) -> void:
	super._on_move_started(move, clip_len)
	_segnata = false
	_punti.clear()
	if move.id == FRUSTA:
		_frusta_mirata = false
		_frusta_partita = false
		var sk := _scheletro()
		if sk != null:
			_frusta = FrustaSpine.new()
			_frusta.prepara(sk, mano_sinistra, mano_destra, colore)
			get_parent().add_child(_frusta)
	elif move.id == RESPINTA:
		_segnata = true
		_punti.append(_a_terra(global_position))
		EcoFx.radice(get_parent(), _punti[0], respinta_raggio, _al_contatto(move), colore)
	elif move.id == RICHIAMO:
		## Dove usciranno, segnato da subito: il richiamo è lento apposta, e
		## chi vede gli anelli ha il tempo di andare a interromperlo.
		_segnata = true
		var n := mini(richiamo_quante, richiamo_max - _evocate_vive())
		var avanti := global_transform.basis.z
		avanti.y = 0.0
		avanti = avanti.normalized()
		var lato := Vector3(avanti.z, 0.0, -avanti.x)
		for i in n:
			var segno := 1.0 if i % 2 == 0 else -1.0
			var p := global_position + avanti * richiamo_davanti + lato * richiamo_lato * segno * (1.0 + float(i / 2))
			_punti.append(_a_terra(p))
		var avviso := _al_contatto(move)
		for p in _punti:
			EcoFx.radice(get_parent(), p, 0.9, avviso, colore)


## Ogni frame, anche in mossa: è qui che le RADICI segnano il punto.
func _pre_ai_step(delta : float) -> void:
	super._pre_ai_step(delta)
	var m := _active_move
	if m == null or _clip_corrente() != m.anim or not is_instance_valid(target):
		return
	if m.id == FRUSTA:
		_passo_frusta(m)
		return
	if m.id != RADICI or _segnata:
		return
	if _clip_pos() >= radici_segna:
		_segna_radici(m)


## La FRUSTA nel tempo della clip: prima mira, poi fa partire le punte.
func _passo_frusta(m : EnemyMove) -> void:
	var pos := _clip_pos()
	if not _frusta_mirata and pos >= frusta_mira:
		_mira_frusta()
	if _frusta_mirata and not _frusta_partita:
		var c := _contact_times(m)
		var contatto : float = c[0] if not c.is_empty() else m.telegraph
		if pos >= contatto - frusta_anticipo:
			_frusta_partita = true
			if is_instance_valid(_frusta):
				_frusta.sferza(_frusta_punto, maxf(contatto - pos, 0.05) / maxf(_move_speed(m), 0.01))


## Il punto della sferzata: dove sta il bersaglio ADESSO, all'altezza del petto,
## mai oltre la portata. Da qui in poi si schiva spostandosi.
func _mira_frusta() -> void:
	_frusta_mirata = true
	var verso := target.global_position - global_position
	verso.y = 0.0
	var dist := minf(verso.length(), frusta_portata)
	var dir := verso.normalized() if verso.length() > 0.01 else global_transform.basis.z
	_frusta_punto = _a_terra(global_position + dir * dist) + Vector3(0.0, 1.0, 0.0)


## Colpito se il bersaglio sta sulla linea della sferzata (in pianta), non
## oltre la punta.
func _frusta_prende() -> bool:
	if not _frusta_mirata or not is_instance_valid(target):
		return false
	var a := Vector2(global_position.x, global_position.z)
	var b := Vector2(_frusta_punto.x, _frusta_punto.z)
	var p := Vector2(target.global_position.x, target.global_position.z)
	var ab := b - a
	var k := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * k) <= frusta_larghezza and absf(target.global_position.y - (_frusta_punto.y - 1.0)) < 2.0


func _scheletro() -> Skeleton3D:
	if model == null:
		return null
	for n in model.find_children("*", "Skeleton3D", true, false):
		return n
	return null


## I tre cerchi delle RADICI, da dove sta il bersaglio adesso (o verso nessuno).
func _segna_radici(m : EnemyMove) -> void:
	_segnata = true
	_punti.clear()
	var centro := target.global_position
	var verso := centro - global_position
	if randf() < sbandata:
		## Verso nessuno: un punto a caso attorno a lui.
		var a := randf() * TAU
		centro = global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(sbandata_distanza.x, sbandata_distanza.y)
		verso = centro - global_position
	verso.y = 0.0
	var lato := Vector3(verso.z, 0.0, -verso.x).normalized() if verso.length() > 0.01 else Vector3.RIGHT
	for k in [0.0, 1.0, -1.0]:
		_punti.append(_a_terra(centro + lato * radici_scarto * k))
	var avviso := _al_contatto(m)
	for p in _punti:
		EcoFx.radice(get_parent(), p, radici_raggio, avviso, colore)


func _deliver_hit(move : EnemyMove) -> void:
	match move.id:
		RADICI:
			## I cerchi, non il cono: conta dove sta il bersaglio ADESSO.
			if _segnata and is_instance_valid(target) and target.has_method("hit"):
				for p in _punti:
					var d := target.global_position - p
					d.y = 0.0
					if d.length() <= radici_raggio:
						target.hit(self, move)
						break
		RICHIAMO:
			_evoca()
		FRUSTA:
			if _frusta_prende() and target.has_method("hit"):
				target.hit(self, move)
		RESPINTA:
			if is_instance_valid(target) and target.has_method("hit"):
				var d := target.global_position - global_position
				d.y = 0.0
				if d.length() <= respinta_raggio:
					target.hit(self, move)
					if move.spinta > 0.0 and target.has_method("spingi") and d.length() > 0.01:
						target.spingi(d.normalized(), move.spinta)
		_:
			super._deliver_hit(move)


func _evoca() -> void:
	if richiamo_scena == null:
		return
	for p in _punti:
		if _evocate_vive() >= richiamo_max:
			break
		var e := richiamo_scena.instantiate() as Node3D
		if e == null:
			continue
		get_parent().add_child(e)
		e.global_position = p + Vector3(0.0, 0.05, 0.0)
		if is_instance_valid(target):
			var guarda := target.global_position
			guarda.y = e.global_position.y
			if guarda.distance_to(e.global_position) > 0.1:
				## Il fronte delle mesh è +Z: si guarda dalla parte opposta.
				e.look_at(e.global_position * 2.0 - guarda, Vector3.UP)
			if "target" in e:
				e.set("target", target)
		_evocate.append(e)


func _clear_move_state() -> void:
	## Una frusta interrotta prima di sferzare torna nelle mani.
	if is_instance_valid(_frusta) and _frusta.fase() == FrustaSpine.Fase.CARICA:
		_frusta.ritira()
	_frusta = null
	_frusta_mirata = false
	_frusta_partita = false
	_segnata = false
	_punti.clear()
	super._clear_move_state()


## Secondi (di tempo vero) da adesso al contatto della mossa: quanto dura
## l'avviso dei cerchi.
func _al_contatto(move : EnemyMove) -> float:
	var c := _contact_times(move)
	var contatto : float = c[0] if not c.is_empty() else move.telegraph
	var ora := _clip_pos() if _clip_corrente() == move.anim else 0.0
	return maxf(contatto - ora, 0.2) / maxf(_move_speed(move), 0.01)


## Il punto sul suolo sotto `p`: i cerchi e le Eco non galleggiano su un pendio.
func _a_terra(p : Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p - Vector3(0, 6.0, 0), 1, [get_rid()])
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3) if not hit.is_empty() else p
