extends Node

## ═══════════════════════════════════════════════════════════════════════════
## IL RICHIAMO DEL BRANCO — l'ululato dell'Alpha porta rinforzi
## ═══════════════════════════════════════════════════════════════════════════
##
## Figlio di un lupo con `is_alpha`: ascolta il suo `howl_summon` (emesso
## all'apice dell'ululato, arcanium_quadruped_enemy.gd) e fa affiorare
## `rinforzi` lupi attorno a lui, con un tetto su quanti ne restano vivi.
##
## Sulla Traccia lo stesso lavoro lo fa il director (traccia_perduta_director.gd,
## `_on_alpha_howl`), che aggancia anche la barra del mini-boss. Kalvorn non ha
## un director: il capobranco porta il richiamo con se', cosi' funziona in
## qualunque livello lo si metta.
##
## ⚠️ I rinforzi nascono FRATELLI dell'Alpha, non figli: un figlio del corpo
## dell'Alpha lo seguirebbe ovunque, e morto lui sparirebbe col cadavere.

const Comparsa := preload("res://arcanium/systems/vfx/comparsa_evocazione.gd")

## Il lupo che il richiamo fa affiorare.
@export_file("*.tscn") var scena_lupo := "res://arcanium/characters/lupo.tscn"
## Quanti lupi per ululato.
@export var rinforzi := 2
## Tetto sui rinforzi vivi: il cooldown dell'ululato sta nel moveset, questo e'
## il secondo paletto perche' uno scontro lungo non degeneri.
@export var vivi_al_massimo := 2
## A che distanza dall'Alpha affiorano.
@export var distanza := 4.0

var _spawnati : Array[Node3D] = []


func _ready() -> void:
	var alpha := get_parent()
	if alpha != null and alpha.has_signal("howl_summon"):
		alpha.howl_summon.connect(_ulula)


## I rinforzi vivi (per le verifiche).
func spawnati() -> Array[Node3D]:
	_spawnati = _spawnati.filter(func(w): return is_instance_valid(w) and not w.is_dead())
	return _spawnati.duplicate()


func _ulula() -> void:
	var alpha := get_parent() as Node3D
	if alpha == null or not is_instance_valid(alpha) or alpha.get_parent() == null:
		return
	var posto : int = vivi_al_massimo - spawnati().size()
	if posto <= 0:
		return
	var packed := load(scena_lupo) as PackedScene
	if packed == null:
		return
	var padre := alpha.get_parent() as Node3D
	for i in mini(rinforzi, posto):
		var inst := packed.instantiate() as Node3D
		## Ai fianchi dell'Alpha, uno per lato.
		var ang := alpha.global_rotation.y + TAU * (0.25 + 0.5 * float(i))
		var dove := alpha.global_position + Vector3(cos(ang), 0.0, sin(ang)) * distanza
		## ⚠️ La posizione si mette PRIMA di entrare nell'albero. Aggiunto e poi
		## spostato, il lupo nasce un frame nell'origine del contenitore: se
		## li' c'e' un altro corpo la fisica lo spinge sopra, e quando quello
		## viene spostato se lo porta dietro come una piattaforma mobile
		## (verifica_branco, 2026-10-02: il capobranco finiva in groppa a un lupo
		## a 3,6 m dal suo posto).
		inst.position = padre.to_local(dove) if padre != null else dove
		padre.add_child(inst)
		## Non compare dal nulla: affiora, col vortice acceso finche' non e'
		## opaco (come i rinforzi della Traccia).
		Comparsa.avvia(inst)
		_spawnati.append(inst)
