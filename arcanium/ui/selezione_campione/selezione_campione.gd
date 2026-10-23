extends Control

## La SELEZIONE DEL CAMPIONE, l'antefatto della run (decisione dell'autore del
## 2026-10-21): a sinistra le sei casate col loro campione, al centro il
## campione in 3D che si gira trascinando (mouse, dito, levetta), a destra la
## sua bio, quella della casata, Marche, kit, affinita' e abilita'.
##
## Legge i campioni da arcanium/resources/campioni/*.tres (CampioneResource):
## un campione in piu' e' un file in piu'. Chi non e' ancora forgiato si
## vede come SAGOMA (manichino del suo genere, bordo nel colore della casata).
## Chi non e' sbloccato si guarda ma non si sceglie.
##
## Stessi segnali della vecchia creazione del personaggio: il menu principale
## non cambia (confirmed avvia la run).

signal confirmed(house_id : String, gender : String)
signal cancelled

const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")
const MarcheStats := preload("res://arcanium/resources/marche_stats.gd")
const MenuStyle := preload("res://arcanium/ui/game_menu/er_style.gd")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")
const Ornati := preload("res://arcanium/ui/theme/ornati.gd")
const SAGOMA := preload("res://arcanium/ui/selezione_campione/sagoma.gdshader")
const CARTELLA := "res://arcanium/resources/campioni/"
const MANICHINI := {
	"male": "res://assets/characters/mannyquin.glb",
	"female": "res://assets/characters/minnyquinn.glb",
}
## La clip della posa del menu dentro il GLB del campione (esporta_glb(posa=...)).
const POSA_MENU := "Posa"
const CorpoCampione := preload("res://arcanium/systems/corpo_campione.gd")
## Altezza a cui si porta ogni corpo nella preview, in metri.
const ALTEZZA := 1.8

var campioni : Array = []
var scelto := 0
var _voci : Array[Button] = []
var _testo : RichTextLabel
var _inizia : Button
var _perno : Node3D
var _corpo : Node3D
var _luce_bordo : OmniLight3D
var _trascina := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_carica()
	_costruisci()
	var parti := 0
	for i in campioni.size():
		if _sbloccato(campioni[i]):
			parti = i
			break
	_scegli(parti)


func _carica() -> void:
	var file : Array = []
	for f in DirAccess.get_files_at(CARTELLA):
		if f.ends_with(".tres"):
			file.append(f)
	var c := {}
	for f in file:
		var r : Resource = load(CARTELLA + f)
		if r != null:
			c[r.casata] = r
	## L'ordine del catalogo delle casate; quelle senza campione restano fuori.
	for id in HouseCatalog.ORDER:
		if c.has(id):
			campioni.append(c[id])


func _sbloccato(c : Resource) -> bool:
	return String(HouseCatalog.get_house(c.casata).get("state", "locked")) == "unlocked"


## ─── Costruzione ─────────────────────────────────────────────────────────────

func _costruisci() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0.02, 0.018, 0.022, 0.97)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var margini := MarginContainer.new()
	margini.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "right", "top", "bottom"]:
		margini.add_theme_constant_override("margin_" + lato, 28)
	add_child(margini)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margini.add_child(col)

	var titolo := Label.new()
	titolo.text = MenuStyle.spaziato("Choose your champion")
	titolo.add_theme_font_override("font", FONT_TITOLO)
	titolo.add_theme_font_size_override("font_size", 28)
	titolo.add_theme_color_override("font_color", MenuStyle.ORO)
	titolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(titolo)

	var riga := HBoxContainer.new()
	riga.size_flags_vertical = Control.SIZE_EXPAND_FILL
	riga.add_theme_constant_override("separation", 20)
	col.add_child(riga)
	riga.add_child(_colonna_casate())
	riga.add_child(_anteprima())
	riga.add_child(_scheda())

	var piede := HBoxContainer.new()
	piede.alignment = BoxContainer.ALIGNMENT_CENTER
	piede.add_theme_constant_override("separation", 24)
	col.add_child(piede)
	var indietro := _bottone("Back", Vector2(200, 52))
	indietro.pressed.connect(func(): cancelled.emit())
	piede.add_child(indietro)
	_inizia = _bottone("Begin", Vector2(240, 52))
	_inizia.pressed.connect(_conferma)
	piede.add_child(_inizia)


func _colonna_casate() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in campioni.size():
		var c : Resource = campioni[i]
		var casa := HouseCatalog.get_house(c.casata)
		var testo := "%s\n%s" % [c.nome, String(casa.get("name", c.casata))]
		if not _sbloccato(c):
			testo = "🔒  " + testo
		var b := _bottone(testo, Vector2(300, 64))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", Color(String(casa.get("color", "#cccccc"))).lerp(Color(0.92, 0.88, 0.80), 0.55))
		if not _sbloccato(c):
			b.modulate = Color(0.62, 0.6, 0.62)
		var idx := i
		b.focus_entered.connect(func(): _scegli(idx))
		b.pressed.connect(func(): _scegli(idx))
		v.add_child(b)
		_voci.append(b)
	return v


func _anteprima() -> Control:
	var cont := SubViewportContainer.new()
	cont.name = "Anteprima"
	cont.stretch = true
	cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cont.custom_minimum_size = Vector2(380, 0)
	cont.mouse_filter = Control.MOUSE_FILTER_STOP
	cont.gui_input.connect(_su_input_anteprima)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(vp)
	var mondo := Node3D.new()
	vp.add_child(mondo)
	var cam := Camera3D.new()
	## Fuori dall'albero look_at() non va: la trasformazione si scrive.
	cam.transform = Transform3D(Basis(), Vector3(0, 1.05, 3.4)).looking_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.fov = 38.0
	mondo.add_child(cam)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-35, 30, 0)
	sole.light_energy = 1.4
	mondo.add_child(sole)
	_luce_bordo = OmniLight3D.new()
	_luce_bordo.position = Vector3(-1.2, 1.6, -1.4)
	_luce_bordo.omni_range = 5.0
	_luce_bordo.light_energy = 2.5
	mondo.add_child(_luce_bordo)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.33, 0.38)
	env.environment.ambient_light_energy = 0.6
	mondo.add_child(env)
	## La pedana: un disco scuro su cui il campione sta.
	var pedana := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = 0.7
	disco.bottom_radius = 0.75
	disco.height = 0.06
	pedana.mesh = disco
	pedana.position.y = -0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.06, 0.06)
	mat.roughness = 0.6
	mat.metallic = 0.4
	pedana.material_override = mat
	mondo.add_child(pedana)
	_perno = Node3D.new()
	_perno.name = "Perno"
	mondo.add_child(_perno)
	return cont


func _scheda() -> Control:
	var box := Ornati.pannello(Vector2(440, 0))
	var scorri := ScrollContainer.new()
	scorri.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ornati.contenuto(box).add_child(scorri)
	_testo = RichTextLabel.new()
	_testo.name = "Scheda"
	_testo.bbcode_enabled = true
	_testo.fit_content = true
	_testo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_testo.add_theme_font_override("bold_font", FONT_TITOLO)
	_testo.add_theme_font_size_override("normal_font_size", 16)
	_testo.add_theme_font_size_override("bold_font_size", 15)
	scorri.add_child(_testo)
	return box


func _bottone(testo : String, minimo : Vector2) -> Button:
	return Ornati.bottone(testo, minimo)


## ─── Scelta ──────────────────────────────────────────────────────────────────

func _scegli(i : int) -> void:
	if campioni.is_empty():
		return
	scelto = clampi(i, 0, campioni.size() - 1)
	var c : Resource = campioni[scelto]
	var casa := HouseCatalog.get_house(c.casata)
	var colore := Color(String(casa.get("color", "#8fbfe0")))
	_luce_bordo.light_color = colore
	_mostra_corpo(c, colore)
	_testo.text = _bbcode(c, casa, colore)
	_inizia.disabled = not _sbloccato(c)
	if not _voci[scelto].has_focus():
		_voci[scelto].grab_focus()


func _bbcode(c : Resource, casa : Dictionary, colore : Color) -> String:
	var oro := MenuStyle.ORO.to_html(false)
	var tinta := colore.lightened(0.25).to_html(false)
	var t := ""
	t += "[font_size=30][b]%s[/b][/font_size]\n" % c.nome
	t += "[color=#%s][i]%s[/i][/color]\n\n" % [tinta, tr(c.epiteto)]
	t += "[i]«%s»[/i]\n\n" % tr(c.battuta)
	t += "%s\n\n" % tr(c.bio)
	if not _sbloccato(c):
		t += "[color=#b07a6a]🔒 %s[/color]\n\n" % tr("Locked. Win a tournament to draw a new champion.")
	elif c.corpo == "":
		t += "[color=#8a8070]%s[/color]\n\n" % tr("Still in the forge: the silhouette stands in until the champion is made.")
	t += "[color=#%s][b]%s[/b][/color]\n" % [oro, tr("House %s") % String(casa.get("name", c.casata))]
	t += "[color=#%s][i]%s[/i][/color]\n" % [tinta, tr(String(casa.get("motto", "")))]
	t += "[color=#8a8070]%s[/color]\n\n" % tr(c.territorio)
	t += "%s\n\n" % tr(c.bio_casata)
	t += "[color=#%s][b]%s[/b][/color]\n" % [oro, tr("The Seven Marks")]
	var marche : Dictionary = casa.get("marche", {})
	var parti : Array = []
	for k in MarcheStats.SIGLE.size():
		parti.append("%s %d" % [MarcheStats.SIGLE_MOSTRATE[k], int(marche.get(MarcheStats.SIGLE[k], 0))])
	t += "   ".join(parti) + "\n\n"
	t += "[color=#%s][b]%s[/b][/color]\n" % [oro, tr("Starting kit")]
	for k in c.kit:
		t += "· %s\n" % tr(k)
	t += "\n[color=#%s][b]%s[/b][/color]  %s\n\n" % [oro, tr("Affinity"), MenuStyle.nome_danno(c.affinita).capitalize()]
	t += "[color=#%s][b]%s[/b][/color]\n" % [oro, tr("House ability: %s") % tr(c.abilita_nome)]
	t += "%s" % tr(c.abilita_testo)
	return t


func _mostra_corpo(c : Resource, colore : Color) -> void:
	if _corpo != null:
		_perno.remove_child(_corpo)
		_corpo.queue_free()
		_corpo = null
	var percorso : String = c.corpo
	var sagoma := percorso == ""
	if sagoma:
		percorso = MANICHINI.get(c.genere, MANICHINI["male"])
	var ps : PackedScene = load(percorso) if ResourceLoader.exists(percorso) else null
	if ps == null:
		return
	_corpo = ps.instantiate()
	_perno.add_child(_corpo)
	_normalizza(_corpo)
	if sagoma:
		var mat := ShaderMaterial.new()
		mat.shader = SAGOMA
		mat.set_shader_parameter("colore", colore)
		for m in _corpo.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = mat
	elif not _posa():
		if c.idle != "":
			_idle(c.idle)


## Nel menu il campione sta in piedi, braccia lungo i fianchi: la clip POSA
## che monta_campione.py cuoce nel suo GLB (posa_menu). L'idle d'autore resta
## per chi non l'ha.
## Il riposo del GLB e' la guardia, piu' bassa: la misura per l'altezza si
## rifa' sulla testa, in posa.
func _posa() -> bool:
	var aps := _corpo.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty() or not (aps[0] as AnimationPlayer).has_animation(POSA_MENU):
		return false
	var ap := aps[0] as AnimationPlayer
	ap.get_animation(POSA_MENU).loop_mode = Animation.LOOP_LINEAR
	ap.play(POSA_MENU)
	ap.seek(0.0, true)
	var sk : Skeleton3D = _corpo.find_children("*", "Skeleton3D", true, false)[0]
	var testa := sk.find_bone("Head")
	if testa >= 0:
		var a_riposo := sk.get_bone_global_rest(testa).origin.y
		var in_posa := sk.get_bone_global_pose(testa).origin.y
		if a_riposo > 0.0 and in_posa > 0.0:
			_corpo.scale *= a_riposo / in_posa
			_corpo.position *= a_riposo / in_posa
	return true


## Il campione forgiato respira: la sua idle d'autore (CampioneResource.idle),
## per i corpi senza Posa e per guardare i pesi in movimento
## (anteprima_selezione.gd). Nel menu le armi non ci sono: di norma resta la
## Posa. Le tracce puntano a `%GeneralSkeleton:<osso>`, quindi lo scheletro del
## corpo prende quel nome unico.
func _idle(percorso : String) -> void:
	var trovati := _corpo.find_children("*", "Skeleton3D", true, false)
	var clip := CorpoCampione.idle_d_autore(percorso)
	if trovati.is_empty() or clip == null:
		return
	var sk := trovati[0] as Skeleton3D
	sk.name = "GeneralSkeleton"
	sk.unique_name_in_owner = true
	var ap := AnimationPlayer.new()
	ap.name = "IdlePreview"
	_corpo.add_child(ap)
	ap.root_node = ap.get_path_to(_corpo)
	var lib := AnimationLibrary.new()
	lib.add_animation("Idle", clip)
	ap.add_animation_library("", lib)
	ap.play("Idle")


## Porta il corpo ad ALTEZZA metri, coi piedi sulla pedana e centrato.
func _normalizza(n : Node3D) -> void:
	var box := AABB()
	var primo := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		box = b if primo else box.merge(b)
		primo = false
	if primo or box.size.y <= 0.0:
		return
	var s := ALTEZZA / box.size.y
	n.scale = Vector3.ONE * s
	n.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)


## ─── Input ───────────────────────────────────────────────────────────────────

func _su_input_anteprima(e : InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_trascina = e.pressed
	elif e is InputEventMouseMotion and _trascina:
		_perno.rotation.y += (e as InputEventMouseMotion).relative.x * 0.01
	elif e is InputEventScreenDrag:
		_perno.rotation.y += (e as InputEventScreenDrag).relative.x * 0.01


func _process(delta : float) -> void:
	## La levetta destra (o i dorsali) girano il campione; senza input gira
	## piano da solo.
	var giro := Input.get_axis("cam_rotate_left", "cam_rotate_right") if InputMap.has_action("cam_rotate_left") else 0.0
	if absf(giro) > 0.1:
		_perno.rotation.y += giro * 2.2 * delta
	elif not _trascina:
		_perno.rotation.y += 0.25 * delta


func _unhandled_input(e : InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _conferma() -> void:
	var c : Resource = campioni[scelto]
	if not _sbloccato(c):
		return
	confirmed.emit(c.casata, c.genere)
