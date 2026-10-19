extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## TIRO CON L'ARCO — i tre istanti di una clip di tiro, letti dalle mani
## ═══════════════════════════════════════════════════════════════════════════
##
## Condiviso da `misura_arco.gd` (che stampa il profilo e i tre istanti) e da
## `measure_attack_contacts.gd` (che mette il rilascio nella tabella dei
## tempi come "contatto" delle clip d'arco). Un solo criterio, cosi' il numero
## che si guarda e quello che il gioco usa sono lo stesso. Si importa per path:
##     const TiroArco := preload("res://arcanium/tools/tiro_arco.gd")
##
## Perche' non il criterio dei fendenti (il picco di velocita' dell'osso
## armato): sul tiro rapido dava 0,75 s, che e' lo STRAPPO della freccia dalla
## faretra — la sinistra fa 19,9 m/s uscendo dalla faretra, e per un misuratore
## di spadate quello e' il colpo. Il rilascio vero sta a 1,86 s, quando la mano
## non fa nessun picco: apre le dita e basta. E le dita non si possono leggere:
## le clip animano solo il pollice, che resta fermo sul riposo.
##
## Quello che un tiro con l'arco ha PER FORZA, e che si legge dal solo rig:
##   • le due mani si UNISCONO (la sinistra porta la freccia sulla corda, che
##     sta nella destra), poi si ALLONTANANO — la trazione — fino alla guancia,
##     e da li' si RICHIUDONO quando la sinistra lascia la corda e va avanti;
##   • la mano che tira si posa sull'INCOCCO della corda a riposo, e da quel
##     momento la corda deve seguirla.

## Sotto questa trazione visibile la mano e' "sulla corda" (metri).
const SOGLIA_INCOCCO := 0.04
## Le mani si sono "richiuse" quando la loro distanza scende di tanto sotto il
## massimo raggiunto (metri): e' il rilascio.
const CHIUSURA := 0.02
## Testa della clip da saltare: il salto dal riposo al primo fotogramma e
## l'uscita dalla posa di guardia non sono gesti del tiro.
const TESTA_FRAZ := 0.08
const TESTA_MIN := 0.08


## INCOCCO: il primo indice, saltata la testa, in cui la trazione VISIBILE
## (`corda`: la distanza in piano fra la mano e l'incocco a riposo, come la
## disegna `corda_arco.gd`) sta sotto `SOGLIA_INCOCCO`. -1 se non succede mai.
static func incocco(tempi : Array[float], corda : Array[float]) -> int:
	var testa := _testa(tempi)
	for i in tempi.size():
		if tempi[i] >= testa and corda[i] <= SOGLIA_INCOCCO:
			return i
	return -1


## APERTURA e RILASCIO dalla distanza fra le due mani (`mani`). `unite` e' il
## minimo (le mani insieme sulla corda); da li' la distanza cresce fino al
## massimo (`apertura`, la guancia) e il `rilascio` e' il primo indice in cui
## si e' richiusa di `CHIUSURA` sotto quel massimo. Indici -1 se non trovati.
##
## ⚠️ Vale per un tiro in cui la mano STA FERMA alla guancia finche' non
## lascia: sul caricato (`sword_bow_shot_charged_01`) la mano si stacca
## piano dalla guancia da 2,6 s, e questo criterio darebbe 2,7 mentre le dita
## si aprono a 3,07 — li' il rilascio resta dichiarato a mano, sui fotogrammi.
static func trazione(tempi : Array[float], mani : Array[float]) -> Dictionary:
	var out := {"unite": -1, "apertura": -1, "rilascio": -1}
	var testa := _testa(tempi)
	var d_min := 1e9
	for i in tempi.size():
		if tempi[i] >= testa and mani[i] < d_min:
			d_min = mani[i]
			out["unite"] = i
	if out["unite"] < 0:
		return out
	var i_max : int = out["unite"]
	var d_max : float = mani[i_max]
	for i in range(out["unite"], tempi.size()):
		if mani[i] > d_max:
			d_max = mani[i]
			i_max = i
		elif mani[i] <= d_max - CHIUSURA:
			out["apertura"] = i_max
			out["rilascio"] = i
			break
	return out


static func _testa(tempi : Array[float]) -> float:
	return maxf(TESTA_MIN, tempi[tempi.size() - 1] * TESTA_FRAZ)
