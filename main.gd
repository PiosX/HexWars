extends Node

const MAIN_MENU = preload("res://home.tscn")
const SHOP_MENU = preload("res://shop.tscn")
const LEVEL_SELECT = preload("res://levels.tscn")
const HEX_GRID_SCENE = preload("res://main_scene.tscn")
const HOWTO_MENU = preload("res://howto.tscn")

# Ścieżka do pliku zapisu
const SAVE_FILE_PATH = "user://game_data.save"

var current_scene = null
var current_level_number: int = 0
var global_time_currency: int = 10

var btn_sound: AudioStreamPlayer
var switch_sound: AudioStreamPlayer
var select_sound: AudioStreamPlayer
var put_sound: AudioStreamPlayer
var defeat_sound: AudioStreamPlayer
var victory_sound: AudioStreamPlayer
var background_music: AudioStreamPlayer

var sound_enabled: bool = true
var music_enabled: bool = true

func _ready():
	load_game_data()  # Wczytaj zapisane dane na początku
	setup_audio()
	change_scene(MAIN_MENU)

# ========== SYSTEM ZAPISU/WCZYTYWANIA ==========

func save_game_data():
	"""Zapisuje dane gry do pliku"""
	var save_data = {
		"global_time_currency": global_time_currency,
		"sound_enabled": sound_enabled,
		"music_enabled": music_enabled
	}
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		print("✓ Game data saved: Currency = %d" % global_time_currency)
	else:
		print("✗ Failed to save game data")

func load_game_data():
	"""Wczytuje dane gry z pliku"""
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("ℹ No save file found, using default values")
		return
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var save_data = file.get_var()
		file.close()
		
		if save_data is Dictionary:
			if save_data.has("global_time_currency"):
				global_time_currency = save_data["global_time_currency"]
			if save_data.has("sound_enabled"):
				sound_enabled = save_data["sound_enabled"]
			if save_data.has("music_enabled"):
				music_enabled = save_data["music_enabled"]
			
			print("✓ Game data loaded: Currency = %d" % global_time_currency)
	else:
		print("✗ Failed to load game data")

func add_currency(amount: int):
	"""Dodaje walutę i automatycznie zapisuje"""
	global_time_currency += amount
	save_game_data()
	print("Currency added: +%d (Total: %d)" % [amount, global_time_currency])

func spend_currency(amount: int) -> bool:
	"""Zużywa walutę jeśli jest wystarczająco dużo. Zwraca true jeśli się udało."""
	if global_time_currency >= amount:
		global_time_currency -= amount
		save_game_data()
		print("Currency spent: -%d (Remaining: %d)" % [amount, global_time_currency])
		return true
	else:
		print("Not enough currency! Need: %d, Have: %d" % [amount, global_time_currency])
		return false

func get_currency() -> int:
	"""Zwraca aktualną ilość waluty"""
	return global_time_currency

# ========== AUDIO SETUP ==========

func setup_audio():
	"""Tworzy wszystkie AudioStreamPlayer'y"""
	print("=== SETTING UP AUDIO ===")
	
	# Button sound
	btn_sound = AudioStreamPlayer.new()
	btn_sound.name = "ButtonSound"
	btn_sound.stream = load("res://sounds/btn.mp3")
	btn_sound.bus = "Master"
	add_child(btn_sound)
	print("✓ Button sound loaded")
	
	# Switch sound
	switch_sound = AudioStreamPlayer.new()
	switch_sound.name = "SwitchSound"
	switch_sound.stream = load("res://sounds/switch.mp3")
	switch_sound.bus = "Master"
	add_child(switch_sound)
	print("✓ Switch sound loaded")
	
	# Select sound
	select_sound = AudioStreamPlayer.new()
	select_sound.name = "SelectSound"
	select_sound.stream = load("res://sounds/select.mp3")
	select_sound.bus = "Master"
	add_child(select_sound)
	print("✓ Select sound loaded")
	
	# Put sound
	put_sound = AudioStreamPlayer.new()
	put_sound.name = "PutSound"
	put_sound.stream = load("res://sounds/put.mp3")
	put_sound.bus = "Master"
	add_child(put_sound)
	print("✓ Put sound loaded")
	
	# Defeat sound
	defeat_sound = AudioStreamPlayer.new()
	defeat_sound.name = "DefeatSound"
	defeat_sound.stream = load("res://sounds/defeat.mp3")
	defeat_sound.bus = "Master"
	add_child(defeat_sound)
	print("✓ Defeat sound loaded")
	
	# Victory sound
	victory_sound = AudioStreamPlayer.new()
	victory_sound.name = "VictorySound"
	victory_sound.stream = load("res://sounds/victory.mp3")
	victory_sound.bus = "Master"
	add_child(victory_sound)
	print("✓ Victory sound loaded")
	
	# Background music (loop)
	background_music = AudioStreamPlayer.new()
	background_music.name = "BackgroundMusic"
	var music_stream = load("res://sounds/background.mp3")
	if music_stream is AudioStreamMP3:
		music_stream.loop = true
	background_music.stream = music_stream
	background_music.bus = "Master"
	add_child(background_music)
	
	# Włącz muzykę tylko jeśli music_enabled = true (wczytane z zapisu)
	if music_enabled:
		background_music.play()
		print("✓ Background music loaded and playing")
	else:
		print("✓ Background music loaded (but disabled)")
	
	print("=== AUDIO SETUP COMPLETE ===")

func play_btn_sound():
	if sound_enabled and btn_sound and btn_sound.stream:
		print("🔊 Playing button sound")
		btn_sound.play()

func play_switch_sound():
	if sound_enabled and switch_sound and switch_sound.stream:
		print("🔊 Playing switch sound")
		switch_sound.play()

func play_select_sound():
	if sound_enabled and select_sound and select_sound.stream:
		print("🔊 Playing select sound")
		select_sound.play()
		
func play_put_sound():
	if sound_enabled and put_sound and put_sound.stream:
		print("🔊 Playing select sound")
		put_sound.play()

func play_defeat_sound():
	if sound_enabled and defeat_sound and defeat_sound.stream:
		print("🔊 Playing defeat sound")
		defeat_sound.play()

func play_victory_sound():
	if sound_enabled and victory_sound and victory_sound.stream:
		print("🔊 Playing victory sound")
		victory_sound.play()

func toggle_sound(enabled: bool):
	sound_enabled = enabled
	save_game_data()  # Zapisz ustawienia
	print("Sound %s" % ("enabled" if enabled else "disabled"))

func toggle_music(enabled: bool):
	music_enabled = enabled
	save_game_data()  # Zapisz ustawienia
	if background_music:
		if enabled:
			if not background_music.playing:
				background_music.play()
		else:
			background_music.stop()
	print("Music %s" % ("enabled" if enabled else "disabled"))

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
	
	if new_scene.has_signal("play_pressed"):
		new_scene.play_pressed.connect(_on_play_pressed)

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

func _on_play_pressed(level_file: String, difficulty: int, level_num: int):
	"""Handles play button press from main menu"""
	current_level_number = level_num
	load_game_level(level_file, difficulty, level_num)

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
		
		# Synchronizuj ustawienia audio z UI
		sync_audio_settings_to_ui(ui_manager)

func sync_audio_settings_to_ui(ui_manager):
	"""Synchronizuje stan audio (sound_enabled, music_enabled) z przełącznikami w UI"""
	if not ui_manager:
		return
	
	# Ustaw stan w ui_manager
	ui_manager.sound_enabled = sound_enabled
	ui_manager.music_enabled = music_enabled
	
	print("✓ Audio settings synced to UI: Sound=%s, Music=%s" % [sound_enabled, music_enabled])

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
			
			# Poczekaj chwilę na zakończenie ładowania
			await get_tree().process_frame
			await get_tree().process_frame
			
			# JAWNIE odblokuj przyciski po retry
			if hex_grid.ui_manager:
				hex_grid.ui_manager.set_buttons_enabled(true)
				print("DEBUG: Przyciski odblokowane po retry")
