extends HealthSystem
class_name ArcaniumHealthSystem

const PerkRivincita := preload("res://arcanium/systems/perk_rivincita.gd")

## Sostituto compatibile di HealthSystem per Arcanium. Mantiene i contratti del
## template — segnali `died` / `health_updated`, aggancio via `damage_signal` a
## un nodo che riporta `.power` — e aggiunge:
##  - danno FLOAT (accumulo interno preciso, `current_health` resta int per la UI)
##  - RESISTENZE / VULNERABILITÀ per tipo di danno (letto da `_by_what.damage_type`)
##  - hook per gli STATUS EFFECT (Erosione dell'Eco, Frattura) — Fase 3 task 3
##
## Il template chiama `_on_damage_signal(_by_what)` (metodo virtuale): qui lo
## sovrascriviamo. `_by_what` è tipicamente una ArcaniumEquipmentResource, ma se
## è una EquipmentResource base (nessun `damage_type`) trattiamo il danno come
## FISICO, così resta retro-compatibile.

## Moltiplicatore di danno per tipo. >1 = vulnerabilità, <1 = resistenza.
## Chiavi coerenti con ArcaniumEquipmentResource.damage_type.
@export var resistances : Dictionary = {
	"FISICO": 1.0,
	"TAGLIO": 1.0,
	"PERFORAZIONE": 1.0,
	"SCHIANTO": 1.0,
	"CRIO": 1.0,
	"EROSIONE": 1.0,
	"SACRO": 1.0,
	"FRATTURA": 1.0,
	"VELENO": 1.0,
	"FUOCO": 1.0,
	"FULMINE": 1.0,
}

## Gestore degli status effect del bersaglio. Se assegnato, la sua vulnerabilità
## (Frattura) moltiplica il danno subito, e gli status inflitti dall'arma vengono
## instradati qui. Opzionale: senza StatusHost il sistema funziona comunque.
@export var status_host : StatusHost

## HP interno in virgola mobile: `current_health` (int, ereditato) è derivato da
## questo per la UI. Evita che tanti piccoli colpi frazionari si perdano.
var _health_f : float

## Emesso a ogni colpo col danno finale (utile per numeri di danno / log).
signal damage_dealt(amount : float, damage_type : String)

func _ready() -> void:
	_health_f = float(total_health)
	super._ready()

func _final_damage(_by_what) -> float:
	var raw : float = float(_by_what.power)
	var dtype : String = "FISICO"
	if "damage_type" in _by_what:
		dtype = _by_what.damage_type
	var mult : float = resistances.get(dtype, 1.0)
	# Vulnerabilità temporanea da status, PER TIPO: Frattura (piatta su tutti) +
	# Gelo (espone taglio/perforazione/schianto). Vedi StatusHost.damage_multiplier_for.
	if status_host:
		mult *= status_host.damage_multiplier_for(dtype)
	## I perk della rivincita (perk_rivincita.gd): valgono per il giocatore che
	## incassa e per i nemici del dungeon che incassano da lui.
	if hit_reporting_node != null:
		if hit_reporting_node.is_in_group("player"):
			mult *= PerkRivincita.danno_subito
		elif hit_reporting_node.is_in_group("nemico_dungeon"):
			mult *= PerkRivincita.danno_inflitto
	return raw * mult

func _on_damage_signal(_by_what) -> void:
	if health_bar_control and show_timer:
		show_timer.start()

	var dtype : String = "FISICO"
	if "damage_type" in _by_what:
		dtype = _by_what.damage_type
	var dmg : float = _final_damage(_by_what)

	_health_f -= dmg
	## Ultimo Respiro: il primo colpo mortale lascia a 1.
	if _health_f <= 0.0 and PerkRivincita.salva_vita and hit_reporting_node != null 			and hit_reporting_node.is_in_group("player"):
		PerkRivincita.salva_vita = false
		_health_f = 1.0
	current_health = int(ceil(_health_f))

	damage_dealt.emit(dmg, dtype)
	health_updated.emit(current_health)

	_scuoti(_by_what, dmg)
	_lamento(dmg)
	_route_statuses(_by_what)

	if _health_f <= 0.0:
		died.emit()

## ─── SCOSSA DI CAMERA SUI COLPI A SEGNO ─────────────────────────────────────
##
## Sta qui perché questo è l'IMBUTO: ogni colpo che va a segno su qualunque cosa
## passa da `_on_damage_signal`. Metterla nelle mosse avrebbe voluto dire
## ricordarsene in ogni mossa nuova, per sempre.
##
## ⚠️ Ma "ogni colpo su qualunque cosa" include due evocazioni che si picchiano
## dall'altra parte della radura, e quelle non devono scuotere niente. Per questo
## si passa da `Scossa.nel_mondo` e non da `Scossa.colpo`: la distanza dal player
## fa da filtro da sola, e a portata corta un colpo lontano si spegne senza che
## nessuno debba chiedersi "chi ha colpito chi".
const SCOSSA_PORTATA := 16.0

## Soglie di danno per i gradini della scossa, quando l'arma non dichiara la sua.
##
## ⚠️ Sono un RIPIEGO, non il modo giusto. Il peso di un colpo è una scelta di
## direzione, non una conseguenza del suo danno: un colpo che fa poco male può
## essere pesantissimo (una spallata che ti sposta) e uno che ne fa tanto può
## essere secco e silenzioso (una stoccata). La strada buona è che la risorsa
## dell'arma o della mossa dichiari `scossa`; queste soglie servono a far
## funzionare tutto il resto del gioco nel frattempo, senza toccare le decine di
## risorse esistenti.
const SOGLIA_MEDIO := 15.0
const SOGLIA_PESANTE := 35.0
const SOGLIA_DEVASTANTE := 70.0

func _scuoti(_by_what, dmg : float) -> void:
	var corpo := _corpo_nel_mondo()
	if corpo == null:
		return
	var dove : Vector3 = corpo.global_position
	var forza : float = Scossa.LEGGERO
	if "scossa" in _by_what and float(_by_what.scossa) > 0.0:
		forza = float(_by_what.scossa)
	elif dmg >= SOGLIA_DEVASTANTE:
		forza = Scossa.DEVASTANTE
	elif dmg >= SOGLIA_PESANTE:
		forza = Scossa.PESANTE
	elif dmg >= SOGLIA_MEDIO:
		forza = Scossa.MEDIO
	Scossa.nel_mondo(dove, forza, SCOSSA_PORTATA)


## Il corpo a cui questo sistema appartiene. Si risale l'albero invece di
## assumere che il genitore diretto sia il personaggio: il template annida i
## sistemi a profondità diverse a seconda della scena.
func _corpo_nel_mondo() -> Node3D:
	var n : Node = self
	while n != null:
		if n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


## ─── VOCE: il protagonista che incassa ──────────────────────────────────────
##
## ⚠️ SOLO il protagonista. Questo sistema sta addosso a tutti — nemici,
## evocazioni, manichini — e farli lamentare tutti con la voce del giocatore
## sarebbe grottesco. Il gruppo "player" e' l'unico discrimine affidabile.
##
## ⚠️ E la soglia del grido forte e' `total_health`, NON `current_health`:
## il grido deve dire "questo colpo era enorme", non "sei messo male". Con la
## vita corrente la soglia si abbasserebbe man mano che si e' feriti, e il grido
## grosso partirebbe su colpetti qualunque proprio quando si e' gia' in
## difficolta' — cioe' direbbe il contrario di quel che serve.
const LAMENTO_FORTE_FRAZIONE := 0.5

func _lamento(dmg : float) -> void:
	var corpo := _corpo_nel_mondo()
	if corpo == null or not corpo.is_in_group("player"):
		return
	if total_health > 0 and dmg > float(total_health) * LAMENTO_FORTE_FRAZIONE:
		Suoni.addosso(Suoni.voce_forte())
	else:
		Suoni.addosso(Suoni.voce_lieve(), -3.0)


## Instrada gli status dichiarati dall'arma allo StatusHost del bersaglio.
func _route_statuses(_by_what) -> void:
	if status_host == null:
		return
	if "inflicts_fracture" in _by_what and _by_what.inflicts_fracture:
		status_host.apply_fracture(_by_what.fracture_multiplier, _by_what.fracture_duration)
	if "builds_echo" in _by_what and _by_what.builds_echo:
		status_host.build_echo()
	if "poise_damage" in _by_what and _by_what.poise_damage > 0.0:
		status_host.build_poise(_by_what.poise_damage)
	# Congelamento (spell Crio, es. Shard di Ghiaccio) — build-up letto dal
	# proiettile (ice_shard_projectile.gd costruisce un info con questo campo).
	if "frozen_buildup" in _by_what and _by_what.frozen_buildup > 0.0:
		status_host.build_frozen(_by_what.frozen_buildup)
	# Lacerazione (spine, rampicanti: la Frusta di Spine del Mago Sylvorn).
	if "laceration_buildup" in _by_what and _by_what.laceration_buildup > 0.0:
		status_host.build_laceration(_by_what.laceration_buildup)

func _on_health_signal(_by_what) -> void:
	if health_bar_control and show_timer:
		show_timer.start()
	_health_f += float(_by_what.power)
	if _health_f > float(total_health):
		_health_f = float(total_health)
	current_health = int(ceil(_health_f))
	health_updated.emit(current_health)

## Drena HP diretto (DoT non mitigato) — usato dal veleno scriptato del Senza Nome.
## A differenza di apply_damage(), EMETTE `died` quando arriva a 0, così una fonte
## di danno continuo può effettivamente uccidere (apply_damage non lo fa).
func drain(amount : float, damage_type : String = "EROSIONE") -> void:
	if _health_f <= 0.0:
		return
	_health_f -= amount
	current_health = maxi(0, int(ceil(_health_f)))
	damage_dealt.emit(amount, damage_type)
	health_updated.emit(current_health)
	if _health_f <= 0.0:
		died.emit()

## Cura diretta (es. consumabile) senza passare dal signaling del template.
func heal(amount : float) -> void:
	_health_f = minf(_health_f + amount, float(total_health))
	current_health = int(ceil(_health_f))
	health_updated.emit(current_health)

## Danno diretto (es. da status effect over-time) senza passare da un'arma.
func apply_damage(amount : float, damage_type : String = "EROSIONE") -> void:
	var mult : float = resistances.get(damage_type, 1.0)
	_health_f -= amount * mult
	current_health = int(ceil(_health_f))
	damage_dealt.emit(amount * mult, damage_type)
	health_updated.emit(current_health)
	if _health_f <= 0.0:
		died.emit()
