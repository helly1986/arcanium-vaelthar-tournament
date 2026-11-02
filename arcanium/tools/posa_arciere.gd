extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## LA POSA DI RIPOSO DELL'ARCIERE, costruita con l'IK sul corpo del campione
## ═══════════════════════════════════════════════════════════════════════════
##
## Per il banco delle impugnature degli archi (Ilwen, e chiunque prenda un arco:
## l'equipaggiamento e' intercambiabile). L'utente, 2026-11-02: la corda sta
## verso l'INTERNO, e il braccio un po' piu' largo, cosi' il filo passa sotto
## l'ascella invece di attraversare fianco e busto.
##
## La presa dell'arco nella mano (presa_arma della scheda) non si tocca: si
## decide dove sta l'ARCO nel mondo (flettenti quasi verticali, corda verso il
## corpo e un poco indietro) e la mano lo segue: polso dove serve, braccio con
## l'IK a due ossa di guardia_due_mani.gd, il resto nella Posa.
##
## L'Arco di Spirito ha 27 cm fra impugnatura e corda: per un metro di corda
## lungo il fianco la finestra e' stretta, fuori dall'anca (larga, coi
## pannelli) e dentro il braccio. Cercati su Ilwen con la pelle deformata
## nella posa, su una griglia di angoli: il braccio a 50 gradi, l'arco dritto
## e la corda girata di 12 gradi in AVANTI tengono la corda a 7 mm dal corpo
## su tutta la lunghezza, ed entra nell'ascella. Le quote si misurano sul
## corpo (spalla, braccio), cosi' vale per ogni campione. Si lavora nello
## spazio dello scheletro, nomi Humanoid, corpo rivolto verso +Z.

const Guardia := preload("res://arcanium/tools/guardia_due_mani.gd")

## Gradi dalla verticale della linea spalla -> impugnatura, verso l'esterno.
const ANGOLO := 50.0
## La linea spalla -> impugnatura e' lunga RAGGIUNGE del braccio disteso.
const RAGGIUNGE := 0.93
## Gradi di cui la punta alta dell'arco piega verso il corpo.
const PENDENZA := 0.0
## Gradi di cui la corda, verso il corpo, gira all'indietro (negativo: in avanti).
const CORDA_INDIETRO := -12.0


## Porta il braccio destro nella posa dell'arciere. `mano_arco` e' l'arco
## (il modello: Y lungo i flettenti, X verso la corda, origine sull'impugnatura)
## nello spazio dell'osso RightHand: perno · presa_arma · held_transform.
## Lo scheletro parte dalla posa che ha (la Posa); ritorna le pose globali.
static func applica(sk : Skeleton3D, mano_arco : Transform3D, angolo := ANGOLO, pendenza := PENDENZA,
		indietro := CORDA_INDIETRO) -> Dictionary:
	var glob := globali(sk)
	var i_br := sk.find_bone("RightUpperArm")
	var i_av := sk.find_bone("RightLowerArm")
	var i_ma := sk.find_bone("RightHand")
	var spalla : Vector3 = (glob[i_br] as Transform3D).origin
	var esterno := signf(spalla.x - (glob[sk.find_bone("LeftUpperArm")] as Transform3D).origin.x)
	var l1 := sk.get_bone_global_rest(i_br).origin.distance_to(sk.get_bone_global_rest(i_av).origin)
	var l2 := sk.get_bone_global_rest(i_av).origin.distance_to(sk.get_bone_global_rest(i_ma).origin)
	## L'arco nel mondo: flettenti (Y) quasi verticali con la punta verso il
	## corpo, corda (X) verso il corpo e un poco indietro.
	var dentro := Vector3(-esterno, 0.0, 0.0)
	var p := deg_to_rad(pendenza)
	var y := (Vector3.UP * cos(p) + dentro * sin(p)).normalized()
	var c := deg_to_rad(indietro)
	var x := dentro * cos(c) + Vector3.BACK * -sin(c)
	x = (x - y * x.dot(y)).normalized()
	var base := Basis(x, y, x.cross(y))
	## L'impugnatura lungo la linea dalla spalla, accorciata finche' il polso
	## che ne viene sta nel braccio.
	var a := deg_to_rad(angolo)
	var verso := Vector3(esterno * sin(a), -cos(a), 0.0)
	var arco := Transform3D(base, spalla + verso * (l1 + l2) * RAGGIUNGE)
	var mano := arco * mano_arco.affine_inverse()
	for k in 20:
		if mano.origin.distance_to(spalla) <= (l1 + l2) * 0.98:
			break
		arco.origin -= verso * 0.01
		mano = arco * mano_arco.affine_inverse()
	## Il gomito indietro e un poco in fuori, come a braccia lungo i fianchi.
	var polso := Guardia._due_ossa(sk, glob, i_br, i_av, i_ma, mano.origin, Vector3(esterno * 0.3, 0.0, -1.0).normalized())
	Guardia._imposta(sk, glob, i_ma, Transform3D(mano.basis, polso))
	return glob


## Le pose globali composte dalle locali: fuori dall'editor
## get_bone_global_pose puo' restituire una posa vecchia.
static func globali(sk : Skeleton3D) -> Dictionary:
	var glob := {}
	for i in sk.get_bone_count():
		var l := Transform3D(Basis(sk.get_bone_pose_rotation(i)).scaled(sk.get_bone_pose_scale(i)),
				sk.get_bone_pose_position(i))
		var par := sk.get_bone_parent(i)
		glob[i] = l if par < 0 else (glob[par] as Transform3D) * l
	return glob
