from pathlib import Path
import re

path = Path('scenes/game/game_screen.tscn')
original = path.read_text(encoding='utf-8')
resources = original[:original.index('[sub_resource')]
if 'id="13_drawer"' not in resources:
    resources += '[ext_resource type="Script" path="res://scripts/presentation/game_command_drawer.gd" id="13_drawer"]\n\n'
if 'id="14_settings"' not in resources:
    resources += '[ext_resource type="Texture2D" path="res://assets/ui/settings.png" id="14_settings"]\n\n'
if 'id="22_background"' not in resources:
    resources += '[ext_resource type="Texture2D" path="res://assets/ui/default_background.png" id="22_background"]\n\n'
if 'id="23_board_deck"' not in resources:
    resources += '[ext_resource type="Texture2D" path="res://assets/ui/board_deck.png" id="23_board_deck"]\n\n'
if 'id="26_close"' not in resources:
    resources += '[ext_resource type="Texture2D" path="res://assets/ui/close.png" id="26_close"]\n\n'
if 'id="27_bottom_navigation"' not in resources:
    resources += '[ext_resource type="Script" path="res://scripts/presentation/game_bottom_navigation.gd" id="27_bottom_navigation"]\n\n'
if 'id="29_header_logo"' not in resources:
    resources += '[ext_resource type="Texture2D" path="res://assets/branding/pokabow-header-logo-v2.tres" id="29_header_logo"]\n\n'
blocks = re.split(r'(?=\[node )', original[original.index('[node '):])
nodes = {re.search(r'name="([^"]+)"', b)[1]: b for b in blocks if b.strip()}
parts = [resources]
parts.append('''[sub_resource type="StyleBoxFlat" id="AvatarTurnOutline"]
draw_center = false
corner_radius_top_left = 10
corner_radius_top_right = 10
corner_radius_bottom_right = 10
corner_radius_bottom_left = 10

''')
parts.append('[sub_resource type="StyleBoxEmpty" id="SettingsButtonEmpty"]\n\n')

def style(id, bg, border, radius=16, margin=14):
    parts.append(f'''[sub_resource type="StyleBoxFlat" id="{id}"]
bg_color = Color({bg})
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 2
border_color = Color({border})
corner_radius_top_left = {radius}
corner_radius_top_right = {radius}
corner_radius_bottom_left = {radius}
corner_radius_bottom_right = {radius}
content_margin_left = {margin}.0
content_margin_right = {margin}.0
content_margin_top = 10.0
content_margin_bottom = 10.0
shadow_color = Color(0, 0, 0, 0.28)
shadow_size = 5
shadow_offset = Vector2(0, 3)

''')

style('StyleBox_panel','0.07, 0.09, 0.11, 0.98','0.28, 0.33, 0.35, 1')
style('HumanPanel','0.38, 0.06, 0.08, 1','0.85, 0.21, 0.24, 1')
style('RivalPanel','0.035, 0.18, 0.33, 1','0.08, 0.52, 0.8, 1')
style('PotPanel','0.22, 0.13, 0.07, 1','0.64, 0.42, 0.2, 1')
style('RackPanel','0.19, 0.105, 0.06, 1','0.52, 0.32, 0.16, 1',20)
style('ButtonNormal','0.09, 0.13, 0.17, 1','0.22, 0.3, 0.37, 1',12)
style('ButtonHover','0.14, 0.21, 0.27, 1','0.45, 0.66, 0.77, 1',12)
style('ButtonPressed','0.04, 0.09, 0.12, 1','0.3, 0.75, 0.62, 1',12)
style('ButtonDisabled','0.09, 0.11, 0.13, 1','0.16, 0.2, 0.22, 1',12)
parts.append('''[sub_resource type="SystemFont" id="InterfaceFont"]
font_names = PackedStringArray("Bahnschrift", "Segoe UI", "DejaVu Sans")
font_weight = 600

[sub_resource type="Theme" id="InterfaceTheme"]
default_font = SubResource("InterfaceFont")
default_font_size = 18
Button/colors/font_color = Color(0.95, 0.97, 0.98, 1)
Button/colors/font_disabled_color = Color(0.42, 0.49, 0.54, 1)
Button/styles/normal = SubResource("ButtonNormal")
Button/styles/hover = SubResource("ButtonHover")
Button/styles/pressed = SubResource("ButtonPressed")
Button/styles/disabled = SubResource("ButtonDisabled")
Button/styles/focus = SubResource("ButtonHover")
OptionButton/styles/normal = SubResource("ButtonNormal")
OptionButton/styles/hover = SubResource("ButtonHover")
OptionButton/styles/pressed = SubResource("ButtonPressed")
OptionButton/styles/disabled = SubResource("ButtonDisabled")

''')

def node(name, type, parent=None, props='', unique=False):
    head = f'[node name="{name}" type="{type}"'
    if parent is not None: head += f' parent="{parent}"'
    parts.append(head + ']\n' + ('unique_name_in_owner = true\n' if unique else '') + props.strip() + '\n\n')

full = 'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2'
container = 'layout_mode = 2\nmouse_filter = 2'
node('GameScreen','Control', props=full+'\nscript = ExtResource("1_screen")\ntheme = SubResource("InterfaceTheme")')
parts.append(nodes['Background'])
node('Root','MarginContainer','.',full+'\noffset_bottom = -76.0\ntheme_override_constants/margin_left = 16\ntheme_override_constants/margin_right = 16\ntheme_override_constants/margin_top = 16\ntheme_override_constants/margin_bottom = 16')
node('Column','VBoxContainer','Root',container+'\ntheme_override_constants/separation = 12')
for block in blocks:
    if 'name="HeaderTools"' in block or 'parent="Root/Column/HeaderTools' in block:
        parts.append(block)
node('Hud','HBoxContainer','Root/Column',container+'\ntheme_override_constants/separation = 10')

def label(name,parent,text,size=18,extra='',unique=False):
    node(name,'Label',parent,container+f'\ntext = "{text}"\ntheme_override_font_sizes/font_size = {size}\n'+extra,unique)

def score(name,prefix,title,style_id):
    p='Root/Column/Hud/'+name
    node(name,'PanelContainer','Root/Column/Hud',container+f'\nsize_flags_horizontal = 3\nsize_flags_vertical = 4\ncustom_minimum_size = Vector2(80, 94)\ntheme_override_styles/panel = SubResource("{style_id}")',True)
    node(prefix+'ScoreBox','VBoxContainer',p,container+'\nalignment = 1\ntheme_override_constants/separation = 0')
    label(prefix+'ScoreTitle',p+'/'+prefix+'ScoreBox',title,16,'horizontal_alignment = 1\ntext_overrun_behavior = 3',prefix=='Human')
    label(prefix+'ScoreValue',p+'/'+prefix+'ScoreBox','0',36,'horizontal_alignment = 1',True)

# Keep the authored sprite composition and its score/name bindings intact.
for block in blocks:
    if 'name="HumanScorePanel"' in block or 'parent="Root/Column/Hud/HumanScorePanel' in block:
        parts.append(block)
for block in blocks:
    if 'name="PotPanel"' in block or 'parent="Root/Column/Hud/PotPanel' in block:
        parts.append(block)
for block in blocks:
    if 'name="AiScorePanel"' in block or 'parent="Root/Column/Hud/AiScorePanel' in block:
        parts.append(block)
node('Body','HBoxContainer','Root/Column',container+'\nsize_flags_vertical = 3')
node('BoardViewport','MarginContainer','Root/Column/Body',container+'\nsize_flags_horizontal = 3\nsize_flags_vertical = 3')
for b in blocks:
    if 'name="BoardView"' in b or 'parent="Root/Column/Body/BoardViewport/BoardView' in b:
        parts.append(b)
for block in blocks:
    if 'name="DeckBar"' in block or 'parent="Root/Column/DeckBar' in block:
        parts.append(block)
if not any('name="DeckBar"' in block for block in blocks):
    node('DeckBar','HBoxContainer','Root/Column',container+'\nalignment = 1',True)
if not any('name="DeckPanel"' in block for block in blocks):
	node('DeckPanel','TextureRect','Root/Column/DeckBar',container+'\ntexture = ExtResource("23_board_deck")\nexpand_mode = 1\nstretch_mode = 5',True)
	node('RackColumn','VBoxContainer','Root/Column/DeckBar/DeckPanel','''layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 38.0
offset_top = 14.0
offset_right = -38.0
offset_bottom = -22.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme_override_constants/separation = 0''')
	rack='Root/Column/DeckBar/DeckPanel/RackColumn'
	node('DeckRow','HBoxContainer',rack,container+'\nsize_flags_vertical = 3')
	node('DeckView','Control',rack+'/DeckRow',container.replace('mouse_filter = 2', 'mouse_filter = 0')+'\nsize_flags_vertical = 3\nsize_flags_horizontal = 3\nscript = ExtResource("10_deck")',True)

node('BottomNavigation','PanelContainer','.', 'layout_mode = 1\nanchors_preset = 12\nanchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -76.0\ngrow_horizontal = 2\ngrow_vertical = 0\nmouse_filter = 2\nscript = ExtResource("27_bottom_navigation")',True)
node('CommandDrawer','Control','.',full+'\nclip_contents = true\nscript = ExtResource("13_drawer")',True)
node('DrawerScrim','Button','CommandDrawer',full.replace('mouse_filter = 2','mouse_filter = 0')+'\nvisible = false\nflat = true\nfocus_mode = 0\nmodulate = Color(0, 0, 0, 0.3)',True)
node('DrawerPanel','PanelContainer','CommandDrawer','visible = false\nlayout_mode = 0\nmouse_filter = 0\ntheme_override_styles/panel = SubResource("StyleBox_panel")',True)
node('DrawerColumn','VBoxContainer','CommandDrawer/DrawerPanel',container+'\ntheme_override_constants/separation = 10')
drawer='CommandDrawer/DrawerPanel/DrawerColumn'
node('DrawerHeader','HBoxContainer',drawer,container)
label('TurnIndicator',drawer+'/DrawerHeader','Your turn',20,'size_flags_horizontal = 3\nvertical_alignment = 1',True)
node('CloseMenuButton','Button',drawer+'/DrawerHeader','layout_mode = 2\ncustom_minimum_size = Vector2(44, 44)\ntooltip_text = "Close turn actions"\ntheme_override_colors/icon_pressed_color = Color(0.75, 0.75, 0.75, 1)\ntheme_override_styles/normal = SubResource("SettingsButtonEmpty")\ntheme_override_styles/hover = SubResource("SettingsButtonEmpty")\ntheme_override_styles/pressed = SubResource("SettingsButtonEmpty")\ntheme_override_styles/disabled = SubResource("SettingsButtonEmpty")\nicon = ExtResource("26_close")\nicon_alignment = 1\nexpand_icon = true',True)
node('CommandScroll','ScrollContainer',drawer,'layout_mode = 2\nsize_flags_vertical = 3\nhorizontal_scroll_mode = 0')
node('Commands','VBoxContainer',drawer+'/CommandScroll',container+'\nsize_flags_horizontal = 3\ntheme_override_constants/separation = 10')
commands=drawer+'/CommandScroll/Commands'

for name,text in [('SwapConfirmButton','Return selected tiles'),('SwapCancelButton','Keep tiles')]:
    node(name,'Button',commands,'visible = false\nlayout_mode = 2\ncustom_minimum_size = Vector2(0, 48)\ntext = "'+text+'"',True)
node('PreviewPanel','PanelContainer',commands,container+'\ntheme_override_styles/panel = SubResource("StyleBox_panel")')
node('PreviewColumn','VBoxContainer',commands+'/PreviewPanel',container+'\ntheme_override_constants/separation = 8')
preview=commands+'/PreviewPanel/PreviewColumn'
label('PreviewTitle',preview,'Move preview',19)
node('Rule','HSeparator',preview,container)
for name,title in [('PokerPreview','Hand score'),('EdgePreview','Edge matches'),('ClusterPreview','Cluster bonus'),('TotalPreview','Total preview')]:
    node(name+'Row','HBoxContainer',preview,container)
    label(name+'Title',preview+'/'+name+'Row',title,16,'size_flags_horizontal = 3')
    label(name,preview+'/'+name+'Row','—',24 if name=='TotalPreview' else 17,'theme_override_colors/font_color = Color(0.22, 0.84, 0.59, 1)',True)
label('StatusLabel',commands,'Drag tiles onto the board to build a hand.',14,'autowrap_mode = 2\ntheme_override_colors/font_color = Color(0.66, 0.74, 0.77, 1)',True)
node('MatchOptions','VBoxContainer',commands,container+'\ntheme_override_constants/separation = 8',True)
label('DifficultyTitle',commands+'/MatchOptions','Rival difficulty',14)
node('DifficultyPicker','OptionButton',commands+'/MatchOptions','layout_mode = 2\ncustom_minimum_size = Vector2(0, 48)',True)
for name,text in [('RestartButton','New match'),('MenuHubButton','Back to hub')]:
    node(name,'Button',commands+'/MatchOptions','layout_mode = 2\ncustom_minimum_size = Vector2(0, 48)\ntext = "'+text+'"',True)
tail=original[original.index('[node name="BoardInputController"'):]
tail=tail.replace('Vector2(520, 0)','Vector2(280, 0)')
parts.append(tail)
path.write_text(''.join(parts),encoding='utf-8')
