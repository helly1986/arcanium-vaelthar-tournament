extends BossProjectile

## ═══════════════════════════════════════════════════════════════════════════
## FRECCIA — il proiettile dell'arciere Sylvorn
## ═══════════════════════════════════════════════════════════════════════════
##
## Estende `BossProjectile` per il volo, il contatto e le fazioni: e' lo stesso
## contratto (`direction`, `speed`, `move`, `source`) che `_fire_projectile`
## dell'umanoide riempie, e non c'era ragione di riscrivere la parte che
## funziona. Cambiano solo le due cose che una freccia fa diversamente da un
## orbo di Erosione:
##
##   • l'ASPETTO: un'asta sottile orientata lungo il volo, niente luce negativa,
##     niente braci — una freccia si vede per la scia dritta, non per il bagliore;
##   • l'IMPATTO: si conficca e sparisce. Non sfonda gli oggetti distruttibili
##     (l'orbo abbatte 2,2 m di scenario: una freccia no).
##
## Il raggio di contatto resta quello del padre (0,35 m): e' generoso per un'asta,
## ma a 22 m/s con un solo giro di fisica fra un campione e l'altro un raggio
## realistico bucherebbe il player fra due frame. Meglio un contatto largo di
## un tiro che passa attraverso.

## La lunghezza della freccia, in metri: e' quella a cui `prepara_frecce.py`
## porta i modelli, ed e' UNA — la freccia in mano (`freccia_in_mano.gd`) e i
## misuratori la leggono da qui. 70 cm: una freccia vera (28 pollici).
const LUNGHEZZA := 0.70
const SPESSORE := 0.025

## Il modello della freccia (un GLB passato da `prepara_frecce.py`: punta a
## -Z, cocca a +Z, asta sull'origine, LUNGHEZZA). Vuoto = i due cilindri di
## ripiego qui sotto, che sono la freccia di quando il prop non c'era ancora.
## Il tipo di freccia e' la SCENA: `freccia.tscn` porta quella di ferro,
## `freccia_spirito.tscn` quella di Spirito; domani ognuna la sua.
@export var modello : PackedScene

## Il colore della SCIA (`scia_freccia.gd`): e' la lettura del tiro, e il tipo
## di freccia lo decide la scena come il modello — Spirito verde-acqua, ferro
## bianco caldo.
@export var colore_scia : Color = Color(1.0, 0.9, 0.7)

const SciaFreccia := preload("res://arcanium/systems/armi/scia_freccia.gd")


func _ready() -> void:
	super._ready()
	## Orientata lungo il volo: `direction` e' gia' stata scritta da chi
	## ci ha istanziato (prima di `add_child`), quindi qui c'e'.
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	## La scia nel livello, accanto alla freccia: le sopravvive un attimo
	## all'impatto invece di sparire con lei.
	var scia := SciaFreccia.new()
	scia.name = "SciaFreccia"
	scia.freccia = self
	scia.colore = colore_scia
	get_parent().add_child.call_deferred(scia)


func _build_visuals() -> void:
	if modello != null:
		var m := modello.instantiate() as Node3D
		if m != null:
			m.name = "Modello"
			add_child(m)
			return
	var asta := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = SPESSORE * 0.5
	mesh.bottom_radius = SPESSORE
	mesh.height = LUNGHEZZA
	mesh.radial_segments = 6
	asta.mesh = mesh
	## Il cilindro nasce lungo Y: lo si corica lungo -Z, che e' l'asse su cui
	## `look_at` punta il nodo.
	asta.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.24, 0.16)
	m.roughness = 0.85
	asta.material_override = m
	add_child(asta)

	var punta := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0
	pm.bottom_radius = SPESSORE * 1.6
	pm.height = 0.09
	pm.radial_segments = 6
	punta.mesh = pm
	punta.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	punta.position = Vector3(0.0, 0.0, -(LUNGHEZZA * 0.5 + 0.04))
	var mp := StandardMaterial3D.new()
	mp.albedo_color = Color(0.55, 0.58, 0.6)
	mp.metallic = 0.8
	mp.roughness = 0.35
	punta.material_override = mp
	add_child(punta)


## I primi metri di volo non toccano il MONDO. La sfera di contatto e' larga
## (0,35 m, vedi sopra) e la freccia parte dall'arco: dal camminamento del
## cancello di Kalvorn, a un palmo sopra il parapetto, la sfera lo toccava al
## primo fotogramma e la freccia si piantava nel muro davanti all'arciere invece
## di volare (2026-09-25). Chi si puo' colpire invece si colpisce da subito.
const DISARMO_MONDO := 1.5

var _partenza : Vector3
var _partita : bool = false


func _physics_process(delta : float) -> void:
	if not _partita:
		_partenza = global_position
		_partita = true
	super._physics_process(delta)


func _on_body_entered(body : Node) -> void:
	if _alive and body != source and not Fazioni.colpibile(body, source) 			and (not _partita or global_position.distance_to(_partenza) < DISARMO_MONDO):
		return
	super._on_body_entered(body)


## Si conficca: niente scarico sugli oggetti distruttibili, niente esplosione.
func _impact() -> void:
	if not _alive:
		return
	_alive = false
	_fade_and_free()


func _burst() -> void:
	pass
