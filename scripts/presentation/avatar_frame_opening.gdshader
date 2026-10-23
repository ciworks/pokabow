shader_type canvas_item;

// Atlas UVs describe the original oval; the frame control maps it to a circle.
uniform vec4 opening_rect;

void fragment() {
	vec2 opening_uv = (UV - opening_rect.xy) / opening_rect.zw;
	float radius = length(opening_uv - vec2(0.5));
	float edge = max(fwidth(radius), 0.001);
	COLOR.a *= smoothstep(0.5 - edge, 0.5, radius);
}
