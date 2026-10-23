shader_type canvas_item;
uniform vec2 view_size = vec2(1.0);
varying vec2 local_uv;
void vertex() {
    local_uv = VERTEX / view_size;
}
void fragment() {
    float radius = length(local_uv - vec2(0.5));
    float edge = max(fwidth(radius), 0.001);
    COLOR.a *= 1.0 - smoothstep(0.47 - edge, 0.47, radius);
}
