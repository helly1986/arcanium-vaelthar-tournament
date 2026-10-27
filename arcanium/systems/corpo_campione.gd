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
const SCUDO_IN_MANO := "GadgetSystem/LeftHand/HandPivot/Shield"
const Retarget := preload("res://arcanium/tools/rig_retarget.gd")
const StoffaSimulata := preload("res://arcanium/systems/stoffa_simulata.gd")
const PresaMano := preload("res://arcanium/systems/presa_mano.gd")
const ScintilleIdle := preload("res://arcanium/systems/scintille_idle.gd")

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
	## La presa nelle mani di questo corpo. Sul corpo del Comandante (il
	## rivale del battleground) questi nodi non ci sono.
	var arma := radice.get_node_or_null(ARMA_IN_MANO) as Node3D
	if arma != null:
		arma.transform = c.presa_arma
	var scudo := radice.get_node_or_null(SCUDO_IN_MANO) as Node3D
	if scudo != null:
		scudo.transform = c.presa_scudo
	## Le dita chiuse sull'impugnatura, sopra le clip (che sono del protagonista).
	_presa("PresaManoDestra", "Right", c.chiusura_mano_destra, arma)
	_presa("PresaManoSinistra", "Left", c.chiusura_mano_sinistra, scudo)
	_scintille(c, radice)

	## Le clip portate sul nuovo riposo.
	if animazioni != null:
		var sostituite := {}
		var posa := _posa_del_campione(scena)
		if posa != null:
			sostituite[IDLE_LEGGERA] = posa
		var d_autore := idle_d_autore(c.idle)
		if d_autore != null and idle_sostituita(c) != "":
			sostituite[idle_sostituita(c)] = d_autore
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


func _presa(nome : String, lato : String, chiusura : float, oggetto : Node3D) -> void:
	var vecchia := scheletro.get_node_or_null(nome)
	if vecchia != null:
		scheletro.remove_child(vecchia)
		vecchia.free()
	if chiusura <= 0.0:
		return
	var p := PresaMano.new()
	p.name = nome
	p.lato = lato
	p.chiusura = chiusura
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
## rivolte al nostro scheletro; null se non c'e'. Come la Posa e' animata sul
## riposo del campione stesso (stessa bone map all'import): non si converte.
static func idle_d_autore(percorso : String) -> Animation:
	if percorso == "" or not ResourceLoader.exists(percorso):
		return null
	var scena : Node = (load(percorso) as PackedScene).instantiate()
	var aps := scena.find_children("*", "AnimationPlayer", true, false)
	var clip : Animation = null
	if not aps.is_empty():
		var a := aps[0] as AnimationPlayer
		if not a.get_animation_list().is_empty():
			clip = _per_lo_scheletro(a.get_animation(a.get_animation_list()[0]))
	scena.free()
	return clip


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
