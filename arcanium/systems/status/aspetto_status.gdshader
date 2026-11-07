shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Lo status che si vede addosso: una pellicola sopra le mesh del corpo (material_overlay,
// quindi segue la pelle). `coprente` a 0 e' un bordo di luce che corre; a 1 copre il corpo
// a chiazze, come il ghiaccio.

uniform vec3 colore = vec3(1.0);
uniform float forza = 1.0;
uniform float coprente = 0.0;
uniform float scorre = 0.6;

varying vec3 locale;

float hash(vec3 q) {
	return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float rumore(vec3 q) {
	vec3 i = floor(q);
	vec3 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	locale = VERTEX;
}

void fragment() {
	float bordo = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	vec3 q = locale * 7.0 + vec3(0.0, -TIME * scorre * 3.0, 0.0);
	float n = 0.65 * rumore(q) + 0.35 * rumore(q * 2.3);
	float chiazze = smoothstep(0.38, 0.62, n);
	float a = mix(bordo * (0.55 + 0.75 * n), max(chiazze * 0.72, bordo), coprente);
	ALBEDO = mix(colore, vec3(1.0), clamp(bordo * coprente * 0.7 + n * n * 0.25, 0.0, 1.0));
	ALPHA = clamp(a * forza, 0.0, 1.0);
}
