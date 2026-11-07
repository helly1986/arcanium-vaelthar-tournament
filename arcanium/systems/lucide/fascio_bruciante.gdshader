shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Il LASCITO DEL BRUCIANTE: il fascio. Un cilindro dal bordo che non sta fermo, fuoco
// teal che corre lungo l'asse; `forza` distingue il corpo largo dal nucleo stretto.

uniform float lunghezza = 20.0;
// Fin dove e' arrivata la testa, in metri.
uniform float fronte = 0.0;
uniform float vita = 1.0;
uniform float forza = 0.6;
// Quanto si muove il bordo, in quota del raggio.
uniform float agitazione = 0.3;
uniform vec3 esterno = vec3(0.03, 0.62, 0.58);
uniform vec3 interno = vec3(0.62, 1.0, 0.92);

varying float lungo;

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
	for (int k = 0; k < 3; k++) {
		v += a * rumore(q);
		q = q * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	lungo = VERTEX.y + lunghezza * 0.5;
	float giro = atan(VERTEX.z, VERTEX.x);
	vec2 sul_giro = vec2(cos(giro), sin(giro)) * 1.4;
	float n = fbm(sul_giro + vec2(lungo * 0.45 - TIME * 7.0, TIME * 1.3));
	// Nasce stretto dall'arco e si apre; il bordo e' una fiamma.
	float apertura = mix(0.22, 1.0, smoothstep(0.0, 2.6, lungo));
	VERTEX.xz *= apertura * (1.0 + (n - 0.5) * agitazione * 2.0);
}

void fragment() {
	float faccia = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fiamma = fbm(vec2(lungo * 0.38 - TIME * 8.5, UV.x * 7.0 + TIME * 0.6));
	float lingue = smoothstep(0.28, 0.72, fiamma);
	float corpo = pow(faccia, 1.6);
	vec3 colore = mix(esterno, interno, clamp(pow(faccia, 3.0) * lingue * 1.3, 0.0, 1.0));
	float a = corpo * mix(0.45, 1.0, lingue) * forza;
	a *= smoothstep(fronte, fronte - 1.4, lungo) * vita;
	// Si perde dove finisce, invece di troncarsi.
	a *= smoothstep(lunghezza, lunghezza - 0.8, lungo);
	ALBEDO = colore;
	ALPHA = clamp(a, 0.0, 1.0);
}
