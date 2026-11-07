extends Node
class_name StatusHost

## Componente che gestisce gli status effect attivi su un'entità. Da appendere a
## un nemico/player accanto al suo ArcaniumHealthSystem. Contiene gli StatusEffect
## come Node figli (o li crea di default), li aggiorna e fa da punto d'accesso:
##  - `damage_multiplier()` → prodotto delle vulnerabilità attive (Frattura)
##  - `apply_fracture()` / `build_echo()` → inflitti da chi colpisce
##  - `status_log` → segnale testuale (DoD Fase 3: "status visibile a log")
##
## Gli effetti si auto-registrano dai figli StatusEffect; se assenti e
## `create_defaults` è on, crea Frattura + Erosione dell'Eco standard.

@export var create_defaults : bool = true
## Quanto entra di ogni accumulo di stato (Congelamento, Lacerazione): sotto 1
## resiste meglio. Il campione lo abbassa studiando ai riposi (bonus_run.gd).
var accumulo_mult : float = 1.0
## Se true stampa in console ogni evento di status (comodo per il playtest).
@export var log_to_console : bool = true

## id → StatusEffect
var _effects : Dictionary = {}

const BurnEffect := preload("res://arcanium/systems/status/burn_effect.gd")
const SpiritiEffect := preload("res://arcanium/systems/status/spiriti_effect.gd")
const GhiacciatoEffect := preload("res://arcanium/systems/status/ghiacciato_effect.gd")
const ShockEffect := preload("res://arcanium/systems/status/shock_effect.gd")
const BagnatoEffect := preload("res://arcanium/systems/status/bagnato_effect.gd")
const OMBRA_ASPETTO := preload("res://arcanium/systems/status/aspetto_status.gdshader")
## Quale status si vede addosso, se ce n'e' piu' d'uno: il primo. [colore da effetto],
## quanto copre il corpo, quanto corre.
const ASPETTI := [["ghiacciato", 1.0, 0.03], ["shock", 0.0, 3.0], ["burn", 0.0, 1.4], ["frozen", 0.35, 0.1],
		["spiriti", 0.0, 0.8], ["laceration", 0.0, 0.5], ["bagnato", 0.0, 0.5]]

var _pellicola : ShaderMaterial = null
var _mesh_corpo : Array[MeshInstance3D] = []
var _aspetto_acceso := false
var _al_ripasso := 0.0

signal status_log(text : String)

func _ready() -> void:
	for child in get_children():
		if child is StatusEffect:
			_register(child)

	if create_defaults:
		if not _effects.has("fracture"):
			_register(_add_effect(FractureEffect.new()))
		if not _effects.has("echo_erosion"):
			_register(_add_effect(EchoErosionEffect.new()))

func _add_effect(effect : StatusEffect) -> StatusEffect:
	add_child(effect)
	return effect

func _register(effect : StatusEffect) -> void:
	_effects[effect.id] = effect
	effect.applied.connect(_on_applied)
	effect.refreshed.connect(_on_refreshed)
	effect.expired.connect(_on_expired)

func _process(delta : float) -> void:
	## Il modello di un corpo puo' cambiare mentre lo status dura (i nemici si vestono dopo
	## la comparsa): la pellicola si ripassa ogni tanto, o resterebbe su una mesh nascosta.
	if _aspetto_acceso:
		_al_ripasso -= delta
		if _al_ripasso <= 0.0:
			_al_ripasso = 0.5
			_aggiorna_aspetto()
	# Il decadimento della barra di build-up va fatto anche quando non attiva.
	var echo := get_effect("echo_erosion")
	if echo and echo is EchoErosionEffect:
		echo.decay_meter(delta)
	var poise := get_effect("poise_break")
	if poise and poise is PoiseBreakEffect:
		poise.decay_meter(delta)
	var frozen := get_effect("frozen")
	if frozen and frozen is FrozenEffect:
		frozen.decay_meter(delta)
	var lac := get_effect("laceration")
	if lac and lac is LacerationEffect:
		lac.decay_meter(delta)
	var ghiaccio := get_effect("ghiacciato")
	if ghiaccio and ghiaccio is GhiacciatoEffect:
		ghiaccio.decay_meter(delta)
	var shock := get_effect("shock")
	if shock and shock is ShockEffect:
		shock.decay_meter(delta)
	var burn := get_effect("burn")
	if burn and burn is BurnEffect:
		burn.decay_meter(delta)

func get_effect(id : String) -> StatusEffect:
	return _effects.get(id, null)

## Le barre di ACCUMULO in corso (non ancora scattate), per la HUD: ogni effetto
## con una barra (Lacerazione, Congelamento, Erosione dell'Eco, rottura della
## guardia) la mostra salire come in Elden Ring (status_centrali.gd).
## Ogni voce: { id, icon, color, ratio } (ratio = riempimento 0→1).
func accumuli() -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for effect in _effects.values():
		if effect.has_method("accumulo") and not effect.is_active() and effect.accumulo() > 0.0:
			out.append({"id": effect.id, "icon": effect.icon, "color": effect.color, "ratio": effect.accumulo()})
	return out

## Elenco degli status attualmente attivi, per la HUD.
## Ogni voce: { id, label, icon, color, ratio } (ratio 1→0 sulla durata).
func active_statuses() -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for effect in _effects.values():
		if effect.is_active():
			out.append({
				"id": effect.id, "label": effect.label, "icon": effect.icon,
				"color": effect.color, "ratio": effect.ratio(),
			})
	return out

## Prodotto dei moltiplicatori di vulnerabilità PIATTI (indipendenti dal tipo):
## oggi solo Frattura. Mantenuto per compatibilità; il calcolo danno usa la
## variante per-tipo qui sotto.
func damage_multiplier() -> float:
	var mult := 1.0
	for effect in _effects.values():
		if effect is FractureEffect and effect.is_active():
			mult *= effect.damage_multiplier()
	return mult

## Moltiplicatore di vulnerabilità per uno SPECIFICO tipo di danno: combina i
## contributi piatti (Frattura, vale per ogni tipo) e quelli per-tipo (Gelo, che
## espone di più taglio/perforazione/schianto). È questo che l'ArcaniumHealthSystem
## interroga in fase di calcolo danno, così un colpo da SCHIANTO su un congelato
## incassa il ×1.5 mentre un colpo Crio no.
func damage_multiplier_for(dtype : String) -> float:
	var mult := 1.0
	for effect in _effects.values():
		if not effect.is_active():
			continue
		if effect is FractureEffect:
			mult *= effect.damage_multiplier()
		elif effect is FrozenEffect:
			mult *= effect.damage_multiplier_for(dtype)
	return mult

## ─── Inflizione (chiamati da chi colpisce / dall'health system) ──────────────
func apply_fracture(mult : float = 1.35, dur : float = 15.0) -> void:
	## Si crea al primo uso, come la Lacerazione: i nemici non hanno gli effetti di
	## default, e la Frattura andava persa senza un errore.
	var f := get_effect("fracture")
	if f == null:
		f = _add_effect(FractureEffect.new())
		_register(f)
	if f is FractureEffect:
		f.inflict(mult, dur)

## Aggiunge build-up di Erosione (un colpo del Gruppo A). Proc gestito internamente.
func build_echo() -> void:
	var e := get_effect("echo_erosion")
	if e and e is EchoErosionEffect:
		e.build()

## Aggiunge build-up di poise (un colpo del player). Proc gestito internamente.
func build_poise(amount : float) -> void:
	var p := get_effect("poise_break")
	if p and p is PoiseBreakEffect:
		p.build(amount)

## Rottura istantanea del poise (parry riuscito), a prescindere dalla barra.
func break_poise_now() -> void:
	var p := get_effect("poise_break")
	if p and p is PoiseBreakEffect:
		p.break_now()

## True se il bersaglio è attualmente staggerato dal poise-break.
func is_poise_broken() -> bool:
	var p := get_effect("poise_break")
	return p != null and p is PoiseBreakEffect and p.is_active()

## Aggiunge build-up di Congelamento (un colpo di ghiaccio, es. Shard). Crea il
## FrozenEffect figlio al primo utilizzo se non presente (lazy, a differenza di
## Frattura/Erosione che sono nei create_defaults — il Congelamento è opzionale,
## serve solo ai bersagli esposti a magia Crio). Proc gestito internamente.
func build_frozen(amount : float) -> void:
	var f := get_effect("frozen")
	if f == null:
		f = _add_effect(FrozenEffect.new())
		_register(f)
	if f is FrozenEffect:
		## Su chi e' gia' congelato il freddo va oltre: si accumula il Ghiacciato. Il
		## giocatore non ha chi lo fermi: per lui resta il Congelamento.
		if f.is_active() and not _e_il_giocatore():
			var g := get_effect("ghiacciato")
			if g == null:
				g = _add_effect(GhiacciatoEffect.new())
				_register(g)
			g.add_buildup(amount * accumulo_mult)
			return
		f.add_buildup(amount * accumulo_mult)


## Vero se il bersaglio e' Ghiacciato: lo legge chi lo muove (ArcaniumEnemy).
func is_ghiacciato() -> bool:
	var g := get_effect("ghiacciato")
	return g != null and g.is_active()


## Aggiunge build-up di Shock (Comando del Tuono).
func build_shock(amount : float) -> void:
	var s := get_effect("shock")
	if s == null:
		s = _add_effect(ShockEffect.new())
		_register(s)
	s.add_buildup(amount * accumulo_mult)


## Bagna il bersaglio, o rinnova: i corsi d'acqua e i colpi che bagnano.
func bagna() -> void:
	var b := get_effect("bagnato")
	if b == null:
		b = _add_effect(BagnatoEffect.new())
		_register(b)
	b.trigger()


## Il fuoco che arriva (danni di tipo fuoco, bruciatura): cauterizza l'Emorragia, anche
## se e' solo build-up, e scioglie Congelamento e Ghiacciato. Regola dell'autore.
func cauterizza() -> void:
	for id in ["laceration", "frozen", "ghiacciato"]:
		if get_effect(id) != null:
			cura(id)

## Rottura istantanea del Congelamento (proc immediato, a prescindere dalla
## barra) — analogo a break_poise_now(), per colpi/incantesimi speciali che
## vogliono congelare senza passare dal build-up.
func apply_frozen() -> void:
	var f := get_effect("frozen")
	if f == null:
		f = _add_effect(FrozenEffect.new())
		_register(f)
	if f is FrozenEffect:
		f.buildup = 0.0
		f.trigger()

## Aggiunge build-up di Lacerazione (spine, rampicanti). Crea l'effetto al primo
## utilizzo, come il Congelamento: serve solo a chi incontra chi lacera.
func build_laceration(amount : float) -> void:
	var l := get_effect("laceration")
	if l == null:
		l = _add_effect(LacerationEffect.new())
		_register(l)
	if l is LacerationEffect:
		l.add_buildup(amount * accumulo_mult)

## Aggiunge build-up di Bruciatura (il Lascito del Bruciante). Si crea al primo
## utilizzo, come la Lacerazione.
func build_burn(amount : float) -> void:
	cauterizza()
	var b := get_effect("burn")
	if b == null:
		b = _add_effect(BurnEffect.new())
		_register(b)
	if b is BurnEffect:
		b.add_buildup(amount * accumulo_mult)


## Manda addosso gli Spiriti Risvegliati (Terra Risvegliata): niente accumulo, arrivano e
## basta. Ritorna l'effetto: chi li ha mandati sa cosi' se uccidono.
func affida_spiriti(danno_totale : float, lanciatore : Node, costo : float) -> StatusEffect:
	var s := get_effect("spiriti")
	if s == null:
		s = _add_effect(SpiritiEffect.new())
		_register(s)
	if s is SpiritiEffect:
		s.affida(danno_totale, lanciatore, costo)
	return s


## Quanto si puo' muovere il bersaglio: il prodotto dei rallentamenti attivi. Lo legge chi
## controlla il nemico (ArcaniumEnemy._scorri).
func moltiplicatore_velocita() -> float:
	var mult := 1.0
	for effect in _effects.values():
		if effect.is_active() and "slow_multiplier" in effect:
			mult *= float(effect.get("slow_multiplier"))
	return mult


## CURA uno stato: azzera la sua barra d'accumulo e, se e' scattato, lo chiude.
## Vera se c'era qualcosa da curare (un consumabile sprecato non si consuma).
## Le Bende dell'Eco (LORE/ITEMS_LORE: «rimuove Lacerazione, stoppa la barra»).
func cura(id : String) -> bool:
	var e := get_effect(id)
	if e == null:
		return false
	var fatto := false
	var barra := "meter" if "meter" in e else "buildup"
	if barra in e and float(e.get(barra)) > 0.0:
		e.set(barra, 0.0)
		if e.has_signal("meter_changed"):
			e.emit_signal("meter_changed", 0.0)
		fatto = true
	if e.is_active():
		e.termina()
		fatto = true
	if fatto:
		_emit_log("%s: %s curata" % [_host_name(), e.label])
	return fatto

## True se il bersaglio è attualmente congelato/rallentato dal Congelamento.
func is_frozen() -> bool:
	var f := get_effect("frozen")
	return f != null and f is FrozenEffect and f.is_frozen()

## ─── Log ─────────────────────────────────────────────────────────────────────
func _emit_log(text : String) -> void:
	if log_to_console:
		print("[STATUS] ", text)
	status_log.emit(text)

func _e_il_giocatore() -> bool:
	var corpo := get_parent()
	return corpo != null and corpo.is_in_group("player")


## La pellicola sul corpo per lo status che conta di piu'. Sul giocatore no: la sua
## armatura e la sua stoffa hanno gia' i loro materiali, e gli status li legge dalla HUD.
func _aggiorna_aspetto() -> void:
	if _e_il_giocatore():
		return
	var corpo := get_parent()
	if corpo == null or not is_inside_tree():
		return
	var scelto : Array = []
	for a in ASPETTI:
		var e := get_effect(a[0])
		if e != null and e.is_active():
			scelto = a
			break
	for mi in _mesh_corpo:
		if is_instance_valid(mi):
			mi.material_overlay = null
	_mesh_corpo.clear()
	_aspetto_acceso = not scelto.is_empty()
	if not _aspetto_acceso:
		return
	for n in corpo.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).skin != null:
			_mesh_corpo.append(n)
	if _pellicola == null:
		_pellicola = ShaderMaterial.new()
		_pellicola.shader = OMBRA_ASPETTO
	var c : Color = get_effect(scelto[0]).color
	_pellicola.set_shader_parameter("colore", Vector3(c.r, c.g, c.b))
	_pellicola.set_shader_parameter("coprente", scelto[1])
	_pellicola.set_shader_parameter("scorre", scelto[2])
	for mi in _mesh_corpo:
		mi.material_overlay = _pellicola


func _on_applied(effect : StatusEffect) -> void:
	_aggiorna_aspetto()
	_emit_log("%s applicato su %s (%.1fs)" % [effect.label, _host_name(), effect.duration])

func _on_refreshed(effect : StatusEffect) -> void:
	_emit_log("%s rinnovato su %s" % [effect.label, _host_name()])

func _on_expired(effect : StatusEffect) -> void:
	_aggiorna_aspetto()
	_emit_log("%s svanito da %s" % [effect.label, _host_name()])

func _host_name() -> String:
	var host := get_parent()
	return host.name if host else "?"
