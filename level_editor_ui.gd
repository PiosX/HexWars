extends CanvasLayer
class_name LevelEditorUI

# UI do łatwego zapisywania i przypisywania poziomów BEZ KONSOLI
# Dodaj ten skrypt jako Node do sceny hex_grid.tscn lub level_select.tscn

var hex_grid: HexGrid
var level_select: LevelSelect
var mode: String = "hex_grid"  # "hex_grid" lub "level_select"

# UI Elements
var panel: Panel
var save_input: LineEdit
var save_button: Button
var load_button: Button
var level_list: VBoxContainer
var scroll_container: ScrollContainer
var info_label: Label
var assign_panel: Panel
var assign_level_input: SpinBox
var assign_file_dropdown: OptionButton
var assign_button: Button

func _ready():
	# Ukryj UI na początku (pokaż tylko w trybie edytora)
	visible = false
	
	# WAŻNE: Ustaw wysoki layer aby panel był NA WIERZCHU
	layer = 100
	
	# Główny panel
	panel = Panel.new()
	panel.custom_minimum_size = Vector2(480, 850)
	panel.position = Vector2(20, 50)
	add_child(panel)
	
	# MarginContainer dla paddingu
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)
	
	# Kontener główny
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)  # Większe odstępy!
	margin.add_child(vbox)
	
	# Tytuł
	var title = Label.new()
	title.text = "📁 EDYTOR POZIOMÓW"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)
	
	# Spacer po tytule
	var title_spacer = Control.new()
	title_spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(title_spacer)
	
	# Info
	info_label = Label.new()
	info_label.text = "Naciśnij ` lub F12 aby pokazać/ukryć"
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info_label)
	
	# Separator
	var sep1 = HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(sep1)
	
	# === SEKCJA ZAPISYWANIA ===
	var save_label = Label.new()
	save_label.text = "💾 ZAPISZ POZIOM"
	save_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(save_label)
	
	var save_desc = Label.new()
	save_desc.text = "Wpisz nazwę pliku i kliknij 'Zapisz'"
	save_desc.add_theme_font_size_override("font_size", 13)
	save_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(save_desc)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer1)
	
	# Label dla inputa
	var save_input_label = Label.new()
	save_input_label.text = "Nazwa pliku:"
	save_input_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(save_input_label)
	
	# Input dla nazwy pliku
	save_input = LineEdit.new()
	save_input.placeholder_text = "np. hex_layout_level1.json"
	save_input.text = "hex_layout_level1.json"
	save_input.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(save_input)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# Przycisk zapisu
	save_button = Button.new()
	save_button.text = "💾 ZAPISZ POZIOM"
	save_button.custom_minimum_size = Vector2(0, 45)
	save_button.pressed.connect(_on_save_pressed)
	vbox.add_child(save_button)
	
	# Separator
	var sep2 = HSeparator.new()
	sep2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(sep2)
	
	# === SEKCJA PRZYPISYWANIA (tylko dla level_select) ===
	assign_panel = Panel.new()
	assign_panel.custom_minimum_size = Vector2(0, 400)  # Stały rozmiar!
	var assign_style = StyleBoxFlat.new()
	assign_style.bg_color = Color(0.15, 0.15, 0.2)
	assign_style.border_width_left = 2
	assign_style.border_width_right = 2
	assign_style.border_width_top = 2
	assign_style.border_width_bottom = 2
	assign_style.border_color = Color(0.3, 0.3, 0.4)
	assign_panel.add_theme_stylebox_override("panel", assign_style)
	vbox.add_child(assign_panel)
	
	# Margin wewnętrzny - BEZ PRESET!
	var assign_margin = MarginContainer.new()
	assign_margin.add_theme_constant_override("margin_left", 15)
	assign_margin.add_theme_constant_override("margin_right", 15)
	assign_margin.add_theme_constant_override("margin_top", 15)
	assign_margin.add_theme_constant_override("margin_bottom", 15)
	# USUNIĘTE: assign_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	assign_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assign_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	assign_panel.add_child(assign_margin)
	
	var assign_vbox = VBoxContainer.new()
	assign_vbox.add_theme_constant_override("separation", 15)  # Większe odstępy!
	assign_margin.add_child(assign_vbox)
	
	var assign_label = Label.new()
	assign_label.text = "🔗 PRZYPISZ PLIK DO POZIOMU"
	assign_label.add_theme_font_size_override("font_size", 20)
	assign_vbox.add_child(assign_label)
	
	var assign_desc = Label.new()
	assign_desc.text = "1. Wybierz numer poziomu (strzałki)\n2. Wybierz plik z listy (kliknij)\n3. Kliknij 'PRZYPISZ'"
	assign_desc.add_theme_font_size_override("font_size", 13)
	assign_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	assign_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assign_vbox.add_child(assign_desc)
	
	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	assign_vbox.add_child(spacer3)
	
	# Numer poziomu
	var level_label = Label.new()
	level_label.text = "Numer poziomu:"
	level_label.add_theme_font_size_override("font_size", 15)
	assign_vbox.add_child(level_label)
	
	assign_level_input = SpinBox.new()
	assign_level_input.min_value = 1
	assign_level_input.max_value = 100
	assign_level_input.value = 1
	assign_level_input.custom_minimum_size = Vector2(0, 45)
	assign_vbox.add_child(assign_level_input)
	
	# Spacer
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 15)
	assign_vbox.add_child(spacer4)
	
	# Dropdown z plikami
	var file_label = Label.new()
	file_label.text = "Plik poziomu:"
	file_label.add_theme_font_size_override("font_size", 15)
	assign_vbox.add_child(file_label)
	
	assign_file_dropdown = OptionButton.new()
	assign_file_dropdown.custom_minimum_size = Vector2(0, 45)
	assign_vbox.add_child(assign_file_dropdown)
	
	# Spacer
	var spacer5 = Control.new()
	spacer5.custom_minimum_size = Vector2(0, 15)
	assign_vbox.add_child(spacer5)
	
	# Przycisk przypisania
	assign_button = Button.new()
	assign_button.text = "🔗 PRZYPISZ"
	assign_button.custom_minimum_size = Vector2(0, 45)
	assign_button.pressed.connect(_on_assign_pressed)
	assign_vbox.add_child(assign_button)
	
	# Separator
	var sep3 = HSeparator.new()
	sep3.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(sep3)
	
	# === LISTA PLIKÓW ===
	var list_label = Label.new()
	list_label.text = "📄 DOSTĘPNE PLIKI"
	list_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(list_label)
	
	var list_desc = Label.new()
	list_desc.text = "Zapisane poziomy w res://levels/"
	list_desc.add_theme_font_size_override("font_size", 13)
	list_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(list_desc)
	
	# Spacer
	var spacer6 = Control.new()
	spacer6.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer6)
	
	# Scroll dla listy
	scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(0, 200)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)
	
	level_list = VBoxContainer.new()
	level_list.add_theme_constant_override("separation", 8)
	scroll_container.add_child(level_list)
	
	# Spacer
	var spacer7 = Control.new()
	spacer7.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer7)
	
	# Przycisk odświeżenia listy
	var refresh_button = Button.new()
	refresh_button.text = "🔄 Odśwież Listę Plików"
	refresh_button.custom_minimum_size = Vector2(0, 45)
	refresh_button.pressed.connect(_on_refresh_list)
	vbox.add_child(refresh_button)

func setup_for_hex_grid(grid: HexGrid):
	"""Konfiguracja dla edytora poziomów (hex_grid)"""
	hex_grid = grid
	mode = "hex_grid"
	assign_panel.visible = false  # Ukryj sekcję przypisywania
	info_label.text = "💡 Stwórz poziom, nadaj mu nazwę i zapisz"
	_on_refresh_list()

func setup_for_level_select(ls: LevelSelect):
	"""Konfiguracja dla level select (przypisywanie plików)"""
	level_select = ls
	mode = "level_select"
	assign_panel.visible = true  # Pokaż sekcję przypisywania
	info_label.text = "💡 Przypisz pliki poziomów do hexów w trybie edytora (E → 4)"
	_on_refresh_list()

func _input(event):
	if event is InputEventKey and event.pressed:
		# Toggle widoczności przy naciśnięciu klawisza backtick (`) lub F12
		if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_F12:
			visible = not visible
			if visible:
				_on_refresh_list()

func _on_save_pressed():
	"""Zapisuje poziom do pliku"""
	print("=== SAVE PRESSED ===")
	print("Mode: ", mode)
	print("hex_grid valid: ", hex_grid != null)
	
	var file_name = save_input.text.strip_edges()
	
	if file_name.is_empty():
		info_label.text = "❌ Błąd: Podaj nazwę pliku!"
		info_label.add_theme_color_override("font_color", Color.RED)
		print("ERROR: Empty filename")
		return
	
	# Dodaj .json jeśli nie ma rozszerzenia
	if not file_name.ends_with(".json"):
		file_name += ".json"
	
	print("Filename: ", file_name)
	
	if mode == "hex_grid" and hex_grid:
		print("Calling save_layout_to_file...")
		hex_grid.save_layout_to_file(file_name)
		info_label.text = "✅ Zapisano: " + file_name
		info_label.add_theme_color_override("font_color", Color.GREEN)
		_on_refresh_list()
		
		# Automatycznie zwiększ numer dla następnego poziomu
		var regex = RegEx.new()
		regex.compile("level(\\d+)")
		var result = regex.search(file_name)
		if result:
			var num = int(result.get_string(1)) + 1
			save_input.text = "hex_layout_level" + str(num) + ".json"
			print("Auto-incremented to: ", save_input.text)
	else:
		info_label.text = "❌ Błąd: hex_grid nie jest dostępny (mode=" + str(mode) + ")"
		info_label.add_theme_color_override("font_color", Color.RED)
		print("ERROR: hex_grid not available or wrong mode")

func _on_assign_pressed():
	"""Przypisuje plik do poziomu w level select"""
	if mode != "level_select" or not level_select:
		info_label.text = "❌ Błąd: To działa tylko w level select!"
		info_label.add_theme_color_override("font_color", Color.RED)
		return
	
	var level_num = int(assign_level_input.value)
	var selected_idx = assign_file_dropdown.selected
	
	if selected_idx < 0:
		info_label.text = "❌ Błąd: Wybierz plik z listy!"
		info_label.add_theme_color_override("font_color", Color.RED)
		return
	
	var file_name = assign_file_dropdown.get_item_text(selected_idx)
	
	# Wywołaj funkcję z level_select
	level_select.assign_level_file_to_level(level_num, file_name)
	
	info_label.text = "✅ Przypisano: Poziom " + str(level_num) + " → " + file_name
	info_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Automatycznie zwiększ numer poziomu
	assign_level_input.value = level_num + 1
	
	# Zapisz dane level select
	if level_select.has_method("save_level_data"):
		level_select.save_level_data()

func _on_refresh_list():
	"""Odświeża listę dostępnych plików poziomów"""
	# Wyczyść starą listę
	for child in level_list.get_children():
		child.queue_free()
	
	# Wyczyść dropdown
	assign_file_dropdown.clear()
	
	# Skanuj pliki w res://levels/
	var dir = DirAccess.open("res://levels/")
	if not dir:
		var error_label = Label.new()
		error_label.text = "❌ Nie można otworzyć katalogu res://levels/"
		error_label.add_theme_color_override("font_color", Color.RED)
		level_list.add_child(error_label)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var files_found: Array[String] = []
	
	while file_name != "":
		if file_name.begins_with("hex_layout") and file_name.ends_with(".json"):
			files_found.append(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Sortuj alfabetycznie
	files_found.sort()
	
	if files_found.is_empty():
		var no_files_label = Label.new()
		no_files_label.text = "Brak plików poziomów.\nStwórz poziom i zapisz go!"
		no_files_label.add_theme_color_override("font_color", Color.YELLOW)
		level_list.add_child(no_files_label)
		return
	
	# Pokaż pliki
	for file in files_found:
		var file_panel = Panel.new()
		var file_style = StyleBoxFlat.new()
		file_style.bg_color = Color(0.12, 0.12, 0.15)
		file_style.border_width_left = 1
		file_style.border_width_right = 1
		file_style.border_width_top = 1
		file_style.border_width_bottom = 1
		file_style.border_color = Color(0.25, 0.25, 0.3)
		file_panel.add_theme_stylebox_override("panel", file_style)
		file_panel.custom_minimum_size = Vector2(0, 40)
		level_list.add_child(file_panel)
		
		var file_hbox = HBoxContainer.new()
		file_hbox.add_theme_constant_override("separation", 10)
		file_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		file_hbox.add_theme_constant_override("margin_left", 8)
		file_hbox.add_theme_constant_override("margin_right", 8)
		file_hbox.add_theme_constant_override("margin_top", 5)
		file_hbox.add_theme_constant_override("margin_bottom", 5)
		file_panel.add_child(file_hbox)
		
		var file_label = Label.new()
		file_label.text = "📄 " + file
		file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		file_label.add_theme_font_size_override("font_size", 13)
		file_hbox.add_child(file_label)
		
		# Przycisk wczytania (tylko dla hex_grid)
		if mode == "hex_grid":
			var load_btn = Button.new()
			load_btn.text = "Wczytaj"
			load_btn.custom_minimum_size = Vector2(80, 30)
			load_btn.pressed.connect(_on_load_file.bind(file))
			file_hbox.add_child(load_btn)
		
		# Dodaj do dropdown (dla level_select)
		if mode == "level_select":
			assign_file_dropdown.add_item(file)
	
	info_label.text = "📁 Znaleziono " + str(files_found.size()) + " plików"
	info_label.add_theme_color_override("font_color", Color.WHITE)

func _on_load_file(file_name: String):
	"""Wczytuje poziom z pliku"""
	if mode == "hex_grid" and hex_grid:
		var success = hex_grid.load_layout_from_file(file_name)
		if success:
			info_label.text = "✅ Wczytano: " + file_name
			info_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			info_label.text = "❌ Błąd wczytywania: " + file_name
			info_label.add_theme_color_override("font_color", Color.RED)
