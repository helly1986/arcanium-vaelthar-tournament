extends RefCounted
class_name BossVFX

## Materiali condivisi per le particelle del Senza Nome.
##
## Le texture in `assets/vfx/` sono MONOCROMATICHE apposta: portano solo la forma
## (alpha ~= luminanza, sfondo trasparente), il colore lo mette la mossa via
## `_glow_tint()`. Così la stessa scintilla serve sia FRATTURA (ciano) sia
## EROSIONE (viola) senza rigenerare nulla.
##
## NOTA su `shading_mode = UNSHADED`: in questa modalità Godot scrive ALBEDO
## direttamente e IGNORA `emission`. Il bagliore (bloom) si ottiene portando
## `albedo_color` SOPRA 1.0 — è quello che fa il parametro `energy` qui sotto.

const TEX_SPARK      := preload("res://assets/vfx/spark.png")
const TEX_ARC        := preload("res://assets/vfx/arc_lightning.png")
const TEX_RING       := preload("res://assets/vfx/shockwave_ring.png")
const TEX_ENERGY     := preload("res://assets/vfx/energy_wisp.png")
const TEX_SMOKE      := preload("res://assets/vfx/smoke_wisp.png")
const TEX_GLOW       := preload("res://assets/vfx/soft_glow.png")

## Materiale additivo per un quad di particella.
##
## `energy > 1.0` spinge il colore fuori dal range LDR: è ciò che accende il
## bloom. L'additivo somma al fondo, quindi lo sfondo trasparente della texture
## (alpha ~0) non lascia il tipico quadrato nero.
static func particle_material(tex : Texture2D, tinta : Color, energy : float = 2.5) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_texture = tex
	sm.albedo_color = Color(tinta.r * energy, tinta.g * energy, tinta.b * energy, tinta.a)
	# Le particelle si compenetrano di continuo: senza questo i bordi dei quad
	# si vedono come tagli netti l'uno contro l'altro.
	sm.disable_receive_shadows = true
	sm.no_depth_test = false
	sm.vertex_color_use_as_albedo = true   # il color_ramp della ParticleProcessMaterial
	return sm

## Variante NON additiva, per il "fuoco nero" del proiettile.
##
## L'orbo è Erosione condensata: ha una luce a energia NEGATIVA e deve SCURIRE
## l'ambiente mentre vola. Un blend additivo lo farebbe brillare e ribalterebbe
## proprio la lettura che la mossa cerca — quindi qui la texture serve solo a
## dare FORMA alle braci, non bagliore. Colori sotto 1.0, blend MIX.
static func dark_particle_material(tex : Texture2D, tinta : Color) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_texture = tex
	sm.albedo_color = tinta
	sm.vertex_color_use_as_albedo = true
	return sm
