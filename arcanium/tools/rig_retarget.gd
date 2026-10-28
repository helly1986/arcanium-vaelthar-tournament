@tool
extends RefCounted
class_name RigRetarget

## ═══════════════════════════════════════════════════════════════════════════
## RETARGET DI POSA — porta una clip da uno scheletro a un altro
## ═══════════════════════════════════════════════════════════════════════════
##
## Serve allo SCHELETRO UNICO. La bone map `nephilite_humanoid.tres` ha già
## unificato i NOMI delle ossa: una clip Nephilite e lo scheletro del player si
## riferiscono agli stessi `LeftUpperArm`, `Hips`, `Chest`. Restano diverse le
## POSE DI RIPOSO — bracci a un'angolazione diversa, ossa di lunghezza diversa,
## roll diverso — e finché non si compensa quella, una clip trasferita esce
## storta anche se ogni traccia risolve.
##
## Questo è il pezzo che la bone map non può fare: `retarget/rest_fixer` di Godot
## lavora solo all'IMPORT di un GLB, e MeleeLib.res è una libreria già cotta, di
## cui non esistono più i sorgenti. L'unico modo di portarla sul rig nuovo è
## trasformarla da dentro Godot — ed è esattamente ciò che fa questo file.
##
## ─── Il conto ───────────────────────────────────────────────────────────────
## Il modo SBAGLIATO e tentante è tenere la rotazione locale così com'è: funziona
## solo se le due ossa hanno gli stessi assi locali, e due rig di provenienza
## diversa non li hanno mai. Il modo giusto passa per lo spazio del modello.
##
## Per ogni osso, a ogni istante:
##
##   1. FK sul rig SORGENTE            → G_s(b,t)   orientamento nel modello
##   2. scarto rispetto al SUO riposo  → D = G_s(b,t) · GRs(b)⁻¹
##   3. lo stesso scarto sul riposo del DESTINATARIO → G_d(b,t) = D · GRd(b)
##   4. rientro in locale               → L_d(b) = G_d(parent)⁻¹ · G_d(b)
##
## D è una rotazione espressa in spazio-modello, quindi si moltiplica A SINISTRA:
## "ruota l'arto di tanto rispetto a come sta a riposo" è un'affermazione sul
## mondo, non sull'osso. È la differenza fra un fendente che spazza orizzontale
## su entrambi i rig e uno che spazza dove capita.
##
## ─── Cosa NON viene ruotato ─────────────────────────────────────────────────
## Le POSIZIONI restano quelle di riposo del destinatario: le ossa hanno
## lunghezze diverse e copiare le traslazioni disarticolerebbe lo scheletro.
## L'eccezione è l'`Hips`, che è l'unico osso la cui traslazione è movimento
## vero (accosciarsi, saltare): il suo scarto viene portato in spazio-modello,
## scalato per il rapporto d'altezza dei due bacini, e rimesso in locale.
##
## ─── `Root` è uno pseudo-osso ───────────────────────────────────────────────
## Il player NON ha un osso `Root` (il suo scheletro parte da `Hips`), eppure il
## suo AnimationTree ha `root_motion_track = %GeneralSkeleton:Root` e le clip
## `root-` di MeleeLib portano una traccia `Root` con dentro lo spostamento. È la
## convenzione che regge la locomozione del gioco — `set_root_move()` prende la
## velocità SOLO da lì. Quindi la traccia `Root` non si retargetta: si copia
## tal quale, scalata come l'Hips. Trattarla come un osso vero significherebbe
## perderla, e con lei il root motion della mossa.
##
## ─── Ricampionamento ────────────────────────────────────────────────────────
## Il conto ha bisogno della catena FK completa a ogni istante, quindi le chiavi
## non si possono trasformare una per una: la clip viene ricampionata a passo
## fisso. Le sorgenti sono GLB a 30 fps, quindi campionare a 30 non perde nulla;
## il default è 60 per stare larghi sugli archi veloci.

## Un osso del destinatario che non esiste nella sorgente resta a riposo, senza
## traccia. Un osso della sorgente che non esiste nel destinatario viene
## ignorato. Nessuno dei due casi è un errore: i due rig non hanno lo stesso
## numero di ossa ed è proprio il motivo per cui questo strumento esiste.


## Posa di riposo GLOBALE (spazio-scheletro) di ogni osso, per nome.
static func _global_rests(sk : Skeleton3D) -> Dictionary:
	var out : Dictionary = {}
	for i in range(sk.get_bone_count()):
		var t : Transform3D = sk.get_bone_rest(i)
		var p : int = sk.get_bone_parent(i)
		while p >= 0:
			t = sk.get_bone_rest(p) * t
			p = sk.get_bone_parent(p)
		out[sk.get_bone_name(i)] = t
	return out


## Indice delle tracce dell'animazione per nome-osso:
##   { "LeftHand": { "pos": idx, "rot": idx, "scl": idx } }
static func _track_index(anim : Animation) -> Dictionary:
	var out : Dictionary = {}
	for t in range(anim.get_track_count()):
		var path : String = str(anim.track_get_path(t))
		if not path.contains(":"):
			continue
		var bone : String = path.get_slice(":", 1)
		if not out.has(bone):
			out[bone] = {}
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D: out[bone]["pos"] = t
			Animation.TYPE_ROTATION_3D: out[bone]["rot"] = t
			Animation.TYPE_SCALE_3D:    out[bone]["scl"] = t
	return out


## Posa LOCALE dell'osso `bone` all'istante `time`: SOLO rotazione e posizione.
##
## La scala non entra nella catena degli orientamenti, e non è un dettaglio: le
## clip di MeleeLib animano la scala su 17 ossa (colonna, braccia, mani — squash
## authorato). Propagandola nella FK, ogni figlio eredita una base non ortogonale
## e l'orientamento che se ne estrae non è più la rotazione che si voleva.
##
## ⚠️ E soprattutto NON basta "ricostruire con la scala e poi ortonormalizzare".
## Gram-Schmidt su `Basis(rot).scaled(s)` con `s` NON UNIFORME non restituisce
## `rot`: lo ruota. Con `(1.03, 0.94, 1.03)` sul braccio l'errore era 9° sul
## braccio stesso e 17° sul dito in fondo alla catena — contro lo 0.04° di rumore
## atteso. La rotazione si PRENDE dalla sua traccia, non si deduce da una base
## sporca.
##
## La scala non viene persa: viaggia sulle proprie tracce, copiata tale e quale
## (vedi `retarget`). È l'unica delle tre componenti che attraversa un retarget
## senza doversi trasformare, perché è locale all'osso.
static func _sample_local(anim : Animation, idx : Dictionary, bone : String,
		time : float, rest : Transform3D) -> Transform3D:
	var pos : Vector3 = rest.origin
	var rot : Quaternion = rest.basis.get_rotation_quaternion()
	if idx.has(bone):
		var e : Dictionary = idx[bone]
		if e.has("pos"): pos = anim.position_track_interpolate(e["pos"], time)
		if e.has("rot"): rot = anim.rotation_track_interpolate(e["rot"], time)
	return Transform3D(Basis(rot), pos)


## Converte `anim` dal rig `src` al rig `dst`.
##
## `root_bone` è lo pseudo-osso del root motion (vedi sopra): la sua traccia
## viene copiata invece che retargettata. Passare "" per disattivare.
static func retarget(anim : Animation, src : Skeleton3D, dst : Skeleton3D,
		fps : float = 60.0, root_bone : String = "Root") -> Animation:

	var src_g : Dictionary = _global_rests(src)
	var dst_g : Dictionary = _global_rests(dst)
	var idx : Dictionary = _track_index(anim)

	# Ossa del destinatario che esistono anche nella sorgente, in ordine di
	# gerarchia: il conto in locale ha bisogno del genitore già calcolato.
	var comuni : Array[String] = []
	for i in range(dst.get_bone_count()):
		var n : String = dst.get_bone_name(i)
		if src.find_bone(n) >= 0:
			comuni.append(n)

	# Rapporto di taglia fra i due rig, misurato sull'altezza del bacino a
	# riposo: è il fattore che impedisce a un salto authorato su un corpo alto
	# di diventare un balzo assurdo su uno basso.
	var k : float = 1.0
	if src_g.has("Hips") and dst_g.has("Hips"):
		var hs : float = src_g["Hips"].origin.y
		if absf(hs) > 0.0001:
			k = dst_g["Hips"].origin.y / hs

	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	out.step = 1.0 / fps

	# Una traccia di rotazione per ogni osso comune; posizione solo per l'Hips.
	var rot_tr : Dictionary = {}
	for n in comuni:
		var t : int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%GeneralSkeleton:" + n))
		out.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		rot_tr[n] = t
	var hips_tr : int = -1
	if comuni.has("Hips"):
		hips_tr = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_tr, NodePath("%GeneralSkeleton:Hips"))

	# Le tracce di SCALA si copiano tali e quali, solo per le ossa che la
	# sorgente scala davvero. La scala di un osso è locale e non dipende
	# dall'orientamento del rig, quindi è l'unica delle tre componenti che
	# attraversa un retarget senza doversi trasformare.
	var scl_tr : Dictionary = {}
	for n in comuni:
		if idx.has(n) and (idx[n] as Dictionary).has("scl"):
			var ts : int = out.add_track(Animation.TYPE_SCALE_3D)
			out.track_set_path(ts, NodePath("%GeneralSkeleton:" + n))
			scl_tr[n] = ts

	var n_frames : int = int(ceil(anim.length * fps)) + 1
	for f in range(n_frames):
		var time : float = minf(float(f) / fps, anim.length)

		# 1) FK sul rig sorgente: orientamento di ogni osso nello spazio modello.
		var g_src : Dictionary = {}
		for i in range(src.get_bone_count()):
			var bn : String = src.get_bone_name(i)
			var loc : Transform3D = _sample_local(anim, idx, bn, time, src.get_bone_rest(i))
			var p : int = src.get_bone_parent(i)
			if p < 0:
				g_src[bn] = loc
			else:
				g_src[bn] = (g_src[src.get_bone_name(p)] as Transform3D) * loc

		# 2-3) scarto in spazio-modello, riapplicato sul riposo del destinatario.
		var g_dst : Dictionary = {}
		for n in comuni:
			var d : Basis = (g_src[n] as Transform3D).basis * (src_g[n] as Transform3D).basis.inverse()
			g_dst[n] = d.orthonormalized() * (dst_g[n] as Transform3D).basis.orthonormalized()

		# 4) rientro in locale e scrittura delle chiavi.
		for n in comuni:
			var bi : int = dst.find_bone(n)
			var p : int = dst.get_bone_parent(bi)
			var parent_basis : Basis = Basis()
			if p >= 0:
				var pn : String = dst.get_bone_name(p)
				# Se il genitore non è comune resta a riposo: usare il suo riposo
				# globale tiene la catena coerente invece di appoggiarsi a un
				# orientamento che nessuno ha calcolato.
				parent_basis = g_dst[pn] if g_dst.has(pn) else (dst_g[pn] as Transform3D).basis.orthonormalized()
			var local : Basis = parent_basis.inverse() * (g_dst[n] as Basis)
			out.rotation_track_insert_key(rot_tr[n], time, local.get_rotation_quaternion())

		for n in scl_tr.keys():
			var e : Dictionary = idx[n]
			out.scale_track_insert_key(scl_tr[n], time, anim.scale_track_interpolate(e["scl"], time))

		# Hips: la traslazione è movimento vero, va portata attraverso.
		if hips_tr >= 0:
			var rest_s : Transform3D = src.get_bone_rest(src.find_bone("Hips"))
			var rest_d : Transform3D = dst.get_bone_rest(dst.find_bone("Hips"))
			var cur : Transform3D = _sample_local(anim, idx, "Hips", time, rest_s)
			out.position_track_insert_key(hips_tr, time, rest_d.origin + (cur.origin - rest_s.origin) * k)

	# Lo pseudo-osso del root motion: copiato, non retargettato.
	if root_bone != "" and idx.has(root_bone):
		var e : Dictionary = idx[root_bone]
		if e.has("pos"):
			var t : int = out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(t, NodePath("%GeneralSkeleton:" + root_bone))
			for f in range(n_frames):
				var time : float = minf(float(f) / fps, anim.length)
				out.position_track_insert_key(t, time, anim.position_track_interpolate(e["pos"], time) * k)
		if e.has("rot"):
			var t2 : int = out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t2, NodePath("%GeneralSkeleton:" + root_bone))
			for f in range(n_frames):
				var time : float = minf(float(f) / fps, anim.length)
				out.rotation_track_insert_key(t2, time, anim.rotation_track_interpolate(e["rot"], time))

	return out


## Mette su `sk` la posa di `anim` all'istante `t`: rotazioni e posizioni delle
## ossa che trova per nome, tranne `salta` (il Root porta la root motion). Per
## i banchi delle impugnature e per le basi di Cascadeur nella guardia pesante.
static func applica_istante(anim : Animation, sk : Skeleton3D, t : float = 0.0,
		salta : PackedStringArray = ["Root"]) -> void:
	for k in anim.get_track_count():
		var nome := String(anim.track_get_path(k).get_concatenated_subnames())
		var osso := sk.find_bone(nome)
		if osso < 0 or nome in salta:
			continue
		match anim.track_get_type(k):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(osso, anim.rotation_track_interpolate(k, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(osso, anim.position_track_interpolate(k, t))
