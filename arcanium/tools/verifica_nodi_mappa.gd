extends SceneTree

## Cancello dei NODI DELLA MAPPA che non si combattono (arcanium/ui/mappa/
## nodo_*.gd) e dei miglioramenti della run sul giocatore (bonus_run.gd):
##   1. riposo: «Meditate» e' spento senza sconfitte e ne toglie una se c'e';
##      «Sharpen» alza il grado dell'arma e la sua potenza;
##   2. riposo: «Train» e «Study» abbassano il danno fisico e magico subito;
##   3. tesoro: Arcanium (30-60 per tappa) e un oggetto nello zaino;
##   4. mercante: c'e' sempre la Brace Votiva; comprarla toglie Arcanium e
##      alza il tetto delle sconfitte;
##   5. imprevisto: lo stesso nodo pesca lo stesso evento, e una scelta applica
##      i suoi effetti;
##   6. ogni schermata, chiusa, completa il nodo;
##   7. nel dungeon il giocatore porta i miglioramenti: stamina massima +20%
##      con due allenamenti, salute massima +10 dagli eventi.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_nodi_mappa.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 7
const MarcheStats := preload("res://arcanium/resources/marche_stats.gd")

var _fatti := 0
var _falliti := 0
var torneo : Node


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	torneo = root.get_node("Torneo")
	var banca : Node = root.get_node("CrystalBank")
	var armadio : Node = root.get_node("EquipmentLoadout")
	var zaino : Node = root.get_node("ArcaniumInventory")
	torneo.inizia(5)

	## 1.
	var r : Node = await _apri("riposo")
	var medita_spento : bool = _bottone(r, "Meditate").disabled
	r.queue_free()
	await process_frame
	torneo.sconfitte = 1
	r = await _apri("riposo")
	_bottone(r, "Meditate").pressed.emit()
	var dopo_medita : int = torneo.sconfitte
	r.chiudi()
	var lama : Resource = load("res://arcanium/resources/weapons/lama_prima_veglia.tres")
	## Una Marca da meta' run: con quelle di base (10) un grado in piu' sparisce
	## nell'arrotondamento di una lama da 12.
	var stats := MarcheStats.new()
	stats.volonta = 60
	var prima : int = lama.power_with(stats, 0)
	r = await _apri("riposo")
	_bottone(r, "Sharpen").pressed.emit()
	var dopo : int = lama.power_with(stats, torneo.affilature)
	r.chiudi()
	_ok(medita_spento and dopo_medita == 0 and torneo.affilature == 1 and dopo > prima,
			"riposo: Meditate spento senza sconfitte, poi 1 -> %d; Sharpen grado +%d, potenza %d -> %d" % [dopo_medita, torneo.affilature, prima, dopo])

	## 2.
	r = await _apri("riposo")
	_bottone(r, "Train").pressed.emit()
	r.chiudi()
	r = await _apri("riposo")
	_bottone(r, "Study").pressed.emit()
	r.chiudi()
	_ok(is_equal_approx(armadio.resistenza_della_run("TAGLIO"), 0.95) and is_equal_approx(armadio.resistenza_della_run("CRIO"), 0.95)
			and is_equal_approx(armadio.resistenza_della_run("FISICO"), 0.95),
			"riposo: Train e Study, danno subito TAGLIO x%.2f, CRIO x%.2f" % [armadio.resistenza_della_run("TAGLIO"), armadio.resistenza_della_run("CRIO")])

	## 3.
	var saldo : int = banca.crystals
	var voci : int = _conta_zaino(zaino)
	var vite : int = torneo.vite_extra
	var t : Node = await _apri("tesoro")
	var preso : int = t.arcanium
	var oggetto : Resource = t.oggetto
	_bottone(t, "Take it").pressed.emit()
	await process_frame
	var arrivato : bool = _conta_zaino(zaino) > voci or torneo.vite_extra > vite
	_ok(banca.crystals - saldo == preso and preso >= 30 and preso <= 60 * 4 and oggetto != null and arrivato,
			"tesoro: +%d Arcanium e %s nello zaino" % [preso, oggetto.item_name if oggetto != null else "niente"])

	## 4.
	banca.add(2000)
	var m : Node = await _apri("mercante")
	var brace : Resource = null
	for o in m.offerte:
		if String(o.id) == "brace_votiva":
			brace = o
	var tetto : int = torneo.sconfitte_max()
	saldo = banca.crystals
	if brace != null:
		m._compra(brace, m.Bottino.prezzo(brace, m.tappa()))
	_ok(brace != null and torneo.sconfitte_max() == tetto + 1 and banca.crystals < saldo,
			"mercante: Brace Votiva in vendita, comprata: tetto %d -> %d, ◆ %d -> %d" % [tetto, torneo.sconfitte_max(), saldo, banca.crystals])
	m.chiudi()

	## 5.
	var id_imp := _nodo("imprevisto")
	var e1 : Node = await _apri("imprevisto", id_imp)
	var ev1 : String = e1.evento.id
	e1.queue_free()
	await process_frame
	var e2 : Node = await _apri("imprevisto", id_imp)
	var salute : int = torneo.salute_bonus
	e2.applica({"salute": 10})
	_ok(ev1 == String(e2.evento.id) and torneo.salute_bonus == salute + 10,
			"imprevisto: stesso nodo, stesso evento (%s); salute massima %+d" % [ev1, torneo.salute_bonus - salute])

	## 6.
	var fatti_prima : int = torneo.completati.size()
	e2.chiudi()
	await process_frame
	_ok(torneo.completati.size() == fatti_prima + 1 and torneo.nodo_corrente == "",
			"la schermata chiusa completa il nodo (%d completati)" % torneo.completati.size())

	## 7.
	torneo.allenamenti = 2
	torneo.salute_bonus = 10
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 5:
		await process_frame
	var pl : Node = scena.get_node("Player")
	var base_stamina := 100.0
	_ok(is_equal_approx(pl.vitals.max_stamina, base_stamina * 1.2) and int(pl.health_system.total_health) == 110,
			"nel dungeon: stamina massima %.0f, salute massima %d" % [pl.vitals.max_stamina, pl.health_system.total_health])
	root.remove_child(scena)
	scena.free()

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


## Il primo nodo di quel tipo in tutta la mappa.
func _nodo(tipo : String) -> String:
	for reg in torneo.mappa["regioni"]:
		for id in reg["nodi"]:
			if reg["nodi"][id]["tipo"] == tipo:
				return id
	return ""


## Apre la schermata di un nodo di quel tipo (forzandolo come nodo in corso).
func _apri(tipo : String, id : String = "") -> Node:
	torneo.nodo_corrente = id if id != "" else _nodo(tipo)
	var s : Node = load("res://arcanium/ui/mappa/nodo_%s.tscn" % tipo).instantiate()
	root.add_child(s)
	await process_frame
	return s


func _bottone(s : Node, testo : String) -> Button:
	for b in s.find_children("*", "Button", true, false):
		if String((b as Button).text).begins_with(testo):
			return b
	return null


func _conta_zaino(zaino : Node) -> int:
	var n := 0
	for sl in zaino.slots:
		n += int(sl.count)
	return n
