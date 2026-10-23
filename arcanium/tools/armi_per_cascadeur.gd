extends SceneTree

## Le ARMI IN MANO del giocatore, pronte per `casc_arma_su_osso.py`: per ogni
## mesh visibile sotto la mano destra (spada) e la sinistra (scudo) del player,
## un GLB con la sola mesh e la sua trasformazione RELATIVA ALL'OSSO della mano,
## scritta nel json dell'allestimento.
##
## La trasformazione si compone salendo dai `transform` locali fino al
## BoneAttachment3D, senza chiedere pose globali: in headless i BoneAttachment
## danno zero (godot-headless-pose-non-avanza), e l'aggancio all'osso non
## dipende dalla posa.
##
## ⚠️ Gli assi delle ossa in Godot NON sono quelli del GLB: col bone map
## l'import riorienta i riposi sul profilo umanoide (rest_fixer/overwrite_axis,
## acceso di default e quindi assente dal .import). In Cascadeur, che legge il
## GLB grezzo, la spada agganciata con la trasformazione di Godot usciva dietro
## il braccio, puntata in alto (2026-10-23). Si passa allora per il riposo
## dello stesso osso nei due mondi: C = grezzo⁻¹ · godot, e l'aggancio sul GLB
## e' C · aggancio.
##
## I 12 float escono come li legge `casc_arma_su_osso._da_godot`: le tre RIGHE
## della base, poi l'origine in metri. L'osso e' il nome nel GLB (Hand_R).
##
## La PRESA e' quella del campione (CampioneResource.presa_arma/presa_scudo),
## messa sui nodi `Sword` e `Shield` come fa CorpoCampione in gioco.
##
## Uso: godot --headless --path . --script res://arcanium/tools/armi_per_cascadeur.gd -- <cartella> <nome json> <scheda campione .tres>
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const MANI := {"WeaponSystem/RightHand": "RightHand", "GadgetSystem/LeftHand": "LeftHand"}
const BONE_MAP := "res://arcanium/resources/rigs/nephilite_humanoid.tres"
const CorpoCampione := preload("res://arcanium/systems/corpo_campione.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dove : String = args[0]
	var nome_json : String = args[1] if args.size() > 1 else "armi_campione.json"
	var scheda : Resource = load(args[2])
	var corpo : String = scheda.corpo
	await process_frame
	var importato : Node = (load(corpo) as PackedScene).instantiate()
	var sk_godot : Skeleton3D = _scheletro(importato)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path(corpo), st)
	var grezzo : Node = doc.generate_scene(st)
	var sk_grezzo : Skeleton3D = _scheletro(grezzo)
	var mappa : BoneMap = load(BONE_MAP)
	var p : Node = (load(PLAYER) as PackedScene).instantiate()
	(p.get_node(CorpoCampione.ARMA_IN_MANO) as Node3D).transform = scheda.presa_arma
	(p.get_node(CorpoCampione.SCUDO_IN_MANO) as Node3D).transform = scheda.presa_scudo
	var armi : Array = []
	for percorso in MANI:
		var mano : Node3D = p.get_node(percorso)
		for mi in mano.find_children("*", "MeshInstance3D", true, false):
			if not _visibile(mi, mano) or (mi as MeshInstance3D).mesh == null:
				continue
			var rel := Transform3D.IDENTITY
			var n : Node = mi
			while n != mano:
				rel = (n as Node3D).transform * rel
				n = n.get_parent()
			var osso_glb := String(mappa.get_skeleton_bone_name(MANI[percorso]))
			var g := sk_godot.get_bone_global_rest(sk_godot.find_bone(MANI[percorso]))
			var r := sk_grezzo.get_bone_global_rest(sk_grezzo.find_bone(osso_glb))
			print("RIPOSO %s: origine godot %s, grezza %s" % [osso_glb, g.origin, r.origin])
			rel = r.affine_inverse() * g * rel
			var nome := "%s_%s" % [MANI[percorso], mi.name]
			var glb := dove.path_join(nome + ".glb")
			_esporta(mi as MeshInstance3D, glb)
			var b := rel.basis
			var dodici : Array = []
			for i in 3:
				dodici.append_array([b.x[i], b.y[i], b.z[i]])
			dodici.append_array([rel.origin.x, rel.origin.y, rel.origin.z])
			armi.append({"nome": nome, "glb": glb, "osso": osso_glb, "transform_godot": dodici})
			print("ARMA %s su %s, scala %.4f, origine %s" % [nome, MANI[percorso], b.get_scale().x, rel.origin])
	var spec := {
		"_nota": "Le armi in mano del player (%s) con la presa di %s, da armi_per_cascadeur.gd." % [PLAYER, scheda.nome],
		"armi": armi,
		"controlla_posa_osso": false,
	}
	var f := FileAccess.open(dove.path_join(nome_json), FileAccess.WRITE)
	f.store_string(JSON.stringify(spec, "    "))
	f.close()
	p.free()
	importato.free()
	grezzo.free()
	print("SCRITTO ", dove.path_join(nome_json))
	quit()


func _scheletro(radice : Node) -> Skeleton3D:
	return radice.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _visibile(n : Node, fino_a : Node) -> bool:
	while n != fino_a:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## La sola mesh, all'origine: la posizione sull'osso la mette Cascadeur.
func _esporta(mi : MeshInstance3D, percorso : String) -> void:
	var radice := Node3D.new()
	var copia := MeshInstance3D.new()
	copia.name = "mesh_node"
	copia.mesh = mi.mesh
	for k in mi.get_surface_override_material_count():
		copia.set_surface_override_material(k, mi.get_surface_override_material(k))
	radice.add_child(copia)
	copia.owner = radice
	var doc := GLTFDocument.new()
	var stato := GLTFState.new()
	doc.append_from_scene(radice, stato)
	doc.write_to_filesystem(stato, percorso)
	radice.free()
