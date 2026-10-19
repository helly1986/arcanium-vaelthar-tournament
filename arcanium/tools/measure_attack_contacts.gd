extends Node
## ═══════════════════════════════════════════════════════════════════════════
## MISURATORE DEGLI ISTANTI DI CONTATTO
## ═══════════════════════════════════════════════════════════════════════════
##
## Legge le clip d'attacco VERE e ne ricava l'istante in cui l'arma (o il muso)
## colpisce, invece di lasciarlo stimare a mano. Il numero prodotto finisce in
## `AttackTiming` ed è ciò che il gioco usa per far arrivare il danno.
##
## Perché conta: in un soulslike il momento del danno DEVE coincidere con quello
## che si vede a schermo. Se non coincide, parata e schivata all'ultimo istante
## smettono di essere abilità e diventano indovinelli — il giocatore temporizza
## su ciò che vede, e se il danno arriva altrove impara che il gioco bara.
##
## ─── Metodo ─────────────────────────────────────────────────────────────────
## Si campiona la posa dello scheletro a 240 Hz e si segue l'osso che COLPISCE
## (la mano armata per gli umanoidi, la punta del muso per i quadrupedi).
##
## Il criterio NON è il semplice picco di velocità, perché non regge su entrambi
## i tipi di colpo: in un FENDENTE la lama spazza di lato e il contatto cade sul
## picco, ma in un MORSO o in un AFFONDO il colpo arriva a fine estensione, cioè
## DOPO il picco (nel morso del lupo la differenza è di un decimo abbondante,
## abbastanza da spostare la finestra di parata).
##
## Criterio unico che vale per tutti e due: si isolano le REGIONI in cui l'osso
## viaggia veloce (sopra una frazione del picco della clip — ogni regione è un
## colpo), e dentro ciascuna si prende l'istante di massimo AVANZAMENTO verso il
## bersaglio. Su un fendente è il momento in cui la lama attraversa l'asse
## frontale; su un affondo è la massima estensione. In entrambi i casi è
## l'istante in cui l'arma è più dentro al bersaglio.
##
## I primi istanti della clip sono ignorati: il salto dalla posa di riposo al
## primo fotogramma produce una velocità enorme che non è un colpo.
##
## ─── Uso ────────────────────────────────────────────────────────────────────
##   godot --headless --path . res://arcanium/tools/measure_attack_contacts.tscn
##
## Stampa la tabella e RISCRIVE `arcanium/resources/attack_timing.tres`.
## Da rilanciare ogni volta che si aggiunge o si ri-esporta una clip d'attacco.

const AttackTiming := preload("res://arcanium/resources/attack_timing.gd")
const TiroArco := preload("res://arcanium/tools/tiro_arco.gd")
const OUT_PATH := "res://arcanium/resources/attack_timing.tres"

## Un rig da misurare: dove stanno le clip e quale osso colpisce.
## `dir` = cartella di GLB solo-armatura, uno per clip (pack Nephilite).
## `glb` = un unico GLB che contiene tutte le clip (lupo).
## Per ogni clip si dichiara QUANTI impatti ha (`colpi`). Non è un dettaglio
## burocratico: è l'unico pezzo di informazione che la geometria non può darci.
## Il misuratore trova sempre qualche candidato in più — lo swing delle braccia
## nella clip di corsa, il riposizionamento della testa tra un morso e l'altro —
## e senza sapere quanti colpi cercare non può distinguerli da un colpo vero.
## Dichiarandolo, il tool tiene gli N impatti più forti e la scelta umana
## sopravvive a ogni rigenerazione (che è il punto: le clip si ri-esportano).
##
## `preferisci: "ultimo"` per le mosse in cui il colpo è l'ATTERRAGGIO (balzi):
## lì l'impatto più violento può essere lo stacco, non l'arrivo.
## `preferisci: "primi"` per le COMBO: i colpi sono i primi N archi in ordine
## di tempo, e il rientro finale dell'arma — che è veloce — non conta.
## `soglia`: frazione del picco sopra cui l'osso è "in colpo", al posto di
## FAST_RATIO, per le clip in cui un colpo pesante nasconde quelli leggeri.
## `fra: [da, a]` (secondi): si tengono solo gli archi che cadono li' dentro,
## per le clip in cui il colpo non e' ne' il piu' forte ne' il primo ne'
## l'ultimo.
## `arco: true`: e' un TIRO CON L'ARCO, e il "contatto" e' il rilascio della
## corda — che non e' un moto veloce di nessun osso. Si misura sulle DUE MANI
## (si uniscono sulla corda, si allontanano fino alla guancia, si richiudono
## quando la sinistra lascia): il criterio sta in `tiro_arco.gd`, lo stesso di
## `misura_arco.tscn`, che stampa anche l'incocco per la corda.
## `a_mano: [t, ...]` (secondi): contatti DICHIARATI, per le clip in cui
## l'istante non e' un moto veloce dell'osso (il rilascio morbido di un tiro
## caricato). Va motivato accanto, con il profilo letto e i fotogrammi visti:
## e' l'eccezione alla regola «misurato, non stimato», e resta scritta qui
## perche' una riesportazione la rimetta in discussione.
const RIGS := [
	{
		"nome": "Nephilite (umanoidi: Consumato, Senza Nome)",
		"dir": "res://assets/characters/enemies/anims/sword/",
		"prefisso": "sword/",
		"osso": "Prop_Attachment_R",
		"clip": {
			"sword_light_attack_01": {"colpi": 1},
			"sword_light_attack_02": {"colpi": 1},
			"sword_run_attack_01": {"colpi": 1},
			"sword_charged_attack_01": {"colpi": 1},
			"sword_charged_attack_02": {"colpi": 1},
			"sword_jump_attack_01": {"colpi": 1, "preferisci": "ultimo"},
			"sword_th_charged_attack_01": {"colpi": 1},
			# La combo dello spadone (autorata in Cascadeur, 2026-09-12): un
			# fendente orizzontale e poi un gran colpo dall'alto. DUE colpi, e
			# quindi due finestre: e' la clip per cui `windows` esiste.
			# Soglia 0,35: il fendente d'apertura sta al 39-45% del picco (il
			# gran colpo e' 9,6 m/s sulla punta), e il rialzarsi finale al 40-53%
			# e' un terzo arco che `primi` scarta.
			"sword_th_combo_01": {"colpi": 2, "preferisci": "primi", "soglia": 0.35},
			# Non colpiscono con la lama: il "contatto" è l'istante di RILASCIO
			# (il proiettile parte, l'onda esplode). La misura vale lo stesso,
			# perché il rilascio è proprio lo scatto delle braccia in avanti.
			"sword_cast_01": {"colpi": 1},
			"sword_burst_01": {"colpi": 1},
			# L'ARCO (autorate dall'utente in Cascadeur, 2026-09-13): l'arco sta
			# nella DESTRA, ferma; il "contatto" e' il RILASCIO della sinistra.
			# ⚠️ NON con la velocita' (2026-09-14): il picco della sinistra
			# (19,9 m/s a f21) e' lo STRAPPO della freccia dalla faretra, e il
			# misuratore dei fendenti dava 0,75 s — la freccia partiva con la
			# mano ancora nella faretra. Si misura sulle due mani: unite a
			# f35 (1,17 s), trazione fino a f55 (62,8 cm, 1,83 s), rilascio a
			# f56 = 1,86 s. Verificato sui fotogrammi: all'86% la mano e' alla
			# guancia, all'88% e' avanti.
			"sword_bow_shot_01": {"colpi": 1, "arco": true},
			# Il caricato NON si misura nemmeno cosi': la mano si stacca PIANO
			# dalla guancia da 2,6 s (le mani si richiudono di 15 cm fra 2,6 e
			# 3,04 s) e il criterio delle mani darebbe 2,65 s; ma le dita si
			# aprono a f92 = 3,07 s, letto sui fotogrammi (al 74% la mano e'
			# ancora vicina alla guancia, al 78% e' aperta e avanti). Il
			# rilascio resta dichiarato A MANO a 3,07; se la clip si riautora
			# (una tenuta ferma fino al rilascio lo renderebbe misurabile),
			# si rilancia misura_arco.tscn prima di fidarsi di questo numero.
			"sword_bow_shot_charged_01": {"colpi": 1, "a_mano": [3.07]},
		},
	},
	{
		"nome": "Lupo (quadrupedi: Branco Guasto)",
		"glb": "res://assets/characters/enemies/wolf_animated.glb",
		"prefisso": "",
		"osso": "headend",
		"clip": {
			"bite": {"colpi": 1},
			"bite_combo": {"colpi": 2},
			"leap": {"colpi": 1, "preferisci": "ultimo"},
		},
	},
]

## Campionamento: fitto abbastanza da non perdere il picco di uno swing veloce.
const SAMPLE_HZ := 240.0
## L'osso è "in colpo" sopra questa frazione del picco assoluto della clip:
## sotto ci sono carica, rinculo e riposizionamento. Soglia ALTA di proposito:
## serve a individuare QUANTI colpi ci sono e dove cadono, non quanto durano.
const FAST_RATIO := 0.50
## Soglia più bassa, usata solo per allargare la FINESTRA della hitbox attorno a
## un contatto già individuato. L'arma ferisce per tutto l'arco dello swing, non
## solo nell'istante più veloce: se la finestra si fermasse al picco, il colpo
## diventerebbe un evento puntiforme e passare di lato all'arma la
## attraverserebbe senza conseguenze.
const WINDOW_RATIO := 0.22
## Buchi più brevi di così dentro una regione veloce non la spezzano: è lo
## stesso colpo che rallenta un istante a metà arco.
const GAP_TOLERANCE := 0.05
## Una regione veloce più corta di così è rumore, non un colpo.
const MIN_REGION := 0.02
## Nessun attacco colpisce nel primo scampolo della PROPRIA clip: quello è il
## wind-up per definizione. Serve anche a buttare via il salto dalla posa di
## riposo al primo fotogramma, che produce una velocità enorme e finta.
const IGNORE_HEAD_FRAC := 0.15
const IGNORE_HEAD_MIN := 0.08


func _ready() -> void:
	var lib : Resource = AttackTiming.new()
	print("\n╔══════════════════════════════════════════════════════════════════════════╗")
	print("║  ISTANTI DI CONTATTO MISURATI DALLE CLIP                                 ║")
	print("╚══════════════════════════════════════════════════════════════════════════╝")
	for rig in RIGS:
		print("\n── %s ── osso: %s" % [rig["nome"], rig["osso"]])
		print("   %-30s %8s  %-16s %-14s %s" % [
			"clip", "durata", "contatti (s)", "finestra", "lama viva"])
		for clip in rig["clip"].keys():
			var res := _measure(rig, clip)
			if res.is_empty():
				print("   %-30s  NON MISURABILE" % clip)
				continue
			var key : String = str(rig["prefisso"]) + clip
			lib.set_clip(key, res["contatti"], res["finestra"], res["durata"], res["finestre"])
			var lista := ""
			for t in res["contatti"]:
				lista += "%.2f " % t
			var fin : Vector2 = res["finestra"]
			print("   %-30s %7.2fs  %-16s %.2f-%.2f      %.0f%% della clip" % [
				clip, res["durata"], lista, fin.x, fin.y,
				100.0 * (fin.y - fin.x) / maxf(res["durata"], 0.01)])
			if (res["finestre"] as Array).size() > 1:
				var per_colpo := ""
				for w in res["finestre"]:
					per_colpo += "%.2f-%.2f  " % [w.x, w.y]
				print("   %-30s          per colpo: %s" % ["", per_colpo])

	var err := ResourceSaver.save(lib, OUT_PATH)
	print("\n%s  →  %s\n" % ["SCRITTO" if err == OK else "ERRORE SCRITTURA", OUT_PATH])
	get_tree().quit()


func _measure(rig : Dictionary, clip : String) -> Dictionary:
	var path : String = str(rig["glb"]) if rig.has("glb") else str(rig["dir"]) + clip + ".glb"
	if not ResourceLoader.exists(path):
		return {}
	var inst : Node = (load(path) as PackedScene).instantiate()
	add_child(inst)
	var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk : Skeleton3D = inst.find_child("Skeleton3D", true, false)
	if ap == null or sk == null:
		inst.queue_free()
		return {}

	# In un GLB per-clip il nome interno è arbitrario: si prende l'unica clip.
	# In un GLB multi-clip si cerca per nome.
	var anim_name : String = clip
	if not ap.has_animation(anim_name):
		if ap.get_animation_list().is_empty():
			inst.queue_free()
			return {}
		anim_name = ap.get_animation_list()[0]
	var anim : Animation = ap.get_animation(anim_name)
	## L'osso da seguire e' del rig, salvo la clip che ne dichiara un altro
	## (l'arco: e' la mano che tira la corda a scattare, non quella armata).
	var bone := sk.find_bone(str(rig["clip"][clip].get("osso", rig["osso"])))
	if bone < 0:
		inst.queue_free()
		return {}

	# ─── campionamento: velocità e avanzamento dell'osso che colpisce ───────
	var opt : Dictionary = rig["clip"][clip]
	var step := 1.0 / SAMPLE_HZ
	var tempi : Array[float] = []
	var vel : Array[float] = []
	var avanti : Array[float] = []   # componente "verso il bersaglio" (+Z: la mesh guarda +Z)
	var mani : Array[float] = []     # distanza fra le due mani (solo `arco`)
	var mano_l := sk.find_bone("Prop_Attachment_L")
	var mano_r := sk.find_bone("Prop_Attachment_R")
	var testa : float = maxf(IGNORE_HEAD_MIN, anim.length * IGNORE_HEAD_FRAC)
	var prev := Vector3.ZERO
	var have_prev := false
	var t := 0.0
	while t <= anim.length:
		ap.play(anim_name)
		ap.seek(t, true)
		var p : Vector3 = sk.get_bone_global_pose(bone).origin
		if have_prev and t >= testa:
			tempi.append(t)
			vel.append(p.distance_to(prev) / step)
			avanti.append(p.z)
			if opt.has("arco") and mano_l >= 0 and mano_r >= 0:
				mani.append(sk.get_bone_global_pose(mano_l).origin.distance_to(
					sk.get_bone_global_pose(mano_r).origin))
		prev = p
		have_prev = true
		t += step
	inst.queue_free()
	if vel.is_empty():
		return {}

	var esito : Dictionary
	if opt.has("arco"):
		var tr := TiroArco.trazione(tempi, mani) if not mani.is_empty() else {"rilascio": -1}
		if int(tr["rilascio"]) < 0:
			print("   %-30s  ARCO: rilascio non trovato (le mani non si richiudono)" % clip)
			return {}
		var ril := snappedf(tempi[tr["rilascio"]], 0.01)
		esito = {"contatti": PackedFloat32Array([ril]), "finestra": Vector2(ril - 0.05, ril + 0.05),
			"finestre": [Vector2(ril - 0.05, ril + 0.05)] as Array[Vector2]}
		print("   %-30s  ARCO: rilascio dalle mani (tiro_arco.gd)" % clip)
	elif opt.has("a_mano"):
		var dichiarati := PackedFloat32Array()
		var finestre : Array[Vector2] = []
		for t_ in opt["a_mano"]:
			dichiarati.append(float(t_))
			finestre.append(Vector2(float(t_) - 0.05, float(t_) + 0.05))
		esito = {"contatti": dichiarati, "finestra": Vector2(dichiarati[0] - 0.05, dichiarati[-1] + 0.05), "finestre": finestre}
		print("   %-30s  contatti A MANO (vedi la nota nella tabella)" % clip)
	else:
		esito = _contacts(tempi, vel, avanti, opt)
	esito["durata"] = anim.length
	esito["picco"] = _max(vel)
	return esito


## Un candidato per REGIONE veloce, all'istante di massimo avanzamento dentro
## quella regione (vedi la nota sul metodo in testa al file); poi si tengono i
## `colpi` candidati più forti, rimessi in ordine di tempo.
##
## Restituisce anche la FINESTRA: l'intervallo in cui l'arma sta davvero
## spazzando (dall'inizio della prima regione tenuta alla fine dell'ultima).
## Serve alle hitbox fisiche: una lama deve essere viva mentre COLPISCE, non per
## tre quarti dell'animazione — se resta accesa durante il wind-up ti ferisce
## mentre alza la spada, e nessuna schivata a tempo può funzionare.
func _contacts(tempi : Array[float], vel : Array[float], avanti : Array[float],
		opt : Dictionary) -> Dictionary:
	## `soglia` per clip: una combo con un FINALE pesante schiaccia il colpo
	## d'apertura sotto il 50% del picco (la combo dello spadone: fendente al
	## 45%, gran colpo dall'alto al 100%). Si dichiara accanto ai colpi, e si
	## sceglie GUARDANDO il profilo (arcanium/tools/profilo_clip.tscn), non a
	## occhio.
	var soglia := _max(vel) * float(opt.get("soglia", FAST_RATIO))
	var cand : Array = []   # [{t, forza, da, a}]
	var i := 0
	while i < vel.size():
		if vel[i] < soglia:
			i += 1
			continue
		# estende la regione finché resta veloce, tollerando buchi brevi
		var start := i
		var last_fast := i
		var j := i
		while j < vel.size() and tempi[j] - tempi[last_fast] <= GAP_TOLERANCE:
			if vel[j] >= soglia:
				last_fast = j
			j += 1
		if tempi[last_fast] - tempi[start] >= MIN_REGION:
			var best_t : float = tempi[start]
			var best_z := -1e9
			var forza := 0.0
			for k in range(start, last_fast + 1):
				forza = maxf(forza, vel[k])
				if avanti[k] > best_z:
					best_z = avanti[k]
					best_t = tempi[k]
			cand.append({"t": best_t, "forza": forza, "da": tempi[start], "a": tempi[last_fast]})
		i = last_fast + 1

	if opt.has("fra"):
		var fra : Array = opt["fra"]
		cand = cand.filter(func(c): return c["t"] >= float(fra[0]) and c["t"] <= float(fra[1]))
	var quanti : int = int(opt.get("colpi", cand.size()))
	if cand.size() > quanti:
		var pref := str(opt.get("preferisci", ""))
		if pref == "ultimo":
			cand = cand.slice(cand.size() - quanti)
		elif pref == "primi":
			## Una COMBO: i colpi sono i primi N archi in ordine di tempo, e
			## l'ultimo arco e' il rientro dell'arma — veloce quanto un colpo,
			## ma non lo e'. Coi "piu' forti" la combo dello spadone dava per
			## secondo contatto il rientro (2,75 s) e perdeva il fendente
			## d'apertura (1,15 s), che e' piu' lento del gran colpo finale.
			cand.sort_custom(func(a, b): return a["t"] < b["t"])
			cand = cand.slice(0, quanti)
		else:
			cand.sort_custom(func(a, b): return a["forza"] > b["forza"])
			cand = cand.slice(0, quanti)
	cand.sort_custom(func(a, b): return a["t"] < b["t"])

	var out := PackedFloat32Array()
	for c in cand:
		out.append(snappedf(c["t"], 0.01))
	return {"contatti": out, "finestra": _window(tempi, vel, cand),
		"finestre": _finestre(tempi, vel, cand)}


## Una finestra PER COLPO: ogni colpo allargato ai bordi del suo arco, come in
## `_window`, ma senza farne l'unione. Due colpi i cui archi si toccano si
## fondono in una finestra sola — a quel punto sono un colpo solo.
func _finestre(tempi : Array[float], vel : Array[float], cand : Array) -> Array[Vector2]:
	var out : Array[Vector2] = []
	if cand.is_empty():
		return out
	var soglia := _max(vel) * WINDOW_RATIO
	for c in cand:
		var i := tempi.find(c["da"])
		var j := tempi.find(c["a"])
		if i < 0 or j < 0:
			continue
		while i > 0 and vel[i - 1] >= soglia:
			i -= 1
		while j < vel.size() - 1 and vel[j + 1] >= soglia:
			j += 1
		var w := Vector2(snappedf(tempi[i], 0.01), snappedf(tempi[j], 0.01))
		if not out.is_empty() and w.x <= out[-1].y:
			out[-1].y = maxf(out[-1].y, w.y)
		else:
			out.append(w)
	return out


## Allarga i colpi tenuti fino ai bordi dell'ARCO (soglia bassa) e ne fa
## l'unione: è l'intervallo in cui l'arma è in movimento offensivo.
func _window(tempi : Array[float], vel : Array[float], cand : Array) -> Vector2:
	if cand.is_empty():
		return Vector2(-1.0, -1.0)
	var soglia := _max(vel) * WINDOW_RATIO
	var da := INF
	var a := -INF
	for c in cand:
		var i := tempi.find(c["da"])
		var j := tempi.find(c["a"])
		if i < 0 or j < 0:
			continue
		while i > 0 and vel[i - 1] >= soglia:
			i -= 1
		while j < vel.size() - 1 and vel[j + 1] >= soglia:
			j += 1
		da = minf(da, tempi[i])
		a = maxf(a, tempi[j])
	if da == INF:
		return Vector2(-1.0, -1.0)
	return Vector2(snappedf(da, 0.01), snappedf(a, 0.01))


func _max(a : Array[float]) -> float:
	var m := -1.0
	for v in a:
		m = maxf(m, v)
	return m
