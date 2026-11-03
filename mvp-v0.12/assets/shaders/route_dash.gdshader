shader_type spatial;
// Ruta de flota animada (quad estirado entre origen y destino).
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float length_tiles = 10.0;
uniform float progress = 0.0;
void fragment() {
	float x = UV.x * length_tiles;
	float dash = step(0.5, fract(x * 0.9 - TIME * 1.8));
	float edge = smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	float done = UV.x < progress ? 0.25 : 1.0;
	ALBEDO = color.rgb * dash * edge * done * 1.4;
	ALPHA = 1.0;
}
