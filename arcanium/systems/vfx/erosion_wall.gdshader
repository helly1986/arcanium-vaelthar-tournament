shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// MEMBRANA DEL MURO DI EROSIONE — la superficie del muro lasciato dal Rovescio
// Risonante (A2 del Senza Nome).
//
// PERCHÉ ESISTE: il muro finora era fatto SOLO di particelle che salgono. Le
// particelle dicono "qui succede qualcosa", non "qui c'è una parete". In
// isometrica, con la camera a ~52°, un velo di fumo verticale non ha un bordo:
// il player non sa dove finisce la zona che fa danno, e la mossa di A2 è
// CONTROLLO DELLO SPAZIO — se il confine non si legge, la mossa non esiste.
// La membrana dà quel confine: una superficie continua lungo la traccia della
// lama, con una BASE netta (dove sta la collisione) che si sfrangia salendo.
//
// PERCHÉ SI SFRANGIA IN ALTO E NON È UN MURO PIENO: un pannello opaco alto 2 m
// in isometrica nasconde tutto ciò che gli sta dietro — compreso il boss. La
// densità sta in basso, dove serve a marcare il terreno; salendo si disfa in
// brandelli così la leggibilità del campo non si perde.

uniform vec4 tint : source_color = vec4(0.80, 0.45, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.5;
// 1 = appena piantato, 0 = sta svanendo. Pilotato dal BossWall.
uniform float life : hint_range(0.0, 1.0) = 1.0;
// Quanto in fretta la membrana si dirada salendo.
// Verificato a schermo: a 2.0 la membrana moriva entro il primo terzo
// dell'altezza e si leggeva alta ~0.7 m, mentre il BoxShape3D che fa danno
// e' alto 2.0 — il muro PROMETTEVA MENO di quanto colpisse, e un player puo'
// legittimamente pensare di scavalcarlo. Ora sale quasi tutta l'altezza
// della hitbox, sfrangiandosi.
uniform float fray : hint_range(0.5, 6.0) = 1.25;
uniform float scroll_speed = 0.9;
uniform float band_scale = 5.0;
// Sfumatura ai due capi orizzontali del segmento: i tratti consecutivi devono
// fondersi, non mostrare la giuntura tra un quad e il successivo.
// Piccola: i quad dei tratti consecutivi si SOVRAPPONGONO gia' (vedi
// BossWall._spawn_membrane), quindi qui basta ammorbidire. A 0.12 la
// sfumatura era piu' larga della sovrapposizione e apriva buchi neri tra un
// tratto e l'altro lungo la curva della spadata.
uniform float seam_fade : hint_range(0.0, 0.5) = 0.05;

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);      // 0 = base a terra, 1 = cima
	float u = clamp(UV.x, 0.0, 1.0);

	// Densità verticale: piena alla base, si disfa salendo.
	float body = pow(1.0 - h, fray);

	// Filamenti che salgono. Due frequenze sfalsate: una sola darebbe righe
	// regolari da tapparella, due si battono e sembrano energia.
	float f1 = sin(u * band_scale * 6.283 + TIME * scroll_speed * 2.0 - h * 4.0);
	float f2 = sin(u * band_scale * 2.7 * 6.283 - TIME * scroll_speed + h * 6.0);
	float strands = 0.5 + 0.5 * (f1 * 0.6 + f2 * 0.4);

	// La sfrangiatura vera: salendo, la soglia mangia i filamenti più deboli,
	// così il bordo alto è frastagliato invece che tagliato dritto.
	float tatter = smoothstep(h * 0.85, h * 0.85 + 0.35, strands);

	// Giunture tra segmenti consecutivi.
	float seam = smoothstep(0.0, seam_fade, u) * smoothstep(0.0, seam_fade, 1.0 - u);

	// Riga incandescente al piede: è LÌ che sta la collisione, ed è l'unica
	// informazione del muro che deve restare leggibile sempre.
	float foot = smoothstep(0.06, 0.0, h) * 0.9;

	float a = (body * (0.25 + 0.55 * tatter) + foot) * seam * life;

	ALBEDO = tint.rgb * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
