extends CanvasLayer
class_name VictoryPopup

# Colors
const BG_GRADIENT_TOP = Color("1F1F2E")
const BG_GRADIENT_BOTTOM = Color("15151F")
const BORDER_COLOR = Color("3A3A50")
const TOP_LINE_COLOR = Color("FE9A00")
const LEVEL_COLOR = Color("FFB900")
const COMPLETED_COLOR = Color("99A1AF")
const REWARD_BG = Color("12121A")
const REWARD_BORDER = Color("2A2A40")
const HOME_BG = Color("2A2A40")
const HOME_HOVER = Color("3A3A50")
const NEXT_BG = Color("009966")
const NEXT_HOVER = Color("00BC7D")
const HOME_TEXT = Color("D1D5DC")

# Paths
const SHADOW_PATH = "res://ui/victory/shadowpanel.png"
const CROWN_PATH = "res://ui/victory/crown.png"
const VIC_PATH = "res://ui/victory/vic.png"
const RELIC_PATH = "res://ui/shop/timeSquare.png"
const HOME_ICON = "res://ui/settings/home.png"
const NEXT_ICON = "res://ui/victory/next.png"

# Progress tracking
const PROGRESS_PATH = "res://levels/level_progress.json"

# Refs
var overlay: ColorRect
var popup_container: Control
var shadow: TextureRect
var main_panel: Panel
var confetti_particles: Array = []
var relic_textures: Array = []
var current_level: int = 0

signal home_pressed
signal next_pressed

func _ready():
	# Set layer to be above everything (including UI)
	layer = 100
	setup_ui()

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
	main_panel.custom_minimum_size = Vector2(480, 760)
	main_panel.offset_left = -240
	main_panel.offset_top = -380
	main_panel.offset_right = 240
	main_panel.offset_bottom = 380
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
	gradient_texture.height = 760
	
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
	
	# === TOP LINE ===
	var top_line = ColorRect.new()
	top_line.name = "TopLine"
	top_line.color = TOP_LINE_COLOR
	top_line.anchor_left = 0
	top_line.anchor_right = 1
	top_line.anchor_top = 0
	top_line.anchor_bottom = 0
	top_line.offset_left = 32
	top_line.offset_right = -32
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
	
	# Crown icon
	var crown_container = MarginContainer.new()
	crown_container.name = "CrownContainer"
	crown_container.add_theme_constant_override("margin_top", -80)
	crown_container.add_theme_constant_override("margin_bottom", -40)
	
	var crown = TextureRect.new()
	crown.name = "Crown"
	crown.texture = load(CROWN_PATH)
	crown.custom_minimum_size = Vector2(280, 280)
	crown.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crown_container.add_child(crown)
	
	content.add_child(crown_container)
	
	# Victory image
	var vic_img = TextureRect.new()
	vic_img.name = "VictoryImage"
	vic_img.texture = load(VIC_PATH)
	vic_img.custom_minimum_size = Vector2(180, 45)
	vic_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	vic_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vic_img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(vic_img)
	
	# Level label
	var level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Level 1"
	level_label.add_theme_font_size_override("font_size", 32)
	level_label.add_theme_color_override("font_color", LEVEL_COLOR)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var font_variation = FontVariation.new()
	font_variation.set_variation_embolden(0.5)
	level_label.add_theme_font_override("font", font_variation)
	
	content.add_child(level_label)
	
	# Completed label
	var completed_label = Label.new()
	completed_label.name = "CompletedLabel"
	completed_label.text = "Completed"
	completed_label.add_theme_font_size_override("font_size", 24)
	completed_label.add_theme_color_override("font_color", COMPLETED_COLOR)
	completed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(completed_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	content.add_child(spacer1)
	
	# === REWARD PANEL ===
	var reward_panel = Panel.new()
	reward_panel.name = "RewardPanel"
	reward_panel.custom_minimum_size = Vector2(360, 200)
	reward_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var reward_style = StyleBoxFlat.new()
	reward_style.bg_color = REWARD_BG
	reward_style.border_width_left = 2
	reward_style.border_width_right = 2
	reward_style.border_width_top = 2
	reward_style.border_width_bottom = 2
	reward_style.border_color = REWARD_BORDER
	reward_style.corner_radius_top_left = 20
	reward_style.corner_radius_top_right = 20
	reward_style.corner_radius_bottom_left = 20
	reward_style.corner_radius_bottom_right = 20
	reward_panel.add_theme_stylebox_override("panel", reward_style)
	
	content.add_child(reward_panel)
	
	var reward_vbox = VBoxContainer.new()
	reward_vbox.anchor_left = 0
	reward_vbox.anchor_right = 1
	reward_vbox.anchor_top = 0
	reward_vbox.anchor_bottom = 1
	reward_vbox.add_theme_constant_override("separation", 16)
	reward_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_panel.add_child(reward_vbox)
	
	# REWARD label
	var reward_label = Label.new()
	reward_label.text = "REWARD"
	reward_label.add_theme_font_size_override("font_size", 20)
	reward_label.add_theme_color_override("font_color", COMPLETED_COLOR)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_vbox.add_child(reward_label)
	
	# Relics HBox
	var relics_hbox = HBoxContainer.new()
	relics_hbox.add_theme_constant_override("separation", -10)
	relics_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_vbox.add_child(relics_hbox)
	
	# 3 relics
	relic_textures.clear()
	for i in range(3):
		# Pivot control — animujemy scale/modulate tutaj
		# height 80 = 120 - 40, żeby layout widział je tak samo jak MarginContainer z margin_bottom -40
		var pivot = Control.new()
		pivot.custom_minimum_size = Vector2(120, 80)
		pivot.modulate.a = 0.0
		pivot.clip_contents = false
		
		var relic = TextureRect.new()
		relic.texture = load(RELIC_PATH)
		relic.custom_minimum_size = Vector2(120, 120)
		relic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		relic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pivot.add_child(relic)
		
		relics_hbox.add_child(pivot)
		relic_textures.append(pivot)
	
	# Relic count label
	var count_label = Label.new()
	count_label.text = "Chrono Relic ×3"
	count_label.add_theme_font_size_override("font_size", 24)
	count_label.add_theme_color_override("font_color", LEVEL_COLOR)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_vbox.add_child(count_label)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	content.add_child(spacer2)
	
	# === BUTTONS ===
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.add_theme_constant_override("separation", 16)
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_hbox.custom_minimum_size = Vector2(360, 0)
	content.add_child(buttons_hbox)
	
	# Home button
	var home_btn = create_button("Home", HOME_ICON, HOME_BG, HOME_HOVER, HOME_TEXT)
	home_btn.pressed.connect(_on_home_pressed)
	buttons_hbox.add_child(home_btn)
	
	# Next button
	var next_btn = create_button("Next", NEXT_ICON, NEXT_BG, NEXT_HOVER, Color.WHITE)
	next_btn.pressed.connect(_on_next_pressed)
	buttons_hbox.add_child(next_btn)

func create_button(text: String, icon_path: String, bg_color: Color, hover_color: Color, text_color: Color) -> Button:
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
	
	var is_next = (text == "Next")
	
	if not is_next:
		# Home button - icon on left
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
	else:
		# Next button - text first, then smaller icon
		var label = Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", text_color)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(label)
		
		var icon = TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon)
	
	return btn

func show_victory(level: int):
	"""Shows victory popup and marks level as completed"""
	# Play sound at the beginning like defeat_popup
	get_node("/root/Main").play_victory_sound()
	
	current_level = level
	
	# Update level text
	var level_label = main_panel.get_node("Content/LevelLabel")
	if level_label:
		level_label.text = "Level %d" % level
	
	# Check if level was already completed BEFORE marking it
	var was_already_completed = is_level_completed(level)
	
	# IMPORTANT: Mark level as completed
	mark_level_completed(level)
	
	# Add currency reward ONLY if first time completing
	if not was_already_completed:
		var main = get_node("/root/Main")
		main.add_currency(3)
		print("First time victory! +3 currency awarded")
	else:
		print("Level already completed before - no currency reward")
	
	# Update reward panel based on completion status
	update_reward_panel(was_already_completed)
	
	# Show overlay and container
	overlay.visible = true
	popup_container.visible = true
	
	# Start with scale 0
	popup_container.scale = Vector2.ZERO
	
	# Spawn confetti
	spawn_confetti()
	
	# Animate popup scale
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ONE, 0.6)
	
	# Animate crown bounce with CENTER pivot
	var crown_container = main_panel.get_node("Content/CrownContainer")
	if crown_container:
		var crown = crown_container.get_node("Crown")
		if crown:
			# POPRAWKA: Ustaw pivot_offset na środek tekstury
			crown.pivot_offset = crown.custom_minimum_size / 2.0
			crown.scale = Vector2(0.8, 0.8)
			var crown_tween = create_tween()
			crown_tween.set_ease(Tween.EASE_OUT)
			crown_tween.set_trans(Tween.TRANS_BOUNCE)
			crown_tween.tween_property(crown, "scale", Vector2(1.0, 1.0), 0.8).set_delay(0.4)
	
	# Animate rewards ONLY if showing relics
	if not was_already_completed:
		# Relics — wchodzą jeden po drugim po popup animacji
		for i in range(relic_textures.size()):
			var pivot = relic_textures[i]
			pivot.scale = Vector2.ZERO
			pivot.modulate.a = 0.0
			
			var relic_tween = create_tween()
			relic_tween.set_parallel(true)
			# Scale z bounce
			var scale_tw = relic_tween.tween_property(pivot, "scale", Vector2.ONE, 0.45).set_delay(0.6 + i * 0.18)
			scale_tw.set_ease(Tween.EASE_OUT)
			scale_tw.set_trans(Tween.TRANS_BOUNCE)
			# Fade in szybko na początku
			var fade_tw = relic_tween.tween_property(pivot, "modulate:a", 1.0, 0.15).set_delay(0.6 + i * 0.18)
			fade_tw.set_ease(Tween.EASE_OUT)
			
	_show_interstitial_after_delay()
	_maybe_show_rate_popup(level)
	
func _maybe_show_rate_popup(level: int):
	if level < 5:
		return
	await get_tree().create_timer(3.0).timeout  # po animacji victory
	var main = get_node("/root/Main")
	if RatePopup.should_show(main):
		var popup = preload("res://rate_popup.tscn").instantiate()
		get_tree().root.add_child(popup)
		popup.show_popup()
	
func _show_interstitial_after_delay():
	# Poczekaj aż animacja popup się skończy, potem pokaż reklamę
	await get_tree().create_timer(1.5).timeout
	var admob = get_node_or_null("/root/AdMobManager")
	if admob and admob.has_method("show_interstitial"):
		admob.show_interstitial()

func mark_level_completed(level_num: int):
	"""Marks a level as completed in progress data"""
	var progress_data = load_progress_data()
	
	if not progress_data.has(str(level_num)):
		progress_data[str(level_num)] = {}
	
	progress_data[str(level_num)]["completed"] = true
	
	save_progress_data(progress_data)
	print("Level ", level_num, " marked as completed and saved!")

func is_level_completed(level_num: int) -> bool:
	"""Checks if a level was already completed"""
	var progress_data = load_progress_data()
	
	if not progress_data.has(str(level_num)):
		return false
	
	return progress_data[str(level_num)].get("completed", false)

func update_reward_panel(already_completed: bool):
	"""Updates the reward panel to show relics or 'already claimed' message"""
	var reward_panel = main_panel.get_node("Content/RewardPanel")
	if not reward_panel:
		return
	
	var reward_vbox = reward_panel.get_child(0)  # First child is VBoxContainer
	if not reward_vbox:
		return
	
	# Find reward_label, relics_hbox and count_label
	var reward_label = null
	var relics_hbox = null
	var count_label = null
	
	for child in reward_vbox.get_children():
		if child is Label:
			if child.text == "REWARD":
				reward_label = child
			elif child.text.begins_with("Chrono") or child.text.begins_with("Reward"):
				count_label = child
		elif child is HBoxContainer:
			relics_hbox = child
	
	if already_completed:
		# Hide REWARD label
		if reward_label:
			reward_label.visible = false
		
		# Hide relics
		if relics_hbox:
			relics_hbox.visible = false
		
		# Change text to "Reward already claimed"
		if count_label:
			count_label.text = "Reward already claimed"
			count_label.add_theme_color_override("font_color", COMPLETED_COLOR)
			count_label.add_theme_font_size_override("font_size", 20)
	else:
		# Show REWARD label
		if reward_label:
			reward_label.visible = true
		
		# Show relics
		if relics_hbox:
			relics_hbox.visible = true
		
		# Show normal reward text
		if count_label:
			count_label.text = "Chrono Relic ×3"
			count_label.add_theme_color_override("font_color", LEVEL_COLOR)
			count_label.add_theme_font_size_override("font_size", 24)

func load_progress_data() -> Dictionary:
	"""Loads progress data from file"""
	if not FileAccess.file_exists(PROGRESS_PATH):
		return {}
	
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		return {}
	
	return json.data

func save_progress_data(data: Dictionary):
	"""Saves progress data to file"""
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		print("ERROR: Failed to save progress data")

func spawn_confetti():
	"""Spawns confetti particles falling from top"""
	var confetti_colors = [
		Color("FE9A00"),  # Orange
		Color("FFB900"),  # Yellow
		Color("4D99FF"),  # Blue
		Color("FF6467"),  # Red
		Color("9B59FF"),  # Purple
		Color("00BC7D"),  # Green
	]
	
	# Spawn 50 confetti pieces
	for i in range(50):
		var confetti = ColorRect.new()
		confetti.color = confetti_colors[randi() % confetti_colors.size()]
		confetti.custom_minimum_size = Vector2(randf_range(8, 16), randf_range(12, 24))
		
		# Random position at top
		var viewport_size = get_viewport().get_visible_rect().size
		confetti.position = Vector2(randf_range(0, viewport_size.x), -30)
		
		# Random rotation
		confetti.rotation = randf_range(0, TAU)
		
		add_child(confetti)
		confetti_particles.append(confetti)
		
		# Animate falling
		var fall_duration = randf_range(2.0, 4.0)
		var fall_distance = viewport_size.y + 50
		var horizontal_drift = randf_range(-100, 100)
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(confetti, "position:y", fall_distance, fall_duration)
		tween.tween_property(confetti, "position:x", confetti.position.x + horizontal_drift, fall_duration)
		tween.tween_property(confetti, "rotation", confetti.rotation + randf_range(-TAU * 2, TAU * 2), fall_duration)
		tween.tween_property(confetti, "modulate:a", 0.0, fall_duration * 0.5).set_delay(fall_duration * 0.5)
		
		# Remove after animation
		tween.finished.connect(func(): 
			if is_instance_valid(confetti):
				confetti.queue_free()
				confetti_particles.erase(confetti)
		)

func hide_popup():
	"""Hides the popup with animation"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(popup_container, "scale", Vector2.ZERO, 0.4)
	tween.finished.connect(func():
		overlay.visible = false
		popup_container.visible = false
		# Clean up confetti
		for confetti in confetti_particles:
			if is_instance_valid(confetti):
				confetti.queue_free()
		confetti_particles.clear()
	)

func _on_home_pressed():
	get_node("/root/Main").play_btn_sound()
	home_pressed.emit()
	hide_popup()

func _on_next_pressed():
	get_node("/root/Main").play_btn_sound()
	next_pressed.emit()
	hide_popup()
