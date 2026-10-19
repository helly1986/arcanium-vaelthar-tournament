extends SceneTree

## Prova la sparizione degli ostacoli della IsoCam su una scena finta: un muro
## piazzato fra camera e player deve togliersi di mezzo, e TORNARE COM'ERA
## appena non da' piu' fastidio.
##
## La seconda meta' e' quella che conta: un sistema che nasconde e si dimentica
## di ripristinare lascia il livello coi buchi, ed e' un difetto che poi nessuno
## riesce a riprodurre perche' dipende da dove sei passato.
##
## Si provano ENTRAMBE le modalita': NASCONDI (default, funziona su qualunque
## renderer) e DISSOLVENZA (piu' bella ma dipende dal renderer). Provarne una
## sola lascerebbe l'altra a marcire.
##
## ⚠️ Il muro NON deve nascere addosso al player: si dissolverebbe nei primi
## frame e la "misura di partenza" varrebbe gia' 0.78, facendo dire alla prova
## "non si e' dissolto" mentre il sistema funziona.
##
## Uso: godot --headless --script arcanium/tools/verifica_occlusioni.gd

const IsoCamScene := "res://cameras/iso_cam/iso_cam.tscn"
const LONTANO := Vector3(200.0, 0.0, 0.0)


func _init() -> void:
	await process_frame
	var esito := 0
	esito = maxi(esito, await _prova(1, "NASCONDI"))
	esito = maxi(esito, await _prova(0, "DISSOLVENZA"))
	print("esito: ", "OCCLUSIONI SANE" if esito == 0 else "PROBLEMI")
	quit(esito)


func _prova(modo : int, nome : String) -> int:
	var esito := 0
	var mondo := Node3D.new()
	root.add_child(mondo)

	var player := CharacterBody3D.new()
	player.add_child(_forma(Vector3(0.5, 1.0, 0.5)))
	mondo.add_child(player)
	player.global_position = Vector3.ZERO

	var muro := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12.0, 12.0, 1.0)
	mesh.mesh = box
	muro.add_child(mesh)
	mondo.add_child(muro)
	muro.global_position = LONTANO

	var cam : Node3D = load(IsoCamScene).instantiate()
	cam.target = player
	cam.occluder_mode = modo
	cam.occluder_fade_speed = 20.0
	cam.occluder_scan_interval = 0.05
	mondo.add_child(cam)
	for i in 10:
		await physics_frame

	print("--- %s ---" % nome)
	print("  candidati trovati in scena: %d" % cam._candidati.size())
	if cam._candidati.is_empty():
		print("   LA SCANSIONE NON HA TROVATO LA MESH DEL MURO")
		esito = 1

	var camera : Camera3D = cam.camera_3d
	var meta : Vector3 = (camera.global_position + player.global_position + Vector3.UP) * 0.5
	var prima := _stato(mesh, modo)
	muro.global_position = meta
	for i in 40:
		await physics_frame
	var durante := _stato(mesh, modo)
	muro.global_position = LONTANO
	for i in 40:
		await physics_frame
	var dopo := _stato(mesh, modo)

	print("  prima %.2f → col muro davanti %.2f → tolto di mezzo %.2f" % [
		prima, durante, dopo])
	if durante <= prima + 0.01:
		print("   IL MURO NON SI E' TOLTO DI MEZZO")
		esito = 1
	if absf(dopo - prima) > 0.001:
		print("   NON E' TORNATO COM'ERA")
		esito = 1
	if not cam._occlusi.is_empty():
		print("   RESTA REGISTRATO come occluso: %d voci" % cam._occlusi.size())
		esito = 1

	mondo.queue_free()
	await process_frame
	return esito


## Quanto l'ostacolo si e' tolto di mezzo, 0 = del tutto presente. Le due
## modalita' agiscono su proprieta' diverse, ma la domanda e' la stessa.
func _stato(mesh : MeshInstance3D, modo : int) -> float:
	if modo == 1:
		return 0.0 if mesh.visible else 1.0
	return mesh.transparency


func _forma(mezze: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = mezze * 2.0
	cs.shape = b
	return cs
