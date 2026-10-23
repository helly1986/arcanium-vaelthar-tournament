extends "res://arcanium/ui/mappa/nodo_base.gd"

## Il RIPOSO (decisione dell'autore del 2026-10-22): al fuoco si sceglie UNA
## cosa sola fra quattro.
##   Medita    cancella una delle sconfitte della run (spento se non ce ne sono);
##   Affila    l'arma sale di un grado (marche_wielder.gd);
##   Allenati  piu' stamina massima e resistenze fisiche;
##   Studia    piu' Arcanium massimo e resistenze magiche e agli status.
## La salute massima non si alza riposando: solo eventi e consumabili.

const BonusRun := preload("res://arcanium/systems/bonus_run.gd")


func _costruisci() -> void:
	titolo("A fire by the road")
	testo(tr("The night is quiet for once. There is time for one thing only."))
	var sconfitte : int = torneo.sconfitte if torneo != null else 0
	scelta(tr("Meditate"), tr("Forget one defeat: %d of %d becomes %d.") % [sconfitte, torneo.sconfitte_max(), maxi(sconfitte - 1, 0)] if sconfitte > 0 \
			else tr("No defeat to forget yet."), _medita, sconfitte > 0)
	scelta(tr("Sharpen"), tr("Your weapon's scaling rises one grade for the rest of the run."), _affila)
	scelta(tr("Train"), tr("+%d%% maximum stamina, and physical damage taken drops by 5%%.") % int(BonusRun.STAMINA_PER_ALLENAMENTO * 100), _allenati)
	scelta(tr("Study"), tr("+%d%% maximum Arcanium, magic damage and status build-up taken drop.") % int(BonusRun.ARCANIUM_PER_STUDIO * 100), _studia)


func _medita() -> void:
	torneo.medita()
	esito("Meditate", tr("One defeat fades. Defeats: %d of %d.") % [torneo.sconfitte, torneo.sconfitte_max()])


func _affila() -> void:
	torneo.affilature += 1
	esito("Sharpen", tr("The edge bites deeper. Weapon grade +%d for this run.") % torneo.affilature)


func _allenati() -> void:
	torneo.allenamenti += 1
	esito("Train", tr("Breath comes easier, blows land softer."))


func _studia() -> void:
	torneo.studi += 1
	esito("Study", tr("The Arcanium answers a little louder."))
