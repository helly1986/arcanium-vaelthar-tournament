extends SceneTree

## Prova il POSSESSO dell'equipaggiamento: catalogo contro armadio.
##
## Prima di questo sistema il protagonista possedeva tutto cio' che esisteva su
## disco, e un mercante non avrebbe avuto niente da vendere. La prova che conta
## e' proprio quella: il catalogo deve essere piu' grande di cio' che si
## possiede, altrimenti siamo tornati al punto di partenza.
##
## Uso: godot --headless --script arcanium/tools/verifica_possesso_equip.gd


func _init() -> void:
	await process_frame
	var esito := 0

	var lo := root.get_node_or_null("/root/EquipmentLoadout")
	if lo == null:
		push_error("EquipmentLoadout non registrato come autoload")
		quit(1)
		return

	## ─── catalogo vs posseduto ──────────────────────────────────────────────
	var catalogo: Array = lo.catalog_for_slot("arma_primaria")
	var armadio: Array = lo.owned_for_slot("arma_primaria")
	print("armi primarie: %d nel catalogo, %d possedute" % [catalogo.size(), armadio.size()])
	for a in catalogo:
		print("   %-46s %s" % [str(a.resource_path).get_file(), "posseduta" if lo.owns(a) else "-"])

	esito = _controlla("il catalogo non e' vuoto", catalogo.size() > 0, esito)
	esito = _controlla("si possiede l'arma iniziale", armadio.size() >= 1, esito)
	esito = _controlla("il catalogo contiene roba NON posseduta (Solan ha cosa vendere)",
			catalogo.size() > armadio.size(), esito)

	## ─── acquisto ───────────────────────────────────────────────────────────
	var da_comprare: Resource = null
	for a in catalogo:
		if not lo.owns(a):
			da_comprare = a
			break
	if da_comprare == null:
		push_error("nessun pezzo non posseduto: impossibile provare l'acquisto")
		quit(1)
		return

	esito = _controlla("l'acquisto riesce", lo.acquire(da_comprare), esito)
	esito = _controlla("ora risulta posseduto", lo.owns(da_comprare), esito)
	esito = _controlla("comprare due volte lo stesso non fa niente",
			not lo.acquire(da_comprare), esito)
	esito = _controlla("entra nell'armadio",
			lo.owned_for_slot("arma_primaria").has(da_comprare), esito)

	## ─── vendita ────────────────────────────────────────────────────────────
	esito = _controlla("si puo' rivendere", lo.release(da_comprare), esito)
	esito = _controlla("non risulta piu' posseduto", not lo.owns(da_comprare), esito)
	esito = _controlla("rivenderlo di nuovo non fa niente",
			not lo.release(da_comprare), esito)

	## ─── cio' che indossi non si vende ──────────────────────────────────────
	var indosso: Resource = lo.equipped_in("arma_primaria")
	esito = _controlla("c'e' un'arma indossata", indosso != null, esito)
	esito = _controlla("l'arma indossata risulta tale", lo.is_equipped(indosso), esito)
	esito = _controlla("l'arma indossata NON si puo' vendere",
			not lo.release(indosso), esito)
	esito = _controlla("ed e' ancora posseduta", lo.owns(indosso), esito)

	## ─── il giro dal salvataggio ────────────────────────────────────────────
	lo.acquire(da_comprare)
	var salvato: Dictionary = lo.to_dict()
	esito = _controlla("il salvataggio elenca i posseduti",
			(salvato.get("posseduti", []) as Array).size() >= 2, esito)
	esito = _controlla("e anche cosa si indossa",
			(salvato.get("indossati", {}) as Dictionary).has("arma_primaria"), esito)

	lo.release(da_comprare)
	esito = _controlla("tolto prima del ricarico", not lo.owns(da_comprare), esito)
	lo.from_dict(salvato)
	esito = _controlla("ricaricando torna posseduto", lo.owns(da_comprare), esito)
	esito = _controlla("ricaricando resta l'arma indossata",
			lo.equipped_in("arma_primaria") != null, esito)

	quit(esito)


func _controlla(cosa: String, passato: bool, esito_finora: int) -> int:
	print("%s  %s" % ["[ok]" if passato else "[NO]", cosa])
	return esito_finora if passato else 1
