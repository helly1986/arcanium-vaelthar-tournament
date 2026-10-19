extends SceneTree

## Ritratto ravvicinato di un PERSONAGGIO, da solo, fermo nella posa della scena.
##
##   "C:/Godot/Godot_v4.7.1-stable_win64_console.exe" --path . --rendering-method mobile ^
##       --script res://arcanium/tools/ritratto_personaggio.gd -- <scena.tscn> <quota_m> <distanza_m> <etichetta> [vivo]
##
## Scatta da +Z e da -Z (non si sa a priori dove guarda il modello), alla quota
## data, in arcanium/tools/prove/ritratto_<etichetta>_{piu,meno}_z.png.
## Nato per guardare il volto del Comandante DENTRO l'elmo (2026-10-02): nel
## livello i nemici si rigirano a ogni corsa, e una posa fissa non li prende.
## ⚠️ MAI --headless: serve un renderer vero.
## `vivo`: il personaggio resta acceso (gira l'idle, e la STOFFA SIMULATA si
## inizializza). Fermo, il solver della stoffa non parte e il mantello non si
## disegna: un mantello assente in un ritratto fermo NON e' un difetto del corpo.

func _initialize() -> void:
	_scatta.call_deferred()


func _scatta() -> void:
	var a := OS.get_cmdline_user_args()
	var scena : String = a[0]
	var quota := float(a[1])
	var dist := float(a[2])
	var etichetta : String = a[3]
	DisplayServer.window_set_size(Vector2i(1000, 1000))
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = env
	root.add_child(we)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-35, 20, 0)
	root.add_child(sole)
	## Il suolo: da `vivo` il personaggio ha la gravita'.
	var suolo := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 40)
	fs.shape = bx
	fs.position = Vector3(0, -0.5, 0)
	suolo.add_child(fs)
	root.add_child(suolo)
	var p : Node3D = (load(scena) as PackedScene).instantiate()
	var vivo := a.size() > 4 and a[4] == "vivo"
	if not vivo:
		p.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(p)
	var cam := Camera3D.new()
	cam.fov = 20.0
	root.add_child(cam)
	for lato in [["piu_z", 1.0], ["meno_z", -1.0]]:
		cam.look_at_from_position(Vector3(0, quota + 0.05, dist * float(lato[1])), Vector3(0, quota, 0), Vector3.UP)
		cam.current = true
		for i in (120 if vivo else 20):
			await process_frame
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("res://arcanium/tools/prove/ritratto_%s_%s.png" % [etichetta, lato[0]])
		img.save_png(out)
		print("scatto: ", out)
	quit(0)
