extends Node2D
class_name HexGrid

# --- KONFIGURACJA ---
@export var editor_mode: bool = false
@export_enum("Hex", "Castle_Blue", "Castle_Red", "Castle_Purple", "Castle_Yellow", 
			 "Knight_Blue", "Knight_Red", "Knight_Purple", "Knight_Yellow", 
			 "Farmer_Blue", "Farmer_Red", "Farmer_Purple", "Farmer_Yellow", 
			 "Spearman_Blue", "Spearman_Red", "Spearman_Purple", "Spearman_Yellow",
			 "Cavalry_Blue", "Cavalry_Red", "Cavalry_Purple", "Cavalry_Yellow",
			 "Farmer_Bandit", "Castle_Bandit", "Wall") var editor_tool: String = "Hex"

const HEX_SCENE = preload("res://hex.tscn")
const CASTLE_SCENE = preload("res://castle.tscn")
const KNIGHT_SCENE = preload("res://knight.tscn")
const SPEARMAN_SCENE = preload("res://spearman.tscn")
const CAVALRY_SCENE = preload("res://cavalry.tscn")
const FARMER_SCENE = preload("res://farmer.tscn")
const TURN_HISTORY_SCENE = preload("res://turn_history.gd")
const SAVE_PATH = "user://hex_layout.json"
var current_level_file: String = ""  # Currently loaded level file
var current_level_number: int = 0  # Current level number for victory tracking
var ui_manager: UIManager

@export var hex_width: float = 96.0
@export var hex_height: float = 96.0
@export var hex_gap: float = 0.1

# Kolory teamow
const TEAM_COLORS = {
	1: Color("#4D99FF"),  # Niebieski
	2: Color("#FF4D4D"),  # Czerwony
	3: Color("#9B59FF"),  # Fioletowy
	4: Color("#FFD645")   # Zolty
}

var camera_drag_enabled: bool = true
var camera_dragging: bool = false
var drag_start_position: Vector2
var initial_camera_position: Vector2

const NEUTRAL_COLOR = Color("#2b2b2b")
const MERCENARY_COLOR = Color("#1a1a1a")
const CAMP_COLOR = Color("#4a3520")

const HIGHLIGHT_COLOR_CAPTURE = Color("#FFA500")
const HIGHLIGHT_COLOR_MERGE = Color("#00FFFF")
const BANDIT_COLOR = Color("#404040")
const BANDIT_CAMP_COLOR = Color("#5a5a5a")

var hex_horiz_spacing: float
var hex_vert_spacing: float

# Slowniki
var hex_map: Dictionary = {}
var castle_map: Dictionary = {}
var knight_map: Dictionary = {}
var spearman_map: Dictionary = {}
var cavalry_map: Dictionary = {}
var farmer_map: Dictionary = {}
var territory_map: Dictionary = {}
var wall_map: Dictionary = {}
var cavalry_moves_this_turn: Dictionary = {}
var unit_pulse_tweens: Dictionary = {}

# Stan gry
var current_team: int = 1
var selected_unit = null
var highlighted_hexes: Array[Hex] = []
var game_mode: bool = true
var units_moved_this_turn: Array = []
var current_round: int = 1
var bandits_need_camp: Array[Vector2i] = []  # Jednostki bandytów bez obozu
const BANDIT_TEAM = -1
const BANDIT_CAMP_REWARD = 10

# Ekonomia
var team_gold: Dictionary = {1: 10, 2: 10, 3: 10, 4: 10, 5: 0}
var team_territory_count: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}

const FARMER_COST = 10
const FARMER_UPKEEP = 2
const SPEARMAN_COST = 20
const SPEARMAN_UPKEEP = 6
const KNIGHT_COST = 40
const KNIGHT_UPKEEP = 18
const CAVALRY_COST = 80
const CAVALRY_UPKEEP = 2
const GOLD_PER_TERRITORY = 2
const WALL_COST_PER_HEX = 3

# UI
var buy_mode: String = ""  # "farmer", "knight", "wall"
var wall_buy_hexes: Array[Vector2i] = []


# Edytor murow
var wall_hexes_selected: Array[Vector2i] = []
var wall_placement_mode: bool = false
var wall_start_hex: Vector2i = Vector2i.ZERO

# Tryb laczenia
var merge_mode: bool = false

# Historia tur (system cofania)
var turn_history: TurnHistory

func _ready():
	var victory_popup = preload("res://victory_popup.tscn").instantiate()
	add_child(victory_popup)
	set_meta("victory_popup", victory_popup)
	
	var defeat_popup = preload("res://defeat_popup.gd").new()
	add_child(defeat_popup)
	set_meta("defeat_popup", defeat_popup)
	
	turn_history = TurnHistory.new()
	add_child(turn_history)
	
	hex_horiz_spacing = hex_width * 0.866 * (1.0 + hex_gap)
	hex_vert_spacing = hex_height * 0.75 * (1.0 + hex_gap)
	
	var camera = Camera2D.new()
	camera.name = "GameCamera"
	camera.zoom = Vector2(1.5, 1.5)
	camera.enabled = true
	add_child(camera)
	set_meta("game_camera", camera)
	
	ui_manager = UIManager.new()
	ui_manager.hex_grid = self
	add_child(ui_manager)
	await ui_manager.ui_ready
	
	if not load_layout():
		create_rectangle_grid(8, 8)
	
	update_ui()
	
	print("=== STEROWANIE ===")
	print("E = Toggle tryb edytor/gra")
	print("== EDYTOR ==")
	print("1 = Hex | 2-5 = Zamki | 6-9 = Rycerze | Q/W/R/T = Farmerzy | I/O/P/[ = Włócznicy | ]/;/'/ = Kawaleria | M = Tryb łączenia")
	print("Y = Farmer Bandyta | U = Oboz Bandytow")
	print("0 = Tryb murow (kliknij dwa hexy aby polaczyc)")
	print("LPM = Postaw | PPM = Usun | Shift+LPM = Oznacz teren")
	print("S = Zapisz (domyślny) | L = Wczytaj | C = Wyczysc")
	print("F1-F10 = Zapisz jako Level 1-10 (hex_layout_level1.json...)")
	print("== GRA ==")
	print("X = Zmien druzyne | SPACE = Zakoncz ture")
	print("Kliknij jednostke = Wybierz | Przycisk 'Polacz' = Tryb laczenia")
	print("==================")
	
	if game_mode:
		pulse_available_units()
		turn_history.save_turn_snapshot(self)
		
	await get_tree().process_frame
	var editor_ui = get_parent().get_node_or_null("LevelEditorUI")
	if editor_ui:
		editor_ui.setup_for_hex_grid(self)
		print("✓ Panel połączony z HexGrid!")

func update_ui():
	if ui_manager:
		ui_manager.update_ui_data()

func calculate_income(team: int) -> int:
	if team == 5 or team == BANDIT_TEAM:
		return 0
	# Tylko pola POLACZONE z zamkiem daja przychod
	var connected_territories = get_connected_territories(team)
	var territory_income = connected_territories.size() * GOLD_PER_TERRITORY
	
	# Dodaj zloto za kazdy zamek
	var castle_gold = 0
	for coords in castle_map:
		if castle_map[coords].team == team:
			castle_gold += 6
	
	return territory_income + castle_gold

func calculate_upkeep(team: int) -> int:
	if team == 5 or team == BANDIT_TEAM:
		return 0
	var cost = 0
	for cavalry in cavalry_map.values():
		if cavalry.team == team:
			cost += CAVALRY_UPKEEP
	for knight in knight_map.values():
		if knight.team == team:
			cost += KNIGHT_UPKEEP
	for spearman in spearman_map.values():
		if spearman.team == team:
			cost += SPEARMAN_UPKEEP
	for farmer in farmer_map.values():
		if farmer.team == team:
			cost += FARMER_UPKEEP
	return cost

func update_territory_counts():
	team_territory_count = {1: 0, 2: 0, 3: 0, 4: 0}
	for coords in territory_map:
		var team = int(territory_map[coords])
		if team > 0:
			team_territory_count[team] += 1

func get_enemy_territory_count() -> int:
	var count = 0
	for team in [1, 2, 3, 4]:
		if team != current_team:
			count += team_territory_count[team]
	return count

func get_neutral_territory_count() -> int:
	var total_hexes = hex_map.size()
	var occupied = 0
	for count in team_territory_count.values():
		occupied += count
	return total_hexes - occupied

func _input(event):
	if event is InputEventKey and event.pressed:
		
		if event.keycode == KEY_SPACE and game_mode:
			_on_end_turn()
			get_viewport().set_input_as_handled()
			return
		
		match event.keycode:
			KEY_E:
				game_mode = not game_mode
				clear_highlights()
				merge_mode = false
				wall_placement_mode = false
				print("Tryb: ", "GRA" if game_mode else "EDYTOR")
				update_ui()
				if game_mode:
					pulse_available_units()
			KEY_1:
				if not game_mode:
					editor_tool = "Hex"
					wall_placement_mode = false
			KEY_2:
				if not game_mode:
					editor_tool = "Castle_Blue"
					wall_placement_mode = false
			KEY_3:
				if not game_mode:
					editor_tool = "Castle_Red"
					wall_placement_mode = false
			KEY_4:
				if not game_mode:
					editor_tool = "Castle_Purple"
					wall_placement_mode = false
			KEY_5:
				if not game_mode:
					editor_tool = "Castle_Yellow"
					wall_placement_mode = false
			KEY_6:
				if not game_mode:
					editor_tool = "Knight_Blue"
					wall_placement_mode = false
			KEY_7:
				if not game_mode:
					editor_tool = "Knight_Red"
					wall_placement_mode = false
			KEY_8:
				if not game_mode:
					editor_tool = "Knight_Purple"
					wall_placement_mode = false
			KEY_9:
				if not game_mode:
					editor_tool = "Knight_Yellow"
					wall_placement_mode = false
			KEY_Q:
				if not game_mode:
					editor_tool = "Farmer_Blue"
					wall_placement_mode = false
			KEY_W:
				if not game_mode:
					editor_tool = "Farmer_Red"
					wall_placement_mode = false
			KEY_R:
				if not game_mode:
					editor_tool = "Farmer_Purple"
					wall_placement_mode = false
			KEY_T:
				if not game_mode:
					editor_tool = "Farmer_Yellow"
					wall_placement_mode = false
			KEY_I:
				if not game_mode:
					editor_tool = "Spearman_Blue"
					wall_placement_mode = false
			KEY_O:
				if not game_mode:
					editor_tool = "Spearman_Red"
					wall_placement_mode = false
			KEY_P:
				if not game_mode:
					editor_tool = "Spearman_Purple"
					wall_placement_mode = false
			KEY_BRACKETLEFT:  # [
				if not game_mode:
					editor_tool = "Spearman_Yellow"
					wall_placement_mode = false
			KEY_Y:
				if not game_mode:
					editor_tool = "Farmer_Bandit"
					wall_placement_mode = false
			KEY_U:
				if not game_mode:
					editor_tool = "Castle_Bandit"
					wall_placement_mode = false
			KEY_BRACKETRIGHT:  # ]
				if not game_mode:
					editor_tool = "Cavalry_Blue"
					wall_placement_mode = false
			KEY_BACKSLASH:  # \
				if not game_mode:
					editor_tool = "Cavalry_Red"
					wall_placement_mode = false
			KEY_APOSTROPHE:  # '
				if not game_mode:
					editor_tool = "Cavalry_Purple"
					wall_placement_mode = false
			KEY_SEMICOLON:  # ;
				if not game_mode:
					editor_tool = "Cavalry_Yellow"
					wall_placement_mode = false
			KEY_0:
				if not game_mode:
					wall_placement_mode = not wall_placement_mode
					if wall_placement_mode:
						wall_hexes_selected.clear()
						current_team = 1  # ← domyślnie niebieski
						print("TRYB MUROW (druzyna: ", current_team, ")")
						print("Klikaj hexy. Zmien druzyne: F1-F4. Enter = utworz")
					else:
						create_walls_between_selected()
						wall_hexes_selected.clear()
						print("Mury utworzone")
			KEY_F1:
				if not game_mode and wall_placement_mode:
					current_team = 1
					print("Mury dla: NIEBIESKIEJ")
			KEY_F2:
				if not game_mode and wall_placement_mode:
					current_team = 2
					print("Mury dla: CZERWONEJ")
			KEY_F3:
				if not game_mode and wall_placement_mode:
					current_team = 3
					print("Mury dla: FIOLETOWEJ")
			KEY_F4:
				if not game_mode and wall_placement_mode:
					current_team = 4
					print("Mury dla: ZOLTEJ")
			KEY_X:
				if game_mode:
					cycle_team()
			KEY_S:
				save_layout()
			KEY_L:
				load_layout()
			KEY_C:
				if not game_mode:
					clear_grid()
			# QUICK SAVE SHORTCUTS - F1 to F10 save as level 1-10
			KEY_F1:
				if not game_mode:
					save_layout_to_file("hex_layout_level1.json")
					print("✓ Saved as Level 1")
			KEY_F2:
				if not game_mode:
					save_layout_to_file("hex_layout_level2.json")
					print("✓ Saved as Level 2")
			KEY_F3:
				if not game_mode:
					save_layout_to_file("hex_layout_level3.json")
					print("✓ Saved as Level 3")
			KEY_F4:
				if not game_mode:
					save_layout_to_file("hex_layout_level4.json")
					print("✓ Saved as Level 4")
			KEY_F5:
				if not game_mode:
					save_layout_to_file("hex_layout_level5.json")
					print("✓ Saved as Level 5")
			KEY_F6:
				if not game_mode:
					save_layout_to_file("hex_layout_level6.json")
					print("✓ Saved as Level 6")
			KEY_F7:
				if not game_mode:
					save_layout_to_file("hex_layout_level7.json")
					print("✓ Saved as Level 7")
			KEY_F8:
				if not game_mode:
					save_layout_to_file("hex_layout_level8.json")
					print("✓ Saved as Level 8")
			KEY_F9:
				if not game_mode:
					save_layout_to_file("hex_layout_level9.json")
					print("✓ Saved as Level 9")
			KEY_F10:
				if not game_mode:
					save_layout_to_file("hex_layout_level10.json")
					print("✓ Saved as Level 10")
			KEY_ESCAPE:
				if wall_placement_mode or buy_mode != "":
					wall_placement_mode = false
					wall_hexes_selected.clear()
					buy_mode = ""
					clear_highlights()
					update_ui()
	
	if game_mode and wall_placement_mode and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_local_mouse_position()
			var hex_coords = pixel_to_hex(mouse_pos)
			
			# Sprawdz czy to wlasne terytorium
			if territory_map.get(hex_coords, 0) == current_team:
				handle_wall_placement(hex_coords)
				# KRYTYCZNE: Zablokuj dalsze przetwarzanie (zeby nie kliknac jednostki)
				get_viewport().set_input_as_handled()
				# DODAJ: Nie pozwol na dalsze eventy
				return
	
	# Edytor
	if not game_mode and event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_local_mouse_position()
		var hex_coords = pixel_to_hex(mouse_pos)
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if wall_placement_mode:
				handle_wall_placement(hex_coords)
			elif Input.is_key_pressed(KEY_SHIFT):
				toggle_territory(hex_coords)
			else:
				match editor_tool:
					"Hex":
						add_hex_at(hex_coords)
					"Castle_Blue":
						place_castle_at(hex_coords, 1)
					"Castle_Red":
						place_castle_at(hex_coords, 2)
					"Castle_Purple":
						place_castle_at(hex_coords, 3)
					"Castle_Yellow":
						place_castle_at(hex_coords, 4)
					"Knight_Blue":
						place_knight_at(hex_coords, 1)
					"Knight_Red":
						place_knight_at(hex_coords, 2)
					"Knight_Purple":
						place_knight_at(hex_coords, 3)
					"Knight_Yellow":
						place_knight_at(hex_coords, 4)
					"Farmer_Blue":
						place_farmer_at(hex_coords, 1)
					"Farmer_Red":
						place_farmer_at(hex_coords, 2)
					"Farmer_Purple":
						place_farmer_at(hex_coords, 3)
					"Farmer_Yellow":
						place_farmer_at(hex_coords, 4)
					"Spearman_Blue":
						place_spearman_at(hex_coords, 1)
					"Spearman_Red":
						place_spearman_at(hex_coords, 2)
					"Spearman_Purple":
						place_spearman_at(hex_coords, 3)
					"Spearman_Yellow":
						place_spearman_at(hex_coords, 4)
					"Cavalry_Blue":
						place_cavalry_at(hex_coords, 1)
					"Cavalry_Red":
						place_cavalry_at(hex_coords, 2)
					"Cavalry_Purple":
						place_cavalry_at(hex_coords, 3)
					"Cavalry_Yellow":
						place_cavalry_at(hex_coords, 4)
					"Farmer_Bandit":
						place_farmer_at(hex_coords, -1)
						territory_map[hex_coords] = -1
						update_hex_color(hex_coords)
					"Castle_Bandit":
						place_castle_at(hex_coords, -1)
						territory_map[hex_coords] = -2
						update_hex_color(hex_coords)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remove_all_at(hex_coords)
			
func _unhandled_input(event):
	if not camera_drag_enabled:
		return
	
	var camera = get_meta("game_camera") if has_meta("game_camera") else null
	if not camera:
		return
		
	# Obsługa TOUCH na telefonie/tablecie
	if event is InputEventScreenTouch:
		if event.pressed:
			camera_dragging = true
			drag_start_position = event.position
			initial_camera_position = self.position
		else:
			camera_dragging = false
		get_viewport().set_input_as_handled()
		return
	
	if event is InputEventScreenDrag and camera_dragging:
		var delta = event.position - drag_start_position
		var new_position = initial_camera_position + delta / camera.zoom
		
		# Oblicz granice mapy
		var bounds = calculate_map_bounds()
		
		# Ogranicz pozycję - margines 500px
		new_position.x = clamp(new_position.x, -bounds.end.x, -bounds.position.x)
		new_position.y = clamp(new_position.y, -bounds.end.y, -bounds.position.y)
		
		self.position = new_position
		get_viewport().set_input_as_handled()
		return
	# Start/stop dragging z ŚRODKOWYM przyciskiem myszy
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			camera_dragging = true
			drag_start_position = event.position
			initial_camera_position = self.position
		else:
			camera_dragging = false
		get_viewport().set_input_as_handled()
		return
	
	# Dragging w trakcie ruchu myszy
	if event is InputEventMouseMotion and camera_dragging:
		var delta = event.position - drag_start_position
		var new_position = initial_camera_position + delta / camera.zoom
		
		# Oblicz granice mapy
		var bounds = calculate_map_bounds()
		
		# Ogranicz pozycję - margines 500px
		new_position.x = clamp(new_position.x, -bounds.end.x, -bounds.position.x)
		new_position.y = clamp(new_position.y, -bounds.end.y, -bounds.position.y)
		
		self.position = new_position
		get_viewport().set_input_as_handled()

func handle_wall_placement(hex_coords: Vector2i):
	"""Obsluguje zaznaczanie hexow do murow"""
	if not hex_map.has(hex_coords):
		print("Brak hexa na tej pozycji")
		return
	
	# Sprawdz czy to wlasne terytorium (w trybie gry)
	if game_mode:
		if territory_map.get(hex_coords, 0) != current_team:
			print("To nie twoje terytorium!")
			return
	
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	
	# SPRAWDZ ile murow ma ten hex
	if hex_coords not in wall_hexes_selected:
		var neighbors = get_neighbors(hex_coords)
		var walls_count = 0
		for neighbor in neighbors:
			if has_wall_between(hex_coords, neighbor):
				walls_count += 1
		
		# Jesli ma 6 murow (pelne otoczenie) - nie pozwol zaznaczyc
		if walls_count >= 6:
			print("To pole ma juz pelne otoczenie murami!")
			return
	
	# Dodaj lub usun hex z listy
	if hex_coords in wall_hexes_selected:
		wall_hexes_selected.erase(hex_coords)
		print("Odznaczono hex: ", hex_coords)
		remove_hex_outline(hex_coords)
	else:
		# Sprawdz limit zlota
		if game_mode:
			var current_cost = wall_hexes_selected.size() * WALL_COST_PER_HEX
			var new_cost = current_cost + WALL_COST_PER_HEX
			if new_cost > team_gold[current_team]:
				print("Nie stac cie na wiecej scian! Masz: ", team_gold[current_team], " zlota")
				return
		
		wall_hexes_selected.append(hex_coords)
		print("Zaznaczono hex: ", hex_coords, " (Koszt: ", wall_hexes_selected.size() * WALL_COST_PER_HEX, ")")
		draw_hex_outline(hex_coords, Color.WHITE)
		
func draw_hex_outline(hex_coords: Vector2i, color: Color):
	"""Rysuje biala przerywana obwodke wokol hexa (taki sam styl jak walle)"""
	var center = hex_to_pixel(hex_coords)
	var hex_radius = hex_width * 0.45
	var angles = [30, 90, 150, 210, 270, 330]
	var vertices = []
	
	for angle in angles:
		var rad = deg_to_rad(angle)
		var x = center.x + hex_radius * cos(rad)
		var y = center.y + hex_radius * sin(rad)
		vertices.append(Vector2(x, y))
	
	var outline_container = Node2D.new()
	outline_container.z_index = 15
	add_child(outline_container)
	
	for i in range(vertices.size()):
		var start = vertices[i]
		var end = vertices[(i + 1) % vertices.size()]
		
		var wall_line = WallLine.new()
		wall_line.setup(start, end, Color.WHITE, 3.75, false)  # Taki sam styl jak walle
		outline_container.add_child(wall_line)
	
	if not has_meta("hex_outlines"):
		set_meta("hex_outlines", {})
	var hex_outlines = get_meta("hex_outlines")
	hex_outlines[hex_coords] = outline_container
	
func remove_hex_outline(hex_coords: Vector2i):
	"""Usuwa obwodke hexa"""
	if not has_meta("hex_outlines"):
		return
	
	var hex_outlines = get_meta("hex_outlines")
	if hex_outlines.has(hex_coords):
		hex_outlines[hex_coords].queue_free()
		hex_outlines.erase(hex_coords)
			
func create_walls_between_selected():
	"""Każdy hex tworzy swoje własne walle na WSZYSTKICH 6 krawędziach"""
	if wall_hexes_selected.size() < 1:
		print("Zaznacz przynajmniej 1 hex")
		return
	
	print("=== Tworzenie walli ===")
	print("Zaznaczone hexy: ", wall_hexes_selected)
	
	# W trybie gry sprawdz czy wszystkie hexy sa wlasne
	if game_mode:
		for hex_coords in wall_hexes_selected:
			if territory_map.get(hex_coords, 0) != current_team:
				print("Nie mozesz stawiac scian na neutralnym terenie!")
				return
	
	var walls_created = 0
	
	# KAZDY HEX TWORZY SWOJE WLASNE WALLE - NIEZALEZNIE OD SASIADOW
	for hex_coords in wall_hexes_selected:
		# Stworz 6 walli dla tego hexa (kazda krawedz osobno)
		walls_created += create_hex_walls(hex_coords, current_team)
	
	# Usun obwodki
	for hex_coords in wall_hexes_selected:
		remove_hex_outline(hex_coords)
	
	print("Utworzono walli: ", walls_created)
	
func create_hex_walls(hex_coords: Vector2i, wall_team: int) -> int:
	"""Tworzy 6 osobnych walli wokol hexa (kazda krawedz jako osobny wall)"""
	var center = hex_to_pixel(hex_coords)
	var hex_radius = hex_width * 0.45
	var angles = [30, 90, 150, 210, 270, 330]
	var vertices = []
	
	# Oblicz 6 wierzcholkow hexa
	for angle in angles:
		var rad = deg_to_rad(angle)
		var x = center.x + hex_radius * cos(rad)
		var y = center.y + hex_radius * sin(rad)
		vertices.append(Vector2(x, y))
	
	var walls_created = 0
	
	# Dla kazdej z 6 krawedzi stworz osobny wall
	for i in range(vertices.size()):
		var start = vertices[i]
		var end = vertices[(i + 1) % vertices.size()]
		
		# Unikalny klucz dla kazdej krawedzi TEGO hexa
		var edge_key = "%d,%d-edge%d" % [hex_coords.x, hex_coords.y, i]
		
		# Sprawdz czy juz jest wall na tej krawedzi
		if wall_map.has(edge_key):
			print("  -> Wall juz istnieje na krawedzi ", i, " hexa ", hex_coords)
			continue
		
		# Dodaj wall do mapy
		wall_map[edge_key] = {"team": wall_team, "hex": hex_coords, "edge": i}
		
		# Narysuj wall (bialy, przerywany)
		var wall_line = WallLine.new()
		wall_line.z_index = 10
		wall_line.setup(start, end, Color.WHITE, 2.5, false)
		add_child(wall_line)
		
		# Zapisz linie
		if not has_meta("wall_lines"):
			set_meta("wall_lines", {})
		var wall_lines = get_meta("wall_lines")
		wall_lines[edge_key] = wall_line
		
		walls_created += 1
	
	print("Hex ", hex_coords, " otrzymal ", walls_created, " walli")
	return walls_created

func cycle_team():
	var old_team = current_team
	current_team += 1
	
	# ZMIANA: Sprawdź czy są bandyci (team -1)
	var has_bandits = false
	for coords in knight_map:
		if knight_map[coords].team == BANDIT_TEAM:
			has_bandits = true
			break
	if not has_bandits:
		for coords in farmer_map:
			if farmer_map[coords].team == BANDIT_TEAM:
				has_bandits = true
				break
	
	var max_team = 5 if has_bandits else 4
	
	if current_team > max_team:
		current_team = 1
		current_round += 1
		print("=== KONIEC RUNDY ===")
		
		# POPRAWKA: Rozdaj pieniądze WSZYSTKIM drużynom na początku rundy
		print("Rozdzielanie pieniędzy dla wszystkich drużyn...")
		for team in [1, 2, 3, 4]:
			var income = calculate_income(team)
			var upkeep = calculate_upkeep(team)
			var net_income = income - upkeep
			team_gold[team] += net_income
			
			print("Drużyna ", team, ": +", income, " -", upkeep, " = ", net_income, " (razem: ", team_gold[team], ")")
			
			# Sprawdź bankructwo
			if team_gold[team] < 0:
				print("BANKRUCTWO! Drużyna ", team, " nie może płacić jednostkom!")
				handle_bankruptcy(team)
				team_gold[team] = 0
		
		print("=== Sprawdzam bankructwa ===")
		process_bankruptcies()
	
	clear_highlights()
	merge_mode = false
	selected_unit = null
	
	buy_mode = ""
	wall_placement_mode = false
	
	for hex_coords in wall_hexes_selected:
		remove_hex_outline(hex_coords)
	wall_hexes_selected.clear()
	
	# Reset przycisków
	if ui_manager:
		ui_manager.reset_wall_button()
	
	var team_names = {1: "NIEBIESKI", 2: "CZERWONY", 3: "FIOLETOWY", 4: "ZOLTY", 5: "BANDYCI"}
	print("Druzyna: ", team_names.get(current_team, "NIEZNANA"))
	
	# DODAJ: Sprawdź czy bandyci potrzebują obozu
	if current_team == 5:
		check_bandits_need_camp()
	
	update_ui()
	pulse_available_units()
	
func check_bandits_need_camp():
	"""Sprawdza czy bandyci bez obozu stoja na pustym miejscu - jesli tak, twórz obóz"""
	print("=== TURA BANDYTOW - sprawdzam obozy ===")
	
	var bandits_without_camp = []
	
	# Znajdź wszystkie jednostki bandytów
	for coords in knight_map:
		if knight_map[coords].team == BANDIT_TEAM:
			bandits_without_camp.append(coords)
	for coords in farmer_map:
		if farmer_map[coords].team == BANDIT_TEAM:
			bandits_without_camp.append(coords)
	
	# Sprawdź czy jest obóz bandytów
	var has_camp = false
	for coords in castle_map:
		if castle_map[coords].team == BANDIT_TEAM:
			has_camp = true
			break
	
	if has_camp:
		print("Bandyci mają już obóz")
		return
	
	print("Bandyci NIE mają obozu - szukam miejsca...")
	
	# Spróbuj postawić obóz obok którejkolwiek jednostki
	var camp_placed = place_bandit_camp_near_units(bandits_without_camp, bandits_without_camp)
	
	if camp_placed:
		print("✓ Utworzono obóz bandytów")
	else:
		print("✗ Brak miejsca na obóz - jednostki izolowane")

func _on_end_turn():
	if not game_mode:
		return
		
	if current_team == 5:
		units_moved_this_turn.clear()
		merge_mode = false
		buy_mode = ""
		wall_placement_mode = false
		
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		
		clear_highlights()
		cycle_team()
		return
	
	# POPRAWKA: Usuń naliczanie pieniędzy - jest teraz w cycle_team()
	print("Tura zakonczona.")
	
	units_moved_this_turn.clear()
	cavalry_moves_this_turn.clear()
	merge_mode = false
	
	# DODAJ: PELNY reset wszystkich trybow
	buy_mode = ""
	wall_placement_mode = false
	
	# Usun tymczasowe sciany (outline'y)
	for hex_coords in wall_hexes_selected:
		remove_hex_outline(hex_coords)
	wall_hexes_selected.clear()
	
	if ui_manager:
		ui_manager.reset_wall_button()
	
	clear_highlights()
	cycle_team()
	turn_history.save_turn_snapshot(self)
	pulse_available_units()
	
func _on_rewind_turn():
	"""Obsługa przycisku cofania tury"""
	if not game_mode:
		print("Cofanie tur dostępne tylko w trybie gry!")
		return
	
	if not turn_history.can_rewind():
		print("Nie można cofnąć tury!")
		return
	
	print("=== COFANIE TURY ===")
	
	# Wyczyść aktualny stan UI
	clear_highlights()
	merge_mode = false
	selected_unit = null
	buy_mode = ""
	wall_placement_mode = false
	
	for hex_coords in wall_hexes_selected:
		remove_hex_outline(hex_coords)
	wall_hexes_selected.clear()
	
	# Resetuj przyciski
	if ui_manager:
		ui_manager.reset_wall_button()
	
	# Cofnij turę
	var success = turn_history.restore_previous_turn(self)
	
	if success:
		print("✓ Tura cofnięta pomyślnie!")
		update_ui()
	else:
		print("✗ Nie udało się cofnąć tury")
	
func handle_bankruptcy(team: int):
	"""Obsluguje bankructwo - OZNACZ do konwersji, ale nie konwertuj od razu"""
	print("=== BANKRUCTWO DRUZYNY ", team, " ===")
	print("Jednostki zostana zbuntowane po zakonczeniu rundy wszystkich graczy")
	
	# Zaznacz druzyne jako zbankrutowana
	if not has_meta("bankrupt_teams"):
		set_meta("bankrupt_teams", {})
	var bankrupt_teams = get_meta("bankrupt_teams")
	bankrupt_teams[team] = true
	
func process_bankruptcies():
	"""Przetwarza wszystkie bankructwa po zakonczeniu rundy"""
	if not has_meta("bankrupt_teams"):
		return
	
	var bankrupt_teams = get_meta("bankrupt_teams")
	if bankrupt_teams.is_empty():
		return
	
	print("=== PRZETWARZANIE BANKRUCTW ===")
	
	for team in bankrupt_teams.keys():
		print("Zbuntowanie druzyny: ", team)
		
		var team_units = []
		
		# Zbierz wszystkie jednostki tej druzyny
		for coords in cavalry_map:
			if cavalry_map[coords].team == team:
				team_units.append(coords)
		
		for coords in knight_map:
			if knight_map[coords].team == team:
				team_units.append(coords)
				
		for coords in spearman_map:
			if spearman_map[coords].team == team:
				team_units.append(coords)
		
		for coords in farmer_map:
			if farmer_map[coords].team == team:
				team_units.append(coords)
		
		if team_units.is_empty():
			print("Brak jednostek do zbuntowania")
			continue
		
		# Przeksztalc wszystkie jednostki w bandytow
		for coords in team_units:
			if knight_map.has(coords):
				remove_knight_at(coords)
				place_farmer_at(coords, -1)
			elif cavalry_map.has(coords):
				remove_cavalry_at(coords)
				place_farmer_at(coords, -1)
			elif spearman_map.has(coords):
				remove_spearman_at(coords)
				place_farmer_at(coords, -1)
			elif farmer_map.has(coords):
				var farmer = farmer_map[coords]
				farmer.team = -1
			
			territory_map[coords] = -1
			update_hex_color(coords)
		
		# Postaw oboz bandytow obok jednostek
		var isolated_territories = []
		for coords in team_units:
			if territory_map.get(coords, 0) == -1:
				isolated_territories.append(coords)
		
		place_bandit_camp_near_units(team_units, isolated_territories)
		
		print("Wszystkie jednostki druzyny ", team, " zbuntowaly sie!")
	
	# Wyczysc liste zbankrutowanych
	bankrupt_teams.clear()
	print("=== KONIEC PRZETWARZANIA BANKRUCTW ===")

func _on_merge_button_pressed():
	"""Aktywuje tryb łączenia"""
	print("=== PRZYCISK POLACZ ===")
	print("Selected unit: ", selected_unit)
	
	if not selected_unit:
		print("Najpierw zaznacz jednostkę!")
		return
	
	if not (selected_unit is Farmer or selected_unit is Spearman or selected_unit is Knight):
		print("Można łączyć tylko farmerów, spearmanów lub knightów!")
		return
	
	merge_mode = true
	clear_highlights()
	
	print("TRYB LACZENIA AKTYWNY")
	
	if selected_unit is Farmer:
		for coords in farmer_map:
			var farmer = farmer_map[coords]
			if farmer.team == current_team and farmer != selected_unit:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(HIGHLIGHT_COLOR_MERGE)
					highlighted_hexes.append(hex)
		print("Tryb laczenia: Kliknij farmera aby polaczyc w spearmana")
	
	elif selected_unit is Spearman:
		for coords in spearman_map:
			var spearman = spearman_map[coords]
			if spearman.team == current_team and spearman != selected_unit:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(HIGHLIGHT_COLOR_MERGE)
					highlighted_hexes.append(hex)
		print("Tryb laczenia: Kliknij spearmana aby polaczyc w knighta")
	
	elif selected_unit is Knight:
		for coords in knight_map:
			var knight = knight_map[coords]
			if knight.team == current_team and knight != selected_unit:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(HIGHLIGHT_COLOR_MERGE)
					highlighted_hexes.append(hex)
		print("Tryb laczenia: Kliknij knighta aby polaczyc w cavalry")

func can_attack_through_walls(attacker, target_pos: Vector2i) -> bool:
	"""Sprawdza czy jednostka może zaatakować cel chroniony murami
	
	Knight może atakować przez mury tylko farmera
	Spearman nie może atakować przez mury w ogóle
	"""
	
	# Sprawdź czy cel jest otoczony murami
	var hex = get_hex_at(target_pos)
	if not hex or not hex.occupied_object:
		return true
	
	var target = hex.occupied_object
	
	# Sprawdź czy cel jest chroniony murami (wszystkie 6 krawędzi)
	var neighbors = get_neighbors(target_pos)
	var wall_count = 0
	
	for neighbor in neighbors:
		if has_wall_between(target_pos, neighbor):
			wall_count += 1
	
	# Jeśli nie ma pełnego otoczenia murami - może atakować
	if wall_count < 6:
		return true
	
	# CEL JEST OTOCZONY MURAMI - sprawdź rangę
	print("Cel otoczony murami (", wall_count, "/6)")
	
	if attacker is Knight:
		# Knight może zaatakować tylko farmera w murach
		if target is Farmer:
			print("Knight może zaatakować farmera w murach")
			return true
		else:
			print("Knight NIE może zaatakować ", target.get_class(), " w murach")
			return false
	
	elif attacker is Spearman:
		# Spearman nie może atakować nikogo w murach
		print("Spearman NIE może atakować przez mury")
		return false
	
	elif attacker is Farmer:
		# Farmer nie może atakować w ogóle
		return false
	
	return false

# --- KONWERSJE ---
func hex_to_pixel(hex_coords: Vector2i) -> Vector2:
	var q = hex_coords.x
	var r = hex_coords.y
	var x = q * hex_horiz_spacing + (r % 2) * (hex_horiz_spacing * 0.5)
	var y = r * hex_vert_spacing
	return Vector2(x, y)

func pixel_to_hex(pixel_pos: Vector2) -> Vector2i:
	var q = round(pixel_pos.x / hex_horiz_spacing)
	var offset = (int(q) % 2) * (hex_vert_spacing * 0.5)
	var r = round((pixel_pos.y - offset) / hex_vert_spacing)
	return Vector2i(int(q), int(r))

# --- HEXY ---
func add_hex_at(hex_coords: Vector2i) -> Hex:
	if hex_map.has(hex_coords):
		return hex_map[hex_coords]
	
	var hex = HEX_SCENE.instantiate()
	hex.grid_position = hex_coords
	hex.position = hex_to_pixel(hex_coords)
	
	add_child(hex)
	hex_map[hex_coords] = hex
	
	await hex.ready
	update_hex_color(hex_coords)
	
	return hex

func remove_hex_at(hex_coords: Vector2i):
	if hex_map.has(hex_coords):
		var hex = hex_map[hex_coords]
		hex.queue_free()
		hex_map.erase(hex_coords)
		territory_map.erase(hex_coords)

func get_hex_at(hex_coords: Vector2i) -> Hex:
	return hex_map.get(hex_coords, null)

func update_hex_color(hex_coords: Vector2i, animate: bool = false):
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	
	var new_color: Color
	if territory_map.has(hex_coords):
		var team = territory_map[hex_coords]
		if team == -1:
			new_color = BANDIT_COLOR
		elif team == -2:
			new_color = BANDIT_CAMP_COLOR
		elif team > 0:
			new_color = TEAM_COLORS[int(team)]
		else:
			new_color = Color("#2b2b2b")
	else:
		new_color = Color("#2b2b2b")
	
	if animate and hex.sprite:
		hex.animate_capture(new_color)
	else:
		hex.set_color(new_color)

func toggle_territory(hex_coords: Vector2i):
	if not hex_map.has(hex_coords):
		return
	
	var team_cycle = [0, 1, 2, 3, 4]
	var current_owner = territory_map.get(hex_coords, 0)
	var next_index = (team_cycle.find(current_owner) + 1) % team_cycle.size()
	var next_owner = team_cycle[next_index]
	
	if next_owner == 0:
		territory_map.erase(hex_coords)
	else:
		territory_map[hex_coords] = next_owner
	
	update_hex_color(hex_coords)

func create_rectangle_grid(width: int, height: int, start_pos: Vector2i = Vector2i.ZERO):
	for q in range(width):
		for r in range(height):
			var coords = start_pos + Vector2i(q, r)
			add_hex_at(coords)
	if turn_history:
		turn_history.reset_rewinds()

func clear_grid():
	# Usun linie murow
	if has_meta("hex_outlines"):
		var hex_outlines = get_meta("hex_outlines")
		for outline in hex_outlines.values():
			outline.queue_free()
		hex_outlines.clear()
	
	# Usun linie murow
	if has_meta("wall_lines"):
		var wall_lines = get_meta("wall_lines")
		for line in wall_lines.values():
			line.queue_free()
		wall_lines.clear()
	
	for farmer in farmer_map.values():
		farmer.queue_free()
	farmer_map.clear()
	
	for spearman in spearman_map.values():
		spearman.queue_free()
	spearman_map.clear()
	
	for knight in knight_map.values():
		knight.queue_free()
	knight_map.clear()
	
	for cavalry in cavalry_map.values():
		cavalry.queue_free()
	cavalry_map.clear()
	
	for castle in castle_map.values():
		castle.queue_free()
	castle_map.clear()
	
	for hex in hex_map.values():
		hex.queue_free()
	hex_map.clear()
	
	territory_map.clear()
	wall_map.clear()
	current_round = 1
	
	if turn_history: 
		turn_history.reset_rewinds()

# --- ZAMKI ---
func place_castle_at(hex_coords: Vector2i, team: int):
	var hex = get_hex_at(hex_coords)
	if not hex:
		add_hex_at(hex_coords)
		hex = get_hex_at(hex_coords)
	
	if castle_map.has(hex_coords):
		remove_castle_at(hex_coords)
	
	var castle = CASTLE_SCENE.instantiate()
	castle.team = team
	castle.hex_position = hex_coords
	castle.position = hex.position
	add_child(castle)
	
	castle_map[hex_coords] = castle
	hex.place_object(castle)
	
	territory_map[hex_coords] = team
	update_hex_color(hex_coords)

func remove_castle_at(hex_coords: Vector2i):
	if castle_map.has(hex_coords):
		var castle = castle_map[hex_coords]
		castle.queue_free()
		castle_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()
			
func place_cavalry_at(hex_coords: Vector2i, team: int):
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	if hex.occupied_object != null:
		return
	
	var cavalry = CAVALRY_SCENE.instantiate()
	cavalry.team = team
	cavalry.hex_position = hex_coords
	cavalry.position = hex.position
	add_child(cavalry)
	
	cavalry_map[hex_coords] = cavalry
	hex.place_object(cavalry)
	
	await get_tree().process_frame
	if cavalry.sprite:
		cavalry.sprite.scale = Vector2(1.0, 1.0)

func remove_cavalry_at(hex_coords: Vector2i):
	if cavalry_map.has(hex_coords):
		var cavalry = cavalry_map[hex_coords]
		cavalry.queue_free()
		cavalry_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_cavalry(from: Vector2i, to: Vector2i):
	if not cavalry_map.has(from):
		return
	
	var cavalry = cavalry_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
	
	# Cavalry może atakować WSZYSTKO oprócz cavalry w pełnych murach
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Cavalry VS Cavalry - WYMAGA braku pełnych murów
		if target is Cavalry and target.team != cavalry.team:
			var neighbors = get_neighbors(to)
			var wall_count = 0
			for neighbor in neighbors:
				if has_wall_between(to, neighbor):
					wall_count += 1
			
			if wall_count >= 6:
				print("Nie można zaatakować cavalry w pełnych murach!")
				return
			remove_cavalry_at(to)
		
		# Cavalry VS inne jednostki - IGNORUJE MURY
		elif target is Farmer and target.team != cavalry.team:
			remove_farmer_at(to)
		elif target is Spearman and target.team != cavalry.team:
			remove_spearman_at(to)
		elif target is Knight and target.team != cavalry.team:
			remove_knight_at(to)
		elif target is Castle:
			# Cavalry może przejąć obóz bandytów
			if target.team == -1:
				team_gold[cavalry.team] += BANDIT_CAMP_REWARD
				remove_castle_at(to)

				var bandit_units = []
				for coords in knight_map.keys():
					if knight_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in farmer_map.keys():
					if farmer_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in spearman_map.keys():
					if spearman_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in cavalry_map.keys():
					if cavalry_map[coords].team == -1:
						bandit_units.append(coords)

				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
				
				var bandit_territories = []
				for coords in territory_map.keys():
					var owner = territory_map[coords]
					if owner == -1 or owner == -2:
						bandit_territories.append(coords)

				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							remove_wall(coords, neighbor)
				
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)

			elif target.team != cavalry.team and target.team > 0 and target.team <= 4:
				var old_team = target.team
				
				if old_team == 1:
					if has_meta("defeat_popup"):
						var defeat_popup = get_meta("defeat_popup")
						await get_tree().create_timer(0.4).timeout
						defeat_popup.show_defeat(current_round)
				
				remove_castle_at(to)
				
				var old_team_territories = []
				for coords in territory_map:
					if territory_map[coords] == old_team:
						old_team_territories.append(coords)
				
				for coords in old_team_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if neighbor in old_team_territories:
							if has_wall_between(coords, neighbor):
								remove_wall(coords, neighbor)
				
				var old_team_units = []
				
				for coords in knight_map.keys():
					if knight_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in farmer_map.keys():
					if farmer_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in spearman_map.keys():
					if spearman_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in cavalry_map.keys():
					if cavalry_map[coords].team == old_team:
						old_team_units.append(coords)
				
				for coords in old_team_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
						place_farmer_at(coords, -1)
					elif farmer_map.has(coords):
						var farmer = farmer_map[coords]
						farmer.team = -1
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
						place_farmer_at(coords, -1)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
						place_farmer_at(coords, -1)
					
					territory_map[coords] = -1
					update_hex_color(coords)
				
				if old_team_units.size() > 0:
					place_bandit_camp_near_units(old_team_units, old_team_units)
				
				for coords in old_team_territories:
					if territory_map.get(coords, 0) == old_team:
						territory_map.erase(coords)
						update_hex_color(coords)
						
				if old_team != 1:
					check_victory()
		else:
			if target.team == cavalry.team:
				print("Nie można atakować własnej jednostki!")
				return
			return
	
	# Przenieś cavalry
	cavalry_map.erase(from)
	from_hex.remove_object()
	
	cavalry.hex_position = to
	cavalry_map[to] = cavalry
	to_hex.place_object(cavalry)
	cavalry.sprite.scale = Vector2.ZERO
	
	cavalry.animate_slide_to(to_hex.position, 0.3)
	var cavalry_pop = create_tween()
	cavalry_pop.tween_property(cavalry.sprite, "scale", Vector2.ONE, 0.15).set_delay(0.2)
	
	var old_hex = get_hex_at(from)
	if old_hex and old_hex.has_meta("is_unit_selected"):
		old_hex.set_selected_state(false)
	
	# LICZNIK RUCHÓW
	if not cavalry_moves_this_turn.has(cavalry):
		cavalry_moves_this_turn[cavalry] = 0
	cavalry_moves_this_turn[cavalry] += 1
	
	# Regalo capture po zakończeniu slide animacji
	await get_tree().create_timer(0.15).timeout
	capture_territory(to, cavalry.team)
	
	if cavalry_moves_this_turn[cavalry] >= 2:
		units_moved_this_turn.append(cavalry)
		cavalry.set_selected(false)
		selected_unit = null
		clear_highlights()
		pulse_available_units()
	else:
		clear_highlights()
		var new_hex = get_hex_at(to)
		if new_hex:
			new_hex.set_selected_state(true)
		highlight_unit_moves(cavalry.hex_position, cavalry.team)

func merge_knights_to_cavalry(knight1_pos: Vector2i, knight2_pos: Vector2i):
	"""Łączy dwóch knightów w cavalry"""
	if not knight_map.has(knight1_pos) or not knight_map.has(knight2_pos):
		return
	
	var knight1 = knight_map[knight1_pos]
	var knight2 = knight_map[knight2_pos]
	
	if knight1.team != knight2.team:
		return
	
	remove_knight_at(knight2_pos)
	remove_knight_at(knight1_pos)
	
	place_cavalry_at(knight2_pos, knight1.team)
	
	print("Utworzono cavalry!")
	merge_mode = false
	clear_highlights()
	update_ui()

func on_cavalry_clicked(cavalry):
	if not game_mode:
		return
	if wall_placement_mode:
		return
	
	if merge_mode:
		print("Cavalry nie może być łączony!")
		return
	
	if cavalry.team != current_team:
		return
	
	var moves_done = cavalry_moves_this_turn.get(cavalry, 0)
	if moves_done >= 2:
		print("Cavalry wykonał już 2 ruchy w tej turze")
		return
	
	# NOWE: Odklikanie
	if selected_unit == cavalry:
		clear_selected_unit_highlight()
		selected_unit = null
		clear_highlights()
		pulse_available_units()
		update_ui()
		return
	
	# NOWE: Wyczyść poprzednią
	if selected_unit:
		clear_selected_unit_highlight()
	
	clear_highlights()
	merge_mode = false
	selected_unit = cavalry
	if cavalry.has_method("set_selected"):
		cavalry.set_selected(true)
	
	set_selected_unit_highlight(cavalry)
	
	highlight_unit_moves(cavalry.hex_position, cavalry.team)
	update_ui()
			
# --- SPEARMEN ---
func place_spearman_at(hex_coords: Vector2i, team: int):
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	if hex.occupied_object != null:
		return
	
	var spearman = SPEARMAN_SCENE.instantiate()
	spearman.team = team
	spearman.hex_position = hex_coords
	spearman.position = hex.position
	add_child(spearman)
	
	spearman_map[hex_coords] = spearman
	hex.place_object(spearman)
	
	await get_tree().process_frame
	if spearman.sprite:
		spearman.sprite.scale = Vector2(1.0, 1.0)

func remove_spearman_at(hex_coords: Vector2i):
	if spearman_map.has(hex_coords):
		var spearman = spearman_map[hex_coords]
		spearman.queue_free()
		spearman_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_spearman(from: Vector2i, to: Vector2i):
	if not spearman_map.has(from):
		return
	
	var spearman = spearman_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
	
	var from_owner = territory_map.get(from, 0)
	var to_owner = territory_map.get(to, 0)
	
	if castle_map.has(to):
		var target_castle = castle_map[to]
		if target_castle.team != spearman.team:
			var old_team = target_castle.team
			
			if old_team == 1:
				if has_meta("defeat_popup"):
					var defeat_popup = get_meta("defeat_popup")
					await get_tree().create_timer(0.4).timeout
					defeat_popup.show_defeat(current_round)
			
			if old_team == -1:
				print("=== SPEARMAN PRZEJMUJE OBÓZ BANDYTÓW ===")
				
				team_gold[spearman.team] += BANDIT_CAMP_REWARD
				print("Otrzymano ", BANDIT_CAMP_REWARD, " złota!")
				remove_castle_at(to)
				
				var bandit_units = []
				for coords in knight_map.keys():
					if knight_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in farmer_map.keys():
					if farmer_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in spearman_map.keys():
					if spearman_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in cavalry_map.keys():
					if cavalry_map[coords].team == -1:
						bandit_units.append(coords)
				
				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
				
				# Usuń wszystkie terytoria bandytów
				var bandit_territories = []
				for coords in territory_map.keys():
					var owner = territory_map[coords]
					if owner == -1 or owner == -2:
						bandit_territories.append(coords)
				
				# Usuń mury
				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							remove_wall(coords, neighbor)
				
				# Resetuj pola
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)

			elif old_team > 0 and old_team <= 4:
				print("=== SPEARMAN PRZEJMUJE ZAMEK GRACZA ===")
				remove_castle_at(to)
				
				var old_team_territories = []
				for coords in territory_map:
					if territory_map[coords] == old_team:
						old_team_territories.append(coords)
				
				for coords in old_team_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if neighbor in old_team_territories:
							if has_wall_between(coords, neighbor):
								remove_wall(coords, neighbor)
				
				var old_team_units = []
				for coords in knight_map.keys():
					if knight_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in farmer_map.keys():
					if farmer_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in spearman_map.keys():
					if spearman_map[coords].team == old_team:
						old_team_units.append(coords)
				for coords in cavalry_map.keys():
					if cavalry_map[coords].team == old_team:
						old_team_units.append(coords)
				
				for coords in old_team_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
						place_farmer_at(coords, -1)
					elif farmer_map.has(coords):
						var farmer = farmer_map[coords]
						farmer.team = -1
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
						place_farmer_at(coords, -1)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
						place_farmer_at(coords, -1)
					
					territory_map[coords] = -1
					update_hex_color(coords)
				
				if old_team_units.size() > 0:
					place_bandit_camp_near_units(old_team_units, old_team_units)
				
				for coords in old_team_territories:
					if territory_map.get(coords, 0) == old_team:
						territory_map.erase(coords)
						update_hex_color(coords)
						
				if old_team != 1:
					check_victory()
	
	# DODAJ: Obsługa ataku na wrogie jednostki
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Spearman może atakować farmera (team 1-4 I bandytów team -1)
		if target is Farmer:
			if target.team != spearman.team:
				# Sprawdź mury
				if not can_attack_through_walls(spearman, to):
					print("Nie można zaatakować - cel chroniony murami!")
					return
				# Usuń farmera
				remove_farmer_at(to)
		elif target is Spearman and target.team != spearman.team:
			# Sprawdź mury
			if not can_attack_through_walls(spearman, to):
				print("Nie można zaatakować - cel chroniony murami!")
				return
			# Usuń spearmana
			remove_spearman_at(to)
		elif target is Knight:
			# NOWE: Może atakować knightów bandytów (team -1)
			if target.team == -1:
				if not can_attack_through_walls(spearman, to):
					print("Nie można zaatakować - cel chroniony murami!")
					return
				remove_knight_at(to)
			else:
				print("Spearman nie może zaatakować knighta gracza!")
				return
		else:
			# Własna jednostka lub zamek
			if target.team == spearman.team:
				print("Nie można atakować własnej jednostki!")
				return
			return
	
	# Sprawdź wrogie mury przed wejściem
	if from_owner == spearman.team and to_owner != spearman.team:
		var enemy_neighbors = get_neighbors(to)
		var edge_index = enemy_neighbors.find(from)
		
		if edge_index != -1:
			var enemy_wall_key = "%d,%d-edge%d" % [to.x, to.y, edge_index]
			if wall_map.has(enemy_wall_key):
				var wall_data = wall_map[enemy_wall_key]
				if wall_data.get("team", 0) != spearman.team:
					print("Wrogi mur blokuje wejście!")
					return
	
	# Przenieś spearmana
	spearman_map.erase(from)
	from_hex.remove_object()
	
	spearman.hex_position = to
	spearman_map[to] = spearman
	to_hex.place_object(spearman)
	spearman.sprite.scale = Vector2.ZERO
	
	spearman.animate_slide_to(to_hex.position, 0.3)
	var spearman_pop = create_tween()
	spearman_pop.tween_property(spearman.sprite, "scale", Vector2.ONE, 0.15).set_delay(0.2)
	
	units_moved_this_turn.append(spearman)
	
	var old_hex = get_hex_at(from)
	if old_hex and old_hex.has_meta("is_unit_selected"):
		old_hex.set_selected_state(false)
	
	if selected_unit == spearman:
		clear_selected_unit_highlight()
		spearman.set_selected(false)
		selected_unit = null
	
	await get_tree().create_timer(0.15).timeout
	capture_territory(to, spearman.team)
	clear_highlights()
	pulse_available_units()

func merge_farmers_to_spearman(farmer1_pos: Vector2i, farmer2_pos: Vector2i):
	"""Łączy dwóch farmerów w spearmana"""
	if not farmer_map.has(farmer1_pos) or not farmer_map.has(farmer2_pos):
		return
	
	var farmer1 = farmer_map[farmer1_pos]
	var farmer2 = farmer_map[farmer2_pos]
	
	if farmer1.team != farmer2.team:
		return
	
	remove_farmer_at(farmer2_pos)
	remove_farmer_at(farmer1_pos)
	
	place_spearman_at(farmer2_pos, farmer1.team)
	
	print("Utworzono spearmana!")
	merge_mode = false
	clear_highlights()
	update_ui()

func merge_spearmen_to_knight(spearman1_pos: Vector2i, spearman2_pos: Vector2i):
	"""Łączy dwóch spearmanów w knighta"""
	if not spearman_map.has(spearman1_pos) or not spearman_map.has(spearman2_pos):
		return
	
	var spearman1 = spearman_map[spearman1_pos]
	var spearman2 = spearman_map[spearman2_pos]
	
	if spearman1.team != spearman2.team:
		return
	
	remove_spearman_at(spearman2_pos)
	remove_spearman_at(spearman1_pos)
	
	place_knight_at(spearman2_pos, spearman1.team)
	
	print("Utworzono knighta!")
	merge_mode = false
	clear_highlights()
	update_ui()

func on_spearman_clicked(spearman):
	if not game_mode:
		return
	if wall_placement_mode:
		return
	
	# === NOWE: Łączenie spearmanów ===
	if selected_unit and selected_unit is Spearman and selected_unit != spearman:
		if spearman.team == selected_unit.team:
			merge_spearmen_to_knight(selected_unit.hex_position, spearman.hex_position)
			return
	
	# === Reszta bez zmian ===
	if spearman.team != current_team:
		return
	
	if spearman in units_moved_this_turn:
		print("Ta jednostka już się ruszyła w tej turze")
		return
	
	if selected_unit == spearman:
		clear_selected_unit_highlight()
		selected_unit = null
		clear_highlights()
		pulse_available_units()
		update_ui()
		return
	
	if selected_unit:
		clear_selected_unit_highlight()
	
	# DODAJ TUTAJ: Zatrzymaj pulse tweeny PRZED highlight
	clear_unit_pulses()
	
	clear_highlights()
	selected_unit = spearman
	if spearman.has_method("set_selected"):
		spearman.set_selected(true)
	
	set_selected_unit_highlight(spearman)
	
	highlight_unit_moves(spearman.hex_position, spearman.team)
	update_ui()

# --- RYCERZE ---
func place_knight_at(hex_coords: Vector2i, team: int):
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	if hex.occupied_object != null:
		return
	
	var knight = KNIGHT_SCENE.instantiate()
	knight.team = team
	knight.hex_position = hex_coords
	knight.position = hex.position
	add_child(knight)
	
	knight_map[hex_coords] = knight
	hex.place_object(knight)
	
	# DODAJ: Wymus prawidlowa skale po dodaniu do sceny
	await get_tree().process_frame
	if knight.sprite:
		knight.sprite.scale = Vector2(1.0, 1.0)

func remove_knight_at(hex_coords: Vector2i):
	if knight_map.has(hex_coords):
		var knight = knight_map[hex_coords]
		knight.queue_free()
		knight_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_knight(from: Vector2i, to: Vector2i):
	if not knight_map.has(from):
		return
	
	var knight = knight_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
		
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Jeśli to jednostka wroga
		if (target is Knight or target is Spearman or target is Farmer) and target.team != knight.team:
			if not can_attack_through_walls(knight, to):
				print("Nie można zaatakować - cel chroniony murami!")
				return
	
	# ZMIANA: Jesli atakujemy zamek wroga - ZNISZCZ GO
	if castle_map.has(to):
		var target_castle = castle_map[to]
		if target_castle.team != knight.team:
			var old_team = target_castle.team
			
			if old_team == 1:
				if has_meta("defeat_popup"):
					var defeat_popup = get_meta("defeat_popup")
					await get_tree().create_timer(0.4).timeout
					defeat_popup.show_defeat(current_round)
			
			if old_team == -1:
				print("=== PRZEJECIE OBOZU BANDYTOW ===")
				
				team_gold[knight.team] += BANDIT_CAMP_REWARD
				print("Otrzymano ", BANDIT_CAMP_REWARD, " złota za przejęcie obozu!")
				# Usun oboz
				remove_castle_at(to)
				
				# Znajdz WSZYSTKIE jednostki bandytow (team -1)
				var bandit_units = []
				for coords in knight_map.keys():
					if knight_map[coords].team == -1:
						bandit_units.append(coords)
				for coords in farmer_map.keys():
					if farmer_map[coords].team == -1:
						bandit_units.append(coords)
				
				print("Znaleziono jednostek bandytow: ", bandit_units.size())
				
				# Usun wszystkie jednostki bandytow
				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
				
				# Znajdz wszystkie pola bandytow (team -1 i -2)
				var bandit_territories = []
				for coords in territory_map.keys():
					var owner = territory_map[coords]
					if owner == -1 or owner == -2:
						bandit_territories.append(coords)
				
				print("Znaleziono terytoriow bandytow: ", bandit_territories.size())
				
				# Usun WSZYSTKIE mury miedzy polami bandytow
				print("Usuwanie murow bandytow...")
				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							remove_wall(coords, neighbor)
				
				# Resetuj wszystkie pola bandytow do neutralnych
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)
				
				print("Oboz bandytow przejety! Jednostki i terytoria usuniete.")
			else:
				# NORMALNA OBSLUGA: Przejecie zamku gracza (team 1-4)
				# ZNISZCZ zamek
				remove_castle_at(to)
				
				# ZNISZCZ WSZYSTKIE mury starego wlasciciela
				var old_team_territories = []
				for coords in territory_map:
					if territory_map[coords] == old_team:
						old_team_territories.append(coords)
				
				# Usun wszystkie mury w regionie starego teamu
				for coords in old_team_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if neighbor in old_team_territories:
							if has_wall_between(coords, neighbor):
								remove_wall(coords, neighbor)
				
				# Konwertuj WSZYSTKIE jednostki starego teamu na bandytow
				var old_team_units = []
				
				for coords in knight_map.keys():
					if knight_map[coords].team == old_team:
						old_team_units.append(coords)
				
				for coords in farmer_map.keys():
					if farmer_map[coords].team == old_team:
						old_team_units.append(coords)
				
				# Przeksztalc wszystkie jednostki w farmerow bandytow
				for coords in old_team_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
						place_farmer_at(coords, -1)
					elif farmer_map.has(coords):
						var farmer = farmer_map[coords]
						farmer.team = -1
					
					territory_map[coords] = -1
					update_hex_color(coords)
				
				# Postaw 1 oboz bandytow
				if old_team_units.size() > 0:
					place_bandit_camp_near_units(old_team_units, old_team_units)
				
				# Reszta pol starego teamu → neutralna
				for coords in old_team_territories:
					if territory_map.get(coords, 0) == old_team:
						territory_map.erase(coords)
						update_hex_color(coords)
				
				if old_team != 1:
					check_victory()
				print("Zniszczono zamek druzyny ", old_team, "!")
	
	# Usun wroga jednostke jesli jest
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		if target is Knight and knight_map.has(to):
			var target_knight = knight_map[to]
			if target_knight.team != knight.team:
				remove_knight_at(to)
		elif target is Farmer and farmer_map.has(to):
			var target_farmer = farmer_map[to]
			if target_farmer.team != knight.team:
				remove_farmer_at(to)
		elif target is Spearman and spearman_map.has(to):
			var target_spearman = spearman_map[to]
			if target_spearman.team != knight.team:
				remove_spearman_at(to)
		else:
			if target.team == knight.team:
				print("Nie mozna atakowac wlasnej jednostki!")
				return
			if target is Cavalry:
				print("Knight nie może zaatakować Cavalry!")
				return
	
	# Przenies rycerza
	knight_map.erase(from)
	from_hex.remove_object()
	
	knight.hex_position = to
	knight_map[to] = knight
	to_hex.place_object(knight)
	knight.sprite.scale = Vector2.ZERO
	
	knight.animate_slide_to(to_hex.position, 0.3)
	var knight_pop = create_tween()
	knight_pop.tween_property(knight.sprite, "scale", Vector2.ONE, 0.15).set_delay(0.2)
	
	units_moved_this_turn.append(knight)
	
	var old_hex = get_hex_at(from)
	if old_hex and old_hex.has_meta("is_unit_selected"):
		old_hex.set_selected_state(false)
	
	if selected_unit == knight:
		clear_selected_unit_highlight()
		if knight.has_method("set_selected"):
			knight.set_selected(false)
		selected_unit = null
	
	await get_tree().create_timer(0.15).timeout
	
	# Przejmij terytorium
	capture_territory(to, knight.team)
	clear_highlights()
	pulse_available_units()
	
func remove_wall(hex1: Vector2i, hex2: Vector2i):
	"""Usuwa wall TYLKO z hex1 (nie dotyka hex2)"""
	
	var neighbors1 = get_neighbors(hex1)
	var edge_index1 = neighbors1.find(hex2)
	
	if edge_index1 != -1:
		var key1 = "%d,%d-edge%d" % [hex1.x, hex1.y, edge_index1]
		if wall_map.has(key1):
			wall_map.erase(key1)
			
			if has_meta("wall_lines"):
				var wall_lines = get_meta("wall_lines")
				if wall_lines.has(key1):
					wall_lines[key1].queue_free()
					wall_lines.erase(key1)
			
func purge_walls_connected_to(hex_coords: Vector2i):
	"""Usuwa TYLKO walle tego konkretnego hexa (6 krawedzi)"""
	print("PURGE: usuwam walle hexa ", hex_coords)
	
	for edge_index in range(6):
		var edge_key = "%d,%d-edge%d" % [hex_coords.x, hex_coords.y, edge_index]
		
		if wall_map.has(edge_key):
			wall_map.erase(edge_key)
			
			if has_meta("wall_lines"):
				var wall_lines = get_meta("wall_lines")
				if wall_lines.has(edge_key):
					wall_lines[edge_key].queue_free()
					wall_lines.erase(edge_key)
				
# --- FARMERZY ---
func place_farmer_at(hex_coords: Vector2i, team: int):
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	if hex.occupied_object != null:
		return
	
	var farmer = FARMER_SCENE.instantiate()
	farmer.team = team
	farmer.hex_position = hex_coords
	farmer.position = hex.position
	add_child(farmer)
	
	farmer_map[hex_coords] = farmer
	hex.place_object(farmer)

func remove_farmer_at(hex_coords: Vector2i):
	if farmer_map.has(hex_coords):
		var farmer = farmer_map[hex_coords]
		farmer.queue_free()
		farmer_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_farmer(from: Vector2i, to: Vector2i):
	if not farmer_map.has(from):
		return
	
	var farmer = farmer_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
	
	var from_owner = territory_map.get(from, 0)
	var to_owner = territory_map.get(to, 0)
	
	# DODAJ: Obsługa ataku na wrogiego farmera
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Farmer może atakować tylko farmera (nie spearmana ani knighta)
		if target is Farmer and target.team != farmer.team:
			# Sprawdź mury
			var neighbors = get_neighbors(to)
			var wall_count = 0
			for neighbor in neighbors:
				if has_wall_between(to, neighbor):
					wall_count += 1
			
			if wall_count >= 6:
				print("Nie można zaatakować - cel chroniony murami!")
				return
			
			# Usuń wrogiego farmera
			remove_farmer_at(to)
		else:
			# Nie może atakować innych jednostek
			print("Farmer może atakować tylko farmera!")
			return
	
	# TYLKO sprawdź WROGIE mury (nie swoje!)
	if from_owner == farmer.team and to_owner != farmer.team:
		var enemy_neighbors = get_neighbors(to)
		var edge_index = enemy_neighbors.find(from)
		
		if edge_index != -1:
			var enemy_wall_key = "%d,%d-edge%d" % [to.x, to.y, edge_index]
			if wall_map.has(enemy_wall_key):
				var wall_data = wall_map[enemy_wall_key]
				if wall_data.get("team", 0) != farmer.team:
					print("Wrogi mur blokuje wejście!")
					return
	
	# Przenieś farmera
	farmer_map.erase(from)
	from_hex.remove_object()
	
	farmer.hex_position = to
	farmer_map[to] = farmer
	to_hex.place_object(farmer)
	farmer.sprite.scale = Vector2.ZERO
	
	farmer.animate_slide_to(to_hex.position, 0.3)
	var farmer_pop = create_tween()
	farmer_pop.tween_property(farmer.sprite, "scale", Vector2.ONE, 0.15).set_delay(0.2)
	
	units_moved_this_turn.append(farmer)
	
	var old_hex = get_hex_at(from)
	if old_hex and old_hex.has_meta("is_unit_selected"):
		old_hex.set_selected_state(false)
	
	clear_unit_pulses()
	
	if selected_unit == farmer:
		clear_selected_unit_highlight()
		farmer.set_selected(false)
		selected_unit = null
	
	await get_tree().create_timer(0.15).timeout
	if farmer.team == BANDIT_TEAM:
		check_bandit_camp_after_move(from, to)
	capture_territory(to, farmer.team)
	clear_highlights()
	pulse_available_units()
	
func check_bandit_camp_after_move(from: Vector2i, to: Vector2i):
	"""Sprawdza czy bandyta ruszył się i czy można postawić obóz na starym miejscu"""
	
	# Sprawdź czy bandyci mają już obóz
	for coords in castle_map:
		if castle_map[coords].team == BANDIT_TEAM:
			return  # Już mają obóz
	
	print("Bandyta ruszył się - sprawdzam czy można postawić obóz na ", from)
	
	var hex = get_hex_at(from)
	if not hex or hex.occupied_object != null:
		print("Pole zajęte - nie można postawić obozu")
		return
	
	# Sprawdź czy są mury wokół (jeśli tak - nie stawiaj)
	var neighbors = get_neighbors(from)
	var wall_count = 0
	for neighbor in neighbors:
		if has_wall_between(from, neighbor):
			wall_count += 1
	
	if wall_count >= 6:
		print("Pole otoczone murami - nie można postawić obozu")
		return
	
	# Postaw obóz!
	var castle = CASTLE_SCENE.instantiate()
	castle.team = BANDIT_TEAM
	castle.hex_position = from
	castle.position = hex.position
	add_child(castle)
	
	castle_map[from] = castle
	hex.place_object(castle)
	
	territory_map[from] = -2  # Oznacz jako obóz
	update_hex_color(from)
	
	print("✓ Utworzono obóz bandytów na ", from)

func merge_farmers(farmer1_pos: Vector2i, farmer2_pos: Vector2i):
	"""Laczy dwoch farmerow w rycerza"""
	if not farmer_map.has(farmer1_pos) or not farmer_map.has(farmer2_pos):
		return
	
	var farmer1 = farmer_map[farmer1_pos]
	var farmer2 = farmer_map[farmer2_pos]
	
	if farmer1.team != farmer2.team:
		return
	
	# Usun farmerow
	remove_farmer_at(farmer2_pos)
	remove_farmer_at(farmer1_pos)
	
	# Stworz rycerza w miejscu pierwszego farmera
	place_knight_at(farmer1_pos, farmer1.team)
	
	print("Utworzono rycerza!")
	merge_mode = false
	clear_highlights()
	update_ui()

func remove_all_at(hex_coords: Vector2i):
	remove_farmer_at(hex_coords)
	remove_spearman_at(hex_coords)
	remove_knight_at(hex_coords)
	remove_cavalry_at(hex_coords)
	remove_castle_at(hex_coords)
	remove_hex_at(hex_coords)
	
func get_connected_territories(team: int) -> Array:
	"""Zwraca tylko pola POŁĄCZONE z zamkiem (dla przychodów)"""
	
	# Znajdz zamki druzyny
	var castle_positions = []
	for coords in castle_map:
		if castle_map[coords].team == team:
			castle_positions.append(coords)
	
	if castle_positions.is_empty():
		return []  # Brak zamku = brak przychodow
	
	# Flood fill od zamkow (tylko przez pola tej druzyny)
	var connected = []
	var visited = {}
	var queue = castle_positions.duplicate()
	
	for pos in castle_positions:
		visited[pos] = true
		connected.append(pos)
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var neighbors = get_neighbors(current)
		
		for neighbor in neighbors:
			if visited.has(neighbor):
				continue
			if not territory_map.has(neighbor):
				continue
			if territory_map[neighbor] != team:
				continue
			
			visited[neighbor] = true
			connected.append(neighbor)
			queue.append(neighbor)
	
	return connected

# --- PRZEJMOWANIE ---
func capture_territory(hex_coords: Vector2i, team: int):
	var old_owner = territory_map.get(hex_coords, 0)
	
	# Usun walle PRZED zmiana wlasciciela
	if old_owner > 0 and old_owner != team:
		remove_walls_around_captured_hex(hex_coords, old_owner)
		purge_walls_connected_to(hex_coords)
	
	# Zmien wlasciciela — ANIMUJ tego hexa (jest to hex na który właśnie wylądowała jednostka)
	territory_map[hex_coords] = team
	update_hex_color(hex_coords, true)
	
	# Sprawdz czy przejelismy zamek
	if castle_map.has(hex_coords):
		var castle = castle_map[hex_coords]
		if castle.team != team:
			capture_castle(hex_coords, team, castle.team)
			return
	
	# Sprawdz izolacje
	if old_owner > 0 and old_owner != team:
		var has_castle = false
		for coords in castle_map:
			if castle_map[coords].team == old_owner:
				has_castle = true
				break
		
		if has_castle:
			check_team_isolation(old_owner)
	
	update_ui()
	
func remove_walls_around_captured_hex(hex_coords: Vector2i, old_team: int):
	"""Usuwa TYLKO walle przejętego hexa, nie dotyka walli sąsiadów"""
	print("=== USUWANIE WALLI ===")
	print("Przejete pole: ", hex_coords, " (stary team: ", old_team, ")")
	
	# Usun TYLKO 6 walli tego hexa (nie dotykaj sasiadow!)
	for edge_index in range(6):
		var edge_key = "%d,%d-edge%d" % [hex_coords.x, hex_coords.y, edge_index]
		
		if wall_map.has(edge_key):
			wall_map.erase(edge_key)
			
			# Usun wizualna linie
			if has_meta("wall_lines"):
				var wall_lines = get_meta("wall_lines")
				if wall_lines.has(edge_key):
					wall_lines[edge_key].queue_free()
					wall_lines.erase(edge_key)
			
			print("  -> Usunieto wall edge", edge_index, " hexa ", hex_coords)
	
	print("=== KONIEC USUWANIA WALLI ===")
	
func check_team_isolation(team: int):
	"""Sprawdza czy jakas czesc terytorium druzyny zostala odcieta"""
	var team_territories = []
	for coords in territory_map:
		if territory_map[coords] == team:
			team_territories.append(coords)
	
	if team_territories.is_empty():
		return
	
	var castle_territories = []
	for coords in castle_map:
		if castle_map[coords].team == team:
			castle_territories.append(coords)
	
	if castle_territories.is_empty():
		print("Druzyna ", team, " nie ma zamku - konwersja calego terytorium")
		for coords in team_territories:
			convert_to_mercenary(coords)
		return
	
	var connected = flood_fill_team(castle_territories, team)
	
	# Znajdz odciete regiony
	var checked = {}
	var isolated_regions = []  # Lista regionow [[coords, coords], [coords]]
	
	for coords in team_territories:
		if coords in connected or checked.has(coords):
			continue
		
		# Znaleziono odciety region
		var region = get_isolated_region(coords, team)
		isolated_regions.append(region)
		
		for pos in region:
			checked[pos] = true
	
	# Konwertuj kazdy odciety region (1 oboz na region)
	for region in isolated_regions:
		print("Znaleziono odciety region z ", region.size(), " polami")
		convert_isolated_region(region, team)
		
func convert_isolated_region(region: Array, original_team: int):
	"""Konwertuje TYLKO pola z jednostkami na bandytów, reszta pozostaje u wlasciciela (odcieta)"""
	print("=== KONWERSJA ODCIETEGO REGIONU ===")
	print("Pola w regionie: ", region.size())
	
	# Znajdz wszystkie jednostki w regionie
	var units_positions = []
	for coords in region:
		if knight_map.has(coords):
			units_positions.append(coords)
		elif spearman_map.has(coords):
			units_positions.append(coords)
		elif farmer_map.has(coords):
			units_positions.append(coords)
		elif cavalry_map.has(coords):
			units_positions.append(coords)
	
	print("Jednostek do konwersji: ", units_positions.size())
	
	# ZMIANA: Jesli nie ma jednostek - pola POZOSTAJA u wlasciciela (tylko odciete)
	if units_positions.is_empty():
		print("Brak jednostek - pola pozostaja u wlasciciela (odciete od zamku)")
		# NIE zmieniamy territory_map - pola dalej naleza do original_team
		return
	
	# Przeksztalc jednostki w farmerow bandytow
	for coords in units_positions:
		if knight_map.has(coords):
			remove_knight_at(coords)
			place_farmer_at(coords, -1)
		elif spearman_map.has(coords):
			remove_spearman_at(coords)
			place_farmer_at(coords, -1)
		elif cavalry_map.has(coords):  
			remove_cavalry_at(coords)
			place_farmer_at(coords, -1)
		elif farmer_map.has(coords):
			var farmer = farmer_map[coords]
			farmer.team = -1
		
		# TYLKO pola z jednostkami staja sie bandyckie
		territory_map[coords] = -1
		update_hex_color(coords)
	
	# Usun WSZYSTKIE mury w regionie (bandyci nie zachowuja murow)
	print("Usuwanie walli w regionie...")
	for coords in region:
		for edge_index in range(6):
			var edge_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
			if wall_map.has(edge_key):
				wall_map.erase(edge_key)
				
				if has_meta("wall_lines"):
					var wall_lines = get_meta("wall_lines")
					if wall_lines.has(edge_key):
						wall_lines[edge_key].queue_free()
						wall_lines.erase(edge_key)
	
	# Postaw JEDEN oboz bandytow dla jednostek
	var camp_placed = place_bandit_camp_near_units(units_positions, units_positions)
	
	if not camp_placed:
		print("UWAGA: Nie znaleziono miejsca na oboz bandytow!")
	
	print("=== KONIEC KONWERSJI REGIONU ===")
	print("Bandytow: ", units_positions.size(), " | Pola wlasciciela (odciete): ", region.size() - units_positions.size())

func capture_castle(castle_coords: Vector2i, new_team: int, old_team: int):
	"""Przejmuje zamek wroga - jednostki wroga NATYCHMIAST staja sie bandytami"""
	print("=== PRZEJECIE ZAMKU ===")
	print("Zamek druzyny ", old_team, " przejety przez druzyne ", new_team)
	
	var castle = castle_map[castle_coords]
	castle.team = new_team
	
	# Znajdz 3 najblizsze pola wroga lub puste
	var nearby_hexes = get_nearest_hexes(castle_coords, 3, old_team, new_team)
	for coords in nearby_hexes:
		territory_map[coords] = new_team
		update_hex_color(coords)
	
	# ZMIANA: Konwertuj wszystkie jednostki starego wlasciciela na bandytow
	var old_team_units = []
	
	# Zbierz wszystkie jednostki starego wlasciciela
	for coords in knight_map:
		if knight_map[coords].team == old_team:
			old_team_units.append(coords)
			
	for coords in spearman_map:
		if spearman_map[coords].team == old_team:
			old_team_units.append(coords)
	
	for coords in farmer_map:
		if farmer_map[coords].team == old_team:
			old_team_units.append(coords)
	
	if old_team_units.is_empty():
		print("Stary wlasciciel nie ma jednostek")
		return
	
	print("Konwersja jednostek starego wlasciciela (", old_team_units.size(), ") na bandytow...")
	
	# Znajdz wszystkie pola starego teamu (aby usunac walle)
	var old_team_region = []
	for coords in territory_map:
		if territory_map[coords] == old_team:
			old_team_region.append(coords)
	
	# DODAJ: Usun WSZYSTKIE walle w regionie starego teamu (jak przy bandytach)
	print("Usuwanie walli starego teamu...")
	for coords in old_team_region:
		var neighbors = get_neighbors(coords)
		for neighbor in neighbors:
			# Usun WSZYSTKIE mury (nie tylko wewnetrzne)
			if has_wall_between(coords, neighbor):
				remove_wall(coords, neighbor)
	
	# Przeksztalc wszystkie jednostki w farmerow bandytow
	for coords in old_team_units:
		if knight_map.has(coords):
			remove_knight_at(coords)
			place_farmer_at(coords, -1)
		elif spearman_map.has(coords):
			remove_spearman_at(coords)
			place_farmer_at(coords, -1)
		elif farmer_map.has(coords):
			var farmer = farmer_map[coords]
			farmer.team = -1
		
		territory_map[coords] = -1
		update_hex_color(coords)
	
	# Zbierz terytoria bandyckie (tylko te z jednostkami)
	var isolated_territories = []
	for coords in old_team_units:
		if territory_map.get(coords, 0) == -1:
			isolated_territories.append(coords)
	
	# Postaw oboz bandytow obok jednostek
	place_bandit_camp_near_units(old_team_units, isolated_territories)
	
	# Reszta pol starego wlasciciela (bez jednostek) zostaje neutralna
	for coords in old_team_region:
		if territory_map.get(coords, 0) == old_team:
			territory_map.erase(coords)
			update_hex_color(coords)
	
	check_victory()
	print("=== KONIEC PRZEJECIA ZAMKU ===")

func get_nearest_hexes(center: Vector2i, count: int, old_team: int, new_team: int) -> Array:
	"""Zwraca N najblizszych pol wroga lub pustych"""
	var candidates = []
	var checked = {}
	var queue = [center]
	checked[center] = true
	
	while not queue.is_empty() and candidates.size() < count * 3:
		var current = queue.pop_front()
		var neighbors = get_neighbors(current)
		
		for neighbor in neighbors:
			if checked.has(neighbor):
				continue
			checked[neighbor] = true
			
			if not hex_map.has(neighbor):
				continue
			
			var owner = territory_map.get(neighbor, 0)
			# Pole wroga lub puste (nie inne druzyny)
			if owner == old_team or owner == 0:
				var distance = get_hex_distance(center, neighbor)
				candidates.append({"coords": neighbor, "distance": distance})
			
			queue.append(neighbor)
	
	# Sortuj po odleglosci
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	
	var result = []
	for i in range(min(count, candidates.size())):
		result.append(candidates[i].coords)
	
	return result

func flood_fill_team(start_positions: Array, team: int) -> Array:
	var visited = {}
	var queue = start_positions.duplicate()
	
	for pos in start_positions:
		visited[pos] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var neighbors = get_neighbors(current)
		
		for neighbor in neighbors:
			if visited.has(neighbor):
				continue
			if not territory_map.has(neighbor):
				continue
			if territory_map[neighbor] != team:
				continue
			
			visited[neighbor] = true
			queue.append(neighbor)
	
	return visited.keys()

func convert_to_mercenary(hex_coords: Vector2i):
	"""Przeksztalca odciete terytoria - TYLKO jednostki staja sie bandytami"""
	var original_team = territory_map.get(hex_coords, 0)
	if original_team <= 0:
		return
	
	# Zbierz wszystkie odciete pola tego samego terytorium
	var isolated_territories = get_isolated_region(hex_coords, original_team)
	
	print("=== KONWERSJA NA BANDYTOW ===")
	print("Odciete pola: ", isolated_territories.size())
	
	# Znajdz wszystkie jednostki na odcietym terenie
	var units_positions = []
	for coords in isolated_territories:
		if knight_map.has(coords):
			units_positions.append(coords)
		elif farmer_map.has(coords):
			units_positions.append(coords)
		elif spearman_map.has(coords):  
			units_positions.append(coords)
		elif cavalry_map.has(coords):  
			units_positions.append(coords)
	
	print("Jednostek do konwersji: ", units_positions.size())
	
	# Jesli nie ma jednostek - pola POZOSTAJA u wlasciciela (odciete)
	if units_positions.is_empty():
		print("Brak jednostek - pola pozostaja u wlasciciela (odciete od zamku)")
		return
	
	# Przeksztalc jednostki w farmerow bandytow
	for coords in units_positions:
		if knight_map.has(coords):
			remove_knight_at(coords)
			place_farmer_at(coords, -1)
		elif spearman_map.has(coords):
			remove_spearman_at(coords)
			place_farmer_at(coords, -1)
		elif cavalry_map.has(coords):
			remove_cavalry_at(coords)
			place_farmer_at(coords, -1)
		elif farmer_map.has(coords):
			var farmer = farmer_map[coords]
			farmer.team = -1
		
		# TYLKO pola z jednostkami staja sie bandyckie
		territory_map[coords] = -1
		update_hex_color(coords)
	
	# Usun walle w CALYM regionie (zeby nie bylo problemow)
	for coords in isolated_territories:
		for edge_index in range(6):
			var edge_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
			if wall_map.has(edge_key):
				wall_map.erase(edge_key)
				
				if has_meta("wall_lines"):
					var wall_lines = get_meta("wall_lines")
					if wall_lines.has(edge_key):
						wall_lines[edge_key].queue_free()
						wall_lines.erase(edge_key)
	
	# Postaw oboz bandytow
	var camp_placed = place_bandit_camp_near_units(units_positions, units_positions)
	
	if not camp_placed:
		print("UWAGA: Nie znaleziono miejsca na oboz bandytow!")
	
	print("=== KONIEC KONWERSJI ===")
	print("Bandytow: ", units_positions.size(), " | Pola wlasciciela (odciete): ", isolated_territories.size() - units_positions.size())
	
func place_bandit_camp_near_units(units_positions: Array, available_territories: Array) -> bool:
	"""Stawia oboz bandytow na wolnym polu obok jednostek"""
	
	var adjacent_hexes = []
	for unit_pos in units_positions:
		var neighbors = get_neighbors(unit_pos)
		for neighbor in neighbors:
			if neighbor not in available_territories:
				continue
			var hex = get_hex_at(neighbor)
			if not hex or hex.occupied_object != null:
				continue
			if neighbor not in adjacent_hexes:
				adjacent_hexes.append(neighbor)
	
	print("Dostepnych pol na oboz w regionie: ", adjacent_hexes.size())
	
	# Jesli nie ma miejsca w available_territories, szukaj neutralnych pol
	if adjacent_hexes.is_empty():
		print("Brak miejsca w regionie - szukam neutralnych pol...")
		for unit_pos in units_positions:
			var neighbors = get_neighbors(unit_pos)
			for neighbor in neighbors:
				if not hex_map.has(neighbor):
					continue
				var hex = get_hex_at(neighbor)
				if not hex or hex.occupied_object != null:
					continue
				# Neutralne pole (bez wlasciciela)
				if not territory_map.has(neighbor):
					adjacent_hexes.append(neighbor)
					break
			if not adjacent_hexes.is_empty():
				break
	
	if adjacent_hexes.is_empty():
		# Jesli nadal brak, znajdz DOWOLNE wolne pole w regionie
		for coords in available_territories:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				adjacent_hexes.append(coords)
				break
	
	if adjacent_hexes.is_empty():
		print("BLAD: Nie znaleziono miejsca na oboz bandytow!")
		return false
	
	var camp_pos = adjacent_hexes[0]
	var castle = CASTLE_SCENE.instantiate()
	castle.team = -1
	castle.hex_position = camp_pos
	castle.position = get_hex_at(camp_pos).position
	add_child(castle)
	
	castle_map[camp_pos] = castle
	get_hex_at(camp_pos).place_object(castle)
	
	territory_map[camp_pos] = -2  # Oznacz jako oboz
	update_hex_color(camp_pos)
	
	print("Utworzono oboz bandytow na: ", camp_pos)
	return true

func get_isolated_region(start_pos: Vector2i, team: int) -> Array:
	"""Zwraca wszystkie pola polaczonej odcietej enklawy"""
	var region = []
	var visited = {}
	var queue = [start_pos]
	visited[start_pos] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		region.append(current)
		
		var neighbors = get_neighbors(current)
		for neighbor in neighbors:
			if visited.has(neighbor):
				continue
			if not territory_map.has(neighbor):
				continue
			if territory_map[neighbor] != team:
				continue
			
			visited[neighbor] = true
			queue.append(neighbor)
	
	return region

# --- MURY ---
func has_wall_between(hex1: Vector2i, hex2: Vector2i, check_team: int = -999) -> bool:
	"""Sprawdza czy KTÓRYKOLWIEK z hexów ma wall na tej krawędzi"""
	
	# Znajdz numer krawedzi dla hex1 prowadzacej do hex2
	var neighbors1 = get_neighbors(hex1)
	var edge_index1 = neighbors1.find(hex2)
	
	if edge_index1 != -1:
		var key1 = "%d,%d-edge%d" % [hex1.x, hex1.y, edge_index1]
		if wall_map.has(key1):
			if check_team == -999:
				return true
			var wall_data = wall_map[key1]
			if wall_data.get("team", -1) == check_team:
				return true
	
	# Sprawdz też hex2
	var neighbors2 = get_neighbors(hex2)
	var edge_index2 = neighbors2.find(hex1)
	
	if edge_index2 != -1:
		var key2 = "%d,%d-edge%d" % [hex2.x, hex2.y, edge_index2]
		if wall_map.has(key2):
			if check_team == -999:
				return true
			var wall_data = wall_map[key2]
			if wall_data.get("team", -1) == check_team:
				return true
	
	return false

func add_wall(hex1: Vector2i, hex2: Vector2i, wall_team: int = 0):
	"""Dodaje wall - używa nowego systemu per-hex"""
	if wall_team == 0:
		wall_team = territory_map.get(hex1, 0)
	
	# Sprawdz czy juz jest
	if has_wall_between(hex1, hex2):
		print("Wall juz istnieje!")
		return
	
	# Stworz wall dla hex1
	var neighbors = get_neighbors(hex1)
	var edge_index = neighbors.find(hex2)
	
	if edge_index == -1:
		print("BLAD: hex2 nie jest sasiadem hex1!")
		return
	
	# Oblicz pozycje krawedzi
	var center = hex_to_pixel(hex1)
	var hex_radius = hex_width * 0.45
	var angles = [30, 90, 150, 210, 270, 330]
	var vertices = []
	
	for angle in angles:
		var rad = deg_to_rad(angle)
		var x = center.x + hex_radius * cos(rad)
		var y = center.y + hex_radius * sin(rad)
		vertices.append(Vector2(x, y))
	
	var start = vertices[edge_index]
	var end = vertices[(edge_index + 1) % vertices.size()]
	
	# Dodaj wall
	var edge_key = "%d,%d-edge%d" % [hex1.x, hex1.y, edge_index]
	wall_map[edge_key] = {"team": wall_team, "hex": hex1, "edge": edge_index}
	
	var wall_line = WallLine.new()
	wall_line.z_index = 10
	wall_line.setup(start, end, Color.WHITE, 2.5, false)
	add_child(wall_line)
	
	if not has_meta("wall_lines"):
		set_meta("wall_lines", {})
	var wall_lines = get_meta("wall_lines")
	wall_lines[edge_key] = wall_line

# --- SASIEDZI ---
func get_neighbors(hex_coords: Vector2i) -> Array[Vector2i]:
	var q = hex_coords.x
	var r = hex_coords.y
	var neighbors: Array[Vector2i] = []
	
	var offset_coords = [
		[Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), 
		 Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)],
		[Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
		 Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	]
	
	var offsets = offset_coords[r % 2]
	for offset in offsets:
		neighbors.append(hex_coords + offset)
	
	return neighbors

func get_hex_distance(from: Vector2i, to: Vector2i) -> int:
	var from_cube = offset_to_cube(from)
	var to_cube = offset_to_cube(to)
	return (abs(from_cube.x - to_cube.x) + abs(from_cube.y - to_cube.y) + abs(from_cube.z - to_cube.z)) / 2

func offset_to_cube(hex: Vector2i) -> Vector3i:
	var q = hex.x
	var r = hex.y
	var x = q - (r - (r % 2)) / 2
	var z = r
	var y = -x - z
	return Vector3i(x, y, z)

# --- PODSWIETLANIE ---
func highlight_unit_moves(unit_pos: Vector2i, team: int):
	clear_highlights()
	
	if not selected_unit:
		return
	
	if selected_unit is Cavalry:
		highlight_cavalry_moves(unit_pos, team)
	elif selected_unit is Knight:
		highlight_knight_moves(unit_pos, team)
	elif selected_unit is Spearman:
		highlight_spearman_moves(unit_pos, team)
	elif selected_unit is Farmer:
		highlight_farmer_moves(unit_pos, team)
		
func highlight_cavalry_moves(cavalry_pos: Vector2i, team: int):
	"""Cavalry: jak knight ale może atakować WSZYSTKIE jednostki (ignoruje mury)"""
	
	# Własne terytoria
	for coords in territory_map:
		if territory_map[coords] == team and coords != cavalry_pos:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				var lightened_color = TEAM_COLORS[team].lightened(0.3)
				hex.highlight(lightened_color)
				highlighted_hexes.append(hex)
	
	# Znajdź sąsiadów
	var neighbors_of_team = []
	for coords in territory_map:
		if territory_map[coords] == team:
			var neighbors = get_neighbors(coords)
			for neighbor in neighbors:
				if neighbor not in neighbors_of_team:
					neighbors_of_team.append(neighbor)
	
	# Obozy bandytów
	for coords in neighbors_of_team:
		if castle_map.has(coords):
			var castle = castle_map[coords]
			if castle.team == -1:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(BANDIT_CAMP_COLOR.lightened(0.4))
					highlighted_hexes.append(hex)
		
		# Jednostki bandytów
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object != null:
			var unit = hex.occupied_object
			if (unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry) and unit.team == -1:
				hex.highlight(BANDIT_COLOR.lightened(0.5))
				highlighted_hexes.append(hex)
	
	# Granica - WSZYSTKIE wrogie jednostki (IGNORUJE MURY!)
	var border_hexes = get_territory_border(team)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		# Cavalry może atakować WSZYSTKIE jednostki (nawet w murach!)
		if hex.occupied_object != null:
			var unit = hex.occupied_object
			if unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry:
				if unit.team != team and unit.team > 0 and unit.team <= 4:
					if unit is Cavalry:
						var neighbors = get_neighbors(coords)
						var wall_count = 0
						for neighbor in neighbors:
							if has_wall_between(coords, neighbor):
								wall_count += 1
								
						if wall_count >= 6:
							continue
					highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
					hex.highlight(highlight_color)
					highlighted_hexes.append(hex)
					continue
		
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
		
func highlight_spearman_moves(spearman_pos: Vector2i, team: int):
	"""Spearman: jak farmer (swobodnie po swoim terenie + granica)"""
	
	# Własne terytoria
	for coords in territory_map:
		if territory_map[coords] == team and coords != spearman_pos:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				var lightened_color = TEAM_COLORS[team].lightened(0.3)
				hex.highlight(lightened_color)
				highlighted_hexes.append(hex)
	
	# Granica
	var border_hexes = get_territory_border(team)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		# Sprawdź czy jest wrogie jednostki
		var can_reach = false
		var neighbors = get_neighbors(coords)
		
		for neighbor in neighbors:
			if territory_map.get(neighbor, 0) == team:
				var enemy_has_wall = false
				var enemy_neighbors = get_neighbors(coords)
				var edge_index = enemy_neighbors.find(neighbor)
				
				if edge_index != -1:
					var enemy_wall_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
					if wall_map.has(enemy_wall_key):
						var wall_data = wall_map[enemy_wall_key]
						if wall_data.get("team", 0) != team:
							enemy_has_wall = true
				
				if not enemy_has_wall:
					can_reach = true
					break
		
		if not can_reach:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		# Podświetl wrogie jednostki (w tym bandytów!)
		if hex.occupied_object != null:
			var unit = hex.occupied_object
			
			# NOWE: Bandyci (team -1)
			if (unit is Farmer or unit is Knight) and unit.team == -1:
				# Sprawdź mury
				var wall_count = 0
				for n in neighbors:
					if has_wall_between(coords, n):
						wall_count += 1
				
				if wall_count < 6:  # Nie jest w pełnym murze
					highlight_color = BANDIT_COLOR.lightened(0.5)
					hex.highlight(highlight_color)
					highlighted_hexes.append(hex)
				continue
			
			# Farmerzy (team 1-4)
			if unit is Farmer and unit.team != team and unit.team > 0 and unit.team <= 4:
				# Sprawdź mury
				var wall_count = 0
				for n in neighbors:
					if has_wall_between(coords, n):
						wall_count += 1
				
				if wall_count < 6:  # Nie jest w pełnym murze
					highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
					hex.highlight(highlight_color)
					highlighted_hexes.append(hex)
				continue
			
			# NOWE: Inni spearmani (team 1-4)
			if unit is Spearman and unit.team != team and unit.team > 0 and unit.team <= 4:
				# Sprawdź mury
				if can_attack_through_walls(selected_unit, coords):
					highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
					hex.highlight(highlight_color)
					highlighted_hexes.append(hex)
				continue
				
		if castle_map.has(coords):
			var castle = castle_map[coords]
			if castle.team == -1:
				hex.highlight(BANDIT_CAMP_COLOR.lightened(0.4))
				highlighted_hexes.append(hex)
				continue
			elif castle.team != team and castle.team > 0 and castle.team <= 4:
				hex.highlight(TEAM_COLORS[int(castle.team)].lightened(0.3))
				highlighted_hexes.append(hex)
				continue
		
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		if hex.occupied_object == null:
			hex.highlight(highlight_color)
			highlighted_hexes.append(hex)
			
	for coords in spearman_map:
		if coords == spearman_pos:
			continue
		var other_spearman = spearman_map[coords]
		if other_spearman.team == team:
			var hex = get_hex_at(coords)
			if hex:
				hex.highlight(Color("#10B981"))
				highlighted_hexes.append(hex)

func highlight_knight_moves(knight_pos: Vector2i, team: int):
	"""Rycerz: wlasne terytoria (rozjasnione) + granica (z jednostkami wroga)"""
	
	# Wlasne terytoria - rozjasniony kolor druzyny
	for coords in territory_map:
		if territory_map[coords] == team and coords != knight_pos:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				var lightened_color = TEAM_COLORS[team].lightened(0.3)
				hex.highlight(lightened_color)
				highlighted_hexes.append(hex)
				
	var neighbors_of_team = []
	for coords in territory_map:
		if territory_map[coords] == team:
			var neighbors = get_neighbors(coords)
			for neighbor in neighbors:
				if neighbor not in neighbors_of_team:
					neighbors_of_team.append(neighbor)
	
	# Sprawdz czy sa obozy bandytow w sasiedztwie
	for coords in neighbors_of_team:
		if castle_map.has(coords):
			var castle = castle_map[coords]
			if castle.team == -1:  # Oboz bandytow
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(BANDIT_CAMP_COLOR.lightened(0.4))
					highlighted_hexes.append(hex)
		
		# NOWE: Podswietl takze jednostki bandytow (farmerow i knightow team -1)
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object != null:
			var unit = hex.occupied_object
			if (unit is Knight or unit is Farmer) and unit.team == -1:
				# Podswietl jednostke bandyty pomaranczowym kolorem
				hex.highlight(BANDIT_COLOR.lightened(0.5))
				highlighted_hexes.append(hex)
	
	# Granica - rozne kolory + jednostki wroga
	var border_hexes = get_territory_border(team)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		# NAPRAW: Sprawdz czy owner jest poprawny (1-4)
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		# Knight moze atakowac wrogie jednostki
		if hex.occupied_object != null:
			var unit = hex.occupied_object
			if unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry:
				if unit.team != team and unit.team > 0 and unit.team <= 4:
					if unit is Cavalry:
						continue
					# DODAJ: Sprawdź czy może zaatakować przez mury
					if can_attack_through_walls(selected_unit, coords):
						highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
						hex.highlight(highlight_color)
						highlighted_hexes.append(hex)
					else:
						continue
		
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
		
	for coords in knight_map:
		if coords == knight_pos:
			continue
		var other_knight = knight_map[coords]
		if other_knight.team == team:
			var hex = get_hex_at(coords)
			if hex:
				hex.highlight(Color("#10B981"))  # Zielony
				highlighted_hexes.append(hex)

func highlight_farmer_moves(farmer_pos: Vector2i, team: int):
	"""Farmer: swobodnie po swoim terenie (ignoruje swoje mury) + granica (blokowana przez wrogie mury)"""
	
	if team == BANDIT_TEAM or team == 5:
		# Terytoria bandytów (-1 i -2)
		for coords in territory_map:
			var owner = territory_map[coords]
			if (owner == -1 or owner == -2) and coords != farmer_pos:
				var hex = get_hex_at(coords)
				if hex and hex.occupied_object == null:
					hex.highlight(BANDIT_COLOR.lightened(0.3))
					highlighted_hexes.append(hex)
		
		# Granica bandytów
		var border_hexes = get_bandit_border()
		for coords in border_hexes:
			var hex = get_hex_at(coords)
			if not hex or hex.occupied_object != null:
				continue
			
			var owner = territory_map.get(coords, 0)
			var highlight_color = HIGHLIGHT_COLOR_CAPTURE
			
			if owner > 0 and owner <= 4:
				highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
			
			hex.highlight(highlight_color)
			highlighted_hexes.append(hex)
		
		return
	
	# WLASNE TERYTORIA - farmer moze sie swobodnie poruszac (SWOJE mury NIE blokuja)
	for coords in territory_map:
		if territory_map[coords] == team and coords != farmer_pos:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				var lightened_color = TEAM_COLORS[team].lightened(0.3)
				hex.highlight(lightened_color)
				highlighted_hexes.append(hex)
				
	for coords in farmer_map:
		if coords == farmer_pos:
			continue
		var other_farmer = farmer_map[coords]
		if other_farmer.team == team:
			var hex = get_hex_at(coords)
			if hex:
				hex.highlight(Color("#10B981"))
				highlighted_hexes.append(hex)
	
	# GRANICA - pola obok swojego terytorium
	var border_hexes = get_territory_border(team)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex or hex.occupied_object != null:
			continue
		
		# Sprawdz czy JAKIEKOLWIEK pole naszego teamu sasiada z tym polem BEZ WROGIEGO MURU
		var can_reach = false
		var neighbors = get_neighbors(coords)
		
		for neighbor in neighbors:
			# Jesli sasiad jest naszym terytorium
			if territory_map.get(neighbor, 0) == team:
				# Sprawdz czy na granicy jest WROGI mur (coords to wrogie/neutralne pole)
				var enemy_has_wall = false
				
				# Sprawdz czy WROGIE pole (coords) ma mur w kierunku naszego pola (neighbor)
				var enemy_neighbors = get_neighbors(coords)
				var edge_index = enemy_neighbors.find(neighbor)
				
				if edge_index != -1:
					var enemy_wall_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
					if wall_map.has(enemy_wall_key):
						var wall_data = wall_map[enemy_wall_key]
						# Jesli wrogie pole ma mur i NIE jest nasz - blokuj
						if wall_data.get("team", 0) != team:
							enemy_has_wall = true
				
				# Jesli NIE MA wrogiego muru - mozemy przejsc
				if not enemy_has_wall:
					can_reach = true
					break
		
		if not can_reach:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
		
func get_bandit_border() -> Array[Vector2i]:
	"""Zwraca granicę terytoriów bandytów"""
	var border: Array[Vector2i] = []
	var checked = {}
	
	for coords in territory_map:
		var owner = territory_map[coords]
		if owner != -1 and owner != -2:
			continue
		
		var neighbors = get_neighbors(coords)
		for neighbor in neighbors:
			if checked.has(neighbor):
				continue
			
			checked[neighbor] = true
			
			if not hex_map.has(neighbor):
				continue
			
			var neighbor_owner = territory_map.get(neighbor, 0)
			if neighbor_owner == -1 or neighbor_owner == -2:
				continue
			
			border.append(neighbor)
	
	return border

func get_territory_border(team: int) -> Array[Vector2i]:
	"""Zwraca wszystkie pola wokol terytorium druzyny (promien 1) - wrogie i neutralne"""
	var border: Array[Vector2i] = []
	var checked = {}
	
	# Dla kazdego pola druzyny sprawdz sasiadow
	for coords in territory_map:
		if territory_map[coords] != team:
			continue
		
		var neighbors = get_neighbors(coords)
		for neighbor in neighbors:
			if checked.has(neighbor):
				continue
			
			checked[neighbor] = true
			
			# Pole musi istniec
			if not hex_map.has(neighbor):
				continue
			
			# Pole nie moze nalezec do tej druzyny
			var owner = territory_map.get(neighbor, 0)
			if owner == team:
				continue
			
			# ZMIANA: Dodaj pole niezaleznie od tego czy jest tam jednostka
			# (filtrowanie jednostek robi sie w highlight_farmer_moves)
			border.append(neighbor)
	
	return border

func clear_highlights():
	for hex in highlighted_hexes:
		if is_instance_valid(hex):
			hex.unhighlight()
	highlighted_hexes.clear()
	
	update_ui()

# --- KLIKNIECIA ---
func on_hex_clicked(hex: Hex):
	if not game_mode:
		return
	
	var clicked_pos = hex.grid_position
	
	if selected_unit and hex not in highlighted_hexes:
		print("Pole poza zasięgiem!")
		return
	
	if hex.occupied_object is Farmer and selected_unit is Cavalry:
		var farmer = hex.occupied_object as Farmer
		if farmer.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_cavalry(from, clicked_pos)
			return
	
	if hex.occupied_object is Spearman and selected_unit is Cavalry:
		var spearman = hex.occupied_object as Spearman
		if spearman.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_cavalry(from, clicked_pos)
			return
	
	if hex.occupied_object is Knight and selected_unit is Cavalry:
		var knight = hex.occupied_object as Knight
		if knight.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_cavalry(from, clicked_pos)
			return
	
	if hex.occupied_object is Cavalry and selected_unit is Cavalry:
		var cavalry = hex.occupied_object as Cavalry
		if cavalry.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_cavalry(from, clicked_pos)
			return
	
	if hex.occupied_object is Castle and selected_unit is Cavalry:
		var castle = hex.occupied_object as Castle
		if castle.team == -1:  # Obóz bandytów
			var from = selected_unit.hex_position
			move_cavalry(from, clicked_pos)
			return
	
	if hex.occupied_object is Castle and selected_unit is Knight:
		var castle = hex.occupied_object as Castle
		if castle.team != selected_unit.team:
			# Knight atakuje zamek
			var from = selected_unit.hex_position
			move_knight(from, clicked_pos)
			return
			
	if hex.occupied_object is Castle and selected_unit is Spearman:
		var castle = hex.occupied_object as Castle
		if castle.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_spearman(from, clicked_pos)
			return
			
	if hex.occupied_object is Farmer and selected_unit is Knight:
		var farmer = hex.occupied_object as Farmer
		if farmer.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_knight(from, clicked_pos)
			return
			
	if hex.occupied_object is Spearman and selected_unit is Knight:
		var spearman = hex.occupied_object as Spearman
		if spearman.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_knight(from, clicked_pos)
			return
			
	if hex.occupied_object is Knight and selected_unit is Knight:
		var knight = hex.occupied_object as Knight
		if knight.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_knight(from, clicked_pos)
			return
			
	if hex.occupied_object is Farmer and selected_unit is Spearman:
		var farmer = hex.occupied_object as Farmer
		if farmer.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_spearman(from, clicked_pos)
			return
	
	if hex.occupied_object is Spearman and selected_unit is Spearman:
		var spearman = hex.occupied_object as Spearman
		if spearman.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_spearman(from, clicked_pos)
			return

	if hex.occupied_object is Cavalry and selected_unit is Spearman:
		var cavalry = hex.occupied_object as Cavalry
		if cavalry.team != selected_unit.team:
			var from = selected_unit.hex_position
			move_spearman(from, clicked_pos)
			return
			
	if wall_placement_mode:
		handle_wall_placement(clicked_pos)
		return
	
	# Obsluga zakupu jednostek
	if buy_mode == "farmer" and hex in highlighted_hexes:
		if team_gold[current_team] >= FARMER_COST:
			place_farmer_at(clicked_pos, current_team)
			team_gold[current_team] -= FARMER_COST
			capture_territory(clicked_pos, current_team)
			buy_mode = ""
			clear_highlights()
			update_ui()
			pulse_available_units()
			print("Kupiono farmera")
		return
		
	if buy_mode == "spearman" and hex in highlighted_hexes:
		if team_gold[current_team] >= SPEARMAN_COST:
			place_spearman_at(clicked_pos, current_team)
			team_gold[current_team] -= SPEARMAN_COST
			capture_territory(clicked_pos, current_team)
			buy_mode = ""
			clear_highlights()
			update_ui()
			pulse_available_units()
			print("Kupiono spearmana")
		return
		
	if buy_mode == "cavalry" and hex in highlighted_hexes:
		if team_gold[current_team] >= CAVALRY_COST:
			place_cavalry_at(clicked_pos, current_team)
			team_gold[current_team] -= CAVALRY_COST
			capture_territory(clicked_pos, current_team)
			buy_mode = ""
			clear_highlights()
			update_ui()
			pulse_available_units()
			print("Kupiono cavalry")
		return
	
	if buy_mode == "knight" and hex in highlighted_hexes:
		if team_gold[current_team] >= 20:
			if hex.occupied_object:
				if knight_map.has(clicked_pos):
					remove_knight_at(clicked_pos)
				elif farmer_map.has(clicked_pos):
					remove_farmer_at(clicked_pos)
			
			place_knight_at(clicked_pos, current_team)
			team_gold[current_team] -= 20
			capture_territory(clicked_pos, current_team)
			buy_mode = ""
			clear_highlights()
			update_ui()
			pulse_available_units()
			print("Kupiono knighta")
		return
	
	# Tryb laczenia
	if merge_mode:
		if farmer_map.has(clicked_pos):
			var clicked_farmer = farmer_map[clicked_pos]
			if clicked_farmer.team == current_team and clicked_farmer != selected_unit:
				merge_farmers(selected_unit.hex_position, clicked_pos)
				return
		print("Wybierz farmera tej samej druzyny")
		return
	
	if hex in highlighted_hexes and selected_unit:
		var from = selected_unit.hex_position
		var to = hex.grid_position
		
		if selected_unit is Knight:
			move_knight(from, to)
		elif selected_unit is Farmer:
			move_farmer(from, to)
		elif selected_unit is Spearman:
			move_spearman(from, to)
		elif selected_unit is Cavalry:
			move_cavalry(from, to)

func on_knight_clicked(knight: Knight):
	if not game_mode:
		return
	if wall_placement_mode:
		return
	
	# === NOWE: Łączenie knightów ===
	if selected_unit and selected_unit is Knight and selected_unit != knight:
		if knight.team == selected_unit.team:
			merge_knights_to_cavalry(selected_unit.hex_position, knight.hex_position)
			return
	
	# === Reszta bez zmian ===
	if knight.team != current_team:
		return
	
	if knight in units_moved_this_turn:
		print("Ta jednostka już się ruszyła w tej turze")
		return
	
	if selected_unit == knight:
		clear_selected_unit_highlight()
		selected_unit = null
		clear_highlights()
		pulse_available_units()
		update_ui()
		return
	
	if selected_unit:
		clear_selected_unit_highlight()
	
	# DODAJ TUTAJ: Zatrzymaj pulse tweeny PRZED highlight
	clear_unit_pulses()
	
	clear_highlights()
	selected_unit = knight
	if knight.has_method("set_selected"):
		knight.set_selected(true)
	
	set_selected_unit_highlight(knight)
	
	highlight_knight_moves(knight.hex_position, knight.team)
	
	update_ui()

func on_farmer_clicked(farmer):
	if not game_mode:
		return
	if wall_placement_mode:
		return
	
	# === NOWE: Łączenie farmerów ===
	if selected_unit and selected_unit is Farmer and selected_unit != farmer:
		if farmer.team == selected_unit.team:
			merge_farmers_to_spearman(selected_unit.hex_position, farmer.hex_position)
			return
	
	# === Reszta bez zmian ===
	if farmer.team == BANDIT_TEAM:
		if current_team != 5:
			return
	else:
		if farmer.team != current_team:
			return
	
	if farmer in units_moved_this_turn:
		print("Ta jednostka już się ruszyła w tej turze")
		return
	
	if selected_unit == farmer:
		clear_selected_unit_highlight()
		selected_unit = null
		clear_highlights()
		pulse_available_units()
		update_ui()
		return
	
	if selected_unit:
		clear_selected_unit_highlight()
	
	# DODAJ TUTAJ: Zatrzymaj pulse tweeny PRZED highlight
	clear_unit_pulses()
	
	clear_highlights()
	selected_unit = farmer
	if farmer.has_method("set_selected"):
		farmer.set_selected(true)
	
	set_selected_unit_highlight(farmer)
	
	if farmer.team == BANDIT_TEAM:
		highlight_unit_moves(farmer.hex_position, BANDIT_TEAM)
	else:
		highlight_unit_moves(farmer.hex_position, farmer.team)
	
	update_ui()

func on_castle_clicked(castle: Castle):
	if not game_mode:
		return
	print("Zamek druzyny ", castle.team)

# --- ZAPIS/ODCZYT ---
func save_layout():
	var data = {
		"hexes": [],
		"castles": [],
		"knights": [],
		"cavalry": [],
		"spearmen": [],
		"farmers": [],
		"territories": [],
		"walls": []
	}
	
	for coords in hex_map.keys():
		data["hexes"].append({"x": coords.x, "y": coords.y})
	
	for coords in castle_map.keys():
		var castle = castle_map[coords]
		data["castles"].append({
			"x": coords.x,
			"y": coords.y,
			"team": castle.team
		})
	
	for coords in knight_map.keys():
		var knight = knight_map[coords]
		data["knights"].append({
			"x": coords.x,
			"y": coords.y,
			"team": knight.team
		})
		
	for coords in cavalry_map.keys():
		var cavalry = cavalry_map[coords]
		data["cavalry"].append({
			"x": coords.x,
			"y": coords.y,
			"team": cavalry.team
		})
		
	for coords in spearman_map.keys():
		var spearman = spearman_map[coords]
		data["spearmen"].append({
			"x": coords.x,
			"y": coords.y,
			"team": spearman.team
		})
	
	for coords in farmer_map.keys():
		var farmer = farmer_map[coords]
		data["farmers"].append({
			"x": coords.x,
			"y": coords.y,
			"team": farmer.team
		})
	
	for coords in territory_map.keys():
		data["territories"].append({
			"x": coords.x,
			"y": coords.y,
			"team": territory_map[coords]
		})
	
	for key in wall_map.keys():
		data["walls"].append(key)
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("✓ Zapisano uklad")

func save_layout_to_file(file_name: String):
	"""Saves layout to a specific file (for level editor)"""
	var data = {
		"hexes": [],
		"castles": [],
		"knights": [],
		"cavalry": [],
		"spearmen": [],
		"farmers": [],
		"territories": [],
		"walls": []
	}
	
	for coords in hex_map.keys():
		data["hexes"].append({"x": coords.x, "y": coords.y})
	
	for coords in castle_map.keys():
		var castle = castle_map[coords]
		data["castles"].append({
			"x": coords.x,
			"y": coords.y,
			"team": castle.team
		})
	
	for coords in knight_map.keys():
		var knight = knight_map[coords]
		data["knights"].append({
			"x": coords.x,
			"y": coords.y,
			"team": knight.team
		})
		
	for coords in cavalry_map.keys():
		var cavalry = cavalry_map[coords]
		data["cavalry"].append({
			"x": coords.x,
			"y": coords.y,
			"team": cavalry.team
		})
		
	for coords in spearman_map.keys():
		var spearman = spearman_map[coords]
		data["spearmen"].append({
			"x": coords.x,
			"y": coords.y,
			"team": spearman.team
		})
	
	for coords in farmer_map.keys():
		var farmer = farmer_map[coords]
		data["farmers"].append({
			"x": coords.x,
			"y": coords.y,
			"team": farmer.team
		})
	
	for coords in territory_map.keys():
		data["territories"].append({
			"x": coords.x,
			"y": coords.y,
			"team": territory_map[coords]
		})
	
	for key in wall_map.keys():
		data["walls"].append(key)
	
	var full_path = "res://levels/" + file_name
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("✓ Zapisano uklad do: ", full_path)
	else:
		print("✗ Błąd zapisu do: ", full_path)

func load_layout() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_text) != OK:
		return false
	
	var data = json.data
	clear_grid()
	
	for hex_data in data["hexes"]:
		var coords = Vector2i(hex_data["x"], hex_data["y"])
		add_hex_at(coords)
	
	if data.has("territories"):
		for territory_data in data["territories"]:
			var coords = Vector2i(territory_data["x"], territory_data["y"])
			territory_map[coords] = territory_data["team"]
			update_hex_color(coords)
	
	for castle_data in data["castles"]:
		var coords = Vector2i(castle_data["x"], castle_data["y"])
		place_castle_at(coords, castle_data["team"])
	
	if data.has("knights"):
		for knight_data in data["knights"]:
			var coords = Vector2i(knight_data["x"], knight_data["y"])
			place_knight_at(coords, knight_data["team"])
			
	if data.has("spearmen"):
		for spearman_data in data["spearmen"]:
			var coords = Vector2i(spearman_data["x"], spearman_data["y"])
			place_spearman_at(coords, spearman_data["team"])
			
	if data.has("cavalry"):
		for cavalry_data in data["cavalry"]:
			var coords = Vector2i(cavalry_data["x"], cavalry_data["y"])
			place_cavalry_at(coords, cavalry_data["team"])
	
	if data.has("farmers"):
		for farmer_data in data["farmers"]:
			var coords = Vector2i(farmer_data["x"], farmer_data["y"])
			place_farmer_at(coords, farmer_data["team"])
	
	if data.has("walls"):
		for wall_key in data["walls"]:
			wall_map[wall_key] = true
			# Odtworz linie z klucza
			var parts = wall_key.split("-")
			if parts.size() == 2:
				var from_coords = parts[0].split(",")
				var to_coords = parts[1].split(",")
				if from_coords.size() == 2 and to_coords.size() == 2:
					var hex1 = Vector2i(int(from_coords[0]), int(from_coords[1]))
					var hex2 = Vector2i(int(to_coords[0]), int(to_coords[1]))
	
	current_round = 1
	update_ui()
	print("✓ Wczytano uklad")
	if turn_history:
		turn_history.reset_rewinds()
	return true

func load_layout_from_file(file_name: String) -> bool:
	"""Loads layout from a specific file (for level loading)"""
	var full_path = "res://levels/" + file_name
	
	var file = FileAccess.open(full_path, FileAccess.READ)
	if not file:
		print("✗ Nie można otworzyć pliku: ", full_path)
		print("Błąd FileAccess: ", FileAccess.get_open_error())
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("✗ Błąd parsowania JSON: ", full_path)
		return false
	
	var data = json.data
	clear_grid()
	
	# Load hexes
	for hex_data in data["hexes"]:
		var coords = Vector2i(hex_data["x"], hex_data["y"])
		add_hex_at(coords)
	
	# Load territories
	if data.has("territories"):
		for territory_data in data["territories"]:
			var coords = Vector2i(territory_data["x"], territory_data["y"])
			territory_map[coords] = territory_data["team"]
			update_hex_color(coords)
	
	# Load castles
	for castle_data in data["castles"]:
		var coords = Vector2i(castle_data["x"], castle_data["y"])
		place_castle_at(coords, castle_data["team"])
	
	# Load knights
	if data.has("knights"):
		for knight_data in data["knights"]:
			var coords = Vector2i(knight_data["x"], knight_data["y"])
			place_knight_at(coords, knight_data["team"])
			
	# Load spearmen
	if data.has("spearmen"):
		for spearman_data in data["spearmen"]:
			var coords = Vector2i(spearman_data["x"], spearman_data["y"])
			place_spearman_at(coords, spearman_data["team"])
			
	# Load cavalry
	if data.has("cavalry"):
		for cavalry_data in data["cavalry"]:
			var coords = Vector2i(cavalry_data["x"], cavalry_data["y"])
			place_cavalry_at(coords, cavalry_data["team"])
	
	# Load farmers
	if data.has("farmers"):
		for farmer_data in data["farmers"]:
			var coords = Vector2i(farmer_data["x"], farmer_data["y"])
			place_farmer_at(coords, farmer_data["team"])
	
	# Load walls
	if data.has("walls"):
		for wall_key in data["walls"]:
			wall_map[wall_key] = true
	
	# Store the current level file
	current_level_file = file_name
	set_meta("current_level_file", file_name)
	
	# Reset game state
	current_round = 1
	units_moved_this_turn.clear()
	cavalry_moves_this_turn.clear()
	
	update_ui()
	print("✓ Wczytano poziom z: ", full_path)
	
	if turn_history:
		turn_history.reset_rewinds()
		turn_history.save_turn_snapshot(self)
	
	return true

func _on_buy_farmer():
	if team_gold[current_team] < FARMER_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null

	buy_mode = "farmer"
	clear_highlights()
	
	# Pobierz pola POLACZONE z zamkiem
	var connected = get_connected_territories(current_team)
	
	# Podswietl TYLKO polaczone pola (puste)
	for coords in connected:
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[current_team].lightened(0.3))
			highlighted_hexes.append(hex)
	
	# Podswietl SASIADOW polaczenych pol (granica)
	var border = get_border_of_connected_territories(current_team, connected)
	for coords in border:
		var hex = get_hex_at(coords)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE  # Pomaranczowy dla neutralnych
		
		# Jesli wrogie pole - uzywamy koloru wroga (rozjasnionego)
		if owner > 0 and owner <= 4 and owner != current_team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
	
	print("Tryb zakupu: Farmer - kliknij pole")
	
func _on_buy_cavalry():
	if team_gold[current_team] < CAVALRY_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "cavalry"
	clear_highlights()
	
	var connected = get_connected_territories(current_team)
	
	for coords in connected:
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[current_team].lightened(0.3))
			highlighted_hexes.append(hex)
	
	var border = get_border_of_connected_territories(current_team, connected)
	for coords in border:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		if owner > 0 and owner <= 4 and owner != current_team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		# Cavalry może zastąpić DOWOLNĄ jednostkę
		if hex.occupied_object == null:
			hex.highlight(highlight_color)
			highlighted_hexes.append(hex)
		elif hex.occupied_object is Knight or hex.occupied_object is Farmer or hex.occupied_object is Spearman or hex.occupied_object is Cavalry:
			var unit = hex.occupied_object
			if unit.team != current_team and unit.team > 0 and unit.team <= 4:
				hex.highlight(TEAM_COLORS[int(unit.team)].lightened(0.3))
				highlighted_hexes.append(hex)
	
	print("Tryb zakupu: Cavalry - kliknij pole")
	
func _on_buy_spearman():
	if team_gold[current_team] < SPEARMAN_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "spearman"
	clear_highlights()
	
	var connected = get_connected_territories(current_team)
	
	for coords in connected:
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[current_team].lightened(0.3))
			highlighted_hexes.append(hex)
	
	var border = get_border_of_connected_territories(current_team, connected)
	for coords in border:
		var hex = get_hex_at(coords)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		
		if owner > 0 and owner <= 4 and owner != current_team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
	
	print("Tryb zakupu: Spearman - kliknij pole")

func _on_buy_knight():
	if team_gold[current_team] < 20:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "knight"
	clear_highlights()
	
	# Pobierz pola POLACZONE z zamkiem
	var connected = get_connected_territories(current_team)
	
	# Podswietl TYLKO polaczone pola (puste)
	for coords in connected:
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[current_team].lightened(0.3))
			highlighted_hexes.append(hex)
	
	# Podswietl SASIADOW polaczenych pol
	var border = get_border_of_connected_territories(current_team, connected)
	for coords in border:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		var owner = territory_map.get(coords, 0)
		
		# Knight moze na puste pole LUB na wrogie jednostki
		if hex.occupied_object == null:
			# Puste pole
			var highlight_color = HIGHLIGHT_COLOR_CAPTURE  # Pomaranczowy dla neutralnych
			
			# Jesli wrogie terytorium - kolor wroga
			if owner > 0 and owner <= 4 and owner != current_team:
				highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
			
			hex.highlight(highlight_color)
			highlighted_hexes.append(hex)
		elif hex.occupied_object is Knight or hex.occupied_object is Farmer:
			# Wroga jednostka - kolor jej druzyny
			var unit = hex.occupied_object
			if unit.team != current_team and unit.team > 0 and unit.team <= 4:
				hex.highlight(TEAM_COLORS[int(unit.team)].lightened(0.3))
				highlighted_hexes.append(hex)
	
	print("Tryb zakupu: Knight - kliknij pole")

func _on_buy_wall():
	print("=== _on_buy_wall wywolane ===")
	print("wall_placement_mode przed: ", wall_placement_mode)
	
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	if wall_placement_mode:
		if wall_hexes_selected.size() > 0:
			var cost = wall_hexes_selected.size() * WALL_COST_PER_HEX
			if team_gold[current_team] >= cost:
				create_walls_between_selected()
				team_gold[current_team] -= cost
				print("Kupiono sciany za: ", cost, " zlota")
			else:
				print("Nie stac cie! Koszt: ", cost, ", masz: ", team_gold[current_team])
		
		wall_placement_mode = false
		
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		
		if ui_manager:
			ui_manager.reset_wall_button()
		
		clear_highlights()
		update_ui()
		pulse_available_units()
		print("Zakonczono stawianie scian")
		return
	
	if team_gold[current_team] < WALL_COST_PER_HEX:
		print("Nie stac na sciany")
		return
	
	wall_placement_mode = true
	wall_hexes_selected.clear()
	clear_highlights()
	
	if ui_manager:
		ui_manager.set_wall_button_active(true)
	
	print("wall_placement_mode po aktywacji: ", wall_placement_mode)
	
	var connected = get_connected_territories(current_team)
	
	for coords in connected:
		var hex = get_hex_at(coords)
		if hex:
			hex.highlight(TEAM_COLORS[current_team].lightened(0.3))
			highlighted_hexes.append(hex)
	
	print("Tryb zakupu: Wall - klikaj pola, potem kliknij przycisk ponownie aby kupic")
	
func get_border_of_connected_territories(team: int, connected_territories: Array) -> Array[Vector2i]:
	"""Zwraca granice TYLKO dla polaczenych terytoriow (promien 1 wokol nich)"""
	var border: Array[Vector2i] = []
	var checked = {}
	
	# Dla kazdego POLACZONEGO pola sprawdz sasiadow
	for coords in connected_territories:
		var neighbors = get_neighbors(coords)
		for neighbor in neighbors:
			if checked.has(neighbor):
				continue
			
			checked[neighbor] = true
			
			# Pole musi istniec
			if not hex_map.has(neighbor):
				continue
			
			# Pole nie moze nalezec do tej druzyny (lub moze byc odciete)
			var owner = territory_map.get(neighbor, 0)
			
			# Jesli pole nalezy do nas - sprawdz czy jest POLACZONE
			if owner == team:
				# Jesli NIE jest w connected_territories - traktuj jako granice (odciete)
				if neighbor not in connected_territories:
					border.append(neighbor)
			else:
				# Wrogie lub neutralne - dodaj
				border.append(neighbor)
	
	return border
		
func pulse_available_units():
	"""Migocze jednostkami które mogą się ruszyć w tej turze"""
	clear_unit_pulses()
	
	# Lista wszystkich jednostek danego teamu
	var available_units = []
	
	if current_team == 5:
		# Bandyci
		for farmer in farmer_map.values():
			if farmer.team == BANDIT_TEAM and farmer not in units_moved_this_turn:
				available_units.append(farmer)
	else:
		# Normalni gracze
		for knight in knight_map.values():
			if knight.team == current_team and knight not in units_moved_this_turn:
				available_units.append(knight)
		for farmer in farmer_map.values():
			if farmer.team == current_team and farmer not in units_moved_this_turn:
				available_units.append(farmer)
		for spearman in spearman_map.values():
			if spearman.team == current_team and spearman not in units_moved_this_turn:
				available_units.append(spearman)
		for cavalry in cavalry_map.values():
			if cavalry.team == current_team:
				var moves_done = cavalry_moves_this_turn.get(cavalry, 0)
				if moves_done < 2:
					available_units.append(cavalry)
	
	# Dla każdej jednostki - migocz hexem pod nią
	for unit in available_units:
		# ZMIANA: Pomiń zaznaczoną jednostkę - ona ma stały jasny kolor
		if unit == selected_unit:
			continue
			
		var hex = get_hex_at(unit.hex_position)
		if not hex or not hex.sprite:
			continue
		
		# Zapisz oryginalny kolor
		hex.set_meta("original_color_pulse", hex.current_color)
		
		# Tween dla migotania
		var tween = create_tween()
		tween.set_loops()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		
		# Migocz między kolorem teamu a jaśniejszym
		var base_color = hex.current_color
		var bright_color = base_color.lightened(0.4)
		
		tween.tween_property(hex.sprite, "modulate", bright_color, 0.8)
		tween.tween_property(hex.sprite, "modulate", base_color, 0.8)
		
		unit_pulse_tweens[unit] = {"tween": tween, "hex": hex}

func clear_unit_pulses():
	"""Usuwa wszystkie migotania jednostek i przywraca kolory"""
	for data in unit_pulse_tweens.values():
		if is_instance_valid(data.tween) and data.tween.is_valid():
			data.tween.kill()
		
		# WAŻNE: Przywróć oryginalny kolor
		var hex = data.hex
		if is_instance_valid(hex) and hex.sprite and hex.has_meta("original_color_pulse"):
			var original_color = hex.get_meta("original_color_pulse")
			hex.sprite.modulate = original_color
			hex.remove_meta("original_color_pulse")
	
	unit_pulse_tweens.clear()
	
func set_selected_unit_highlight(unit):
	"""Ustawia stały jasny kolor dla zaznaczonej jednostki"""
	if not unit:
		return
		
	var hex = get_hex_at(unit.hex_position)
	if not hex or not hex.sprite:
		return
	
	# KRYTYCZNE: Zatrzymaj pulse tween jeśli istnieje
	if unit_pulse_tweens.has(unit):
		var pulse_data = unit_pulse_tweens[unit]
		if is_instance_valid(pulse_data.tween) and pulse_data.tween.is_valid():
			pulse_data.tween.kill()
		unit_pulse_tweens.erase(unit)
	
	# NOWE: Użyj funkcji hexa zamiast bezpośredniego dostępu
	hex.set_selected_state(true)
	
func clear_selected_unit_highlight():
	"""Przywraca hex zaznaczonej jednostki do normalnego stanu"""
	if not selected_unit:
		return
		
	var hex = get_hex_at(selected_unit.hex_position)
	if not hex or not hex.sprite:
		return
	
	# Przywróć oryginalny kolor
	if hex.has_meta("original_color_selected"):
		hex.sprite.modulate = hex.get_meta("original_color_selected")
		hex.remove_meta("original_color_selected")
	else:
		hex.sprite.modulate = hex.current_color
	
	# Przywróć oryginalny rozmiar
	hex.sprite.scale = hex.original_scale
	
	# Przywróć sprite jednostki do normalnego rozmiaru
	if selected_unit.has_method("set_selected"):
		selected_unit.set_selected(false)
		
func check_victory():
	"""Sprawdza czy gracz wygral (przejal wszystkie wrogie zamki)"""
	if not game_mode:
		return
	
	var enemy_castles = 0
	for coords in castle_map:
		var castle = castle_map[coords]
		if castle.team != current_team and castle.team > 0 and castle.team <= 4:
			enemy_castles += 1
	
	if enemy_castles == 0:
		# Wygrana!
		if has_meta("victory_popup"):
			var victory_popup = get_meta("victory_popup")
			# Pass the current level number (if available)
			var level_to_show = current_level_number if current_level_number > 0 else current_round
			await get_tree().create_timer(0.4).timeout
			victory_popup.show_victory(level_to_show)
			
func calculate_map_bounds() -> Rect2:
	"""Oblicza granice mapy na podstawie pozycji hexów"""
	if hex_map.is_empty():
		return Rect2(0, 0, 1000, 1000)
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for coords in hex_map.keys():
		var hex = hex_map[coords]
		var pos = hex.position
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)
	
	# Dodaj margines
	var margin_left = 300.0
	var margin_top = 400.0
	var margin_right = 150.0
	var margin_bottom = 200.0 
	
	return Rect2(min_x - margin_left, min_y - margin_top, 
				 max_x - min_x + margin_left - 2*margin_right,
				 max_y - min_y - 2*margin_bottom)
