extends Node3D
class_name EnemyHealthBar

## Barretta di vita flottante sopra un nemico COMUNE.
##
## Compare quando il nemico incassa un colpo e si dissolve da sola dopo qualche
## secondo di calma. I mini-boss e i boss non la usano: hanno la loro barra a
## fondo schermo, e due indicatori sullo stesso avversario si contraddicono a
## vicenda.
##
## Costruita con due quad billboard invece che con una UI proiettata dal mondo
## allo schermo: con quattro Consumati e un branco di lupi in campo, un Control
## per nemico da riposizionare a ogni frame costa molto più di due MeshInstance
## che il rendering orienta da solo. Il rovescio è che la barretta vive nello
## spazio 3D e quindi rimpicciolisce con la distanza — che per una barra di un
## nemico comune è esattamente il comportamento voluto.

const LARGHEZZA := 0.62
const ALTEZZA := 0.075
## Quanto resta visibile dopo l'ultimo colpo incassato.
const PERMANENZA := 4.0
const DISSOLVENZA := 0.5

const COL_FONDO := Color(0.06, 0.05, 0.07, 0.85)
const COL_VITA := Color(0.72, 0.16, 0.16)
## Il "chip": la coda chiara che insegue il valore vero e rende leggibile
## QUANTO hai tolto con l'ultimo colpo, non solo quanto resta.
const COL_CHIP := Color(0.92, 0.72, 0.35, 0.9)
const VEL_CHIP := 0.55

var _fondo : MeshInstance3D
var _chip : MeshInstance3D
var _vita : MeshInstance3D
var _ratio : float = 1.0
var _ratio_chip : float = 1.0
var _nascondi_a : float = 0.0
var _tween : Tween


func _ready() -> void:
	_fondo = _quad(COL_FONDO, LARGHEZZA, ALTEZZA, 0)
	_chip = _quad(COL_CHIP, LARGHEZZA, ALTEZZA * 0.8, 1)
	_vita = _quad(COL_VITA, LARGHEZZA, ALTEZZA * 0.8, 2)
	modulate_alpha(0.0)


## ═══════════════════════════════════════════════════════════════════════════
## ⚠️⚠️ IL BILLBOARD BUTTA VIA LA SCALA DEL NODO
## ═══════════════════════════════════════════════════════════════════════════
## `billboard_mode` riscrive la matrice del modello con quella della camera:
## l'origine resta, la BASE no. Quindi `mi.scale.x = 0.5` non fa niente —
## `billboard_keep_scale` e' `false` di default — e `mi.position.x` si applica
## sì, ma **in coordinate di mondo**, non nel piano dello schermo.
##
## Era il guasto della barretta, e produceva esattamente due difetti insieme:
##  • la parte rossa NON si accorciava mai (a meta' vita occupava ancora tre
##    quarti della barra);
##  • quel poco che si vedeva era la barra INTERA traslata di lato, e la
##    traslazione andava lungo l'asse X del mondo — quindi girando attorno al
##    nemico lo scorrimento diventava uno spostamento in profondita'.
##
## Provato a schermo: accendendo `billboard_keep_scale` la barra si dimezzava
## di colpo. Ma non e' quella la cura, perche' lascerebbe comunque la
## traslazione in coordinate di mondo. La cura e' non usare affatto la
## trasformazione del nodo: si cambia la MESH (`QuadMesh.size` e
## `center_offset`), che vive nello spazio del modello e quindi viene ruotata
## dal billboard insieme al quad. Il risultato e' giusto da qualunque angolo.
##
## Un quad billboard non illuminato. `priority` tiene l'ordine di disegno tra i
## tre strati sovrapposti, che essendo complanari altrimenti farebbero z-fighting.
func _quad(colore : Color, w : float, h : float, priority : int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = colore
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = priority
	# Senza questo i tre quad, essendo esattamente complanari, sfarfallano.
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	add_child(mi)
	return mi


func modulate_alpha(a : float) -> void:
	for mi in [_fondo, _chip, _vita]:
		if mi and mi.material_override:
			var c : Color = mi.material_override.albedo_color
			c.a = a * (COL_FONDO.a if mi == _fondo else 1.0)
			mi.material_override.albedo_color = c
	visible = a > 0.01


## Aggiorna il valore e (ri)accende la barretta.
func set_ratio(r : float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	_nascondi_a = Time.get_ticks_msec() / 1000.0 + PERMANENZA
	if _tween and _tween.is_valid():
		_tween.kill()
	modulate_alpha(1.0)
	_applica()


func _process(delta : float) -> void:
	if not visible:
		return
	# Il chip scende verso il valore vero con un ritardo: e' la lettura del
	# danno appena subito.
	if _ratio_chip > _ratio:
		_ratio_chip = maxf(_ratio, _ratio_chip - VEL_CHIP * delta)
		_applica()
	elif _ratio_chip < _ratio:
		_ratio_chip = _ratio          # cura: nessuna coda, si allinea subito
		_applica()

	if _nascondi_a > 0.0 and Time.get_ticks_msec() / 1000.0 >= _nascondi_a:
		_nascondi_a = 0.0
		_tween = create_tween()
		_tween.tween_method(modulate_alpha, 1.0, 0.0, DISSOLVENZA)


## Le barre si accorciano da SINISTRA: il quad si stringe e il suo centro si
## sposta di meta' della parte tolta, o si accorcerebbe simmetricamente verso il
## centro.
func _applica() -> void:
	_scala(_vita, _ratio)
	_scala(_chip, _ratio_chip)


## ⚠️ Si tocca la MESH e non il nodo: vedi il cappello di `_quad`. La
## trasformazione del nodo, sotto un materiale billboard, viene in gran parte
## buttata via — la scala del tutto, e la traslazione finisce nello spazio del
## mondo invece che nel piano dello schermo.
##
## ⚠️ E NON si separano gli strati con un offset in Z. C'era, e aveva lo stesso
## difetto: `0.001 * indice` in coordinate di mondo, quindi guardando il nemico
## da est o da ovest la parte rossa finiva DIETRO il fondo invece che sopra.
## L'ordine lo tiene `render_priority`, che e' fatto per questo e non ha un
## verso nel mondo (e la scrittura di profondita' e' comunque spenta).
func _scala(mi : MeshInstance3D, r : float) -> void:
	if mi == null or not (mi.mesh is QuadMesh):
		return
	var qm : QuadMesh = mi.mesh
	var w : float = LARGHEZZA * clampf(r, 0.0, 1.0)
	qm.size = Vector2(maxf(w, 0.0001), qm.size.y)
	qm.center_offset = Vector3(-(LARGHEZZA - w) * 0.5, 0.0, 0.0)
