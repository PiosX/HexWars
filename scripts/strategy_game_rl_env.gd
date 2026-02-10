extends Node
class_name StrategyGameRLEnv

## ULEPSZONA WERSJA z poprawkami:
## 1. AI wykorzystuje WSZYSTKIE jednostki w jednej turze
## 2. Cavalry ma 2 ruchy (prawidłowo zaimplementowane)
## 3. Jednostki mogą teleportować się po swoim terytorium
## 4. Nagroda za ruszenie wszystkimi jednostkami
## 5. Zespół 2 też się rusza (2 instancje RL)

# ============================================================================
# KONFIGURACJA
# ============================================================================
@export var hex_grid: HexGrid
@export var ai_team: int = 1
@export var episode_max_steps: int = 500

# Flagi kontrolne
@export var needs_reset: bool = false
@export var done: bool = false

# Liczniki i stan
var current_step: int = 0
var episode_rewards: float = 0.0
var episode_number: int = 0  # NOWE: Licznik epizodów

# Stan początkowy
var initial_state: Dictionary = {}
var current_reward: float = 0.0
var enemy_ai: AIController = null

# Śledzenie poprzedniego stanu dla lepszych nagród
var previous_territory: int = 0
var previous_enemy_territory: int = 0
var previous_units: int = 0
var previous_enemy_units: int = 0
var previous_bandit_units: int = 0  # NOWE: Tracking bandytów

# ✅ NOWE: Śledzenie jednostek które się poruszyły w tej turze
var units_moved_in_turn: Dictionary = {}  # {unit: moves_count}

# ============================================================================
# INICJALIZACJA
# ============================================================================
func _ready():
	print("🤖 RL Environment zainicjalizowane - SELF-PLAY MODE")
	print("   1 agent kontroluje obie drużyny (Team 1 i Team 2)")
	
	if not hex_grid:
		push_error("hex_grid nie jest ustawiony!")
		return
	
	await get_tree().process_frame
	# Nie tworzymy enemy_ai w self-play
	reset()

func setup_ai_opponent():
	"""
	⚠️ WYŁĄCZONE - enemy_ai NIE używamy!
	W treningu RL oba teamy są kontrolowane przez godot_rl_agents.
	"""
	print("⚠️ Enemy AI (AIController) WYŁĄCZONY - używamy 2 instancji RL")
	return

# ============================================================================
# RESET
# ============================================================================

func reset():
	print("🔄 Reset - EPIZOD nowy")
	
	episode_number += 1
	current_step = 0
	episode_rewards = 0.0
	current_reward = 0.0
	done = false
	needs_reset = false
	
	# Wczytaj poziom od nowa
	hex_grid.units_moved_this_turn.clear()
	hex_grid.cavalry_moves_this_turn.clear()
	
	if hex_grid.current_level_file != "":
		hex_grid.load_layout_from_file(hex_grid.current_level_file)
	elif not hex_grid.load_layout():
		print("Nie można wczytać - brak layoutu")
	
	hex_grid.team_gold = {1: 10, 2: 10, 3: 10, 4: 10, 5: 0, -1: 0}
	hex_grid.current_round = 1
	hex_grid.current_team = 1
	
	await get_tree().process_frame
	initial_state = generate_initial_state()
	
	previous_territory = count_territories(ai_team)
	previous_enemy_territory = count_all_enemy_territories()
	previous_units = count_my_units_total()
	previous_enemy_units = count_all_enemy_units_total()
	previous_bandit_units = count_bandit_units()
	
	print("✅ Poziom zresetowany! EPIZOD %d" % episode_number)
	print("   Team %d: %d jednostek" % [ai_team, count_my_units_total()])
	
	return get_obs()

func generate_initial_state() -> Dictionary:
	return {
		"territory": count_territories(ai_team),
		"units": count_my_units_total(),
		"gold": hex_grid.team_gold.get(ai_team, 0),
		"enemy_territory": count_all_enemy_territories(),
		"enemy_units": count_all_enemy_units_total()
	}

# ============================================================================
# OBSERWACJE
# ============================================================================

func get_obs() -> Dictionary:
	"""
	Zwraca obserwacje dla AI.
	
	WAŻNE INFO DLA AI:
	- Cavalry ma 2 ruchy na turę
	- Każda jednostka może teleportować się po swoim terytorium
	- Złoto przyznawane po zakończeniu WSZYSTKICH tur
	- Start: 10 złota
	"""
	var obs_vector = []
	
	# EKONOMIA (3)
	obs_vector.append(normalize_value(hex_grid.team_gold.get(ai_team, 0), 0, 500))
	obs_vector.append(normalize_value(hex_grid.calculate_income(ai_team), -50, 100))
	obs_vector.append(normalize_value(hex_grid.calculate_upkeep(ai_team), 0, 100))
	
	# TERYTORIUM (3)
	var my_territory = count_territories(ai_team)
	var enemy_territory = count_all_enemy_territories()
	obs_vector.append(normalize_value(my_territory, 0, 100))
	obs_vector.append(normalize_value(enemy_territory, 0, 100))
	obs_vector.append(get_territory_connectivity())
	
	# JEDNOSTKI (6)
	var my_units = count_units_by_type(ai_team)
	obs_vector.append(normalize_value(my_units.knights, 0, 20))
	obs_vector.append(normalize_value(my_units.spearmen, 0, 20))
	obs_vector.append(normalize_value(my_units.cavalry, 0, 10))
	
	var enemy_units = count_all_enemy_units()
	obs_vector.append(normalize_value(enemy_units.knights, 0, 20))
	obs_vector.append(normalize_value(enemy_units.spearmen, 0, 20))
	obs_vector.append(normalize_value(enemy_units.cavalry, 0, 10))
	
	# SYTUACJA STRATEGICZNA (5)
	obs_vector.append(float(is_castle_threatened()))
	obs_vector.append(get_border_strength_normalized())
	obs_vector.append(get_expansion_potential_normalized())
	obs_vector.append(normalize_value(count_attackable_enemies(), 0, 10))
	obs_vector.append(get_wall_coverage())
	
	# KONTEKST CZASOWY (2)
	obs_vector.append(normalize_value(current_step, 0, episode_max_steps))
	obs_vector.append(normalize_value(episode_rewards, -100, 100))
	
	# ✅ NOWE: Informacja o nieporuszonych jednostkach (1)
	var unmoved_ratio = get_unmoved_units_ratio()
	obs_vector.append(unmoved_ratio)
	
	return {"obs": obs_vector}

func get_unmoved_units_ratio() -> float:
	"""Zwraca stosunek nieporuszonych jednostek do wszystkich"""
	var total_units = count_my_units_total()
	if total_units == 0:
		return 0.0
	
	var moved_count = 0
	
	# Zlicz poruszone jednostki
	for unit in hex_grid.units_moved_this_turn:
		if is_instance_valid(unit) and unit.team == ai_team:
			moved_count += 1
	
	var unmoved = total_units - moved_count
	return float(unmoved) / float(total_units)

func get_obs_space() -> Dictionary:
	return {
		"obs": {
			"size": [21],  # Zwiększone z 20 do 21 (dodano unmoved_units_ratio)
			"space": "box"
		}
	}

# ============================================================================
# AKCJE - POPRAWIONA WERSJA
# ============================================================================

func get_action_space() -> Dictionary:
	return {
		"action": {
			"size": 10,
			"action_type": "discrete"
		}
	}

func set_action(action):
	"""
	✅ SELF-PLAY: Agent wykonuje akcję dla Team 1, potem dla Team 2
	"""
	current_step += 1
	
	# Konwersja Dictionary → int
	var action_int: int = 0
	if typeof(action) == TYPE_DICTIONARY:
		action_int = action.get("action", 0)
	elif typeof(action) == TYPE_INT:
		action_int = action
	else:
		push_error("Nieprawidłowy typ akcji: %s" % typeof(action))
		return
		
	hex_grid.units_moved_this_turn.clear()
	hex_grid.cavalry_moves_this_turn.clear()
	
	# ============================================================================
	# ✅ TURA TEAM 1
	# ============================================================================
	ai_team = 1
	var state_before_1 = {
		"gold": hex_grid.team_gold.get(1, 0),
		"territory": count_territories(1),
		"units": count_units_for_team(1),
		"enemy_units": count_units_for_team(2),
		"enemy_territory": count_territories(2),
		"has_castle": has_castle_team(1),
		"unmoved_units": get_unmoved_units_count()
	}
	
	# Wykonaj akcję dla Team 1
	execute_action_for_all_units(action_int)
	
	# Oblicz nagrodę Team 1
	var reward_1 = calculate_reward_for_team(state_before_1, 1)
	
	# ============================================================================
	# ✅ TURA TEAM 2 (ta sama akcja!)
	# ============================================================================
	ai_team = 2
	var state_before_2 = {
		"gold": hex_grid.team_gold.get(2, 0),
		"territory": count_territories(2),
		"units": count_units_for_team(2),
		"enemy_units": count_units_for_team(1),
		"enemy_territory": count_territories(1),
		"has_castle": has_castle_team(2),
		"unmoved_units": get_unmoved_units_count()
	}
	
	# Wykonaj tę samą akcję dla Team 2
	execute_action_for_all_units(action_int)
	
	# Oblicz nagrodę Team 2
	var reward_2 = calculate_reward_for_team(state_before_2, 2)
	
	# ============================================================================
	# ✅ ZŁOTO PRZYDZIELANE DOPIERO TERAZ (po obu turach)
	# ============================================================================
	distribute_gold_and_check_bankruptcy()
	
	# ============================================================================
	# ✅ NAGRODA FINALNA = Team1 minus Team2 (zero-sum game)
	# ============================================================================
	current_reward = reward_1 - reward_2
	episode_rewards += current_reward
	
	# Przywróć ai_team na 1 (dla obserwacji)
	ai_team = 1
	
	# Aktualizuj tracking
	previous_territory = count_territories(1)
	previous_enemy_territory = count_territories(2)
	previous_units = count_units_for_team(1)
	previous_enemy_units = count_units_for_team(2)
	previous_bandit_units = count_bandit_units()  # NOWE
	
	check_episode_done()
	
	# Debug co 50 kroków
	if current_step % 50 == 0:
		print("🎮 Krok %d | Akcja: %d | Reward: %.2f (T1: %.2f, T2: %.2f)" % [current_step, action_int, current_reward, reward_1, reward_2])



func count_units_for_team(team: int) -> int:
	"""Zlicz jednostki dla konkretnej drużyny"""
	var count = 0
	for coords in hex_grid.knight_map:
		if hex_grid.knight_map[coords].team == team:
			count += 1
	for coords in hex_grid.spearman_map:
		if hex_grid.spearman_map[coords].team == team:
			count += 1
	for coords in hex_grid.cavalry_map:
		if hex_grid.cavalry_map[coords].team == team:
			count += 1
	for coords in hex_grid.farmer_map:
		if hex_grid.farmer_map[coords].team == team:
			count += 1
	return count

func has_castle_team(team: int) -> bool:
	"""Sprawdza czy drużyna ma zamek"""
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == team:
			return true
	return false

func calculate_reward_for_team(state_before: Dictionary, team: int) -> float:
	"""
	✅ POPRAWIONA: Oblicza nagrodę dla konkretnej drużyny
	BEZPIECZNY dostęp do dictionary z .get()
	"""
	var old_ai_team = ai_team
	ai_team = team
	
	var reward = 0.0
	
	var state_after = {
		"gold": hex_grid.team_gold.get(team, 0),
		"territory": count_territories(team),
		"units": count_units_for_team(team),
		"enemy_units": count_units_for_team(3 - team),  # 3-1=2, 3-2=1
		"enemy_territory": count_territories(3 - team),
		"has_castle": has_castle_team(team),
		"unmoved_units": get_unmoved_units_count()
	}
	
	# ✅ BEZPIECZNY dostęp z wartościami domyślnymi
	var gold_before = state_before.get("gold", 0)
	var territory_before = state_before.get("territory", 0)
	var units_before = state_before.get("units", 0)
	var enemy_units_before = state_before.get("enemy_units", 0)
	var enemy_territory_before = state_before.get("enemy_territory", 0)
	var unmoved_before = state_before.get("unmoved_units", 0)
	var has_castle_before = state_before.get("has_castle", true)
	
	# ============================================================================
	# ✅ NAGRODY TYLKO za przejęcie terenów
	# ============================================================================
	var units_that_captured = 0
	for unit in units_moved_in_turn.keys():
		if not is_instance_valid(unit) or unit.team != team:
			continue
			
		var move_info = units_moved_in_turn[unit]
		if typeof(move_info) == TYPE_DICTIONARY:
			if move_info.get("captured_territory", false):
				units_that_captured += 1
				reward += 3.0  # Nagroda za każde przejęcie terenu
	
	# Bonus za masowe przejęcia
	if units_that_captured >= 3:
		reward += 5.0
		print("🎖️ Team %d: Przejęto %d pól jednocześnie! Bonus: +5" % [team, units_that_captured])
	
	# ✅ GŁÓWNA NAGRODA: Przyrost terytorium
	var territory_gain = state_after.territory - territory_before
	if territory_gain > 0:
		reward += territory_gain * 5.0
		print("🏆 Team %d: Przejęto %d nowych pól! Nagroda: +%.1f" % [team, territory_gain, territory_gain * 5.0])
	
	# Nagroda za złoto
	var gold_gain = state_after.gold - gold_before
	reward += gold_gain * 0.3
	
	# ============================================================================
	# NAGRODY ZA WALKĘ
	# ============================================================================
	
	var enemy_units_killed = enemy_units_before - state_after.enemy_units
	if enemy_units_killed > 0:
		reward += enemy_units_killed * 12.0
		print("⚔️ Team %d: Zabito %d wrogów! Nagroda: +%.1f" % [team, enemy_units_killed, enemy_units_killed * 12.0])
	
	var enemy_territory_lost = enemy_territory_before - state_after.enemy_territory
	if enemy_territory_lost > 0:
		reward += enemy_territory_lost * 5.0
	
	# ============================================================================
	# BONUS: Atakowanie bandytów
	# ============================================================================
	var bandit_units_after = count_bandit_units()
	var bandits_killed = previous_bandit_units - bandit_units_after
	if bandits_killed > 0:
		reward += bandits_killed * 5.0
		print("🏴‍☠️ Team %d: Zabito %d bandytów! Bonus: +%.1f" % [team, bandits_killed, bandits_killed * 5.0])
	
	# BONUS: Bycie blisko wrogiego zamku (motywuj do ataku)
	var attacking_enemy_castle = is_attacking_enemy_castle_team(team)
	if attacking_enemy_castle:
		reward += 3.0
	
	# ============================================================================
	# KARY
	# ============================================================================
	
	var units_lost = units_before - state_after.units
	if units_lost > 0:
		reward -= units_lost * 8.0
		print("💀 Team %d: Stracono %d jednostek. Kara: -%.1f" % [team, units_lost, units_lost * 8.0])
	
	# Kara za utratę terytorium
	if territory_gain < 0:
		reward += territory_gain * 3.0
		
	# ===== NOWE: Kara za brak ekspansji =====
	# Jeśli jednostki się ruszały, ale terytorium nie rosło - kara
	var moved_units = units_moved_in_turn.size()
	
	if moved_units > 0 and territory_gain == 0:
		# Jednostki się ruszały ale nie zdobyły nowego terenu
		reward -= 0.5
		if current_step % 100 == 0:
			print("   ⚠️ Team %d: Kara za brak ekspansji (-0.5)" % team)
	
	# Kara za cofanie się (utrata terytorium)
	if territory_gain < 0:
		reward -= abs(territory_gain) * 2.0
	
	# ============================================================================
	# WARUNKI WYGRANEJ/PRZEGRANEJ
	# ============================================================================
	
	# Przegrana zamku = koniec gry
	if not state_after.has_castle:
		reward -= 500.0
		done = true
		print("💥 Team %d: Stracono zamek! PRZEGRANA!" % team)
	
	# Wygrana = zabicie zamku wroga
	if enemy_territory_before > 0 and state_after.enemy_territory == 0:
		reward += 1000.0
		done = true
		print("🏆 Team %d: Zniszczono wrogi zamek! WYGRANA!" % team)
	
	ai_team = old_ai_team
	return reward

func get_unmoved_units_count() -> int:
	"""Zlicz jednostki które jeszcze się nie poruszyły"""
	var total_units = count_my_units_total()
	var moved_count = 0
	
	for unit in hex_grid.units_moved_this_turn:
		if is_instance_valid(unit) and unit.team == ai_team:
			moved_count += 1
	
	return total_units - moved_count

func execute_action_for_all_units(action: int):
	"""
	✅ NOWA FUNKCJA: Wykonuje akcję dla WSZYSTKICH jednostek jednocześnie
	Dzięki temu AI wykorzystuje całą armię w jednej turze!
	"""
	var state = get_game_state()
	
	# Resetuj licznik poruszonych jednostek na początku tury
	units_moved_in_turn.clear()
	
	match action:
		0:  # EKSPANSJA - wszystkie jednostki idą na neutralne tereny
			action_expand_all_units(state)
		1:  # ATAK AGRESYWNY - wszystkie jednostki atakują
			action_attack_all_units(state)
		2:  # OBRONA - wszystkie jednostki wracają do zamku
			action_defend_all_units(state)
		3:  # KUP RYCERZA
			try_buy_unit_near_castle("knight")
		4:  # KUP WŁÓCZNIKA
			try_buy_unit_near_castle("spearman")
		5:  # KUP KAWALERIĘ
			try_buy_unit_near_castle("cavalry")
		6:  # EKONOMIA - skupienie na ekspansji
			action_economy_all_units(state)
		7:  # PATROL - losowe ruchy wszystkich jednostek
			action_patrol_all_units(state)
		8:  # NIC NIE RÓB
			pass
		9:  # ✅ NOWE: BUDUJ MUR
			try_build_wall_near_castle()

func get_game_state() -> Dictionary:
	var my_units = []
	var enemy_units = []
	
	# Zbierz wszystkie jednostki swojego teamu
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"type": "knight", "pos": coords, "unit": unit})
	
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"type": "spearman", "pos": coords, "unit": unit})
	
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"type": "cavalry", "pos": coords, "unit": unit})
	
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"type": "farmer", "pos": coords, "unit": unit})
	
	# Zbierz jednostki wrogów
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append({"type": "knight", "pos": coords, "unit": unit})
	
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append({"type": "cavalry", "pos": coords, "unit": unit})
	
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append({"type": "spearman", "pos": coords, "unit": unit})
	
	return {
		"my_units": my_units,
		"enemy_units": enemy_units,
		"gold": hex_grid.team_gold.get(ai_team, 0)
	}

# ============================================================================
# ✅ NOWE IMPLEMENTACJE AKCJI - DLA WSZYSTKICH JEDNOSTEK
# ============================================================================

func action_expand_all_units(state: Dictionary):
	"""Wszystkie jednostki ekspandują na neutralne tereny"""
	if state.my_units.is_empty():
		return
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		# Sprawdź czy jednostka już się ruszyła
		if is_unit_moved(unit_data.unit):
			continue
		
		var moves = get_unit_available_moves(unit_data)
		if moves.is_empty():
			continue
		
		var neutral_target = find_neutral_move(moves)
		if neutral_target != Vector2i.ZERO:
			move_unit_smart(unit_data, neutral_target)

func action_attack_all_units(state: Dictionary):
	"""Wszystkie jednostki atakują najbliższych wrogów"""
	if state.my_units.is_empty() or state.enemy_units.is_empty():
		return
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		if is_unit_moved(unit_data.unit):
			continue
		
		var closest_enemy = find_closest_enemy_to_unit(unit_data, state.enemy_units)
		if not closest_enemy:
			continue
		
		var moves = get_unit_available_moves(unit_data)
		if moves.is_empty():
			continue
		
		var best_move = find_move_towards(unit_data.pos, moves, closest_enemy.pos)
		if best_move != Vector2i.ZERO:
			move_unit_smart(unit_data, best_move)

func action_defend_all_units(state: Dictionary):
	"""Wszystkie jednostki wracają do zamku"""
	if state.my_units.is_empty():
		return
	
	var castle_pos = Vector2i.ZERO
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == ai_team:
			castle_pos = coords
			break
	
	if castle_pos == Vector2i.ZERO:
		return
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		if is_unit_moved(unit_data.unit):
			continue
		
		var moves = get_unit_available_moves(unit_data)
		if moves.is_empty():
			continue
		
		var best_move = find_move_towards(unit_data.pos, moves, castle_pos)
		if best_move != Vector2i.ZERO:
			move_unit_smart(unit_data, best_move)

func action_economy_all_units(state: Dictionary):
	"""Wszystkie jednostki ekspandują"""
	action_expand_all_units(state)

func action_patrol_all_units(state: Dictionary):
	"""Wszystkie jednostki wykonują losowe ruchy"""
	if state.my_units.is_empty():
		return
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		if is_unit_moved(unit_data.unit):
			continue
		
		var moves = get_unit_available_moves(unit_data)
		if moves.is_empty():
			continue
		
		var random_move = moves[randi() % moves.size()]
		move_unit_smart(unit_data, random_move)

# ============================================================================
# POMOCNICZE FUNKCJE DLA RUCHU JEDNOSTEK
# ============================================================================

func is_unit_moved(unit) -> bool:
	"""Sprawdza czy jednostka już się ruszyła w tej turze"""
	if unit in hex_grid.units_moved_this_turn:
		return true
	
	# Cavalry ma 2 ruchy
	if unit is Cavalry:
		var cavalry_id = unit.get_instance_id()
		var moves_count = hex_grid.cavalry_moves_this_turn.get(cavalry_id, 0)
		return moves_count >= 2
	
	return false

func get_unit_available_moves(unit_data: Dictionary) -> Array:
	"""
	✅ POPRAWIONA: Zwraca WSZYSTKIE dostępne ruchy dla jednostki
	Uwzględnia teleportację po swoim terytorium!
	"""
	var type = unit_data.type
	var pos = unit_data.pos
	var moves = []
	
	# ✅ TELEPORTACJA: Jednostka może przejść na KAŻDE pole swojego terytorium
	for coords in hex_grid.territory_map:
		if hex_grid.territory_map[coords] == ai_team and coords != pos:
			var hex = hex_grid.get_hex_at(coords)
			if not hex:
				continue
			
			# ✅ POPRAWKA: Sprawdź czy pole NIE MA zamku
			if hex_grid.castle_map.has(coords):
				continue  # Nie można iść na zamek!
			
			# Sprawdź czy pole jest puste lub ma wroga
			var obj = hex.occupied_object
			if obj == null or (is_instance_valid(obj) and obj.team != ai_team):
				moves.append(coords)
	
	# Dodatkowo: ruchy na granicę (ekspansja/atak)
	var neighbors = hex_grid.get_neighbors(pos)
	for neighbor in neighbors:
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		
		# Można iść na neutralne lub wrogie tereny
		if owner == 0 or owner != ai_team:
			# Jeśli pole jest puste lub ma wroga
			if target == null or (is_instance_valid(target) and target.team != ai_team):
				if neighbor not in moves:
					moves.append(neighbor)
	
	return moves

func move_unit_smart(unit_data: Dictionary, target: Vector2i):
	"""
	✅ POPRAWIONA: Inteligentny ruch jednostki
	Automatycznie wykorzystuje cavalry 2 razy jeśli to możliwe
	DODANO: Śledzenie czy ruch to przejęcie terenu
	"""
	if not is_instance_valid(unit_data.unit):
		return
	
	var from = unit_data.pos
	var type = unit_data.type
	var unit = unit_data.unit
	
	# ✅ SPRAWDŹ CZY TO PRZEJĘCIE NOWEGO TERENU (przed ruchem)
	var owner_before = hex_grid.territory_map.get(target, 0)
	var is_capturing_territory = (owner_before != ai_team)  # Neutralne lub wrogie
	
	# Wykonaj ruch
	match type:
		"knight":
			hex_grid.move_knight(from, target)
		"spearman":
			hex_grid.move_spearman(from, target)
		"cavalry":
			hex_grid.move_cavalry(from, target)
			
			# ✅ CAVALRY: Jeśli to pierwszy ruch, spróbuj wykonać drugi
			var cavalry_id = unit.get_instance_id()
			var moves_count = hex_grid.cavalry_moves_this_turn.get(cavalry_id, 0)
			if moves_count == 1:
				# Poczekaj na zakończenie pierwszego ruchu
				await get_tree().create_timer(0.4).timeout
				
				# Sprawdź czy cavalry nadal istnieje i może się ruszyć
				if is_instance_valid(unit) and unit.team == ai_team:
					var second_moves = get_unit_available_moves({
						"type": "cavalry",
						"pos": target,  # Nowa pozycja po pierwszym ruchu
						"unit": unit
					})
					
					if not second_moves.is_empty():
						# Wybierz najlepszy drugi ruch
						var best_second_move = choose_best_move(target, second_moves)
						if best_second_move != Vector2i.ZERO:
							# Sprawdź czy drugi ruch też przejmuje teren
							var owner_before_2 = hex_grid.territory_map.get(best_second_move, 0)
							var is_capturing_territory_2 = (owner_before_2 != ai_team)
							
							hex_grid.move_cavalry(target, best_second_move)
							
							# Jeśli drugi ruch też przejmuje, oznacz to
							if is_capturing_territory_2:
								is_capturing_territory = true  # Przynajmniej jeden ruch przejmuje
		"farmer":
			hex_grid.move_farmer(from, target)
	
	# ✅ OZNACZ JEDNOSTKĘ JAKO PORUSZONĄ + informacja czy przejęła teren
	units_moved_in_turn[unit] = {
		"moved": true,
		"captured_territory": is_capturing_territory
	}

func choose_best_move(from: Vector2i, moves: Array) -> Vector2i:
	"""Wybiera najlepszy ruch z dostępnych - PRIORYTETYZUJ WROGIE CELE"""
	if moves.is_empty():
		return Vector2i.ZERO
	
	# PRIORYTET 1: Bandyci i wrogie jednostki  
	for move in moves:
		var hex = hex_grid.get_hex_at(move)
		if hex and hex.occupied_object != null:
			var target = hex.occupied_object
			if is_instance_valid(target) and "team" in target:
				var target_team = target.team
				# Bandyci (-1) lub wrogowie (!=ai_team)
				if target_team == -1 or (target_team > 0 and target_team != ai_team):
					return move
	
	# PRIORYTET 2: Wrogi zamek
	for move in moves:
		if hex_grid.castle_map.has(move):
			var castle = hex_grid.castle_map[move]
			if castle.team > 0 and castle.team != ai_team:
				return move
	
	# PRIORYTET 3: Obóz bandytów
	for move in moves:
		if hex_grid.castle_map.has(move):
			var castle = hex_grid.castle_map[move]
			if castle.team == -1:  # Bandycki obóz
				return move
	
	# PRIORYTET 4: Neutralne pola
	for move in moves:
		var owner = hex_grid.territory_map.get(move, 0)
		if owner == 0:
			return move
	
	# PRIORYTET 5: W kierunku wroga
	var enemy_castle = find_enemy_castle_position()
	if enemy_castle != Vector2i.ZERO:
		return find_move_towards(from, moves, enemy_castle)
	
	# Fallback: losowy ruch
	return moves[randi() % moves.size()]

func find_enemy_castle_position() -> Vector2i:
	"""Znajduje pozycję wrogiego zamku"""
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team > 0 and castle.team != ai_team:
			return coords
	return Vector2i.ZERO

func find_closest_enemy_to_unit(unit_data: Dictionary, enemy_units: Array) -> Dictionary:
	"""Znajduje najbliższego wroga do danej jednostki"""
	if enemy_units.is_empty():
		return {}
	
	var closest = null
	var min_dist = 999999
	
	for enemy in enemy_units:
		var dist = hex_distance(unit_data.pos, enemy.pos)
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	
	return closest if closest else {}

func find_move_towards(from: Vector2i, moves: Array, target: Vector2i) -> Vector2i:
	"""Znajduje ruch najbliżej celu"""
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		var dist = hex_distance(move, target)
		if dist < min_dist:
			min_dist = dist
			best_move = move
	
	return best_move

func find_neutral_move(moves: Array) -> Vector2i:
	"""Znajduje ruch na neutralne pole"""
	for move in moves:
		var owner = hex_grid.territory_map.get(move, 0)
		if owner == 0:
			return move
	return Vector2i.ZERO

# ============================================================================
# ✅ ULEPSZONE NAGRODY
# ============================================================================

func calculate_reward(state_before: Dictionary) -> float:
	var reward = 0.0
	
	var state_after = {
		"gold": hex_grid.team_gold.get(ai_team, 0),
		"territory": count_territories(ai_team),
		"units": count_my_units_total(),
		"enemy_units": count_all_enemy_units_total(),
		"enemy_territory": count_all_enemy_territories(),
		"has_castle": has_castle(),
		"unmoved_units": get_unmoved_units_count()
	}
	
	# ============================================================================
	# ✅ NOWA NAGRODA: Za poruszenie jednostkami
	# ============================================================================
	
	var units_moved_delta = state_before.unmoved_units - state_after.unmoved_units
	if units_moved_delta > 0:
		# Nagroda za każdą poruszoną jednostkę
		reward += units_moved_delta * 2.0
		
		# Bonus za poruszenie WSZYSTKIMI jednostkami
		if state_after.unmoved_units == 0 and state_before.unmoved_units > 0:
			reward += 10.0
			print("🎖️ WSZYSTKIE JEDNOSTKI SIĘ PORUSZYŁY! Bonus: +10")
	
	# Kara za nieporuszanie się
	if state_after.unmoved_units > state_before.unmoved_units * 0.5:
		reward -= 3.0
	
	# ============================================================================
	# NAGRODY ZA POSTĘP
	# ============================================================================
	
	var territory_gain = state_after.territory - state_before.territory
	reward += territory_gain * 5.0
	
	var gold_gain = state_after.gold - state_before.gold
	reward += gold_gain * 0.3
	
	# ============================================================================
	# NAGRODY ZA WALKĘ
	# ============================================================================
	
	var enemy_killed = state_before.enemy_units - state_after.enemy_units
	reward += enemy_killed * 25.0
	
	var enemy_territory_lost = state_before.enemy_territory - state_after.enemy_territory
	reward += enemy_territory_lost * 5.0
	
	# ============================================================================
	# KARY
	# ============================================================================
	
	var units_lost = state_before.units - state_after.units
	reward -= units_lost * 20.0
	
	if territory_gain < 0:
		reward += territory_gain * 3.0
	
	if state_after.gold < 0:
		reward -= 5.0
		print("💸 BANKRUCTWO! Kara: -5")
	elif state_after.gold < 20:
		reward -= 0.5
	
	# ============================================================================
	# BONUSY STRATEGICZNE
	# ============================================================================
	
	var connected_territories = hex_grid.get_connected_territories(ai_team).size()
	var total_territories = state_after.territory
	
	if total_territories > 0:
		var connectivity_ratio = float(connected_territories) / float(total_territories)
		reward += connectivity_ratio * 5.0
	
	var distance_to_enemy_castle = get_min_distance_to_enemy_castle()
	if distance_to_enemy_castle >= 0 and distance_to_enemy_castle < 5:
		var proximity_bonus = (5.0 - float(distance_to_enemy_castle)) * 2.0
		reward += proximity_bonus
	
	if state_after.territory > 20:
		reward += 10.0
	
	# Sprawdź warunki końca epizodu
	if current_step >= episode_max_steps:
		reward += state_after.territory * 2.0
		reward += float(state_after.gold) * 0.5
	
	if not state_after.has_castle:
		reward -= 100.0
		print("💀 ZAMEK PRZEJĘTY! Koniec epizodu. Kara: -100")
	
	return reward

# ============================================================================
# SPRAWDZANIE KOŃCA EPIZODU
# ============================================================================

func check_episode_done():
	"""Sprawdza czy epizod się skończył"""
	
	# Sprawdź WAŻNE: Czy któryś team zbankrutował
	for team in [1, 2]:
		if hex_grid.team_gold.get(team, 0) < -50:  # Duże długi
			done = true
			needs_reset = true
			print("💸 Koniec epizodu: Team %d zbankrutował" % team)
			return
	
	# 1. Przekroczono limit kroków
	if current_step >= episode_max_steps:
		done = true
		needs_reset = true
		print("⏱️ Koniec epizodu: Limit kroków osiągnięty")
		return
	
	# 2. Jeden z teamów stracił zamek
	var team1_has_castle = has_castle_team(1)
	var team2_has_castle = has_castle_team(2)
	
	if not team1_has_castle or not team2_has_castle:
		done = true
		needs_reset = true
		if not team1_has_castle:
			print("💀 Koniec epizodu: Team 1 stracił zamek - Team 2 WYGRYWA!")
		else:
			print("💀 Koniec epizodu: Team 2 stracił zamek - Team 1 WYGRYWA!")
		return

func has_castle() -> bool:
	"""Sprawdza czy mamy zamek"""
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == ai_team:
			return true
	return false

# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================

func count_territories(team: int) -> int:
	var count = 0
	for owner in hex_grid.territory_map.values():
		if owner == team:
			count += 1
	return count

func count_all_enemy_territories() -> int:
	var count = 0
	for owner in hex_grid.territory_map.values():
		if owner > 0 and owner != ai_team and owner <= 4:
			count += 1
	return count

func count_my_units_total() -> int:
	var count = 0
	
	for coords in hex_grid.knight_map:
		if hex_grid.knight_map[coords].team == ai_team:
			count += 1
	
	for coords in hex_grid.spearman_map:
		if hex_grid.spearman_map[coords].team == ai_team:
			count += 1
	
	for coords in hex_grid.cavalry_map:
		if hex_grid.cavalry_map[coords].team == ai_team:
			count += 1
	
	for coords in hex_grid.farmer_map:
		if hex_grid.farmer_map[coords].team == ai_team:
			count += 1
	
	return count

func count_all_enemy_units_total() -> int:
	var count = 0
	
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			count += 1
	
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			count += 1
	
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			count += 1
	
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			count += 1
	
	return count

func count_units_by_type(team: int) -> Dictionary:
	var counts = {
		"knights": 0,
		"spearmen": 0,
		"cavalry": 0,
		"farmers": 0
	}
	
	for coords in hex_grid.knight_map:
		if hex_grid.knight_map[coords].team == team:
			counts.knights += 1
	
	for coords in hex_grid.spearman_map:
		if hex_grid.spearman_map[coords].team == team:
			counts.spearmen += 1
	
	for coords in hex_grid.cavalry_map:
		if hex_grid.cavalry_map[coords].team == team:
			counts.cavalry += 1
	
	for coords in hex_grid.farmer_map:
		if hex_grid.farmer_map[coords].team == team:
			counts.farmers += 1
	
	return counts

func count_all_enemy_units() -> Dictionary:
	var counts = {
		"knights": 0,
		"spearmen": 0,
		"cavalry": 0
	}
	
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			counts.knights += 1
	
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			counts.spearmen += 1
	
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			counts.cavalry += 1
	
	return counts

func is_castle_threatened() -> bool:
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == ai_team:
			var neighbors = get_hexes_in_range(coords, 3)
			for neighbor in neighbors:
				if hex_grid.knight_map.has(neighbor):
					var unit = hex_grid.knight_map[neighbor]
					if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
						return true
				if hex_grid.cavalry_map.has(neighbor):
					var unit = hex_grid.cavalry_map[neighbor]
					if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
						return true
	return false

func get_territory_connectivity() -> float:
	var connected = hex_grid.get_connected_territories(ai_team)
	var total = count_territories(ai_team)
	if total == 0:
		return 0.0
	return float(connected.size()) / float(total)

func get_border_strength_normalized() -> float:
	var border_hexes = get_border_hexes()
	if border_hexes.is_empty():
		return 0.0
	
	var units_on_border = 0
	for unit in hex_grid.knight_map.values():
		if is_instance_valid(unit) and unit.team == ai_team:
			if unit.hex_position in border_hexes:
				units_on_border += 1
	
	return clamp(float(units_on_border) / float(border_hexes.size()), 0.0, 1.0)

func get_border_hexes() -> Array:
	var border = []
	for coords in hex_grid.territory_map:
		if hex_grid.territory_map[coords] == ai_team:
			var neighbors = hex_grid.get_neighbors(coords)
			for neighbor in neighbors:
				var owner = hex_grid.territory_map.get(neighbor, 0)
				if owner != ai_team:
					border.append(coords)
					break
	return border

func get_expansion_potential_normalized() -> float:
	var neutral_count = 0
	var my_units = count_my_units_total()
	
	if my_units == 0:
		return 0.0
	
	for unit in hex_grid.knight_map.values():
		if is_instance_valid(unit) and unit.team == ai_team:
			var neighbors = hex_grid.get_neighbors(unit.hex_position)
			for neighbor in neighbors:
				var owner = hex_grid.territory_map.get(neighbor, 0)
				if owner == 0:
					neutral_count += 1
	
	return clamp(float(neutral_count) / (float(my_units) * 2.0), 0.0, 1.0)

func count_attackable_enemies() -> int:
	var count = 0
	
	for my_unit in hex_grid.knight_map.values():
		if is_instance_valid(my_unit) and my_unit.team == ai_team:
			var neighbors = hex_grid.get_neighbors(my_unit.hex_position)
			for neighbor in neighbors:
				if hex_grid.farmer_map.has(neighbor):
					var enemy = hex_grid.farmer_map[neighbor]
					if is_instance_valid(enemy) and enemy.team > 0 and enemy.team != ai_team:
						count += 1
	
	return count

func get_wall_coverage() -> float:
	var total_walls = 0
	var max_walls = 0
	
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == ai_team:
			var neighbors = hex_grid.get_neighbors(coords)
			max_walls += neighbors.size()
			for neighbor in neighbors:
				if hex_grid.has_wall_between(coords, neighbor):
					total_walls += 1
	
	if max_walls == 0:
		return 0.0
	return float(total_walls) / float(max_walls)

func get_min_distance_to_enemy_castle() -> int:
	var min_distance = -1
	
	var my_castle_pos = Vector2i.ZERO
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == ai_team:
			my_castle_pos = coords
			break
	
	if my_castle_pos == Vector2i.ZERO:
		return -1
	
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team > 0 and castle.team != ai_team:
			var dist = hex_distance(my_castle_pos, coords)
			if min_distance == -1 or dist < min_distance:
				min_distance = dist
	
	return min_distance

func try_buy_unit_near_castle(unit_type: String) -> bool:
	"""
	Kupuje jednostkę - PRIORYTET: neutralne/wrogie tereny > własne pola
	"""
	var cost = get_unit_cost(unit_type)
	var upkeep = get_unit_upkeep(unit_type)
	var gold = hex_grid.team_gold.get(ai_team, 0)
	
	if gold < cost:
		return false
	
	# Sprawdź czy dochód pokrywa upkeep
	var current_income = hex_grid.calculate_income(ai_team)
	var current_upkeep = hex_grid.calculate_upkeep(ai_team)
	var future_upkeep = current_upkeep + upkeep
	
	if current_income < future_upkeep * 0.8:
		return false
	
	# Znajdź NAJLEPSZĄ pozycję do spawnu
	var best_pos = Vector2i.ZERO
	var best_priority = -1
	
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team == ai_team:
			var neighbors = hex_grid.get_neighbors(coords)
			
			for neighbor in neighbors:
				var hex = hex_grid.get_hex_at(neighbor)
				if hex and hex.occupied_object == null:
					var owner = hex_grid.territory_map.get(neighbor, 0)
					var priority = 0
					
					# PRIORYTET 1: Neutralne pola (+3)
					if owner == 0:
						priority = 3
					# PRIORYTET 2: Wrogie pola (+2)
					elif owner > 0 and owner != ai_team:
						priority = 2
					# PRIORYTET 3: Własne pola (+1 - tylko gdy nie ma lepszych)
					elif owner == ai_team:
						priority = 1
					
					if priority > best_priority:
						best_priority = priority
						best_pos = neighbor
	
	# Spawnuj na najlepszej pozycji
	if best_pos != Vector2i.ZERO:
		match unit_type:
			"knight":
				return hex_grid.buy_knight(best_pos, ai_team)
			"spearman":
				return hex_grid.buy_spearman(best_pos, ai_team)
			"cavalry":
				return hex_grid.buy_cavalry(best_pos, ai_team)
			"farmer":
				return hex_grid.buy_farmer(best_pos, ai_team)
	
	return false

func get_unit_upkeep(unit_type: String) -> int:
	"""Zwraca koszt utrzymania jednostki na turę"""
	match unit_type:
		"knight":
			return 18
		"spearman":
			return 6
		"cavalry":
			return 50
		"farmer":
			return 2
	return 0

func get_unit_cost(unit_type: String) -> int:
	match unit_type:
		"knight":
			return 20
		"spearman":
			return 10
		"cavalry":
			return 40
		"farmer":
			return 10
	return 0

func normalize_value(value: float, min_val: float, max_val: float) -> float:
	if max_val == min_val:
		return 0.0
	return clamp((value - min_val) / (max_val - min_val), 0.0, 1.0)

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = axial_to_cube(a)
	var bc = axial_to_cube(b)
	return (abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2

func axial_to_cube(hex: Vector2i) -> Vector3i:
	var x = hex.x
	var z = hex.y
	var y = -x - z
	return Vector3i(x, y, z)

func get_hexes_in_range(center: Vector2i, range_dist: int) -> Array:
	var hexes = []
	for q in range(center.x - range_dist, center.x + range_dist + 1):
		for r in range(center.y - range_dist, center.y + range_dist + 1):
			var hex_pos = Vector2i(q, r)
			if hex_distance(center, hex_pos) <= range_dist:
				hexes.append(hex_pos)
	return hexes

func distribute_gold_and_check_bankruptcy():
	"""
	✅ Przydziela złoto i sprawdza bankructwo PO TURACH OBUDWÓCH drużyn
	"""
	for team in [1, 2]:
		var income = hex_grid.calculate_income(team)
		var upkeep = hex_grid.calculate_upkeep(team)
		var net = income - upkeep
		
		var old_gold = hex_grid.team_gold.get(team, 0)
		var new_gold = old_gold + net
		hex_grid.team_gold[team] = new_gold
		
		if current_step % 50 == 0:
			print("   💵 Team %d: Złoto %d → %d (dochód: %d, koszty: %d)" % [team, old_gold, new_gold, income, upkeep])
		
		# ============================================================================
		# ✅ BANKRUCTWO - zamień wszystkie jednostki na bandytów
		# ============================================================================
		if new_gold < 0:
			print("💥 BANKRUCTWO Team %d! Złoto: %d. Zamieniamy jednostki na bandytów!" % [team, new_gold])
			hex_grid.handle_bankruptcy(team)
			
			# Kara za bankructwo
			if team == ai_team:
				current_reward -= 200.0
				print("⚠️ Kara za bankructwo: -200")
	
	# ✅ POPRAWKA: Przetwórz bankructwa RAZ po sprawdzeniu obu teamów
	hex_grid.process_bankruptcies()

func convert_team_to_bandits(team: int):
	"""Zamienia wszystkie jednostki drużyny na bandytów"""
	var units_to_convert = []
	
	# Zbierz wszystkie jednostki drużyny
	for coords in hex_grid.knight_map.keys():
		if hex_grid.knight_map[coords].team == team:
			units_to_convert.append({"type": "knight", "pos": coords})
	
	for coords in hex_grid.spearman_map.keys():
		if hex_grid.spearman_map[coords].team == team:
			units_to_convert.append({"type": "spearman", "pos": coords})
	
	for coords in hex_grid.cavalry_map.keys():
		if hex_grid.cavalry_map[coords].team == team:
			units_to_convert.append({"type": "cavalry", "pos": coords})
	
	for coords in hex_grid.farmer_map.keys():
		if hex_grid.farmer_map[coords].team == team:
			units_to_convert.append({"type": "farmer", "pos": coords})
	
	# Zamień na bandytów (farmerów z team -1)
	for unit_data in units_to_convert:
		var pos = unit_data.pos
		var type = unit_data.type
		
		# Usuń starą jednostkę
		match type:
			"knight":
				hex_grid.remove_knight_at(pos)
			"spearman":
				hex_grid.remove_spearman_at(pos)
			"cavalry":
				hex_grid.remove_cavalry_at(pos)
			"farmer":
				hex_grid.remove_farmer_at(pos)
		
		# Dodaj bandyckiego farmera
		hex_grid.spawn_farmer_at(pos, -1)
	
	print("🏴‍☠️ Zamieniono %d jednostek Team %d na bandytów!" % [units_to_convert.size(), team])
	
	# NOWE: Usuń mury wokół zbuntowanych jednostek
	for unit_data in units_to_convert:
		var pos = unit_data.pos
		var neighbors = hex_grid.get_neighbors(pos)
		
		# Usuń wszystkie mury wokół tej pozycji
		for i in range(6):  # 6 krawędzi hexa
			var edge_key = "%d,%d-edge%d" % [pos.x, pos.y, i]
			if hex_grid.wall_map.has(edge_key):
				hex_grid.wall_map.erase(edge_key)
				# Usuń wizualną linię
				if hex_grid.has_meta("wall_lines"):
					var wall_lines = hex_grid.get_meta("wall_lines")
					if wall_lines.has(edge_key):
						var line = wall_lines[edge_key]
						if is_instance_valid(line):
							line.queue_free()
						wall_lines.erase(edge_key)
	
	print("   🧹 Usunięto mury wokół zbuntowanych jednostek")
	
	# Zamień terytorium na bandyckie
	for coords in hex_grid.territory_map.keys():
		if hex_grid.territory_map[coords] == team:
			hex_grid.territory_map[coords] = -1
			hex_grid.update_hex_color(coords)
	
	# Zamień zamek na bandycki obóz (jeśli mają zamek)
	for coords in hex_grid.castle_map.keys():
		var castle = hex_grid.castle_map[coords]
		if castle.team == team:
			castle.team = -1
			hex_grid.territory_map[coords] = -2
			hex_grid.update_hex_color(coords)

func try_build_wall_near_castle() -> bool:
	"""
	Buduje mury wokół JEDNOSTEK (nie zamku) aby je chronić.
	Logika:
	- Farmer w murach = tylko knight może go zniszczyć
	- Spearman w murach = tylko knight może go zniszczyć  
	- Knight w murach = tylko cavalry może go zniszczyć
	- Cavalry w murach = niezniszczalny (chyba że odcięty)
	
	Priorytet: jednostki blisko wroga > silne jednostki
	"""
	var wall_cost = hex_grid.WALL_COST_PER_HEX
	var gold = hex_grid.team_gold.get(ai_team, 0)
	
	if gold < wall_cost:
		return false
	
	# Zbierz jednostki z priorytetem (cavalry > knight > spearman > farmer)
	var my_units = []
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"pos": coords, "type": "cavalry", "priority": 4})
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"pos": coords, "type": "knight", "priority": 3})
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"pos": coords, "type": "spearman", "priority": 2})
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team == ai_team:
			my_units.append({"pos": coords, "type": "farmer", "priority": 1})
	
	# Znajdź wrogów
	var enemy_units = []
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append(coords)
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append(coords)
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append(coords)
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team > 0 and unit.team != ai_team:
			enemy_units.append(coords)
	
	# Bez wrogów nie buduj murów
	if enemy_units.is_empty():
		return false
	
	# Znajdź jednostkę najbliżej wroga, która nie ma murów
	var best_unit = null
	var min_distance_to_enemy = 999999
	
	for unit_data in my_units:
		var pos = unit_data.pos
		
		# Sprawdź czy ma pełne mury (6 ścian)
		var walls_count = 0
		var neighbors = hex_grid.get_neighbors(pos)
		for nn in neighbors:
			if hex_grid.has_wall_between(pos, nn):
				walls_count += 1
		
		if walls_count >= 6:
			continue  # Już ma pełne mury
		
		# Odległość do najbliższego wroga
		var min_dist = 999999
		for enemy_pos in enemy_units:
			var dist = hex_distance(pos, enemy_pos)
			min_dist = min(min_dist, dist)
		
		# Wybierz jednostkę najbliżej wroga (z uwzględnieniem priorytetu)
		if min_dist < min_distance_to_enemy or (min_dist == min_distance_to_enemy and unit_data.priority > (best_unit.priority if best_unit else 0)):
			min_distance_to_enemy = min_dist
			best_unit = unit_data
	
	# Zbuduj mury wokół najlepszej jednostki
	if best_unit != null:
		var walls_created = hex_grid.create_hex_walls(best_unit.pos, ai_team)
		if walls_created > 0:
			hex_grid.team_gold[ai_team] -= wall_cost
			print("   🧱 Zbudowano %d murów wokół %s (Team %d) - odległość od wroga: %d" % [walls_created, best_unit.type, ai_team, min_distance_to_enemy])
			return true
	
	return false

# ============================================================================
# FUNKCJE POMOCNICZE - BANDYCI I WROGIE CELE
# ============================================================================

func count_bandit_units() -> int:
	"""Zlicza wszystkie jednostki bandytów (team -1)"""
	var count = 0
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team == -1:
			count += 1
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team == -1:
			count += 1
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team == -1:
			count += 1
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team == -1:
			count += 1
	return count

func is_attacking_enemy_castle_team(team: int) -> bool:
	"""Sprawdza czy jednostki danego teamu są blisko wrogiego zamku"""
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team > 0 and castle.team != team:
			# Sprawdź czy mamy jednostki w odległości 2
			for unit_coords in hex_grid.knight_map:
				var unit = hex_grid.knight_map[unit_coords]
				if is_instance_valid(unit) and unit.team == team:
					if hex_distance(unit_coords, coords) <= 2:
						return true
			for unit_coords in hex_grid.spearman_map:
				var unit = hex_grid.spearman_map[unit_coords]
				if is_instance_valid(unit) and unit.team == team:
					if hex_distance(unit_coords, coords) <= 2:
						return true
			for unit_coords in hex_grid.cavalry_map:
				var unit = hex_grid.cavalry_map[unit_coords]
				if is_instance_valid(unit) and unit.team == team:
					if hex_distance(unit_coords, coords) <= 2:
						return true
	return false
