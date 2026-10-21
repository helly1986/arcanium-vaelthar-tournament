shader_type canvas_item;

// Il ritratto del campione ritagliato a cerchio, con il bordo sfumato: sta
// dentro l'anello del medaglione (medaglione_campione.gd). `zoom` e `centro`
// scelgono il pezzo del volto da un'illustrazione a mezzo busto.

uniform float zoom = 1.0;
uniform vec2 centro = vec2(0.5, 0.42);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	vec2 uv = centro + d / zoom;
	vec4 c = texture(TEXTURE, uv);
	// Un'ombra verso il bordo: il volto affiora dal fondo del medaglione.
	c.rgb *= mix(1.0, 0.55, smoothstep(0.30, 0.5, r));
	c.a *= 1.0 - smoothstep(0.47, 0.5, r);
	COLOR = c;
}
