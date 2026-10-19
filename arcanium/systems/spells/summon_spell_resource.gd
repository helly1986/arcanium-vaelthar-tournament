extends "res://arcanium/systems/spells/spell_resource.gd"
class_name SummonSpellResource

## Variante "evocazione" di ArcaniumSpellResource: invece di un proiettile o di
## un campo a terra, SpellCaster.cast_summon() istanzia `minion_scene` vicino
## al player. Riusa cost/cooldown/name/icon/lore/color della base — evocare
## COSTA Arcanium Vivo e ha un cooldown come qualunque spell, semplicemente non
## c'è un bersaglio da mirare: il posto è sempre "davanti al player".
##
## SpellSelection (arcanium/systems/spell_selection.gd) scansiona
## res://arcanium/resources/summons/*.tres per popolare `known_summons` — QUI,
## non in resources/spells/, perché è la cartella che l'altro stream aveva già
## predisposto per i summon (vedi SpellSelection.SUMMON_DIR).

## Scena del minion da istanziare (root consigliata: SummonedMinion, vedi
## arcanium/systems/summons/summoned_minion.gd/.tscn). Contratto duck-typed,
## stesso stile dei proiettili: la scena deve esporre `follow_target` (Node3D),
## `vitals` (PlayerVitals) e `arcanium_per_sec` (float) come var pubbliche.
@export var minion_scene : PackedScene

## Arcanium Vivo generato al secondo dal minion finché resta in vita (0 = non
## genera nulla). Sovrascrive il default della scena minion al momento dello
## spawn (vedi SpellCaster._spawn_summon), così più tipi di summon possono
## condividere la stessa scena con numeri diversi.
@export var arcanium_per_sec : float = 1.0

## Quanti minion di QUESTO tipo possono essere vivi insieme. Oggi sempre 1:
## SpellCaster.cast_summon con un minion già vivo non ne evoca un secondo, lo
## riposiziona semplicemente davanti al player (vedi commento lì). Il campo
## resta per quando arriveranno le evocazioni di casata (multiple istanze).
@export var max_active : int = 1

## ═══════════════════════════════════════════════════════════════════════════
## CASATA E LISTINO
## ═══════════════════════════════════════════════════════════════════════════

## Casata di appartenenza, in minuscolo: "sylvorn", "vorrkai", "dawnkeep",
## "aethon", "verath", "amareth". Vuota = neutrale (la Scintilla). Serve alla
## bottega di Myori per raggruppare il listino e per dire, nella scheda, di chi
## è il dialetto che stai comprando.
@export var casata : String = ""

## Prezzo in Arcanium Cristallizzato. Sta QUI e non nella lista del mercante,
## stessa regola delle armi (vedi shop_menu.MERCE): il listino appartiene
## all'oggetto, così non esistono due numeri da tenere allineati.
## 0 = non in vendita (la Scintilla si impara, non si compra).
@export var value : int = 0

## ═══════════════════════════════════════════════════════════════════════════
## TARATURA DELLA CREATURA
## ═══════════════════════════════════════════════════════════════════════════
##
## Le sei evocazioni di primo livello condividono UNA scena
## (summoned_minion.tscn): quello che le distingue sta qui e viene copiato sul
## minion allo spawn (vedi SpellCaster.CAMPI_MINION). Il motivo non è pigrizia:
## una scena per casata sarebbe sei file da tenere allineati a ogni modifica del
## comportamento, e la differenza fra un'Eco Radicata e una Sentinella del Passo
## è di NUMERI e di COLORE, non di struttura.
##
## ⚠️ Ogni campo aggiunto qui va aggiunto anche a SpellCaster.CAMPI_MINION,
## altrimenti resta scritto nel .tres e non arriva mai alla creatura.

## Famiglia per i bonus da equipaggiamento. Vedi EquipmentLoadout.summon_multiplier
## e i `summon_damage_bonus` delle armature. Famiglie in uso:
##   "bestia" (lupi e simili) · "eco" (Sylvorn) · "costrutto" (Vorrkai)
##   "gelo" (Dawnkeep) · "contrario" (Aethon) · "non_morto" (Verath)
##   "tempesta" (Amareth) · "" (neutrale: la Scintilla d'Arcanium)
@export var summon_family : String = ""

## Colore di casata della creatura: tinge la mesh, la luce, il sigillo a terra
## e la scarica. In isometrica, con tre-quattro evocazioni in campo, è il primo
## (e spesso l'unico) canale con cui il giocatore legge di chi è quella figura.
@export var minion_tint : Color = Color(1.0, 0.2, 0.85)

## Punti vita della creatura (0 = lascia il valore della scena).
@export var minion_health : int = 0

## Ingombro: 1.0 = la taglia della scena. Per le evocazioni con una mesh propria
## si lascia a 1.0 e si usa `minion_height`, che è assoluta.
@export var minion_scale : float = 1.0

## Il modello 3D della creatura. Sostituisce quello della scena: è così che sei
## evocazioni diverse vivono dentro summoned_minion.tscn senza sei scene.
@export var minion_model : PackedScene

## Altezza voluta, in metri. La silhouette è il secondo canale di lettura dopo
## il colore — il Rievocato di Verath è alto, la Scintilla del Keth è minuta — e
## i GLB generati arrivano tutti normalizzati alla stessa dimensione: senza
## questo numero sarebbero sei creature della stessa stazza.
@export var minion_height : float = 0.0

## Quanto sta sollevata da terra: 0 per chi cammina, >0 per chi fluttua.
@export var minion_hover : float = 0.0

## Corpo di SPIRITO (corpo_spirito.gd): la mesh fluttua, ondeggia e si piega
## nel moto senza ossa, col bordo della casata. Per le creature RIG-B di
## Sylvorn, che nascono mesh intere: l'Eco Radicata.
@export var corpo_spirito : bool = false

@export_group("Attacco")
## "scarica" = la scarica radiale di sempre; "radice" = la Radice che Afferra
## dell'Eco (cerchio a terra sotto il nemico piu' vicino, poi la radice esplode).
@export_enum("scarica", "radice") var attacco : String = "scarica"
@export var can_attack : bool = true
@export var blast_power : int = 4
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var blast_damage_type : String = "EROSIONE"
@export var blast_radius : float = 2.4
@export var attack_range : float = 5.0
@export var attack_cooldown : float = 3.5
## Congelamento portato dalla scarica (firma di Dawnkeep).
@export var blast_frozen_buildup : float = 0.0
## Frazione di danno rimandata a chi colpisce la creatura (firma di Aethon).
@export var riflette : float = 0.0

@export_group("Movimento")
@export var move_speed : float = 3.5
@export var follow_distance : float = 1.8

@export_group("Sblocco")
## Flag di PlayerFlags richiesto perché questo summon compaia in
## SpellSelection.known_summons (quindi nella sezione EVOCAZIONI della
## SpellBar). Stringa vuota = sempre sbloccato. Il Maestro di Evocazioni lo
## imposta col trigger SET_FLAG del suo dialogo finale (vedi
## characters/dialogues/dialogues.json, voce "maestro_evocazioni", e
## arcanium/characters/maestro_evocazioni_npc.gd che ne ascolta la conclusione
## per emettere `summon_taught`).
@export var unlock_flag : String = ""
