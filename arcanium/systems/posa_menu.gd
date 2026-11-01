extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## LA POSA DEL MENU, ricavata dal riposo dello scheletro
## ═══════════════════════════════════════════════════════════════════════════
##
## I campioni montati sul Nephilite avevano la clip `Posa` cotta nel GLB da
## Blender (posa_menu di monta_campione.py): in piedi, braccia lungo i fianchi.
## Quelli sullo scheletro ARP (pipeline nostra, 2026-11-01) escono dall'export
## di ARP senza clip, e nella selezione restavano in A-pose, a braccia aperte.
## Qui la stessa posa si costruisce in Godot dal riposo, coi nomi Humanoid:
## le braccia scendono a BRACCIA gradi dalla verticale verso l'esterno, gli
## avambracci si piegano di GOMITI in avanti, e il petto respira.
##
## `assicura(scena)` la aggiunge a un AnimationPlayer del corpo se il GLB non
## ne ha una: CorpoCampione, la selezione e il banco delle impugnature la
## trovano dove la trovavano prima.

const NOME := "Posa"
const BRACCIA := 9.0
const GOMITI := 14.0
## Gradi di respiro a meta' giro (come esporta_glb di monta_consumato_sylvorn).
const RESPIRO := {"Chest": 0.8, "UpperChest": 1.2, "LeftShoulder": -1.0, "RightShoulder": -1.0}
const DURATA := 3.0


static func assicura(scena : Node) -> void:
	for ap in scena.find_children("*", "AnimationPlayer", true, false):
		if (ap as AnimationPlayer).has_animation(NOME):
			return
	var trovati := scena.find_children("*", "Skeleton3D", true, false)
	if trovati.is_empty():
		return
	var sk := trovati[0] as Skeleton3D
	var aps := scena.find_children("*", "AnimationPlayer", true, false)
	var ap : AnimationPlayer
	if aps.is_empty():
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		scena.add_child(ap)
	else:
		ap = aps[0]
	var radice := ap.get_node(ap.root_node)
	var lib := AnimationLibrary.new()
	if ap.has_animation_library(""):
		lib = ap.get_animation_library("")
	else:
		ap.add_animation_library("", lib)
	lib.add_animation(NOME, crea(sk, String(radice.get_path_to(sk))))


## La clip: tracce di rotazione `<percorso>:<osso>` sulle ossa che cambiano.
static func crea(sk : Skeleton3D, percorso : String) -> Animation:
	var giu := Vector3.DOWN
	var avanti := Vector3.BACK          # i corpi guardano verso +Z in Godot
	var globali := {}
	for i in sk.get_bone_count():
		globali[i] = sk.get_bone_global_rest(i)
	var locali := {}
	for lato in ["Left", "Right"]:
		var b_spalla := sk.find_bone(lato + "UpperArm")
		var b_gomito := sk.find_bone(lato + "LowerArm")
		if b_spalla < 0 or b_gomito < 0:
			continue
		var gs : Transform3D = globali[b_spalla]
		var gg : Transform3D = globali[b_gomito]
		var d := (gg.origin - gs.origin).normalized()
		var fuori := Vector3(signf(d.x), 0.0, 0.0)
		var a := deg_to_rad(BRACCIA)
		var meta := (giu * cos(a) + fuori * sin(a)).normalized()
		var q_spalla := Quaternion(d, meta)
		var q_gomito := Quaternion(giu.cross(avanti).normalized(), deg_to_rad(GOMITI))
		var spalla := Basis(q_spalla) * gs.basis
		var gomito := Basis(q_gomito) * Basis(q_spalla) * gg.basis
		var genitore : Basis = (globali[sk.get_bone_parent(b_spalla)] as Transform3D).basis
		locali[b_spalla] = (genitore.inverse() * spalla).get_rotation_quaternion()
		locali[b_gomito] = (spalla.inverse() * gomito).get_rotation_quaternion()
	var anim := Animation.new()
	anim.length = DURATA
	anim.loop_mode = Animation.LOOP_LINEAR
	var ossa := locali.keys()
	for n in RESPIRO:
		var i := sk.find_bone(n)
		if i >= 0 and not ossa.has(i):
			ossa.append(i)
	for i in ossa:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [percorso, sk.get_bone_name(i)]))
		var base : Quaternion = locali.get(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
		var gradi : float = RESPIRO.get(sk.get_bone_name(i), 0.0)
		for k in [[0.0, 0.0], [DURATA / 2.0, 1.0], [DURATA, 0.0]]:
			var q := base * Quaternion(Vector3.RIGHT, deg_to_rad(gradi * k[1]))
			anim.rotation_track_insert_key(t, k[0], q)
	return anim
