extends RefCounted
## Il moveset NOSTRO fatto in Cascadeur, per TIPO d'arma: nome della clip in MeleeLib -> GLB
## d'autore che la sostituisce.
##
## L'utente, 2026-11-10: «tutti condividono lo stesso scheletro, dobbiamo usare le animazioni
## in base all'equip slot attualmente selezionato nell'inventario e rispondere anche allo switch
## dell'arma». Le clip nascono su un corpo (la una mano su Edran, la due mani su Zarine) e ogni
## campione le suona sul suo: CorpoCampione.idle_d_autore le porta col retarget sul riposo di
## chi le indossa. Si caricano tutte insieme, perche' i tipi hanno nomi diversi e l'albero
## sceglie da se' il sotto-albero del tipo in mano (`SLASH_tree`, `HEAVY_tree`) a ogni
## `weapon_change_ended`. Lo sprint e la rotolata sono stati soli per tutti i tipi: la loro
## clip la sceglie player_anim_tree.gd con PER_STATO.
##
## CampioneResource.clip_d_autore resta per le clip di UN campione, e vince su queste.
##
## Si importa per path (preload), non con class_name.

const EDRAN := "res://assets/characters/campioni/edran/"
const ZARINE := "res://assets/characters/campioni/zarine/"

const PER_TIPO := {
	## Una mano (Edran, scudo a sinistra), 2026-11-08/10.
	"SLASH": {
		"root-LightWalking": EDRAN + "edran_cammino.glb",
		"root-LightRunning": EDRAN + "edran_corsa.glb",
		"root-Sprint": EDRAN + "edran_sprint.glb",
		"root-LightStrafeFwalk": EDRAN + "edran_strafe_av.glb",
		"root-LightStrafeBwalk": EDRAN + "edran_strafe_ind.glb",
		"root-LightStrafeLwalk": EDRAN + "edran_strafe_sx.glb",
		"root-LightStrafeRwalk": EDRAN + "edran_strafe_dx.glb",
		"root-LightStrafeL": EDRAN + "edran_strafe_corsa_sx.glb",
		"root-LightStrafeR": EDRAN + "edran_strafe_corsa_dx.glb",
		"root-LightStrafeBrun": EDRAN + "edran_corsa_ind.glb",
		## La schivata: rotolata sopra la spalla sinistra (2026-11-10).
		"root-RollLight": EDRAN + "edran_rotolata.glb",
		## Da fermi: il piccolo salto all'indietro alla souls-like (2026-11-11).
		"root-BackstepLight": EDRAN + "edran_salto_indietro.glb",
		## La guardia con lo scudo alto (2026-11-11): la fonde il blend `Guarding` sulla parte
		## alta del corpo finche' si tiene il blocco. Solo chi ha lo scudo para (start_guard),
		## quindi la clip di MeleeLib si sostituisce per tutti.
		"Guarding": EDRAN + "edran_parata.glb",
		## Il colpo preso sullo scudo (il oneshot `Block`), con la fisica di Cascadeur.
		"GuardBlocked": EDRAN + "edran_parata_colpo.glb",
	},
	## Due mani (Zarine con l'asta), 2026-11-10: in spalla libera e di corsa, in guardia al
	## passo da agganciati.
	"HEAVY": {
		"root-HeavyWalking": ZARINE + "zarine_cammino_due_mani.glb",
		"root-HeavyRunning": ZARINE + "zarine_corsa_due_mani.glb",
		"root-HeavySprint": ZARINE + "zarine_sprint_due_mani.glb",
		"root-HeavyStrafeFwalk": ZARINE + "zarine_guardia_av.glb",
		"root-HeavyStrafeBwalk": ZARINE + "zarine_guardia_ind.glb",
		"root-HeavyStrafeLwalk": ZARINE + "zarine_guardia_sx.glb",
		"root-HeavyStrafeRwalk": ZARINE + "zarine_guardia_dx.glb",
		"root-HeavyStrafeLrun": ZARINE + "zarine_corsa_agg_sx.glb",
		"root-HeavyStrafeRrun": ZARINE + "zarine_corsa_agg_dx.glb",
		"root-HeavyStrafeBrun": ZARINE + "zarine_corsa_agg_ind.glb",
		## La schivata: rotolata sopra la spalla destra con l'asta di traverso al petto
		## (2026-11-11).
		"root-RollHeavy": ZARINE + "zarine_rotolata.glb",
		## Da fermi: il salto all'indietro in guardia (2026-11-11).
		"root-BackstepHeavy": ZARINE + "zarine_salto_indietro.glb",
	},
}

## Le clip che non girano in tondo: si suonano una volta (la schivata).
const UNA_VOLTA := ["root-RollLight", "root-BackstepLight", "root-RollHeavy", "root-BackstepHeavy", "GuardBlocked"]

## Gli stati che sono UNO per tutti i tipi d'arma: per ognuno, la clip per tipo e quella di
## ripiego (i tipi che non sono nella tabella, o il corpo che non ha la clip).
const PER_STATO := {
	"MovementStates/SPRINT_tree/Sprint": {
		"SLASH": &"MeleeLib/root-Sprint", "HEAVY": &"MeleeLib/root-HeavySprint",
		"": &"MeleeLib/root-Sprint"},
	## La rotolata in avanti. Senza la clip del tipo resta quella di MeleeLib.
	"DODGE_tree/Roll": {
		"SLASH": &"MeleeLib/root-RollLight", "HEAVY": &"MeleeLib/root-RollHeavy",
		"": &"MeleeLib/root-Roll"},
	## Da fermi. Il ripiego e' la rotolata di MeleeLib suonata AL CONTRARIO (il nodo del .tscn
	## la suona cosi'); le clip nostre si suonano in avanti.
	"DODGE_tree/JumpBack": {
		"SLASH": &"MeleeLib/root-BackstepLight", "HEAVY": &"MeleeLib/root-BackstepHeavy",
		"": &"MeleeLib/root-Roll"},
}


## Tutte le clip nostre che suona il campione `c`: quelle di ogni tipo d'arma, piu' le sue.
static func clip_di(c : Resource) -> Dictionary:
	var tutte := {}
	for tipo in PER_TIPO:
		tutte.merge(PER_TIPO[tipo], true)
	if c != null and "clip_d_autore" in c:
		tutte.merge(c.clip_d_autore, true)
	return tutte


## La clip dello stato `stato` (una chiave di PER_STATO) col tipo d'arma `tipo`.
static func clip_dello_stato(stato : String, tipo : String) -> StringName:
	var tabella : Dictionary = PER_STATO[stato]
	return tabella.get(tipo, tabella[""])


## La clip di ripiego dello stato `stato`.
static func ripiego(stato : String) -> StringName:
	return PER_STATO[stato][""]
