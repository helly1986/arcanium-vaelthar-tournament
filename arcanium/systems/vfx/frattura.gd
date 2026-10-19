extends RefCounted
class_name Frattura

## FRATTURA PROCEDURALE — spezza una mesh in N frammenti chiusi, tagliandola
## con dei PIANI.
##
## Serve a `OggettoDistruttibile`: quando una colonna si rompe, i pezzi che
## volano devono essere PEZZI DI QUELLA COLONNA — con le sue scanalature, la sua
## texture, il suo colore — non sassi generici presi da un'altra parte.
##
## ─── PERCHÉ NON IL CELL FRACTURE DI BLENDER ──────────────────────────────────
## Quella resta la strada giusta per un pezzo CURATO A MANO, e il componente
## accetta frammenti pre-fratturati esattamente come questi. Ma come strada
## UNICA aveva due difetti seri:
##   • ogni oggetto distruttibile nuovo costa un giro Blender → export → import
##     → .import → collisioni. Vuol dire che ne esisteranno tre, non trenta;
##   • i frammenti pre-generati vanno in git, e il peso degli asset su questo
##     progetto è già stato un problema una volta.
## Qui invece si prende un prop qualunque fra quelli che ci sono già e diventa
## distruttibile senza produrre un solo file nuovo.
##
## ─── PERCHÉ SI TAGLIA, invece di smistare i triangoli ────────────────────────
## ⚠️ Il primo tentativo NON tagliava niente: smistava ogni triangolo al più
## vicino di N semi (una Voronoi fatta sui triangoli) e chiudeva il buco rimasto
## con un ventaglio dal bordo al suo centro. È più semplice, non tocca la
## geometria e conserva le UV originali — e a schermo era inguardabile.
##
## Il motivo, che vale la pena ricordare: **il bordo di una cella di Voronoi
## segue gli spigoli dei triangoli, quindi è frastagliato e NON PIANO.** Un
## ventaglio da un bordo così verso il suo centro produce triangoli che escono
## dal volume del pezzo — a schermo, grandi schegge a raggiera che sparano fuori
## dai rocchi. Non era un difetto di taratura: era la forma stessa di quel tappo.
##
## Tagliando con un piano, invece, la faccia di rottura è PIANA per costruzione.
## Chiuderla è un ventaglio dentro al suo stesso piano, e una scheggia fuori dal
## pezzo non può nascere nemmeno volendo. Costa il codice di taglio del triangolo
## (poco, ed è tutto qui sotto) e in cambio non ha nessun caso brutto.
##
## ─── COME TAGLIA ─────────────────────────────────────────────────────────────
## In FETTE lungo l'asse più lungo dell'oggetto.
##
## ⚠️ Non è un ripiego rispetto a un Voronoi 3D: su una colonna è *migliore*. Le
## colonne di pietra vere sono costruite a rocchi sovrapposti e crollano così, a
## rocchi. Su una cassa dà delle assi, che è altrettanto giusto. Un tritume
## uniforme, che è ciò che darebbe un Voronoi, non somiglia a nessuna delle due.

## Faccia interna: pietra spaccata di fresco. Più CHIARA della superficie, non
## più scura — la crosta esposta alle intemperie è sempre la parte scura, e
## invertirlo è l'errore che fa sembrare i pezzi bruciati invece che rotti.
const SCHIARIMENTO_INTERNO := 0.22

## Con true stampa, per ogni fetta, quanti triangoli ha e quanti ne servono a
## chiudere le due facce di rottura.
static var diagnostica : bool = false


## Spezza `mesh` in `pezzi` fette lungo il suo asse più lungo.
##
## Ritorna un array di `{"mesh": ArrayMesh, "centro": Vector3}`, dove `centro` è
## dove stava il pezzo nella mesh originale (in coordinate della MESH) e la sua
## geometria è già ricentrata lì sopra.
##
## `base` porta i vertici nell'orientamento e nella SCALA del mondo, cotti dentro
## la mesh.
## ⚠️ Serve perché un RigidBody3D NON tiene la scala: il server di fisica gli
## riscrive il transform ogni frame e la azzera. Misurato su una colonna scalata
## ×12 dal builder: i frammenti uscivano da 28 cm — tutti presenti, tutti nel
## posto giusto, tutti invisibili perché grandi come una scatola di fiammiferi.
## Cotta nella geometria, il corpo resta a scala 1, che è l'unico stato che la
## fisica sa mantenere.
static func spezza(mesh : Mesh, pezzi : int = 8, seme : int = 0,
		base : Basis = Basis()) -> Array:
	var tri := _raccogli_triangoli(mesh)
	if tri.is_empty():
		return []

	var aabb := mesh.get_aabb()
	var asse := _asse_lungo(aabb)
	var tagli := _tagli(aabb, asse, maxi(pezzi, 2), seme)

	var mat_sorgente := _materiale_sorgente(mesh)
	var mat_interno := _materiale_interno(mesh)

	var out : Array = []
	for i in tagli.size() - 1:
		var lo : float = tagli[i]
		var hi : float = tagli[i + 1]
		var fetta := _fetta(tri, asse, lo, hi)
		if fetta.is_empty():
			continue
		var costruito := _costruisci(fetta, asse, lo, hi, base,
				mat_sorgente, mat_interno)
		if not costruito.is_empty():
			out.append(costruito)
	return out


static func _asse_lungo(aabb : AABB) -> int:
	var s := aabb.size
	if s.x >= s.y and s.x >= s.z:
		return 0
	if s.z >= s.y and s.z >= s.x:
		return 2
	return 1


## Le quote dei tagli, dal fondo alla cima dell'oggetto.
##
## ⚠️ IRREGOLARI. Fette tutte uguali si riconoscono subito come una divisione
## fatta a tavolino — l'occhio conta i pezzi identici. Un po' di sbilanciamento
## (±35%) e diventano rocchi rotti. Il seme è quello del prop, quindi la stessa
## colonna si rompe sempre allo stesso modo: stessa varietà del casuale puro, ma
## riproducibile quando c'è da capire un difetto.
static func _tagli(aabb : AABB, asse : int, quanti : int, seme : int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seme * 6151 + 17
	var a0 : float = aabb.position[asse]
	var lun : float = aabb.size[asse]

	var pesi : Array = []
	var somma := 0.0
	for _i in quanti:
		var w : float = rng.randf_range(0.65, 1.35)
		pesi.append(w)
		somma += w

	## ⚠️ Il primo e l'ultimo taglio stanno un filo FUORI dall'ingombro. Messi
	## esatti sul bordo, i triangoli del fondo e della cima cadono sul piano e la
	## classificazione ">= 0" li può perdere: si ritroverebbe una colonna senza
	## base e senza capitello, e il pezzo mancante è il primo che si nota.
	var out : Array = [a0 - lun * 0.01]
	var acc := 0.0
	for i in quanti - 1:
		acc += float(pesi[i]) / somma
		out.append(a0 + lun * acc)
	out.append(a0 + lun * 1.01)
	return out


## ─── Taglio di una fetta ────────────────────────────────────────────────────
##
## Ritaglia i triangoli alla fascia [lo, hi] lungo `asse`, e riporta anche i
## SEGMENTI di taglio: sono loro il contorno delle due facce di rottura.
static func _fetta(tri : Array, asse : int, lo : float, hi : float) -> Dictionary:
	## Prima si toglie tutto ciò che sta sotto `lo`, poi tutto ciò che sta sopra
	## `hi`: due passate dello stesso codice, col piano girato.
	var passo1 := _taglia(tri, asse, lo, true)
	var passo2 := _taglia(passo1["dentro"], asse, hi, false)
	if (passo2["dentro"] as Array).is_empty():
		return {}
	return {
		"tri": passo2["dentro"],
		"seg_lo": passo1["segmenti"],
		"seg_hi": passo2["segmenti"],
	}


## Taglia una lista di triangoli con un piano perpendicolare ad `asse`.
## `tieni_sopra` = si conserva la parte con coordinata >= `q`.
static func _taglia(tri : Array, asse : int, q : float, tieni_sopra : bool) -> Dictionary:
	var dentro : Array = []
	var segmenti : Array = []
	var verso : float = 1.0 if tieni_sopra else -1.0

	for t in tri:
		var p : Array = t["p"]
		var d : Array = []
		for k in 3:
			d.append(((p[k] as Vector3)[asse] - q) * verso)

		var quanti_dentro := 0
		for k in 3:
			if float(d[k]) >= 0.0:
				quanti_dentro += 1

		if quanti_dentro == 3:
			dentro.append(t)
			continue
		if quanti_dentro == 0:
			continue

		## Il triangolo attraversa il piano. Si ricostruisce la parte che resta,
		## camminando i tre lati in ordine: si tiene ogni vertice che sta dentro
		## e si aggiunge un vertice nuovo ogni volta che il lato cambia lato.
		## I punti nuovi stanno SUL piano, e il segmento che li unisce è un pezzo
		## del contorno della faccia di rottura.
		var tenuti : Array = []
		var nuovi : Array = []
		for k in 3:
			var k2 : int = (k + 1) % 3
			var dk : float = d[k]
			var dk2 : float = d[k2]
			if dk >= 0.0:
				tenuti.append(_vertice(t, k))
			if (dk >= 0.0) != (dk2 >= 0.0):
				var f : float = dk / (dk - dk2)
				var v := _interpola(t, k, k2, f)
				tenuti.append(v)
				nuovi.append(v)

		if nuovi.size() == 2:
			segmenti.append([nuovi[0]["p"], nuovi[1]["p"]])
		## Il poligono che resta ha 3 o 4 lati: si triangola a ventaglio.
		for i in range(1, tenuti.size() - 1):
			dentro.append(_triangolo(tenuti[0], tenuti[i], tenuti[i + 1]))

	return {"dentro": dentro, "segmenti": segmenti}


static func _vertice(t : Dictionary, k : int) -> Dictionary:
	return {"p": t["p"][k], "n": t["n"][k], "uv": t["uv"][k]}


static func _interpola(t : Dictionary, k : int, k2 : int, f : float) -> Dictionary:
	return {
		"p": (t["p"][k] as Vector3).lerp(t["p"][k2], f),
		"n": (t["n"][k] as Vector3).lerp(t["n"][k2], f).normalized(),
		"uv": (t["uv"][k] as Vector2).lerp(t["uv"][k2], f),
	}


static func _triangolo(a : Dictionary, b : Dictionary, c : Dictionary) -> Dictionary:
	return {
		"p": [a["p"], b["p"], c["p"]],
		"n": [a["n"], b["n"], c["n"]],
		"uv": [a["uv"], b["uv"], c["uv"]],
	}


## ─── Costruzione del frammento ──────────────────────────────────────────────
static func _costruisci(fetta : Dictionary, asse : int, lo : float, hi : float,
		base : Basis, mat_sorgente : Material,
		mat_interno : Material) -> Dictionary:
	var tri : Array = fetta["tri"]
	var centro := Vector3.ZERO
	var n := 0
	for t in tri:
		for k in 3:
			centro += t["p"][k]
			n += 1
	if n == 0:
		return {}
	centro /= float(n)

	## GUSCIO — la superficie originale ritagliata. Normali e UV arrivano
	## interpolate dal taglio, quindi la texture non salta sul bordo.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tri:
		for k in 3:
			st.set_normal((base * (t["n"][k] as Vector3)).normalized())
			st.set_uv(t["uv"][k])
			st.add_vertex(base * ((t["p"][k] as Vector3) - centro))
	st.index()
	var m : ArrayMesh = st.commit()
	if m == null or m.get_surface_count() == 0:
		return {}
	m.surface_set_material(0, mat_sorgente)

	## FACCE DI ROTTURA — una sotto e una sopra, ciascuna PIANA.
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var messi := 0
	messi += _chiudi(cap, fetta["seg_lo"], asse, lo, false, centro, base)
	messi += _chiudi(cap, fetta["seg_hi"], asse, hi, true, centro, base)
	if messi > 0:
		var mc : ArrayMesh = cap.commit()
		if mc != null and mc.get_surface_count() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mc.surface_get_arrays(0))
			m.surface_set_material(m.get_surface_count() - 1, mat_interno)

	if diagnostica:
		print("[frattura] fetta: %d tri guscio | rottura %d tri (%d+%d segmenti)"
				% [tri.size(), messi, (fetta["seg_lo"] as Array).size(),
				(fetta["seg_hi"] as Array).size()])

	return {"mesh": m, "centro": centro}


## Chiude UNA faccia di rottura: ventaglio dai segmenti di taglio al loro centro.
##
## ⚠️ Tutti i punti stanno sul piano del taglio, quindi il ventaglio è PIANO e
## non può produrre schegge fuori dal pezzo — che è esattamente ciò che rendeva
## inguardabile il metodo precedente. E il verso non va misurato: la normale è
## l'asse del taglio, e si sa da che parte guarda.
static func _chiudi(cap : SurfaceTool, segmenti : Array, asse : int, q : float,
		guarda_su : bool, centro : Vector3, base : Basis) -> int:
	if segmenti.size() < 3:
		## Meno di tre segmenti non e' un contorno: e' un tocco di striscio, e non
		## c'e' niente da chiudere.
		return 0

	## Assi del piano: le due coordinate diverse da quella tagliata.
	var u1 := (asse + 1) % 3
	var u2 := (asse + 2) % 3

	## ⚠️ LA FACCIA DI ROTTURA E' L'INVILUPPO CONVESSO DEI PUNTI DI TAGLIO.
	## Non il contorno percorso, non "il gruppo di segmenti piu' grande".
	##
	## Ci sono arrivato dopo due tentativi sbagliati, e vale la pena dire perche'
	## erano sbagliati, perche' sembravano tutti e due ragionevoli.
	##
	## 1) Ventaglio su TUTTI i segmenti. La colonna dell'arena e' modellata come
	##    un TUBO CAVO (lo si vede a occhio nei suoi prop `column_broken`), quindi
	##    la sezione tagliata non e' un disco ma una CORONA: due contorni
	##    concentrici. I triangoli del contorno interno finivano sopra quelli
	##    dell'esterno con verso opposto, e a schermo quella sovrapposizione
	##    leggeva come una macchia nera sulla faccia di rottura.
	##
	## 2) Raggruppare i segmenti in contorni e tenere il piu' esterno. Giusto in
	##    teoria, fragile in pratica: il raggruppamento univa gli estremi con un
	##    confronto a tolleranza, e due triangoli adiacenti producono lo STESSO
	##    punto di taglio con l'ultima cifra diversa (l'interpolazione corre
	##    lungo lo spigolo in versi opposti). Bastava un estremo non riconosciuto
	##    e il contorno si spezzava in archi: il ventaglio ne copriva uno solo e
	##    restava il buco — cioe' la chiazza scura residua, piu' piccola di prima
	##    e con la stessa identica causa.
	##
	## L'inviluppo convesso non ha nessuna tolleranza, nessun raggruppamento e
	## nessun ordinamento da indovinare: prende i punti come nuvola e restituisce
	## un poligono convesso ORDINATO. Sulla corona ignora da solo i punti interni
	## e da' il disco pieno — che e' anche la lettura giusta, perche' una colonna
	## spezzata deve mostrare pietra piena e non rivelare che era una scatola.
	##
	## ⚠️ Il prezzo: su una sezione CONCAVA (un prop a L) la faccia di rottura
	## esce un po' piu' piena della sagoma vera. E' un difetto che a 20 m su un
	## detrito non si vede, e comunque preferibile al suo opposto: un buco nella
	## faccia si legge come un errore anche da lontano, una faccia un filo troppo
	## piena no.
	var nuvola := PackedVector2Array()
	for sg in segmenti:
		nuvola.append(Vector2(sg[0][u1], sg[0][u2]))
		nuvola.append(Vector2(sg[1][u1], sg[1][u2]))
	var scafo := Geometry2D.convex_hull(nuvola)
	## `convex_hull` ripete il primo punto in fondo per chiudere il poligono: se
	## non lo si toglie si ottiene un triangolo degenere e una cucitura visibile.
	if scafo.size() > 1 and scafo[0].is_equal_approx(scafo[scafo.size() - 1]):
		scafo.remove_at(scafo.size() - 1)
	if scafo.size() < 3:
		return 0

	var perno2 := Vector2.ZERO
	for v in scafo:
		perno2 += v
	perno2 /= float(scafo.size())
	## Un poligono CONVESSO e' stellato rispetto al proprio baricentro, sempre:
	## e' la proprieta' che rende il ventaglio corretto per costruzione qui,
	## mentre su un contorno qualunque sarebbe stato solo probabile.
	var perno := _sul_piano(perno2, asse, q, u1, u2)

	var nor_locale := Vector3.ZERO
	nor_locale[asse] = 1.0 if guarda_su else -1.0
	var nor := (base * nor_locale).normalized()

	var messi := 0
	for i in scafo.size():
		var va : Vector2 = scafo[i]
		var vb : Vector2 = scafo[(i + 1) % scafo.size()]
		## Verso coerente. Si guarda il SEGNO DELL'AREA in 2D sul piano del
		## taglio, non un prodotto vettoriale in 3D: sul contorno di un taglio i
		## triangoli quasi degeneri ci sono sempre, e su quelli una normale
		## calcolata in 3D e' rumore, mentre il segno dell'area resta buono.
		var area : float = (va.x - perno2.x) * (vb.y - perno2.y) \
				- (vb.x - perno2.x) * (va.y - perno2.y)
		if absf(area) < 1e-12:
			continue
		var primo := va
		var secondo := vb
		if (area > 0.0) != guarda_su:
			primo = vb
			secondo = va
		for p in [perno, _sul_piano(primo, asse, q, u1, u2),
				_sul_piano(secondo, asse, q, u1, u2)]:
			cap.set_normal(nor)
			cap.set_uv(Vector2(p[u1], p[u2]))
			cap.add_vertex(base * (p - centro))
		messi += 1
	return messi


## Riporta un punto del piano di taglio nello spazio 3D del frammento. La
## coordinata tagliata vale ESATTAMENTE `q`: e' cio' che garantisce che la faccia
## di rottura sia perfettamente piana invece che quasi.
static func _sul_piano(v : Vector2, asse : int, q : float, u1 : int, u2 : int) -> Vector3:
	var p := Vector3.ZERO
	p[asse] = q
	p[u1] = v.x
	p[u2] = v.y
	return p


## ─── Lettura della mesh di partenza ─────────────────────────────────────────
static func _raccogli_triangoli(mesh : Mesh) -> Array:
	var out : Array = []
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var pos : PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if pos.is_empty():
			continue
		var nor : PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv : PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx : PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		## Una superficie può essere indicizzata o no: si normalizzano i due casi
		## a un'unica lista di indici, invece di duplicare il ciclo.
		if idx.is_empty():
			idx = PackedInt32Array()
			for i in pos.size():
				idx.append(i)
		var t := 0
		while t + 2 < idx.size():
			var p : Array = []
			var n : Array = []
			var u : Array = []
			for k in 3:
				var i : int = idx[t + k]
				p.append(pos[i])
				n.append(nor[i] if i < nor.size() else Vector3.UP)
				u.append(uv[i] if i < uv.size() else Vector2.ZERO)
			out.append({"p": p, "n": n, "uv": u})
			t += 3
	return out


static func _materiale_sorgente(mesh : Mesh) -> Material:
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null:
			return m
	return null


## Materiale della faccia spaccata. Derivato dall'albedo della superficie
## originale quando si riesce a leggerlo, così la pietra rotta appartiene ancora
## alla pietra da cui viene invece di essere un grigio qualunque.
static func _materiale_interno(mesh : Mesh) -> StandardMaterial3D:
	var base := Color(0.62, 0.62, 0.60)
	var src := _materiale_sorgente(mesh)
	if src is BaseMaterial3D:
		base = (src as BaseMaterial3D).albedo_color
		if base.get_luminance() < 0.05:
			## Molti materiali da glTF tengono l'albedo a bianco e mettono il
			## colore nella texture: un albedo quasi nero qui è quasi sempre un
			## materiale da leggere in altro modo, non una pietra nera.
			base = Color(0.62, 0.62, 0.60)
	var m := StandardMaterial3D.new()
	m.albedo_color = base.lightened(SCHIARIMENTO_INTERNO)
	m.roughness = 1.0
	m.metallic = 0.0
	return m
