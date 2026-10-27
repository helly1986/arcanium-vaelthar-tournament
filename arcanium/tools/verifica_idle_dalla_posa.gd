extends SceneTree

## L'IDLE RIPARTE DALLA POSA (player_anim_tree.gd, `_tieni_idle_alla_posa`):
## Kessra nel dungeon di prova, senza nemici, lascia scorrere la sua idle fino
## al martello alzato e poi
##   1. cammina un secondo e si ferma: l'idle deve rientrare dal fotogramma 0;
##   2. da ferma tira un fendente: finito il colpo, l'idle riparte da 0;
##   3. controprova col meccanismo spento: deve rientrare a meta' giro, o
##      questa verifica non distingue niente.
##
## Si legge il tempo dell'idle nell'albero nel primo fotogramma in cui torna a
## pesare (lo spazio di fusione sotto IDLE_SPARITA, nessun gesto pieno).
##
## Uso (APPDATA isolato, --fixed-fps 60):
##   godot --headless --path . --fixed-fps 60 --script res://arcanium/tools/verifica_idle_dalla_posa.gd

const CASA := "vorrkai"
## Il martello di Kessra e' alzato fra 3,7 e 5,3 s.
const META_GIRO := 4.2
## Il rientro conta come "dalla Posa" entro questo tempo dell'idle: il primo
## fotogramma visibile ha gia' fatto un passo.
const TOLLERANZA := 0.1

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	salva._house = CASA
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 40:
		await process_frame
	for e in get_nodes_in_group("nemico_dungeon"):
		e.queue_free()
	var pl : Node = scena.get_node("Player")
	var albero = pl.animation_tree
	var tempo := "parameters/MovementStates/%s_tree/MoveStrafe/%s/Idle/current_position"
	var punto := _punto_idle(albero)
	_ok(punto != "", "l'idle e' avvolta nel TimeSeek (%s)" % albero._idle_seek)
	if punto == "":
		_fine()
		return
	tempo = tempo % [albero.weapon_type, punto]

	for spento in [false, true]:
		albero.idle_dalla_posa = not spento
		var nome := "controprova, meccanismo spento: " if spento else ""
		await _fermo(META_GIRO)
		var prima : float = albero.get(tempo)
		Input.action_press("move_up")
		await _fisica(60)
		Input.action_release("move_up")
		var rientro : float = await _rientro(albero, tempo)
		if spento:
			_ok(rientro > 1.0, "%sfermandosi l'idle rientra a %.2f s (era a %.2f): la verifica vede il difetto" % [nome, rientro, prima])
		else:
			_ok(rientro < TOLLERANZA, "fermandosi dopo un secondo di cammino l'idle rientra a %.2f s (era a %.2f)" % [rientro, prima])
		await _fermo(0.5)
		var dopo : float = albero.get(tempo)
		if not spento:
			_ok(dopo > 0.3, "poi scorre: %.2f s mezzo secondo dopo" % dopo)

		await _fermo(META_GIRO)
		prima = albero.get(tempo)
		pl.attack()
		await _fisica(2)
		var colpo : bool = albero.get("parameters/Attack/active")
		## Il rientro si cerca dopo che il colpo ha coperto l'idle: durante la
		## sfumatura d'ingresso (0,2 s) l'idle si vede ancora.
		await _fisica(int(albero.tree_root.get_node("Attack").fadein_time * 60.0) + 2)
		rientro = await _rientro(albero, tempo)
		if spento:
			_ok(colpo and rientro > 1.0, "%sdopo il fendente l'idle rientra a %.2f s (era a %.2f)" % [nome, rientro, prima])
		else:
			_ok(colpo and rientro < TOLLERANZA, "dopo il fendente (partito: %s) l'idle rientra a %.2f s (era a %.2f)" % [colpo, rientro, prima])
	albero.idle_dalla_posa = true
	_fine()


func _fine() -> void:
	if _fatti < 6:
		_falliti += 1
		print("NO    eseguiti %d controlli su 6 attesi" % _fatti)
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


func _punto_idle(albero) -> String:
	var chiave : String = albero.weapon_type + "_tree"
	if not albero._idle_seek.has(chiave):
		return ""
	return String(albero._idle_seek[chiave]).get_slice("/MoveStrafe/", 1).get_slice("/", 0)


func _fisica(n : int) -> void:
	for k in n:
		await physics_frame


## Fermo per `secondi` di idle visibile.
func _fermo(secondi : float) -> void:
	await _fisica(int(secondi * 60.0))


## Aspetta il primo fotogramma in cui l'idle torna a vedersi e ne da' il tempo.
func _rientro(albero, tempo : String) -> float:
	for k in 600:
		await physics_frame
		if not albero.idle_nascosta():
			return albero.get(tempo)
	return -1.0
