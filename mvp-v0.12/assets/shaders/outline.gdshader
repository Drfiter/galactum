shader_type spatial;
// Contorno cartoon por casco invertido (segunda pasada del material toon).
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 outline_color : source_color = vec4(0.03, 0.04, 0.10, 1.0);
uniform float width = 0.035;

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
