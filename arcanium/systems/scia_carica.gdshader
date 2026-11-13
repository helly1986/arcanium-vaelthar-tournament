shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// IL BAGLIORE DELLA CARICA sulla lama (2026-11-13). UV.x attraversa la lama (0 e 1 i bordi
// dell'alone, 0.5 il filo), UV.y va dall'elsa (0) alla punta (1). Cresce con `livello`
// (la carica, 0..1); a carica piena pulsa, e `lampo` e' il colpo di luce dell'istante in
// cui si riempie. Il nucleo e' chiaro, l'alone caldo e sfrangiato.

uniform float livello = 0.0;
uniform float lampo = 0.0;
uniform vec3 alone : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 nucleo : source_color = vec3(1.0, 0.92, 0.7);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float rumore(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float d = abs(UV.x * 2.0 - 1.0);
	// L'energia sale lungo la lama verso la punta.
	float scorre = rumore(vec2(UV.x * 6.0, UV.y * 9.0 - TIME * 3.5));
	float bordo = 1.0 - smoothstep(0.15 + 0.5 * scorre * livello, 1.0, d);
	float filo = 1.0 - smoothstep(0.0, 0.22, d);
	float lungo = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y) * 0.4);
	float pieno = step(0.999, livello);
	// Niente pulsazione: la carica deve solo crescere (l'utente, 2026-11-13).
	float pulsa = 1.0 + pieno * 0.2;
	float a = lungo * (bordo * 0.55 + filo * 0.9) * livello * pulsa + lampo * lungo * bordo * 1.5;
	vec3 c = mix(alone, nucleo, filo * 0.8 + lampo * 0.5);
	ALBEDO = c * a;
}
