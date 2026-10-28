extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## STOFFA SIMULATA — le mesh `Stoffa<N>` del corpo mosse da GPU Cloth Sim
## ═══════════════════════════════════════════════════════════════════════════
##
## Standard dal 2026-09-30 (docs/05 §4-quater): ogni tessuto di un personaggio
## esce dal montaggio come mesh a se', `Stoffa1`, `Stoffa2`..., con la maschera
## nel colore dei vertici (canale R: 0 segue le ossa, 1 libera). Questo nodo,
## figlio del personaggio, le trova sotto il suo genitore e da' a ognuna un
## `GPUClothSolver` (addons/godot_gpu_cloth):
##   - le stoffe si nominano a vicenda come PEER, cosi' collidono fra loro;
##   - capsule sulle gambe, perche' la veste libera non le attraversi.
##
## ⚠️ COSTO: pesano i dispatch, non le particelle. Sul Mago (Radeon 890M,
## renderer Mobile) ~0,8 ms per personaggio a 2x4 passi; 8 maghi insieme 7,95
## ms/frame contro 1,8. Il collisore dalla sagoma del corpo (`collisore_corpo`)
## costa ~3 ms a personaggio e non toglieva il buco dello stivale: spento.
## Per questo la stoffa si ACCENDE solo entro `distanza_attiva` dal GIOCATORE
## (dalla camera se un giocatore non c'e', nei playground e nelle verifiche).
## ⚠️ Non dalla camera: quella isometrica sta a ~29 m dal giocatore (offset
## 35,6 m per zoom 0,82), tutto cio' che e' a schermo e' fra 25 e 45 m da lei,
## e con la soglia sulla camera la stoffa in partita non si accendeva mai
## (verifica_mago_in_campo, 2026-09-30). Fuori, la mesh torna allo skinning normale
## (`gpu_driven = false`) e il solver si ferma. Riaccendendo si riparte dalla
## posa delle ossa (warm start) e si azzera l'inerzia accumulata da spenti,
## che altrimenti arriverebbe tutta in un frame.
##
## Senza RenderingDevice (headless, renderer Compatibility) non fa niente:
## i cancelli headless vedono il personaggio col solo skinning.

const SOLVER := preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
const COLLIDER := preload("res://addons/godot_gpu_cloth/src/gpu_cloth_collider.gd")
const PosaFinale := preload("res://arcanium/systems/posa_finale.gd")

## Le mesh di stoffa si riconoscono dal nome.
const PREFISSO := "Stoffa"
## Capsule che la stoffa libera non attraversa: osso → raggio (metri).
const CAPSULE := {
	"LeftUpperLeg": 0.085, "RightUpperLeg": 0.085,
	"LeftLowerLeg": 0.065, "RightLowerLeg": 0.065,
	## Senza i piedi lo stivale, nel passo, bucava l'orlo della veste.
	"LeftFoot": 0.055, "RightFoot": 0.055,
}

## Oltre questa distanza dal giocatore la stoffa torna skinning puro. A zoom
## normale lo schermo copre una ventina di metri attorno al giocatore.
@export var distanza_attiva := 25.0
## Passi e iterazioni del solver. Con 1 passo, nel passo lungo la gamba
## scavalcava la veste in ritardo e lo stivale bucava l'orlo: 2x4 non buca
## (Mago, 2026-09-30; 8 maghi 7,95 ms/frame a 2x4, 5,15 a 1x4).
@export var passi := 2
@export var iterazioni := 4
## Quanto la stoffa libera puo' allontanarsi dalla posa delle ossa (metri).
## A 0,15 la veste restava tanto indietro che la gamba la superava.
@export var viaggio := 0.06
## Collisore dalla sagoma del CORPO (le mesh che non sono stoffa): griglia di
## semplificazione dell'addon (`body_collider_voxel_resolution`), 0 = spento.
@export var collisore_corpo := 0

## Lo scheletro che muove le stoffe. Vuoto = il primo sotto il personaggio;
## sul giocatore lo passa CorpoCampione (il player ne ha piu' d'uno).
var scheletro : Skeleton3D = null
## La regolazione di un corpo, dalla scheda del campione
## (CampioneResource.stoffa), sopra i default di questo nodo:
##   "capsule": {osso senza lato: raggio} — "UpperLeg": 0.06 vale per le due
##       cosce. La capsula da 8,5 cm, piu' grossa delle cosce di Zarine,
##       spingeva fuori la tunica che aderisce all'anca e i triangoli si
##       ribaltavano (chiazze scure); quella dello stinco da 6,5, piu' stretta
##       del polpaccio con lo stivale, lasciava affondare il pannello dietro.
##   "viaggio": metri dalla posa delle ossa. A 6 cm la tunica di Zarine
##       affondava nei glutei e dietro le cosce, dove le capsule sull'asse
##       dell'osso stanno dentro la sagoma; a 2-3 cm resta pulita e cade ancora.
##   "rilievo": scostamento SOLO VISIVO verso fuori (cloth_render_offset): i
##       pantaloni non bucano piu' la stoffa che li sfiora. 1,2 cm su Zarine; a
##       2,5 i pannelli sembrano imbottiti (2026-10-28).
var regolazione : Dictionary = {}

var _solver : Array[Node3D] = []


func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var corpo := get_parent()
	var sk : Skeleton3D = scheletro
	if sk == null:
		var scheletri := corpo.find_children("*", "Skeleton3D", true, false)
		if scheletri.is_empty():
			return
		sk = scheletri[0]
	var stoffe : Array[MeshInstance3D] = []
	for mi in corpo.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(PREFISSO):
			stoffe.append(mi)
	if stoffe.is_empty():
		push_warning("StoffaSimulata: '%s' non ha mesh %s* (GLB montato senza separa_stoffe?)" % [corpo.name, PREFISSO])
		return
	## I percorsi sono ASSOLUTI: il solver si inizializza nel suo _ready e li
	## risolve da li'; i peer li risolve pigramente, quindi possono precedere i nodi.
	var corpo_mi : MeshInstance3D = null
	for mi in corpo.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).begins_with(PREFISSO) and mi.skin != null:
			corpo_mi = mi
			break
	## Le ossa dopo i modificatori (l'IK dei piedi): vedi posa_finale.gd.
	var finale := PosaFinale.new()
	finale.name = "PosaFinaleStoffa"
	sk.add_child(finale)
	sk.move_child(finale, -1)
	var capsule : Array[NodePath] = []
	for osso in CAPSULE:
		var senza_lato := String(osso).trim_prefix("Left").trim_prefix("Right")
		var c := _capsula(sk, osso, float((regolazione.get("capsule", {}) as Dictionary).get(senza_lato, CAPSULE[osso])))
		if c != null:
			capsule.append(c.get_path())
	var percorsi : Array[NodePath] = []
	for mi in stoffe:
		percorsi.append(NodePath(str(get_path()) + "/Solver" + String(mi.name)))
	for i in stoffe.size():
		var peer : Array[NodePath] = []
		for j in percorsi.size():
			if j != i:
				peer.append(percorsi[j])
		var s : Node3D = SOLVER.new()
		s.name = "Solver" + String(stoffe[i].name)
		s.set("target_mesh", stoffe[i].get_path())
		s.set("skeleton", sk.get_path())
		s.set("pose_provider", finale)
		s.set("collider_targets", capsule)
		s.set("peer_cloth_solvers", peer)
		s.set("substeps", passi)
		s.set("solver_iterations", iterazioni)
		s.set("stiffness", 0.8)
		s.set("bend_stiffness", 0.15)
		s.set("damping", 0.98)
		s.set("max_travel_distance", float(regolazione.get("viaggio", viaggio)))
		s.set("cloth_render_offset", float(regolazione.get("rilievo", 0.0)))
		s.set("cloth_skin_offset", float(regolazione.get("pelle", 0.0)))
		s.set("collider_friction", 0.3)
		if collisore_corpo > 0 and corpo_mi != null:
			s.set("body_mesh", corpo_mi.get_path())
			s.set("body_collider_voxel_resolution", collisore_corpo)
		s.set_meta("accesa", true)
		add_child(s)
		_solver.append(s)


func _process(_delta : float) -> void:
	if _solver.is_empty():
		return
	var vicino := true
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		vicino = pl.global_position.distance_to(global_position) <= distanza_attiva
	else:
		var cam := get_viewport().get_camera_3d()
		vicino = cam == null or cam.global_position.distance_to(global_position) <= distanza_attiva
	for s in _solver:
		if s.get_meta("accesa") != vicino:
			_accendi(s, vicino)


## Vera se almeno un solver sta simulando (per i cancelli e il debug).
func attiva() -> bool:
	for s in _solver:
		if s.get_meta("accesa") and s.get("_gpu_init_done"):
			return true
	return false


func _accendi(s : Node3D, si : bool) -> void:
	## Finche' il solver non ha finito l'init sulla GPU non ha materiale ne'
	## stato da toccare: si riprova al frame dopo.
	if not s.get("_gpu_init_done"):
		return
	s.set_meta("accesa", si)
	s.set_process(si)
	var mat : ShaderMaterial = s.get("_surf_mat")
	if mat != null:
		mat.set_shader_parameter("gpu_driven", si)
	if si:
		s.set("_needs_warm_start", true)
		var ref : Node3D = s.get("_ref_node")
		if ref != null:
			s.set("_prev_skel_world_pos", ref.global_position)
			s.set("_prev_skel_world_basis", ref.global_transform.basis)


## Una capsula lungo l'osso, dalla sua testa a quella del figlio.
func _capsula(sk : Skeleton3D, osso : String, raggio : float) -> Node3D:
	var i := sk.find_bone(osso)
	if i < 0 or sk.get_bone_children(i).is_empty():
		return null
	var punta : Vector3 = sk.get_bone_rest(sk.get_bone_children(i)[0]).origin
	var att := BoneAttachment3D.new()
	att.bone_name = osso
	sk.add_child(att)
	var c : Node3D = COLLIDER.new()
	c.set("shape", 1)  # CAPSULE
	c.set("radius", raggio)
	c.set("height", punta.length() + 2.0 * raggio)
	var y := punta.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	c.transform = Transform3D(Basis(x, y, x.cross(y)), punta * 0.5)
	att.add_child(c)
	return c
