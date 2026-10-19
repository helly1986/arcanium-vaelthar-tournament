extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: colpo e HP dei lupi — il morso a schermo e il danno arrivano insieme?
## ═══════════════════════════════════════════════════════════════════════════
##
## L'utente vede i colpi di lupi e Alpha "non ben calibrati fra colpo e
## rimozione degli HP". Prima di toccare clip o mosse si misura: il player sta
## fermo nell'arena dell'Alpha, reso indistruttibile, e si lascia mordere per
## 45 s. Per ogni colpo che toglie HP, colpi.jsonl tiene mossa, distanza vera,
## angolo dal muso, clip e punto della clip; per le prime due volte di ogni
## mossa ci sono i fotogrammi da tre angolazioni allo stesso tick.
##
## La lettura (fatta da Claude, sui fotogrammi): se il morso a schermo non tocca
## il player mentre gli HP scendono, il difetto e' nei dati (istanti di contatto,
## portata) e si corregge nei .tres; se tocca ma in un altro momento della
## clip, sono le animazioni.

const VITA := 1000000
const PER_MOSSA := 2
## Oltre questa distanza (m) fra i centri un morso e' "lungo" e si fotografa sempre.
const LUNGO := 2.5

var _contati : Dictionary = {}     ## mossa -> quante catture fatte
var _gia_visti : Dictionary = {}


func _init() -> void:
	scena = "res://arcanium/levels/arena_branco.tscn"
	durata = 60 * 30


func prepara(oss) -> void:
	porta_player(oss, Vector3(0.0, 0.3, 0.0))
	## Messa in scena: il player regge tutto, cosi' i colpi si contano a decine.
	_rendi_robusto(oss)


## La salute del player nel livello e' un ArcaniumHealthSystem, che conta in
## un float interno (`_health_f`): scrivere solo `current_health` non basta, il
## primo colpo lo riallinea al valore vero e il player muore lo stesso.
func _rendi_robusto(oss) -> void:
	var hs = oss.player.get("health_system")
	hs.total_health = VITA
	if hs.has_method("heal"):
		hs.heal(float(VITA))
	else:
		hs.current_health = VITA
	print("PLAYTEST: salute del player = %s, %s HP" % [hs.get_script().resource_path.get_file(), hs.current_health])


func al_tick(_tick : int, oss) -> void:
	## Il ponte svuota l'elenco dei colpi mentre li scrive: si guarda quello
	## che c'e' adesso e si ricorda cosa si e' gia' visto.
	for c in ponte.sorv.colpi:
		var chiave := "%s|%s|%s" % [c.get("tick"), c.get("cosa"), c.get("autore")]
		if _gia_visti.has(chiave) or str(c.get("vittima")) != "player":
			continue
		_gia_visti[chiave] = true
		var mossa := str(c.get("cosa")).get_slice(" ", 0)
		## Si fotografano i primi di ogni mossa, e TUTTI i colpi lunghi: sono
		## quelli in cui il morso a schermo puo' non toccare il player.
		if float(c.get("distanza", 0.0)) >= LUNGO:
			ponte.cattura_scenario("lungo_%s_%.1fm" % [mossa, float(c.get("distanza"))], oss.player.global_position)
			continue
		var n := int(_contati.get(mossa, 0))
		if n < PER_MOSSA:
			_contati[mossa] = n + 1
			ponte.cattura_scenario("colpo_%s_%d" % [mossa, n + 1], oss.player.global_position)
	## Il player resta in piedi: ogni tanto si rimette la vita.
	var hs = oss.player.get("health_system")
	if hs.current_health < VITA / 2:
		_rendi_robusto(oss)


func azione(_tick : int, _oss) -> String:
	return "wait"
