extends Node
class_name AIController

# === TYPY AI ===
enum Difficulty {
	NORMAL,
	HARD
}

var hex_grid: HexGrid
var difficulty: Difficulty = Difficulty.NORMAL
var team: int = -1
var aggression_level: float = 0.5  # 0.1 = defensywny, 0.5 = zbalansowany, 1.0 = super agresywny

# Parametry dla różnych poziomów trudności
var params = {
	Difficulty.NORMAL: {
		"aggression": 0.5,  # Będzie nadpisane przez aggression_level
		"expansion_priority": 0.6,
		"defense_priority": 0.4,
		"economy_reserve": 30,
		"wall_threshold": 0.3,
		"think_time": 0.5,
	},
	Difficulty.HARD: {
		"aggression": 0.8,  # Będzie nadpisane przez aggression_level
		"expansion_priority": 0.7,
		"defense_priority": 0.7,
		"economy_reserve": 20,
		"wall_threshold": 0.5,
		"think_time": 0.3,
	}
}

# === AI MEMORY (Funkcja #2) ===
var memory: Dictionary = {
	"last_attacked_by": {},
	"lost_territories": [],
	"previous_hex_count": 0,
	"enemy_strength_history": {},
	"danger_zones": []
}

# === STRATEGIC PLANNING (Funkcja #6) ===
var strategic_goals: Array = []

func _init(grid: HexGrid, ai_team: int, diff: Difficulty = Difficulty.NORMAL, aggro: float = 0.5):
	hex_grid = grid
	team = ai_team
	difficulty = diff
	aggression_level = clamp(aggro, 0.1, 1.0)
	
	# Nadpisz aggression w params
	params[difficulty].aggression = aggression_level
	
	# Dostosuj inne parametry na podstawie agresywności
	if aggression_level < 0.3:  # Defensywny
		params[difficulty].defense_priority = 0.8
		params[difficulty].expansion_priority = 0.3
		params[difficulty].wall_threshold = 0.6
	elif aggression_level > 0.7:  # Agresywny
		params[difficulty].defense_priority = 0.3
		params[difficulty].expansion_priority = 0.9
		params[difficulty].wall_threshold = 0.2

# === HELPER FUNCTIONS ===
func has_team(obj) -> bool:
	"""Bezpieczne sprawdzenie czy obiekt ma właściwość team"""
	return obj != null and "team" in obj

func get_object_team(obj) -> int:
	"""Bezpieczne pobranie teamu z obiektu"""
	if has_team(obj):
		return obj.team
	return -1

# === GŁÓWNA FUNKCJA - WYKONAJ TURĘ AI ===
func execute_turn():
	print("=== AI (Team %d, %s, Aggro: %.1f) zaczyna turę ===" % [team, "HARD" if difficulty == Difficulty.HARD else "NORMAL", aggression_level])
	
	# 1. Analiza sytuacji
	var state = analyze_game_state()
	
	# 2. Aktualizacja pamięci i strategii
	update_memory(state)
	set_strategic_goals(state)
	
	# 3. BANDYCI - nie kupują jednostek ani nie stawiają murów
	if team == -1:
		print("AI %d: Bandyci - tylko ruch jednostek" % team)
		await move_all_units(state)
		print("=== AI (Team %d) kończy turę ===" % team)
		return
	
	# 4. Strategia - kupowanie jednostek (jeśli nie bankrutujemy)
	var is_bankrupt = hex_grid.team_gold.get(team, 0) < hex_grid.calculate_upkeep(team)
	if not is_bankrupt:
		await buy_units(state)
	else:
		print("AI %d: Bankructwo - pomijam kupowanie jednostek" % team)
	
	# 5. Łączenie jednostek (farmerzy -> spearman, knightowie -> cavalry)
	await merge_units(state)
	
	# 6. Budowanie murów (jeśli opłacalne i nie bankrutujemy)
	if not is_bankrupt and aggression_level < 0.7:  # Tylko dla mniej agresywnych
		await build_walls(state)
	
	# 7. Ruch wszystkich jednostek (ZAWSZE, nawet podczas bankructwa)
	await move_all_units(state)
	
	print("=== AI (Team %d) kończy turę ===" % team)

# === ANALIZA STANU GRY ===
func analyze_game_state() -> Dictionary:
	var state = {
		"my_hexes": [],
		"my_connected_hexes": [],
		"enemy_hexes": [],
		"neutral_hexes": [],
		"border_hexes": [],
		"my_units": [],
		"enemy_units": [],
		"my_castles": [],
		"enemy_castles": [],
		"threats": [],
		"opportunities": [],
		"gold": hex_grid.team_gold.get(team, 0),
		"income": hex_grid.calculate_income(team),
		"upkeep": hex_grid.calculate_upkeep(team),
	}
	
	# Zbierz wszystkie hexy
	for coords in hex_grid.hex_map:
		var owner = hex_grid.territory_map.get(coords, 0)
		
		if owner == team:
			state.my_hexes.append(coords)
		elif owner > 0 and owner <= 4:
			state.enemy_hexes.append(coords)
		else:
			state.neutral_hexes.append(coords)
	
	# Hexy połączone z zamkiem
	state.my_connected_hexes = hex_grid.get_connected_territories(team)
	
	# Granica (pola do ataku/ekspansji)
	state.border_hexes = hex_grid.get_border_of_connected_territories(team, state.my_connected_hexes)
	
	# Zbierz jednostki
	for unit in hex_grid.knight_map.values():
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "knight", "pos": unit.hex_position})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "knight", "pos": unit.hex_position})
	
	for unit in hex_grid.farmer_map.values():
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "farmer", "pos": unit.hex_position})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "farmer", "pos": unit.hex_position})
	
	for unit in hex_grid.spearman_map.values():
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "spearman", "pos": unit.hex_position})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "spearman", "pos": unit.hex_position})
	
	for unit in hex_grid.cavalry_map.values():
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "cavalry", "pos": unit.hex_position})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "cavalry", "pos": unit.hex_position})
	
	# Zbierz zamki
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team == team:
			state.my_castles.append(coords)
		elif castle.team > 0 and castle.team <= 4:
			state.enemy_castles.append(coords)
	
	# Analizuj zagrożenia (wrogie jednostki blisko moich hexów)
	for enemy in state.enemy_units:
		var dist_to_border = get_min_distance(enemy.pos, state.my_connected_hexes)
		if dist_to_border <= 2:
			state.threats.append(enemy)
	
	# Analizuj możliwości (słabe cele)
	for enemy in state.enemy_units:
		var nearby_allies = count_nearby_units(enemy.pos, state.my_units, 2)
		if nearby_allies >= 1:
			state.opportunities.append(enemy)
	
	return state

# === AI MEMORY (#2) ===
func update_memory(state: Dictionary):
	"""Aktualizuje pamięć AI o poprzednich turach"""
	# Sprawdź czy straciłeś terytoria
	if memory.previous_hex_count > 0:
		var current = state.my_connected_hexes.size()
		var previous = memory.previous_hex_count
		if current < previous:
			memory.lost_territories.append({
				"turn": hex_grid.current_round,
				"count": previous - current
			})
			print("AI %d: Straciłem %d pól! Zwiększam obronę." % [team, previous - current])
			# Zwiększ priorytet obrony
			params[difficulty].defense_priority = min(1.0, params[difficulty].defense_priority * 1.3)
	
	memory.previous_hex_count = state.my_connected_hexes.size()
	
	# Analiza wroga - kto atakuje
	for threat in state.threats:
		var enemy_team = threat.unit.team
		if not memory.last_attacked_by.has(enemy_team):
			memory.last_attacked_by[enemy_team] = hex_grid.current_round
			print("AI %d: Team %d atakuje! Pamiętam to." % [team, enemy_team])
	
	# Zapisz strefy niebezpieczne
	memory.danger_zones.clear()
	for threat in state.threats:
		memory.danger_zones.append(threat.pos)
	
	# Monitoruj siłę wrogów
	for enemy_team in [1, 2, 3, 4]:
		if enemy_team == team:
			continue
		var strength = calculate_team_strength(enemy_team)
		if not memory.enemy_strength_history.has(enemy_team):
			memory.enemy_strength_history[enemy_team] = []
		memory.enemy_strength_history[enemy_team].append(strength)
		# Trzymaj tylko ostatnie 5 tur
		if memory.enemy_strength_history[enemy_team].size() > 5:
			memory.enemy_strength_history[enemy_team].pop_front()

func get_priority_enemy() -> int:
	"""Zwraca priorytetowego wroga (ostatnio atakującego)"""
	var most_recent = -1
	var most_recent_turn = 0
	
	for enemy_team in memory.last_attacked_by:
		var turn = memory.last_attacked_by[enemy_team]
		if turn > most_recent_turn:
			most_recent_turn = turn
			most_recent = enemy_team
	
	return most_recent

func calculate_team_strength(t: int) -> float:
	"""Oblicza siłę drużyny (Funkcja #5)"""
	var strength = 0.0
	
	# Punkty za jednostki
	for unit in hex_grid.knight_map.values():
		if unit.team == t:
			strength += 40
	for unit in hex_grid.spearman_map.values():
		if unit.team == t:
			strength += 20
	for unit in hex_grid.cavalry_map.values():
		if unit.team == t:
			strength += 80
	for unit in hex_grid.farmer_map.values():
		if unit.team == t:
			strength += 10
	
	# Punkty za terytoria
	var connected = hex_grid.get_connected_territories(t)
	strength += connected.size() * 2
	
	# Punkty za złoto
	strength += hex_grid.team_gold.get(t, 0) * 0.5
	
	return strength

# === STRATEGIC PLANNING (#6) ===
func set_strategic_goals(state: Dictionary):
	"""Planuje długoterminowe cele strategiczne"""
	strategic_goals.clear()
	
	# Cel 1: Przejmij wrogie zamki (najwyższy priorytet)
	for castle_pos in state.enemy_castles:
		if hex_grid.get_hex_at(castle_pos):
			var turns_needed = estimate_turns_to_capture(castle_pos, state)
			strategic_goals.append({
				"type": "capture_castle",
				"position": castle_pos,
				"priority": 10,
				"turns_to_complete": turns_needed,
				"target_team": hex_grid.castle_map[castle_pos].team
			})
	
	# Cel 2: Rozbuduj ekonomię (zajmij więcej pól)
	if state.my_connected_hexes.size() < 20:
		var expansion_target = state.my_connected_hexes.size() + 8
		strategic_goals.append({
			"type": "expand_economy",
			"target_size": expansion_target,
			"priority": 6
		})
	
	# Cel 3: Odetnij największą grupę wroga
	var cutoff_target = find_best_cutoff_target(state)
	if cutoff_target.has("position"):
		strategic_goals.append({
			"type": "cutoff_enemy",
			"position": cutoff_target.position,
			"priority": 8,
			"potential_cutoff": cutoff_target.cutoff_count
		})
	
	# Cel 4: Eliminuj priorytetowego wroga (z pamięci)
	var priority_enemy = get_priority_enemy()
	if priority_enemy > 0:
		strategic_goals.append({
			"type": "eliminate_enemy",
			"target_team": priority_enemy,
			"priority": 9
		})
	
	# DEBUG: Pokaż cele
	print("AI %d: Cele strategiczne:" % team)
	for goal in strategic_goals:
		print("  - %s (priorytet: %d)" % [goal.type, goal.priority])

func estimate_turns_to_capture(castle_pos: Vector2i, state: Dictionary) -> int:
	"""Szacuje ile tur zajmie przejęcie zamku"""
	var min_dist = 999999
	for unit_data in state.my_units:
		var dist = hex_distance(unit_data.pos, castle_pos)
		if dist < min_dist:
			min_dist = dist
	
	return max(1, min_dist)

func find_best_cutoff_target(state: Dictionary) -> Dictionary:
	"""Znajduje pole, którego przejęcie odcina najwięcej jednostek wroga"""
	var best = {"position": Vector2i.ZERO, "cutoff_count": 0}
	
	for border_hex in state.border_hexes:
		var owner = hex_grid.territory_map.get(border_hex, 0)
		if owner <= 0 or owner > 4 or owner == team:
			continue
		
		var cutoff = count_units_that_would_be_cutoff(owner, border_hex)
		if cutoff > best.cutoff_count:
			best.position = border_hex
			best.cutoff_count = cutoff
	
	return best

# === MERGING UNITS ===
func merge_units(state: Dictionary):
	"""Łączy jednostki: 2 farmerów -> spearman, 2 knightów -> cavalry"""
	
	# Zbierz farmerów według pozycji
	var farmers_by_pos = {}
	for unit_data in state.my_units:
		if unit_data.type == "farmer":
			farmers_by_pos[unit_data.pos] = unit_data
	
	# Spróbuj połączyć farmerów w spearmana
	var farmers_positions = farmers_by_pos.keys()
	for i in range(farmers_positions.size()):
		var pos1 = farmers_positions[i]
		if not hex_grid.farmer_map.has(pos1):
			continue
		
		# Znajdź najbliższego farmera
		for j in range(i + 1, farmers_positions.size()):
			var pos2 = farmers_positions[j]
			if not hex_grid.farmer_map.has(pos2):
				continue
			
			# Jeśli są obok siebie - połącz
			if are_hexes_adjacent(pos1, pos2):
				print("AI %d: Łączę farmerów %s + %s -> spearman" % [team, pos1, pos2])
				hex_grid.merge_farmers_to_spearman(pos1, pos2)
				await hex_grid.get_tree().create_timer(0.2).timeout
				break
	
	# Zbierz knightów według pozycji
	var knights_by_pos = {}
	for unit_data in state.my_units:
		if unit_data.type == "knight":
			knights_by_pos[unit_data.pos] = unit_data
	
	# Spróbuj połączyć knightów w cavalry
	var knights_positions = knights_by_pos.keys()
	for i in range(knights_positions.size()):
		var pos1 = knights_positions[i]
		if not hex_grid.knight_map.has(pos1):
			continue
		
		# Znajdź najbliższego knighta
		for j in range(i + 1, knights_positions.size()):
			var pos2 = knights_positions[j]
			if not hex_grid.knight_map.has(pos2):
				continue
			
			# Jeśli są obok siebie - połącz
			if are_hexes_adjacent(pos1, pos2):
				print("AI %d: Łączę knightów %s + %s -> cavalry" % [team, pos1, pos2])
				hex_grid.merge_knights_to_cavalry(pos1, pos2)
				await hex_grid.get_tree().create_timer(0.2).timeout
				break

# === BUYING UNITS (#3) ===
func buy_units(state: Dictionary):
	"""Kupuje jednostki zgodnie ze strategią"""
	var gold = state.gold
	var income = state.income
	var upkeep = state.upkeep
	
	var reserve = params[difficulty].economy_reserve
	var available_gold = max(0, gold - reserve)
	
	if available_gold < hex_grid.FARMER_COST:
		return
	
	# Strategia kupowania
	var units_to_buy = plan_unit_purchases(state, available_gold)
	
	for purchase in units_to_buy:
		var unit_type = purchase.type
		var position = purchase.position
		var cost = purchase.cost
		
		if hex_grid.team_gold[team] < cost:
			continue
		
		# Kup jednostkę
		if unit_type == "farmer":
			hex_grid.place_farmer_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: Kupiono farmera na %s" % [team, position])
		elif unit_type == "knight":
			hex_grid.place_knight_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: Kupiono knighta na %s" % [team, position])
		elif unit_type == "spearman":
			hex_grid.place_spearman_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: Kupiono spearmana na %s" % [team, position])
		elif unit_type == "cavalry":
			hex_grid.place_cavalry_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: Kupiono cavalry na %s" % [team, position])
		
		await hex_grid.get_tree().create_timer(0.1).timeout

func plan_unit_purchases(state: Dictionary, budget: int) -> Array:
	"""Planuje zakup jednostek"""
	var purchases = []
	
	# Znajdź bezpieczne miejsce do kupna (zamek lub bezpieczny border)
	var safe_positions = find_safe_purchase_positions(state)
	
	if safe_positions.is_empty():
		return purchases
	
	var remaining_budget = budget
	var aggression = params[difficulty].aggression
	
	# Strategia: więcej knightów jeśli agresywny
	if aggression > 0.6 and remaining_budget >= hex_grid.KNIGHT_COST:
		for pos in safe_positions:
			if remaining_budget >= hex_grid.KNIGHT_COST:
				purchases.append({
					"type": "knight",
					"position": pos,
					"cost": hex_grid.KNIGHT_COST
				})
				remaining_budget -= hex_grid.KNIGHT_COST
				break
	
	# Kup farmerów dla ekspansji
	while remaining_budget >= hex_grid.FARMER_COST and purchases.size() < safe_positions.size():
		var pos = safe_positions[purchases.size()]
		purchases.append({
			"type": "farmer",
			"position": pos,
			"cost": hex_grid.FARMER_COST
		})
		remaining_budget -= hex_grid.FARMER_COST
	
	return purchases

func find_safe_purchase_positions(state: Dictionary) -> Array:
	"""Znajduje bezpieczne miejsca do zakupu jednostek"""
	var positions = []
	
	# Priorytet 1: Na zamku
	for castle_pos in state.my_castles:
		var hex = hex_grid.get_hex_at(castle_pos)
		if hex and hex.occupied_object == null:
			positions.append(castle_pos)
	
	# Priorytet 2: Pola connected border (bezpieczne od wrogów)
	for border_hex in state.border_hexes:
		var owner = hex_grid.territory_map.get(border_hex, 0)
		if owner != 0 and owner != team:
			continue
		
		var hex = hex_grid.get_hex_at(border_hex)
		if not hex or hex.occupied_object != null:
			continue
		
		# Sprawdź czy nie ma wrogów obok
		var safe = true
		var neighbors = hex_grid.get_neighbors(border_hex)
		for neighbor in neighbors:
			if hex_grid.knight_map.has(neighbor):
				var knight = hex_grid.knight_map[neighbor]
				if knight.team != team and knight.team > 0:
					safe = false
					break
		
		if safe:
			positions.append(border_hex)
	
	return positions

# === BUILDING WALLS (#4) ===
func build_walls(state: Dictionary):
	"""Buduje mury jeśli opłacalne"""
	var gold = state.gold
	var wall_threshold = params[difficulty].wall_threshold
	
	# Jeśli mamy dużo złota i priorytet obrony jest wysoki
	if gold > 50 and state.threats.size() > 0:
		var walls_to_build = plan_wall_construction(state)
		
		for wall_pos in walls_to_build:
			var cost = hex_grid.WALL_COST_PER_HEX
			if hex_grid.team_gold[team] >= cost:
				var from = wall_pos.from
				var to = wall_pos.to
				create_wall(from, to)
				hex_grid.team_gold[team] -= cost
				print("AI %d: Zbudowano mur %s-%s" % [team, from, to])
				await hex_grid.get_tree().create_timer(0.1).timeout

func plan_wall_construction(state: Dictionary) -> Array:
	"""Planuje budowę murów"""
	var walls = []
	
	# Zbuduj mury wokół zagrożonych pól
	for threat in state.threats:
		var threat_pos = threat.pos
		var neighbors = hex_grid.get_neighbors(threat_pos)
		
		for neighbor in neighbors:
			if hex_grid.territory_map.get(neighbor, 0) == team:
				# Pole mojego teamu sąsiaduje z zagrożeniem
				if not is_blocked_by_wall(neighbor, threat_pos):
					walls.append({"from": neighbor, "to": threat_pos})
	
	return walls

# === MOVING UNITS (#1 + #7) ===
func move_all_units(state: Dictionary):
	"""Rusza wszystkimi jednostkami AI w optymalny sposób"""
	
	# Sortuj jednostki według priorytetu (cavalry > knight > spearman > farmer)
	var sorted_units = state.my_units.duplicate()
	sorted_units.sort_custom(func(a, b): return get_unit_priority(a.type) > get_unit_priority(b.type))
	
	for unit_data in sorted_units:
		var unit = unit_data.unit
		
		# Sprawdź czy jednostka już się ruszyła
		if unit in hex_grid.units_moved_this_turn:
			continue
		
		# Znajdź najlepszy ruch dla tej jednostki
		var best_move = find_best_move(unit, unit_data, state)
		
		if best_move != Vector2i.ZERO and best_move != unit_data.pos:
			await execute_move(unit, unit_data, best_move)
			await hex_grid.get_tree().create_timer(0.15).timeout

func get_unit_priority(unit_type: String) -> int:
	match unit_type:
		"cavalry": return 4
		"knight": return 3
		"spearman": return 2
		"farmer": return 1
	return 0

func find_best_move(unit, unit_data: Dictionary, state: Dictionary) -> Vector2i:
	"""Znajduje najlepszy ruch dla jednostki"""
	var moves = get_possible_moves_for_unit(unit, unit_data)
	
	if moves.is_empty():
		return Vector2i.ZERO
	
	# Strategia zależy od typu jednostki i sytuacji
	var best_move = Vector2i.ZERO
	var best_score = -999999.0
	
	for move in moves:
		var score = evaluate_move(unit, unit_data, move, state)
		if score > best_score:
			best_score = score
			best_move = move
	
	return best_move

func evaluate_move(unit, unit_data: Dictionary, move: Vector2i, state: Dictionary) -> float:
	"""Ocenia wartość ruchu - uwzględnia agresywność AI"""
	var score = 0.0
	
	var hex = hex_grid.get_hex_at(move)
	if not hex:
		return -999999.0
	
	var owner = hex_grid.territory_map.get(move, 0)
	var aggression = params[difficulty].aggression
	
	# === OCENA DEFENSYWNA (ważna dla niskiej agresywności) ===
	if aggression < 0.5:
		# Sprawdź czy to ruch obronny (blisko zagrożenia)
		var is_defensive = false
		for threat in state.threats:
			if hex_distance(move, threat.pos) <= 2:
				is_defensive = true
				score += 600  # BONUS za obronną pozycję
				break
		
		# Sprawdź czy to wypełnia lukę w granicy
		if owner == team:
			var neighbors = hex_grid.get_neighbors(move)
			var border_neighbors = 0
			for neighbor in neighbors:
				var n_owner = hex_grid.territory_map.get(neighbor, 0)
				if n_owner != team and n_owner >= 0:
					border_neighbors += 1
			
			if border_neighbors >= 2:
				score += 400  # BONUS za zapełnianie luk w granicy
	
	# === KARA ZA STACKOWANIE (mniejsza dla defensywnych AI) ===
	if owner == team:
		var is_threatened = false
		for threat in state.threats:
			if hex_distance(move, threat.pos) <= 2:
				is_threatened = true
				break
		
		if not is_threatened:
			# Kara zależy od agresywności
			var stack_penalty = -200 - (aggression * 400)  # -200 do -600
			score += stack_penalty
	
	# === ATAK NA WROGIE JEDNOSTKI ===
	if hex.occupied_object != null:
		var target = hex.occupied_object
		var target_team = get_object_team(target)
		
		if target_team > 0 and target_team != team and target_team <= 4:
			var combat_advantage = calculate_combat_advantage(unit, unit_data, target, move, state)
			if combat_advantage > 0:
				# Bonus zależy od agresywności
				var attack_bonus = 1000 + (aggression * 1500) + combat_advantage * 10
				score += attack_bonus
			else:
				score -= 500
		elif target_team == -1:  # Bandyci
			score += 300  # Zawsze warto atakować bandytów
	
	# === PRZEJMOWANIE TERYTORIÓW ===
	if owner > 0 and owner != team and owner <= 4:
		# Bonus zależy od agresywności
		var conquest_bonus = 400 + (aggression * 600)  # 400-1000
		score += conquest_bonus
		
		# BONUS: Cutoff
		var cutoff_count = count_units_that_would_be_cutoff(owner, move)
		if cutoff_count > 0:
			score += cutoff_count * 200
	elif owner == 0:
		# Neutralne pole - bonus zależy od strategii
		var neutral_bonus = 300 + (aggression * 400)  # 300-700
		score += neutral_bonus
	
	# === POSZERZANIE GRANICY (ważne dla defensywnych AI) ===
	if aggression < 0.5:
		if owner == 0 or (owner > 0 and owner != team):
			var neighbors = hex_grid.get_neighbors(move)
			var friendly_neighbors = 0
			for neighbor in neighbors:
				if hex_grid.territory_map.get(neighbor, 0) == team:
					friendly_neighbors += 1
			
			# BONUS za równomierne poszerzanie
			if friendly_neighbors >= 2:
				score += 350
	
	# === POZYCJA PRZY GRANICY ===
	if owner == 0 or (owner > 0 and owner != team):
		var neighbors = hex_grid.get_neighbors(move)
		var adjacent_to_enemy = false
		for neighbor in neighbors:
			var neighbor_owner = hex_grid.territory_map.get(neighbor, 0)
			if neighbor_owner > 0 and neighbor_owner != team and neighbor_owner <= 4:
				adjacent_to_enemy = true
				break
		
		if adjacent_to_enemy:
			# BONUS zależy od agresywności
			var border_bonus = 150 + (aggression * 250)  # 150-400
			score += border_bonus
	
	# === CELE STRATEGICZNE ===
	for goal in strategic_goals:
		if goal.type == "capture_castle" and goal.has("position"):
			var dist_from_current = hex_distance(unit_data.pos, goal.position)
			var dist_from_move = hex_distance(move, goal.position)
			if dist_from_move < dist_from_current:
				# Bonus zależy od agresywności
				var progress_bonus = 30 + (aggression * 40)  # 30-70
				score += (dist_from_current - dist_from_move) * progress_bonus
	
	# === UNIKANIE STREF NIEBEZPIECZNYCH ===
	if unit_data.type in ["farmer", "spearman"]:
		for danger_zone in memory.danger_zones:
			var dist = hex_distance(move, danger_zone)
			if dist <= 1:
				# Kara większa dla defensywnych AI
				var danger_penalty = -300 - ((1.0 - aggression) * 200)  # -300 do -500
				score += danger_penalty
	
	return score

func calculate_combat_advantage(unit, unit_data: Dictionary, target, target_pos: Vector2i, state: Dictionary) -> float:
	"""Oblicza przewagę w walce"""
	# Policz wsparcie
	var my_support = count_nearby_units(target_pos, state.my_units, 1)
	var enemy_support = count_nearby_units(target_pos, state.enemy_units, 1)
	
	# Siły jednostek
	var my_power = get_unit_power(unit_data.type)
	var enemy_power = get_unit_power(get_unit_type(target))
	
	var my_total = my_power + my_support * 10
	var enemy_total = enemy_power + enemy_support * 10
	
	# Zwróć różnicę - dodatnia = przewaga
	return my_total - enemy_total

func get_unit_power(unit_type: String) -> int:
	match unit_type:
		"cavalry": return 80
		"knight": return 40
		"spearman": return 20
		"farmer": return 10
	return 0

func get_unit_type(unit) -> String:
	if unit is Cavalry:
		return "cavalry"
	elif unit is Knight:
		return "knight"
	elif unit is Spearman:
		return "spearman"
	elif unit is Farmer:
		return "farmer"
	return "unknown"

func get_possible_moves_for_unit(unit, unit_data: Dictionary) -> Array:
	var moves = []
	
	# NOWA LOGIKA: Tak samo jak highlight_*_moves - PEŁNA WOLNOŚĆ po swoim królestwie!
	
	if unit_data.type == "cavalry":
		# Cavalry: cały border + może atakować jednostki
		var border_hexes = hex_grid.get_territory_border(team)
		for coords in border_hexes:
			var hex = hex_grid.get_hex_at(coords)
			if not hex:
				continue
			
			# Może atakować wrogie jednostki
			if hex.occupied_object != null:
				var target = hex.occupied_object
				var target_team = get_object_team(target)
				if target_team != team and target_team > 0 and target_team <= 4:
					moves.append(coords)
					continue
			
			# Może wejść na puste border
			if hex.occupied_object == null:
				moves.append(coords)
	
	elif unit_data.type == "knight":
		# Knight: WSZYSTKIE własne pola + border z wrogimi jednostkami
		
		# 1. Wszystkie własne terytoria (puste)
		for coords in hex_grid.territory_map:
			if hex_grid.territory_map[coords] == team and coords != unit_data.pos:
				var hex = hex_grid.get_hex_at(coords)
				if hex and hex.occupied_object == null:
					moves.append(coords)
		
		# 2. Border z wrogimi jednostkami i pustymi polami
		var border_hexes = hex_grid.get_territory_border(team)
		for coords in border_hexes:
			var hex = hex_grid.get_hex_at(coords)
			if not hex:
				continue
			
			# Może atakować wrogie jednostki
			if hex.occupied_object != null:
				var target = hex.occupied_object
				var target_team = get_object_team(target)
				if target_team != team and target_team > 0 and target_team <= 4:
					# Sprawdź czy nie jest cavalry (knight nie może atakować cavalry)
					if not (target is Cavalry):
						moves.append(coords)
			else:
				# Może wejść na puste border
				moves.append(coords)
	
	elif unit_data.type == "farmer" or unit_data.type == "spearman":
		# Farmer/Spearman: WSZYSTKIE własne pola + border (tylko puste lub do przejęcia)
		
		# 1. Wszystkie własne terytoria (puste)
		var my_territories = []
		if team == -1:
			# Bandyci - terytoria -1 i -2
			for coords in hex_grid.territory_map:
				var owner = hex_grid.territory_map[coords]
				if (owner == -1 or owner == -2) and coords != unit_data.pos:
					my_territories.append(coords)
		else:
			# Normalne teamy
			for coords in hex_grid.territory_map:
				if hex_grid.territory_map[coords] == team and coords != unit_data.pos:
					my_territories.append(coords)
		
		for coords in my_territories:
			var hex = hex_grid.get_hex_at(coords)
			if hex and hex.occupied_object == null:
				moves.append(coords)
		
		# 2. Border - tylko puste pola do przejęcia
		var border_hexes
		if team == -1:
			border_hexes = get_bandit_border()
		else:
			border_hexes = hex_grid.get_territory_border(team)
		
		for coords in border_hexes:
			var hex = hex_grid.get_hex_at(coords)
			if not hex or hex.occupied_object != null:
				continue
			
			# KLUCZOWE: Bandyci NIE MOGĄ przejść przez wrogie mury!
			var can_reach = false
			var neighbors = hex_grid.get_neighbors(coords)
			for neighbor in neighbors:
				var neighbor_owner = hex_grid.territory_map.get(neighbor, 0)
				
				# Sprawdź czy to nasze pole
				var is_our_territory = false
				if team == -1:
					is_our_territory = (neighbor_owner == -1 or neighbor_owner == -2)
				else:
					is_our_territory = (neighbor_owner == team)
				
				if is_our_territory:
					# Sprawdź czy NIE MA WROGIEGO muru
					var blocked = false
					var enemy_neighbors = hex_grid.get_neighbors(coords)
					var edge_index = enemy_neighbors.find(neighbor)
					if edge_index != -1:
						var enemy_wall_key = "%d,%d-edge%d" % [coords.x, coords.y, edge_index]
						if hex_grid.wall_map.has(enemy_wall_key):
							var wall_data = hex_grid.wall_map[enemy_wall_key]
							# Sprawdź czy wrogi mur (nie nasz)
							var wall_team = wall_data.get("team", 0)
							if team == -1:
								# Bandyci - każdy mur blokuje (nie mają swoich)
								blocked = true
							elif wall_team != team:
								blocked = true
					
					if not blocked:
						can_reach = true
						break
			
			if can_reach:
				moves.append(coords)
	
	return moves

func get_bandit_border() -> Array:
	"""Zwraca granicę terytoriów bandytów"""
	var border = []
	var checked = {}
	
	for coords in hex_grid.territory_map:
		var owner = hex_grid.territory_map[coords]
		if owner != -1 and owner != -2:
			continue
		
		var neighbors = hex_grid.get_neighbors(coords)
		for neighbor in neighbors:
			if checked.has(neighbor):
				continue
			
			checked[neighbor] = true
			
			if not hex_grid.hex_map.has(neighbor):
				continue
			
			var neighbor_owner = hex_grid.territory_map.get(neighbor, 0)
			if neighbor_owner == -1 or neighbor_owner == -2:
				continue
			
			border.append(neighbor)
	
	return border

func is_blocked_by_wall(from: Vector2i, to: Vector2i) -> bool:
	"""Sprawdza czy między hexami jest mur"""
	var wall_key1 = "%s-%s" % [from, to]
	var wall_key2 = "%s-%s" % [to, from]
	return hex_grid.wall_map.has(wall_key1) or hex_grid.wall_map.has(wall_key2)

func find_cutoff_target(from: Vector2i, moves: Array, state: Dictionary) -> Vector2i:
	var best_move = Vector2i.ZERO
	var max_cutoff = 0
	
	for move in moves:
		var owner = hex_grid.territory_map.get(move, 0)
		
		if owner > 0 and owner != team and owner <= 4:
			var cutoff_count = count_units_that_would_be_cutoff(owner, move)
			if cutoff_count > max_cutoff:
				max_cutoff = cutoff_count
				best_move = move
	
	return best_move

func count_units_that_would_be_cutoff(enemy_team: int, captured_pos: Vector2i) -> int:
	var original_owner = hex_grid.territory_map.get(captured_pos, 0)
	hex_grid.territory_map[captured_pos] = team
	
	var enemy_connected = hex_grid.get_connected_territories(enemy_team)
	
	hex_grid.territory_map[captured_pos] = original_owner
	
	var cutoff = 0
	# Sprawdź wszystkie jednostki wroga
	for unit in hex_grid.knight_map.values():
		if unit.team == enemy_team and unit.hex_position not in enemy_connected:
			cutoff += 1
	
	for unit in hex_grid.farmer_map.values():
		if unit.team == enemy_team and unit.hex_position not in enemy_connected:
			cutoff += 1
	
	for unit in hex_grid.spearman_map.values():
		if unit.team == enemy_team and unit.hex_position not in enemy_connected:
			cutoff += 1
	
	for unit in hex_grid.cavalry_map.values():
		if unit.team == enemy_team and unit.hex_position not in enemy_connected:
			cutoff += 1
	
	return cutoff

func find_expansion_target(from: Vector2i, moves: Array, state: Dictionary) -> Vector2i:
	var best_move = Vector2i.ZERO
	var best_score = -1
	
	for move in moves:
		var hex = hex_grid.get_hex_at(move)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = hex_grid.territory_map.get(move, 0)
		
		var score = 0
		if owner == 0:
			score = 1
		elif owner > 0 and owner != team:
			score = 3
		else:
			continue
		
		var dist_to_border = get_min_distance(move, state.border_hexes)
		score += max(0, 5 - dist_to_border)
		
		if score > best_score:
			best_score = score
			best_move = move
	
	return best_move

func find_defense_target(from: Vector2i, moves: Array, state: Dictionary) -> Vector2i:
	if state.threats.is_empty():
		return Vector2i.ZERO
	
	var threat_positions = state.threats.map(func(t): return t.pos)
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		var dist = get_min_distance(move, threat_positions)
		if dist < min_dist:
			min_dist = dist
			best_move = move
	
	return best_move

func find_border_target(from: Vector2i, moves: Array, state: Dictionary) -> Vector2i:
	if state.border_hexes.is_empty():
		return Vector2i.ZERO
	
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		var hex = hex_grid.get_hex_at(move)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = hex_grid.territory_map.get(move, 0)
		if owner != team:
			continue
		
		var dist = get_min_distance(move, state.border_hexes)
		if dist < min_dist:
			min_dist = dist
			best_move = move
	
	return best_move

func execute_move(unit, unit_data: Dictionary, target: Vector2i):
	print("AI %d: %s z %s na %s" % [team, unit_data.type, unit_data.pos, target])
	
	# NAPRAW: Bezpośrednio wywołaj funkcje move_* zamiast symulować kliknięcia
	var from = unit_data.pos
	
	if unit_data.type == "knight":
		hex_grid.move_knight(from, target)
	elif unit_data.type == "farmer":
		hex_grid.move_farmer(from, target)
	elif unit_data.type == "spearman":
		hex_grid.move_spearman(from, target)
	elif unit_data.type == "cavalry":
		hex_grid.move_cavalry(from, target)
	
	await hex_grid.get_tree().create_timer(0.2).timeout

# === FUNKCJE POMOCNICZE ===
func get_min_distance(pos: Vector2i, targets: Array) -> int:
	if targets.is_empty():
		return 999999
	
	var min_dist = 999999
	for target in targets:
		var dist = hex_distance(pos, target)
		if dist < min_dist:
			min_dist = dist
	
	return min_dist

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = axial_to_cube(a)
	var bc = axial_to_cube(b)
	return (abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2

func axial_to_cube(hex: Vector2i) -> Vector3i:
	var x = hex.x
	var z = hex.y
	var y = -x - z
	return Vector3i(x, y, z)

func count_nearby_units(pos: Vector2i, units: Array, max_dist: int) -> int:
	var count = 0
	for unit_data in units:
		if hex_distance(pos, unit_data.pos) <= max_dist:
			count += 1
	return count

func are_hexes_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var neighbors = hex_grid.get_neighbors(a)
	return b in neighbors

func create_wall(from: Vector2i, to: Vector2i):
	if not are_hexes_adjacent(from, to):
		return
	
	var wall_id = "%s-%s" % [from, to]
	var wall_id_rev = "%s-%s" % [to, from]
	
	if hex_grid.wall_map.has(wall_id) or hex_grid.wall_map.has(wall_id_rev):
		return
	
	hex_grid.wall_map[wall_id] = true
	hex_grid.wall_map[wall_id_rev] = true
