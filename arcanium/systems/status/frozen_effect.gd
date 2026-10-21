extends StatusEffect
class_name FrozenEffect

## Congelamento (spell Crio, es. Shard di Ghiaccio) — meccanica di BUILD-UP a
## soglia leggera, analoga a EchoErosionEffect/PoiseBreakEffect ma per i colpi a
## distanza del player: ogni proiettile di ghiaccio che va a segno accumula
## `buildup`; a `threshold` scatta FROZEN per `duration` secondi, che rallenta il
## bersaglio (`slow_multiplier`, letto da chi controlla il movimento del nemico —
## se il nemico non lo legge esplicitamente, resta comunque visibile in HUD via
## `active_statuses()` dello StatusHost). La barra decade nel tempo se non si
## mantiene la pressione (stesso pattern di Erosione dell'Eco/Poise).
##
## id="frozen", label="Frostbite", icon="❄", colore azzurro Crio (#9fe6ff).

@export var threshold : float = 100.0        ## soglia di proc
@export var decay_per_sec : float = 10.0      ## decadimento barra/s se non colpito
## Moltiplicatore di velocità/animazione mentre FROZEN attivo (letto da chi
## controlla il nemico: 1.0 = nessun rallentamento, 0.4 = 40% della velocità).
@export var slow_multiplier : float = 0.4

## VULNERABILITÀ per tipo di danno mentre FROZEN (danno subito ×valore). Il gelo
## non solo rallenta: fessura le difese. Taglio/perforazione mordono di più
## (−20% difesa → ×1.2), ma è lo SCHIANTO a spaccare il bersaglio ghiacciato
## (×1.5) — è l'anello che rende sensata la build "mago glaciale con la mazza"
## (congeli col Crio, poi frantumi col SCHIANTO). Tarabili.
@export var vuln_taglio : float = 1.2
@export var vuln_perforazione : float = 1.2
@export var vuln_schianto : float = 1.5

## Moltiplicatore di danno per un dato tipo mentre FROZEN (1.0 se non attiva o
## tipo non colpito). Interrogato da StatusHost.damage_multiplier_for().
func damage_multiplier_for(dtype : String) -> float:
	if not is_active():
		return 1.0
	match dtype:
		"TAGLIO": return vuln_taglio
		"PERFORAZIONE": return vuln_perforazione
		"SCHIANTO": return vuln_schianto
		_: return 1.0

var buildup : float = 0.0

## Rapporto di riempimento della barra, 0..1: lo legge StatusHost.accumuli()
## per gli status alla Elden Ring in basso al centro (status_centrali.gd).
func accumulo() -> float:
	return clampf(buildup / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


## Emesso quando la barra cambia (per la UI di build-up): buildup/threshold.
signal meter_changed(ratio : float)

func _init() -> void:
	id = "frozen"
	label = "Frostbite"
	icon = "❄"
	color = Color("#9fe6ff")
	duration = 5.0    ## scelta utente 2026-07-22: 2.5s erano troppo pochi

## Chiamato a ogni colpo di ghiaccio che va a segno. Riempie la barra; a soglia
## piena scatta l'afflizione. Mentre è già attiva i colpi non ricaricano
## (coerente con Erosione dell'Eco/Poise-break).
func add_buildup(amount : float) -> void:
	if is_active():
		return
	buildup = minf(threshold, buildup + amount)
	meter_changed.emit(buildup / threshold)
	if buildup >= threshold:
		buildup = 0.0
		meter_changed.emit(0.0)
		trigger()  # attiva FROZEN per `duration` secondi

## True se il bersaglio è attualmente congelato/rallentato.
func is_frozen() -> bool:
	return is_active()

## Da chiamare ogni frame anche quando NON attiva, per far decadere la barra
## (stesso pattern di EchoErosionEffect.decay_meter / PoiseBreakEffect.decay_meter).
func decay_meter(delta : float) -> void:
	if is_active() or buildup <= 0.0:
		return
	buildup = maxf(0.0, buildup - decay_per_sec * delta)
	meter_changed.emit(buildup / threshold)
