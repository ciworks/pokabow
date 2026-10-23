shader_type canvas_item;

void fragment() {
	float radius = length(UV - vec2(0.5));
	COLOR.a *= 1.0 - smoothstep(0.49, 0.5, radius);
}
