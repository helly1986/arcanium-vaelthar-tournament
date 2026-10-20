shader_type spatial;

// La NEBBIA del mini-dungeon, come material_overlay su ogni mesh del dungeon:
// un velo nero sopra il materiale vero, opaco dove la cella non si e' mai
// vista, mezzo dove e' esplorata ma ora fuori vista, assente dove si vede.
// La texture ha un texel per cella: R = esplorata, G = vista adesso (vedi
// nebbia_dungeon.gd).
//
// Ogni frammento legge la nebbia un po' DAVANTI a se', lungo la sua normale:
// la faccia di un muro appartiene alla stanza che guarda, non a quella dietro.
// I tetti dei muri (normale in su) cadono sul bordo, e li' la texture e'
// dilatata dalle celle vicine.

render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;

uniform sampler2D nebbia : filter_linear, repeat_disable;
// Angolo della cella (0, 0) nel mondo, lato della cella, celle per lato.
uniform vec2 angolo;
uniform float lato = 2.0;
uniform vec2 dimensioni = vec2(64.0, 64.0);
// Quanto resta di luce in una cella esplorata ma fuori vista.
uniform float luce_esplorata = 0.4;
uniform float anticipo = 0.9;

varying vec3 pos_mondo;
varying vec3 normale_mondo;

void vertex() {
	pos_mondo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normale_mondo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = pos_mondo.xz + normale_mondo.xz * anticipo;
	vec2 uv = (p - angolo) / lato / dimensioni;
	vec2 f = texture(nebbia, uv).rg;
	float luce = max(f.r * luce_esplorata, f.g);
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - luce;
}
