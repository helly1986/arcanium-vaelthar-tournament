shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// LA SCIA DELLA LAMA (2026-11-13). UV.x e' l'eta' del tratto (0 appena passato, 1
// spento), UV.y va dalla base (0) alla punta (1) della lama. La scia e' piena vicino al
// filo e alla punta e si sfrangia verso la base; dietro si consuma in strisce, non in un
// velo uniforme.

uniform vec3 colore : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 nucleo : source_color = vec3(1.0, 1.0, 1.0);
uniform float forza = 0.8;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float rumore(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float eta = UV.x;
	float lungo = UV.y;
	// Strisce lungo la lama, che scorrono con l'eta': la scia si "sfilaccia".
	float strisce = rumore(vec2(lungo * 14.0, eta * 3.0 - TIME * 2.0));
	float vivo = pow(1.0 - eta, 3.0);
	// Un velo leggero sul corpo e un FILO acceso sulla traiettoria della punta: e' il filo
	// che si legge, il velo da' solo il volume del colpo.
	float velo = smoothstep(0.0, 1.0, lungo) * 0.2;
	float filo = smoothstep(0.82, 0.98, lungo) * (1.0 - smoothstep(0.98, 1.0, lungo) * 0.5);
	float a = vivo * (velo * (0.4 + 0.6 * strisce) + filo * 0.9) * forza;
	vec3 c = mix(colore, nucleo, filo * pow(vivo, 0.5));
	ALBEDO = c * a;
}
