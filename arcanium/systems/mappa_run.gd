extends RefCounted

## La MAPPA DELLA RUN (design-mappa-run, decisioni dell'autore del 2026-10-19
## e del 2026-10-22): il torneo intero attraverso 4 dei 6 territori, pescati a
## sorte; in ogni territorio un albero visibile di 6 piani su 2-3 corsie che si
## incrociano, e in cima il boss del territorio. La difficolta' sta nella TAPPA
## (1a-4a regione), non nel territorio.
##
## Tutto dipende dal seme: lo stesso seme da' la stessa mappa (si mescola col
## generatore locale, mai col caso globale: vedi stato-mini-dungeon,
## `Array.shuffle()`).
##
## Il risultato e' un Dictionary, cosi' si salva cosi' com'e':
##   {"seme": int, "regioni": [ {
##       "territorio": "kalvorn", "nome": ..., "boss": ..., "tappa": 1..4,
##       "piani": [[id, ...], ...],            # dal basso; l'ultimo e' il boss
##       "nodi": {id: {"id", "regione", "piano", "corsia", "tipo", "seme",
##                     "prossimi": [id, ...]}} } ]}
## Dal boss di una regione si passa a tutti i nodi del primo piano della
## successiva.

const TipoNodo := preload("res://arcanium/resources/mappa/tipo_nodo.gd")
const CARTELLA_TIPI := "res://arcanium/resources/mappa/tipi/"

const REGIONI := 4
## Piani per regione prima del boss: 6 piani danno circa 5-6 combattimenti per
## regione su un sentiero, boss compreso, e i ~24 scontri della run del design.
const PIANI := 6
const CORSIE := 3

## I sei territori del lore (LORE/WORLD.md) e il boss di ognuno
## (design-regioni-e-slice).
const TERRITORI := {
	"kalvorn": {"nome": "Kalvorn — the Perpetual Forest", "boss": "Vyrath", "casata": "sylvorn"},
	"pyrrath": {"nome": "Pyrrath — the Lands of Fire", "boss": "The Perfect One", "casata": "vorrkai"},
	"halrath": {"nome": "Halrath — the Watch Mountains", "boss": "Sera the Watchful", "casata": "dawnkeep"},
	"davrath": {"nome": "Davrath — the Plains of Judgement", "boss": "Khanna the Atesh", "casata": "aethon"},
	"pianure_grigie": {"nome": "Verath — the Grey Plains", "boss": "Drath the Bearer", "casata": "verath"},
	"kalath_dun": {"nome": "Kalath-Dun — the Sea of Sand", "boss": "Sorath-Dun", "casata": "amareth"},
}


## I tipi di nodo, per id.
static func tipi() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(CARTELLA_TIPI):
		var nome := f.trim_suffix(".remap")
		if nome.ends_with(".tres"):
			var t : Resource = load(CARTELLA_TIPI + nome)
			if t != null and String(t.id) != "":
				out[t.id] = t
	return out


static func genera(seme : int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seme
	var catalogo := tipi()
	var territori : Array = TERRITORI.keys()
	territori.sort()
	_mescola(territori, rng)
	var regioni : Array = []
	for r in REGIONI:
		regioni.append(_regione(r, territori[r], rng, catalogo))
	return {"seme": seme, "regioni": regioni}


static func _regione(r : int, territorio : String, rng : RandomNumberGenerator, catalogo : Dictionary) -> Dictionary:
	var nodi := {}
	var piani : Array = []
	## Le corsie di ogni piano: 2 o 3 nodi, il boss da solo nel mezzo.
	for p in PIANI + 1:
		var corsie : Array
		if p == PIANI:
			corsie = [1]
		elif rng.randi_range(2, 3) == 3:
			corsie = [0, 1, 2]
		else:
			corsie = [[0, 2], [0, 1], [1, 2]][rng.randi_range(0, 2)]
		var ids : Array = []
		for c in corsie:
			var id := "r%d_p%d_c%d" % [r, p, c]
			nodi[id] = {"id": id, "regione": r, "piano": p, "corsia": c,
					"tipo": "boss" if p == PIANI else "scontro",
					"seme": rng.randi() % 1000000, "prossimi": []}
			ids.append(id)
		piani.append(ids)
	## I sentieri: ogni nodo verso i nodi del piano sopra a una corsia di
	## distanza al massimo; chi resta senza uscita o senza ingresso si lega al
	## piu' vicino. Al boss arrivano tutti.
	for p in PIANI:
		var sotto : Array = piani[p]
		var sopra : Array = piani[p + 1]
		for a in sotto:
			for b in sopra:
				if p + 1 == PIANI or absi(nodi[a]["corsia"] - nodi[b]["corsia"]) <= 1:
					nodi[a]["prossimi"].append(b)
			if (nodi[a]["prossimi"] as Array).is_empty():
				nodi[a]["prossimi"].append(_vicino(nodi, a, sopra))
		for b in sopra:
			var entra := false
			for a in sotto:
				if b in nodi[a]["prossimi"]:
					entra = true
			if not entra:
				nodi[_vicino(nodi, b, sotto)]["prossimi"].append(b)
	_assegna_tipi(nodi, piani, rng, catalogo)
	var t : Dictionary = TERRITORI[territorio]
	return {"territorio": territorio, "nome": t["nome"], "boss": t["boss"], "casata": t["casata"],
			"tappa": r + 1, "piani": piani, "nodi": nodi}


static func _vicino(nodi : Dictionary, da : String, fra : Array) -> String:
	var meglio : String = fra[0]
	for b in fra:
		if absi(nodi[b]["corsia"] - nodi[da]["corsia"]) < absi(nodi[meglio]["corsia"] - nodi[da]["corsia"]):
			meglio = b
	return meglio


## I tipi speciali sui posti liberi (piani 1-4; il primo e' sempre uno
## scontro), dai tipi con le regole piu' strette a quelli piu' larghi. Ogni tipo
## mette almeno `min_per_regione` nodi e al piu' `max_per_regione`. Il
## riposo ne mette uno nell'ultimo piano prima del boss.
static func _assegna_tipi(nodi : Dictionary, piani : Array, rng : RandomNumberGenerator, catalogo : Dictionary) -> void:
	var ordine : Array = catalogo.values().filter(func(t): return t.max_per_regione > 0)
	ordine.sort_custom(func(a, b): return a.priorita > b.priorita if a.priorita != b.priorita else a.id < b.id)
	for t in ordine:
		var quanti := rng.randi_range(t.min_per_regione, t.max_per_regione)
		if t.prima_del_boss:
			var liberi_ultimo : Array = (piani[PIANI - 1] as Array).filter(func(id): return nodi[id]["tipo"] == "scontro")
			if not liberi_ultimo.is_empty():
				nodi[liberi_ultimo[rng.randi_range(0, liberi_ultimo.size() - 1)]]["tipo"] = t.id
				quanti -= 1
		for k in maxi(quanti, 0):
			var posti : Array = []
			for p in range(maxi(t.piano_min, 1), mini(t.piano_max, PIANI - 1) + 1):
				for id in piani[p]:
					if nodi[id]["tipo"] == "scontro" and not _vicino_dello_stesso(nodi, piani, id, t.id):
						posti.append(id)
			if posti.is_empty():
				break
			nodi[posti[rng.randi_range(0, posti.size() - 1)]]["tipo"] = t.id
	## Lo stesso tipo non speciale due volte di fila su un sentiero va bene
	## (scontro dopo scontro); per gli speciali lo evita `_vicino_dello_stesso`.


## Vero se un nodo collegato (sopra o sotto) e' gia' di questo tipo: due
## mercanti o due riposi uno dopo l'altro sprecano la scelta.
static func _vicino_dello_stesso(nodi : Dictionary, piani : Array, id : String, tipo : String) -> bool:
	for b in nodi[id]["prossimi"]:
		if nodi[b]["tipo"] == tipo:
			return true
	var p : int = nodi[id]["piano"]
	if p > 0:
		for a in piani[p - 1]:
			if id in nodi[a]["prossimi"] and nodi[a]["tipo"] == tipo:
				return true
	return false


## Fisher-Yates col generatore della run.
static func _mescola(a : Array, rng : RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
