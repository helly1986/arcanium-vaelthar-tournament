shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// La PROPAGAZIONE DELL'EQUILIBRIO a terra: un fronte irregolare che corre fuori dal
// punto d'impatto e lascia dietro di se' crepe e un velo. Sinistra oscura (+X nel
// nodo, che ha l'orientamento di chi colpisce), destra lucente; il confine e' una
// cucitura frastagliata, non una riga. Dall'isometrica si legge il piano.

// Il raggio del fronte e quello massimo, in metri.
uniform float fronte = 0.0;
uniform float raggio = 7.0;
// 1 mentre vive, a 0 quando si spegne.
uniform float vita = 1.0;
// Dove l'onda arriva davvero (propagazione_equilibrio.gd): baratri e muri la fermano.
uniform sampler2D suolo : filter_linear, repeat_disable;
uniform float mezzo_suolo = 8.0;

uniform vec3 cresta_luce = vec3(1.0, 0.93, 0.66);
uniform vec3 alone_luce = vec3(0.86, 0.62, 0.24);
uniform vec3 cresta_buio = vec3(0.36, 0.13, 0.68);
uniform vec3 alone_buio = vec3(0.025, 0.008, 0.05);

varying vec2 p;

void vertex() {
	p = VERTEX.xz;
}

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

void fragment() {
	float d = length(p);
	float angolo = atan(p.y, p.x);
	// Il fronte non e' un cerchio: il rumore e' letto sulla circonferenza.
	vec2 sul_giro = vec2(cos(angolo), sin(angolo));
	float f = fronte + (fbm(sul_giro * 2.6 + vec2(fronte * 0.12, 3.0)) - 0.5) * 1.5;

	// Il lato, con la cucitura frastagliata: 1 = oscuro.
	float bordo_lato = p.x + (fbm(vec2(p.y * 0.8, 3.1)) - 0.5) * 0.9;
	float oscuro = smoothstep(-0.09, 0.09, bordo_lato);

	float dietro = smoothstep(0.0, 0.5, f - d);
	float cresta = smoothstep(0.75, 0.0, abs(d - f)) * (0.72 + 0.28 * fbm(p * 2.2));
	float nucleo = smoothstep(0.26, 0.0, abs(d - f));

	// Le crepe che restano: rumore a creste, che si raffreddano allontanandosi dal fronte.
	float vena = 1.0 - abs(2.0 * fbm(p * 1.15 + vec2(4.0, 8.0)) - 1.0);
	float crepe = pow(vena, 9.0) * dietro * smoothstep(5.5, 0.4, f - d);
	float velo = dietro * smoothstep(3.4, 0.0, f - d) * (0.25 + 0.5 * fbm(p * 0.9 + 11.0));

	// La cucitura si accende fra le due meta', e corre col fronte.
	float cucitura = smoothstep(0.24, 0.0, abs(bordo_lato)) * dietro * smoothstep(3.0, 0.0, f - d);

	vec3 luce = mix(alone_luce, cresta_luce, clamp(nucleo + crepe, 0.0, 1.0));
	// Il buio non puo' brillare: e' scuro col bordo viola, e per questo sta bene
	// accanto al lucente.
	vec3 buio = mix(alone_buio, cresta_buio, clamp(nucleo * 0.9 + crepe * 1.1, 0.0, 1.0));
	vec3 colore = mix(luce, buio, oscuro);
	colore = mix(colore, vec3(0.92, 0.84, 1.0), cucitura * 0.8);

	// Il lucente rischiara appena, l'oscuro si mangia il pavimento.
	float a = max(max(cresta * 0.95, crepe), velo * mix(0.42, 1.25, oscuro));
	a = max(a, cucitura * 0.85);
	a *= smoothstep(raggio, raggio - 1.6, d) * vita;
	a *= smoothstep(0.35, 0.7, texture(suolo, p / (2.0 * mezzo_suolo) + 0.5).r);

	ALBEDO = colore;
	ALPHA = clamp(a, 0.0, 1.0);
}
