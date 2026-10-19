extends SceneTree

## Prova le tre soglie del danno da caduta lasciando cadere il player VERO su un
## pavimento, da altezze diverse. Non simula la formula: fa cadere il corpo e
## legge la vita rimasta, cosi' se un giorno cambia la gravita' o il modo in cui
## si misura la distanza, questa prova se ne accorge.
##
## La terza prova e' quella che conta di piu': un player che cade SENZA
## pavimento deve morire da solo. E' la rete contro i buchi nel terreno.
##
## ⚠️ Si aspettano i frame di FISICA, non quelli di process: in headless il gioco
## gira a briglia sciolta e i frame di process sono il doppio: contando quelli, la
## caduta sembrava non arrivare mai a terra e la prova falliva su un codice sano.
##
## Uso: godot --headless --script arcanium/tools/verifica_danno_caduta.gd

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"

func _init() -> void:
	await physics_frame
	var esito := 0
	esito = maxi(esito, await _prova(3.0,  "sotto la soglia", false, false))
	esito = maxi(esito, await _prova(12.0, "in mezzo",        true,  false))
	esito = maxi(esito, await _prova(25.0, "oltre il letale", true,  true))
	esito = maxi(esito, await _prova_vuoto())
	print("\nesito: ", "CADUTA SANA" if esito == 0 else "PROBLEMI")
	quit(esito)

func _mondo(con_pavimento : bool) -> Array:
	var mondo := Node3D.new()
	root.add_child(mondo)
	if con_pavimento:
		var suolo := StaticBody3D.new()
		var forma := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(60, 2, 60)
		forma.shape = box
		suolo.add_child(forma)
		mondo.add_child(suolo)
	var p = load(PLAYER).instantiate()
	mondo.add_child(p)
	return [mondo, p]

func _prova(altezza : float, nome : String, danno_atteso : bool, morte_attesa : bool) -> int:
	var m := _mondo(true)
	var mondo : Node3D = m[0]
	var p = m[1]
	p.global_position = Vector3(0, 1.0 + altezza, 0)
	var hs = p.health_system
	var vita0 : int = hs.current_health
	## Tempo di volo con margine: t = sqrt(2h/g), piu' mezzo secondo.
	var frame : int = int((sqrt(2.0 * altezza / 9.8) + 0.8) * 60.0)
	for i in frame:
		await physics_frame
	var vita1 : int = hs.current_health
	var morto : bool = p.is_dead or vita1 <= 0
	var danno : bool = vita1 < vita0
	var ok : bool = danno == danno_atteso and morto == morte_attesa
	print("  %-16s da %5.1f m: vita %d → %d, morto=%s  %s" % [
		nome, altezza, vita0, vita1, morto,
		"ok" if ok else "!! atteso danno=%s morte=%s" % [danno_atteso, morte_attesa]])
	mondo.queue_free()
	await physics_frame
	return 0 if ok else 1

func _prova_vuoto() -> int:
	var m := _mondo(false)
	var mondo : Node3D = m[0]
	var p = m[1]
	p.global_position = Vector3(0, 5, 0)
	## Piu' del fall_void_time del player, con margine.
	var limite : float = p.fall_void_time + 1.5
	for i in int(limite * 60.0):
		await physics_frame
	var morto : bool = p.is_dead or p.health_system.current_health <= 0
	print("  %-16s caduta senza pavimento per %.1f s: morto=%s  %s" % [
		"nel vuoto", limite, morto, "ok" if morto else "!! CADE ALL'INFINITO"])
	mondo.queue_free()
	return 0 if morto else 1
