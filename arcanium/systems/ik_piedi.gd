@tool
extends SkeletonModifier3D

## ═══════════════════════════════════════════════════════════════════════════
## IK DEI PIEDI
## ═══════════════════════════════════════════════════════════════════════════
##
## Posa i piedi sul terreno che c'e' davvero, invece che sulla quota a cui li ha
## lasciati la clip.
##
## Perche' serve, misurato in gioco al Crocevia sulla posa d'attesa: le caviglie
## stanno a **15,3 e 14,9 cm** da terra contro i 12,3 del rest, e il piede
## sinistro fluttua — l'ombra sotto la suola si vede a occhio. La causa e' nota
## (`docs/05` §5-bis): le clip sono state autorate su un corpo con le gambe
## **6,4 cm piu' corte**. Non si aggiusta abbassando il nodo del modello, perche'
## l'errore CAMBIA a ogni clip; e non e' la capsula, il cui fondo e' gia' a zero.
##
## ## ⚠️⚠️ NON c'e' una lista di animazioni su cui spegnere
##
## La strada ovvia — elencare gli stati (finisher, salto, rotolata) e spegnere
## la' — e' quella che non regge. Questo `AnimationTree` ha OTTO macchine a stati
## annidate (ATTACK, DODGE, GADGET, ITEM, LANDED, INTERACT, MovementStates,
## SPRINT, piu' i sotto-alberi per tipo d'arma), e ogni calcio, ogni scavalcata,
## ogni finisher nuovo aggiungerebbe una riga a una lista che nessuno ricorda di
## aggiornare. Sarebbe sempre incompleta di una animazione: quella appena messa.
##
## Qui decide la GEOMETRIA. Ogni piede cerca il terreno solo dentro una finestra
## stretta attorno a se' (`finestra_su`/`finestra_giu`). Se il terreno non e' li'
## dentro, quel piede e' in aria **per volonta' dell'animatore** — un salto, una
## rotolata, il calcio del finisher — e non lo si tocca. Un piede alzato di mezzo
## metro non e' un errore da correggere: e' l'animazione.
##
## Restano due interruttori espliciti, per cio' che la geometria non puo' sapere:
##   • `is_on_floor()` del corpo — in caduta non si posa niente;
##   • `influence`, che si porta a zero da fuori per una clip particolare.
## E si SFUMA (`velocita_influenza`) invece di spegnere di colpo, o al rientro in
## locomozione i piedi scattano.
##
## ## ⚠️ I raycast NON si tirano qui dentro
##
## `_process_modification_with_delta` gira dentro l'aggiornamento dello scheletro,
## che non e' il passo di fisica: interrogare li' il `direct_space_state` e' un
## accesso fuori tempo. Le sonde si tirano in `_physics_process` e si mettono in
## cassa; la modifica legge la cassa. Un frame di ritardo su un piede che si posa
## non si vede.
##
## ## ⚠️ `get_bone_global_pose()` NON dice se l'IK sta funzionando
##
## Da fuori quella chiamata restituisce la posa dell'ANIMAZIONE, non quella che
## esce dai modificatori: la pelle usa un altro buffer. Misurando cosi' l'IK
## sembrava non fare niente — caviglia a 0,154 con l'IK acceso, esattamente come
## spento — mentre chiamando la funzione a mano il piede scendeva a 0,120.
## Sembrava che il motore non ci chiamasse affatto. Ci chiamava: 642 volte.
##
## L'unica prova e' GUARDARE. E se una correzione da tre centimetri e' troppo
## piccola per distinguerla in uno screenshot, si esagera il parametro finche'
## il difetto diventa evidente — con l'offset a 60 cm le gambe si sono piegate
## in modo inequivocabile, e quello ha chiuso la questione in un colpo.

## Le tre ossa per gamba, dall'anca alla caviglia.
@export var gamba_sinistra : PackedStringArray = ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
@export var gamba_destra : PackedStringArray = ["RightUpperLeg", "RightLowerLeg", "RightFoot"]
## L'osso del bacino, che scende quando una gamba non arriva (gradini, pendii).
@export var osso_bacino : String = "Hips"

@export_group("Terreno")
## Il corpo del personaggio. Serve solo per `is_on_floor()`: in aria non si posa.
@export var corpo : CharacterBody3D
@export_flags_3d_physics var maschera_terreno : int = 1

@export_group("Finestra")
## Quanto sopra il piede comincia la sonda.
@export var finestra_su : float = 0.45
## Quanto sotto il piede finisce. Oltre questa quota il terreno "non c'e'": il
## piede e' in aria per scelta dell'animatore e resta dov'e'.
@export var finestra_giu : float = 0.40
## Quanto puo' scendere il bacino quando una gamba non arriva.
@export var discesa_massima_bacino : float = 0.35

@export_group("Sfumatura")
## Quanto e' rapido il passaggio acceso/spento, in influence al secondo.
@export var velocita_influenza : float = 6.0
## Inclinazione del piede sulla pendenza. Oltre questo angolo non si ruota piu':
## su uno spigolo la normale impazzisce e la caviglia si torcerebbe.
@export_range(0.0, 60.0) var pendenza_massima_gradi : float = 40.0

## Distanza suola→caviglia, LETTA dal rest invece che scritta a mano: cosi' un
## corpo diverso (quello femminile, i nemici) non ha bisogno di un altro numero.
var _offset_suola : float = 0.0
var _pronto := false
## Cassa delle sonde, riempita in _physics_process. Per piede: [colpito, y, normale]
var _terreno : Array = [[false, 0.0, Vector3.UP], [false, 0.0, Vector3.UP]]


func _ready() -> void:
	influence = 0.0
	set_physics_process(not Engine.is_editor_hint())


func _prepara(skel : Skeleton3D) -> void:
	## La suola sta a quota zero nel rest, quindi la quota della caviglia NEL REST
	## e' la distanza suola→caviglia. Vale finche' il rest e' in piedi a terra,
	## che e' il caso di tutti i corpi del progetto.
	var i : int = skel.find_bone(gamba_sinistra[2])
	_offset_suola = skel.get_bone_global_rest(i).origin.y if i >= 0 else 0.12
	_pronto = true


func _physics_process(delta : float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _pronto:
		_prepara(skel)

	var voluta := 1.0
	if corpo != null and not corpo.is_on_floor():
		voluta = 0.0
	influence = move_toward(influence, voluta, velocita_influenza * delta)

	var spazio := get_world_3d().direct_space_state
	var gambe := [gamba_sinistra, gamba_destra]
	for k in 2:
		_terreno[k] = [false, 0.0, Vector3.UP]
		var idx : int = skel.find_bone(gambe[k][2])
		if idx < 0:
			continue
		var piede : Vector3 = (skel.global_transform * skel.get_bone_global_pose(idx)).origin
		var par := PhysicsRayQueryParameters3D.create(
			piede + Vector3.UP * finestra_su,
			piede - Vector3.UP * finestra_giu)
		par.collision_mask = maschera_terreno
		if corpo != null:
			par.exclude = [corpo.get_rid()]
		var colpo := spazio.intersect_ray(par)
		if not colpo.is_empty():
			_terreno[k] = [true, colpo.position.y, colpo.normal]


func _process_modification_with_delta(_delta : float) -> void:
	var skel := get_skeleton()
	if skel == null or influence <= 0.001 or not _pronto:
		return

	var gambe := [gamba_sinistra, gamba_destra]
	var voluta : Array = [0.0, 0.0]
	var attiva : Array = [false, false]
	for k in 2:
		if not _terreno[k][0]:
			continue
		if skel.find_bone(gambe[k][2]) < 0:
			continue
		attiva[k] = true
		voluta[k] = float(_terreno[k][1]) + _offset_suola
	if not (attiva[0] or attiva[1]):
		return

	## Il bacino scende SOLO se una gamba non arriva stendendosi. Alzarlo non si
	## fa mai: farebbe crescere il personaggio sui dossi.
	var discesa := 0.0
	for k in 2:
		if not attiva[k]:
			continue
		var anca : Vector3 = _posa(skel, gambe[k][0]).origin
		var gin : Vector3 = _posa(skel, gambe[k][1]).origin
		var piede : Vector3 = _posa(skel, gambe[k][2]).origin
		var portata : float = anca.distance_to(gin) + gin.distance_to(piede)
		var manca : float = anca.distance_to(Vector3(piede.x, voluta[k], piede.z)) - portata * 0.999
		if manca > discesa:
			discesa = manca
	discesa = minf(discesa, discesa_massima_bacino) * influence
	if discesa > 0.0001:
		var ib : int = skel.find_bone(osso_bacino)
		if ib >= 0:
			var t : Transform3D = skel.get_bone_global_pose(ib)
			t.origin.y -= discesa
			skel.set_bone_global_pose(ib, t)

	for k in 2:
		if not attiva[k]:
			continue
		var piede : Vector3 = _posa(skel, gambe[k][2]).origin
		var bersaglio : Vector3 = Vector3(piede.x, voluta[k], piede.z)
		_due_ossa(skel, gambe[k], piede.lerp(bersaglio, influence))
		_appoggia(skel, gambe[k][2], _terreno[k][2])


func _posa(skel : Skeleton3D, nome : String) -> Transform3D:
	var i : int = skel.find_bone(nome)
	if i < 0:
		return Transform3D.IDENTITY
	return skel.global_transform * skel.get_bone_global_pose(i)


## IK a due ossa. Il ginocchio NON prende un polo scritto a mano: si tiene il
## piano che ha gia' nella clip e si cambia solo l'angolo. Un polo fisso fa
## incrociare le gambe appena il personaggio si muove di lato, ed e' un difetto
## che si nota molto piu' del piede che fluttua.
func _due_ossa(skel : Skeleton3D, ossa : PackedStringArray, bersaglio : Vector3) -> void:
	var i_anca : int = skel.find_bone(ossa[0])
	var i_gin : int = skel.find_bone(ossa[1])
	var i_pie : int = skel.find_bone(ossa[2])
	if i_anca < 0 or i_gin < 0 or i_pie < 0:
		return
	var g : Transform3D = skel.global_transform
	var gi : Transform3D = g.affine_inverse()
	var t_anca : Transform3D = g * skel.get_bone_global_pose(i_anca)
	var t_gin : Transform3D = g * skel.get_bone_global_pose(i_gin)
	var t_pie : Transform3D = g * skel.get_bone_global_pose(i_pie)
	var a : Vector3 = t_anca.origin
	var b : Vector3 = t_gin.origin
	var c : Vector3 = t_pie.origin
	var l1 : float = a.distance_to(b)
	var l2 : float = b.distance_to(c)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var verso : Vector3 = bersaglio - a
	if verso.length() < 0.0001:
		return
	var d : float = clampf(verso.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	verso = verso.normalized()

	## L'asse attorno a cui gira il ginocchio: la normale del piano anca-ginocchio-
	## piede che la clip ha gia'. Se le tre ossa sono allineate quel piano non
	## esiste, e si lascia stare invece di inventarne uno.
	var asse : Vector3 = (b - a).cross(c - a)
	if asse.length() < 0.00001:
		return
	asse = asse.normalized()

	var cos_anca : float = clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var nuovo_gin : Vector3 = a + verso.rotated(asse, -acos(cos_anca)) * l1
	var nuovo_pie : Vector3 = a + verso * d

	skel.set_bone_global_pose(i_anca, gi *
		Transform3D(_ruota_verso(t_anca.basis, b - a, nuovo_gin - a), a))
	var t_gin2 : Transform3D = g * skel.get_bone_global_pose(i_gin)
	skel.set_bone_global_pose(i_gin, gi *
		Transform3D(_ruota_verso(t_gin2.basis, c - b, nuovo_pie - nuovo_gin), nuovo_gin))


## La rotazione che porta `da` su `a`, applicata a una base. Si RUOTA la base
## invece di ricostruirla: ricostruirla con un `looking_at` butta via la
## torsione dell'osso, e il piede finisce girato di lato.
func _ruota_verso(base : Basis, da : Vector3, a : Vector3) -> Basis:
	if da.length() < 0.00001 or a.length() < 0.00001:
		return base
	var u : Vector3 = da.normalized()
	var v : Vector3 = a.normalized()
	var asse : Vector3 = u.cross(v)
	if asse.length() < 0.00001:
		return base
	return Basis(asse.normalized(), acos(clampf(u.dot(v), -1.0, 1.0))) * base


## Inclina il piede sulla pendenza, entro un limite.
func _appoggia(skel : Skeleton3D, nome : String, normale : Vector3) -> void:
	var i : int = skel.find_bone(nome)
	if i < 0:
		return
	var ang : float = Vector3.UP.angle_to(normale)
	if ang < 0.005 or ang > deg_to_rad(pendenza_massima_gradi):
		return
	var asse : Vector3 = Vector3.UP.cross(normale)
	if asse.length() < 0.00001:
		return
	var g : Transform3D = skel.global_transform
	var t : Transform3D = g * skel.get_bone_global_pose(i)
	t.basis = Basis(asse.normalized(), ang * influence) * t.basis
	skel.set_bone_global_pose(i, g.affine_inverse() * t)
