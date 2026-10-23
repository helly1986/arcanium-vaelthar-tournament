extends "res://arcanium/ui/mappa/nodo_base.gd"

## L'IMPREVISTO: un evento sulla strada con 2-3 scelte (evento_mappa.gd, i dati
## in arcanium/resources/mappa/eventi/). Lo stesso nodo pesca sempre lo stesso
## evento (dal seme del nodo). Le scelte con un costo si spengono se non si ha
## abbastanza Arcanium; alcune hanno un rischio, l'esito storto che a volte va
## al posto di quello buono.

const Bottino := preload("res://arcanium/systems/bottino.gd")
const CARTELLA := "res://arcanium/resources/mappa/eventi/"

var evento : Resource


static func eventi() -> Array:
	var out : Array = []
	for f in DirAccess.get_files_at(CARTELLA):
		var nome := f.trim_suffix(".remap")
		if nome.ends_with(".tres"):
			out.append(load(CARTELLA + nome))
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


func _costruisci() -> void:
	var tutti := eventi()
	if tutti.is_empty():
		esito("Unknown", tr("The road is quiet."))
		return
	evento = tutti[rng.randi_range(0, tutti.size() - 1)]
	titolo(String(evento.titolo))
	testo(tr(String(evento.testo)))
	var banca := get_node_or_null("/root/CrystalBank")
	var saldo : int = int(banca.crystals) if banca != null else 0
	for s in evento.scelte:
		var costo : int = int(s.get("costo", 0)) * tappa()
		var nome := tr(String(s["nome"])) + ("  —  ◆ %d" % costo if costo > 0 else "")
		scelta(nome, tr(String(s.get("spiegazione", ""))), _scegli.bind(s), saldo >= costo)


func _scegli(s : Dictionary) -> void:
	var costo : int = int(s.get("costo", 0)) * tappa()
	var banca := get_node_or_null("/root/CrystalBank")
	if costo > 0 and (banca == null or not banca.spend(costo)):
		return
	var effetti : Dictionary = s.get("effetti", {})
	var t := String(s.get("esito", ""))
	var rischio : Dictionary = s.get("rischio", {})
	if not rischio.is_empty() and rng.randf() < float(rischio.get("probabilita", 0.0)):
		effetti = rischio.get("effetti", {})
		t = String(rischio.get("esito", t))
	applica(effetti)
	esito(String(evento.titolo), tr(t))


## Gli effetti di una scelta sul torneo, sulla banca e sullo zaino.
func applica(effetti : Dictionary) -> void:
	var banca := get_node_or_null("/root/CrystalBank")
	if effetti.has("arcanium") and banca != null:
		banca.add(int(effetti["arcanium"]) * tappa())
	if torneo != null:
		torneo.salute_bonus += int(effetti.get("salute", 0))
		torneo.affilature += int(effetti.get("affilatura", 0))
		torneo.allenamenti += int(effetti.get("allenamento", 0))
		torneo.studi += int(effetti.get("studio", 0))
		if int(effetti.get("medita", 0)) > 0:
			torneo.medita()
	if effetti.has("oggetto"):
		var lista : Array = Bottino.candidati(String(effetti["oggetto"]), get_tree())
		if not lista.is_empty():
			Bottino.consegna(lista[rng.randi_range(0, lista.size() - 1)], get_tree())
