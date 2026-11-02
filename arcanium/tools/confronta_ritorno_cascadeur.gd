extends SceneTree

## IL GIRO DA CASCADEUR, MISURATO: una clip mandata in Cascadeur, riggata e
## riesportata (rifinisci_clip_cascadeur.py) torna come era partita?
##
## Legge i due GLB a runtime con GLTFDocument (stanno in lavorazione/, che
## Godot non importa), campiona le tracce di ogni osso sullo scheletro del
## primo GLB e confronta le pose GLOBALI ricostruite dalle locali, frame per
## frame: posizione in centimetri e rotazione in gradi. Le pose si calcolano a
## mano dalla gerarchia, senza AnimationPlayer: in headless le pose lette da
## uno script SceneTree restavano a zero.
##
## Nata per lo scheletro ARP (pipeline nostra, 2026-11-02): la clip di prova di
## Zarine con le dita chiuse e la mano girata, prima e dopo il rig di Cascadeur.
##
## Uso: godot --headless --path . --script res://arcanium/tools/confronta_ritorno_cascadeur.gd -- <andata.glb> <ritorno.glb> [frame,frame,...]

const SOGLIA_CM := 0.5
const SOGLIA_GRADI := 1.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var andata := _carica(args[0])
	var ritorno := _carica(args[1])
	var sk : Skeleton3D = andata.find_children("*", "Skeleton3D", true, false)[0]
	var a := _clip(andata)
	var b := _clip(ritorno)
	print("andata %s: %.2f s, %d tracce | ritorno %s: %.2f s, %d tracce" % [
			a.resource_name, a.length, a.get_track_count(), b.resource_name, b.length, b.get_track_count()])
	var frames := []
	if args.size() > 2:
		for f in args[2].split(","):
			frames.append(int(f))
	else:
		for f in range(0, int(round(a.length * 30.0)) + 1, 5):
			frames.append(f)
	var peggio_cm := 0.0
	var peggio_gradi := 0.0
	for f in frames:
		var t : float = f / 30.0
		var ga := _globali(sk, a, t)
		var gb := _globali(sk, b, t)
		var righe := []
		for i in sk.get_bone_count():
			var d_cm : float = (ga[i].origin - gb[i].origin).length() * 100.0
			var q1 : Quaternion = ga[i].basis.get_rotation_quaternion()
			var q2 : Quaternion = gb[i].basis.get_rotation_quaternion()
			var d_g := rad_to_deg(q1.angle_to(q2))
			righe.append([d_cm, d_g, sk.get_bone_name(i)])
			peggio_cm = maxf(peggio_cm, d_cm)
			peggio_gradi = maxf(peggio_gradi, d_g)
		righe.sort_custom(func(x, y): return x[0] + x[1] * 0.1 > y[0] + y[1] * 0.1)
		var testa := righe.slice(0, 4).map(func(r): return "%s %.2f cm %.1f°" % [r[2], r[0], r[1]])
		print("frame %3d: %s" % [f, ", ".join(testa)])
	print("PEGGIORE: %.2f cm, %.2f gradi -> %s" % [peggio_cm, peggio_gradi,
			"OK" if peggio_cm < SOGLIA_CM and peggio_gradi < SOGLIA_GRADI else "DIVERSE"])
	quit()


func _carica(percorso : String) -> Node:
	var doc := GLTFDocument.new()
	var stato := GLTFState.new()
	var err := doc.append_from_file(percorso, stato)
	assert(err == OK, "non si legge %s" % percorso)
	var scena := doc.generate_scene(stato)
	root.add_child(scena)
	return scena


func _clip(scena : Node) -> Animation:
	var ap : AnimationPlayer = scena.find_children("*", "AnimationPlayer", true, false)[0]
	return ap.get_animation(ap.get_animation_list()[0])


## Le pose globali di tutte le ossa al tempo t: le locali dalla clip (o il
## riposo dove la clip non ha traccia), composte lungo la gerarchia.
func _globali(sk : Skeleton3D, anim : Animation, t : float) -> Array:
	var locali := []
	for i in sk.get_bone_count():
		locali.append(sk.get_bone_rest(i))
	for k in anim.get_track_count():
		var osso := sk.find_bone(String(anim.track_get_path(k).get_concatenated_subnames()))
		if osso < 0:
			continue
		var l : Transform3D = locali[osso]
		match anim.track_get_type(k):
			Animation.TYPE_ROTATION_3D:
				l.basis = Basis(anim.rotation_track_interpolate(k, t)).scaled(l.basis.get_scale())
			Animation.TYPE_POSITION_3D:
				l.origin = anim.position_track_interpolate(k, t)
			Animation.TYPE_SCALE_3D:
				l.basis = Basis(l.basis.get_rotation_quaternion()).scaled(anim.scale_track_interpolate(k, t))
		locali[osso] = l
	var globali := []
	globali.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		globali[i] = locali[i] if p < 0 else globali[p] * locali[i]
	return globali
