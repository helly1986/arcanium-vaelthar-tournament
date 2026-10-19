extends RefCounted
class_name ArcaniumVFX

## Fabbrica di materiali per gli shader di magia (gelo, cristallo, sigilli).
##
## Gemello di BossVFX (che resta il posto per i materiali a PARTICELLA basati
## sulle texture monocromatiche in assets/vfx/): qui vivono i materiali basati
## su SHADER, cioe' quelli che devono ANIMARSI da soli sulla GPU o portare
## informazione di gameplay (raggio, durata, fazione).
##
## REGOLA DI BATCHING seguita qui — e la ragione per cui questo file esiste
## invece di costruire i materiali dentro ogni scena:
##   • CONDIVISO  → un solo ShaderMaterial per TUTTE le istanze, quando i
##     parametri che cambiano possono stare in `instance uniform`
##     (sigillo delle evocazioni: 3-4 per fazione in campo, duplicare il
##     materiale romperebbe la batch).
##   • UNICO      → un ShaderMaterial per istanza, quando i parametri sono
##     realmente per-istanza e animati da CPU (campo di gelo: `life` e `open`
##     cambiano ogni frame e ci sono al massimo 1-2 campi vivi insieme).
##
## Nota sul renderer: il progetto gira in MOBILE (project.godot →
## renderer/rendering_method="mobile"). Nessuno di questi shader legge
## DEPTH_TEXTURE o SCREEN_TEXTURE, che li' non sono disponibili: niente soft
## particles, niente proximity fade. La morbidezza si ottiene con le maschere
## radiali dentro gli shader.

const SH_FROST_FIELD := preload("res://arcanium/systems/vfx/frost_field.gdshader")
const SH_FROST_WALL  := preload("res://arcanium/systems/vfx/frost_wall.gdshader")
const SH_ICE_CRYSTAL := preload("res://arcanium/systems/vfx/ice_crystal.gdshader")
const SH_SUMMON_SIGIL := preload("res://arcanium/systems/vfx/summon_sigil.gdshader")
const SH_EROSION_WALL := preload("res://arcanium/systems/vfx/erosion_wall.gdshader")

## Materiale del sigillo, CONDIVISO da tutte le evocazioni. Il colore e la
## carica passano da set_instance_shader_parameter sul MeshInstance3D, non da
## qui: vedi summon_sigil.gdshader.
static var _sigil_shared : ShaderMaterial = null

## ─── Campo di gelo (disco a terra) ───────────────────────────────────────────
## UNICO per istanza: `life`/`open` sono animati per-campo.
static func frost_field_material(tinta : Color, energy : float = 1.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_FROST_FIELD
	m.set_shader_parameter("tint", tinta)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("life", 1.0)
	m.set_shader_parameter("open", 0.0)
	return m

## ─── Velo verticale sul bordo del campo ──────────────────────────────────────
static func frost_wall_material(tinta : Color, energy : float = 1.1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_FROST_WALL
	m.set_shader_parameter("tint", tinta)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("life", 1.0)
	m.set_shader_parameter("open", 0.0)
	return m

## ─── Ghiaccio solido (lama dello Shard, punte del campo) ─────────────────────
## UNICO per istanza solo perche' la lama e le punte usano energie diverse; se
## servisse spingere il numero di proiettili contemporanei, questo e' il primo
## candidato a diventare un materiale condiviso + instance uniform.
static func ice_crystal_material(tinta : Color, glow : float = 1.8,
		opacity : float = 0.62) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_ICE_CRYSTAL
	m.set_shader_parameter("ice_tint", tinta)
	m.set_shader_parameter("core_tint", tinta.lerp(Color.WHITE, 0.55))
	m.set_shader_parameter("glow_energy", glow)
	m.set_shader_parameter("body_opacity", opacity)
	return m

## ─── Membrana del muro di Erosione ───────────────────────────────────────────
## CONDIVISO da tutti i segmenti di UN muro: un muro nasce da una singola
## spadata e i suoi tratti condividono età e tinta, quindi non serve un
## materiale per segmento (ne nascono parecchi per swing — sarebbero altrettanti
## stati GPU per niente). Il BossWall ne tiene uno e ci scrive `life`.
static func erosion_wall_material(tinta : Color, energy : float = 1.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_EROSION_WALL
	m.set_shader_parameter("tint", tinta)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("life", 1.0)
	return m

## ─── Sigillo dell'evocazione ─────────────────────────────────────────────────
## CONDIVISO: ritorna sempre la STESSA istanza. Non modificarne i parametri per
## personalizzare una creatura — si personalizza con
## `mesh_instance.set_instance_shader_parameter("inst_tint", colore)`.
static func summon_sigil_material() -> ShaderMaterial:
	if _sigil_shared == null:
		_sigil_shared = ShaderMaterial.new()
		_sigil_shared.shader = SH_SUMMON_SIGIL
		_sigil_shared.set_shader_parameter("energy", 1.6)
	return _sigil_shared

## Costruisce il MeshInstance3D del sigillo, gia' orientato a terra e tinto.
## `radius` in metri (il quad e' 2*radius di lato, lo shader ritaglia il cerchio).
static func make_summon_sigil(radius : float, tinta : Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Sigillo"
	var quad := PlaneMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = quad
	mi.material_override = summon_sigil_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Sopra il pavimento quanto basta a non compenetrarlo, sotto la soglia in cui
	## si vedrebbe "galleggiare" in isometrica.
	mi.position = Vector3(0.0, 0.04, 0.0)
	mi.set_instance_shader_parameter("inst_tint", tinta)
	mi.set_instance_shader_parameter("inst_charge", 0.0)
	return mi
