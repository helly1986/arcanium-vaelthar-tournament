shader_type sky;

// Cielo notturno stellato per "L'Arena Senza Fuoco": gradiente blu-notte molto
// scuro (zenit quasi nero, orizzonte leggermente più chiaro/freddo) + campo di
// stelle procedurale (hash su EYEDIR), niente sole. Poche stelle grandi danno
// un pallido bagliore bluastro che si somma all'ambient SKY della scena.

uniform vec3 zenith_color : source_color = vec3(0.005, 0.01, 0.03);
uniform vec3 horizon_color : source_color = vec3(0.03, 0.05, 0.09);
uniform float star_density : hint_range(0.0, 1.0) = 0.12;
uniform float star_brightness : hint_range(0.0, 5.0) = 0.75;
uniform float star_size : hint_range(0.01, 1.0) = 0.35;
uniform vec3 star_color : source_color = vec3(0.75, 0.82, 1.0);

const float STAR_GRID_FREQ = 340.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	// gradiente verticale in base all'altezza dell'occhio di vista
	float t = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 base = mix(horizon_color, zenith_color, pow(t, 0.5));

	// campo stellare: quantizza la direzione in una griglia fine sulla sfera per
	// ottenere punti stabili (non tremolano al ruotare della camera), poi
	// disegna ogni stella come un puntino tondo e sfumato (non un blocco pieno).
	vec3 p = EYEDIR * STAR_GRID_FREQ;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5; // offset dal centro della cella, -0.5..0.5

	float h = hash13(cell);
	float present = step(1.0 - star_density * 0.02, h);

	// variazione di luminosità per-stella (alcune più "pallide", poche brillanti)
	float b = hash13(cell + 7.31);
	float twinkle = 0.35 + 0.65 * b;

	// dot rotondo con bordo morbido, niente puntoni pieni netti
	float d = length(local);
	float dot_mask = 1.0 - smoothstep(0.0, star_size * 0.5, d);

	// solo sopra l'orizzonte, sfumando verso il basso
	float horizon_fade = smoothstep(-0.05, 0.15, EYEDIR.y);

	vec3 stars = star_color * present * dot_mask * twinkle * star_brightness * horizon_fade;

	COLOR = base + stars;
}
