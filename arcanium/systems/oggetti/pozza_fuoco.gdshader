shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// La POZZA DI FUOCO dell'ampolla (2026-11-13), vista da sopra: un disco irregolare di
// liquido che brucia. Non un cerchio pulito: il bordo e' frastagliato da un rumore,
// dentro scorrono lingue chiare su un fondo arancio scuro, e verso il bordo restano
// braci rosse. `vita` spegne tutto, `fiammata` e' il lampo dei primi istanti.

uniform float raggio = 2.0;
uniform float vita = 1.0;
uniform float fiammata = 0.0;
uniform float seme = 0.0;

varying vec3 locale;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float rumore(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float frattale(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * rumore(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	locale = VERTEX;
}

void fragment() {
	vec2 p = locale.xz / raggio;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// Il bordo: un raggio che cambia con l'angolo, come una macchia versata.
	float bordo = 0.72 + 0.22 * frattale(vec2(ang * 1.6 + seme, seme * 3.0)) + 0.08 * sin(ang * 5.0 + seme);
	float dentro = 1.0 - smoothstep(bordo - 0.35, bordo, r);
	// Le lingue che scorrono: rumore che sale verso il centro.
	float t = TIME;
	float lingue = frattale(p * 3.2 + vec2(t * 0.35, -t * 0.6) + seme);
	lingue = smoothstep(0.42, 0.85, lingue + 0.18 * sin(t * 3.0 + r * 9.0));
	float braci = smoothstep(0.55, 0.9, frattale(p * 9.0 - t * 0.25 + seme * 2.0));
	vec3 fondo = vec3(0.55, 0.12, 0.02);
	vec3 chiaro = vec3(1.0, 0.62, 0.18);
	vec3 bianco = vec3(1.0, 0.9, 0.6);
	// Il centro brucia piu' forte; il bordo si spegne in braci sparse.
	float centro = 1.0 - smoothstep(0.0, bordo, r);
	vec3 c = fondo * (0.7 + 0.6 * centro) + chiaro * lingue * (0.6 + 0.8 * centro) + bianco * pow(lingue, 4.0) * 0.6 * centro;
	c += vec3(0.9, 0.18, 0.03) * braci * 0.6;
	c += bianco * fiammata * (1.0 - r);
	float alfa = dentro * vita * (0.55 + 0.45 * lingue);
	ALBEDO = c * alfa;
}
