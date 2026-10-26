class_name GemHistoryScreen
extends Control
## Read-only account wallet. Every row comes from a confirmed server transaction.

signal back_requested
signal shop_requested

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const GEM: Texture2D = preload("res://assets/ui/modern_tabletop/store_gem.svg")

var _margin: MarginContainer
var _scroll: ScrollContainer
var _history: VBoxContainer
var _balance: Label
var _status: Label
var _count: Label


func _ready() -> void:
	theme = T.create()
	_build()
	resized.connect(_fit)
	_fit()


func _build() -> void:
	var background := ColorRect.new()
	background.color = T.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)
	var back := Button.new()
	back.name = "BackButton"
	back.tooltip_text = "Back to Home"
	T.style_back_button(back)
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
	var heading := _label("Gems", 38, T.BOLD, T.ink())
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)

	_scroll = ScrollContainer.new()
	_scroll.name = "HistoryScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	page.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "HistoryBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_scroll.add_child(body)

	var balance_card := PanelContainer.new()
	balance_card.name = "BalanceCard"
	balance_card.add_theme_stylebox_override("panel", T.panel(Color("#173D42"), 24, 20))
	body.add_child(balance_card)
	var balance_row := HBoxContainer.new()
	balance_row.add_theme_constant_override("separation", 12)
	balance_card.add_child(balance_row)
	var balance_copy := VBoxContainer.new()
	balance_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balance_row.add_child(balance_copy)
	balance_copy.add_child(_label("CONFIRMED BALANCE", 17, T.MEDIUM, Color("#DCEBE3")))
	_balance = _label("—", 48, T.BOLD, Color("#F6F2E9"))
	_balance.name = "GemBalance"
	balance_copy.add_child(_balance)
	balance_copy.add_child(_label("gems in your account", 17, T.REGULAR, Color("#DCEBE3")))
	var gem := TextureRect.new()
	gem.texture = GEM
	gem.custom_minimum_size = Vector2(72, 72)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance_row.add_child(gem)

	var title := _label("Gem history", 28, T.SEMIBOLD, T.ink())
	body.add_child(title)
	var intro := _label("Confirmed gems from games appear here. Adverts and purchases will appear when available.", 18, T.REGULAR, T.muted())
	body.add_child(intro)
	_status = _label("Loading your Gem history...", 18, T.REGULAR, T.muted())
	_status.name = "HistoryStatus"
	body.add_child(_status)
	_history = VBoxContainer.new()
	_history.name = "Transactions"
	_history.add_theme_constant_override("separation", 10)
	body.add_child(_history)
	_count = _label("", 16, T.REGULAR, T.muted())
	_count.name = "HistoryCount"
	body.add_child(_count)
	var shop := Button.new()
	shop.name = "ShopButton"
	shop.text = "Visit Gem shop"
	shop.custom_minimum_size.y = 52
	T.style_button(shop, "primary")
	shop.pressed.connect(func() -> void: shop_requested.emit())
	page.add_child(shop)


func set_gem_wallet(data: Dictionary) -> void:
	if not data.has("balance"):
		return
	_balance.text = _format_gems(maxi(0, int(data.get("balance", 0))))
	for child: Node in _history.get_children():
		_history.remove_child(child)
		child.queue_free()
	var entries: Array = data.get("transactions", [])
	_status.text = "No confirmed Gem activity yet." if entries.is_empty() else ""
	_count.text = "Showing your latest 50 transactions." if entries.size() >= 50 else ""
	for raw: Variant in entries:
		if raw is Dictionary:
			_add_transaction(raw as Dictionary)


func set_gem_wallet_error(message: String) -> void:
	if _balance.text == "—":
		_status.text = message
	else:
		_count.text = "Could not refresh history. Showing the last loaded activity."


func _add_transaction(entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", T.panel(T.sage(), 18, 14))
	_history.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	var source := _label(_source_name(String(entry.get("kind", ""))), 20, T.SEMIBOLD, T.ink())
	description.add_child(source)
	var date := String(entry.get("createdAt", "")).left(10)
	description.add_child(_label(date if not date.is_empty() else "Date unavailable", 16, T.REGULAR, T.muted()))
	var amount := int(entry.get("amount", 0))
	var amount_label := _label(("+" if amount >= 0 else "") + _format_gems(amount), 23, T.BOLD, T.ink())
	amount_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount_label.custom_minimum_size.x = 72
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(amount_label)


static func _source_name(kind: String) -> String:
	match kind:
		"online_pot": return "Online game pot"
		"online_completion": return "Online game completion"
		"verified_ai_pot": return "AI game pot"
		"rewarded_ad", "ad_reward": return "Advert reward"
		"purchase", "shop_purchase": return "Gem purchase"
		_: return "Gem activity"


static func _format_gems(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits.substr(index, 1)
	return ("-" if value < 0 else "") + result


func _label(value: String, font_size: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fit() -> void:
	if not is_node_ready():
		return
	var side := maxi(16, roundi(24 * clampf(size.x / 540.0, 0.66, 1.0)))
	var top := side
	var bottom := side
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := DisplayServer.get_display_safe_area()
		var window := DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0 and safe.has_area():
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	_balance.add_theme_font_size_override("font_size", 40 if size.x < 400 else 48)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		back_requested.emit()
