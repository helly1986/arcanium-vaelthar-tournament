shader_type canvas_item;

// La BARRA VIVA dell'HUD (design-ui-nuova, 2026-10-21): un liquido dentro un
// tubo di vetro scuro, non un rettangolo piatto.
//   tipo 0  SANGUE:   denso, ribolle piano, il bordo ondeggia; sotto il 30%
//                     pulsa, come un battito.
//   tipo 1  ARCANIUM: scorre verso destra a vene, con scintille che si
//                     accendono e si spengono.
//   tipo 2  VIGORE:   leggero, strisce che corrono, quasi aria.
// La scia (il danno appena preso) e' una zona chiara e spenta fra `valore` e
// `scia`, come in BarChip. Tutto procedurale: nessuna texture, costa poco
// anche su un telefono di fascia media (tre rettangoli piccoli).

uniform float valore : hint_range(0.0, 1.0) = 1.0;
uniform float scia : hint_range(0.0, 1.0) = 1.0;
uniform int tipo = 0;
uniform vec4 colore_fondo : source_color = vec4(0.30, 0.02, 0.03, 1.0);
uniform vec4 colore_vivo : source_color = vec4(0.86, 0.14, 0.12, 1.0);
uniform vec4 colore_luce : source_color = vec4(1.0, 0.55, 0.45, 1.0);
// Larghezza in pixel, per tenere le onde della stessa misura a ogni lunghezza.
uniform float larghezza_px = 240.0;
uniform float altezza_px = 16.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rumore(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * rumore(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// Coordinate in "altezze": un'onda larga quanto la barra e' alta, a ogni
	// lunghezza della barra.
	vec2 q = vec2(uv.x * larghezza_px / altezza_px, uv.y);

	// ── Il tubo: estremi arrotondati, fondo scuro con un'ombra dentro.
	float r = 0.5;
	vec2 pq = vec2(q.x, uv.y);
	float lung = larghezza_px / altezza_px;
	float dx = max(max(r - pq.x, pq.x - (lung - r)), 0.0);
	float dist = length(vec2(dx, pq.y - 0.5));
	float dentro = 1.0 - smoothstep(r - 0.06, r, dist);
	float ombra = smoothstep(0.0, 0.5, abs(uv.y - 0.5));
	vec3 tubo = mix(vec3(0.035, 0.028, 0.030), vec3(0.008, 0.006, 0.008), ombra);

	// ── Il bordo del liquido ondeggia (il sangue di piu', il vigore poco).
	float ampiezza = tipo == 0 ? 0.010 : (tipo == 1 ? 0.006 : 0.004);
	float onda = sin(uv.y * 9.0 + t * 3.1) * ampiezza
			+ sin(uv.y * 17.0 - t * 4.7) * ampiezza * 0.5;
	float bordo = valore + onda * step(0.002, valore) * step(valore, 0.998);
	float pieno = 1.0 - smoothstep(bordo - 0.002, bordo + 0.002, uv.x);

	// ── Il liquido.
	vec2 flusso;
	float n;
	if (tipo == 0) {
		flusso = vec2(q.x * 0.55 - t * 0.12, uv.y * 1.6 + t * 0.05);
		// Grumi scuri e filo vivo: il sangue non e' una tinta unita.
		n = fbm(flusso * 1.3 + vec2(fbm(flusso + t * 0.08) * 1.6, 0.0));
		n = smoothstep(0.30, 0.78, n);
	} else if (tipo == 1) {
		flusso = vec2(q.x * 0.7 - t * 0.9, uv.y * 2.4);
		float vena = fbm(flusso + vec2(0.0, fbm(flusso * 1.7 - t * 0.3) * 1.4));
		n = smoothstep(0.35, 0.75, vena);
	} else {
		flusso = vec2(q.x * 0.35 - t * 1.6, uv.y * 3.0);
		n = smoothstep(0.45, 0.85, rumore(flusso * vec2(1.0, 2.5)));
	}
	vec3 liquido = mix(colore_fondo.rgb, colore_vivo.rgb, (tipo == 0 ? 0.15 : 0.35) + (tipo == 0 ? 0.85 : 0.65) * n);
	// Piu' scuro in basso, piu' chiaro sotto la superficie: ha un volume.
	liquido *= mix(1.15, 0.55, smoothstep(0.15, 1.0, uv.y));
	// Il battito del sangue quando sta per finire.
	if (tipo == 0 && valore < 0.3) {
		float battito = pow(max(sin(t * 6.0), 0.0), 6.0);
		liquido += colore_luce.rgb * battito * 0.35;
	}
	// Le scintille dell'Arcanium.
	if (tipo == 1) {
		vec2 cella = floor(vec2(q.x * 2.2 - t * 1.8, uv.y * 4.0));
		float h = hash(cella);
		float accesa = step(0.86, h) * pow(max(sin(t * 3.0 + h * 40.0), 0.0), 8.0);
		vec2 f = fract(vec2(q.x * 2.2 - t * 1.8, uv.y * 4.0)) - 0.5;
		liquido += colore_luce.rgb * accesa * (1.0 - smoothstep(0.0, 0.35, length(f))) * 1.4;
	}
	// La superficie che brilla: una luce sul fronte del liquido.
	float fronte = exp(-abs(uv.x - bordo) * larghezza_px * 0.18) * step(0.002, valore);
	liquido += colore_luce.rgb * fronte * 0.55;

	// ── La scia: il danno appena preso, chiaro e spento.
	float in_scia = step(bordo, uv.x) * (1.0 - step(scia, uv.x));
	// Spenta e velata: si vede il tubo sotto, e un filo chiaro sul suo fronte.
	vec3 col_scia = mix(colore_fondo.rgb, colore_luce.rgb, 0.45);
	float fronte_scia = exp(-abs(uv.x - scia) * larghezza_px * 0.35);

	vec3 col = tubo;
	col = mix(col, col_scia, in_scia * 0.55);
	col += colore_luce.rgb * fronte_scia * in_scia * 0.25;
	col = mix(col, liquido, pieno);

	// ── Il vetro: riflesso in alto, filo scuro in basso.
	float riflesso = smoothstep(0.32, 0.12, uv.y) * smoothstep(0.02, 0.12, uv.y);
	col += vec3(1.0) * riflesso * 0.13;
	col *= mix(1.0, 0.6, smoothstep(0.82, 1.0, uv.y));

	COLOR = vec4(col, dentro);
}
