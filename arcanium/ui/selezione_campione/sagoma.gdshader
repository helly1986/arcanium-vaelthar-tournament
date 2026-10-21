shader_type spatial;
render_mode unshaded, cull_back;

// La SAGOMA di un campione non ancora forgiato (selezione_campione.gd): il
// corpo in ombra, con il bordo acceso nel colore della casata.

uniform vec4 colore : source_color = vec4(0.56, 0.75, 0.88, 1.0);
uniform float potenza = 2.4;

void fragment() {
	float bordo = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), potenza);
	ALBEDO = mix(vec3(0.015, 0.013, 0.018), colore.rgb, bordo);
}
