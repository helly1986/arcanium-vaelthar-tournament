extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## LA PRESA DI UN'ARMA PORTATA DA UNO SCHELETRO A UN ALTRO
## ═══════════════════════════════════════════════════════════════════════════
##
## Le prese delle schede (CampioneResource.presa_arma / presa_scudo) sono nello
## spazio dell'osso della mano, e l'osso della mano del Nephilite non e'
## orientato come quello di ARP: passati i campioni sullo scheletro ARP
## (2026-11-02), le armi stavano storte e lo scudo di Edran galleggiava.
##
## La mesh della mano pero' e' la stessa. Qui la presa si tiene ferma rispetto
## alla MANO ANATOMICA: origine sulle nocche di indice e medio, asse delle dita
## dal polso alle nocche, palmo dalla parte del pollice. Il Nephilite ha una
## sola catena per medio, anulare e mignolo (mappata sul medio) e nessun
## mignolo: si usano solo indice, medio e pollice, che hanno tutti e due.
## E' un punto di partenza per il banco, non la presa finita.
##
## presa_nuova = perno⁻¹ · H_a⁻¹ · A_a · A_n⁻¹ · H_n · perno · presa
## (H = posa a riposo dell'osso della mano, A = mano anatomica, entrambe nello
## spazio del proprio scheletro).


## Il centro del palmo nella mano anatomica: dietro le nocche, verso il mignolo,
## dalla parte delle dita chiuse (la Z della sinistra guarda fuori dal palmo).
const PALMO := Vector3(0.01, -0.012, 0.025)


static func converti(presa : Transform3D, perno : Transform3D, sk_da : Skeleton3D, sk_a : Skeleton3D,
		lato : String) -> Transform3D:
	var da := _anatomica(sk_da, lato)
	var a := _anatomica(sk_a, lato)
	var h_da := sk_da.get_bone_global_rest(sk_da.find_bone(lato + "Hand"))
	var h_a := sk_a.get_bone_global_rest(sk_a.find_bone(lato + "Hand"))
	return perno.affine_inverse() * h_a.affine_inverse() * a * da.affine_inverse() * h_da * perno * presa


## La presa di un pezzo a disco (scudo, sigillo) con il suo `punto` sul palmo:
## la faccia resta dove la mette `presa`, e il disco gira sul suo asse finche' la
## sua Y sta di traverso nel palmo, verso il pollice. Per lo scudo il punto e' il
## centro della maniglia, che cosi' sta sotto le dita chiuse (2026-11-07).
static func sul_palmo(presa : Transform3D, perno : Transform3D, sk : Skeleton3D, lato : String,
		punto : Vector3) -> Transform3D:
	var a := _anatomica(sk, lato)
	var padre := sk.get_bone_global_rest(sk.find_bone(lato + "Hand")) * perno
	var z := (padre * presa).basis.z.normalized()
	var y := (a.basis.y - z * a.basis.y.dot(z)).normalized()
	var b := Basis(y.cross(z), y, z)
	var palmo := a * PALMO
	return padre.affine_inverse() * Transform3D(b, palmo - b * punto)


## Lo scheletro di un GLB, istanziato fuori dall'albero (bastano i riposi).
## Si libera con `libera`.
static func scheletro(glb : String) -> Skeleton3D:
	var c : Node = (load(glb) as PackedScene).instantiate()
	return c.find_children("*", "Skeleton3D", true, false)[0]


static func libera(sk : Skeleton3D) -> void:
	(sk.owner if sk.owner != null else sk).free()


static func _anatomica(sk : Skeleton3D, lato : String) -> Transform3D:
	var o := func(n : String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(lato + n)).origin
	var polso : Vector3 = o.call("Hand")
	var nocche : Vector3 = (o.call("IndexProximal") + o.call("MiddleProximal")) * 0.5
	var dita := (nocche - polso).normalized()
	var pollice : Vector3 = o.call("ThumbMetacarpal") - polso
	var palmo := (pollice - dita * pollice.dot(dita)).normalized()
	return Transform3D(Basis(dita, palmo, dita.cross(palmo)), nocche)
