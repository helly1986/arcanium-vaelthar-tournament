extends SceneTree

## Le SCINTILLE DELL'IDLE (scintille_idle.gd): Kessra nel dungeon di prova,
## senza nemici.
##   1. ferma per due giri d'idle: partono due volte;
##   2. si mette a camminare poco prima del giro di vite: in cammino non
##      partono, e al rientro l'idle riparte dalla Posa;
##   3. tira un fendente poco prima: sotto il colpo non partono;
##   4. Rashan, che non le ha, non ha il nodo.
##
## Uso (APPDATA isolato, --fixed-fps 60):
##   godot --headless --path . --fixed-fps 60 --script res://arcanium/tools/verifica_scintille_idle.gd

const GIRO := 6.0

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var pl := await _scena("vorrkai")
	var albero = pl.animation_tree
	var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")
	var s = sk.get_node_or_null("ScintilleIdle")
	_ok(s != null and s.bone_name == "LeftIndexDistal" and s.momento > 0.0,
			"Kessra ha le scintille sull'indice sinistro (%s)" % (s.momento if s != null else "-"))
	if s == null:
		_fine()
		return

	await _a_tempo(albero, 0.1)
	s.partite = 0
	await _fisica(int(GIRO * 2 * 60))
	_ok(s.partite == 2, "ferma per due giri: partite %d volte (attese 2)" % s.partite)

	await _a_tempo(albero, s.momento - 0.3)
	s.partite = 0
	Input.action_press("move_up")
	await _fisica(120)
	var in_cammino : int = s.partite
	Input.action_release("move_up")
	await _fisica(30)
	_ok(in_cammino == 0, "in cammino sul giro di vite: partite %d volte" % in_cammino)
	_ok(albero.tempo_idle() < s.momento, "al rientro l'idle riparte dalla Posa (%.2f s)" % albero.tempo_idle())

	await _a_tempo(albero, s.momento - 0.25)
	s.partite = 0
	pl.attack()
	await _fisica(40)
	_ok(s.partite == 0, "sotto un fendente sul giro di vite: partite %d volte" % s.partite)

	var radice := pl.get_parent()
	root.remove_child(radice)
	radice.free()
	await process_frame
	var rashan := await _scena("amareth")
	var sk_r : Skeleton3D = rashan.get_node("protagonist/BaseArmature/GeneralSkeleton")
	_ok(sk_r.get_node_or_null("ScintilleIdle") == null, "Rashan non ha il nodo delle scintille")
	_fine()


func _scena(casa : String) -> Node:
	var salva : Node = root.get_node("SaveManager")
	salva._house = casa
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 40:
		await process_frame
	for e in get_nodes_in_group("nemico_dungeon"):
		e.queue_free()
	await _fisica(60)
	return scena.get_node("Player")


## Aspetta l'idle visibile a questo tempo del giro.
func _a_tempo(albero, t : float) -> void:
	for k in 1200:
		await physics_frame
		var ora : float = albero.tempo_idle()
		if ora >= 0.0 and absf(ora - t) < 0.02:
			return


func _fisica(n : int) -> void:
	for k in n:
		await physics_frame


func _fine() -> void:
	if _fatti < 6:
		_falliti += 1
		print("NO    eseguiti %d controlli su 6 attesi" % _fatti)
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
