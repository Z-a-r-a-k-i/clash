// Fog of war: samples the one-texel-per-tile R8 fog texture
// (0.0 unexplored / 0.5 explored / 1.0 visible). The fog sprite uses
// filter_linear, so smoothstepping the interpolated value turns hard
// tile edges into soft gradients. Adapted from allin's spatial fog
// shader for the 2D renderer.
shader_type canvas_item;
render_mode blend_mix;

uniform float unexplored_alpha: hint_range(0.0, 1.0) = 0.82;
uniform float explored_alpha: hint_range(0.0, 1.0) = 0.38;
uniform float max_alpha: hint_range(0.0, 1.0) = 0.9;
uniform vec3 fog_color: source_color = vec3(0.004, 0.008, 0.016);

void fragment() {
	float v = texture(TEXTURE, UV).r;
	float unexplored = 1.0 - smoothstep(0.1, 0.45, v);
	float explored = (1.0 - smoothstep(0.6, 0.95, v)) * (1.0 - unexplored);
	float alpha = unexplored * unexplored_alpha + explored * explored_alpha;
	COLOR = vec4(fog_color, clamp(alpha, 0.0, max_alpha));
}
