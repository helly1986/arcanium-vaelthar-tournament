extends Node

## Stampa la posizione (spazio armatura, in Godot) di alcune ossa a frame
## scelti: per confrontare una clip con la sua sorgente (Cascadeur/Blender) e
## capire se un bake ha spostato la posa. E' una SCENA: da `--script` la posa
## non si aggiorna.
##
##   godot --headless --path . res://arcanium/tools/posa_clip.tscn -- \
##       <clip.glb> <ossa,separate,da,virgola> <frame,separati,da,virgola>

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("uso: -- <clip.glb> <ossa> <frame>")
		get_tree().quit(2)
		return
	var inst : Node = (load(a[0]) as PackedScene).instantiate()
	add_child(inst)
	var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk : Skeleton3D = inst.find_child("Skeleton3D", true, false)
	var nome : String = ap.get_animation_list()[0]
	print("clip %s: %d ossa nello scheletro, radice=%s" % [nome, sk.get_bone_count(), sk.get_bone_name(0)])
	for f_s in str(a[2]).split(","):
		var f := int(f_s)
		ap.play(nome)
		ap.seek(f / 30.0, true)
		var riga := "f%-3d " % f
		for osso in str(a[1]).split(","):
			var b := sk.find_bone(osso)
			if b < 0:
				riga += "%s=ASSENTE  " % osso
				continue
			var g := sk.get_bone_global_pose(b).origin
			var l := sk.get_bone_pose_position(b)
			riga += "%s glob(%.2f %.2f %.2f) loc(%.2f %.2f %.2f)  " % [osso, g.x, g.y, g.z, l.x, l.y, l.z]
		print(riga)
	get_tree().quit(0)
