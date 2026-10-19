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
## Se true stampa in console ogni evento di status (comodo per il playtest).
@export var log_to_console : bool = true

## id → StatusEffect
var _effects : Dictionary = {}

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

func get_effect(id : String) -> StatusEffect:
	return _effects.get(id, null)

## Le barre di ACCUMULO in corso (non ancora scattate), per la HUD: oggi solo la
## Lacerazione, che chiede di vedere la barra salire come in Elden Ring.
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
	var f := get_effect("fracture")
	if f and f is FractureEffect:
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
		f.add_buildup(amount)

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
		l.add_buildup(amount)

## CURA uno stato: azzera la sua barra d'accumulo e, se e' scattato, lo chiude.
## Vera se c'era qualcosa da curare (un consumabile sprecato non si consuma).
## Le Bende dell'Eco (LORE/ITEMS_LORE: «rimuove Lacerazione, stoppa la barra»).
func cura(id : String) -> bool:
	var e := get_effect(id)
	if e == null:
		return false
	var fatto := false
	if "meter" in e and float(e.get("meter")) > 0.0:
		e.set("meter", 0.0)
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

func _on_applied(effect : StatusEffect) -> void:
	_emit_log("%s applicato su %s (%.1fs)" % [effect.label, _host_name(), effect.duration])

func _on_refreshed(effect : StatusEffect) -> void:
	_emit_log("%s rinnovato su %s" % [effect.label, _host_name()])

func _on_expired(effect : StatusEffect) -> void:
	_emit_log("%s svanito da %s" % [effect.label, _host_name()])

func _host_name() -> String:
	var host := get_parent()
	return host.name if host else "?"
