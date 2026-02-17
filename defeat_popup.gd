extends CanvasLayer
class_name DefeatPopup

# Colors
const BG_GRADIENT_TOP = Color("1F1F2E")
const BG_GRADIENT_BOTTOM = Color("15151F")
const BORDER_COLOR = Color("3A3A50")
const TOP_LINE_COLOR = Color("E7000B")
const LEVEL_COLOR = Color("FF6467")
const FALLEN_COLOR = Color("99A1AF")
const REWARD_BG = Color("12121A")
const REWARD_BORDER = Color("2A2A40")
const HOME_BG = Color("2A2A40")
const HOME_HOVER = Color("3A3A50")
const RETRY_BG = Color("E7000B")
const RETRY_HOVER = Color("FB2C36")
const HOME_TEXT = Color("D1D5DC")

# Box colors
const WATCH_BG = Color("2B7FFF", 0.2)
const WATCH_BORDER = Color("2B7FFF", 0.3)
const WATCH_BORDER_HOVER = Color("2B7FFF", 0.6)
const WATCH_TEXT = Color("51A2FF")
const USE_BG = Color("FE9A00", 0.2)
const USE_BORDER = Color("FE9A00", 0.3)
const USE_BORDER_HOVER = Color("FE9A00", 0.6)
const USE_TEXT = Color("FFB900")

# Paths
const SHADOW_PATH = "res://ui/defeat/shadowpanel.png"
const SKULL_PATH = "res://ui/defeat/skull.png"
const DEF_PATH = "res://ui/defeat/def.png"
const RET_PATH = "res://ui/defeat/ret.png"
const HOME_ICON = "res://ui/settings/home.png"
const RETRY_ICON = "res://ui/defeat/retry.png"
const WATCH_ICON = "res://ui/defeat/watch.png"
const TIME_ICON = "res://ui/time.png"

# Refs
var overlay: ColorRect
var popup_container: Control
var shadow: TextureRect
var main_panel: Panel
var watch_box: Panel
var use_box: Panel
var time_owned: int = 5  # Number of time rewinds owned

signal home_pressed
signal retry_pressed
signal watch_ad_pressed
signal rewind_2_turns_pressed

func _ready():
	# Set layer to be above everything (including UI)
	layer = 100
	setup_ui()
	# Show on game start for testing

func setup_ui():
	# === OVERLAY (blurred dark background) ===
	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	
	# === POPUP CONTAINER (centered) ===
	popup_container = Control.new()
	popup_container.name = "PopupContainer"
	popup_container.anchor_left = 0.5
	popup_container.anchor_top = 0.5
	popup_container.anchor_right = 0.5
	popup_container.anchor_bottom = 0.5
	popup_container.visible = false
	add_child(popup_container)
	
	# === SHADOW ===
	shadow = TextureRect.new()
	shadow.name = "Shadow"
	shadow.texture = load(SHADOW_PATH)
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shadow.custom_minimum_size = Vector2(800, 900)
	shadow.offset_left = -400
	shadow.offset_top = -450
	shadow.offset_right = 400
	shadow.offset_bottom = 450
	popup_container.add_child(shadow)
	
	# === MAIN PANEL ===
	main_panel = Panel.new()
	main_panel.name = "MainPanel"
	main_panel.custom_minimum_size = Vector2(480, 780)
	main_panel.offset_left = -240
	main_panel.offset_top = -390
	main_panel.offset_right = 240
	main_panel.offset_bottom = 390
	main_panel.clip_contents = true
	
	# Panel style with gradient background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_GRADIENT_TOP  # Fallback color
	panel_style.corner_radius_top_left = 32
	panel_style.corner_radius_top_right = 32
	panel_style.corner_radius_bottom_left = 32
	panel_style.corner_radius_bottom_right = 32
	main_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Background gradient using ColorRect
	var bg_rect = ColorRect.new()
	bg_rect.name = "Background"
	bg_rect.anchor_left = 0
	bg_rect.anchor_right = 1
	bg_rect.anchor_top = 0
	bg_rect.anchor_bottom = 1
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.z_index = -1
	
	# Simple gradient without shader (more reliable)
	var gradient = Gradient.new()
	gradient.set_color(0, BG_GRADIENT_TOP)
	gradient.set_color(1, BG_GRADIENT_BOTTOM)
	
	var gradient_texture = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	gradient_texture.width = 480
	gradient_texture.height = 780
	
	var texture_rect = TextureRect.new()
	texture_rect.texture = gradient_texture
	texture_rect.anchor_left = 0
	texture_rect.anchor_right = 1
	texture_rect.anchor_top = 0
	texture_rect.anchor_bottom = 1
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.z_index = -1
	
	main_panel.add_child(texture_rect)
	
	# Panel border (separate control)
	var border_panel = Panel.new()
	border_panel.name = "Border"
	border_panel.anchor_left = 0
	border_panel.anchor_right = 1
	border_panel.anchor_top = 0
	border_panel.anchor_bottom = 1
	border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_width_left = 1
	border_style.border_width_right = 1
	border_style.border_width_top = 1
	border_style.border_width_bottom = 1
	border_style.border_color = BORDER_COLOR
	border_style.corner_radius_top_left = 32
	border_style.corner_radius_top_right = 32
	border_style.corner_radius_bottom_left = 32
	border_style.corner_radius_bottom_right = 32
	border_panel.add_theme_stylebox_override("panel", border_style)
	main_panel.add_child(border_panel)
	
	popup_container.add_child(main_panel)
	
	# === TOP LINE (RED) ===
	var top_line = ColorRect.new()
	top_line.name = "TopLine"
	top_line.color = TOP_LINE_COLOR
	top_line.anchor_left = 0
	top_line.anchor_right = 1
	top_line.anchor_top = 0
	top_line.anchor_bottom = 0
	top_line.offset_left = 32  # Same as corner radius
	top_line.offset_right = -32  # Same as corner radius
	top_line.offset_bottom = 6
	top_line.z_index = 10
	main_panel.add_child(top_line)
	
	# === CONTENT VBOX ===
	var content = VBoxContainer.new()
	content.name = "Content"
	content.anchor_left = 0
	content.anchor_right = 1
	content.anchor_top = 0
	content.anchor_bottom = 1
	content.offset_left = 32
	content.offset_right = -40
	content.offset_top = 60
	content.offset_bottom = -40
	content.add_theme_constant_override("separation", 10)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	main_panel.add_child(content)
	
	# Skull icon (with negative margins to reduce whitespace)
	var skull_container = MarginContainer.new()
	skull_container.name = "SkullContainer"
	skull_container.add_theme_constant_override("margin_top", -80)
	skull_container.add_theme_constant_override("margin_bottom", -40)
	
	var skull = TextureRect.new()
	skull.name = "Skull"
	skull.texture = load(SKULL_PATH)
	skull.custom_minimum_size = Vector2(280, 280)
	skull.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	skull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skull.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skull_container.add_child(skull)
	
	content.add_child(skull_container)
	
	# Defeat image
	var def_img = TextureRect.new()
	def_img.name = "DefeatImage"
	def_img.texture = load(DEF_PATH)
	def_img.custom_minimum_size = Vector2(180, 45)
	def_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	def_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	def_img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(def_img)
	
	# "Your kingdom has fallen..." label (same style as "Completed")
	var spacer_fallen = Control.new()
	spacer_fallen.custom_minimum_size = Vector2(0, 0)  # 15px margines
	content.add_child(spacer_fallen)
	var fallen_label = Label.new()
	fallen_label.name = "FallenLabel"
	fallen_label.text = "Your kingdom has fallen..."
	fallen_label.add_theme_font_size_override("font_size", 24)
	fallen_label.add_theme_color_override("font_color", FALLEN_COLOR)
	fallen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(fallen_label)
	
	# Level label (smaller and red)
	var level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Level 1"
	level_label.add_theme_font_size_override("font_size", 28)
	level_label.add_theme_color_override("font_color", LEVEL_COLOR)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Add bold font
	var font_variation = FontVariation.new()
	font_variation.set_variation_embolden(0.5)
	level_label.add_theme_font_override("font", font_variation)
	
	content.add_child(level_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 5)
	content.add_child(spacer1)
	
	# === REWIND PANEL ===
	var rewind_panel = Panel.new()
	rewind_panel.name = "RewindPanel"
	rewind_panel.custom_minimum_size = Vector2(300, 240)
	
	var rewind_style = StyleBoxFlat.new()
	rewind_style.bg_color = REWARD_BG
	rewind_style.border_width_left = 1
	rewind_style.border_width_right = 1
	rewind_style.border_width_top = 1
	rewind_style.border_width_bottom = 1
	rewind_style.border_color = REWARD_BORDER
	rewind_style.corner_radius_top_left = 24
	rewind_style.corner_radius_top_right = 24
	rewind_style.corner_radius_bottom_left = 24
	rewind_style.corner_radius_bottom_right = 24
	rewind_panel.add_theme_stylebox_override("panel", rewind_style)
	
	content.add_child(rewind_panel)
	
	# Rewind VBox
	var rewind_vbox = VBoxContainer.new()
	rewind_vbox.anchor_left = 0
	rewind_vbox.anchor_right = 1
	rewind_vbox.anchor_top = 0
	rewind_vbox.anchor_bottom = 1
	rewind_vbox.offset_left = 20
	rewind_vbox.offset_right = -20
	rewind_vbox.offset_top = 0
	rewind_vbox.offset_bottom = 0
	rewind_vbox.add_theme_constant_override("separation", 16)
	rewind_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rewind_panel.add_child(rewind_vbox)
	
	# REWIND 2 TURNS label with icon
	var rewind_header = HBoxContainer.new()
	rewind_header.add_theme_constant_override("separation", 12)
	rewind_header.alignment = BoxContainer.ALIGNMENT_CENTER
	rewind_vbox.add_child(rewind_header)
	
	var ret_icon = TextureRect.new()
	ret_icon.texture = load(RET_PATH)
	ret_icon.custom_minimum_size = Vector2(28, 28)
	ret_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ret_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewind_header.add_child(ret_icon)
	
	var rewind_label = Label.new()
	rewind_label.text = "REWIND 2 TURNS"
	rewind_label.add_theme_font_size_override("font_size", 20)
	rewind_label.add_theme_color_override("font_color", FALLEN_COLOR)
	rewind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewind_header.add_child(rewind_label)
	
	# Grid container for 2 boxes
	var boxes_grid = HBoxContainer.new()
	boxes_grid.add_theme_constant_override("separation", 16)
	boxes_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	rewind_vbox.add_child(boxes_grid)
	
	# === WATCH AD BOX ===
	watch_box = create_option_box(
		WATCH_ICON,
		"Watch Ad",
		"FREE",
		WATCH_BG,
		WATCH_BORDER,
		WATCH_BORDER_HOVER,
		WATCH_TEXT
	)
	watch_box.gui_input.connect(_on_watch_box_gui_input)
	boxes_grid.add_child(watch_box)
	
	# === USE TIME BOX ===
	use_box = create_option_box_with_time(
		TIME_ICON,
		"Use",
		"(%d owned)" % time_owned,
		USE_BG,
		USE_BORDER,
		USE_BORDER_HOVER,
		USE_TEXT
	)
	use_box.gui_input.connect(_on_use_box_gui_input)
	boxes_grid.add_child(use_box)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	content.add_child(spacer2)
	
	# === BUTTONS ===
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.add_theme_constant_override("separation", 16)
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_hbox.custom_minimum_size = Vector2(360, 0)
	content.add_child(buttons_hbox)
	
	# Home button
	var home_btn = create_button("Home", HOME_ICON, HOME_BG, HOME_HOVER, HOME_TEXT, false)
	home_btn.pressed.connect(_on_home_pressed)
	buttons_hbox.add_child(home_btn)
	
	# Retry button
	var retry_btn = create_button("Retry", RETRY_ICON, RETRY_BG, RETRY_HOVER, Color.WHITE, false)
	retry_btn.pressed.connect(_on_retry_pressed)
	buttons_hbox.add_child(retry_btn)

func create_option_box(icon_path: String, title: String, subtitle: String, 
		bg_color: Color, border_color: Color, border_hover: Color, text_color: Color) -> Panel:
	var box = Panel.new()
	box.custom_minimum_size = Vector2(170, 150)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = border_color
	style_normal.corner_radius_top_left = 16
	style_normal.corner_radius_top_right = 16
	style_normal.corner_radius_bottom_left = 16
	style_normal.corner_radius_bottom_right = 16
	box.add_theme_stylebox_override("panel", style_normal)
	
	# Store hover colors for manual hover effect
	box.set_meta("border_normal", border_color)
	box.set_meta("border_hover", border_hover)
	box.set_meta("text_color", text_color)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.anchor_left = 0
	vbox.anchor_right = 1
	vbox.anchor_top = 0
	vbox.anchor_bottom = 1
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vbox)
	
	# Icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)
	
	# Title
	var title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", text_color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var font_var = FontVariation.new()
	font_var.set_variation_embolden(0.5)
	title_label.add_theme_font_override("font", font_var)
	
	vbox.add_child(title_label)
	
	# Subtitle
	var subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 16)
	var subtitle_color = Color(text_color, 0.6)
	subtitle_label.add_theme_color_override("font_color", subtitle_color)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle_label)
	
	# Mouse enter/exit for hover effect
	box.mouse_entered.connect(func(): _on_box_hover(box, true))
	box.mouse_exited.connect(func(): _on_box_hover(box, false))
	
	return box

func create_option_box_with_time(icon_path: String, title: String, subtitle: String, 
		bg_color: Color, border_color: Color, border_hover: Color, text_color: Color) -> Panel:
	var box = Panel.new()
	box.custom_minimum_size = Vector2(170, 150)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = border_color
	style_normal.corner_radius_top_left = 16
	style_normal.corner_radius_top_right = 16
	style_normal.corner_radius_bottom_left = 16
	style_normal.corner_radius_bottom_right = 16
	box.add_theme_stylebox_override("panel", style_normal)
	
	# Store hover colors
	box.set_meta("border_normal", border_color)
	box.set_meta("border_hover", border_hover)
	box.set_meta("text_color", text_color)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.anchor_left = 0
	vbox.anchor_right = 1
	vbox.anchor_top = 0
	vbox.anchor_bottom = 1
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vbox)
	
	# Icon + x2 HBox
	var icon_hbox = HBoxContainer.new()
	icon_hbox.add_theme_constant_override("separation", 8)
	icon_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_hbox)
	
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_hbox.add_child(icon)
	
	var x2_label = Label.new()
	x2_label.name = "X2Label"
	x2_label.text = "x2"
	x2_label.add_theme_font_size_override("font_size", 24)
	x2_label.add_theme_color_override("font_color", text_color)
	
	var x2_font_var = FontVariation.new()
	x2_font_var.set_variation_embolden(0.5)
	x2_label.add_theme_font_override("font", x2_font_var)
	
	icon_hbox.add_child(x2_label)
	
	# Title
	var title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", text_color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var font_var = FontVariation.new()
	font_var.set_variation_embolden(0.5)
	title_label.add_theme_font_override("font", font_var)
	
	vbox.add_child(title_label)
	
	# Subtitle
	var subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 16)
	var subtitle_color = Color(text_color, 0.6)
	subtitle_label.add_theme_color_override("font_color", subtitle_color)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle_label)
	
	# Mouse enter/exit for hover effect
	box.mouse_entered.connect(func(): _on_box_hover(box, true))
	box.mouse_exited.connect(func(): _on_box_hover(box, false))
	
	return box

func _on_box_hover(box: Panel, is_hovering: bool):
	var border_normal = box.get_meta("border_normal")
	var border_hover = box.get_meta("border_hover")
	var text_color = box.get_meta("text_color")
	
	var style = box.get_theme_stylebox("panel").duplicate()
	style.border_color = border_hover if is_hovering else border_normal
	box.add_theme_stylebox_override("panel", style)
	
	# Brighten icon and title
	var vbox = box.get_node("Content")
	
	# DODAJ SPRAWDZENIE:
	if not vbox:
		return
		
	var icon = vbox.get_node("Icon")
	var title = vbox.get_node("Title")
	
	# DODAJ SPRAWDZENIA:
	if not icon or not title:
		return
	
	if is_hovering:
		icon.modulate = Color(1.3, 1.3, 1.3)
		title.add_theme_color_override("font_color", Color(text_color.r * 1.2, text_color.g * 1.2, text_color.b * 1.2))
	else:
		icon.modulate = Color.WHITE
		title.add_theme_color_override("font_color", text_color)

func _on_watch_box_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_node("/root/Main").play_btn_sound()
		_show_rewarded_ad()
		
func _show_rewarded_ad():
	var admob = get_node_or_null("/root/AdMobManager")
	if not admob:
		print("AdMobManager nie znaleziony")
		return
	# Podłącz sygnały jednorazowo
	if not admob.rewarded_ad_completed.is_connected(_on_rewarded_completed):
		admob.rewarded_ad_completed.connect(_on_rewarded_completed, CONNECT_ONE_SHOT)
	if not admob.rewarded_ad_failed.is_connected(_on_rewarded_failed):
		admob.rewarded_ad_failed.connect(_on_rewarded_failed, CONNECT_ONE_SHOT)

	admob.show_rewarded()
	
func _on_rewarded_completed():
	print("Rewarded obejrzany - cofamy 2 tury!")
	# Tutaj emitujesz sygnał który hex_grid obsługuje:
	watch_ad_pressed.emit()
	hide_popup()
	
func _on_rewarded_failed():
	print("Reklama niedostepna - sprobuj pozniej")

func _on_use_box_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		rewind_2_turns_pressed.emit()

func create_button(text: String, icon_path: String, bg_color: Color, hover_color: Color, text_color: Color, icon_right: bool = false) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(200, 82)
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = BORDER_COLOR
	style_normal.corner_radius_top_left = 41
	style_normal.corner_radius_top_right = 41
	style_normal.corner_radius_bottom_left = 41
	style_normal.corner_radius_bottom_right = 41
	style_normal.content_margin_left = 28
	style_normal.content_margin_right = 28
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = hover_color
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	
	# HBox for icon + text
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.anchor_left = 0
	hbox.anchor_right = 1
	hbox.anchor_top = 0
	hbox.anchor_bottom = 1
	hbox.offset_left = 28
	hbox.offset_right = -28
	btn.add_child(hbox)
	
	# Icon on left
	var icon = TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", text_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)
	
	return btn

func show_defeat(level: int):
	"""Shows defeat popup with animation (no confetti)"""
	get_node("/root/Main").play_defeat_sound()
	# Update level text
	var level_label = main_panel.get_node("Content/LevelLabel")
	if level_label:
		level_label.text = "Level %d" % level
	
	# NOWE: Sprawdź dostępność rewindów i ustaw stan boxów
	update_rewind_boxes_state()
	
	# Show overlay and container
	overlay.visible = true
	popup_container.visible = true
	
	# Start with scale 0
	popup_container.scale = Vector2.ZERO
	
	# Animate popup scale
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ONE, 0.6)
	
	# Animate skull bounce (subtle scale pulse)
	var skull_container = main_panel.get_node("Content/SkullContainer")
	if skull_container:
		var skull = skull_container.get_node("Skull")
		if skull:
			skull.scale = Vector2(0.8, 0.8)
			var skull_tween = create_tween()
			skull_tween.set_ease(Tween.EASE_OUT)
			skull_tween.set_trans(Tween.TRANS_BOUNCE)
			skull_tween.tween_property(skull, "scale", Vector2(1.0, 1.0), 0.8).set_delay(0.4)

func hide_popup():
	"""Hides the popup with animation"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ZERO, 0.4)
	tween.finished.connect(func():
		overlay.visible = false
		popup_container.visible = false
	)

func _on_home_pressed():
	get_node("/root/Main").play_btn_sound()
	home_pressed.emit()
	hide_popup()

func _on_retry_pressed():
	get_node("/root/Main").play_btn_sound()
	retry_pressed.emit()
	hide_popup()

func update_rewind_boxes_state():
	"""Aktualizuje stan use_box (niebieski) na podstawie dostępnych rewindów"""
	if not use_box:
		print("WARNING: use_box nie istnieje")
		return
	
	# Pobierz hex_grid z rodzica
	var hex_grid = get_parent()
	if not hex_grid:
		print("WARNING: Nie można znaleźć hex_grid (parent)")
		use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_box.modulate = Color(0.5, 0.5, 0.5, 0.5)
		return
	
	# UIManager może być w dzieciach hex_grid (nie has_node)
	var ui_manager = null
	for child in hex_grid.get_children():
		if child is UIManager:
			ui_manager = child
			break
	
	if not ui_manager:
		print("WARNING: Nie można znaleźć UIManager w hex_grid")
		use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_box.modulate = Color(0.5, 0.5, 0.5, 0.5)
		return
	
	if not ui_manager.rewind_counter:
		print("WARNING: Brak rewind_counter w UIManager")
		use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_box.modulate = Color(0.5, 0.5, 0.5, 0.5)
		return
	
	var rewind_label = ui_manager.rewind_counter.get_node_or_null("RewindLabel")
	
	if not rewind_label:
		print("WARNING: Brak RewindLabel")
		use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_box.modulate = Color(0.5, 0.5, 0.5, 0.5)
		return
	
	var current_rewinds = int(rewind_label.text)
	print("DEBUG: Sprawdzam rewindy - current: %d, needed: 2" % current_rewinds)
	
	# Box aktywny tylko gdy mamy >= 2 rewindy
	if current_rewinds >= 2:
		use_box.mouse_filter = Control.MOUSE_FILTER_PASS
		use_box.modulate = Color.WHITE
		print("Use Time box: ENABLED (rewinds: %d)" % current_rewinds)
	else:
		use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_box.modulate = Color(0.5, 0.5, 0.5, 0.5)
		print("Use Time box: DISABLED (rewinds: %d, need 2)" % current_rewinds)
	
	# Watch box zawsze aktywny
	if watch_box:
		watch_box.mouse_filter = Control.MOUSE_FILTER_PASS
		watch_box.modulate = Color.WHITE
