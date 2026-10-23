shader_type canvas_item;
render_mode unshaded;

uniform float scroll_phase = 0.0;
varying vec2 panel_position;

void vertex() {
	panel_position = VERTEX;
}

void fragment() {
	// Inverse 45-degree rotation; 200px reference squares become 100px squares.
	vec2 grid = vec2(panel_position.x + panel_position.y,
		-panel_position.x + panel_position.y) * 0.70710678118 / 100.0;
	grid.x -= scroll_phase;
	vec2 cell = floor(grid);
	vec2 within_cell = fract(grid);
	// Rebuild the reference's shifted suit rows from its first four squares.
	// The source has only three rows, so repeating the whole sheet would seam.
	float suit = mod(cell.x - cell.y, 4.0);
	vec2 source_pixel = vec2(suit * 200.0, 0.0) +
		clamp(within_cell * 200.0, vec2(0.5), vec2(199.5));
	COLOR = texture(TEXTURE, source_pixel * TEXTURE_PIXEL_SIZE);
}
