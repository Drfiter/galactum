shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 c1 : source_color = vec4(0.70, 0.45, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(0.25, 0.80, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 4.0 - r * 10.0 + TIME * 2.5) * 0.5 + 0.5;
	float ring = (1.0 - smoothstep(0.75, 1.0, r)) * smoothstep(0.12, 0.35, r);
	vec3 col = mix(c1.rgb, c2.rgb, swirl) * ring * (0.6 + 0.6 * swirl);
	col += vec3(1.0, 0.95, 1.0) * (1.0 - smoothstep(0.0, 0.25, r)) * (0.8 + 0.2 * sin(TIME * 3.0));
	ALBEDO = col;
	ALPHA = 1.0;
}
