extends Node3D

## CANCELLO DI VERIFICA della frattura procedurale: una colonna VERA dell'Arena
## Senza Fuoco che crolla, guardata dalla camera di gioco.
##
## ⚠️ È la verifica che conta più di tutte, perché la frattura procedurale può
## fallire in modi che non danno nessun errore:
##   • frammenti APERTI (tappo mancante o girato) → si vede dentro, e sono neri;
##   • frammenti in miniatura → la scala del prop sta nel transform, non nella
##     mesh, e dimenticarla dà detriti da modellino ai piedi di una colonna;
##   • frammenti che partono dal posto sbagliato → la mesh è ricentrata sul
##     baricentro e va rimessa dov'era;
##   • frammenti che attraversano il pavimento → layer/maschera sbagliati.
## Nessuna di queste cose si vede leggendo il codice. Tutte si vedono qui.
##
## Lancio (niente --headless):
##   Godot_v4.7-stable_win64.exe --path . res://arcanium/tools/verifica_distruttibile.tscn --resolution 1600x900

const LIVELLO := "res://arcanium/levels/arena_senza_fuoco.tscn"
## Dove finiscono gli scatti: primo argomento utente, o la cartella utente.
var FUORI : String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()

const ISO_FOV := 50.0
## ⚠️ ZOOM DI GIOCO, non uno da vetrina. Durante la messa a punto l'ho tenuto a
## 0.42 per vedere i difetti da vicino, ed è utile — ma il giudizio finale si dà
## qui, allo zoom con cui si combatte davvero (`zoom_default` della IsoCam).
## Un dettaglio che si nota a 0.42 e sparisce a 0.82 non è un difetto da
## inseguire; uno che si nota a 0.82 lo è per forza.
const ISO_OFFSET := Vector3(0, 25.18, 25.18)
const ZOOM := 0.82

var _cam : Camera3D


func _ready() -> void:
	add_child(load(LIVELLO).instantiate())
	_cam = Camera3D.new()
	_cam.fov = ISO_FOV
	add_child(_cam)
	_cam.make_current()
	for _i in 30:
		await get_tree().physics_frame

	var comps := get_tree().get_nodes_in_group("distruttibile")
	print("[distr] distruttibili trovati: %d" % comps.size())
	if comps.is_empty():
		push_error("Nessun distruttibile: le colonne non sono state agganciate.")
		get_tree().quit(1)
		return

	var comp : OggettoDistruttibile = comps[0]
	var colonna : Node3D = comp.get_parent()
	## ⚠️ NON `colonna.global_position + su`: l'origine della colonna non è alla
	## sua base. Il builder la posiziona a `-aabb.position.y * scala`, che su
	## questa colonna vale +6 m — puntando lì si inquadrava il vuoto sopra il
	## capitello e i detriti restavano fuori campo. Il punto giusto è il centro
	## dell'ingombro reale in coordinate di mondo, e va preso PRIMA di romperla.
	var centro := Vector3.ZERO
	for mi0 in colonna.find_children("*", "MeshInstance3D", true, false):
		var m0 : MeshInstance3D = mi0
		if m0.mesh != null:
			centro = m0.global_transform * m0.mesh.get_aabb().get_center()
			break
	## Si guarda un po' più in basso del centro: dopo il crollo la roba sta a
	## terra, non a mezz'aria.
	centro.y *= 0.45
	print("[distr] colonna '%s' a %s  scala %s" %
			[colonna.name, colonna.global_position, colonna.scale])

	## Quanti triangoli ha, e quanti frammenti ne escono: se la frattura
	## restituisce zero pezzi il crollo non avviene e la colonna resta intera —
	## senza errori. Meglio saperlo qui che chiedersi perché non succede nulla.
	for mi in colonna.find_children("*", "MeshInstance3D", true, false):
		var m : MeshInstance3D = mi
		if m.mesh == null:
			continue
		Frattura.diagnostica = true
		var f := Frattura.spezza(m.mesh, comp.pezzi, 1)
		Frattura.diagnostica = false
		print("[distr]   mesh '%s': %d superfici, frattura di prova -> %d frammenti"
				% [m.name, m.mesh.get_surface_count(), f.size()])
		for k in mini(f.size(), 3):
			var fm : ArrayMesh = f[k]["mesh"]
			var facce := 0
			for s in fm.get_surface_count():
				facce += fm.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
			print("[distr]     frammento %d: %d superfici, %d triangoli, aabb %s"
					% [k, fm.get_surface_count(), facce, fm.get_aabb().size])

	await _scatta("distr_0_intera.png", centro)

	## Si rompe dal basso e di lato, come farebbe una palla d'energia arrivata
	## all'altezza del petto: la direzione dell'impatto decide da che parte
	## cascano i pezzi, e con un'origine centrata non si vedrebbe.
	comp.rompi(colonna.global_position + Vector3(-2.0, 1.2, 0.0))

	for quando in [0.20, 0.65, 1.60, 3.20, 5.00]:
		await get_tree().create_timer(quando).timeout
		await _scatta("distr_%.2f.png" % quando, centro)
		print("[distr] t=%.2f  corpi detrito vivi: %d" % [quando, _conta_detriti()])

	get_tree().quit()


## ⚠️ Contarli non basta, e su questo ho già sbagliato una diagnosi: ho preso i
## prop `column_broken` dell'arena per frammenti miei e ho inseguito un difetto
## che non c'era. Un frammento "vivo" può essere sotto il pavimento, grande come
## un francobollo o a cinquanta metri. Qui si stampa DOVE sta e QUANTO è grande.
func _conta_detriti() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if not (c is RigidBody3D):
			continue
		n += 1
		if n <= 4:
			var rb : RigidBody3D = c
			var mi : MeshInstance3D = rb.get_child(0) as MeshInstance3D
			var lato := "?"
			if mi != null and mi.mesh != null:
				lato = str((mi.mesh.get_aabb().size * rb.scale).snapped(Vector3.ONE * 0.01))
			print("[distr]    pezzo %d: pos %s  scala %.2f  ingombro %s  visibile %s"
					% [n, str(rb.global_position.snapped(Vector3.ONE * 0.1)),
					rb.scale.x, lato, str(rb.visible and (mi == null or mi.visible))])
	return n


func _scatta(nome : String, centro : Vector3) -> void:
	_cam.global_position = centro + ISO_OFFSET * ZOOM
	_cam.look_at(centro, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(FUORI + "/" + nome)
	print("[distr] %s" % nome)
