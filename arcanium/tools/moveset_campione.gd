extends SceneTree

## Il MOVESET CONDIVISO portato sul corpo di un campione.
##
## I moveset dei campioni sono gli stessi (decisione dell'autore del
## 2026-10-21), ma le clip di MeleeLib sono cotte sullo scheletro del
## protagonista: suonate cosi' su un corpo con un riposo diverso escono storte
## (Kessra: braccia sparite nella idle). rig_retarget.gd le porta da uno
## scheletro all'altro passando per lo spazio del modello; qui lo si fa per
## tutta la libreria e la si salva accanto al corpo, in
## assets/characters/campioni/<nome>/meleelib.res. La selezione e il gioco
## usano quella.
##
## Uso: godot --headless --path . --script res://arcanium/tools/moveset_campione.gd -- <nome> [<nome> ...]
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const Retarget := preload("res://arcanium/tools/rig_retarget.gd")
const SORGENTE := "res://assets/characters/base_body/protagonista_v4.glb"
const LIBRERIA := "res://player/animation_libraries/MeleeLib.res"


func _init() -> void:
	await process_frame
	var nomi := OS.get_cmdline_user_args()
	var src_scena : Node = (load(SORGENTE) as PackedScene).instantiate()
	root.add_child(src_scena)
	var src : Skeleton3D = src_scena.find_children("*", "Skeleton3D", true, false)[0]
	var lib : AnimationLibrary = load(LIBRERIA)
	for nome in nomi:
		var glb := "res://assets/characters/campioni/%s/%s_rigged.glb" % [nome, nome]
		var dst_scena : Node = (load(glb) as PackedScene).instantiate()
		root.add_child(dst_scena)
		var dst : Skeleton3D = dst_scena.find_children("*", "Skeleton3D", true, false)[0]
		var nuova := AnimationLibrary.new()
		var t0 := Time.get_ticks_msec()
		for clip in lib.get_animation_list():
			var a : Animation = Retarget.retarget(lib.get_animation(clip), src, dst)
			## Le tracce puntano a `%GeneralSkeleton:<osso>` come quelle del
			## protagonista: lo scheletro del campione prende quel nome.
			nuova.add_animation(clip, a)
		var uscita := "res://assets/characters/campioni/%s/meleelib.res" % nome
		## Compressa: 123 clip a 60 fps sono 11 MB, compresse molto meno.
		var err := ResourceSaver.save(nuova, uscita, ResourceSaver.FLAG_COMPRESS)
		print("MOVESET: %s, %d clip in %.1f s -> %s (%s)" % [nome, nuova.get_animation_list().size(),
				(Time.get_ticks_msec() - t0) / 1000.0, uscita, error_string(err)])
		dst_scena.queue_free()
	quit()
