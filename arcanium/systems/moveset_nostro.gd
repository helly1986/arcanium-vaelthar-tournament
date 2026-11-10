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
## `weapon_change_ended`. Lo sprint e' uno stato solo per tutti i tipi: la sua clip la sceglie
## player_anim_tree.gd con SPRINT.
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
	},
}

## La clip dello stato Sprint per tipo d'arma; i tipi che non sono qui suonano quella di SLASH.
const SPRINT := {"SLASH": &"MeleeLib/root-Sprint", "HEAVY": &"MeleeLib/root-HeavySprint"}


## Tutte le clip nostre che suona il campione `c`: quelle di ogni tipo d'arma, piu' le sue.
static func clip_di(c : Resource) -> Dictionary:
	var tutte := {}
	for tipo in PER_TIPO:
		tutte.merge(PER_TIPO[tipo], true)
	if c != null and "clip_d_autore" in c:
		tutte.merge(c.clip_d_autore, true)
	return tutte


## La clip dello sprint col tipo d'arma `tipo`.
static func sprint(tipo : String) -> StringName:
	return SPRINT.get(tipo, SPRINT["SLASH"])
