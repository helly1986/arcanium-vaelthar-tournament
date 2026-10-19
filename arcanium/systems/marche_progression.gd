extends Node

## Autoload: MarcheProgression
##
## SALITA DI LIVELLO ai Coni di Canalizzazione, pagata in Arcanium Cristallizzato.
##
## Souls-like: non c'è esperienza. La stessa valuta che spendi per comprare da
## Solan è quella che spendi per salire — quindi ogni livello è una rinuncia a
## qualcos'altro, e morire (che ne costa il 50%, vedi `crystal_bank.gd`) fa male
## davvero. È il motivo per cui il costo NON deve essere piatto.
##
## ─── La curva ───────────────────────────────────────────────────────────────
##   costo(L) = 100 + 25 · (L-1)^1.3        [costo per passare da L a L+1]
##
##   L1 → 100     L50 → 4.115     L300 → 41.434
##   L2 → 125     L100 → 9.923    L624 → 107.443
##
## L1 e L2 valgono 100 e 125 per costruzione, qualunque sia l'esponente: a L=2
## il termine (L-1)^k vale 1. L'esponente governa solo il medio-lungo periodo.
##
## ─── Il tetto ───────────────────────────────────────────────────────────────
## Una Marca arriva al massimo a 99. Sette Marche da 10 a 99 = **623 punti**,
## quindi il livello massimo e' **624**, e cappare tutto costa ~29,1 milioni di
## Arcanium — circa 2,3 volte quanto costa massimizzare un souls classico.
##
## E' un traguardo pensato su TRE cicli (NG0, NG+, NG+2), non su una partita:
## ~10 milioni per giro. Deve restare un obiettivo da completista, mai la fine
## naturale del gioco.
##
## ⚠️ Quei totali sono un BUDGET che il resto del gioco deve produrre, non
## numeri da confrontare con le taglie di oggi. Le taglie attuali (Consumato 1,
## Lupo 3, Alpha 100) sono da **prologo**: un giro della Traccia Perduta rende
## ~113 Arcanium. Salgono atto per atto fino all'endgame dell'Atto 4, e ancora
## a ogni ciclo NG+. Quando si tarano le taglie di un atto nuovo, il riferimento
## e' questo.
##
## Un'esponenziale pura (1,25^L) e' stata scartata: supererebbe i 7 milioni gia'
## al livello 50, e il progresso si fermerebbe molto prima del tetto.
##
## ─── Chi tiene cosa ─────────────────────────────────────────────────────────
## Questo autoload è la FONTE AUTOREVOLE del livello e dei punti spesi. Il
## `MarcheStats` del player è solo il posto dove il risultato viene applicato,
## ed è una copia per-partita (vedi `marche_wielder.gd`): senza quella copia i
## punti finirebbero scritti dentro `marche_dawnkeep.tres`, cioè condivisi fra
## tutte le partite e persino salvati dall'editor.

const Marche := preload("res://arcanium/resources/marche_stats.gd")

const COSTO_BASE := 100
const COSTO_PASSO := 25
const COSTO_ESPONENTE := 1.3

## Valore massimo di una singola Marca, e valore di partenza (vedi
## `marche_stats.gd`). Da qui discende il livello massimo: 7 · (99-10) + 1.
const MARCA_MASSIMA := 99
const MARCA_PARTENZA := 10
const LIVELLO_MASSIMO := 7 * (MARCA_MASSIMA - MARCA_PARTENZA) + 1

signal changed
signal leveled_up(livello : int, marca : int)

var livello : int = 1
## Punti spesi per Marca, indicizzati come `MarcheStats.Marca`.
var _punti : Array[int] = [0, 0, 0, 0, 0, 0, 0]


## Costo per passare dal livello attuale al successivo.
func costo_prossimo() -> int:
	return costo_per_livello(livello)


func costo_per_livello(l : int) -> int:
	var passi := maxf(float(l) - 1.0, 0.0)
	return COSTO_BASE + int(round(COSTO_PASSO * pow(passi, COSTO_ESPONENTE)))


func punti_spesi(marca : int) -> int:
	if marca < 0 or marca >= _punti.size():
		return 0
	return _punti[marca]


## Valore attuale di una Marca: base del personaggio + punti comprati. Se il
## player non è in scena (menu, test) si assume la base standard.
func valore_marca(marca : int) -> int:
	var w := _wielder()
	if w != null and w.stats != null:
		return w.stats.get_marca(marca)
	return MARCA_PARTENZA + punti_spesi(marca)


func marca_al_massimo(marca : int) -> bool:
	return valore_marca(marca) >= MARCA_MASSIMA


## Almeno una Marca deve avere ancora spazio: a tutte e sette al massimo non
## c'è più niente da comprare, e la voce di menu va spenta invece di prendere i
## cristalli senza dare niente.
func esistono_marche_disponibili() -> bool:
	for m in _punti.size():
		if not marca_al_massimo(m):
			return true
	return false


func puo_salire() -> bool:
	var banca := get_node_or_null("/root/CrystalBank")
	if banca == null:
		return false
	if not esistono_marche_disponibili():
		return false
	return int(banca.crystals) >= costo_prossimo()


## Sale di un livello mettendo il punto sulla Marca scelta. Ritorna false (e non
## tocca niente) se i cristalli non bastano: chi chiama non deve controllare
## prima, così non esistono due letture del saldo con in mezzo una spesa.
func sali(marca : int) -> bool:
	if marca < 0 or marca >= _punti.size():
		return false
	## Il tetto si controlla PRIMA di spendere: una Marca gia' a 99 prenderebbe
	## i cristalli senza dare niente in cambio.
	if marca_al_massimo(marca):
		return false
	var banca := get_node_or_null("/root/CrystalBank")
	if banca == null:
		return false
	if not banca.spend(costo_prossimo()):
		return false

	_punti[marca] += 1
	livello += 1
	_applica_incremento(marca)

	leveled_up.emit(livello, marca)
	changed.emit()
	return true


## Applica il punto appena comprato al player vivo, e riscala l'arma in mano:
## senza `refresh()` il danno resterebbe quello di prima fino al cambio arma, e
## il livello sembrerebbe non fare niente.
func _applica_incremento(marca : int) -> void:
	var w := _wielder()
	if w == null or w.stats == null:
		return
	w.stats.add_marca(marca, 1)
	if w.has_method("refresh"):
		w.refresh()


## Applica TUTTI i punti accumulati a un MarcheStats fresco. Lo chiama
## `marche_wielder.gd` sulla propria copia, una volta sola: al caricamento di
## una partita i punti stanno qui, non nel .tres di partenza.
func applica_a(stats : MarcheStats) -> void:
	if stats == null:
		return
	for m in _punti.size():
		if _punti[m] > 0:
			stats.add_marca(m, _punti[m])


func _wielder() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	for f in player.get_children():
		if f is MarcheWielder:
			return f
	return null


## ─── Serializzazione per SaveManager ────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"livello": livello, "punti": _punti.duplicate()}


func from_dict(d : Dictionary) -> void:
	if d == null or d.is_empty():
		reset()
		return
	livello = maxi(1, int(d.get("livello", 1)))
	var letti : Array = d.get("punti", [])
	_punti = [0, 0, 0, 0, 0, 0, 0]
	for i in mini(letti.size(), _punti.size()):
		_punti[i] = maxi(0, int(letti[i]))
	changed.emit()


func reset() -> void:
	livello = 1
	_punti = [0, 0, 0, 0, 0, 0, 0]
	changed.emit()
