shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.05, 0.55);
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - smoothstep(0.2, 1.0, r));
}
