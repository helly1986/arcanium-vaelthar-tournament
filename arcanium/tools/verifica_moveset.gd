extends SceneTree

## Cancello per i move set: un .tres che non parsa NON dà errore a chi lo scrive,
## dà un nemico che in gioco non attacca. Qui si carica davvero la risorsa, si
## controlla che ogni mossa abbia una clip che ESISTE nelle famiglie dichiarate,
## e che i `contact_times` cadano dentro la durata vera della clip.
##
##   godot --headless --path . --script res://arcanium/tools/verifica_moveset.gd
##
## Perché serve il confronto con la durata: un contatto oltre la fine della clip
## è esattamente il bug che il Consumato aveva (danno consegnato dopo che
## l'animazione era finita, docs/04 §2) e nessuna lettura del file lo mostra.

const ANIM_DIR := "res://assets/characters/enemies/anims/"

func _init() -> void:
	var timing : Resource = load("res://arcanium/resources/attack_timing.tres")
	var esiti : Array[String] = []
	var guasti := 0

	for path in [
		"res://arcanium/resources/enemies/sylvorn_fante_moveset.tres",
		"res://arcanium/resources/enemies/sylvorn_fante_spadone_moveset.tres",
		"res://arcanium/resources/enemies/consumato_moveset.tres",
	]:
		if not ResourceLoader.exists(path):
			esiti.append("MANCA   %s" % path)
			guasti += 1
			continue
		var set_ : Resource = load(path)
		if set_ == null or not ("moves" in set_):
			esiti.append("ROTTO   %s (non è un EnemyMoveSet)" % path)
			guasti += 1
			continue
		esiti.append("\n=== %s — %d mosse ===" % [path.get_file(), set_.moves.size()])
		for mv in set_.moves:
			## I gruppi C e S passano da `eligible()` SOLO in fase 2, e la fase 2
			## la decide `_in_phase2()`, che fuori dal boss risponde false: una
			## mossa C/S su un nemico con `phase2_hp_ratio = 0` non partira' MAI.
			## E' successo alla combo dello spadone (gruppo "S" per "spadone"):
			## un mese di Fanti che facevano solo il colpo caricato.
			if (mv.group == "C" or mv.group == "S") and set_.phase2_hp_ratio <= 0.0:
				esiti.append("  %-4s ⚠ GRUPPO %s SU UN NEMICO SENZA FASE 2: non partira' mai" % [mv.id, mv.group])
				guasti += 1
			var clip : String = mv.anim
			var glb := "%s%s.glb" % [ANIM_DIR, clip]
			var ok_clip := ResourceLoader.exists(glb)
			var durata := -1.0
			if timing != null and "clips" in timing and timing.clips.has(clip):
				durata = float(timing.clips[clip]["length"])
			var righe := "  %-4s %-34s clip=%s" % [mv.id, clip, "OK" if ok_clip else "MANCANTE"]
			if not ok_clip:
				guasti += 1
			if durata > 0.0:
				righe += "  durata=%.2fs" % durata
				for t in mv.contact_times:
					if t <= 0.0 or t >= durata:
						righe += "  ⚠ CONTATTO %.2f FUORI DALLA CLIP" % t
						guasti += 1
					else:
						righe += "  contatto=%.2f (%.0f%%)" % [t, 100.0 * t / durata]
			else:
				righe += "  (durata non misurata: contatti non verificabili)"
			esiti.append(righe)

	for r in esiti:
		print(r)
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
