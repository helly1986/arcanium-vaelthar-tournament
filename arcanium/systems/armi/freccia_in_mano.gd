extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## FRECCIA IN MANO — la freccia che si estrae, si porta all'arco e si incocca
## ═══════════════════════════════════════════════════════════════════════════
##
## Il proiettile nasce al rilascio (`freccia.gd`); fino a quel momento la
## freccia che si VEDE e' questa: un modello senza fisica, che vive tre fasi.
##
##   • IN MANO: dall'ESTRAZIONE (la mano che tira l'ha presa dalla faretra)
##     segue quella mano con una presa fissa, `presa`, come una spada
##     nell'impugnatura. La presa NON si tara a occhio: si calcola all'istante
##     dell'incocco, dalla posa che la freccia avra' incoccata in quello stesso
##     istante — cosi' il passaggio alla fase dopo non fa nessuno scatto
##     (`misura_presa_arco.tscn` la stampa).
##   • INCOCCATA: dall'INCOCCO al rilascio la cocca sta sull'incocco della
##     corda (`corda_arco.gd`, che segue la mano) e l'asta punta al POGGIO
##     dell'arco — il punto sopra l'impugnatura dove la freccia appoggia,
##     all'altezza dell'incocco a riposo. Tirando, la cocca arretra con la
##     corda e l'asta scorre sul poggio: e' la freccia che si carica.
##   • al RILASCIO sparisce: da li' vola il proiettile.
##
## Il modello e' quello del proiettile (`freccia_spirito.tscn` porta
## `modello`, il GLB passato da prepara_frecce.py: punta a -Z, cocca a +Z,
## asta sull'origine): lo si legge dalla scena impacchettata senza istanziarla,
## con `modello_di()`, cosi' la freccia in mano e' sempre la stessa che poi
## vola. `top_level`: la posizione la scrive questo nodo, non il genitore.

const Freccia := preload("res://arcanium/systems/enemies/freccia.gd")

enum Fase { NASCOSTA, IN_MANO, INCOCCATA }

## Lunghezza dell'asta: la cocca sta a +lunghezza/2 dall'origine del modello.
## Il numero e' quello del proiettile (`freccia.gd`), cosi' resta uno solo.
@export var lunghezza : float = Freccia.LUNGHEZZA

var _fase : int = Fase.NASCOSTA
var _mano : Node3D = null
var _presa : Transform3D = Transform3D.IDENTITY
var _corda : Node = null
var _modello : Node3D = null
var _scena_modello : PackedScene = null


func _ready() -> void:
	top_level = true
	visible = false


## Il GLB della freccia dichiarato da una scena di proiettile (`modello`),
## letto dallo stato impacchettato: niente istanza, niente script che parte.
static func modello_di(proiettile : PackedScene) -> PackedScene:
	if proiettile == null:
		return null
	var st := proiettile.get_state()
	if st.get_node_count() == 0:
		return null
	for i in st.get_node_property_count(0):
		if str(st.get_node_property_name(0, i)) == "modello":
			return st.get_node_property_value(0, i) as PackedScene
	return null


## Monta (o cambia) il modello. Con `null` resta la freccia di prima, se c'e'.
func monta(scena : PackedScene) -> void:
	if scena == null or scena == _scena_modello:
		return
	if _modello != null:
		_modello.queue_free()
	_scena_modello = scena
	_modello = scena.instantiate() as Node3D
	if _modello != null:
		_modello.name = "Modello"
		add_child(_modello)


## L'estrazione: da adesso la freccia segue `mano` con la presa data.
func estrai(mano : Node3D, presa : Transform3D) -> void:
	if _modello == null or mano == null:
		return
	_mano = mano
	_presa = presa
	_fase = Fase.IN_MANO
	visible = true
	_segui()


## L'incocco: da adesso la cocca sta sulla corda.
func incocca(corda : Node) -> void:
	if _modello == null or corda == null or not corda.has_method("incocco_attuale"):
		return
	_corda = corda
	_fase = Fase.INCOCCATA
	visible = true
	_segui()


## Il rilascio (o un tiro interrotto): sparisce.
func rilascia() -> void:
	_fase = Fase.NASCOSTA
	_mano = null
	_corda = null
	visible = false


func fase() -> int:
	return _fase


func _process(_delta : float) -> void:
	_segui()


func _segui() -> void:
	match _fase:
		Fase.IN_MANO:
			if is_instance_valid(_mano):
				global_transform = _mano.global_transform * _presa
		Fase.INCOCCATA:
			if is_instance_valid(_corda):
				global_transform = posa_incoccata(_corda, lunghezza)


## Dove sta una freccia incoccata su questa corda, adesso: cocca sull'incocco
## attuale, asta verso il poggio dell'arco. Statica perche' la stessa posa
## serve a chi calcola la presa in mano (misura_presa_arco.tscn).
static func posa_incoccata(corda : Node3D, lung : float) -> Transform3D:
	return posa_da(corda.global_transform, corda.get_node("Incocco").position, corda.incocco_attuale(), lung)


## La stessa posa da numeri puri: la trasformazione della corda, l'incocco a
## riposo e quello attuale (entrambi nel riferimento della corda). E' cio' che
## usa il tool in headless, dove i BoneAttachment non si muovono.
static func posa_da(t_corda : Transform3D, riposo : Vector3, incocco : Vector3, lung : float) -> Transform3D:
	var cocca : Vector3 = t_corda * incocco
	var poggio : Vector3 = t_corda * Vector3(0.0, riposo.y, riposo.z)
	var verso : Vector3 = (poggio - cocca).normalized()
	var su : Vector3 = t_corda.basis.y.normalized()
	if absf(verso.dot(su)) > 0.99:
		su = t_corda.basis.z.normalized()
	return Transform3D(Basis.looking_at(verso, su), cocca + verso * lung * 0.5)
