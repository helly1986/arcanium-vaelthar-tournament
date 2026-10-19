shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// CAMPO DI GELO — disco a terra di "Morsa del Gelo".
//
// LETTURA ISOMETRICA (camera a ~52° sull'orizzonte, offset 0/28/22): il campo
// e' visto quasi dall'alto, quindi tutta l'informazione di gameplay sta sul
// PIANO, non in altezza:
//   1. BORDO  → dove finisce il raggio (5 m). Sempre acceso, e' il contratto.
//   2. RIEMPIMENTO → il disco interno pieno si RITIRA verso il centro col
//      passare del tempo: `life` va 1→0, quindi si legge quanto dura ancora
//      esattamente come un quadrante di cooldown. E' invariante alla ROTAZIONE
//      della camera (IsoCam ruota in azimut): una lancetta angolare sarebbe
//      ambigua, un raggio che si accorcia no.
//   3. cristalli radiali procedurali → texture, zero asset, costo trascurabile.
//
// blend_add: le arene sono buie e low-albedo (bg 0.027). Additivo = l'effetto
// SOMMA luce al fondo e non mostra mai il quadrato nero della trasparenza.
// depth_draw_never (ma depth TEST attivo): non scrive profondita', cosi' non
// litiga col pavimento, ma i personaggi davanti lo occludono comunque.
//
// NIENTE branch dinamici (step/smoothstep), niente texture, niente
// DEPTH_TEXTURE: il progetto gira sul renderer MOBILE, dove la depth texture
// non e' leggibile e i soft-particle/proximity-fade non sono disponibili.

uniform vec4 tint : source_color = vec4(0.62, 0.90, 1.0, 1.0);
// >1.0 spinge il colore fuori dal range LDR: acceso il glow nell'Environment,
// e' quello che fa "bruciare" il bordo.
// TARATO A SCHERMO (iso, arena reale, 2026-07-27): il pavimento dell'Arena
// Senza Fuoco NON è scuro come da assunto iniziale — è un kit in pietra chiara
// con ambient 1.1. Un additivo generoso ci si satura sopra all'istante e il
// campo diventa una lastra bianca opaca: esattamente il fallimento peggiore per
// una spell POSIZIONALE, perché nasconde i nemici che ci stanno dentro, cioè
// l'informazione per cui la spell esiste. Da qui i valori bassi: il campo deve
// TINGERE il pavimento, non sostituirlo.
uniform float energy : hint_range(0.0, 8.0) = 1.2;

group_uniforms Gameplay;
// Frazione di durata RIMANENTE (1 = appena lanciato, 0 = sta per sparire).
uniform float life : hint_range(0.0, 1.0) = 1.0;
// Apertura del campo allo spawn (0 → 1 in ~0.25 s): lo snap di ghiaccio.
uniform float open : hint_range(0.0, 1.0) = 1.0;
uniform float rim_width : hint_range(0.005, 0.30) = 0.055;

group_uniforms Aspetto;
uniform float crystal_count = 16.0;
uniform float drift_speed = 0.35;
uniform float breathe_speed = 1.6;
uniform float floor_opacity : hint_range(0.0, 1.0) = 0.055;
// Peso delle tre componenti sul pavimento. Tenuti bassi apposta: la SOMMA di
// queste tre e' cio' che decide se un nemico dentro al campo resta visibile.
uniform float fill_weight : hint_range(0.0, 1.0) = 0.09;
uniform float shard_weight : hint_range(0.0, 1.0) = 0.13;
// Il BORDO invece resta forte: e' il contratto di gameplay (dove arriva il
// raggio) ed e' una linea sottile, quindi non copre nulla.
uniform float rim_weight : hint_range(0.0, 2.0) = 0.85;

void fragment() {
	// UV di una PlaneMesh: 0..1 sui due assi → p in [-1,1], r = raggio normalizzato.
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);

	// Raggio corrente (animazione di apertura).
	float edge = max(open, 0.0001);
	float inside = 1.0 - smoothstep(edge - 0.02, edge, r);

	// 1. BORDO — il raggio d'effetto. Non svanisce mai finche' il campo vive.
	float rim = smoothstep(rim_width, 0.0, abs(r - edge));

	// 2. CLESSIDRA — il pieno si ritira verso il centro.
	float fill_r = edge * life;
	float fill = 1.0 - smoothstep(fill_r - 0.03, fill_r, r);
	// Fronte luminoso del ritiro: il ghiaccio che si scioglie all'indietro.
	float fill_edge = smoothstep(0.05, 0.0, abs(r - fill_r)) * smoothstep(0.0, 0.05, life);

	// 3. Cristalli radiali: raggi che si irradiano dal centro, sfalsati da una
	// sinusoide sul raggio cosi' non sembrano una ruota di bicicletta.
	float wobble = sin(r * 7.0 - TIME * drift_speed) * 0.06;
	float spokes = abs(fract(ang / TAU * crystal_count + wobble) * 2.0 - 1.0);
	float shard = smoothstep(0.72, 1.0, spokes) * (0.30 + 0.70 * r);

	// 4. Respiro lento: il campo e' vivo, non un decal incollato.
	float breathe = 0.85 + 0.15 * sin(TIME * breathe_speed);

	float a = inside * (floor_opacity + fill * fill_weight + shard * shard_weight);
	a += rim * rim_weight + fill_edge * 0.55;
	a *= breathe;
	a = clamp(a, 0.0, 1.0);

	ALBEDO = tint.rgb * energy;
	ALPHA = a;
}
