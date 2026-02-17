extends Node
# Main.gd - Rozszerzona wersja z obsługą IAP i trwałym zapisem
# Zastąp swój obecny main.gd tym plikiem

const MAIN_MENU = preload("res://home.tscn")
const SHOP_MENU = preload("res://shop.tscn")
const LEVEL_SELECT = preload("res://levels.tscn")
const HEX_GRID_SCENE = preload("res://main_scene.tscn")
const HOWTO_MENU = preload("res://howto.tscn")

# ===== ŚCIEŻKA ZAPISU =====
const SAVE_FILE_PATH = "user://game_data.save"
const SAVE_VERSION = 2  # Zwiększ gdy zmieniasz format zapisu

# ===== SCENY I POZIOMY =====
var current_scene = null
var current_level_number: int = 0

# ===== WALUTA I PROGRES =====
var global_time_currency: int = 10
var completed_levels: Array = []  # Lista ukończonych poziomów [1, 2, 3, ...]
var high_scores: Dictionary = {}  # {level_num: best_time}

# ===== ZAKUPY =====
var ads_disabled: bool = false
var purchased_products: Array = []  # Lista zakupionych produktów

# ===== AUDIO =====
var btn_sound: AudioStreamPlayer
var switch_sound: AudioStreamPlayer
var select_sound: AudioStreamPlayer
var put_sound: AudioStreamPlayer
var defeat_sound: AudioStreamPlayer
var victory_sound: AudioStreamPlayer
var background_music: AudioStreamPlayer

var sound_enabled: bool = true
var music_enabled: bool = true

# ===== STATYSTYKI =====
var total_playtime: float = 0.0  # Sekundy
var total_levels_completed: int = 0
var total_ads_watched: int = 0

func _ready():
	print("=== MAIN NODE STARTING ===")
	load_game_data()
	setup_audio()
	change_scene(MAIN_MENU)
	
	# Pokaż banner w menu głównym
	var admob = get_node_or_null("/root/AdMobManager")
	if admob and admob.has_method("show_banner"):
		admob.show_banner()

# ========== SYSTEM ZAPISU/WCZYTYWANIA ==========

func save_game_data():
	"""Zapisuje wszystkie dane gry do pliku"""
	var save_data = {
		"version": SAVE_VERSION,
		
		# Waluta i progres
		"global_time_currency": global_time_currency,
		"completed_levels": completed_levels,
		"high_scores": high_scores,
		
		# Ustawienia
		"sound_enabled": sound_enabled,
		"music_enabled": music_enabled,
		
		# Zakupy
		"ads_disabled": ads_disabled,
		"purchased_products": purchased_products,
		
		# Statystyki
		"total_playtime": total_playtime,
		"total_levels_completed": total_levels_completed,
		"total_ads_watched": total_ads_watched,
		
		# Timestamp
		"last_save": Time.get_unix_time_from_system()
	}
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		print("✅ Game data saved (Currency: %d, Completed: %d levels)" % [global_time_currency, completed_levels.size()])
		return true
	else:
		print("❌ Failed to save game data")
		return false

func load_game_data():
	"""Wczytuje dane gry z pliku"""
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("ℹ️ No save file found, using default values")
		return
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if not file:
		print("❌ Failed to open save file")
		return
	
	var save_data = file.get_var()
	file.close()
	
	if not save_data is Dictionary:
		print("⚠️ Invalid save data format")
		return
	
	# Sprawdź wersję
	var version = save_data.get("version", 1)
	if version < SAVE_VERSION:
		print("ℹ️ Migrating save data from version %d to %d" % [version, SAVE_VERSION])
		save_data = migrate_save_data(save_data, version)
	
	# Wczytaj dane
	global_time_currency = save_data.get("global_time_currency", 10)
	completed_levels = save_data.get("completed_levels", [])
	high_scores = save_data.get("high_scores", {})
	
	sound_enabled = save_data.get("sound_enabled", true)
	music_enabled = save_data.get("music_enabled", true)
	
	ads_disabled = save_data.get("ads_disabled", false)
	purchased_products = save_data.get("purchased_products", [])
	
	total_playtime = save_data.get("total_playtime", 0.0)
	total_levels_completed = save_data.get("total_levels_completed", 0)
	total_ads_watched = save_data.get("total_ads_watched", 0)
	
	print("✅ Game data loaded:")
	print("   - Currency: %d" % global_time_currency)
	print("   - Completed levels: %d" % completed_levels.size())
	print("   - Ads disabled: %s" % ads_disabled)

func migrate_save_data(old_data: Dictionary, from_version: int) -> Dictionary:
	"""Migruje stare dane do nowej wersji"""
	# Przykład migracji z v1 do v2
	if from_version == 1:
		if not old_data.has("completed_levels"):
			old_data["completed_levels"] = []
		if not old_data.has("high_scores"):
			old_data["high_scores"] = {}
	
	old_data["version"] = SAVE_VERSION
	return old_data

# ========== WALUTA ==========

func add_currency(amount: int):
	"""Dodaje walutę i zapisuje"""
	global_time_currency += amount
	save_game_data()
	print("💰 Currency +%d (Total: %d)" % [amount, global_time_currency])
	
	# Aktualizuj UI jeśli istnieje
	update_currency_displays()

func spend_currency(amount: int) -> bool:
	"""Zużywa walutę jeśli wystarczy. Zwraca true jeśli się udało."""
	if global_time_currency >= amount:
		global_time_currency -= amount
		save_game_data()
		print("💸 Currency -%d (Remaining: %d)" % [amount, global_time_currency])
		update_currency_displays()
		return true
	else:
		print("⚠️ Not enough currency! Need: %d, Have: %d" % [amount, global_time_currency])
		return false

func get_currency() -> int:
	"""Zwraca aktualną ilość waluty"""
	return global_time_currency

func update_currency_displays():
	"""Aktualizuje wyświetlanie waluty we wszystkich scenach"""
	if current_scene and current_scene.has_method("set_currency"):
		current_scene.set_currency(global_time_currency)

# ========== PROGRES GRY ==========

func complete_level(level_number: int, completion_time: float = 0.0):
	"""Oznacza poziom jako ukończony"""
	if level_number not in completed_levels:
		completed_levels.append(level_number)
		total_levels_completed += 1
		print("🎯 Level %d completed!" % level_number)
	
	# Zapisz najlepszy czas
	if completion_time > 0:
		var level_key = str(level_number)
		if not high_scores.has(level_key) or completion_time < high_scores[level_key]:
			high_scores[level_key] = completion_time
			print("⭐ New best time for level %d: %.2fs" % [level_number, completion_time])
	
	save_game_data()
	
	# Pokaż interstitial co kilka poziomów
	var admob = get_node_or_null("/root/AdMobManager")
	if admob and admob.has_method("try_show_interstitial_after_level"):
		admob.try_show_interstitial_after_level()

func is_level_completed(level_number: int) -> bool:
	"""Sprawdza czy poziom został ukończony"""
	return level_number in completed_levels

func get_level_best_time(level_number: int) -> float:
	"""Zwraca najlepszy czas dla poziomu (0 jeśli nie ukończono)"""
	var level_key = str(level_number)
	return high_scores.get(level_key, 0.0)

func get_total_stars() -> int:
	"""Zwraca liczbę gwiazdek (np. 1 gwiazdka za każdy ukończony poziom)"""
	return completed_levels.size()

# ========== ZAKUPY I REKLAMY ==========

func set_ads_disabled(disabled: bool):
	"""Ustawia status wyłączenia reklam"""
	ads_disabled = disabled
	if disabled and "no_ads" not in purchased_products:
		purchased_products.append("no_ads")
	save_game_data()
	print("📵 Ads %s" % ("DISABLED" if disabled else "ENABLED"))

func get_ads_disabled() -> bool:
	"""Zwraca status wyłączenia reklam"""
	return ads_disabled

func add_purchased_product(product_id: String):
	"""Dodaje produkt do listy zakupów"""
	if product_id not in purchased_products:
		purchased_products.append(product_id)
		save_game_data()
		print("🛒 Product purchased: %s" % product_id)

func owns_product(product_id: String) -> bool:
	"""Sprawdza czy gracz posiada produkt"""
	return product_id in purchased_products

func on_rewarded_ad_watched():
	"""Callback po obejrzeniu reklamy z nagrodą"""
	total_ads_watched += 1
	save_game_data()

# ========== STATYSTYKI ==========

func add_playtime(seconds: float):
	"""Dodaje czas gry"""
	total_playtime += seconds
	# Nie zapisujemy przy każdym wywołaniu - tylko przy innych zapisach

func get_playtime_formatted() -> String:
	"""Zwraca sformatowany czas gry"""
	var hours = int(total_playtime) / 3600
	var minutes = (int(total_playtime) % 3600) / 60
	return "%dh %dm" % [hours, minutes]

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
	
	# Switch sound
	switch_sound = AudioStreamPlayer.new()
	switch_sound.name = "SwitchSound"
	switch_sound.stream = load("res://sounds/switch.mp3")
	switch_sound.bus = "Master"
	add_child(switch_sound)
	
	# Select sound
	select_sound = AudioStreamPlayer.new()
	select_sound.name = "SelectSound"
	select_sound.stream = load("res://sounds/select.mp3")
	select_sound.bus = "Master"
	add_child(select_sound)
	
	# Put sound
	put_sound = AudioStreamPlayer.new()
	put_sound.name = "PutSound"
	put_sound.stream = load("res://sounds/put.mp3")
	put_sound.bus = "Master"
	add_child(put_sound)
	
	# Defeat sound
	defeat_sound = AudioStreamPlayer.new()
	defeat_sound.name = "DefeatSound"
	defeat_sound.stream = load("res://sounds/defeat.mp3")
	defeat_sound.bus = "Master"
	add_child(defeat_sound)
	
	# Victory sound
	victory_sound = AudioStreamPlayer.new()
	victory_sound.name = "VictorySound"
	victory_sound.stream = load("res://sounds/victory.mp3")
	victory_sound.bus = "Master"
	add_child(victory_sound)
	
	# Background music (loop)
	background_music = AudioStreamPlayer.new()
	background_music.name = "BackgroundMusic"
	var music_stream = load("res://sounds/background.mp3")
	if music_stream is AudioStreamMP3:
		music_stream.loop = true
	background_music.stream = music_stream
	background_music.bus = "Master"
	background_music.volume_db = linear_to_db(0.75)
	add_child(background_music)
	
	# Włącz muzykę jeśli włączona
	if music_enabled:
		background_music.play()
	
	print("✅ Audio setup complete")

func play_btn_sound():
	if sound_enabled and btn_sound:
		btn_sound.play()

func play_switch_sound():
	if sound_enabled and switch_sound:
		switch_sound.play()

func play_select_sound():
	if sound_enabled and select_sound:
		select_sound.play()
		
func play_put_sound():
	if sound_enabled and put_sound:
		put_sound.play()

func play_defeat_sound():
	if sound_enabled and defeat_sound:
		defeat_sound.play()

func play_victory_sound():
	if sound_enabled and victory_sound:
		victory_sound.play()

func toggle_sound(enabled: bool):
	sound_enabled = enabled
	save_game_data()

func toggle_music(enabled: bool):
	music_enabled = enabled
	save_game_data()
	if background_music:
		if enabled:
			if not background_music.playing:
				background_music.play()
		else:
			background_music.stop()

# ========== ZARZĄDZANIE SCENAMI ==========

func change_scene(scene_resource):
	# Ukryj banner podczas rozgrywki
	var admob = get_node_or_null("/root/AdMobManager")
	if current_scene:
		current_scene.queue_free()
	
	var new_scene = scene_resource.instantiate()
	add_child(new_scene)
	current_scene = new_scene
	
	# Pokaż banner w menu, ukryj w grze
	if admob:
		if scene_resource == HEX_GRID_SCENE:
			admob.hide_banner()
		else:
			admob.show_banner()
	
	# Podłącz sygnały
	if new_scene.has_signal("tab_changed"):
		new_scene.tab_changed.connect(_on_tab_changed)
	
	if new_scene.has_signal("level_selected"):
		new_scene.level_selected.connect(_on_level_selected)
	
	if new_scene.has_signal("play_pressed"):
		new_scene.play_pressed.connect(_on_play_pressed)
	
	# Aktualizuj walutę
	update_currency_displays()

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
		sync_audio_settings_to_ui(ui_manager)
	
	# Ukryj banner podczas gry
	var admob = get_node_or_null("/root/AdMobManager")
	if admob and admob.has_method("hide_banner"):
		admob.hide_banner()

func sync_audio_settings_to_ui(ui_manager):
	if not ui_manager:
		return
	
	ui_manager.sound_enabled = sound_enabled
	ui_manager.music_enabled = music_enabled

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
			
			await get_tree().process_frame
			await get_tree().process_frame
			
			if hex_grid.ui_manager:
				hex_grid.ui_manager.set_buttons_enabled(true)
