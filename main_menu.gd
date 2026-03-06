extends CanvasLayer
class_name MainMenu

# === COLORS ===
const BG_COLOR = Color("121218")
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
const ICON_TITLE = "res://ui/hex-wars.png"
const ICON_BTN = "res://ui/btn.png"
const ICON_H1 = "res://ui/h1.png"
const ICON_H2 = "res://ui/h2.png"
const ICON_H3 = "res://ui/h3.png"
const ICON_H4 = "res://ui/h4.png"

const PROGRESS_PATH = "res://levels/level_progress.json"
const LEVEL_DATA_PATH = "res://levels/level_select_data.json"

# === ANIMATED BACKGROUND COLORS ===
const HEX_COLORS = [
	Color(0.259, 0.522, 0.957),  # blue (66, 133, 244)
	Color(0.541, 0.310, 1.000),  # purple (138, 79, 255)
	Color(0.859, 0.267, 0.216),  # red (219, 68, 55)
	Color(0.957, 0.761, 0.051),  # yellow (244, 194, 13)
	Color(0.392, 0.455, 0.545),  # slate (100, 116, 139)
]

# === BACKGROUND ANIMATION DATA ===
class AnimatedHexagon:
	var x: float
	var y: float
	var size: float
	var opacity: float
	var target_opacity: float
	var color: Color
	var rotation: float
	var rotation_speed: float
	var drift_x: float
	var drift_y: float
	var pulse_phase: float
	var pulse_speed: float

class Particle:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var size: float
	var opacity: float
	var color: Color
	var life: int
	var max_life: int

class GlowOrb:
	var base_x: float
	var base_y: float
	var offset_phase_x: float
	var offset_phase_y: float
	var radius: float
	var color: Color

# === REFS ===
var background: ColorRect
var hex_animation_container: Node2D
var animated_background: Control
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

var current_level_number: int = 1
var current_level_file: String = ""
var current_level_difficulty: int = 1

# Background animation state
var animated_hexagons: Array[AnimatedHexagon] = []
var particles: Array[Particle] = []
var glow_orbs: Array[GlowOrb] = []
var animation_time: float = 0.0

signal tab_changed(tab_name: String)
signal play_pressed(level_file: String, difficulty: int, level_number: int)

func _ready():
	#setup_hex_animation()
	var main_node = get_node_or_null("/root/Main")
	if main_node:
		sound_enabled = main_node.sound_enabled
		music_enabled = main_node.music_enabled
	setup_animated_background()
	setup_top_panel()
	setup_center_content()
	setup_bottom_nav()
	
	load_current_level()
	update_level_display()
	
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	var admob = get_node_or_null("/root/AdMobManager")
	if admob:
		admob.banner_loaded_signal.connect(func(): admob.show_banner(), CONNECT_ONE_SHOT)
		admob.show_banner()

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
	# Container for hex animations (behind everything)
	if not hex_animation_container:
		hex_animation_container = Node2D.new()
		hex_animation_container.name = "HexAnimation"
		hex_animation_container.z_index = -2
		add_child(hex_animation_container)
	
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

func setup_animated_background():
	"""Creates advanced animated canvas background"""
	# Background color
	background = ColorRect.new()
	background.name = "Background"
	background.color = Color("121218")
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.z_index = -10
	add_child(background)
	
	animated_background = Control.new()
	animated_background.name = "AnimatedBackground"
	animated_background.anchor_right = 1.0
	animated_background.anchor_bottom = 1.0
	animated_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	animated_background.z_index = -1
	add_child(animated_background)
	
	# Initialize animation elements
	var viewport_size = get_viewport().get_visible_rect().size
	init_animated_hexagons(viewport_size)
	init_particles(viewport_size)
	init_glow_orbs(viewport_size)
	
	# Connect draw signal
	animated_background.draw.connect(_draw_animated_background)

func init_animated_hexagons(viewport_size: Vector2):
	"""Initialize floating hexagons"""
	animated_hexagons.clear()
	var count = int((viewport_size.x * viewport_size.y) / 25000.0)
	
	for i in range(count):
		var hex = AnimatedHexagon.new()
		hex.x = randf() * viewport_size.x
		hex.y = randf() * viewport_size.y
		hex.size = 15.0 + randf() * 45.0
		hex.opacity = randf() * 0.5
		hex.target_opacity = 0.1 + randf() * 0.6
		hex.color = HEX_COLORS[randi() % HEX_COLORS.size()]
		hex.rotation = randf() * PI
		hex.rotation_speed = (randf() - 0.5) * 0.003
		hex.drift_x = (randf() - 0.5) * 0.3
		hex.drift_y = -0.1 - randf() * 0.3
		hex.pulse_phase = randf() * PI * 2.0
		hex.pulse_speed = 0.005 + randf() * 0.015
		animated_hexagons.append(hex)

func init_particles(viewport_size: Vector2):
	"""Initialize floating particles"""
	particles.clear()
	for i in range(50):
		particles.append(spawn_particle(viewport_size))

func spawn_particle(viewport_size: Vector2) -> Particle:
	"""Create a new particle"""
	var p = Particle.new()
	p.x = randf() * viewport_size.x
	p.y = randf() * viewport_size.y
	p.vx = (randf() - 0.5) * 0.5
	p.vy = (randf() - 0.5) * 0.5
	p.size = 1.0 + randf() * 2.5
	p.opacity = 0.3 + randf() * 0.5
	p.color = HEX_COLORS[randi() % HEX_COLORS.size()]
	p.life = 0
	p.max_life = 200 + int(randf() * 400.0)
	return p

func init_glow_orbs(viewport_size: Vector2):
	"""Initialize glow orbs"""
	glow_orbs.clear()
	
	var orb1 = GlowOrb.new()
	orb1.base_x = viewport_size.x * 0.2
	orb1.base_y = viewport_size.y * 0.3
	orb1.offset_phase_x = 0.003
	orb1.offset_phase_y = 0.004
	orb1.radius = 120.0
	orb1.color = Color(0.259, 0.522, 0.957)  # blue
	glow_orbs.append(orb1)
	
	var orb2 = GlowOrb.new()
	orb2.base_x = viewport_size.x * 0.8
	orb2.base_y = viewport_size.y * 0.6
	orb2.offset_phase_x = 0.002
	orb2.offset_phase_y = 0.003
	orb2.radius = 100.0
	orb2.color = Color(0.541, 0.310, 1.000)  # purple
	glow_orbs.append(orb2)
	
	var orb3 = GlowOrb.new()
	orb3.base_x = viewport_size.x * 0.5
	orb3.base_y = viewport_size.y * 0.15
	orb3.offset_phase_x = 0.0025
	orb3.offset_phase_y = 0.0035
	orb3.radius = 80.0
	orb3.color = Color(0.859, 0.267, 0.216)  # red
	glow_orbs.append(orb3)
	
	var orb4 = GlowOrb.new()
	orb4.base_x = viewport_size.x * 0.7
	orb4.base_y = viewport_size.y * 0.85
	orb4.offset_phase_x = 0.002
	orb4.offset_phase_y = 0.003
	orb4.radius = 90.0
	orb4.color = Color(0.957, 0.761, 0.051)  # yellow
	glow_orbs.append(orb4)

func _process(delta: float):
	"""Update animation state"""
	animation_time += delta
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Update hexagons
	for hex in animated_hexagons:
		hex.x += hex.drift_x
		hex.y += hex.drift_y
		hex.rotation += hex.rotation_speed
		hex.pulse_phase += hex.pulse_speed
		
		var pulse = sin(hex.pulse_phase) * 0.3
		var current_opacity = clamp(hex.target_opacity + pulse, 0.0, 1.0)
		hex.opacity += (current_opacity - hex.opacity) * 0.02
		
		# Wrap around
		if hex.y < -hex.size * 2: hex.y = viewport_size.y + hex.size * 2
		if hex.y > viewport_size.y + hex.size * 2: hex.y = -hex.size * 2
		if hex.x < -hex.size * 2: hex.x = viewport_size.x + hex.size * 2
		if hex.x > viewport_size.x + hex.size * 2: hex.x = -hex.size * 2
	
	# Update particles
	for i in range(particles.size()):
		var p = particles[i]
		p.x += p.vx
		p.y += p.vy
		p.life += 1
		
		# Respawn if dead
		if p.life >= p.max_life:
			particles[i] = spawn_particle(viewport_size)
	
	# Request redraw
	animated_background.queue_redraw()

func _draw_animated_background():
	"""Draw the animated background"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Draw floating hexagons
	for hex in animated_hexagons:
		draw_animated_hexagon(Vector2(hex.x, hex.y), hex.size, hex.rotation, hex.color, hex.opacity, true)
	
	# Draw particles
	for p in particles:
		var life_ratio = float(p.life) / float(p.max_life)
		var fade_opacity = 1.0
		if life_ratio < 0.1:
			fade_opacity = life_ratio * 10.0
		elif life_ratio > 0.8:
			fade_opacity = (1.0 - life_ratio) * 5.0
		
		var final_color = p.color
		final_color.a = p.opacity * fade_opacity
		animated_background.draw_circle(Vector2(p.x, p.y), p.size, final_color)
	
	# Draw glow orbs
	draw_glow_orbs(viewport_size)

func draw_animated_hexagon(pos: Vector2, size: float, rotation: float, color: Color, opacity: float, filled: bool):
	"""Draw a single animated hexagon"""
	var points = PackedVector2Array()
	
	for i in range(6):
		var angle = (PI / 3.0) * i - PI / 6.0 + rotation
		var px = pos.x + size * cos(angle)
		var py = pos.y + size * sin(angle)
		points.append(Vector2(px, py))
	
	if filled:
		var fill_color = color
		fill_color.a = opacity * 0.15
		animated_background.draw_colored_polygon(points, fill_color)
	
	# Draw outline
	var stroke_color = color
	stroke_color.a = opacity * 0.4
	for i in range(6):
		var next_i = (i + 1) % 6
		animated_background.draw_line(points[i], points[next_i], stroke_color, 1.5)

func draw_glow_orbs(viewport_size: Vector2):
	"""Draw glowing orbs with radial gradient effect"""
	for orb in glow_orbs:
		var x = orb.base_x + sin(animation_time * orb.offset_phase_x) * 60.0
		var y = orb.base_y + cos(animation_time * orb.offset_phase_y) * 40.0
		
		# Simulate radial gradient with multiple circles
		var steps = 20
		for i in range(steps, 0, -1):
			var ratio = float(i) / float(steps)
			var current_radius = orb.radius * ratio
			
			var alpha = 0.0
			if ratio < 0.5:
				alpha = 0.06 * (1.0 - ratio * 2.0) + 0.02
			else:
				alpha = 0.02 * (1.0 - (ratio - 0.5) * 2.0)
			
			var glow_color = orb.color
			glow_color.a = alpha
			animated_background.draw_circle(Vector2(x, y), current_radius, glow_color)

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

func setup_center_content():
	"""Creates title and CTA button in center"""
	# Container for center content
	var center_container = Control.new()
	center_container.name = "CenterContainer"
	center_container.set_meta("center_middle", true)
	add_child(center_container)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_container.add_child(vbox)
	
	# Title image
	title_image = TextureRect.new()
	title_image.texture = load(ICON_TITLE)
	title_image.custom_minimum_size = Vector2(265, 265)
	title_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title_image)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "CONQUER THE KINGDOMS"
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color("FFFFFF"))  # Jaśniejszy szary
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
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
	tap_label.text = "PRESS TO PLAY"
	tap_label.add_theme_font_size_override("font_size", 20)
	tap_label.add_theme_color_override("font_color", Color("9CA3AF"))  # Jaśniejszy szary
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
	glow_style.bg_color = Color(1, 1, 1, 0.075)  # Zmniejszone o 75%
	glow_style.shadow_size = 10  # Zmniejszone o 75%
	glow_style.shadow_color = Color(1, 1, 1, 0.125)  # Zmniejszone o 75%
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
		badge_style.bg_color = "00BC7D"
		badge_style.corner_radius_top_left = 14
		badge_style.corner_radius_top_right = 14
		badge_style.corner_radius_bottom_left = 14
		badge_style.corner_radius_bottom_right = 14
		badge.add_theme_stylebox_override("panel", badge_style)
		
		var badge_label = Label.new()
		badge_label.text = "BONUS"
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
	"""Toggles settings menu"""
	get_node("/root/Main").play_btn_sound()
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
	get_node("/root/Main").toggle_sound(sound_enabled)
	get_node("/root/Main").play_btn_sound()

func _on_music_pressed():
	"""Toggles music"""
	get_node("/root/Main").play_btn_sound()
	music_enabled = !music_enabled
	update_toggle_button(music_button, music_enabled)
	get_node("/root/Main").toggle_music(music_enabled)

func update_toggle_button(btn: Button, is_enabled: bool):
	"""Updates toggle button appearance"""
	if is_enabled:
		btn.modulate = Color.WHITE
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)
		# TODO: Add cross-out line

func _on_info_pressed():
	"""Opens info/tutorial"""
	get_node("/root/Main").play_btn_sound()
	OS.shell_open("market://details?id=com.redmoongames.hexwars")
	print("Info pressed")

func _on_cta_clicked(event: InputEvent):
	"""Handles CTA button click - starts current level"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_node("/root/Main").play_btn_sound()
		if not current_level_file.is_empty():
			play_pressed.emit(current_level_file, current_level_difficulty, current_level_number)

func _on_viewport_size_changed():
	"""Handles responsive layout"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Reinitialize animated background elements on resize
	if animated_background:
		init_animated_hexagons(viewport_size)
		init_particles(viewport_size)
		init_glow_orbs(viewport_size)
	
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
			var banner_height = 80
			child.position = Vector2(viewport_size.x / 2 - container_width / 2, viewport_size.y - 200 - banner_height)

func set_currency(amount: int):
	"""Updates currency display"""
	if currency_amount:
		currency_amount.text = str(amount)

func set_level(level: int):
	"""Updates level display"""
	if level_label:
		level_label.text = "LEVEL %02d" % level

func load_current_level():
	"""Loads current level from progress data"""
	var progress_data = load_progress_data()
	var level_data = load_level_data()
	
	if level_data.is_empty():
		print("WARNING: No level data found, defaulting to level 1")
		current_level_number = 1
		return
	
	# Find first uncompleted level
	var all_levels = []
	for data in level_data.values():
		if data.has("level"):
			all_levels.append(int(data.level))
	all_levels.sort()
	
	# Find first uncompleted
	current_level_number = 1
	for level_num in all_levels:
		var is_completed = progress_data.get(str(level_num), {}).get("completed", false)
		if not is_completed:
			current_level_number = level_num
			break
	
	# Get level file and difficulty for current level
	for data in level_data.values():
		if int(data.get("level", 0)) == current_level_number:
			current_level_file = data.get("level_file", "")
			current_level_difficulty = int(data.get("difficulty", 1))
			break
	
	print("Current level: ", current_level_number, " file: ", current_level_file, " difficulty: ", current_level_difficulty)

func load_progress_data() -> Dictionary:
	var main = get_node_or_null("/root/Main")
	if not main:
		return {}
	var result = {}
	for level_num in main.completed_levels:
		result[str(level_num)] = {"completed": true}
	return result

func load_level_data() -> Dictionary:
	"""Loads level data from file"""
	if not FileAccess.file_exists(LEVEL_DATA_PATH):
		return {}
	
	var file = FileAccess.open(LEVEL_DATA_PATH, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		return {}
	
	var save_dict = json.data
	if not save_dict.has("level_data"):
		return {}
	
	# Convert to simple dictionary
	var result = {}
	for key in save_dict.level_data.keys():
		var data = save_dict.level_data[key]
		if data.has("level"):
			data["level"] = int(data["level"])
		result[key] = data
	
	return result

func update_level_display():
	"""Updates the level label with current level"""
	set_level(current_level_number)
