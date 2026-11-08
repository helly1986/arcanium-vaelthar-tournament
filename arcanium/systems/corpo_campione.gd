extends Node

## ═══════════════════════════════════════════════════════════════════════════
## CORPO DEL CAMPIONE
## ═══════════════════════════════════════════════════════════════════════════
##
## Il giocatore ha il corpo del campione scelto nella selezione (la casata sta
## in SaveManager, la scheda in arcanium/resources/campioni/<casata>.tres).
##
## Il player e' costruito attorno al nodo `GeneralSkeleton` del protagonista:
## armi, scudo, sigillo, passi, IK dei piedi e scie lo puntano per percorso, e
## le clip per nome unico (`%GeneralSkeleton:<osso>`). Quel NODO quindi resta
## dov'e'; cambiano le sue OSSA, che diventano quelle del campione, e le mesh,
## che diventano le sue. Le ossa si chiamano gia' uguali (bone map Humanoid
## all'import), cambiano proporzioni e pose di riposo: le clip del moveset si
## portano sul nuovo riposo con rig_retarget.gd.
##
## Le vecchie armature non si vedono sul campione (decisione dell'autore,
## 2026-10-22): la sua armatura e' quella della casata, coi vessilli, e cio'
## che si equipaggia negli slot d'armatura sono imbottiture magiche. Il nodo
## che vestiva il protagonista (ArmaturaIndossata) si spegne.
##
## Gira PRIMA dell'AnimationTree: nella scena sta subito dopo `protagonist`.

const CARTELLA := "res://arcanium/resources/campioni/"
## I nodi delle armi in mano, dalla radice del player: la presa del campione
## (CampioneResource.presa_arma / presa_scudo) va li'.
const ARMA_IN_MANO := "WeaponSystem/RightHand/HandPivot/Sword"
const GADGET := "GadgetSystem"
## Dove sta lo scudo nella scena del player: in gioco puo' stare sul fianco (_gadget).
const SCUDO_IN_MANO := "GadgetSystem/LeftHand/HandPivot/Shield"
const Retarget := preload("res://arcanium/tools/rig_retarget.gd")
const StoffaSimulata := preload("res://arcanium/systems/stoffa_simulata.gd")
const PresaMano := preload("res://arcanium/systems/presa_mano.gd")
const ScintilleIdle := preload("res://arcanium/systems/scintille_idle.gd")
const PosaMenu := preload("res://arcanium/systems/posa_menu.gd")
const SecondaMano := preload("res://arcanium/systems/seconda_mano.gd")

@export var scheletro : Skeleton3D
@export var animazioni : AnimationPlayer
## Il nodo che vestiva il protagonista con le armature equipaggiate.
@export var armatura_indossata : Node
## Per i cancelli e le anteprime: la casata da indossare al posto di quella
## della run ("" = SaveManager).
@export var casata_forzata := ""

## Le librerie convertite, per campione e per libreria: la conversione costa
## circa un secondo per le 123 clip di MeleeLib, e ogni scontro ricarica la
## scena. Statica, sopravvive al cambio scena.
static var _cache := {}

var campione : Resource = null


func _ready() -> void:
	var casa := casata_forzata
	if casa == "":
		var salva := get_node_or_null("/root/SaveManager")
		casa = String(salva.get_house()) if salva != null else ""
	var percorso := CARTELLA + casa + ".tres"
	if casa == "" or not ResourceLoader.exists(percorso):
		return
	var c : Resource = load(percorso)
	if c == null or String(c.corpo) == "" or not ResourceLoader.exists(c.corpo):
		return
	indossa(c)


## Mette addosso al giocatore il corpo del campione `c`.
func indossa(c : Resource) -> void:
	if scheletro == null:
		push_warning("CorpoCampione: nessuno scheletro.")
		return
	var scena : Node = (load(c.corpo) as PackedScene).instantiate()
	## I corpi sullo scheletro ARP non portano la Posa: si ricava dal riposo.
	PosaMenu.assicura(scena)
	var nuovi := scena.find_children("*", "Skeleton3D", true, false)
	if nuovi.is_empty():
		scena.free()
		return
	var sk_c := nuovi[0] as Skeleton3D

	## Il riposo del protagonista serve da SORGENTE per convertire le clip:
	## si copia prima di cambiare le ossa.
	var sorgente := _copia_ossa(scheletro)

	## Le ossa del campione dentro il nodo di sempre.
	scheletro.clear_bones()
	for i in sk_c.get_bone_count():
		scheletro.add_bone(sk_c.get_bone_name(i))
	for i in sk_c.get_bone_count():
		scheletro.set_bone_parent(i, sk_c.get_bone_parent(i))
		scheletro.set_bone_rest(i, sk_c.get_bone_rest(i))
	scheletro.reset_bone_poses()
	## Il nodo armatura del GLB del campione puo' avere una sua trasformazione:
	## la porta anche il genitore del nostro scheletro.
	var arm := scheletro.get_parent() as Node3D
	var arm_c := sk_c.get_parent() as Node3D
	if arm != null and arm_c != null:
		arm.transform = arm_c.transform
	scheletro.transform = sk_c.transform

	## Le mesh: via quelle del protagonista, dentro quelle del campione. Si
	## svuotano invece di buttarle: sotto ArmorChest c'e' l'Area3D della
	## corazza, che il sistema d'equipaggiamento usa. Solo nascoste, la loro
	## Skin cercava ancora ossa del protagonista ("Skin bind ... no bone").
	for m in scheletro.get_children():
		if m is MeshInstance3D:
			var vecchia := m as MeshInstance3D
			vecchia.visible = false
			vecchia.skin = null
			vecchia.mesh = null
	for m in sk_c.get_children():
		if m is MeshInstance3D:
			var mi := m as MeshInstance3D
			sk_c.remove_child(mi)
			scheletro.add_child(mi)
			mi.owner = scheletro.owner
			mi.skeleton = NodePath("..")
	## Il tessuto del campione (mesh `Stoffa<N>`, docs/05 §4-quater) e' stoffa
	## simulata: il nodo che la muove nasce qui, dopo che le mesh sono passate
	## nello scheletro del giocatore.
	var ha_stoffe := false
	for m in scheletro.get_children():
		if m is MeshInstance3D and String(m.name).begins_with(StoffaSimulata.PREFISSO):
			ha_stoffe = true
	if ha_stoffe:
		var radice_stoffa := owner if owner != null else get_parent()
		var vecchia := radice_stoffa.get_node_or_null("StoffaSimulata")
		if vecchia != null:
			radice_stoffa.remove_child(vecchia)
			vecchia.free()
		var stoffa := StoffaSimulata.new()
		stoffa.name = "StoffaSimulata"
		stoffa.scheletro = scheletro
		stoffa.regolazione = c.stoffa
		radice_stoffa.add_child.call_deferred(stoffa)
	if armatura_indossata != null:
		armatura_indossata.process_mode = Node.PROCESS_MODE_DISABLED
		armatura_indossata.set_script(null)

	## Gli agganci alle ossa rileggono l'indice dell'osso dal nome.
	var radice := owner if owner != null else get_parent()
	for ba in radice.find_children("*", "BoneAttachment3D", true, false):
		var b := ba as BoneAttachment3D
		var nome := b.bone_name
		b.bone_name = ""
		b.bone_name = nome
	## La presa dell'arma che il giocatore ha in mano adesso (o di quella del
	## kit), e di nuovo a ogni cambio di TIPO d'arma: l'equipaggiamento e'
	## intercambiabile e ogni campione ha una presa per tipo
	## (CampioneResource.prese, 2026-11-02).
	var tipo := String(radice.get("weapon_type")) if "weapon_type" in radice else ""
	_applica_presa(c, tipo if tipo != "" else String(c.tipo_del_kit()))
	if radice.has_signal("weapon_change_ended") and not radice.weapon_change_ended.is_connected(_tipo_cambiato):
		radice.weapon_change_ended.connect(_tipo_cambiato)
	## E la sinistra cambia pezzo: lo scambio scudo-sigillo, lo scudo nell'armadio.
	var sistema := radice.get_node_or_null(GADGET)
	if sistema != null and sistema.has_signal("equipment_changed") and not sistema.equipment_changed.is_connected(_sinistra_cambiata):
		sistema.equipment_changed.connect(_sinistra_cambiata)
	var armadio := get_node_or_null("/root/EquipmentLoadout")
	if armadio != null and not armadio.changed.is_connected(_sinistra_cambiata):
		armadio.changed.connect(_sinistra_cambiata)
	_scintille(c, radice)

	## Le clip portate sul nuovo riposo.
	if animazioni != null:
		var sostituite := {}
		var posa := _posa_del_campione(scena)
		if posa != null:
			sostituite[IDLE_LEGGERA] = posa
		var d_autore := idle_d_autore(c.idle, scheletro)
		if d_autore != null and idle_sostituita(c) != "":
			sostituite[idle_sostituita(c)] = d_autore
		## Il moveset nostro di Cascadeur: si carica come l'idle d'autore.
		for nome_clip in c.clip_d_autore:
			var nostra := idle_d_autore(String(c.clip_d_autore[nome_clip]), scheletro)
			if nostra != null:
				sostituite[String(nome_clip)] = nostra
		for nome_lib in animazioni.get_animation_library_list():
			if String(nome_lib) == "":
				continue
			var lib := animazioni.get_animation_library(nome_lib)
			animazioni.remove_animation_library(nome_lib)
			animazioni.add_animation_library(nome_lib, _converti(c.casata, nome_lib, lib, sorgente,
					sostituite if String(nome_lib) == LIBRERIA_IDLE else {}))
	sorgente.free()
	scena.free()
	campione = c


func _tipo_cambiato(tipo) -> void:
	if campione != null:
		_applica_presa(campione, String(tipo))


func _sinistra_cambiata(_pezzo = null) -> void:
	var radice := owner if owner != null else get_parent()
	if campione != null and "weapon_type" in radice:
		_applica_presa(campione, String(radice.get("weapon_type")))


## Il gadget che dichiara `campo` nella sua risorsa, in mano o sul fianco.
func _gadget(radice : Node, campo : String) -> Node3D:
	var sistema := radice.get_node_or_null(GADGET)
	if sistema == null:
		return null
	for mount in [sistema.get("held_mount_point"), sistema.get("stored_mount_point")]:
		if mount == null:
			continue
		for g in mount.get_children():
			var info = g.get("equipment_info")
			if info != null and campo in info and info.get(campo):
				return g
	return null


## La presa di `c` per il tipo d'arma `tipo` (CampioneResource.presa_per):
## l'arma nella mano, le dita chiuse e, con le armi a due mani, la sinistra
## sull'asta. Sul corpo del Comandante (il rivale del battleground) i nodi
## delle mani non ci sono.
func _applica_presa(c : Resource, tipo : String) -> void:
	var p : Dictionary = c.presa_per(tipo)
	var radice := owner if owner != null else get_parent()
	var arma := radice.get_node_or_null(ARMA_IN_MANO) as Node3D
	if arma != null:
		arma.transform = p["presa_arma"]
	var scudo := _gadget(radice, "block_resistances")
	var sigillo := _gadget(radice, "is_spell_focus")
	var armadio := get_node_or_null("/root/EquipmentLoadout")
	var su_scudo : Dictionary = c.presa_sinistra("SCUDO", armadio.equipped_in("scudo") if armadio != null else null)
	var su_sigillo : Dictionary = c.presa_sinistra("SIGILLO")
	if scudo != null:
		scudo.transform = su_scudo["presa"]
	if sigillo != null and su_sigillo.has("presa"):
		sigillo.transform = su_sigillo["presa"]
	var con_scudo : bool = c.dotazione.has("scudo") and not tipo in ["BOW", "HEAVY"]
	## Le dita chiuse sull'impugnatura: le clip le lasciano a riposo (rig_retarget.gd).
	## L'arma posata per il sigillo (HeldWeapon.arma_riposta): la destra resta aperta.
	var posata : bool = arma != null and not arma.visible
	_presa("PresaManoDestra", "Right", 0.0 if posata else p["chiusura_mano_destra"], p["pollice_mano_destra"], arma)
	## La seconda mano sull'arma a due mani, prima che le dita si chiudano.
	var vecchia_sm := scheletro.get_node_or_null("SecondaMano")
	if vecchia_sm != null:
		scheletro.remove_child(vecchia_sm)
		vecchia_sm.free()
	if p["seconda_mano_attiva"] and not con_scudo:
		var sm := SecondaMano.new()
		sm.name = "SecondaMano"
		sm.relativa = p["seconda_mano"]
		sm.oggetto = arma
		scheletro.add_child(sm)
	## La sinistra si chiude sullo scudo se c'e', se no sull'arma: Zarine e
	## Aurin la tengono a due mani.
	## Con un'arma a una mano si chiude sul gadget che ha in mano.
	var sistema := radice.get_node_or_null(GADGET)
	var in_mano = sistema.get("current_equipment") if sistema != null else null
	var su_gadget : Dictionary = {}
	if not tipo in ["BOW", "HEAVY"] and in_mano != null:
		su_gadget = su_scudo if in_mano == scudo else su_sigillo
	if su_gadget.is_empty():
		_presa("PresaManoSinistra", "Left", p["chiusura_mano_sinistra"], p["pollice_mano_sinistra"],
				scudo if con_scudo else arma)
	else:
		_presa("PresaManoSinistra", "Left", su_gadget["chiusura"], su_gadget["pollice"], in_mano)


## Le scintille in un momento dell'idle d'autore (CampioneResource.idle_scintille).
func _scintille(c : Resource, radice : Node) -> void:
	var vecchie := scheletro.get_node_or_null("ScintilleIdle")
	if vecchie != null:
		scheletro.remove_child(vecchie)
		vecchie.free()
	if c.idle_scintille < 0.0 or String(c.idle) == "" or scheletro.find_bone(c.idle_scintille_osso) < 0:
		return
	var s := ScintilleIdle.new()
	s.name = "ScintilleIdle"
	s.bone_name = c.idle_scintille_osso
	s.momento = c.idle_scintille
	s.albero = radice.get("animation_tree")
	scheletro.add_child(s)


func _presa(nome : String, lato : String, chiusura : float, pollice : float, oggetto : Node3D) -> void:
	var vecchia := scheletro.get_node_or_null(nome)
	if vecchia != null:
		scheletro.remove_child(vecchia)
		vecchia.free()
	if chiusura == 0.0:
		return
	var p := PresaMano.new()
	p.name = nome
	p.lato = lato
	p.chiusura = chiusura
	p.pollice = pollice
	p.oggetto = oggetto
	scheletro.add_child(p)


## Da fermo il campione suona la sua IDLE D'AUTORE (CampioneResource.idle,
## pose chiave in Cascadeur e fisica dell'autore: Edran dal 2026-10-23); chi
## non l'ha ancora sta nella sua POSA (la clip che monta_campione.py cuoce nel
## GLB: in piedi, braccia lungo i fianchi, un respiro). Mai la guardia del
## moveset con le mani unite davanti al petto: richiesta dell'autore del
## 2026-10-22. La Posa sostituisce LightIdle; HeavyIdle resta, l'arma a due
## mani vuole la sua presa.
##
## L'idle d'autore prende il posto dell'idle del TIPO dell'arma del kit: con
## un'arma a due mani e' la HeavyIdle (Zarine, Aurin), e allora parte dalla sua
## posa e ci torna, con le mani sull'arma (docs/campioni_concept.md, idle
## riscritte il 2026-10-23). Con un'arma d'altro tipo in mano il campione ha
## l'idle del moveset di quel tipo: il gesto della sua arma non si fa con
## un'altra.
const LIBRERIA_IDLE := "MeleeLib"
const IDLE_LEGGERA := "LightIdle"
const IDLE_PER_TIPO := {"SLASH": IDLE_LEGGERA, "HEAVY": "HeavyIdle"}


## La clip del moveset che l'idle d'autore di `c` sostituisce, dal tipo
## dell'arma del suo kit; "" se quel tipo non ha ancora un'idle sostituibile
## (l'arco suona la sua).
static func idle_sostituita(c : Resource) -> String:
	if not c.dotazione.has("arma_primaria"):
		return IDLE_LEGGERA
	var arma : Resource = load(c.dotazione["arma_primaria"])
	return IDLE_PER_TIPO.get(String(arma.object_type) if arma != null else "SLASH", "")


func _converti(casa : String, nome : StringName, lib : AnimationLibrary, sorgente : Skeleton3D,
		sostituite : Dictionary = {}) -> AnimationLibrary:
	## Lo stesso campione puo' vestire corpi diversi (il giocatore, l'arcimago
	## rivale del battleground sul corpo del Comandante): la chiave tiene anche
	## la scena di chi lo indossa, perche' il riposo di partenza cambia.
	var chi := get_parent()
	var radice : String = String(chi.scene_file_path) if chi != null else ""
	var chiave := "%s/%s/%s" % [radice, casa, nome]
	if _cache.has(chiave):
		return _cache[chiave]
	var nuova := AnimationLibrary.new()
	for clip in lib.get_animation_list():
		if sostituite.has(String(clip)):
			nuova.add_animation(clip, sostituite[String(clip)])
		else:
			nuova.add_animation(clip, Retarget.retarget(lib.get_animation(clip), sorgente, scheletro))
	_cache[chiave] = nuova
	return nuova


## La clip `Posa` del GLB del campione, con le tracce rivolte al nostro
## scheletro. E' gia' sul riposo del campione: non serve convertirla.
func _posa_del_campione(scena : Node) -> Animation:
	for ap in scena.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		if a.has_animation("Posa"):
			return _per_lo_scheletro(a.get_animation("Posa"))
	return null


## La clip del GLB `percorso` (l'idle d'autore della scheda), con le tracce
## rivolte al nostro scheletro; null se non c'e'. E' animata sul riposo del
## corpo su cui l'ha fatta l'autore, che il GLB porta con se'. Se `su` ha lo
## stesso riposo (il corpo Nephilite del campione) non si converte; su un
## altro riposo si porta col retarget (il corpo ARP, 2026-11-02: presa cosi'
## com'era, Edran stava a braccia giu' con lo scudo sul fianco).
static func idle_d_autore(percorso : String, su : Skeleton3D = null) -> Animation:
	if percorso == "" or not ResourceLoader.exists(percorso):
		return null
	var scena : Node = (load(percorso) as PackedScene).instantiate()
	var aps := scena.find_children("*", "AnimationPlayer", true, false)
	var clip : Animation = null
	if not aps.is_empty():
		var a := aps[0] as AnimationPlayer
		if not a.get_animation_list().is_empty():
			clip = a.get_animation(a.get_animation_list()[0])
			var sks := scena.find_children("*", "Skeleton3D", true, false)
			if su != null and not sks.is_empty() and not Retarget.stesso_riposo(sks[0], su):
				clip = Retarget.retarget(_per_lo_scheletro(clip), sks[0], su)
				clip.loop_mode = Animation.LOOP_LINEAR
			else:
				clip = _per_lo_scheletro(clip)
				## L'import con la bone map divide le tracce di posizione per
				## l'altezza del bacino del GLB (il suo motion_scale, 1,051 su
				## Edran ARP), e chi suona le rimoltiplica per il SUO: lo
				## scheletro del player ha quello del protagonista (1,014). Senza
				## questo il cammino di Cascadeur andava a 1,37 m/s invece di
				## 1,44 e il bacino stava 3,7 cm sotto (2026-11-08).
				if su != null and not sks.is_empty() and su.motion_scale > 0.0:
					_scala_posizioni(clip, (sks[0] as Skeleton3D).motion_scale / su.motion_scale)
	scena.free()
	return clip


## Moltiplica per `k` ogni chiave delle tracce di posizione di `clip`.
static func _scala_posizioni(clip : Animation, k : float) -> void:
	if is_equal_approx(k, 1.0):
		return
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		for i in clip.track_get_key_count(t):
			clip.track_set_key_value(t, i, (clip.track_get_key_value(t, i) as Vector3) * k)


## Una copia della clip in loop, con le tracce su `%GeneralSkeleton:<osso>`.
static func _per_lo_scheletro(sorgente : Animation) -> Animation:
	var p := sorgente.duplicate() as Animation
	for t in p.get_track_count():
		var osso := String(p.track_get_path(t).get_concatenated_subnames())
		p.track_set_path(t, NodePath("%GeneralSkeleton:" + osso))
	p.loop_mode = Animation.LOOP_LINEAR
	return p


func _copia_ossa(da : Skeleton3D) -> Skeleton3D:
	var sk := Skeleton3D.new()
	for i in da.get_bone_count():
		sk.add_bone(da.get_bone_name(i))
	for i in da.get_bone_count():
		sk.set_bone_parent(i, da.get_bone_parent(i))
		sk.set_bone_rest(i, da.get_bone_rest(i))
	return sk
