extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## LA GUARDIA A DUE MANI, costruita con l'IK sul corpo del campione
## ═══════════════════════════════════════════════════════════════════════════
##
## Per il banco delle impugnature delle armi a due mani (Zarine, Aurin): la
## guardia del moveset portata col retarget metteva l'asta in diagonale, con la
## sinistra lontana, e la presa non si giudicava (l'utente, 2026-11-01). Questa
## e' la guardia chiesta: l'asta VERTICALE sul fianco destro, pronta all'uso;
## la destra sopra, all'altezza del petto, a dare forza; la sinistra sotto,
## col braccio che passa appena sotto il petto. Pollici in su, pugni centrati
## sull'asta (le dita le chiude presa_mano.gd).
##
## Le quote si misurano sul corpo (spalle, petto), cosi' vale per ogni campione.
## Si lavora nello spazio dello scheletro, nomi Humanoid. In Cascadeur la
## stessa guardia si fa legando le due mani all'arma: questa serve al banco.
##
## `asta()` ritorna l'asse dell'asta (punto alto, punto basso): il banco lo
## mostra per controllare la presa.

## Distanze in metri. L'asta sta davanti al petto di DAVANTI, sulla linea
## della spalla destra; le mani distano FRA_LE_MANI. La sinistra sta il piu'
## in basso che il suo braccio arriva comodo (RAGGIUNGE della lunghezza piena):
## attraversa il corpo, e con le braccia corte (Zarine, 0,44 m) piu' in basso
## restava a mezz'aria. La destra le sta sopra, all'altezza del petto.
const DAVANTI := 0.27
const FRA_LE_MANI := 0.24
const RAGGIUNGE := 0.92
## Il centro del pugno davanti al palmo: dove passa il manico.
const PUGNO := 0.025


static func asta(sk : Skeleton3D) -> Array:
	var sd := _o(sk, "RightUpperArm")
	var ss := _o(sk, "LeftUpperArm")
	var petto := _o(sk, "UpperChest") if sk.find_bone("UpperChest") >= 0 else _o(sk, "Chest")
	var x := sd.x
	var z := petto.z + DAVANTI
	var braccio := ss.distance_to(_o(sk, "LeftLowerArm")) + _o(sk, "LeftLowerArm").distance_to(_o(sk, "LeftHand")) 			+ _o(sk, "LeftHand").distance_to(_o(sk, "LeftMiddleProximal"))
	var orizz := Vector2(x - ss.x, z - ss.z).length()
	var r := braccio * RAGGIUNGE
	var y_sinistra := ss.y - sqrt(maxf(r * r - orizz * orizz, 0.0))
	var basso := Vector3(x, y_sinistra, z)
	var alto := basso + Vector3.UP * FRA_LE_MANI
	return [alto, basso]


static func applica(sk : Skeleton3D) -> Dictionary:
	for i in sk.get_bone_count():
		sk.reset_bone_pose(i)
	## Le pose globali si tengono QUI, partendo dal riposo, e allo scheletro si
	## scrivono solo le locali. Fuori dall'editor get_bone_global_pose, riletto
	## subito dopo un set_bone_global_pose, da' ancora la posa di prima (anche
	## quella del GENITORE che set_bone_global_pose usa): sul banco di Aurin
	## (2026-11-02) il secondo braccio e la mano uscivano staccati, una mano
	## sopra la testa e l'altra 25 cm fuori dal polso.
	var glob := {}
	for i in sk.get_bone_count():
		glob[i] = sk.get_bone_global_rest(i)
	var punti := asta(sk)
	var esterno := signf(_o(sk, "RightUpperArm").x - _o(sk, "LeftUpperArm").x)
	## Il gomito destro scende e va un po' fuori e indietro. Il sinistro va in
	## FUORI e in avanti: puntato in basso e indietro, l'omero entrava nel
	## pettorale e nella veste (Zarine sul banco, 2026-11-01); cosi'
	## l'avambraccio attraversa il corpo davanti al petto.
	_mano(sk, glob, "Right", punti[0], Vector3(esterno * 0.6, -1.0, -0.4))
	_mano(sk, glob, "Left", punti[1], Vector3(-esterno * 1.0, -0.3, 0.5))
	return glob


## Porta l'osso `i` alla posa globale `g`: scrive la locale rispetto al
## genitore (dalle globali tenute in `glob`) e aggiorna `glob`.
static func _imposta(sk : Skeleton3D, glob : Dictionary, i : int, g : Transform3D) -> void:
	var p := sk.get_bone_parent(i)
	var locale : Transform3D = g if p < 0 else (glob[p] as Transform3D).affine_inverse() * g
	sk.set_bone_pose_position(i, locale.origin)
	sk.set_bone_pose_rotation(i, locale.basis.get_rotation_quaternion())
	glob[i] = g


static func _o(sk : Skeleton3D, nome : String) -> Vector3:
	return sk.get_bone_global_rest(sk.find_bone(nome)).origin


static func _mano(sk : Skeleton3D, glob : Dictionary, lato : String, presa : Vector3, polo : Vector3) -> void:
	var i_br := sk.find_bone(lato + "UpperArm")
	var i_av := sk.find_bone(lato + "LowerArm")
	var i_ma := sk.find_bone(lato + "Hand")
	if i_br < 0 or i_av < 0 or i_ma < 0:
		return
	## La mano a riposo: l'asse delle nocche (indice -> mignolo), le dita, il
	## palmo (dalla parte del pollice) e il centro del pugno.
	var hr := sk.get_bone_global_rest(i_ma)
	var dito_basso := lato + ("LittleProximal" if sk.find_bone(lato + "LittleProximal") >= 0 else "MiddleProximal")
	var indice := _o(sk, lato + "IndexProximal")
	var basso := _o(sk, dito_basso)
	var medio := _o(sk, lato + "MiddleProximal")
	var nocche := (indice - basso).normalized()
	var dita := (medio - hr.origin)
	dita = (dita - nocche * dita.dot(nocche)).normalized()
	var palmo := nocche.cross(dita).normalized()
	var pollice := _o(sk, lato + "ThumbProximal") if sk.find_bone(lato + "ThumbProximal") >= 0 else medio
	if (pollice - hr.origin).dot(palmo) < 0.0:
		palmo = -palmo
	var centro := (indice + basso) * 0.5 + palmo * PUGNO
	## Dove deve andare: nocche lungo l'asta (indice in alto), dita in
	## orizzontale nella direzione da cui arriva il braccio.
	var spalla := _o(sk, lato + "UpperArm")
	var arriva := presa - spalla
	arriva.y = 0.0
	arriva = arriva.normalized()
	var r := _allinea(nocche, dita, Vector3.UP, arriva)
	var base_mano := r * hr.basis
	var polso := presa - r * (centro - hr.origin)
	var raggiunto := _due_ossa(sk, glob, i_br, i_av, i_ma, polso, polo.normalized())
	_imposta(sk, glob, i_ma, Transform3D(base_mano, raggiunto))


## La rotazione che porta la coppia (a1, a2) sulla coppia (b1, b2): a1 su b1
## esatto, a2 il piu' vicino possibile a b2.
static func _allinea(a1 : Vector3, a2 : Vector3, b1 : Vector3, b2 : Vector3) -> Basis:
	var x1 := a1.normalized()
	var z1 := x1.cross(a2).normalized()
	var y1 := z1.cross(x1)
	var x2 := b1.normalized()
	var z2 := x2.cross(b2).normalized()
	var y2 := z2.cross(x2)
	return Basis(x2, y2, z2) * Basis(x1, y1, z1).inverse()


## IK a due ossa con un POLO: il gomito sta nel piano spalla-bersaglio-polo.
## Le basi nuove si calcolano dalle globali tenute in `glob`, senza rileggere
## le pose dallo scheletro: rilette subito dopo un set_bone_global_pose erano
## ancora quelle di prima, e la sinistra restava 18 cm sopra la presa.
## Ritorna dove arriva il polso.
static func _due_ossa(sk : Skeleton3D, glob : Dictionary, i_a : int, i_b : int, i_c : int, bersaglio : Vector3,
		polo : Vector3) -> Vector3:
	var ta : Transform3D = glob[i_a]
	var tb : Transform3D = glob[i_b]
	var tc : Transform3D = glob[i_c]
	var a := ta.origin
	var b := tb.origin
	var c := tc.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var verso := bersaglio - a
	var d := clampf(verso.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	verso = verso.normalized()
	var fuori := (polo - verso * polo.dot(verso)).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var gomito := a + (verso * cos_a + fuori * sin_a) * l1
	var polso := a + verso * d
	var r1 := _rotazione(b - a, gomito - a)
	var r2 := _rotazione(r1 * (c - b), polso - gomito)
	_imposta(sk, glob, i_a, Transform3D(r1 * ta.basis, a))
	_imposta(sk, glob, i_b, Transform3D(r2 * r1 * tb.basis, gomito))
	_imposta(sk, glob, i_c, Transform3D(r2 * r1 * tc.basis, polso))
	return polso


static func _rotazione(da : Vector3, a : Vector3) -> Basis:
	var u := da.normalized()
	var v := a.normalized()
	var asse := u.cross(v)
	if asse.length() < 0.00001:
		return Basis()
	return Basis(asse.normalized(), acos(clampf(u.dot(v), -1.0, 1.0)))


## La mano sinistra nello spazio della destra nella guardia: va nella scheda
## del campione (CampioneResource.seconda_mano) e la usa seconda_mano.gd.
static func seconda_mano(sk : Skeleton3D) -> Transform3D:
	var glob := applica(sk)
	return (glob[sk.find_bone("RightHand")] as Transform3D).affine_inverse() * glob[sk.find_bone("LeftHand")]
