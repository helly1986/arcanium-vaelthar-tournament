extends RefCounted

## I MIGLIORAMENTI DELLA RUN sul giocatore (design-mappa-run, decisioni
## dell'autore del 2026-10-22), dal riposo e dagli eventi:
##   «Affila»    il grado dell'arma (lo legge marche_wielder.gd);
##   «Allenati»  stamina massima e resistenze fisiche;
##   «Studia»    Arcanium massimo, resistenze magiche e accumulo degli status;
##   la salute massima in piu' o in meno, solo da eventi e consumabili speciali.
## Le resistenze stanno in EquipmentLoadout.resistenza_della_run. Qui il resto,
## sul giocatore appena portato all'ingresso del dungeon: ogni scontro ricarica
## la scena, e il giocatore nasce coi valori di base.

## +10% di stamina massima per ogni allenamento, di Arcanium per ogni studio.
const STAMINA_PER_ALLENAMENTO := 0.10
const ARCANIUM_PER_STUDIO := 0.10
## L'accumulo degli status che entra, per ogni studio (10% in meno a volta).
const ACCUMULO_PER_STUDIO := 0.9


static func applica(giocatore : Node, torneo : Node) -> void:
	if giocatore == null or torneo == null or not ("allenamenti" in torneo):
		return
	var v = giocatore.get("vitals")
	if v != null:
		v.max_stamina *= 1.0 + STAMINA_PER_ALLENAMENTO * int(torneo.allenamenti)
		v.stamina = v.max_stamina
		v.max_arcanium *= 1.0 + ARCANIUM_PER_STUDIO * int(torneo.studi)
		v.arcanium = minf(v.arcanium, v.max_arcanium) if int(torneo.studi) == 0 else v.max_arcanium
	var hs = giocatore.get("health_system")
	if hs != null and int(torneo.salute_bonus) != 0:
		hs.total_health = maxi(1, int(hs.total_health) + int(torneo.salute_bonus))
		hs.current_health = hs.total_health
		if "_health_f" in hs:
			hs._health_f = float(hs.total_health)
		hs.health_updated.emit(hs.current_health)
	var sh = hs.get("status_host") if hs != null else null
	if sh != null and "accumulo_mult" in sh:
		sh.accumulo_mult = pow(ACCUMULO_PER_STUDIO, int(torneo.studi))
	## Le resistenze della run entrano con il ricalcolo dell'armadio.
	var armadio := giocatore.get_node_or_null("/root/EquipmentLoadout")
	if armadio != null and hs != null:
		armadio.apply_to(hs)
	## E il grado dell'arma con il ricalcolo della potenza.
	for n in giocatore.get_children():
		if n.has_method("refresh") and "stats" in n:
			n.refresh()
