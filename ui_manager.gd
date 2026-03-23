extends CanvasLayer
class_name UIManager

signal ui_ready
signal tab_changed(tab_name: String)
# --- COLORS ---
const BG_PANEL = Color("121218")
const BG_BOX = Color("1A1A28")
const BORDER_COLOR = Color("2A2A40")
const BORDER_HOVER = Color("2A2A40")
const SETTINGS_BUTTON_COLOR = Color("2A2A40")
const SETTINGS_BUTTON_HOVER = Color("3a3a50")

const TEAM_COLORS = {
	1: Color("#4D99FF"),  # Blue
	2: Color("#FF6467"),  # Red
	3: Color("#9B59FF"),  # Purple
	4: Color("#FFCC52")   # Yellow
}

const COST_RED = Color("#FF6467")

# --- REFS ---
var hex_grid: HexGrid

# Top panel
var top_panel: Panel
var settings_button: Button
var turn_label: Label
var rewind_counter: HBoxContainer

# Dominance bar
var dominance_container: Panel
var dominance_bar: Node2D

# Team boxes (4 kingdoms)
var team_boxes_container: HBoxContainer
var team_boxes: Array = []

# Bottom panel
var bottom_panel: Panel
var undo_button: VBoxContainer
var next_button: VBoxContainer

# Unit buttons (5 units)
var unit_buttons_container: HBoxContainer
var unit_buttons: Dictionary = {}

# Settings popup
var settings_popup: Control
var settings_overlay: ColorRect
var sound_enabled: bool = true
var music_enabled: bool = true

# Icons paths
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_TIME = "res://ui/time2.png"
const ICON_TURN = "res://turn.svg"
const ICON_COINS = "res://ui/coins.png"
const ICON_RETURN = "res://ui/return.png"
const ICON_NEXT = "res://ui/next.png"
const ICON_FARMER = "res://ui/farmer128.png"
const ICON_SPEARMAN = "res://ui/spear128.png"
const ICON_KNIGHT = "res://ui/sword128.png"
const ICON_CAVALRY = "res://ui/horse128.png"
const ICON_WALL = "res://ui/shield128.png"

# Settings icons
const ICON_CLOSE = "res://ui/settings/close.png"
const ICON_SOUND = "res://ui/settings/sound.png"
const ICON_MUSIC = "res://ui/settings/music.png"
const ICON_RESTART = "res://ui/settings/restart.png"
const ICON_HOWTO = "res://ui/settings/howto1.png"
const ICON_STORE = "res://ui/settings/store.png"
const ICON_HOME = "res://ui/settings/home.png"

func _ready():
	# Wait for hex_grid to be set
	await get_tree().process_frame
	setup_ui()
	setup_settings_popup()

func setup_ui():
	# === TOP PANEL ===
	top_panel = Panel.new()
	top_panel.name = "TopPanel"
	add_child(top_panel)
	
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = BG_PANEL
	top_style.border_width_bottom = 1
	top_style.border_color = BORDER_COLOR
	top_panel.add_theme_stylebox_override("panel", top_style)
	
	# Top panel content container
	var top_content = HBoxContainer.new()
	top_content.name = "TopContent"
	top_content.position = Vector2(12, 20)
	top_panel.add_child(top_content)
	
	# Settings button (left)
	settings_button = create_rounded_button("", ICON_SETTINGS)
	settings_button.custom_minimum_size = Vector2(95, 95)
	settings_button.add_theme_constant_override("icon_max_width", 45)
	settings_button.pressed.connect(_on_settings_pressed)
	top_content.add_child(settings_button)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_content.add_child(spacer1)
	
	# Turn label (center) - wewnątrz rounded boxa
	var turn_container = Panel.new()
	turn_container.custom_minimum_size = Vector2(200, 96)
	
	var turn_style = StyleBoxFlat.new()
	turn_style.bg_color = BG_BOX
	turn_style.border_width_left = 1
	turn_style.border_width_right = 1
	turn_style.border_width_top = 1
	turn_style.border_width_bottom = 1
	turn_style.border_color = BORDER_COLOR
	turn_style.corner_radius_top_left = 999
	turn_style.corner_radius_top_right = 999
	turn_style.corner_radius_bottom_left = 999
	turn_style.corner_radius_bottom_right = 999
	turn_style.content_margin_left = 12
	turn_style.content_margin_right = 12
	turn_style.content_margin_top = 8
	turn_style.content_margin_bottom = 8
	turn_container.add_theme_stylebox_override("panel", turn_style)
	
	turn_label = Label.new()
	turn_label.text = "Turn 1"
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.position = Vector2(0, 0)
	turn_label.size = Vector2(200, 96)
	turn_label.add_theme_font_size_override("font_size", 28)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	turn_container.add_child(turn_label)
	turn_container.set_meta("center_top", true)
	add_child(turn_container)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_content.add_child(spacer2)
	
	# Rewind counter (right) - BEZ BOXA, tylko ikona + tekst
	var rewind_panel = Panel.new()
	rewind_panel.name = "RewindPanel"
	rewind_panel.custom_minimum_size = Vector2(160, 60)  # Jak currency w innych

	var rewind_style = StyleBoxFlat.new()
	rewind_style.bg_color = Color(BG_BOX, 0.9)
	rewind_style.border_width_left = 1
	rewind_style.border_width_right = 1
	rewind_style.border_width_top = 1
	rewind_style.border_width_bottom = 1
	rewind_style.border_color = BORDER_COLOR
	rewind_style.corner_radius_top_left = 999
	rewind_style.corner_radius_top_right = 999
	rewind_style.corner_radius_bottom_left = 999
	rewind_style.corner_radius_bottom_right = 999
	rewind_panel.add_theme_stylebox_override("panel", rewind_style)

	# HBox wewnątrz panelu
	rewind_counter = HBoxContainer.new()
	rewind_counter.add_theme_constant_override("separation", 4)
	rewind_counter.alignment = BoxContainer.ALIGNMENT_END
	rewind_counter.anchor_left = 0.0
	rewind_counter.anchor_right = 1.0
	rewind_counter.anchor_top = 0.0
	rewind_counter.anchor_bottom = 1.0
	rewind_counter.offset_left = 10
	rewind_counter.offset_right = -10
	rewind_panel.add_child(rewind_counter)

	var currency = get_node("/root/Main").global_time_currency
	var rewind_label = Label.new()
	rewind_label.name = "RewindLabel"
	rewind_label.text = str(currency)
	rewind_label.add_theme_font_size_override("font_size", 24)  # Zmienione z 30 na 24
	rewind_label.add_theme_color_override("font_color", Color.WHITE)
	rewind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rewind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rewind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewind_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var font_var = FontVariation.new()
	font_var.set_variation_embolden(0.5)
	rewind_label.add_theme_font_override("font", font_var)
	rewind_counter.add_child(rewind_label)

	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(54, 44)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var rewind_icon = TextureRect.new()
	rewind_icon.texture = load(ICON_TIME)
	rewind_icon.custom_minimum_size = Vector2(60, 60)  # Zmienione z 32 na 60
	rewind_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rewind_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewind_icon.anchor_right = 1.0
	rewind_icon.anchor_top = 0.0
	rewind_icon.anchor_bottom = 1.0
	icon_container.add_child(rewind_icon)

	rewind_counter.add_child(icon_container)
	rewind_panel.set_meta("right_top", true)
	add_child(rewind_panel)
	
	# === DOMINANCE BAR ===
	dominance_container = Panel.new()
	dominance_container.name = "DominanceContainer"
	add_child(dominance_container)
	
	var dom_style = StyleBoxFlat.new()
	dom_style.bg_color = Color.TRANSPARENT
	dominance_container.add_theme_stylebox_override("panel", dom_style)
	
	dominance_bar = Node2D.new()
	dominance_bar.name = "DominanceBar"
	dominance_container.add_child(dominance_bar)
	
	# === TEAM BOXES (4 kingdoms) ===
	team_boxes_container = HBoxContainer.new()
	team_boxes_container.name = "TeamBoxes"
	team_boxes_container.add_theme_constant_override("separation", 8)
	add_child(team_boxes_container)
	
	for team in [1, 2, 3, 4]:
		var box = create_team_box(team)
		team_boxes.append(box)
		team_boxes_container.add_child(box)
	
	# === BOTTOM PANEL ===
	bottom_panel = Panel.new()
	bottom_panel.name = "BottomPanel"
	add_child(bottom_panel)

	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = BG_PANEL
	bottom_style.border_width_top = 1
	bottom_style.border_color = BORDER_COLOR
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)

	# Bottom content - TYLKO jednostki
	var bottom_content = HBoxContainer.new()
	bottom_content.name = "BottomContent"
	bottom_content.position = Vector2(20, 20)
	bottom_content.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_content.add_theme_constant_override("separation", 16)
	bottom_panel.add_child(bottom_content)

	# Unit buttons (center) - 5 units
	unit_buttons_container = HBoxContainer.new()
	unit_buttons_container.name = "UnitButtons"
	unit_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	unit_buttons_container.add_theme_constant_override("separation", 12)
	bottom_content.add_child(unit_buttons_container)

	var units_data = [
		{"name": "Farmer", "icon": ICON_FARMER, "cost": 10, "upkeep": 2, "id": "farmer"},
		{"name": "Spearman", "icon": ICON_SPEARMAN, "cost": 20, "upkeep": 6, "id": "spearman"},
		{"name": "Knight", "icon": ICON_KNIGHT, "cost": 40, "upkeep": 18, "id": "knight"},
		{"name": "Cavalry", "icon": ICON_CAVALRY, "cost": 80, "upkeep": 50, "id": "cavalry"},
		{"name": "Wall", "icon": ICON_WALL, "cost": 4, "upkeep": 0, "id": "wall"}
	]

	for unit_data in units_data:
		var btn = create_unit_button(unit_data)
		unit_buttons[unit_data.id] = btn
		unit_buttons_container.add_child(btn)

	# Undo button (NAD panelem po lewej)
	undo_button = create_action_button("UNDO", ICON_RETURN)
	var undo_btn = undo_button.get_meta("button")
	undo_btn.pressed.connect(_on_undo_pressed)
	add_child(undo_button)

	# Next button (NAD panelem po prawej)
	next_button = create_next_button()
	var next_btn = next_button.get_meta("button")
	next_btn.pressed.connect(_on_next_pressed)
	add_child(next_button)
	
	# Initial layout
	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	ui_ready.emit()

func setup_settings_popup():
	# Overlay (przyciemnione i zablurowane tło)
	settings_overlay = ColorRect.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.color = Color(0, 0, 0, 0.6)
	settings_overlay.visible = false
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# NOWE - anchor do full screen
	settings_overlay.anchor_left = 0
	settings_overlay.anchor_top = 0
	settings_overlay.anchor_right = 1
	settings_overlay.anchor_bottom = 1
	settings_overlay.offset_left = 0
	settings_overlay.offset_top = 0
	settings_overlay.offset_right = 0
	settings_overlay.offset_bottom = 0
	
	add_child(settings_overlay)
	
	# Główny popup container
	settings_popup = Control.new()
	settings_popup.name = "SettingsPopup"
	settings_popup.visible = false
	settings_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# NOWE - full screen
	settings_popup.anchor_left = 0
	settings_popup.anchor_top = 0
	settings_popup.anchor_right = 1
	settings_popup.anchor_bottom = 1
	
	add_child(settings_popup)
	
	# Panel pionowy
	var popup_panel = Panel.new()
	popup_panel.name = "PopupPanel"
	# ANCHOR do wyśrodkowania
	popup_panel.anchor_left = 0.5
	popup_panel.anchor_right = 0.5
	popup_panel.anchor_top = 0.5
	popup_panel.anchor_bottom = 0.5

	# ROZMIAR - 90% szerokości ekranu, ale max 700px
	popup_panel.custom_minimum_size = Vector2(600, 750)  # 1.5x większe (było 500x600)

	# OFFSET - wyśrodkowanie z marginesami
	popup_panel.offset_left = -300  # połowa szerokości
	popup_panel.offset_right = 300
	popup_panel.offset_top = -420  # połowa wysokości
	popup_panel.offset_bottom = 420
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_BOX
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 36
	panel_style.content_margin_right = 36
	panel_style.content_margin_top = 36
	panel_style.content_margin_bottom = 36
	popup_panel.add_theme_stylebox_override("panel", panel_style)
	settings_popup.add_child(popup_panel)
	
	# VBox dla zawartości
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	vbox.anchor_left = 0
	vbox.anchor_right = 1
	vbox.anchor_top = 0
	vbox.anchor_bottom = 1
	vbox.offset_left = 36
	vbox.offset_right = -36
	vbox.offset_top = 36
	vbox.offset_bottom = -36
	popup_panel.add_child(vbox)
	
	# === HEADER ===
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(header)
	
	# SETTINGS label
	var settings_label = Label.new()
	settings_label.text = "SETTINGS"
	settings_label.add_theme_font_size_override("font_size", 48)
	settings_label.add_theme_color_override("font_color", Color.WHITE)
	settings_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settings_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(settings_label)
	
	# Close button
	var close_btn = Button.new()
	close_btn.custom_minimum_size = Vector2(60, 60)
	close_btn.focus_mode = Control.FOCUS_NONE
	
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color.TRANSPARENT
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	
	var close_icon = load(ICON_CLOSE)
	if close_icon:
		close_btn.icon = close_icon
		close_btn.add_theme_constant_override("icon_max_width", 48)
	
	close_btn.pressed.connect(_on_close_settings)
	header.add_child(close_btn)
	
	# === TOGGLE PANEL ===
	var toggle_panel = Panel.new()
	toggle_panel.custom_minimum_size = Vector2(0, 200)
	
	var toggle_style = StyleBoxFlat.new()
	toggle_style.bg_color = Color.TRANSPARENT
	toggle_style.border_width_top = 1
	toggle_style.border_width_bottom = 1
	toggle_style.border_color = BORDER_COLOR
	toggle_style.content_margin_top = 30
	toggle_style.content_margin_bottom = 30
	toggle_panel.add_theme_stylebox_override("panel", toggle_style)
	vbox.add_child(toggle_panel)
	
	# HBox dla 2 kolumn
	var toggles_hbox = HBoxContainer.new()
	toggles_hbox.add_theme_constant_override("separation", 80)
	toggles_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	toggles_hbox.anchor_left = 0
	toggles_hbox.anchor_right = 1
	toggles_hbox.anchor_top = 0
	toggles_hbox.anchor_bottom = 1
	toggle_panel.add_child(toggles_hbox)
	
	# Sound toggle
	var main_node = get_node_or_null("/root/Main")
	var initial_sound_state = main_node.sound_enabled if main_node else true
	var sound_vbox = create_toggle_control("Sound", ICON_SOUND, initial_sound_state)
	sound_vbox.set_meta("type", "sound")
	toggles_hbox.add_child(sound_vbox)
	
	# Music toggle
	var initial_music_state = main_node.music_enabled if main_node else true
	var music_vbox = create_toggle_control("Music", ICON_MUSIC, initial_music_state)
	music_vbox.set_meta("type", "music")
	toggles_hbox.add_child(music_vbox)
	
	# === BUTTONS ===
	var buttons_vbox = VBoxContainer.new()
	buttons_vbox.add_theme_constant_override("separation", 20)
	buttons_vbox.custom_minimum_size = Vector2(0, 300)
	buttons_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons_vbox)
	
	# Restart button
	var restart_btn = create_settings_button("Restart", ICON_RESTART)
	restart_btn.pressed.connect(_on_restart_pressed)
	buttons_vbox.add_child(restart_btn)
	
	# How to Play button
	var howto_btn = create_settings_button("How to Play", ICON_HOWTO)
	howto_btn.pressed.connect(_on_howto_pressed)
	buttons_vbox.add_child(howto_btn)
	
	# Store button
	var store_btn = create_settings_button("Store", ICON_STORE)
	store_btn.pressed.connect(_on_store_pressed)
	buttons_vbox.add_child(store_btn)
	
	# Home button
	var home_btn = create_settings_button("Home", ICON_HOME)
	home_btn.pressed.connect(_on_home_pressed)
	buttons_vbox.add_child(home_btn)

func create_toggle_control(label_text: String, icon_path: String, initial_state: bool) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)  # było 16, zmniejszone
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Icon + Label
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(icon_path)
	hbox.add_child(icon)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("D1D5DC"))
	hbox.add_child(label)
	
	vbox.add_child(hbox)
	
	# Toggle switch container (większy obszar klikalny)
	var switch_container = Control.new()
	switch_container.custom_minimum_size = Vector2(100, 60)  # było 80, zwiększone dla lepszego paddingu
	switch_container.name = "SwitchContainer"  # DODAJ nazwę dla łatwiejszego dostępu
	
	# Toggle switch button
	var switch_btn = Button.new()
	switch_btn.custom_minimum_size = Vector2(100, 50)
	switch_btn.focus_mode = Control.FOCUS_NONE
	switch_btn.set_meta("state", initial_state)
	
	# Wyśrodkowanie w kontenerze
	switch_btn.anchor_left = 0.5
	switch_btn.anchor_top = 0.5
	switch_btn.offset_left = -50
	switch_btn.offset_top = -25
	switch_btn.offset_right = 50
	switch_btn.offset_bottom = 25
	
	var switch_style = StyleBoxFlat.new()
	switch_style.bg_color = Color("00BC7D") if initial_state else Color("3A3A50")
	switch_style.corner_radius_top_left = 25
	switch_style.corner_radius_top_right = 25
	switch_style.corner_radius_bottom_left = 25
	switch_style.corner_radius_bottom_right = 25
	switch_btn.add_theme_stylebox_override("normal", switch_style)
	switch_btn.add_theme_stylebox_override("hover", switch_style)
	switch_btn.add_theme_stylebox_override("pressed", switch_style)
	
	# White circle indicator
	var circle = Panel.new()
	circle.name = "Circle"
	circle.custom_minimum_size = Vector2(42, 42)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var circle_style = StyleBoxFlat.new()
	circle_style.bg_color = Color.WHITE
	circle_style.corner_radius_top_left = 21
	circle_style.corner_radius_top_right = 21
	circle_style.corner_radius_bottom_left = 21
	circle_style.corner_radius_bottom_right = 21
	circle.add_theme_stylebox_override("panel", circle_style)
	
	# Position circle based on state - POPRAWIONE pozycje
	circle.position = Vector2(54, 4) if initial_state else Vector2(4, 4)
	switch_btn.add_child(circle)
	
	switch_btn.pressed.connect(func(): _on_toggle_pressed(switch_btn, circle, label_text, vbox))
	switch_container.add_child(switch_btn)
	vbox.add_child(switch_container)
	
	# ON/OFF label
	var state_label = Label.new()
	state_label.name = "StateLabel"
	state_label.text = "ON" if initial_state else "OFF"
	state_label.add_theme_font_size_override("font_size", 24)
	state_label.add_theme_color_override("font_color", Color("6A7282"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(state_label)
	
	return vbox

func create_settings_button(label_text: String, icon_path: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(540, 90)  # było 400x60
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = SETTINGS_BUTTON_COLOR
	style_normal.corner_radius_top_left = 30
	style_normal.corner_radius_top_right = 30
	style_normal.corner_radius_bottom_left = 30
	style_normal.corner_radius_bottom_right = 30
	
	# WIĘKSZE PADDINGI
	style_normal.content_margin_left = 24
	style_normal.content_margin_right = 24
	style_normal.content_margin_top = 24
	style_normal.content_margin_bottom = 24
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = SETTINGS_BUTTON_HOVER
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	
	# HBox dla ikony i tekstu - WYRÓWNANIE DO LEWEJ
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)  # było 12
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN  # ZMIANA: było CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.anchor_left = 0
	hbox.anchor_right = 1
	hbox.anchor_top = 0
	hbox.anchor_bottom = 1
	btn.add_child(hbox)
	
	var left_padding = MarginContainer.new()
	left_padding.add_theme_constant_override("margin_left", 24)
	left_padding.add_theme_constant_override("margin_right", 0)
	left_padding.add_theme_constant_override("margin_top", 0)
	left_padding.add_theme_constant_override("margin_bottom", 0)

	hbox.add_child(left_padding)
	
	var icon = TextureRect.new()
	icon.texture = load(icon_path)

	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 33)  # było 22
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)
	
	return btn

func create_rounded_button(text: String, icon_path: String = "") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = BG_BOX
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = BORDER_COLOR
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = BORDER_COLOR
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	
	if icon_path != "":
		var icon = load(icon_path)
		if icon:
			btn.icon = icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	return btn

func create_team_box(team: int) -> Panel:
	var box = Panel.new()
	box.custom_minimum_size = Vector2(120, 52)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style = StyleBoxFlat.new()
	style.bg_color = BG_BOX
	# FIXED: gruby border tylko z lewej strony
	style.border_width_left = 6
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = TEAM_COLORS[team]
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	box.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.anchor_left = 0
	hbox.anchor_right = 1
	hbox.anchor_top = 0.5
	hbox.anchor_bottom = 0.5
	hbox.offset_left = 14
	hbox.offset_right = -14
	hbox.offset_top = -16
	hbox.offset_bottom = 16
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 8)
	box.add_child(hbox)
	
	# FIXED: Kropka drużyny (team dot)
	var team_dot = Panel.new()
	team_dot.custom_minimum_size = Vector2(22, 22)
	team_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var dot_style = StyleBoxFlat.new()
	dot_style.bg_color = TEAM_COLORS[team]
	dot_style.corner_radius_top_left = 999
	dot_style.corner_radius_top_right = 999
	dot_style.corner_radius_bottom_left = 999
	dot_style.corner_radius_bottom_right = 999
	team_dot.add_theme_stylebox_override("panel", dot_style)
	
	# Numer królestwa wewnątrz kropki (domyślnie ukryty)
	var kid_label = Label.new()
	kid_label.name = "KingdomLabel"
	kid_label.text = ""
	kid_label.add_theme_font_size_override("font_size", 11)
	kid_label.add_theme_color_override("font_color", Color.WHITE)
	kid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kid_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kid_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kid_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_dot.add_child(kid_label)
	
	hbox.add_child(team_dot)
	
	# FIXED: coin icon proper size
	var coin_icon = TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture = load(ICON_COINS)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(coin_icon)
	
	# FIXED: Gold + net income w JEDNEJ linii za pomocą RichTextLabel
	var rich_label = RichTextLabel.new()
	rich_label.name = "GoldUpkeepLabel"
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.scroll_active = false
	rich_label.custom_minimum_size = Vector2(100, 32)
	rich_label.add_theme_font_size_override("normal_font_size", 22)
	rich_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rich_label.text = "[color=white]0[/color] [color=#00FF00](+0)[/color]"
	hbox.add_child(rich_label)
	
	return box

func create_action_button(text: String, icon_path: String) -> VBoxContainer:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 6)
	
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(90, 90)
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = BG_BOX
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = BORDER_COLOR
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = BORDER_COLOR
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = BG_BOX.darkened(0.3)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	
	var icon = load(icon_path)
	if icon:
		btn.icon = icon
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 45)
	
	container.add_child(btn)
	
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(label)
	
	container.set_meta("button", btn)
	
	return container

func create_unit_button(unit_data: Dictionary) -> VBoxContainer:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 10)
	container.custom_minimum_size = Vector2(120, 0)
	
	# Button with icon
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(110, 110)
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = BG_BOX
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = BORDER_COLOR
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = BORDER_COLOR
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = BG_BOX.darkened(0.3)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	
	var icon = load(unit_data.icon)
	if icon:
		btn.icon = icon
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 55)
	
	# Connect to appropriate function
	match unit_data.id:
		"farmer":
			btn.pressed.connect(func(): 
				get_node("/root/Main").play_select_sound()
				hex_grid._on_buy_farmer()
			)
		"spearman":
			btn.pressed.connect(func(): 
				get_node("/root/Main").play_select_sound()
				hex_grid._on_buy_spearman()
			)
		"knight":
			btn.pressed.connect(func(): 
				get_node("/root/Main").play_select_sound()
				hex_grid._on_buy_knight()
			)
		"cavalry":
			btn.pressed.connect(func(): 
				get_node("/root/Main").play_select_sound()
				hex_grid._on_buy_cavalry()
			)
		"wall":
			btn.pressed.connect(func(): 
				get_node("/root/Main").play_select_sound()
				hex_grid._on_buy_wall()
			)
	
	container.add_child(btn)
	
	# Name label
	var name_label = Label.new()
	name_label.text = unit_data.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(name_label)
	
	# FIXED: Cost container PERFECTLY centered
	var cost_container = HBoxContainer.new()
	cost_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cost_container.add_theme_constant_override("separation", 4)
	
	var coin_icon = TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture = load(ICON_COINS)
	cost_container.add_child(coin_icon)
	
	# Cost and upkeep in one container with minimal spacing
	var numbers_container = HBoxContainer.new()
	numbers_container.add_theme_constant_override("separation", 0)
	
	# Use Label for cost
	var cost_label = Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cost_label.add_theme_font_size_override("font_size", 20)
	cost_label.add_theme_color_override("font_color", Color.WHITE)
	cost_label.text = "%d" % unit_data.cost
	numbers_container.add_child(cost_label)
	
	# Upkeep in red (separate label) with space before
	if unit_data.upkeep > 0:
		var upkeep_label = Label.new()
		upkeep_label.text = " (-%d)" % unit_data.upkeep
		upkeep_label.add_theme_font_size_override("font_size", 20)
		upkeep_label.add_theme_color_override("font_color", COST_RED)
		numbers_container.add_child(upkeep_label)
	
	cost_container.add_child(numbers_container)
	container.add_child(cost_container)
	
	# Store button reference
	container.set_meta("button", btn)
	
	return container

func create_next_button() -> VBoxContainer:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 6)
	
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(90, 90)
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color("10B981")  # emerald-500
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color("059669")  # emerald-600
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color("01402C")  # Ciemnoszary jak w UNDO
	style_disabled.border_width_left = 1
	style_disabled.border_width_right = 1
	style_disabled.border_width_top = 1
	style_disabled.border_width_bottom = 1
	style_disabled.border_color = Color("01402c")
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	
	var icon = load(ICON_NEXT)
	if icon:
		btn.icon = icon
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 45)
	
	container.add_child(btn)
	
	var label = Label.new()
	label.text = "NEXT"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(label)
	
	container.set_meta("button", btn)
	
	return container

func _on_viewport_size_changed():
	var viewport_size = get_viewport().get_visible_rect().size
	var safe_area = DisplayServer.get_display_safe_area()
	
	# Position elements with meta tags (like other tabs)
	for child in get_children():
		if child.has_meta("center_top"):
			child.position = Vector2(viewport_size.x / 2 - child.custom_minimum_size.x / 2, 20)
		
		if child.has_meta("right_top"):
			var title_center_y = 20 + 96 / 2
			var currency_center_y = child.custom_minimum_size.y / 2
			child.position = Vector2(viewport_size.x - child.custom_minimum_size.x - 20, title_center_y - currency_center_y)
	
	# Top panel - full width, at top with anchors (NO safe area offset)
	top_panel.anchor_top = 0.0
	top_panel.anchor_bottom = 0.0
	top_panel.anchor_left = 0.0
	top_panel.anchor_right = 1.0
	top_panel.offset_top = 0
	top_panel.offset_bottom = 235
	top_panel.offset_left = 0
	top_panel.offset_right = 0
	
	# Adjust top content width
	var top_content = top_panel.get_node("TopContent")
	top_content.size.x = viewport_size.x - 24
	
	# Dominance bar - below settings/turn/rewind
	dominance_container.position = Vector2(12, 136)
	dominance_container.size = Vector2(viewport_size.x - 24, 18)
	
	# Team boxes - below dominance bar
	team_boxes_container.position = Vector2(12, 136 + 18 + 12)
	team_boxes_container.size = Vector2(viewport_size.x - 24, 52)
	
	# FIXED: Bottom panel - używam anchor_bottom, WIĘKSZY
	var bottom_height = 240.0
	bottom_panel.anchor_top = 1.0
	bottom_panel.anchor_bottom = 1.0
	bottom_panel.anchor_left = 0.0
	bottom_panel.anchor_right = 1.0
	bottom_panel.offset_top = -bottom_height
	bottom_panel.offset_bottom = 0
	bottom_panel.offset_left = 0
	bottom_panel.offset_right = 0
	
	# Adjust bottom content
	var bottom_content = bottom_panel.get_node("BottomContent")
	if bottom_content:
		bottom_content.size.x = viewport_size.x - 40
		bottom_content.size.y = bottom_height - 40
	
	# Position UNDO button (NAD panelem po lewej)
	if undo_button:
		undo_button.position = Vector2(16, viewport_size.y - bottom_height - 130)
	
	# Position NEXT button (NAD panelem po prawej)
	if next_button:
		next_button.position = Vector2(viewport_size.x - 106, viewport_size.y - bottom_height - 130)
	
	# Overlay covers whole screen
	if settings_overlay:
		settings_overlay.anchor_left = 0
		settings_overlay.anchor_top = 0
		settings_overlay.anchor_right = 1
		settings_overlay.anchor_bottom = 1
		settings_overlay.offset_left = 0
		settings_overlay.offset_top = 0
		settings_overlay.offset_right = 0
		settings_overlay.offset_bottom = 0

func update_ui_data():
	"""Called by hex_grid to update all UI elements"""
	# Safety check - make sure UI elements exist
	if not is_instance_valid(hex_grid) or not is_instance_valid(turn_label):
		print("UI not ready yet")
		return
		
	hex_grid.update_territory_counts()
	
	# Update turn label
	turn_label.text = "Turn %d" % hex_grid.current_round
	
	# Update rewind counter (currency display)
	if is_instance_valid(rewind_counter):
		var rewind_label = rewind_counter.get_node("RewindLabel")
		if is_instance_valid(rewind_label):
			var main = get_node_or_null("/root/Main")
			if main:
				rewind_label.text = str(main.get_currency())
	
	# Update undo button state
	if is_instance_valid(undo_button) and undo_button.has_meta("button"):
		var undo_btn = undo_button.get_meta("button")
		if is_instance_valid(undo_btn):
			# NAPRAWKA: Zablokuj UNDO gdy AI gra lub nie można cofnąć
			var ai_playing = hex_grid.ai_is_playing
			var active_teams = {}
			for coords in hex_grid.castle_map:
				if hex_grid.castle_map[coords].team > 0:
					active_teams[hex_grid.castle_map[coords].team] = true
			var num_t = max(1, active_teams.size())
			undo_btn.disabled = ai_playing or not hex_grid.turn_history.can_rewind(num_t)
			
	var active_teams_count = 0
	for team in [1, 2, 3, 4]:
		if hex_grid.team_territory_count[team] > 0:
			active_teams_count += 1

	# Oblicz szerokość boxa
	var available_width = team_boxes_container.size.x
	var box_width = 120.0  # domyślna
	if active_teams_count > 0:
		box_width = (available_width - (active_teams_count - 1) * 8) / active_teams_count  # 8 = separation
	
	# Update team boxes - FIXED: jedna linia dla gold + upkeep
	for i in range(4):
		var team = i + 1
		if i < team_boxes.size() and is_instance_valid(team_boxes[i]):
			var box = team_boxes[i]
			var has_territory = hex_grid.team_territory_count[team] > 0
			
			# Ukryj/pokaż box w zależności od posiadania terytoriów
			box.visible = has_territory
			
			if has_territory:
				# Ustaw szerokość dynamicznie
				box.custom_minimum_size.x = box_width
				
				var hbox = box.get_node("HBoxContainer")
				if is_instance_valid(hbox):
					var rich_label = hbox.get_node("GoldUpkeepLabel")
					
					if is_instance_valid(rich_label):
						# --- Zbierz dane o zamkach drużyny ---
						var castle_count_for_team = 0
						for cpos in hex_grid.castle_map:
							if hex_grid.castle_map[cpos].team == team:
								castle_count_for_team += 1
						
						# Sprawdź czy zamki są scalone (mają ten sam kid)
						# Znajdź aktywne castle kingdom IDs posortowane rosnąco
						var active_kids_for_team: Array = []
						var castle_coords_per_kid: Dictionary = {}
						for cpos in hex_grid.castle_map:
							if hex_grid.castle_map[cpos].team == team:
								var k = hex_grid.castle_kingdom_id.get(cpos, 0) if "castle_kingdom_id" in hex_grid else 0
								if k > 0 and k not in active_kids_for_team:
									active_kids_for_team.append(k)
									castle_coords_per_kid[k] = cpos
						active_kids_for_team.sort()
						
						# Scalone = wszystkie zamki tego teamu mają ten sam kid
						var are_merged = active_kids_for_team.size() <= 1
						
						# Wybierz display_kid: selected lub najniższy aktywny
						var skpt = hex_grid.selected_kingdom_per_team if "selected_kingdom_per_team" in hex_grid else {}
						var selected_kid = skpt.get(team, 0)
						var kid_valid = selected_kid > 0 and selected_kid in active_kids_for_team
						# Użyj wybranego kid dla wszystkich teamów (gracz może kliknąć zamek wroga)
						# Jeśli selected_kid nieważny (np. nie istnieje) - użyj najniższego aktywnego
						var display_kid = selected_kid if kid_valid else (active_kids_for_team[0] if active_kids_for_team.size() > 0 else 0)
						
						# Znajdź KingdomLabel w team_dot
						var hbox2 = box.get_node_or_null("HBoxContainer")
						var team_dot2 = hbox2.get_child(0) if hbox2 else null
						var kid_lbl = team_dot2.get_node_or_null("KingdomLabel") if team_dot2 else null
						
						var gold: int
						var income: int
						var upkeep: int
						var net_income: int
						
						if castle_count_for_team > 1 and not are_merged and display_kid > 0:
							# Rozłączone królestwa → pokaż ekonomię konkretnego królestwa
							income = hex_grid.calculate_income_for_kingdom(display_kid)
							upkeep = hex_grid.calculate_upkeep_for_kingdom(display_kid)
							net_income = income - upkeep
							# Złoto per zamek: castle_gold = team_gold / count
							var c_coords = castle_coords_per_kid.get(display_kid, Vector2i.ZERO)
							gold = hex_grid.kingdom_gold.get(display_kid, 0) if "kingdom_gold" in hex_grid else 0
							if kid_lbl:
								kid_lbl.text = str(hex_grid.kid_to_display(display_kid) if hex_grid.has_method("kid_to_display") else display_kid)
						else:
							# Jeden zamek lub scalone → złoto wybranego królestwa
							gold = hex_grid.kingdom_gold.get(display_kid, 0) if "kingdom_gold" in hex_grid else hex_grid.team_gold.get(team, 0)
							income = hex_grid.calculate_income(team)
							upkeep = hex_grid.calculate_upkeep(team)
							net_income = income - upkeep
							if kid_lbl:
								kid_lbl.text = ""
						
						# Kolor dla net_income: zielony jeśli > 0, czerwony jeśli <= 0
						var net_color = "#00FF00" if net_income > 0 else "#FF6467"
						rich_label.text = "[color=white]%d[/color] [color=%s](%+d)[/color]" % [gold, net_color, net_income]
	
	# Update unit buttons availability
	if hex_grid.current_team in hex_grid.team_gold:
		var ai_playing = hex_grid.ai_is_playing
		# NAPRAWKA: Sprawdzaj złoto wybranego królestwa (nie całego teamu)
		var current_gold = hex_grid.get_selected_kingdom_gold(hex_grid.current_team)
		
		for unit_id in ["farmer", "spearman", "knight", "cavalry", "wall"]:
			if unit_id in unit_buttons and unit_buttons[unit_id].has_meta("button"):
				var btn = unit_buttons[unit_id].get_meta("button")
				if is_instance_valid(btn):
					if ai_playing:
						btn.disabled = true
					else:
						match unit_id:
							"farmer":
								btn.disabled = current_gold < 10
							"spearman":
								btn.disabled = current_gold < 20
							"knight":
								btn.disabled = current_gold < 40
							"cavalry":
								btn.disabled = current_gold < 80
							"wall":
								btn.disabled = current_gold < 4
	
	# Update dominance bar
	update_dominance_bar()

func update_dominance_bar():
	"""Updates the visual dominance bar"""
	if not hex_grid:
		return
	
	# Clear existing segments
	for child in dominance_bar.get_children():
		child.queue_free()
	
	hex_grid.update_territory_counts()
	
	var total = 0
	for count in hex_grid.team_territory_count.values():
		total += count
	
	if total == 0:
		return
	
	var bar_width = dominance_container.size.x
	var bar_height = 18.0
	var current_x = 0.0
	
	var active_teams = []
	for team in [1, 2, 3, 4]:
		if hex_grid.team_territory_count[team] > 0:
			active_teams.append(team)

	var team_index = 0
	for team in [1, 2, 3, 4]:
		var count = hex_grid.team_territory_count[team]
		if count > 0:
			var segment_width = (float(count) / total) * bar_width
			
			var is_first = (team_index == 0)
			var is_last = (team_index == active_teams.size() - 1)
			
			if is_first or is_last:
				var style = StyleBoxFlat.new()
				style.bg_color = TEAM_COLORS[team]
				if is_first:
					style.corner_radius_top_left = 999
					style.corner_radius_bottom_left = 999
				if is_last:
					style.corner_radius_top_right = 999
					style.corner_radius_bottom_right = 999
				var panel = Panel.new()
				panel.add_theme_stylebox_override("panel", style)
				panel.position = Vector2(current_x, 0)
				panel.size = Vector2(segment_width, bar_height)
				dominance_bar.add_child(panel)
			else:
				var segment = ColorRect.new()
				segment.color = TEAM_COLORS[team]
				segment.position = Vector2(current_x, 0)
				segment.size = Vector2(segment_width, bar_height)
				dominance_bar.add_child(segment)
			
			current_x += segment_width
			team_index += 1

func _on_undo_pressed():
	get_node("/root/Main").play_btn_sound()
	reset_all_buy_buttons()
	if hex_grid:
		hex_grid._on_rewind_turn()

func _on_next_pressed():
	get_node("/root/Main").play_btn_sound()
	reset_all_buy_buttons()
	if hex_grid:
		hex_grid._on_end_turn()

func reset_all_buy_buttons():
	"""Resetuje wszystkie przyciski zakupu do stanu nieaktywnego"""
	for id in unit_buttons:
		var container = unit_buttons[id]
		if container.has_meta("button"):
			var btn = container.get_meta("button")
			if is_instance_valid(btn):
				var style = StyleBoxFlat.new()
				style.bg_color = BG_BOX
				style.border_width_left = 1; style.border_width_right = 1
				style.border_width_top = 1; style.border_width_bottom = 1
				style.border_color = BORDER_COLOR
				style.corner_radius_top_left = 999; style.corner_radius_top_right = 999
				style.corner_radius_bottom_left = 999; style.corner_radius_bottom_right = 999
				btn.add_theme_stylebox_override("normal", style)
				var style_h = style.duplicate()
				style_h.bg_color = BORDER_COLOR
				btn.add_theme_stylebox_override("hover", style_h)
				btn.release_focus()

func set_buy_button_active(id: String, active: bool):
	"""Ustawia jeden przycisk zakupu jako aktywny/nieaktywny, resztę resetuje"""
	reset_all_buy_buttons()
	if not active:
		return
	if id in unit_buttons and unit_buttons[id].has_meta("button"):
		var btn = unit_buttons[id].get_meta("button")
		if is_instance_valid(btn):
			var style = StyleBoxFlat.new()
			style.bg_color = Color("#10B981", 0.25)
			style.border_width_left = 2; style.border_width_right = 2
			style.border_width_top = 2; style.border_width_bottom = 2
			style.border_color = Color("#10B981", 0.7)
			style.corner_radius_top_left = 999; style.corner_radius_top_right = 999
			style.corner_radius_bottom_left = 999; style.corner_radius_bottom_right = 999
			btn.add_theme_stylebox_override("normal", style)
			var style_h = style.duplicate()
			style_h.bg_color = Color("#10B981", 0.35)
			btn.add_theme_stylebox_override("hover", style_h)

func _on_settings_pressed():
	get_node("/root/Main").play_btn_sound()
	
	settings_overlay.visible = true
	settings_popup.visible = true
	settings_popup.modulate = Color(1, 1, 1, 0)  # Przezroczysty
	
	var popup_panel = settings_popup.get_node("PopupPanel")
	popup_panel.scale = Vector2(0.8, 0.8)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(settings_popup, "modulate", Color.WHITE, 0.3)
	tween.tween_property(popup_panel, "scale", Vector2.ONE, 0.3)

func _on_close_settings():
	get_node("/root/Main").play_btn_sound()
	var popup_panel = settings_popup.get_node("PopupPanel")
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(settings_popup, "modulate", Color(1, 1, 1, 0), 0.25)
	tween.tween_property(popup_panel, "scale", Vector2(0.8, 0.8), 0.25)
	
	tween.finished.connect(func():
		settings_overlay.visible = false
		settings_popup.visible = false
	)

func _on_toggle_pressed(btn: Button, circle: Panel, type: String, parent_vbox: VBoxContainer):
	var current_state = btn.get_meta("state")
	var new_state = !current_state
	btn.set_meta("state", new_state)
	
	# Update switch color
	var switch_style = btn.get_theme_stylebox("normal").duplicate()
	switch_style.bg_color = Color("00BC7D") if new_state else Color("3A3A50")
	btn.add_theme_stylebox_override("normal", switch_style)
	btn.add_theme_stylebox_override("hover", switch_style)
	btn.add_theme_stylebox_override("pressed", switch_style)
	
	# Animate circle position - POPRAWIONE POZYCJE
	var tween = create_tween()
	tween.tween_property(circle, "position", Vector2(54, 4) if new_state else Vector2(4, 4), 0.2)
	
	var main_node = get_node_or_null("/root/Main")
	if type == "Sound":
		sound_enabled = new_state
		if main_node and main_node.has_method("toggle_sound"):
			main_node.toggle_sound(new_state)
	elif type == "Music":
		music_enabled = new_state
		if main_node and main_node.has_method("toggle_music"):
			main_node.toggle_music(new_state)
	
	# Update state label - POPRAWKA: szukaj w parent_vbox zamiast btn.get_parent()
	var state_label = parent_vbox.get_node("StateLabel")
	if state_label:
		state_label.text = "ON" if new_state else "OFF"
	
	# Update actual sound/music settings
	if type == "Sound":
		sound_enabled = new_state
		get_node("/root/Main").toggle_sound(new_state)
		get_node("/root/Main").play_switch_sound()
	elif type == "Music":
		music_enabled = new_state
		get_node("/root/Main").toggle_music(new_state)
		get_node("/root/Main").play_switch_sound()

func _on_restart_pressed():
	print("Restart pressed")
	get_node("/root/Main").play_btn_sound()
	_on_close_settings()

	if hex_grid and hex_grid.has_meta("current_level_file"):
		var level_file = hex_grid.get_meta("current_level_file")
		if not level_file.is_empty() and hex_grid.has_method("load_layout_from_file"):
			await get_tree().create_timer(0.3).timeout
			if is_instance_valid(hex_grid):
				hex_grid.load_layout_from_file(level_file)
				print("Level restarted from settings: ", level_file)

func _on_howto_pressed():
	get_node("/root/Main").play_btn_sound()
	tab_changed.emit("howto")
	_on_close_settings()

func _on_store_pressed():
	get_node("/root/Main").play_btn_sound()
	tab_changed.emit("shop")
	_on_close_settings()

func _on_home_pressed():
	get_node("/root/Main").play_btn_sound()
	tab_changed.emit("home")
	_on_close_settings()
			
func reset_wall_button():
	"""Resetuje przycisk murów — używa ogólnego reset"""
	get_node("/root/Main").play_select_sound()
	reset_all_buy_buttons()
	
func set_wall_button_active(active: bool):
	"""Ustawia przycisk murów jako aktywny/nieaktywny"""
	get_node("/root/Main").play_select_sound()
	set_buy_button_active("wall", active)
				
func set_buttons_enabled(enabled: bool):
	"""Blokuje/odblokuje przyciski Next Round i Undo, odswiezа przyciski zakupu"""
	if undo_button and undo_button.has_meta("button"):
		var undo_btn = undo_button.get_meta("button")
		if is_instance_valid(undo_btn):
			undo_btn.disabled = not enabled
	
	if next_button and next_button.has_meta("button"):
		var next_btn = next_button.get_meta("button")
		if is_instance_valid(next_btn):
			next_btn.disabled = not enabled
	
	# Odswież przyciski zakupu — update_ui_data sprawdzi ai_is_playing i złoto
	update_ui_data()
