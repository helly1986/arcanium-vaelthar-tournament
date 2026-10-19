shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// SIGILLO DELL'EVOCAZIONE — anello runico a terra sotto ogni creatura evocata.
//
// PROBLEMA DI CAMPO: il design prevede 3-4 evocazioni PER FAZIONE in campo
// contemporaneamente. In isometrica, con l'arena buia, una mischia di 8
// creature diventa illeggibile: non capisci quali sono TUE. Il sigillo risolve
// esattamente questo — un marchio colorato a terra, sempre visibile perche' sta
// sul piano che la camera iso inquadra meglio, che non e' occluso dai corpi.
//
// COSTO / BATCHING: la tinta e' una `instance uniform`, NON un uniform normale.
// Cosi' tutte le evocazioni condividono UNA sola ShaderMaterial (una draw call
// per batch) pur avendo colori diversi. Duplicare il materiale per creatura
// romperebbe il batch — con 8 istanze e' esattamente lo scenario che la regola
// vieta.

uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform float spin_speed = 0.55;
uniform float ring_width : hint_range(0.005, 0.2) = 0.045;
uniform float rune_count = 7.0;
uniform float pulse_speed = 2.2;

// Per-istanza (set_instance_shader_parameter):
//   inst_tint   → colore di fazione/famiglia della creatura
//   inst_charge → 0..1, sale mentre la creatura carica la scarica radiale
instance uniform vec4 inst_tint : source_color = vec4(1.0, 0.2, 0.85, 1.0);
instance uniform float inst_charge = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);

	// Anello esterno fisso: la "pianta" della creatura, dove appoggia.
	float outer = smoothstep(ring_width, 0.0, abs(r - 0.92));

	// Corona di rune controrotante: e' il movimento a farlo leggere come
	// magia attiva invece che come ombra dipinta.
	float spin = TIME * spin_speed;
	float runes = abs(fract((ang + spin) / TAU * rune_count) * 2.0 - 1.0);
	runes = smoothstep(0.80, 1.0, runes);
	float rune_band = smoothstep(0.16, 0.0, abs(r - 0.68)) * runes;

	// Anello interno che gira al contrario, meta' velocita'.
	float inner_spin = -TIME * spin_speed * 0.5;
	float inner = abs(fract((ang + inner_spin) / TAU * (rune_count * 2.0)) * 2.0 - 1.0);
	inner = smoothstep(0.85, 1.0, inner) * smoothstep(0.18, 0.0, abs(r - 0.42));

	// Alone centrale, tenuto basso: deve dire "sono qui", non accecare.
	float core = smoothstep(1.0, 0.0, r) * 0.14;

	// Carica: quando la creatura sta per scaricare, tutto il sigillo pulsa.
	float pulse = 1.0 + inst_charge * (0.6 + 0.4 * sin(TIME * pulse_speed * TAU));

	float a = (outer * 0.85 + rune_band * 0.6 + inner * 0.45 + core) * pulse;
	a *= 1.0 - smoothstep(0.95, 1.02, r);   // taglia gli angoli del quad

	ALBEDO = inst_tint.rgb * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
