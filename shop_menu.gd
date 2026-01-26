extends CanvasLayer
class_name ShopMenu

# === COLORS ===
const BG_COLOR = Color("121218")
const PANEL_BG = Color("1A1A28")
const PANEL_BORDER = Color("2A2A40")
const TEXT_PRIMARY = Color("FFFFFF")
const TEXT_SECONDARY = Color("6A7282")
const TEXT_GOLD = Color("FFB900")
const TEXT_GOLD_DIM = Color("FEE685", 0.8)
const TEXT_GREEN = Color("00D492")
const ORANGE_PRIMARY = Color("FE9A00")
const ORANGE_BOX_BG = Color("FE9A00", 0.1)
const ORANGE_BORDER = Color("FE9A00", 0.5)
const GREEN_PRIMARY = Color("00BC7D")
const GREEN_DARK = Color("006045")
const RED_PRIMARY = Color("FB2C36")
const RED_BORDER = Color("C10007")
const ZAP_GREEN = Color("00BC7D")
const BUTTON_BG = Color("2A2A40")
const BUTTON_HOVER = Color("3A3A50")
const BUTTON_BORDER = Color("3A3A50")

# === PATHS ===
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_SOUND = "res://ui/settings/sound.png"
const ICON_MUSIC = "res://ui/settings/music.png"
const ICON_INFO = "res://ui/settings/howto.png"
const ICON_TIME = "res://ui/time2.png"
const ICON_TIME_BIG = "res://ui/shop/timeBig.png"
const ICON_TIME_MAIN = "res://ui/shop/timeMain.png"
const ICON_TIME_SMALL = "res://ui/shop/timeSmall.png"
const ICON_TIME_SQUARE = "res://ui/shop/timeSquare.png"
const ICON_BUY = "res://ui/shop/buy.png"
const ICON_NO_ADS = "res://ui/shop/noads.png"
const ICON_ZAP = "res://ui/shop/zap.png"
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
var shop_label: Label
var currency_panel: Panel
var currency_amount: Label
var nav_container: HBoxContainer
var nav_buttons: Dictionary = {}
var active_tab: String = "shop"

var settings_expanded: bool = false
var sound_enabled: bool = true
var music_enabled: bool = true

signal tab_changed(tab_name: String)

func _ready():
	setup_background()
	setup_top_panel()
	setup_shop_content()
	setup_bottom_nav()
	
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func setup_background():
	"""Creates dark background"""
	background = ColorRect.new()
	background.name = "Background"
	background.color = BG_COLOR
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	add_child(background)

func setup_top_panel():
	"""Creates top panel with settings, SHOP label, and currency"""
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
	
	# SHOP label (center)
	var shop_container = Panel.new()
	shop_container.name = "ShopContainer"
	shop_container.custom_minimum_size = Vector2(200, 96)  # Taki sam jak w main_menu
	
	var shop_style = StyleBoxFlat.new()
	shop_style.bg_color = PANEL_BG
	shop_style.border_width_left = 1
	shop_style.border_width_right = 1
	shop_style.border_width_top = 1
	shop_style.border_width_bottom = 1
	shop_style.border_color = PANEL_BORDER
	shop_style.corner_radius_top_left = 999
	shop_style.corner_radius_top_right = 999
	shop_style.corner_radius_bottom_left = 999
	shop_style.corner_radius_bottom_right = 999
	shop_container.add_theme_stylebox_override("panel", shop_style)
	add_child(shop_container)
	
	shop_label = Label.new()
	shop_label.text = "SHOP"
	shop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shop_label.add_theme_font_size_override("font_size", 28)
	shop_label.add_theme_color_override("font_color", Color.WHITE)
	shop_label.anchor_right = 1.0
	shop_label.anchor_bottom = 1.0
	shop_container.add_child(shop_label)
	
	shop_container.set_meta("center_top", true)
	
	# Currency panel (top right) - IDENTYCZNY jak w main_menu
	currency_panel = Panel.new()
	currency_panel.name = "CurrencyPanel"
	currency_panel.custom_minimum_size = Vector2(160, 60)  # Zmienione z 120 na 160
	
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
	currency_hbox.add_theme_constant_override("separation", 4)  # Zmienione z 8 na 4
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
	currency_amount.text = "12500"  # Zmienione z "1251" na "12500"
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
	icon_container.custom_minimum_size = Vector2(54, 44)  # Zmienione z 32,22 na 54,44
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Ikona (bez cienia) - IDENTYCZNIE jak w main_menu
	var currency_icon = TextureRect.new()
	currency_icon.texture = load(ICON_TIME)
	currency_icon.custom_minimum_size = Vector2(60, 60)  # Zmienione z 40 na 60
	currency_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	currency_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	currency_icon.anchor_right = 1.0
	currency_icon.anchor_top = 0.0
	currency_icon.anchor_bottom = 1.0
	currency_icon.offset_top = 0  # Zmienione z -5 na 0
	icon_container.add_child(currency_icon)
	
	currency_hbox.add_child(icon_container)
	currency_panel.set_meta("right_top", true)

func setup_shop_content():
	"""Creates scrollable shop content"""
	var scroll = ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.set_meta("shop_content", true)
	add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 26)  # Większe odstępy
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	# Info box with timeBig.png
	create_info_box(vbox)
	
	# Mega Bundle box
	create_mega_bundle_box(vbox)
	
	# 3 small purchase boxes
	create_small_purchase_boxes(vbox)
	
	# Remove ads box
	create_remove_ads_box(vbox)

func create_info_box(parent: VBoxContainer):
	"""Info box with timeBig.png and text"""
	var info_panel = Panel.new()
	info_panel.custom_minimum_size = Vector2(0, 100)
	
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = ORANGE_BOX_BG
	info_style.border_width_left = 1
	info_style.border_width_right = 1
	info_style.border_width_top = 1
	info_style.border_width_bottom = 1
	info_style.border_color = ORANGE_PRIMARY
	info_style.corner_radius_top_left = 16
	info_style.corner_radius_top_right = 16
	info_style.corner_radius_bottom_left = 16
	info_style.corner_radius_bottom_right = 16
	info_panel.add_theme_stylebox_override("panel", info_style)
	parent.add_child(info_panel)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.anchor_left = 0.0
	hbox.anchor_right = 1.0
	hbox.anchor_top = 0.5
	hbox.anchor_bottom = 0.5
	hbox.offset_left = 20
	hbox.offset_right = -20
	hbox.offset_top = -30  # Wyśrodkowanie pionowe
	hbox.offset_bottom = 30
	info_panel.add_child(hbox)
	
	# Icon container with offset for shadow
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(64, 54)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var time_big = TextureRect.new()
	time_big.texture = load(ICON_TIME_BIG)
	time_big.custom_minimum_size = Vector2(80, 80)
	time_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	time_big.anchor_right = 1.0
	time_big.anchor_bottom = 1.0
	time_big.offset_top = -17
	icon_container.add_child(time_big)
	hbox.add_child(icon_container)
	
	# Rich text label with bold
	var text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.custom_minimum_size = Vector2(0, 80)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_label.add_theme_font_size_override("normal_font_size", 20)
	text_label.add_theme_font_size_override("bold_font_size", 20)
	text_label.add_theme_color_override("default_color", TEXT_GOLD_DIM)
	
	text_label.text = "[b][color=#FFB900]Chrono Relics[/color][/b] bend time itself! Use them to [b][color=#FFFFFF]rewind turns[/color][/b] and turn defeat into victory."
	hbox.add_child(text_label)

func create_mega_bundle_box(parent: VBoxContainer):
	"""Mega bundle with special gradient background"""
	var bundle_panel = Panel.new()
	bundle_panel.custom_minimum_size = Vector2(0, 220)
	bundle_panel.clip_contents = true
	
	# Gradient background
	var gradient = Gradient.new()
	gradient.set_color(0, Color("2A2A40"))
	gradient.set_color(1, Color("1A1A28"))
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	
	var gradient_texture = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	gradient_texture.width = 600
	gradient_texture.height = 200
	
	var bg_rect = TextureRect.new()
	bg_rect.texture = gradient_texture
	bg_rect.anchor_right = 1.0
	bg_rect.anchor_bottom = 1.0
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.z_index = -1
	bundle_panel.add_child(bg_rect)
	
	# Border
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_width_left = 2
	border_style.border_width_right = 2
	border_style.border_width_top = 2
	border_style.border_width_bottom = 2
	border_style.border_color = ORANGE_BORDER
	border_style.corner_radius_top_left = 16
	border_style.corner_radius_top_right = 16
	border_style.corner_radius_bottom_left = 16
	border_style.corner_radius_bottom_right = 16
	bundle_panel.add_theme_stylebox_override("panel", border_style)
	parent.add_child(bundle_panel)
	
	# LIMITED badge (top left)
	var limited_badge = Panel.new()
	limited_badge.custom_minimum_size = Vector2(120, 32)
	limited_badge.position = Vector2(0, 0)
	
	var limited_style = StyleBoxFlat.new()
	limited_style.bg_color = ZAP_GREEN
	limited_style.corner_radius_top_left = 16
	limited_style.corner_radius_bottom_right = 16
	limited_badge.add_theme_stylebox_override("panel", limited_style)
	bundle_panel.add_child(limited_badge)
	
	var limited_hbox = HBoxContainer.new()
	limited_hbox.add_theme_constant_override("separation", 6)
	limited_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	limited_hbox.anchor_right = 1.0
	limited_hbox.anchor_bottom = 1.0
	limited_badge.add_child(limited_hbox)
	
	var zap_icon = TextureRect.new()
	zap_icon.texture = load(ICON_ZAP)
	zap_icon.custom_minimum_size = Vector2(20, 20)
	zap_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zap_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	limited_hbox.add_child(zap_icon)
	
	var limited_label = Label.new()
	limited_label.text = "LIMITED"
	limited_label.add_theme_font_size_override("font_size", 16)
	limited_label.add_theme_color_override("font_color", Color.WHITE)
	var font_bold = FontVariation.new()
	font_bold.set_variation_embolden(0.5)
	limited_label.add_theme_font_override("font", font_bold)
	limited_hbox.add_child(limited_label)
	
	# 75% OFF badge (top right)
	var discount_badge = Panel.new()
	discount_badge.custom_minimum_size = Vector2(120, 36)
	discount_badge.anchor_left = 1.0
	discount_badge.anchor_right = 1.0
	discount_badge.offset_left = -120
	discount_badge.offset_right = 0
	discount_badge.offset_top = 0
	
	var discount_style = StyleBoxFlat.new()
	discount_style.bg_color = RED_PRIMARY
	discount_style.border_width_left = 2
	discount_style.border_width_bottom = 2
	discount_style.border_color = RED_BORDER
	discount_style.corner_radius_top_right = 16
	discount_style.corner_radius_bottom_left = 16
	discount_badge.add_theme_stylebox_override("panel", discount_style)
	bundle_panel.add_child(discount_badge)
	
	var discount_label = Label.new()
	discount_label.text = "-75% OFF"
	discount_label.add_theme_font_size_override("font_size", 16)
	discount_label.add_theme_color_override("font_color", Color.WHITE)
	discount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discount_label.anchor_right = 1.0
	discount_label.anchor_bottom = 1.0
	var discount_bold = FontVariation.new()
	discount_bold.set_variation_embolden(0.5)
	discount_label.add_theme_font_override("font", discount_bold)
	discount_badge.add_child(discount_label)
	
	# Content HBox
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 24)
	content_hbox.anchor_left = 0.0
	content_hbox.anchor_right = 1.0
	content_hbox.anchor_top = 0.5
	content_hbox.anchor_bottom = 0.5
	content_hbox.offset_left = 20
	content_hbox.offset_right = -20
	content_hbox.offset_top = -60
	content_hbox.offset_bottom = 60
	bundle_panel.add_child(content_hbox)
	
	# Icon container with bouncing small icons
	var icon_area = Control.new()
	icon_area.custom_minimum_size = Vector2(150, 150)
	content_hbox.add_child(icon_area)
	
	var main_icon = TextureRect.new()
	main_icon.texture = load(ICON_TIME_MAIN)
	main_icon.custom_minimum_size = Vector2(150, 150)
	main_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	main_icon.anchor_left = 0.5
	main_icon.anchor_top = 0.5
	main_icon.anchor_right = 0.5
	main_icon.anchor_bottom = 0.5
	main_icon.offset_left = -100
	main_icon.offset_top = -74  # Offset for shadow + centering
	main_icon.offset_right = 100
	main_icon.offset_bottom = 95
	icon_area.add_child(main_icon)
	
	# Small bouncing icons on corners
	var small_icon1 = create_bouncing_icon(Vector2(0, 0), 1.0)
	icon_area.add_child(small_icon1)
	
	var small_icon2 = create_bouncing_icon(Vector2(110, 110), 1.6)  # Wolniejsza animacja, bez delay
	icon_area.add_child(small_icon2)
	
	# Text VBox
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 4)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_hbox.add_child(text_vbox)
	
	var title_label = Label.new()
	title_label.text = "MEGA BUNDLE"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	var title_bold = FontVariation.new()
	title_bold.set_variation_embolden(0.5)
	title_label.add_theme_font_override("font", title_bold)
	text_vbox.add_child(title_label)
	
	var amount_hbox = HBoxContainer.new()
	amount_hbox.add_theme_constant_override("separation", 8)
	amount_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	text_vbox.add_child(amount_hbox)
	
	var amount_label = Label.new()
	amount_label.text = "5,000"
	amount_label.add_theme_font_size_override("font_size", 32)
	amount_label.add_theme_color_override("font_color", TEXT_GOLD)
	var amount_bold = FontVariation.new()
	amount_bold.set_variation_embolden(0.5)
	amount_label.add_theme_font_override("font", amount_bold)
	amount_hbox.add_child(amount_label)
	
	var relic_label = Label.new()
	relic_label.text = "Chrono Relics"
	relic_label.add_theme_font_size_override("font_size", 18)
	relic_label.add_theme_color_override("font_color", Color(TEXT_GOLD, 0.7))
	relic_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	relic_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount_hbox.add_child(relic_label)
	
	var price_hbox = HBoxContainer.new()
	price_hbox.add_theme_constant_override("separation", 8)
	text_vbox.add_child(price_hbox)
	
	# Strikethrough price using Label with custom draw
	var old_price_container = Control.new()
	old_price_container.custom_minimum_size = Vector2(80, 30)
	price_hbox.add_child(old_price_container)
	
	var old_price = Label.new()
	old_price.text = "$19.99"
	old_price.add_theme_font_size_override("font_size", 22)
	old_price.add_theme_color_override("font_color", TEXT_SECONDARY)
	old_price.anchor_left = 0.0
	old_price.anchor_top = 0.5
	old_price.anchor_bottom = 0.5
	old_price.offset_top = -15
	old_price.offset_bottom = 15
	old_price_container.add_child(old_price)
	
	# Draw strikethrough line
	var line = ColorRect.new()
	line.color = TEXT_SECONDARY
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_top = -1
	line.offset_bottom = 1
	line.offset_right = -20
	old_price_container.add_child(line)
	
	var new_price = Label.new()
	new_price.text = "$4.99"
	new_price.add_theme_font_size_override("font_size", 28)
	new_price.add_theme_color_override("font_color", TEXT_GREEN)
	var price_bold = FontVariation.new()
	price_bold.set_variation_embolden(0.5)
	new_price.add_theme_font_override("font", price_bold)
	price_hbox.add_child(new_price)
	
	# Buy button
	var buy_button = create_buy_button()
	buy_button.custom_minimum_size = Vector2(140, 70)
	content_hbox.add_child(buy_button)

func create_bouncing_icon(pos: Vector2, duration: float = 1.0) -> TextureRect:
	"""Creates a bouncing small icon"""
	var icon = TextureRect.new()
	icon.texture = load(ICON_TIME_SMALL)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = pos
	
	# Bounce animation - continuous, no pauses
	var tween = create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(icon, "position:y", pos.y - 15, duration)
	tween.tween_property(icon, "position:y", pos.y, duration)
	
	return icon

func create_buy_button() -> TextureButton:
	"""Creates buy button with hover effect"""
	var btn = TextureButton.new()
	btn.texture_normal = load(ICON_BUY)
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.ignore_texture_size = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = Vector2(70, 35)  # Center pivot
	
	# Hover effect
	btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "modulate", Color(1.3, 1.2, 1.0), 0.2)
		tween.parallel().tween_property(btn, "scale", Vector2(1.05, 1.05), 0.2)
	)
	
	btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "modulate", Color.WHITE, 0.2)
		tween.parallel().tween_property(btn, "scale", Vector2.ONE, 0.2)
	)
	
	return btn

func create_small_purchase_boxes(parent: VBoxContainer):
	"""Creates 3 small purchase boxes in a row"""
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	
	# Box 1: 100 for $0.99
	create_small_box(hbox, "100", "$0.99", "")
	
	# Box 2: 500 for $4.99 with +10% BONUS
	create_small_box(hbox, "500", "$4.99", "+10% BONUS")
	
	# Box 3: 1200 for $9.99 with +20% BONUS
	create_small_box(hbox, "1200", "$9.99", "+20% BONUS")

func create_small_box(parent: HBoxContainer, amount: String, price: String, bonus: String):
	"""Creates single small purchase box"""
	var box_container = Control.new()
	box_container.custom_minimum_size = Vector2(0, 240)
	box_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box_container)
	
	# Bonus badge (if exists)
	if bonus != "":
		var badge = Panel.new()
		badge.custom_minimum_size = Vector2(120, 28)
		badge.position = Vector2(30, -14)
		badge.anchor_left = 0.5
		badge.anchor_top = 0.0
		badge.anchor_right = 0.5
		badge.anchor_bottom = 0.0
		badge.offset_left = -60
		badge.offset_right = 60
		badge.offset_top = -14
		badge.offset_bottom = 14
		badge.z_index = 10  # Above box
		
		var badge_style = StyleBoxFlat.new()
		badge_style.bg_color = GREEN_PRIMARY
		badge_style.corner_radius_top_left = 14
		badge_style.corner_radius_top_right = 14
		badge_style.corner_radius_bottom_left = 14
		badge_style.corner_radius_bottom_right = 14
		badge.add_theme_stylebox_override("panel", badge_style)
		box_container.add_child(badge)
		
		var badge_label = Label.new()
		badge_label.text = bonus
		badge_label.add_theme_font_size_override("font_size", 16)
		badge_label.add_theme_color_override("font_color", Color.WHITE)
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_label.anchor_right = 1.0
		badge_label.anchor_bottom = 1.0
		var badge_bold = FontVariation.new()
		badge_bold.set_variation_embolden(0.5)
		badge_label.add_theme_font_override("font", badge_bold)
		badge.add_child(badge_label)
	
	# Main box
	var box = Panel.new()
	box.custom_minimum_size = Vector2(0, 240)
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = PANEL_BG
	box_style.border_width_left = 1
	box_style.border_width_right = 1
	box_style.border_width_top = 1
	box_style.border_width_bottom = 1
	box_style.border_color = PANEL_BORDER
	box_style.corner_radius_top_left = 16
	box_style.corner_radius_top_right = 16
	box_style.corner_radius_bottom_left = 16
	box_style.corner_radius_bottom_right = 16
	box.add_theme_stylebox_override("panel", box_style)
	box.set_meta("normal_style", box_style)
	
	# Hover style
	var hover_style = box_style.duplicate()
	hover_style.border_color = Color(ORANGE_PRIMARY, 0.6)
	box.set_meta("hover_style", hover_style)
	
	box.mouse_entered.connect(func():
		box.add_theme_stylebox_override("panel", hover_style)
	)
	
	box.mouse_exited.connect(func():
		box.add_theme_stylebox_override("panel", box_style)
	)
	
	box_container.add_child(box)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = -90
	vbox.offset_bottom = 90
	box.add_child(vbox)
	
	# Icon container with shadow offset - BIGGER
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(120, 80)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var icon = TextureRect.new()
	icon.texture = load(ICON_TIME_SQUARE)
	icon.custom_minimum_size = Vector2(120, 120)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_left = 0.5
	icon.anchor_top = 0.0
	icon.anchor_right = 0.5
	icon.anchor_bottom = 1.0
	icon.offset_left = -60
	icon.offset_right = 60
	icon.offset_top = -10
	icon_container.add_child(icon)
	vbox.add_child(icon_container)
	
	var amount_label = Label.new()
	amount_label.text = amount
	amount_label.add_theme_font_size_override("font_size", 28)
	amount_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var amount_bold = FontVariation.new()
	amount_bold.set_variation_embolden(0.5)
	amount_label.add_theme_font_override("font", amount_bold)
	vbox.add_child(amount_label)
	
	var price_button = Button.new()
	price_button.text = price
	price_button.custom_minimum_size = Vector2(140, 48)
	price_button.focus_mode = Control.FOCUS_NONE
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = BUTTON_BG
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	btn_style.border_width_top = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = BUTTON_BORDER
	btn_style.corner_radius_top_left = 24
	btn_style.corner_radius_top_right = 24
	btn_style.corner_radius_bottom_left = 24
	btn_style.corner_radius_bottom_right = 24
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = BUTTON_HOVER
	
	price_button.add_theme_stylebox_override("normal", btn_style)
	price_button.add_theme_stylebox_override("hover", btn_hover)
	price_button.add_theme_stylebox_override("pressed", btn_hover)
	price_button.add_theme_font_size_override("font_size", 20)
	price_button.add_theme_color_override("font_color", TEXT_PRIMARY)
	var btn_bold = FontVariation.new()
	btn_bold.set_variation_embolden(0.5)
	price_button.add_theme_font_override("font", btn_bold)
	
	vbox.add_child(price_button)

func create_remove_ads_box(parent: VBoxContainer):
	"""Creates remove ads box"""
	var box = Panel.new()
	box.custom_minimum_size = Vector2(0, 120)
	
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = PANEL_BG
	box_style.border_width_left = 1
	box_style.border_width_right = 1
	box_style.border_width_top = 1
	box_style.border_width_bottom = 1
	box_style.border_color = PANEL_BORDER
	box_style.corner_radius_top_left = 16
	box_style.corner_radius_top_right = 16
	box_style.corner_radius_bottom_left = 16
	box_style.corner_radius_bottom_right = 16
	box.add_theme_stylebox_override("panel", box_style)
	parent.add_child(box)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.anchor_left = 0.0
	hbox.anchor_right = 1.0
	hbox.anchor_top = 0.5
	hbox.anchor_bottom = 0.5
	hbox.offset_left = 20  # Same as info box
	hbox.offset_right = -20
	hbox.offset_top = -30  # Centered vertically
	hbox.offset_bottom = 30
	box.add_child(hbox)
	
	# Icon container with shadow offset
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(100, 65)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var icon = TextureRect.new()
	icon.texture = load(ICON_NO_ADS)
	icon.custom_minimum_size = Vector2(100, 100)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_top = -7  # Shadow offset
	icon_container.add_child(icon)
	hbox.add_child(icon_container)
	
	# Text VBox - properly centered
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 4)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(text_vbox)
	
	var title_label = Label.new()
	title_label.text = "REMOVE ADS"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	var title_bold = FontVariation.new()
	title_bold.set_variation_embolden(0.5)
	title_label.add_theme_font_override("font", title_bold)
	text_vbox.add_child(title_label)
	
	var desc_label = Label.new()
	desc_label.text = "Play without interruptions forever!"
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	text_vbox.add_child(desc_label)
	
	# Price button - SMALL, FULLY ROUNDED
	var price_button = Button.new()
	price_button.text = "$4.99"
	price_button.custom_minimum_size = Vector2(100, 48)
	price_button.focus_mode = Control.FOCUS_NONE
	price_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color("009966")
	btn_style.border_width_bottom = 2
	btn_style.border_color = GREEN_DARK
	btn_style.corner_radius_top_left = 24  # Full rounded
	btn_style.corner_radius_top_right = 24
	btn_style.corner_radius_bottom_left = 24
	btn_style.corner_radius_bottom_right = 24
	btn_style.shadow_size = 6  # Subtle shadow
	btn_style.shadow_color = Color(GREEN_PRIMARY, 0.15)
	btn_style.shadow_offset = Vector2(0, 3)
	btn_style.content_margin_left = 16
	btn_style.content_margin_right = 16
	btn_style.content_margin_top = 8
	btn_style.content_margin_bottom = 8
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color("00BC7D")
	
	price_button.add_theme_stylebox_override("normal", btn_style)
	price_button.add_theme_stylebox_override("hover", btn_hover)
	price_button.add_theme_stylebox_override("pressed", btn_hover)
	price_button.add_theme_font_size_override("font_size", 22)
	price_button.add_theme_color_override("font_color", TEXT_PRIMARY)
	var btn_bold = FontVariation.new()
	btn_bold.set_variation_embolden(0.5)
	price_button.add_theme_font_override("font", btn_bold)
	
	hbox.add_child(price_button)

func setup_bottom_nav():
	"""Creates bottom navigation - copied from main_menu"""
	nav_container = HBoxContainer.new()
	nav_container.name = "NavContainer"
	nav_container.add_theme_constant_override("separation", 24)
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.set_meta("bottom_center", true)
	add_child(nav_container)
	
	# Navigation buttons (copied from main_menu.gd)
	var home_btn = create_nav_button("HOME", ICON_H1, Color("AD46FF", 0.3), Color("AD46FF"))
	nav_buttons["home"] = home_btn
	nav_container.add_child(home_btn)
	
	var levels_btn = create_nav_button("LEVELS", ICON_H2, Color("2B7FFF", 0.2), Color("2B7FFF"))
	nav_buttons["levels"] = levels_btn
	nav_container.add_child(levels_btn)
	
	var shop_btn = create_nav_button("SHOP", ICON_H3, Color("00BC7D", 0.3), Color("00BC7D"), true)
	nav_buttons["shop"] = shop_btn
	nav_container.add_child(shop_btn)
	
	var howto_btn = create_nav_button("HOW TO", ICON_H4, Color("FE9A00", 0.2), Color("FE9A00"))
	nav_buttons["howto"] = howto_btn
	nav_container.add_child(howto_btn)
	
	update_active_tab("shop")

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
	
	var style_normal = create_nav_button_style(border_color)
	var style_hover = create_nav_button_style(active_color)
	style_hover.shadow_size = 8
	style_hover.shadow_color = Color(active_color, 0.4)
	style_hover.shadow_offset = Vector2(0, 4)
	
	panel.add_theme_stylebox_override("panel", style_normal)
	panel.set_meta("style_normal", style_normal)
	panel.set_meta("style_hover", style_hover)
	panel.set_meta("style_active", style_hover)
	
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
		badge_style.bg_color = Color("FB2C36")
		badge_style.corner_radius_top_left = 14
		badge_style.corner_radius_top_right = 14
		badge_style.corner_radius_bottom_left = 14
		badge_style.corner_radius_bottom_right = 14
		badge.add_theme_stylebox_override("panel", badge_style)
		
		var badge_label = Label.new()
		badge_label.text = "75% OFF"
		badge_label.add_theme_font_size_override("font_size", 16)
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
	label.add_theme_color_override("font_color", Color("D1D5DC"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_container.add_child(label)
	
	btn.mouse_entered.connect(func(): _on_nav_hover(panel, true))
	btn.mouse_exited.connect(func(): _on_nav_hover(panel, false))
	
	btn.pressed.connect(func(): _on_nav_pressed(label_text.to_lower().replace(" ", "")))
	
	return btn

func create_nav_button_style(border_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("1A1A28")
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
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
	update_active_tab(tab_name)
	tab_changed.emit(tab_name)

func update_active_tab(tab_name: String):
	active_tab = tab_name
	
	for key in nav_buttons.keys():
		var container = nav_buttons[key]
		var panel = container.get_meta("panel")
		
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

func create_icon_button(icon_path: String, size: Vector2) -> Button:
	"""Creates rounded icon button IDENTICAL to main_menu"""
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

func _on_viewport_size_changed():
	var viewport_size = get_viewport().get_visible_rect().size
	
	for child in get_children():
		if child.has_meta("center_top"):
			child.position = Vector2(viewport_size.x / 2 - child.custom_minimum_size.x / 2, 20)
		
		if child.has_meta("right_top"):
			var shop_center_y = 20 + 96 / 2
			var currency_center_y = child.custom_minimum_size.y / 2
			child.position = Vector2(viewport_size.x - child.custom_minimum_size.x - 20, shop_center_y - currency_center_y)
		
		if child.has_meta("shop_content"):
			child.position = Vector2(20, 140)
			child.size = Vector2(viewport_size.x - 40, viewport_size.y - 360)
		
		if child.has_meta("bottom_center"):
			await get_tree().process_frame
			var container_width = child.size.x if child.size.x > 0 else 600
			child.position = Vector2(viewport_size.x / 2 - container_width / 2, viewport_size.y - 200)

func set_currency(amount: int):
	if currency_amount:
		currency_amount.text = str(amount)
		
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

func _on_info_pressed():
	"""Opens info/tutorial"""
	print("Info pressed")
