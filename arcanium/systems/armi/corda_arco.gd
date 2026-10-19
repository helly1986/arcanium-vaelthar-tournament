extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## CORDA D'ARCO — punta, mano, punta
## ═══════════════════════════════════════════════════════════════════════════
##
## La corda non sta nella mesh dell'arco: gliel'ha tolta
## `arcanium/tools/prepara_arco_spirito.py`, e la disegna questo nodo. Due
## segmenti: dalla punta alta all'INCOCCO, e dall'incocco alla punta bassa. A
## riposo l'incocco sta sulla corda dritta; quando qualcuno TENDE, l'incocco
## segue la mano che tira e i due segmenti si piegano con lei. E' il motivo per
## cui la corda e' codice e non geometria: una corda modellata resta tesa fra
## le punte mentre la mano tira il vuoto, e si vede.
##
## Le tre posizioni di riposo sono figli `Marker3D` — `PuntaAlta`, `PuntaBassa`,
## `Incocco` — messi dove il tool ha misurato la corda di Tripo prima di
## toglierla (le misure stanno accanto al GLB, in `*_misure.json`). Chi tende
## passa un Node3D a `tendi()`, di solito il BoneAttachment della mano destra;
## `rilascia()` la lascia tornare. Nessuno dei due si aspetta che l'animazione
## sia una trazione vera: l'incocco resta nel PIANO dell'arco e non passa mai
## dalla parte sbagliata dell'impugnatura, cosi' anche un gesto segnaposto
## tira la corda invece di attraversarla.
##
## Sull'Arco di Spirito la corda e' Spirito anche lei: teal, emissiva, e non
## vibra (vedi la lore dell'oggetto). Il colore e' un export perche' un arco di
## legno domani la vorra' di canapa.

## Spessore della corda in metri. Sotto i 5 mm a dieci metri e' sub-pixel e
## sfarfalla: meglio una corda un filo grossa che una che scompare.
@export var spessore : float = 0.006
@export var colore : Color = Color(0.36, 0.98, 0.9)
## Quanto si illumina da sola. Con `colore` teal e' lo Spirito; a 0 e' canapa.
@export var energia : float = 1.8
## Il rombo dell'incocco (quello che Tripo aveva modellato a meta' corda).
@export var incocco_lato : float = 0.014
## Velocita' con cui l'incocco torna a riposo dopo il rilascio (1/s): ~18 e'
## uno scatto, non un teletrasporto. In trazione segue la mano senza ritardo.
@export var ritorno : float = 18.0

@onready var _punta_alta : Marker3D = $PuntaAlta
@onready var _punta_bassa : Marker3D = $PuntaBassa
@onready var _incocco : Marker3D = $Incocco

var _mano : Node3D = null
var _pos_incocco : Vector3 = Vector3.ZERO
var _alto : MeshInstance3D
var _basso : MeshInstance3D
var _rombo : MeshInstance3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colore
	mat.emission_enabled = energia > 0.0
	mat.emission = colore
	mat.emission_energy_multiplier = energia
	mat.roughness = 0.6
	var cil := CylinderMesh.new()
	cil.top_radius = spessore * 0.5
	cil.bottom_radius = spessore * 0.5
	cil.height = 1.0
	cil.radial_segments = 6
	cil.rings = 1
	cil.material = mat
	_alto = _segmento("SegmentoAlto", cil)
	_basso = _segmento("SegmentoBasso", cil)
	var box := BoxMesh.new()
	box.size = Vector3(incocco_lato, incocco_lato, spessore * 1.6)
	box.material = mat
	_rombo = MeshInstance3D.new()
	_rombo.name = "Rombo"
	_rombo.mesh = box
	_rombo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rombo)
	_pos_incocco = _incocco.position
	_disegna()


func _segmento(nome : String, mesh : Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nome
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## La corda segue questa mano finche' non si rilascia.
func tendi(mano : Node3D) -> void:
	_mano = mano


func rilascia() -> void:
	_mano = null


func tesa() -> bool:
	return is_instance_valid(_mano)


## Dove sta l'incocco adesso, in coordinate di questo nodo.
func incocco_attuale() -> Vector3:
	return _pos_incocco


func _process(delta : float) -> void:
	var meta := _incocco.position
	if is_instance_valid(_mano):
		meta = _vincola(to_local(_mano.global_position))
		_pos_incocco = meta
	else:
		_pos_incocco = _pos_incocco.lerp(meta, clampf(ritorno * delta, 0.0, 1.0))
	_disegna()


## L'incocco tirato resta nel piano dell'arco (x = lungo la corda, y = lungo i
## flettenti) e dalla parte della corda: la componente fuori piano si butta, e
## verso l'impugnatura non si va mai oltre il riposo.
func _vincola(p : Vector3) -> Vector3:
	var riposo := _incocco.position
	var lato := signf(riposo.x)
	if lato == 0.0:
		lato = 1.0
	p.z = riposo.z
	if p.x * lato < riposo.x * lato:
		p.x = riposo.x
	return p


func _disegna() -> void:
	_stendi(_alto, _punta_alta.position, _pos_incocco)
	_stendi(_basso, _pos_incocco, _punta_bassa.position)
	_rombo.position = _pos_incocco
	## Il rombo e' un cubetto girato di 45 gradi nel piano dell'arco.
	_rombo.basis = Basis(Vector3(0, 0, 1), PI * 0.25)


## Un cilindro alto 1 lungo Y, portato da `a` a `b`: la base si costruisce
## per assi, con Y lungo ab e lungo quanto ab. Niente `Quaternion(UP, dir)`:
## il tratto alto della corda scende quasi parallelo a -Y, e l'arco fra due
## vettori opposti non ha un asse — su quel caso il quaternione fa NaN.
func _stendi(mi : MeshInstance3D, a : Vector3, b : Vector3) -> void:
	var ab := b - a
	var l := ab.length()
	if l < 0.0005:
		mi.visible = false
		return
	mi.visible = true
	mi.position = (a + b) * 0.5
	var y := ab / l
	var ausilio := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ausilio).normalized()
	mi.basis = Basis(x, y * l, x.cross(y))
