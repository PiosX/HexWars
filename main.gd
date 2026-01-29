extends Node

# Preload scenes
const MAIN_MENU = preload("res://home.tscn")
const SHOP_MENU = preload("res://shop.tscn")
const LEVEL_SELECT = preload("res://levels.tscn")
const HEX_GRID_SCENE = preload("res://main_scene.tscn")

var current_scene = null
var current_level_number: int = 0

func _ready():
	change_scene(MAIN_MENU)

func change_scene(scene_resource):
	if current_scene:
		current_scene.queue_free()
	
	var new_scene = scene_resource.instantiate()
	add_child(new_scene)
	current_scene = new_scene
	
	if new_scene.has_signal("tab_changed"):
		new_scene.tab_changed.connect(_on_tab_changed)
	
	if new_scene.has_signal("level_selected"):
		new_scene.level_selected.connect(_on_level_selected)

func _on_tab_changed(tab_name: String):
	match tab_name:
		"home":
			change_scene(MAIN_MENU)
		"shop":
			change_scene(SHOP_MENU)
		"levels":
			change_scene(LEVEL_SELECT)

func _on_level_selected(level_file: String, difficulty: int):
	if current_scene and current_scene.has_method("get_selected_level_number"):
		current_level_number = current_scene.get_selected_level_number()
	
	load_game_level(level_file, difficulty, current_level_number)

func load_game_level(level_file: String, difficulty: int, level_num: int = 0):
	"""Loads a game level from the specified file"""
	if current_scene:
		current_scene.queue_free()
	
	# Create scene instance
	var hex_grid = HEX_GRID_SCENE.instantiate()
	add_child(hex_grid)
	current_scene = hex_grid
	
	# Wait for _ready to complete
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Find the actual HexGrid node (it's a child of the wrapper)
	for child in hex_grid.get_children():
		if child.has_method("load_layout_from_file"):
			hex_grid = child
			break
	
	# Set level number
	if level_num > 0:
		hex_grid.set("current_level_number", level_num)
	
	# Load the level file
	if hex_grid.has_method("load_layout_from_file"):
		hex_grid.load_layout_from_file(level_file)
	
	# Connect victory/defeat signals
	if hex_grid.has_meta("victory_popup"):
		var victory_popup = hex_grid.get_meta("victory_popup")
		
		if victory_popup.home_pressed.is_connected(_on_victory_home):
			victory_popup.home_pressed.disconnect(_on_victory_home)
		if victory_popup.next_pressed.is_connected(_on_victory_next):
			victory_popup.next_pressed.disconnect(_on_victory_next)
		
		victory_popup.home_pressed.connect(_on_victory_home)
		victory_popup.next_pressed.connect(_on_victory_next)
	
	if hex_grid.has_meta("defeat_popup"):
		var defeat_popup = hex_grid.get_meta("defeat_popup")
		
		if defeat_popup.home_pressed.is_connected(_on_defeat_home):
			defeat_popup.home_pressed.disconnect(_on_defeat_home)
		if defeat_popup.retry_pressed.is_connected(_on_defeat_retry):
			defeat_popup.retry_pressed.disconnect(_on_defeat_retry)
		
		defeat_popup.home_pressed.connect(_on_defeat_home)
		defeat_popup.retry_pressed.connect(_on_defeat_retry)

func _on_victory_home():
	change_scene(LEVEL_SELECT)

func _on_victory_next():
	change_scene(LEVEL_SELECT)

func _on_defeat_home():
	change_scene(LEVEL_SELECT)

func _on_defeat_retry():
	if current_scene and current_scene.has_method("load_layout_from_file"):
		var level_file = current_scene.get_meta("current_level_file", "")
		if not level_file.is_empty():
			current_scene.load_layout_from_file(level_file)
