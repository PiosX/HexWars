extends CanvasLayer
class_name MainMenu

# === COLORS ===
const BG_COLOR = Color("1A1A1A")
const PANEL_BG = Color("1A1A28")
const PANEL_BORDER = Color("2A2A40")
const TEXT_SUBTITLE = Color("6A7282")
const TEXT_TAP = Color("4A5565")
const TEXT_NAV = Color("D1D5DC")
const BADGE_BG = Color("#FB2C36")

# Gradient colors for nav buttons
const NAV_GRADIENT_TOP = Color("2A2A40")
const NAV_GRADIENT_BOTTOM = Color("1A1A28")

# Border colors with opacity
const HOME_BORDER = Color("AD46FF", 0.3)
const HOME_ACTIVE = Color("AD46FF")
const LEVELS_BORDER = Color("2B7FFF", 0.2)
const LEVELS_ACTIVE = Color("2B7FFF")
const SHOP_BORDER = Color("00BC7D", 0.3)
const SHOP_ACTIVE = Color("00BC7D")
const HOWTO_BORDER = Color("FE9A00", 0.2)
const HOWTO_ACTIVE = Color("FE9A00")

# === PATHS ===
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_SOUND = "res://ui/settings/sound.png"
const ICON_MUSIC = "res://ui/settings/music.png"
const ICON_INFO = "res://ui/settings/howto.png"
const ICON_TIME = "res://ui/time2.png"
const ICON_TITLE = "res://ui/title.png"
const ICON_BTN = "res://ui/btn.png"
const ICON_H1 = "res://ui/h1.png"
const ICON_H2 = "res://ui/h2.png"
const ICON_H3 = "res://ui/h3.png"
const ICON_H4 = "res://ui/h4.png"

# === REFS ===
var background: ColorRect
var hex_animation_container: Node2D
var settings_button: Button
var settings_menu: VBoxContainer
var sound_button: Button
var music_button: Button
var info_button: Button
var level_label: Label
var currency_panel: Panel
var currency_amount: Label
var title_image: TextureRect
var cta_button: TextureRect
var tap_label: Label
var nav_container: HBoxContainer
var nav_buttons: Dictionary = {}

var active_tab: String = "home"
var settings_expanded: bool = false
var sound_enabled: bool = true
var music_enabled: bool = true

signal tab_changed(tab_name: String)
signal play_pressed()

func _ready():
	setup_background()
	setup_hex_animation()
	setup_top_panel()
	setup_center_content()
	setup_bottom_nav()
	
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func setup_background():
	"""Creates dark background with animated hexes"""
	background = ColorRect.new()
	background.name = "Background"
	background.color = BG_COLOR
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	add_child(background)
	
	# Container for hex animations (behind everything)
	hex_animation_container = Node2D.new()
	hex_animation_container.name = "HexAnimation"
	hex_animation_container.z_index = -1
	add_child(hex_animation_container)

func setup_hex_animation():
	"""Creates moving hex pattern in background"""
	var hex_size = 60.0
	var hex_spacing = hex_size * 1.732  # sqrt(3) for perfect hex tiling
	
	# Create grid of hexes that covers screen + extra for scrolling
	for row in range(-2, 20):
		for col in range(-2, 15):
			var hex = create_animated_hex()
			var x = col * hex_spacing
			var y = row * hex_size * 1.5
			
			# Offset every other row
			if row % 2 == 1:
				x += hex_spacing * 0.5
			
			hex.position = Vector2(x, y)
			hex_animation_container.add_child(hex)
			
			# Animate slowly moving
			var tween = create_tween()
			tween.set_loops()
			var duration = randf_range(20.0, 30.0)
			tween.tween_property(hex, "position:y", y + hex_size * 2, duration)
			tween.tween_property(hex, "position:y", y, duration)

func create_animated_hex() -> Polygon2D:
	"""Creates a single hex shape"""
	var hex = Polygon2D.new()
	var size = 30.0
	var points = PackedVector2Array()
	
	# Create hexagon points
	for i in range(6):
		var angle = deg_to_rad(60 * i + 30)
		points.append(Vector2(cos(angle) * size, sin(angle) * size))
	
	hex.polygon = points
	hex.color = Color("2A2A40", 0.15)  # Very subtle
	
	return hex

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
	
	# Music button
	music_button = create_icon_button(ICON_MUSIC, Vector2(95, 95))
	music_button.pressed.connect(_on_music_pressed)
	settings_menu.add_child(music_button)
	
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
	
	level_label = Label.new()
	level_label.text = "LEVEL 01"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 28)
	level_label.add_theme_color_override("font_color", Color.WHITE)
	level_label.anchor_right = 1.0
	level_label.anchor_bottom = 1.0
	level_container.add_child(level_label)
	
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
	
	currency_amount = Label.new()
	currency_amount.text = "12500"
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

func setup_center_content():
	"""Creates title and CTA button in center"""
	# Container for center content
	var center_container = Control.new()
	center_container.name = "CenterContainer"
	center_container.set_meta("center_middle", true)
	add_child(center_container)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_container.add_child(vbox)
	
	# Title image
	title_image = TextureRect.new()
	title_image.texture = load(ICON_TITLE)
	title_image.custom_minimum_size = Vector2(225, 72)
	title_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title_image)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Conquer the battlefield"
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", TEXT_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer1)
	
	# CTA Button
	cta_button = TextureRect.new()
	cta_button.texture = load(ICON_BTN)
	cta_button.custom_minimum_size = Vector2(200, 200)
	cta_button.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	cta_button.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cta_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cta_button.pivot_offset = Vector2(100, 100)  # Center pivot for animation
	vbox.add_child(cta_button)
	
	# Animate CTA button (pulse)
	var tween = create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(cta_button, "scale", Vector2(1.08, 1.08), 1.2)
	tween.tween_property(cta_button, "scale", Vector2.ONE, 1.2)
	
	# Add glow effect
	var glow = create_glow_effect()
	cta_button.add_child(glow)
	
	# Make clickable
	var click_area = Control.new()
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	click_area.anchor_right = 1.0
	click_area.anchor_bottom = 1.0
	click_area.gui_input.connect(_on_cta_clicked)
	cta_button.add_child(click_area)
	
	# Spacer before tap label
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer2)
	
	# Tap to play label
	tap_label = Label.new()
	tap_label.text = "TAP TO PLAY"
	tap_label.add_theme_font_size_override("font_size", 20)
	tap_label.add_theme_color_override("font_color", TEXT_TAP)
	tap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tap_label)
	
	# Animate tap label (blink effect)
	var blink_tween = create_tween()
	blink_tween.set_loops()
	blink_tween.tween_property(tap_label, "modulate:a", 0.3, 0.8)
	blink_tween.tween_property(tap_label, "modulate:a", 1.0, 0.8)

func create_glow_effect() -> Panel:
	"""Creates glowing shadow effect"""
	var glow = Panel.new()
	glow.z_index = -1
	glow.anchor_left = 0.5
	glow.anchor_top = 0.5
	glow.anchor_right = 0.5
	glow.anchor_bottom = 0.5
	glow.offset_left = -100
	glow.offset_top = -100
	glow.offset_right = 100
	glow.offset_bottom = 100
	
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(1, 1, 1, 0.3)
	glow_style.shadow_size = 40
	glow_style.shadow_color = Color(1, 1, 1, 0.5)
	glow_style.corner_radius_top_left = 999
	glow_style.corner_radius_top_right = 999
	glow_style.corner_radius_bottom_left = 999
	glow_style.corner_radius_bottom_right = 999
	glow.add_theme_stylebox_override("panel", glow_style)
	
	return glow

func setup_bottom_nav():
	"""Creates bottom navigation with 4 tabs"""
	nav_container = HBoxContainer.new()
	nav_container.name = "NavContainer"
	nav_container.add_theme_constant_override("separation", 24)
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
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
	
	# Set home as active
	update_active_tab("home")

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
	"""Creates gradient style for nav button"""
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
	
	# Gradient effect
	style.bg_color = gradient_bottom
	
	return style

func _on_nav_hover(panel: Panel, is_hovering: bool):
	"""Handles hover effect for nav buttons"""
	if not panel.has_meta("is_active") or not panel.get_meta("is_active"):
		# Find icon container (first child of panel, before badge if exists)
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
	"""Handles navigation button press"""
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
	"""Toggles settings menu"""
	settings_expanded = !settings_expanded
	settings_menu.visible = settings_expanded
	
	if settings_expanded:
		# Animate menu appearing
		settings_menu.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(settings_menu, "modulate", Color.WHITE, 0.2)

func _on_sound_pressed():
	"""Toggles sound"""
	sound_enabled = !sound_enabled
	update_toggle_button(sound_button, sound_enabled)

func _on_music_pressed():
	"""Toggles music"""
	music_enabled = !music_enabled
	update_toggle_button(music_button, music_enabled)

func update_toggle_button(btn: Button, is_enabled: bool):
	"""Updates toggle button appearance"""
	if is_enabled:
		btn.modulate = Color.WHITE
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)
		# TODO: Add cross-out line

func _on_info_pressed():
	"""Opens info/tutorial"""
	print("Info pressed")

func _on_cta_clicked(event: InputEvent):
	"""Handles CTA button click"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		play_pressed.emit()
		get_tree().change_scene_to_file("res://main_scene.tscn")

func _on_viewport_size_changed():
	"""Handles responsive layout"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Position level label (center top)
	for child in get_children():
		if child.has_meta("center_top"):
			child.position = Vector2(viewport_size.x / 2 - child.custom_minimum_size.x / 2, 20)
		
		if child.has_meta("right_top"):
			var shop_center_y = 20 + 96 / 2
			var currency_center_y = child.custom_minimum_size.y / 2
			child.position = Vector2(viewport_size.x - child.custom_minimum_size.x - 20, shop_center_y - currency_center_y)
		
		if child.has_meta("center_middle"):
			child.position = Vector2(viewport_size.x / 2, viewport_size.y / 2 - 100)
			var vbox = child.get_child(0)
			if vbox:
				vbox.position = Vector2(-vbox.size.x / 2, -vbox.size.y / 2)
		
		if child.has_meta("bottom_center"):
			# Dynamically center based on actual container size
			await get_tree().process_frame  # Wait for layout to update
			var container_width = child.size.x if child.size.x > 0 else 600  # fallback
			child.position = Vector2(viewport_size.x / 2 - container_width / 2, viewport_size.y - 200)

func set_currency(amount: int):
	"""Updates currency display"""
	if currency_amount:
		currency_amount.text = str(amount)

func set_level(level: int):
	"""Updates level display"""
	if level_label:
		level_label.text = "LEVEL %02d" % level
