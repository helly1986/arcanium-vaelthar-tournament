shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// L'infusione sull'arma (LucidaTecnica.infusione): una pellicola sopra la lama. Lingue che
// corrono lungo l'arma e un bordo acceso. `scatti` a 1 la fa battere come una scarica.

uniform vec3 colore = vec3(1.0);
uniform vec3 nucleo = vec3(1.0);
uniform float forza = 1.0;
uniform float velocita = 1.0;
uniform float scatti = 0.0;
uniform float scala = 16.0;

varying vec3 locale;

float hash(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

float rumore(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	locale = VERTEX;
}

void fragment() {
	vec2 q = vec2(locale.x + locale.z, locale.y) * scala;
	float n = rumore(q + vec2(0.0, -TIME * velocita * 3.0));
	n = 0.6 * n + 0.4 * rumore(q * 2.2 + vec2(3.0, -TIME * velocita * 5.0));
	float bordo = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.8);
	float lingue = smoothstep(0.42, 0.68, n);
	float battito = mix(1.0, step(0.45, hash(vec2(floor(TIME * 18.0), 3.0))), scatti);
	ALBEDO = mix(colore, nucleo, clamp(lingue * lingue + bordo * 0.3, 0.0, 1.0));
	ALPHA = clamp((lingue * 0.8 + bordo * 0.55) * forza * battito, 0.0, 1.0);
}
