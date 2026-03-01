extends CanvasLayer
class_name RatePopup

# === COLORS ===
const BG_GRADIENT_TOP    = Color("1F1F2E")
const BG_GRADIENT_BOTTOM = Color("15151F")
const BORDER_COLOR       = Color("3A3A50")
const TOP_LINE_COLOR     = Color("FE9A00")
const TITLE_COLOR        = Color("FFB900")
const SUBTITLE_COLOR     = Color("99A1AF")
const BUTTON_BG          = Color("2A2A40")
const BUTTON_HOVER       = Color("3A3A50")
const RATE_BTN_BG        = Color("009966")
const RATE_BTN_HOVER     = Color("00BC7D")
const STAR_COLOR         = Color("FFB900")
const NO_THANKS_COLOR    = Color("99A1AF")
const NO_THANKS_HOVER    = Color("D1D5DC")

# === PATHS ===
const RATE_IMG_PATH  = "res://ui/rate.png"
const STAR_ICON_PATH = "res://ui/star.png"

# === REFS ===
var overlay: ColorRect
var popup_container: Control
var main_panel: Panel

# ─────────────────────────────────────────────
func _ready():
	layer = 200
	_build_ui()

# ─────────────────────────────────────────────
#  LOGIC: should we show the popup?
# ─────────────────────────────────────────────
static func should_show(main_node: Node) -> bool:
	if main_node.get("review_done") == true:
		return false

	var completed: Array = main_node.get("completed_levels") as Array
	if completed.size() == 0:
		return false
	var max_lvl = completed.max()
	if max_lvl < 5:
		return false

	var last_date: String = main_node.get("review_last_date") if main_node.get("review_last_date") != null else ""
	if last_date == "":
		return true

	var today_dict = Time.get_date_dict_from_system()
	var last_dict  = Time.get_datetime_dict_from_datetime_string(last_date + "T00:00:00", false)

	var today_days = today_dict["year"] * 365 + today_dict["month"] * 30 + today_dict["day"]
	var last_days  = last_dict["year"]  * 365 + last_dict["month"]  * 30 + last_dict["day"]

	return (today_days - last_days) >= 3

# ─────────────────────────────────────────────
#  SHOW / HIDE
# ─────────────────────────────────────────────
func show_popup():
	overlay.visible = true
	popup_container.visible = true
	popup_container.scale = Vector2.ZERO

	var main = get_node_or_null("/root/Main")
	if main:
		main.set("review_last_date", Time.get_date_string_from_system())
		if main.has_method("save_game_data"):
			main.save_game_data()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ONE, 0.5)

func hide_popup():
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ZERO, 0.35)
	tween.finished.connect(func():
		overlay.visible = false
		popup_container.visible = false
		queue_free()
	)

# ─────────────────────────────────────────────
#  BUTTON HANDLERS
# ─────────────────────────────────────────────
func _on_rate_pressed():
	_play_sound()
	var main = get_node_or_null("/root/Main")
	if main:
		main.set("review_done", true)
		if main.has_method("save_game_data"):
			main.save_game_data()
	# Android — replace with your package name:
	OS.shell_open("market://details?id=com.your.game")
	# iOS — uncomment and replace ID:
	# OS.shell_open("https://apps.apple.com/app/idXXXXXX")
	hide_popup()

func _on_later_pressed():
	_play_sound()
	hide_popup()

func _on_no_pressed():
	_play_sound()
	var main = get_node_or_null("/root/Main")
	if main:
		main.set("review_done", true)
		if main.has_method("save_game_data"):
			main.save_game_data()
	hide_popup()

func _play_sound():
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("play_btn_sound"):
		main.play_btn_sound()

# ─────────────────────────────────────────────
#  BUILD UI
# ─────────────────────────────────────────────
func _build_ui():
	# --- Overlay ---
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0; overlay.anchor_top = 0
	overlay.anchor_right = 1; overlay.anchor_bottom = 1
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	# --- Popup container ---
	popup_container = Control.new()
	popup_container.anchor_left   = 0.5; popup_container.anchor_top    = 0.5
	popup_container.anchor_right  = 0.5; popup_container.anchor_bottom = 0.5
	popup_container.visible = false
	add_child(popup_container)

	# --- Main panel ---
	main_panel = Panel.new()
	main_panel.custom_minimum_size = Vector2(440, 410)
	main_panel.offset_left  = -210; main_panel.offset_right  = 210
	main_panel.offset_top   = -195; main_panel.offset_bottom = 235
	main_panel.clip_contents = true

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_GRADIENT_TOP
	panel_style.corner_radius_top_left    = 32; panel_style.corner_radius_top_right    = 32
	panel_style.corner_radius_bottom_left = 32; panel_style.corner_radius_bottom_right = 32
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Gradient background
	var gradient = Gradient.new()
	gradient.set_color(0, BG_GRADIENT_TOP)
	gradient.set_color(1, BG_GRADIENT_BOTTOM)
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.fill_from = Vector2(0, 0); grad_tex.fill_to = Vector2(0, 1)
	grad_tex.width = 420; grad_tex.height = 450
	var bg_tex = TextureRect.new()
	bg_tex.texture = grad_tex
	bg_tex.anchor_left = 0; bg_tex.anchor_right = 1
	bg_tex.anchor_top = 0;  bg_tex.anchor_bottom = 1
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_tex.z_index = -1
	main_panel.add_child(bg_tex)

	# Border
	var border = Panel.new()
	border.anchor_left = 0; border.anchor_right = 1
	border.anchor_top = 0;  border.anchor_bottom = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_width_left = 1; border_style.border_width_right  = 1
	border_style.border_width_top  = 1; border_style.border_width_bottom = 1
	border_style.border_color = BORDER_COLOR
	border_style.corner_radius_top_left    = 32; border_style.corner_radius_top_right    = 32
	border_style.corner_radius_bottom_left = 32; border_style.corner_radius_bottom_right = 32
	border.add_theme_stylebox_override("panel", border_style)
	main_panel.add_child(border)

	popup_container.add_child(main_panel)

	# Top orange line
	var top_line = ColorRect.new()
	top_line.color = TOP_LINE_COLOR
	top_line.anchor_left = 0; top_line.anchor_right  = 1
	top_line.anchor_top  = 0; top_line.anchor_bottom = 0
	top_line.offset_left = 32; top_line.offset_right = -32
	top_line.offset_bottom = 6
	top_line.z_index = 10
	main_panel.add_child(top_line)

	# --- Content VBox ---
	var content = VBoxContainer.new()
	content.anchor_left  = 0; content.anchor_right  = 1
	content.anchor_top   = 0; content.anchor_bottom = 1
	content.offset_left  = 28; content.offset_right  = -28
	content.offset_top   = 36; content.offset_bottom = -20
	content.add_theme_constant_override("separation", 16)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	main_panel.add_child(content)

	# Stars image — larger
	var stars_img = TextureRect.new()
	if ResourceLoader.exists(RATE_IMG_PATH):
		stars_img.texture = load(RATE_IMG_PATH)
	stars_img.modulate = STAR_COLOR
	stars_img.custom_minimum_size = Vector2(200, 60)
	stars_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	stars_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stars_img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(stars_img)

	# Title
	var title = Label.new()
	title.text = "Enjoying the game?"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bold_font = FontVariation.new()
	bold_font.set_variation_embolden(0.5)
	title.add_theme_font_override("font", bold_font)
	content.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Your review helps us a lot!\nIt only takes a moment."
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(subtitle)

	# Spacer
	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	content.add_child(sp)

	# === Row: Rate Now + Maybe Later side by side ===
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(btn_row)

	var rate_btn = _make_button("Rate Now", RATE_BTN_BG, RATE_BTN_HOVER, Color.WHITE, 190, STAR_ICON_PATH)
	rate_btn.pressed.connect(_on_rate_pressed)
	btn_row.add_child(rate_btn)

	var later_btn = _make_button("Maybe Later", BUTTON_BG, BUTTON_HOVER, SUBTITLE_COLOR, 175, "")
	later_btn.pressed.connect(_on_later_pressed)
	btn_row.add_child(later_btn)

	# === "No, thanks" — plain label, no button background ===
	var no_label = Label.new()
	no_label.text = "No, thanks"
	no_label.add_theme_font_size_override("font_size", 19)
	no_label.add_theme_color_override("font_color", NO_THANKS_COLOR)
	no_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_label.mouse_filter = Control.MOUSE_FILTER_STOP
	no_label.mouse_entered.connect(func():
		no_label.add_theme_color_override("font_color", NO_THANKS_HOVER)
	)
	no_label.mouse_exited.connect(func():
		no_label.add_theme_color_override("font_color", NO_THANKS_COLOR)
	)
	no_label.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_no_pressed()
	)
	content.add_child(no_label)

func _make_button(text: String, bg: Color, hover: Color, text_color: Color, width: int, icon_path: String = "") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 72)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_constant_override("h_separation", 4)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_tex = load(icon_path)
		btn.icon = icon_tex
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_constant_override("icon_max_width", 28)
		# Tint black icon to white/gold to match button
		btn.add_theme_color_override("icon_normal_color", STAR_COLOR)
		btn.add_theme_color_override("icon_hover_color", STAR_COLOR)
		btn.add_theme_color_override("icon_pressed_color", STAR_COLOR)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)

	var bold = FontVariation.new()
	bold.set_variation_embolden(0.3)
	btn.add_theme_font_override("font", bold)

	var s_normal = StyleBoxFlat.new()
	s_normal.bg_color = bg
	s_normal.corner_radius_top_left    = 999; s_normal.corner_radius_top_right    = 999
	s_normal.corner_radius_bottom_left = 999; s_normal.corner_radius_bottom_right = 999
	s_normal.border_width_left = 1; s_normal.border_width_right  = 1
	s_normal.border_width_top  = 1; s_normal.border_width_bottom = 1
	s_normal.border_color = BORDER_COLOR
	s_normal.content_margin_left = 18
	s_normal.content_margin_right = 18
	s_normal.content_margin_top = 8
	s_normal.content_margin_bottom = 8

	var s_hover = s_normal.duplicate()
	s_hover.bg_color = hover

	btn.add_theme_stylebox_override("normal",  s_normal)
	btn.add_theme_stylebox_override("hover",   s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	return btn
