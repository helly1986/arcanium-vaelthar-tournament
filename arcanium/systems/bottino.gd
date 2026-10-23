extends RefCounted

## Il BOTTINO della mappa della run: cio' che danno il tesoro e gli eventi e
## cio' che vende il mercante. Pesca dagli oggetti dello zaino
## (arcanium/resources/items/): consumabili, la Pietra del Varco, la Brace
## Votiva (la vita in piu'), e i pezzi che hanno un equipaggiabile o insegnano
## una tecnica, che si offrono solo a chi non li ha gia'.

const CARTELLA := "res://arcanium/resources/items/"

## Le famiglie del bottino e il loro peso al tesoro.
const PESI_TESORO := {"varco": 30.0, "vita": 8.0, "consumabile": 34.0, "pezzo": 28.0}


static func oggetti() -> Array:
	var out : Array = []
	for f in DirAccess.get_files_at(CARTELLA):
		var nome := f.trim_suffix(".remap")
		if nome.ends_with(".tres"):
			var r : Resource = load(CARTELLA + nome)
			if r != null and "id" in r:
				out.append(r)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


## La famiglia di un oggetto.
static func famiglia(o : Resource) -> String:
	if String(o.id) == "pietra_del_varco":
		return "varco"
	if String(o.get("effect")) == "vita_torneo":
		return "vita"
	if String(o.get("category")) == "consumabile":
		return "consumabile"
	return "pezzo"


## Gli oggetti di una famiglia che hanno senso adesso: i pezzi (armi,
## armature, tomi) solo se non li si possiede gia'.
static func candidati(fam : String, albero : SceneTree) -> Array:
	var zaino := albero.root.get_node_or_null("ArcaniumInventory")
	return oggetti().filter(func(o):
		if famiglia(o) != fam:
			return false
		if fam == "pezzo" and zaino != null and zaino.has_item(String(o.id)):
			return false
		return true)


## Un oggetto a caso, pesato per famiglia (null se non c'e' niente).
static func pesca(rng : RandomNumberGenerator, albero : SceneTree, pesi : Dictionary = PESI_TESORO) -> Resource:
	var famiglie : Array = pesi.keys()
	famiglie.sort()
	var disponibili := famiglie.filter(func(f): return not candidati(f, albero).is_empty())
	if disponibili.is_empty():
		return null
	var tot := 0.0
	for f in disponibili:
		tot += float(pesi[f])
	var t := rng.randf() * tot
	var scelta : String = disponibili[-1]
	for f in disponibili:
		t -= float(pesi[f])
		if t <= 0.0:
			scelta = f
			break
	var lista : Array = candidati(scelta, albero)
	return lista[rng.randi_range(0, lista.size() - 1)]


## Il prezzo in Arcanium al mercante: il valore dell'oggetto, piu' caro a ogni
## tappa (le taglie dei nemici crescono con lei).
## Il prezzo minimo per famiglia: i pezzi del kit hanno valore 0, e un'arma a
## 20 cristalli costava quanto una fiala.
const PREZZO_MINIMO := {"varco": 50, "vita": 150, "consumabile": 20, "pezzo": 140}


static func prezzo(o : Resource, tappa : int) -> int:
	var base := maxi(int(PREZZO_MINIMO.get(famiglia(o), 20)), int(o.get("value")) if o.get("value") != null else 40)
	return int(round(float(base) * (1.0 + 0.25 * float(tappa - 1))))


## Mette l'oggetto nello zaino (o lo applica, per la Brace Votiva).
static func consegna(o : Resource, albero : SceneTree) -> void:
	var zaino := albero.root.get_node_or_null("ArcaniumInventory")
	if zaino != null and o != null:
		zaino.add(o, 1)
