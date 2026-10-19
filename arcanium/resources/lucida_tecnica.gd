@tool
extends Resource

## `@tool` perché è un DATO: senza, l'editor ne istanzia un segnaposto e ogni
## strumento che voglia validarla (o mostrarla in un menu @tool) fallisce con
## "Attempt to call a method on a placeholder instance".

## ═══════════════════════════════════════════════════════════════════════════
## LUCIDA TECNICA — un colpo iconico che l'arma sa insegnare
## ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ Niente `class_name`: si importa con
## `const LucidaTecnica := preload("res://arcanium/resources/lucida_tecnica.gd")`.
## Vedi la nota in `arcanium/systems/fazioni.gd`.
##
## Le Lucide Tecniche sono la risposta di Arcanium a "perché quel colpo lo può
## fare solo il boss?". Le armi speciali portano con sé un gesto del loro
## padrone: la Spada del Senza Nome insegna il Rovescio Risonante, e chi la
## impugna disegna lo stesso muro di Erosione che gli è stato tirato addosso.
##
## ─── È una DEFINIZIONE, non un caso particolare ─────────────────────────────
## Questa risorsa esiste perché la seconda Lucida Tecnica dev'essere un `.tres`,
## non del codice nuovo. Nulla qui dentro nomina il Rovescio Risonante, il muro
## di fuoco o il Senza Nome: una tecnica è
##
##     un GESTO  +  una FINESTRA in cui l'arma è viva  +  un EFFETTO  +  un COSTO
##
## e ognuna delle quattro parti è un dato. Un colpo che semina spuntoni di
## ghiaccio invece del fuoco è la stessa definizione con `effetto` diverso; un
## colpo che non lascia nulla e fa solo danno è la stessa definizione con
## `effetto` vuoto.
##
## Il corollario da rispettare: quando servirà una tecnica che questa forma non
## sa esprimere, si ALLARGA la forma per tutte, non si aggiunge un ramo `if` per
## quella. Il precedente da non ripetere è "chi posso ferire", che era finito
## scritto in quattro punti diversi prima di diventare `Fazioni.colpibile`.

## ─── Identità (menu, HUD, Diario) ───────────────────────────────────────────
@export var name : String = "Lucida Tecnica"
@export var icon : String = "◈"
@export var image : Texture2D
@export_multiline var lore : String = ""


## ─── Il gesto ───────────────────────────────────────────────────────────────
## La clip vive in una `AnimationLibrary` registrata sull'AnimationPlayer del
## portatore, e si nomina "Libreria/Clip" come ovunque nel progetto.
##
## L'AnimationTree ha UN solo slot per le Lucide Tecniche
## (`LucidaTecnica` + `LucidaTecnicaAnim`): il caster ci scrive dentro questa
## stringa prima di far partire il colpo. Un nodo per tecnica sarebbe stato il
## modo sbagliato — il grafo sarebbe cresciuto di un ramo a ogni arma nuova.
@export var clip : String = ""
@export var speed_scale : float = 1.0


## ─── La finestra in cui l'arma è viva ───────────────────────────────────────
## In FRAZIONI della clip, non in secondi: così la finestra sopravvive a un
## `speed_scale` diverso e a una ri-esportazione dell'animazione con durata
## leggermente diversa.
##
## È lo stesso principio delle finestre d'arma dei nemici, con una differenza
## che conta: quelle andrebbero MISURATE (`AttackTiming`), non stimate. Finché
## una tecnica non è misurata questi due numeri sono un ripiego onesto, e vanno
## trattati come tali — cioè tarati a vista sul playtest e poi sostituiti dalla
## misura.
@export_range(0.0, 1.0) var finestra_da : float = 0.15
@export_range(0.0, 1.0) var finestra_a : float = 0.60


## ─── L'effetto che nasce lungo la traccia della lama ─────────────────────────
## Qualunque scena la cui radice esponga `add_segment(a, b)`. Vuoto = la tecnica
## non lascia nulla dietro di sé e vale per il solo danno del fendente.
##
## Il contratto è deliberatamente minimo: chi vuole inventare una scia di rovi o
## un nastro di luce implementa quel metodo e basta, senza ereditare da nulla.
@export var effetto : PackedScene
@export var effetto_durata : float = 6.0
@export var effetto_danno_tick : int = 4
@export var effetto_intervallo_tick : float = 0.55

## Deroga al fuoco amico: SPENTO di default, come tutto in Arcanium. Si accende
## solo per le tecniche che pagano la propria forza col rischio di colpire i
## propri — vedi `Fazioni`.
@export var fuoco_amico : bool = false

## Maschera di collisione dell'effetto. Deve vedere il layer di chi si vuole
## colpire: se `fuoco_amico` è acceso ma la maschera non include il layer degli
## alleati, la deroga resta teorica perché non vengono nemmeno rilevati.
@export_flags_3d_physics var effetto_maschera : int = 5


## ─── Il costo ───────────────────────────────────────────────────────────────
@export var cooldown : float = 10.0
## Arcanium Vivo speso al lancio. 0 = gratis, la tecnica è limitata dal solo
## cooldown.
@export var costo : float = 0.0


## Una tecnica senza clip non è lanciabile: serve a distinguere "arma senza
## Lucida Tecnica" da "risorsa compilata male", che a schermo si assomigliano.
func valida() -> bool:
	return clip != ""
