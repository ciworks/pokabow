shader_type canvas_item;

uniform vec4 portrait_rect = vec4(0.16, 0.21, 0.68, 0.68);
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 portrait_uv = (UV - portrait_rect.xy) / portrait_rect.zw;
	float radius = length(portrait_uv - vec2(0.5));
	float edge = max(fwidth(radius), 0.001);
	COLOR = texture(TEXTURE, clamp(portrait_uv, vec2(0.0), vec2(1.0))) * tint;
	COLOR.a *= 1.0 - smoothstep(0.5 - edge, 0.5, radius);
}
