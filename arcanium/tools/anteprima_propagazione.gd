extends SceneTree

## La PROPAGAZIONE DELL'EQUILIBRIO fotografata con la camera di gioco: Zarine nel
## dungeon vero, la tecnica lanciata dal suo caster, i fotogrammi dall'impatto in poi.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_propagazione.gd -- <cartella>

const MOMENTI := [0.08, 0.22, 0.42, 0.62, 0.95, 1.4]


func _init() -> void:
	var dove : String = OS.get_cmdline_user_args()[0]
	await process_frame
	root.get_node("SaveManager")._house = "aethon"
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 60:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	print("lancia: ", pl.lucida_tecnica_caster.lancia())
	var onda : Node = null
	var attesa := 0.0
	while onda == null and attesa < 4.0:
		await process_frame
		attesa += get_root().get_process_delta_time()
		for n in scena.get_children():
			if String(n.name).begins_with("PropagazioneEquilibrio"):
				onda = n
	print("impatto dopo %.2f s" % attesa)
	var inizio := Time.get_ticks_msec()
	for k in MOMENTI.size():
		while (Time.get_ticks_msec() - inizio) / 1000.0 < MOMENTI[k]:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dove.path_join("onda_%d.png" % k))
	quit()
