extends "res://arcanium/ui/mappa/nodo_base.gd"

## Il MERCANTE (design-mappa-run): vende per Arcanium oggetti veri. Ogni banco
## ha sempre la Brace Votiva (la vita in piu': decisione dell'autore del
## 2026-10-21) e una Pietra del Varco, piu' due consumabili e due pezzi che non
## si hanno ancora. Si compra quanto si vuole, poi si riparte.
##
## In arrivo col banco dei potenziamenti: togliere o rilanciare un
## potenziamento (i potenziamenti non ci sono ancora).

const Bottino := preload("res://arcanium/systems/bottino.gd")

var offerte : Array = []
var _bottoni : Dictionary = {}
var _saldo : Label


func _costruisci() -> void:
	offerte = _banco()
	titolo("A travelling merchant")
	testo(tr("\"Arcanium only. No credit, no questions.\""))
	_saldo = Label.new()
	_saldo.name = "Saldo"
	_saldo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saldo.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
	_colonna.add_child(_saldo)
	for o in offerte:
		var p := Bottino.prezzo(o, tappa())
		## Una riga di lore sola: sette offerte con due righe uscivano dallo schermo.
		var lore := tr(String(o.lore))
		var b := scelta("%s  —  ◆ %d" % [tr(String(o.item_name)), p], lore.left(72) + ("…" if lore.length() > 72 else ""),
				_compra.bind(o, p))
		_bottoni[o] = b
	scelta(tr("Leave"), "", chiudi)
	_aggiorna()


func _banco() -> Array:
	var banco : Array = []
	for fam in ["vita", "varco"]:
		var c : Array = Bottino.candidati(fam, get_tree())
		if not c.is_empty():
			banco.append(c[0])
	for fam in ["consumabile", "pezzo"]:
		var c : Array = Bottino.candidati(fam, get_tree())
		for k in 2:
			if c.is_empty():
				break
			banco.append(c.pop_at(rng.randi_range(0, c.size() - 1)))
	return banco


func _compra(o : Resource, prezzo : int) -> void:
	var banca := get_node_or_null("/root/CrystalBank")
	if banca == null or not banca.spend(prezzo):
		return
	Bottino.consegna(o, get_tree())
	## I pezzi si vendono una volta; consumabili e brace si ricomprano.
	if Bottino.famiglia(o) == "pezzo":
		(_bottoni[o] as Button).disabled = true
		(_bottoni[o] as Button).text = tr("%s  —  sold") % tr(String(o.item_name))
		_bottoni.erase(o)
	_aggiorna()


func _aggiorna() -> void:
	var banca := get_node_or_null("/root/CrystalBank")
	var saldo : int = int(banca.crystals) if banca != null else 0
	_saldo.text = tr("You carry ◆ %d") % saldo
	for o in _bottoni:
		(_bottoni[o] as Button).disabled = saldo < Bottino.prezzo(o, tappa())
