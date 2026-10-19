extends Node3D
class_name SchiantoATerra

## SCHIANTO A TERRA — zolle, polvere e chiazza all'impatto di un colpo pesante.
##
## È SOLO SPETTACOLO: il Terrain3D sotto non viene toccato in nessun modo. Non
## c'è deformazione, non c'è scrittura sull'heightmap, non c'è niente da
## ripristinare. Quello che si vede volare è materia finta che nasce sopra un
## terreno intatto — esattamente come in Elden Ring, dove il suolo non ha mai un
## buco dopo un martello.
##
## ⚠️ E NON è fisica. Ogni zolla percorre un ARCO BALISTICO calcolato a mano
## (posizione, velocità, gravità), con un rimbalzo smorzato e poi il riposo.
## Sono ~20 corpi per schianto: metterli nel motore fisico costerebbe altrettanti
## RigidBody3D, altrettante collisioni contro il terreno e un risultato che NON
## si controlla (una zolla che rotola per dieci metri o si incastra in un prop
## rovina la lettura). Qui invece la traiettoria è nostra: la si tara e resta
## tarata. La fisica vera vive nell'ALTRO sistema, quello degli oggetti
## distruttibili, dove serve davvero.
##
## ─── COME SI CHIAMA ──────────────────────────────────────────────────────────
##   SchiantoATerra.sotto(nodo, 1.2)                  # trova il suolo da solo
##   SchiantoATerra.al_punto(mondo, punto, normale)   # punto già noto
##
## ─── PERCHÉ È FATTO COSÌ (vincoli del progetto) ──────────────────────────────
## • Camera ISOMETRICA a ~20 m: si legge la SILHOUETTE e la DIMENSIONE, non il
##   dettaglio. Da qui le due scelte che contano di più:
##     – le zolle sono grosse (0.18–0.45 m). Sotto i ~15 cm a quella distanza
##       una zolla è meno di un pixel e mezzo: sparisce, e con lei i soldi spesi
##       a lanciarla;
##     – sono POCHE e ANGOLOSE, non tante e tonde. Venti sassi spigolosi si
##       leggono; cento ciottoli lisci diventano una nuvola grigia.
## • Renderer FORWARD MOBILE col GLOW DI SCENA SPENTO: niente si illumina da
##   solo. Le zolle sono materia OPACA e ILLUMINATA dalla scena — che è anche
##   giusto, sono terra. Contro un suolo che per direzione artistica è il piano
##   più chiaro dell'inquadratura, staccano da sole come sagome scure.
## • La polvere è in blend MIX, mai additiva: additiva vorrebbe dire polvere che
##   BRILLA, e l'unico effetto sarebbe schiarire una macchia informe.
##
## ─── I TRE STRATI, in ordine di quanto lavorano ──────────────────────────────
##   ① ZOLLE   — MultiMesh, arco balistico, rimbalzo, riposo, sprofondamento.
##               È lo strato che racconta l'impatto. Se ne resta uno, è questo.
##   ② POLVERE — GPUParticles3D one-shot: un fungo basso che si allarga.
##               Dà il VOLUME che le zolle da sole non hanno.
##   ③ CHIAZZA — un Decal di terra smossa che resta qualche secondo.
##               È l'unica cosa che dice «qui è successo», dopo.

# ---------------------------------------------------------------------------
# PALETTE
# ---------------------------------------------------------------------------

## ⚠️ LA TINTA CHE SI PASSA È QUELLA DEL SUOLO, NON QUELLA DELLE ZOLLE.
## Le zolle vengono scurite da sole (vedi `SCURIMENTO`), così il contratto per
## chi chiama è quello ovvio — «di che colore è la terra qui» — e non «di che
## colore vuoi i detriti», che nessuno sa rispondere.
##
## Il primo giro l'ho sbagliato proprio qui: tinta fissa scura (0.34, 0.31,
## 0.26) sopra l'ocra chiarissimo della Traccia Perduta. Da camera isometrica le
## zolle uscivano NERE — non scure: nere, buchi nel terreno. La direzione
## artistica dice che il suolo è il piano più chiaro dell'inquadratura, quindi
## qualunque tinta fissa presa da un altro livello sbaglia sempre di parecchio.

## Traccia Perduta: conca aperta, terra secca e chiara (l'ocra del suo builder).
const TERRA_TRACCIA := Color(0.72, 0.52, 0.34)
## Kalvorn: sottobosco umido, più verde e più scuro.
const TERRA_KALVORN := Color(0.32, 0.34, 0.24)
## Lastricato del Crocevia: pietra chiara — schegge, non zolle.
const PIETRA := Color(0.55, 0.52, 0.47)
## Pavimento dell'Arena Senza Fuoco. Preso dal suo builder (`arena_builder.gd`,
## `mat.albedo_color`): è una pietra chiara e FREDDA, virata al blu-notte come
## tutta l'arena. Copiare qui il numero invece di inventarne uno "grigio" è la
## differenza fra detriti che appartengono a quel pavimento e detriti che
## sembrano venire da un altro livello.
const PIETRA_ARENA := Color(0.82, 0.85, 0.9)
## Default prudente: una terra media. Chi costruisce un livello dovrebbe passare
## la SUA, non affidarsi a questa.
const TERRA := Color(0.55, 0.45, 0.34)

## Quanto le zolle sono più scure del suolo da cui vengono.
##
## ⚠️ Serve MOLTO più di quanto sembri ragionevole, e l'ho tarato due volte al
## contrario. A un quarto le zolle sono terra credibile — e quando ricadono si
## confondono col terreno e spariscono, perché hanno la sua stessa luminanza.
## Metà è il punto in cui esistono ancora come materia (non sono nere) ma
## staccano come SAGOMA sia in volo sia da ferme. È esattamente la regola ⑤a
## della direzione artistica: il suolo è il piano chiaro, ciò che ci sta sopra è
## scuro, ed è quel contrasto — non il dettaglio — a rendere leggibile la scena.
const SCURIMENTO := 0.5

# ---------------------------------------------------------------------------
# TARATURA
# ---------------------------------------------------------------------------

## Gravità delle zolle. Più alta di 9.8 — un arco a gravità reale, visto
## dall'alto, si legge fiacco e galleggiante — ma NON quanto avevo messo la
## prima volta (24): lì il volo intero durava 0.6 s, cioè meno di quanto serva
## all'occhio per accorgersi che è successo qualcosa. A 16 le zolle stanno in
## aria poco più di un secondo, che è il tempo di una mossa pesante: si vede la
## salita, si vede l'apice, si vede la ricaduta.
const GRAVITA := 16.0

## Quanto si perde a ogni rimbalzo. Un solo rimbalzo visibile, poi ferme: due o
## tre le farebbero sembrare palline di gomma.
const RIMBALZO_Y := 0.26
const RIMBALZO_XZ := 0.42

## Ciclo di vita di una zolla dopo che si è fermata: sta ferma `RIPOSO` secondi,
## poi sprofonda e si rimpicciolisce in `SPARIZIONE`.
##
## ⚠️ Sono corti apposta. Detriti che restano a terra a lungo, in un gioco dove
## si combatte per minuti nello stesso punto, si accumulano in un tappeto — e il
## tappeto racconta il contrario dell'impatto singolo che vogliamo vendere.
const RIPOSO := 1.1
const SPARIZIONE := 0.7

## La CHIAZZA sopravvive alle zolle: è la traccia, e una traccia che se ne va
## insieme a ciò che l'ha lasciata non è una traccia. Resta piena per
## `CHIAZZA_PIENA` e poi svanisce in `CHIAZZA_FADE`.
const CHIAZZA_PIENA := 3.0
const CHIAZZA_FADE := 1.6

## Sotto questa altezza sul suolo una zolla è considerata "arrivata".
const TOLLERANZA_SUOLO := 0.02

## Layer su cui cercare il suolo: "World" (Terrain3D ci sta sopra col suo
## collision_layer di default, vedi il .tscn dei livelli — collision_mode = 3,
## cioè Full/Game, quindi la collisione c'è davvero ed è già lì).
const MASCHERA_SUOLO := 1

# ---------------------------------------------------------------------------
# STATO
# ---------------------------------------------------------------------------

var _tinta := TERRA
var _forza := 1.0
var _raggio := 1.0            ## raggio nominale dello schianto, in metri

## Una riga per zolla. PackedArray e non un Array di oggetti: sono ~20 elementi
## letti e riscritti ogni frame, e qui la località di memoria è gratis.
var _pos : PackedVector3Array = PackedVector3Array()
var _vel : PackedVector3Array = PackedVector3Array()
var _asse : PackedVector3Array = PackedVector3Array()   ## asse di rotolamento
var _giro : PackedFloat32Array = PackedFloat32Array()   ## rad/s attorno a _asse
var _ang : PackedFloat32Array = PackedFloat32Array()    ## angolo corrente
var _scala : PackedFloat32Array = PackedFloat32Array()
var _scala0 : PackedFloat32Array = PackedFloat32Array() ## scala di partenza, per la sparizione
var _suolo : PackedFloat32Array = PackedFloat32Array()  ## quota del suolo sotto la zolla
var _sondato : PackedByteArray = PackedByteArray()      ## il raggio verso il basso è già stato tirato?
var _rimbalzi : PackedByteArray = PackedByteArray()
var _ferma_da : PackedFloat32Array = PackedFloat32Array()
var _variante : PackedByteArray = PackedByteArray()     ## quale MultiMesh la disegna

var _mm : Array[MultiMesh] = []
var _chiazza : Decal = null
var _vive := 0
var _eta := 0.0
var _durata_massima := 4.0

# ---------------------------------------------------------------------------
# API PUBBLICA
# ---------------------------------------------------------------------------

## Schianto SOTTO un nodo: tira un raggio verso il basso e usa quel punto e
## quella normale. È la chiamata normale — chi picchia per terra sa dove sta,
## non sa a che quota sia il terreno (su Terrain3D non è mai y=0).
##
## Ritorna null se sotto al nodo non c'è suolo entro 6 m (in aria, o sopra un
## burrone): meglio niente che uno schianto a mezz'aria.
static func sotto(nodo : Node3D, forza : float = 1.0, tinta : Color = TERRA,
		scossa : bool = true) -> SchiantoATerra:
	if nodo == null or not nodo.is_inside_tree():
		return null
	var mondo := nodo.get_world_3d()
	if mondo == null:
		return null
	var da : Vector3 = nodo.global_position + Vector3.UP * 1.5
	var a : Vector3 = da + Vector3.DOWN * 7.5
	var q := PhysicsRayQueryParameters3D.create(da, a, MASCHERA_SUOLO)
	if nodo is CollisionObject3D:
		q.exclude = [(nodo as CollisionObject3D).get_rid()]
	var colpo := mondo.direct_space_state.intersect_ray(q)
	if colpo.is_empty():
		return null
	return al_punto(nodo, colpo["position"], colpo["normal"], forza, tinta, scossa)


## Schianto in un punto GLOBALE già noto. `nel_mondo` serve solo a trovare
## l'albero di scena: l'effetto si appende alla radice della scena corrente, non
## a chi lo ha chiesto.
##
## ⚠️ Appenderlo all'attaccante sarebbe il difetto classico: le zolle sono in
## coordinate di MONDO e devono restare dove sono cadute — se il nemico si
## sposta o muore, l'effetto non deve seguirlo né sparire con lui.
## `scossa`: se true (default) lo schianto fa anche tremare la camera, con
## un'intensità ricavata dalla forza. È acceso di default perché il caso in cui
## il terreno si spacca e la camera resta immobile non esiste — e perché così le
## cose future che useranno questo effetto (meteore, crolli) sono a posto senza
## che nessuno debba ricordarsi di aggiungere una riga.
static func al_punto(nel_mondo : Node, punto : Vector3, normale : Vector3 = Vector3.UP,
		forza : float = 1.0, tinta : Color = TERRA, scossa : bool = true) -> SchiantoATerra:
	if nel_mondo == null or not nel_mondo.is_inside_tree():
		return null
	var radice := nel_mondo.get_tree().current_scene
	if radice == null:
		radice = nel_mondo.get_tree().root
	var fx := SchiantoATerra.new()
	fx.name = "SchiantoATerra"
	fx._forza = clampf(forza, 0.3, 2.5)
	fx._tinta = tinta
	radice.add_child(fx)
	fx.global_position = punto
	fx._monta(normale.normalized() if normale.length_squared() > 0.001 else Vector3.UP)
	if scossa:
		Scossa.nel_mondo(punto, _trauma_per(fx._forza))
	## Il boato. Sta QUI, accanto alla scossa, perche' schianto/scossa/suono sono
	## la stessa cosa vista in tre modi: separarli vorrebbe dire poterne
	## dimenticare uno, e uno schianto muto e' esattamente cio' che si nota.
	Suoni.nel_mondo(fx, Suoni.SCHIANTO_MASSO, linear_to_db(clampf(fx._forza * 0.75, 0.3, 1.0)))
	return fx


## Da forza dello schianto a trauma di camera.
##
## La scala parte da MEDIO e non da zero: se il terreno si è aperto abbastanza
## da buttare fuori delle zolle, il minimo sindacale è che si senta.
##
## Dove cadono i casi veri, coi numeri di oggi:
##   • Respinta dell'Eco (forza ~1.07) → ~0.63, cioè PESANTE;
##   • balzo del Lupo Alpha (forza 1.2) → ~0.72;
##   • blast di fase 2 (forza ~1.29)   → ~0.79.
##
## ⚠️ Il blast di fase 2 NON arriva a DEVASTANTE da qui, ed è voluto: quella è
## una scossa che si merita di essere chiesta a mano, perché è il momento più
## grosso dello scontro e non deve dipendere da quanto è largo il suo raggio.
## Vedi `_phase2_blast` in arcanium_boss.gd.
static func _trauma_per(forza : float) -> float:
	return clampf(remap(forza, 0.7, 1.6, Scossa.MEDIO, Scossa.DEVASTANTE),
			Scossa.LEGGERO, Scossa.DEVASTANTE)


# ---------------------------------------------------------------------------
# COSTRUZIONE
# ---------------------------------------------------------------------------

func _monta(normale : Vector3) -> void:
	_raggio = 1.1 * _forza
	_lancia_zolle()
	_monta_polvere()
	_monta_chiazza(normale)
	## Il nodo vive finché non è finito l'ULTIMO dei suoi strati — che è la
	## chiazza, non le zolle. Liberarlo sul tempo delle zolle farebbe sparire la
	## chiazza di scatto a metà dissolvenza.
	_durata_massima = CHIAZZA_PIENA + CHIAZZA_FADE + 0.1


## ─── ① ZOLLE ────────────────────────────────────────────────────────────────
##
## Le zolle partono da un ANELLO attorno al punto d'impatto, non dal centro:
## uno schianto scava e butta fuori, non sputa in su. Partendo dal centro
## verrebbe un getto, che è il gesto di un geyser, non di un martello.
func _lancia_zolle() -> void:
	var quante := int(round(18.0 * _forza))
	var mesh := _mesh_zolle(_tinta)
	var per_variante := int(ceil(float(quante) / float(mesh.size())))

	for v in mesh.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Zolle%d" % v
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh[v]
		mm.instance_count = per_variante
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		## ⚠️ Le zolle si muovono ma l'AABB del MultiMesh viene calcolato UNA
		## volta sui transform iniziali: senza questo box generoso, appena si
		## alzano escono dal volume e il motore le culla via — spariscono tutte
		## insieme a metà volo, e sembra un difetto di caricamento.
		var r := _raggio * 6.0
		mmi.custom_aabb = AABB(Vector3(-r, -1.0, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
		## ⚠️ LE OMBRE SERVONO, ed è il contrario di quello che avevo scritto qui
		## al primo giro ("chi vuoi che le veda, sono venti disegni in più").
		## Misurato: a effetto finito le 25 zolle erano tutte vive, tutte sopra il
		## suolo e tutte INVISIBILI — una zolla scura, ferma, appoggiata su terra
		## scura, vista da 20 m, non ha silhouette contro niente. L'ombra di
		## contatto è ciò che la stacca dal terreno, e costa UN disegno in più in
		## shadow map per tutte quante, perché è un MultiMesh solo.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mm.append(mm)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var conta := PackedInt32Array()
	conta.resize(mesh.size())

	for i in quante:
		## Direzione d'uscita: sparpagliata sul cerchio ma non uniforme — un po'
		## di grumo si legge come "il colpo ha aperto una crepa", l'uniforme
		## come "è esploso un petardo".
		var ang := rng.randf_range(0.0, TAU)
		var fuori := Vector3(cos(ang), 0.0, sin(ang))
		var r0 : float = _raggio * rng.randf_range(0.15, 0.55)

		## Il rapporto verticale/orizzontale è ciò che decide se lo schianto si
		## legge come uno SCHIACCIAMENTO (roba che schizza di lato, basso e
		## largo) o come un'esplosione (tutto in su). Serve il primo: il colpo
		## viene dall'alto, l'energia va a finire nel piano.
		var su : float = rng.randf_range(3.6, 6.4) * _forza
		## ⚠️ La spinta ORIZZONTALE è molto più bassa della verticale, ed è la
		## taratura che ho sbagliato per prima. A 2.8-6.0 m/s, con un secondo di
		## volo, le zolle atterravano a 5-8 metri dal punto d'impatto: sparse su
		## mezza radura, senza più alcun rapporto visivo col colpo che le aveva
		## alzate. Uno schianto deve restare LEGGIBILE COME UN PUNTO — i detriti
		## incorniciano l'impatto, non lo diluiscono.
		var via : float = rng.randf_range(1.2, 3.0) * _forza

		## ⚠️ La variante si assegna A GIRO, non a caso. Ogni MultiMesh ha
		## `per_variante` slot allocati: tirando a caso, una variante può
		## pescarne di più e sfonda il suo array (`instance_count`), che è
		## esattamente il difetto che ha fatto sparire le zolle alla prima prova.
		## La varietà non ci perde niente — tutto il resto della zolla (misura,
		## rotazione, spinta) è già casuale, quindi l'occhio non vede un ciclo.
		var v : int = i % mesh.size()
		_variante.append(v)
		conta[v] += 1

		_pos.append(Vector3(fuori.x * r0, 0.06, fuori.z * r0))
		_vel.append(Vector3(fuori.x * via, su, fuori.z * via))
		_asse.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized())
		_giro.append(rng.randf_range(-9.0, 9.0))
		_ang.append(rng.randf_range(0.0, TAU))
		var s : float = rng.randf_range(0.75, 1.35)
		_scala.append(s)
		_scala0.append(s)
		_suolo.append(0.0)
		_sondato.append(0)
		_rimbalzi.append(0)
		_ferma_da.append(-1.0)

	for v in _mm.size():
		_mm[v].visible_instance_count = conta[v]
	_vive = quante
	_scrivi_transform()


## ─── ② POLVERE ──────────────────────────────────────────────────────────────
##
## Un fungo BASSO e LARGO, non una colonna. Da camera isometrica una colonna di
## polvere copre il personaggio e non si vede nemmeno bene; un anello che si
## allarga a terra resta sotto la linea dello sguardo e allarga l'impatto.
func _monta_polvere() -> void:
	var p := GPUParticles3D.new()
	p.name = "Polvere"
	p.local_coords = false        ## la polvere resta dove è nata anche se il nodo si muove
	p.one_shot = true
	p.explosiveness = 0.92        ## tutta insieme: è un impatto, non un fumaiolo
	## ⚠️ TANTE e piccole, non poche e grandi. `smoke_wisp.png` è un FILAMENTO
	## (nasce per l'aura del boss), non un batuffolo: preso singolo e grande, su
	## un terreno screziato come questo, non si vede proprio — ci ho perso due
	## giri prima di guardare la texture invece che i numeri. Un fungo di
	## polvere si costruisce sovrapponendo molti filamenti semitrasparenti, che
	## in blend MIX si sommano fino a coprire.
	p.amount = int(round(70.0 * _forza))
	p.lifetime = 1.35
	p.randomness = 0.5
	p.emitting = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = _raggio * 0.6
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.15
	pm.direction = Vector3(0, 0.35, 0)
	pm.spread = 78.0
	pm.initial_velocity_min = 1.4 * _forza
	pm.initial_velocity_max = 3.4 * _forza
	## Gravità quasi nulla e attrito radiale: la polvere si allarga e SI FERMA,
	## invece di ricadere. È così che si comporta davvero, ed è anche l'unico
	## modo di tenerla bassa senza schiacciarla a terra.
	pm.gravity = Vector3(0, -0.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.8 * _forza
	pm.scale_max = 1.9 * _forza
	var cur := Curve.new()
	cur.add_point(Vector2(0.0, 0.25))
	cur.add_point(Vector2(0.35, 1.0))
	cur.add_point(Vector2(1.0, 0.9))
	var curt := CurveTexture.new()
	curt.curve = cur
	pm.scale_curve = curt
	## L'alpha scende su tutta la vita: senza, la polvere non svanisce, SCOMPARE.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.10, Color(1, 1, 1, 0.95))
	ramp.add_point(0.55, Color(1, 1, 1, 0.62))
	var rampt := GradientTexture1D.new()
	rampt.gradient = ramp
	pm.color_ramp = rampt
	## ⚠️ MOLTO più chiara del suolo, non "un filo". Al primo giro l'avevo messa
	## a metà strada fra la terra e un grigio chiaro: il risultato aveva la
	## stessa LUMINANZA del terreno sotto, e una macchia che ha la luminanza del
	## fondo non esiste — a schermo non si vedeva niente, pur essendoci.
	## Fisicamente è anche giusto: la polvere in sospensione è illuminata da ogni
	## direzione e non ha ombre proprie, quindi è sempre più chiara del suolo da
	## cui è stata alzata. Resta un'idea della tinta della terra, non di più.
	## ⚠️ Metà e metà, non un bianco appena sporcato. La polvere di UN terreno
	## deve avere il colore di QUEL terreno: neutra su un livello caldo come la
	## Traccia esce grigio-azzurrina, e una nuvola fredda su terra ocra si legge
	## come fumo — cioè come un'altra cosa.
	pm.color = Color(1.0, 0.97, 0.92).lerp(_tinta, 0.5)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	## ⚠️ MIX, non additivo. `dark_particle_material` ha un nome che inganna: non
	## fa "particelle scure", fa particelle NON ADDITIVE — ed è esattamente ciò
	## che serve alla polvere. Additiva schiarirebbe e basta, dando una macchia
	## lattiginosa invece di un velo che copre.
	quad.material = BossVFX.dark_particle_material(BossVFX.TEX_SMOKE, Color.WHITE)
	p.draw_pass_1 = quad
	add_child(p)


## ─── ③ CHIAZZA ──────────────────────────────────────────────────────────────
##
## Un Decal, non un quad appoggiato: su Terrain3D il suolo è quasi mai piano e
## un quad a +2 cm o compenetra la salita o galleggia sulla discesa. Il Decal si
## proietta e segue la forma, che è il suo unico mestiere.
##
## ⚠️ I Decal ci sono su Forward+ e su Mobile (non su Compatibility): questo
## progetto gira su mobile, quindi stiamo dentro. Se un giorno si passasse a
## Compatibility, questo è il pezzo da sostituire.
func _monta_chiazza(normale : Vector3) -> void:
	var d := Decal.new()
	d.name = "Chiazza"
	d.texture_albedo = _texture_chiazza()
	var lato := _raggio * 2.6
	## L'altezza del box è la PROFONDITÀ di proiezione: generosa, o su un pendio
	## la chiazza si taglia a metà.
	d.size = Vector3(lato, 4.0, lato)
	## Terra rivoltata: stessa logica delle zolle (più scura del suolo asciutto),
	## ma con la mano LEGGERA — è un alone, non una bruciatura. `albedo_mix` sotto
	## 1 lascia trasparire la texture del terreno sotto, così la chiazza legge
	## come terra smossa e non come un adesivo appiccicato sopra.
	d.modulate = _tinta.darkened(SCURIMENTO * 1.4)
	d.albedo_mix = 0.65
	d.upper_fade = 2.0
	d.lower_fade = 2.0
	## Allineata alla normale del terreno e girata a caso: tre schianti vicini
	## con la stessa chiazza si notano subito come "la stessa decalcomania".
	add_child(d)
	if normale.dot(Vector3.UP) < 0.999:
		var avanti := Vector3.FORWARD - normale * Vector3.FORWARD.dot(normale)
		if avanti.length_squared() > 0.001:
			d.look_at_from_position(d.global_position, d.global_position + avanti.normalized(), normale)
	d.rotate_object_local(Vector3.UP, randf_range(0.0, TAU))
	_chiazza = d


# ---------------------------------------------------------------------------
# INTEGRAZIONE
# ---------------------------------------------------------------------------

func _process(delta : float) -> void:
	_eta += delta
	if _vive > 0:
		_avanza_zolle(delta)
		_scrivi_transform()
	if _chiazza != null and _eta > CHIAZZA_PIENA:
		_chiazza.modulate.a = maxf(0.0, 1.0 - (_eta - CHIAZZA_PIENA) / CHIAZZA_FADE)
	if _eta >= _durata_massima:
		queue_free()


func _avanza_zolle(delta : float) -> void:
	var spazio := get_world_3d().direct_space_state
	for i in _pos.size():
		if _ferma_da[i] >= 0.0:
			_avanza_riposo(i, delta)
			continue

		_vel[i] = _vel[i] + Vector3.DOWN * GRAVITA * delta
		_pos[i] = _pos[i] + _vel[i] * delta
		_ang[i] = _ang[i] + _giro[i] * delta

		## Il raggio verso il basso si tira UNA VOLTA per zolla, e solo quando
		## sta scendendo: tirarlo ogni frame per ogni zolla sarebbe ~20 query di
		## fisica al frame per un effetto decorativo. Così sono ~20 in tutto.
		if _sondato[i] == 0 and _vel[i].y < 0.0:
			_sondato[i] = 1
			var g := global_position
			var da := Vector3(g.x + _pos[i].x, g.y + _pos[i].y + 2.0, g.z + _pos[i].z)
			var a := da + Vector3.DOWN * 12.0
			var colpo := spazio.intersect_ray(
					PhysicsRayQueryParameters3D.create(da, a, MASCHERA_SUOLO))
			## Nessun suolo sotto (burrone, bordo del terreno): si tiene la quota
			## dell'impatto, così la zolla non cade all'infinito.
			_suolo[i] = (colpo["position"].y - g.y) if not colpo.is_empty() else 0.0

		if _pos[i].y <= _suolo[i] + TOLLERANZA_SUOLO and _vel[i].y < 0.0:
			_tocca_terra(i)


func _tocca_terra(i : int) -> void:
	var p := _pos[i]
	p.y = _suolo[i]
	_pos[i] = p
	if _rimbalzi[i] == 0 and absf(_vel[i].y) > 1.2:
		_rimbalzi[i] = 1
		_vel[i] = Vector3(_vel[i].x * RIMBALZO_XZ, -_vel[i].y * RIMBALZO_Y, _vel[i].z * RIMBALZO_XZ)
		_giro[i] = _giro[i] * 0.45
		return
	## Ferma, e appena INFILATA nel terreno — non mezza sepolta.
	##
	## Il compromesso è fra due difetti veri. Appoggiata esatta sul piano di
	## contatto sembra un modello posato (il giunto netto che la direzione
	## artistica chiama per nome); sepolta a metà sparisce, che è ciò che ho
	## misurato al primo giro. Un dito dentro le lascia quasi tutto il volume
	## fuori — e insieme all'ombra di contatto è quella che la fa leggere come
	## materia caduta lì.
	p.y = _suolo[i] + 0.10 * _scala[i]
	_pos[i] = p
	_vel[i] = Vector3.ZERO
	_giro[i] = 0.0
	_ferma_da[i] = 0.0


func _avanza_riposo(i : int, delta : float) -> void:
	_ferma_da[i] += delta
	if _ferma_da[i] < RIPOSO:
		return
	var t : float = (_ferma_da[i] - RIPOSO) / SPARIZIONE
	if t >= 1.0:
		if _scala[i] > 0.0:
			_scala[i] = 0.0
			_vive -= 1
		return
	## Sprofonda MENTRE si rimpicciolisce. Il solo rimpicciolire legge come
	## "l'oggetto si dissolve"; sprofondare insieme legge come "la terra se la
	## riprende", che è la storia giusta e costa uguale.
	##
	## La scala si ricalcola dalla scala INIZIALE, non si decrementa: decrementare
	## una scala già decrementata è la strada per una curva che dipende dal
	## framerate (e che, sotto carico, lascia zolle grosse a mezz'aria).
	_scala[i] = _scala0[i] * (1.0 - t)
	var p := _pos[i]
	p.y -= delta * 0.35 * _scala0[i]
	_pos[i] = p


## Riversa lo stato nei MultiMesh. Un solo passaggio, e le zolle di ogni
## variante si scrivono in ordine: l'indice dentro il MultiMesh non è l'indice
## globale della zolla, quindi si tiene un contatore per variante.
func _scrivi_transform() -> void:
	var cursore := PackedInt32Array()
	cursore.resize(_mm.size())
	for i in _pos.size():
		var v : int = _variante[i]
		var k : int = cursore[v]
		cursore[v] = k + 1
		var s : float = _scala[i]
		if s <= 0.0:
			## Scala zero = triangoli degeneri, non disegna nulla. Costa meno che
			## ricompattare gli array a ogni zolla che muore.
			_mm[v].set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), _pos[i]))
			continue
		var b := Basis(_asse[i], _ang[i]).scaled(Vector3(s, s, s))
		_mm[v].set_instance_transform(k, Transform3D(b, _pos[i]))


# ---------------------------------------------------------------------------
# MESH E TEXTURE PROCEDURALI
# ---------------------------------------------------------------------------
#
# ⚠️ Le zolle NON sono asset. Sono tre cubi con gli angoli spostati a caso, con
# normali piatte, otto vertici e dodici triangoli l'uno.
#
# È una scelta, non una scorciatoia in attesa di modelli veri: la direzione
# artistica dice che a questa distanza conta la SAGOMA e non la superficie, e la
# sagoma di una zolla è un sasso storto. Un modello Meshy da 2000 triangoli
# darebbe la stessa silhouette a venti volte il costo, più una texture da
# importare, comprimere e tenere sotto il cap. Se un giorno servissero zolle
# riconoscibili (erba sopra, radici sotto), il punto in cui sostituirle è
# questo solo metodo.

static var _mesh_cache : Dictionary = {}

## Tre varianti: una compatta, una piatta (zolla di cotico erboso), una lunga
## (scheggia). Tre bastano — a venti pezzi che ruotano nessuno le riconosce.
static func _mesh_zolle(tinta : Color) -> Array[Mesh]:
	var chiave := tinta.to_html(false)
	if _mesh_cache.has(chiave):
		var gia : Array[Mesh] = _mesh_cache[chiave]
		return gia
	var mat := StandardMaterial3D.new()
	## ILLUMINATA, non unshaded: è terra, e deve prendere la luce del livello.
	## Una zolla unshaded avrebbe lo stesso colore all'alba e a mezzanotte, e da
	## camera isometrica si noterebbe subito che "galleggia" fuori dalla scena.
	mat.albedo_color = tinta.darkened(SCURIMENTO)
	mat.roughness = 0.95
	mat.metallic = 0.0
	## ⚠️ CULLING NORMALE, mai CULL_DISABLED. Ci sono cascato al primo giro
	## ragionando "così si vedono da tutti i lati mentre ruotano": ma le zolle
	## sono solidi CHIUSI, quindi il retro non si deve vedere per definizione —
	## e con cull_disabled il motore disegna anche le facce di dietro, la cui
	## normale punta lontano dal sole. Risultato: metà zolla nera, e da 20 m
	## venti zolle mezze nere si leggono come venti buchi.
	## (È la stessa trappola già annotata per gli shader del progetto.)
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	var fatte : Array[Mesh] = []
	fatte.append(_zolla(1, Vector3(0.30, 0.26, 0.30), 0.30, mat))
	fatte.append(_zolla(2, Vector3(0.42, 0.13, 0.38), 0.34, mat))
	fatte.append(_zolla(3, Vector3(0.20, 0.18, 0.46), 0.26, mat))
	_mesh_cache[chiave] = fatte
	return fatte


## Un cubo di dimensione `mis` con gli otto angoli spostati a caso di `caos`
## (frazione del lato), triangolato a facce piatte.
static func _zolla(seme : int, mis : Vector3, caos : float, mat : Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seme * 7919
	var ang : Array[Vector3] = []
	for i in 8:
		var s := Vector3(
			-0.5 if (i & 1) == 0 else 0.5,
			-0.5 if (i & 2) == 0 else 0.5,
			-0.5 if (i & 4) == 0 else 0.5)
		ang.append(Vector3(
			s.x * mis.x * rng.randf_range(1.0 - caos, 1.0 + caos),
			s.y * mis.y * rng.randf_range(1.0 - caos, 1.0 + caos),
			s.z * mis.z * rng.randf_range(1.0 - caos, 1.0 + caos)))

	## Le sei facce del cubo, ognuna coi suoi quattro angoli in ordine antiorario
	## visti da fuori.
	const FACCE := [
		[0, 2, 3, 1],   # -Z … indici sui bit: 1=+x, 2=+y, 4=+z
		[4, 5, 7, 6],   # +Z
		[0, 1, 5, 4],   # -Y
		[2, 6, 7, 3],   # +Y
		[0, 4, 6, 2],   # -X
		[1, 3, 7, 5],   # +X
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in FACCE:
		var a : Vector3 = ang[f[0]]
		var b : Vector3 = ang[f[1]]
		var c : Vector3 = ang[f[2]]
		var d : Vector3 = ang[f[3]]
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	var m : ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


static func _tri(st : SurfaceTool, a : Vector3, b : Vector3, c : Vector3) -> void:
	## Normale calcolata per FACCIA e non interpolata: è quello che dà lo
	## spigolo netto, cioè l'unica cosa che si legge da 20 m.
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


## Chiazza di terra smossa: rumore moltiplicato per una caduta radiale, cotta
## una volta in una Image e riusata da tutti gli schianti (è modulata dal Decal,
## quindi una texture sola serve per qualunque tinta di terreno).
static var _tex_chiazza : ImageTexture = null

static func _texture_chiazza() -> ImageTexture:
	if _tex_chiazza != null:
		return _tex_chiazza
	const LATO := 128
	var rumore := FastNoiseLite.new()
	rumore.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rumore.frequency = 0.045
	rumore.fractal_octaves = 3
	var img := Image.create(LATO, LATO, false, Image.FORMAT_RGBA8)
	var centro := (LATO - 1) * 0.5
	for y in LATO:
		for x in LATO:
			var d : float = Vector2(x - centro, y - centro).length() / centro
			## Bordo IRREGOLARE: la caduta radiale viene spostata dal rumore, o
			## la chiazza è un cerchio perfetto e si legge come un adesivo.
			var n : float = rumore.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var mask : float = clampf(1.0 - d * (0.75 + n * 0.55), 0.0, 1.0)
			mask = pow(mask, 1.4)
			## Il colore porta le venature (più scure al centro dello schianto),
			## l'alpha porta la forma.
			var v : float = 0.55 + n * 0.45
			img.set_pixel(x, y, Color(v, v, v, mask))
	_tex_chiazza = ImageTexture.create_from_image(img)
	return _tex_chiazza
