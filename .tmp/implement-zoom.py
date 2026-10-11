from pathlib import Path
p=Path('scenes/game/game_screen.tscn');s=p.read_text(encoding='utf-8');s=s.replace('[node name="LogoBalanceSpace" type="Control" parent="Root/Column/HeaderTools"]\ncustom_minimum_size = Vector2(48, 0)\nlayout_mode = 2\nmouse_filter = 2','''[node name="ZoomControls" type="HBoxContainer" parent="Root/Column/HeaderTools"]
custom_minimum_size = Vector2(104, 48)
layout_mode = 2
theme_override_constants/separation = 8

[node name="ZoomOutButton" type="Button" parent="Root/Column/HeaderTools/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(48, 48)
layout_mode = 2
text = "−"
tooltip_text = "Zoom out: full board"

[node name="ZoomInButton" type="Button" parent="Root/Column/HeaderTools/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(48, 48)
layout_mode = 2
text = "+"
tooltip_text = "Zoom in: six columns"''');s=s.replace('[node name="OpenMenuButton" type="Button" parent="Root/Column/HeaderTools"', '''[node name="SettingsSlot" type="HBoxContainer" parent="Root/Column/HeaderTools"]
custom_minimum_size = Vector2(104, 48)
layout_mode = 2
alignment = 2
mouse_filter = 2

[node name="OpenMenuButton" type="Button" parent="Root/Column/HeaderTools/SettingsSlot"''');base='Root/Column/Body/BoardViewport/BoardView'
for name in ['TileLayer','HighlightLayer','PreviewLayer','ClusterDisplayLayer','ScoreRevealLayer','EffectsLayer','DebugOverlay']:
 s=s.replace(f'[node name="{name}" type="Control" parent="{base}"',f'[node name="{name}" type="Control" parent="{base}/BoardCanvas"')
pos=s.index('[node name="TileLayer"');s=s[:pos]+f'[node name="BoardCanvas" type="Control" parent="{base}"]\nclip_contents = true\nlayout_mode = 0\nmouse_filter = 2\n\n'+s[pos:];p.write_text(s,encoding='utf-8')
p=Path('scripts/presentation/board_view.gd');s=p.read_text(encoding='utf-8').replace('tile.cell == cell','tile.get_cell() == cell');p.write_text(s,encoding='utf-8')
p=Path('tests/integration/test_game_screen.gd');s=p.read_text(encoding='utf-8');
for name in ['TileLayer','PreviewLayer','HighlightLayer','ScoreRevealLayer','EffectsLayer']:s=s.replace('BoardView/'+name,'BoardView/BoardCanvas/'+name)
p.write_text(s,encoding='utf-8')
p=Path('scripts/presentation/game_screen.gd');s=p.read_text(encoding='utf-8').replace('var board_width: float = board_view.global_board_rect().size.x','var board_width: float = board_view.global_visible_rect().size.x');s=s.replace('func _setup_buttons() -> void:', '''func _set_board_zoom(close: bool) -> void:
	board_input.reset()
	_end_drag()
	_clear_staged_drag()
	board_view.set_close_view(close)


func _refresh_zoom_buttons() -> void:
	(get_node("%ZoomInButton") as Button).disabled = board_view.zoom == BoardView.CLOSE_ZOOM
	(get_node("%ZoomOutButton") as Button).disabled = board_view.zoom == BoardView.OVERVIEW_ZOOM


func _setup_buttons() -> void:
	_connect_button(get_node("%ZoomInButton") as Button, _set_board_zoom.bind(true))
	_connect_button(get_node("%ZoomOutButton") as Button, _set_board_zoom.bind(false))
	_connect_once(board_view.zoom_changed, _refresh_zoom_buttons)
	_refresh_zoom_buttons()''');s=s.replace('\treturn floating_scores.get_global_transform().affine_inverse() * cell_global','\tvar visible: Rect2 = board_view.global_visible_rect().grow(-24.0)\n\tcell_global = cell_global.clamp(visible.position, visible.end)\n\treturn floating_scores.get_global_transform().affine_inverse() * cell_global');p.write_text(s,encoding='utf-8')
p=Path('tools/build_game_layout.py');s=p.read_text(encoding='utf-8');start=s.index("node('HeaderTools'");end=s.index("node('Hud'",start);s=s[:start]+'''for block in blocks:
    if 'name="HeaderTools"' in block or 'parent="Root/Column/HeaderTools' in block:
        parts.append(block)
'''+s[end:];s=s.replace('parent="Root/Column/Body/BoardViewport/BoardView"','parent="Root/Column/Body/BoardViewport/BoardView');p.write_text(s,encoding='utf-8')
p=Path('tools/preview_header_logo.gd');s=p.read_text(encoding='utf-8').replace('board_view.global_board_rect()','board_view.global_visible_rect()').replace('res://header-logo-%d','res://board-zoom-%d');p.write_text(s,encoding='utf-8')