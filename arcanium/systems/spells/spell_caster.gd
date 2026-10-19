extends Node3D
class_name SpellCaster

## ⚠️ `class_name` deve stare PRIMA di qualunque `const`: con il preload sopra,
## Godot 4 rifiuta il file con «Unexpected "class_name" in class body», e il
## guasto non resta qui — senza la classe globale `SpellCaster` non compila più
## nemmeno `player_charbody3D.gd`, che la usa come tipo.
const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const Comparsa := preload("res://arcanium/systems/vfx/comparsa_evocazione.gd")

## Campi che una SummonSpellResource può imporre alla creatura che istanzia.
## È il ponte fra il .tres (che descrive UNA evocazione) e summoned_minion.tscn
## (che è UNA scena per tutte): il travaso avviene solo se il nome esiste da
## entrambe le parti, quindi aggiungere un campo qui non rompe nulla e
## dimenticarsene lo rende semplicemente inefficace.
##
## ⚠️ Aggiungendo un campo a SummonSpellResource, aggiungilo ANCHE qui — è
## l'errore più facile da fare e il più silenzioso: il valore resta scritto nel
## .tres, l'ispettore lo mostra, e in gioco non succede niente.
const CAMPI_MINION := [
	"arcanium_per_sec", "summon_family",
	"minion_tint", "minion_health", "minion_scale",
	"minion_model", "minion_height", "minion_hover",
	"can_attack", "blast_power", "blast_damage_type", "blast_radius",
	"attack_range", "attack_cooldown", "blast_frozen_buildup", "riflette",
	"move_speed", "follow_distance",
	"corpo_spirito", "attacco",
]

## Componente di lancio incantesimi del player. Ricalca Lite/Archmage.js
## `_handleSpellInput` (consuma Arcanium Vivo, applica cooldown, istanzia il
## proiettile con posizione/direzione correnti) ma in forma di nodo Godot
## riusabile: chi lo possiede (player_charbody3D.gd, FUORI dal mio ambito —
## vedi INTEGRAZIONE RICHIESTA nel report) chiama semplicemente `cast(...)`.
##
## CONTRATTO PUBBLICO (non cambiare firma — altri stream dipendono da questa):
##   func cast(spell: ArcaniumSpellResource, origin: Vector3, direction: Vector3) -> bool
## Ritorna true se il lancio è avvenuto (cooldown libero + Arcanium sufficiente),
## false altrimenti (nessun effetto collaterale in caso di false).

## Pool di Arcanium Vivo da cui spendere il costo dello spell.
@export var vitals : PlayerVitals
## Nodo a cui appendere i proiettili istanziati. Se null, usa
## get_tree().current_scene (comodo in editor/test, ma un parent esplicito
## evita sorprese se la scena root non è quella di gioco).
@export var projectile_parent : Node

signal cast_performed(spell : ArcaniumSpellResource)
signal cast_failed(spell : ArcaniumSpellResource)

## spell (Resource) → timestamp (s, OrologioGioco.adesso()) di riuso.
var _cooldown_until : Dictionary = {}

## Evocazioni attualmente vive, PER RISORSA SPELL (una alla volta per tipo,
## vedi SummonSpellResource.max_active — oggi sempre 1). Chiave = spell
## (Resource) → istanza Node3D del minion. Ripulita da sé quando il minion
## esce dall'albero (morte o scena cambiata), vedi _spawn_summon.
var _active_summons : Dictionary = {}

## Evocazioni GIÀ PAGATE ma non ancora comparse, quando `cast_summon` lavora con
## un ritardo. Chiave = spell (Resource) → true.
## ⚠️ Non basta guardare `_active_summons`: lì dentro il minion entra solo
## quando esiste davvero, quindi durante l'attesa il posto risulta libero e
## ripremere il tasto pagherebbe una seconda volta facendo comparire due minion.
var _summons_in_arrivo : Dictionary = {}

func cast(spell : ArcaniumSpellResource, origin : Vector3, direction : Vector3) -> bool:
	if spell == null:
		return false
	if not _try_consume(spell):
		return false
	_spawn_projectile(spell, origin, direction)
	cast_performed.emit(spell)
	return true

## Come cast(), ma il proiettile compare dopo `delay` secondi, mentre costo e
## cooldown si pagano SUBITO. Serve a sincronizzare lo spawn col gesto: prima il
## proiettile partiva all'istante della pressione e l'animazione arrivava dopo,
## facendolo sembrare sganciato dal personaggio.
## Costo immediato e spawn ritardato non sono un dettaglio: pagare al rilascio
## permetterebbe di spammare il tasto durante l'attesa spendendo una volta sola.
## `aim_source`: nodo opzionale da cui RICALCOLARE origine e direzione al momento
## del rilascio (tipicamente il player). Passandolo, il colpo parte da dove sei
## quando la mano si apre, non da dove eri quando hai premuto.
func cast_delayed(spell : ArcaniumSpellResource, origin : Vector3, direction : Vector3,
		delay : float, aim_source : Node3D = null, muzzle_height : float = 0.0,
		muzzle_forward : float = 0.0) -> bool:
	if spell == null:
		return false
	if not _try_consume(spell):
		return false
	cast_performed.emit(spell)
	if delay <= 0.0:
		_spawn_projectile(spell, origin, direction)
	else:
		## ⚠️ L'attesa sta in un metodo SEPARATO, chiamato senza `await`: se
		## `cast_delayed` contenesse essa stessa un `await`, chiamarla senza
		## attenderla non restituirebbe più un bool e il controllo
		## "ho abbastanza Arcanium?" del chiamante accetterebbe qualunque cosa.
		_spawn_projectile_after(spell, origin, direction, delay, aim_source,
			muzzle_height, muzzle_forward)
	return true

func _spawn_projectile_after(spell : ArcaniumSpellResource, origin : Vector3,
		direction : Vector3, delay : float, aim_source : Node3D,
		muzzle_height : float, muzzle_forward : float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return  ## costo già pagato: la scena è cambiata, niente spawn
	var o := origin
	var d := direction
	if is_instance_valid(aim_source):
		## +Z = avanti (vedi player_charbody3D.cast_spell).
		d = aim_source.global_transform.basis.z.normalized()
		o = aim_source.global_position + Vector3.UP * muzzle_height + d * muzzle_forward
		## ⚠️ Qui la direzione viene RICALCOLATA, quindi qualunque mira passata
		## dal chiamante andrebbe persa: l'inclinazione verso il bersaglio va
		## rifatta anche qui, o il colpo riparte orizzontale e sopra un nemico
		## basso passa sopra.
		if aim_source.has_method("aim_direction_from"):
			d = aim_source.aim_direction_from(o, d)
	_spawn_projectile(spell, o, d)

## Variante POSIZIONALE di cast(): risolve lo spell in un PUNTO (tipicamente il
## centro del decal scelto dal player durante il piazzamento — vedi
## PlacementController), non lungo una direzione. Stessa logica di
## costo/cooldown di cast() (fattorizzata in _try_consume), ma spawna
## `spell.aoe_field_scene` invece di `spell.projectile_scene`.
## ⚠️ NON è un cambio di firma di cast(): è un metodo pubblico aggiuntivo — il
## contratto esistente `cast(spell, origin, direction) -> bool` resta invariato.
func cast_positional(spell : ArcaniumSpellResource, position : Vector3) -> bool:
	if spell == null:
		return false
	if not _try_consume(spell):
		return false
	_spawn_field(spell, position)
	cast_performed.emit(spell)
	return true

## Verifica cooldown + spesa Arcanium ed EFFETTIVAMENTE spende/avvia il
## cooldown se entrambi passano. Condiviso da cast() e cast_positional().
## Nessun effetto collaterale se ritorna false (coerente col contratto di cast()).
func _try_consume(spell : ArcaniumSpellResource) -> bool:
	var now := OrologioGioco.adesso()
	if now < float(_cooldown_until.get(spell, 0.0)):
		cast_failed.emit(spell)
		return false

	if vitals == null or not vitals.spend_arcanium(spell.cost):
		cast_failed.emit(spell)
		return false

	if spell.cooldown > 0.0:
		_cooldown_until[spell] = now + spell.cooldown
	return true

func _spawn_projectile(spell : ArcaniumSpellResource, origin : Vector3, direction : Vector3) -> void:
	if spell.projectile_scene == null:
		push_warning("SpellCaster: spell '%s' non ha projectile_scene assegnata." % spell.name)
		return

	var dir := direction
	if dir.length() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector3.FORWARD

	var proj := spell.projectile_scene.instantiate()
	if proj is IceShardProjectile or "direction" in proj:
		proj.direction = dir
		proj.speed = spell.projectile_speed
		proj.damage = spell.damage
		proj.radius = spell.projectile_radius
		proj.lifetime = spell.lifetime
		proj.color = spell.color
		proj.frozen_buildup = spell.frozen_buildup
		proj.damage_type = spell.damage_type
		# Niente `faction`: la deduce `Fazioni` dal caster. Il caster DEVE essere
		# il corpo del player (questo nodo è creato da player_charbody3D.gd come
		# suo figlio) — un caster sbagliato significa proiettile senza fazione,
		# cioè che ferisce chiunque.
		proj.caster = get_parent() if get_parent() else self

	var parent := projectile_parent if projectile_parent else get_tree().current_scene
	parent.add_child(proj)
	if proj is Node3D:
		proj.global_position = origin

## Variante SUMMON di cast(): niente proiettile né campo, istanzia
## `spell.minion_scene` davanti al player. Se il minion di QUESTA risorsa è già
## vivo, non ne evoca un secondo (né spende nulla): lo riposiziona all'origine
## corrente, comodo se è rimasto indietro o incastrato. Ritorna true SOLO
## quando una nuova evocazione avviene — il riposizionamento è un effetto
## voluto ma gratuito, coerente con "nessuna spesa aggiuntiva sul già vivo".
## `forward`: direzione in cui il player guarda, usata per piazzare il minion
## qualche passo avanti invece che esattamente sui piedi.
##
## `delay`: secondi fra il lancio e la comparsa del minion. Stesso modello di
## `cast_delayed`: costo e cooldown si pagano SUBITO, la materializzazione
## arriva dopo, così l'evocazione affiora quando il gesto dell'animazione lo
## dice e non nell'istante del click. Con 0.0 il comportamento è quello di
## sempre — comparsa immediata.
func cast_summon(spell : ArcaniumSpellResource, origin : Vector3, forward : Vector3,
		delay : float = 0.0) -> bool:
	if spell == null:
		return false
	var existing = _active_summons.get(spell)
	if existing != null and is_instance_valid(existing):
		existing.global_position = origin
		return false
	if _summons_in_arrivo.get(spell, false):
		return false  ## già pagata, sta per comparire: non se ne paga una seconda
	## ⚠️ La scena del minion si verifica PRIMA di spendere: dopo `_try_consume`
	## l'Arcanium è andato e non si può restituire, e una risorsa mal configurata
	## si mangiava il costo senza evocare nulla.
	if not ("minion_scene" in spell) or spell.minion_scene == null:
		push_warning("SpellCaster: spell '%s' non ha minion_scene assegnata." % spell.name)
		return false
	if not _try_consume(spell):
		return false
	cast_performed.emit(spell)
	_suona_carica(delay)
	if delay <= 0.0:
		return _materializza(spell, origin, forward)
	_summons_in_arrivo[spell] = true
	## Come in `cast_delayed`, l'attesa sta in un metodo SEPARATO chiamato senza
	## `await`: un `await` qui dentro farebbe restituire una coroutine invece di
	## un bool, e il chiamante prenderebbe qualunque cosa per un successo.
	_spawn_summon_after(spell, origin, forward, delay)
	return true

## Istanzia il minion e lo registra fra quelli vivi. Ritorna false se la scena
## non ha prodotto un Node3D.
func _materializza(spell : ArcaniumSpellResource, origin : Vector3, forward : Vector3) -> bool:
	var minion := _spawn_summon(spell, origin, forward)
	if minion == null:
		return false
	_active_summons[spell] = minion
	return true

func _spawn_summon_after(spell : ArcaniumSpellResource, origin : Vector3,
		forward : Vector3, delay : float) -> void:
	await get_tree().create_timer(delay).timeout
	_summons_in_arrivo.erase(spell)
	if not is_inside_tree():
		return  ## costo già pagato: la scena è cambiata, niente evocazione
	_materializza(spell, origin, forward)

func _spawn_summon(spell : ArcaniumSpellResource, origin : Vector3, forward : Vector3) -> Node3D:
	if not ("minion_scene" in spell) or spell.minion_scene == null:
		push_warning("SpellCaster: spell '%s' non ha minion_scene assegnata." % spell.name)
		return null

	var minion : Node = spell.minion_scene.instantiate()

	## Contratto duck-typed con summoned_minion.gd: follow_target = chi seguire
	## (il player, cioè get_parent() di questo SpellCaster — stesso pattern di
	## `caster = get_parent()` usato in _spawn_projectile), vitals = pool da cui
	## il minion rimpingua l'Arcanium Vivo, e i CAMPI_MINION dalla risorsa
	## (sovrascrivono i default della scena, dato che una scena sola serve tutte
	## le evocazioni di casata con numeri e colori diversi).
	##
	## ⚠️ TUTTO QUESTO VA PRIMA DI `add_child`. `add_child` fa scattare `_ready`,
	## ed è lì dentro che il minion si veste della casata (tinta della mesh, HP,
	## taglia, sigillo a terra): assegnare i campi dopo significava costruire il
	## sigillo col colore sbagliato e la vita della scena, e vedersi poi cambiare
	## solo i numeri. Prima l'ordine era invertito e non si notava perché
	## l'unico campo travasato (`arcanium_per_sec`) non viene letto in `_ready`.
	if "follow_target" in minion:
		minion.follow_target = get_parent()
	if "vitals" in minion:
		minion.vitals = vitals
	for campo in CAMPI_MINION:
		if campo in spell and campo in minion:
			minion.set(campo, spell.get(campo))

	var parent := projectile_parent if projectile_parent else get_tree().current_scene
	parent.add_child(minion)

	if minion is Node3D:
		minion.global_position = origin
		## Stessa materializzazione dei lupi del richiamo: l'evocazione affiora
		## col suo vortice invece di comparire intera.
		Comparsa.avvia(minion)

	minion.tree_exiting.connect(func() -> void:
		if _active_summons.get(spell) == minion:
			_active_summons.erase(spell)
	)

	return minion as Node3D

## Istanzia il campo AoE di uno spell posizionale al centro `position`. Duck
## typing sui campi esposti dal contratto spell_aoe_field.gd (radius, duration,
## color, status_buildup_per_sec, damage_type), stesso stile di _spawn_projectile.
func _spawn_field(spell : ArcaniumSpellResource, position : Vector3) -> void:
	if spell.aoe_field_scene == null:
		push_warning("SpellCaster: spell '%s' non ha aoe_field_scene assegnata." % spell.name)
		return

	var field := spell.aoe_field_scene.instantiate()
	if "radius" in field:
		field.radius = spell.aoe_radius
	if "duration" in field:
		field.duration = spell.aoe_duration
	if "color" in field:
		field.color = spell.color
	if "status_buildup_per_sec" in field:
		field.status_buildup_per_sec = spell.aoe_status_buildup_per_sec
	if "damage_type" in field:
		field.damage_type = spell.damage_type

	var parent := projectile_parent if projectile_parent else get_tree().current_scene
	parent.add_child(field)
	if field is Node3D:
		field.global_position = position


## ─── LA CARICA DELL'EVOCAZIONE ──────────────────────────────────────────────
##
## Lo stesso campione della carica del Senza Nome. ⚠️ Non e' pigrizia: e'
## esattamente ciò che deve dire. L'Arcanium è uno solo, e un'evocazione del
## protagonista attinge alla stessa cosa a cui attinge lui — che il suono sia
## riconoscibilmente lo stesso è un pezzo di racconto, non un riuso.
##
## ⚠️ Il TONO si alza in proporzione all'attesa. Il campione dura ~3.9 s e sale
## fino al rilascio, mentre `delay` (il tempo fra il gesto e la materializzazione)
## è tipicamente sotto il secondo: senza comprimere la salita, la creatura
## comparirebbe mentre il suono sta ancora caricando, e il culmine arriverebbe
## sul vuoto. Alzando il tono la salita si accorcia e il culmine cade sulla
## comparsa — che è il momento che deve sentirsi.
##
## Piu' acuto della carica del boss anche a parita' di durata: e' magia di un
## uomo, non di ciò che il Senza Nome è diventato.
const CARICA_DURATA := 3.9
const CARICA_TONO_MIN := 1.15
const CARICA_TONO_MAX := 2.6

func _suona_carica(delay : float) -> void:
	var p := Suoni.nel_mondo(self, Suoni.CARICA_ARCANA, -5.0, 0.0)
	if p == null:
		return
	## Con delay 0 (comparsa immediata) non c'è nessuna attesa da riempire: si
	## sta al minimo, che è già un accenno rapido.
	if delay <= 0.05:
		p.pitch_scale = CARICA_TONO_MAX
		return
	p.pitch_scale = clampf(CARICA_DURATA / delay, CARICA_TONO_MIN, CARICA_TONO_MAX)
