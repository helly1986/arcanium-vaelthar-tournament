extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: un nemico vero insegue il giocatore per i corridoi di un dungeon
## ═══════════════════════════════════════════════════════════════════════════
##
## Nato il 2026-10-20 col mini-dungeon procedurale. Il cancello
## verifica_dungeon cammina lungo la guida con un punto ideale; qui cammina un
## nemico VERO, con la sua root motion, i suoi attacchi e la sua collisione.
##
## La messa in scena:
##   1. si ricostruisce il dungeon col seme dello scenario, si sceglie un
##      nemico del tipo voluto in una stanza aperta, e si fermano gli altri
##      (la prova e' sull'inseguimento, non sulla rissa);
##   2. il giocatore appare a vista del nemico per un secondo: il nemico lo
##      nota (ingaggio);
##   3. il giocatore sparisce dietro un angolo, in una cella che il nemico
##      NON vede e che dista almeno `PASSI_MIN` celle di cammino;
##   4. il giocatore sta fermo e immortale; il nemico deve arrivargli addosso.
## Esito: arrivato (a meno di `ARRIVO` metri), o no; e quante volte e' rimasto
## piantato (meno di 0,5 m in 3 secondi mentre era ancora lontano).
##
## Lancio: python arcanium/tools/playtest/gioca.py --scenario inseguimento_dungeon
## (varianti: inseguimento_dungeon_fante, inseguimento_dungeon_seme7).

const VITA := 1000000
const PASSI_MIN := 7
const ARRIVO := 2.6
const T_NASCONDI := 70

## Il seme del dungeon e il tipo di nemico (prefisso del nome di scena).
var seme_dungeon := 3
var tipo := "lupo"

var _dungeon : Node
var _nemico : Node3D
var _nascondiglio := Vector3.ZERO
var _arrivato_al := -1
var _min_dist := INF
var _piantato := 0
var _storia : Array = []        ## [tick, posizione] ogni 30 tick
var _montato := false
var _t0 := 0


func _init() -> void:
	scena = "res://arcanium/levels/dungeon/dungeon_prova.tscn"
	durata = 1500


func prepara(oss) -> void:
	_dungeon = oss.player.get_tree().current_scene.get_node("Dungeon")
	_dungeon.seme = seme_dungeon
	_dungeon.mostra_contatore = false
	_dungeon.costruisci()


## Al primo tick i nemici ricostruiti esistono: si sceglie, si ferma il resto,
## si monta la scena.
func _monta(oss) -> void:
	var p : RefCounted = _dungeon.pianta
	var g : Node = _dungeon.guida
	var candidati : Array = []
	for e in oss.nemici():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var c : Vector2i = p.cella_di(e.global_position)
		var st : int = p.stanza(c)
		if st < 0:
			continue
		var ruolo : int = p.stanze[st]["ruolo"]
		var aperta : bool = ruolo == 1  ## COMBATTIMENTO
		if aperta:
			candidati.append(e)
	## Il tipo si riconosce dalla scena d'origine: i nemici costruiti si
	## chiamano "@CharacterBody3D@nnn".
	candidati.sort_custom(func(a, b): return int(_e_del_tipo(a)) > int(_e_del_tipo(b)))
	## Prima i nascondigli lontani; se il dungeon non ne ha, piu' vicini.
	for passi in [PASSI_MIN, 5, 4]:
		for e in candidati:
			var dove : Variant = _cerca_nascondiglio(p, g, e, passi)
			if dove != null:
				_nemico = e
				_nascondiglio = dove
				break
		if _nemico != null:
			break
	if _nemico == null:
		push_error("SCENARIO inseguimento: nessun nemico con un nascondiglio adatto")
		return
	for e in oss.nemici():
		if e != _nemico:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.hide()
	## A vista del nemico, a 4 metri, dalla parte del nascondiglio.
	var verso : Vector3 = (_nascondiglio - _nemico.global_position)
	verso.y = 0.0
	var vicino : Vector3 = _nemico.global_position + verso.normalized() * 4.0
	if not g.segmento_libero(_nemico.global_position, vicino):
		vicino = _nemico.global_position + Vector3(0, 0, 3.0)
	porta_player(oss, vicino + Vector3(0, 0.2, 0))
	print("PLAYTEST: inseguimento — seme %d, nemico %s (%s), nascondiglio a %.1f m in linea d'aria" % [
		seme_dungeon, _nemico.name, _nemico.scene_file_path.get_file(), _nemico.global_position.distance_to(_nascondiglio)])
	etichetta("pulito", str(_nemico.name), 0, durata, "inseguimento per i corridoi: nessun difetto atteso")


func _e_del_tipo(e : Node) -> bool:
	return e.scene_file_path.get_file().to_lower().contains(tipo.to_lower())


## Una cella di pavimento che il nemico non vede, ad almeno PASSI_MIN passi di
## cammino ma entro il suo raggio d'ingaggio in linea d'aria (oltre, torna a
## riposo per regola, e la prova misurerebbe un'altra cosa).
func _cerca_nascondiglio(p, g, e : Node3D, passi_min : int) -> Variant:
	var origine : Vector2i = p.cella_di(e.global_position)
	var dist := {origine: 0}
	var coda : Array[Vector2i] = [origine]
	var testa := 0
	var raggio : float = float(e.get("aggro_range")) * 0.85
	var migliore : Variant = null
	var migliore_passi := 0
	while testa < coda.size():
		var c : Vector2i = coda[testa]
		testa += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q : Vector2i = c + d
			## Come camminerebbe il nemico: niente porte chiuse ne' arredo (il
			## teletrasporto del giocatore non apre porte).
			if g._passabile(c, q) and not dist.has(q):
				dist[q] = dist[c] + 1
				coda.append(q)
				var w : Vector3 = p.centro(q)
				if dist[q] >= passi_min and dist[q] > migliore_passi and w.distance_to(e.global_position) < raggio \
						and not g.in_vista(e.global_position, w) and p.stanza(q) == -1:
					migliore = w
					migliore_passi = dist[q]
	return migliore


func al_tick(tick : int, oss) -> void:
	## Al primo tick ricevuto (non sempre lo 0), con i nemici ricostruiti.
	if not _montato:
		_montato = true
		_t0 = tick
		_monta(oss)
	tick -= _t0
	if _nemico == null or not is_instance_valid(_nemico):
		return
	var hs = oss.player.get("health_system")
	if hs != null and float(hs.current_health) < VITA / 2.0:
		hs.total_health = VITA
		hs.heal(float(VITA))
	if tick == T_NASCONDI:
		porta_player(oss, _nascondiglio + Vector3(0, 0.2, 0))
		ponte.cattura_scenario("02_nascosto", _nascondiglio)
	if tick < T_NASCONDI:
		return
	var d := Vector2(_nemico.global_position.x - oss.player.global_position.x,
		_nemico.global_position.z - oss.player.global_position.z).length()
	_min_dist = minf(_min_dist, d)
	if d < ARRIVO and _arrivato_al < 0:
		_arrivato_al = tick
		ponte.cattura_scenario("04_arrivato", oss.player.global_position)
		print("PLAYTEST: inseguimento — %s arrivato al tick %d (%.1f s dopo)" % [_nemico.name, tick, (tick - T_NASCONDI) / 60.0])
	if tick % 120 == 0:
		## Diagnosi: cosa pensa il nemico, e dove lo manda la guida.
		var g : Node = _dungeon.guida
		print("PLAYTEST: inseguimento — t %d, %s stato %s busy %s hurt %.2f, bersaglio %s, punto guida %s (da %s), libero %s" % [
			tick, _nemico.name, _nemico.get("_state"), _nemico.get("_busy"), float(_nemico.get("_hurt_lock")),
			_nemico.target.name if _nemico.get("target") != null else "-",
			g.prossimo_punto(_nemico.global_position, oss.player.global_position).snapped(Vector3.ONE * 0.1),
			_nemico.global_position.snapped(Vector3.ONE * 0.1),
			g.segmento_libero(_nemico.global_position, oss.player.global_position)])
	if tick % 30 == 0:
		_storia.append([tick, _nemico.global_position])
		if _storia.size() >= 7 and _arrivato_al < 0 and d > ARRIVO * 1.5:
			var prima : Vector3 = _storia[_storia.size() - 7][1]
			if prima.distance_to(_nemico.global_position) < 0.5:
				_piantato += 1
				print("PLAYTEST: inseguimento — %s fermo da 3 s a %s (distanza %.1f m)" % [
					_nemico.name, _nemico.global_position.snapped(Vector3.ONE * 0.1), d])
	if tick == T_NASCONDI + 240:
		ponte.cattura_scenario("03_insegue", _nemico.global_position)
	if tick == durata - 1 - _t0:
		print("PLAYTEST: inseguimento_dungeon — seme %d, %s: %s, distanza minima %.1f m, piantato %d volte" % [
			seme_dungeon, _nemico.name,
			"ARRIVATO in %.1f s" % ((_arrivato_al - T_NASCONDI) / 60.0) if _arrivato_al >= 0 else "NON arrivato",
			_min_dist, _piantato])
