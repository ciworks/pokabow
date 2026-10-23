class_name GameCommandDrawer
extends Control

## Presentation-only sliding command sheet. Buttons are wired by GameScreen.
signal opened_changed(opened: bool)

const SLIDE_SECONDS: float = 0.24
var is_open: bool = false
var _motion: Tween
@onready var panel: PanelContainer = %DrawerPanel
@onready var scrim: Button = %DrawerScrim


func _ready() -> void:
	%CloseMenuButton.pressed.connect(func() -> void: set_open(false))
	scrim.pressed.connect(func() -> void: set_open(false))
	resized.connect(_layout)
	%PotPanel.resized.connect(func() -> void: call_deferred("_layout"))
	_layout()


func open_settings() -> void:
	set_open(true)


func set_open(value: bool, animate: bool = true) -> void:
	var was_open: bool = is_open
	is_open = value
	if _motion != null:
		_motion.kill()
	scrim.visible = value
	panel.visible = true
	var destination: float = size.x - panel.size.x - 12.0 if value else size.x + 8.0
	if animate and is_inside_tree():
		_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_property(panel, "position:x", destination, SLIDE_SECONDS)
		if not value:
			_motion.tween_callback(panel.hide)
	else:
		panel.position.x = destination
		panel.visible = value
	if value:
		%CloseMenuButton.grab_focus()
	elif was_open:
		var menu_button := get_parent().get_node_or_null("Root/Column/HeaderTools/HeaderSpacer") as Button
		if menu_button != null:
			menu_button.grab_focus()
	opened_changed.emit(value)


func _layout() -> void:
	if panel == null or not is_inside_tree() or is_queued_for_deletion():
		return
	if _motion != null:
		_motion.kill()
	var pot: Control = get_node("%PotPanel") as Control
	var hud: Control = pot.get_parent() as Control
	var top: float = clampf(hud.get_global_rect().end.y - global_position.y + 12.0, 80.0, size.y * 0.4)
	panel.size = Vector2(minf(350.0, maxf(260.0, size.x * 0.7)), maxf(180.0, size.y - top - 16.0))
	panel.position = Vector2(size.x - panel.size.x - 12.0 if is_open else size.x + 8.0, top)
	panel.visible = is_open
	scrim.visible = is_open


func _unhandled_key_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
