extends Node
class_name OggettoDistruttibile

## OGGETTO DISTRUTTIBILE — un prop che si rompe in pezzi mossi dalla fisica.
##
## Si aggiunge come FIGLIO del prop da rendere distruttibile:
##
##   var d := OggettoDistruttibile.new()
##   d.salute = 60
##   colonna.add_child(d)
##
## oppure, dai builder, con la comodità che fa tutto:
##
##   OggettoDistruttibile.applica(colonna, {"salute": 60})
##
## ─── LA DIFFERENZA CON LO SCHIANTO A TERRA ───────────────────────────────────
## Sono due sistemi imparentati e volutamente separati.
##   • `SchiantoATerra` è SPETTACOLO: nessuna fisica, archi calcolati, il terreno
##     non cambia. Succede decine di volte per scontro.
##   • Questo è un CAMBIAMENTO DI STATO del livello: la colonna c'era e adesso
##     non c'è più. Succede una volta sola, quindi qui la fisica vera si può
##     pagare — ed è l'unica cosa che rende credibile un crollo, perché i pezzi
##     devono rimbalzare sul pavimento e appoggiarsi l'uno all'altro in modo che
##     nessuna traiettoria scritta a mano saprebbe imitare.
##
## ⚠️ I DETRITI NON FERMANO IL PLAYER (deciso). Stanno su un layer loro e vedono
## solo il mondo: cadono sul pavimento e contro i muri, e il giocatore ci passa
## attraverso. È la scelta giusta anche a prescindere dal gusto — dei RigidBody
## che rotolano possono incastrare qualcuno contro una parete durante uno
## scontro, e una morte per detrito incastrato non è una morte che si accetta.

## Emesso quando l'oggetto si rompe: il livello può reagire (aprire un varco,
## far cadere un ponte, contare gli obiettivi).
signal rotto(chi : Node3D)

# ---------------------------------------------------------------------------
# TARATURA
# ---------------------------------------------------------------------------

## Danno da assorbire prima di rompersi. A 0 si rompe al primo colpo.
@export var salute : float = 50.0

## In quanti pezzi. ⚠️ La camera isometrica NON li conta: da 20 m otto pezzi
## grossi si leggono come "è crollata una colonna" e venticinque si leggono come
## "è comparsa della ghiaia". Più pezzi vuol dire pezzi più piccoli, e i pezzi
## piccoli spariscono (vedi la regola della luminanza in docs/08).
@export_range(3, 16, 1) var pezzi : int = 8

## Quanto restano prima di sparire, e in quanto svaniscono. Stessi tempi
## dell'effetto di schianto: sono la scala su cui l'occhio si è già tarato in
## questo gioco, e due detriti che spariscono con ritmi diversi si notano.
@export var riposo : float = 6.0
@export var sparizione : float = 1.5

## Quanti pezzi NON spariscono mai. 0 = sparisce tutto.
##
## ⚠️ Serve, e non è una rifinitura. Una cassa può evaporare: era un oggetto, se
## n'è andata, nessuno la cerca più. Una COLONNA no — era architettura, teneva su
## qualcosa, e un pezzo d'arena dove prima c'era una colonna e adesso c'è
## pavimento pulito racconta che non c'è mai stata. Le macerie che restano sono
## la prova che quello scontro è successo davvero, e sono anche l'unico modo in
## cui un'arena può portarsi addosso la memoria di come è andata.
##
## I pezzi che restano sono quelli **più in basso**: su una colonna vuol dire il
## moncone e ciò che gli è caduto attorno, cioè esattamente la silhouette di una
## colonna spezzata. Scegliere "i più grossi" avrebbe lasciato in giro un rocchio
## a caso in mezzo alla piazza, che non racconta niente.
@export_range(0, 8, 1) var pezzi_che_restano : int = 3

## Spinta data ai pezzi al momento della rottura, dal centro verso fuori.
@export var spinta : float = 3.2
## Quota di spinta verso l'ALTO. Bassa di proposito: una colonna che crolla
## viene giù, non salta. Alzarla la fa sembrare esplosa dall'interno.
@export var spinta_su : float = 0.35

## Peso di un frammento in kg. Conta per come rimbalza e per quanto in fretta si
## ferma: leggero = plasticoso, pesantissimo = si pianta dove tocca.
@export var massa_pezzo : float = 24.0

## Scossa di camera alla rottura. Un crollo strutturale è forte per definizione.
@export var scossa : float = Scossa.PESANTE

## Se true, alla rottura alza anche polvere e detriti da terra alla base.
@export var polvere_alla_base : bool = true
## Tinta del suolo su cui poggia, per quella polvere.
@export var tinta_suolo : Color = SchiantoATerra.PIETRA_ARENA

# ---------------------------------------------------------------------------
# LAYER DEI DETRITI
# ---------------------------------------------------------------------------

## Layer 6 = "Detriti" (vedi project.godot). I pezzi ci VIVONO sopra...
const LAYER_DETRITI := 1 << 5
## ...e vedono SOLO il mondo (layer 1): pavimento e muri li fermano, il player
## no. ⚠️ E nemmeno gli altri detriti: pezzi che si urtano fra loro sembrano più
## ricchi per il primo mezzo secondo e poi si mettono a vibrare in pila, che a
## camera ferma è molto più visibile di quanto valga.
const MASCHERA_DETRITI := 1

# ---------------------------------------------------------------------------
# STATO
# ---------------------------------------------------------------------------

var _salute_ora : float = 0.0
var _rotto : bool = false


func _ready() -> void:
	_salute_ora = salute
	## Il gruppo è l'unico modo che ha il resto del gioco per trovare questi
	## oggetti senza conoscerli: vedi `colpisci_intorno`.
	add_to_group("distruttibile")


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Aggiunge il componente a `prop` e lo restituisce. `opzioni` sono i nomi delle
## proprietà esportate qui sopra.
static func applica(prop : Node3D, opzioni : Dictionary = {}) -> OggettoDistruttibile:
	var d := OggettoDistruttibile.new()
	d.name = "Distruttibile"
	for k in opzioni:
		d.set(k, opzioni[k])
	prop.add_child(d)
	return d


## Incassa danno. Si rompe quando la salute finisce.
## `origine` è da dove è arrivato il colpo: decide da che parte cascano i pezzi.
func subisci(danno : float, origine : Vector3 = Vector3.INF) -> void:
	if _rotto:
		return
	_salute_ora -= danno
	if _salute_ora <= 0.0:
		rompi(origine)


## Rompe subito, salute o non salute.
func rompi(origine : Vector3 = Vector3.INF) -> void:
	if _rotto:
		return
	_rotto = true
	var prop := get_parent() as Node3D
	if prop == null:
		return
	var radice := get_tree().current_scene
	if radice == null:
		radice = get_tree().root

	var pezzi_creati := 0
	for mi in _mesh_del_prop(prop):
		pezzi_creati += _spezza_una(mi, prop, radice, origine)

	## ⚠️ Il prop originale si nasconde SOLO se qualche pezzo è nato davvero.
	## Se la frattura fallisce (mesh vuota, formato inatteso) e si nascondesse
	## comunque, la colonna sparirebbe nel nulla: un difetto molto peggiore di
	## una colonna che incassa il colpo e resta in piedi.
	if pezzi_creati > 0:
		prop.visible = false
		_spegni_collisione(prop)
	else:
		push_warning("OggettoDistruttibile: nessun frammento da %s, resta intero." % prop.name)
		_rotto = false
		return

	Scossa.nel_mondo(prop.global_position, scossa)
	Suoni.nel_mondo(prop, Suoni.CROLLO_COLONNA)
	if polvere_alla_base:
		## Alla BASE, non al centro: la polvere di un crollo nasce dove la roba
		## picchia per terra. `sotto` trova il pavimento da solo.
		SchiantoATerra.sotto(prop, 1.3, tinta_suolo, false)
	rotto.emit(prop)


## Colpisce tutti i distruttibili entro `raggio` da `punto`. È la porta che usano
## i proiettili, gli schianti e — domani — meteore e palle di cannone.
##
## ⚠️ È un'API a SENSO UNICO, apposta. L'alternativa era che i distruttibili
## sapessero dei proiettili (aree, layer, segnali da collegare per ogni tipo di
## danno nuovo). Così invece chi fa male dice solo "ho fatto male qui, così
## tanto" e non ha idea di cosa ci sia intorno.
static func colpisci_intorno(nel_mondo : Node, punto : Vector3, raggio : float,
		danno : float) -> int:
	if nel_mondo == null or not nel_mondo.is_inside_tree():
		return 0
	var colpiti := 0
	for d in nel_mondo.get_tree().get_nodes_in_group("distruttibile"):
		var comp := d as OggettoDistruttibile
		if comp == null or comp._rotto:
			continue
		var prop := comp.get_parent() as Node3D
		if prop == null:
			continue
		if prop.global_position.distance_to(punto) > raggio:
			continue
		comp.subisci(danno, punto)
		colpiti += 1
	return colpiti


# ---------------------------------------------------------------------------
# INTERNI
# ---------------------------------------------------------------------------

func _mesh_del_prop(prop : Node3D) -> Array:
	var out : Array = []
	if prop is MeshInstance3D:
		out.append(prop)
	for n in prop.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


## Spezza UNA MeshInstance3D e crea i RigidBody3D. Ritorna quanti ne ha fatti.
func _spezza_una(mi : MeshInstance3D, prop : Node3D, radice : Node,
		origine : Vector3) -> int:
	if mi.mesh == null:
		return 0
	## ⚠️ La rotazione e la SCALA del prop si CUOCIONO nella mesh dei frammenti
	## (`t.basis`), non si mettono sul corpo. Un RigidBody3D non tiene la scala:
	## il server di fisica gli riscrive il transform e la azzera. Misurato su
	## questa colonna, scalata ×12 dal builder: i frammenti uscivano da 28 cm,
	## tutti presenti e tutti invisibili. Cotta nella geometria, il corpo può
	## restare a scala 1 — che è l'unico stato che la fisica sa mantenere.
	var t := mi.global_transform
	var frammenti := Frattura.spezza(mi.mesh, pezzi,
			int(prop.get_instance_id()) & 0xFFFF, t.basis)
	if frammenti.is_empty():
		return 0

	var centro_mondo := t * mi.mesh.get_aabb().get_center()
	var da := origine
	if da == Vector3.INF:
		da = centro_mondo - Vector3(0, 1, 0)

	## Quali pezzi restano per sempre: i più BASSI nella mesh originale, cioè il
	## piede della colonna. Si decide QUI, prima di crearli, perché serve
	## l'ordine di tutti quanti — non si può guardarli uno alla volta.
	var per_altezza : Array = frammenti.duplicate()
	per_altezza.sort_custom(func(x, y) -> bool:
		return (x["centro"] as Vector3).y < (y["centro"] as Vector3).y)
	var restano : Dictionary = {}
	for i in mini(pezzi_che_restano, per_altezza.size()):
		restano[per_altezza[i]] = true

	for f in frammenti:
		var corpo := RigidBody3D.new()
		corpo.mass = massa_pezzo
		corpo.collision_layer = LAYER_DETRITI
		corpo.collision_mask = MASCHERA_DETRITI
		## Smorzamento alto: la pietra non rotola per sempre. Senza questo i
		## pezzi scivolano via dal punto del crollo e la scena perde il centro.
		corpo.linear_damp = 0.6
		corpo.angular_damp = 1.2

		var vista := MeshInstance3D.new()
		vista.mesh = f["mesh"]
		corpo.add_child(vista)

		var forma := CollisionShape3D.new()
		var conv := (f["mesh"] as ArrayMesh).create_convex_shape(true, true)
		if conv == null:
			continue
		forma.shape = conv
		corpo.add_child(forma)

		radice.add_child(corpo)
		## Basis IDENTITÀ: orientamento e scala stanno già nei vertici. Al corpo
		## resta solo dove sta.
		corpo.global_transform = Transform3D(Basis(), t * (f["centro"] as Vector3))

		## Spinta: via dal punto d'impatto, con una componente in su piccola.
		var via : Vector3 = corpo.global_position - da
		via.y = 0.0
		if via.length_squared() < 0.01:
			via = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		via = via.normalized()
		corpo.linear_velocity = via * spinta * randf_range(0.6, 1.4) \
				+ Vector3.UP * spinta * spinta_su * randf_range(0.4, 1.6)
		corpo.angular_velocity = Vector3(
			randf_range(-2.5, 2.5), randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))

		if restano.has(f):
			_programma_riposo_definitivo(corpo)
		else:
			_programma_sparizione(corpo)
	return frammenti.size()


## Un pezzo che RESTA. Cade normalmente, poi si congela dove si è fermato.
##
## ⚠️ Il congelamento non è un'ottimizzazione facoltativa: sono macerie
## PERMANENTI, quindi senza di esso ogni colonna abbattuta lascerebbe per sempre
## dei RigidBody attivi nell'arena. Tre colonne e ci si porta dietro una decina
## di corpi che il motore continua a simulare fino alla fine dello scontro, per
## della roba che non si muove più.
##
## Si congela a tempo e non "quando si ferma": un pezzo appoggiato male può
## restare a tremare per sempre sotto la soglia di sleep, e aspettare quel
## momento vuol dire non congelarlo mai.
func _programma_riposo_definitivo(corpo : RigidBody3D) -> void:
	get_tree().create_timer(riposo).timeout.connect(func() -> void:
		if is_instance_valid(corpo):
			corpo.freeze = true)


## Vita del frammento: sta lì, poi sprofonda rimpicciolendo e se ne va.
##
## ⚠️ Al momento di sparire il corpo diventa `freeze`: un RigidBody a cui si
## cambia la scala sotto i piedi continua a rispondere alla fisica con la forma
## di collisione vecchia, e si vedono i pezzi piccoli galleggiare a mezz'aria
## sopra il punto in cui erano grandi.
func _programma_sparizione(corpo : RigidBody3D) -> void:
	var t := get_tree().create_timer(riposo)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(corpo):
			return
		corpo.freeze = true
		var tw := corpo.create_tween()
		tw.set_parallel(true)
		tw.tween_property(corpo, "scale", corpo.scale * 0.05, sparizione)
		tw.tween_property(corpo, "position:y", corpo.position.y - 0.5, sparizione)
		tw.chain().tween_callback(corpo.queue_free))


## Spegne la collisione del prop rotto. ⚠️ Nell'arena il corpo di collisione
## delle colonne NON è figlio della colonna: il builder lo crea a parte. Si
## cerca quindi anche fra i FRATELLI vicini, o resterebbe in piedi un muro
## invisibile esattamente dove la colonna non c'è più — che è peggio di non
## averla rotta.
func _spegni_collisione(prop : Node3D) -> void:
	for n in prop.find_children("*", "CollisionObject3D", true, false):
		(n as CollisionObject3D).process_mode = Node.PROCESS_MODE_DISABLED
		(n as CollisionObject3D).set_deferred("collision_layer", 0)
	var padre := prop.get_parent()
	if padre == null:
		return
	for f in padre.get_children():
		if f == prop or not (f is CollisionObject3D):
			continue
		var co := f as CollisionObject3D
		## ⚠️ Il confronto è solo sul PIANO, non nello spazio. Il cilindro di
		## collisione di una colonna sta a mezza altezza (`height * 0.5`) mentre
		## la colonna ha l'origine alla base: in 3D distano metri, e cercandoli
		## vicini nello spazio non se ne trova mai nessuno — resterebbe in piedi
		## un muro invisibile dove la colonna non c'è più.
		var a := co.global_position
		var b := prop.global_position
		if Vector2(a.x - b.x, a.z - b.z).length() < 1.5:
			co.set_deferred("collision_layer", 0)
