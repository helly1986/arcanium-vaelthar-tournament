extends Node

## ═══════════════════════════════════════════════════════════════════════════
## PROFILO DI VELOCITA' DI UNA CLIP — per capire PERCHE' il misuratore sbaglia
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . res://arcanium/tools/profilo_clip.tscn -- \
##       res://assets/characters/enemies/anims/sword/sword_th_combo_01.glb Prop_Attachment_R
##
## Stampa, frame per frame, la velocita' dell'osso che colpisce come PERCENTUALE
## del picco della clip: e' la stessa grandezza su cui `measure_attack_contacts`
## decide cosa e' un colpo (regioni sopra FAST_RATIO del picco). Quando il
## misuratore "perde" un colpo o ne inventa uno, questo dice se e' un problema
## di soglia, di rientro veloce, o di clip.
##
## ⚠️ E' una SCENA, non un `--script`: dentro `_init` di un SceneTree la posa
## dello scheletro non si aggiorna nemmeno con `seek(t, true)`, e il profilo
## esce tutto a zero. Da un nodo in scena si'.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("uso: -- <clip.glb> <osso>")
		get_tree().quit(2)
		return
	var inst : Node = (load(args[0]) as PackedScene).instantiate()
	add_child(inst)
	var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk : Skeleton3D = inst.find_child("Skeleton3D", true, false)
	var nome : String = ap.get_animation_list()[0]
	var anim := ap.get_animation(nome)
	var b := sk.find_bone(args[1])
	if b < 0:
		push_error("osso assente: " + args[1])
		get_tree().quit(1)
		return
	var step := 1.0 / 240.0
	var prev := Vector3.ZERO
	var have := false
	var t := 0.0
	var vmax := 0.0
	var per_frame := {}
	while t <= anim.length:
		ap.play(nome)
		ap.seek(t, true)
		var p : Vector3 = sk.get_bone_global_pose(b).origin
		if have:
			var v := p.distance_to(prev) / step
			var f := int(round(t * 30.0))
			per_frame[f] = maxf(per_frame.get(f, 0.0), v)
			vmax = maxf(vmax, v)
		prev = p
		have = true
		t += step
	print("clip %s (%.2f s)  osso %s  picco %.2f m/s" % [nome, anim.length, args[1], vmax])
	var riga := ""
	var frame_tot := int(round(anim.length * 30.0))
	for f in range(0, frame_tot + 1):
		var v : float = per_frame.get(f, 0.0)
		riga += "f%-3d%3d%%  " % [f, int(round(100.0 * v / maxf(vmax, 0.001)))]
		if f % 10 == 9:
			print(riga)
			riga = ""
	if riga != "":
		print(riga)
	get_tree().quit(0)
