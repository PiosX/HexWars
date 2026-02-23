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
const BANDIT_COLOR = Color("#5a5a5a")
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
var ai_controllers: Dictionary = {}
var ai_teams: Array = []
var game_over: bool = false  # Flaga zatrzymująca grę po defeat

var main_node: Node

# Ekonomia
var team_gold: Dictionary = {1: 8, 2: 8, 3: 8, 4: 8, 5: 0}
var castle_gold: Dictionary = {}  # {castle_coords: gold} - złoto przechowywane w zamku
var team_territory_count: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}

const FARMER_COST = 10
const FARMER_UPKEEP = 2
const SPEARMAN_COST = 20
const SPEARMAN_UPKEEP = 6
const KNIGHT_COST = 40
const KNIGHT_UPKEEP = 18
const CAVALRY_COST = 80
const CAVALRY_UPKEEP = 2
const GOLD_PER_TERRITORY = 1
const WALL_COST_PER_HEX = 4

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

var next_bandit_camp_id: int = 1
var bandit_camp_ownership: Dictionary = {}
var unit_to_camp: Dictionary = {}
var bandit_spawn_hexes: Dictionary = {}  # hex_coords → true, pola na których bandyta się spawnił
var bandit_camp_gold: Dictionary = {}  # {camp_id: gold} - złoto zebrane z okupacji pól
var editor_last_camp_id: int = -1  # W trybie edytora: ID ostatnio postawionego obozu bandytów

# ===== SYSTEM SOJUSZNIKÓW / WIELE ZAMKÓW =====
# castle_kingdom_id: {hex_coords: kingdom_id} - stały unikalny ID każdego zamku
var castle_kingdom_id: Dictionary = {}
# hex_kingdom_map: {hex_coords: kingdom_id} - do którego królestwa należy pole
var hex_kingdom_map: Dictionary = {}
# next_kingdom_id_per_team: {team: next_id} - licznik ID dla każdej drużyny
var next_kingdom_id_per_team: Dictionary = {1: 1, 2: 101, 3: 201, 4: 301}  # Zakresy: T1=1-100, T2=101-200, T3=201-300, T4=301-400
# Czy pokazywać etykiety numerków w edytorze
var show_kingdom_labels: bool = true
# Wybrany zamek/pole do wyświetlania ekonomii w UI (hex_coords)
var selected_kingdom_per_team: Dictionary = {1: 1, 2: 1, 3: 1, 4: 1}  # {team: kingdom_id}
# Ekonomia per królestwo (wypełniana przez recalculate_kingdoms)
var kingdom_gold: Dictionary = {}  # {kingdom_id: gold}

func _ready():
	main_node = get_node("/root/Main")
	
	var victory_popup = preload("res://victory_popup.tscn").instantiate()
	add_child(victory_popup)
	set_meta("victory_popup", victory_popup)
	
	var defeat_popup = preload("res://defeat_popup.gd").new()
	add_child(defeat_popup)
	set_meta("defeat_popup", defeat_popup)
	
	# NOWE: Połącz sygnały defeat popup
	defeat_popup.rewind_2_turns_pressed.connect(_on_defeat_rewind_2_turns)
	defeat_popup.watch_ad_pressed.connect(_on_defeat_watch_ad)
	
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
	
	set_team_ai(2, 1, 0.8)  # Czerwony = Hard, agresywny
	set_team_ai(3, 0, 0.3)  # Fioletowy = Normal, defensywny
	set_team_ai(4, 0, 0.5)  # Żółty = Normal, zbalansowany
	
	print("=== AI TEAMS INITIALIZED ===")
	for ai_team in ai_teams:
		print("Team %d: AI enabled" % ai_team)
	
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
	
	# Poczekaj jedną klatkę żeby scena była gotowa
	await get_tree().process_frame
	
	# Po załadowaniu planszy - inicjalizuj wszystko
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	# Upewnij się że kingdom IDs są unikalne per team po wczytaniu pliku
	_ensure_unique_kingdom_ids()
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	# Inicjalizuj złoto: każdy zamek dostaje 8 (team_gold = suma zamków * 8)
	team_gold = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	castle_gold = {}
	for coords in castle_map:
		var t = castle_map[coords].team
		if t > 0 and t <= 4:
			team_gold[t] = team_gold.get(t, 0) + 8
	# Redistribute shows castle_gold = team_gold / num_castles (8 per castle for equal start)
	for t in [1, 2, 3, 4]:
		_redistribute_castle_gold(t)
	_update_bandit_camp_gold_labels()
	# Inicjalizuj selected_kingdom_per_team na najniższy aktywny kid per team
	for t in [1, 2, 3, 4]:
		var min_kid = 0
		for coords in castle_kingdom_id:
			if castle_map.has(coords) and castle_map[coords].team == t:
				var k = castle_kingdom_id[coords]
				if k > 0 and (min_kid == 0 or k < min_kid):
					min_kid = k
		if min_kid > 0:
			selected_kingdom_per_team[t] = min_kid
	# Poczekaj żeby zamki były gotowe przed rysowaniem etykiet
	await get_tree().process_frame
	_update_castle_gold_labels()
	update_ui()
	
	if game_mode:
		turn_history.save_turn_snapshot(self)
		# Poczekaj jeszcze jedną klatkę żeby kolory hexów były ustawione przed pulse
		await get_tree().process_frame
		pulse_available_units()
	
	await get_tree().process_frame
	var editor_ui = get_parent().get_node_or_null("LevelEditorUI")
	if editor_ui:
		editor_ui.setup_for_hex_grid(self)
		print("✓ Panel połączony z HexGrid!")
		
	var map_gen_ui = get_parent().get_node_or_null("MapGeneratorUI")
	if map_gen_ui:
		map_gen_ui.setup_for_hex_grid(self)
		print("✓ MapGeneratorUI połączony z HexGrid!")

func _ensure_unique_kingdom_ids():
	"""Po wczytaniu pliku: upewnij się że każdy zamek ma unikalny kingdom_id w zakresie swojego teamu.
	TtTeam 1: 1-100, Team 2: 101-200, Team 3: 201-300, Team 4: 301-400"""	
	var base_ids = {1: 1, 2: 101, 3: 201, 4: 301}
	var next_ids = base_ids.duplicate()
	
	# Przenumeruj wszystkie zamki per team
	var remap: Dictionary = {}  # {old_kid: new_kid}
	for coords in castle_kingdom_id:
		if not castle_map.has(coords):
			continue
		var t = castle_map[coords].team
		if t < 1 or t > 4:
			continue
		var old_kid = castle_kingdom_id[coords]
		var new_kid = next_ids[t]
		next_ids[t] += 1
		if old_kid != new_kid:
			remap[old_kid] = new_kid
			castle_kingdom_id[coords] = new_kid
			print("Renumber: kid %d → %d (team %d)" % [old_kid, new_kid, t])
	
	# Zaktualizuj next_kingdom_id_per_team
	for t in [1, 2, 3, 4]:
		next_kingdom_id_per_team[t] = next_ids[t]
	
	# Zaktualizuj hex_kingdom_map i selected_kingdom_per_team
	if not remap.is_empty():
		for coords in hex_kingdom_map.keys():
			var kid = hex_kingdom_map[coords]
			if remap.has(kid):
				hex_kingdom_map[coords] = remap[kid]
		for t in selected_kingdom_per_team.keys():
			var kid = selected_kingdom_per_team[t]
			if remap.has(kid):
				selected_kingdom_per_team[t] = remap[kid]

func kid_to_display(kid: int) -> int:
	"""Konwertuje wewnętrzny kingdom_id na numer wyświetlany (101→1, 102→2, 201→1 itd.)"""	
	if kid <= 0:
		return 0
	if kid <= 100:
		return kid          # Team 1: 1,2,3...
	elif kid <= 200:
		return kid - 100    # Team 2: 101→1, 102→2...
	elif kid <= 300:
		return kid - 200    # Team 3: 201→1, 202→2...
	else:
		return kid - 300    # Team 4: 301→1, 302→2...

func _redistribute_castle_gold(team: int):
	"""Dzieli team_gold równo między wszystkie zamki tego teamu (dla etykiet)."""
	var team_castles_list: Array = []
	for c in castle_map:
		if castle_map[c].team == team and team > 0 and team <= 4:
			team_castles_list.append(c)
	
	if team_castles_list.is_empty():
		return
	
	var total = team_gold.get(team, 0)
	var per_castle = total / team_castles_list.size()
	var remainder = total % team_castles_list.size()
	
	for i in range(team_castles_list.size()):
		var c = team_castles_list[i]
		castle_gold[c] = per_castle + (1 if i < remainder else 0)

func _update_castle_gold_labels():
	"""Aktualizuje etykiety złota na zamkach (team 1-4)."""
	for coords in castle_map:
		var castle = castle_map[coords]
		if not is_instance_valid(castle):
			continue
		if castle.team <= 0 or castle.team > 4:
			continue
		var gold = castle_gold.get(coords, 0)
		_set_castle_gold_label(castle, gold)

func _set_castle_gold_label(castle: Node, gold: int):
	"""Ustawia/aktualizuje etykietę złota nad zamkiem gracza."""
	var label: Label = null
	for child in castle.get_children():
		if child is Label and child.has_meta("castle_gold_label"):
			label = child
			break
	
	if not label:
		label = Label.new()
		label.set_meta("castle_gold_label", true)
		label.z_index = 30
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("#FFD700"))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("shadow_as_outline", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(40, 20)
		label.position = Vector2(-20, -48)  # Nad zamkiem
		castle.add_child(label)
	
	label.text = str(gold)
	label.visible = true

func _collect_castle_gold_on_capture(castle_coords: Vector2i, new_team: int, old_team: int = -999):
	"""Przejmujący team dostaje złoto ze zdobytego zamku.
	Jeśli new_team == old_team (scalanie własnych zamków), złoto zostaje w team_gold (już wliczone)."""	
	var captured_gold = castle_gold.get(castle_coords, 0)
	if captured_gold > 0:
		if new_team != old_team:
			# Prawdziwe przejęcie - dodaj złoto do nowego właściciela
			team_gold[new_team] = team_gold.get(new_team, 0) + captured_gold
			# Odejmij od starego właściciela (złoto już nie należy do niego)
			if old_team > 0 and old_team <= 4 and old_team in team_gold:
				team_gold[old_team] = max(0, team_gold.get(old_team, 0) - captured_gold)
		# else: scalanie własnych zamków - team_gold już zawiera to złoto, tylko usuń castle_gold
		castle_gold.erase(castle_coords)
		print("Zebrano ", captured_gold, " złota z zamku (new_team=", new_team, " old_team=", old_team, ")")

func update_ui():
	if ui_manager:
		ui_manager.update_ui_data()

func calculate_income(team: int) -> int:
	if team == 5 or team == BANDIT_TEAM:
		return 0
	# Tylko pola POLACZONE z zamkiem daja przychod (bez pól zamków)
	var connected_territories = get_connected_territories(team)
	var territory_income = 0
	for coords in connected_territories:
		if not castle_map.has(coords):  # Pole zamku nie daje dochodu z terytorium
			territory_income += GOLD_PER_TERRITORY
	
	# Dodaj zloto za kazdy zamek
	var castle_income = 0
	for coords in castle_map:
		if castle_map[coords].team == team:
			castle_income += 2
	
	return territory_income + castle_income

func calculate_upkeep(team: int) -> int:
	if team == 5 or team == BANDIT_TEAM:
		return 0
	
	# Tylko jednostki na POŁĄCZONYM terytorium kosztują utrzymanie
	var connected = get_connected_territories(team)
	var connected_set = {}
	for pos in connected:
		connected_set[pos] = true
	
	var cost = 0
	for cavalry in cavalry_map.values():
		if cavalry.team == team and connected_set.has(cavalry.hex_position):
			cost += CAVALRY_UPKEEP
	for knight in knight_map.values():
		if knight.team == team and connected_set.has(knight.hex_position):
			cost += KNIGHT_UPKEEP
	for spearman in spearman_map.values():
		if spearman.team == team and connected_set.has(spearman.hex_position):
			cost += SPEARMAN_UPKEEP
	for farmer in farmer_map.values():
		if farmer.team == team and connected_set.has(farmer.hex_position):
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
			KEY_N:
				if not game_mode:
					show_kingdom_labels = not show_kingdom_labels
					_update_all_kingdom_labels()
					print("Etykiety królestw: ", "WIDOCZNE" if show_kingdom_labels else "UKRYTE")
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
						# Postaw bandytę i przypisz do ostatnio postawionego obozu w edytorze
						spawn_bandit_at(hex_coords)
						# EDYTOR: Przypisz do ostatnio postawionego obozu
						if editor_last_camp_id > 0:
							var farmer = farmer_map.get(hex_coords)
							if is_instance_valid(farmer):
								unit_to_camp[hex_coords] = editor_last_camp_id
								if not bandit_camp_ownership.has(editor_last_camp_id):
									bandit_camp_ownership[editor_last_camp_id] = []
								if hex_coords not in bandit_camp_ownership[editor_last_camp_id]:
									bandit_camp_ownership[editor_last_camp_id].append(hex_coords)
								bandits_need_camp.erase(hex_coords)
								print("EDYTOR: Bandyta @ %s przypisany do obozu #%d" % [hex_coords, editor_last_camp_id])
					"Castle_Bandit":
						# Postaw obóz i ustaw go jako aktywny dla kolejnych bandytów
						place_castle_at(hex_coords, -1)
						territory_map[hex_coords] = -2
						update_hex_color(hex_coords)
						# Znajdź camp_id tego obozu
						var new_camp = castle_map.get(hex_coords)
						if is_instance_valid(new_camp):
							if not new_camp.has_meta("camp_id"):
								var cid = next_bandit_camp_id
								next_bandit_camp_id += 1
								new_camp.set_meta("camp_id", cid)
								bandit_camp_ownership[cid] = []
								bandit_camp_gold[cid] = 10  # Bazowe 10 golda
							editor_last_camp_id = new_camp.get_meta("camp_id")
							# Pokaż etykietę złota
							var camp_id_val = new_camp.get_meta("camp_id")
							_set_bandit_camp_gold_label(new_camp, bandit_camp_gold.get(camp_id_val, 10))
							print("EDYTOR: Nowy obóz bandytów #%d @ %s (kolejne bandyty będą do niego przypisane)" % [editor_last_camp_id, hex_coords])
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
		get_node("/root/Main").play_put_sound()
		
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
	
	# Jeśli wall_placement_mode był aktywny przy Next Turn - wykonaj dokładnie to samo
	# co drugi klik przycisku wall (używając old_team bo current_team już się zmieniło)
	if wall_placement_mode:
		if wall_hexes_selected.size() > 0:
			var cost = wall_hexes_selected.size() * WALL_COST_PER_HEX
			if team_gold[old_team] >= cost:
				var saved_team = current_team
				current_team = old_team
				create_walls_between_selected()
				current_team = saved_team
				team_gold[old_team] -= cost
				print("Auto-scalono mury za: ", cost, " zlota (Next Turn)")
			else:
				print("Nie stac na mury przy Next Turn - anulowano")
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		wall_placement_mode = false
	
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
	if not game_mode or game_over:
		return
	
	# === FINALIZUJ MURY jeśli wall_placement_mode był aktywny ===
	if wall_placement_mode:
		if wall_hexes_selected.size() > 0:
			var cost = wall_hexes_selected.size() * WALL_COST_PER_HEX
			if team_gold[current_team] >= cost:
				create_walls_between_selected()
				team_gold[current_team] -= cost
				print("Auto-scalono mury za: ", cost, " zlota (Next Turn)")
			else:
				print("Nie stac na mury przy Next Turn - anulowano")
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		wall_placement_mode = false
	# ===
		
	if ui_manager:
		ui_manager.set_buttons_enabled(false)
	# === EKONOMIA - TYLKO NA KOŃCU RUNDY (gdy current_team == 4) ===
	# Sprawdź bankructwa PRZED zapisem (zawsze)
	var teams_to_check = [1, 2, 3, 4]
	for t in teams_to_check:
		var gold = team_gold.get(t, 0)
		var upkeep = calculate_upkeep(t)
		
		if gold < upkeep:
			print("⚠ Drużyna %d bankrutuje! (Złoto: %d, Koszty: %d)" % [t, gold, upkeep])
			handle_bankruptcy(t)
	
	# WAŻNE: Nalicz złoto/koszty TYLKO gdy kończy się cała runda (current_team == 4)
	if current_team == 4:
		print("=== KONIEC RUNDY %d - NALICZANIE EKONOMII ===" % current_round)
		for t in teams_to_check:
			var income = calculate_income(t)
			var upkeep = calculate_upkeep(t)
			var net = income - upkeep
			team_gold[t] += net
			
			if team_gold[t] < 0:
				team_gold[t] = 0
			
			print("Team %d: +%d dochód, -%d koszty = %d (saldo: %d)" % [t, income, upkeep, net, team_gold[t]])
	# === KONIEC ZMIANY EKONOMII ===
	
	# === BANDYCI: dochód z okupacji i spawn z obozów ===
	if current_team == 4:
		process_bandit_occupation_income()
	# ===
	
	# Obsługa bandytów
	var bandits_copy = []
	bandits_copy.assign(bandits_need_camp)
	for coords in bandits_copy:
		var farmer = farmer_map.get(coords)
		if farmer and farmer.team == BANDIT_TEAM:
			var camp_id = find_nearest_bandit_camp(coords)
			if camp_id > 0:
				unit_to_camp[farmer] = camp_id
				bandit_camp_ownership[camp_id] = bandit_camp_ownership.get(camp_id, [])
				bandit_camp_ownership[camp_id].append(farmer)
				bandits_need_camp.erase(coords)
	
	# Zapisz snapshot PRZED zmianą drużyny
	turn_history.save_turn_snapshot(self)
	
	# === DODAJ TUTAJ - sprawdź czy następna drużyna to AI ===
	var next_team = (current_team % 4) + 1
	var is_next_ai = next_team in ai_teams
	# === KONIEC DODANIA ===
	
	# Zmiana drużyny
	current_team = (current_team % 4) + 1
	
	# Resetuj jednostki które się ruszyły
	units_moved_this_turn.clear()
	cavalry_moves_this_turn.clear()
	
	# Nowa runda co 4 tury
	if current_team == 1:
		current_round += 1
		
		# === TURA BANDYTÓW NA KOŃCU RUNDY ===
		# Bandyci ruszają się po zakończeniu rundy wszystkich graczy
		if farmer_map.values().any(func(f): return is_instance_valid(f) and f.team == -1):
			print("=== TURA BANDYTÓW (koniec rundy %d) ===" % (current_round - 1))
			
			# Utwórz AI dla bandytów jeśli nie istnieje
			if not ai_controllers.has(-1):
				var bandit_ai = AIController.new(self, -1, 0, 0.5)
				add_child(bandit_ai)
				ai_controllers[-1] = bandit_ai
				print("AI dla bandytów utworzone")
			
			# Wykonaj turę bandytów
			await get_tree().create_timer(0.3).timeout
			await ai_controllers[-1].execute_turn()
			await get_tree().create_timer(0.3).timeout
			
			# Resetuj jednostki bandytów które się ruszyły
			units_moved_this_turn.clear()
			cavalry_moves_this_turn.clear()
			
			print("=== KONIEC TURY BANDYTÓW ===")
	
	# UI
	update_ui()
	clear_highlights()
	
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	pulse_available_units()
	check_victory()
	
	# Odśwież numerki królestw (mogły zmienić się podczas tury)
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	for t in [1, 2, 3, 4]:
		_redistribute_castle_gold(t)
	_update_bandit_camp_gold_labels()
	_update_castle_gold_labels()
	
	# === DODAJ TUTAJ - wykonaj turę AI jeśli potrzeba ===
	if is_next_ai and ai_controllers.has(current_team):
		# Przyciski już zablokowane na początku funkcji
		await get_tree().create_timer(0.5).timeout
		await ai_controllers[current_team].execute_turn()
		# Po zakończeniu tury AI - przelicz królestwa (naprawia znikające numerki)
		for t in [1, 2, 3, 4]:
			recalculate_kingdoms(t)
		for t in [1, 2, 3, 4]:
			_redistribute_castle_gold(t)
		_update_bandit_camp_gold_labels()
		_update_castle_gold_labels()
		# automatycznie zakończ turę
		await get_tree().create_timer(0.5).timeout
		_on_end_turn()
	else:
		# Nie ma AI - odblokuj przyciski
		if ui_manager:
			ui_manager.set_buttons_enabled(true)
	# === KONIEC DODANIA ===
	
func _on_rewind_turn():
	"""Obsługa przycisku cofania tury"""
	if not game_mode:
		print("Cofanie tur dostępne tylko w trybie gry!")
		return
	
	if not turn_history.can_rewind():
		print("Nie można cofnąć tury!")
		return
	
	get_node("/root/Main").play_btn_sound()
	
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
				spawn_bandit_at(coords)
			elif cavalry_map.has(coords):
				remove_cavalry_at(coords)
				spawn_bandit_at(coords)
			elif spearman_map.has(coords):
				remove_spearman_at(coords)
				spawn_bandit_at(coords)
			elif farmer_map.has(coords):
				var farmer = farmer_map[coords]
				farmer.team = -1
				farmer.spawn_turn = current_round
				bandit_spawn_hexes[coords] = true
				update_hex_color(coords)
		
		# Postaw oboz bandytow obok jednostek
		place_bandit_camp_near_units(team_units, team_units)
		
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
	"""STARA FUNKCJA - zachowana dla kompatybilności. Teraz używaj try_break_walls."""
	# Sprawdź czy cel jest otoczony murami
	var hex = get_hex_at(target_pos)
	if not hex or not hex.occupied_object:
		return true
	
	var target = hex.occupied_object
	var wall_count = count_walls_around(target_pos)
	
	# Jeśli nie ma pełnego otoczenia murami - może atakować
	if wall_count < 6:
		return true
	
	# CEL JEST OTOCZONY MURAMI
	print("Cel otoczony murami (", wall_count, "/6)")
	
	if attacker is Knight:
		if target is Farmer:
			return true
		else:
			return false
	elif attacker is Spearman:
		return false
	elif attacker is Farmer:
		return false
	
	return false

func count_walls_around(hex_pos: Vector2i) -> int:
	"""Liczy ile murów otacza dany hex"""
	var count = 0
	for neighbor in get_neighbors(hex_pos):
		if has_wall_between(hex_pos, neighbor):
			count += 1
	return count

func get_attacker_wall_power(attacker) -> int:
	"""Zwraca 'siłę przełamania murów' jednostki:
	0 = nie może niszczyć murów (farmer)
	1 = niszczy puste mury, mury z farmerem, mury ze spearmanem (spearman)
	2 = dodatkowo mury z knightem (knight)
	3 = dodatkowo mury z cavalry (cavalry)
	"""
	if attacker is Cavalry:
		return 3
	elif attacker is Knight:
		return 2
	elif attacker is Spearman:
		return 1
	else:
		return 0  # Farmer

func get_unit_wall_defense(unit) -> int:
	"""Zwraca 'twardość' jednostki w murach - ile potrzeba siły by przebić.
	0 = puste mury (spearman może)
	1 = farmer/spearman/zamek w murach (spearman może)
	2 = knight w murach (tylko knight+ może)
	3 = cavalry w murach (tylko cavalry może)
	"""
	if unit == null:
		return 0  # Puste mury
	elif unit is Castle:
		return 1  # Zamek = spearman może zniszczyć mury i przejąć
	elif unit is Cavalry:
		return 3
	elif unit is Knight:
		return 2
	elif unit is Spearman:
		return 1
	elif unit is Farmer:
		return 1
	return 0

func try_break_walls(attacker, from: Vector2i, to: Vector2i) -> bool:
	"""Próbuje zniszczyć mury na polu docelowym.
	
	Nowa mechanika:
	- Jeśli pole TO ma mury i atakujący ma wystarczającą siłę - NISZCZY MURY, jednostka zostaje
	- Atakujący traci turę (wraca na miejsce), NIE wchodzi na pole
	- Zwraca TRUE jeśli atak był na mury (turę pochłonięto), FALSE jeśli normalny atak
	
	Hierarchia siły:
	- Farmer (0): nie może niszczyć murów w ogóle
	- Spearman (1): niszczy puste mury, mury z farmerem/spearmanem
	- Knight (2): + mury z knightem
	- Cavalry (3): + mury z cavalry
	"""
	
	# Sprawdź czy cel ma mury
	var wall_count = count_walls_around(to)
	if wall_count < 6:
		return false  # Brak pełnych murów - normalny atak
	
	# Siła atakującego
	var attacker_power = get_attacker_wall_power(attacker)
	if attacker_power == 0:
		# Farmer nie może niszczyć murów - blokuj ruch
		print("Farmer nie może niszczyć murów!")
		return true  # Pochłoń turę i zablokuj (farmer traci ruch)
	
	# Sprawdź co jest w środku
	var to_hex = get_hex_at(to)
	var defender = to_hex.occupied_object if to_hex else null
	var defense_level = get_unit_wall_defense(defender)
	
	# Sprawdź czy atakujący ma wystarczającą siłę
	if attacker_power < defense_level:
		# Np. spearman vs knight w murach - za słaby
		print("Za słaby by przebić mury! (siła=%d, obrona=%d)" % [attacker_power, defense_level])
		return true  # Pochłoń turę, nie wchodź
	
	# Atakujący MA wystarczającą siłę - NISZCZ MURY!
	print("=== NISZCZENIE MURÓW na %s! (siła=%d, obrona=%d) ===" % [to, attacker_power, defense_level])
	
	# Animacja: mury błyskają i znikają
	if has_meta("wall_lines"):
		var wall_lines = get_meta("wall_lines")
		for edge_i in range(6):
			var edge_key = "%d,%d-edge%d" % [to.x, to.y, edge_i]
			if wall_lines.has(edge_key):
				var wall_line = wall_lines[edge_key]
				if is_instance_valid(wall_line):
					var wt = create_tween()
					wt.tween_property(wall_line, "modulate", Color(1, 0.9, 0.2, 1.0), 0.05)
					wt.tween_property(wall_line, "modulate:a", 0.0, 0.08)
	await get_tree().create_timer(0.13).timeout
	
	# Upewnij się że atakujący jest na swojej pozycji (nie leci nigdzie)
	var from_hex_reset = get_hex_at(from)
	if from_hex_reset and is_instance_valid(attacker):
		attacker.position = from_hex_reset.position
		# Resetuj sprite do normalnego stanu (nie "wciśnięty")
		if attacker.has_method("set_selected"):
			attacker.set_selected(false)
		if attacker.sprite and is_instance_valid(attacker.sprite):
			attacker.sprite.scale = Vector2.ONE
	
	# Zniszcz mury
	purge_walls_connected_to(to)
	print("Mury na %s zniszczone! Jednostka %s zostaje." % [to, defender.get_class() if defender else "brak"])
	
	# Zaznacz atakującego jako ruszonego (stracił turę)
	if attacker not in units_moved_this_turn:
		units_moved_this_turn.append(attacker)
	
	# Upewnij się że atakujący stoi poprawnie na swoim hexie (nie "wciśnięty")
	var from_hex_final = get_hex_at(from)
	if from_hex_final and is_instance_valid(attacker):
		attacker.position = from_hex_final.position
		if attacker.sprite and is_instance_valid(attacker.sprite):
			attacker.sprite.scale = Vector2.ONE
		if attacker.has_method("set_selected"):
			attacker.set_selected(false)
	
	# Odśwież UI
	get_node("/root/Main").play_put_sound()
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	clear_highlights()
	pulse_available_units()
	
	return true  # Atak na mury pochłonął turę

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

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	"""Oblicza odległość między dwoma hexami"""
	var ac = axial_to_cube(a)
	var bc = axial_to_cube(b)
	return (abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2

func axial_to_cube(hex: Vector2i) -> Vector3i:
	"""Konwertuje współrzędne axial na cube"""
	var x = hex.x
	var z = hex.y
	var y = -x - z
	return Vector3i(x, y, z)

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
	
	# Sprawdź czy stoi tu bandyta - jeśli tak, rysuj szaro wizualnie
	# (territory_map nie jest zmieniane, żeby ekonomia i pathfinding działały)
	var bandit_here = farmer_map.has(hex_coords) and farmer_map[hex_coords].team == BANDIT_TEAM
	
	var new_color: Color
	if bandit_here:
		new_color = BANDIT_COLOR
	elif territory_map.has(hex_coords):
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
		hex.current_color = new_color
		if hex.sprite and not hex.is_highlighted:
			hex.sprite.modulate = new_color

func _set_bandit_visual(hex_coords: Vector2i, is_bandit_here: bool):
	"""Ustawia wizualny kolor hexa bez zmiany territory_map.
	Gdy bandyta stoi - szaro. Gdy odchodzi - przywróć prawdziwy kolor (lub neutralny jeśli odcięte)."""
	if not is_bandit_here:
		if bandit_spawn_hexes.has(hex_coords):
			# Pole spawnu → zawsze neutralne
			territory_map.erase(hex_coords)
			bandit_spawn_hexes.erase(hex_coords)
		else:
			# Sprawdź czy pole jest odcięte od zamku właściciela
			var owner = territory_map.get(hex_coords, 0)
			if owner > 0:
				var connected = get_connected_territories(owner)
				if hex_coords not in connected:
					# Odcięte → neutralne
					territory_map.erase(hex_coords)
	update_hex_color(hex_coords)

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
	
	# Przelicz królestwa dla obu drużyn
	if current_owner > 0 and current_owner <= 4:
		recalculate_kingdoms(current_owner)
	if next_owner > 0 and next_owner <= 4 and next_owner != current_owner:
		recalculate_kingdoms(next_owner)

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
	bandit_spawn_hexes.clear()
	current_round = 1
	
	# Wyczyść dane królestw
	castle_kingdom_id.clear()
	hex_kingdom_map.clear()
	next_kingdom_id_per_team = {1: 1, 2: 1, 3: 1, 4: 1}
	kingdom_gold.clear()
	
	if turn_history: 
		turn_history.reset_rewinds()

# --- ZAMKI ---
func place_castle_at(hex_coords: Vector2i, team: int, forced_kingdom_id: int = -1):
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
	castle.modulate = Color.WHITE  # Sprite zamku zawsze biały
	add_child(castle)
	
	castle_map[hex_coords] = castle
	hex.place_object(castle)
	
	territory_map[hex_coords] = team
	# NAPRAWIONY BUG: Zawsze ustaw kolor bezpośrednio żeby naprawić stan po rewind
	hex.current_color = TEAM_COLORS.get(team, Color("#2b2b2b")) if team > 0 else (BANDIT_COLOR if team == -1 else BANDIT_CAMP_COLOR if team == -2 else Color("#2b2b2b"))
	if hex.sprite:
		hex.sprite.modulate = hex.current_color
	
	# === KINGDOM SYSTEM ===
	if team > 0 and team <= 4:
		var kid: int
		if forced_kingdom_id > 0:
			kid = forced_kingdom_id
			# Upewnij się że licznik jest wyższy
			if not next_kingdom_id_per_team.has(team):
				next_kingdom_id_per_team[team] = 1
			if kid >= next_kingdom_id_per_team[team]:
				next_kingdom_id_per_team[team] = kid + 1
		else:
			if not next_kingdom_id_per_team.has(team):
				next_kingdom_id_per_team[team] = 1
			kid = next_kingdom_id_per_team[team]
			next_kingdom_id_per_team[team] += 1
		castle_kingdom_id[hex_coords] = kid
		hex_kingdom_map[hex_coords] = kid
		# Inicjalizuj złoto zamku - podziel równo między wszystkie zamki teamu
		_redistribute_castle_gold(team)
		# Ustaw etykietę na zamku (stały ID zamku)
		if castle.has_method("set_kingdom_label"):
			castle.set_kingdom_label(kid_to_display(kid), show_kingdom_labels)
		# Przelicz królestwa - synchronicznie, bez await
		recalculate_kingdoms(team)

func remove_castle_at(hex_coords: Vector2i):
	if castle_map.has(hex_coords):
		var castle = castle_map[hex_coords]
		
		# Jeśli to obóz bandytów, odłącz jednostki (nie usuwaj ich)
		if castle.team == BANDIT_TEAM and castle.has_meta("camp_id"):
			var camp_id = castle.get_meta("camp_id")
			if bandit_camp_ownership.has(camp_id):
				var bandit_units = bandit_camp_ownership[camp_id].duplicate()
				print("Obóz bandytów #%d zniszczony - odłączam %d bandytów (pozostają żywi)" % [camp_id, bandit_units.size()])
				for unit_pos in bandit_units:
					unit_to_camp.erase(unit_pos)
				bandit_camp_ownership.erase(camp_id)
			bandit_camp_gold.erase(camp_id)
		
		# Usuń dane królestwa dla tego zamku
		var old_team = castle.team
		castle_kingdom_id.erase(hex_coords)
		
		castle.queue_free()
		castle_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()
		
		# Przelicz królestwa po usunięciu zamku
		if old_team > 0 and old_team <= 4:
			recalculate_kingdoms(old_team)
			
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
	
	# Ustaw terytorium jeśli unit należy do drużyny (nie-neutralny)
	if team > 0 and team <= 4:
		if not territory_map.has(hex_coords) or territory_map[hex_coords] == 0:
			territory_map[hex_coords] = team
			update_hex_color(hex_coords)
	
	await get_tree().process_frame
	if cavalry.sprite:
		cavalry.sprite.scale = Vector2(1.0, 1.0)

func remove_cavalry_at(hex_coords: Vector2i):
	if unit_to_camp.has(hex_coords):
		var camp_id = unit_to_camp[hex_coords]
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			camp_units.erase(hex_coords)
		unit_to_camp.erase(hex_coords)
	
	if cavalry_map.has(hex_coords):
		var cavalry = cavalry_map[hex_coords]
		cavalry.queue_free()
		cavalry_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_cavalry(from: Vector2i, to: Vector2i):
	var player_lost = false  # Flaga czy gracz przegrał
	
	if not cavalry_map.has(from):
		return
	
	var cavalry = cavalry_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
	
	# MECHANIKA MURÓW DLA CAVALRY
	var wall_count = count_walls_around(to)
	if wall_count >= 6:
		var moves_done = cavalry_moves_this_turn.get(cavalry, 0)
		if moves_done == 0:
			purge_walls_connected_to(to)
			cavalry_moves_this_turn[cavalry] = 1
		else:
			purge_walls_connected_to(to)
			cavalry_moves_this_turn[cavalry] = 2
			units_moved_this_turn.append(cavalry)
			if selected_unit == cavalry:
				clear_selected_unit_highlight()
				cavalry.set_selected(false)
				selected_unit = null
			clear_highlights()
			pulse_available_units()
			get_node("/root/Main").play_put_sound()
			return
	
	# Cavalry może atakować WSZYSTKO
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		if target is Cavalry and target.team != cavalry.team:
			remove_cavalry_at(to)
		elif target is Farmer and target.team != cavalry.team:
			remove_farmer_at(to)
		elif target is Spearman and target.team != cavalry.team:
			remove_spearman_at(to)
		elif target is Knight and target.team != cavalry.team:
			remove_knight_at(to)
		elif target is Castle:
			# Cavalry może przejąć obóz bandytów
			if target.team == -1:
				print("=== CAVALRY PRZEJMUJE OBÓZ BANDYTÓW ===")
				
				team_gold[cavalry.team] += BANDIT_CAMP_REWARD
				print("Otrzymano ", BANDIT_CAMP_REWARD, " złota!")
				
				# ===== NOWE: Znajdź ID obozu =====
				var destroyed_camp = castle_map[to]
				var camp_id = destroyed_camp.get_meta("camp_id", -1)
				
				if camp_id == -1:
					print("BŁĄD: Obóz nie ma ID!")
					remove_castle_at(to)
					return
				
				print("Zniszczono obóz bandytów ID:", camp_id)
				
				# ===== NOWE: Znajdź TYLKO jednostki z tego obozu =====
				var bandit_units = []
				if bandit_camp_ownership.has(camp_id):
					var camp_units = bandit_camp_ownership[camp_id]
					
					for coords in camp_units:
						if knight_map.has(coords) and knight_map[coords].team == -1:
							bandit_units.append(coords)
						elif farmer_map.has(coords) and farmer_map[coords].team == -1:
							bandit_units.append(coords)
						elif spearman_map.has(coords) and spearman_map[coords].team == -1:
							bandit_units.append(coords)
						elif cavalry_map.has(coords) and cavalry_map[coords].team == -1:
							bandit_units.append(coords)
				
				print("Znaleziono jednostek z tego obozu:", bandit_units.size())
				
				# Usuń obóz
				remove_castle_at(to)
				
				# ===== NOWE: Usuń informacje o obozie =====
				bandit_camp_ownership.erase(camp_id)
				
				# Usuń jednostki z tego obozu
				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
					unit_to_camp.erase(coords)
				
				# Znajdź terytoria tego obozu
				var bandit_territories = []
				for coords in bandit_units:
					if territory_map.get(coords, 0) == -1 or territory_map.get(coords, 0) == -2:
						if coords not in bandit_territories:
							bandit_territories.append(coords)
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						var owner = territory_map.get(neighbor, 0)
						if (owner == -1 or owner == -2) and neighbor not in bandit_territories:
							bandit_territories.append(neighbor)
				
				# Dodaj pole obozu
				if to not in bandit_territories:
					bandit_territories.append(to)
				
				print("Znaleziono terytoriów tego obozu:", bandit_territories.size())
				
				# Usuń mury
				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							purge_walls_connected_to(coords)
				
				# Resetuj pola
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)
				
				print("Obóz bandytów", camp_id, "przejęty przez cavalry!")

			elif target.team != cavalry.team and target.team > 0 and target.team <= 4:
				var old_team_cv = target.team
				capture_castle(to, cavalry.team, old_team_cv)
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
	
	get_node("/root/Main").play_put_sound()
	
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
	
	if unit_to_camp.has(from):
		var camp_id = unit_to_camp[from]
		unit_to_camp.erase(from)
		unit_to_camp[to] = camp_id
		
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			var idx = camp_units.find(from)
			if idx != -1:
				camp_units[idx] = to
	
	# Regalo capture po zakończeniu slide animacji
	await get_tree().create_timer(0.15).timeout
	# Nie przejmuj terytorium jeśli to było przejęcie zamku (capture_castle już to zrobiło)
	if not castle_map.has(to) or castle_map[to].team != cavalry.team:
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
	# capture_castle obsługuje defeat jeśli stracono ostatni zamek

func merge_knights_to_cavalry(knight1_pos: Vector2i, knight2_pos: Vector2i):
	"""Łączy dwóch knightów w cavalry"""
	if not knight_map.has(knight1_pos) or not knight_map.has(knight2_pos):
		return
	
	var knight1 = knight_map[knight1_pos]
	var knight2 = knight_map[knight2_pos]
	
	if knight1.team != knight2.team:
		return
		
	get_node("/root/Main").play_put_sound()
	
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
	if buy_mode != "":
		if cavalry.team != current_team:
			return
		_cancel_buy_mode()
		# Kontynuuj normalnie poniżej
	
	if merge_mode:
		print("Cavalry nie może być łączony!")
		return
	
	# Aktualizuj wybrane królestwo dla UI (każda cavalry)
	var kid_cv = hex_kingdom_map.get(cavalry.hex_position, 0)
	if kid_cv > 0 and cavalry.team > 0 and cavalry.team <= 4:
		selected_kingdom_per_team[cavalry.team] = kid_cv
		update_ui()
	
	if cavalry.team != current_team:
		return
	
	get_node("/root/Main").play_select_sound()
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
	
	# Ustaw terytorium jeśli unit należy do drużyny
	if team > 0 and team <= 4:
		if not territory_map.has(hex_coords) or territory_map[hex_coords] == 0:
			territory_map[hex_coords] = team
			update_hex_color(hex_coords)
	
	await get_tree().process_frame
	if spearman.sprite:
		spearman.sprite.scale = Vector2(1.0, 1.0)

func remove_spearman_at(hex_coords: Vector2i):
	if unit_to_camp.has(hex_coords):
		var camp_id = unit_to_camp[hex_coords]
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			camp_units.erase(hex_coords)
		unit_to_camp.erase(hex_coords)
	
	if spearman_map.has(hex_coords):
		var spearman = spearman_map[hex_coords]
		spearman.queue_free()
		spearman_map.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()

func move_spearman(from: Vector2i, to: Vector2i):
	var player_lost = false  # Flaga czy gracz przegrał
	
	if not spearman_map.has(from):
		return
	
	var spearman = spearman_map[from]
	var from_hex = get_hex_at(from)
	var to_hex = get_hex_at(to)
	
	if not to_hex:
		return
	
	# NOWA MECHANIKA MURÓW
	var wall_count = count_walls_around(to)
	if wall_count >= 6:
		var broke_walls = await try_break_walls(spearman, from, to)
		if broke_walls:
			return
	
	var from_owner = territory_map.get(from, 0)
	var to_owner = territory_map.get(to, 0)
	
	if castle_map.has(to):
		var target_castle = castle_map[to]
		if target_castle.team != spearman.team:
			var old_team = target_castle.team
			
			if old_team == 1:
				# Zapamiętaj że gracz przegrał - pokażemy defeat PO przejęciu
				player_lost = true
			
			if old_team == -1:
				print("=== SPEARMAN PRZEJMUJE OBÓZ BANDYTÓW ===")
				
				team_gold[spearman.team] += BANDIT_CAMP_REWARD
				print("Otrzymano ", BANDIT_CAMP_REWARD, " złota!")
				
				# ===== NOWE: Znajdź ID obozu =====
				var destroyed_camp = castle_map[to]
				var camp_id = destroyed_camp.get_meta("camp_id", -1)
				
				if camp_id == -1:
					print("BŁĄD: Obóz nie ma ID!")
					remove_castle_at(to)
					return
				
				print("Zniszczono obóz bandytów ID:", camp_id)
				
				# ===== NOWE: Znajdź TYLKO jednostki z tego obozu =====
				var bandit_units = []
				if bandit_camp_ownership.has(camp_id):
					var camp_units = bandit_camp_ownership[camp_id]
					
					for coords in camp_units:
						if knight_map.has(coords) and knight_map[coords].team == -1:
							bandit_units.append(coords)
						elif farmer_map.has(coords) and farmer_map[coords].team == -1:
							bandit_units.append(coords)
						elif spearman_map.has(coords) and spearman_map[coords].team == -1:
							bandit_units.append(coords)
						elif cavalry_map.has(coords) and cavalry_map[coords].team == -1:
							bandit_units.append(coords)
				
				print("Znaleziono jednostek z tego obozu:", bandit_units.size())
				
				# Usuń obóz
				remove_castle_at(to)
				
				# ===== NOWE: Usuń informacje o obozie =====
				bandit_camp_ownership.erase(camp_id)
				
				# Usuń jednostki z tego obozu
				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
					elif spearman_map.has(coords):
						remove_spearman_at(coords)
					elif cavalry_map.has(coords):
						remove_cavalry_at(coords)
					unit_to_camp.erase(coords)
				
				# Znajdź terytoria tego obozu
				var bandit_territories = []
				for coords in bandit_units:
					if territory_map.get(coords, 0) == -1 or territory_map.get(coords, 0) == -2:
						if coords not in bandit_territories:
							bandit_territories.append(coords)
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						var owner = territory_map.get(neighbor, 0)
						if (owner == -1 or owner == -2) and neighbor not in bandit_territories:
							bandit_territories.append(neighbor)
				
				# Dodaj pole obozu
				if to not in bandit_territories:
					bandit_territories.append(to)
				
				print("Znaleziono terytoriów tego obozu:", bandit_territories.size())
				
				# Usuń mury
				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							purge_walls_connected_to(coords)
				
				# Resetuj pola
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)
				
				print("Obóz bandytów", camp_id, "przejęty przez spearmana!")

			elif old_team > 0 and old_team <= 4:
				print("=== SPEARMAN PRZEJMUJE ZAMEK GRACZA ===")
				capture_castle(to, spearman.team, old_team)
	
	# DODAJ: Obsługa ataku na wrogie jednostki
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Spearman może atakować farmera (team 1-4 I bandytów team -1)
		if target is Farmer:
			if target.team != spearman.team:
				# Usuń farmera (mury już sprawdzone przez try_break_walls)
				remove_farmer_at(to)
		elif target is Spearman and target.team != spearman.team:
			# Usuń spearmana
			remove_spearman_at(to)
		elif target is Knight:
			# NOWE: Może atakować knightów bandytów (team -1)
			if target.team == -1:
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
	
	# Przenieś spearmana
	spearman_map.erase(from)
	from_hex.remove_object()
	
	spearman.hex_position = to
	spearman_map[to] = spearman
	to_hex.place_object(spearman)
	spearman.sprite.scale = Vector2.ZERO
	
	get_node("/root/Main").play_put_sound()
	
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
		
	if unit_to_camp.has(from):
		var camp_id = unit_to_camp[from]
		unit_to_camp.erase(from)
		unit_to_camp[to] = camp_id
		
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			var idx = camp_units.find(from)
			if idx != -1:
				camp_units[idx] = to
	
	await get_tree().create_timer(0.15).timeout
	if not castle_map.has(to) or castle_map[to].team != spearman.team:
		capture_territory(to, spearman.team)
	clear_highlights()
	pulse_available_units()
	# capture_castle obsługuje defeat jeśli stracono ostatni zamek

func merge_farmers_to_spearman(farmer1_pos: Vector2i, farmer2_pos: Vector2i):
	"""Łączy dwóch farmerów w spearmana"""
	if not farmer_map.has(farmer1_pos) or not farmer_map.has(farmer2_pos):
		return
	
	var farmer1 = farmer_map[farmer1_pos]
	var farmer2 = farmer_map[farmer2_pos]
	
	if farmer1.team != farmer2.team:
		return
		
	get_node("/root/Main").play_put_sound()
	
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
		
	get_node("/root/Main").play_put_sound()
	
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
	if buy_mode != "":
		if spearman.team != current_team:
			return
		_cancel_buy_mode()
		# Kontynuuj normalnie poniżej
	
	# Aktualizuj wybrane królestwo dla UI (każdy spearman)
	var kid_sp = hex_kingdom_map.get(spearman.hex_position, 0)
	if kid_sp > 0 and spearman.team > 0 and spearman.team <= 4:
		selected_kingdom_per_team[spearman.team] = kid_sp
		update_ui()
	
	# === NOWE: Łączenie spearmanów ===
	if selected_unit and selected_unit is Spearman and selected_unit != spearman:
		if spearman.team == selected_unit.team:
			merge_spearmen_to_knight(selected_unit.hex_position, spearman.hex_position)
			return
		else:
			get_node("/root/Main").play_select_sound()
	
	# === Reszta bez zmian ===
	if spearman.team != current_team:
		return
	
	if spearman in units_moved_this_turn:
		print("Ta jednostka już się ruszyła w tej turze")
		return
		
	get_node("/root/Main").play_select_sound()
	
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
	
	# Ustaw terytorium jeśli unit należy do drużyny
	if team > 0 and team <= 4:
		if not territory_map.has(hex_coords) or territory_map[hex_coords] == 0:
			territory_map[hex_coords] = team
			update_hex_color(hex_coords)
	
	# DODAJ: Wymus prawidlowa skale po dodaniu do sceny
	await get_tree().process_frame
	if knight.sprite:
		knight.sprite.scale = Vector2(1.0, 1.0)

func remove_knight_at(hex_coords: Vector2i):
	if unit_to_camp.has(hex_coords):
		var camp_id = unit_to_camp[hex_coords]
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			camp_units.erase(hex_coords)
		unit_to_camp.erase(hex_coords)
	
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
	
	# NOWA MECHANIKA MURÓW: Sprawdź czy cel ma pełne mury
	# Jeśli tak - spróbuj je zniszczyć (pochłania turę, jednostka w środku zostaje)
	var wall_count = count_walls_around(to)
	if wall_count >= 6:
		var broke_walls = await try_break_walls(knight, from, to)
		if broke_walls:
			return  # Turę pochłonięto (niszczyliśmy mury lub byliśmy za słabi)
		
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
	
	# ZMIANA: Jesli atakujemy zamek wroga - ZNISZCZ GO
	var player_lost = false  # Flaga czy gracz przegrał (zamek team 1 przejęty)
	
	if castle_map.has(to):
		var target_castle = castle_map[to]
		if target_castle.team != knight.team:
			var old_team = target_castle.team
			
			if old_team == 1:
				# Zapamiętaj że gracz przegrał - pokażemy defeat PO przejęciu
				player_lost = true
			
			if old_team == -1:
				print("=== PRZEJECIE OBOZU BANDYTOW ===")
				
				team_gold[knight.team] += BANDIT_CAMP_REWARD
				print("Otrzymano ", BANDIT_CAMP_REWARD, " złota za przejęcie obozu!")
				
				# ===== NOWE: Znajdź ID obozu =====
				var destroyed_camp = castle_map[to]
				var camp_id = destroyed_camp.get_meta("camp_id", -1)
				
				if camp_id == -1:
					print("BŁĄD: Obóz nie ma ID!")
					# Usun oboz
					remove_castle_at(to)
					return
				
				print("Zniszczono obóz bandytów ID:", camp_id)
				
				# ===== NOWE: Znajdź TYLKO jednostki z tego obozu =====
				var bandit_units = []
				if bandit_camp_ownership.has(camp_id):
					var camp_units = bandit_camp_ownership[camp_id]
					
					for coords in camp_units:
						if knight_map.has(coords) and knight_map[coords].team == -1:
							bandit_units.append(coords)
						elif farmer_map.has(coords) and farmer_map[coords].team == -1:
							bandit_units.append(coords)
				
				print("Znaleziono jednostek z tego obozu:", bandit_units.size())
				
				# Usun oboz
				remove_castle_at(to)
				
				# ===== NOWE: Usuń informacje o obozie =====
				bandit_camp_ownership.erase(camp_id)
				
				# Usun jednostki z tego obozu
				for coords in bandit_units:
					if knight_map.has(coords):
						remove_knight_at(coords)
					elif farmer_map.has(coords):
						remove_farmer_at(coords)
					unit_to_camp.erase(coords)
				
				# Znajdz terytoria tego obozu
				var bandit_territories = []
				for coords in bandit_units:
					if territory_map.get(coords, 0) == -1 or territory_map.get(coords, 0) == -2:
						if coords not in bandit_territories:
							bandit_territories.append(coords)
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						var owner = territory_map.get(neighbor, 0)
						if (owner == -1 or owner == -2) and neighbor not in bandit_territories:
							bandit_territories.append(neighbor)
				
				# Dodaj pole obozu
				if to not in bandit_territories:
					bandit_territories.append(to)
				
				print("Znaleziono terytoriow tego obozu:", bandit_territories.size())
				
				# Usun mury
				for coords in bandit_territories:
					var neighbors = get_neighbors(coords)
					for neighbor in neighbors:
						if has_wall_between(coords, neighbor):
							purge_walls_connected_to(coords)
				
				# Resetuj pola
				for coords in bandit_territories:
					territory_map.erase(coords)
					update_hex_color(coords)
				
				print("Oboz bandytow", camp_id, "przejety!")
				
				print("Oboz bandytow przejety! Jednostki i terytoria usuniete.")
			else:
				# NORMALNA OBSLUGA: Przejecie zamku gracza (team 1-4)
				capture_castle(to, knight.team, old_team)
	
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
	
	get_node("/root/Main").play_put_sound()
	
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
		
	if unit_to_camp.has(from):
		var camp_id = unit_to_camp[from]
		unit_to_camp.erase(from)
		unit_to_camp[to] = camp_id
		
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			var idx = camp_units.find(from)
			if idx != -1:
				camp_units[idx] = to
	
	await get_tree().create_timer(0.15).timeout
	
	# Przejmij terytorium (nie jeśli to było przejęcie zamku)
	if not castle_map.has(to) or castle_map[to].team != knight.team:
		capture_territory(to, knight.team)
	clear_highlights()
	pulse_available_units()
	# capture_castle obsługuje defeat jeśli stracono ostatni zamek

func remove_wall(hex1: Vector2i, hex2: Vector2i):
	"""Usuwa wall między hex1 i hex2 (z obu stron)"""
	
	# Usuń z hex1
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
	
	# Usuń z hex2 (DODANE - to naprawia problem z resztkami murów)
	var neighbors2 = get_neighbors(hex2)
	var edge_index2 = neighbors2.find(hex1)
	
	if edge_index2 != -1:
		var key2 = "%d,%d-edge%d" % [hex2.x, hex2.y, edge_index2]
		if wall_map.has(key2):
			wall_map.erase(key2)
			
			if has_meta("wall_lines"):
				var wall_lines = get_meta("wall_lines")
				if wall_lines.has(key2):
					wall_lines[key2].queue_free()
					wall_lines.erase(key2)
			
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
	farmer.spawn_turn = current_round  # NOWE: Zapisz turę spawnu
	farmer.position = hex.position
	add_child(farmer)
	
	farmer_map[hex_coords] = farmer
	hex.place_object(farmer)
	
	# Ustaw terytorium jeśli unit należy do drużyny
	if team > 0 and team <= 4:
		if not territory_map.has(hex_coords) or territory_map[hex_coords] == 0:
			territory_map[hex_coords] = team
			update_hex_color(hex_coords)
	
	# AUTO-PRZYPISANIE: Jeśli to bandyta, przypisz go do najbliższego obozu
	if team == BANDIT_TEAM:
		var camp_id = find_nearest_bandit_camp(hex_coords)
		if camp_id > 0:
			unit_to_camp[hex_coords] = camp_id
			if not bandit_camp_ownership.has(camp_id):
				bandit_camp_ownership[camp_id] = []
			bandit_camp_ownership[camp_id].append(hex_coords)
			print("Bandyta @ %s auto-przypisany do obozu #%d" % [hex_coords, camp_id])
		else:
			# Brak obozu - spróbuj postawić obóz na najbliższym wolnym neutralnym polu
			var camp_placed = place_bandit_camp_on_nearest_neutral(hex_coords)
			if not camp_placed:
				bandits_need_camp.append(hex_coords)
				print("Bandyta @ %s czeka na obóz" % hex_coords)

func spawn_bandit_at(hex_coords: Vector2i):
	"""Stawia bandytę. Hex wygląda szaro (bandyta tu stoi) ale territory_map się nie zmienia.
	Po opuszczeniu pola spawnu przez bandytę - pole staje się neutralne."""
	place_farmer_at(hex_coords, BANDIT_TEAM)
	# Zapamiętaj oryginalne terytorium tego pola (żeby po odejściu je wyczyścić do neutralnego)
	bandit_spawn_hexes[hex_coords] = true
	# Usuń z territory_map jeśli było -1 (bandyckie spawn z edytora - tam edytor ustawia -1)
	# update_hex_color samo pomaluje szaro bo farmer_map.has(hex_coords)
	update_hex_color(hex_coords)

func remove_farmer_at(hex_coords: Vector2i):
	if unit_to_camp.has(hex_coords):
		var camp_id = unit_to_camp[hex_coords]
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			camp_units.erase(hex_coords)
		unit_to_camp.erase(hex_coords)
	
	if farmer_map.has(hex_coords):
		var farmer = farmer_map[hex_coords]
		farmer.queue_free()
		farmer_map.erase(hex_coords)
		bandit_spawn_hexes.erase(hex_coords)
		
		var hex = get_hex_at(hex_coords)
		if hex:
			hex.remove_object()
			update_hex_color(hex_coords)

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
	
	# NOWA MECHANIKA MURÓW: Farmer nie może niszczyć murów w ogóle
	var wall_count = count_walls_around(to)
	if wall_count >= 6:
		print("Farmer nie może wejść na pole z murami!")
		return
	
	# DODAJ: Obsługa ataku na wrogiego farmera
	if to_hex.occupied_object != null:
		var target = to_hex.occupied_object
		
		# Farmer może atakować tylko farmera (nie spearmana ani knighta)
		if target is Farmer and target.team != farmer.team:
			# Usuń wrogiego farmera (mury już sprawdzone powyżej)
			remove_farmer_at(to)
		else:
			# Nie może atakować innych jednostek
			print("Farmer może atakować tylko farmera!")
			return
	
	# Przenieś farmera
	farmer_map.erase(from)
	from_hex.remove_object()
	
	farmer.hex_position = to
	farmer_map[to] = farmer
	to_hex.place_object(farmer)
	farmer.sprite.scale = Vector2.ZERO
	
	get_node("/root/Main").play_put_sound()
	
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
		
	if unit_to_camp.has(from):
		var camp_id = unit_to_camp[from]
		unit_to_camp.erase(from)
		unit_to_camp[to] = camp_id
		
		if bandit_camp_ownership.has(camp_id):
			var camp_units = bandit_camp_ownership[camp_id]
			var idx = camp_units.find(from)
			if idx != -1:
				camp_units[idx] = to
	
	await get_tree().create_timer(0.15).timeout
	if farmer.team == BANDIT_TEAM:
		# Bandyci NIE zmieniają territory_map - tylko wizualnie malują hex na szaro
		# Dzięki temu get_connected_territories działa poprawnie i podświetlanie też
		
		# Pole docelowe: pomaluj szaro wizualnie
		_set_bandit_visual(to, true)
		
		# Pole źródłowe: przywróć wizualny kolor
		var from_farmer = farmer_map.get(from)
		var occupied_by_bandit = (from_farmer != null and is_instance_valid(from_farmer) and from_farmer.team == BANDIT_TEAM)
		
		if not occupied_by_bandit:
			_set_bandit_visual(from, false)
	else:
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
	castle.modulate = Color.WHITE  # Sprite zamku zawsze biały
	add_child(castle)
	
	castle_map[from] = castle
	hex.place_object(castle)
	
	territory_map[from] = -2  # Oznacz jako obóz
	update_hex_color(from)
	
	# Inicjalizuj złoto obozu (bazowe 10) i pokaż etykietę
	if not castle.has_meta("camp_id"):
		var new_cid = next_bandit_camp_id
		next_bandit_camp_id += 1
		castle.set_meta("camp_id", new_cid)
		bandit_camp_gold[new_cid] = 10
		bandit_camp_ownership[new_cid] = []
	var cid = castle.get_meta("camp_id")
	_set_bandit_camp_gold_label(castle, bandit_camp_gold.get(cid, 10))
	
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
	"""Zwraca tylko pola POŁĄCZONE z zamkiem (dla przychodów) - TYLKO przez istniejące hexy"""
	
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
			
			# KLUCZOWE: Sprawdź czy hex FIZYCZNIE ISTNIEJE (nie przeskakuj przez przepaść)
			if not hex_map.has(neighbor):
				continue
			
			if not territory_map.has(neighbor):
				continue
			if territory_map[neighbor] != team:
				continue
			
			visited[neighbor] = true
			connected.append(neighbor)
			queue.append(neighbor)
	
	return connected

func get_connected_territories_for_unit(unit_pos: Vector2i, team: int) -> Array:
	"""Zwraca pola połączone TYLKO z zamkiem tego samego królestwa co jednostka.
	Gdy drużyna ma 1 zamek lub brak kingdom_id → standardowe zachowanie."""
	# Sprawdź kingdom_id pola jednostki
	var kid = hex_kingdom_map.get(unit_pos, 0)
	if kid <= 0:
		return get_connected_territories(team)
	
	# Ile zamków ma drużyna?
	var team_castle_count = 0
	for coords in castle_map:
		if castle_map[coords].team == team:
			team_castle_count += 1
	
	if team_castle_count <= 1:
		return get_connected_territories(team)
	
	# Znajdź zamek tego królestwa
	var castle_pos = Vector2i(-9999, -9999)
	for coords in castle_kingdom_id:
		if castle_kingdom_id[coords] == kid and castle_map.has(coords) and castle_map[coords].team == team:
			castle_pos = coords
			break
	
	if castle_pos == Vector2i(-9999, -9999):
		return get_connected_territories(team)
	
	# Flood fill od tego zamku
	var connected: Array = []
	var visited: Dictionary = {}
	var queue: Array = [castle_pos]
	visited[castle_pos] = true
	connected.append(castle_pos)
	
	while not queue.is_empty():
		var current = queue.pop_front()
		for neighbor in get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not hex_map.has(neighbor):
				continue
			if territory_map.get(neighbor, 0) != team:
				continue
			# Nie przekraczaj przez inne zamki (osobne królestwa)
			if castle_map.has(neighbor) and castle_map[neighbor].team == team and neighbor != castle_pos:
				var neighbor_kid = castle_kingdom_id.get(neighbor, 0)
				if neighbor_kid > 0 and neighbor_kid != kid:
					# Inny zamek tego teamu - sprawdź czy w innym królestwie
					# (Jeśli są scaleni to kid będzie ten sam)
					if hex_kingdom_map.get(neighbor, 0) != kid:
						visited[neighbor] = true
						connected.append(neighbor)
						continue
			visited[neighbor] = true
			connected.append(neighbor)
			queue.append(neighbor)
	
	return connected

# ===== KINGDOM SYSTEM FUNCTIONS =====

func castle_kingdom_id_belongs_to_team(kid: int, team: int) -> bool:
	"""Sprawdza czy kingdom_id należy do konkretnego teamu (niezawodne - szuka po teamie)"""	
	for coords in castle_kingdom_id:
		if castle_kingdom_id[coords] == kid:
			if castle_map.has(coords) and castle_map[coords].team == team:
				return true
			else:
				return false  # Znaleziono kid ale należy do innego teamu
	return false  # kid nie istnieje w żadnym zamku

func recalculate_kingdoms(team: int):
	"""Przelicza do którego królestwa należy każde pole drużyny.
	Zasada: flood fill od każdego zamku. Jeśli dwa zamki są połączone
	polami tej samej drużyny → scalają się (niższy ID wygrywa).
	Pola odcięte od wszystkich zamków → hex_kingdom_map bez wpisu.
	"""
	if team <= 0 or team > 4:
		return
	
	# Zbierz wszystkie zamki tej drużyny
	var team_castles: Array = []
	for coords in castle_map:
		if castle_map[coords].team == team:
			team_castles.append(coords)
	
	if team_castles.is_empty():
		# Brak zamków - wyczyść hex_kingdom_map dla tej drużyny
		for coords in territory_map.keys():
			if territory_map.get(coords, 0) == team:
				hex_kingdom_map.erase(coords)
				_update_hex_kingdom_label(coords, 0)
		return
	
	# BFS od każdego zamku - znajdź do którego królestwa należy każde pole
	# Jeśli pole jest osiągalne z wielu zamków → scalamy (bierzemy min ID)
	var field_to_kingdoms: Dictionary = {}  # {hex_coords: [kid1, kid2, ...]}
	
	for castle_coords in team_castles:
		var castle_kid = castle_kingdom_id.get(castle_coords, 0)
		if castle_kid <= 0:
			continue
		
		# Flood fill przez pola tej drużyny
		var visited: Dictionary = {}
		var queue: Array = [castle_coords]
		visited[castle_coords] = true
		
		while not queue.is_empty():
			var current = queue.pop_front()
			
			if not field_to_kingdoms.has(current):
				field_to_kingdoms[current] = []
			if castle_kid not in field_to_kingdoms[current]:
				field_to_kingdoms[current].append(castle_kid)
			
			for neighbor in get_neighbors(current):
				if visited.has(neighbor):
					continue
				if not hex_map.has(neighbor):
					continue
				if territory_map.get(neighbor, 0) != team:
					continue
				visited[neighbor] = true
				queue.append(neighbor)
	
	# Wyznacz finalne ID dla każdego pola (min z dostępnych)
	# Zbierz też grupowania zamków (które zamki są ze sobą połączone)
	var castle_groups: Dictionary = {}  # {kid: [kid1, kid2, ...]} - które IDs są połączone
	
	for coords in field_to_kingdoms:
		var kids_for_coord = field_to_kingdoms[coords]
		if kids_for_coord.size() > 1:
			# Pole osiągalne z wielu zamków → zamki są połączone
			var min_kid = kids_for_coord.min()
			for k in kids_for_coord:
				if k != min_kid:
					if not castle_groups.has(min_kid):
						castle_groups[min_kid] = []
					if k not in castle_groups[min_kid]:
						castle_groups[min_kid].append(k)
	
	# Rozwiąż transitive closure (jeśli 1→2 i 2→3 to 1→2,3)
	var merged_into: Dictionary = {}  # {old_kid: canonical_kid}
	for base_kid in castle_groups:
		for merged_kid in castle_groups[base_kid]:
			merged_into[merged_kid] = base_kid
	
	# Upewnij się że canonical jest tym z grupy o min wartości
	for old_kid in merged_into.keys():
		var canonical = merged_into[old_kid]
		# Sprawdź czy canonical sam jest merged
		var safety = 0
		while merged_into.has(canonical) and safety < 20:
			canonical = merged_into[canonical]
			safety += 1
		merged_into[old_kid] = canonical
	
	# Teraz przypisz finalne ID do pól
	for coords in hex_map.keys():
		if territory_map.get(coords, 0) != team:
			# Wyczyść tylko jeśli to pole było oznaczone jako należące do TEGO teamu
			# (nie czyść pól innych teamów - one mają własne kingdom IDs)
			if hex_kingdom_map.has(coords) and castle_kingdom_id_belongs_to_team(hex_kingdom_map[coords], team):
				hex_kingdom_map.erase(coords)
				_update_hex_kingdom_label(coords, 0)
			continue
		
		# Sprawdź czy to pole jest osiągalne z jakiegokolwiek zamku
		if not field_to_kingdoms.has(coords):
			# Odcięte od zamków → brak ID
			hex_kingdom_map.erase(coords)
			_update_hex_kingdom_label(coords, 0)
			continue
		
		var kids_final = field_to_kingdoms[coords]
		var base_kid = kids_final.min()
		# Resolve merged
		var safety2 = 0
		while merged_into.has(base_kid) and safety2 < 20:
			base_kid = merged_into[base_kid]
			safety2 += 1
		
		hex_kingdom_map[coords] = base_kid
		# Nie nadpisuj etykiety zamku (stała), tylko pola
		if not castle_map.has(coords) or castle_map[coords].team != team:
			_update_hex_kingdom_label(coords, base_kid)
	
	# Aktualizuj etykiety zamków (stałe - nie zmieniają się przez scaling)
	for castle_coords in team_castles:
		var castle = castle_map.get(castle_coords)
		if castle and is_instance_valid(castle):
			var castle_label_kid = castle_kingdom_id.get(castle_coords, 0)
			if castle.has_method("set_kingdom_label"):
				castle.set_kingdom_label(kid_to_display(castle_label_kid), show_kingdom_labels)

func _renumber_kingdoms(team: int):
	"""Po utracie zamku - przeponumeruj pozostałe zamki od 1 żeby nie było dziur.
	Zamek który pozostał jako jedyny → ID 1."""
	if team <= 0 or team > 4:
		return
	
	var team_castles = []
	for coords in castle_map:
		if castle_map[coords].team == team:
			team_castles.append(coords)
	
	if team_castles.is_empty():
		return
	
	if team_castles.size() == 1:
		# Jeden zamek → zawsze ID 1
		var c = team_castles[0]
		castle_kingdom_id[c] = 1
		next_kingdom_id_per_team[team] = 2
		var castle = castle_map[c]
		if castle.has_method("set_kingdom_label"):
			castle.set_kingdom_label(kid_to_display(1), show_kingdom_labels)
		# Zresetuj wybrany kid dla tego teamu
		selected_kingdom_per_team[team] = 1
	# Jeśli więcej zamków - zostawiamy stare IDs (recalculate_kingdoms zajmie się scalaniem)

func _get_kid_team(kid: int) -> int:
	"""Pomocnicza: zwraca team zamku o danym kingdom_id (uproszczone - szuka w castle_kingdom_id)"""
	for coords in castle_kingdom_id:
		if castle_kingdom_id[coords] == kid:
			if castle_map.has(coords):
				return castle_map[coords].team
	return 0

func _update_hex_kingdom_label(hex_coords: Vector2i, kingdom_id: int):
	"""Aktualizuje etykietę królestwa na hexie"""
	var hex = get_hex_at(hex_coords)
	if not hex:
		return
	# Nie aktualizuj pola zamku (zamek ma własną etykietę)
	if castle_map.has(hex_coords):
		return
	if hex.has_method("set_kingdom_label"):
		# Wyświetl lokalny numer (101→1, 201→1 itd.)
		hex.set_kingdom_label(kid_to_display(kingdom_id), show_kingdom_labels)

func _update_all_kingdom_labels():
	"""Aktualizuje widoczność wszystkich etykiet"""
	# Pola
	for coords in hex_map:
		var hex = get_hex_at(coords)
		if hex and hex.has_method("update_kingdom_label_visibility"):
			hex.update_kingdom_label_visibility(show_kingdom_labels)
	# Zamki
	for coords in castle_map:
		var castle = castle_map[coords]
		if castle and is_instance_valid(castle) and castle.has_method("update_label_visibility"):
			castle.update_label_visibility(show_kingdom_labels)
	# Obozy bandytów - złoto
	_update_bandit_camp_gold_labels()

func get_kingdom_id_at(hex_coords: Vector2i) -> int:
	"""Zwraca ID królestwa pola (0 = brak/odcięte)"""
	return hex_kingdom_map.get(hex_coords, 0)

func get_castle_kingdom_id(castle_coords: Vector2i) -> int:
	"""Zwraca stały ID zamku"""
	return castle_kingdom_id.get(castle_coords, 0)

func get_kingdom_connected_territories(kingdom_id: int) -> Array:
	"""Zwraca pola połączone z konkretnym królestwem"""
	var result: Array = []
	for coords in hex_kingdom_map:
		if hex_kingdom_map[coords] == kingdom_id:
			result.append(coords)
	return result

func calculate_income_for_kingdom(kingdom_id: int) -> int:
	"""Dochód z konkretnego królestwa"""
	var territories = get_kingdom_connected_territories(kingdom_id)
	var income = 0
	for coords in territories:
		if not castle_map.has(coords):  # Pole zamku nie daje dochodu z terytorium
			income += GOLD_PER_TERRITORY
	# Zamki tego królestwa
	for coords in castle_map:
		if castle_kingdom_id.get(coords, 0) == kingdom_id and castle_map[coords].team > 0:
			income += 2
	return income

func calculate_upkeep_for_kingdom(kingdom_id: int) -> int:
	"""Koszt utrzymania jednostek w konkretnym królestwie"""
	# Znajdź team właściciela tego królestwa
	var kingdom_team = _get_kid_team(kingdom_id)
	var connected = get_kingdom_connected_territories(kingdom_id)
	var connected_set: Dictionary = {}
	for pos in connected:
		connected_set[pos] = true
	
	var cost = 0
	for cavalry in cavalry_map.values():
		if cavalry.team == kingdom_team and connected_set.has(cavalry.hex_position):
			cost += CAVALRY_UPKEEP
	for knight in knight_map.values():
		if knight.team == kingdom_team and connected_set.has(knight.hex_position):
			cost += KNIGHT_UPKEEP
	for spearman in spearman_map.values():
		if spearman.team == kingdom_team and connected_set.has(spearman.hex_position):
			cost += SPEARMAN_UPKEEP
	for farmer in farmer_map.values():
		if farmer.team == kingdom_team and connected_set.has(farmer.hex_position):
			cost += FARMER_UPKEEP
	return cost

func _update_bandit_camp_gold_labels():
	"""Aktualizuje etykiety złota na obozach bandytów"""
	for coords in castle_map:
		var castle = castle_map[coords]
		if not is_instance_valid(castle):
			continue
		if castle.team != BANDIT_TEAM:
			continue
		var camp_id = castle.get_meta("camp_id") if castle.has_meta("camp_id") else -1
		if camp_id <= 0:
			continue
		var gold = bandit_camp_gold.get(camp_id, 0)
		_set_bandit_camp_gold_label(castle, gold)

func _set_bandit_camp_gold_label(castle: Node, gold: int):
	"""Ustawia/aktualizuje etykietę złota na obozie bandytów"""
	var label: Label = null
	for child in castle.get_children():
		if child is Label and child.has_meta("bandit_gold_label"):
			label = child
			break
	
	if not label:
		label = Label.new()
		label.set_meta("bandit_gold_label", true)
		label.z_index = 30
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("#FFD700"))  # Złoty
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("shadow_as_outline", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(40, 20)
		label.position = Vector2(-20, -44)  # Nieco wyżej niż zamek, ale nie za wysoko
		castle.add_child(label)
	
	label.text = str(gold)
	label.visible = true

# ===== END KINGDOM SYSTEM =====

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
	
	# Aktualizuj królestwa drużyny która przejęła pole
	if team > 0 and team <= 4:
		recalculate_kingdoms(team)
	# Nie przeliczaj kingdoms wroga tutaj - robi to _on_end_turn
	# żeby uniknąć wizualnego znikania numerków podczas ruchu
	
	# Aktualizuj etykietę złota na obozach bandytów
	_update_bandit_camp_gold_labels()
	
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
	
	# KLUCZOWY FIX: Jeśli nie ma jednostek - NIE TWÓRZ OBOZU
	if units_positions.is_empty():
		print("Brak jednostek w odcietym regionie - pomijam tworzenie obozu")
		return
	
	# Przeksztalc TYLKO knight/cavalry/spearman w farmerow bandytow, farmery królestwa usuń
	for coords in units_positions:
		if knight_map.has(coords):
			remove_knight_at(coords)
			spawn_bandit_at(coords)
		elif cavalry_map.has(coords):  
			remove_cavalry_at(coords)
			spawn_bandit_at(coords)
		elif spearman_map.has(coords):
			remove_spearman_at(coords)
			spawn_bandit_at(coords)
		elif farmer_map.has(coords):
			if farmer_map[coords].team == BANDIT_TEAM:
				# Bandyci już tu są - zostawiamy ich w spokoju
				pass
			else:
				# Farmery królestwa znikają przy odcięciu
				remove_farmer_at(coords)
				continue
	
	# Usun mury TYLKO z pol które faktycznie stały się bandyckie
	print("Usuwanie walli tylko z pol bandyckich...")
	for coords in units_positions:
		# Usuń mury tylko jeśli na tym polu stoi bandyta
		if farmer_map.has(coords) and farmer_map[coords].team == BANDIT_TEAM:
			for edge_index in range(6):
				var edge_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
				if wall_map.has(edge_key):
					wall_map.erase(edge_key)
					
					if has_meta("wall_lines"):
						var wall_lines = get_meta("wall_lines")
						if wall_lines.has(edge_key):
							wall_lines[edge_key].queue_free()
							wall_lines.erase(edge_key)
	
	# NOWE: Sprawdź czy po konwersji są jakiekolwiek jednostki bandytów
	var bandit_units = []
	for coords in region:
		if farmer_map.has(coords) and farmer_map[coords].team == BANDIT_TEAM:
			bandit_units.append(coords)
	
	if bandit_units.is_empty():
		print("Po konwersji brak jednostek bandytow - pomijam tworzenie obozu")
		print("=== KONIEC KONWERSJI REGIONU ===")
		return
	
	print("Tworzenie obozu dla ", bandit_units.size(), " bandytow...")
	
	# Postaw JEDEN oboz bandytow dla jednostek
	var camp_placed = place_bandit_camp_near_units(units_positions, units_positions)
	
	if not camp_placed:
		print("UWAGA: Nie znaleziono miejsca na oboz bandytow!")
	
	print("=== KONIEC KONWERSJI REGIONU ===")
	print("Bandytow: ", units_positions.size(), " | Pola wlasciciela (odciete): ", region.size() - units_positions.size())

func capture_castle(castle_coords: Vector2i, new_team: int, old_team: int):
	"""Przejmuje zamek wroga.
	- Zawsze: zamek ZNIKA, pole zamku neutralne
	- Multi-castle: pola połączone z innym zamkiem old_team zostają, odcięte → neutralne + bandyci
	- Last castle: wszystkie pola → neutralne, wszystkie jednostki → bandyci
	"""
	print("=== PRZEJECIE ZAMKU %s: team %d -> team %d ===" % [str(castle_coords), old_team, new_team])
	
	if not castle_map.has(castle_coords):
		print("BLAD: Brak zamku na ", castle_coords)
		return
	
	# Zbierz zloto PRZED usunieciem
	_collect_castle_gold_on_capture(castle_coords, new_team, old_team)
	
	# Sprawdz czy stary team ma jeszcze inne zamki
	var old_team_other_castles: Array = []
	for c in castle_map:
		if castle_map[c].team == old_team and c != castle_coords:
			old_team_other_castles.append(c)
	var has_other_castles = not old_team_other_castles.is_empty()
	
	# Flood fill pol TYLKO tego zamku (granica = inne zamki old_team)
	var fields_this_castle: Array = []
	var ff_v = {}
	var ff_q = [castle_coords]
	ff_v[castle_coords] = true
	while not ff_q.is_empty():
		var cur = ff_q.pop_front()
		fields_this_castle.append(cur)
		for nb in get_neighbors(cur):
			if ff_v.has(nb): continue
			if not hex_map.has(nb): continue
			if territory_map.get(nb, 0) != old_team: continue
			if castle_map.has(nb) and castle_map[nb].team == old_team: continue
			ff_v[nb] = true
			ff_q.append(nb)
	
	# ZAWSZE: usun zamek i mury przy zamku
	remove_castle_at(castle_coords)
	purge_walls_connected_to(castle_coords)
	
	# Usun jednostki old_team NA polu zamku
	if farmer_map.has(castle_coords) and farmer_map[castle_coords].team == old_team:
		remove_farmer_at(castle_coords)
	if spearman_map.has(castle_coords) and spearman_map[castle_coords].team == old_team:
		remove_spearman_at(castle_coords)
	if knight_map.has(castle_coords) and knight_map[castle_coords].team == old_team:
		remove_knight_at(castle_coords)
		spawn_bandit_at(castle_coords)
	if cavalry_map.has(castle_coords) and cavalry_map[castle_coords].team == old_team:
		remove_cavalry_at(castle_coords)
		spawn_bandit_at(castle_coords)
	
	# Pole zamku neutralne
	territory_map.erase(castle_coords)
	update_hex_color(castle_coords)
	castle_kingdom_id.erase(castle_coords)
	
	if has_other_castles:
		# === MULTI-CASTLE: sprawdz ktore pola sa odciete od pozostalych zamkow ===
		var still_connected: Dictionary = {}
		for oc in old_team_other_castles:
			var q2 = [oc]
			var v2 = {oc: true}
			while not q2.is_empty():
				var cur2 = q2.pop_front()
				still_connected[cur2] = true
				for nb2 in get_neighbors(cur2):
					if v2.has(nb2): continue
					if not hex_map.has(nb2): continue
					if territory_map.get(nb2, 0) != old_team: continue
					v2[nb2] = true
					q2.append(nb2)
	
		var cut_off: Array = []
		for f in fields_this_castle:
			if f == castle_coords: continue
			if not still_connected.has(f):
				cut_off.append(f)
	
		var bandit_pos_mc: Array = []
		for f in cut_off:
			if farmer_map.has(f) and farmer_map[f].team == old_team:
				remove_farmer_at(f)
			elif spearman_map.has(f) and spearman_map[f].team == old_team:
				remove_spearman_at(f)
			elif knight_map.has(f) and knight_map[f].team == old_team:
				remove_knight_at(f)
				spawn_bandit_at(f)
				bandit_pos_mc.append(f)
			elif cavalry_map.has(f) and cavalry_map[f].team == old_team:
				remove_cavalry_at(f)
				spawn_bandit_at(f)
				bandit_pos_mc.append(f)
	
		for f in cut_off:
			if territory_map.get(f, 0) == old_team:
				territory_map.erase(f)
				update_hex_color(f)
	
		if not bandit_pos_mc.is_empty():
			place_bandit_camp_near_units(bandit_pos_mc, bandit_pos_mc)
	
		_renumber_kingdoms(old_team)
		recalculate_kingdoms(old_team)
		recalculate_kingdoms(new_team)
		_redistribute_castle_gold(old_team)
		_redistribute_castle_gold(new_team)
		_update_bandit_camp_gold_labels()
		_update_castle_gold_labels()
		update_ui()
		check_victory()
		print("=== KONIEC PRZEJECIA (multi-castle) ===")
		return
	
	# === LAST CASTLE ===
	for c in fields_this_castle:
		if c != castle_coords:
			purge_walls_connected_to(c)
	
	var bandit_pos_lc: Array = []
	for c in fields_this_castle:
		if c == castle_coords: continue
		if knight_map.has(c) and knight_map[c].team == old_team:
			remove_knight_at(c)
			spawn_bandit_at(c)
			bandit_pos_lc.append(c)
		elif spearman_map.has(c) and spearman_map[c].team == old_team:
			remove_spearman_at(c)
			spawn_bandit_at(c)
			bandit_pos_lc.append(c)
		elif cavalry_map.has(c) and cavalry_map[c].team == old_team:
			remove_cavalry_at(c)
			spawn_bandit_at(c)
			bandit_pos_lc.append(c)
		elif farmer_map.has(c) and farmer_map[c].team == old_team:
			var f2 = farmer_map[c]
			f2.team = -1
			bandit_spawn_hexes[c] = true
			update_hex_color(c)
			bandit_pos_lc.append(c)
	
	if not bandit_pos_lc.is_empty():
		place_bandit_camp_near_units(bandit_pos_lc, bandit_pos_lc)
	
	for c in fields_this_castle:
		if c != castle_coords and territory_map.get(c, 0) == old_team:
			territory_map.erase(c)
			update_hex_color(c)
	
	castle_gold.erase(castle_coords)
	team_gold[old_team] = 0
	
	_renumber_kingdoms(old_team)
	recalculate_kingdoms(old_team)
	recalculate_kingdoms(new_team)
	_redistribute_castle_gold(new_team)
	_update_bandit_camp_gold_labels()
	_update_castle_gold_labels()
	update_ui()
	check_victory()
	
	if old_team == 1:
		game_over = true
		if has_meta("defeat_popup"):
			var dp2 = get_meta("defeat_popup")
			await get_tree().create_timer(0.4).timeout
			dp2.show_defeat(current_level_number)
	
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
	"""Przeksztalca odciete terytoria.
	- Knight/Cavalry -> bandyci (silne jednostki przeżywają jako wolne oddziały)
	- Farmer/Spearman -> znikają (słabe jednostki nie przeżywają odcięcia)
	- Pola pozostają u właściciela ale odcięte (brak dochodu do czasu połączenia)
	"""
	var original_team = territory_map.get(hex_coords, 0)
	if original_team <= 0:
		return
	
	# Zbierz wszystkie odciete pola tego samego terytorium
	var isolated_territories = get_isolated_region(hex_coords, original_team)
	
	print("=== KONWERSJA PO ODCIĘCIU ===")
	print("Odciete pola: ", isolated_territories.size())
	
	# Kategoryzuj jednostki
	var strong_units = []   # knight, cavalry -> bandyci
	var weak_units = []     # farmer, spearman -> znikają
	
	for coords in isolated_territories:
		if knight_map.has(coords):
			strong_units.append(coords)
		elif cavalry_map.has(coords):
			strong_units.append(coords)
		elif spearman_map.has(coords):
			weak_units.append(coords)
		elif farmer_map.has(coords):
			weak_units.append(coords)
	
	print("Silnych (->bandyci): ", strong_units.size(), " | Słabych (->znikają): ", weak_units.size())
	
	# Słabe jednostki po prostu znikają
	for coords in weak_units:
		if spearman_map.has(coords):
			print("Spearman na ", coords, " ginie po odcięciu")
			remove_spearman_at(coords)
		elif farmer_map.has(coords):
			print("Farmer na ", coords, " ginie po odcięciu")
			var farmer = farmer_map[coords]
			farmer.queue_free()
			farmer_map.erase(coords)
	
	# Silne jednostki (knight/cavalry) stają się bandytami
	var bandit_positions = []
	for coords in strong_units:
		if knight_map.has(coords):
			remove_knight_at(coords)
			spawn_bandit_at(coords)
			bandit_positions.append(coords)
		elif cavalry_map.has(coords):
			remove_cavalry_at(coords)
			spawn_bandit_at(coords)
			bandit_positions.append(coords)
	
	# Usuń walle TYLKO z pól które stały się bandyckie
	# Odcięte pola królestwa (bez jednostek) ZACHOWUJĄ swoje mury
	for coords in bandit_positions:
		for edge_index in range(6):
			var edge_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
			if wall_map.has(edge_key):
				wall_map.erase(edge_key)
				if has_meta("wall_lines"):
					var wall_lines = get_meta("wall_lines")
					if wall_lines.has(edge_key):
						wall_lines[edge_key].queue_free()
						wall_lines.erase(edge_key)
	
	# Obóz tylko jeśli są bandyci
	if not bandit_positions.is_empty():
		var camp_placed = place_bandit_camp_near_units(bandit_positions, bandit_positions)
		if not camp_placed:
			print("UWAGA: Nie znaleziono miejsca na obóz bandytów!")
	
	print("=== KONIEC KONWERSJI ===")
	print("Bandytów: ", bandit_positions.size(), " | Odcięte pola: ", isolated_territories.size())
	
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
				if not territory_map.has(neighbor):
					adjacent_hexes.append(neighbor)
					break
			if not adjacent_hexes.is_empty():
				break
	
	if adjacent_hexes.is_empty():
		for coords in available_territories:
			var hex = get_hex_at(coords)
			if hex and hex.occupied_object == null:
				adjacent_hexes.append(coords)
				break
	
	if adjacent_hexes.is_empty():
		print("BLAD: Nie znaleziono miejsca na oboz bandytow!")
		return false
	
	var camp_pos = adjacent_hexes[0]
	
	# NOWE: Sprawdź czy w promieniu 4 hexów nie ma już innego obozu bandytów
	var too_close_to_camp = false
	for existing_camp_pos in castle_map:
		var castle = castle_map[existing_camp_pos]
		if castle.team == BANDIT_TEAM:
			var dist = hex_distance(camp_pos, existing_camp_pos)
			if dist <= 4:
				print("Oboz za blisko innego obozu (odleglosc: %d) - pomijam" % dist)
				too_close_to_camp = true
				break
	
	if too_close_to_camp:
		return false
	
	var castle = CASTLE_SCENE.instantiate()
	castle.team = -1
	castle.hex_position = camp_pos
	castle.position = get_hex_at(camp_pos).position
	castle.modulate = Color.WHITE  # Sprite zamku zawsze biały
	
	# ===== NOWE: Przypisz unikalne ID obozowi =====
	var camp_id = next_bandit_camp_id
	next_bandit_camp_id += 1
	castle.set_meta("camp_id", camp_id)
	
	add_child(castle)
	
	castle_map[camp_pos] = castle
	get_hex_at(camp_pos).place_object(castle)
	
	territory_map[camp_pos] = -2
	update_hex_color(camp_pos)
	
	# ===== NOWE: Zapisz jednostki należące do tego obozu =====
	bandit_camp_ownership[camp_id] = units_positions.duplicate()
	for unit_pos in units_positions:
		unit_to_camp[unit_pos] = camp_id
	
	# Inicjalizuj złoto obozu na 10
	bandit_camp_gold[camp_id] = 10
	_set_bandit_camp_gold_label(castle, 10)
	
	print("Utworzono oboz bandytow ID:", camp_id, " na:", camp_pos)
	print("Przypisano ", units_positions.size(), " jednostek do obozu")
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
	var connected = get_connected_territories_for_unit(cavalry_pos, team)
	var connected_set = {}
	for c in connected:
		connected_set[c] = true
	
	# Własne POŁĄCZONE terytoria
	for coords in connected:
		if coords == cavalry_pos:
			continue
		var hex = get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[team].lightened(0.3))
			highlighted_hexes.append(hex)
		elif hex.occupied_object is Farmer and (hex.occupied_object as Farmer).team == BANDIT_TEAM:
			hex.highlight(BANDIT_COLOR.lightened(0.5))
			highlighted_hexes.append(hex)
	
	# Sąsiedzi POŁĄCZONEGO terytorium
	var neighbors_of_team = []
	for coords in connected:
		for neighbor in get_neighbors(coords):
			if neighbor not in neighbors_of_team and not connected_set.has(neighbor):
				neighbors_of_team.append(neighbor)
	
	# Obozy bandytów i jednostki bandytów (poza terytorium)
	for coords in neighbors_of_team:
		if castle_map.has(coords):
			var castle = castle_map[coords]
			if castle.team == -1:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(BANDIT_CAMP_COLOR.lightened(0.4))
					highlighted_hexes.append(hex)
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object != null:
			var unit = hex.occupied_object
			if (unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry) and unit.team == -1:
				hex.highlight(BANDIT_COLOR.lightened(0.5))
				highlighted_hexes.append(hex)
	
	# Granica POŁĄCZONEGO terytorium
	var border_hexes = get_border_of_connected_territories(team, connected)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		if hex.occupied_object != null:
			var unit = hex.occupied_object
			if unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry:
				if unit.team != team and unit.team > 0 and unit.team <= 4:
					if unit is Cavalry:
						var wall_count = 0
						for neighbor in get_neighbors(coords):
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
	var connected = get_connected_territories_for_unit(spearman_pos, team)
	
	# Własne POŁĄCZONE terytoria
	for coords in connected:
		if coords == spearman_pos:
			continue
		var hex = get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[team].lightened(0.3))
			highlighted_hexes.append(hex)
		elif hex.occupied_object is Farmer and (hex.occupied_object as Farmer).team == BANDIT_TEAM:
			hex.highlight(BANDIT_COLOR.lightened(0.5))
			highlighted_hexes.append(hex)
	
	# Granica POŁĄCZONEGO terytorium
	var border_hexes = get_border_of_connected_territories(team, connected)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		
		# NOWA MECHANIKA: pole blokuje tylko 6/6 pełnych murów
		# Przy mniejszej liczbie murów - spearman może wejść lub zniszczyć
		var neighbors = get_neighbors(coords)
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
				# Nowa mechanika: spearman może zniszczyć mury z farmerem/spearmanem
				var wc = count_walls_around(coords)
				if wc < 6:
					highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
					hex.highlight(highlight_color)
					highlighted_hexes.append(hex)
				else:
					# Mury pełne - sprawdź czy możemy je zniszczyć
					var attacker_power = get_attacker_wall_power(selected_unit)
					var defense = get_unit_wall_defense(unit)
					if attacker_power >= defense and attacker_power > 0:
						# Pokaż jako "możliwe zniszczenie murów" - lekko przyciemnione
						hex.highlight(TEAM_COLORS[int(unit.team)].lightened(0.3).darkened(0.3))
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
	"""Rycerz: połączone terytoria (rozjaśnione) + granica połączonego terytorium"""
	var connected = get_connected_territories_for_unit(knight_pos, team)
	var connected_set = {}
	for c in connected:
		connected_set[c] = true
	
	# Własne POŁĄCZONE terytoria
	for coords in connected:
		if coords == knight_pos:
			continue
		var hex = get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[team].lightened(0.3))
			highlighted_hexes.append(hex)
		elif hex.occupied_object is Farmer and (hex.occupied_object as Farmer).team == BANDIT_TEAM:
			hex.highlight(BANDIT_COLOR.lightened(0.5))
			highlighted_hexes.append(hex)
	
	# Sąsiedzi POŁĄCZONEGO terytorium
	var neighbors_of_team = []
	for coords in connected:
		for neighbor in get_neighbors(coords):
			if neighbor not in neighbors_of_team and not connected_set.has(neighbor):
				neighbors_of_team.append(neighbor)
	
	# Obozy bandytów i jednostki bandytów
	for coords in neighbors_of_team:
		if castle_map.has(coords):
			var castle = castle_map[coords]
			if castle.team == -1:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(BANDIT_CAMP_COLOR.lightened(0.4))
					highlighted_hexes.append(hex)
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object != null:
			var unit = hex.occupied_object
			if (unit is Knight or unit is Farmer) and unit.team == -1:
				hex.highlight(BANDIT_COLOR.lightened(0.5))
				highlighted_hexes.append(hex)
	
	# Granica POŁĄCZONEGO terytorium
	var border_hexes = get_border_of_connected_territories(team, connected)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		var owner = territory_map.get(coords, 0)
		var highlight_color = HIGHLIGHT_COLOR_CAPTURE
		if owner > 0 and owner <= 4 and owner != team:
			highlight_color = TEAM_COLORS[int(owner)].lightened(0.3)
		if hex.occupied_object != null:
			var unit = hex.occupied_object
			if unit is Knight or unit is Farmer or unit is Spearman or unit is Cavalry:
				if unit.team != team and unit.team > 0 and unit.team <= 4:
					if unit is Cavalry:
						continue
					# Nowa mechanika murów: pokaż czy możemy zniszczyć mury
					var wc = count_walls_around(coords)
					if wc < 6:
						highlight_color = TEAM_COLORS[int(unit.team)].lightened(0.3)
						hex.highlight(highlight_color)
						highlighted_hexes.append(hex)
					else:
						var attacker_power = get_attacker_wall_power(selected_unit)
						var defense = get_unit_wall_defense(unit)
						if attacker_power >= defense and attacker_power > 0:
							# Możemy zniszczyć mury - pokaż przyciemnione (zajmie turę)
							hex.highlight(TEAM_COLORS[int(unit.team)].lightened(0.3).darkened(0.3))
							highlighted_hexes.append(hex)
					continue
		hex.highlight(highlight_color)
		highlighted_hexes.append(hex)
	
	for coords in knight_map:
		if coords == knight_pos:
			continue
		var other_knight = knight_map[coords]
		if other_knight.team == team:
			var hex = get_hex_at(coords)
			if hex and connected_set.has(coords):  # Tylko połączone
				hex.highlight(Color("#10B981"))
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
	
	# WLASNE POŁĄCZONE TERYTORIA - farmer moze sie swobodnie poruszac
	var connected = get_connected_territories_for_unit(farmer_pos, team)
	var connected_set = {}
	for c in connected:
		connected_set[c] = true
	
	# Jeśli farmer jest na odciętym polu - brak podświetleń
	if not connected_set.has(farmer_pos):
		return
	
	for coords in connected:
		if coords == farmer_pos:
			continue
		var hex = get_hex_at(coords)
		if hex and hex.occupied_object == null:
			hex.highlight(TEAM_COLORS[team].lightened(0.3))
			highlighted_hexes.append(hex)
			
	for coords in farmer_map:
		if coords == farmer_pos:
			continue
		var other_farmer = farmer_map[coords]
		if other_farmer.team == team and connected_set.has(coords):
			var hex = get_hex_at(coords)
			if hex:
				hex.highlight(Color("#10B981"))
				highlighted_hexes.append(hex)
	
	# GRANICA - tylko połączonego terytorium
	var border_hexes = get_border_of_connected_territories(team, connected)
	for coords in border_hexes:
		var hex = get_hex_at(coords)
		if not hex or hex.occupied_object != null:
			continue
		
		# Tylko 6/6 pełnych murów blokuje ruch farmera
		if count_walls_around(coords) >= 6:
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
	
	# Aktualizuj wybrane królestwo dla UI - dla każdego teamu (podgląd)
	var kid = hex_kingdom_map.get(clicked_pos, 0)
	if kid > 0:
		var hex_team = territory_map.get(clicked_pos, 0)
		if hex_team > 0 and hex_team <= 4:
			selected_kingdom_per_team[hex_team] = kid
		update_ui()
	
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
		if count_walls_around(clicked_pos) >= 6:
			return
		var obj = hex.occupied_object
		if obj != null and is_instance_valid(obj) and obj is Farmer and obj.team == current_team:
			if team_gold[current_team] >= FARMER_COST:
				team_gold[current_team] -= FARMER_COST
				_redistribute_castle_gold(current_team); _update_castle_gold_labels()
				var t = obj.team
				remove_farmer_at(clicked_pos)
				place_spearman_at(clicked_pos, t)
				var sp = spearman_map.get(clicked_pos)
				if sp: units_moved_this_turn.append(sp)
				capture_territory(clicked_pos, current_team)
				buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
				if ui_manager: ui_manager.reset_all_buy_buttons()
				get_node("/root/Main").play_put_sound()
		elif obj == null and team_gold[current_team] >= FARMER_COST:
			get_node("/root/Main").play_put_sound()
			place_farmer_at(clicked_pos, current_team)
			var f = farmer_map.get(clicked_pos)
			if f: units_moved_this_turn.append(f)
			team_gold[current_team] -= FARMER_COST
			_redistribute_castle_gold(current_team); _update_castle_gold_labels()
			capture_territory(clicked_pos, current_team)
			buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
			if ui_manager: ui_manager.reset_all_buy_buttons()
		return

	if buy_mode == "spearman" and hex in highlighted_hexes:
		if count_walls_around(clicked_pos) >= 6:
			return
		var obj = hex.occupied_object
		if obj != null and is_instance_valid(obj) and obj is Spearman and obj.team == current_team:
			if team_gold[current_team] >= SPEARMAN_COST:
				team_gold[current_team] -= SPEARMAN_COST
				_redistribute_castle_gold(current_team); _update_castle_gold_labels()
				var t = obj.team
				remove_spearman_at(clicked_pos)
				place_knight_at(clicked_pos, t)
				var kn = knight_map.get(clicked_pos)
				if kn: units_moved_this_turn.append(kn)
				capture_territory(clicked_pos, current_team)
				buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
				if ui_manager: ui_manager.reset_all_buy_buttons()
				get_node("/root/Main").play_put_sound()
			return
		if obj != null and is_instance_valid(obj) and not is_friendly_unit(obj):
			if team_gold[current_team] >= SPEARMAN_COST:
				if _buy_attack(clicked_pos, "spearman"): return
		if obj == null and team_gold[current_team] >= SPEARMAN_COST:
			get_node("/root/Main").play_put_sound()
			place_spearman_at(clicked_pos, current_team)
			var sp = spearman_map.get(clicked_pos)
			if sp: units_moved_this_turn.append(sp)
			team_gold[current_team] -= SPEARMAN_COST
			_redistribute_castle_gold(current_team); _update_castle_gold_labels()
			capture_territory(clicked_pos, current_team)
			buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
			if ui_manager: ui_manager.reset_all_buy_buttons()
		return

	if buy_mode == "cavalry" and hex in highlighted_hexes:
		if count_walls_around(clicked_pos) >= 6:
			return
		var obj = hex.occupied_object
		if obj != null and is_instance_valid(obj) and not is_friendly_unit(obj):
			if team_gold[current_team] >= CAVALRY_COST:
				if _buy_attack(clicked_pos, "cavalry"): return
		if obj == null and team_gold[current_team] >= CAVALRY_COST:
			get_node("/root/Main").play_put_sound()
			place_cavalry_at(clicked_pos, current_team)
			team_gold[current_team] -= CAVALRY_COST
			_redistribute_castle_gold(current_team); _update_castle_gold_labels()
			capture_territory(clicked_pos, current_team)
			buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
			if ui_manager: ui_manager.reset_all_buy_buttons()
		return

	if buy_mode == "knight" and hex in highlighted_hexes:
		if count_walls_around(clicked_pos) >= 6:
			return
		var obj = hex.occupied_object
		if obj != null and is_instance_valid(obj) and obj is Knight and obj.team == current_team:
			if team_gold[current_team] >= KNIGHT_COST:
				team_gold[current_team] -= KNIGHT_COST
				_redistribute_castle_gold(current_team); _update_castle_gold_labels()
				var t = obj.team
				remove_knight_at(clicked_pos)
				place_cavalry_at(clicked_pos, t)
				capture_territory(clicked_pos, current_team)
				buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
				if ui_manager: ui_manager.reset_all_buy_buttons()
				get_node("/root/Main").play_put_sound()
			return
		if obj != null and is_instance_valid(obj) and not is_friendly_unit(obj):
			if team_gold[current_team] >= KNIGHT_COST:
				if _buy_attack(clicked_pos, "knight"): return
		if team_gold[current_team] >= KNIGHT_COST:
			get_node("/root/Main").play_put_sound()
			if obj != null and is_instance_valid(obj):
				if knight_map.has(clicked_pos): remove_knight_at(clicked_pos)
				elif farmer_map.has(clicked_pos): remove_farmer_at(clicked_pos)
			place_knight_at(clicked_pos, current_team)
			var kn = knight_map.get(clicked_pos)
			if kn: units_moved_this_turn.append(kn)
			team_gold[current_team] -= KNIGHT_COST
			_redistribute_castle_gold(current_team); _update_castle_gold_labels()
			capture_territory(clicked_pos, current_team)
			buy_mode = ""; clear_highlights(); update_ui(); pulse_available_units()
			if ui_manager: ui_manager.reset_all_buy_buttons()
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
	if buy_mode != "":
		if knight.team != current_team:
			return
		_cancel_buy_mode()
		# Kontynuuj normalnie poniżej
	
	# Aktualizuj wybrane królestwo dla UI
	var kid_kn = hex_kingdom_map.get(knight.hex_position, 0)
	if kid_kn > 0 and knight.team > 0 and knight.team <= 4:
		selected_kingdom_per_team[knight.team] = kid_kn
		update_ui()
	if selected_unit and selected_unit is Knight and selected_unit != knight:
		if knight.team == selected_unit.team:
			merge_knights_to_cavalry(selected_unit.hex_position, knight.hex_position)
			return
		else:
			get_node("/root/Main").play_select_sound()
	
	# === Reszta bez zmian ===
	if knight.team != current_team:
		return
	
	if knight in units_moved_this_turn:
		print("Ta jednostka już się ruszyła w tej turze")
		return
	
	get_node("/root/Main").play_select_sound()
	
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
	# Anuluj buy mode i pozwól na normalny ruch
	if buy_mode != "":
		if farmer.team != current_team:
			return
		_cancel_buy_mode()
		# Kontynuuj normalnie poniżej
	
	# Aktualizuj wybrane królestwo dla UI
	var kid_fm = hex_kingdom_map.get(farmer.hex_position, 0)
	if kid_fm > 0 and farmer.team > 0 and farmer.team <= 4:
		selected_kingdom_per_team[farmer.team] = kid_fm
		update_ui()
	if selected_unit and selected_unit is Farmer and selected_unit != farmer:
		if farmer.team == selected_unit.team:
			merge_farmers_to_spearman(selected_unit.hex_position, farmer.hex_position)
			return
		else:
			get_node("/root/Main").play_select_sound()
	
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
		
	get_node("/root/Main").play_select_sound()
	
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
	# Aktualizuj wybrane królestwo dla UI - użyj hex_kingdom_map który jest zawsze aktualny
	var pos = castle.hex_position
	var kid = hex_kingdom_map.get(pos, castle_kingdom_id.get(pos, 0))
	# Aktualizuj selected_kingdom dla klikniętego teamu (gracz i wróg - tylko do podglądu)
	if kid > 0 and castle.team > 0 and castle.team <= 4:
		selected_kingdom_per_team[castle.team] = kid
	update_ui()

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
		"walls": [],
		"castle_kingdom_ids": {}
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
		# Zapisz kingdom ID zamku
		if castle_kingdom_id.has(coords):
			var key = "%d,%d" % [coords.x, coords.y]
			data["castle_kingdom_ids"][key] = castle_kingdom_id[coords]
	
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
		"walls": [],
		"castle_kingdom_ids": {}
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
		# Zapisz kingdom ID zamku
		if castle_kingdom_id.has(coords):
			var key = "%d,%d" % [coords.x, coords.y]
			data["castle_kingdom_ids"][key] = castle_kingdom_id[coords]
	
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
		# Sprawdź czy mamy zapisane kingdom ID dla tego zamku
		var forced_kid = -1
		if data.has("castle_kingdom_ids"):
			var key = "%d,%d" % [coords.x, coords.y]
			if data["castle_kingdom_ids"].has(key):
				forced_kid = int(data["castle_kingdom_ids"][key])
		place_castle_at(coords, castle_data["team"], forced_kid)
	
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
	
	# Przelicz królestwa dla wszystkich drużyn
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	
	current_round = 1
	update_ui()
	print("✓ Wczytano uklad")
	if turn_history:
		turn_history.reset_rewinds()
	return true

func load_layout_from_file(file_name: String) -> bool:
	"""Loads layout from a specific file (for level loading)"""
	# Reset game_over flag when loading new level
	game_over = false
	
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
		var forced_kid = -1
		if data.has("castle_kingdom_ids"):
			var key = "%d,%d" % [coords.x, coords.y]
			if data["castle_kingdom_ids"].has(key):
				forced_kid = int(data["castle_kingdom_ids"][key])
		place_castle_at(coords, castle_data["team"], forced_kid)
	
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
	
	# Przelicz królestwa dla wszystkich drużyn
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	# Upewnij się że kingdom IDs są unikalne per team (naprawia stare pliki)
	_ensure_unique_kingdom_ids()
	for t in [1, 2, 3, 4]:
		recalculate_kingdoms(t)
	
	# Store the current level file
	current_level_file = file_name
	set_meta("current_level_file", file_name)
	
	current_round = 1
	current_team = 1
	units_moved_this_turn.clear()
	cavalry_moves_this_turn.clear()
	
	team_gold = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	castle_gold = {}
	for coords in castle_map:
		var t = castle_map[coords].team
		if t > 0 and t <= 4:
			team_gold[t] = team_gold.get(t, 0) + 8
	for t in [1, 2, 3, 4]:
		_redistribute_castle_gold(t)
	team_territory_count = {1: 0, 2: 0, 3: 0, 4: 0}
	# Inicjalizuj selected_kingdom_per_team na najniższy aktywny kid per team
	for t in [1, 2, 3, 4]:
		var min_kid_ll = 0
		for coords in castle_kingdom_id:
			if castle_map.has(coords) and castle_map[coords].team == t:
				var k = castle_kingdom_id[coords]
				if k > 0 and (min_kid_ll == 0 or k < min_kid_ll):
					min_kid_ll = k
		if min_kid_ll > 0:
			selected_kingdom_per_team[t] = min_kid_ll
	
	if selected_unit:
		clear_selected_unit_highlight()
		selected_unit = null
	buy_mode = ""
	merge_mode = false
	wall_placement_mode = false
	wall_hexes_selected.clear()
	clear_highlights()
	
	update_territory_counts()
	
	# Reset game state
	current_round = 1
	units_moved_this_turn.clear()
	cavalry_moves_this_turn.clear()
	
	# Poczekaj żeby zamki były gotowe przed rysowaniem etykiet złota
	await get_tree().process_frame
	_update_castle_gold_labels()
	update_ui()
	
	# WAŻNE: Odblokuj przyciski po wczytaniu poziomu (dla retry)
	if ui_manager:
		ui_manager.set_buttons_enabled(true)
	
	print("✓ Wczytano poziom z: ", full_path)
	
	if turn_history:
		turn_history.reset_rewinds()
		turn_history.save_turn_snapshot(self)
	
	return true

func is_friendly_unit(obj) -> bool:
	"""Sprawdza czy obiekt jest własną jednostką"""
	if obj == null:
		return false
	if obj.has_method("get"):
		var team_val = obj.get("team")
		if team_val != null:
			return team_val == current_team
	return false

func _buy_attack(target_pos: Vector2i, unit_type: String) -> bool:
	"""W trybie zakupu: kup jednostkę i od razu zaatakuj/zastąp wrogą jednostkę/obóz.
	Zwraca true jeśli atak się powiódł."""
	var hex = get_hex_at(target_pos)
	if not hex:
		return false
	var obj = hex.occupied_object
	if obj == null:
		return false
	
	var cost = 0
	match unit_type:
		"farmer":   cost = FARMER_COST
		"spearman": cost = SPEARMAN_COST
		"knight":   cost = KNIGHT_COST
		"cavalry":  cost = CAVALRY_COST
	
	if team_gold[current_team] < cost:
		return false
	
	# Sprawdź czy możemy zaatakować tę jednostkę tym typem
	var can_attack = false
	if obj is Farmer and obj.team != current_team:
		can_attack = unit_type in ["farmer", "spearman", "knight", "cavalry"]
	elif obj is Spearman and obj.team != current_team:
		can_attack = unit_type in ["spearman", "knight", "cavalry"]
	elif obj is Knight and obj.team != current_team:
		can_attack = unit_type in ["knight", "cavalry"]
	elif obj is Cavalry and obj.team != current_team:
		can_attack = unit_type == "cavalry"
	elif obj is Castle:
		var castle = obj as Castle
		if castle.team == BANDIT_TEAM:
			can_attack = unit_type in ["spearman", "knight", "cavalry"]
		elif castle.team != current_team and castle.team > 0:
			can_attack = unit_type in ["spearman", "knight", "cavalry"]
	
	if not can_attack:
		return false
	
	get_node("/root/Main").play_put_sound()
	
	# Usuń wrogą jednostkę (zamki obsługujemy przez capture)
	if obj is Farmer:
		remove_farmer_at(target_pos)
	elif obj is Spearman:
		remove_spearman_at(target_pos)
	elif obj is Knight:
		remove_knight_at(target_pos)
	elif obj is Cavalry:
		remove_cavalry_at(target_pos)
	elif obj is Castle:
		var castle = obj as Castle
		if castle.team == BANDIT_TEAM:
			# Przejęcie obozu bandytów
			team_gold[current_team] += BANDIT_CAMP_REWARD
			var camp_id = castle.get_meta("camp_id", -1)
			remove_castle_at(target_pos)
			if camp_id > 0:
				bandit_camp_ownership.erase(camp_id)
		else:
			capture_castle(target_pos, current_team, castle.team)
	
	# Postaw swoją jednostkę
	match unit_type:
		"farmer":   place_farmer_at(target_pos, current_team)
		"spearman": place_spearman_at(target_pos, current_team)
		"knight":   place_knight_at(target_pos, current_team)
		"cavalry":  place_cavalry_at(target_pos, current_team)
	
	# Oznacz jako ruszaną
	match unit_type:
		"farmer":
			if farmer_map.has(target_pos): units_moved_this_turn.append(farmer_map[target_pos])
		"spearman":
			if spearman_map.has(target_pos): units_moved_this_turn.append(spearman_map[target_pos])
		"knight":
			if knight_map.has(target_pos): units_moved_this_turn.append(knight_map[target_pos])
		"cavalry":
			if cavalry_map.has(target_pos): units_moved_this_turn.append(cavalry_map[target_pos])
	
	team_gold[current_team] -= cost
	_redistribute_castle_gold(current_team)
	_update_castle_gold_labels()
	capture_territory(target_pos, current_team)
	buy_mode = ""
	clear_highlights()
	update_ui()
	pulse_available_units()
	return true

func _highlight_merge_targets_for(farmer_unit: Farmer):
	"""Podświetl sąsiadów farmerów dla merge (zielone)"""
	for nb in get_neighbors(farmer_unit.hex_position):
		if farmer_map.has(nb) and farmer_map[nb].team == current_team:
			var hex = get_hex_at(nb)
			if hex:
				hex.highlight(Color("#10B981"))
				highlighted_hexes.append(hex)

func _highlight_merge_targets_for_knight(knight_unit: Knight):
	"""Podświetl sąsiadów knightów dla merge (zielone)"""
	for nb in get_neighbors(knight_unit.hex_position):
		if knight_map.has(nb) and knight_map[nb].team == current_team:
			var hex = get_hex_at(nb)
			if hex:
				hex.highlight(Color("#10B981"))
				highlighted_hexes.append(hex)

func _get_buy_mode_highlighted_hexes(unit_type: String) -> Array:
	"""Zwraca listę hexów które powinny być podświetlone dla danego trybu zakupu.
	
	Zasady:
	- Własne puste pola połączone z zamkiem: TAK (zielone)
	- Granica (neutralne/wrogie puste): TAK (pomarańczowe/kolor wroga)
	- Wrogie jednostki na granicy (farmer/spearman gdy kupujemy unit zdolny do ataku): TAK
	- Obozy bandytów na granicy: TAK
	- Pola z murami (6/6): NIE (trzeba najpierw zniszczyć mury)
	"""
	var result = []
	var connected = get_connected_territories(current_team)
	var connected_set = {}
	for c in connected:
		connected_set[c] = true
	
	# Własne puste pola (bez murów)
	for coords in connected:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object != null:
			continue  # zajęte
		if count_walls_around(coords) >= 6:
			continue  # mury - nie można postawić
		result.append({
			"hex": hex,
			"coords": coords,
			"color": TEAM_COLORS[current_team].lightened(0.3),
			"type": "own"
		})
	
	# Granica
	var border = get_border_of_connected_territories(current_team, connected)
	for coords in border:
		var hex = get_hex_at(coords)
		if not hex:
			continue
		if count_walls_around(coords) >= 6:
			continue  # mury blokują
		
		var owner = territory_map.get(coords, 0)
		var obj = hex.occupied_object
		
		if obj == null:
			# Puste pole na granicy
			var col = HIGHLIGHT_COLOR_CAPTURE
			if owner > 0 and owner <= 4 and owner != current_team:
				col = TEAM_COLORS[int(owner)].lightened(0.3)
			result.append({"hex": hex, "coords": coords, "color": col, "type": "border_empty"})
		
		elif obj is Castle:
			# Obóz bandytów lub wrogi zamek
			var castle = obj as Castle
			if castle.team == BANDIT_TEAM:
				# Obozy bandytów - wszystkie jednostki mogą atakować
				result.append({"hex": hex, "coords": coords, "color": BANDIT_CAMP_COLOR.lightened(0.4), "type": "bandit_camp"})
			elif castle.team != current_team and castle.team > 0:
				match unit_type:
					"knight", "cavalry", "spearman":
						result.append({"hex": hex, "coords": coords, "color": TEAM_COLORS[int(castle.team)].lightened(0.3), "type": "enemy_castle"})
		
		elif obj is Farmer:
			var farmer_u = obj as Farmer
			if farmer_u.team == BANDIT_TEAM:
				# Bandyta na granicy - wszystkie jednostki mogą
				result.append({"hex": hex, "coords": coords, "color": BANDIT_COLOR.lightened(0.3), "type": "bandit"})
			elif farmer_u.team != current_team and farmer_u.team > 0:
				match unit_type:
					"farmer", "spearman", "knight", "cavalry":
						result.append({"hex": hex, "coords": coords, "color": TEAM_COLORS[int(farmer_u.team)].lightened(0.3), "type": "enemy_farmer"})
		
		elif obj is Spearman:
			var spear_u = obj as Spearman
			if spear_u.team == BANDIT_TEAM:
				result.append({"hex": hex, "coords": coords, "color": BANDIT_COLOR.lightened(0.3), "type": "bandit"})
			elif spear_u.team != current_team and spear_u.team > 0:
				match unit_type:
					"spearman", "knight", "cavalry":
						result.append({"hex": hex, "coords": coords, "color": TEAM_COLORS[int(spear_u.team)].lightened(0.3), "type": "enemy_spearman"})
		
		elif obj is Knight:
			var knight_u = obj as Knight
			if knight_u.team == BANDIT_TEAM:
				result.append({"hex": hex, "coords": coords, "color": BANDIT_COLOR.lightened(0.3), "type": "bandit"})
			elif knight_u.team != current_team and knight_u.team > 0:
				match unit_type:
					"knight", "cavalry":
						result.append({"hex": hex, "coords": coords, "color": TEAM_COLORS[int(knight_u.team)].lightened(0.3), "type": "enemy_knight"})
		
		elif obj is Cavalry:
			var cav_u = obj as Cavalry
			if cav_u.team != current_team and cav_u.team > 0:
				if unit_type == "cavalry":
					result.append({"hex": hex, "coords": coords, "color": TEAM_COLORS[int(cav_u.team)].lightened(0.3), "type": "enemy_cavalry"})
	
	return result

func _apply_buy_mode_highlights(unit_type: String):
	"""Podświetla pola w trybie zakupu + własne jednostki do mergu (zielono)"""
	clear_highlights()
	clear_unit_pulses()
	
	var hex_list = _get_buy_mode_highlighted_hexes(unit_type)
	for entry in hex_list:
		entry.hex.highlight(entry.color)
		highlighted_hexes.append(entry.hex)
	
	if unit_type == "farmer":
		for coords in farmer_map:
			var u = farmer_map[coords]
			if is_instance_valid(u) and u.team == current_team:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(Color("#10B981"))
					if hex not in highlighted_hexes:
						highlighted_hexes.append(hex)
	elif unit_type == "spearman":
		for coords in spearman_map:
			var u = spearman_map[coords]
			if is_instance_valid(u) and u.team == current_team:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(Color("#10B981"))
					if hex not in highlighted_hexes:
						highlighted_hexes.append(hex)
	elif unit_type == "knight":
		for coords in knight_map:
			var u = knight_map[coords]
			if is_instance_valid(u) and u.team == current_team:
				var hex = get_hex_at(coords)
				if hex:
					hex.highlight(Color("#10B981"))
					if hex not in highlighted_hexes:
						highlighted_hexes.append(hex)

func _cancel_buy_mode():
	"""Anuluje tryb zakupu, czyści podświetlenia, resetuje przyciski UI"""
	if buy_mode == "":
		return
	buy_mode = ""
	merge_mode = false
	clear_highlights()
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	if ui_manager:
		ui_manager.reset_all_buy_buttons()
	update_ui()
	pulse_available_units()

func _on_buy_farmer():
	if wall_placement_mode:
		wall_placement_mode = false
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		if ui_manager:
			ui_manager.reset_wall_button()
			
	if buy_mode == "farmer":
		_cancel_buy_mode()
		return
	
	if team_gold[current_team] < FARMER_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null

	buy_mode = "farmer"
	_apply_buy_mode_highlights("farmer")
	if ui_manager: ui_manager.set_buy_button_active("farmer", true)
	
func _on_buy_cavalry():
	if wall_placement_mode:
		wall_placement_mode = false
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		if ui_manager:
			ui_manager.reset_wall_button()
			
	if buy_mode == "cavalry":
		_cancel_buy_mode()
		return
	
	if team_gold[current_team] < CAVALRY_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "cavalry"
	_apply_buy_mode_highlights("cavalry")
	if ui_manager: ui_manager.set_buy_button_active("cavalry", true)
	
func _on_buy_spearman():
	if wall_placement_mode:
		wall_placement_mode = false
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		if ui_manager:
			ui_manager.reset_wall_button()
			
	if buy_mode == "spearman":
		_cancel_buy_mode()
		return
	
	if team_gold[current_team] < SPEARMAN_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "spearman"
	_apply_buy_mode_highlights("spearman")
	if ui_manager: ui_manager.set_buy_button_active("spearman", true)

func _on_buy_knight():
	if wall_placement_mode:
		wall_placement_mode = false
		for hex_coords in wall_hexes_selected:
			remove_hex_outline(hex_coords)
		wall_hexes_selected.clear()
		if ui_manager:
			ui_manager.reset_wall_button()
			
	if buy_mode == "knight":
		_cancel_buy_mode()
		return
	
	if team_gold[current_team] < KNIGHT_COST:
		return
		
	if selected_unit:
		clear_selected_unit_highlight()
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
		selected_unit = null
	
	buy_mode = "knight"
	_apply_buy_mode_highlights("knight")
	if ui_manager: ui_manager.set_buy_button_active("knight", true)

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
		# Wygrana! Sound is now played inside victory_popup.show_victory()
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

func set_team_ai(team: int, difficulty: int, aggression: float = 0.5):
	"""Ustawia AI dla danego teamu
	difficulty: 0 = NORMAL, 1 = HARD
	aggression: 0.1-1.0 (0.1=defensywny, 0.5=zbalansowany, 1.0=agresywny)
	"""
	if not ai_controllers.has(team):
		var ai = AIController.new(self, team, difficulty, aggression)
		add_child(ai)
		ai_controllers[team] = ai
		ai_teams.append(team)
		print("AI ustawione dla drużyny %d (%s, Agresywność: %.1f)" % [team, "HARD" if difficulty == 1 else "NORMAL", aggression])

func remove_team_ai(team: int):
	"""Usuwa AI z teamu"""
	if ai_controllers.has(team):
		var ai = ai_controllers[team]
		ai.queue_free()
		ai_controllers.erase(team)
		ai_teams.erase(team)
		print("AI usunięte z drużyny %d" % team)

func spawn_farmer_at(pos: Vector2i, team_id: int):
	"""Spawuje farmera na danej pozycji"""
	var hex = get_hex_at(pos)
	if not hex or hex.occupied_object != null:
		return
	
	var farmer = FARMER_SCENE.instantiate()
	farmer.team = team_id
	farmer.hex_position = pos
	add_child(farmer)
	farmer.position = hex.position
	farmer_map[pos] = farmer
	hex.occupied_object = farmer
	
	territory_map[pos] = team_id
	hex.set_color(TEAM_COLORS[team_id])

func spawn_spearman_at(pos: Vector2i, team_id: int):
	"""Spawuje włócznika na danej pozycji"""
	var hex = get_hex_at(pos)
	if not hex or hex.occupied_object != null:
		return
	
	var spearman = SPEARMAN_SCENE.instantiate()
	spearman.team = team_id
	spearman.hex_position = pos
	add_child(spearman)
	spearman.position = hex.position
	spearman_map[pos] = spearman
	hex.occupied_object = spearman
	
	territory_map[pos] = team_id
	hex.set_color(TEAM_COLORS[team_id])

func spawn_knight_at(pos: Vector2i, team_id: int):
	"""Spawuje rycerza na danej pozycji"""
	var hex = get_hex_at(pos)
	if not hex or hex.occupied_object != null:
		return
	
	var knight = KNIGHT_SCENE.instantiate()
	knight.team = team_id
	knight.hex_position = pos
	add_child(knight)
	knight.position = hex.position
	knight_map[pos] = knight
	hex.occupied_object = knight
	
	territory_map[pos] = team_id
	hex.set_color(TEAM_COLORS[team_id])

func spawn_cavalry_at(pos: Vector2i, team_id: int):
	"""Spawuje kawalerię na danej pozycji"""
	var hex = get_hex_at(pos)
	if not hex or hex.occupied_object != null:
		return
	
	var cavalry = CAVALRY_SCENE.instantiate()
	cavalry.team = team_id
	cavalry.hex_position = pos
	add_child(cavalry)
	cavalry.position = hex.position
	cavalry_map[pos] = cavalry
	hex.occupied_object = cavalry
	
	territory_map[pos] = team_id
	hex.set_color(TEAM_COLORS[team_id])

func place_bandit_camp_on_nearest_neutral(unit_pos: Vector2i) -> bool:
	"""Stawia obóz bandytów na najbliższym wolnym neutralnym hexie od jednostki.
	   Używane gdy bandyta spawnuje bez istniejącego obozu."""
	# Jeśli jest już obóz w pobliżu - przypisz do niego
	var existing_id = find_nearest_bandit_camp(unit_pos)
	if existing_id > 0:
		unit_to_camp[unit_pos] = existing_id
		if not bandit_camp_ownership.has(existing_id):
			bandit_camp_ownership[existing_id] = []
		if unit_pos not in bandit_camp_ownership[existing_id]:
			bandit_camp_ownership[existing_id].append(unit_pos)
		print("Bandyta @ %s przypisany do istniejącego obozu #%d" % [unit_pos, existing_id])
		return true
	
	# BFS - szukaj wolnego neutralnego/bandyckiego pola
	var visited = {unit_pos: true}
	var queue = [unit_pos]
	var candidate = Vector2i.ZERO
	var searched = 0
	
	while not queue.is_empty() and searched < 40:
		var current = queue.pop_front()
		searched += 1
		for neighbor in get_neighbors(current):
			if visited.get(neighbor, false):
				continue
			visited[neighbor] = true
			if not hex_map.has(neighbor):
				continue
			var owner = territory_map.get(neighbor, 0)
			var hex = get_hex_at(neighbor)
			if hex and hex.occupied_object == null and (owner == 0 or owner == BANDIT_TEAM):
				candidate = neighbor
				break
			queue.append(neighbor)
		if candidate != Vector2i.ZERO:
			break
	
	if candidate == Vector2i.ZERO:
		print("Bandyta @ %s: brak miejsca na nowy obóz" % unit_pos)
		return false
	
	# Sprawdź odległość od istniejących obozów
	for ep in castle_map:
		if castle_map[ep].team == BANDIT_TEAM and hex_distance(candidate, ep) <= 3:
			if castle_map[ep].has_meta("camp_id"):
				var cid = castle_map[ep].get_meta("camp_id")
				unit_to_camp[unit_pos] = cid
				if not bandit_camp_ownership.has(cid):
					bandit_camp_ownership[cid] = []
				if unit_pos not in bandit_camp_ownership[cid]:
					bandit_camp_ownership[cid].append(unit_pos)
				return true
	
	# Postaw nowy obóz
	var castle = CASTLE_SCENE.instantiate()
	castle.team = BANDIT_TEAM
	castle.hex_position = candidate
	castle.position = get_hex_at(candidate).position
	castle.modulate = Color.WHITE
	var camp_id = next_bandit_camp_id
	next_bandit_camp_id += 1
	castle.set_meta("camp_id", camp_id)
	add_child(castle)
	castle_map[candidate] = castle
	get_hex_at(candidate).place_object(castle)
	territory_map[candidate] = -2
	update_hex_color(candidate)
	bandit_camp_gold[camp_id] = 10  # Bazowe 10 golda
	bandit_camp_ownership[camp_id] = [unit_pos]
	unit_to_camp[unit_pos] = camp_id
	# Pokaż etykietę złota
	_set_bandit_camp_gold_label(castle, 10)
	print("✓ Nowy obóz #%d @ %s dla bandyty @ %s" % [camp_id, candidate, unit_pos])
	return true


func process_bandit_occupation_income():
	print("=== BANDYCI: przetwarzanie okupacji ===")
	
	for pos in farmer_map.keys():
		var f = farmer_map.get(pos)
		if not (is_instance_valid(f) and f.team == BANDIT_TEAM):
			continue
		var owner = territory_map.get(pos, 0)
		if owner <= 0:
			continue
		# Bandyta na polu królestwa
		var connected = get_connected_territories(owner)
		if pos not in connected:
			territory_map[pos] = 0
			update_hex_color(pos)
			print("Bandyta @ %s: odcięte pole → neutralne" % pos)
			continue
		# Pole połączone - kradnie 1 gold
		var camp_id = unit_to_camp.get(pos, -1)
		if camp_id <= 0:
			camp_id = find_nearest_bandit_camp(pos)
		if camp_id > 0:
			bandit_camp_gold[camp_id] = bandit_camp_gold.get(camp_id, 0) + 1
			print("Bandyta @ %s kradnie 1g → obóz #%d (łącznie: %d)" % [pos, camp_id, bandit_camp_gold[camp_id]])
			# Aktualizuj etykietę złota obozu
			for cpos in castle_map:
				if castle_map[cpos].team == BANDIT_TEAM and castle_map[cpos].has_meta("camp_id") and castle_map[cpos].get_meta("camp_id") == camp_id:
					_set_bandit_camp_gold_label(castle_map[cpos], bandit_camp_gold[camp_id])
					break
	
	# Obozy z wystarczającą ilością gold (min 10 + koszt spawna) → spawn bandyty
	for camp_id in bandit_camp_gold.keys():
		# Zachowaj minimum 10 gold w obozie - nie spawnuj jeśli by spadło poniżej 10
		if bandit_camp_gold.get(camp_id, 0) - 3 < 10:
			continue
		var camp_pos = Vector2i.ZERO
		for cpos in castle_map:
			if castle_map[cpos].team == BANDIT_TEAM and castle_map[cpos].has_meta("camp_id") and castle_map[cpos].get_meta("camp_id") == camp_id:
				camp_pos = cpos
				break
		if camp_pos == Vector2i.ZERO:
			bandit_camp_gold.erase(camp_id)
			continue
		var spawn_pos = Vector2i.ZERO
		for nb in get_neighbors(camp_pos):
			if not hex_map.has(nb):
				continue
			var hex = get_hex_at(nb)
			if not hex or hex.occupied_object != null:
				continue
			spawn_pos = nb
			break
		if spawn_pos == Vector2i.ZERO:
			print("Obóz #%d: brak miejsca na spawn" % camp_id)
			continue
		bandit_camp_gold[camp_id] -= 3
		place_farmer_at(spawn_pos, BANDIT_TEAM)
		var nf = farmer_map.get(spawn_pos)
		if is_instance_valid(nf):
			unit_to_camp[spawn_pos] = camp_id
			if not bandit_camp_ownership.has(camp_id):
				bandit_camp_ownership[camp_id] = []
			if spawn_pos not in bandit_camp_ownership[camp_id]:
				bandit_camp_ownership[camp_id].append(spawn_pos)
			nf.set("spawn_turn", current_round)
		bandit_spawn_hexes[spawn_pos] = true
		update_hex_color(spawn_pos)
		print("✓ Obóz #%d spawn @ %s (gold: %d)" % [camp_id, spawn_pos, bandit_camp_gold[camp_id]])


func find_nearest_bandit_camp(unit_pos: Vector2i) -> int:
	"""Znajduje najbliższy obóz bandytów dla jednostki"""
	# Jeśli nie ma obozów, zwróć 0
	var bandit_camps = []
	for coords in castle_map:
		if castle_map[coords].team == BANDIT_TEAM:
			bandit_camps.append(coords)
	
	if bandit_camps.is_empty():
		return 0
	
	var nearest_camp_pos = bandit_camps[0]
	var min_distance = hex_distance(unit_pos, nearest_camp_pos)
	
	for camp_pos in bandit_camps:
		var dist = hex_distance(unit_pos, camp_pos)
		if dist < min_distance:
			min_distance = dist
			nearest_camp_pos = camp_pos
	
	# Znajdź ID obozu
	var camp = castle_map[nearest_camp_pos]
	if camp.has_meta("camp_id"):
		return camp.get_meta("camp_id")
	
	return 0

# ============================================================================
# DEFEAT POPUP - Obsługa przycisków
# ============================================================================

func _on_defeat_rewind_2_turns():
	"""Wywoływane gdy użytkownik kliknie przycisk rewind (niebieski)"""
	print("=== DEFEAT POPUP: Rewind 2 turns ===")
	
	# Sprawdź czy mamy 2 rewindy
	var rewind_label = ui_manager.rewind_counter.get_node_or_null("RewindLabel")
	if not rewind_label:
		print("ERROR: Brak RewindLabel")
		return
	
	var current_rewinds = int(rewind_label.text)
	if current_rewinds < 2:
		print("Nie wystarczajaco rewindow: %d (potrzeba 2)" % current_rewinds)
		return
	
	# Oblicz ile tur trzeba cofnąć aby wrócić do początku ostatnich 2 PEŁNYCH rund gracza (team 1)
	var num_teams = ai_teams.size() + 1  # AI teams + gracz
	var turns_to_rewind = 2 * num_teams  # 2 rundy × liczba teamów
	
	print("Cofanie %d tur (2 rundy x %d teamów)" % [turns_to_rewind, num_teams])
	
	# Użyj nowej funkcji która cofa wiele tur naraz
	var success = await turn_history.restore_multiple_turns(self, turns_to_rewind, 2)
	
	if not success:
		print("ERROR: Nie udało się cofnąć tur!")
		return
	
	# Odśwież UI po cofnięciu
	update_ui()
	
	# WAŻNE: Resetuj game_over żeby móc grać dalej
	game_over = false
	
	# WAŻNE: Odblokuj przyciski UI
	if ui_manager:
		ui_manager.set_buttons_enabled(true)
	
	# Zamknij defeat popup
	if has_meta("defeat_popup"):
		var defeat_popup = get_meta("defeat_popup")
		if defeat_popup and defeat_popup.has_method("hide_popup"):
			defeat_popup.hide_popup()
	
	print("=== Cofnieto 2 rundy (powrot do team 1) ===")

func _on_defeat_watch_ad():
	"""Wywoływane gdy użytkownik kliknie Watch Ad"""
	print("=== DEFEAT POPUP: Watch Ad ===")
	
	# TODO: Tutaj możesz dodać logikę wyświetlania reklamy
	# Po obejrzeniu reklamy wywołaj rewind:
	_on_defeat_rewind_2_turns()
