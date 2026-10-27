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
## il piano fra l'indice e le altre dita, e ogni dito ha UN cardine,
## direzione_polso_nocca x normale_del_palmo, attorno a cui girano tutte le sue
## falangi: la punta va verso il palmo. Non dalla direzione di ogni falange:
## sulle dita gia' piegate a riposo (il guanto di Kessra) le falangi in punta
## guardano quasi dentro il palmo, il prodotto vettoriale cambiava segno e
## quelle falangi si piegavano all'indietro (2026-10-27).
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
## Il pollice si chiude sopra le dita, verso il centro del pugno. Con 0-25-25
## verso la nocca dell'indice si muoveva quasi di lato e restava fuori, girato
## dall'altra parte (Kessra, 2026-10-27: la punta a 9,5 cm dal pugno, ora 4,2).
const PIEGA_POLLICE := [15.0, 35.0, 45.0]
## Il centro del pugno: davanti al palmo, all'altezza della seconda nocca del
## medio, dove sta il manico.
const PUGNO := 0.03
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
		var base := sk.find_bone(lato + dito + FALANGI[0])
		if base < 0:
			continue
		var cardine := (sk.get_bone_global_rest(base).origin - o).normalized().cross(palmo)
		for k in FALANGI.size():
			_aggiungi(sk, sk.find_bone(lato + dito + FALANGI[k]), cardine, PIEGA_DITA[k])
	## Il pollice si chiude verso il centro del pugno, attorno a un cardine
	## solo anche lui: dalla direzione del metacarpo.
	var nocca := sk.find_bone(lato + "MiddleIntermediate")
	var centro := (sk.get_bone_global_rest(nocca).origin if nocca >= 0 else sk.get_bone_global_rest(medio).origin) + palmo * PUGNO
	var meta := sk.find_bone(lato + POLLICE[0])
	var prima := sk.find_bone(lato + POLLICE[1])
	if meta >= 0 and prima >= 0:
		var m0 := sk.get_bone_global_rest(meta).origin
		var cardine := (sk.get_bone_global_rest(prima).origin - m0).normalized().cross((centro - m0).normalized())
		for k in POLLICE.size():
			_aggiungi(sk, sk.find_bone(lato + POLLICE[k]), cardine, PIEGA_POLLICE[k])


## Una piega attorno al `cardine` (nel mondo, al riposo), portato nello spazio
## dell'osso: cosi' segue la falange in qualunque posa.
func _aggiungi(sk : Skeleton3D, osso : int, cardine : Vector3, gradi : float) -> void:
	if osso < 0 or gradi == 0.0 or cardine.length() < 1e-4:
		return
	var g := sk.get_bone_global_rest(osso)
	_pieghe.append([osso, (g.basis.inverse() * cardine).normalized(), deg_to_rad(gradi)])


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
