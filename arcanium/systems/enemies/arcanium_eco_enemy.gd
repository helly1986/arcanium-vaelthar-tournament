extends "res://arcanium/systems/enemies/arcanium_enemy.gd"

## ⚠️ Niente `class_name`: come gli altri nemici si aggancia per percorso.

## ═══════════════════════════════════════════════════════════════════════════
## ECO RADICATA GUASTA — l'evocazione che non risponde piu' a chi la chiama
## ═══════════════════════════════════════════════════════════════════════════
##
## LORE/CREATURES.md: quando la Marea Sorda arriva a un'evocazione gia' in
## piedi non la distrugge, la RIASSEGNA. E' la stessa Eco Radicata che Myori
## vende al Crocevia — stessa mesh, stesso modo di non fidarsi del terreno — col
## bordo viola d'Arcanium grezzo invece che verde. La somiglianza e' il
## contenuto.
##
## Il corpo e' `corpo_spirito.gd` (niente ossa: fluttua, i lembi ondeggiano, nel
## moto il fondo resta indietro) e le clip sono numeri (`eco_clip.gd`): questo
## script aggiunge solo cio' che le mosse fanno nel MONDO.
##
##   artigli — l'affondo vero (il corpo avanza nella finestra della
##             sciabolata) e i graffi di luce. Il colpo e' il cono frontale
##             del nemico base: artigli, non una lama.
##   radice  — quando affonda la coda (0,8 s di clip) SEGNA il punto dove sta il
##             bersaglio in quel momento; la radice esplode li' al contatto.
##             Colpisce chi e' nel cerchio, non chi e' davanti: si schiva
##             uscendone, e c'e' quasi un secondo per farlo.
##   beve    — a ogni contatto toglie Arcanium Vivo a chi e' vicino e se ne cura.
##             E' il rovescio dell'Eco evocata, che quell'Arcanium lo restituisce.

const EcoClip := preload("res://arcanium/systems/spiriti/eco_clip.gd")
const EcoFx := preload("res://arcanium/systems/spiriti/eco_fx.gd")

@export_group("Eco")
## Il colore della Guasta: viola d'Arcanium grezzo.
@export var colore : Color = Color(0.62, 0.32, 1.0)
## Artigli: quanto avanza il corpo, e in quale finestra della clip (secondi).
@export var affondo_artigli : float = 1.1
@export var finestra_artigli : Vector2 = Vector2(0.55, 0.74)
## Radice: quando si segna il punto (secondi di clip), raggio del cerchio.
@export var radice_segna : float = 0.8
@export var radice_raggio : float = 1.3
## Beve: Arcanium tolto a ogni contatto, e fin dove arriva.
@export var sorso : float = 2.0
@export var sorso_portata : float = 3.4

var _radice_punto := Vector3.ZERO
var _radice_segnata := false
var _sorso_fx := false


func _ready() -> void:
	## La libreria PRIMA del ready del padre, che suona gia' l'idle.
	if anim_player != null and not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", EcoClip.libreria())
	if model != null and "colore_bordo" in model:
		model.colore_bordo = colore
	super._ready()


## Gli istanti di contatto stanno accanto alle clip che li producono.
func _contact_times(move : EnemyMove) -> PackedFloat32Array:
	if move.contact_times.is_empty() and EcoClip.CONTATTI.has(move.anim):
		return PackedFloat32Array(EcoClip.CONTATTI[move.anim])
	return super._contact_times(move)


func _on_move_started(move : EnemyMove, clip_len : float) -> void:
	super._on_move_started(move, clip_len)
	_radice_segnata = false
	_sorso_fx = false


## Ogni frame, anche in mossa: e' qui che la radice segna il punto e che il
## sorso comincia a vedersi.
func _pre_ai_step(delta : float) -> void:
	super._pre_ai_step(delta)
	var m := _active_move
	if m == null or _clip_corrente() != m.anim or not is_instance_valid(target):
		return
	var pos := _clip_pos()
	if m.anim == "radice" and not _radice_segnata and pos >= radice_segna:
		_radice_segnata = true
		_radice_punto = target.global_position
		var contatto : float = EcoClip.CONTATTI["radice"][0]
		EcoFx.radice(get_parent(), _radice_punto, radice_raggio,
			(contatto - radice_segna) / maxf(_move_speed(m), 0.01), colore)
	elif m.anim == "beve" and not _sorso_fx and pos >= 0.4 \
			and _flat_distance(target) <= sorso_portata:
		_sorso_fx = true
		EcoFx.sorso(get_parent(), target, self, colore, 2.2 / maxf(_move_speed(m), 0.01))


## L'affondo degli artigli: il corpo avanza davvero nella finestra della
## sciabolata, verso dove guarda (e dal rilascio il facing e' bloccato).
func _attack_motion(delta : float) -> void:
	var m := _active_move
	if m != null and m.anim == "artigli" and _clip_corrente() == "artigli":
		var pos := _clip_pos()
		if pos >= finestra_artigli.x and pos <= finestra_artigli.y:
			var durata : float = (finestra_artigli.y - finestra_artigli.x) / maxf(_move_speed(m), 0.01)
			var avanti := global_transform.basis.z
			avanti.y = 0.0
			avanti = avanti.normalized() * (affondo_artigli / maxf(durata, 0.01))
			velocity.x = avanti.x
			velocity.z = avanti.z
			return
	super._attack_motion(delta)


func _on_move_released(move : EnemyMove) -> void:
	super._on_move_released(move)
	if move.anim == "artigli":
		var xf := global_transform
		xf.basis = Basis(Vector3.UP, rotation.y)
		EcoFx.artigli(get_parent(), xf, colore)


func _deliver_hit(move : EnemyMove) -> void:
	match move.anim:
		"radice":
			## Il cerchio, non il cono: conta dove sta il bersaglio ADESSO
			## rispetto al punto segnato.
			if _radice_segnata and is_instance_valid(target) and target.has_method("hit"):
				var d := target.global_position - _radice_punto
				d.y = 0.0
				if d.length() <= radice_raggio:
					target.hit(self, move)
		"beve":
			if is_instance_valid(target) and _flat_distance(target) <= sorso_portata:
				var vit = target.get("vitals")
				if vit != null and vit.has_method("drena_arcanium"):
					var tolto : float = vit.drena_arcanium(sorso)
					if tolto > 0.0 and health_system != null and health_system.has_method("heal"):
						health_system.heal(tolto)
		_:
			super._deliver_hit(move)


func _clear_move_state() -> void:
	_radice_segnata = false
	_sorso_fx = false
	super._clear_move_state()
