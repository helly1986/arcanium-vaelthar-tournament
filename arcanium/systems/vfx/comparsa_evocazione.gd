extends Node

## ═══════════════════════════════════════════════════════════════════════════
## COMPARSA DELL'EVOCAZIONE — ciò che si evoca non appare, si MATERIALIZZA
## ═══════════════════════════════════════════════════════════════════════════
##
## Il problema: i lupi del richiamo e la Scintilla comparivano di colpo, interi,
## dal nulla. Un'evocazione che appare istantanea non si legge come magia — si
## legge come un difetto, e toglie al giocatore il mezzo secondo che gli serve
## per capire che sta arrivando qualcosa.
##
## Qui la creatura affiora: parte invisibile e diventa opaca, mentre sopra di lei
## resta acceso un vortice che si spegne solo quando è finita di comparire. Il
## vortice non è decorazione: è il segnale che l'evocazione è ANCORA in corso,
## e sparisce esattamente quando la creatura diventa reale.
##
## ─── Perché `transparency` e non un materiale ───────────────────────────────
## `GeometryInstance3D.transparency` sbiadisce QUALUNQUE mesh senza toccarne il
## materiale. Un dissolve su shader avrebbe richiesto un materiale dedicato per
## ogni creatura — lupo, Scintilla, e chiunque venga dopo — e sarebbe entrato in
## conflitto con quelli che già esistono (il pelo guasto dell'Alpha su tutti).
##
## ⚠️ `transparency > 0` manda la mesh nella coda dei trasparenti: niente ombre
## proprie e ordinamento per profondità approssimato. Dura il tempo della
## comparsa, poi si torna a 0.0 ESATTO — non 0.001 — così la creatura rientra
## nella coda opaca e riprende le ombre.
##
## Uso:
##   const Comparsa := preload("res://arcanium/systems/vfx/comparsa_evocazione.gd")
##   Comparsa.avvia(istanza)
## (per path, non per class_name: vedi la convenzione del progetto)

## Quanto dura la materializzazione. Sotto il mezzo secondo non si legge, sopra
## il secondo e mezzo il giocatore ha già iniziato a ignorarla.
const DURATA := 1.1
## Il viola dell'Arcanium, lo stesso degli occhi dell'Alpha e del pelo guasto:
## un'evocazione parla la lingua di chi la evoca.
const VIOLA := Color(0.65, 0.18, 1.0)


## Fa materializzare `bersaglio`. Sicura da chiamare su qualunque Node3D: se non
## ha mesh, non fa nulla di male — mette solo il vortice.
static func avvia(bersaglio : Node3D, durata : float = DURATA) -> void:
	if bersaglio == null or not is_instance_valid(bersaglio):
		return
	var mesh : Array = bersaglio.find_children("*", "GeometryInstance3D", true, false)
	for m in mesh:
		(m as GeometryInstance3D).transparency = 1.0

	var vortice := _crea_vortice(bersaglio)

	## Il tween vive sul BERSAGLIO: se la creatura muore a metà comparsa (un colpo
	## d'area la prende appena nata) il tween muore con lei invece di scrivere su
	## un nodo liberato.
	var tw := bersaglio.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		func(v : float) -> void:
			for m in mesh:
				if is_instance_valid(m):
					(m as GeometryInstance3D).transparency = v,
		1.0, 0.0, durata)
	tw.finished.connect(func() -> void:
		## azzeramento ESATTO: vedi la nota sulla coda dei trasparenti
		for m in mesh:
			if is_instance_valid(m):
				(m as GeometryInstance3D).transparency = 0.0
		if is_instance_valid(vortice):
			vortice.emitting = false
			## non si libera subito: le particelle già emesse devono finire il
			## loro volo, o il vortice si spegne con uno scatto
			vortice.get_tree().create_timer(1.2).timeout.connect(
				func() -> void:
					if is_instance_valid(vortice):
						vortice.queue_free())
	)


## Il vortice che resta acceso finché la creatura non è opaca: particelle che
## cadono lungo un anello, viste dall'alto girano.
static func _crea_vortice(bersaglio : Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var alt : float = _altezza(bersaglio)
	p.amount = 48
	p.lifetime = 0.9
	p.explosiveness = 0.0
	p.local_coords = true
	p.position = Vector3(0, alt * 1.15, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = maxf(alt * 0.45, 0.25)
	mat.emission_ring_inner_radius = maxf(alt * 0.30, 0.15)
	mat.emission_ring_height = 0.05
	## il vortice: le particelle cadono VERSO la creatura mentre ruotano attorno
	## all'asse — è la spirale che si vede, non un anello che scende
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = alt * 0.5
	mat.initial_velocity_max = alt * 0.9
	mat.gravity = Vector3.ZERO
	mat.tangential_accel_min = 3.0
	mat.tangential_accel_max = 5.5
	mat.scale_min = 0.04
	mat.scale_max = 0.10
	mat.color = VIOLA
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = VIOLA
	sm.disable_receive_shadows = true
	quad.material = sm
	p.draw_pass_1 = quad

	bersaglio.add_child(p)
	p.emitting = true
	return p


## L'altezza serve a dimensionare il vortice: un lupo alpha da 2 metri e una
## Scintilla non possono avere lo stesso anello. Si misura dalle mesh, con un
## ripiego sensato se non ce ne sono.
static func _altezza(n : Node3D) -> float:
	var alt := 0.0
	for m in n.find_children("*", "VisualInstance3D", true, false):
		var ab : AABB = (m as VisualInstance3D).get_aabb()
		var s : Vector3 = (m as Node3D).global_transform.basis.get_scale()
		alt = maxf(alt, ab.size.y * s.y)
	return alt if alt > 0.05 else 1.0
