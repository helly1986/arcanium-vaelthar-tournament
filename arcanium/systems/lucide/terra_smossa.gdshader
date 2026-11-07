shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Il punto in cui la vanga di Aurin scava: una buca scura dai bordi mangiati, e crepe
// da cui filtra la luce pallida degli spiriti.

uniform float raggio = 2.4;
uniform float vita = 1.0;
uniform float luce = 1.0;
uniform vec3 pallido = vec3(0.75, 0.3, 1.0);

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
	p = VERTEX.xz;
}

void fragment() {
	float d = length(p);
	float giro = atan(p.y, p.x);
	vec2 sul_giro = vec2(cos(giro), sin(giro));
	float bordo = 0.75 + (fbm(sul_giro * 2.2 + 4.0) - 0.5) * 0.7;
	float buca = smoothstep(bordo, bordo * 0.55, d);

	// Crepe che partono dalla buca: rumore a creste, piu' fitte vicino al centro.
	float vena = 1.0 - abs(2.0 * fbm(p * 2.1 + vec2(2.0, 6.0)) - 1.0);
	float crepe = pow(vena, 8.0) * smoothstep(raggio, bordo, d);
	float alone = smoothstep(bordo * 1.5, bordo * 0.6, d) * (1.0 - buca) * 0.5;

	vec3 terra = vec3(0.015, 0.018, 0.016);
	float acceso = clamp((crepe + alone) * luce, 0.0, 1.0);
	// Dal fondo della buca sale il chiarore, finche' gli spiriti non sono usciti.
	vec3 fondo = mix(terra, pallido, smoothstep(0.5, 0.0, d) * luce * 0.9);
	ALBEDO = mix(fondo, pallido, acceso * (1.0 - buca));
	ALPHA = clamp(max(buca * 0.96, acceso), 0.0, 1.0) * vita;
}
