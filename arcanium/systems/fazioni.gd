extends RefCounted

## ⚠️ NIENTE `class_name`, di proposito. Chi lo usa fa
## `const Fazioni := preload("res://arcanium/systems/fazioni.gd")`.
## Due motivi: la registrazione dei class_name dipende dallo scan dell'editor,
## che su questo progetto non attecchisce sempre; e un `const` che porta lo
## stesso nome di una classe globale la OMBREGGIA — è già successo in
## `arcanium/ui/shop/shop_menu.gd`, che da allora non compila.

## ═══════════════════════════════════════════════════════════════════════════
## FAZIONI — chi può ferire chi
## ═══════════════════════════════════════════════════════════════════════════
##
## La regola del gioco è una sola: **ciò che spari fa male ai nemici, non agli
## amici**. Vale per l'intera fazione di chi lancia, non solo per chi lancia:
## le tue evocazioni non bruciano nel tuo fuoco, un Consumato non brucia nel
## fuoco di un altro Consumato. Il fuoco amico esiste, ma **solo come deroga
## esplicita per singola mossa**, scelta come contrappeso alla forza — non come
## effetto collaterale di come sono scritti i gruppi.
##
## ─── Perché è un file a parte ───────────────────────────────────────────────
## Perché quella regola era già scritta QUATTRO volte, in quattro forme diverse
## che non si somigliavano:
##
##   • `boss_projectile.gd`      → `is_in_group("player")`, cablato sul player
##   • `ice_shard_projectile.gd` → scarta "player" a mano, poi cerca "targets"
##   • `summoned_minion.gd`      → un commento che DESCRIVE la convenzione altrui
##   • `boss_wall.gd`            → fazione + deroga, la versione completa
##
## Ognuna corretta per sé e incapace di servire le altre: aggiungere una terza
## fazione, o un'arma che ferisce i propri, avrebbe significato ritrovare e
## correggere quattro punti diversi sperando di non saltarne uno. Qui la
## domanda "posso ferirlo?" ha UNA risposta, e chiunque infligga danno la fa.
##
## ─── Perché la fazione si DEDUCE ────────────────────────────────────────────
## Non si dichiara: si legge dai gruppi di chi lancia. Un default che protegge
## solo quando il chiamante si ricorda di impostarlo non è un default, è una
## trappola — e il chiamante che se lo dimentica non riceve un errore, riceve
## un'arma che uccide i propri alleati.
##
## ─── Cosa NON fa ────────────────────────────────────────────────────────────
## Non guarda le maschere di collisione. Un bersaglio che il layer non rileva
## non arriva nemmeno qui: perché una mossa con `fuoco_amico` colpisca davvero
## gli alleati, la `collision_mask` di chi la lancia deve includerne il layer.
## Questo è l'errore da cercare per primo se una deroga sembra non funzionare.

## Le fazioni del gioco, in ordine di controllo. `"player"` contiene ANCHE i
## minion evocati (vedi `summoned_minion.gd`): è il motivo per cui la protezione
## non può basarsi sull'identità del solo lanciatore.
const GRUPPI : PackedStringArray = ["player", "targets"]


## Fazione di un nodo, "" se non ne ha una (scenografia, proiettili, trigger).
static func di(chi : Node) -> String:
	if chi == null:
		return ""
	for g in GRUPPI:
		if chi.is_in_group(g):
			return g
	return ""


## LA domanda. Chiunque infligga danno passa di qui.
##
## `bersaglio` viene ferito se: sa incassare, non è chi ha lanciato, e non è
## della fazione del lanciatore — salvo `fuoco_amico`, che è la deroga di
## design. Chi lancia resta immune anche con la deroga attiva: il fuoco amico
## riguarda gli ALLEATI, l'autolesionismo è un'altra cosa e vorrà una sua
## manopola quando servirà.
##
## Un bersaglio SENZA fazione (una cassa, una colonna) non è mai "amico": se sa
## incassare, lo si colpisce. Serve a non dover elencare in ogni arma tutto ciò
## che è distruttibile ma non schierato.
static func colpibile(bersaglio : Node, lanciatore : Node, fuoco_amico : bool = false) -> bool:
	if bersaglio == null or bersaglio == lanciatore:
		return false
	if not bersaglio.has_method("hit"):
		return false
	if fuoco_amico:
		return true
	var mia := di(lanciatore)
	if mia == "":
		return true      # lanciatore senza schieramento: ferisce tutti
	return not bersaglio.is_in_group(mia)
