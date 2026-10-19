extends Node

## ═══════════════════════════════════════════════════════════════════════════
## MISURA DELLA PRESA DELL'ARCO — da che parte sta la corda rispetto al braccio
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . res://arcanium/tools/misura_presa_arco.tscn -- \
##       [scena_arciere.tscn] [clip] [istanti es. 0.0,1.2,1.83] [gradi]
##
## In coda stampa anche la `held_transform` del PLAYER derivata (vedi sotto).
##
## La presa dell'arco (`MountArma/ArcoDiSpiritoSylvorn.transform`) si tara a
## mano nell'editor, e l'occhio giudica l'impugnatura: la CORDA no. La corda
## sta nel piano dell'arco a +X del suo riferimento (i marker `Corda/*` hanno
## x ~ 0,27), e in un tiro vero passa lungo l'INTERNO dell'avambraccio che
## regge l'arco — e' il motivo del bracciale degli arcieri. Con la presa del
## 2026-09-13 passava all'ESTERNO: l'arco era girato di circa un quarto di
## giro attorno ai flettenti.
##
## Questo tool misura, agli istanti chiesti della clip, l'angolo attorno
## all'asse dei flettenti (Y dell'arco) fra la direzione della corda (+X) e
## la direzione dall'impugnatura al GOMITO del braccio che regge l'arco:
## 0 gradi = la corda corre lungo l'avambraccio. E stampa la trasformazione
## dell'arco ruotata di `gradi` attorno ai flettenti, pronta per il .tscn:
## la si guarda con `anteprima_clip_nemico` prima di tenerla.
##
## E il PLAYER. Tiene lo stesso arco su
## `WeaponSystem/RightHand/HandPivot/<arma>/ModelloEquipaggiato`, con la
## `held_transform` del .tres dell'arco. La presa NON si copia da quella
## dell'arciere: le due `RightHand` hanno assi diversi (i due rig differiscono
## di un angolo COSTANTE, ~67 gradi sulla mano, uguale in ogni posa — misurato
## sull'idle e sul tiro entro 2 gradi). Si CALCOLA: nella stessa posa della
## stessa clip, l'arco deve stare nella mano del player come sta in quella
## dell'arciere, quindi held = C⁻¹ · H_p⁻¹ · A, con A l'orientamento dell'arco
## sull'arciere, H_p quello della RightHand del player e C la catena fissa
## HandPivot·arma. Fino al 2026-09-14 la presa del player era sbagliata di
## ~89 gradi: nel tiro non si notava, nell'idle l'arco stava orizzontale.
##
## ⚠️ E' una SCENA: le pose si leggono con seek + get_bone_global_pose da un
## nodo in scena; l'arciere ha la fisica spenta (senza bersaglio rimetterebbe
## l'idle) e non ha l'albero, quindi si suona l'AnimationPlayer direttamente.

const SCENA := "res://arcanium/characters/sylvorn_soldato_scelto.tscn"
const CLIP := "sword/sword_bow_shot_01"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scena : String = args[0] if args.size() >= 1 else SCENA
	var clip : String = args[1] if args.size() >= 2 else CLIP
	var istanti := PackedFloat32Array([0.0, 1.2, 1.83])
	if args.size() >= 3:
		istanti = PackedFloat32Array()
		for s in str(args[2]).split(","):
			istanti.append(float(s))
	var gradi : float = float(args[3]) if args.size() >= 4 else 0.0

	var a : Node3D = (load(scena) as PackedScene).instantiate()
	add_child(a)
	a.set_physics_process(false)
	a.set_process(false)
	var sk : Skeleton3D = a.get_node("Model/NephiliteRig/Skeleton3D")
	var arco : Node3D = a.get_node(a.get("arco"))
	var mount := arco.get_parent() as BoneAttachment3D
	var ap : AnimationPlayer = a.get("anim_player")
	var i_mount := sk.find_bone(mount.bone_name)
	var lato := "Right" if mount.bone_name.ends_with("_R") else "Left"
	var i_gomito := sk.find_bone(lato + "LowerArm")
	var i_spalla := sk.find_bone(lato + "UpperArm")
	if i_mount < 0 or i_gomito < 0 or not ap.has_animation(clip):
		push_error("ossa o clip assenti (%s, %sLowerArm, %s)" % [mount.bone_name, lato, clip])
		get_tree().quit(1)
		return
	print("presa attuale: %s" % var_to_str(arco.transform))
	var somma := 0.0
	for t in istanti:
		ap.play(clip)
		ap.seek(t, true)
		var t_mount : Transform3D = sk.get_bone_global_pose(i_mount)
		var t_arco : Transform3D = t_mount * arco.transform
		var flettenti : Vector3 = t_arco.basis.y.normalized()
		var corda : Vector3 = t_arco.basis.x
		var gomito : Vector3 = sk.get_bone_global_pose(i_gomito).origin - t_arco.origin
		var spalla : Vector3 = sk.get_bone_global_pose(i_spalla).origin - t_arco.origin
		## Nel piano perpendicolare ai flettenti: angolo con segno da corda a gomito.
		var c := (corda - flettenti * corda.dot(flettenti)).normalized()
		var g := (gomito - flettenti * gomito.dot(flettenti)).normalized()
		var ang := atan2(c.cross(g).dot(flettenti), c.dot(g))
		somma += ang
		print("t %.2f: corda-gomito %+.0f gradi attorno ai flettenti | flettenti vs avambraccio %.0f gradi | corda.spalla %+.2f" % [
			t, rad_to_deg(ang), rad_to_deg(flettenti.angle_to(gomito.normalized())), c.dot(spalla.normalized())])
	print("media: %+.0f gradi (0 = la corda corre lungo l'avambraccio, verso il gomito)" % rad_to_deg(somma / istanti.size()))
	if gradi != 0.0:
		var nuova : Transform3D = arco.transform * Transform3D(Basis(Vector3.UP, deg_to_rad(gradi)), Vector3.ZERO)
		print("ruotata di %+.0f gradi attorno ai flettenti:" % gradi)
		print(var_to_str(nuova))
	_presa_player(a, sk, ap, clip, i_mount, arco, istanti)
	_presa_freccia(a, sk, ap, clip, i_mount, arco)
	get_tree().quit(0)


const ClipDaGlb := preload("res://arcanium/systems/clip_da_glb.gd")
const FrecciaInMano := preload("res://arcanium/systems/armi/freccia_in_mano.gd")
const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const ARCO_TRES := "res://arcanium/resources/weapons/arco_di_spirito_sylvorn.tres"
const CLIP_PLAYER_DIR := "res://assets/characters/anims/arco/"


## La presa del player derivata da quella dell'arciere (vedi il cappello).
## La clip del player e' la copia in `anims/arco/` con lo stesso nome file.
func _presa_player(a : Node3D, ska : Skeleton3D, apa : AnimationPlayer, clip : String,
		i_mount : int, arco : Node3D, istanti : PackedFloat32Array) -> void:
	var glb := CLIP_PLAYER_DIR + clip.get_file() + ".glb"
	if not ResourceLoader.exists(PLAYER) or not ResourceLoader.exists(ARCO_TRES) or not ResourceLoader.exists(glb):
		print("player: salto (manca %s, %s o %s)" % [PLAYER, ARCO_TRES, glb])
		return
	var p : Node3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	for c in p.find_children("*", "", true, false):
		c.set_physics_process(false)
		c.set_process(false)
	p.set_physics_process(false)
	p.set_process(false)
	var albero : AnimationTree = p.find_child("AnimStateTree", true, false)
	if albero:
		albero.active = false
	var skp : Skeleton3D = p.find_child("GeneralSkeleton", true, false)
	var pivot : Node3D = p.get_node_or_null("WeaponSystem/RightHand/HandPivot")
	var res : Resource = load(ARCO_TRES)
	if skp == null or pivot == null or res == null or not ("held_transform" in res):
		print("player: scheletro, HandPivot o held_transform assenti")
		return
	## La catena fissa fra l'attacco della mano e il modello: il pivot e l'arma
	## che ci sta sotto (a runtime `held_weapon.gd` appende il modello all'arma).
	var catena : Transform3D = pivot.transform
	if pivot.get_child_count() > 0 and pivot.get_child(0) is Node3D:
		catena = catena * (pivot.get_child(0) as Node3D).transform
	var anim : Animation = ClipDaGlb.carica(glb, skp, true)
	if anim == null:
		print("player: clip %s non caricabile" % glb)
		return
	var i_mano := skp.find_bone("RightHand")
	var held : Transform3D = res.held_transform
	var stime : Array[Basis] = []
	for t in istanti:
		apa.play(clip)
		apa.seek(t, true)
		var arco_a : Basis = (ska.get_bone_global_pose(i_mount) * arco.transform).basis.orthonormalized()
		for tr in anim.get_track_count():
			if anim.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
				continue
			var b := skp.find_bone(str(anim.track_get_path(tr)).get_slice(":", 1))
			if b >= 0:
				skp.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
		skp.force_update_all_bone_transforms()
		var mano_p : Basis = skp.get_bone_global_pose(i_mano).basis.orthonormalized()
		var arco_p : Basis = (mano_p * catena.basis * held.basis).orthonormalized()
		var stima : Basis = (catena.basis.inverse() * mano_p.inverse() * arco_a).orthonormalized()
		stime.append(stima)
		print("player t %.2f: arco del player contro l'arciere %.1f gradi (con la held_transform attuale)" % [
			t, rad_to_deg((arco_p.inverse() * arco_a).get_rotation_quaternion().get_angle())])
	var coerenza := 0.0
	for s_ in stime:
		coerenza = maxf(coerenza, rad_to_deg((stime[0].inverse() * s_).get_rotation_quaternion().get_angle()))
	print("player: held_transform derivata dall'arciere (stime coerenti entro %.1f gradi; origine tenuta):" % coerenza)
	print("held_transform = " + var_to_str(Transform3D(stime[0], held.origin)))


## La PRESA DELLA FRECCIA nella mano che tira (`presa_freccia` dell'arciere e
## del SetArco): all'istante dell'incocco della mossa (`tendi_da`) la freccia
## incoccata ha una posa precisa — cocca sull'incocco della corda (che segue
## la mano), asta verso il poggio — e la presa in mano e' quella stessa posa
## letta nel riferimento della mano. Cosi' la freccia, portata in mano dalla
## faretra, arriva sulla corda esattamente dove la fase incoccata la prende.
func _presa_freccia(a : Node3D, ska : Skeleton3D, apa : AnimationPlayer, clip : String,
		i_mount : int, arco : Node3D) -> void:
	var move = null
	for m in a.move_set.moves:
		if m.anim == clip:
			move = m
	if move == null or not ("tendi_da" in move):
		print("presa freccia: nessuna mossa con la clip %s" % clip)
		return
	var t : float = move.tendi_da
	var corda : Node3D = arco.get_node_or_null("Corda")
	var mano_a := a.get_node_or_null(a.mano_che_tira) as BoneAttachment3D
	if corda == null or mano_a == null:
		return
	var riposo : Vector3 = corda.get_node("Incocco").position
	var lung : float = FrecciaInMano.Freccia.LUNGHEZZA
	apa.play(clip)
	apa.seek(t, true)
	var t_corda_a : Transform3D = ska.get_bone_global_pose(i_mount) * arco.transform * corda.transform
	var t_mano_a : Transform3D = ska.get_bone_global_pose(ska.find_bone(mano_a.bone_name))
	var incocco_a : Vector3 = corda._vincola(t_corda_a.affine_inverse() * t_mano_a.origin)
	var posa_a : Transform3D = FrecciaInMano.posa_da(t_corda_a, riposo, incocco_a, lung)
	print("presa freccia ARCIERE (all'incocco, t %.2f; cocca a %.1f cm dal riposo):" % [t, incocco_a.distance_to(riposo) * 100.0])
	print("presa_freccia = " + var_to_str(t_mano_a.affine_inverse() * posa_a))

	## Il player: la corda sta sotto l'arco in mano (RightHand · HandPivot ·
	## arma · held_transform), la mano che tira e' GadgetSystem/LeftHand/HandPivot.
	var glb := CLIP_PLAYER_DIR + clip.get_file() + ".glb"
	if not ResourceLoader.exists(PLAYER) or not ResourceLoader.exists(glb):
		return
	var p : Node3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	for c in p.find_children("*", "", true, false):
		c.set_physics_process(false)
		c.set_process(false)
	var albero : AnimationTree = p.find_child("AnimStateTree", true, false)
	if albero:
		albero.active = false
	var skp : Skeleton3D = p.find_child("GeneralSkeleton", true, false)
	var pivot_d : Node3D = p.get_node_or_null("WeaponSystem/RightHand/HandPivot")
	var pivot_s : Node3D = p.get_node_or_null("GadgetSystem/LeftHand/HandPivot")
	var res : Resource = load(ARCO_TRES)
	if skp == null or pivot_d == null or pivot_s == null or res == null:
		return
	var catena : Transform3D = pivot_d.transform
	if pivot_d.get_child_count() > 0 and pivot_d.get_child(0) is Node3D:
		catena = catena * (pivot_d.get_child(0) as Node3D).transform
	var anim : Animation = ClipDaGlb.carica(glb, skp, true)
	if anim == null:
		return
	for tr in anim.get_track_count():
		if anim.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var b := skp.find_bone(str(anim.track_get_path(tr)).get_slice(":", 1))
		if b >= 0:
			skp.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
	skp.force_update_all_bone_transforms()
	var t_corda_p : Transform3D = skp.get_bone_global_pose(skp.find_bone("RightHand")) * catena * res.held_transform * corda.transform
	var t_mano_p : Transform3D = skp.get_bone_global_pose(skp.find_bone("LeftHand")) * pivot_s.transform
	var incocco_p : Vector3 = corda._vincola(t_corda_p.affine_inverse() * t_mano_p.origin)
	var posa_p : Transform3D = FrecciaInMano.posa_da(t_corda_p, riposo, incocco_p, lung)
	print("presa freccia PLAYER (all'incocco, t %.2f; cocca a %.1f cm dal riposo):" % [t, incocco_p.distance_to(riposo) * 100.0])
	print("presa_freccia = " + var_to_str(t_mano_p.affine_inverse() * posa_p))
