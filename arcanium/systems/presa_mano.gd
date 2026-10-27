@tool
extends SkeletonModifier3D

## ═══════════════════════════════════════════════════════════════════════════
## PRESA DELLA MANO — le dita chiuse sull'impugnatura, sopra ogni clip
## ═══════════════════════════════════════════════════════════════════════════
##
## Le clip del moveset sono del protagonista: sulla mano di un campione le
## dita restano aperte attorno all'impugnatura (Edran, 2026-10-23: «la mano è
## troppo aperta rispetto all'impugnatura»). Questo modificatore, figlio dello
## scheletro, piega ogni falange verso il palmo DOPO l'animazione, finche'
## l'oggetto in quella mano si vede. Lo crea CorpoCampione, con la chiusura
## della scheda del campione (CampioneResource.chiusura_mano_*).
##
## L'asse di ogni piega si ricava dal riposo, non da una tabella: il palmo e'
## il piano fra l'indice e le altre dita, e la falange ruota attorno a
## direzione_del_dito x normale_del_palmo, cioe' la punta va verso il palmo.
##
## @tool perche' gira anche nei banchi delle impugnature
## (banco_impugnatura.gd lo mette sullo scheletro): la presa si sistema con la
## mano chiusa come in gioco, non aperta (Kessra, 2026-10-27).

## "Right" o "Left": i nomi del profilo Humanoid (bone map all'import).
@export var lato := "Right"
## 0 = la mano della clip, 1 = gli angoli pieni sotto.
@export var chiusura := 1.0
## L'oggetto tenuto: la presa vale solo mentre si vede (spada in mano, non
## nel fodero). Vuoto = sempre.
var oggetto : Node3D = null

## Gradi di piega a chiusura 1, per falange (dalla base alla punta). Le due
## in punta pesano di piu': con 40-55-35 le punte restavano fuori sotto il
## manico, come moncherini aperti (Edran, 2026-10-23).
const PIEGA_DITA := [45.0, 65.0, 70.0]
const PIEGA_POLLICE := [0.0, 25.0, 25.0]
const DITA := ["Index", "Middle", "Ring", "Little"]
const FALANGI := ["Proximal", "Intermediate", "Distal"]
const POLLICE := ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]

## [indice osso, asse locale, gradi]
var _pieghe : Array = []


func _ready() -> void:
	prepara()


## Le pieghe dal riposo dello scheletro: va richiamata se le ossa cambiano.
func prepara() -> void:
	_pieghe.clear()
	var sk := get_skeleton()
	if sk == null:
		return
	var mano := sk.find_bone(lato + "Hand")
	var indice := sk.find_bone(lato + "IndexProximal")
	var medio := sk.find_bone(lato + "MiddleProximal")
	if mano < 0 or indice < 0 or medio < 0:
		return
	var o := sk.get_bone_global_rest(mano).origin
	var a := sk.get_bone_global_rest(indice).origin - o
	var b := sk.get_bone_global_rest(medio).origin - o
	## Per la destra indice x medio guarda nel palmo; la sinistra e' specchiata.
	var palmo := (a.cross(b) if lato == "Right" else b.cross(a)).normalized()
	for dito in DITA:
		for k in FALANGI.size():
			_aggiungi(sk, sk.find_bone(lato + dito + FALANGI[k]), palmo, PIEGA_DITA[k])
	## Il pollice si chiude verso l'indice.
	var verso_indice := palmo
	for k in POLLICE.size():
		var i := sk.find_bone(lato + POLLICE[k])
		if i >= 0:
			verso_indice = (sk.get_bone_global_rest(indice).origin - sk.get_bone_global_rest(i).origin).normalized()
			_aggiungi(sk, i, verso_indice, PIEGA_POLLICE[k])


func _aggiungi(sk : Skeleton3D, osso : int, verso : Vector3, gradi : float) -> void:
	if osso < 0 or gradi == 0.0 or sk.get_bone_children(osso).is_empty():
		return
	var g := sk.get_bone_global_rest(osso)
	var dito := (sk.get_bone_global_rest(sk.get_bone_children(osso)[0]).origin - g.origin).normalized()
	var asse := dito.cross(verso)
	if asse.length() < 1e-4:
		return
	## Nello spazio dell'osso: la piega segue la falange in qualunque posa.
	_pieghe.append([osso, (g.basis.inverse() * asse).normalized(), deg_to_rad(gradi)])


func _process_modification() -> void:
	if chiusura <= 0.0 or (oggetto != null and not oggetto.is_visible_in_tree()):
		return
	var quanto := chiusura * _chiusura_arma()
	var sk := get_skeleton()
	for p in _pieghe:
		var q := sk.get_bone_pose_rotation(p[0])
		sk.set_bone_pose_rotation(p[0], q * Quaternion(p[1], p[2] * quanto))


## Il manico dell'arma in mano decide quanto si chiude il pugno
## (ArcaniumEquipmentResource.chiusura_mano): l'arma cambia durante la run, e
## held_weapon.gd ne mette la scheda sull'oggetto.
func _chiusura_arma() -> float:
	if oggetto == null or not "equipment_info" in oggetto:
		return 1.0
	var info = oggetto.equipment_info
	return info.chiusura_mano if info != null and "chiusura_mano" in info else 1.0
