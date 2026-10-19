extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## L'OROLOGIO DI GIOCO — il tempo che passa NEL MONDO, non sul muro
## ═══════════════════════════════════════════════════════════════════════════
##
## Conta i tick di fisica, non i millisecondi reali. In una partita normale le
## due cose coincidono (60 tick al secondo), quindi cooldown e stordimenti
## durano quanto prima. Ma divergono proprio dove conta:
##
##   - in PLAYTEST DISCRETO il ponte ferma il ciclo a ogni decisione di Jev e
##     aspetta la risposta (~0,4 s). Con `Time.get_ticks_msec()` i cooldown dei
##     nemici e lo stordimento del player scadevano DURANTE l'attesa: il mondo
##     era fermo e i suoi orologi correvano;
##   - nel REPLAY la stessa partita deve ridare gli stessi numeri. Un orologio
##     da muro dipende da quanto ci mette la macchina a disegnare ogni frame, e
##     due corse identiche smettevano di esserlo al primo cooldown.
##
## Si importa per path (vedi la nota in interaction_manager.gd sui class_name):
##   const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")


## Secondi di gioco trascorsi dall'avvio.
static func adesso() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Lo stesso, in millisecondi interi, per chi ragionava gia' in msec.
static func adesso_msec() -> int:
	return int(Engine.get_physics_frames() * 1000 / Engine.physics_ticks_per_second)
