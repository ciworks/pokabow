class_name AchievementBrowser
extends Control
## Catalogue-driven presentation only. Unlock rules remain in the application/API.
signal home_requested
signal profile_requested
signal tournaments_requested
signal refresh_requested
const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const PAGE_SIZE: int = 6
const GROUPS := {"first_hand": "Hands", "straight": "Hands", "full_house": "Hands", "edge_cluster": "Edge Matching", "ai_victory": "Victories"}
const ART_ROOT: String = "res://assets/achievements/"
var rows: Array[Dictionary] = []
var category: String = ""
var filter: String = "All"
var page: int = 0
var query: String = ""
var received: bool = false
var loading: bool = true
var error_message: String = ""
var _factor: float = 1.0
var _margin: MarginContainer
var _column: VBoxContainer
var _heading: Label
var _back: Button
var _search_button: Button
var _search: LineEdit
var _filters: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _pages: HBoxContainer
var _previous: Button
var _next: Button
var _page_label: Label
var _nav: HBoxContainer
var _detail: Control
var _detail_panel: PanelContainer
var _detail_copy: Label
var _detail_title: Label
var _detail_status: Label
var _detail_art: TextureRect
var _detail_close: Button
var _last_badge: WeakRef
var _detail_id: String = ""

func _ready() -> void:
	theme = T.create()
	var background := ColorRect.new()
	background.color = T.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column = VBoxContainer.new()
	_margin.add_child(_column)
	var header := HBoxContainer.new()
	_column.add_child(header)
	_back = _button("", go_back)
	T.style_back_button(_back)
	_back.tooltip_text = "Back"
	header.add_child(_back)
	_heading = _label("Achievements", 32, true)
	_heading.add_theme_font_override("font", T.BOLD)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	_search_button = _button("", _toggle_search)
	_search_button.icon = load("res://assets/achievements/search.svg")
	_search_button.tooltip_text = "Search this category"
	header.add_child(_search_button)
	_search = LineEdit.new()
	_search.placeholder_text = "Search achievements"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_search_changed)
	_search.visible = false
	_column.add_child(_search)
	_filters = HBoxContainer.new()
	_column.add_child(_filters)
	for value: String in ["All", "Unlocked", "Locked"]:
		var button := _button(value, select_filter.bind(value))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_filters.add_child(button)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_pages = HBoxContainer.new()
	_pages.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(_pages)
	_previous = _button("‹", change_page.bind(-1))
	_previous.tooltip_text = "Previous page"
	_pages.add_child(_previous)
	_page_label = _label("", 20)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size.x = 100
	_pages.add_child(_page_label)
	_next = _button("›", change_page.bind(1))
	_next.tooltip_text = "Next page"
	_pages.add_child(_next)
	_nav = HBoxContainer.new()
	_nav.add_theme_constant_override("separation", 8)
	_column.add_child(_nav)
	for destination: String in ["Home", "Achievements", "Tournaments"]:
		var nav_button := _button("", _navigate.bind(destination))
		nav_button.name = destination + "Button"
		nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_button.tooltip_text = destination + (" — current page" if destination == "Achievements" else "")
		_nav.add_child(nav_button)
		T.style_button(nav_button, "selected" if destination == "Achievements" else "quiet")
		var contents := VBoxContainer.new()
		contents.name = "Contents"
		contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nav_button.add_child(contents)
		contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_top = 7
		contents.offset_bottom = -7
		contents.alignment = BoxContainer.ALIGNMENT_CENTER
		contents.add_theme_constant_override("separation", 3)
		var icon := _image(T.icon_texture(destination.to_lower()), 24)
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(24, 24)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		contents.add_child(icon)
		var caption := _label(destination, 18)
		caption.name = "Caption"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_override("font", T.SEMIBOLD if destination == "Achievements" else T.MEDIUM)
		caption.add_theme_color_override("font_color", T.ink() if destination == "Achievements" else T.muted())
		contents.add_child(caption)
	_build_detail()
	resized.connect(_fit)
	_fit()

func _pixel_scale() -> float:
	return maxf(1.0, size.x / maxf(1.0, get_window().size.x))

func _touch_size() -> float:
	return maxf(48.0, 48.0 * _pixel_scale())

func _label(copy: String, font_size: int, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = copy
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", T.SEMIBOLD if bold else T.REGULAR)
	label.add_theme_font_size_override("font_size", maxi(ceili(14 * _pixel_scale()), roundi(font_size * _factor)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(copy: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = copy
	button.custom_minimum_size = Vector2(_touch_size(), maxf(_touch_size(), 64 * _factor))
	button.add_theme_font_size_override("font_size", maxi(14, roundi(22 * _factor)))
	T.style_button(button, "quiet")
	button.pressed.connect(action)
	return button

func _image(texture: Texture2D, height: float) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size.y = height * _factor
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _art(key: String) -> Texture2D:
	var file: String = {"Hands": "first_hand", "Edge Matching": "edge_cluster", "Victories": "ai_victory"}.get(key, key)
	if not file in ["first_hand", "straight", "full_house", "edge_cluster", "ai_victory", "two_pair_10", "perfect_match"]:
		file = "milestone"
	return load(ART_ROOT + file + ".svg") as Texture2D


func _badge_key_for(row: Dictionary) -> String:
	var supplied: Variant = row.get("badgeKey", "")
	return str(supplied) if supplied is String and not str(supplied).is_empty() else str(row.id)

func _fit() -> void:
	_factor = clampf(size.x / 540.0, 0.5, 1.4)
	var hub_scale: float = clampf(size.x / 540.0, 0.66, 1.0)
	var side: int = maxi(16, roundi(24 * hub_scale))
	var top: int = maxi(16, roundi(20 * hub_scale))
	var bottom: int = maxi(16, roundi(24 * hub_scale))
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0 and safe.has_area():
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	for key: String in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + key, side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	_column.add_theme_constant_override("separation", maxi(6, roundi(10 * _factor)))
	_body.add_theme_constant_override("separation", maxi(10, roundi(16 * _factor)))
	_heading.add_theme_font_size_override("font_size", 40)
	_search.add_theme_font_size_override("font_size", maxi(16, roundi(24 * _factor)))
	_search.custom_minimum_size.y = maxf(_touch_size(), 64 * _factor)
	for holder: Node in [_nav, _filters, _pages, _back.get_parent()]:
		for node: Node in holder.get_children():
			if node is Button:
				node.custom_minimum_size = Vector2(_touch_size(), maxf(_touch_size(), 64 * _factor))
				node.add_theme_font_size_override("font_size", maxi(14, roundi(22 * _factor)))
				if holder == _nav:
					node.custom_minimum_size.y = maxi(64, roundi(80 * _factor))
					var contents: VBoxContainer = node.get_child(0)
					contents.get_child(0).custom_minimum_size = Vector2(24, 24)
					contents.get_child(1).add_theme_font_size_override("font_size", maxi(13, roundi(20 * _factor)))
	_back.custom_minimum_size = T.BACK_BUTTON_SIZE
	_detail_panel.custom_minimum_size = Vector2(minf(size.x - 32, 480), 0)
	_detail_copy.add_theme_font_size_override("font_size", maxi(16, roundi(22 * _factor)))
	_detail_title.add_theme_font_size_override("font_size", maxi(20, roundi(28 * _factor)))
	_detail_title.max_lines_visible = 3
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_status.add_theme_font_size_override("font_size", maxi(14, roundi(22 * _factor)))
	_detail_art.custom_minimum_size.y = 80 * _factor
	_detail_close.custom_minimum_size.y = maxf(_touch_size(), 64 * _factor)
	_render()

func set_rows(values: Array) -> void:
	rows.clear()
	var ids: Dictionary = {}
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var id: String = str(value.get("id", "")).strip_edges()
		if id.is_empty() or ids.has(id):
			continue
		var row: Dictionary = value.duplicate(true)
		row["id"] = id
		row["name"] = str(row.get("name", id.replace("_", " ").capitalize()))
		rows.append(row)
		ids[id] = true
	received = true
	loading = false
	error_message = ""
	if is_node_ready():
		_refresh_detail()
		_render()

func _refresh_detail() -> void:
	if not _detail.visible:
		return
	for row: Dictionary in rows:
		if str(row.id) == _detail_id:
			open_detail(row)
			return
	_close_detail()

func set_loading() -> void:
	loading = true
	error_message = ""
	if is_node_ready():
		_render()

func set_error(message: String) -> void:
	loading = false
	error_message = message
	if is_node_ready():
		_render()

func group_for(row: Dictionary) -> String:
	var supplied: Variant = row.get("category", "")
	if supplied is Dictionary:
		supplied = supplied.get("name", supplied.get("id", ""))
	var group: String = str(supplied).strip_edges() if supplied is String else ""
	if group.is_empty():
		return GROUPS.get(str(row.id), "Milestones")
	if group.to_lower() in ["edge", "edges", "edge_matching", "edge matching"]:
		return "Edge Matching"
	return group.replace("_", " ").capitalize()

func filtered_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		if group_for(row) != category:
			continue
		var unlocked: bool = bool(row.get("unlocked", false))
		if filter == "Unlocked" and not unlocked or filter == "Locked" and unlocked:
			continue
		if not query.is_empty() and not (str(row.name) + " " + str(row.get("description", ""))).to_lower().contains(query.to_lower()):
			continue
		result.append(row)
	return result

func select_category(value: String) -> void:
	category = value
	filter = "All"
	query = ""
	_search.text = ""
	_search.visible = false
	page = 0
	_scroll.scroll_vertical = 0
	_render()

func select_filter(value: String) -> void:
	filter = value
	page = 0
	_scroll.scroll_vertical = 0
	_render()

func _search_changed(value: String) -> void:
	query = value.strip_edges()
	page = 0
	_scroll.scroll_vertical = 0
	_render()

func _toggle_search() -> void:
	_search.visible = not _search.visible
	if _search.visible:
		_search.grab_focus()
	else:
		_search.text = ""
		_search_changed("")

func change_page(direction: int) -> void:
	page += direction
	_scroll.scroll_vertical = 0
	_render()

func show_overview() -> void:
	if is_node_ready():
		_detail.visible = false
		select_category("")

func go_back() -> void:
	if _detail.visible:
		_close_detail()
	elif not category.is_empty():
		show_overview()
	else:
		home_requested.emit()

func _navigate(destination: String) -> void:
	if destination == "Achievements":
		show_overview()
	elif destination == "Tournaments":
		tournaments_requested.emit()
	elif destination == "Profile":
		profile_requested.emit()
	else:
		home_requested.emit()

func _retry() -> void:
	set_loading()
	refresh_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		go_back()

func _render() -> void:
	if not is_node_ready():
		return
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_heading.text = "Achievements" if category.is_empty() else category
	_filters.visible = not category.is_empty()
	_search_button.visible = true
	_search_button.disabled = category.is_empty()
	_search_button.modulate.a = 0.0 if category.is_empty() else 1.0
	_search_button.focus_mode = Control.FOCUS_NONE if category.is_empty() else Control.FOCUS_ALL
	for button: Button in _filters.get_children():
		T.style_button(button, "selected" if button.text == filter else "secondary")
		button.set_pressed_no_signal(button.text == filter)
		if button.text == filter:
			for state: String in ["normal", "hover", "pressed"]:
				button.add_theme_stylebox_override(state, T.panel(T.ink(), 18, 12))
			for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				button.add_theme_color_override(state, T.canvas())
	_pages.visible = false
	if loading:
		_body.add_child(_label("Refreshing your collection…" if received else "Loading your collection…", 22))
	if not error_message.is_empty():
		_body.add_child(_label(error_message, 22))
		_body.add_child(_button("Retry", _retry))
	if not received:
		return
	if rows.is_empty():
		_body.add_child(_label("Your collection is empty", 28, true))
		_body.add_child(_label("Achievements will appear here when they are available for your account.", 24))
		if not loading and error_message.is_empty():
			_body.add_child(_button("Refresh", _retry))
		return
	if category.is_empty():
		_render_overview()
	else:
		_render_category()

func _unlocked(values: Array[Dictionary]) -> int:
	var count: int = 0
	for row: Dictionary in values:
		if bool(row.get("unlocked", false)):
			count += 1
	return count

func _panel(fill: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", T.panel(fill, 20, 14 * _factor))
	return panel

func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", maxi(8, roundi(12 * _factor)))
	grid.add_theme_constant_override("v_separation", maxi(8, roundi(12 * _factor)))
	_body.add_child(grid)
	return grid

func _render_overview() -> void:
	var summary := _panel(T.sage())
	summary.name = "CollectionSummary"
	_body.add_child(summary)
	var summary_row := HBoxContainer.new()
	summary.add_child(summary_row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(copy)
	copy.add_child(_label("Your collection", 24))
	copy.add_child(_label("%d of %d unlocked" % [_unlocked(rows), rows.size()], 32, true))
	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12 * _factor
	progress.max_value = rows.size()
	progress.value = _unlocked(rows)
	progress.add_theme_stylebox_override("background", T.panel(T.canvas(), 6, 0))
	progress.add_theme_stylebox_override("fill", T.panel(T.ink(), 6, 0))
	copy.add_child(progress)
	var trophy := _image(_art("ai_victory"), 100)
	trophy.custom_minimum_size.x = 100 * _factor
	summary_row.add_child(trophy)
	var highlights: Array[Dictionary] = []
	var dated: bool = true
	for row: Dictionary in rows:
		if bool(row.get("unlocked", false)):
			highlights.append(row)
			if _date(row).is_empty():
				dated = false
	if not highlights.is_empty():
		if dated:
			highlights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _date(a) > _date(b))
		_body.add_child(_label("Recently unlocked" if dated else "Unlocked highlights", 26, true))
		var recent := HBoxContainer.new()
		recent.add_theme_constant_override("separation", 8)
		_body.add_child(recent)
		for row: Dictionary in highlights.slice(0, 3):
			recent.add_child(_badge(row, true))
	_body.add_child(_label("Explore categories", 26, true))
	var grouped: Dictionary = {}
	for row: Dictionary in rows:
		var group: String = group_for(row)
		if not grouped.has(group):
			grouped[group] = []
		grouped[group].append(row)
	var names: Array = grouped.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		var order: Array[String] = ["Hands", "Edge Matching", "Victories", "Milestones"]
		var ai: int = order.find(a)
		var bi: int = order.find(b)
		if ai == -1 and bi == -1:
			return a.naturalnocasecmp_to(b) < 0
		return (ai if ai >= 0 else order.size()) < (bi if bi >= 0 else order.size())
	)
	var grid: GridContainer = _grid()
	_paginate(names.size())
	for value: Variant in names.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE):
		var group: String = value
		var entries: Array[Dictionary] = []
		entries.assign(grouped[group])
		var card := _button("", select_category.bind(group))
		card.name = "Category_" + group.replace(" ", "")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 168 * _factor
		_style_card(card, T.sage() if grid.get_child_count() % 2 == 0 else Color("#FBE6D7"))
		grid.add_child(card)
		var stack := _card_contents(card)
		stack.add_child(_image(_art(group), 80))
		stack.add_child(_label(group + "  ›", 26, true))
		stack.add_child(_label("%d of %d unlocked" % [_unlocked(entries), entries.size()], 20))

func _render_category() -> void:
	var all: Array[Dictionary] = []
	for row: Dictionary in rows:
		if group_for(row) == category:
			all.append(row)
	_body.add_child(_label("%d of %d unlocked" % [_unlocked(all), all.size()], 28, true))
	var matches: Array[Dictionary] = filtered_rows()
	_paginate(matches.size())
	if matches.is_empty():
		_body.add_child(_label("No matching achievements", 26, true))
		_body.add_child(_label("Try another filter or search.", 22))
		return
	var grid := _grid()
	grid.name = "BadgeGrid"
	for row: Dictionary in matches.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE):
		grid.add_child(_badge(row))
	_body.add_child(_label("Tap a badge to see how to unlock it.", 18))

func _paginate(count: int) -> void:
	var total: int = maxi(1, ceili(float(count) / PAGE_SIZE))
	page = clampi(page, 0, total - 1)
	_pages.visible = total > 1
	_previous.disabled = page == 0
	_next.disabled = page == total - 1
	_page_label.text = "%d of %d" % [page + 1, total]

func _style_card(card: Button, colour: Color) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		card.add_theme_stylebox_override(state, T.panel(colour if state == "normal" else colour.darkened(0.04), 18, 0))

func _card_contents(button: Button) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, maxi(6, roundi(10 * _factor)))
	var contents := VBoxContainer.new()
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", 4)
	margin.add_child(contents)
	return contents

func _badge(row: Dictionary, compact: bool = false) -> Button:
	var card := _button("", open_detail.bind(row))
	card.name = "Badge_" + str(row.id).validate_node_name()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = (140 if compact else 192) * _factor
	card.tooltip_text = str(row.name)
	card.set_meta("achievement_id", row.id)
	var unlocked: bool = bool(row.get("unlocked", false))
	_style_card(card, T.canvas() if compact else (Color("#FBE6D7") if unlocked else T.sage()))
	var contents := _card_contents(card)
	var art := _image(_art(_badge_key_for(row)), 64 if compact else 98)
	if not unlocked:
		art.modulate = Color(0.75, 0.83, 0.8)
	contents.add_child(art)
	var title := _label(str(row.name), 19 if compact else 24, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contents.add_child(title)
	var status := _label("✓ Unlocked" if unlocked else "Locked", 18)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", T.ink() if unlocked else T.muted())
	contents.add_child(status)
	var metric: String = str(row.get("metric", ""))
	if not metric.is_empty() and not unlocked:
		var progress: int = mini(int(row.get("progress", 0)), int(row.get("target", 1)))
		var counter := _label("%d / %d" % [progress, int(row.get("target", 1))], 17)
		counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		contents.add_child(counter)
	return card

func _date(row: Dictionary) -> String:
	var value: Variant = row.get("unlockedAt", row.get("unlocked_at", ""))
	return str(value) if value is String else ""

func _build_detail() -> void:
	_detail = Control.new()
	_detail.name = "AchievementDetail"
	add_child(_detail)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.24, 0.26, 0.55)
	_detail.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_detail.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_panel = _panel(T.canvas())
	center.add_child(_detail_panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	_detail_panel.add_child(contents)
	_detail_art = _image(_art("milestone"), 80)
	contents.add_child(_detail_art)
	_detail_title = _label("", 28, true)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(_detail_title)
	_detail_status = _label("", 22)
	_detail_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(_detail_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 100
	contents.add_child(scroll)
	_detail_copy = _label("", 22)
	_detail_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_copy)
	_detail_close = _button("Close", _close_detail)
	T.style_button(_detail_close, "primary")
	contents.add_child(_detail_close)
	_detail.hide()

func open_detail(row: Dictionary) -> void:
	if not _detail.visible:
		_last_badge = weakref(get_viewport().gui_get_focus_owner())
	_detail_id = str(row.id)
	_detail_title.text = str(row.name)
	_detail_copy.text = str(row.get("description", ""))
	if _detail_copy.text.is_empty():
		_detail_copy.text = "The unlock requirement is not available in the catalogue yet."
	_detail_status.text = "✓ Unlocked" if bool(row.get("unlocked", false)) else "Locked"
	if not bool(row.get("unlocked", false)) and not str(row.get("metric", "")).is_empty():
		_detail_status.text = "%d / %d" % [mini(int(row.get("progress", 0)), int(row.get("target", 1))), int(row.get("target", 1))]
	_detail_art.texture = _art(_badge_key_for(row))
	_detail.show()
	_detail_close.focus_next = NodePath(".")
	_detail_close.focus_previous = NodePath(".")
	_detail_close.grab_focus()

func _close_detail() -> void:
	_detail.hide()
	if _last_badge != null and is_instance_valid(_last_badge.get_ref()):
		_last_badge.get_ref().grab_focus()
