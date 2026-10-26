class_name StoreScreen
extends Control
## Gem shop. Ad rewards come from verified server settlement; packs are previews.

signal home_requested
signal achievements_requested
signal tournaments_requested
signal ad_requested

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const GEM: Texture2D = preload("res://assets/ui/modern_tabletop/store_gem.svg")
const PACKS: Array[Dictionary] = [
	{"name": "Pocket gems", "gems": 100, "price": "£0.99", "art": 1},
	{"name": "Handful of gems", "gems": 340, "price": "£2.99", "art": 2},
	{"name": "Treasure pile", "gems": 800, "price": "£5.99", "art": 3},
	{"name": "Gem vault", "gems": 1800, "price": "£9.99", "art": 3, "featured": true},
]

var _margin: MarginContainer
var _column: VBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _nav: HBoxContainer
var _balance: Label
var _mini_balance: Label
var _balance_caption: Label
var _balance_art: StoreGemCluster
var _daily_art: StoreGemCluster
var _notice: PanelContainer
var _notice_label: Label
var _notice_timer: Timer
var _back: Button
var _ad_button: Button
var _ad_status: Label
var _pack_buttons: Array[Button] = []
var _pack_panels: Array[PanelContainer] = []
var _pack_arts: Array[StoreGemCluster] = []
var _section_labels: Array[Label] = []


func _ready() -> void:
	theme = T.create()
	_build()
	resized.connect(_fit)
	_fit()


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = T.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_margin = MarginContainer.new()
	_margin.name = "PageMargin"
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column = VBoxContainer.new()
	_column.name = "Page"
	_margin.add_child(_column)
	_column.add_theme_constant_override("separation", 12)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	_column.add_child(header)
	_back = _button("", _go_home, "quiet")
	_back.name = "BackButton"
	T.style_back_button(_back)
	_back.tooltip_text = "Back to Home"
	header.add_child(_back)
	var heading := _label("Gem shop", 38, T.BOLD, T.ink())
	heading.name = "Heading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)
	var mini_gem := _image(GEM, Vector2(30, 28))
	header.add_child(mini_gem)
	_mini_balance = _label("—", 24, T.SEMIBOLD, T.ink())
	_mini_balance.name = "HeaderBalance"
	_mini_balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	_mini_balance.custom_minimum_size.x = 80
	_mini_balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_mini_balance)

	_scroll = ScrollContainer.new()
	_scroll.name = "OffersScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Offers"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	_build_balance_card()
	_add_section("A little sparkle, on us", "One optional reward every 24 hours")
	_build_daily_offer()
	_add_section("Gem packs", "A boost for your next chapter")
	for pack: Dictionary in PACKS:
		_build_pack(pack)
	var disclosure := _label("Gem packs are previews; purchases are not available yet.", 16, T.REGULAR, T.muted())
	disclosure.name = "OfferDisclosure"
	disclosure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(disclosure)

	_nav = HBoxContainer.new()
	_nav.name = "BottomNavigation"
	_nav.add_theme_constant_override("separation", 8)
	_column.add_child(_nav)
	_add_nav("Home", _go_home, false)
	_add_nav("Achievements", _go_achievements, false)
	_add_nav("Tournaments", func() -> void: tournaments_requested.emit(), false)
	_build_notice()


func _build_balance_card() -> void:
	var card := PanelContainer.new()
	card.name = "BalanceCard"
	card.add_theme_stylebox_override("panel", T.panel(Color("#173D42"), 24, 12))
	_body.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	copy.add_child(_label("YOUR BALANCE", 19, T.MEDIUM, Color("#DCEBE3")))
	var balance_row := HBoxContainer.new()
	balance_row.add_theme_constant_override("separation", 8)
	copy.add_child(balance_row)
	_balance = _label("—", 54, T.BOLD, Color("#F6F2E9"))
	_balance.name = "GemBalance"
	_balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	_balance.custom_minimum_size.x = 130
	balance_row.add_child(_balance)
	var units := _label("gems", 24, T.MEDIUM, Color("#DCEBE3"))
	units.autowrap_mode = TextServer.AUTOWRAP_OFF
	units.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	balance_row.add_child(units)
	_balance_caption = _label("Your confirmed Gem balance appears here.", 16, T.REGULAR, Color("#BFD0D0"))
	copy.add_child(_balance_caption)
	_balance_art = StoreGemCluster.new()
	_balance_art.name = "BalanceGems"
	_balance_art.gem_count = 2
	_balance_art.custom_minimum_size = Vector2(100, 100)
	row.add_child(_balance_art)


func _add_section(title: String, subtitle: String) -> void:
	var section := VBoxContainer.new()
	section.name = "Section" + title.replace(" ", "")
	section.add_theme_constant_override("separation", 0)
	_body.add_child(section)
	var heading := _label(title, 26, T.SEMIBOLD, T.ink())
	section.add_child(heading)
	var detail := _label(subtitle, 20, T.REGULAR, T.muted())
	section.add_child(detail)
	_section_labels.append(heading)
	_section_labels.append(detail)


func _build_daily_offer() -> void:
	var card := _offer_panel("DailyOffer", T.sage(), T.border())
	_body.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	_daily_art = StoreGemCluster.new()
	_daily_art.name = "DailyGems"
	_daily_art.gem_count = 3
	_daily_art.backdrop = Color("#C7DCD3") if not T.is_dark_mode() else Color("#2D4A50")
	_daily_art.custom_minimum_size = Vector2(84, 84)
	row.add_child(_daily_art)
	var copy := VBoxContainer.new()
	copy.name = "DailyCopy"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(_label("Daily gem gift", 21, T.SEMIBOLD, T.ink()))
	copy.add_child(_label("20 gems", 31, T.BOLD, T.ink()))
	_ad_status = _label("Checking availability…", 16, T.REGULAR, T.muted())
	_ad_status.name = "DailyAdStatus"
	copy.add_child(_ad_status)
	_ad_button = _button("Watch ad", _on_ad_pressed, "primary")
	_ad_button.name = "WatchAdButton"
	_ad_button.disabled = true
	_ad_button.tooltip_text = "Watch one rewarded advert for 20 Gems every 24 hours"
	_ad_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ad_button)


func _build_pack(pack: Dictionary) -> void:
	var featured: bool = bool(pack.get("featured", false))
	var fill: Color = (Color("#FFF8E9") if featured else Color.WHITE) if not T.is_dark_mode() else T.canvas_alt()
	var border: Color = T.honey() if featured else T.border()
	var card := _offer_panel(String(pack["name"]).replace(" ", "") + "Card", fill, border)
	_body.add_child(card)
	_pack_panels.append(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var art := StoreGemCluster.new()
	art.name = "PackGems"
	art.gem_count = int(pack["art"])
	art.backdrop = Color("#F8E4AD") if featured else T.sage()
	art.custom_minimum_size = Vector2(72, 72)
	row.add_child(art)
	_pack_arts.append(art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(_label(String(pack["name"]), 21, T.SEMIBOLD, T.ink()))
	copy.add_child(_label(_format_gems(int(pack["gems"])), 34, T.BOLD, T.ink()))
	var action := VBoxContainer.new()
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(action)
	if featured:
		var badge := _label("BEST VALUE", 14, T.SEMIBOLD, T.honey() if T.is_dark_mode() else T.on_primary())
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action.add_child(badge)
	var price := _button(String(pack["price"]), _on_pack_pressed.bind(String(pack["name"])), "primary" if featured else "price")
	price.name = "PriceButton"
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.tooltip_text = "%s: %s gems for %s (preview)" % [pack["name"], _format_gems(int(pack["gems"])), pack["price"]]
	action.add_child(price)
	_pack_buttons.append(price)


func _offer_panel(node_name: String, fill: Color, border: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	var style := T.panel(fill, 20, 8)
	style.set_border_width_all(2 if border == T.honey() else 1)
	style.border_color = border
	card.add_theme_stylebox_override("panel", style)
	return card


func _add_nav(caption: String, action: Callable, selected: bool) -> void:
	var button := _button("", action, "selected" if selected else "quiet")
	button.name = caption + "Button"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = caption + (" — current page" if selected else "")
	_nav.add_child(button)
	var contents := VBoxContainer.new()
	contents.name = "Contents"
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(contents)
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.offset_top = 7
	contents.offset_bottom = -7
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", 3)
	var icon := _image(T.icon_texture(caption.to_lower()), Vector2(24, 24))
	icon.name = "Icon"
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	contents.add_child(icon)
	var label := _label(caption, 20, T.SEMIBOLD if selected else T.MEDIUM, T.ink() if selected else T.muted())
	label.name = "Caption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(label)


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.name = "Notice"
	_notice.visible = false
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_theme_stylebox_override("panel", T.panel(T.ink(), 18, 16))
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_notice.offset_left = -155
	_notice.offset_right = 155
	_notice.offset_top = -36
	_notice.offset_bottom = 36
	_notice_label = _label("", 18, T.MEDIUM, T.canvas())
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.add_child(_notice_label)
	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = 2.8
	_notice_timer.timeout.connect(func() -> void: _notice.hide())
	add_child(_notice_timer)


func _label(value: String, font_size: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(value: String, action: Callable, kind: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 19)
	T.style_button(button, "selected" if kind == "price" else kind)
	if kind == "price":
		var fill := Color("#173D42") if not T.is_dark_mode() else Color("#2D4A50")
		for state: String in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, T.panel(fill.lightened(0.08) if state == "hover" else fill, 14, 8))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("#F6F2E9"))
	button.pressed.connect(action)
	return button


func _image(texture: Texture2D, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _fit() -> void:
	if not is_node_ready():
		return
	var factor: float = clampf(size.x / 540.0, 0.66, 1.0)
	var side: int = maxi(16, roundi(24 * factor))
	var top: int = maxi(16, roundi(20 * factor))
	var bottom: int = maxi(16, roundi(24 * factor))
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0 and safe.has_area():
			var ratio: Vector2 = size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	_column.add_theme_constant_override("separation", maxi(8, roundi(12 * factor)))
	_body.add_theme_constant_override("separation", maxi(9, roundi(12 * factor)))
	_ad_button.custom_minimum_size = Vector2(roundi(120 * factor), maxi(48, roundi(60 * factor)))
	_ad_button.add_theme_font_size_override("font_size", maxi(14, roundi(20 * factor)))
	for button: Button in _pack_buttons:
		button.custom_minimum_size = Vector2(maxi(72, roundi(102 * factor)), maxi(48, roundi(58 * factor)))
		button.add_theme_font_size_override("font_size", maxi(15, roundi(22 * factor)))
	for art: StoreGemCluster in _pack_arts:
		art.custom_minimum_size = Vector2(62, 62) if size.x < 410 else Vector2(72, 72)
	for button: Button in _nav.get_children():
		button.custom_minimum_size.y = maxi(64, roundi(80 * factor))
		(button.get_node("Contents/Caption") as Label).add_theme_font_size_override("font_size", maxi(13, roundi(20 * factor)))
	_back.custom_minimum_size = T.BACK_BUTTON_SIZE
	_notice.offset_left = -minf(160, size.x / 2.0 - 20)
	_notice.offset_right = minf(160, size.x / 2.0 - 20)
	if size.x < 410:
		(_column.get_node("Header/Heading") as Label).add_theme_font_size_override("font_size", 28)
		_balance.add_theme_font_size_override("font_size", 42)
		_balance.custom_minimum_size.x = 110
		_balance_art.custom_minimum_size = Vector2(74, 80)
		_daily_art.custom_minimum_size = Vector2(64, 68)
		for label: Label in _section_labels:
			label.add_theme_font_size_override("font_size", 18 if label == _section_labels[0] or label == _section_labels[2] else 14)
	else:
		(_column.get_node("Header/Heading") as Label).add_theme_font_size_override("font_size", 38)
		_balance.add_theme_font_size_override("font_size", 54)
		_balance.custom_minimum_size.x = 150
		_balance_art.custom_minimum_size = Vector2(100, 100)
		_daily_art.custom_minimum_size = Vector2(84, 84)
		for index: int in range(_section_labels.size()):
			_section_labels[index].add_theme_font_size_override("font_size", 26 if index % 2 == 0 else 20)


func set_gem_wallet(data: Dictionary) -> void:
	var balance: int = maxi(0, int(data.get("balance", 0)))
	var value: String = _format_gems(balance)
	_balance.text = value
	_mini_balance.text = value
	_balance_caption.text = "Earn in matches" if size.x < 410 else "Earn in matches. Keep your table growing."


func set_gem_wallet_error(_message: String) -> void:
	if _balance.text == "—":
		_balance_caption.text = "Balance unavailable. Try again when connected."


func set_rewarded_ad_status(data: Dictionary) -> void:
	var enabled: bool = bool(data.get("enabled", false))
	var available: bool = bool(data.get("available", false))
	_ad_button.disabled = not enabled or not available
	if not enabled:
		_ad_status.text = "Rewarded ads are unavailable right now."
	elif available:
		_ad_status.text = "One ad available · 20 Gems"
	else:
		var next: Variant = data.get("nextAvailableAtUnix")
		if next == null:
			_ad_status.text = "Today's ad reward has been used."
		else:
			var local := Time.get_datetime_dict_from_unix_time(int(next))
			_ad_status.text = "Used today · available at %02d:%02d UTC" % [local.hour, local.minute]


func set_ad_progress(message: String) -> void:
	_ad_button.disabled = true
	_ad_status.text = message


static func _format_gems(value: int) -> String:
	var digits: String = str(value)
	var result: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits.substr(index, 1)
	return result


func _on_ad_pressed() -> void:
	set_ad_progress("Preparing your ad…")
	ad_requested.emit()


func _on_pack_pressed(_pack_name: String) -> void:
	show_notice("Gem purchases are coming soon.")


func show_notice(message: String) -> void:
	_notice_label.text = message
	_notice.show()
	_notice_timer.start()


func current_notice() -> String:
	return _notice_label.text


func _go_home() -> void:
	home_requested.emit()


func _go_achievements() -> void:
	achievements_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		_go_home()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_go_home()
