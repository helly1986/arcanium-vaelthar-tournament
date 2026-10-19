// Il corpo di uno SPIRITO (RIG-B: niente gambe, niente ossa, fluttua).
// Vedi corpo_spirito.gd, che lo costruisce copiando le texture del modello e
// lo pilota dal moto del corpo.
//
// Tutto e' in spazio MODELLO, perche' e' li' che sta la forma: il cappuccio in
// alto resta fermo, e piu' si scende — lembi del mantello, coda di radice — piu'
// ci si muove. `quota_cima` / `quota_fondo` sono la Y del modello in cima e in
// fondo, misurate dal modello stesso (AABB), non scritte a mano.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool ha_normal = false;
uniform bool ha_orm = false;
uniform float roughness_base = 0.8;

uniform float quota_cima = 1.0;
uniform float quota_fondo = -1.0;
// Semi-larghezza del modello: i lembi lontani dall'asse ondeggiano di piu'.
uniform float raggio = 0.5;

// Ondeggio a riposo (frazione dell'altezza), e quanto il fondo resta indietro
// nel moto (`vento`, gia' in spazio modello: verso e intensita').
uniform float ondeggio = 1.0;
uniform float ampiezza = 0.035;
uniform vec3 vento = vec3(0.0);
// Lembi che si ALLARGANO (attacco, carica): spinta radiale, pesata dal basso.
uniform float strappo = 0.0;
// La coda di radice si attorciglia attorno all'asse.
uniform float torsione = 0.35;
uniform float seme = 0.0;

// Il bordo luminoso della casata (fresnel) e il bagliore dentro il cappuccio.
uniform vec4 colore_bordo : source_color = vec4(0.35, 0.72, 0.55, 1.0);
uniform float bordo_forza = 1.2;
uniform float bagliore = 0.0;

// Dissoluzione (morte, ritirata): sotto soglia il pixel sparisce, sul filo brilla.
uniform sampler2D rumore_tex : hint_default_white, filter_linear, repeat_enable;
uniform float dissolvi = 0.0;

varying float v_peso;

void vertex() {
	float alto = max(quota_cima - quota_fondo, 0.001);
	float w = clamp((quota_cima - VERTEX.y) / alto, 0.0, 1.0);
	// Il cappuccio (primo quinto) quasi fermo; il fondo libero.
	w = smoothstep(0.12, 1.0, w);
	v_peso = w;
	float r = length(VERTEX.xz) / max(raggio, 0.001);
	float fase = TIME * 1.6 + VERTEX.y * 3.1 + seme;
	vec3 d = vec3(sin(fase), 0.0, cos(fase * 0.83 + 1.3)) * (ampiezza * alto * ondeggio) * w * (0.5 + r);
	d += vento * w * w;
	vec2 fuori = VERTEX.xz / max(length(VERTEX.xz), 0.001);
	d.xz += fuori * strappo * alto * 0.12 * w * (0.4 + r);
	VERTEX += d;
	// La coda: rotazione attorno all'asse Y, solo nella meta' bassa.
	float coda = max(w - 0.55, 0.0) / 0.45;
	float ang = sin(TIME * 1.1 + VERTEX.y * 2.3 + seme) * torsione * coda * ondeggio;
	float c = cos(ang);
	float s = sin(ang);
	VERTEX.xz = vec2(c * VERTEX.x - s * VERTEX.z, s * VERTEX.x + c * VERTEX.z);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb;
	if (ha_orm) {
		vec4 orm = texture(orm_tex, UV);
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	} else {
		ROUGHNESS = roughness_base;
	}
	if (ha_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// Il bagliore accende il BUIO: il vuoto del cappuccio e le ombre del muschio,
	// non la stoffa chiara — pesato sull'oscurita' della texture e sull'alto.
	// ⚠️ Soglia sul NERO vero: la stoffa della texture e' grigio scuro (~0,2) e
	// con una soglia larga il bagliore accendeva lo spirito intero di verde.
	float buio = 1.0 - smoothstep(0.03, 0.10, dot(a.rgb, vec3(0.333)));
	float alto_corpo = 1.0 - smoothstep(0.15, 0.45, v_peso);
	EMISSION = colore_bordo.rgb * (rim * bordo_forza * (1.0 + 0.5 * bagliore) + bagliore * buio * alto_corpo * 3.0);
	if (dissolvi > 0.0) {
		float n = texture(rumore_tex, UV * 2.0).r;
		// Dal basso verso l'alto: la coda se ne va per prima.
		float soglia = dissolvi * 1.3 - (1.0 - v_peso) * 0.3;
		if (n < soglia) {
			discard;
		}
		float filo = 1.0 - smoothstep(0.0, 0.06, n - soglia);
		EMISSION += colore_bordo.rgb * filo * 4.0;
	}
}
