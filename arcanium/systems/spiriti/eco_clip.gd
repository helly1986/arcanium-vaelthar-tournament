extends RefCounted

## ⚠️ Niente `class_name`: si usa con `preload`.

## ═══════════════════════════════════════════════════════════════════════════
## LE CLIP DELL'ECO RADICATA — fatte di numeri, non di ossa
## ═══════════════════════════════════════════════════════════════════════════
##
## L'Eco non ha scheletro (vedi corpo_spirito.gd). Le sue clip animano le
## proprieta' del corpo: `affondo` (m, avanti), `inchino` (gradi, + in avanti),
## `immersione` (m, giu'), `strappo` (lembi allargati), `bagliore` (dentro il
## cappuccio), `ondeggio`, `dissolvi`. Il nemico le suona con l'AnimationPlayer
## come fossero clip di Cascadeur: telegraph, contatti e cooldown sono quelli
## del sistema delle mosse, e gli istanti di contatto stanno qui sotto,
## accanto alla clip che li produce (`CONTATTI`).
##
## Le mosse, in una riga ciascuna:
##   artigli — si ritrae, i lembi si allargano, poi AFFONDA: la sciabolata
##             spettrale. Mischia.
##   radice  — sale un palmo, poi affonda la coda nel terreno; la radice corre
##             sotto e ESPLODE sotto il bersaglio. Media distanza: la si schiva
##             leggendo il cerchio a terra.
##   beve    — si ferma, alza il cappuccio e succhia l'Arcanium di chi e' vicino
##             (la Guasta). E' il rovescio del dono dell'Eco evocata.

## Istante di contatto (secondi di clip) per ogni mossa.
const CONTATTI := {
	"artigli": [0.68],
	"radice": [1.55],
	"beve": [0.7, 1.3, 1.9, 2.5],
}

## Le chiavi: {proprieta': [[t, valore], ...]} per clip, piu' lunghezza e loop.
const CLIP := {
	"idle": {"lunghezza": 2.4, "loop": true, "chiavi": {
		"bagliore": [[0.0, 0.05], [1.2, 0.18], [2.4, 0.05]],
	}},
	"glide": {"lunghezza": 1.2, "loop": true, "chiavi": {
		"bagliore": [[0.0, 0.1], [1.2, 0.1]],
		"ondeggio": [[0.0, 1.2], [1.2, 1.2]],
	}},
	"artigli": {"lunghezza": 1.4, "loop": false, "chiavi": {
		"affondo": [[0.0, 0.0], [0.55, -0.3], [0.72, 0.55], [1.0, 0.35], [1.4, 0.0]],
		"inchino": [[0.0, 0.0], [0.55, -20.0], [0.72, 30.0], [1.0, 18.0], [1.4, 0.0]],
		"strappo": [[0.0, 0.0], [0.55, 1.0], [0.72, 0.4], [1.4, 0.0]],
		"bagliore": [[0.0, 0.1], [0.55, 0.9], [0.72, 1.0], [1.4, 0.1]],
	}},
	"radice": {"lunghezza": 2.1, "loop": false, "chiavi": {
		"immersione": [[0.0, 0.0], [0.45, -0.25], [0.8, 0.5], [1.6, 0.5], [2.1, 0.0]],
		"inchino": [[0.0, 0.0], [0.45, -12.0], [0.8, 22.0], [1.6, 22.0], [2.1, 0.0]],
		"strappo": [[0.0, 0.0], [0.45, 0.5], [0.8, 0.2], [1.55, 0.9], [2.1, 0.0]],
		"bagliore": [[0.0, 0.1], [0.45, 0.7], [1.55, 1.0], [2.1, 0.1]],
		"ondeggio": [[0.0, 1.0], [0.8, 2.2], [1.6, 2.2], [2.1, 1.0]],
	}},
	"beve": {"lunghezza": 3.0, "loop": false, "chiavi": {
		"inchino": [[0.0, 0.0], [0.4, -12.0], [2.6, -12.0], [3.0, 0.0]],
		"strappo": [[0.0, 0.0], [0.4, 0.6], [2.6, 0.7], [3.0, 0.0]],
		"bagliore": [[0.0, 0.1], [0.4, 1.0], [2.6, 1.0], [3.0, 0.1]],
		"ondeggio": [[0.0, 1.0], [0.4, 2.4], [2.6, 2.4], [3.0, 1.0]],
		"immersione": [[0.0, 0.0], [0.4, -0.15], [2.6, -0.15], [3.0, 0.0]],
	}},
	"colpito": {"lunghezza": 0.45, "loop": false, "chiavi": {
		"inchino": [[0.0, 0.0], [0.1, -22.0], [0.45, 0.0]],
		"affondo": [[0.0, 0.0], [0.1, -0.25], [0.45, 0.0]],
		"strappo": [[0.0, 0.0], [0.1, 0.7], [0.45, 0.0]],
	}},
	"morte": {"lunghezza": 2.2, "loop": false, "chiavi": {
		"immersione": [[0.0, 0.0], [0.3, -0.1], [2.2, 0.6]],
		"inchino": [[0.0, 0.0], [0.3, -25.0], [2.2, 35.0]],
		"ondeggio": [[0.0, 1.0], [0.3, 2.5], [2.2, 0.2]],
		"strappo": [[0.0, 0.0], [0.3, 1.0], [2.2, 0.3]],
		"bagliore": [[0.0, 0.1], [0.3, 1.0], [2.2, 0.0]],
		"dissolvi": [[0.0, 0.0], [0.5, 0.0], [2.1, 1.0], [2.2, 1.0]],
	}},
}


## La libreria completa, da aggiungere all'AnimationPlayer figlio del corpo
## (il suo `root_node` di default e' il padre: il corpo).
static func libreria() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for nome in CLIP:
		var d : Dictionary = CLIP[nome]
		var a := Animation.new()
		a.length = float(d["lunghezza"])
		a.loop_mode = Animation.LOOP_LINEAR if bool(d["loop"]) else Animation.LOOP_NONE
		for prop in d["chiavi"]:
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(".:%s" % prop))
			a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
			for k in d["chiavi"][prop]:
				a.track_insert_key(tr, float(k[0]), float(k[1]))
		lib.add_animation(StringName(nome), a)
	return lib
