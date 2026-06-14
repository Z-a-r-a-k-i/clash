// Fog of war: samples the one-texel-per-tile R8 fog texture
// (0.5 discovered / 1.0 visible). The fog sprite uses filter_linear,
// so smoothstepping the interpolated value turns hard tile edges into
// soft gradients. Adapted from allin's spatial fog shader for the 2D
// renderer.
shader_type canvas_item;
render_mode blend_mix;

uniform float discovered_alpha: hint_range(0.0, 1.0) = 0.24;
uniform float max_alpha: hint_range(0.0, 1.0) = 0.9;
uniform vec3 fog_color: source_color = vec3(0.004, 0.008, 0.016);

void fragment() {
	float v = texture(TEXTURE, UV).r;
	float discovered = 1.0 - smoothstep(0.6, 0.95, v);
	float alpha = discovered * discovered_alpha;
	COLOR = vec4(fog_color, clamp(alpha, 0.0, max_alpha));
}
