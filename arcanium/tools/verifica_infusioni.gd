extends SceneTree

## Cancello delle INFUSIONI (Edran, Rashan, Kessra) e degli status che portano, col player
## vero, un nemico vero e il colpo vero dell'arma (EquipmentSystem._apply_hit):
##   Baluardo del Freddo: i fendenti congelano; da congelato rallenta; insistendo si
##     accumula Ghiacciato: immobile davvero, -5 HP al secondo per 10 s.
##   Comando del Tuono: Shock toglie il 20% degli HP e la soglia sale; da Bagnato toglie il
##     25% e la soglia torna quella di partenza. L'acqua dei dungeon bagna.
##   Infusione della Fucina: Bruciatura; il fuoco arresta l'Emorragia e scioglie
##     Congelamento e Ghiacciato, anche solo come danno di tipo FUOCO.
##   Per tutte: costo, durata di 5 minuti, solo con l'arma infusa in mano, poi finisce.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_infusioni.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const VITA := 100000

var _falliti := 0


class ColpoDiFuoco extends Resource:
	var power : float = 1.0
	var damage_type : String = "FUOCO"


class ColpoBagnato extends Resource:
	var power : float = 1.0
	var damage_type : String = "FISICO"
	var inflicts_wet : bool = true


func _ok(cond : bool, cosa : String) -> void:
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _prepara(casa : String) -> Array:
	root.get_node("SaveManager")._house = casa
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 15:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var nemico : CharacterBody3D = null
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D:
			if nemico == null and n.get("health_system") != null:
				nemico = n
			n.set_physics_process(n == nemico and false)
	nemico.health_system.total_health = VITA
	nemico.health_system.current_health = VITA
	nemico.health_system.set("_health_f", float(VITA))
	nemico.global_position = pl.global_transform * Vector3(0.0, 0.0, 2.0)
	return [scena, pl, nemico]


func _infondi(pl : Node3D, t : Resource) -> void:
	var caster : Node = pl.lucida_tecnica_caster
	var arc : float = pl.vitals.arcanium
	_ok(caster.lancia(), "%s: il gesto parte" % t.name)
	_ok(is_equal_approx(arc - pl.vitals.arcanium, t.costo), "%s: spende %.0f Arcanium" % [t.name, t.costo])
	var attesa := 0.0
	while attesa < 3.0 and caster._infusione == null:
		await physics_frame
		attesa += 1.0 / 60.0
	_ok(caster.infusione_attiva(), "%s: l'arma e' infusa (dopo %.2f s)" % [t.name, attesa])
	_ok(absf(caster._infusione_fino - caster._adesso() - 300.0) < 5.0, "%s: per 5 minuti" % t.name)
	_ok(is_instance_valid(caster._infusione_vfx), "%s: si vede sull'arma" % t.name)


func _fendente(pl : Node3D, nemico : Node) -> void:
	var armi : Node = pl.get_node("WeaponSystem")
	armi._hit_this_swing.clear()
	armi._apply_hit(nemico)


func _chiudi(scena : Node) -> void:
	root.remove_child(scena)
	scena.free()
	await process_frame


func _init() -> void:
	await process_frame
	await _edran()
	await _rashan()
	await _kessra()
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


func _edran() -> void:
	var s : Array = await _prepara("dawnkeep")
	var scena : Node = s[0]
	var pl : Node3D = s[1]
	var nemico : CharacterBody3D = s[2]
	var caster : Node = pl.lucida_tecnica_caster
	var t : Resource = caster.tecnica_corrente()
	_ok(t != null and t.name == "Baluardo del Freddo", "Edran: Baluardo del Freddo")
	var host : Node = nemico.health_system.status_host
	## Senza infusione il fendente non congela.
	_fendente(pl, nemico)
	_ok(host.get_effect("frozen") == null, "senza infusione il fendente non congela")
	await _infondi(pl, t)
	_ok(not caster.lancia(), "appena infusa non si rilancia, e non si spreca il costo")
	var colpi := 0
	while colpi < 10 and not host.get_effect("frozen") is Object:
		_fendente(pl, nemico)
		colpi += 1
	while colpi < 10 and not host.get_effect("frozen").is_active():
		_fendente(pl, nemico)
		colpi += 1
	_ok(host.get_effect("frozen").is_active(), "congelato dopo %d fendenti" % colpi)
	_ok(host.moltiplicatore_velocita() < 1.0, "e rallentato (%.2f)" % host.moltiplicatore_velocita())
	var altri := 0
	while altri < 10 and not host.is_ghiacciato():
		_fendente(pl, nemico)
		altri += 1
	_ok(host.is_ghiacciato(), "Ghiacciato dopo altri %d fendenti" % altri)
	_ok(host._mesh_corpo.size() >= 1 and host._mesh_corpo[0].material_overlay != null, "e si vede sul corpo")
	## Immobile davvero: col suo processo acceso, velocita' chiesta o no, non si sposta.
	nemico.set_physics_process(true)
	var dove : Vector3 = nemico.global_position
	var vita0 : float = float(nemico.health_system.current_health)
	await create_timer(4.0).timeout
	var persa : float = vita0 - float(nemico.health_system.current_health)
	_ok(Vector2(nemico.global_position.x - dove.x, nemico.global_position.z - dove.z).length() < 0.05, "immobile mentre e' Ghiacciato")
	_ok(nemico.anim_player.speed_scale == 0.0, "con le clip ferme")
	_ok(persa >= 15.0 and persa <= 25.0, "perde 5 HP al secondo (-%.0f in 4 s)" % persa)
	await create_timer(6.5).timeout
	_ok(not host.is_ghiacciato(), "dopo 10 s finisce")
	_ok(host._mesh_corpo.is_empty(), "e la pellicola se ne va")
	_ok(nemico.anim_player.speed_scale == 1.0, "e le clip ripartono")
	nemico.set_physics_process(false)
	## Solo con l'arma infusa in mano.
	var armadio : Node = root.get_node("EquipmentLoadout")
	armadio.equip("arma_riserva", load("res://arcanium/resources/weapons/lama_ricurva.tres"))
	armadio.cambia_set()
	await process_frame
	_ok(not caster.infusione_attiva(), "con l'altra arma in mano l'infusione non vale")
	armadio.cambia_set()
	await process_frame
	_ok(caster.infusione_attiva(), "e torna con l'arma infusa")
	## Allo scadere finisce.
	caster._infusione_fino = caster._adesso() - 1.0
	await physics_frame
	await physics_frame
	_ok(not caster.infusione_attiva() and caster._infusione == null, "allo scadere finisce")
	await _chiudi(scena)


func _rashan() -> void:
	var s : Array = await _prepara("amareth")
	var scena : Node = s[0]
	var pl : Node3D = s[1]
	var nemico : CharacterBody3D = s[2]
	var t : Resource = pl.lucida_tecnica_caster.tecnica_corrente()
	_ok(t != null and t.name == "Comando del Tuono", "Rashan: Comando del Tuono")
	var host : Node = nemico.health_system.status_host
	var salute : Node = nemico.health_system
	await _infondi(pl, t)
	var colpi := 0
	while colpi < 12 and (host.get_effect("shock") == null or host.get_effect("shock").extra == 0.0):
		_fendente(pl, nemico)
		colpi += 1
	var shock = host.get_effect("shock")
	_ok(shock != null and shock.extra > 0.0, "Shock dopo %d fendenti" % colpi)
	var perso : float = float(VITA) - float(salute.current_health)
	_ok(perso >= VITA * 0.20 and perso <= VITA * 0.205, "toglie il 20%% degli HP (%.0f su %d)" % [perso, VITA])
	var soglia1 : float = shock.soglia()
	_ok(soglia1 > shock.soglia_base, "la soglia del prossimo sale (%.0f)" % soglia1)
	## Da asciutto sale ancora.
	shock.meter = soglia1 - 1.0
	await create_timer(0.6).timeout
	_fendente(pl, nemico)
	_ok(shock.soglia() > soglia1, "e sale ancora (%.0f)" % shock.soglia())
	## L'acqua del dungeon bagna.
	var acqua : Area3D = load("res://arcanium/levels/dungeon/acqua_dungeon.gd").new()
	scena.add_child(acqua)
	acqua._dentro(nemico)
	var bagnato = host.get_effect("bagnato")
	_ok(bagnato != null and bagnato.is_active(), "l'acqua del dungeon bagna")
	acqua.queue_free()
	## Da bagnato: 25% e soglia azzerata.
	await create_timer(0.6).timeout
	var vita_prima : float = float(salute.current_health)
	shock.meter = shock.soglia() - 1.0
	_fendente(pl, nemico)
	var tolto : float = vita_prima - float(salute.current_health)
	_ok(tolto >= VITA * 0.25 and tolto <= VITA * 0.255, "da bagnato toglie il 25%% degli HP totali (%.0f)" % tolto)
	_ok(shock.extra == 0.0 and shock.soglia() == shock.soglia_base, "e la soglia torna quella di partenza")
	## Anche i colpi possono bagnare.
	host.cura("bagnato")
	bagnato.termina()
	salute._route_statuses(ColpoBagnato.new())
	_ok(bagnato.is_active(), "anche un colpo con `inflicts_wet` bagna")
	await _chiudi(scena)


func _kessra() -> void:
	var s : Array = await _prepara("vorrkai")
	var scena : Node = s[0]
	var pl : Node3D = s[1]
	var nemico : CharacterBody3D = s[2]
	var t : Resource = pl.lucida_tecnica_caster.tecnica_corrente()
	_ok(t != null and t.name == "Infusione della Fucina", "Kessra: Infusione della Fucina")
	var host : Node = nemico.health_system.status_host
	await _infondi(pl, t)
	## Cauterizza: l'Emorragia solo accumulata si arresta al primo fendente.
	host.build_laceration(60.0)
	_ok(host.get_effect("laceration").accumulo() > 0.5, "c'e' build-up di Emorragia")
	_fendente(pl, nemico)
	_ok(host.get_effect("laceration").accumulo() == 0.0, "il fendente infuocato la arresta")
	_ok(host.get_effect("burn") != null and host.get_effect("burn").accumulo() > 0.0, "e accumula Bruciatura")
	## Anche scattata.
	host.build_laceration(200.0)
	_ok(host.get_effect("laceration").is_active(), "l'Emorragia scattata")
	_fendente(pl, nemico)
	_ok(not host.get_effect("laceration").is_active(), "si arresta anche lei")
	## Scioglie.
	host.build_frozen(60.0)
	_fendente(pl, nemico)
	_ok(host.get_effect("frozen").accumulo() == 0.0 and not host.get_effect("frozen").is_active(), "scioglie l'accumulo di Congelamento")
	host.build_frozen(100.0)
	_ok(host.get_effect("frozen").is_active(), "Congelato")
	host.build_frozen(100.0)
	_ok(host.is_ghiacciato(), "Ghiacciato")
	nemico.set_physics_process(true)
	await physics_frame
	await physics_frame
	_ok(nemico.anim_player.speed_scale == 0.0, "fermo")
	## Il danno di tipo FUOCO da solo: il Lascito del Bruciante, un incantesimo.
	nemico.health_system._route_statuses(ColpoDiFuoco.new())
	_ok(not host.is_ghiacciato() and not host.get_effect("frozen").is_active(), "un danno di tipo FUOCO scioglie tutto, subito")
	await physics_frame
	await physics_frame
	_ok(nemico.anim_player.speed_scale == 1.0, "e riparte")
	nemico.set_physics_process(false)
	## La Bruciatura gia' attiva: ogni morso e' fuoco.
	host.build_burn(200.0)
	_ok(host.get_effect("burn").is_active(), "la Bruciatura scatta")
	host.build_frozen(60.0)
	host.build_laceration(40.0)
	await create_timer(0.7).timeout
	_ok(host.get_effect("frozen").accumulo() == 0.0 and host.get_effect("laceration").accumulo() == 0.0,
			"e i suoi morsi sciolgono e cauterizzano quello che arriva dopo")
	await _chiudi(scena)
