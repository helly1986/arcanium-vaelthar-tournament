extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## CLIP DA GLB — una clip dei nemici in mano al protagonista
## ═══════════════════════════════════════════════════════════════════════════
##
## Le clip di `assets/characters/enemies/anims/` sono autorate sul rig
## Nephilite e importate con la bone map: dentro il GLB le tracce si chiamano
## `<Skeleton>:<osso>` con i nomi Humanoid. Il protagonista ha lo stesso
## scheletro (docs/05_RIG_CANONICO.md: una sola convenzione di ossa) ma lo
## raggiunge come `%GeneralSkeleton`: qui si tiene il nome dell'osso, si cambia
## il prefisso, e si butta ciò che il player non ha.
##
## Nato in `tecnica_guerra_caster.gd` per la Testuggine; estratto il 2026-09-13
## quando l'arco del protagonista ha avuto bisogno della stessa cosa
## (regola: si estrae solo cio' che e' gia' duplicato). Si importa per path:
##     const ClipDaGlb := preload("res://arcanium/systems/clip_da_glb.gd")

const PREFISSO_SCHELETRO := "%GeneralSkeleton"


## L'AnimationPlayer dietro un AnimationTree, o null.
static func anim_player(anim_tree : AnimationTree) -> AnimationPlayer:
	if anim_tree == null:
		return null
	return anim_tree.get_node_or_null(anim_tree.anim_player) as AnimationPlayer


## Lo scheletro che l'AnimationPlayer anima: `GeneralSkeleton` sotto la sua radice.
static func scheletro(anim_tree : AnimationTree) -> Skeleton3D:
	var ap := anim_player(anim_tree)
	if ap == null:
		return null
	var radice := ap.get_node_or_null(ap.root_node)
	if radice == null:
		return null
	return radice.find_child("GeneralSkeleton", true, false) as Skeleton3D


## La prima clip del GLB, riscritta sulle ossa di `sk`. Null se il GLB non
## esiste, non ha animazioni, o nessuna traccia trova il suo osso.
##
## ⚠️ COMPLETATA con il riposo del rig dei nemici. L'import butta le tracce
## immutabili (`remove_immutable_tracks`): `sword_cast_01` arriva con 25 ossa
## su 79, e le altre — mani, dita, piedi, cio' che in quella clip sta fermo —
## sul nemico restano al SUO riposo, che e' la stance di combattimento e si
## vede giusto. Sul player un osso senza traccia, in uno slot non filtrato,
## cade al riposo del PLAYER, che e' una T-pose: braccia larghe a meta' tiro.
## Per ogni osso del player che la clip non anima si aggiunge una chiave con
## la rotazione di riposo del rig del nemico, letta dal GLB stesso. Con
## `completa = false` si lascia com'era (uno slot filtrato non ne ha bisogno).
static func carica(glb : String, sk : Skeleton3D, loop : bool = false, completa : bool = true) -> Animation:
	if sk == null or glb == "" or not ResourceLoader.exists(glb):
		return null
	var scn : PackedScene = load(glb)
	if scn == null:
		return null
	var inst := scn.instantiate()
	var cap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if cap == null or cap.get_animation_list().is_empty():
		inst.queue_free()
		return null
	var src : Animation = cap.get_animation(cap.get_animation_list()[0])
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracce := 0
	var ruotate := {}
	for i in src.get_track_count():
		var p := str(src.track_get_path(i))
		var due_punti := p.find(":")
		if due_punti < 0:
			continue
		var osso := p.substr(due_punti + 1)
		if sk.find_bone(osso) < 0:
			continue
		var tipo := src.track_get_type(i)
		if tipo == Animation.TYPE_ROTATION_3D:
			ruotate[osso] = true
		var j := anim.add_track(tipo)
		anim.track_set_path(j, NodePath("%s:%s" % [PREFISSO_SCHELETRO, osso]))
		anim.track_set_interpolation_type(j, src.track_get_interpolation_type(i))
		for k in src.track_get_key_count(i):
			var tempo := src.track_get_key_time(i, k)
			## `track_get_key_value` legge qualunque tipo (Vector3 / Quaternion
			## per le tracce 3D); in scrittura invece esistono solo i metodi
			## tipizzati — `position_track_get_key` &c. NON esistono.
			var valore = src.track_get_key_value(i, k)
			match tipo:
				Animation.TYPE_POSITION_3D:
					anim.position_track_insert_key(j, tempo, valore)
				Animation.TYPE_ROTATION_3D:
					anim.rotation_track_insert_key(j, tempo, valore)
				Animation.TYPE_SCALE_3D:
					anim.scale_track_insert_key(j, tempo, valore)
				_:
					anim.track_insert_key(j, tempo, valore)
		tracce += 1
	if completa and tracce > 0:
		var sk_nemico : Skeleton3D = null
		for n in inst.find_children("*", "Skeleton3D", true, false):
			sk_nemico = n
			break
		if sk_nemico != null:
			for b in sk_nemico.get_bone_count():
				var osso := sk_nemico.get_bone_name(b)
				if ruotate.has(osso) or sk.find_bone(osso) < 0:
					continue
				var j := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(j, NodePath("%s:%s" % [PREFISSO_SCHELETRO, osso]))
				anim.rotation_track_insert_key(j, 0.0, sk_nemico.get_bone_rest(b).basis.get_rotation_quaternion())
	inst.queue_free()
	return anim if tracce > 0 else null


## La libreria `nome` dell'AnimationPlayer, creata se manca.
static func libreria(ap : AnimationPlayer, nome : String) -> AnimationLibrary:
	if ap.has_animation_library(nome):
		return ap.get_animation_library(nome)
	var lib := AnimationLibrary.new()
	ap.add_animation_library(nome, lib)
	return lib


## Mette (o sostituisce) `anim` come `Libreria/nome`.
static func registra(lib : AnimationLibrary, nome : String, anim : Animation) -> void:
	if lib.has_animation(nome):
		lib.remove_animation(nome)
	lib.add_animation(nome, anim)
