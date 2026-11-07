shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Il BRUCIATO che il Lascito del Bruciante lascia a terra: una striscia carbonizzata
// dai bordi mangiati, con braci teal nelle crepe che si spengono prima del nero.

uniform float lunghezza = 20.0;
uniform float mezza_larghezza = 1.7;
uniform float fronte = 0.0;
// `vita` spegne tutto, `braci` solo il teal.
uniform float vita = 1.0;
uniform float braci = 1.0;
// Dove c'e' suolo davvero (lascito_bruciante.gd): sul baratro non si brucia niente.
uniform sampler2D suolo : filter_linear, repeat_disable;
uniform float margine = 2.2;

varying vec2 p;

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

float fbm(vec2 q) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * rumore(q);
		q = q * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	p = VERTEX.xz + vec2(0.0, lunghezza * 0.5);
}

void fragment() {
	// I bordi non sono dritti: la larghezza cambia lungo la striscia.
	float largo = mezza_larghezza * (0.62 + 0.55 * fbm(vec2(p.y * 0.42, 5.0)));
	float dentro = smoothstep(largo, largo * 0.55, abs(p.x) + (fbm(p * 1.8) - 0.5) * 0.7);
	float nero = dentro * smoothstep(0.0, 0.8, fronte - p.y);
	nero *= smoothstep(0.0, 0.8, p.y) * smoothstep(lunghezza + 0.5, lunghezza - 0.6, p.y);

	float vena = 1.0 - abs(2.0 * fbm(p * 1.5 + vec2(3.0, 1.0)) - 1.0);
	float crepe = pow(vena, 7.0) * dentro;
	float brace = crepe * braci * (0.7 + 0.3 * sin(TIME * 5.0 + p.y * 1.3));

	vec3 carbone = vec3(0.012, 0.016, 0.018) + vec3(0.02) * fbm(p * 3.0);
	vec3 colore = mix(carbone, vec3(0.2, 1.0, 0.88), clamp(brace * 1.4, 0.0, 1.0));
	float a = nero * max(0.86, brace) * vita;
	vec2 sul_suolo = vec2(p.x / (2.0 * margine) + 0.5, p.y / lunghezza);
	a *= smoothstep(0.35, 0.7, texture(suolo, sul_suolo).r);

	ALBEDO = colore;
	ALPHA = clamp(a, 0.0, 1.0);
}
