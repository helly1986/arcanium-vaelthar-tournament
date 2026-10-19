extends Node3D

## ⚠️ Niente `class_name`: chi lo usa fa `preload` (vedi `fazioni.gd`).

## ═══════════════════════════════════════════════════════════════════════════
## CORPO DI SPIRITO — come si muove una creatura senza ossa
## ═══════════════════════════════════════════════════════════════════════════
##
## Gli spiriti di Sylvorn (RIG-B nel CREATURES_FRAMEWORK: niente gambe,
## fluttuano) sono mesh intere, senza scheletro: l'Eco Radicata e' 15.467
## triangoli e nessun osso. Il movimento non e' in una clip: e' qui.
##
##   • GALLEGGIA: su e giu' lento, a mezz'aria sopra il suolo;
##   • nel moto si INCLINA in avanti e il fondo — lembi e coda di radice —
##     RESTA INDIETRO (shader, `vento`), piu' quanto piu' va veloce;
##   • a riposo i lembi ONDEGGIANO e la coda si attorciglia (shader).
##
## Le MOSSE sono clip di un AnimationPlayer figlio che animano le proprieta'
## qui sotto (`affondo`, `inchino`, `immersione`, `strappo`, `bagliore`,
## `dissolvi`): cosi' uno spirito usa lo stesso sistema delle mosse di un
## umanoide — telegraph, contatti dal playhead, cooldown — con clip fatte di
## numeri invece che di ossa. Vedi `eco_clip.gd`.
##
## Struttura: questo nodo (la radice del modello, quello che il nemico chiama
## `model`) → `Posa` (ricomposta a ogni frame) → il GLB. Il GLB si porta
## all'altezza voluta; tutto il resto e' in metri.

const SHADER := preload("res://arcanium/systems/spiriti/corpo_spirito.gdshader")

## Il modello da istanziare (GLB), e quanto dev'essere alto in metri.
@export var modello : PackedScene
@export var altezza : float = 1.15
## Quota del fondo del modello sopra l'origine del nodo (a mezz'aria).
@export var sospensione : float = 0.35

@export_group("Casata")
## Il bordo luminoso: verde di Sylvorn per chi e' evocato, viola d'Arcanium
## grezzo per chi e' Consumato.
@export var colore_bordo : Color = Color(0.35, 0.72, 0.55)
@export var bordo_forza : float = 0.5

@export_group("Galleggiamento")
@export var bob_ampiezza : float = 0.07
@export var bob_periodo : float = 2.4
## Inclinazione in avanti a piena velocita' (gradi), e la velocita' "piena".
@export var inclinazione_max : float = 16.0
@export var velocita_piena : float = 3.5
## Quanto il fondo resta indietro a piena velocita' (frazione dell'altezza).
@export var scia_fondo : float = 0.22

@export_group("Posa (la animano le clip)")
## Spinta in avanti (m), inchino (gradi, + in avanti), immersione (m, giu').
@export var affondo : float = 0.0
@export var inchino : float = 0.0
@export var immersione : float = 0.0
## Lembi allargati (0-1), bagliore nel cappuccio (0-1), dissoluzione (0-1),
## ampiezza dell'ondeggio (1 = a riposo).
@export var strappo : float = 0.0
@export var bagliore : float = 0.0
@export var dissolvi : float = 0.0
@export var ondeggio : float = 1.0

var _posa : Node3D
var _materiali : Array[ShaderMaterial] = []
var _t : float = 0.0
var _scala : float = 1.0
var _vento := Vector3.ZERO
var _piega := 0.0
var _seme := 0.0


func _ready() -> void:
	_seme = randf() * TAU
	_t = randf() * 10.0
	_posa = Node3D.new()
	_posa.name = "Posa"
	add_child(_posa)
	if modello != null:
		monta(modello.instantiate() as Node3D)


## Monta un modello qualunque (un GLB istanziato) come corpo dello spirito.
func monta(inst : Node3D) -> void:
	if inst == null:
		return
	for c in _posa.get_children():
		c.queue_free()
	_materiali.clear()
	_posa.add_child(inst)
	## Ingombro in spazio del GLB, per portarlo all'altezza e alla quota.
	var box := AABB()
	var primo := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b : AABB = (inst.global_transform.affine_inverse() * m.global_transform) * m.mesh.get_aabb()
		box = b if primo else box.merge(b)
		primo = false
	_scala = altezza / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * _scala
	inst.position = Vector3(-box.get_center().x * _scala, sospensione - box.position.y * _scala, -box.get_center().z * _scala)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab := m.mesh.get_aabb()
		for i in m.mesh.get_surface_count():
			var sm := _materiale_spirito(m.mesh.surface_get_material(i), ab)
			m.set_surface_override_material(i, sm)
			_materiali.append(sm)


func _materiale_spirito(orig : Material, ab : AABB) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	if orig is BaseMaterial3D:
		var b := orig as BaseMaterial3D
		sm.set_shader_parameter("albedo_tex", b.albedo_texture)
		if b.normal_texture != null:
			sm.set_shader_parameter("normal_tex", b.normal_texture)
			sm.set_shader_parameter("ha_normal", true)
		if b.roughness_texture != null:
			sm.set_shader_parameter("orm_tex", b.roughness_texture)
			sm.set_shader_parameter("ha_orm", true)
		sm.set_shader_parameter("roughness_base", b.roughness)
	sm.set_shader_parameter("quota_cima", ab.end.y)
	sm.set_shader_parameter("quota_fondo", ab.position.y)
	sm.set_shader_parameter("raggio", maxf(ab.size.x, ab.size.z) * 0.5)
	sm.set_shader_parameter("seme", _seme)
	sm.set_shader_parameter("rumore_tex", _rumore())
	return sm


static var _rumore_cache : NoiseTexture2D


static func _rumore() -> NoiseTexture2D:
	if _rumore_cache == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.03
		_rumore_cache = NoiseTexture2D.new()
		_rumore_cache.noise = n
		_rumore_cache.seamless = true
		_rumore_cache.width = 256
		_rumore_cache.height = 256
	return _rumore_cache


func _process(delta : float) -> void:
	_t += delta
	## Il moto del corpo: la velocita' del CharacterBody3D padre, se c'e'.
	var v := Vector3.ZERO
	var corpo := get_parent() as CharacterBody3D
	if corpo != null:
		v = corpo.velocity
		v.y = 0.0
	var locale : Vector3 = global_transform.basis.inverse() * v
	var quanto : float = clampf(locale.length() / maxf(velocita_piena, 0.01), 0.0, 1.0)
	var avanti : float = clampf(locale.z / maxf(velocita_piena, 0.01), -1.0, 1.0)
	## Smorzati, non istantanei: uno spirito non ha inerzia di muscoli ma di stoffa.
	_piega = lerpf(_piega, avanti * inclinazione_max, clampf(delta * 4.0, 0.0, 1.0))
	## Il fondo resta INDIETRO: verso opposto al moto, in spazio modello (che
	## e' scalato: si divide per la scala del GLB).
	var scia : Vector3 = -locale.normalized() * quanto * scia_fondo * altezza / maxf(_scala, 0.0001) if locale.length() > 0.01 else Vector3.ZERO
	_vento = _vento.lerp(scia, clampf(delta * 3.0, 0.0, 1.0))

	var bob : float = sin(_t * TAU / maxf(bob_periodo, 0.1)) * bob_ampiezza
	## L'inchino ruota attorno al CENTRO del corpo, non all'origine (che e' a
	## terra): ruotando dai piedi uno spirito a mezz'aria viene scagliato via.
	var perno := Vector3(0.0, sospensione + altezza * 0.5, 0.0)
	var giro := Basis(Vector3.RIGHT, deg_to_rad(_piega + inchino))
	_posa.transform = Transform3D(giro, perno - giro * perno + Vector3(0.0, bob - immersione, affondo))

	for sm in _materiali:
		sm.set_shader_parameter("vento", _vento)
		sm.set_shader_parameter("strappo", strappo)
		sm.set_shader_parameter("ondeggio", ondeggio * (1.0 + quanto * 0.8))
		sm.set_shader_parameter("colore_bordo", colore_bordo)
		sm.set_shader_parameter("bordo_forza", bordo_forza)
		sm.set_shader_parameter("bagliore", bagliore)
		sm.set_shader_parameter("dissolvi", dissolvi)
