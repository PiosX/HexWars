extends Node

# Preload scenes
const MAIN_MENU = preload("res://home.tscn")
const SHOP_MENU = preload("res://shop.tscn")

var current_scene = null

func _ready():
	print("=== MAIN.GD START ===")
	# Załaduj main_menu jako pierwszą scenę
	change_scene(MAIN_MENU)

func change_scene(scene_resource):
	print("=== CHANGE SCENE called ===")
	
	# Usuń poprzednią scenę
	if current_scene:
		print("Removing old scene...")
		current_scene.queue_free()
	
	# Załaduj nową scenę
	print("Instantiating new scene...")
	var new_scene = scene_resource.instantiate()
	add_child(new_scene)
	current_scene = new_scene
	print("New scene added: ", new_scene.name)
	
	# Podłącz sygnał zmiany zakładki
	if new_scene.has_signal("tab_changed"):
		print("Connecting tab_changed signal...")
		new_scene.tab_changed.connect(_on_tab_changed)
		print("Signal connected!")
	else:
		print("WARNING: Scene doesn't have tab_changed signal!")

func _on_tab_changed(tab_name: String):
	print("=== TAB CHANGED: ", tab_name, " ===")
	print("Current scene before change: ", current_scene)
	
	match tab_name:
		"home":
			print("Switching to HOME")
			change_scene(MAIN_MENU)
		"shop":
			print("Switching to SHOP")
			change_scene(SHOP_MENU)
		"levels":
			print("LEVELS - nie ma jeszcze sceny")
		"howto":
			print("HOW TO - nie ma jeszcze sceny")
		_:
			print("Unknown tab: ", tab_name)
