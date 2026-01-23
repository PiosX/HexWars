extends CanvasLayer
class_name UIManager

# --- COLORS ---
const BG_PANEL = Color("121218")
const BG_BOX = Color("1A1A28")
const BORDER_COLOR = Color("2A2A40")
const BORDER_HOVER = Color("2A2A40")

const TEAM_COLORS = {
	1: Color("#4D99FF"),  # Blue
	2: Color("#FF6467"),  # Red
	3: Color("#9B59FF"),  # Purple
	4: Color("#FFD645")   # Yellow
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

# Icons paths
const ICON_SETTINGS = "res://ui/settings.png"
const ICON_TIME = "res://ui/time.png"
const ICON_TURN = "res://turn.svg"
const ICON_COINS = "res://ui/coins.png"
const ICON_RETURN = "res://ui/return.png"
const ICON_NEXT = "res://ui/next.png"
const ICON_FARMER = "res://ui/farmer128.png"
const ICON_SPEARMAN = "res://ui/spear128.png"
const ICON_KNIGHT = "res://ui/sword128.png"
const ICON_CAVALRY = "res://ui/horse128.png"
const ICON_WALL = "res://ui/shield128.png"

func _ready():
	# Wait for hex_grid to be set
	await get_tree().process_frame
	setup_ui()

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
	top_content.add_child(settings_button)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_content.add_child(spacer1)
	
	# Turn label (center) - wewnątrz rounded boxa
	var turn_container = Panel.new()
	turn_container.custom_minimum_size = Vector2(160, 96)
	
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
	turn_label.size = Vector2(160, 96)
	turn_label.add_theme_font_size_override("font_size", 28)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	turn_container.add_child(turn_label)
	top_content.add_child(turn_container)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_content.add_child(spacer2)
	
	# Rewind counter (right) - BEZ BOXA, tylko ikona + tekst
	rewind_counter = HBoxContainer.new()
	rewind_counter.alignment = BoxContainer.ALIGNMENT_CENTER
	rewind_counter.add_theme_constant_override("separation", 8)
	rewind_counter.custom_minimum_size = Vector2(90, 96)
	
	var rewind_icon = TextureRect.new()
	rewind_icon.custom_minimum_size = Vector2(32, 32)
	rewind_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rewind_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewind_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rewind_icon.texture = load(ICON_TIME)
	rewind_counter.add_child(rewind_icon)
	
	var rewind_label = Label.new()
	rewind_label.name = "RewindLabel"
	rewind_label.text = "3"
	rewind_label.add_theme_font_size_override("font_size", 30)
	rewind_label.add_theme_color_override("font_color", Color.WHITE)
	rewind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rewind_counter.add_child(rewind_label)
	
	top_content.add_child(rewind_counter)
	
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
		{"name": "Cavalry", "icon": ICON_CAVALRY, "cost": 80, "upkeep": 2, "id": "cavalry"},
		{"name": "Wall", "icon": ICON_WALL, "cost": 3, "upkeep": 0, "id": "wall"}
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

func create_rounded_button(text: String, icon_path: String = "") -> Button:
	var btn = Button.new()
	btn.text = text
	
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
	hbox.add_child(team_dot)
	
	# FIXED: coin icon proper size
	var coin_icon = TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture = load(ICON_COINS)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(coin_icon)
	
	# FIXED: Gold + upkeep w JEDNEJ linii za pomocą RichTextLabel
	var rich_label = RichTextLabel.new()
	rich_label.name = "GoldUpkeepLabel"
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.scroll_active = false
	rich_label.custom_minimum_size = Vector2(80, 32)
	rich_label.add_theme_font_size_override("normal_font_size", 22)
	rich_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rich_label.text = "[color=white]0[/color] [color=#FF6467](-0)[/color]"
	hbox.add_child(rich_label)
	
	return box

func create_action_button(text: String, icon_path: String) -> VBoxContainer:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 6)
	
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(90, 90)
	
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
			btn.pressed.connect(func(): hex_grid._on_buy_farmer())
		"spearman":
			btn.pressed.connect(func(): hex_grid._on_buy_spearman())
		"knight":
			btn.pressed.connect(func(): hex_grid._on_buy_knight())
		"cavalry":
			btn.pressed.connect(func(): hex_grid._on_buy_cavalry())
		"wall":
			btn.pressed.connect(func(): hex_grid._on_buy_wall())
	
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
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color("10B981")  # emerald-500
	style_normal.corner_radius_top_left = 999
	style_normal.corner_radius_top_right = 999
	style_normal.corner_radius_bottom_left = 999
	style_normal.corner_radius_bottom_right = 999
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color("059669")  # emerald-600
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	
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

func update_ui_data():
	"""Called by hex_grid to update all UI elements"""
	# Safety check - make sure UI elements exist
	if not is_instance_valid(hex_grid) or not is_instance_valid(turn_label):
		print("UI not ready yet")
		return
	
	# Update turn label
	turn_label.text = "Turn %d" % hex_grid.current_round
	
	# Update rewind counter
	if is_instance_valid(rewind_counter):
		var rewind_label = rewind_counter.get_node("RewindLabel")
		if is_instance_valid(rewind_label):
			rewind_label.text = str(hex_grid.turn_history.get_rewinds_remaining())
	
	# Update undo button state
	if is_instance_valid(undo_button) and undo_button.has_meta("button"):
		var undo_btn = undo_button.get_meta("button")
		if is_instance_valid(undo_btn):
			undo_btn.disabled = not hex_grid.turn_history.can_rewind()
	
	# Update team boxes - FIXED: jedna linia dla gold + upkeep
	for i in range(4):
		var team = i + 1
		if i < team_boxes.size() and is_instance_valid(team_boxes[i]):
			var box = team_boxes[i]
			
			var hbox = box.get_node("HBoxContainer")
			if is_instance_valid(hbox):
				var rich_label = hbox.get_node("GoldUpkeepLabel")
				
				if is_instance_valid(rich_label):
					var gold = hex_grid.team_gold.get(team, 0)
					var upkeep = hex_grid.calculate_upkeep(team)
					
					# FIXED: jedna linia z białym złotem i czerwonym upkeep
					rich_label.text = "[color=white]%d[/color] [color=#FF6467](-%d)[/color]" % [gold, upkeep]
	
	# Update unit buttons availability
	if hex_grid.current_team in hex_grid.team_gold:
		var current_gold = hex_grid.team_gold[hex_grid.current_team]
		
		for unit_id in ["farmer", "spearman", "knight", "cavalry", "wall"]:
			if unit_id in unit_buttons and unit_buttons[unit_id].has_meta("button"):
				var btn = unit_buttons[unit_id].get_meta("button")
				if is_instance_valid(btn):
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
							btn.disabled = current_gold < 3
	
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
	
	for team in [1, 2, 3, 4]:
		var count = hex_grid.team_territory_count[team]
		if count > 0:
			var segment_width = (float(count) / total) * bar_width
			
			var segment = ColorRect.new()
			segment.color = TEAM_COLORS[team]
			segment.position = Vector2(current_x, 0)
			segment.size = Vector2(segment_width, bar_height)
			
			# Rounded corners for first and last segments
			if team == 1:
				var style = StyleBoxFlat.new()
				style.bg_color = TEAM_COLORS[team]
				style.corner_radius_top_left = 999
				style.corner_radius_bottom_left = 999
				var panel = Panel.new()
				panel.add_theme_stylebox_override("panel", style)
				panel.position = segment.position
				panel.size = segment.size
				dominance_bar.add_child(panel)
			elif team == 4 and hex_grid.team_territory_count.get(team, 0) > 0:
				var style = StyleBoxFlat.new()
				style.bg_color = TEAM_COLORS[team]
				style.corner_radius_top_right = 999
				style.corner_radius_bottom_right = 999
				var panel = Panel.new()
				panel.add_theme_stylebox_override("panel", style)
				panel.position = segment.position
				panel.size = segment.size
				dominance_bar.add_child(panel)
			else:
				dominance_bar.add_child(segment)
			
			current_x += segment_width

func _on_undo_pressed():
	if hex_grid:
		hex_grid._on_rewind_turn()

func _on_next_pressed():
	if hex_grid:
		hex_grid._on_end_turn()
		
func reset_wall_button():
	"""Resetuje przycisk murów do stanu początkowego"""
	if "wall" in unit_buttons and unit_buttons["wall"].has_meta("button"):
		var container = unit_buttons["wall"]
		var btn = container.get_meta("button")
		if is_instance_valid(btn):
			# Przywróć normalny styl
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
			btn.add_theme_stylebox_override("normal", style_normal)
			
func set_wall_button_active(active: bool):
	"""Ustawia przycisk murów jako aktywny/nieaktywny"""
	if "wall" in unit_buttons and unit_buttons["wall"].has_meta("button"):
		var container = unit_buttons["wall"]
		var btn = container.get_meta("button")
		if is_instance_valid(btn):
			if active:
				# POPRAWKA: Niebieski kolor (jak drużyna niebieska)
				var style_active = StyleBoxFlat.new()
				style_active.bg_color = Color("#4D99FF")  # Niebieski
				style_active.border_width_left = 2
				style_active.border_width_right = 2
				style_active.border_width_top = 2
				style_active.border_width_bottom = 2
				style_active.border_color = Color.WHITE
				style_active.corner_radius_top_left = 999
				style_active.corner_radius_top_right = 999
				style_active.corner_radius_bottom_left = 999
				style_active.corner_radius_bottom_right = 999
				btn.add_theme_stylebox_override("normal", style_active)
				
				var style_hover = style_active.duplicate()
				style_hover.bg_color = Color("#3D89EF")  # Trochę ciemniejszy niebieski
				btn.add_theme_stylebox_override("hover", style_hover)
			else:
				reset_wall_button()
