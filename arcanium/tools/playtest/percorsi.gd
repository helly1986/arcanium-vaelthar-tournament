extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## I PERCORSI DEL PLAYTEST — il filo che il codice segue, livello per livello
## ═══════════════════════════════════════════════════════════════════════════
##
## Come in doom-jev: la NAVIGAZIONE e' del codice, Jev decide la tattica. Qui
## stanno le tappe in ordine, con il testo dell'obiettivo che Jev legge (in
## inglese: e' la lingua in cui Jev rende meglio, vedi docs/15_PLAYTEST_JEV.md).
##
## Tipi di tappa:
##   "punto" — si raggiunge (o si oltrepassa lungo la strada);
##   "cono"  — si attiva il Cono `nodo` (interact quando si e' vicini);
##   "boss"  — si abbatte il nemico `nodo` (cercato fra i quest_enemy per nome).
##
## Vaelthar Tournament: la Traccia Perduta non c'e' piu'. Il percorso vive
## nell'arena del branco (arena_branco.tscn: l'arena del prologo con l'Alpha e
## due lupi), finche' le arene del roguelike non avranno i loro.

const ARENA_BRANCO := {
	"scena": "res://arcanium/levels/arena_branco.tscn",
	"tappe": [
		{"tipo": "punto", "pos": Vector3(0, 0, 4),
			"testo": "Walk north into the arena, towards the wolf pack."},
		{"tipo": "boss", "nodo": "LupoAlpha", "pos": Vector3(0, 0, -6),
			"testo": "Defeat the Alpha of the Broken Pack; it howls to call more wolves."},
	],
}

const PER_SCENA := {
	"res://arcanium/levels/arena_branco.tscn": ARENA_BRANCO,
}


static func per_scena(percorso_scena : String) -> Dictionary:
	return PER_SCENA.get(percorso_scena, {})
