extends SceneTree

## La GUARDIA PESANTE del campione, per la base di Cascadeur
## (base_cascadeur.py `posa=`).
##
## Le idle d'autore delle armi a due mani (Zarine, Aurin) partono dalla posa
## della HeavyIdle e ci tornano, cosi' si legano alla camminata pesante senza
## strappi (docs/campioni_concept.md, 2026-10-23). Quella posa esiste solo qui:
## MeleeLib.res e' una libreria cotta sul protagonista, e la porta sul campione
## rig_retarget.gd, come nel banco delle impugnature.
##
## Si scrive, per ogni osso, il riposo e la posa NEL MONDO (metri, Y in alto)
## col nome che l'osso ha nel GLB grezzo: la bone map dell'import rinomina le
## ossa del profilo umanoide (LeftHand) e lascia le altre (Cape_Attachment_04).
## Gli assi delle ossa in Godot non sono quelli del GLB (il rest fixer li
## riorienta): per questo si danno riposo E posa, e Blender ne usa solo lo
## scarto, sul suo riposo.
##
## Uso (APPDATA isolato):
##   godot --headless --path . --script res://arcanium/tools/guardia_per_cascadeur.gd -- <casata> <uscita.json>

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const SCHELETRO_PLAYER := "protagonist/BaseArmature/GeneralSkeleton"
const MOVESET := "res://player/animation_libraries/MeleeLib.res"
const GUARDIA_PESANTE := "HeavyIdle"
const BONE_MAP := "res://arcanium/resources/rigs/nephilite_humanoid.tres"
const Retarget := preload("res://arcanium/tools/rig_retarget.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("uso: ... -- <casata> <uscita.json>")
		quit(1)
		return
	var scheda : Resource = load("res://arcanium/resources/campioni/%s.tres" % args[0])
	var corpo : Node3D = (load(scheda.corpo) as PackedScene).instantiate()
	root.add_child(corpo)
	var sk : Skeleton3D = corpo.find_children("*", "Skeleton3D", true, false)[0]
	var pl : Node = (load(PLAYER) as PackedScene).instantiate()
	Retarget.applica_istante(Retarget.retarget((load(MOVESET) as AnimationLibrary).get_animation(GUARDIA_PESANTE),
			pl.get_node(SCHELETRO_PLAYER) as Skeleton3D, sk), sk)
	pl.free()

	var mappa : BoneMap = load(BONE_MAP)
	## Dentro _init lo scheletro non e' ancora nell'albero e global_transform
	## non risponde: si compongono i transform dei nodi fino al corpo.
	var mondo := Transform3D.IDENTITY
	var n : Node = sk
	while n != null and n is Node3D:
		mondo = (n as Node3D).transform * mondo
		n = n.get_parent()
	var ossa := {}
	var mosse := 0
	for b in sk.get_bone_count():
		var nome := sk.get_bone_name(b)
		var grezzo := String(mappa.get_skeleton_bone_name(nome)) if mappa.profile.find_bone(nome) >= 0 else ""
		var riposo := mondo * sk.get_bone_global_rest(b)
		var posa := mondo * sk.get_bone_global_pose(b)
		if not riposo.basis.is_equal_approx(posa.basis):
			mosse += 1
		ossa[grezzo if grezzo != "" else nome] = {"riposo": _righe(riposo), "posa": _righe(posa)}
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify({"_nota": "guardia_per_cascadeur.gd, %s: %s frame 0" % [scheda.nome, GUARDIA_PESANTE],
			"ossa": ossa}, " "))
	f.close()
	print("GUARDIA: %s, %d ossa, %d girate rispetto al riposo -> %s" % [scheda.nome, ossa.size(), mosse, args[1]])
	quit()


## Le tre righe della base e l'origine: 12 numeri, la matrice 4x4 senza l'ultima riga.
func _righe(t : Transform3D) -> Array:
	var r := []
	for i in 3:
		r.append_array([t.basis[0][i], t.basis[1][i], t.basis[2][i], t.origin[i]])
	return r
