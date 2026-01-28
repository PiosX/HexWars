extends CanvasLayer
class_name LevelSelect

# === COLORS ===
const BG_COLOR = Color("121218")
const PANEL_BG = Color("1A1A28")
const PANEL_BORDER = Color("2A2A40")
const TEXT_PRIMARY = Color("FFFFFF")
const TEXT_SECONDARY = Color("6A7282")

# Hex level colors
const HEX_DEFAULT_BG = Color("364153", 0.6)
const HEX_DEFAULT_BORDER = Color("4A5565", 0.4)
const HEX_NUMBER_COLOR = Color("6A7282")
const HEX_COMPLETED_BG = Color("4D99FF")  # Niebieski jak w hex_grid (TEAM_COLORS[1])
const HEX_COMPLETED_BORDER = Color("51A2FF", 0.6)
const HEX_CURRENT_BG = Color("00BC7D")  # Zielony dla aktualnego poziomu
const HEX_CURRENT_BORDER = Color("00D492")
const HEX_ACTIVE_NUMBER_COLOR = Color("FFFFFF")  # Białe numery na niebieskim/zielonym

# Selection box colors
const SELECTION_BOX_BG = Color("1A1A28")
const SELECTION_BOX_BORDER = Color("2A2A40")

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

# === UI BOUNDS ===
const TOP_PANEL_HEIGHT = 116.0  # 20 (margin) + 96 (button height)
const BOTTOM_PANEL_HEIGHT = 200.0  # wysokość bottom nav

# === PATHS ===
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_SOUND = "res://ui/settings/sound.png"
const ICON_MUSIC = "res://ui/settings/music.png"
const ICON_INFO = "res://ui/settings/howto.png"
const ICON_TIME = "res://ui/time2.png"
const ICON_CROWN = "res://ui/levels/crown.png"
const ICON_SK1 = "res://ui/levels/sk1.png"
const ICON_SK2 = "res://ui/levels/sk2.png"
const ICON_SK3 = "res://ui/levels/sk3.png"
const ICON_CLOSE = "res://ui/settings/close.png"
const ICON_PLAY = "res://ui/play.png"
const ICON_H1 = "res://ui/h1.png"
const ICON_H2 = "res://ui/h2.png"
const ICON_H3 = "res://ui/h3.png"
const ICON_H4 = "res://ui/h4.png"

# === EDITOR MODE ===
var editor_mode: bool = false
var edit_stage: int = 0  # 0 = place hexes, 1 = assign numbers, 2 = assign difficulty
var number_counter: int = 1
var mouse_button_mode: int = 0  # 0 = left (increment), 1 = right (decrement)

# === LEVEL DATA ===
const SAVE_PATH = "user://level_select_data.json"
var level_data: Dictionary = {}  # {Vector2i: {level: int, difficulty: int, completed: bool, is_current: bool}}

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
var hex_container: Node2D
var camera: Camera2D
var selection_box: Panel
var nav_container: HBoxContainer
var nav_buttons: Dictionary = {}

# Top and bottom panel backgrounds
var top_panel_bg: ColorRect
var bottom_panel_bg: ColorRect

var settings_expanded: bool = false
var sound_enabled: bool = true
var music_enabled: bool = true
var active_tab: String = "levels"

# Hex grid settings
const HEX_WIDTH: float = 96.0
const HEX_HEIGHT: float = 96.0
const HEX_GAP: float = 0.1
var hex_horiz_spacing: float
var hex_vert_spacing: float
var hex_map: Dictionary = {}  # {Vector2i: LevelHex}

# Camera dragging
var camera_dragging: bool = false
var drag_start_position: Vector2
var initial_camera_position: Vector2

# Selected level
var selected_level_coords: Vector2i = Vector2i.MAX
var selected_hex: Node = null

signal tab_changed(tab_name: String)
signal level_selected(level: int, difficulty: int)

# === LEVEL HEX CLASS ===
class LevelHex extends Area2D:
	var grid_position: Vector2i = Vector2i.ZERO
	var level_number: int = 0
	var difficulty: int = 0  # 1=sk1, 2=sk2, 3=sk3
	var completed: bool = false
	var is_current: bool = false
	
	var sprite: Sprite2D
	var label: Label
	var icon: TextureRect
	var original_scale: Vector2 = Vector2.ONE
	var hover_tween: Tween
	var current_color: Color = HEX_DEFAULT_BG
	
	func _init():
		input_pickable = true
	
	func _ready():
		setup_visuals()
		
		# CRITICAL: Set these for proper input handling
		input_pickable = true
		monitorable = true
		monitoring = true
		
		# Connect signals
		input_event.connect(_on_input_event)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	
	func setup_visuals():
		# Use actual hexagon96.png texture
		sprite = Sprite2D.new()
		sprite.texture = load("res://hexagon96.png")
		sprite.modulate = HEX_DEFAULT_BG
		add_child(sprite)
		
		# Create collision shape - MUST BE FIRST for input to work
		var collision = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 45.0  # Slightly smaller for better precision
		collision.shape = shape
		collision.position = Vector2.ZERO
		add_child(collision)
		move_child(collision, 0)  # Move to front for input priority
		
		# Label for number
		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", HEX_NUMBER_COLOR)
		label.position = Vector2(-48, -16)
		label.size = Vector2(96, 32)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		
		# Icon for difficulty/crown
		icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(-24, -35)  # Bliżej numeru
		icon.size = Vector2(48, 24)  # Mniejsze (2x mniejsze crown)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		add_child(icon)
		
		original_scale = scale
		
		# IMPORTANT: Set z_index to be above background
		z_index = 1
	
	func set_level_data(level: int, diff: int, comp: bool, curr: bool):
		level_number = level
		difficulty = diff
		completed = comp
		is_current = curr
		update_appearance()
	
	func update_appearance():
		if level_number > 0:
			label.text = str(level_number)
			label.visible = true
			
			if completed:
				current_color = HEX_COMPLETED_BG
				sprite.modulate = current_color
				label.add_theme_color_override("font_color", HEX_ACTIVE_NUMBER_COLOR)  # Białe
				icon.texture = load(ICON_CROWN)
				icon.visible = true
				icon.modulate = Color.WHITE  # Kolorowe crown
			elif is_current:
				current_color = HEX_CURRENT_BG
				sprite.modulate = current_color
				label.add_theme_color_override("font_color", HEX_ACTIVE_NUMBER_COLOR)  # Białe
				if difficulty > 0:
					var diff_icon = [ICON_SK1, ICON_SK2, ICON_SK3][difficulty - 1]
					icon.texture = load(diff_icon)
					icon.visible = true
					icon.modulate = Color.WHITE  # Białe sk (domyślnie)
				# Add pulsing animation for current level
				add_pulse_animation()
			else:
				current_color = HEX_DEFAULT_BG
				sprite.modulate = current_color
				label.add_theme_color_override("font_color", HEX_NUMBER_COLOR)  # Szare
				if difficulty > 0:
					var diff_icon = [ICON_SK1, ICON_SK2, ICON_SK3][difficulty - 1]
					icon.texture = load(diff_icon)
					icon.visible = true
					icon.modulate = Color("6A7282", 0.6)  # Wyszarzone
		else:
			label.visible = false
			icon.visible = false
			current_color = HEX_DEFAULT_BG
			sprite.modulate = current_color
			label.add_theme_color_override("font_color", HEX_NUMBER_COLOR)
	
	func add_pulse_animation():
		var tween = create_tween()
		tween.set_loops()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(sprite, "modulate:a", 0.7, 0.8)
		tween.tween_property(sprite, "modulate:a", 1.0, 0.8)
	
	func _on_mouse_entered():
		# Only respond to hover on active hexes (current or completed)
		if is_current or completed:
			animate_scale(original_scale * 1.08, 0.15)
			# Lighter color on hover (less bright)
			sprite.modulate = current_color.lightened(0.1)  # Było 0.2, teraz 0.1
	
	func _on_mouse_exited():
		# Only respond if not selected
		if not (has_meta("is_selected") and get_meta("is_selected")):
			animate_scale(original_scale, 0.15)
			sprite.modulate = current_color  # Restore original color
	
	func _on_input_event(_viewport, event, _shape_idx):
		if event is InputEventMouseButton and event.pressed:
			print("Hex clicked! Level: ", level_number, " Completed: ", completed, " Current: ", is_current)
			
			# Navigate up to find LevelSelect instance
			var node = get_parent()
			var level_select = null
			while node != null:
				if node is LevelSelect:
					level_select = node
					break
				node = node.get_parent()
			
			if level_select:
				# Special handling for editor mode stage 1 (assign numbers)
				if level_select.editor_mode and level_select.edit_stage == 1:
					if event.button_index == MOUSE_BUTTON_LEFT:
						# Increase number
						if level_select.level_data.has(grid_position):
							var data = level_select.level_data[grid_position]
							data.level += 1
							set_level_data(data.level, data.difficulty, data.completed, data.is_current)
							print("Increased to ", data.level)
						else:
							level_select.on_hex_clicked(self)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						# Decrease number
						if level_select.level_data.has(grid_position):
							var data = level_select.level_data[grid_position]
							data.level = max(1, data.level - 1)  # Don't go below 1
							set_level_data(data.level, data.difficulty, data.completed, data.is_current)
							print("Decreased to ", data.level)
				elif event.button_index == MOUSE_BUTTON_LEFT:
					# Normal click handling
					level_select.on_hex_clicked(self)
	
	func animate_scale(target_scale: Vector2, duration: float):
		if hover_tween and hover_tween.is_valid():
			hover_tween.kill()
		hover_tween = create_tween()
		hover_tween.set_ease(Tween.EASE_OUT)
		hover_tween.set_trans(Tween.TRANS_QUAD)
		hover_tween.tween_property(self, "scale", target_scale, duration)
	
	func set_selected(selected: bool):
		if selected:
			set_meta("is_selected", true)
			# Same scale as hover (not bigger)
			sprite.modulate = current_color.lightened(0.1)
			animate_scale(original_scale * 1.08, 0.15)  # Takie samo jak hover
		else:
			remove_meta("is_selected")
			sprite.modulate = current_color
			animate_scale(original_scale, 0.15)

func _ready():
	setup_background()
	setup_panel_backgrounds()  # NOWE - dodajemy tła dla paneli
	setup_top_panel()
	setup_hex_grid()
	setup_bottom_nav()
	
	load_level_data()
	
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	print("=== LEVEL SELECT CONTROLS ===")
	print("EDITOR MODE: Press 'E' to toggle")
	print("PLAY MODE: Click levels to select, click PLAY to start")
	print("EDITOR: Stage 1 - Place hexes | Stage 2 - Assign numbers (LMB=next, RMB=prev) | Stage 3 - Assign difficulty")
	print("Middle mouse or touch - drag map")
	print("S = Save | L = Load")

func setup_background():
	background = ColorRect.new()
	background.name = "Background"
	background.color = BG_COLOR
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # CRITICAL: Don't block hex clicks
	add_child(background)

# NOWA FUNKCJA - tła dla top i bottom panelu
func setup_panel_backgrounds():
	# Top panel background - blokuje hexagony
	top_panel_bg = ColorRect.new()
	top_panel_bg.name = "TopPanelBG"
	top_panel_bg.color = BG_COLOR
	top_panel_bg.anchor_right = 1.0
	top_panel_bg.size = Vector2(0, TOP_PANEL_HEIGHT + 20)
	top_panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel_bg.z_index = 10  # Nad hexami (1) ale pod UI (100)
	add_child(top_panel_bg)
	
	# Bottom panel background - blokuje hexagony
	bottom_panel_bg = ColorRect.new()
	bottom_panel_bg.name = "BottomPanelBG"
	bottom_panel_bg.color = BG_COLOR
	bottom_panel_bg.anchor_left = 0.0
	bottom_panel_bg.anchor_right = 1.0
	bottom_panel_bg.anchor_top = 1.0
	bottom_panel_bg.anchor_bottom = 1.0
	bottom_panel_bg.offset_top = -(BOTTOM_PANEL_HEIGHT + 20)
	bottom_panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_panel_bg.z_index = 10  # Nad hexami (1) ale pod UI (100)
	add_child(bottom_panel_bg)

func setup_top_panel():
	# Settings button (top left)
	settings_button = create_icon_button(ICON_SETTINGS, Vector2(95, 95))
	settings_button.position = Vector2(12, 20)
	settings_button.pressed.connect(_on_settings_pressed)
	settings_button.z_index = 100  # Nad tłem
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
	
	# "CHOOSE LEVEL" label (center)
	var title_container = Panel.new()
	title_container.name = "TitleContainer"
	title_container.custom_minimum_size = Vector2(250, 96)
	title_container.z_index = 100  # Nad tłem
	
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = PANEL_BG
	title_style.border_width_left = 1
	title_style.border_width_right = 1
	title_style.border_width_top = 1
	title_style.border_width_bottom = 1
	title_style.border_color = PANEL_BORDER
	title_style.corner_radius_top_left = 999
	title_style.corner_radius_top_right = 999
	title_style.corner_radius_bottom_left = 999
	title_style.corner_radius_bottom_right = 999
	title_container.add_theme_stylebox_override("panel", title_style)
	add_child(title_container)
	
	title_label = Label.new()
	title_label.text = "CHOOSE LEVEL"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	title_container.add_child(title_label)
	
	title_container.set_meta("center_top", true)
	
	# Currency panel (top right)
	currency_panel = Panel.new()
	currency_panel.name = "CurrencyPanel"
	currency_panel.custom_minimum_size = Vector2(160, 60)
	currency_panel.z_index = 100  # Nad tłem
	
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
	currency_amount.text = "1251"
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
	icon_container.custom_minimum_size = Vector2(54, 44)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var currency_icon = TextureRect.new()
	currency_icon.texture = load(ICON_TIME)
	currency_icon.custom_minimum_size = Vector2(60, 60)
	currency_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	currency_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	currency_icon.anchor_right = 1.0
	currency_icon.anchor_top = 0.0
	currency_icon.anchor_bottom = 1.0
	currency_icon.offset_top = 0
	icon_container.add_child(currency_icon)
	
	currency_hbox.add_child(icon_container)
	currency_panel.set_meta("right_top", true)

func setup_hex_grid():
	# Calculate spacing - IDENTICAL to hex_grid.gd
	hex_horiz_spacing = HEX_WIDTH * 0.866 * (1.0 + HEX_GAP)
	hex_vert_spacing = HEX_HEIGHT * 0.75 * (1.0 + HEX_GAP)
	
	# Create hex container
	hex_container = Node2D.new()
	hex_container.name = "HexContainer"
	hex_container.z_index = 0  # Above background but below UI
	add_child(hex_container)
	
	# Create camera (separate from hex_container)
	camera = Camera2D.new()
	camera.name = "LevelSelectCamera"
	camera.zoom = Vector2(1.0, 1.0)
	camera.enabled = true
	camera.position = Vector2(0, 0)
	add_child(camera)

func center_camera_on_hexes():
	"""Centers hex_container to show all hexes"""
	if hex_map.is_empty():
		hex_container.position = Vector2(0, 0)
		return
	
	var bounds = calculate_map_bounds()
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Center the hex container so bounds center is at screen center
	var offset = viewport_size / 2 - bounds.get_center()
	hex_container.position = offset

func calculate_map_bounds() -> Rect2:
	"""Calculate bounds of the hex map"""
	if hex_map.is_empty():
		return Rect2(0, 0, 1000, 1000)
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for hex in hex_map.values():
		var pos = hex.position
		min_pos.x = min(min_pos.x, pos.x - HEX_WIDTH/2)
		min_pos.y = min(min_pos.y, pos.y - HEX_HEIGHT/2)
		max_pos.x = max(max_pos.x, pos.x + HEX_WIDTH/2)
		max_pos.y = max(max_pos.y, pos.y + HEX_HEIGHT/2)
	
	return Rect2(min_pos, max_pos - min_pos)

func setup_bottom_nav():
	nav_container = HBoxContainer.new()
	nav_container.name = "NavContainer"
	nav_container.add_theme_constant_override("separation", 24)
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.z_index = 100  # Nad tłem
	add_child(nav_container)
	
	nav_container.set_meta("bottom_center", true)
	
	nav_buttons["home"] = create_nav_button("HOME", ICON_H1, HOME_BORDER, HOME_ACTIVE)
	nav_buttons["levels"] = create_nav_button("LEVELS", ICON_H2, LEVELS_BORDER, LEVELS_ACTIVE)
	nav_buttons["shop"] = create_nav_button("SHOP", ICON_H3, SHOP_BORDER, SHOP_ACTIVE, true)
	nav_buttons["howto"] = create_nav_button("HOW TO", ICON_H4, HOWTO_BORDER, HOWTO_ACTIVE)
	
	for button in nav_buttons.values():
		nav_container.add_child(button)
	
	update_active_tab("levels")

func create_nav_button(label_text: String, icon_path: String, border_color: Color, active_color: Color, has_badge: bool = false) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(140, 170)
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_transparent = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", style_transparent)
	btn.add_theme_stylebox_override("hover", style_transparent)
	btn.add_theme_stylebox_override("pressed", style_transparent)
	
	var visual_container = VBoxContainer.new()
	visual_container.add_theme_constant_override("separation", 12)
	visual_container.alignment = BoxContainer.ALIGNMENT_CENTER
	visual_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_container.anchor_left = 0.0
	visual_container.anchor_top = 0.0
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

# === HEX GRID MANAGEMENT ===
func create_hex_at(grid_pos: Vector2i) -> LevelHex:
	var hex = LevelHex.new()
	hex.grid_position = grid_pos
	
	var row = grid_pos.y
	var col = grid_pos.x
	var x = col * hex_horiz_spacing
	var y = row * hex_vert_spacing
	
	if row % 2 == 1:
		x += hex_horiz_spacing * 0.5
	
	hex.position = Vector2(x, y)
	hex_container.add_child(hex)
	hex_map[grid_pos] = hex
	
	return hex

func get_hex_at(grid_pos: Vector2i) -> LevelHex:
	return hex_map.get(grid_pos, null)

func remove_hex_at(grid_pos: Vector2i):
	if hex_map.has(grid_pos):
		var hex = hex_map[grid_pos]
		hex.queue_free()
		hex_map.erase(grid_pos)
		level_data.erase(grid_pos)

func on_hex_clicked(hex: LevelHex):
	print("on_hex_clicked - Editor mode: ", editor_mode)
	if editor_mode:
		handle_editor_click(hex)
	else:
		handle_play_click(hex)

func handle_editor_click(hex: LevelHex):
	print("Editor click - Stage: ", edit_stage)
	match edit_stage:
		0:  # Place hexes stage
			# Hex already exists, do nothing
			print("Stage 0 - hex already placed")
			pass
		1:  # Assign numbers - LMB increases, RMB decreases
			if not level_data.has(hex.grid_position):
				# New hex - assign current number_counter
				level_data[hex.grid_position] = {
					"level": number_counter,
					"difficulty": 0,
					"completed": false,
					"is_current": false
				}
				print("Assigned number ", number_counter, " to hex at ", hex.grid_position)
				hex.set_level_data(number_counter, 0, false, false)
				number_counter += 1
			else:
				# Hex already has a number - allow changing it
				print("Hex already has number: ", level_data[hex.grid_position].level, " - can change with LMB/RMB")
		2:  # Assign difficulty
			if level_data.has(hex.grid_position):
				var data = level_data[hex.grid_position]
				data.difficulty = (data.difficulty % 3) + 1
				print("Set difficulty to ", data.difficulty, " for hex at ", hex.grid_position)
				hex.set_level_data(data.level, data.difficulty, data.completed, data.is_current)
			else:
				print("Hex has no level number yet!")

func handle_play_click(hex: LevelHex):
	print("handle_play_click called - Level: ", hex.level_number, " Current: ", hex.is_current, " Completed: ", hex.completed)
	
	if not (hex.is_current or hex.completed):
		print("Hex is locked, ignoring click")
		return  # Can't select locked levels
	
	print("Hex is clickable, selecting...")
	
	# Deselect previous
	if selected_hex and is_instance_valid(selected_hex):
		selected_hex.set_selected(false)
	
	# Select new
	selected_hex = hex
	selected_level_coords = hex.grid_position
	hex.set_selected(true)
	
	# Show selection box
	show_selection_box(hex)

func show_selection_box(hex: LevelHex):
	# Remove old box if exists
	if selection_box and is_instance_valid(selection_box):
		selection_box.queue_free()
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Create selection box - nad bottom menu
	selection_box = Panel.new()
	selection_box.name = "SelectionBox"
	selection_box.custom_minimum_size = Vector2(viewport_size.x - 40, 140)  # Większa wysokość
	selection_box.z_index = 100  # Above everything
	selection_box.set_meta("selection_box", true)
	
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = SELECTION_BOX_BG
	box_style.border_width_left = 1
	box_style.border_width_right = 1
	box_style.border_width_top = 1
	box_style.border_width_bottom = 1
	box_style.border_color = SELECTION_BOX_BORDER
	box_style.corner_radius_top_left = 16
	box_style.corner_radius_top_right = 16
	box_style.corner_radius_bottom_left = 16
	box_style.corner_radius_bottom_right = 16
	selection_box.add_theme_stylebox_override("panel", box_style)
	
	# Position above bottom menu
	selection_box.position = Vector2(20, viewport_size.y - 360)
	add_child(selection_box)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.anchor_left = 0.0
	hbox.anchor_right = 1.0
	hbox.anchor_top = 0.5
	hbox.anchor_bottom = 0.5
	hbox.offset_left = 20
	hbox.offset_right = -20
	hbox.offset_top = -50
	hbox.offset_bottom = 50
	selection_box.add_child(hbox)
	
	# Mini hex preview (bigger, without icon)
	var mini_hex_container = Control.new()
	mini_hex_container.custom_minimum_size = Vector2(100, 100)
	hbox.add_child(mini_hex_container)
	
	var mini_hex = create_mini_hex_simple(hex)
	mini_hex.position = Vector2(50, 50)
	mini_hex_container.add_child(mini_hex)
	
	# Level info with icon
	var info_hbox = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 12)
	info_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(info_hbox)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 8)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.add_child(info_vbox)
	
	# Level title with icon
	var title_hbox = HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 12)
	info_vbox.add_child(title_hbox)
	
	var level_label = Label.new()
	level_label.text = "Level %d" % hex.level_number
	level_label.add_theme_font_size_override("font_size", 32)  # Większa czcionka
	level_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	var level_font = FontVariation.new()
	level_font.set_variation_embolden(0.5)
	level_label.add_theme_font_override("font", level_font)
	title_hbox.add_child(level_label)
	
	# Icon next to title
	if hex.completed or hex.difficulty > 0:
		var title_icon = TextureRect.new()
		if hex.completed:
			title_icon.texture = load(ICON_CROWN)
			title_icon.modulate = Color.WHITE
			title_icon.custom_minimum_size = Vector2(36, 36)  # Crown standardowy rozmiar
		else:
			var diff_icon = [ICON_SK1, ICON_SK2, ICON_SK3][hex.difficulty - 1]
			title_icon.texture = load(diff_icon)
			title_icon.modulate = Color("FF6467")
			# Różne szerokości ale ta sama wysokość 36px
			var icon_widths = [36, 60, 84]  # sk1=36, sk2=60, sk3=84
			title_icon.custom_minimum_size = Vector2(icon_widths[hex.difficulty - 1], 36)
		title_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_hbox.add_child(title_icon)
	
	var diff_label = Label.new()
	var diff_names = ["", "Easy", "Medium", "Hard"]
	diff_label.text = "Difficulty: " + diff_names[hex.difficulty]
	diff_label.add_theme_font_size_override("font_size", 20)  # Większa czcionka
	diff_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	info_vbox.add_child(diff_label)
	
	# Close button (28x28)
	var close_container = Control.new()
	close_container.custom_minimum_size = Vector2(70, 0)
	close_container.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_container.size_flags_vertical = Control.SIZE_FILL 

	var close_btn = TextureButton.new()
	close_btn.texture_normal = load(ICON_CLOSE)
	close_btn.custom_minimum_size = Vector2(56, 56)
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.ignore_texture_size = true

	# Ustaw anchory dla wyśrodkowania w kontenerze
	close_btn.anchor_left = 0.5
	close_btn.anchor_top = 0.5
	close_btn.anchor_right = 0.5
	close_btn.anchor_bottom = 0.5
	close_btn.offset_left = -28  # Połowa szerokości (56/2 = 28)
	close_btn.offset_top = -28   # Połowa wysokości (56/2 = 28)
	close_btn.offset_right = 70
	close_btn.offset_bottom = 28

	close_btn.pressed.connect(_on_close_selection)

	# Hover effect
	close_btn.mouse_entered.connect(func(): 
		var tween = create_tween()
		tween.tween_property(close_btn, "modulate", Color(1.3, 1.3, 1.3), 0.1)
	)
	close_btn.mouse_exited.connect(func(): 
		var tween = create_tween()
		tween.tween_property(close_btn, "modulate", Color.WHITE, 0.1)
	)

	close_container.add_child(close_btn)
	hbox.add_child(close_container)  # Dodajemy kontener zamiast samego przycisku
	
	# ===== PLAY BUTTON - 1:1 jak BUY BUTTON =====
	var play_container = Control.new()
	play_container.custom_minimum_size = Vector2(180, 100)  # Większa wysokość dla cienia
	play_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var play_btn = TextureButton.new()
	play_btn.texture_normal = load("res://ui/levels/play.png")
	play_btn.custom_minimum_size = Vector2(180, 120)
	play_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	play_btn.ignore_texture_size = true
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.pivot_offset = Vector2(90, 60)  # KLUCZOWE - środek (180/2=90, 120/2=60)
	play_btn.position = Vector2(0, 10)
	play_btn.pressed.connect(_on_play_level)

	# Hover effect - DOKŁADNIE jak buy button
	play_btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.tween_property(play_btn, "modulate", Color(1.3, 1.2, 1.0), 0.2)
		tween.parallel().tween_property(play_btn, "scale", Vector2(1.05, 1.05), 0.2)
	)

	play_btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(play_btn, "modulate", Color.WHITE, 0.2)
		tween.parallel().tween_property(play_btn, "scale", Vector2.ONE, 0.2)
	)

	play_container.add_child(play_btn)
	hbox.add_child(play_container) 

func create_mini_hex_simple(hex: LevelHex) -> Node2D:
	"""Simple mini hex without icon - just color and number centered"""
	var mini = Node2D.new()
	
	var sprite = Sprite2D.new()
	sprite.texture = load("res://hexagon96.png")
	sprite.scale = Vector2(0.9, 0.9)  # 90% scale
	
	# Use same color logic as main hex
	if hex.completed:
		sprite.modulate = HEX_COMPLETED_BG
	elif hex.is_current:
		sprite.modulate = HEX_CURRENT_BG
	else:
		sprite.modulate = HEX_DEFAULT_BG
	
	mini.add_child(sprite)
	
	# TYLKO LICZBA - wyśrodkowana pionowo i poziomo
	var label = Label.new()
	label.text = str(hex.level_number)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)  # Większa czcionka
	label.add_theme_color_override("font_color", HEX_ACTIVE_NUMBER_COLOR if (hex.completed or hex.is_current) else HEX_NUMBER_COLOR)
	# Perfect centering: 96 * 0.9 = 86.4, offset = -43.2
	label.position = Vector2(-42, -24)  # Wyśrodkowane pionowo (-16 zamiast -14)
	label.size = Vector2(86, 32)
	mini.add_child(label)
	
	return mini

func create_mini_hex(hex: LevelHex) -> Node2D:
	var mini = Node2D.new()
	
	var sprite = Sprite2D.new()
	sprite.texture = load("res://hexagon96.png")
	sprite.scale = Vector2(0.7, 0.7)  # Make it smaller (70% of original)
	sprite.modulate = HEX_COMPLETED_BG if hex.completed else (HEX_CURRENT_BG if hex.is_current else HEX_DEFAULT_BG)
	mini.add_child(sprite)
	
	var label = Label.new()
	label.text = str(hex.level_number)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.position = Vector2(-20, -15)
	label.size = Vector2(40, 30)
	mini.add_child(label)
	
	if hex.completed or hex.difficulty > 0:
		var icon = TextureRect.new()
		if hex.completed:
			icon.texture = load(ICON_CROWN)
		else:
			var diff_icon = [ICON_SK1, ICON_SK2, ICON_SK3][hex.difficulty - 1]
			icon.texture = load(diff_icon)
		icon.position = Vector2(-10, -28)
		icon.size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini.add_child(icon)
	
	return mini

func _on_close_selection():
	if selection_box and is_instance_valid(selection_box):
		selection_box.queue_free()
		selection_box = null
	
	if selected_hex and is_instance_valid(selected_hex):
		selected_hex.set_selected(false)
		selected_hex = null
	
	selected_level_coords = Vector2i.MAX

func _on_play_level():
	if selected_hex and is_instance_valid(selected_hex):
		var hex_data = level_data.get(selected_hex.grid_position, {})
		var level = hex_data.get("level", 0)
		var difficulty = hex_data.get("difficulty", 1)
		
		print("Starting level: ", level, " difficulty: ", difficulty)
		level_selected.emit(level, difficulty)

# === INPUT HANDLING ===
func _unhandled_input(event):
	# Camera dragging with middle mouse button - move hex_container instead of camera
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				camera_dragging = true
				drag_start_position = get_viewport().get_mouse_position()
				initial_camera_position = hex_container.position
				get_viewport().set_input_as_handled()  # Prevent other inputs
			else:
				camera_dragging = false
		
		# Editor mode - place/remove hexes (only in stage 0)
		elif editor_mode and edit_stage == 0:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var mouse_pos = get_viewport().get_mouse_position()
				place_hex_at_mouse(mouse_pos)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var mouse_pos = get_viewport().get_mouse_position()
				remove_hex_at_mouse(mouse_pos)
				get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion:
		if camera_dragging:
			var current_mouse_pos = get_viewport().get_mouse_position()
			var delta = current_mouse_pos - drag_start_position
			var new_pos = initial_camera_position + delta
			
			# Apply drag limits
			hex_container.position = clamp_to_bounds(new_pos)
			get_viewport().set_input_as_handled()

func _input(event):
	# Keyboard shortcuts (use _input for these)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				toggle_editor_mode()
			KEY_S:
				save_level_data()
			KEY_L:
				load_level_data()
			KEY_1:
				if editor_mode:
					set_edit_stage(0)
			KEY_2:
				if editor_mode:
					set_edit_stage(1)
			KEY_3:
				if editor_mode:
					set_edit_stage(2)

# ===== OGRANICZENIA DRAGOWANIA =====
func clamp_to_bounds(pos: Vector2) -> Vector2:
	"""Clamps hex_container position to keep map visible within safe zones"""
	if hex_map.is_empty():
		return pos
	
	var bounds = calculate_map_bounds()
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Define safe zones (areas where hexes shouldn't appear)
	var safe_top = TOP_PANEL_HEIGHT  # Top panel area
	var safe_bottom = BOTTOM_PANEL_HEIGHT  # Bottom panel area
	var safe_left = 20.0  # Left margin
	var safe_right = 20.0  # Right margin
	
	# Calculate available space for hexes
	var available_width = viewport_size.x - safe_left - safe_right
	var available_height = viewport_size.y - safe_top - safe_bottom
	
	# Calculate limits - ZMNIEJSZONY MARGIN o połowę!
	var margin = 50.0  # Było 100.0, teraz 50.0 - mniejsza swoboda przewijania
	var bounds_end = bounds.position + bounds.size
	
	# X limits - keep map within left/right margins
	var min_x = -bounds_end.x - margin + safe_left
	var max_x = available_width - bounds.position.x + margin + safe_left
	
	# Y limits - keep map within top/bottom safe zones
	var min_y = -bounds_end.y - margin + safe_top
	var max_y = available_height - bounds.position.y + margin + safe_top
	
	return Vector2(
		clamp(pos.x, min_x, max_x),
		clamp(pos.y, min_y, max_y)
	)

func toggle_editor_mode():
	editor_mode = !editor_mode
	print("Editor mode: ", editor_mode)
	if editor_mode:
		title_label.text = "EDITOR MODE"
		set_edit_stage(0)
	else:
		title_label.text = "CHOOSE LEVEL"
		edit_stage = 0

func set_edit_stage(stage: int):
	edit_stage = stage
	var stage_names = ["PLACE HEXES", "ASSIGN NUMBERS", "ASSIGN DIFFICULTY"]
	print("Edit stage: ", stage_names[stage])
	title_label.text = stage_names[stage]
	
	if stage == 1:
		number_counter = 1

func place_hex_at_mouse(screen_pos: Vector2):
	# Convert screen position to hex_container local position
	var local_pos = screen_pos - hex_container.position
	
	# Convert to grid coordinates
	var col = round(local_pos.x / hex_horiz_spacing)
	var row = round(local_pos.y / hex_vert_spacing)
	
	# Adjust for offset rows
	if int(row) % 2 == 1:
		col = round((local_pos.x - hex_horiz_spacing * 0.5) / hex_horiz_spacing)
	
	var grid_pos = Vector2i(int(col), int(row))
	
	if not hex_map.has(grid_pos):
		create_hex_at(grid_pos)
		center_camera_on_hexes()

func remove_hex_at_mouse(screen_pos: Vector2):
	# Convert screen position to hex_container local position
	var local_pos = screen_pos - hex_container.position
	
	var col = round(local_pos.x / hex_horiz_spacing)
	var row = round(local_pos.y / hex_vert_spacing)
	
	if int(row) % 2 == 1:
		col = round((local_pos.x - hex_horiz_spacing * 0.5) / hex_horiz_spacing)
	
	var grid_pos = Vector2i(int(col), int(row))
	remove_hex_at(grid_pos)
	center_camera_on_hexes()

# === SAVE/LOAD ===
func save_level_data():
	var save_dict = {
		"hex_positions": [],
		"level_data": {}
	}
	
	for grid_pos in hex_map.keys():
		save_dict.hex_positions.append([grid_pos.x, grid_pos.y])
	
	for grid_pos in level_data.keys():
		var key = "%d,%d" % [grid_pos.x, grid_pos.y]
		save_dict.level_data[key] = level_data[grid_pos]
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_dict, "\t"))
		file.close()
		print("Level data saved to ", SAVE_PATH)
	else:
		print("Failed to save level data")

func load_level_data() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No saved level data found")
		create_default_levels()
		return false
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		print("Failed to open save file")
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("Failed to parse JSON")
		return false
	
	var save_dict = json.data
	
	# Clear existing hexes
	for hex in hex_map.values():
		hex.queue_free()
	hex_map.clear()
	level_data.clear()
	
	# Recreate hexes
	for pos_array in save_dict.hex_positions:
		var grid_pos = Vector2i(pos_array[0], pos_array[1])
		create_hex_at(grid_pos)
	
	# Load level data
	for key in save_dict.level_data.keys():
		var parts = key.split(",")
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		var data = save_dict.level_data[key]
		level_data[grid_pos] = data
		
		var hex = get_hex_at(grid_pos)
		if hex:
			hex.set_level_data(data.level, data.difficulty, data.completed, data.is_current)
	
	center_camera_on_hexes()
	print("Level data loaded from ", SAVE_PATH)
	return true

func create_default_levels():
	# Create a default hex grid layout (similar to the design image)
	var layout = [
		[0, 1], [1, 1], [2, 1], [3, 1],
		[0, 2], [1, 2], [2, 2], [3, 2], [4, 2],
		[0, 3], [1, 3], [2, 3], [3, 3],
		[0, 4], [1, 4], [2, 4], [3, 4],
		[1, 5], [2, 5], [3, 5],
		[1, 6], [2, 6], [3, 6]
	]
	
	for i in range(layout.size()):
		var pos = layout[i]
		var grid_pos = Vector2i(pos[0], pos[1])
		var hex = create_hex_at(grid_pos)
		
		var level_num = i + 1
		var is_completed = level_num < 9
		var is_current = level_num == 9
		var diff = 1 if level_num <= 8 else (2 if level_num <= 16 else 3)
		
		level_data[grid_pos] = {
			"level": level_num,
			"difficulty": diff,
			"completed": is_completed,
			"is_current": is_current
		}
		
		hex.set_level_data(level_num, diff, is_completed, is_current)
	
	center_camera_on_hexes()

# === SETTINGS ===
func _on_settings_pressed():
	settings_expanded = !settings_expanded
	settings_menu.visible = settings_expanded
	
	if settings_expanded:
		settings_menu.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(settings_menu, "modulate", Color.WHITE, 0.2)

func _on_sound_pressed():
	sound_enabled = !sound_enabled
	update_toggle_button(sound_button, sound_enabled)

func _on_music_pressed():
	music_enabled = !music_enabled
	update_toggle_button(music_button, music_enabled)

func update_toggle_button(btn: Button, is_enabled: bool):
	if is_enabled:
		btn.modulate = Color.WHITE
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)

func _on_info_pressed():
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
