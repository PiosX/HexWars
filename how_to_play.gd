extends CanvasLayer
class_name HowToPlay

@onready var content_scroll = $ContentWrapper/ContentScroll
@onready var sections = [
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/SectionGoal,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/SectionGame,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/SectionKingdoms,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/Economy,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/Units,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/Rules,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/Bandits
]

@onready var buttons = [
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow1,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow2,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow3,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow4,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow5,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow6,
	$ContentWrapper/ContentScroll/MarginContainer/MainContent/ContentsPanel/MarginContainer/ContentsLayout/ButtonGrid/ButtonRow7
]

# === COLORS ===
const BG_COLOR = Color("121218")
const PANEL_BG = Color("1A1A28")
const PANEL_BORDER = Color("2A2A40")
const TEXT_PRIMARY = Color("FFFFFF")
const TEXT_SECONDARY = Color("6A7282")
const TEXT_NAV = Color("D1D5DC")
const BADGE_BG = Color("#FB2C36")

# Nav button colors
const NAV_GRADIENT_TOP = Color("2A2A40")
const NAV_GRADIENT_BOTTOM = Color("1A1A28")
const HOME_BORDER = Color("AD46FF", 0.3)
const HOME_ACTIVE = Color("AD46FF")
const LEVELS_BORDER = Color("2B7FFF", 0.2)
const LEVELS_ACTIVE = Color("2B7FFF")
const SHOP_BORDER = Color("00BC7D", 0.3)
const SHOP_ACTIVE = Color("00BC7D")
const HOWTO_BORDER = Color("FE9A00", 0.2)
const HOWTO_ACTIVE = Color("FE9A00")
const BOTTOM_PANEL_HEIGHT = 200.0
var bottom_panel_bg: ColorRect

# === PATHS ===
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_SOUND = "res://ui/settings/sound.png"
const ICON_MUSIC = "res://ui/settings/music.png"
const ICON_INFO = "res://ui/settings/howto.png"
const ICON_TIME = "res://ui/time2.png"
const ICON_H1 = "res://ui/h1.png"
const ICON_H2 = "res://ui/h2.png"
const ICON_H3 = "res://ui/h3.png"
const ICON_H4 = "res://ui/h4.png"

# === REFS ===
var background: ColorRect
var settings_button: Button
var settings_menu: VBoxContainer
var sound_button: Button
var music_button: Button
var info_button: Button
var title_label: Label
var currency_panel: Panel
var currency_amount: Label
var nav_container: HBoxContainer
var nav_buttons: Dictionary = {}

var settings_expanded: bool = false
var sound_enabled: bool = true
var music_enabled: bool = true
var active_tab: String = "howto"

signal tab_changed(tab_name: String)

func _ready():
	var main_node = get_node_or_null("/root/Main")
	if main_node:
		sound_enabled = main_node.sound_enabled
		music_enabled = main_node.music_enabled
	setup_panel_backgrounds()
	setup_top_panel()
	setup_bottom_nav()
	
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	for i in range(buttons.size()):
		buttons[i].pressed.connect(_scroll_to_section.bind(i))

func setup_top_panel():
	"""Creates top panel with settings, level, and currency"""
	# Settings button (top left)
	settings_button = create_icon_button(ICON_SETTINGS, Vector2(95, 95))
	settings_button.position = Vector2(12, 20)
	settings_button.pressed.connect(_on_settings_pressed)
	add_child(settings_button)
	
	# Settings menu (hidden by default)
	settings_menu = VBoxContainer.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.add_theme_constant_override("separation", 8)
	settings_menu.position = Vector2(12, 127)
	settings_menu.visible = false
	settings_menu.z_index = 100
	add_child(settings_menu)
	
	# Sound button
	sound_button = create_icon_button(ICON_SOUND, Vector2(95, 95))
	sound_button.pressed.connect(_on_sound_pressed)
	settings_menu.add_child(sound_button)
	update_toggle_button(sound_button, sound_enabled)
	
	# Music button
	music_button = create_icon_button(ICON_MUSIC, Vector2(95, 95))
	music_button.pressed.connect(_on_music_pressed)
	settings_menu.add_child(music_button)
	update_toggle_button(music_button, music_enabled)
	
	# Info button
	info_button = create_icon_button(ICON_INFO, Vector2(95, 95))
	info_button.pressed.connect(_on_info_pressed)
	settings_menu.add_child(info_button)
	
	# Level label (center)
	var level_container = Panel.new()
	level_container.name = "LevelContainer"
	level_container.custom_minimum_size = Vector2(250, 96)
	
	var level_style = StyleBoxFlat.new()
	level_style.bg_color = PANEL_BG
	level_style.border_width_left = 1
	level_style.border_width_right = 1
	level_style.border_width_top = 1
	level_style.border_width_bottom = 1
	level_style.border_color = PANEL_BORDER
	level_style.corner_radius_top_left = 999
	level_style.corner_radius_top_right = 999
	level_style.corner_radius_bottom_left = 999
	level_style.corner_radius_bottom_right = 999
	level_container.add_theme_stylebox_override("panel", level_style)
	add_child(level_container)
	
	title_label = Label.new()
	title_label.text = "HOW TO PLAY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	level_container.add_child(title_label)
	
	level_container.set_meta("center_top", true)
	
	# Currency panel (top right)
	currency_panel = Panel.new()
	currency_panel.name = "CurrencyPanel"
	currency_panel.custom_minimum_size = Vector2(160, 60)
	
	var currency_style = StyleBoxFlat.new()
	currency_style.bg_color = Color(PANEL_BG, 0.9)
	currency_style.border_width_left = 1
	currency_style.border_width_right = 1
	currency_style.border_width_top = 1
	currency_style.border_width_bottom = 1
	currency_style.border_color = PANEL_BORDER
	currency_style.corner_radius_top_left = 999
	currency_style.corner_radius_top_right = 999
	currency_style.corner_radius_bottom_left = 999
	currency_style.corner_radius_bottom_right = 999
	currency_panel.add_theme_stylebox_override("panel", currency_style)
	add_child(currency_panel)
	
	var currency_hbox = HBoxContainer.new()
	currency_hbox.add_theme_constant_override("separation", 4)
	currency_hbox.alignment = BoxContainer.ALIGNMENT_END
	currency_hbox.anchor_left = 0.0
	currency_hbox.anchor_right = 1.0
	currency_hbox.anchor_top = 0.0
	currency_hbox.anchor_bottom = 1.0
	currency_hbox.offset_left = 10
	currency_hbox.offset_right = -10
	currency_hbox.offset_top = 0
	currency_hbox.offset_bottom = 0
	currency_panel.add_child(currency_hbox)
	
	var currency = get_node("/root/Main").global_time_currency
	currency_amount = Label.new()
	currency_amount.text = str(currency)
	currency_amount.add_theme_font_size_override("font_size", 24)
	currency_amount.add_theme_color_override("font_color", Color.WHITE)
	currency_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	currency_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	currency_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	currency_amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var font_var = FontVariation.new()
	font_var.set_variation_embolden(0.5)
	currency_amount.add_theme_font_override("font", font_var)
	currency_hbox.add_child(currency_amount)
	
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(54, 44)  # 32 width, 22 height (compensating for 10px shadow)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Główna ikona (bez cienia)
	var currency_icon = TextureRect.new()
	currency_icon.texture = load(ICON_TIME)
	currency_icon.custom_minimum_size = Vector2(60, 60)
	currency_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	currency_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	currency_icon.anchor_right = 1.0
	currency_icon.anchor_top = 0.0
	currency_icon.anchor_bottom = 1.0
	currency_icon.offset_top = 0  # Przesunięcie w górę o 5px dla kompensacji cienia
	icon_container.add_child(currency_icon)
	
	currency_hbox.add_child(icon_container)
	currency_panel.set_meta("right_top", true)
	
func setup_panel_backgrounds():
	# Bottom panel background
	bottom_panel_bg = ColorRect.new()
	bottom_panel_bg.name = "BottomPanelBG"
	bottom_panel_bg.color = BG_COLOR
	bottom_panel_bg.anchor_left = 0.0
	bottom_panel_bg.anchor_right = 1.0
	bottom_panel_bg.anchor_top = 1.0
	bottom_panel_bg.anchor_bottom = 1.0
	bottom_panel_bg.offset_top = -(BOTTOM_PANEL_HEIGHT + 20)
	bottom_panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_panel_bg.z_index = 10
	add_child(bottom_panel_bg)

func setup_bottom_nav():
	"""Creates bottom navigation with 4 tabs"""
	nav_container = HBoxContainer.new()
	nav_container.name = "NavContainer"
	nav_container.add_theme_constant_override("separation", 24)
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.z_index = 100
	nav_container.set_meta("bottom_center", true)
	add_child(nav_container)
	
	# Home button
	var home_btn = create_nav_button("HOME", ICON_H1, HOME_BORDER, HOME_ACTIVE)
	nav_buttons["home"] = home_btn
	nav_container.add_child(home_btn)
	
	# Levels button
	var levels_btn = create_nav_button("LEVELS", ICON_H2, LEVELS_BORDER, LEVELS_ACTIVE)
	nav_buttons["levels"] = levels_btn
	nav_container.add_child(levels_btn)
	
	# Shop button (with badge)
	var shop_btn = create_nav_button("SHOP", ICON_H3, SHOP_BORDER, SHOP_ACTIVE, true)
	nav_buttons["shop"] = shop_btn
	nav_container.add_child(shop_btn)
	
	# How to button
	var howto_btn = create_nav_button("HOW TO", ICON_H4, HOWTO_BORDER, HOWTO_ACTIVE)
	nav_buttons["howto"] = howto_btn
	nav_container.add_child(howto_btn)
	
	# Set howto as active
	update_active_tab("howto")

func create_icon_button(icon_path: String, size: Vector2) -> Button:
	"""Creates rounded icon button"""
	var btn = Button.new()
	btn.custom_minimum_size = size
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = PANEL_BG
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = PANEL_BORDER
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(PANEL_BORDER, 1.0)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	
	var icon = load(icon_path)
	if icon:
		btn.icon = icon
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", int(size.x * 0.47))
	
	return btn

func create_nav_button(label_text: String, icon_path: String, border_color: Color, active_color: Color, has_badge: bool = false) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(140, 170)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	
	var transparent_style = StyleBoxFlat.new()
	transparent_style.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("normal", transparent_style)
	btn.add_theme_stylebox_override("hover", transparent_style)
	btn.add_theme_stylebox_override("pressed", transparent_style)
	
	var visual_container = VBoxContainer.new()
	visual_container.add_theme_constant_override("separation", 12)
	visual_container.alignment = BoxContainer.ALIGNMENT_CENTER
	visual_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_container.anchor_right = 1.0
	visual_container.anchor_bottom = 1.0
	btn.add_child(visual_container)
	
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(140, 140)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style_normal = create_nav_button_style(border_color, NAV_GRADIENT_BOTTOM)
	var style_hover = create_nav_button_style(active_color, NAV_GRADIENT_BOTTOM)
	style_hover.shadow_size = 8
	style_hover.shadow_color = Color(active_color, 0.4)
	style_hover.shadow_offset = Vector2(0, 4)
	
	panel.add_theme_stylebox_override("panel", style_normal)
	panel.set_meta("style_normal", style_normal)
	panel.set_meta("style_hover", style_hover)
	panel.set_meta("style_active", style_hover)
	panel.set_meta("border_color", border_color)
	panel.set_meta("active_color", active_color)
	
	var icon_container = Control.new()
	icon_container.anchor_left = 0.5
	icon_container.anchor_top = 0.5
	icon_container.anchor_right = 0.5
	icon_container.anchor_bottom = 0.5
	icon_container.offset_left = -40
	icon_container.offset_top = -40
	icon_container.offset_right = 40
	icon_container.offset_bottom = 40
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon_container)
	
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.pivot_offset = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon)
	
	if has_badge:
		var badge = Panel.new()
		badge.custom_minimum_size = Vector2(70, 28)
		badge.position = Vector2(70, -10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var badge_style = StyleBoxFlat.new()
		badge_style.bg_color = BADGE_BG
		badge_style.corner_radius_top_left = 14
		badge_style.corner_radius_top_right = 14
		badge_style.corner_radius_bottom_left = 14
		badge_style.corner_radius_bottom_right = 14
		badge.add_theme_stylebox_override("panel", badge_style)
		
		var badge_label = Label.new()
		badge_label.text = "75% OFF"
		badge_label.add_theme_font_size_override("font_size", 14)
		badge_label.add_theme_color_override("font_color", Color.WHITE)
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_label.anchor_right = 1.0
		badge_label.anchor_bottom = 1.0
		badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(badge_label)
		
		panel.add_child(badge)
	
	visual_container.add_child(panel)
	btn.set_meta("panel", panel)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_NAV)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_container.add_child(label)
	
	# DODAJ TE LINIE:
	btn.mouse_entered.connect(func(): _on_nav_hover(panel, true))
	btn.mouse_exited.connect(func(): _on_nav_hover(panel, false))
	btn.pressed.connect(func(): _on_nav_pressed(label_text.to_lower().replace(" ", "")))

	return btn

func create_nav_button_style(border_color: Color, gradient_bottom: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = NAV_GRADIENT_TOP
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.bg_color = gradient_bottom
	
	return style

func _on_nav_hover(panel: Panel, is_hovering: bool):
	if not panel.has_meta("is_active") or not panel.get_meta("is_active"):
		var icon_container = null
		for child in panel.get_children():
			if child is Control and child.get_child_count() > 0:
				var first_child = child.get_child(0)
				if first_child is TextureRect and first_child.name == "Icon":
					icon_container = first_child
					break
		
		if is_hovering:
			panel.add_theme_stylebox_override("panel", panel.get_meta("style_hover"))
			if icon_container:
				var tween = create_tween()
				tween.tween_property(icon_container, "scale", Vector2(1.15, 1.15), 0.2)
		else:
			panel.add_theme_stylebox_override("panel", panel.get_meta("style_normal"))
			if icon_container:
				var tween = create_tween()
				tween.tween_property(icon_container, "scale", Vector2.ONE, 0.2)

func _on_nav_pressed(tab_name: String):
	get_node("/root/Main").play_btn_sound()
	update_active_tab(tab_name)
	tab_changed.emit(tab_name)

func update_active_tab(tab_name: String):
	active_tab = tab_name
	
	for key in nav_buttons.keys():
		var btn = nav_buttons[key]
		var panel = btn.get_meta("panel")
		
		var icon_container = null
		for child in panel.get_children():
			if child is Control and child.get_child_count() > 0:
				var first_child = child.get_child(0)
				if first_child is TextureRect and first_child.name == "Icon":
					icon_container = first_child
					break
		
		if key == tab_name:
			panel.set_meta("is_active", true)
			panel.add_theme_stylebox_override("panel", panel.get_meta("style_active"))
			if icon_container:
				icon_container.scale = Vector2(1.15, 1.15)
		else:
			panel.set_meta("is_active", false)
			panel.add_theme_stylebox_override("panel", panel.get_meta("style_normal"))
			if icon_container:
				icon_container.scale = Vector2.ONE

func _on_settings_pressed():
	get_node("/root/Main").play_btn_sound()
	settings_expanded = !settings_expanded
	settings_menu.visible = settings_expanded
	
	if settings_expanded:
		settings_menu.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(settings_menu, "modulate", Color.WHITE, 0.2)

func _on_sound_pressed():
	"""Toggles sound"""
	sound_enabled = !sound_enabled
	update_toggle_button(sound_button, sound_enabled)
	get_node("/root/Main").toggle_sound(sound_enabled)
	get_node("/root/Main").play_btn_sound()

func _on_music_pressed():
	"""Toggles music"""
	get_node("/root/Main").play_btn_sound()
	music_enabled = !music_enabled
	update_toggle_button(music_button, music_enabled)
	get_node("/root/Main").toggle_music(music_enabled)

func update_toggle_button(btn: Button, is_enabled: bool):
	if is_enabled:
		btn.modulate = Color.WHITE
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)

func _on_info_pressed():
	get_node("/root/Main").play_btn_sound()
	print("Info pressed")

func _on_viewport_size_changed():
	var viewport_size = get_viewport().get_visible_rect().size
	
	for child in get_children():
		if child.has_meta("center_top"):
			child.position = Vector2(viewport_size.x / 2 - child.custom_minimum_size.x / 2, 20)
		
		if child.has_meta("right_top"):
			var title_center_y = 20 + 96 / 2
			var currency_center_y = child.custom_minimum_size.y / 2
			child.position = Vector2(viewport_size.x - child.custom_minimum_size.x - 20, title_center_y - currency_center_y)
		
		if child.has_meta("bottom_center"):
			await get_tree().process_frame
			var container_width = child.size.x if child.size.x > 0 else 600
			child.position = Vector2(viewport_size.x / 2 - container_width / 2, viewport_size.y - 200)

func set_currency(amount: int):
	if currency_amount:
		currency_amount.text = str(amount)
		
func _scroll_to_section(index: int):
	var section = sections[index]
	var section_pos = section.position.y
	
	var tween = create_tween()
	tween.tween_property(content_scroll, "scroll_vertical", int(section_pos), 0.4)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
