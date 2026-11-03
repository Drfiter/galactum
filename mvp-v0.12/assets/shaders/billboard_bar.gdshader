shader_type spatial;
// Barra de vida flotante (billboard) para entidades 3D.
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;
uniform float fill = 1.0;
uniform vec4 fill_color : source_color = vec4(0.25, 0.9, 0.45, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.15) + step(0.85, uv.y);
	vec3 col = uv.x < fill ? fill_color.rgb : vec3(0.08, 0.06, 0.12);
	col = mix(col, vec3(0.02, 0.02, 0.05), clamp(border, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = 0.95;
}
