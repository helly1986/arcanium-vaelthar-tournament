extends Node3D

## Anteprima di un CORPO DI SPIRITO (corpo_spirito.gd): lo mette in scena e
## fotografa le pose che contano, affiancate, per guardarle invece di
## immaginarle.
##
##   Godot.exe --path . --rendering-method mobile res://arcanium/tools/anteprima_spirito.tscn -- <cartella> [clip1,clip2,...]
##
## Senza clip: quattro stati del corpo — a riposo, in corsa (velocita' piena),
## lembi allargati, a meta' dissoluzione. Con le clip (nomi della libreria di
## `eco_clip.gd`): per ogni clip tre scatti, a un quarto, a meta' e a tre quarti.
##
## ⚠️ NON `--headless`: lo shader lavora nel vertex, e in headless non si vede.

const CorpoSpirito := preload("res://arcanium/systems/spiriti/corpo_spirito.gd")
const EcoClip := preload("res://arcanium/systems/spiriti/eco_clip.gd")
const MODELLO := "res://assets/characters/summons/sylvorn/eco_radicata.glb"

var _cartella := ""


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var args := OS.get_cmdline_user_args()
	_cartella = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	var clip : PackedStringArray = str(args[1]).split(",") if args.size() > 1 else PackedStringArray()

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.1)
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	add_child(env)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sole)
	var suolo := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	suolo.mesh = pm
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.16, 0.17, 0.15)
	suolo.material_override = ms
	add_child(suolo)

	var corpo := CharacterBody3D.new()
	add_child(corpo)
	var spirito := CorpoSpirito.new()
	spirito.name = "Model"
	spirito.modello = load(MODELLO)
	corpo.add_child(spirito)
	## Guarda la camera, di tre quarti.
	corpo.rotation.y = deg_to_rad(-35.0)
	var ap := AnimationPlayer.new()
	spirito.add_child(ap)
	ap.add_animation_library("", EcoClip.libreria())

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.05, 2.1), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	cam.fov = 50.0
	cam.current = true

	for i in 30:
		await get_tree().process_frame

	if clip.is_empty():
		var stati := [["riposo", Vector3.ZERO, 0.0, 0.0], ["corsa", Vector3(0, 0, 3.5), 0.0, 0.0],
			["strappo", Vector3.ZERO, 1.0, 0.0], ["dissolvi", Vector3.ZERO, 0.0, 0.5]]
		for s in stati:
			corpo.velocity = corpo.global_basis * (s[1] as Vector3)
			spirito.strappo = s[2]
			spirito.dissolvi = s[3]
			for i in 45:
				await get_tree().process_frame
			await _scatta("spirito_%s" % s[0])
	else:
		for c in clip:
			if not ap.has_animation(c):
				push_error("clip %s non c'e'" % c)
				continue
			var lun := ap.get_animation(c).length
			for f in [0.25, 0.5, 0.75]:
				ap.play(c)
				ap.seek(lun * f, true)
				ap.pause()
				for i in 3:
					await get_tree().process_frame
				await _scatta("spirito_%s_%02d" % [c, int(f * 100)])
	get_tree().quit()


func _scatta(nome : String) -> void:
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [_cartella, nome]
	get_viewport().get_texture().get_image().save_png(p)
	print("scatto ", p)
