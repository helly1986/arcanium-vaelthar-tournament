extends RefCounted
class_name Scossa

## SCOSSA DI CAMERA (screen shake) — il peso dei colpi, sentito dalla camera.
##
## Due modi di chiamarla, e servono entrambi:
##
##   Scossa.colpo(Scossa.MEDIO)                  # un colpo È andato a segno
##   Scossa.nel_mondo(punto, Scossa.DEVASTANTE)  # è successo QUALCOSA, lì
##
## Il secondo è quello che rende il sistema utile domani: palle di cannone che
## mancano il bersaglio, meteore, crolli. Roba che non colpisce nessuno e deve
## far tremare lo schermo lo stesso, tanto più forte quanto più vicina. Se la
## scossa vivesse dentro la pipeline del danno — «chi prende, trema» — nessuna di
## quelle cose potrebbe scuotere niente, ed è l'errore da cui parte questo file.
##
## ─── PERCHÉ NON È UN AUTOLOAD ────────────────────────────────────────────────
## Lo stato sta in `static var`. Un autoload avrebbe voluto una riga in
## `project.godot` — file che l'editor aperto riscrive quando gli pare — e in
## cambio non avrebbe dato niente: qui non c'è nessun nodo, nessun segnale e
## nessun ciclo di vita, solo un numero che sale e scende. `Scossa.colpo(...)` si
## chiama da qualunque punto del codice senza cercare niente nell'albero.
##
## ─── COME FUNZIONA (modello a "trauma") ──────────────────────────────────────
## Non si somma uno spostamento: si somma TRAUMA (0..1), che decade da solo, e
## l'ampiezza a schermo è `trauma²`.
##
## ⚠️ Il quadrato è tutto il sistema, non un dettaglio. È ciò che permette a un
## colpetto leggero di essere *quasi impercettibile* e a un crollo di essere
## *devastante* con la stessa identica formula: a trauma 0.16 l'ampiezza è lo
## 0.6% del massimo (un fremito che si sente e non si vede), a trauma 1.0 è il
## 100%. Con una relazione lineare la stessa scala darebbe il 16% — cioè un
## colpo leggero che sbatacchia lo schermo, che è il difetto tipico degli screen
## shake fatti a mano.
##
## ⚠️ E il trauma si SOMMA con un tetto, non si sostituisce: tre colpi leggeri in
## fila crescono, ma nessuna combo può arrivare al tremore di una meteora.

# ---------------------------------------------------------------------------
# I QUATTRO GRADINI
# ---------------------------------------------------------------------------
#
# Sono trauma, non ampiezza: passa per il quadrato. Accanto, fra parentesi, cosa
# si vede davvero a schermo.

## Colpo leggero andato a segno (fendente base, morso). Un fremito: lo senti,
## non lo vedi. (≈0.6% dell'ampiezza massima)
const LEGGERO := 0.16
## Colpo caricato medio — la spadata caricata del player, un morso dell'Alpha.
## Chiaramente percettibile, non fastidioso. (≈14%)
const MEDIO := 0.38
## Colpo pesante: atterraggio del balzo, scarica del boss. (≈38%)
const PESANTE := 0.62
## Devastante: blast di transizione, meteore, crolli strutturali. (100%)
const DEVASTANTE := 1.0

# ---------------------------------------------------------------------------
# TARATURA
# ---------------------------------------------------------------------------

## Spostamento massimo della camera, in metri, a trauma pieno.
##
## ⚠️ È tarato sulla DISTANZA della IsoCam (~20-30 m), non su una camera in
## terza persona. A quella distanza mezzo metro di traslazione sposta
## l'inquadratura di circa 1.5°: sembra poco scritto così, ed è già parecchio
## visto. Con i numeri di una camera ravvicinata qui non si vedrebbe nulla.
const SPOSTAMENTO_MAX := 0.55
## Rotazione massima (gradi) a trauma pieno, sui tre assi.
const ROTAZIONE_MAX := 2.2
## Frequenza del tremore. Sotto i ~15 Hz si legge come un dondolio (nausea),
## sopra i ~30 come sfarfallio digitale.
const FREQUENZA := 22.0
## Quanto trauma si perde al secondo. Un DEVASTANTE dura ~0.55 s, un LEGGERO
## meno di un decimo: la durata viene da sola dall'intensità, e non serve un
## parametro "durata" che si possa tarare in contraddizione con l'ampiezza.
const DECADIMENTO := 1.8

## Oltre questa distanza dall'ascoltatore un evento nel mondo non si sente più.
const PORTATA_DEFAULT := 34.0

# ---------------------------------------------------------------------------
# STATO
# ---------------------------------------------------------------------------

static var _trauma : float = 0.0
static var _tempo : float = 0.0

## Dove sta l'orecchio: la aggiorna la IsoCam ogni frame col nodo che segue (il
## player). ⚠️ È il PLAYER e non la camera: la camera si allontana con lo zoom, e
## legare l'attenuazione a lei vorrebbe dire che allargando l'inquadratura le
## esplosioni si sentono di meno — cosa che non ha senso per nessuno.
static var _ascoltatore : Vector3 = Vector3.ZERO

## Moltiplicatore globale, per le opzioni di accessibilità. A 0 il sistema è
## spento del tutto (chi soffre di chinetosi lo azzera e il gioco resta
## giocabile: la scossa non porta MAI informazione di gameplay che non ci sia
## anche altrove).
static var intensita_utente : float = 1.0

static var _rumore : FastNoiseLite = null

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Un colpo è andato a segno. Non ha posizione: quando becchi o vieni beccato, il
## fatto avviene addosso a te, e attenuarlo con la distanza sarebbe sbagliato.
static func colpo(intensita : float) -> void:
	_aggiungi(intensita)


## È successo qualcosa NEL MONDO, in `punto`: si sente tanto meno quanto è
## lontano. È la porta per palle di cannone, meteore e crolli — cose che non
## colpiscono nessuno e devono comunque scuotere.
##
## L'attenuazione è quadratica sulla distanza normalizzata, non lineare: una cosa
## a metà portata deve sentirsi molto meno della metà, o tutta la mappa vibra
## sempre un po' e la scossa smette di voler dire "guarda lì".
static func nel_mondo(punto : Vector3, intensita : float,
		portata : float = PORTATA_DEFAULT) -> void:
	var d : float = _ascoltatore.distance_to(punto)
	if d >= portata:
		return
	var vicinanza : float = 1.0 - (d / maxf(portata, 0.01))
	_aggiungi(intensita * vicinanza * vicinanza)


## La chiama la IsoCam ogni frame. Ritorna la scossa da APPLICARE ORA:
## `[spostamento : Vector3, rotazione_gradi : Vector3]`, e fa decadere il trauma.
##
## ⚠️ Consuma. Se un giorno due camere la chiamassero nello stesso frame, la
## seconda vedrebbe un trauma già decaduto. Oggi la camera è una sola; se ne
## servissero due, il decadimento va spostato fuori di qui.
static func consuma(delta : float) -> Array:
	if _trauma <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	_tempo += delta
	## L'ampiezza è il QUADRATO del trauma: vedi la nota in testa al file.
	var a : float = _trauma * _trauma * clampf(intensita_utente, 0.0, 2.0)
	_trauma = maxf(_trauma - DECADIMENTO * delta, 0.0)

	var n := _noise()
	var t : float = _tempo * FREQUENZA
	## Tre canali indipendenti del rumore (righe lontane fra loro), o gli assi si
	## muovono insieme e il tremore diventa un'oscillazione diagonale regolare —
	## che si legge come "la camera scivola", non come "il mondo ha tremato".
	var sp := Vector3(
		n.get_noise_2d(t, 0.0),
		n.get_noise_2d(t, 137.0),
		n.get_noise_2d(t, 311.0)) * (SPOSTAMENTO_MAX * a)
	var rot := Vector3(
		n.get_noise_2d(t, 523.0),
		n.get_noise_2d(t, 761.0),
		n.get_noise_2d(t, 907.0)) * (ROTAZIONE_MAX * a)
	return [sp, rot]


## True se c'è ancora qualcosa da applicare (la camera può saltare il lavoro).
static func attiva() -> bool:
	return _trauma > 0.0


## Azzera di colpo. Da chiamare ai cambi di scena e alle cut-scene: lo stato è
## statico e sopravvive al caricamento di un livello, quindi senza questo una
## meteora esplosa un istante prima di un caricamento farebbe tremare la prima
## inquadratura del livello nuovo.
static func azzera() -> void:
	_trauma = 0.0
	_tempo = 0.0


# ---------------------------------------------------------------------------
# INTERNI
# ---------------------------------------------------------------------------

static func _aggiungi(intensita : float) -> void:
	## Somma con tetto: le combo si accumulano, ma niente può superare il
	## devastante — o due colpi leggeri simultanei varrebbero una meteora.
	_trauma = minf(_trauma + maxf(intensita, 0.0), DEVASTANTE)


static func _noise() -> FastNoiseLite:
	if _rumore == null:
		_rumore = FastNoiseLite.new()
		## Rumore CONTINUO (Perlin) e non casuale puro: due frame vicini devono
		## dare valori vicini, o invece di un tremore si ottiene uno sfarfallio
		## che a schermo si legge come un difetto di rendering.
		_rumore.noise_type = FastNoiseLite.TYPE_PERLIN
		_rumore.frequency = 0.06
		_rumore.fractal_octaves = 1
	return _rumore
