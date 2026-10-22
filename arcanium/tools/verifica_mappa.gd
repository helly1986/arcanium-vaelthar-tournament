extends SceneTree

## Cancello del GENERATORE DELLA MAPPA DELLA RUN (arcanium/systems/mappa_run.gd),
## su 200 semi:
##   1. lo stesso seme da' la stessa mappa (due generazioni identiche);
##   2. 4 regioni, territori diversi fra i 6, tappe 1-4;
##   3. ogni regione ha 6 piani da 2-3 nodi e in cima un boss solo; il primo
##      piano e' tutto di scontri;
##   4. ogni nodo e' raggiungibile dal primo piano e porta al boss (nessun
##      vicolo cieco, nessun nodo irraggiungibile);
##   5. i tipi rispettano i loro dati: piani ammessi, minimo e massimo per
##      regione; prima del boss c'e' sempre un riposo;
##   6. nell'insieme dei semi compaiono tutti e otto i tipi;
##   7. due nodi speciali uguali non sono mai collegati (due mercanti di fila).
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_mappa.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const MappaRun := preload("res://arcanium/systems/mappa_run.gd")
const SEMI := 200
const ATTESE := 7

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	var catalogo := MappaRun.tipi()
	var errori := {1: [], 2: [], 3: [], 4: [], 5: [], 7: []}
	var visti := {}
	for seme in SEMI:
		var m := MappaRun.genera(seme)
		if var_to_str(m) != var_to_str(MappaRun.genera(seme)):
			errori[1].append(seme)
		var regioni : Array = m["regioni"]
		var territori := {}
		for r in regioni.size():
			territori[regioni[r]["territorio"]] = true
			if regioni[r]["tappa"] != r + 1:
				errori[2].append(seme)
		if regioni.size() != 4 or territori.size() != 4:
			errori[2].append(seme)
		for reg in regioni:
			var nodi : Dictionary = reg["nodi"]
			var piani : Array = reg["piani"]
			## 3.
			var forma_ok : bool = piani.size() == MappaRun.PIANI + 1 and (piani[-1] as Array).size() == 1 \
					and nodi[piani[-1][0]]["tipo"] == "boss"
			for p in MappaRun.PIANI:
				if (piani[p] as Array).size() < 2 or (piani[p] as Array).size() > 3:
					forma_ok = false
			for id in piani[0]:
				if nodi[id]["tipo"] != "scontro":
					forma_ok = false
			if not forma_ok:
				errori[3].append(seme)
			## 4.
			var raggiunti := {}
			var coda : Array = (piani[0] as Array).duplicate()
			while not coda.is_empty():
				var id = coda.pop_back()
				if raggiunti.has(id):
					continue
				raggiunti[id] = true
				coda.append_array(nodi[id]["prossimi"])
			var vicoli := 0
			for id in nodi:
				if (nodi[id]["prossimi"] as Array).is_empty() and nodi[id]["tipo"] != "boss":
					vicoli += 1
			if raggiunti.size() != nodi.size() or vicoli > 0:
				errori[4].append(seme)
			## 5.
			var conta := {}
			for id in nodi:
				var t : String = nodi[id]["tipo"]
				conta[t] = conta.get(t, 0) + 1
				visti[t] = true
				var dati : Resource = catalogo.get(t)
				if dati == null or (t != "boss" and (nodi[id]["piano"] < dati.piano_min or nodi[id]["piano"] > dati.piano_max)):
					errori[5].append("%d %s piano %d" % [seme, t, nodi[id]["piano"]])
			for t in catalogo:
				var d : Resource = catalogo[t]
				if d.max_per_regione > 0 and (conta.get(t, 0) < d.min_per_regione or conta.get(t, 0) > d.max_per_regione):
					errori[5].append("%d %s x%d" % [seme, t, conta.get(t, 0)])
			var riposo_prima := false
			for id in piani[MappaRun.PIANI - 1]:
				if nodi[id]["tipo"] == "riposo":
					riposo_prima = true
			if not riposo_prima:
				errori[5].append("%d senza riposo prima del boss" % seme)
			## 7.
			for id in nodi:
				var t : String = nodi[id]["tipo"]
				if t in ["scontro", "boss"]:
					continue
				for b in nodi[id]["prossimi"]:
					if nodi[b]["tipo"] == t:
						errori[7].append("%d %s->%s" % [seme, id, b])

	_ok(errori[1].is_empty(), "lo stesso seme da' la stessa mappa %s" % str(errori[1].slice(0, 5)))
	_ok(errori[2].is_empty(), "4 regioni, territori diversi, tappe 1-4 %s" % str(errori[2].slice(0, 5)))
	_ok(errori[3].is_empty(), "6 piani da 2-3 nodi, boss in cima, primo piano di scontri %s" % str(errori[3].slice(0, 5)))
	_ok(errori[4].is_empty(), "tutto raggiungibile, nessun vicolo cieco %s" % str(errori[4].slice(0, 5)))
	_ok(errori[5].is_empty(), "i tipi rispettano piani e quote, riposo prima del boss %s" % str(errori[5].slice(0, 5)))
	var tutti : Array = catalogo.keys()
	_ok(tutti.all(func(t): return visti.has(t)) and tutti.size() == 8, "compaiono tutti gli 8 tipi %s" % str(visti.keys()))
	_ok(errori[7].is_empty(), "nessun nodo speciale seguito da uno uguale %s" % str(errori[7].slice(0, 5)))

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
