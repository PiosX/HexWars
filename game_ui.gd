extends CanvasLayer
class_name GameUI

# References
var hex_grid: HexGrid

# UI Elements - Top Panel
var top_panel: Panel
var settings_button: Button
var turn_label: Label
var rewind_counter: HBoxContainer
var rewind_icon: TextureRect
var rewind_label: Label
var dominance_bar: Control
var team_info_container: HBoxContainer

# UI Elements - Bottom Panel
var bottom_panel: Panel
var undo_button: VBoxContainer
var next_button: VBoxContainer
var units_container: HBoxContainer

# Colors
const BG_DARK = Color("#121218")
const BG_PANEL = Color("#1A1A28")
const BORDER_COLOR = Color("#2A2A40")
const BORDER_HOVER = Color("#2A2A40")
const RED_TEXT = Color("#FF6467")
const NEXT_GRADIENT_FROM = Color("#10B981")
const NEXT_GRADIENT_TO = Color("#059669")

const TEAM_COLORS = {
	1: Color("#4D99FF"),
	2: Color("#FF4D4D"),
	3: Color("#9B59FF"),
	4: Color("#FFD645")
}

func _init():
	layer = 100

func setup(grid: HexGrid):
	hex_grid = grid
	_create_top_panel()
	_create_bottom_panel()
	update_all()

# ============================================
# TOP PANEL
# ============================================

func _create_top_panel():
	top_panel = Panel.new()
	top_panel.size_flags_horizontal = Control.SIZE_FILL
	
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = BG_DARK
	top_style.border_width_bottom = 2
	top_style.border_color = BORDER_COLOR
	top_panel.add_theme_stylebox_override("panel", top_style)
	
	add_child(top_panel)
	
	var top_vbox = VBoxContainer.new()
	top_vbox.size_flags_horizontal = Control.SIZE_FILL
	top_vbox.add_theme_constant_override("separation", 12)
	top_panel.add_child(top_vbox)
	
	# Row 1: Settings | Turn | Rewinds
	var row1 = HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_FILL
	row1.add_theme_constant_override("separation", 12)
	top_vbox.add_child(row1)
	
	# Settings button
	settings_button = _create_rounded_button("ui/settings.svg", 32)
	row1.add_child(settings_button)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer1)
	
	# Turn label
	turn_label = Label.new()
	turn_label.text = "TURA 1"
	turn_label.add_theme_font_size_override("font_size", 16)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	
	var turn_panel = Panel.new()
	var turn_style = StyleBoxFlat.new()
	turn_style.bg_color = BG_PANEL
	turn_style.border_width_left = 2
	turn_style.border_width_right = 2
	turn_style.border_width_top = 2
	turn_style.border_width_bottom = 2
	turn_style.border_color = BORDER_COLOR
	turn_style.corner_radius_top_left = 20
	turn_style.corner_radius_top_right = 20
	turn_style.corner_radius_bottom_left = 20
	turn_style.corner_radius_bottom_right = 20
	turn_style.content_margin_left = 20
	turn_style.content_margin_right = 20
	turn_style.content_margin_top = 8
	turn_style.content_margin_bottom = 8
	turn_panel.add_theme_stylebox_override("panel", turn_style)
	turn_panel.add_child(turn_label)
	row1.add_child(turn_panel)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer2)
	
	# Rewind counter
	rewind_counter = HBoxContainer.new()
	rewind_counter.add_theme_constant_override("separation", 8)
	
	var rewind_panel = Panel.new()
	var rewind_style = StyleBoxFlat.new()
	rewind_style.bg_color = BG_PANEL
	rewind_style.border_width_left = 2
	rewind_style.border_width_right = 2
	rewind_style.border_width_top = 2
	rewind_style.border_width_bottom = 2
	rewind_style.border_color = BORDER_COLOR
	rewind_style.corner_radius_top_left = 20
	rewind_style.corner_radius_top_right = 20
	rewind_style.corner_radius_bottom_left = 20
	rewind_style.corner_radius_bottom_right = 20
	rewind_style.content_margin_left = 12
	rewind_style.content_margin_right = 12
	rewind_style.content_margin_top = 8
	rewind_style.content_margin_bottom = 8
	rewind_panel.add_theme_stylebox_override("panel", rewind_style)
	
	rewind_icon = TextureRect.new()
	rewind_icon.texture = load("res://ui/time.svg")
	rewind_icon.custom_minimum_size = Vector2(16, 16)
	rewind_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewind_counter.add_child(rewind_icon)
	
	rewind_label = Label.new()
	rewind_label.text = "3"
	rewind_label.add_theme_font_size_override("font_size", 16)
	rewind_label.add_theme_color_override("font_color", Color.WHITE)
	rewind_counter.add_child(rewind_label)
	
	rewind_panel.add_child(rewind_counter)
	row1.add_child(rewind_panel)
	
	# Row 2: Dominance bar
	dominance_bar = Control.new()
	dominance_bar.custom_minimum_size = Vector2(0, 30)
	dominance_bar.size_flags_horizontal = Control.SIZE_FILL
	top_vbox.add_child(dominance_bar)
	
	var dominance_draw = Node2D.new()
	dominance_draw.name = "DominanceDraw"
	dominance_bar.add_child(dominance_draw)
	
	# Row 3: Team info boxes
	team_info_container = HBoxContainer.new()
	team_info_container.size_flags_horizontal = Control.SIZE_FILL
	team_info_container.add_theme_constant_override("separation", 8)
	top_vbox.add_child(team_info_container)
	
	for team in [1, 2, 3, 4]:
		var team_box = _create_team_info_box(team)
		team_info_container.add_child(team_box)
	
	# Position top panel
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 12
	top_panel.offset_right = -12
	top_panel.offset_top = 12
	
	# Margin for content
	top_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_vbox.offset_left = 12
	top_vbox.offset_right = -12
	top_vbox.offset_top = 12
	top_vbox.offset_bottom = 12

func _create_team_info_box(team: int) -> Panel:
	var panel = Panel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style = StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.border_width_left = 3
	style.border_color = TEAM_COLORS[team]
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)
	
	# Color dot
	var dot = ColorRect.new()
	dot.color = TEAM_COLORS[team]
	dot.custom_minimum_size = Vector2(8, 8)
	hbox.add_child(dot)
	
	# Coins icon
	var coin_icon = TextureRect.new()
	coin_icon.texture = load("res://ui/coins.svg")
	coin_icon.custom_minimum_size = Vector2(16, 16)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(coin_icon)
	
	# Gold amount
	var gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "0"
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(gold_label)
	
	# Upkeep (red)
	var upkeep_label = Label.new()
	upkeep_label.name = "UpkeepLabel"
	upkeep_label.text = "(-0)"
	upkeep_label.add_theme_font_size_override("font_size", 12)
	upkeep_label.add_theme_color_override("font_color", RED_TEXT)
	hbox.add_child(upkeep_label)
	
	panel.set_meta("team", team)
	
	return panel

# ============================================
# BOTTOM PANEL
# ============================================

func _create_bottom_panel():
	bottom_panel = Panel.new()
	bottom_panel.size_flags_horizontal = Control.SIZE_FILL
	
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = BG_DARK
	bottom_style.border_width_top = 2
	bottom_style.border_color = BORDER_COLOR
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	
	add_child(bottom_panel)
	
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.size_flags_horizontal = Control.SIZE_FILL
	bottom_hbox.add_theme_constant_override("separation", 12)
	bottom_panel.add_child(bottom_hbox)
	
	# Undo button
	undo_button = _create_bottom_action_button("ui/return.svg", "COFNIJ")
	undo_button.name = "UndoButton"
	bottom_hbox.add_child(undo_button)
	
	# Units container
	units_container = HBoxContainer.new()
	units_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units_container.alignment = BoxContainer.ALIGNMENT_CENTER
	units_container.add_theme_constant_override("separation", 8)
	bottom_hbox.add_child(units_container)
	
	# Create 5 unit buttons
	var units = [
		{"name": "Farmer", "cost": 10, "upkeep": 2, "icon": "ui/farmer.svg"},
		{"name": "Spearman", "cost": 20, "upkeep": 6, "icon": "ui/spearman.svg"},
		{"name": "Knight", "cost": 40, "upkeep": 18, "icon": "ui/knight.svg"},
		{"name": "Cavalry", "cost": 80, "upkeep": 2, "icon": "ui/cavalry.svg"},
		{"name": "Wall", "cost": 3, "upkeep": 0, "icon": "ui/wall.svg"}
	]
	
	for unit_data in units:
		var unit_button = _create_unit_button(unit_data)
		units_container.add_child(unit_button)
	
	# Next button
	next_button = _create_next_button()
	next_button.name = "NextButton"
	bottom_hbox.add_child(next_button)
	
	# Position bottom panel
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 12
	bottom_panel.offset_right = -12
	bottom_panel.offset_bottom = -12
	
	# Margin for content
	bottom_hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_hbox.offset_left = 12
	bottom_hbox.offset_right = -12
	bottom_hbox.offset_top = 12
	bottom_hbox.offset_bottom = -12

func _create_rounded_button(icon_path: String, size: int = 24) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(40, 40)
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BG_PANEL
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = BORDER_COLOR
	normal_style.corner_radius_top_left = 20
	normal_style.corner_radius_top_right = 20
	normal_style.corner_radius_bottom_left = 20
	normal_style.corner_radius_bottom_right = 20
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = BORDER_HOVER
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
	
	var icon = TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(size, size)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	
	icon.set_anchors_preset(Control.PRESET_CENTER)
	
	return button

func _create_bottom_action_button(icon_path: String, label_text: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var button = Button.new()
	button.custom_minimum_size = Vector2(50, 50)
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BG_PANEL
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = BORDER_COLOR
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = BORDER_HOVER
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
	
	var icon = TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	
	vbox.add_child(button)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	return vbox

func _create_next_button() -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var button = Button.new()
	button.custom_minimum_size = Vector2(50, 50)
	
	# Gradient effect with StyleBoxFlat
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = NEXT_GRADIENT_FROM
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = NEXT_GRADIENT_FROM.lightened(0.2)
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
	
	var icon = TextureRect.new()
	icon.texture = load("res://ui/next.svg")
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	
	vbox.add_child(button)
	
	var label = Label.new()
	label.text = "TURA"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	# Connect to hex_grid's end turn
	button.pressed.connect(func(): 
		if hex_grid:
			hex_grid._on_end_turn()
	)
	
	return vbox

func _create_unit_button(unit_data: Dictionary) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(70, 90)
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BG_PANEL
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = BORDER_COLOR
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	
	panel.add_theme_stylebox_override("panel", normal_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 4
	vbox.offset_right = -4
	vbox.offset_top = 4
	vbox.offset_bottom = -4
	
	# Icon square
	var icon_bg = Panel.new()
	icon_bg.custom_minimum_size = Vector2(40, 40)
	
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = TEAM_COLORS.get(hex_grid.current_team if hex_grid else 1, Color.WHITE)
	icon_style.corner_radius_top_left = 8
	icon_style.corner_radius_top_right = 8
	icon_style.corner_radius_bottom_left = 8
	icon_style.corner_radius_bottom_right = 8
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	
	var icon = TextureRect.new()
	icon.texture = load(unit_data.icon)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_bg.add_child(icon)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	
	vbox.add_child(icon_bg)
	
	# Name label
	var name_label = Label.new()
	name_label.text = unit_data.name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# Cost row
	var cost_hbox = HBoxContainer.new()
	cost_hbox.add_theme_constant_override("separation", 4)
	cost_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var coin_icon = TextureRect.new()
	coin_icon.texture = load("res://ui/coins.svg")
	coin_icon.custom_minimum_size = Vector2(12, 12)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cost_hbox.add_child(coin_icon)
	
	var cost_label = Label.new()
	cost_label.text = str(unit_data.cost)
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", Color.WHITE)
	cost_hbox.add_child(cost_label)
	
	if unit_data.upkeep > 0:
		var upkeep_label = Label.new()
		upkeep_label.text = "(-%d)" % unit_data.upkeep
		upkeep_label.add_theme_font_size_override("font_size", 9)
		upkeep_label.add_theme_color_override("font_color", RED_TEXT)
		cost_hbox.add_child(upkeep_label)
	
	vbox.add_child(cost_hbox)
	
	# Make panel clickable
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_unit_button_pressed(unit_data.name.to_lower())
	)
	
	# Hover effect
	panel.mouse_entered.connect(func():
		normal_style.bg_color = BORDER_HOVER
	)
	panel.mouse_exited.connect(func():
		normal_style.bg_color = BG_PANEL
	)
	
	panel.set_meta("unit_type", unit_data.name.to_lower())
	
	return panel

func _on_unit_button_pressed(unit_type: String):
	if not hex_grid:
		return
	
	match unit_type:
		"farmer":
			hex_grid._on_buy_farmer()
		"spearman":
			hex_grid._on_buy_spearman()
		"knight":
			hex_grid._on_buy_knight()
		"cavalry":
			hex_grid._on_buy_cavalry()
		"wall":
			hex_grid._on_buy_wall()

# ============================================
# UPDATE FUNCTIONS
# ============================================

func update_all():
	update_turn()
	update_rewinds()
	update_dominance_bar()
	update_team_info()

func update_turn():
	if turn_label and hex_grid:
		turn_label.text = "TURA %d" % hex_grid.current_round

func update_rewinds():
	if rewind_label and hex_grid and hex_grid.turn_history:
		rewind_label.text = str(hex_grid.turn_history.get_rewinds_remaining())

func update_dominance_bar():
	if not dominance_bar or not hex_grid:
		return
	
	var draw_node = dominance_bar.get_node_or_null("DominanceDraw")
	if not draw_node:
		return
	
	hex_grid.update_territory_counts()
	
	var total = 0
	for count in hex_grid.team_territory_count.values():
		total += count
	
	if total == 0:
		for child in draw_node.get_children():
			child.queue_free()
		return
	
	var bar_width = dominance_bar.size.x
	var bar_height = dominance_bar.size.y
	var target_widths = {}
	var current_x = 0.0
	
	for team in [1, 2, 3, 4]:
		var count = hex_grid.team_territory_count[team]
		if count > 0:
			var segment_width = (float(count) / total) * bar_width
			target_widths[team] = {"x": current_x, "width": segment_width}
			current_x += segment_width
	
	var existing_segments = {}
	for child in draw_node.get_children():
		if child.has_meta("team"):
			existing_segments[child.get_meta("team")] = child
	
	for team in [1, 2, 3, 4]:
		if not target_widths.has(team):
			if existing_segments.has(team):
				var segment = existing_segments[team]
				var tween = create_tween()
				tween.tween_property(segment, "size:x", 0, 0.3)
				tween.tween_callback(segment.queue_free)
			continue
		
		var target = target_widths[team]
		var segment = null
		
		if existing_segments.has(team):
			segment = existing_segments[team]
		else:
			segment = ColorRect.new()
			segment.color = TEAM_COLORS[team]
			segment.position = Vector2(target.x, 0)
			segment.size = Vector2(0, bar_height)
			segment.set_meta("team", team)
			
			# Rounded corners
			var style = StyleBoxFlat.new()
			style.bg_color = TEAM_COLORS[team]
			style.corner_radius_top_left = 15
			style.corner_radius_top_right = 15
			style.corner_radius_bottom_left = 15
			style.corner_radius_bottom_right = 15
			
			draw_node.add_child(segment)
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(segment, "position:x", target.x, 0.5)
		tween.tween_property(segment, "size:x", target.width, 0.5)

func update_team_info():
	if not hex_grid or not team_info_container:
		return
	
	for child in team_info_container.get_children():
		if not child.has_meta("team"):
			continue
		
		var team = child.get_meta("team")
		var gold_label = child.get_node_or_null("HBoxContainer/GoldLabel")
		var upkeep_label = child.get_node_or_null("HBoxContainer/UpkeepLabel")
		
		if gold_label:
			gold_label.text = str(hex_grid.team_gold.get(team, 0))
		
		if upkeep_label:
			var upkeep = hex_grid.calculate_upkeep(team)
			upkeep_label.text = "(-%d)" % upkeep
