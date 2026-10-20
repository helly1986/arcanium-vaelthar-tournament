extends SceneTree

## Cancello delle TRAPPOLE A PIASTRA (trappola_piastra.gd).
##
## Parte A, la PIANTA su 60 semi: compaiono tutti e quattro i tipi; ogni bocca
## ha il muro dietro e pavimento libero fino alla piastra.
## Parte B, la COSTRUZIONE: per ogni tipo si mette il giocatore sulla piastra
## di un dungeon vero e si guarda che la piastra scatti e che il giocatore
## perda vita col tipo di danno giusto (il fulmine dopo l'avviso, i dardi e la
## palla dalla bocca).
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_piastre.gd

const Pianta := preload("res://arcanium/levels/dungeon/pianta_dungeon.gd")
const NOMI := ["fuoco", "fulmine", "ghiaccio", "veleno"]
const TIPI_DANNO := ["FUOCO", "FULMINE", "CRIO", "VELENO"]
const ATTESE := 6

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var profilo = load("res://arcanium/levels/dungeon/profilo_rovine.tres")
	var per_tipo := [0, 0, 0, 0]
	var bocche_male := 0
	var dove := [-1, -1, -1, -1]
	for s in range(1, 61):
		var p = Pianta.new()
		p.genera(profilo, s)
		for pz in p.piastre:
			per_tipo[pz["tipo"]] += 1
			if dove[pz["tipo"]] < 0:
				dove[pz["tipo"]] = s
			if pz["tipo"] == Pianta.Piastra.FULMINE:
				continue
			var d : Vector2i = pz["dir"]
			var q : Vector2i = pz["cella"]
			var ok : bool = p.cella(pz["bocca"] - d) == Pianta.Cella.VUOTO
			while ok and q != pz["bocca"]:
				q -= d
				ok = p.camminabile(q)
			if not ok:
				bocche_male += 1
	_ok(per_tipo.min() > 0, "compaiono tutti i tipi di piastra (fuoco, fulmine, ghiaccio, veleno: %s)" % str(per_tipo))
	_ok(bocche_male == 0, "ogni bocca ha il muro dietro e la via libera fino alla piastra (%d male)" % bocche_male)
	for k in 4:
		await _prova(k, dove[k])
	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti else 0)


func _prova(tipo : int, s : int) -> void:
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var d : Node = scena.get_node("Dungeon")
	d.seme = s
	d.mostra_fine = false
	root.add_child(scena)
	for i in 5:
		await physics_frame
	## I nemici fermi: si misura la trappola, non un lupo.
	for e in get_nodes_in_group("nemico_dungeon"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var piastra : Node3D = null
	for t in get_nodes_in_group("piastra_dungeon"):
		if t.tipo == tipo and t.is_inside_tree() and t.get_parent() == d:
			piastra = t
			break
	if piastra == null:
		_ok(false, "%s: una piastra nel seme %d" % [NOMI[tipo], s])
		scena.queue_free()
		return
	var g : Node3D = scena.get_node("Player")
	var hs = g.health_system
	var tipi := {}
	hs.damage_dealt.connect(func(_a, t): tipi[t] = true)
	var prima : float = hs._health_f
	g.global_position = piastra.global_position + Vector3(0, 0.3, 0)
	for i in 120:
		await physics_frame
	var dopo : float = hs._health_f
	_ok(piastra.scatti >= 1 and dopo < prima and tipi.has(TIPI_DANNO[tipo]),
			"%s (seme %d): la piastra scatta e il giocatore perde vita %.0f -> %.0f col danno %s" % [NOMI[tipo], s, prima, dopo, str(tipi.keys())])
	scena.queue_free()
	for i in 3:
		await process_frame
