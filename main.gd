extends Node

const MAIN_MENU = preload("res://home.tscn")
const SHOP_MENU = preload("res://shop.tscn")
const LEVEL_SELECT = preload("res://levels.tscn")
const HEX_GRID_SCENE = preload("res://main_scene.tscn")
const HOWTO_MENU = preload("res://howto.tscn")

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
		"howto":
			change_scene(HOWTO_MENU)

func _on_level_selected(level_file: String, difficulty: int):
	if current_scene and current_scene.has_method("get_selected_level_number"):
		current_level_number = current_scene.get_selected_level_number()
	
	load_game_level(level_file, difficulty, current_level_number)

func load_game_level(level_file: String, difficulty: int, level_num: int = 0):
	if current_scene:
		current_scene.queue_free()
	
	var main_scene = HEX_GRID_SCENE.instantiate()
	add_child(main_scene)
	current_scene = main_scene
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	var hex_grid = main_scene.get_node_or_null("HexGrid")
	if not hex_grid:
		return
	
	var wait_count = 0
	while not hex_grid.ui_manager and wait_count < 20:
		await get_tree().process_frame
		wait_count += 1
	
	if not hex_grid.ui_manager:
		await get_tree().process_frame
	
	hex_grid.set_meta("current_level_file", level_file)
	hex_grid.current_level_file = level_file
	
	if level_num > 0:
		hex_grid.set("current_level_number", level_num)
	
	if hex_grid.has_method("load_layout_from_file"):
		hex_grid.load_layout_from_file(level_file)
	
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
	
	if hex_grid.ui_manager:
		var ui_manager = hex_grid.ui_manager
		
		if ui_manager.tab_changed.is_connected(_on_tab_changed):
			ui_manager.tab_changed.disconnect(_on_tab_changed)
		
		ui_manager.tab_changed.connect(_on_tab_changed)

func _on_victory_home():
	change_scene(MAIN_MENU)

func _on_victory_next():
	change_scene(LEVEL_SELECT)

func _on_defeat_home():
	change_scene(MAIN_MENU)

func _on_defeat_retry():
	var hex_grid = null
	
	if current_scene and current_scene.has_node("HexGrid"):
		hex_grid = current_scene.get_node("HexGrid")
	else:
		for child in current_scene.get_children():
			if child is HexGrid:
				hex_grid = child
				break
	
	if hex_grid and hex_grid.has_meta("current_level_file"):
		var level_file = hex_grid.get_meta("current_level_file")
		if not level_file.is_empty() and hex_grid.has_method("load_layout_from_file"):
			hex_grid.load_layout_from_file(level_file)
